# Real-Time Spectrogram App

A real-time audio spectrogram visualizer that runs **fully on your phone** — no backend server needed on mobile.

Captures audio from the device mic, computes FFT in real time using Dart, and displays live spectrogram + phase angle views. Recordings are saved locally as WAV + editable CSV/JSON.

## Features

- **Real-time spectrogram** — frequency vs. time heatmap (dB magnitude)
- **Phase angle view** — cyclic hue colormap of phase angles
- **Recording** — start/stop to capture audio segments
- **Save locally** — exports WAV + editable CSV (time, freq, amplitude, phase) + JSON matrices
- **Editable numerical data** — table with inline editing, filtering, copy-to-clipboard
- **Pure mobile mode** — no backend required on Android

## Quick Start

### Android (mobile — standalone)

```bash
cd flutter_app
flutter build apk --release
```

Install the APK at `build/app/outputs/flutter-apk/app-release.apk` on your phone.

Or with a device connected via USB:

```bash
flutter run -d android
```

The app auto-detects it's on mobile and uses the phone's mic directly. Just open the app, tap **Start Preview**, and you'll see the spectrogram.

### Desktop (with Python backend)

The legacy desktop mode connects to a Python backend via WebSocket for audio capture + STFT.

```bash
# Terminal 1: Start Python backend
cd backend
pip install -r requirements.txt
python main.py

# Terminal 2: Start Flutter app
cd flutter_app
flutter run -d linux
```

## Usage

1. **Open the app** — you'll see a blank screen with a **Start Preview** button
2. **Tap Start Preview** — the live spectrogram appears (phone mic activates)
3. **Tap Record** — begins capturing audio (frames accumulate for save)
4. **Watch** the live spectrogram and phase view update in real time
5. **Tap Stop** — recording ends
6. **Type a filename** and tap **Save** — exports WAV + CSV + JSON to the device

Switch to the **Numerical Data** tab to browse, filter, and edit the STFT values.

## Architecture

### Mobile (standalone)

```
┌─────────────────────────────────────────────┐
│  SpectrogramService (AudioMode.local)        │
│                                              │
│  Device Mic ──► PCM 16-bit ──► Hann Window   │
│       │                                      │
│       ▼                                      │
│  FFT (pure Dart, radix-2 Cooley-Tukey)       │
│       │                                      │
│       ▼                                      │
│  AudioFrame (magnitudes + phases)            │
│       │                                      │
│       ├──► SpectrogramPainter (live view)    │
│       ├──► PhasePainter (live view)          │
│       └──► StftDataTableView (data table)    │
│                                              │
│  Save: WAV + CSV + JSON → device storage     │
└─────────────────────────────────────────────┘
```

### Desktop (legacy — with Python backend)

```
Python Backend                     Flutter Frontend
┌─────────────────────┐           ┌──────────────┐
│ Mic → STFT (SciPy) │ WebSocket │ Spectrograms  │
│ → frame queue      ├─────────► │ Phase views   │
│ → save WAV/CSV/JSON│  frames   │ Data table    │
└─────────────────────┘           └──────────────┘
```

## Save Format

Files are saved to `Android/data/com.example.flutter_app/files/spectrogram_saves/` on mobile (or `~/spectrogram_app/saved/` on desktop backend).

| File | Format | Contents |
|------|--------|----------|
| `recording.wav` | 16-bit PCM WAV | Raw audio |
| `recording_stft.csv` | CSV (editable) | Columns: `time_s`, `frequency_hz`, `amplitude`, `phase_radians` |
| `recording_stft.json` | JSON | Full matrices: `times`, `frequencies`, `magnitudes`, `phases` + metadata |

## Building from Source

### Prerequisites

- **Flutter 3.x** ([install guide](https://docs.flutter.dev/get-started/install))
- **Android SDK** (API 36+) — set `ANDROID_HOME` environment variable
- **Java 17 JDK** — set `JAVA_HOME`

### One-time setup

```bash
# Clone the repo
git clone https://github.com/gitvs33/RealTimeSpectrogram.git
cd RealTimeSpectrogram

# Get Flutter dependencies
cd flutter_app
flutter pub get
cd ..

# Build APK
cd flutter_app
export JAVA_HOME=/path/to/jdk17
export ANDROID_HOME=/path/to/android-sdk
flutter build apk --release
```

The APK is at `flutter_app/build/app/outputs/flutter-apk/app-release.apk`.

## Configuration (Desktop Backend Only)

Edit `backend/main.py` to change:
- `SAMPLE_RATE` — sample rate (default: 44100 Hz)
- `FFT_SIZE` — FFT window size (default: 1024)
- `HOP_LENGTH` — samples between frames (default: 512)
- `WEBSOCKET_PORT` — WebSocket port (default: 8765)

## Requirements

| Component | Mobile | Desktop |
|-----------|--------|---------|
| **Flutter** | 3.x + Android SDK 36 | 3.x + Linux toolchain |
| **Python** | not needed | 3.10+ with numpy, scipy, pyaudio, websockets |
| **JDK** | 17 | not needed |
