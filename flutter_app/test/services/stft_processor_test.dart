import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/stft_processor.dart';
import 'package:flutter_app/models/audio_frame.dart';

void main() {
  group('StftProcessor', () {
    late StftProcessor proc;

    setUp(() {
      proc = StftProcessor(fftSize: 256, hopLength: 128, sampleRate: 44100);
    });

    test('default constructor sets expected values', () {
      final p = StftProcessor();
      expect(p.fftSize, 1024);
      expect(p.hopLength, 512);
      expect(p.sampleRate, 44100);
    });

    test('feed with fewer samples than fftSize produces no frames', () {
      final samples = Float64List(100); // < 256
      final frames = proc.feed(samples);
      expect(frames, isEmpty);
    });

    test('feed produces the correct number of frames', () {
      // 640 samples with fftSize=256, hopLength=128
      // buffer after first feed: 640
      // frames produced: floor((640 - 256) / 128) + 1 = floor(384/128) + 1 = 3 + 1 = 4
      // Wait: while (buffer >= fftSize): process one, remove hopLength
      // 640 >= 256 → frame 1, buffer = 512
      // 512 >= 256 → frame 2, buffer = 384
      // 384 >= 256 → frame 3, buffer = 256
      // 256 >= 256 → frame 4, buffer = 128
      // 128 < 256 → stop. So 4 frames.
      final samples = Float64List(640);
      final frames = proc.feed(samples);
      expect(frames.length, 4);
    });

    test('feed across multiple calls accumulates correctly', () {
      // 200 samples, then 200 more
      final f1 = proc.feed(Float64List(200));
      expect(f1, isEmpty);
      // buffer = 400, enough for 2 frames (while buffer >= 256 → process, remove 128)
      // 400 → frame 1 (buf=272) → frame 2 (buf=144) → stop
      final f2 = proc.feed(Float64List(200));
      expect(f2.length, 2);
      // 3rd call with 200 more: buffer = 144+200 = 344, enough for 1
      final f3 = proc.feed(Float64List(200));
      expect(f3.length, 1);
    });

    test('reset clears buffer and counter', () {
      proc.feed(Float64List(512));
      expect(proc.feed(Float64List(512)), isNotEmpty);

      proc.reset();
      final after = proc.feed(Float64List(100));
      expect(after, isEmpty);
    });

    test('frames have correct time stamps', () {
      // 384 samples → 2 frames
      // fftSize=256, hopLength=128, sampleRate=100
      final p = StftProcessor(fftSize: 256, hopLength: 128, sampleRate: 100);
      final frames = p.feed(Float64List(384));
      expect(frames.length, 2);
      // frame 0: time = 0 * 128 / 100 = 0.0
      expect(frames[0].time, closeTo(0.0, 1e-9));
      // frame 1: time = 1 * 128 / 100 = 1.28
      expect(frames[1].time, closeTo(1.28, 1e-9));
    });

    test('frames have correct bin count', () {
      final frames = proc.feed(Float64List(512));
      expect(frames, isNotEmpty);
      for (final f in frames) {
        // bins = fftSize/2 + 1 = 129
        expect(f.binCount, 129);
        expect(f.frequencies.length, 129);
        expect(f.magnitudes.length, 129);
        expect(f.phases.length, 129);
      }
    });

    test('frames have positive magnitudes', () {
      // Feed a pure tone: sin wave at frequency fftSize/4 * sampleRate/fftSize
      final p = StftProcessor(fftSize: 256, hopLength: 128, sampleRate: 44100);
      final tone = Float64List(2048);
      for (int i = 0; i < tone.length; i++) {
        // tone at bin 32: frequency = 32 * 44100/256 = 5512.5 Hz
        tone[i] = sin(2 * pi * 5512.5 * i / 44100);
      }
      final frames = p.feed(tone);
      expect(frames, isNotEmpty);

      // All magnitudes should be non-negative
      for (final f in frames) {
        for (final m in f.magnitudes) {
          expect(m, greaterThanOrEqualTo(0));
        }
      }

      // The bin at index ~32 should have peak magnitude
      for (final f in frames) {
        final peakBin = f.magnitudes
            .toList()
            .indexOf(f.magnitudes.reduce(max));
        // Peak should be near bin 32 (not exact due to windowing)
        expect((peakBin - 32).abs(), lessThan(5));
      }
    });

    test('frames contain frequencies from 0 to Nyquist', () {
      final frames = proc.feed(Float64List(512));
      expect(frames, isNotEmpty);
      final f = frames.first;
      expect(f.frequencies[0], closeTo(0.0, 1e-6));
      // Nyquist = sampleRate / 2 = 22050
      expect(f.frequencies.last, closeTo(22050.0, 1e-6));
    });

    test('silent input produces near-zero magnitudes', () {
      final frames = proc.feed(Float64List(1024));
      expect(frames, isNotEmpty);
      for (final f in frames) {
        for (final m in f.magnitudes) {
          expect(m, lessThan(1e-10));
        }
      }
    });
  });
}
