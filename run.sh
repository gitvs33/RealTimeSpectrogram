#!/usr/bin/env bash
# Launcher script for the Spectrogram App
# Starts the Python backend and Flutter frontend.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Starting Spectrogram App ==="

# Start Python backend in the background
echo "[1/2] Starting Python backend (ws://localhost:8765)..."
cd "$SCRIPT_DIR/backend"
python3 main.py &
BACKEND_PID=$!
echo "  Backend PID: $BACKEND_PID"

# Wait for backend to be ready
sleep 2

# Start Flutter app
echo "[2/2] Starting Flutter app..."
cd "$SCRIPT_DIR/flutter_app"
flutter run -d linux

# When Flutter exits, kill the backend
echo "Shutting down backend..."
kill $BACKEND_PID 2>/dev/null || true
