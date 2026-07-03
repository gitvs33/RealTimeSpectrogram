import 'package:flutter/material.dart';

/// A scrollable film-strip wrapper for a [CustomPainter].
///
/// Used by both the spectrogram view (which paints magnitude heatmaps)
/// and the phase view (which paints phase angles), sharing the same
/// gesture and clipping logic.
///
/// ```dart
/// SpectrogramFilmStrip(
///   painter: SpectrogramPainter(frames: ..., scrollOffset: ...),
///   viewportWidth: constraints.maxWidth,
///   viewportHeight: constraints.maxHeight,
///   onHorizontalDrag: (dx) { /* update scrollOffset */ },
/// )
/// ```
class SpectrogramFilmStrip extends StatelessWidget {
  final CustomPainter painter;
  final double viewportWidth;
  final double viewportHeight;
  final void Function(double dx) onHorizontalDrag;

  const SpectrogramFilmStrip({
    super.key,
    required this.painter,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.onHorizontalDrag,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) => onHorizontalDrag(details.delta.dx),
      child: ClipRect(
        child: CustomPaint(
          painter: painter,
          size: Size(viewportWidth, viewportHeight),
        ),
      ),
    );
  }
}
