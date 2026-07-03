import 'dart:io';

/// A group of related recording files sharing the same stem name.
///
/// Example: a stem named "my_guitar_riff" might contain:
///   - my_guitar_riff.wav
///   - my_guitar_riff_stft.csv
///   - my_guitar_riff_stft.json
///   - my_guitar_riff_spectrogram.png
///   - my_guitar_riff_instrumental.wav  (after Sound-to-Music conversion)
class RecordingGroup {
  final String name;
  final List<File> files;
  final DateTime lastModified;

  RecordingGroup._({
    required this.name,
    required this.files,
    required this.lastModified,
  });

  /// The original recorded WAV (not the instrumental conversion).
  File? get wavFile {
    for (final f in files) {
      final fn = f.path.split('/').last;
      if (fn.endsWith('.wav') &&
          !fn.contains('_instrumental')) {
        return f;
      }
    }
    return null;
  }

  /// STFT CSV export.
  File? get csvFile {
    for (final f in files) {
      if (f.path.endsWith('_stft.csv')) return f;
    }
    return null;
  }

  /// STFT JSON export.
  File? get jsonFile {
    for (final f in files) {
      if (f.path.endsWith('_stft.json')) return f;
    }
    return null;
  }

  /// Spectrogram PNG screenshot.
  File? get pngFile {
    for (final f in files) {
      if (f.path.endsWith('_spectrogram.png')) return f;
    }
    return null;
  }

  /// Instrumental result from Sound-to-Music conversion.
  File? get instrumentalFile {
    for (final f in files) {
      if (f.path.endsWith('_instrumental.wav')) return f;
    }
    return null;
  }
}

/// Scans and manages recording files in the spectrogram_saves directory.
///
/// ```dart
/// final repo = RecordingRepository(
///   directoryPath: '${dir.path}/spectrogram_saves',
/// );
/// final groups = await repo.list();
/// await repo.delete(groups[0]);
/// ```
class RecordingRepository {
  final String directoryPath;

  RecordingRepository({required this.directoryPath});

  /// List recording groups sorted by most recently modified first.
  Future<List<RecordingGroup>> list() async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return [];

    final entities = await dir.list().toList();
    final Map<String, List<File>> groups = {};

    for (final e in entities) {
      if (e is! File) continue;
      final stem = stemOf(e.path);
      if (stem == null) continue; // unknown file type
      groups.putIfAbsent(stem, () => []).add(e);
    }

    return groups.entries.map((g) {
      final files = g.value;
      DateTime latest = DateTime(2000);
      for (final f in files) {
        final m = f.lastModifiedSync();
        if (m.isAfter(latest)) latest = m;
      }
      return RecordingGroup._(
        name: g.key,
        files: files,
        lastModified: latest,
      );
    }).toList()
      ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
  }

  /// Delete all files in a recording group.
  Future<void> delete(RecordingGroup group) async {
    for (final f in group.files) {
      await f.delete();
    }
  }

  // ── Stem extraction ──

  /// Extract the stem name from a recording file path.
  ///
  /// Returns `null` if the file doesn't match any known pattern.
  static String? stemOf(String path) {
    final name = path.split('/').last;

    // Check longer/compound suffixes first to avoid partial matches.
    if (name.endsWith('_spectrogram.png')) {
      return name.substring(0, name.length - '_spectrogram.png'.length);
    }
    if (name.endsWith('_stft.csv')) {
      return name.substring(0, name.length - '_stft.csv'.length);
    }
    if (name.endsWith('_stft.json')) {
      return name.substring(0, name.length - '_stft.json'.length);
    }
    if (name.endsWith('_instrumental.wav')) {
      return name.substring(0, name.length - '_instrumental.wav'.length);
    }
    if (name.endsWith('.wav')) {
      // Bare .wav (not _instrumental.wav)
      return name.substring(0, name.length - '.wav'.length);
    }

    return null; // unrecognised file type
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Formatting helpers (shared by views)
// ═════════════════════════════════════════════════════════════════════════

/// Format a [DateTime] as "Mon D, YYYY H:MM AM/PM".
String formatDateTime(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = dt.hour > 12
      ? dt.hour - 12
      : (dt.hour == 0 ? 12 : dt.hour);
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year} '
      '$h:${dt.minute.toString().padLeft(2, '0')} $ampm';
}

/// Format byte count as a human-readable string (B, KB, MB).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
