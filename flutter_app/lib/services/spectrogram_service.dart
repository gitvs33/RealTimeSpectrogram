import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/audio_frame.dart';
import 'audio_capture.dart';
import 'recording_persistence.dart';
import 'stft_processor.dart';

/// Orchestrator for the real-time spectrogram pipeline.
///
/// Owns the capture → STFT → display/save pipeline and exposes a
/// [ChangeNotifier] interface for the UI. Delegates to three lean modules:
///
/// | Module | Responsibility |
/// |--------|----------------|
/// | [AudioCapture] | Mic lifecycle, raw PCM → Float64List stream |
/// | [StftProcessor] | Windowing + FFT → [AudioFrame] objects |
/// | [RecordingPersistence] | WAV / CSV / JSON / PNG file writing |
///
/// The service itself handles UI state flags, frame routing (live vs recorded),
/// and error/save messages.
class SpectrogramService extends ChangeNotifier {
  // ── Component modules ──
  final AudioCapture _capture = AudioCapture();
  final StftProcessor _processor = StftProcessor(
    fftSize: 1024,
    hopLength: 512,
    sampleRate: 44100,
  );
  RecordingPersistence? _persistence;

  StreamSubscription<Float64List>? _captureSub;

  // ── UI state ──
  bool _livePreviewActive = false;
  bool _isRecording = false;
  bool _isSaving = false;

  final List<AudioFrame> _liveFrames = [];
  final List<AudioFrame> _recordedFrames = [];

  String _connectionError = '';
  String _saveMessage = '';

  static const int maxLiveFrames = 300;

  // ════════════════════════════════════════════════════════════
  //  Getters (UI-facing)
  // ════════════════════════════════════════════════════════════

  bool get livePreviewActive => _livePreviewActive;
  bool get isRecording => _isRecording;
  bool get isSaving => _isSaving;
  bool get isConnected => true; // local mode only; no network state

  List<AudioFrame> get liveFrames => _liveFrames;
  List<AudioFrame> get recordedFrames => _recordedFrames;
  int get recordedFrameCount => _recordedFrames.length;
  double get recordingDuration =>
      _recordedFrames.isEmpty ? 0.0 : _recordedFrames.last.time;

  String get formattedDuration {
    final seconds = recordingDuration.floor();
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String get connectionError => _connectionError;
  String get saveMessage => _saveMessage;

  void clearConnectionError() {
    _connectionError = '';
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════
  //  Live preview
  // ════════════════════════════════════════════════════════════

  void startLivePreview() {
    _liveFrames.clear();
    _livePreviewActive = true;
    _processor.reset();
    _ensureCapture();
    notifyListeners();
  }

  void stopLivePreview() {
    _livePreviewActive = false;
    _liveFrames.clear();
    _stopCapture();
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════
  //  Recording
  // ════════════════════════════════════════════════════════════

  void startRecording() {
    _recordedFrames.clear();
    _isRecording = true;
    _processor.reset();
    _capture.startRecording();
    _ensureCapture();
    notifyListeners();
  }

  void stopRecording() {
    _isRecording = false;
    _capture.stopRecording();
    if (!_livePreviewActive) _stopCapture();
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════
  //  Save
  // ════════════════════════════════════════════════════════════

  Future<void> saveRecording(String filename) async {
    if (_recordedFrames.isEmpty) return;

    _isSaving = true;
    _saveMessage = '';
    notifyListeners();

    try {
      // Resolve persistence lazily so it works on first save even before
      // the documents directory is known.
      _persistence ??= await _createPersistence();

      final result = await _persistence!.save(
        filename: filename,
        frames: _recordedFrames,
        rawAudio: _capture.getRecordedAudio(),
      );

      _saveMessage = 'Saved to ${result.wavPath}';
      debugPrint('[save] Files written');
    } catch (e) {
      _connectionError = 'Save failed: $e';
      debugPrint('[save] Error: $e');
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<RecordingPersistence> _createPersistence() async {
    final dir = await getApplicationDocumentsDirectory();
    return RecordingPersistence(
      baseDirectory: '${dir.path}/spectrogram_saves',
    );
  }

  // ════════════════════════════════════════════════════════════
  //  Capture lifecycle
  // ════════════════════════════════════════════════════════════

  void _ensureCapture() {
    if (_capture.isCapturing) return;
    _startCapture();
  }

  Future<void> _startCapture() async {
    final error = await _capture.start();
    if (error != null) {
      _connectionError = error;
      notifyListeners();
      return;
    }

    _captureSub = _capture.samples.listen(
      _onSamples,
      onError: (Object e) {
        _connectionError = 'Capture error: $e';
        notifyListeners();
      },
    );
  }

  void _stopCapture() {
    _captureSub?.cancel();
    _captureSub = null;
    _capture.stop();
  }

  // ── Sample processing: AudioCapture → StftProcessor → frame routing ──

  void _onSamples(Float64List samples) {
    final frames = _processor.feed(samples);

    for (final frame in frames) {
      if (_livePreviewActive) {
        _liveFrames.add(frame);
        if (_liveFrames.length > maxLiveFrames) _liveFrames.removeAt(0);
      }
      if (_isRecording) {
        _recordedFrames.add(frame);
      }
    }

    if (frames.isNotEmpty) notifyListeners();
  }

  // ════════════════════════════════════════════════════════════
  //  Cleanup
  // ════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _stopCapture();
    _capture.dispose();
    super.dispose();
  }
}
