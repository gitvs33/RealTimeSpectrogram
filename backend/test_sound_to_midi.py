#!/usr/bin/env python3
"""
test_sound_to_midi.py — Test script for sound_to_music_journey.md pipeline.

Takes an audio file:
  1. Detects HOW MANY sound events (librosa.effects.split)
  2. Maps each event to a MIDI note
  3. Writes a .mid file (midiutil)
  4. Renders to raw instrumental WAV via pure-Python sine-wave synth
     (numpy + soundfile — no external synth required)

Usage:
    python3 test_sound_to_midi.py                    # uses bird.mp3
    python3 test_sound_to_midi.py path/to/audio.mp3  # custom file
    python3 test_sound_to_midi.py --list-instruments # show MIDI programs
    python3 test_sound_to_midi.py --instrument 73    # use Flute
"""

import os
import sys
import argparse
from pathlib import Path

import librosa
import numpy as np
from midiutil import MIDIFile
import soundfile as sf


# ─── Config ────────────────────────────────────────────────────────────────
TOP_DB = 20                  # silence threshold for event detection
TEMPO_BPM = 120
MIN_CHUNK_LEN = 2048         # samples; skip tiny events
VELOCITY_SCALE = 127         # max MIDI velocity
SAMPLE_RATE = 44100          # output WAV sample rate


# ─── General MIDI Instrument Names ─────────────────────────────────────────

GM_INSTRUMENTS = {
    0: "Acoustic Grand Piano",
    1: "Bright Acoustic Piano",
    2: "Electric Grand Piano",
    3: "Honky-tonk Piano",
    4: "Electric Piano 1",
    5: "Electric Piano 2",
    6: "Harpsichord",
    7: "Clavi",
    8: "Celesta",
    9: "Glockenspiel",
    10: "Music Box",
    11: "Vibraphone",
    12: "Marimba",
    13: "Xylophone",
    14: "Tubular Bells",
    15: "Dulcimer",
    16: "Drawbar Organ",
    17: "Percussive Organ",
    18: "Rock Organ",
    19: "Church Organ",
    20: "Reed Organ",
    24: "Acoustic Guitar (nylon)",
    25: "Acoustic Guitar (steel)",
    26: "Electric Guitar (jazz)",
    27: "Electric Guitar (clean)",
    28: "Electric Guitar (muted)",
    29: "Overdriven Guitar",
    30: "Distortion Guitar",
    31: "Guitar harmonics",
    32: "Acoustic Bass",
    40: "Violin",
    41: "Viola",
    42: "Cello",
    43: "Contrabass",
    44: "Tremolo Strings",
    45: "Pizzicato Strings",
    46: "Orchestral Harp",
    47: "Timpani",
    48: "String Ensemble 1",
    49: "String Ensemble 2",
    56: "Trumpet",
    57: "Trombone",
    58: "Tuba",
    59: "Muted Trumpet",
    60: "French Horn",
    73: "Flute",
    74: "Recorder",
    75: "Pan Flute",
    76: "Blown Bottle",
    77: "Shakuhachi",
    78: "Whistle",
    79: "Ocarina",
    116: "Taiko Drum",
    117: "Melodic Tom",
    118: "Synth Drum",
    119: "Reverse Cymbal",
}


def list_instruments():
    """Print all known MIDI instrument names."""
    print("\n  MIDI Instrument Program Numbers (General MIDI):")
    print("  " + "-" * 48)
    for num in range(128):
        name = GM_INSTRUMENTS.get(num, "")
        if name:
            print(f"    {num:>3} = {name}")
    print()


# ─── Step 1: Load Audio ────────────────────────────────────────────────────

def load_audio(path: str) -> tuple:
    """Load audio file → (samples y, sample_rate sr)."""
    print(f"\n  Loading: {path}")
    y, sr = librosa.load(path)
    print(f"  Duration: {len(y)/sr:.2f}s  |  SR: {sr} Hz  |  Samples: {len(y)}")
    return y, sr


# ─── Step 2: Detect Events ─────────────────────────────────────────────────

def detect_events(y, sr: int, top_db: int = 20):
    """Detect sound events via librosa.effects.split.

    Returns array of [start_sample, end_sample] for each event.
    """
    intervals = librosa.effects.split(y, top_db=top_db)
    total_dur = sum((en - st) / sr for st, en in intervals)

    print(f"\n  ═══ EVENT DETECTION ═══")
    print(f"  Method: librosa.effects.split(top_db={top_db})")
    print(f"  Total events found: {len(intervals)}")
    print(f"  Total event duration: {total_dur:.2f}s "
          f"({total_dur/(len(y)/sr)*100:.1f}% of audio)")

    for i, (st, en) in enumerate(intervals):
        dur = (en - st) / sr
        print(f"    Event {i+1:>3}:  {st:>8}–{en:<8}  ({dur:.3f}s)")

    return intervals


# ─── Step 3: Extract Pitch from a Chunk ────────────────────────────────────

def extract_midi_note(chunk, sr: int):
    """Extract dominant MIDI note number and velocity from an audio chunk.

    Uses librosa.piptrack to find the dominant frequency.
    """
    pitches, magnitudes = librosa.piptrack(y=chunk, sr=sr)
    idx = magnitudes.argmax()
    freq = pitches.flatten()[idx]

    if freq <= 0:
        return None, None

    # Frequency → MIDI note (A4 = 440 Hz = note 69)
    note = int(69 + 12 * np.log2(freq / 440.0))
    note = int(np.clip(note, 21, 108))  # valid piano range

    # Amplitude → velocity (1–127)
    amp = np.max(np.abs(chunk))
    velocity = int(np.clip(amp * VELOCITY_SCALE, 1, VELOCITY_SCALE))

    return note, velocity


# ─── Step 4: Events → MIDI Notes (in memory) + MIDI File ──────────────────

def process_events_to_midi(y, sr: int, intervals, output_path: str,
                           instrument: int = 0, tempo: int = 120):
    """Map events to MIDI notes.

    Returns list of note dicts for later synthesis, AND writes .mid file.
    """
    midi = MIDIFile(1)
    midi.addTempo(0, 0, tempo)
    midi.addProgramChange(0, 0, 0, instrument)

    notes = []
    notes_added = 0
    skipped_short = 0
    skipped_nopitch = 0

    for start, end in intervals:
        chunk = y[start:end]

        if len(chunk) < MIN_CHUNK_LEN:
            skipped_short += 1
            continue

        note_num, velocity = extract_midi_note(chunk, sr)
        if note_num is None:
            skipped_nopitch += 1
            continue

        duration = (end - start) / sr
        time_sec = start / sr

        # Keep in memory for synthesis
        notes.append({
            "note": note_num,
            "velocity": velocity,
            "start": time_sec,
            "duration": duration,
        })

        midi.addNote(0, 0, note_num, time_sec, duration, velocity)
        notes_added += 1

    # Write MIDI file
    with open(output_path, "wb") as f:
        midi.writeFile(f)

    print(f"\n  ═══ MIDI OUTPUT ═══")
    print(f"  File:       {output_path}")
    instr_name = GM_INSTRUMENTS.get(instrument, f"program {instrument}")
    print(f"  Instrument: {instrument} ({instr_name})")
    print(f"  Tempo:      {tempo} BPM")
    print(f"  Notes added: {notes_added}")
    print(f"  Skipped (too short):  {skipped_short}")
    print(f"  Skipped (no pitch):   {skipped_nopitch}")

    return notes


# ─── Step 5: MIDI Notes → Instrumental WAV (Pure Python) ──────────────────

def synthesize_notes_to_wav(notes, output_path: str, sr: int = SAMPLE_RATE):
    """Render a list of MIDI notes to a WAV file using numpy sine-wave synth.

    Generates a waveform with fundamental + harmonics and an ADSR-like
    envelope for each note.  No external synth or soundfont needed.
    """
    if not notes:
        print("\n  ⚠ No notes to synthesize.")
        return None

    # Calculate total duration with 1s padding
    total_sec = max(n["start"] + n["duration"] for n in notes) + 1.0
    num_samples = int(total_sec * sr)
    audio = np.zeros(num_samples, dtype=np.float64)

    for n in notes:
        midi_note = n["note"]
        velocity = n["velocity"]
        start_sec = n["start"]
        duration = n["duration"]

        # MIDI note → frequency (A4 = 440 Hz = note 69)
        freq = 440.0 * (2.0 ** ((midi_note - 69) / 12.0))

        start_sample = int(start_sec * sr)
        end_sample = min(start_sample + int(duration * sr), num_samples)

        if start_sample >= num_samples:
            continue

        length = end_sample - start_sample
        if length <= 0:
            continue

        t = np.arange(length) / sr

        # Amplitude from velocity
        amp = (velocity / VELOCITY_SCALE) * 0.3

        # ── Waveform ───────────────────────────────────────────────
        # Mix fundamental + harmonics for a warmer instrumental tone
        tone = (
            np.sin(2 * np.pi * freq * t) * 0.6          # fundamental
            + np.sin(2 * np.pi * freq * 2 * t) * 0.25   # 2nd harmonic
            + np.sin(2 * np.pi * freq * 3 * t) * 0.1    # 3rd harmonic
            + np.sin(2 * np.pi * freq * 4 * t) * 0.05   # 4th harmonic
        )

        # ── Envelope ──────────────────────────────────────────────
        attack_ms = 10    # 10 ms attack
        release_ms = 30   # 30 ms release
        attack_samples = min(int(attack_ms * sr / 1000), length // 4)
        release_samples = min(int(release_ms * sr / 1000), length // 4)

        envelope = np.ones(length)
        if attack_samples > 0:
            envelope[:attack_samples] = np.linspace(0, 1, attack_samples)
        if release_samples > 0:
            envelope[-release_samples:] = np.linspace(1, 0, release_samples)

        # Add to mix
        audio[start_sample:end_sample] += tone * envelope * amp

    # Normalize to float32 range
    max_val = np.max(np.abs(audio))
    if max_val > 0:
        audio = audio / max_val * 0.9

    # Write WAV
    sf.write(output_path, audio.astype(np.float32), sr)

    size_kb = os.path.getsize(output_path) / 1024
    print(f"\n  ═══ INSTRUMENTAL AUDIO ═══")
    print(f"  File:      {output_path}")
    print(f"  Synth:     Pure-Python (sine + harmonics, numpy+soundfile)")
    print(f"  Duration:  {total_sec:.2f}s")
    print(f"  Notes:     {len(notes)}")
    print(f"  Size:      {size_kb:.1f} KB")
    print(f"  Format:    WAV (32-bit float PCM)")

    return output_path


# ─── Summary ───────────────────────────────────────────────────────────────

def print_summary(events_count: int, midi_path: str, audio_path: str):
    print()
    print("=" * 65)
    print("  🎵  SOUND → MUSIC PIPELINE — COMPLETE  🎵")
    print("=" * 65)
    print(f"  Sound events detected     : {events_count}")
    print(f"  MIDI file                 : {midi_path}")
    print(f"  Instrumental audio        : {audio_path}")
    print("=" * 65)


# ─── Main ──────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Detect sound events in audio → MIDI → instrumental audio"
    )
    parser.add_argument("input", nargs="?", default="bird.mp3",
                        help="Input audio file (default: bird.mp3)")
    parser.add_argument("--top-db", type=int, default=TOP_DB,
                        help=f"Silence threshold for event detection "
                             f"(default: {TOP_DB})")
    parser.add_argument("--instrument", "-i", type=int, default=0,
                        help="MIDI program number (default: 0 = Piano). "
                             "Use --list-instruments to see all.")
    parser.add_argument("--tempo", type=int, default=TEMPO_BPM,
                        help=f"MIDI tempo in BPM (default: {TEMPO_BPM})")
    parser.add_argument("--outdir", default="output",
                        help="Output directory (default: output/)")
    parser.add_argument("--list-instruments", action="store_true",
                        help="List MIDI instrument names and exit")
    args = parser.parse_args()

    if args.list_instruments:
        list_instruments()
        return

    # ── Paths ──────────────────────────────────────────────────────
    if not os.path.exists(args.input):
        print(f"\n  ❌ File not found: {args.input}")
        print("  Usage: python3 test_sound_to_midi.py [audio_file]")
        sys.exit(1)

    stem = Path(args.input).stem
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    midi_path  = str(outdir / f"{stem}_events.mid")
    audio_path = str(outdir / f"{stem}_instrumental.wav")

    # ── Pipeline ───────────────────────────────────────────────────
    print()
    print("━" * 65)
    print("  🎵  SOUND → MUSIC PIPELINE")
    print("━" * 65)

    # Step 1 — Load audio
    y, sr = load_audio(args.input)

    # Step 2 — Detect events (this answers "how many events?")
    intervals = detect_events(y, sr, top_db=args.top_db)

    # Step 3 — Convert events → MIDI notes (in memory + .mid file)
    notes = process_events_to_midi(y, sr, intervals, midi_path,
                                   instrument=args.instrument,
                                   tempo=args.tempo)

    # Step 4 — Render notes → instrumental WAV (pure Python, no external synth)
    synthesize_notes_to_wav(notes, audio_path)

    # Done
    print_summary(len(intervals), midi_path, audio_path)


if __name__ == "__main__":
    main()
