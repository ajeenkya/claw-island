# Claw Island Configuration Guide

Configuration is stored in `~/.openclaw/clawIsland.json`. Copy `example-config.json` to get started.

## Configuration Fields

### Hotkey & Triggering

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `hotkey` | String | `"Option+Space"` | Global hotkey to activate recording. Format: `"fn"` or `"MODIFIER+KEY"` (e.g., `"Cmd+Shift+F1"`, `"Option+Space"`). Requires Accessibility permission. |

**Supported modifiers:** CMD, COMMAND, OPTION, ALT, CONTROL, CTRL, SHIFT, FN, FUNCTION
**Supported keys:** A-Z, 0-9, F1-F20, SPACE, RETURN, TAB, ESC, DELETE, PERIOD, COMMA, SLASH, SEMICOLON, and more.

### Gateway & Model Routing

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `gatewayUrl` | String | `"http://localhost:18789"` | OpenClaw gateway URL. Supports HTTP or HTTPS. |
| `gatewayToken` | String? | `null` | Optional authentication token for gateway (if required). |
| `model` | String | `"openclaw"` | Model to use. Set to `"openclaw"` to route through configured agent (with tools, memory, skills). Or specify a model: `"anthropic/claude-opus-4-6"`. |
| `agentId` | String | `"voice"` | OpenClaw agent ID to route messages to. |
| `sessionKey` | String? | `null` | Optional session key for persistent server-side conversation history. When set, conversation history is maintained on gateway. When `null`, local buffer is used. |
| `conversationBufferSize` | Int | `10` | Number of conversation turns (user+assistant pairs) to keep in local buffer. Only used when `sessionKey` is `null`. |

### Text-to-Speech (TTS)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `ttsEngine` | String | `"system"` | TTS backend: `"system"` (Apple `say` voices) or `"kokoro"` (local open-source synthesis). Automatically falls back to system if Kokoro unavailable. |
| `ttsVoice` | String? | `"Samantha (English (US))"` | System voice name (only used when `ttsEngine` is `"system"`). Examples: `"Daniel (English (UK))"`, `"Fred (English (US))"`, `"Zoe (Premium)"`. Run `say -v "?"` to list available voices. |
| `kokoroVoice` | String | `"af_heart"` | Kokoro voice (only used when `ttsEngine` is `"kokoro"`). Currently supported: `"af_heart"` (balanced female). |
| `kokoroSpeed` | Double | `1.15` | Speech rate multiplier for Kokoro (0.6 = slower, 1.6 = faster). Clamped to [0.6, 1.6]. |
| `kokoroLangCode` | String | `"a"` | Language code for Kokoro TTS. |
| `kokoroPythonPath` | String? | `null` | Path to Python executable in Kokoro venv (e.g., `~/.openclaw/clawIsland/kokoro-venv/bin/python3`). Auto-detected if not set. |
| `kokoroScriptPath` | String? | `null` | Path to `kokoro_tts.py` script. Auto-detected in standard locations if not set. |

### Speech Recognition

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `whisperModel` | String | `"base.en"` | Whisper transcription model size (requires whisper-cpp). Options: `"tiny.en"`, `"base.en"`, `"small.en"`, `"medium.en"`. Larger models are more accurate but slower. Falls back to macOS speech framework if unavailable. |

### Recording & Audio

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `maxRecordingSeconds` | Int | `30` | Maximum recording duration before auto-stop (seconds). Minimum 1. |
| `screenshotOnTrigger` | Bool | `true` | Capture screenshot of active window when hotkey pressed (for visual context). Requires Screen Recording permission. Set to `false` to disable screenshots. |

### Token Budgeting

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `maxTokens` | Int | `512` | Maximum tokens requested from gateway for each response. |
| `adaptiveMaxTokensEnabled` | Bool | `true` | Enable adaptive token budgeting: scale `maxTokens` based on user's utterance length/intent. |
| `adaptiveMaxTokensFloor` | Int | `128` | Minimum tokens when adaptive budgeting is enabled. Clamped to [1, maxTokens]. |

### Performance & Optimization

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `relayOnlyMode` | Bool | `true` | When `true` (recommended), forward voice transcripts directly to OpenClaw. Local desktop actions (text rewrite, selection replacement) are disabled for safety. Set to `false` only if you want experimental local action bridges. |
| `speculativePrewarmEnabled` | Bool | `true` | Enable "prewarm" requests: send an early request while recording to reduce first-token latency. |
| `speculativePrewarmMinWords` | Int | `5` | Minimum live transcript word count before speculative prewarm triggers. |
| `speculativePrewarmCooldownSeconds` | Double | `90` | Cooldown between speculative prewarm requests (seconds). Clamped to [10, 600]. |

---

## Common Use Cases

### 1. **System Voices Only (Default)**

```json
{
  "ttsEngine": "system",
  "ttsVoice": "Samantha (English (US))"
}
```

Uses macOS's built-in TTS. No additional setup required. Works offline.

### 2. **Kokoro (Local Open-Source TTS)**

After running `./scripts/install-kokoro.sh`:

```json
{
  "ttsEngine": "kokoro",
  "kokoroVoice": "af_heart",
  "kokoroSpeed": 1.15,
  "kokoroPythonPath": "~/.openclaw/clawIsland/kokoro-venv/bin/python3"
}
```

Higher quality TTS than system voices. Runs locally (offline). Slower first-token latency.

### 3. **Custom Model Routing**

To use a specific model instead of the configured agent:

```json
{
  "model": "anthropic/claude-opus-4-6"
}
```

### 4. **Server-Side Conversation History**

For persistent multi-turn conversations:

```json
{
  "sessionKey": "agent:voice:main",
  "model": "openclaw"
}
```

When `sessionKey` is set, OpenClaw manages conversation history server-side. Local buffer is ignored.

### 5. **Longer Context (More Tokens)**

For complex tasks requiring detailed responses:

```json
{
  "maxTokens": 2048,
  "adaptiveMaxTokensEnabled": true,
  "adaptiveMaxTokensFloor": 256
}
```

---

## Validation & Troubleshooting

### Config Validation

On startup, clawIsland validates your config and logs warnings if:
- TTS engine is not "system" or "kokoro" → fallback to "system"
- Hotkey format is invalid → fallback to "Option+Space"
- Gateway URL is not HTTP/HTTPS
- Kokoro parameters out of bounds → automatically clamped

Invalid config **does not prevent startup**—defaults are used as fallback.

### Check Your Config

Print your current config path and values:

```bash
cat ~/.openclaw/clawIsland.json | jq .
```

### Reset to Defaults

Delete your config file to start fresh with defaults:

```bash
rm ~/.openclaw/clawIsland.json
# Next launch will create a default config
```

---

## File Locations

- **Primary config:** `~/.openclaw/clawIsland.json`
- **Example config:** `example-config.json` (in repo root)
- **Legacy config paths** (auto-detected):
  - `~/.openclaw/milo-overlay.json`
  - `~/.openclaw/claw-island.json`
  - `~/.openclaw/vyom-overlay.json`

---

## Advanced: Permissions Required

Depending on your config, you may need to grant these permissions in **System Settings → Privacy & Security**:

- **Microphone:** Always (for audio recording)
- **Speech Recognition:** Always (for transcription)
- **Accessibility:** Always (for global hotkey)
- **Screen Recording:** Only if `screenshotOnTrigger: true` (for screenshot context)
