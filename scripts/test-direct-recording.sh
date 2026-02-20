#!/bin/bash

echo "🧪 Direct MiloOverlay Recording Test"
echo ""

# Kill any existing MiloOverlay
echo "🔄 Stopping existing MiloOverlay..."
pkill MiloOverlay 2>/dev/null
sleep 1

echo "🚀 Starting MiloOverlay in foreground (you'll see all logs)..."
echo "Try pressing fn key or using menu bar toggle"
echo "Press Ctrl+C to stop"
echo ""

cd "$(dirname "$0")/../src/MiloOverlay"

# Run in foreground so we see all output
exec ./.build/release/MiloOverlay