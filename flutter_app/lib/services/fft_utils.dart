import 'dart:math';
import 'dart:typed_data';

/// In-place radix-2 FFT and utilities for the spectrogram pipeline.
class FFTUtils {
  /// Compute real-input FFT.
  /// Returns (magnitudes, phases) for bins 0..N/2 (N/2+1 bins).
  static (Float64List magnitudes, Float64List phases) computeRFFT(
      Float64List samples) {
    final int n = samples.length;
    assert((n & (n - 1)) == 0, 'Length must be power of 2');

    final real = Float64List.fromList(samples);
    final imag = Float64List(n);

    _fft(real, imag);

    final int bins = n ~/ 2 + 1;
    final mags = Float64List(bins);
    final phases = Float64List(bins);
    for (int i = 0; i < bins; i++) {
      mags[i] = sqrt(real[i] * real[i] + imag[i] * imag[i]);
      phases[i] = atan2(imag[i], real[i]);
    }
    return (mags, phases);
  }

  /// In-place radix-2 Cooley-Tukey FFT.
  /// [real] and [imag] are modified in place. Length must be power of 2.
  static void _fft(Float64List real, Float64List imag) {
    final int n = real.length;

    // ── Bit-reversal permutation ──
    for (int i = 1, j = 0; i < n; i++) {
      int bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        double tr = real[i];
        real[i] = real[j];
        real[j] = tr;
        double ti = imag[i];
        imag[i] = imag[j];
        imag[j] = ti;
      }
    }

    // ── Butterfly stages ──
    for (int len = 2; len <= n; len <<= 1) {
      final double wlenReal = cos(2 * pi / len);
      final double wlenImag = sin(2 * pi / len);
      for (int i = 0; i < n; i += len) {
        double wReal = 1.0;
        double wImag = 0.0;
        final int half = len ~/ 2;
        for (int j = 0; j < half; j++) {
          final int u = i + j;
          final int v = i + j + half;
          final double tReal = wReal * real[v] - wImag * imag[v];
          final double tImag = wReal * imag[v] + wImag * real[v];
          real[v] = real[u] - tReal;
          imag[v] = imag[u] - tImag;
          real[u] = real[u] + tReal;
          imag[u] = imag[u] + tImag;
          final double newWReal = wReal * wlenReal - wImag * wlenImag;
          wImag = wReal * wlenImag + wImag * wlenReal;
          wReal = newWReal;
        }
      }
    }
  }

  /// Generate a Hann window of [size] samples.
  static Float64List hannWindow(int size) {
    final w = Float64List(size);
    for (int i = 0; i < size; i++) {
      w[i] = 0.5 * (1 - cos(2 * pi * i / (size - 1)));
    }
    return w;
  }
}
