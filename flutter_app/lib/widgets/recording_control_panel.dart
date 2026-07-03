import 'package:flutter/material.dart';
import '../services/spectrogram_service.dart';

/// Record / stop / save controls and live metrics display.
///
/// Owns its own [TextEditingController] for the filename input.
/// Delegates recording state and save logic to [SpectrogramService].
///
/// Includes the status bar at the bottom showing REC state, live frame
/// count, and preview status.
class RecordingControlPanel extends StatefulWidget {
  final SpectrogramService service;

  const RecordingControlPanel({super.key, required this.service});

  @override
  State<RecordingControlPanel> createState() => _RecordingControlPanelState();
}

class _RecordingControlPanelState extends State<RecordingControlPanel> {
  final TextEditingController _filenameCtrl = TextEditingController(text: '');

  @override
  void dispose() {
    _filenameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = widget.service;
    return Container(
      color: const Color(0xFF0D1117),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Buttons row ──
          _buildButtonsRow(svc),

          // ── Frame counter & duration ──
          _buildMetrics(svc),

          const SizedBox(height: 16),

          // ── Status bar ──
          _buildStatusBar(svc),
        ],
      ),
    );
  }

  Widget _buildButtonsRow(SpectrogramService svc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          // Record button
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

          // Stop button
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

          // Filename input
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
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Save button
          Container(
            height: 40,
            margin: const EdgeInsets.only(bottom: 16),
            child: ElevatedButton.icon(
              onPressed:
                  (!svc.isSaving && svc.recordedFrameCount > 0)
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
    );
  }

  Widget _buildMetrics(SpectrogramService svc) {
    return Padding(
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
          Container(
            width: 1,
            height: 30,
            color: const Color(0xFF30363D),
          ),
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
    );
  }

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
            svc.livePreviewActive
                ? 'Live preview active'
                : 'Live preview inactive',
            style: TextStyle(
              color:
                  svc.livePreviewActive ? Colors.greenAccent : Colors.white38,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
