import 'dart:io';
import 'dart:typed_data';

/// Writes 16-bit PCM WAV files from normalized float samples.
///
/// Pure function — takes samples in, produces RIFF bytes out.
/// No dependency on Flutter or device APIs.
class WavWriter {
  WavWriter._();

  /// Encode [samples] (normalized [-1, 1]) as a 16-bit PCM WAV byte buffer.
  ///
  /// Example:
  /// ```dart
  /// final bytes = WavWriter.encodePcm16([0.5, -0.5, 0.25], 44100);
  /// await File('test.wav').writeAsBytes(bytes);
  /// ```
  static Uint8List encodePcm16(List<double> samples, int sampleRate) {
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

    // RIFF header
    buf.add('RIFF'.codeUnits);
    w32(fileSize);
    buf.add('WAVE'.codeUnits);

    // fmt chunk
    buf.add('fmt '.codeUnits);
    w32(16); // chunk size
    w16(1); // PCM
    w16(1); // mono
    w32(sampleRate);
    w32(sampleRate * 2); // byte rate
    w16(2); // block align
    w16(16); // bits per sample

    // data chunk
    buf.add('data'.codeUnits);
    w32(dataSize);
    for (final s in samples) {
      int val = (s * 32767).clamp(-32768, 32767).toInt();
      if (val < 0) val += 65536;
      w16(val);
    }

    return buf.toBytes();
  }

  /// Convenience: encode and write to [path] in one call.
  static Future<void> writeToFile(
    String path,
    List<double> samples,
    int sampleRate,
  ) async {
    final bytes = encodePcm16(samples, sampleRate);
    await File(path).writeAsBytes(bytes);
  }
}
