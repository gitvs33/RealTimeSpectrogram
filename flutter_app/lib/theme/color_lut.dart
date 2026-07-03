import 'dart:typed_data';

/// Shared inferno-inspired 256-entry RGBA color lookup table.
///
/// Used by [SpectrogramPainter] (live preview) and [SpectrogramRenderer]
/// (PNG export) so the colormap is defined in exactly one place.
///
/// Each entry is 4 bytes: R, G, B, A (alpha is always 255).
/// Total size: 256 × 4 = 1024 bytes.
///
/// ```dart
/// final r = ColorLut.rgba[idx * 4] / 255.0;   // painter
/// final b = ColorLut.rgba[idx * 4 + 2];         // renderer (byte)
/// ```
class ColorLut {
  ColorLut._();

  /// 1024-byte RGBA lookup table (256 entries × 4 bytes).
  static final Uint8List rgba = _build();

  /// Number of entries (256).
  static const int size = 256;

  /// Bytes per entry (4 → RGBA).
  static const int stride = 4;

  static Uint8List _build() {
    // Inferno-inspired palette (ARGB hex values).
    const colors = <int>[
      0xFF000004, // pure black
      0xFF0c0887, // deep indigo
      0xFF4b0f6b, // purple
      0xFF931e6c, // magenta
      0xFFd4485b, // red
      0xFFfb8844, // orange
      0xFFf6d644, // yellow
      0xFFfcffa4, // pale yellow
    ];

    final lut = Uint8List(size * stride); // 256 × 4
    for (int i = 0; i < size; i++) {
      double t = i / 255.0;

      // Bottom 25% → pure black for better contrast
      if (t < 0.25) {
        lut[i * stride] = 0;
        lut[i * stride + 1] = 0;
        lut[i * stride + 2] = 0;
        lut[i * stride + 3] = 255;
        continue;
      }

      // Remap remaining 75% across the gradient stops
      t = (t - 0.25) / 0.75;
      final pos = t * (colors.length - 1);
      final idx = pos.floor();
      final frac = pos - idx;
      final c0 = colors[idx.clamp(0, colors.length - 1)];
      final c1 = colors[(idx + 1).clamp(0, colors.length - 1)];

      final r0 = (c0 >> 16) & 0xFF;
      final g0 = (c0 >> 8) & 0xFF;
      final b0 = c0 & 0xFF;
      final r1 = (c1 >> 16) & 0xFF;
      final g1 = (c1 >> 8) & 0xFF;
      final b1 = c1 & 0xFF;

      lut[i * stride] = (r0 + (r1 - r0) * frac).round().clamp(0, 255);
      lut[i * stride + 1] = (g0 + (g1 - g0) * frac).round().clamp(0, 255);
      lut[i * stride + 2] = (b0 + (b1 - b0) * frac).round().clamp(0, 255);
      lut[i * stride + 3] = 255; // alpha
    }
    return lut;
  }
}
