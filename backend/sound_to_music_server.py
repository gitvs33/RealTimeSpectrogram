#!/usr/bin/env python3
"""
sound_to_music_server.py — REST API server for the "Sound to Music" pipeline.

Host this separately (on a server, Raspberry Pi, or your dev machine).

Accepts a WAV upload → detects sound events → maps to MIDI notes →
renders instrumental audio → returns the result.

Endpoints:
  POST /convert          Upload a WAV file, get back instrumental WAV
  GET  /health           Health check

Usage:
    python3 sound_to_music_server.py
    # → Server running at http://0.0.0.0:8000

    # Test with curl:
    curl -X POST -F "file=@bird.wav" http://localhost:8000/convert -o output.wav

    # Flutter app will POST to this endpoint with the recorded WAV file.
"""

import io
import os
import tempfile
import logging

import numpy as np
import librosa
from midiutil import MIDIFile
import soundfile as sf
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("sound_to_music")

# ─── Pipeline Config ───────────────────────────────────────────────────────
TOP_DB = 20
MIN_CHUNK_LEN = 2048
VELOCITY_SCALE = 127
SAMPLE_RATE_IN = 22050       # librosa load resample
SAMPLE_RATE_OUT = 44100      # output WAV sample rate
TEMPO_BPM = 120

# ─── Music Fixes (from music_fixes.md) ────────────────────────────────────
# Fix 1: Pentatonic scale — C pentatonic: C D E G A
PENTATONIC = {0, 2, 4, 7, 9}

# Fix 2: Beat grid (eighth-note grid at 90 BPM)
BPM = 90
BEAT_DURATION = 60.0 / BPM
GRID = BEAT_DURATION / 2

# Fix 3: Frequency roles — different instruments per register
ROLE_CONFIG = {
    'bass':    {'channel': 1, 'instrument': 32},   # Acoustic Bass
    'melody':  {'channel': 0, 'instrument': 73},   # Flute
    'texture': {'channel': 2, 'instrument': 98},   # Crystal
}


def snap_to_pentatonic(midi_note):
    octave = midi_note // 12
    pitch_class = midi_note % 12
    nearest = min(PENTATONIC, key=lambda p: abs(p - pitch_class))
    return octave * 12 + nearest


def snap_to_grid(time_sec):
    return round(time_sec / GRID) * GRID


def assign_role(freq):
    if freq < 300:
        return 'bass'
    elif freq < 2000:
        return 'melody'
    else:
        return 'texture'

# ─── App ───────────────────────────────────────────────────────────────────

app = FastAPI(title="Sound to Music Converter", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    return {"status": "ok", "service": "sound-to-music", "endpoints": {"convert": "POST /convert", "health": "GET /health"}}


@app.get("/health")
async def health():
    return {"status": "ok", "service": "sound-to-music"}


@app.post("/convert")
async def convert(file: UploadFile = File(...)):
    """Accept a WAV upload, process through the pipeline, return instrumental WAV."""

    if not file.filename or not file.filename.lower().endswith(('.wav', '.mp3', '.m4a', '.ogg', '.flac')):
        raise HTTPException(400, "Please upload an audio file (.wav, .mp3, .m4a, .ogg, .flac)")

    logger.info("Received: %s (%d bytes)", file.filename, file.size or 0)

    # ── Read uploaded bytes ──────────────────────────────────────────
    audio_bytes = await file.read()
    if len(audio_bytes) < 1024:
        raise HTTPException(400, "File too small or empty")

    # ── Step 1: Load audio ───────────────────────────────────────────
    try:
        y, sr = librosa.load(io.BytesIO(audio_bytes), sr=SAMPLE_RATE_IN)
    except Exception as e:
        raise HTTPException(400, f"Cannot decode audio: {e}")

    duration = len(y) / sr
    logger.info("Loaded: %.2fs @ %d Hz, %d samples", duration, sr, len(y))

    if len(y) < sr:  # less than 1 second
        raise HTTPException(400, "Audio too short (< 1s)")

    # ── Step 2: Detect events ────────────────────────────────────────
    intervals = librosa.effects.split(y, top_db=TOP_DB)
    logger.info("Events detected: %d", len(intervals))

    if len(intervals) == 0:
        raise HTTPException(400, "No distinct sound events detected. Try lowering --top-db or use louder audio.")

    # Filter very short events
    intervals = [(st, en) for st, en in intervals if (en - st) >= MIN_CHUNK_LEN]
    if len(intervals) == 0:
        raise HTTPException(400, "All events too short after filtering")

    # ── Step 3: Map events → MIDI notes ──────────────────────────────
    midi = MIDIFile(3)
    for i in range(3):
        midi.addTempo(i, 0, TEMPO_BPM)
    midi.addProgramChange(0, 0, 0, 73)   # Flute on channel 0
    midi.addProgramChange(1, 1, 0, 32)   # Acoustic Bass on channel 1
    midi.addProgramChange(2, 2, 0, 98)   # Crystal on channel 2

    notes = []  # keep for synthesis
    notes_added = 0

    for start, end in intervals:
        chunk = y[start:end]
        if len(chunk) < MIN_CHUNK_LEN:
            continue

        # Extract dominant pitch
        pitches, magnitudes = librosa.piptrack(y=chunk, sr=sr)
        idx = magnitudes.argmax()
        freq = pitches.flatten()[idx]

        if freq <= 0:
            continue

        note_num = int(69 + 12 * np.log2(freq / 440.0))
        note_num = int(np.clip(note_num, 21, 108))
        note_num = snap_to_pentatonic(note_num)          # Fix 1

        amp = np.max(np.abs(chunk))
        velocity = int(np.clip(amp * VELOCITY_SCALE, 1, VELOCITY_SCALE))

        time_sec = snap_to_grid(start / sr)              # Fix 2
        dur = (end - start) / sr

        role = assign_role(freq)                          # Fix 3
        config = ROLE_CONFIG[role]
        track = {'melody': 0, 'bass': 1, 'texture': 2}[role]

        midi.addNote(track, config['channel'], note_num, time_sec, dur, velocity)

        notes.append({
            "note": note_num,
            "velocity": velocity,
            "start": time_sec,
            "duration": dur,
            "freq": freq,
            "role": role,
        })
        notes_added += 1

    logger.info("MIDI notes generated: %d", notes_added)

    if notes_added == 0:
        raise HTTPException(400, "Could not extract any usable pitches from events")

    # ── Step 4: Synthesize instrumental audio ────────────────────────
    total_sec = max(n["start"] + n["duration"] for n in notes) + 1.0
    num_samples = int(total_sec * SAMPLE_RATE_OUT)
    audio = np.zeros(num_samples, dtype=np.float64)

    for n in notes:
        midi_note = n["note"]
        velocity = n["velocity"]
        start_sec = n["start"]
        duration = n["duration"]

        freq = 440.0 * (2.0 ** ((midi_note - 69) / 12.0))

        start_sample = int(start_sec * SAMPLE_RATE_OUT)
        end_sample = min(start_sample + int(duration * SAMPLE_RATE_OUT), num_samples)
        length = end_sample - start_sample
        if length <= 0:
            continue

        t = np.arange(length) / SAMPLE_RATE_OUT
        amp = (velocity / VELOCITY_SCALE) * 0.3

        # Tone with harmonics
        tone = (
            np.sin(2 * np.pi * freq * t) * 0.6
            + np.sin(2 * np.pi * freq * 2 * t) * 0.25
            + np.sin(2 * np.pi * freq * 3 * t) * 0.1
            + np.sin(2 * np.pi * freq * 4 * t) * 0.05
        )

        # Envelope (attack / release)
        attack_len = min(int(0.01 * SAMPLE_RATE_OUT), length // 4)
        release_len = min(int(0.03 * SAMPLE_RATE_OUT), length // 4)
        envelope = np.ones(length)
        if attack_len > 0:
            envelope[:attack_len] = np.linspace(0, 1, attack_len)
        if release_len > 0:
            envelope[-release_len:] = np.linspace(1, 0, release_len)

        audio[start_sample:end_sample] += tone * envelope * amp

    # Normalize
    max_val = np.max(np.abs(audio))
    if max_val > 0:
        audio = audio / max_val * 0.9

    # ── Return WAV bytes ─────────────────────────────────────────────
    wav_buffer = io.BytesIO()
    sf.write(wav_buffer, audio.astype(np.float32), SAMPLE_RATE_OUT, format="WAV")
    wav_bytes = wav_buffer.getvalue()

    logger.info("Returning: %d bytes of instrumental WAV", len(wav_bytes))

    return Response(
        content=wav_bytes,
        media_type="audio/wav",
        headers={
            "Content-Disposition": f'attachment; filename="{os.path.splitext(file.filename)[0]}_instrumental.wav"',
            "X-Notes-Count": str(notes_added),
            "X-Events-Count": str(len(intervals)),
        },
    )


# ─── Main ──────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    import os
    port = int(os.environ.get("PORT", "8000"))
    print()
    print("=" * 60)
    print("  Sound to Music Server")
    print("=" * 60)
    print("  Endpoints:")
    print("    POST /convert    Upload WAV → get instrumental WAV back")
    print("    GET  /health     Health check")
    print()
    print("  Example:")
    print('    curl -X POST -F "file=@bird.wav" http://localhost:8000/convert -o song.wav')
    print()
    print(f"  Starting server at http://0.0.0.0:{port}")
    print("=" * 60)
    uvicorn.run(app, host="0.0.0.0", port=port)
