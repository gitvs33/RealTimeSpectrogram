import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../models/audio_frame.dart';
import 'fft_utils.dart';

/// Audio source mode.
enum AudioMode {
  /// Connect to a Python backend via WebSocket (desktop default).
  network,

  /// Capture audio locally from the device mic (mobile default).
  local,
}

/// Manages the spectrogram audio pipeline.
///
/// Runs in one of two modes:
/// - [AudioMode.network]: connects to a Python backend via WebSocket
/// - [AudioMode.local]: captures mic + STFT entirely on-device
///
/// In local mode, [connect] is a no-op and the mic starts on
/// [startLivePreview] / [startRecording]. Saved files go to the app's
/// documents directory.
class SpectrogramService extends ChangeNotifier {
  // ── Mode ──
  final AudioMode mode;

  SpectrogramService({this.mode = AudioMode.network});

  /// Auto-detect: mobile → local, desktop → network.
  static AudioMode detectDefaultMode() {
    try {
      if (Platform.isAndroid || Platform.isIOS) return AudioMode.local;
    } catch (_) {}
    return AudioMode.network;
  }

  // ── Network state ──
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _statusTimer;

  // ── Local capture state ──
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _streamSub;
  final List<double> _audioBuffer = [];
  final List<double> _rawAudio = []; // accumulated raw samples for WAV
  static const int fftSize = 1024;
  static const int hopLength = 512;
  static const int sampleRate = 44100;
  final Float64List _hannWindow = FFTUtils.hannWindow(fftSize);
  int _frameIndex = 0;

  // ── Shared state ──
  bool _isConnected = false;
  bool _isRecording = false;
  bool _livePreviewActive = false;
  bool _isCapturing = false;

  final List<AudioFrame> _liveFrames = [];
  static const int maxLiveFrames = 300;
  final List<AudioFrame> _recordedFrames = [];

  String _connectionError = '';
  String _saveMessage = '';

  // ── Getters ──
  bool get isConnected   => mode == AudioMode.local ? true : _isConnected;
  bool get isRecording   => _isRecording;
  bool get livePreviewActive => _livePreviewActive;
  List<AudioFrame> get liveFrames => _liveFrames;
  List<AudioFrame> get recordedFrames => _recordedFrames;
  int get recordedFrameCount => _recordedFrames.length;
  double get recordingDuration =>
      _recordedFrames.isEmpty ? 0.0 : _recordedFrames.last.time;
  String get connectionError => _connectionError;
  String get saveMessage => _saveMessage;

  // ════════════════════════════════════════════════════════════
  //  NETWORK MODE  (WebSocket)
  // ════════════════════════════════════════════════════════════

  /// Connect to a Python backend (only in [AudioMode.network]).
  Future<void> connect(String host, int port) async {
    if (mode == AudioMode.local) return;
    _connectionError = '';
    try {
      final uri = Uri.parse('ws://$host:$port');
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
      _isConnected = true;
      _connectionError = '';
      _startStatusPolling();
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      _connectionError = 'Connection failed: $e';
      notifyListeners();
      _scheduleReconnect(host, port);
    }
  }

  void _scheduleReconnect(String host, int port) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      connect(host, port);
    });
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isConnected) send({'command': 'get_status'});
    });
  }

  void send(Map<String, dynamic> command) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(command));
    }
  }

  void disconnect() {
    if (mode == AudioMode.network) _stopLocalCapture();
    _reconnectTimer?.cancel();
    _statusTimer?.cancel();
    _channel?.sink.close(status.goingAway);
    _isConnected = false;
    notifyListeners();
  }

  /// Register the WebSocket stream listener (called after connect).
  void startListening() {
    _channel?.stream.listen(
      (data) {
        if (data is String) _onNetworkMessage(data);
      },
      onError: (error) {
        _isConnected = false;
        _connectionError = 'Connection lost: $error';
        notifyListeners();
      },
      onDone: () {
        _isConnected = false;
        notifyListeners();
      },
    );
  }

  void _onNetworkMessage(String raw) {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final type = msg['type'] as String?;

      switch (type) {
        case 'frame':
          final frame =
              AudioFrame.fromJson(msg['data'] as Map<String, dynamic>);
          if (_livePreviewActive) {
            _liveFrames.add(frame);
            if (_liveFrames.length > maxLiveFrames) _liveFrames.removeAt(0);
          }
          if (_isRecording) _recordedFrames.add(frame);
          notifyListeners();
          break;
        case 'recording_started':
          _isRecording = true;
          _recordedFrames.clear();
          notifyListeners();
          break;
        case 'recording_stopped':
          _isRecording = false;
          notifyListeners();
          break;
        case 'saved':
          _saveMessage = 'Saved: ${msg['filename']}';
          notifyListeners();
          break;
        case 'full_data':
          // ignore — local save uses recordedFrames directly
          break;
        case 'status':
          _isRecording = msg['is_recording'] as bool? ?? _isRecording;
          notifyListeners();
          break;
        case 'error':
          _connectionError = msg['message'] as String? ?? 'Unknown error';
          notifyListeners();
          break;
      }
    } catch (e) {
      debugPrint('Error parsing message: $e');
    }
  }

  // ════════════════════════════════════════════════════════════
  //  LOCAL CAPTURE MODE  (mic + STFT on-device)
  // ════════════════════════════════════════════════════════════

  Future<void> _startLocalCapture() async {
    if (_isCapturing || mode != AudioMode.local) return;
    _isCapturing = true;
    _audioBuffer.clear();
    _frameIndex = 0;

    try {
      if (!await _recorder.hasPermission()) {
        _connectionError = 'Microphone permission denied';
        notifyListeners();
        return;
      }

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
        ),
      );

      _streamSub = stream.listen(
        _onLocalAudioData,
        onError: (e) {
          _connectionError = 'Capture error: $e';
          _isCapturing = false;
          notifyListeners();
        },
        onDone: () {
          _isCapturing = false;
          notifyListeners();
        },
      );
    } catch (e) {
      _connectionError = 'Failed to start capture: $e';
      _isCapturing = false;
      notifyListeners();
    }
  }

  void _stopLocalCapture() {
    _streamSub?.cancel();
    _streamSub = null;
    _recorder.stop();
    _isCapturing = false;
  }

  void _onLocalAudioData(Uint8List pcmBytes) {
    // Decode 16-bit PCM → float samples in [-1, 1]
    final samples = Float64List(pcmBytes.length ~/ 2);
    for (int i = 0; i < samples.length; i++) {
      int val = pcmBytes[i * 2] | (pcmBytes[i * 2 + 1] << 8);
      if (val >= 32768) val -= 65536; // sign extend
      samples[i] = val / 32768.0;
    }

    if (_isRecording) _rawAudio.addAll(samples);
    _audioBuffer.addAll(samples);

    // Process as many full STFT frames as we can
    while (_audioBuffer.length >= fftSize) {
      // Window the frame
      final frame = Float64List(fftSize);
      for (int i = 0; i < fftSize; i++) {
        frame[i] = _audioBuffer[i] * _hannWindow[i];
      }
      _audioBuffer.removeRange(0, hopLength);

      // FFT
      final (mags, phases) = FFTUtils.computeRFFT(frame);

      // Frequency bins
      final freqStep = sampleRate / fftSize;
      final freqs = Float64List(mags.length);
      for (int i = 0; i < freqs.length; i++) {
        freqs[i] = i * freqStep;
      }

      final time = _frameIndex * hopLength / sampleRate;
      _frameIndex++;

      final af = AudioFrame(
        time: time,
        frequencies: freqs,
        magnitudes: mags,
        phases: phases,
      );

      if (_livePreviewActive) {
        _liveFrames.add(af);
        if (_liveFrames.length > maxLiveFrames) _liveFrames.removeAt(0);
      }
      if (_isRecording) _recordedFrames.add(af);

      notifyListeners();
    }
  }

  // ════════════════════════════════════════════════════════════
  //  COMMON API  (used by the UI regardless of mode)
  // ════════════════════════════════════════════════════════════

  void startLivePreview() {
    _liveFrames.clear();
    _livePreviewActive = true;
    notifyListeners();
    if (mode == AudioMode.local && !_isCapturing) _startLocalCapture();
  }

  void stopLivePreview() {
    _livePreviewActive = false;
    _liveFrames.clear();
    notifyListeners();
  }

  void startRecording() {
    _recordedFrames.clear();
    _rawAudio.clear();
    _isRecording = true;
    _frameIndex = 0;
    notifyListeners();
    if (mode == AudioMode.network) {
      send({'command': 'start_recording'});
    } else {
      if (!_isCapturing) _startLocalCapture();
    }
  }

  void stopRecording() {
    _isRecording = false;
    notifyListeners();
    if (mode == AudioMode.network) {
      send({'command': 'stop_recording'});
    }
  }

  /// Save recorded data.
  ///
  /// In [AudioMode.network] the backend writes WAV/CSV/JSON on its
  /// filesystem and we also write CSV+JSON locally.
  /// In [AudioMode.local] we write all three locally.
  Future<void> saveRecording(String filename) async {
    if (_recordedFrames.isEmpty) return;

    if (mode == AudioMode.network) {
      send({'command': 'save', 'filename': filename});
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final saveDir = Directory('${dir.path}/spectrogram_saves');
      await saveDir.create(recursive: true);

      // ── WAV (only in local mode — we have raw audio) ──
      if (mode == AudioMode.local && _rawAudio.isNotEmpty) {
        final wavPath = '${saveDir.path}/$filename.wav';
        _writeWav(wavPath, _rawAudio, sampleRate);
      }

      // ── CSV ──
      final csvPath = '${saveDir.path}/${filename}_stft.csv';
      final csvSink = File(csvPath).openWrite();
      csvSink.writeln('time_s,frequency_hz,amplitude,phase_radians');
      for (final frame in _recordedFrames) {
        final t = frame.time.toStringAsFixed(3);
        for (int i = 0; i < frame.binCount; i++) {
          csvSink.writeln(
            '$t,${frame.frequencies[i].toStringAsFixed(1)},'
            '${frame.magnitudes[i].toStringAsFixed(6)},'
            '${frame.phases[i].toStringAsFixed(6)}',
          );
        }
      }
      await csvSink.flush();
      await csvSink.close();

      // ── JSON ──
      final jsonPath = '${saveDir.path}/${filename}_stft.json';
      final jsonData = {
        'meta': {
          'sample_rate': sampleRate,
          'fft_size': fftSize,
          'hop_length': hopLength,
          'window': 'hann',
        },
        'times': _recordedFrames.map((f) => f.time).toList(),
        'frequencies': _recordedFrames.isNotEmpty
            ? _recordedFrames.first.frequencies
            : [],
        'magnitudes': _recordedFrames.map((f) => f.magnitudes).toList(),
        'phases': _recordedFrames.map((f) => f.phases).toList(),
      };
      await File(jsonPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(jsonData),
      );

      _saveMessage = 'Saved to ${saveDir.path}/$filename.*';
      debugPrint('[save] Files written to $saveDir');
    } catch (e) {
      _connectionError = 'Save failed: $e';
      debugPrint('[save] Error: $e');
    }
    notifyListeners();
  }

  // ── WAV writer for local mode ──

  void _writeWav(String path, List<double> samples, int sr) {
    final buf = BytesBuilder();
    final dataSize = samples.length * 2; // 16-bit
    final fileSize = 36 + dataSize;

    void w16(int v) {
      buf.addByte(v & 0xFF);
      buf.addByte((v >> 8) & 0xFF);
    }

    void w32(int v) {
      buf.addByte(v & 0xFF);
      buf.addByte((v >> 8) & 0xFF);
      buf.addByte((v >> 16) & 0xFF);
      buf.addByte((v >> 24) & 0xFF);
    }

    // RIFF
    buf.add('RIFF'.codeUnits);
    w32(fileSize);
    buf.add('WAVE'.codeUnits);

    // fmt
    buf.add('fmt '.codeUnits);
    w32(16);          // chunk size
    w16(1);           // PCM
    w16(1);           // mono
    w32(sr);
    w32(sr * 2);      // byte rate
    w16(2);           // block align
    w16(16);          // bits per sample

    // data
    buf.add('data'.codeUnits);
    w32(dataSize);
    for (final s in samples) {
      int val = (s * 32767).clamp(-32768, 32767).toInt();
      if (val < 0) val += 65536;
      w16(val);
    }

    File(path).writeAsBytesSync(buf.toBytes());
  }

  @override
  void dispose() {
    if (mode == AudioMode.local) _stopLocalCapture();
    disconnect();
    super.dispose();
  }
}
