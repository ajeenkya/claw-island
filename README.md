# Claw Island

A macOS menu-bar voice overlay for OpenClaw with notch-style HUD, push-to-talk hotkey, local speech recognition fallback, and low-latency TTS.

Internal app/binary name remains `MiloOverlay`.

## Features

- Global hotkey trigger (`fn` by default)
- Notch-anchored animated HUD
- Live speech recognition with Whisper fallback
- OpenClaw chat completions routing (agent + session aware)
- Sentence-level TTS captions while speaking
- Selected-text rewrite flow with explicit apply confirmation
- TTS engines:
  - `system` (Apple local voices via `say`)
  - `kokoro` (local open-source Kokoro-82M)

## Requirements

- macOS 14+
- Swift 5.9+
- `ffmpeg` (`brew install ffmpeg`)
- OpenClaw gateway running (default `http://localhost:18789`)

## Build and Run

```bash
cd src/MiloOverlay
swift build -c release
.build/release/MiloOverlay
```

Or from repo root:

```bash
./scripts/build.sh
./scripts/run.sh
```

## Install .app Bundle

```bash
./scripts/install-app.sh
open -a "$HOME/Desktop/MiloOverlay.app"
```

## Permissions

Grant these in **System Settings → Privacy & Security**:

- Microphone
- Speech Recognition
- Accessibility (for global hotkey)

## Kokoro Setup (Local Open-Source TTS)

```bash
./scripts/install-kokoro.sh
```

This creates a dedicated venv at `~/.openclaw/milo-overlay/kokoro-venv`, installs Kokoro, and updates config.

## Config

Config file: `~/.openclaw/milo-overlay.json`

Example fields:

```json
{
  "ttsEngine": "kokoro",
  "ttsVoice": "Eddy (English (US))",
  "kokoroVoice": "af_heart",
  "kokoroSpeed": 1.0,
  "kokoroLangCode": "a",
  "kokoroPythonPath": "~/.openclaw/milo-overlay/kokoro-venv/bin/python3",
  "kokoroScriptPath": "~/.openclaw/milo-overlay/kokoro_tts.py",
  "agentId": "voice",
  "sessionKey": "agent:voice:main"
}
```

## Selected-Text Rewrite Flow

When you ask Milo to rewrite text (for example: "rewrite this to sound friendlier"), the app now:

1. Reads the current selection from the active app.
2. Asks OpenClaw to generate a rewrite preview.
3. Speaks the preview and waits for confirmation.
4. Applies only after you say `apply`.

Bridge script (included in this repo): `desktop-actions/milo_bridge.py`

## Open Source Notes

- This repo contains app code and local scripts only.
- Do not commit private tokens or user-specific config values.
- Recommended first publish pass:
  - scrub `~/.openclaw/milo-overlay.json`
  - rotate any local gateway token previously used in development

## License

MIT
