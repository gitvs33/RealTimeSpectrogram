/// Generates app icon PNGs at all Android mipmap densities.
///
/// Run from flutter_app/:
///   dart run tools/generate_icon.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  final sizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };

  for (final entry in sizes.entries) {
    final image = generateIcon(entry.value);
    final outDir = Directory('android/app/src/main/res/${entry.key}');
    outDir.createSync(recursive: true);
    final path = '${outDir.path}/ic_launcher.png';
    File(path).writeAsBytesSync(img.encodePng(image));
    print('  $path  (${entry.value}x${entry.value})');
  }
  print('Done.');
}

img.Image generateIcon(int size) {
  final image = img.Image(width: size, height: size);
  final half = size / 2;

  // ── Background: dark indigo rounded-square ──
  final cornerR = size * 0.22;
  final halfMinusCorner = half - cornerR;
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final dx = (x - half).abs();
      final dy = (y - half).abs();

      // Rounded-square test
      bool inside;
      if (dx < halfMinusCorner || dy < halfMinusCorner) {
        inside = dx < half && dy < half;
      } else {
        final cx = (dx - halfMinusCorner).clamp(0.0, cornerR);
        final cy = (dy - halfMinusCorner).clamp(0.0, cornerR);
        inside = math.sqrt(cx * cx + cy * cy) < cornerR;
      }

      if (inside) {
        // Subtle gradient: slightly lighter toward center
        final dist = math.sqrt((x - half) * (x - half) + (y - half) * (y - half));
        final t = (dist / (size * 0.65)).clamp(0.0, 1.0);
        final r = (18 + (1 - t) * 10).round().clamp(0, 255);
        final g = (22 + (1 - t) * 12).round().clamp(0, 255);
        final b = (30 + (1 - t) * 16).round().clamp(0, 255);
        image.setPixelRgb(x, y, r, g, b);
      } else {
        image.setPixelRgb(x, y, 0, 0, 0);
      }
    }
  }

  // ── Waveform bars ──
  final bars = 7;
  final barAreaW = size * 0.6;
  final barW = barAreaW / bars;
  final barSpacing = barW;
  final maxBarH = size * 0.40;
  final barBottom = half + maxBarH * 0.5;
  final startX = half - barAreaW / 2;

  // Envelope: rise then fall
  for (int i = 0; i < bars; i++) {
    final phase = (i / (bars - 1)) * math.pi;
    final barH = maxBarH * (0.25 + 0.75 * math.sin(phase).abs());
    final cx = startX + (i + 0.5) * barSpacing;
    final left = (cx - barW * 0.3).round();
    final right = (cx + barW * 0.3).round();
    final top = (barBottom - barH).round();
    final bottom = barBottom.round();
    final barCornerR = (barW * 0.25).round();

    for (int py = top; py < bottom; py++) {
      for (int px = left; px < right; px++) {
        if (px < 0 || px >= size || py < 0 || py >= size) continue;
        // Rounded top corners
        if (py - top < barCornerR &&
            ((px - left) < barCornerR || (right - px - 1) < barCornerR)) {
          final d = math.sqrt(
              ((px - left) - barCornerR).toDouble().pow(2) +
                  ((py - top) - barCornerR).toDouble().pow(2));
          if (d > barCornerR) continue;
        }
        // Gradient: brighter at center
        final bright = (1.0 - ((px - cx).abs() / (barW * 0.5)).clamp(0.0, 1.0) * 0.4);
        image.setPixelRgb(
          px,
          py,
          (66 * bright).round().clamp(0, 255),
          (165 * bright).round().clamp(0, 255),
          (245 * bright).round().clamp(0, 255),
        );
      }
    }
  }

  // ── Stylized "O" ring ──
  final oCx = half;
  final oCy = half;
  final oOuterR = size * 0.34;
  final oInnerR = size * 0.22;
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final dist = math.sqrt((x - oCx) * (x - oCx) + (y - oCy) * (y - oCy));
      if (dist > oInnerR && dist < oOuterR) {
        // Read current pixel and blend with white
        // Using the image's internal data directly via getPixel
        final px = image.getPixel(x, y);
        final nr = (px.r * 0.7 + 255 * 0.3).round().clamp(0, 255);
        final ng = (px.g * 0.7 + 255 * 0.3).round().clamp(0, 255);
        final nb = (px.b * 0.7 + 255 * 0.3).round().clamp(0, 255);
        image.setPixelRgb(x, y, nr, ng, nb);
      }
    }
  }

  return image;
}

extension _Pow on double {
  double pow(int e) => math.pow(this, e).toDouble();
}
