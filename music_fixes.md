# Three Fixes To Make Environment Sound Actually Musical

The current system maps environment sounds to random notes played sequentially.
These three changes — scale, rhythm, frequency roles — fix that without needing AI.

---

## Fix 1 — Pentatonic Scale

### The Problem
Right now any frequency maps to any of 88 MIDI notes. Notes have no harmonic
relationship to each other. That's why it sounds random.

### The Fix
Snap every note to the nearest pentatonic scale note. Pentatonic has 5 notes
per octave and they all sound good together by nature.

```python
# C pentatonic: C D E G A
PENTATONIC = {0, 2, 4, 7, 9}

def snap_to_pentatonic(midi_note):
    octave = midi_note // 12
    pitch_class = midi_note % 12
    nearest = min(PENTATONIC, key=lambda p: abs(p - pitch_class))
    return octave * 12 + nearest
```

### Where To Add It
In `sound_to_music_server.py`, inside the event loop, after calculating `note_num`:

```python
note_num = int(69 + 12 * np.log2(freq / 440.0))
note_num = int(np.clip(note_num, 21, 108))
note_num = snap_to_pentatonic(note_num)  # ADD THIS LINE
```

---

## Fix 2 — Snap Events To A Beat Grid

### The Problem
Events play at their exact recorded timestamps — 1.34s, 2.87s, 4.21s.
No musical pulse. Notes feel unrelated in time.

### The Fix
Round each event's start time to the nearest eighth note on a beat grid.

```python
BPM = 90
BEAT_DURATION = 60.0 / BPM   # seconds per beat = 0.667s
GRID = BEAT_DURATION / 2      # eighth note grid = 0.333s

def snap_to_grid(time_sec):
    return round(time_sec / GRID) * GRID
```

### Where To Add It
In the event loop, when calculating `time_sec`:

```python
time_sec = start / sr
time_sec = snap_to_grid(time_sec)  # ADD THIS LINE
```

---

## Fix 3 — Frequency Roles

### The Problem
Every event becomes a melody note regardless of whether it's a low rumble,
a mid-range bird call, or a high frequency texture. Everything sounds the same.

### The Fix
Split events by frequency into three roles. Each role gets a different
instrument and MIDI channel.

```python
def assign_role(freq):
    if freq < 300:
        return 'bass'      # wind, rumbles, low sounds
    elif freq < 2000:
        return 'melody'    # bird calls, voices, mid sounds
    else:
        return 'texture'   # high frequencies, air, detail

ROLE_CONFIG = {
    'bass':    {'channel': 1, 'instrument': 32},  # Acoustic Bass
    'melody':  {'channel': 0, 'instrument': 73},  # Flute
    'texture': {'channel': 2, 'instrument': 98},  # Crystal
}
```

### Where To Add It
In `sound_to_music_server.py`, update MIDIFile to 3 tracks:

```python
midi = MIDIFile(3)
midi.addTempo(0, 0, TEMPO_BPM)
midi.addTempo(1, 0, TEMPO_BPM)
midi.addTempo(2, 0, TEMPO_BPM)

# Add program changes for each channel
midi.addProgramChange(0, 0, 0, 73)   # Flute on channel 0
midi.addProgramChange(1, 1, 0, 32)   # Bass on channel 1
midi.addProgramChange(2, 2, 0, 98)   # Crystal on channel 2
```

Then in the event loop:

```python
role = assign_role(freq)
config = ROLE_CONFIG[role]
track = {'melody': 0, 'bass': 1, 'texture': 2}[role]

midi.addNote(track, config['channel'], note_num, time_sec, dur, velocity)
```

---

## All Three Together — Full Updated Event Loop

Replace the existing event loop in `sound_to_music_server.py` with this:

```python
# Constants at top of file
PENTATONIC = {0, 2, 4, 7, 9}
BPM = 90
BEAT_DURATION = 60.0 / BPM
GRID = BEAT_DURATION / 2

ROLE_CONFIG = {
    'bass':    {'channel': 1, 'instrument': 32},
    'melody':  {'channel': 0, 'instrument': 73},
    'texture': {'channel': 2, 'instrument': 98},
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

# MIDI setup
midi = MIDIFile(3)
for i in range(3):
    midi.addTempo(i, 0, TEMPO_BPM)
midi.addProgramChange(0, 0, 0, 73)
midi.addProgramChange(1, 1, 0, 32)
midi.addProgramChange(2, 2, 0, 98)

notes = []

for start, end in intervals:
    chunk = y[start:end]
    if len(chunk) < MIN_CHUNK_LEN:
        continue

    pitches, magnitudes = librosa.piptrack(y=chunk, sr=sr)
    idx = magnitudes.argmax()
    freq = pitches.flatten()[idx]

    if freq <= 0:
        continue

    note_num = int(69 + 12 * np.log2(freq / 440.0))
    note_num = int(np.clip(note_num, 21, 108))
    note_num = snap_to_pentatonic(note_num)      # Fix 1

    time_sec = snap_to_grid(start / sr)          # Fix 2

    role = assign_role(freq)                      # Fix 3
    config = ROLE_CONFIG[role]
    track = {'melody': 0, 'bass': 1, 'texture': 2}[role]

    amp = np.max(np.abs(chunk))
    velocity = int(np.clip(amp * VELOCITY_SCALE, 1, VELOCITY_SCALE))
    dur = (end - start) / sr

    midi.addNote(track, config['channel'], note_num, time_sec, dur, velocity)
    notes.append({
        'note': note_num,
        'velocity': velocity,
        'start': time_sec,
        'duration': dur,
        'freq': freq,
        'role': role,
    })
    notes_added += 1
```

---

## What These Fixes Actually Change

| Before | After |
|--------|-------|
| Random notes, no harmonic relationship | All notes belong to same pentatonic family |
| Events at exact recorded timestamps | Events snap to musical pulse |
| Every sound = melody note | Low = bass, mid = melody, high = texture |
| One instrument, one channel | Three instruments, three channels |

---

## What These Fixes Do Not Solve

Being honest — these fixes make it more musical but not fully musical. What's
still missing:

- **Tension and resolution** — notes building toward something
- **Dynamic variation** — quiet sections and loud sections
- **Repetition and pattern** — music repeats motifs, this system doesn't

Those require either more creative rules or eventually a learning component.
But fix these three first and listen to the difference before going further.
