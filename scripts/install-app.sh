#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/src/clawIsland"
APP_DIR="$HOME/Desktop/clawIsland.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Building clawIsland (release)..."
cd "$PROJECT_DIR"
swift build -c release

echo "🧱 Creating app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$PROJECT_DIR/.build/release/clawIsland" "$MACOS_DIR/clawIsland"
chmod +x "$MACOS_DIR/clawIsland"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT/scripts/kokoro_tts.py" "$RESOURCES_DIR/kokoro_tts.py"
chmod +x "$RESOURCES_DIR/kokoro_tts.py"

# Prefer real developer signing identity if available; fallback to ad-hoc.
IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk -F'\"' '/Apple Development:/ {print $2; exit}')"
if [ -n "$IDENTITY" ]; then
  echo "🔏 Signing with: $IDENTITY"
  codesign --force --deep --sign "$IDENTITY" "$APP_DIR"
else
  echo "🔏 Signing ad-hoc"
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "✅ Installed: $APP_DIR"
echo "🚀 Launch with: open -a \"$APP_DIR\""
