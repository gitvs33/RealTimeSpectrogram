#!/usr/bin/env python3
"""
Real-time Spectrogram Backend
Captures audio via PyAudio, computes STFT via SciPy, streams via WebSocket.
Saves WAV + editable CSV/JSON with frequency, amplitude, and phase data.
"""

import asyncio
import json
import threading
import queue
import time
import os
import csv
from abc import ABC, abstractmethod
import numpy as np
import pyaudio
import websockets
from scipy.signal import get_window
import wave

# ═══════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════
SAMPLE_RATE = 44100
CHUNK_SIZE = 1024       # samples per audio chunk
FFT_SIZE = 1024         # FFT window size (N)
HOP_LENGTH = 512        # samples between successive frames
WINDOW_TYPE = 'hann'    # window function
CHANNELS = 1
FORMAT = pyaudio.paFloat32
WEBSOCKET_PORT = 8765

_ADVANCE = HOP_LENGTH / SAMPLE_RATE  # seconds per STFT frame (~11.6 ms)


# ═══════════════════════════════════════════════════
# Audio Source (Port) — injectable seam
# ═══════════════════════════════════════════════════

class AudioSource(ABC):
    """Adapter interface for raw audio input.

    Two implementations: MicrophoneSource (live mic via PyAudio) and
    SyntheticSource (chirp generator for demo/testing).
    """
    @abstractmethod
    def read_chunk(self) -> np.ndarray:
        """Return one chunk of audio (CHUNK_SIZE float32 samples)."""
        ...

    @abstractmethod
    def close(self) -> None:
        """Release any resources held by this source."""
        ...


class MicrophoneSource(AudioSource):
    """Live microphone input via PyAudio."""

    def __init__(self):
        self._p = pyaudio.PyAudio()
        self._stream = self._p.open(
            format=FORMAT,
            channels=CHANNELS,
            rate=SAMPLE_RATE,
            input=True,
            frames_per_buffer=CHUNK_SIZE,
        )

    def read_chunk(self) -> np.ndarray:
        raw = self._stream.read(CHUNK_SIZE, exception_on_overflow=False)
        return np.frombuffer(raw, dtype=np.float32)

    def close(self) -> None:
        self._stream.stop_stream()
        self._stream.close()
        self._p.terminate()


class SyntheticSource(AudioSource):
    """Synthetic chirp generator for demo / offline testing."""

    def __init__(self):
        self._elapsed = 0.0

    def read_chunk(self) -> np.ndarray:
        tt = np.arange(CHUNK_SIZE, dtype=np.float32) / SAMPLE_RATE
        t0 = self._elapsed
        self._elapsed += CHUNK_SIZE / SAMPLE_RATE

        # Frequency sweep 200 → 2000 → 200 Hz
        freq = 200 + 900 * (1 + np.sin(2 * np.pi * 0.5 * (t0 + tt)))
        signal = (
            0.3 * np.sin(2 * np.pi * freq * tt)
            + 0.1 * np.sin(2 * np.pi * freq * 2 * tt)
            + 0.05 * np.sin(2 * np.pi * freq * 3 * tt)
            + 0.02 * np.random.randn(CHUNK_SIZE).astype(np.float32)
        )
        return signal

    def close(self) -> None:
        pass


def create_audio_source() -> AudioSource:
    """Try microphone; fall back to synthetic with a warning."""
    try:
        return MicrophoneSource()
    except Exception as e:
        print(f"[audio] Failed to open audio stream: {e}")
        print("[audio] Running in demo mode — sending synthetic frames.")
        return SyntheticSource()


# ═══════════════════════════════════════════════════
# Audio Pipeline — encapsulates capture, STFT, recording
# ═══════════════════════════════════════════════════

class AudioPipeline:
    """Thread-safe pipeline: audio source → STFT → frame queue + recording buffers.

    Owns the capture thread, the audio source, and all recording state.
    Callers interact through a narrow interface — no exposed fields, no manual
    lock management.
    """

    def __init__(self, source: AudioSource):
        self._source = source
        self._lock = threading.Lock()
        self._running = False
        self._is_recording = False
        self._recorded_audio: list[np.ndarray] = []
        self._recorded_stft: list[dict] = []
        self._frame_queue: queue.Queue = queue.Queue(maxsize=120)
        self._window = get_window(WINDOW_TYPE, FFT_SIZE)
        self._thread: threading.Thread | None = None
        self._frame_counter = 0  # monotonic frame index for time computation

    # ── Public interface ──

    @property
    def frame_queue(self) -> queue.Queue:
        """Live frames for the async broadcaster to consume."""
        return self._frame_queue

    @property
    def running(self) -> bool:
        return self._running

    @property
    def is_recording(self) -> bool:
        with self._lock:
            return self._is_recording

    def start(self) -> None:
        """Launch the audio capture thread."""
        self._running = True
        self._thread = threading.Thread(target=self._capture_loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        """Signal shutdown and wait for the capture thread."""
        self._running = False
        if self._thread:
            self._thread.join(timeout=2.0)
        self._source.close()

    def start_recording(self) -> None:
        """Clear buffers and begin accumulating frames."""
        with self._lock:
            self._recorded_audio.clear()
            self._recorded_stft.clear()
            self._is_recording = True
            self._frame_counter = 0

    def stop_recording(self) -> tuple[int, float]:
        """Stop accumulating and return (frame_count, duration_seconds)."""
        with self._lock:
            self._is_recording = False
            count = len(self._recorded_stft)
            duration = count * _ADVANCE
        return count, duration

    def recording_info(self) -> dict:
        """Lightweight status: (is_recording, frame_count, duration).

        No data copy — safe to call frequently.
        """
        with self._lock:
            count = len(self._recorded_stft)
            return {
                'is_recording': self._is_recording,
                'frames': count,
                'duration': count * _ADVANCE,
            }

    def get_recording_data(self) -> dict | None:
        """Thread-safe deep copy of recorded data for save / full_data."""
        with self._lock:
            if not self._recorded_stft:
                return None
            return {
                'audio': np.concatenate(self._recorded_audio),
                'stft': [dict(f) for f in self._recorded_stft],  # deep copy
                'sample_rate': SAMPLE_RATE,
                'channels': CHANNELS,
            }

    # ── Internal ──

    def _compute_frame(self, chunk: np.ndarray, t: float) -> dict:
        """Apply window, run RFFT, return frame dict."""
        if len(chunk) < FFT_SIZE:
            chunk = np.pad(chunk, (0, FFT_SIZE - len(chunk)))
        windowed = chunk[:FFT_SIZE] * self._window
        fft_result = np.fft.rfft(windowed)
        return {
            'time': t,
            'frequencies': np.fft.rfftfreq(FFT_SIZE, 1.0 / SAMPLE_RATE).tolist(),
            'magnitudes': np.abs(fft_result).tolist(),
            'phases': np.angle(fft_result).tolist(),
        }

    def _capture_loop(self) -> None:
        """Main loop: read audio → STFT → enqueue + optionally record."""
        while self._running:
            try:
                chunk = self._source.read_chunk()
                # Monotonic time: always valid, regardless of recording state
                t = self._frame_counter * _ADVANCE
                self._frame_counter += 1

                frame = self._compute_frame(chunk, t)

                # Accumulate if recording
                with self._lock:
                    if self._is_recording:
                        self._recorded_audio.append(chunk.copy())
                        self._recorded_stft.append(frame)

                # Push to live broadcast queue (non-blocking, drop if full)
                try:
                    self._frame_queue.put_nowait(frame)
                except queue.Full:
                    pass

            except Exception as e:
                print(f"[pipeline] Error: {e}")
                time.sleep(0.01)


# ═══════════════════════════════════════════════════
# WebSocket Connection Registry
# ═══════════════════════════════════════════════════

class ConnectionRegistry:
    """Tracks connected WebSocket clients and broadcasts to all of them."""

    def __init__(self):
        self._clients: set = set()

    def add(self, websocket) -> None:
        self._clients.add(websocket)

    def remove(self, websocket) -> None:
        self._clients.discard(websocket)

    @property
    def count(self) -> int:
        return len(self._clients)

    async def broadcast(self, message: dict) -> None:
        """Send a JSON message to every connected client."""
        if not self._clients:
            return
        payload = json.dumps(message)
        await asyncio.gather(
            *[c.send(payload) for c in self._clients],
            return_exceptions=True,
        )


async def frame_broadcaster(pipeline: AudioPipeline, registry: ConnectionRegistry) -> None:
    """Pull live frames from the pipeline and push them to WebSocket clients."""
    loop = asyncio.get_event_loop()
    while pipeline.running:
        try:
            frame = await loop.run_in_executor(
                None, pipeline.frame_queue.get, True, 0.05
            )
            await registry.broadcast({'type': 'frame', 'data': frame})
        except queue.Empty:
            await asyncio.sleep(0.005)


# ═══════════════════════════════════════════════════
# Save Functions (pure-ish: all data passed in)
# ═══════════════════════════════════════════════════

def save_recording(
    filename: str,
    audio_data: np.ndarray,
    stft_data: list[dict],
    sample_rate: int,
    channels: int,
    save_path: str = '.',
) -> bool:
    """Save audio as WAV, STFT data as CSV and JSON.

    All data is passed in — no global state dependency. Testable with
    synthetic arrays.
    """
    try:
        os.makedirs(save_path, exist_ok=True)

        # ── WAV (32-bit float) ──
        wav_path = os.path.join(save_path, f"{filename}.wav")
        with wave.open(wav_path, 'wb') as wf:
            wf.setnchannels(channels)
            wf.setsampwidth(4)       # 32-bit float = 4 bytes
            wf.setframerate(sample_rate)
            wf.writeframes(audio_data.tobytes())

        # ── CSV (editable: time, frequency, amplitude, phase) ──
        csv_path = os.path.join(save_path, f"{filename}_stft.csv")
        with open(csv_path, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['time_s', 'frequency_hz', 'amplitude', 'phase_radians'])
            for frame in stft_data:
                t = frame['time']
                for freq, mag, phase in zip(
                    frame['frequencies'], frame['magnitudes'], frame['phases']
                ):
                    writer.writerow([t, freq, mag, phase])

        # ── JSON (full matrices for programmatic use) ──
        json_path = os.path.join(save_path, f"{filename}_stft.json")
        save_dict = {
            'meta': {
                'sample_rate': sample_rate,
                'fft_size': FFT_SIZE,
                'hop_length': HOP_LENGTH,
                'window': WINDOW_TYPE,
            },
            'times': [f['time'] for f in stft_data],
            'frequencies': stft_data[0]['frequencies'],
            'magnitudes': [f['magnitudes'] for f in stft_data],
            'phases': [f['phases'] for f in stft_data],
        }
        with open(json_path, 'w') as f:
            json.dump(save_dict, f, indent=2)

        print(f"[save] Saved {wav_path}, {csv_path}, {json_path}")
        return True

    except Exception as e:
        print(f"[save] Error: {e}")
        return False


# ═══════════════════════════════════════════════════
# WebSocket Command Handler
# ═══════════════════════════════════════════════════

async def handle_client(
    websocket,
    pipeline: AudioPipeline,
    registry: ConnectionRegistry,
) -> None:
    """Handle incoming commands from one WebSocket client."""
    registry.add(websocket)
    print(f"[ws] Client connected  ({registry.count} total)")
    try:
        async for raw in websocket:
            cmd = json.loads(raw)
            action = cmd.get('command', '')

            if action == 'start_recording':
                pipeline.start_recording()
                await websocket.send(json.dumps({'type': 'recording_started'}))
                print("[cmd] Recording STARTED")

            elif action == 'stop_recording':
                count, duration = pipeline.stop_recording()
                await websocket.send(json.dumps({
                    'type': 'recording_stopped',
                    'frames': count,
                    'duration': duration,
                }))
                print(f"[cmd] Recording STOPPED  ({count} frames)")

            elif action == 'save':
                filename = cmd.get('filename', 'recording')
                save_path = cmd.get(
                    'path',
                    str(os.path.expanduser('~/spectrogram_app/saved')),
                )
                data = pipeline.get_recording_data()
                if data is None:
                    await websocket.send(json.dumps({
                        'type': 'error',
                        'message': 'Save failed – no recording data',
                    }))
                else:
                    ok = save_recording(
                        filename=filename,
                        audio_data=data['audio'],
                        stft_data=data['stft'],
                        sample_rate=data['sample_rate'],
                        channels=data['channels'],
                        save_path=save_path,
                    )
                    if ok:
                        await websocket.send(json.dumps({
                            'type': 'saved',
                            'filename': filename,
                        }))
                    else:
                        await websocket.send(json.dumps({
                            'type': 'error',
                            'message': 'Save failed',
                        }))

            elif action == 'get_full_data':
                data = pipeline.get_recording_data()
                if data is None:
                    await websocket.send(json.dumps({
                        'type': 'error',
                        'message': 'No recorded data',
                    }))
                else:
                    stft = data['stft']
                    await websocket.send(json.dumps({
                        'type': 'full_data',
                        'times': [f['time'] for f in stft],
                        'frequencies': stft[0]['frequencies'],
                        'magnitudes': [f['magnitudes'] for f in stft],
                        'phases': [f['phases'] for f in stft],
                    }))

            elif action == 'get_status':
                info = pipeline.recording_info()
                await websocket.send(json.dumps({
                    'type': 'status',
                    **info,
                }))

            else:
                await websocket.send(json.dumps({
                    'type': 'error',
                    'message': f'Unknown command: {action}',
                }))

    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        registry.remove(websocket)
        print(f"[ws] Client disconnected  ({registry.count} remaining)")


# ═══════════════════════════════════════════════════
# Entry Point
# ═══════════════════════════════════════════════════

async def main():
    # Build the pipeline with the best available audio source
    source = create_audio_source()
    pipeline = AudioPipeline(source)
    pipeline.start()

    registry = ConnectionRegistry()

    # Start frame → WebSocket broadcaster
    asyncio.create_task(frame_broadcaster(pipeline, registry))

    # Wire the handler closure
    async def on_connect(ws):
        await handle_client(ws, pipeline, registry)

    try:
        async with websockets.serve(on_connect, "localhost", WEBSOCKET_PORT):
            print(f"\n{'='*50}")
            print(f"  Spectrogram Backend running")
            print(f"  WebSocket: ws://localhost:{WEBSOCKET_PORT}")
            print(f"  FFT size:  {FFT_SIZE}  |  Hop: {HOP_LENGTH}  |  Rate: {SAMPLE_RATE} Hz")
            print(f"  Audio:     {type(source).__name__}")
            print(f"{'='*50}\n")
            await asyncio.Future()  # run forever
    finally:
        pipeline.stop()
        print("Pipeline stopped.")


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nShutting down...")
