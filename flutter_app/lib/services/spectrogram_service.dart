import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../models/audio_frame.dart';
import 'fft_utils.dart';
import 'spectrogram_renderer.dart';

class SpectrogramService extends ChangeNotifier {
  SpectrogramService();

  // ── Local capture state ──
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _streamSub;
  final List<double> _audioBuffer = [];
  final List<double> _rawAudio = []; // accumulated raw samples for WAV
  static const int fftSize = 1024;
  static const int hopLength = 512;
  static const int sampleRate = 44100;
  final Float64List _hannWindow = FFTUtils.hannWindow(fftSize);
  int _frameIndex = 0;

  // ── Shared state ──
  bool _isRecording = false;
  bool _livePreviewActive = false;
  bool _isCapturing = false;

  final List<AudioFrame> _liveFrames = [];
  static const int maxLiveFrames = 300;
  final List<AudioFrame> _recordedFrames = [];

  String _connectionError = '';
  String _saveMessage = '';
  bool _isSaving = false;

  // ── Getters ──
  bool get isRecording => _isRecording;
  bool get livePreviewActive => _livePreviewActive;
  List<AudioFrame> get liveFrames => _liveFrames;
  List<AudioFrame> get recordedFrames => _recordedFrames;
  int get recordedFrameCount => _recordedFrames.length;
  double get recordingDuration =>
      _recordedFrames.isEmpty ? 0.0 : _recordedFrames.last.time;

  String get formattedDuration {
    final seconds = recordingDuration.floor();
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String get connectionError => _connectionError;
  String get saveMessage => _saveMessage;
  bool get isSaving => _isSaving;

  void clearConnectionError() {
    _connectionError = '';
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════
  //  LOCAL CAPTURE MODE  (mic + STFT on-device)
  // ════════════════════════════════════════════════════════════

  Future<void> _startLocalCapture() async {
    if (_isCapturing) return;
    _isCapturing = true;
    _audioBuffer.clear();
    _frameIndex = 0;

    try {
      if (!await _recorder.hasPermission()) {
        _connectionError = 'Microphone permission denied';
        notifyListeners();
        return;
      }

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
        ),
      );

      _streamSub = stream.listen(
        _onLocalAudioData,
        onError: (e) {
          _connectionError = 'Capture error: $e';
          _isCapturing = false;
          notifyListeners();
        },
        onDone: () {
          _isCapturing = false;
          notifyListeners();
        },
      );
    } catch (e) {
      _connectionError = 'Failed to start capture: $e';
      _isCapturing = false;
      notifyListeners();
    }
  }

  void _stopLocalCapture() {
    _streamSub?.cancel();
    _streamSub = null;
    _recorder.stop();
    _isCapturing = false;
  }

  void _onLocalAudioData(Uint8List pcmBytes) {
    // Decode 16-bit PCM → float samples in [-1, 1]
    final samples = Float64List(pcmBytes.length ~/ 2);
    for (int i = 0; i < samples.length; i++) {
      int val = pcmBytes[i * 2] | (pcmBytes[i * 2 + 1] << 8);
      if (val >= 32768) val -= 65536; // sign extend
      samples[i] = val / 32768.0;
    }

    if (_isRecording) _rawAudio.addAll(samples);
    _audioBuffer.addAll(samples);

    // Process as many full STFT frames as we can
    while (_audioBuffer.length >= fftSize) {
      // Window the frame
      final frame = Float64List(fftSize);
      for (int i = 0; i < fftSize; i++) {
        frame[i] = _audioBuffer[i] * _hannWindow[i];
      }
      _audioBuffer.removeRange(0, hopLength);

      // FFT
      final (mags, phases) = FFTUtils.computeRFFT(frame);

      // Frequency bins
      final freqStep = sampleRate / fftSize;
      final freqs = Float64List(mags.length);
      for (int i = 0; i < freqs.length; i++) {
        freqs[i] = i * freqStep;
      }

      final time = _frameIndex * hopLength / sampleRate;
      _frameIndex++;

      final af = AudioFrame(
        time: time,
        frequencies: freqs,
        magnitudes: mags,
        phases: phases,
      );

      if (_livePreviewActive) {
        _liveFrames.add(af);
        if (_liveFrames.length > maxLiveFrames) _liveFrames.removeAt(0);
      }
      if (_isRecording) _recordedFrames.add(af);
    }

    // Single notify after processing all frames in this chunk
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════
  //  COMMON API  (used by the UI regardless of mode)
  // ════════════════════════════════════════════════════════════

  void startLivePreview() {
    _liveFrames.clear();
    _livePreviewActive = true;
    notifyListeners();
    if (!_isCapturing) _startLocalCapture();
  }

  void stopLivePreview() {
    _livePreviewActive = false;
    _liveFrames.clear();
    _stopLocalCapture();
    notifyListeners();
  }

  void startRecording() {
    _recordedFrames.clear();
    _rawAudio.clear();
    _isRecording = true;
    _frameIndex = 0;
    notifyListeners();
    if (!_isCapturing) _startLocalCapture();
  }

  void stopRecording() {
    _isRecording = false;
    if (!_livePreviewActive) _stopLocalCapture();
    notifyListeners();
  }

  /// Save recorded data.
  Future<void> saveRecording(String filename) async {
    if (_recordedFrames.isEmpty) return;
    _isSaving = true;
    _saveMessage = '';
    notifyListeners();

    try {
      final dir = await getApplicationDocumentsDirectory();
      final saveDir = Directory('${dir.path}/spectrogram_saves');
      await saveDir.create(recursive: true);

      // ── WAV ──
      if (_rawAudio.isNotEmpty) {
        final wavPath = '${saveDir.path}/$filename.wav';
        _writeWav(wavPath, _rawAudio, sampleRate);
      }

      // ── CSV ──
      final csvPath = '${saveDir.path}/${filename}_stft.csv';
      final csvSink = File(csvPath).openWrite();
      csvSink.writeln('time_s,frequency_hz,amplitude,phase_radians');
      final maxCsvFrames = _recordedFrames.length > 200
          ? 200
          : _recordedFrames.length;
      final step = _recordedFrames.length ~/ maxCsvFrames;
      int written = 0;
      for (int fi = 0; fi < _recordedFrames.length && written < maxCsvFrames; fi += step) {
        final frame = _recordedFrames[fi];
        final t = frame.time.toStringAsFixed(3);
        for (int bi = 0; bi < frame.binCount && bi < 128; bi++) {
          csvSink.writeln(
            '$t,${frame.frequencies[bi].toStringAsFixed(1)},'
            '${frame.magnitudes[bi].toStringAsFixed(6)},'
            '${frame.phases[bi].toStringAsFixed(6)}',
          );
        }
        written++;
      }
      await csvSink.flush();
      await csvSink.close();

      // ── PNG spectrogram image (full recording width) ──
      try {
        final numFrames = _recordedFrames.length;
        // Each frame gets ~2px; cap at 4000×1600 (6.4M pixels ≈ 25MB image)
        final pngWidth = (numFrames * 2).round().clamp(600, 4000);
        final pngHeight = (pngWidth * 0.4).round().clamp(300, 1600);
        debugPrint('[save] PNG render ${numFrames}frames → ${pngWidth}x$pngHeight');
        final pngBytes = await SpectrogramRenderer.renderToPng(
          frames: _recordedFrames,
          width: pngWidth,
          height: pngHeight,
        );
        if (pngBytes != null) {
          final pngPath = '${saveDir.path}/${filename}_spectrogram.png';
          await File(pngPath).writeAsBytes(pngBytes);
          debugPrint('[save] PNG written: $pngPath (${pngBytes.length} bytes)');
        } else {
          debugPrint('[save] PNG render returned null (empty frames?)');
        }
      } catch (e) {
        debugPrint('[save] PNG render/write failed: $e');
      }

      // ── JSON ──
      final jsonPath = '${saveDir.path}/${filename}_stft.json';
      final jsonData = {
        'meta': {
          'sample_rate': sampleRate,
          'fft_size': fftSize,
          'hop_length': hopLength,
          'window': 'hann',
        },
        'times': _recordedFrames.map((f) => f.time).toList(),
        'frequencies': _recordedFrames.isNotEmpty
            ? _recordedFrames.first.frequencies
            : [],
        'magnitudes': _recordedFrames.map((f) => f.magnitudes.sublist(0, 64)).toList(),
        'phases': _recordedFrames.map((f) => f.phases.sublist(0, 64)).toList(),
      };
      await File(
        jsonPath,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(jsonData));

      _saveMessage = 'Saved to ${saveDir.path}/$filename.*';
      debugPrint('[save] Files written to $saveDir');
      debugPrint('[save] Dir listing: ${saveDir.listSync().map((f) => (f as File).path.split('/').last).toList()}');
    } catch (e) {
      _connectionError = 'Save failed: $e';
      debugPrint('[save] Error: $e');
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  // ── WAV writer for local mode ──

  void _writeWav(String path, List<double> samples, int sr) {
    final buf = BytesBuilder();
    final dataSize = samples.length * 2; // 16-bit
    final fileSize = 36 + dataSize;

    void w16(int v) {
      buf.addByte(v & 0xFF);
      buf.addByte((v >> 8) & 0xFF);
    }

    void w32(int v) {
      buf.addByte(v & 0xFF);
      buf.addByte((v >> 8) & 0xFF);
      buf.addByte((v >> 16) & 0xFF);
      buf.addByte((v >> 24) & 0xFF);
    }

    // RIFF
    buf.add('RIFF'.codeUnits);
    w32(fileSize);
    buf.add('WAVE'.codeUnits);

    // fmt
    buf.add('fmt '.codeUnits);
    w32(16); // chunk size
    w16(1); // PCM
    w16(1); // mono
    w32(sr);
    w32(sr * 2); // byte rate
    w16(2); // block align
    w16(16); // bits per sample

    // data
    buf.add('data'.codeUnits);
    w32(dataSize);
    for (final s in samples) {
      int val = (s * 32767).clamp(-32768, 32767).toInt();
      if (val < 0) val += 65536;
      w16(val);
    }

    File(path).writeAsBytesSync(buf.toBytes());
  }

  @override
  void dispose() {
    _stopLocalCapture();
    super.dispose();
  }
}
