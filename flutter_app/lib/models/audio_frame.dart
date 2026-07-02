/// Represents a single STFT frame (one time slice of the spectrogram).
class AudioFrame {
  final double time;
  final List<double> frequencies;
  final List<double> magnitudes;
  final List<double> phases;

  AudioFrame({
    required this.time,
    required this.frequencies,
    required this.magnitudes,
    required this.phases,
  });

  factory AudioFrame.fromJson(Map<String, dynamic> json) {
    return AudioFrame(
      time: (json['time'] as num).toDouble(),
      frequencies: (json['frequencies'] as List).cast<num>().map((e) => e.toDouble()).toList(),
      magnitudes: (json['magnitudes'] as List).cast<num>().map((e) => e.toDouble()).toList(),
      phases: (json['phases'] as List).cast<num>().map((e) => e.toDouble()).toList(),
    );
  }

  int get binCount => frequencies.length;
}

/// Complete recording data (all frames).
class FullRecordingData {
  final List<double> times;
  final List<double> frequencies;
  final List<List<double>> magnitudes;
  final List<List<double>> phases;

  FullRecordingData({
    required this.times,
    required this.frequencies,
    required this.magnitudes,
    required this.phases,
  });

  factory FullRecordingData.fromJson(Map<String, dynamic> json) {
    return FullRecordingData(
      times: (json['times'] as List).cast<num>().map((e) => e.toDouble()).toList(),
      frequencies: (json['frequencies'] as List).cast<num>().map((e) => e.toDouble()).toList(),
      magnitudes: (json['magnitudes'] as List)
          .cast<List>()
          .map((row) => row.cast<num>().map((e) => e.toDouble()).toList())
          .toList(),
      phases: (json['phases'] as List)
          .cast<List>()
          .map((row) => row.cast<num>().map((e) => e.toDouble()).toList())
          .toList(),
    );
  }

  int get frameCount => times.length;
  int get binCount => frequencies.length;
}
