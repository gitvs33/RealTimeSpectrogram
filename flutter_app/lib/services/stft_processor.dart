import 'dart:typed_data';
import '../models/audio_frame.dart';
import 'fft_utils.dart';

/// Stateful STFT processor: raw samples in, [AudioFrame] objects out.
///
/// Owns the audio ring buffer and frame counter so callers never touch
/// windowing, FFT scheduling, or frequency-bin arithmetic.
///
/// ```dart
/// final proc = StftProcessor();
/// for (final chunk in rawStream) {
///   for (final frame in proc.feed(chunk)) {
///     // route to display, recording, etc.
///   }
/// }
/// ```
class StftProcessor {
  final int fftSize;
  final int hopLength;
  final int sampleRate;

  final Float64List _hannWindow;
  final List<double> _buffer = [];
  int _frameIndex = 0;

  StftProcessor({
    this.fftSize = 1024,
    this.hopLength = 512,
    this.sampleRate = 44100,
  }) : _hannWindow = FFTUtils.hannWindow(fftSize);

  /// Feed raw normalized samples [-1, 1].
  /// Returns 0 or more completed [AudioFrame] objects produced from the
  /// internal buffer.
  List<AudioFrame> feed(Float64List samples) {
    _buffer.addAll(samples);
    final frames = <AudioFrame>[];
    while (_buffer.length >= fftSize) {
      frames.add(_processOneFrame());
    }
    return frames;
  }

  /// Clear internal buffer and reset frame counter to 0.
  void reset() {
    _buffer.clear();
    _frameIndex = 0;
  }

  // ── internal ──

  AudioFrame _processOneFrame() {
    // Apply Hann window
    final frame = Float64List(fftSize);
    for (int i = 0; i < fftSize; i++) {
      frame[i] = _buffer[i] * _hannWindow[i];
    }
    _buffer.removeRange(0, hopLength);

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

    return AudioFrame(
      time: time,
      frequencies: freqs,
      magnitudes: mags,
      phases: phases,
    );
  }
}
