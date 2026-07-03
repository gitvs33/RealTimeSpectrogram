import 'package:flutter/material.dart';
import '../services/spectrogram_service.dart';

/// Shown when no live preview or recording data is available.
///
/// Displays a permission-error prompt when [SpectrogramService.connectionError]
/// is set, or a generic "Press Start Preview" placeholder otherwise.
class PreviewPlaceholder extends StatelessWidget {
  final SpectrogramService service;
  final bool isPhase;

  const PreviewPlaceholder({
    super.key,
    required this.service,
    this.isPhase = false,
  });

  @override
  Widget build(BuildContext context) {
    final error = service.connectionError;

    if (error.isNotEmpty) {
      return _buildError(error);
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
            onPressed: () => service.startLivePreview(),
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

  Widget _buildError(String error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mic_off, size: 48, color: Colors.redAccent),
          const SizedBox(height: 16),
          const Text(
            'Microphone Access Needed',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
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
              service.clearConnectionError();
              service.startLivePreview();
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
}
