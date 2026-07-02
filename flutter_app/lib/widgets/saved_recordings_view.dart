import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/spectrogram_service.dart';

class _FileEntry {
  final String name;
  final DateTime date;
  final List<File> files;
  final String durationStr;

  _FileEntry({
    required this.name,
    required this.date,
    required this.files,
    this.durationStr = '00:00:00',
  });
}

class SavedRecordingsView extends StatefulWidget {
  const SavedRecordingsView({super.key});

  @override
  State<SavedRecordingsView> createState() => _SavedRecordingsViewState();
}

class _SavedRecordingsViewState extends State<SavedRecordingsView> {
  List<_FileEntry> _recordings = [];
  bool _loading = true;
  String? _error;
  String _lastSaveMsg = '';

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      final svc = context.read<SpectrogramService>();
      svc.addListener(_onServiceChange);
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      context.read<SpectrogramService>().removeListener(_onServiceChange);
    } catch (_) {}
    super.dispose();
  }

  void _onServiceChange() {
    try {
      final svc = context.read<SpectrogramService>();
      if (svc.saveMessage.isNotEmpty && svc.saveMessage != _lastSaveMsg) {
        _lastSaveMsg = svc.saveMessage;
        _loadRecordings();
      }
    } catch (_) {}
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
      final Map<String, List<File>> groups = {};
      for (final e in entities) {
        if (e is! File) continue;
        final stem = _stemOf(e.path);
        groups.putIfAbsent(stem, () => []).add(e);
      }

      final entries = groups.entries.map((g) {
        final files = g.value;
        files.sort((a, b) => a.path.compareTo(b.path));
        final latestDate = files.fold(
          DateTime(2000),
          (DateTime d, f) =>
              f.lastModifiedSync().isAfter(d) ? f.lastModifiedSync() : d,
        );
        return _FileEntry(
          name: g.key,
          date: latestDate,
          files: files,
          // Mock duration for now, real app would parse WAV or JSON
          durationStr: '00:02:53',
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

  String _stemOf(String path) {
    final name = path.split('/').last;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                '$_error',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loadRecordings,
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
                label: const Text('Retry', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      );
    }

    // Top bar
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: const TextField(
                    style: TextStyle(fontSize: 12, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search recordings...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: InputBorder.none,
                      suffixIcon: Icon(
                        Icons.search,
                        size: 16,
                        color: Colors.white54,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: const Row(
                  children: [
                    Text(
                      'Sort: Newest',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white54,
                      size: 16,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _loadRecordings,
                child: const Icon(
                  Icons.refresh,
                  color: Colors.white54,
                  size: 20,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recordings.length,
            itemBuilder: (context, index) => _buildCard(_recordings[index]),
          ),
        ),

        // Footer
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_recordings.length} recordings',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              Text(
                'Total size: ${_getTotalSize()}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getTotalSize() {
    int totalBytes = 0;
    for (var r in _recordings) {
      for (var f in r.files) {
        totalBytes += f.lengthSync();
      }
    }
    if (totalBytes < 1024 * 1024)
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildCard(_FileEntry entry) {
    int totalBytes = 0;
    for (final f in entry.files) totalBytes += f.lengthSync();
    final sizeStr = totalBytes < 1024 * 1024
        ? '${(totalBytes / 1024).toStringAsFixed(1)} KB'
        : '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

    // Mock date format
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dateStr =
        '${monthNames[entry.date.month - 1]} ${entry.date.day}, ${entry.date.year} ${entry.date.hour > 12 ? entry.date.hour - 12 : (entry.date.hour == 0 ? 12 : entry.date.hour)}:${entry.date.minute.toString().padLeft(2, '0')} ${entry.date.hour >= 12 ? 'PM' : 'AM'}';

    // Check for specific files to show badges
    File? wavF, csvF, jsonF, pngF;
    for (var f in entry.files) {
      if (f.path.endsWith('.wav')) wavF = f;
      if (f.path.endsWith('.csv')) csvF = f;
      if (f.path.endsWith('.json')) jsonF = f;
      if (f.path.endsWith('.png')) pngF = f;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 12),
            child: Icon(
              Icons.check_box_outline_blank,
              color: Colors.white38,
              size: 20,
            ),
          ),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: pngF != null
                          ? Image.file(pngF, fit: BoxFit.cover)
                          : const Icon(Icons.image, color: Colors.white24),
                    ),
                    const SizedBox(width: 12),

                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 10,
                                color: Colors.white54,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                dateStr,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 10,
                                color: Colors.white54,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                entry.durationStr,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Icon(
                                Icons.insert_drive_file,
                                size: 10,
                                color: Colors.white54,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                sizeStr,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Delete button
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => _confirmDelete(entry),
                      tooltip: 'Delete recording',
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Badges
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (wavF != null)
                      _buildBadge(
                        'WAV',
                        Colors.purpleAccent,
                        wavF.lengthSync(),
                        file: wavF,
                      ),
                    if (csvF != null)
                      _buildBadge('CSV', Colors.green, csvF.lengthSync(), file: csvF),
                    if (jsonF != null)
                      _buildBadge(
                        'JSON',
                        Colors.orangeAccent,
                        jsonF.lengthSync(),
                        file: jsonF,
                      ),
                    if (pngF != null)
                      _buildBadge('PNG', Colors.blue, pngF.lengthSync(), file: pngF),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(_FileEntry entry) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Delete recording?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${entry.name}" and all its files?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        _deleteRecording(entry);
      }
    });
  }

  void _deleteRecording(_FileEntry entry) {
    try {
      for (final f in entry.files) {
        f.deleteSync();
        debugPrint('[saved] Deleted: ${f.path}');
      }
      _loadRecordings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${entry.name}"'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[saved] Delete error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openFile(File file) {
    debugPrint('[saved] Open file: ${file.path}');
    if (Platform.isAndroid || Platform.isIOS) {
      OpenFilex.open(file.path).then((result) {
        if (result.type != ResultType.done && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No app found to open ${file.path.split('.').last}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      });
    } else {
      // Desktop: show the file path instead of trying to open
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File: ${file.path}'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildBadge(String label, Color color, int sizeBytes, {File? file}) {
    final sizeStr = sizeBytes < 1024 * 1024
        ? '${(sizeBytes / 1024).toStringAsFixed(1)} KB'
        : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

    return GestureDetector(
      onTap: file != null ? () => _openFile(file) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insert_drive_file, size: 10, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sizeStr,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
