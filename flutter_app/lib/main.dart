import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/spectrogram_service.dart';
import 'widgets/spectrogram_painter.dart';
import 'widgets/data_table_view.dart';
import 'widgets/saved_recordings_view.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => SpectrogramService(
        mode: SpectrogramService.detectDefaultMode(),
      ),
      child: const SpectrogramApp(),
    ),
  );
}

class SpectrogramApp extends StatelessWidget {
  const SpectrogramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Real-Time Spectrogram',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: Colors.teal,
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
  final TextEditingController _hostCtrl = TextEditingController(text: 'localhost');
  final TextEditingController _portCtrl = TextEditingController(text: '8765');
  final TextEditingController _filenameCtrl = TextEditingController(text: 'recording');
  int _selectedTab = 0; // 0=spectrogram, 1=phase, 2=data, 3=saved

  @override
  void initState() {
    super.initState();
    // Auto-connect on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connect();
    });
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _filenameCtrl.dispose();
    super.dispose();
  }

  void _connect() {
    final svc = context.read<SpectrogramService>();
    if (svc.mode == AudioMode.local) {
      // Local mode doesn't need a WebSocket connection.
      // The mic starts on startLivePreview / startRecording.
      return;
    }
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 8765;
    svc.connect(host, port);
    // Start listening after connecting
    Future.delayed(const Duration(milliseconds: 100), () {
      svc.startListening();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Real-Time Spectrogram',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        centerTitle: false,
        actions: [
          Consumer<SpectrogramService>(
            builder: (context, svc, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Connection indicator
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: svc.isConnected
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          boxShadow: [
                            BoxShadow(
                              color: (svc.isConnected
                                      ? Colors.greenAccent
                                      : Colors.redAccent)
                                  .withAlpha(100),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        svc.mode == AudioMode.local
                            ? 'Device Mic'
                            : (svc.isConnected
                                ? 'Connected'
                                : 'Disconnected'),
                        style: TextStyle(
                          fontSize: 12,
                          color: svc.isConnected
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                // Settings (network mode only)
                if (svc.mode == AudioMode.network)
                  IconButton(
                    icon: const Icon(Icons.settings, size: 20),
                    onPressed: _showSettings,
                  ),
              ],
            ),
          ),
        ],
      ),
      body: Consumer<SpectrogramService>(
        builder: (context, svc, _) {
          return Column(
            children: [
              // ── Tab bar ──
              Container(
                color: const Color(0xFF161B22),
                child: Row(
                  children: [
                    _tabButton('Spectrogram', 0),
                    _tabButton('Phase View', 1),
                    _tabButton('Numerical Data', 2),
                    _tabButton('Saved', 3),
                  ],
                ),
              ),

              // ── Main visualization ──
              Expanded(
                child: _selectedTab == 0
                    ? _buildSpectrogramView(svc)
                    : _selectedTab == 1
                        ? _buildPhaseView(svc)
                        : _selectedTab == 2
                            ? _buildDataView(svc)
                            : _buildSavedRecordingsView(),
              ),

              // ── Control panel ──
              _buildControlPanel(svc),

              // ── Status bar ──
              _buildStatusBar(svc),
            ],
          );
        },
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? Colors.teal : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? Colors.tealAccent : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }

  // ── Spectrogram ──
  Widget _buildSpectrogramView(SpectrogramService svc) {
    if (!svc.livePreviewActive) {
      return _buildPreviewPrompt(svc, isPhase: false);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: Row(
            children: [
              Icon(Icons.graphic_eq, size: 14, color: Colors.tealAccent),
              const SizedBox(width: 4),
              const Text('Frequency Spectrogram (magnitude, dB scale)',
                  style: TextStyle(fontSize: 11, color: Colors.white54)),
              const Spacer(),
              // Recording badge / Stop Preview
              if (svc.isRecording)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withAlpha(40),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.redAccent, width: 0.5),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fiber_manual_record, size: 8, color: Colors.redAccent),
                      SizedBox(width: 4),
                      Text('RECORDING',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.redAccent)),
                    ],
                  ),
                )
              else
                GestureDetector(
                  onTap: () => svc.stopLivePreview(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange, width: 0.5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.stop, size: 10, color: Colors.orange),
                        SizedBox(width: 3),
                        Text('Stop Preview',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.orange)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 8, 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: SpectrogramPainter(frames: svc.liveFrames),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Phase View ──
  Widget _buildPhaseView(SpectrogramService svc) {
    if (!svc.livePreviewActive) {
      return _buildPreviewPrompt(svc, isPhase: true);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: Row(
            children: [
              Icon(Icons.loop, size: 14, color: Colors.purpleAccent),
              const SizedBox(width: 4),
              const Text('Phase Angle (hue = phase, cyclic colormap)',
                  style: TextStyle(fontSize: 11, color: Colors.white54)),
              const Spacer(),
              // Stop Preview button
              GestureDetector(
                onTap: () => svc.stopLivePreview(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange, width: 0.5),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stop, size: 10, color: Colors.orange),
                      SizedBox(width: 3),
                      Text('Stop Preview',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.orange)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 8, 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: PhasePainter(frames: svc.liveFrames),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Data Table ──
  Widget _buildDataView(SpectrogramService svc) {
    final displayFrames = svc.recordedFrames.isNotEmpty
        ? svc.recordedFrames
        : svc.liveFrames;
    if (displayFrames.isEmpty) {
      return const Center(
        child: Text('No data. Start recording to see numerical values.',
            style: TextStyle(color: Colors.white38)),
      );
    }
    return StftDataTableView(frames: displayFrames);
  }

  // ── Saved Recordings ──
  Widget _buildSavedRecordingsView() {
    return const SavedRecordingsView();
  }

  // ── Controls ──
  Widget _buildControlPanel(SpectrogramService svc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(top: BorderSide(color: Color(0xFF30363D))),
      ),
      child: Row(
        children: [
          // Record button
          _controlButton(
            icon: svc.isRecording ? Icons.stop_circle_outlined : Icons.fiber_manual_record,
            label: svc.isRecording ? 'Stop' : 'Record',
            color: svc.isRecording ? Colors.orange : Colors.redAccent,
            onPressed: () {
              if (svc.isRecording) {
                svc.stopRecording();
              } else {
                svc.startRecording();
              }
            },
          ),
          const SizedBox(width: 8),
          // Save button
          _controlButton(
            icon: Icons.save_alt,
            label: 'Save',
            color: Colors.tealAccent,
            onPressed: svc.recordedFrameCount > 0
                ? () async {
                    final name = _filenameCtrl.text.trim().isEmpty
                        ? 'recording'
                        : _filenameCtrl.text.trim();
                    await svc.saveRecording(name);
                  }
                : null,
          ),
          const SizedBox(width: 8),
          // Filename field
          SizedBox(
            width: 140,
            child: TextField(
              controller: _filenameCtrl,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'filename',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const Spacer(),
          // Frame count
          Text(
            '${svc.recordedFrameCount} frames  ·  ${svc.recordingDuration.toStringAsFixed(1)}s',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ── Status Bar ──
  Widget _buildStatusBar(SpectrogramService svc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        border: Border(top: BorderSide(color: Color(0xFF30363D))),
      ),
      child: Row(
        children: [
          // Recording indicator
          if (svc.isRecording) ...[
            Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(width: 4),
            const Text('REC', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
          ],
          // Live frame rate
          Text(
            'Live: ${svc.liveFrames.length} frames',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          if (svc.connectionError.isNotEmpty) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                svc.connectionError,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (svc.saveMessage.isNotEmpty) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                svc.saveMessage,
                style: const TextStyle(color: Colors.greenAccent, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Preview prompt (shown when preview is off) ──
  Widget _buildPreviewPrompt(SpectrogramService svc, {required bool isPhase}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPhase ? Icons.loop : Icons.graphic_eq,
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
              backgroundColor: Colors.tealAccent.withAlpha(30),
              foregroundColor: Colors.tealAccent,
              side: const BorderSide(color: Colors.tealAccent, width: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helper: control button ──
  Widget _controlButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return Opacity(
      opacity: onPressed != null ? 1.0 : 0.4,
      child: Material(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Settings dialog ──
  void _showSettings() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Connection Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _hostCtrl,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText: 'localhost',
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portCtrl,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '8765',
              ),
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _connect();
            },
            child: const Text('Reconnect'),
          ),
        ],
      ),
    );
  }
}
