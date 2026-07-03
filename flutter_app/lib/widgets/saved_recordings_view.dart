import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/recording_repository.dart';
import '../services/spectrogram_service.dart';

/// Lists saved recordings with metadata, thumbnails, and delete/open actions.
///
/// Uses [RecordingRepository] for directory scanning and file grouping
/// so it shares data logic with [SoundToMusicView].
class SavedRecordingsView extends StatefulWidget {
  const SavedRecordingsView({super.key});

  @override
  State<SavedRecordingsView> createState() => _SavedRecordingsViewState();
}

class _SavedRecordingsViewState extends State<SavedRecordingsView> {
  RecordingRepository? _repo;
  List<RecordingGroup> _recordings = [];
  bool _loading = true;
  String? _error;
  String _lastSaveMsg = '';

  @override
  void initState() {
    super.initState();
    _initRepo();
  }

  Future<void> _initRepo() async {
    final dir = await getApplicationDocumentsDirectory();
    _repo = RecordingRepository(
      directoryPath: '${dir.path}/spectrogram_saves',
    );
    _loadRecordings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      context.read<SpectrogramService>().addListener(_onServiceChange);
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
    if (_repo == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final entries = await _repo!.list();
      if (!mounted) return;
      setState(() {
        _recordings = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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
                _error!,
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

    return Column(
      children: [
        // ── Search / sort / refresh bar ──
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
                      suffixIcon: Icon(Icons.search, size: 16, color: Colors.white54),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: const Row(
                  children: [
                    Text('Sort: Newest', style: TextStyle(color: Colors.white, fontSize: 12)),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_drop_down, color: Colors.white54, size: 16),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _loadRecordings,
                child: const Icon(Icons.refresh, color: Colors.white54, size: 20),
              ),
            ],
          ),
        ),

        // ── Recording list ──
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recordings.length,
            itemBuilder: (context, index) =>
                _buildCard(context, _recordings[index]),
          ),
        ),

        // ── Footer ──
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
                'Total size: ${_totalSize()}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _totalSize() {
    int totalBytes = 0;
    for (final r in _recordings) {
      for (final f in r.files) {
        totalBytes += f.lengthSync();
      }
    }
    return formatBytes(totalBytes);
  }

  Widget _buildCard(BuildContext context, RecordingGroup entry) {
    int totalBytes = 0;
    for (final f in entry.files) totalBytes += f.lengthSync();

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
          // Checkbox placeholder
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
                      child: entry.pngFile != null
                          ? Image.file(entry.pngFile!, fit: BoxFit.cover)
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
                              const Icon(Icons.calendar_today, size: 10, color: Colors.white54),
                              const SizedBox(width: 4),
                              Text(
                                formatDateTime(entry.lastModified),
                                style: const TextStyle(color: Colors.white54, fontSize: 10),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.insert_drive_file, size: 10, color: Colors.white54),
                              const SizedBox(width: 4),
                              Text(
                                formatBytes(totalBytes),
                                style: const TextStyle(color: Colors.white54, fontSize: 10),
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

                // File type badges
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (entry.wavFile != null)
                      _buildBadge(
                        'WAV',
                        Colors.purpleAccent,
                        entry.wavFile!.lengthSync(),
                        file: entry.wavFile,
                      ),
                    if (entry.csvFile != null)
                      _buildBadge('CSV', Colors.green, entry.csvFile!.lengthSync(), file: entry.csvFile),
                    if (entry.jsonFile != null)
                      _buildBadge(
                        'JSON',
                        Colors.orangeAccent,
                        entry.jsonFile!.lengthSync(),
                        file: entry.jsonFile,
                      ),
                    if (entry.pngFile != null)
                      _buildBadge('PNG', Colors.blue, entry.pngFile!.lengthSync(), file: entry.pngFile),
                    if (entry.instrumentalFile != null)
                      _buildBadge(
                        'RESULT',
                        Colors.amber,
                        entry.instrumentalFile!.lengthSync(),
                        file: entry.instrumentalFile,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(RecordingGroup entry) {
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
      if (confirmed == true) _deleteRecording(entry);
    });
  }

  Future<void> _deleteRecording(RecordingGroup entry) async {
    try {
      await _repo?.delete(entry);
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
              content: Text(
                'No app found to open ${file.path.split('.').last}',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File: ${file.path}'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildBadge(String label, Color color, int sizeBytes, {File? file}) {
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
            formatBytes(sizeBytes),
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
