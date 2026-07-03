import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/audio_frame.dart';
import 'spectrogram_renderer.dart';
import 'wav_writer.dart';

/// Result of a save operation.
class SaveResult {
  final String wavPath;
  final String csvPath;
  final String jsonPath;
  final String? pngPath;

  SaveResult({
    required this.wavPath,
    required this.csvPath,
    required this.jsonPath,
    this.pngPath,
  });
}

/// Persists recorded frames + raw audio to WAV, CSV, JSON, and PNG.
///
/// All dependencies are passed in — no global state. Testable with
/// a temp directory and synthetic [AudioFrame] objects.
class RecordingPersistence {
  final String baseDirectory;
  final int maxCsvFrames;
  final int maxCsvBins;

  RecordingPersistence({
    required this.baseDirectory,
    this.maxCsvFrames = 200,
    this.maxCsvBins = 128,
  });

  /// Save a recording to disk.
  ///
  /// [filename] without extension. [frames] are the recorded AudioFrames.
  /// [rawAudio] is the accumulated raw PCM samples for WAV export.
  Future<SaveResult> save({
    required String filename,
    required List<AudioFrame> frames,
    required List<double> rawAudio,
    int sampleRate = 44100,
  }) async {
    final dir = Directory(baseDirectory);
    await dir.create(recursive: true);

    // ── WAV ──
    final wavPath = '${dir.path}/$filename.wav';
    if (rawAudio.isNotEmpty) {
      await WavWriter.writeToFile(wavPath, rawAudio, sampleRate);
    }

    // ── CSV ──
    final csvPath = '${dir.path}/${filename}_stft.csv';
    await _writeCsv(csvPath, frames);

    // ── PNG ──
    String? pngPath;
    try {
      pngPath = await _writePng(dir.path, filename, frames);
    } catch (e) {
      debugPrint('[persistence] PNG render/write failed: $e');
    }

    // ── JSON ──
    final jsonPath = '${dir.path}/${filename}_stft.json';
    await _writeJson(jsonPath, frames);

    return SaveResult(
      wavPath: wavPath,
      csvPath: csvPath,
      jsonPath: jsonPath,
      pngPath: pngPath,
    );
  }

  // ── CSV ──

  Future<void> _writeCsv(String path, List<AudioFrame> frames) async {
    final sink = File(path).openWrite();
    sink.writeln('time_s,frequency_hz,amplitude,phase_radians');
    final maxFrames = frames.length > maxCsvFrames ? maxCsvFrames : frames.length;
    final step = frames.length ~/ maxFrames;
    int written = 0;
    for (int fi = 0; fi < frames.length && written < maxFrames; fi += step) {
      final frame = frames[fi];
      final t = frame.time.toStringAsFixed(3);
      for (int bi = 0; bi < frame.binCount && bi < maxCsvBins; bi++) {
        sink.writeln(
          '$t,${frame.frequencies[bi].toStringAsFixed(1)},'
          '${frame.magnitudes[bi].toStringAsFixed(6)},'
          '${frame.phases[bi].toStringAsFixed(6)}',
        );
      }
      written++;
    }
    await sink.flush();
    await sink.close();
  }

  // ── PNG ──

  Future<String?> _writePng(
    String dirPath,
    String filename,
    List<AudioFrame> frames,
  ) async {
    final numFrames = frames.length;
    final pngWidth = (numFrames * 2).round().clamp(600, 4000);
    final pngHeight = (pngWidth * 0.4).round().clamp(300, 1600);
    debugPrint(
      '[persistence] PNG render ${numFrames}frames → ${pngWidth}x$pngHeight',
    );

    final pngBytes = await SpectrogramRenderer.renderToPng(
      frames: frames,
      width: pngWidth,
      height: pngHeight,
    );

    if (pngBytes == null) return null;

    final pngPath = '$dirPath/${filename}_spectrogram.png';
    await File(pngPath).writeAsBytes(pngBytes);
    debugPrint(
      '[persistence] PNG written: $pngPath (${pngBytes.length} bytes)',
    );
    return pngPath;
  }

  // ── JSON ──

  Future<void> _writeJson(String path, List<AudioFrame> frames) async {
    final data = {
      'meta': {
        'sample_rate': 44100,
        'fft_size': 1024,
        'hop_length': 512,
        'window': 'hann',
      },
      'times': frames.map((f) => f.time).toList(),
      'frequencies':
          frames.isNotEmpty ? frames.first.frequencies.sublist(0, frames.first.binCount.clamp(0, 64)) : [],
      'magnitudes':
          frames.map((f) => f.magnitudes.sublist(0, f.binCount.clamp(0, 64))).toList(),
      'phases':
          frames.map((f) => f.phases.sublist(0, f.binCount.clamp(0, 64))).toList(),
    };
    await File(path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }
}
