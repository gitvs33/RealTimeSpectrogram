import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/audio_frame.dart';

/// Renders a scrollable film-strip spectrogram (frequency vs time heatmap).
///
/// Each column is one STFT frame at a fixed pixel width ([frameWidth]).
/// Only frames visible within the viewport are painted — the rest are skipped.
/// Use [scrollOffset] (in pixels) to pan through history.
class SpectrogramPainter extends CustomPainter {
  final List<AudioFrame> frames;
  final double maxDisplayFreq; // Hz — clip display above this
  final double scrollOffset; // pixels from left
  final double frameWidth; // fixed pixels per STFT frame column

  SpectrogramPainter({
    required this.frames,
    this.maxDisplayFreq = 8000,
    this.scrollOffset = 0,
    this.frameWidth = 3.0,
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

    // ── Determine which frames are visible in the viewport ──
    final firstCol = (scrollOffset / frameWidth).floor();
    final lastCol = ((scrollOffset + size.width) / frameWidth).ceil();
    final startCol = firstCol.clamp(0, numFrames - 1);
    final endCol = lastCol.clamp(startCol + 1, numFrames);
    final visibleCount = endCol - startCol;
    if (visibleCount <= 0) return;

    final cellH = size.height / binCount;

    // ── Compute dB range across visible frames ──
    double minDb = double.infinity;
    double maxDb = double.negativeInfinity;
    for (int col = startCol; col < endCol; col++) {
      final frame = frames[col];
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

    // ── Draw visible frames ──
    for (int col = startCol; col < endCol; col++) {
      final frame = frames[col];
      final x = col * frameWidth - scrollOffset;
      final mags = frame.magnitudes;

      for (int row = 0; row <= maxBin && row < mags.length; row++) {
        final db = _toDb(mags[row]);
        final norm = db.isFinite
            ? ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0)
            : 0.0;
        final colorIdx = (norm * 255).round().clamp(0, 255);
        final r = _colorLut[colorIdx * 4] / 255.0;
        final g = _colorLut[colorIdx * 4 + 1] / 255.0;
        final b = _colorLut[colorIdx * 4 + 2] / 255.0;

        final paint = Paint()
          ..color = Color.fromRGBO(
            (r * 255).round(),
            (g * 255).round(),
            (b * 255).round(),
            1.0,
          );
        canvas.drawRect(
          Rect.fromLTWH(
            x,
            size.height - (row + 1) * cellH,
            frameWidth + 0.5,
            cellH + 0.5,
          ),
          paint,
        );
      }
    }

    // ── Draw axis labels ──
    _drawAxes(canvas, size, binCount, freqs);
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
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
  }

  void _drawAxes(Canvas canvas, Size size, int binCount, List<double> freqs) {
    final numFrames = frames.length;

    // ── Frequency axis labels (left side) ──
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

    // ── Time axis labels (bottom) — only for visible frames ──
    final firstCol = (scrollOffset / frameWidth).floor().clamp(0, numFrames - 1);
    final lastCol =
        ((scrollOffset + size.width) / frameWidth).ceil().clamp(firstCol + 1, numFrames);
    final visibleCount = lastCol - firstCol;
    if (visibleCount <= 0) return;

    final nTimeLabels = min(6, visibleCount);
    for (int i = 0; i <= nTimeLabels; i++) {
      final frameIdx = firstCol + (visibleCount * i / nTimeLabels).round();
      if (frameIdx >= numFrames) continue;
      final time = frames[frameIdx].time;
      final x = frameIdx * frameWidth - scrollOffset;
      // Skip labels outside visible area
      if (x < -10 || x > size.width + 10) continue;
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
      oldDelegate.frames != frames ||
      oldDelegate.frames.length != frames.length ||
      oldDelegate.scrollOffset != scrollOffset ||
      oldDelegate.frameWidth != frameWidth;
}

/// Renders a scrollable film-strip phase-angle colormap.
///
/// Phase is mapped to a cyclic hue (HSV) so that -π = π = same color.
/// Only visible frames are painted. Scrollable via [scrollOffset].
class PhasePainter extends CustomPainter {
  final List<AudioFrame> frames;
  final double maxDisplayFreq;
  final double scrollOffset;
  final double frameWidth;

  PhasePainter({
    required this.frames,
    this.maxDisplayFreq = 8000,
    this.scrollOffset = 0,
    this.frameWidth = 3.0,
  });

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

    // ── Determine visible frames ──
    final firstCol = (scrollOffset / frameWidth).floor();
    final lastCol = ((scrollOffset + size.width) / frameWidth).ceil();
    final startCol = firstCol.clamp(0, numFrames - 1);
    final endCol = lastCol.clamp(startCol + 1, numFrames);
    final visibleCount = endCol - startCol;
    if (visibleCount <= 0) return;

    final cellH = size.height / binCount;

    // ── Draw visible frames ──
    for (int col = startCol; col < endCol; col++) {
      final frame = frames[col];
      final x = col * frameWidth - scrollOffset;
      final phases = frame.phases;

      for (int row = 0; row <= maxBin && row < phases.length; row++) {
        // Map phase [-π, π] → hue [0, 360]
        final phase = phases[row];
        final hue = ((phase / pi) * 180 + 180) % 360;
        final color = HSVColor.fromAHSV(1.0, hue, 0.9, 0.9).toColor();

        canvas.drawRect(
          Rect.fromLTWH(
            x,
            size.height - (row + 1) * cellH,
            frameWidth + 0.5,
            cellH + 0.5,
          ),
          Paint()..color = color,
        );
      }
    }

    // ── Axis labels ──
    _drawAxes(canvas, size, binCount, freqs);
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
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
  }

  void _drawAxes(Canvas canvas, Size size, int binCount, List<double> freqs) {
    final numFrames = frames.length;

    // ── Frequency labels ──
    final labelCount = 4;
    for (int i = 0; i <= labelCount; i++) {
      final binIdx = (binCount * i / labelCount).round().clamp(0, binCount - 1);
      final freq = freqs[binIdx];
      final y = size.height - (binIdx + 0.5) * (size.height / binCount);
      final tp = TextPainter(
        text: TextSpan(
          text: '${freq.round()} Hz',
          style: const TextStyle(color: Colors.white60, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }

    // ── Time labels (visible frames only) ──
    final firstCol = (scrollOffset / frameWidth).floor().clamp(0, numFrames - 1);
    final lastCol =
        ((scrollOffset + size.width) / frameWidth).ceil().clamp(firstCol + 1, numFrames);
    final visibleCount = lastCol - firstCol;
    if (visibleCount <= 0) return;

    final nTimeLabels = min(4, visibleCount);
    for (int i = 0; i <= nTimeLabels; i++) {
      final frameIdx = firstCol + (visibleCount * i / nTimeLabels).round();
      if (frameIdx >= numFrames) continue;
      final time = frames[frameIdx].time;
      final x = frameIdx * frameWidth - scrollOffset;
      if (x < -10 || x > size.width + 10) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: '${time.toStringAsFixed(1)}s',
          style: const TextStyle(color: Colors.white60, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - 14));
    }
  }

  @override
  bool shouldRepaint(PhasePainter oldDelegate) =>
      oldDelegate.frames != frames ||
      oldDelegate.frames.length != frames.length ||
      oldDelegate.scrollOffset != scrollOffset ||
      oldDelegate.frameWidth != frameWidth;
}
