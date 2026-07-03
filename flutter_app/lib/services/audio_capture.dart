import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';

/// Captures microphone audio and emits normalized [-1, 1] sample chunks.
///
/// Owns the [AudioRecorder] lifecycle. Optionally accumulates raw audio
/// for WAV export when recording is active.
///
/// ```dart
/// final capture = AudioCapture();
/// final ok = await capture.start();
/// if (!ok) { /* handle permission error */ }
/// capture.samples.listen((samples) { /* feed to StftProcessor */ });
/// ```
class AudioCapture {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;

  final StreamController<Float64List> _controller =
      StreamController<Float64List>.broadcast();

  bool _isRecording = false;
  final List<double> _rawAudio = [];

  /// Whether the mic is currently capturing.
  bool get isCapturing => _subscription != null;

  /// Broadcast stream of normalized [-1, 1] float sample chunks.
  Stream<Float64List> get samples => _controller.stream;

  // ── Lifecycle ──

  /// Start the microphone capture.
  ///
  /// Returns `null` on success, or an error message string on failure
  /// (e.g. permission denied, mic unavailable).
  Future<String?> start() async {
    if (_subscription != null) return null; // already running

    if (!await _recorder.hasPermission()) {
      return 'Microphone permission denied';
    }

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 44100,
          numChannels: 1,
        ),
      );

      _subscription = stream.listen(
        _onPcmData,
        onError: (Object e) {
          _controller.addError(e);
        },
        onDone: () {
          // Stream ended naturally — don't close the controller so it can
          // be restarted.
        },
      );

      return null; // success
    } catch (e) {
      return 'Failed to start capture: $e';
    }
  }

  /// Stop the microphone capture and release resources.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _recorder.stop();
  }

  // ── Recording (raw audio accumulation) ──

  /// Begin accumulating raw audio for WAV export.
  /// Clears any previously accumulated audio.
  void startRecording() {
    _rawAudio.clear();
    _isRecording = true;
  }

  /// Stop accumulating raw audio.
  void stopRecording() {
    _isRecording = false;
  }

  /// Retrieve accumulated raw audio since the last [startRecording] call.
  /// Returns a copy; internal buffer is cleared.
  Float64List getRecordedAudio() {
    final result = Float64List.fromList(_rawAudio);
    _rawAudio.clear();
    return result;
  }

  // ── Internal ──

  void _onPcmData(Uint8List pcmBytes) {
    // Decode 16-bit PCM → float samples in [-1, 1]
    final samples = Float64List(pcmBytes.length ~/ 2);
    for (int i = 0; i < samples.length; i++) {
      int val = pcmBytes[i * 2] | (pcmBytes[i * 2 + 1] << 8);
      if (val >= 32768) val -= 65536; // sign extend
      samples[i] = val / 32768.0;
    }

    if (_isRecording) {
      _rawAudio.addAll(samples);
    }

    _controller.add(samples);
  }

  // ── Disposal ──

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
