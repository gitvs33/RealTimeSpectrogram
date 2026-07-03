import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/audio_frame.dart';
import 'package:flutter_app/services/stft_data_query.dart';

/// Build a minimal AudioFrame with [binCount] bins.
/// [time] is used directly; [magBase] sets the first bin's magnitude.
AudioFrame _makeFrame(double time, int binCount, {double magBase = 0.5}) {
  return AudioFrame(
    time: time,
    frequencies: List<double>.generate(binCount, (i) => i * 100.0),
    magnitudes: List<double>.generate(binCount, (i) => magBase + i * 0.1),
    phases: List<double>.generate(binCount, (i) => i * 0.1),
  );
}

/// Two frames with non-overlapping time values to make time-based
/// filters unambiguous.
final _distinctFrames = [
  _makeFrame(0.123, 3, magBase: 0.5), // time "0.123"
  _makeFrame(3.456, 3, magBase: 0.8), // time "3.456"
];

void main() {
  group('StftDataQuery', () {
    test('binCount returns frame bin count', () {
      const q = StftDataQuery();
      expect(q.binCount(_distinctFrames), 3);
      expect(q.binCount([]), 0);
    });

    test('isTrivial when no filters active', () {
      // Default: showOnlyNonZero=true (non-zero filter IS active)
      expect(const StftDataQuery().isTrivial, false);
      // Search filter active
      expect(const StftDataQuery(searchFilter: 'x').isTrivial, false);
      // showOnlyNonZero: false means "show all" → no filtering needed
      expect(const StftDataQuery(showOnlyNonZero: false).isTrivial, true);
      // Both search and non-zero filters active
      expect(
        const StftDataQuery(searchFilter: 'x', showOnlyNonZero: false)
            .isTrivial,
        false,
      );
    });

    group('totalRows', () {
      test('returns frames * bins with trivial (no-filter) query', () {
        // showOnlyNonZero=true filters zero rows, but we have no zeros
        const q = StftDataQuery();
        expect(q.totalRows(_distinctFrames), 6); // 2 frames * 3 bins
        expect(q.totalRows([]), 0);
      });

      test('respects showOnlyNonZero', () {
        const q = StftDataQuery(showOnlyNonZero: true);

        final zeroFrames = [
          _makeFrame(0.0, 3, magBase: 0.0), // bin0=0.0, bin1=0.1, bin2=0.2
          _makeFrame(0.5, 3, magBase: 0.8),
        ];
        // Only bin0 of first frame (mag=0.0) is excluded
        expect(q.totalRows(zeroFrames), 5);
      });

      test('searchFilter filters rows', () {
        const q = StftDataQuery(searchFilter: '100');
        expect(q.totalRows(_distinctFrames), 2); // bin1 of each frame
      });

      test('searchFilter matches time column uniquely', () {
        const q = StftDataQuery(searchFilter: '123');
        // "123" appears only in first frame's time "0.123" → 3 bins
        expect(q.totalRows(_distinctFrames), 3);
      });
    });

    group('rowAt', () {
      test('returns correct data for trivial query', () {
        const q = StftDataQuery();
        final row0 = q.rowAt(_distinctFrames, 0);
        expect(row0, isNotNull);
        expect(row0!.time, '0.123');
        expect(row0.frequency, '0.0');
        expect(row0.amplitude, '0.500000');

        final row3 = q.rowAt(_distinctFrames, 3);
        expect(row3, isNotNull);
        expect(row3!.time, '3.456');
        expect(row3.frequency, '0.0');
      });

      test('returns null for out-of-range index', () {
        const q = StftDataQuery();
        expect(q.rowAt(_distinctFrames, 99), isNull);
        expect(q.rowAt(_distinctFrames, -1), isNull);
        expect(q.rowAt([], 0), isNull);
      });

      test('returns null for empty frames', () {
        const q = StftDataQuery();
        expect(q.rowAt([], 0), isNull);
      });

      test('respects showOnlyNonZero filter', () {
        final zeroFrames = [
          _makeFrame(0.0, 3, magBase: 0.0), // bin0=0, bin1=0.1, bin2=0.2
          _makeFrame(0.5, 3, magBase: 0.8),
        ];
        const q = StftDataQuery(showOnlyNonZero: true);
        // row 0 skips bin0 of frame 0 (mag=0), so first visible row is bin1
        final row0 = q.rowAt(zeroFrames, 0);
        expect(row0, isNotNull);
        expect(row0!.frequency, '100.0'); // bin 1 of frame 0
      });

      test('respects searchFilter', () {
        const q = StftDataQuery(searchFilter: '200');
        final row0 = q.rowAt(_distinctFrames, 0);
        expect(row0, isNotNull);
        expect(row0!.frequency, '200.0'); // only bin 2 has freq 200.0
      });
    });

    group('exportTsv', () {
      test('produces header and rows', () {
        const q = StftDataQuery();
        final tsv = q.exportTsv(_distinctFrames);
        expect(
          tsv,
          startsWith('time_s\tfrequency_hz\tamplitude\tphase_radians\n'),
        );
        final lines = tsv.trim().split('\n');
        expect(lines.length, 7); // header + 6 data rows
      });

      test('empty frames returns empty string', () {
        const q = StftDataQuery();
        expect(q.exportTsv([]), '');
      });

      test('respects maxLines', () {
        const q = StftDataQuery();
        final tsv = q.exportTsv(_distinctFrames, maxLines: 2);
        final lines = tsv.trim().split('\n');
        expect(lines.length, 3); // header + 2 data rows
      });

      test('respects time-based filter uniquely', () {
        const q = StftDataQuery(searchFilter: '456');
        final tsv = q.exportTsv(_distinctFrames);
        final lines = tsv.trim().split('\n');
        expect(lines.length, 4); // header + 3 rows (second frame only)
      });

      test('TSV lines are tab-delimited', () {
        const q = StftDataQuery();
        final tsv = q.exportTsv(_distinctFrames);
        final dataLines = tsv.trim().split('\n').skip(1);
        for (final line in dataLines) {
          final parts = line.split('\t');
          expect(parts.length, 4);
          expect(double.tryParse(parts[0]), isNotNull); // time
          expect(double.tryParse(parts[1]), isNotNull); // freq
          expect(double.tryParse(parts[2]), isNotNull); // amp
          expect(double.tryParse(parts[3]), isNotNull); // phase
        }
      });
    });
  });
}
