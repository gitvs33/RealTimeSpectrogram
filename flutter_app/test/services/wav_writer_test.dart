import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/wav_writer.dart';

void main() {
  group('WavWriter', () {
    test('encodePcm16 produces valid RIFF header', () {
      final bytes = WavWriter.encodePcm16([0.0, 0.5, -0.5], 44100);

      // RIFF marker
      expect(bytes[0], 0x52); // R
      expect(bytes[1], 0x49); // I
      expect(bytes[2], 0x46); // F
      expect(bytes[3], 0x46); // F

      // WAVE marker at offset 8
      expect(bytes[8], 0x57); // W
      expect(bytes[9], 0x41); // A
      expect(bytes[10], 0x56); // V
      expect(bytes[11], 0x45); // E

      // fmt  marker at offset 12
      expect(bytes[12], 0x66); // f
      expect(bytes[13], 0x6D); // m
      expect(bytes[14], 0x74); // t
      expect(bytes[15], 0x20); // ' '

      // PCM (1) at offset 20
      expect(bytes[20], 1);

      // channels (1) at offset 22
      expect(bytes[22], 1);

      // sample rate at offset 24
      expect(bytes[24], 44100 & 0xFF);
      expect(bytes[25], (44100 >> 8) & 0xFF);
      expect(bytes[26], (44100 >> 16) & 0xFF);
      expect(bytes[27], (44100 >> 24) & 0xFF);

      // bits per sample (16) at offset 34
      expect(bytes[34], 16);
      expect(bytes[35], 0);

      // data marker at offset 36
      expect(bytes[36], 0x64); // d
      expect(bytes[37], 0x61); // a
      expect(bytes[38], 0x74); // t
      expect(bytes[39], 0x61); // a
    });

    test('encodePcm16 yields correct file size', () {
      final samples = [0.0, 0.25, 0.5, -0.25, -0.5, 1.0];
      final bytes = WavWriter.encodePcm16(samples, 22050);

      // File size at offset 4 = 36 + dataSize
      final fileSize =
          bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24);
      expect(fileSize, bytes.length - 8);
      expect(bytes.length, 44 + samples.length * 2);
    });

    test('encodePcm16 silent input produces zeros', () {
      final bytes = WavWriter.encodePcm16([0.0, 0.0, 0.0, 0.0], 44100);
      // Data starts at offset 44
      for (int i = 44; i < bytes.length; i++) {
        expect(bytes[i], 0);
      }
    });

    test('encodePcm16 clamps extreme values', () {
      final bytes = WavWriter.encodePcm16([2.0, -2.0], 44100);
      // Max 16-bit positive = 32767, min = -32768 (represented as 0..65535 in file)
      // First sample: 2.0 * 32767 clamped to 32767 → 0x7FFF → bytes 44,45
      expect(bytes[44], 0xFF);
      expect(bytes[45], 0x7F);
      // Second sample: -2.0 * 32767 clamped to -32768 → 0x8000 → bytes 46,47
      expect(bytes[46], 0);
      expect(bytes[47], 0x80);
    });

    test('encodePcm16 preserves sample count', () {
      final count = 100;
      final samples = List<double>.generate(count, (i) => (i / count) * 2 - 1);
      final bytes = WavWriter.encodePcm16(samples, 48000);
      // data size at offset 40
      final dataSize =
          bytes[40] | (bytes[41] << 8) | (bytes[42] << 16) | (bytes[43] << 24);
      expect(dataSize, count * 2);
      expect(bytes.length, 44 + count * 2);
    });
  });
}
