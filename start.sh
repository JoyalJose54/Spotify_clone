#!/bin/bash

# 1. Kill any existing instances of main.py to avoid port conflicts
pkill -f "python3 main.py" || true

# Get the absolute path of the project root
PROJECT_ROOT=$(pwd)

echo "🚀 Activating Virtual Environment and Installing Dependencies..."
cd "$PROJECT_ROOT/cloud_functions"

# Create venv if somehow it's missing, otherwise just activate
if [ ! -f "venv/bin/activate" ]; then
    python3 -m venv venv
fi
source venv/bin/activate

# Install requirements inside the venv
pip install -r requirements.txt --quiet

echo "🚀 Starting Python Backend..."
# Run backend in background and save its process ID
python3 main.py > backend.log 2>&1 &
BACKEND_PID=$!

echo "📱 Starting Flutter App..."
cd "$PROJECT_ROOT"
# Run flutter and wait for it to finish
flutter run --no-pub

# Once you stop the flutter app (Ctrl+C), kill the backend too
echo "Stopping Backend..."
kill $BACKEND_PID
