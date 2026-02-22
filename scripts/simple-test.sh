#!/bin/bash

echo "🎤 Simple clawIsland Test - No Hotkeys Required"
echo ""
echo "This will test clawIsland's core recording functionality"
echo "using menu commands instead of hotkeys"
echo ""

# Kill existing
pkill clawIsland 2>/dev/null

echo "🚀 Starting clawIsland..."
cd "$(dirname "$0")/../src/clawIsland"

# Run with debugging
./.build/release/clawIsland &
CLAW_PID=$!

echo "✅ clawIsland started (PID: $CLAW_PID)"
echo ""
echo "📋 IMPORTANT: Look for the MICROPHONE ICON in your menu bar"
echo "             (top-right corner of your screen)"
echo ""
echo "🎯 To test recording:"
echo "   1. Click the microphone icon in menu bar"
echo "   2. Select 'Toggle Recording'"
echo "   3. Speak clearly"
echo "   4. Click 'Toggle Recording' again to stop"
echo ""
echo "If you don't see the menu bar icon, tell me and I'll create"
echo "an alternative solution."
echo ""
echo "Press Ctrl+C to stop clawIsland"
echo ""

# Keep script running
wait $CLAW_PID