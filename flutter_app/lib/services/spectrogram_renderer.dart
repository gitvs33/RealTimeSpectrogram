import 'dart:typed_data';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/audio_frame.dart';

/// Renders a spectrogram image from recorded [AudioFrame] data.
///
/// Uses [dart:ui] Canvas + PictureRecorder to produce a PNG without
/// needing any widget to be visible on screen.  The output matches the
/// look of [SpectrogramPainter] (inferno-like colormap, dB scale, axis
/// labels).
class SpectrogramRenderer {
  SpectrogramRenderer._();

  /// Build a [ui.Image] from recorded frames.
  ///
  /// Returns `null` if [frames] is empty.
  static Future<ui.Image?> render({
    required List<AudioFrame> frames,
    int width = 800,
    int height = 400,
    double maxDisplayFreq = 8000,
  }) async {
    if (frames.isEmpty) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

    _drawSpectrogram(canvas, Size(width.toDouble(), height.toDouble()), frames, maxDisplayFreq);

    final picture = recorder.endRecording();
    return picture.toImage(width, height);
  }

  /// Convenience: render directly to PNG bytes.
  static Future<Uint8List?> renderToPng({
    required List<AudioFrame> frames,
    int width = 800,
    int height = 400,
    double maxDisplayFreq = 8000,
  }) async {
    final image = await render(
      frames: frames,
      width: width,
      height: height,
      maxDisplayFreq: maxDisplayFreq,
    );
    if (image == null) return null;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  // ───── internal drawing logic (mirrors SpectrogramPainter) ─────

  static final Uint8List _colorLut = _buildColorLut();

  static Uint8List _buildColorLut() {
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
    final lut = Uint8List(256 * 4);
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

  static void _drawSpectrogram(
    Canvas canvas,
    Size size,
    List<AudioFrame> frames,
    double maxDisplayFreq,
  ) {
    // ── background ──
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0D1117),
    );

    final numFrames = frames.length;
    if (numFrames == 0) return;
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

    // margin for labels
    const leftMargin = 56.0;
    const bottomMargin = 22.0;
    final plotW = size.width - leftMargin;
    final plotH = size.height - bottomMargin;

    final cellW = plotW / numFrames;
    final cellH = plotH / binCount;

    // dB range
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
    if (maxDb - minDb < 1) {
      minDb = maxDb - 60;
    }
    final dbRange = maxDb - minDb;

    // Draw columns
    for (int col = 0; col < numFrames; col++) {
      final frame = frames[col];
      final x = leftMargin + col * cellW;
      final mags = frame.magnitudes;

      for (int row = 0; row <= maxBin && row < mags.length; row++) {
        final db = _toDb(mags[row]);
        final norm = db.isFinite ? ((db - minDb) / dbRange).clamp(0.0, 1.0) : 0.0;
        final colorIdx = (norm * 255).round().clamp(0, 255);
        final r = _colorLut[colorIdx * 4] / 255.0;
        final g = _colorLut[colorIdx * 4 + 1] / 255.0;
        final b = _colorLut[colorIdx * 4 + 2] / 255.0;

        canvas.drawRect(
          Rect.fromLTWH(x, plotH - (row + 1) * cellH, cellW + 0.5, cellH + 0.5),
          Paint()..color = Color.fromRGBO(
            (r * 255).round(),
            (g * 255).round(),
            (b * 255).round(),
            1.0,
          ),
        );
      }
    }

    // ── axis labels ──
    final labelStyle = TextStyle(color: Colors.white60, fontSize: 11);
    final smallStyle = TextStyle(color: Colors.white38, fontSize: 10);

    // Frequency labels
    const freqLabelCount = 5;
    for (int i = 0; i <= freqLabelCount; i++) {
      final binIdx = (binCount * i / freqLabelCount).round().clamp(0, binCount - 1);
      final freq = freqs[binIdx];
      final y = plotH - (binIdx + 0.5) * cellH;
      _drawText(canvas, '${freq.round()} Hz', Offset(4, y - 6), labelStyle);
    }

    // Time labels
    const timeLabelCount = 6;
    for (int i = 0; i <= timeLabelCount; i++) {
      final frameIdx = (numFrames * i / timeLabelCount).round().clamp(0, numFrames - 1);
      final time = frames[frameIdx].time;
      final x = leftMargin + frameIdx * cellW;
      _drawText(canvas, '${time.toStringAsFixed(1)}s', Offset(x - 10, size.height - 18), smallStyle);
    }

    // Title
    _drawText(canvas, 'Spectrogram (dB magnitude)', Offset(leftMargin + 8, 4), labelStyle);
  }

  static double _toDb(double magnitude) {
    if (magnitude <= 0) return -80;
    return 20 * log(magnitude) / ln10;
  }

  static void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }
}
