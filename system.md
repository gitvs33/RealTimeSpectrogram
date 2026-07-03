# Sound to Music — Python Backend System

This directory contains the Python backend for the **Once** spectrogram app.
Three scripts serve different purposes, all built on free open-source libraries.

---

## Files

| File | Purpose |
|------|---------|
| `sound_to_music_server.py` | **FastAPI web server** — deployed to Render. Flutter app sends WAVs here, gets back instrumental music. |
| `test_sound_to_midi.py` | **Standalone test script** — run locally on any audio file to test the pipeline end-to-end. |
| `main.py` | **Legacy spectrogram WebSocket server** — streams live audio frames to desktop Flutter app (not needed on mobile). |
| `requirements.txt` | All Python dependencies. |
| `runtime.txt` | Pins Python version for Render deployment. |
| `Procfile` | Render start command. |

---

## Pipeline (shared by all three scripts)

```
Audio File (WAV/MP3)
    │
    ▼
┌─────────────────────────────┐
│  1. LOAD & RESAMPLE         │  librosa.load(…, sr=22050)
│     Convert to mono float32 │
└─────────────────────────────┘
    │
    ▼
┌─────────────────────────────┐
│  2. EVENT DETECTION         │  librosa.effects.split(y, top_db=20)
│     Find non-silent regions │  Returns a list of [start, end] intervals
│     Count = "how many       │
│     events"                 │
└─────────────────────────────┘
    │
    ▼
┌─────────────────────────────┐
│  3. PITCH → MIDI NOTES      │  librosa.piptrack() extracts dominant freq
│     Each event becomes one  │  freq → MIDI note number (21-108)
│     MIDI note with velocity │  midiutil.MIDIFile writes .mid in memory
│     derived from amplitude  │
└─────────────────────────────┘
    │
    ▼
┌─────────────────────────────┐
│  4. INSTRUMENTAL SYNTHESIS  │  Pure-Python numpy synthesizer
│     Sine waves + harmonics  │  Attack/release envelope per note
│     No FluidSynth needed    │  soundfile writes final WAV
└─────────────────────────────┘
    │
    ▼
Instrumental WAV
```

---

## `sound_to_music_server.py` — Deployed Server

**Endpoint:** `https://realtimespectrogram.onrender.com`

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Root health check. Returns `{"status": "ok", ...}` |
| `GET` | `/health` | Health check. Returns `{"status": "ok"}` |
| `POST` | `/convert` | **Upload a WAV → download instrumental WAV.** Accepts multipart form with field `file`. |

### `POST /convert` details

**Request:** `multipart/form-data` with field `file` containing an audio file (WAV, MP3, M4A, OGG, FLAC).

**Response:** `audio/wav` binary with headers:
- `Content-Disposition`: filename includes `_instrumental.wav`
- `X-Events-Count`: number of sound events detected
- `X-Notes-Count`: number of MIDI notes generated

**Errors:** Returns 400 with explanatory text for:
- Unsupported file type
- File too small or empty
- Audio too short (< 1 second)
- No distinct sound events detected
- All events too short after filtering
- Could not extract usable pitches

### Configuration

Settings hardcoded at the top of the file:

| Variable | Default | Description |
|----------|---------|-------------|
| `TOP_DB` | 20 | Silence threshold for event detection (lower = more sensitive) |
| `MIN_CHUNK_LEN` | 2048 samples | Minimum event duration; shorter events are skipped |
| `SAMPLE_RATE_IN` | 22050 Hz | Audio is resampled to this for processing |
| `SAMPLE_RATE_OUT` | 44100 Hz | Output WAV sample rate |
| `TEMPO_BPM` | 120 | MIDI tempo |
| `INSTRUMENT` | 0 | General MIDI program number (0 = Acoustic Grand Piano) |

### General MIDI Instrument Map (for `INSTRUMENT`)

```
  0  Acoustic Grand Piano    40  Violin                80  Lead 1 (Square)
  8  Celesta                 56  Trumpet              100  FX 6 (Echoes)
 16  Hammond Organ           64  Soprano Sax           112  Tinkle Bell
 24  Acoustic Guitar (nylon) 72  Clarinet              120  Bird Tweet
 32  Acoustic Bass           73  Flute                 123  Seashore
 33  Electric Bass (finger)  74  Recorder              127  Gunshot
```

Full list available via `python3 test_sound_to_midi.py --list-instruments`.

---

## `test_sound_to_midi.py` — Standalone Test Script

Run locally to test the pipeline on any audio file without a server.

### Usage

```bash
python3 test_sound_to_midi.py                           # uses bird.mp3 (ships with test)
python3 test_sound_to_midi.py path/to/audio.wav         # custom file
python3 test_sound_to_midi.py --instrument 73           # Flute instead of Piano
python3 test_sound_to_midi.py --top-db 15               # more sensitive detection
python3 test_sound_to_midi.py --tempo 140               # faster tempo
python3 test_sound_to_midi.py --list-instruments        # show all 128 MIDI programs
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--instrument` / `-i` | 0 (Piano) | General MIDI instrument number |
| `--top-db` | 20 | Silence threshold (lower = more events detected) |
| `--tempo` | 120 | MIDI tempo in BPM |
| `--list-instruments` | — | Print all MIDI instrument names and exit |

### Output

The script creates an `output/` directory next to the input file containing:
- `{filename}_events.mid` — MIDI file
- `{filename}_instrumental.wav` — Rendered instrumental audio

---

## `main.py` — Legacy Spectrogram Server (Desktop Only)

This was the original Python backend for the desktop Flutter app. It:

- Captures live audio from the microphone via **PyAudio**
- Computes STFT in real-time using **SciPy**
- Streams audio frame data over **WebSocket** on port `8765`
- Saves recordings as WAV + editable CSV/JSON on request

**Not needed on mobile.** The mobile Flutter app does all audio capture and FFT computation on-device in pure Dart.

---

## Deployment

The server `sound_to_music_server.py` is designed to run on **Render** (or any hosting platform).

### Render

1. Connect GitHub repo to Render
2. Create a **Web Service**
3. Settings:
   - **Root Directory:** `backend`
   - **Build Command:** `pip install -r requirements.txt`
   - **Start Command:** `python sound_to_music_server.py`
4. Render auto-sets the `PORT` environment variable (server reads `$PORT`)

### Local

```bash
cd backend
pip install -r requirements.txt
python sound_to_music_server.py
# → http://localhost:8000
```

### Test

```bash
curl -X POST -F "file=@test.wav" http://localhost:8000/convert -o instrumental.wav
```

---

## Dependencies (`requirements.txt`)

| Package | Purpose |
|---------|---------|
| `numpy` | Array math, FFT, tone synthesis |
| `scipy` | Signal processing (legacy `main.py` only) |
| `librosa` | Audio loading, event detection, pitch extraction |
| `midiutil` | MIDI file creation in memory |
| `soundfile` | WAV file I/O |
| `fastapi` | REST API framework |
| `uvicorn` | ASGI server |
| `python-multipart` | File upload parsing for FastAPI |

---

## FAQ

**Q: Why not use FluidSynth for better sound quality?**  
FluidSynth requires system-level installation (`apt install fluidsynth`) and a SoundFont file — not available on Render or without sudo. The pure-Python synthesizer (sine waves with harmonics + envelopes) works everywhere with zero external dependencies.

**Q: How does event detection work?**  
`librosa.effects.split()` looks for non-silent regions by comparing the RMS energy of each frame against a threshold derived from `top_db`. Frames below the threshold are silence; contiguous non-silent frames form an "event."

**Q: Why 22050 Hz sample rate for processing?**  
Lower sample rate = faster processing. 22050 Hz captures frequencies up to ~11 kHz, which covers the fundamental and harmonics of most musical instruments.

**Q: How are pitch and MIDI note mapped?**  
`librosa.piptrack()` computes a spectrogram and finds the frequency bin with the highest energy. That frequency is converted to a MIDI note number using the standard formula: `note = 69 + 12 * log2(freq / 440)`. The result is clamped to the valid MIDI range (21–108).
