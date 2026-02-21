#!/bin/bash
set -euo pipefail

echo "🧪 Testing microphone capture from the CURRENT shell app"
echo "ℹ️  This checks terminal/ffmpeg microphone permission (Ghostty/iTerm/Terminal), not just clawIsland.app"
echo ""

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "❌ ffmpeg not found. Install with: brew install ffmpeg"
  exit 1
fi

TMP_FILE="/tmp/test_mic.wav"
rm -f "$TMP_FILE"

echo "📡 Running ffmpeg mic probe..."
if timeout 3 ffmpeg -f avfoundation -i ":0" -t 2 -y "$TMP_FILE" >/dev/null 2>&1; then
  :
fi

if [ -f "$TMP_FILE" ]; then
  FILE_SIZE=$(wc -c < "$TMP_FILE")
  if [ "$FILE_SIZE" -gt 1000 ]; then
    echo "✅ Microphone capture works from this shell (${FILE_SIZE} bytes)"
    rm -f "$TMP_FILE"
    echo ""
    echo "🚀 Launch clawIsland:"
    echo "   ./scripts/run.sh"
    exit 0
  fi
  echo "⚠️ Audio file exists but too small (${FILE_SIZE} bytes)"
else
  echo "❌ Mic probe failed from this shell app"
fi

echo ""
echo "What this usually means:"
echo "1) Your terminal app does not have microphone permission yet."
echo "2) You may only have legacy 'VyomOverlay' permission (which is okay for old builds)."
echo ""
echo "Next steps:"
echo "1. Open System Settings → Privacy & Security → Microphone"
echo "2. Enable your terminal app (Ghostty/iTerm/Terminal) if listed"
echo "3. Enable VyomOverlay if present (legacy bundle)"
echo "4. Build a fresh clawIsland.app so it appears explicitly:"
echo "   ./scripts/install-app.sh"
echo "5. Launch it once:"
echo "   open -a \"$HOME/Desktop/clawIsland.app\""
echo ""
echo "After that, rerun:"
echo "   ./scripts/verify-permissions.sh"
