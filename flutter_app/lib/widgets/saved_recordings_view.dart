import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

/// A group of files that belong to one recording save.
class SavedRecording {
  final String name;
  final DateTime lastModified;
  final String directory;
  final List<FileSystemEntity> files;

  SavedRecording({
    required this.name,
    required this.lastModified,
    required this.directory,
    required this.files,
  });

  File? get wavFile => files.cast<File?>().firstWhere(
        (f) => f?.path.endsWith('.wav') ?? false,
        orElse: () => null,
      );

  File? get csvFile => files.cast<File?>().firstWhere(
        (f) => f?.path.endsWith('.csv') ?? false,
        orElse: () => null,
      );

  File? get jsonFile => files.cast<File?>().firstWhere(
        (f) => f?.path.endsWith('.json') ?? false,
        orElse: () => null,
      );

  File? get pngFile => files.cast<File?>().firstWhere(
        (f) => f?.path.endsWith('.png') ?? false,
        orElse: () => null,
      );

  String get sizeStr {
    int total = 0;
    for (final f in files) {
      if (f is File) total += f.lengthSync();
    }
    if (total < 1024) return '$total B';
    if (total < 1024 * 1024) return '${(total / 1024).toStringAsFixed(1)} KB';
    return '${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Model for a single file entry in the saved recordings list.
class _FileEntry {
  final String name; // e.g. "myrecording"
  final DateTime date;
  final List<File> files;

  _FileEntry({required this.name, required this.date, required this.files});
}

/// Tab that lists previously saved recordings and their files.
class SavedRecordingsView extends StatefulWidget {
  const SavedRecordingsView({super.key});

  @override
  State<SavedRecordingsView> createState() => _SavedRecordingsViewState();
}

class _SavedRecordingsViewState extends State<SavedRecordingsView> {
  List<_FileEntry> _recordings = [];
  bool _loading = true;
  String? _error;
  String? _deleteConfirm;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final saveDir = Directory('${dir.path}/spectrogram_saves');

      if (!await saveDir.exists()) {
        setState(() {
          _recordings = [];
          _loading = false;
        });
        return;
      }

      final entities = await saveDir.list().toList();
      // ---- Group files by base name ----
      // Each recording produces: {name}.wav, {name}_stft.csv, {name}_stft.json
      // We extract the stem and dedupe.
      final Map<String, List<File>> groups = {};
      for (final e in entities) {
        if (e is! File) continue;
        final stem = _stemOf(e.path);
        groups.putIfAbsent(stem, () => []).add(e);
      }

      // Build sorted entries (newest first)
      final entries = groups.entries.map((g) {
        final files = g.value;
        files.sort((a, b) => a.path.compareTo(b.path));
        final latestDate = files.fold(
          DateTime(2000),
          (DateTime d, f) => f.lastModifiedSync().isAfter(d)
              ? f.lastModifiedSync()
              : d,
        );
        return _FileEntry(
          name: g.key,
          date: latestDate,
          files: files,
        );
      }).toList();

      entries.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _recordings = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Extract the recording name stem from a file path.
  ///
  /// e.g. "dir/foo_stft.csv" → "foo",  "dir/bar.wav" → "bar"
  String _stemOf(String path) {
    final name = path.split('/').last;
    // Strip known suffixes: _stft.csv, _stft.json, _spectrogram.png, .wav, .csv, .json
    var stem = name;
    if (stem.endsWith('_spectrogram.png')) {
      stem = stem.substring(0, stem.length - '_spectrogram.png'.length);
    } else if (stem.endsWith('_stft.csv')) {
      stem = stem.substring(0, stem.length - '_stft.csv'.length);
    } else if (stem.endsWith('_stft.json')) {
      stem = stem.substring(0, stem.length - '_stft.json'.length);
    } else if (stem.endsWith('.wav')) {
      stem = stem.substring(0, stem.length - '.wav'.length);
    } else if (stem.endsWith('.csv')) {
      stem = stem.substring(0, stem.length - '.csv'.length);
    } else if (stem.endsWith('.json')) {
      stem = stem.substring(0, stem.length - '.json'.length);
    } else if (stem.endsWith('.png')) {
      stem = stem.substring(0, stem.length - '.png'.length);
    }
    return stem;
  }

  String _fileIcon(String path) {
    if (path.endsWith('.wav')) return '🎵';
    if (path.endsWith('.csv')) return '📊';
    if (path.endsWith('.json')) return '📋';
    if (path.endsWith('.png')) return '🖼️';
    return '📄';
  }

  String _fileDesc(String path) {
    if (path.endsWith('.wav')) return 'WAV Audio';
    if (path.endsWith('.csv')) return 'CSV Data (editable)';
    if (path.endsWith('.json')) return 'JSON Matrices';
    if (path.endsWith('.png')) return 'Spectrogram Image';
    return path.split('/').last;
  }

  Future<void> _deleteRecording(_FileEntry entry) async {
    setState(() => _deleteConfirm = entry.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Delete Recording'),
        content: Text(
          'Delete "${entry.name}" and all its files?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      setState(() => _deleteConfirm = null);
      return;
    }

    try {
      for (final f in entry.files) {
        await f.delete();
      }
      setState(() {
        _recordings.removeWhere((r) => r.name == entry.name);
        _deleteConfirm = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${entry.name}"'),
            backgroundColor: Colors.green.shade800,
          ),
        );
      }
    } catch (e) {
      setState(() => _deleteConfirm = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _openFile(File file) async {
    try {
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open file: ${result.message}'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening file: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 8),
            Text('Loading saved recordings…',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36, color: Colors.redAccent),
            const SizedBox(height: 8),
            Text('Error: $_error',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            const SizedBox(height: 12),
            _retryButton(),
          ],
        ),
      );
    }

    if (_recordings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            const Text('No saved recordings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                    color: Colors.white38)),
            const SizedBox(height: 4),
            const Text('Record and save to see your files here',
                style: TextStyle(fontSize: 12, color: Colors.white24)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRecordings,
      color: Colors.tealAccent,
      backgroundColor: const Color(0xFF0D1117),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        itemCount: _recordings.length,
        itemBuilder: (context, index) => _buildCard(_recordings[index]),
      ),
    );
  }

  Widget _retryButton() {
    return OutlinedButton.icon(
      onPressed: _loadRecordings,
      icon: const Icon(Icons.refresh, size: 16),
      label: const Text('Retry'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.tealAccent,
        side: const BorderSide(color: Colors.tealAccent, width: 0.5),
      ),
    );
  }

  Widget _buildCard(_FileEntry entry) {
    final isDeleting = _deleteConfirm == entry.name;

    // Calculate total size
    int totalBytes = 0;
    for (final f in entry.files) {
      totalBytes += f.lengthSync();
    }
    final sizeStr = totalBytes < 1024
        ? '$totalBytes B'
        : totalBytes < 1024 * 1024
            ? '${(totalBytes / 1024).toStringAsFixed(1)} KB'
            : '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

    final dateStr =
        '${entry.date.year}-${entry.date.month.toString().padLeft(2, '0')}-${entry.date.day.toString().padLeft(2, '0')} '
        '${entry.date.hour.toString().padLeft(2, '0')}:${entry.date.minute.toString().padLeft(2, '0')}';

    return Card(
      color: const Color(0xFF161B22),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF30363D), width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Name + date
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 10, color: Colors.white38),
                          const SizedBox(width: 4),
                          Text(dateStr,
                              style: const TextStyle(fontSize: 10, color: Colors.white38)),
                          const SizedBox(width: 12),
                          Icon(Icons.storage, size: 10, color: Colors.white38),
                          const SizedBox(width: 4),
                          Text(sizeStr,
                              style: const TextStyle(fontSize: 10, color: Colors.white38)),
                        ],
                      ),
                    ],
                  ),
                ),
                // Delete button
                isDeleting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: Colors.redAccent.withAlpha(150),
                        onPressed: () => _deleteRecording(entry),
                        tooltip: 'Delete recording',
                      ),
              ],
            ),
            const Divider(color: Color(0xFF30363D), height: 16),

            // File list
            ...entry.files.map((f) => _buildFileRow(f)),
          ],
        ),
      ),
    );
  }

  Widget _buildFileRow(File file) {
    final path = file.path;
    final name = path.split('/').last;
    final size = file.lengthSync();
    final sizeStr = size < 1024
        ? '$size B'
        : size < 1024 * 1024
            ? '${(size / 1024).toStringAsFixed(0)} KB'
            : '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _openFile(file),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Text(_fileIcon(path), style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _fileDesc(path),
                        style: const TextStyle(fontSize: 9, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
                Text(sizeStr,
                    style: const TextStyle(fontSize: 10, color: Colors.white38)),
                const SizedBox(width: 8),
                Icon(Icons.open_in_new, size: 14, color: Colors.tealAccent.withAlpha(150)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
