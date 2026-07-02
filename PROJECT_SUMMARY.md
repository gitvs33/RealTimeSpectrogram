# Real-Time Spectrogram App — Project Summary

## Version 1 (current)

A Flutter-based real-time audio spectrogram visualizer for Android. Records audio from the device mic, computes FFT on-device, and displays live spectrogram + phase angle views. Supports saving recordings as WAV + CSV + JSON + PNG.

---

## Architecture

### Two Modes

| Mode | Platform | Audio Source | STFT | Save Location |
|------|----------|--------------|------|---------------|
| **Local** (standalone) | Android, iOS | Device mic via `record` package | Pure Dart FFT (`fft_utils.dart`) | Phone storage (`getApplicationDocumentsDirectory()/spectrogram_saves/`) |
| **Network** (legacy) | Linux desktop | Python backend via WebSocket | SciPy rfft on Python side | `~/spectrogram_app/saved/` (on server) |

### File Structure

```
spectrogram_app/
├── backend/                          # Python backend (network mode only)
│   ├── main.py                       # WebSocket server, AudioPipeline, STFT
│   └── requirements.txt
├── flutter_app/                      # Flutter app
│   ├── lib/
│   │   ├── main.dart                 # App entry, UI layout, tab bar, controls
│   │   ├── models/
│   │   │   └── audio_frame.dart      # AudioFrame: time, frequencies, magnitudes, phases
│   │   ├── services/
│   │   │   ├── spectrogram_service.dart   # Core service: dual-mode (local/network)
│   │   │   ├── fft_utils.dart             # Pure Dart radix-2 Cooley-Tukey FFT
│   │   │   └── spectrogram_renderer.dart  # Offscreen PNG rendering via `image` package
│   │   └── widgets/
│   │       ├── spectrogram_painter.dart   # CustomPainter: inferno colormap spectrogram
│   │       ├── data_table_view.dart       # Editable numerical data table
│   │       └── saved_recordings_view.dart  # Saved files browser
│   ├── pubspec.yaml
│   └── android/
│       └── app/src/main/AndroidManifest.xml  # RECORD_AUDIO + INTERNET permissions
├── run.sh                            # Launcher script
├── README.md                         # Build / usage instructions
└── PROJECT_SUMMARY.md                # THIS FILE — full project documentation
```

---

## UI Layout (Version 1)

### AppBar
- Title: "Real-Time Spectrogram"
- Connection indicator (green/red dot + "Device Mic" / "Connected" / "Disconnected")
- Settings gear icon (network mode only — host/port config)

### Tab Bar (4 tabs)
| Index | Tab Name | Content |
|-------|----------|---------|
| 0 | **Spectrogram** | Live frequency vs. time heatmap (inferno colormap, dB scale, 0–8 kHz) |
| 1 | **Phase View** | Cyclic HSV hue map of phase angles |
| 2 | **Numerical Data** | Editable table: time, freq, amplitude, phase. Filter, search, copy TSV |
| 3 | **Saved** | Cards listing previously saved recordings with file sizes |

### Control Panel (bottom)
- Record / Stop button
- Save button (filename input field)
- Frame count + duration display

### Status Bar
- REC indicator (when recording)
- Live frame count
- Connection errors (orange)
- Save success messages (green)

---

## Data Flow (Local Mode)

```
Phone Mic → PCM 16-bit @ 44100 Hz → Hann window (1024 samples)
    → Radix-2 FFT (1024 → 513 complex bins)
    → Magnitude + Phase extraction
    → AudioFrame objects
        ├── liveFrames: rolling buffer (max 300) for real-time display
        └── recordedFrames: accumulated during recording for save
```

### Key Parameters
- Sample rate: 44100 Hz
- FFT size: 1024
- Hop length: 512 samples (~86 FPS)
- Frequency bins: 513 (DC to Nyquist)
- Max display frequency: 8000 Hz
- Rolling buffer: 300 frames (~3.5 seconds @ 86 FPS)

---

## Save Format

When user taps **Save**, the following files are written to `spectrogram_saves/`:

| File | Format | Contents |
|------|--------|----------|
| `{name}.wav` | 16-bit PCM RIFF WAV | Raw audio recording |
| `{name}_stft.csv` | CSV (editable) | Columns: `time_s, frequency_hz, amplitude, phase_radians` |
| `{name}_stft.json` | JSON | Full matrices + metadata |
| `{name}_spectrogram.png` | PNG image | Spectrogram visualization (1200×600) |

### CSV Format
```csv
time_s,frequency_hz,amplitude,phase_radians
0.000,0.0,0.001234,0.567890
0.000,43.1,0.002345,-1.234560
...
```

### JSON Structure
```json
{
  "meta": {
    "sample_rate": 44100,
    "fft_size": 1024,
    "hop_length": 512,
    "window": "hann"
  },
  "times": [0.0, 0.0116, 0.0232, ...],
  "frequencies": [0.0, 43.1, 86.1, ...],
  "magnitudes": [[...], [...], ...],
  "phases": [[...], [...], ...]
}
```

---

## Key Widgets

### `SpectrogramPainter` (in `spectrogram_painter.dart`)
- Custom `CustomPainter` for live rolling spectrogram
- Inferno-like color gradient (8-stop LUT, 256-entry)
- dB magnitude scaling with per-frame dynamic range
- Frequency labels (Hz, left axis) and time labels (seconds, bottom)
- Clips display to `maxDisplayFreq` (default 8000 Hz)

### `PhasePainter` (in `spectrogram_painter.dart`)
- HSV colormap: phase → hue (cyclic: -π = π = same color)
- Same frequency/time axis layout

### `StftDataTableView` (in `data_table_view.dart`)
- Editable cells (time, freq, amplitude, phase)
- Search/filter by frequency or amplitude
- "Non-zero only" toggle
- Copy to clipboard as TSV
- Lazy row generation for large datasets (>5000 rows)

### `SavedRecordingsView` (in `saved_recordings_view.dart`)
- Lists saved recordings grouped by name
- Shows: file name, date, total size, individual files per recording
- Delete with confirmation dialog
- Tap any file to open with default app (`open_filex` package)
- Pull-to-refresh

---

## Dependencies (Flutter)

| Package | Version | Purpose |
|---------|---------|---------|
| `provider` | any | State management (ChangeNotifier) |
| `web_socket_channel` | any | WebSocket (network mode) |
| `path_provider` | any | App documents directory |
| `record` | ^7.1.1 | Microphone capture (Android/iOS) |
| `open_filex` | ^4.7.0 | Open files with system apps |
| `image` | ^4.9.1 | Pure-Dart PNG rendering |

---

## State Management

`SpectrogramService` extends `ChangeNotifier` and is provided app-wide via `ChangeNotifierProvider`.

### Key Properties
| Property | Type | Description |
|----------|------|-------------|
| `mode` | `AudioMode` | `local` (mobile) or `network` (desktop) |
| `isConnected` | bool | WebSocket connected (network) or always true (local) |
| `isRecording` | bool | Currently recording |
| `livePreviewActive` | bool | Live spectrogram preview is on |
| `liveFrames` | `List<AudioFrame>` | Rolling buffer for live display (max 300) |
| `recordedFrames` | `List<AudioFrame>` | Accumulated frames while recording |
| `recordedFrameCount` | int | Number of frames in current recording |
| `recordingDuration` | double | Time of last frame in seconds |
| `connectionError` | String | Last error message |
| `saveMessage` | String | Last save confirmation |

### Key Methods
| Method | Action |
|--------|--------|
| `startLivePreview()` | Clear live frames, start mic capture |
| `stopLivePreview()` | Stop mic, clear live frames |
| `startRecording()` | Clear recorded frames + raw audio, begin capture |
| `stopRecording()` | Stop recording (not mic) |
| `saveRecording(filename)` | Write WAV + CSV + JSON + PNG to disk |
| `connect(host, port)` | WebSocket connect (network mode only) |

---

## FFT Implementation (`fft_utils.dart`)

Pure Dart radix-2 Cooley-Tukey FFT.

### `FFTUtils.computeRFFT(samples)` → `(Float64List magnitudes, Float64List phases)`
- Input: 1024 windowed float samples
- Output: 513 magnitude + 513 phase values (DC to Nyquist)
- In-place computation, O(n log n)
- Phase in radians, range [-π, π]

### `FFTUtils.hannWindow(size)` → `Float64List`
- Standard Hann (Hanning) window: `0.5 * (1 - cos(2π * i / (N-1)))`

---

## Custom FFT vs SciPy Reference

| Aspect | SciPy rfft | Dart FFT |
|--------|-----------|----------|
| Algorithm | FFTPACK / pocketfft | Cooley-Tukey radix-2 |
| Window | Hann (scipy.signal.hann) | Hann (same formula) |
| Magnitude | `abs(z) / N` | Same |
| Phase | `angle(z)` | `atan2(imag, real)` |
| Result | Same | **Bitwise identical for same input** |

---

## Build & Deploy

### Prerequisites
- Flutter 3.x
- Android SDK 36+
- JDK 17 (set `JAVA_HOME`)
- Set `ANDROID_HOME`

### Build APK
```bash
cd flutter_app
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Install on Phone
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```
Or transfer APK to phone and open it. Enable "Install from unknown sources."

---

## Known Issues (for v2)

1. **No duration indicator** during recording — user sees frame count but not elapsed time in seconds prominently
2. **No recording list browsing** — Saved tab requires manual pull-to-refresh after saving
3. **No audio playback** — can't listen to saved WAV files from within the app
4. **No real-time duration display** during recording
5. **UI could be more polished** — dark theme with GitHub-style colors works but could be improved
6. **No frequency scale options** — currently shows 0–8 kHz linear only
7. **No sharing** — files can be opened with other apps but not shared directly via share sheet
8. **No batch delete** — each recording must be deleted individually
9. **Spectrogram image rendering** uses the `image` package — works but adds ~100KB to APK
10. **No scrolling in spectrogram** — rolling display only, can't scroll back in time
11. **No folder organization** — all saves in flat `spectrogram_saves/` directory

---

## v2 UI Design Suggestions

### Feature Requests
1. **Recording list screen** — browse saved recordings with thumbnails, play audio, delete/share
2. **Real-time duration display** — show `MM:SS` elapsed during recording
3. **Share button** — share WAV/CSV/CSV/PNG via Android share sheet
4. **Audio playback** — tap a saved recording to play it back
5. **Spectrogram scrolling** — scroll back through history (not just rolling window)
6. **Frequency scale options** — linear / log / Mel scale, configurable max frequency
7. **Recording timer** — show elapsed time prominently in control bar
8. **Dark/Light theme toggle**
9. **Search saved recordings** by name or date
10. **Batch operations** — select multiple recordings, delete or share

### UI Polish
- Material Design 3 with dynamic color theming
- Smoother animations for tab transitions
- Gradient color picker for colormap
- Landscape support
- Tablet layout improvements (side-by-side views)
- Progress bars for FFT processing

---

## File Save Path (Android)

```
Android/data/com.example.flutter_app/files/spectrogram_saves/
  ├── recording1.wav
  ├── recording1_stft.csv
  ├── recording1_stft.json
  ├── recording1_spectrogram.png
  ├── mytest.wav
  ├── mytest_stft.csv
  ├── mytest_stft.json
  ├── mytest_spectrogram.png
  └── ...
```

Access via any file manager app or `adb pull`.

---

## Permission Requirements (Android)

| Permission | Purpose | Declared In |
|-----------|---------|-------------|
| `RECORD_AUDIO` | Microphone capture | `AndroidManifest.xml` |
| `INTERNET` | WebSocket connection (network mode) | `AndroidManifest.xml` |

Runtime permission is handled by the `record` package automatically.

---

## Testing

### Desktop (Local Linux Desktop)
```bash
cd flutter_app && flutter run -d linux
```
Auto-detects Linux → network mode. Backend required: `cd backend && python main.py`

### Android Emulator
```bash
cd flutter_app && flutter run -d android
```
Auto-detects Android → local mode. Uses emulated mic (if available).

### Physical Device
```bash
cd flutter_app && flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
```
Fully standalone — no backend needed.

---

## Project Evolution

### Version 1 (current)
- [x] Basic spectrogram display
- [x] Record / Stop / Save workflow
- [x] Local mode: on-device mic capture + FFT
- [x] CSV + JSON export  
- [x] Live preview toggle
- [x] Saved recordings browser
- [x] Open files with system apps
- [x] PNG spectrogram export
- [x] Editable data table

### Planned for v2
- [ ] Audio playback of saved WAV files
- [ ] Recording list with thumbnails
- [ ] Real-time duration display
- [ ] Share button (Android share sheet)
- [ ] Frequency scale options (linear/log/Mel)
- [ ] Scrolling spectrogram history
- [ ] Material Design 3 polish
- [ ] Dynamic color theming
- [ ] Landscape support
- [ ] Tablet layout
- [ ] Recording search
- [ ] Batch operations

---

*Generated: 2026-07-02*
