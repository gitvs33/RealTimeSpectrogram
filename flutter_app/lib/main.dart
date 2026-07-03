import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/spectrogram_service.dart';
import 'widgets/spectrogram_painter.dart';
import 'widgets/data_table_view.dart';
import 'widgets/saved_recordings_view.dart';
import 'widgets/sound_to_music_view.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => SpectrogramService(),
      child: const SpectrogramApp(),
    ),
  );
}

class SpectrogramApp extends StatelessWidget {
  const SpectrogramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Once',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: const Color(0xFF1E88E5),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D1117),
      ),
      home: const SpectrogramHome(),
    );
  }
}

class SpectrogramHome extends StatefulWidget {
  const SpectrogramHome({super.key});

  @override
  State<SpectrogramHome> createState() => _SpectrogramHomeState();
}

class _SpectrogramHomeState extends State<SpectrogramHome> {
  final TextEditingController _filenameCtrl = TextEditingController(text: '');
  int _selectedTab = 0; // 0=spectrogram, 1=phase, 2=data, 3=saved
  bool _showSoundToMusic = false;

  double _spectrogramScrollOffset = 0;
  double _phaseScrollOffset = 0;

  @override
  void dispose() {
    _filenameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text(
          'Once',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        centerTitle: false,
        actions: [
          Consumer<SpectrogramService>(
            builder: (context, svc, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.greenAccent,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Device Mic',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white, size: 20),
            onPressed: () {},
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF161B22),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Once',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.white,
                  ),
                ),
              ),
              const Divider(color: Color(0xFF30363D)),
              _DrawerItem(
                icon: Icons.bar_chart,
                label: 'Spectrogram',
                selected: !_showSoundToMusic,
                onTap: () {
                  setState(() => _showSoundToMusic = false);
                  Navigator.of(context).pop();
                },
              ),
              _DrawerItem(
                icon: Icons.music_note,
                label: 'Sound to Music',
                selected: _showSoundToMusic,
                onTap: () {
                  setState(() => _showSoundToMusic = true);
                  Navigator.of(context).pop();
                },
              ),
              const Spacer(),
              const Divider(color: Color(0xFF30363D)),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Convert recorded sounds into music\nusing a Python backend pipeline.',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _showSoundToMusic
          ? const SoundToMusicView()
          : Consumer<SpectrogramService>(
              builder: (context, svc, _) {
                return Column(
                  children: [
                    // ── Tab bar ──
                    Container(
                      color: const Color(0xFF0D1117),
                      child: Row(
                        children: [
                          _tabButton('Spectrogram', Icons.bar_chart, 0),
                          _tabButton('Phase View', Icons.data_usage, 1),
                          _tabButton('Numerical Data', Icons.list, 2),
                          _tabButton('Saved', Icons.folder, 3),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFF30363D)),

                    // ── Main content ──
                    Expanded(
                      child: _selectedTab == 0
                          ? _buildSpectrogramView(svc)
                          : _selectedTab == 1
                              ? _buildPhaseView(svc)
                              : _selectedTab == 2
                                  ? _buildDataView(svc)
                                  : _buildSavedRecordingsView(),
                    ),

                    // ── Control panel (Spectrogram tab only) ──
                    if (_selectedTab == 0) _buildControlPanel(svc),
                  ],
                );
              },
            ),
    );
  }

  // ──────── Tab buttons ────────────────────────────────────────────────

  Widget _tabButton(String label, IconData icon, int index) {
    final isSelected = _selectedTab == index;
    final color = isSelected ? const Color(0xFF42A5F5) : Colors.white54;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? const Color(0xFF42A5F5) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────── Spectrogram view ─────────────────────────────────────────

  Widget _buildSpectrogramView(SpectrogramService svc) {
    if (!svc.livePreviewActive && svc.recordedFrames.isEmpty) {
      _spectrogramScrollOffset = 0;
      return _buildPreviewPrompt(svc, isPhase: false);
    }

    const frameWidth = 3.0;
    final displayFrames = svc.recordedFrames.isNotEmpty
        ? svc.recordedFrames
        : svc.liveFrames;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 16, 8, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportW = constraints.maxWidth;
          final totalW = max(viewportW, displayFrames.length * frameWidth);
          final maxScroll = max(0.0, totalW - viewportW);

          if (svc.isRecording || svc.livePreviewActive) {
            _spectrogramScrollOffset = maxScroll;
          } else {
            _spectrogramScrollOffset =
                _spectrogramScrollOffset.clamp(0.0, maxScroll);
          }

          return _buildFilmStrip(
            painter: SpectrogramPainter(
              frames: displayFrames,
              scrollOffset: _spectrogramScrollOffset,
              frameWidth: frameWidth,
            ),
            width: viewportW,
            height: constraints.maxHeight,
            onDrag: (dx) {
              if (!svc.isRecording && !svc.livePreviewActive) {
                setState(() {
                  _spectrogramScrollOffset =
                      (_spectrogramScrollOffset - dx).clamp(0.0, maxScroll);
                });
              }
            },
          );
        },
      ),
    );
  }

  // ──────── Phase view ────────────────────────────────────────────────

  Widget _buildPhaseView(SpectrogramService svc) {
    if (!svc.livePreviewActive && svc.recordedFrames.isEmpty) {
      _phaseScrollOffset = 0;
      return _buildPreviewPrompt(svc, isPhase: true);
    }

    const frameWidth = 3.0;
    final displayFrames = svc.recordedFrames.isNotEmpty
        ? svc.recordedFrames
        : svc.liveFrames;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 16, 8, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportW = constraints.maxWidth;
          final totalW = max(viewportW, displayFrames.length * frameWidth);
          final maxScroll = max(0.0, totalW - viewportW);

          if (svc.isRecording || svc.livePreviewActive) {
            _phaseScrollOffset = maxScroll;
          } else {
            _phaseScrollOffset =
                _phaseScrollOffset.clamp(0.0, maxScroll);
          }

          return _buildFilmStrip(
            painter: PhasePainter(
              frames: displayFrames,
              scrollOffset: _phaseScrollOffset,
              frameWidth: frameWidth,
            ),
            width: viewportW,
            height: constraints.maxHeight,
            onDrag: (dx) {
              if (!svc.isRecording && !svc.livePreviewActive) {
                setState(() {
                  _phaseScrollOffset =
                      (_phaseScrollOffset - dx).clamp(0.0, maxScroll);
                });
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildFilmStrip({
    required CustomPainter painter,
    required double width,
    required double height,
    required void Function(double dx) onDrag,
  }) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      child: ClipRect(
        child: CustomPaint(
          painter: painter,
          size: Size(width, height),
        ),
      ),
    );
  }

  // ──────── Data view ─────────────────────────────────────────────────

  Widget _buildDataView(SpectrogramService svc) {
    final displayFrames = svc.recordedFrames.isNotEmpty
        ? svc.recordedFrames
        : svc.liveFrames;
    if (displayFrames.isEmpty) {
      return const Center(
        child: Text(
          'No data. Start recording to see numerical values.',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }
    return StftDataTableView(frames: displayFrames);
  }

  // ──────── Saved recordings view ─────────────────────────────────────

  Widget _buildSavedRecordingsView() {
    return const SavedRecordingsView();
  }

  // ──────── Control panel ─────────────────────────────────────────────

  Widget _buildControlPanel(SpectrogramService svc) {
    return Container(
      color: const Color(0xFF0D1117),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Buttons row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    if (!svc.isRecording) svc.startRecording();
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF30363D)),
                        ),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Record',
                        style: TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () {
                    if (svc.isRecording) svc.stopRecording();
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF30363D)),
                        ),
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.grey,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Stop',
                        style: TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  width: 140,
                  height: 40,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: TextField(
                    controller: _filenameCtrl,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Enter filename...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 40,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ElevatedButton.icon(
                    onPressed: (!svc.isSaving && svc.recordedFrameCount > 0)
                        ? () async {
                            final name = _filenameCtrl.text.trim().isEmpty
                                ? 'recording'
                                : _filenameCtrl.text.trim();
                            _filenameCtrl.clear();
                            await svc.saveRecording(name);
                          }
                        : null,
                    icon: svc.isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save, size: 16, color: Colors.white),
                    label: Text(
                      svc.isSaving ? 'Saving…' : 'Save',
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E88E5),
                      disabledBackgroundColor:
                          const Color(0xFF1E88E5).withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Frames and duration
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    const Text(
                      'Frames',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${svc.recordedFrames.isNotEmpty ? svc.recordedFrameCount : svc.liveFrames.length}',
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(width: 1, height: 30, color: const Color(0xFF30363D)),
                Column(
                  children: [
                    const Text(
                      'Duration',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(svc.recordedFrames.isNotEmpty ? svc.recordingDuration : 0.0).toStringAsFixed(2)} s',
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildStatusBar(svc),
        ],
      ),
    );
  }

  // ──────── Status bar ────────────────────────────────────────────────

  Widget _buildStatusBar(SpectrogramService svc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        border: Border(top: BorderSide(color: Color(0xFF30363D))),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: svc.isRecording ? Colors.redAccent : Colors.grey,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'REC ${svc.isRecording ? svc.formattedDuration : "00:00:00"}',
            style: TextStyle(
              color: svc.isRecording ? Colors.redAccent : Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            'Live Frames: ${svc.liveFrames.length}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const Spacer(),
          Text(
            svc.livePreviewActive ? 'Live preview active' : 'Live preview inactive',
            style: TextStyle(
              color: svc.livePreviewActive ? Colors.greenAccent : Colors.white38,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ──────── Preview prompt ───────────────────────────────────────────

  Widget _buildPreviewPrompt(SpectrogramService svc, {required bool isPhase}) {
    // Show permission error if one exists
    final error = svc.connectionError;
    if (error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic_off, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text(
              'Microphone Access Needed',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(fontSize: 12, color: Colors.white38),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                svc.clearConnectionError();
                svc.startLivePreview();
              },
              icon: const Icon(Icons.mic, size: 20),
              label: const Text('Grant Permission & Start'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withOpacity(0.2),
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent, width: 0.5),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPhase ? Icons.data_usage : Icons.bar_chart,
            size: 48,
            color: Colors.white24,
          ),
          const SizedBox(height: 16),
          Text(
            isPhase ? 'Phase View' : 'Spectrogram',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Press Start Preview to see live audio',
            style: TextStyle(fontSize: 12, color: Colors.white24),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => svc.startLivePreview(),
            icon: const Icon(Icons.play_circle_outline, size: 20),
            label: const Text('Start Preview'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF42A5F5).withOpacity(0.2),
              foregroundColor: const Color(0xFF42A5F5),
              side: const BorderSide(color: Color(0xFF42A5F5), width: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────── Drawer item widget ──────────────────────────────────────────────

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF42A5F5) : Colors.white54;
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          fontSize: 14,
        ),
      ),
      onTap: onTap,
      selected: selected,
      selectedTileColor: const Color(0xFF1E88E5).withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
