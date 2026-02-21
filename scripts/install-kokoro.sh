#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$HOME/.openclaw/clawIsland.json"
KOKORO_HOME="$HOME/.openclaw/clawIsland"
VENV_DIR="$KOKORO_HOME/kokoro-venv"
PYTHON_BIN="$VENV_DIR/bin/python3"
KOKORO_SCRIPT_SRC="$ROOT/scripts/kokoro_tts.py"
KOKORO_SCRIPT_DST="$KOKORO_HOME/kokoro_tts.py"
PYTHON_BASE=""

echo "🧠 Installing Kokoro local TTS..."
mkdir -p "$KOKORO_HOME"

if command -v python3.11 >/dev/null 2>&1; then
  PYTHON_BASE="$(command -v python3.11)"
elif [ -x /opt/homebrew/bin/python3.11 ]; then
  PYTHON_BASE="/opt/homebrew/bin/python3.11"
else
  echo "❌ Python 3.11 not found."
  echo "   Kokoro currently requires Python >=3.10 and <3.13."
  echo "   Install with: brew install python@3.11"
  exit 1
fi

if [ -x "$PYTHON_BIN" ]; then
  if ! "$PYTHON_BIN" -c 'import sys; raise SystemExit(0 if (3,10) <= sys.version_info[:2] < (3,13) else 1)'; then
    echo "♻️ Rebuilding venv with Python 3.11 (existing venv version unsupported)"
    rm -rf "$VENV_DIR"
  fi
fi

if [ ! -x "$PYTHON_BIN" ]; then
  echo "🐍 Creating venv at $VENV_DIR"
  "$PYTHON_BASE" -m venv "$VENV_DIR"
fi

echo "📦 Installing Kokoro dependencies..."
"$PYTHON_BIN" -m pip install --upgrade pip wheel >/dev/null
"$PYTHON_BIN" -m pip install --upgrade "kokoro>=0.9.4" soundfile numpy

if command -v brew >/dev/null 2>&1; then
  if ! brew list espeak-ng >/dev/null 2>&1; then
    echo "🔤 Installing espeak-ng (recommended by Kokoro docs)..."
    brew install espeak-ng
  fi
fi

cp "$KOKORO_SCRIPT_SRC" "$KOKORO_SCRIPT_DST"
chmod +x "$KOKORO_SCRIPT_DST"
echo "✅ Installed script: $KOKORO_SCRIPT_DST"

if [ ! -f "$CONFIG_FILE" ]; then
  mkdir -p "$(dirname "$CONFIG_FILE")"
  cat > "$CONFIG_FILE" <<EOF
{
  "hotkey": "fn",
  "gatewayUrl": "http://localhost:18789",
  "gatewayToken": null,
  "screenshotOnTrigger": false,
  "ttsEngine": "kokoro",
  "ttsVoice": "Samantha (English (US))",
  "kokoroVoice": "af_heart",
  "kokoroSpeed": 1.0,
  "kokoroLangCode": "a",
  "kokoroPythonPath": "$PYTHON_BIN",
  "kokoroScriptPath": "$KOKORO_SCRIPT_DST",
  "whisperModel": "base.en",
  "maxRecordingSeconds": 30,
  "model": "openclaw",
  "conversationBufferSize": 10,
  "agentId": "voice",
  "sessionKey": "agent:voice:main",
  "maxTokens": 2048
}
EOF
else
  if command -v jq >/dev/null 2>&1; then
    tmp="$(mktemp)"
    jq \
      --arg py "$PYTHON_BIN" \
      --arg script "$KOKORO_SCRIPT_DST" \
      '.ttsEngine = "kokoro"
      | .kokoroVoice = (.kokoroVoice // "af_heart")
      | .kokoroSpeed = (.kokoroSpeed // 1.0)
      | .kokoroLangCode = (.kokoroLangCode // "a")
      | .kokoroPythonPath = $py
      | .kokoroScriptPath = $script' \
      "$CONFIG_FILE" > "$tmp"
    mv "$tmp" "$CONFIG_FILE"
  else
    echo "⚠️ jq not found. Please set these fields manually in $CONFIG_FILE:"
    echo "   ttsEngine=kokoro, kokoroVoice=af_heart, kokoroSpeed=1.0, kokoroLangCode=a"
    echo "   kokoroPythonPath=$PYTHON_BIN"
    echo "   kokoroScriptPath=$KOKORO_SCRIPT_DST"
  fi
fi

echo
echo "🧪 Quick Kokoro sanity test..."
OUT="/tmp/milo-kokoro-test.wav"
"$PYTHON_BIN" "$KOKORO_SCRIPT_DST" \
  --text "Hello from Kokoro local voice." \
  --voice "af_heart" \
  --lang "a" \
  --speed "1.0" \
  --output "$OUT"
/usr/bin/afplay "$OUT" || true
rm -f "$OUT"

echo "✅ Kokoro is installed and configured."
echo "   Config: $CONFIG_FILE"
echo "   Next: relaunch clawIsland.app"
