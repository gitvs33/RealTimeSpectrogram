import '../models/audio_frame.dart';

/// Pure data for one row in the STFT data table.
class StftRowData {
  final String key;
  final String time;
  final String frequency;
  final String amplitude;
  final String phase;

  const StftRowData({
    required this.key,
    required this.time,
    required this.frequency,
    required this.amplitude,
    required this.phase,
  });
}

/// Immutable query object that encapsulates filtering, paging, and
/// TSV-export logic for the STFT data table.
///
/// Separating this from the widget makes the filtering logic testable
/// and reduces the widget's state surface.
class StftDataQuery {
  final String searchFilter;
  final bool showOnlyNonZero;

  const StftDataQuery({
    this.searchFilter = '',
    this.showOnlyNonZero = true,
  });

  /// True when neither filter is active — the fast path can be used.
  bool get isTrivial => searchFilter.isEmpty && !showOnlyNonZero;

  // ── Helpers ────────────────────────────────────────────────────────

  int binCount(List<AudioFrame> frames) =>
      frames.isEmpty ? 0 : frames.first.binCount;

  int totalRows(List<AudioFrame> frames) {
    if (frames.isEmpty) return 0;
    if (isTrivial) return frames.length * binCount(frames);

    int count = 0;
    final bc = binCount(frames);
    final q = searchFilter.toLowerCase();
    for (final frame in frames) {
      final t = frame.time.toStringAsFixed(3);
      for (int bi = 0; bi < bc; bi++) {
        if (showOnlyNonZero && frame.magnitudes[bi] == 0) continue;
        if (q.isNotEmpty) {
          final freq = frame.frequencies[bi].toStringAsFixed(1);
          final amp = frame.magnitudes[bi].toStringAsFixed(6);
          final phase = frame.phases[bi].toStringAsFixed(6);
          if (!t.contains(q) &&
              !freq.contains(q) &&
              !amp.contains(q) &&
              !phase.contains(q)) continue;
        }
        count++;
      }
    }
    return count;
  }

  /// Get row data at [idx] (0-based among visible rows), or null if
  /// the index is out of range.
  StftRowData? rowAt(List<AudioFrame> frames, int idx) {
    if (frames.isEmpty) return null;
    final bc = binCount(frames);
    if (bc == 0) return null;

    if (isTrivial) {
      // Fast path: direct index → frame/bin without scanning.
      final fi = idx ~/ bc;
      final bi = idx % bc;
      if (fi >= frames.length) return null;
      final frame = frames[fi];
      if (bi >= frame.binCount) return null;
      return _makeRow(frame, bi);
    }

    // Slow path: scan visible rows until we hit idx.
    int seen = 0;
    final q = searchFilter.toLowerCase();
    for (final frame in frames) {
      final t = frame.time.toStringAsFixed(3);
      for (int bi = 0; bi < bc; bi++) {
        if (showOnlyNonZero && frame.magnitudes[bi] == 0) continue;
        if (q.isNotEmpty) {
          final freq = frame.frequencies[bi].toStringAsFixed(1);
          final amp = frame.magnitudes[bi].toStringAsFixed(6);
          final phase = frame.phases[bi].toStringAsFixed(6);
          if (!t.contains(q) &&
              !freq.contains(q) &&
              !amp.contains(q) &&
              !phase.contains(q)) continue;
        }
        if (seen == idx) return _makeRow(frame, bi, time: t);
        seen++;
      }
    }
    return null;
  }

  /// Build a TSV string from [frames], respecting current filter.
  /// Defaults to a maximum of 10 000 rows to avoid clipboard blow-up.
  String exportTsv(List<AudioFrame> frames, {int maxLines = 10000}) {
    if (frames.isEmpty) return '';
    final sb = StringBuffer('time_s\tfrequency_hz\tamplitude\tphase_radians\n');
    int lines = 0;
    final bc = binCount(frames);
    final q = searchFilter.toLowerCase();

    for (final frame in frames) {
      final t = frame.time.toStringAsFixed(3);
      for (int bi = 0; bi < bc; bi++) {
        if (showOnlyNonZero && frame.magnitudes[bi] == 0) continue;
        if (q.isNotEmpty) {
          final freq = frame.frequencies[bi].toStringAsFixed(1);
          final amp = frame.magnitudes[bi].toStringAsFixed(6);
          final phase = frame.phases[bi].toStringAsFixed(6);
          if (!t.contains(q) &&
              !freq.contains(q) &&
              !amp.contains(q) &&
              !phase.contains(q)) continue;
        }
        if (lines >= maxLines) break;
        sb.writeln(
          '$t\t${frame.frequencies[bi].toStringAsFixed(1)}\t'
          '${frame.magnitudes[bi].toStringAsFixed(6)}\t'
          '${frame.phases[bi].toStringAsFixed(6)}',
        );
        lines++;
      }
      if (lines >= maxLines) break;
    }
    return sb.toString();
  }

  // ── Internal ───────────────────────────────────────────────────────

  StftRowData _makeRow(AudioFrame frame, int bi, {String? time}) {
    return StftRowData(
      key: '${frame.time}_$bi',
      time: time ?? frame.time.toStringAsFixed(3),
      frequency: frame.frequencies[bi].toStringAsFixed(1),
      amplitude: frame.magnitudes[bi].toStringAsFixed(6),
      phase: frame.phases[bi].toStringAsFixed(6),
    );
  }
}
