#!/bin/bash

echo "🧪 Direct clawIsland Recording Test"
echo ""

# Kill any existing clawIsland
echo "🔄 Stopping existing clawIsland..."
pkill clawIsland 2>/dev/null
sleep 1

echo "🚀 Starting clawIsland in foreground (you'll see all logs)..."
echo "Try pressing fn key or using menu bar toggle"
echo "Press Ctrl+C to stop"
echo ""

cd "$(dirname "$0")/../src/clawIsland"

# Run in foreground so we see all output
exec ./.build/release/clawIsland