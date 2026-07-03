import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/theme/color_lut.dart';

void main() {
  group('ColorLut', () {
    test('has 256 entries with 4 bytes each', () {
      expect(ColorLut.rgba.length, 256 * 4);
      expect(ColorLut.size, 256);
      expect(ColorLut.stride, 4);
    });

    test('alpha is always 255', () {
      final lut = ColorLut.rgba;
      for (int i = 0; i < 256; i++) {
        expect(lut[i * 4 + 3], 255, reason: 'Entry $i has non-255 alpha');
      }
    });

    test('entry 0 (fully black) is all zeros', () {
      expect(ColorLut.rgba[0], 0);
      expect(ColorLut.rgba[1], 0);
      expect(ColorLut.rgba[2], 0);
    });

    test('first 64 entries (bottom 25%) are black', () {
      for (int i = 0; i < 64; i++) {
        expect(ColorLut.rgba[i * 4], 0, reason: 'Entry $i R != 0');
        expect(ColorLut.rgba[i * 4 + 1], 0, reason: 'Entry $i G != 0');
        expect(ColorLut.rgba[i * 4 + 2], 0, reason: 'Entry $i B != 0');
      }
    });

    test('final entry is pale yellow', () {
      // Last color stop: 0xFFfcffa4
      expect(ColorLut.rgba[255 * 4], 0xfc); // R
      expect(ColorLut.rgba[255 * 4 + 1], 0xff); // G
      expect(ColorLut.rgba[255 * 4 + 2], 0xa4); // B
    });

    test('entries past index 64 have non-zero color channels', () {
      // At least some channels should be > 0 to ensure gradient works
      bool anyNonZero = false;
      for (int i = 64; i < 256; i++) {
        if (ColorLut.rgba[i * 4] > 0 ||
            ColorLut.rgba[i * 4 + 1] > 0 ||
            ColorLut.rgba[i * 4 + 2] > 0) {
          anyNonZero = true;
          break;
        }
      }
      expect(anyNonZero, isTrue);
    });

    test('no entry has out-of-range byte values', () {
      for (int i = 0; i < ColorLut.rgba.length; i++) {
        expect(ColorLut.rgba[i], inInclusiveRange(0, 255));
      }
    });
  });
}
