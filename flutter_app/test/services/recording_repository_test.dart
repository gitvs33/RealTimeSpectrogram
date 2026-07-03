import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/recording_repository.dart';

void main() {
  group('RecordingRepository.stemOf', () {
    test('extracts stem from bare .wav', () {
      expect(
        RecordingRepository.stemOf('/saves/my_recording.wav'),
        'my_recording',
      );
    });

    test('extracts stem from _stft.csv', () {
      expect(
        RecordingRepository.stemOf('/saves/guitar_riff_stft.csv'),
        'guitar_riff',
      );
    });

    test('extracts stem from _stft.json', () {
      expect(
        RecordingRepository.stemOf('/saves/voice_note_stft.json'),
        'voice_note',
      );
    });

    test('extracts stem from _spectrogram.png', () {
      expect(
        RecordingRepository.stemOf('/saves/piano_loop_spectrogram.png'),
        'piano_loop',
      );
    });

    test('extracts stem from _instrumental.wav', () {
      expect(
        RecordingRepository.stemOf('/saves/drum_track_instrumental.wav'),
        'drum_track',
      );
    });

    test('returns null for unknown file types', () {
      expect(RecordingRepository.stemOf('/saves/notes.txt'), isNull);
      expect(RecordingRepository.stemOf('/saves/config.yaml'), isNull);
      expect(RecordingRepository.stemOf('/saves/.hidden'), isNull);
    });

    test('returns null for files without extension', () {
      expect(RecordingRepository.stemOf('/saves/README'), isNull);
    });

    test('handles deep directory paths', () {
      expect(
        RecordingRepository.stemOf('/home/user/recordings/my_song.wav'),
        'my_song',
      );
    });
  });
}
