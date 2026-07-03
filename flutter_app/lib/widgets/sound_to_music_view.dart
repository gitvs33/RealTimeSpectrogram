import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// SoundToMusicView
///
/// Shows saved recordings, lets user pick one, send it to a Python backend
/// server, and play back the resulting instrumental audio.
///
/// The Python server is hosted separately (see sound_to_music_server.py).
/// ──────────────────────────────────────────────────────────────────────────

class SoundToMusicView extends StatefulWidget {
  const SoundToMusicView({super.key});

  @override
  State<SoundToMusicView> createState() => _SoundToMusicViewState();
}

class _SoundToMusicViewState extends State<SoundToMusicView> {
  // ── Server config (user can customise) ──
  final TextEditingController _serverCtrl = TextEditingController(
    text: 'http://192.168.1.100:8000',
  );

  // ── State ──
  List<_RecordingEntry> _recordings = [];
  bool _loading = true;
  String? _error;
  String _statusMsg = '';
  String? _convertingStem; // which recording is currently converting
  bool _showServerConfig = false;

  String? _currentResultPath;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    super.dispose();
  }

  // ── Load saved recordings from the app's spectrogram_saves dir ──

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
          _statusMsg = 'No recordings yet. Record something first!';
        });
        return;
      }

      final entities = await saveDir.list().toList();
      final Map<String, _RecordingEntry> groups = {};

      for (final e in entities) {
        if (e is! File) continue;
        final name = e.path.split('/').last;
        String stem;

        // Match naming pattern from SpectrogramService.saveRecording
        if (name.endsWith('.wav') && !name.contains('_stft') && !name.contains('_spectrogram') && !name.contains('_instrumental')) {
          stem = name.substring(0, name.length - '.wav'.length);
        } else if (name.endsWith('_stft.csv')) {
          stem = name.substring(0, name.length - '_stft.csv'.length);
        } else if (name.endsWith('_stft.json')) {
          stem = name.substring(0, name.length - '_stft.json'.length);
        } else if (name.endsWith('_spectrogram.png')) {
          stem = name.substring(0, name.length - '_spectrogram.png'.length);
        } else {
          continue;
        }

        groups.putIfAbsent(stem, () => _RecordingEntry(name: stem));
        groups[stem]!.files.add(e);
      }

      final entries = groups.values.toList();
      entries.sort((a, b) => b.latestDate.compareTo(a.latestDate));

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

  // ── Convert selected recording ──

  Future<void> _convert(String stem, File wavFile) async {
    final serverUrl = _serverCtrl.text.trim();
    if (serverUrl.isEmpty) {
      _showSnack('Enter the server URL first');
      return;
    }

    setState(() {
      _convertingStem = stem;
      _statusMsg = '📤 Uploading $stem to server…';
      _currentResultPath = null;
    });

    try {
      // Build full URL
      final uri = Uri.parse('$serverUrl/convert');
      if (!uri.hasScheme) {
        _showError('Invalid URL. Use http://ip:port');
        return;
      }

      // 1) Upload WAV to server
      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        await http.MultipartFile.fromPath('file', wavFile.path),
      );

      setState(() => _statusMsg = '⏳ Processing on server…');

      final streamedResp = await request.send().timeout(
        const Duration(seconds: 120),
      );

      if (streamedResp.statusCode != 200) {
        final body = await streamedResp.stream.bytesToString();
        _showError('Server error (${streamedResp.statusCode}): $body');
        return;
      }

      // 2) Read response bytes (instrumental WAV)
      final bytes = await streamedResp.stream.toBytes();
      if (bytes.lengthInBytes < 1024) {
        _showError('Server returned empty result');
        return;
      }

      // 3) Save result locally
      final dir = await getApplicationDocumentsDirectory();
      final resultDir = Directory('${dir.path}/spectrogram_saves');
      final resultPath = '${resultDir.path}/${stem}_instrumental.wav';
      await File(resultPath).writeAsBytes(bytes.toList());

      setState(() {
        _currentResultPath = resultPath;
        _statusMsg = '✅ Done! ${(bytes.lengthInBytes / 1024).toStringAsFixed(0)} KB received';
        _convertingStem = null;
      });

      // Extract event count from headers (if server sends it)
      final eventsHeader = streamedResp.headers['x-events-count'];
      final notesHeader = streamedResp.headers['x-notes-count'];
      if (eventsHeader != null) {
        _statusMsg += '\n   Events: $eventsHeader  |  Notes: ${notesHeader ?? "?"}';
        setState(() {});
      }

      _showSnack('🎵 Conversion complete! Tap play to listen.');
    } catch (e) {
      _showError('Connection failed: $e');
      setState(() => _convertingStem = null);
    }
  }

  // ── Play result via open_filex ──

  Future<void> _playResult(String path) async {
    setState(() => _currentResultPath = path);
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done && mounted) {
      _showSnack('No app found to play WAV. File saved at: $path');
    }
  }

  // ── UI helpers ──

  void _showError(String msg) {
    setState(() {
      _error = msg;
      _statusMsg = '❌ $msg';
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1E88E5),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  int _totalSize() {
    int total = 0;
    for (var r in _recordings) {
      for (var f in r.files) {
        total += f.lengthSync();
      }
    }
    return total;
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Header: server config toggle ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF0D1117),
          child: Row(
            children: [
              const Icon(Icons.music_note, color: Color(0xFF42A5F5), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Sound to Music',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() => _showServerConfig = !_showServerConfig);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.dns,
                        size: 14,
                        color: _showServerConfig ? Colors.white : Colors.white54,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Server',
                        style: TextStyle(
                          fontSize: 12,
                          color: _showServerConfig ? Colors.white : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Server config (collapsible) ──
        if (_showServerConfig)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF161B22),
              border: Border(
                bottom: BorderSide(color: Color(0xFF30363D)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Python Server URL',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1117),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF30363D)),
                        ),
                        child: TextField(
                          controller: _serverCtrl,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _loadRecordings,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E88E5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.refresh,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Run: python3 sound_to_music_server.py on your server',
                  style: TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ],
            ),
          ),

        // ── Status / conversion progress ──
        if (_statusMsg.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0D1117),
              border: Border(
                bottom: BorderSide(color: Color(0xFF30363D)),
              ),
            ),
            child: Row(
              children: [
                if (_convertingStem != null)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF42A5F5),
                    ),
                  )
                else
                  const Icon(Icons.check_circle, size: 14, color: Colors.greenAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _statusMsg,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                if (_currentResultPath != null)
                  GestureDetector(
                    onTap: () => _playResult(_currentResultPath!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E88E5).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF1E88E5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow, size: 16, color: Color(0xFF1E88E5)),
                          SizedBox(width: 4),
                          Text('Open', style: TextStyle(fontSize: 12, color: Color(0xFF1E88E5))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

        // ── Main content ──
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
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
                onPressed: () {
                  setState(() => _error = null);
                  _loadRecordings();
                },
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
                label: const Text('Retry', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      );
    }

    if (_recordings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_note, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            const Text(
              'No Recordings Yet',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Go to Spectrogram tab, record a sound, and save it.\nThen come here to turn it into music!',
              style: TextStyle(color: Colors.white24, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadRecordings,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E88E5).withOpacity(0.2),
                foregroundColor: const Color(0xFF42A5F5),
                side: const BorderSide(color: Color(0xFF42A5F5), width: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Recording count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${_recordings.length} recordings',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const Spacer(),
              Text(
                'Total: ${_formatBytes(_totalSize())}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recordings.length,
            itemBuilder: (context, index) => _buildCard(_recordings[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(_RecordingEntry entry) {
    final hasWav = entry.wavFile != null;
    final hasResult = entry.instrumentalFile != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + date
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.audiotrack,
                  color: Color(0xFF42A5F5),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(entry.latestDate),
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // File badges
          Row(
            children: [
              if (hasWav)
                _badge('WAV', Colors.purpleAccent, entry.wavFile!.lengthSync()),
              if (entry.jsonFile != null)
                _badge('JSON', Colors.orangeAccent, entry.jsonFile!.lengthSync()),
              if (entry.csvFile != null)
                _badge('CSV', Colors.green, entry.csvFile!.lengthSync()),
              if (hasResult)
                _badge('🎵 RESULT', Colors.amber, entry.instrumentalFile!.lengthSync()),
            ],
          ),

          const SizedBox(height: 12),

          // Convert button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_convertingStem != null || !hasWav)
                  ? null
                  : () => _convert(entry.name, entry.wavFile!),
              icon: _convertingStem == entry.name
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                _convertingStem == entry.name ? 'Converting…' : 'Convert to Song',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E88E5),
                disabledBackgroundColor: const Color(0xFF1E88E5).withOpacity(0.3),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          // Play result button (if exists)
          if (hasResult) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _currentResultPath = entry.instrumentalFile!.path;
                    _statusMsg = '🎵 Playing: ${entry.name}';
                  });
                  _playResult(entry.instrumentalFile!.path);
                },
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text(
                  'Play Result',
                  style: TextStyle(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.greenAccent,
                  side: const BorderSide(color: Colors.greenAccent, width: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(String label, Color color, int sizeBytes) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              _formatBytes(sizeBytes),
              style: TextStyle(color: color.withOpacity(0.7), fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  // ── Formatting helpers ──

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} $h:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }
}

// ─── Data class ───────────────────────────────────────────────────────────

class _RecordingEntry {
  final String name;
  final List<File> files;

  _RecordingEntry({required this.name, List<File>? files})
      : files = files ?? [];

  File? get wavFile {
    // Get the raw WAV (not instrumental)
    for (var f in files) {
      final name = f.path.split('/').last;
      if (name.endsWith('.wav') &&
          !name.contains('_instrumental') &&
          !name.contains('_stft')) {
        return f;
      }
    }
    return null;
  }

  File? get instrumentalFile {
    for (var f in files) {
      if (f.path.endsWith('_instrumental.wav')) return f;
    }
    return null;
  }

  File? get jsonFile {
    for (var f in files) {
      if (f.path.endsWith('_stft.json')) return f;
    }
    return null;
  }

  File? get csvFile {
    for (var f in files) {
      if (f.path.endsWith('_stft.csv')) return f;
    }
    return null;
  }

  DateTime get latestDate {
    DateTime latest = DateTime(2000);
    for (var f in files) {
      final m = f.lastModifiedSync();
      if (m.isAfter(latest)) latest = m;
    }
    return latest;
  }
}
