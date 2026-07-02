import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/audio_frame.dart';

/// Renders a rolling spectrogram (frequency vs time heatmap).
///
/// Each column is one STFT frame. Magnitudes are converted to dB and
/// mapped through an "inferno-like" color gradient.
class SpectrogramPainter extends CustomPainter {
  final List<AudioFrame> frames;
  final double maxDisplayFreq; // Hz — clip display above this

  SpectrogramPainter({
    required this.frames,
    this.maxDisplayFreq = 8000,
  });

  // Pre-built color lookup table (256 entries, inferno-like)
  static final Uint8List _colorLut = _buildColorLut();

  static Uint8List _buildColorLut() {
    // Inferno-inspired gradient: black → purple → orange → yellow → white
    const colors = [
      Color(0xFF000004),
      Color(0xFF0c0887),
      Color(0xFF4b0f6b),
      Color(0xFF931e6c),
      Color(0xFFd4485b),
      Color(0xFFfb8844),
      Color(0xFFf6d644),
      Color(0xFFfcffa4),
    ];
    final lut = Uint8List(256 * 4); // RGBA per entry
    for (int i = 0; i < 256; i++) {
      final t = i / 255.0;
      final pos = t * (colors.length - 1);
      final idx = pos.floor();
      final frac = pos - idx;
      final c0 = colors[idx.clamp(0, colors.length - 1)];
      final c1 = colors[(idx + 1).clamp(0, colors.length - 1)];
      final r = (c0.r + (c1.r - c0.r) * frac);
      final g = (c0.g + (c1.g - c0.g) * frac);
      final b = (c0.b + (c1.b - c0.b) * frac);
      lut[i * 4] = (r * 255).round().clamp(0, 255);
      lut[i * 4 + 1] = (g * 255).round().clamp(0, 255);
      lut[i * 4 + 2] = (b * 255).round().clamp(0, 255);
      lut[i * 4 + 3] = 255;
    }
    return lut;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty) {
      _drawPlaceholder(canvas, size, 'Waiting for audio...');
      return;
    }

    final numFrames = frames.length;
    if (numFrames == 0) return;

    // Determine which frequency bins to show (up to maxDisplayFreq)
    final freqs = frames.first.frequencies;
    int maxBin = freqs.length - 1;
    for (int i = 0; i < freqs.length; i++) {
      if (freqs[i] > maxDisplayFreq) {
        maxBin = i;
        break;
      }
    }
    maxBin = maxBin.clamp(1, freqs.length - 1);
    final binCount = maxBin + 1;

    final cellW = size.width / numFrames;
    final cellH = size.height / binCount;

    // Compute dB range across visible frames for dynamic range
    double minDb = double.infinity;
    double maxDb = double.negativeInfinity;
    for (final frame in frames) {
      for (int i = 0; i <= maxBin && i < frame.magnitudes.length; i++) {
        final db = _toDb(frame.magnitudes[i]);
        if (db.isFinite) {
          minDb = min(minDb, db);
          maxDb = max(maxDb, db);
        }
      }
    }
    if (minDb == double.infinity) {
      minDb = -80;
      maxDb = 0;
    }
    final dbRange = maxDb - minDb;
    if (dbRange < 1) {
      minDb = maxDb - 60;
    }

    // Draw column by column
    for (int col = 0; col < numFrames; col++) {
      final frame = frames[col];
      final x = col * cellW;
      final mags = frame.magnitudes;

      for (int row = 0; row <= maxBin && row < mags.length; row++) {
        final db = _toDb(mags[row]);
        final norm = db.isFinite ? ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0) : 0.0;
        final colorIdx = (norm * 255).round().clamp(0, 255);
        final r = _colorLut[colorIdx * 4] / 255.0;
        final g = _colorLut[colorIdx * 4 + 1] / 255.0;
        final b = _colorLut[colorIdx * 4 + 2] / 255.0;

        final paint = Paint()..color = Color.fromRGBO(
          (r * 255).round(),
          (g * 255).round(),
          (b * 255).round(),
          1.0,
        );
        canvas.drawRect(
          Rect.fromLTWH(x, size.height - (row + 1) * cellH, cellW + 0.5, cellH + 0.5),
          paint,
        );
      }
    }

    // Draw axis labels
    _drawAxes(canvas, size, binCount, freqs, numFrames);
  }

  double _toDb(double magnitude) {
    if (magnitude <= 0) return -80;
    return 20 * log(magnitude) / ln10;
  }

  void _drawPlaceholder(Canvas canvas, Size size, String text) {
    final paint = Paint()..color = Colors.white24;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white54, fontSize: 16),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  void _drawAxes(Canvas canvas, Size size, int binCount, List<double> freqs, int numFrames) {
    // Frequency axis labels (left side)
    final labelCount = 5;
    for (int i = 0; i <= labelCount; i++) {
      final binIdx = (binCount * i / labelCount).round().clamp(0, binCount - 1);
      final freq = freqs[binIdx];
      final y = size.height - (binIdx + 0.5) * (size.height / binCount);
      final tp = TextPainter(
        text: TextSpan(
          text: '${freq.round()} Hz',
          style: TextStyle(color: Colors.white60, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }

    // Time axis labels (top or bottom)
    final timeLabels = 6;
    for (int i = 0; i <= timeLabels; i++) {
      final frameIdx = (numFrames * i / timeLabels).round().clamp(0, numFrames - 1);
      final time = frames.isNotEmpty ? frames[frameIdx].time : 0.0;
      final x = frameIdx * (size.width / max(numFrames, 1));
      final tp = TextPainter(
        text: TextSpan(
          text: '${time.toStringAsFixed(1)}s',
          style: TextStyle(color: Colors.white60, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - 14));
    }
  }

  @override
  bool shouldRepaint(SpectrogramPainter oldDelegate) =>
      oldDelegate.frames != frames || oldDelegate.frames.length != frames.length;
}

/// Renders a phase-angle colormap (rolling).
///
/// Phase is mapped to a cyclic hue (HSV) so that -π = π = same color.
class PhasePainter extends CustomPainter {
  final List<AudioFrame> frames;
  final double maxDisplayFreq;

  PhasePainter({required this.frames, this.maxDisplayFreq = 8000});

  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty) {
      _drawPlaceholder(canvas, size, 'Waiting for audio...');
      return;
    }

    final numFrames = frames.length;
    final freqs = frames.first.frequencies;
    int maxBin = freqs.length - 1;
    for (int i = 0; i < freqs.length; i++) {
      if (freqs[i] > maxDisplayFreq) {
        maxBin = i;
        break;
      }
    }
    maxBin = maxBin.clamp(1, freqs.length - 1);
    final binCount = maxBin + 1;

    final cellW = size.width / numFrames;
    final cellH = size.height / binCount;

    for (int col = 0; col < numFrames; col++) {
      final frame = frames[col];
      final x = col * cellW;
      final phases = frame.phases;

      for (int row = 0; row <= maxBin && row < phases.length; row++) {
        // Map phase [-π, π] → hue [0, 360]
        final phase = phases[row];
        final hue = ((phase / pi) * 180 + 180) % 360;
        final color = HSVColor.fromAHSV(1.0, hue, 0.9, 0.9).toColor();

        canvas.drawRect(
          Rect.fromLTWH(x, size.height - (row + 1) * cellH, cellW + 0.5, cellH + 0.5),
          Paint()..color = color,
        );
      }
    }

    // Axis labels
    _drawAxes(canvas, size, binCount, freqs, numFrames);
  }

  void _drawPlaceholder(Canvas canvas, Size size, String text) {
    final paint = Paint()..color = Colors.white24;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: Colors.white54, fontSize: 16)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  void _drawAxes(Canvas canvas, Size size, int binCount, List<double> freqs, int numFrames) {
    final labelCount = 4;
    for (int i = 0; i <= labelCount; i++) {
      final binIdx = (binCount * i / labelCount).round().clamp(0, binCount - 1);
      final freq = freqs[binIdx];
      final y = size.height - (binIdx + 0.5) * (size.height / binCount);
      final tp = TextPainter(
        text: TextSpan(text: '${freq.round()} Hz', style: const TextStyle(color: Colors.white60, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }

    for (int i = 0; i <= 4; i++) {
      final frameIdx = (numFrames * i / 4).round().clamp(0, numFrames - 1);
      final time = frames.isNotEmpty ? frames[frameIdx].time : 0.0;
      final x = frameIdx * (size.width / max(numFrames, 1));
      final tp = TextPainter(
        text: TextSpan(text: '${time.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white60, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - 14));
    }
  }

  @override
  bool shouldRepaint(PhasePainter oldDelegate) =>
      oldDelegate.frames != frames || oldDelegate.frames.length != frames.length;
}
