import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/audio_frame.dart';
import 'package:flutter_app/services/recording_persistence.dart';

/// Build a minimal AudioFrame with [binCount] bins.
AudioFrame _makeFrame(double time, int binCount) {
  return AudioFrame(
    time: time,
    frequencies: List<double>.generate(binCount, (i) => i * 100.0),
    magnitudes: List<double>.generate(binCount, (i) => 0.1 + i * 0.1),
    phases: List<double>.generate(binCount, (i) => i * 0.1),
  );
}

void main() {
  late Directory tmpDir;
  late RecordingPersistence persistence;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('recording_test_');
    persistence = RecordingPersistence(
      baseDirectory: tmpDir.path,
      maxCsvFrames: 100,
      maxCsvBins: 64,
    );
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('RecordingPersistence', () {
    test('save WAV with raw audio', () async {
      final result = await persistence.save(
        filename: 'test_save',
        frames: [_makeFrame(0.0, 64)],
        rawAudio: [0.0, 0.5, -0.5, 1.0],
        sampleRate: 44100,
      );

      expect(result.wavPath, endsWith('test_save.wav'));
      expect(result.csvPath, endsWith('test_save_stft.csv'));
      expect(result.jsonPath, endsWith('test_save_stft.json'));

      // Check files exist
      expect(File(result.wavPath).existsSync(), isTrue);
      expect(File(result.csvPath).existsSync(), isTrue);
      expect(File(result.jsonPath).existsSync(), isTrue);

      // WAV should be > 44 bytes header
      final wavBytes = File(result.wavPath).readAsBytesSync();
      expect(wavBytes.length, greaterThan(44));
    });

    test('save without raw audio still creates CSV and JSON', () async {
      final result = await persistence.save(
        filename: 'test_metadata',
        frames: [_makeFrame(0.0, 32), _makeFrame(0.5, 32)],
        rawAudio: [],
        sampleRate: 44100,
      );

      // WAV file is not created when raw audio is empty
      // (WavWriter is only called when rawAudio.isNotEmpty)
      expect(File(result.wavPath).existsSync(), false);
      expect(File(result.csvPath).existsSync(), isTrue);
      expect(File(result.jsonPath).existsSync(), isTrue);
    });

    test('CSV has correct header and data format', () async {
      await persistence.save(
        filename: 'csv_test',
        frames: [_makeFrame(0.0, 2)],
        rawAudio: [],
      );

      final csv = File(persistence.baseDirectory + '/csv_test_stft.csv')
          .readAsStringSync();
      final lines = csv.trim().split('\n');

      // Header
      expect(lines[0], 'time_s,frequency_hz,amplitude,phase_radians');

      // Data line: time, freq, amp, phase
      final parts = lines[1].split(',');
      expect(parts.length, 4);
      expect(double.tryParse(parts[0]), isNotNull);
      expect(double.tryParse(parts[1]), isNotNull);
      expect(double.tryParse(parts[2]), isNotNull);
      expect(double.tryParse(parts[3]), isNotNull);
    });

    test('JSON has expected structure', () async {
      await persistence.save(
        filename: 'json_test',
        frames: [_makeFrame(0.0, 64)],
        rawAudio: [], // WAV won't be created without raw audio
      );

      final file = File(persistence.baseDirectory + '/json_test_stft.json');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('"meta"'));
      expect(content, contains('"times"'));
      expect(content, contains('"frequencies"'));
      expect(content, contains('"magnitudes"'));
      expect(content, contains('"phases"'));
    });

    test('CSV respects maxCsvFrames and maxCsvBins', () async {
      final manyFrames = List.generate(
        50,
        (i) => _makeFrame(i * 0.1, 128), // 128 bins per frame
      );

      final limited = RecordingPersistence(
        baseDirectory: tmpDir.path,
        maxCsvFrames: 10,
        maxCsvBins: 4,
      );

      await limited.save(
        filename: 'limited',
        frames: manyFrames,
        rawAudio: [],
      );

      final csv = File(tmpDir.path + '/limited_stft.csv')
          .readAsStringSync();
      final lines = csv.trim().split('\n');
      // header + maxCsvFrames rows, each with maxCsvBins columns
      // But the step calculation means we skip frames: frames.length ~/ maxFrames
      // = 50 ~/ 10 = 5, so we read frames 0, 5, 10, ..., 45 = 10 frames
      // Each frame has 4 bins → 10 * 4 = 40 data rows + header = 41
      expect(lines.length, 41);
    });

    test('SaveResult contains all expected paths', () {
      final result = SaveResult(
        wavPath: '/tmp/a.wav',
        csvPath: '/tmp/a_stft.csv',
        jsonPath: '/tmp/a_stft.json',
      );
      expect(result.wavPath, '/tmp/a.wav');
      expect(result.csvPath, '/tmp/a_stft.csv');
      expect(result.jsonPath, '/tmp/a_stft.json');
      expect(result.pngPath, isNull);
    });
  });
}
