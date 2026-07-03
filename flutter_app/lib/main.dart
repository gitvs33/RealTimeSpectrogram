import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/spectrogram_service.dart';
import 'widgets/data_table_view.dart';
import 'widgets/preview_placeholder.dart';
import 'widgets/recording_control_panel.dart';
import 'widgets/saved_recordings_view.dart';
import 'widgets/sound_to_music_view.dart';
import 'widgets/spectrogram_film_strip.dart';
import 'widgets/spectrogram_painter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF42A5F5),
          surface: Color(0xFF161B22),
        ),
      ),
      home: const SpectrogramHome(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SpectrogramHome — main screen
// ═══════════════════════════════════════════════════════════════════════════

class SpectrogramHome extends StatefulWidget {
  const SpectrogramHome({super.key});

  @override
  State<SpectrogramHome> createState() => _SpectrogramHomeState();
}

class _SpectrogramHomeState extends State<SpectrogramHome> {
  int _selectedTab = 0; // 0=spectrogram, 1=phase, 2=data, 3=saved
  bool _showSoundToMusic = false;

  double _spectrogramScrollOffset = 0;
  double _phaseScrollOffset = 0;

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
                    if (_selectedTab == 0) RecordingControlPanel(service: svc),
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
      return PreviewPlaceholder(service: svc, isPhase: false);
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

          return SpectrogramFilmStrip(
            painter: SpectrogramPainter(
              frames: displayFrames,
              scrollOffset: _spectrogramScrollOffset,
              frameWidth: frameWidth,
            ),
            viewportWidth: viewportW,
            viewportHeight: constraints.maxHeight,
            onHorizontalDrag: (dx) {
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
      return PreviewPlaceholder(service: svc, isPhase: true);
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

          return SpectrogramFilmStrip(
            painter: PhasePainter(
              frames: displayFrames,
              scrollOffset: _phaseScrollOffset,
              frameWidth: frameWidth,
            ),
            viewportWidth: viewportW,
            viewportHeight: constraints.maxHeight,
            onHorizontalDrag: (dx) {
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
