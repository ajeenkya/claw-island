# Claw Island

[![CI](https://github.com/ajeenkya/claw-island/actions/workflows/ci.yml/badge.svg)](https://github.com/ajeenkya/claw-island/actions/workflows/ci.yml)

A macOS menu-bar voice overlay for OpenClaw with notch-style HUD, push-to-talk hotkey, local speech recognition fallback, and low-latency TTS.

Internal app/binary name remains `clawIsland`.

## Features

- Global hotkey trigger (`Option+Space` by default)
- Notch-anchored animated HUD
- Live speech recognition with Whisper fallback
- OpenClaw chat completions routing (agent + session aware)
- Sentence-level TTS captions while speaking
- Relay-only by default: transcripts are forwarded directly to OpenClaw
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
cd src/clawIsland
swift build -c release
.build/release/clawIsland
```

Or from repo root:

```bash
./scripts/build.sh
./scripts/run.sh
```

## Install .app Bundle

```bash
./scripts/install-app.sh
open -a "$HOME/Desktop/clawIsland.app"
```

## Tests

```bash
cd src/clawIsland
swift test
```

## Permissions

Grant these in **System Settings → Privacy & Security**:

- Microphone
- Speech Recognition
- Accessibility (for global hotkey)
- Screen Recording (for screenshot/screen context)

Quick helper:

```bash
./scripts/screen-recording-doctor.sh
```

## Kokoro Setup (Local Open-Source TTS)

```bash
./scripts/install-kokoro.sh
```

This creates a dedicated venv at `~/.openclaw/clawIsland/kokoro-venv`, installs Kokoro, and updates config.

## Config

Config file: `~/.openclaw/clawIsland.json`

**See [docs/CONFIG.md](docs/CONFIG.md) for comprehensive configuration guide.**

Example fields:

```json
{
  "ttsEngine": "kokoro",
  "ttsVoice": "Eddy (English (US))",
  "kokoroVoice": "af_heart",
  "kokoroSpeed": 1.0,
  "kokoroLangCode": "a",
  "kokoroPythonPath": "~/.openclaw/clawIsland/kokoro-venv/bin/python3",
  "kokoroScriptPath": "~/.openclaw/clawIsland/kokoro_tts.py",
  "agentId": "voice",
  "sessionKey": "agent:voice:main",
  "relayOnlyMode": true
}
```

Copy [example-config.json](example-config.json) to get started with all available options.

## Optional Local Action Helpers

If you explicitly set `"relayOnlyMode": false`, Claw Island can run local overlay helpers (for example selection rewrite and direct type/send shortcuts) before forwarding.

Default behavior is relay-only, which keeps action execution responsibility inside OpenClaw.

Bridge script (included in this repo): `desktop-actions/claw_bridge.py`

## Open Source Notes

- This repo contains app code and local scripts only.
- Do not commit private tokens or user-specific config values.
- Recommended first publish pass:
  - scrub `~/.openclaw/clawIsland.json`
  - rotate any local gateway token previously used in development

## Documentation

- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Development setup, testing, and PR guidelines
- **[docs/CONFIG.md](docs/CONFIG.md)** - Comprehensive configuration reference
- **[docs/DEPENDENCIES.md](docs/DEPENDENCIES.md)** - Dependencies, versions, and requirements
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
- **[SECURITY.md](SECURITY.md)** - Security policy
- **[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)** - Community standards
- **[CHANGELOG.md](CHANGELOG.md)** - Release notes and version history

## Contributing

Questions or want to contribute? Start with [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
