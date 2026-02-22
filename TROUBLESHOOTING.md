# Claw Island Troubleshooting Guide

Common issues and solutions for Claw Island voice control.

## Hotkey Not Working

**Problem:** Pressing your configured hotkey doesn't trigger recording.

**Diagnosis Steps:**
1. Check if Accessibility permission is granted:
   ```bash
   # View current accessibility permission status
   ls -la "/Library/Application Support/com.apple.sharedfilelist/com.apple.security.application-groups.plist"
   ```
2. Run the diagnosis script:
   ```bash
   ./scripts/check-permissions.sh
   ```
3. Check the logs:
   ```bash
   tail -f ~/.openclaw/clawIsland.log
   ```

**Solutions:**

- **"Accessibility not granted" in logs?**
  - Go to **System Settings → Privacy & Security → Accessibility**
  - Find "clawIsland" in the list and toggle it ON
  - Restart clawIsland

- **Invalid hotkey format?**
  - Edit `~/.openclaw/clawIsland.json` and check `hotkey` field
  - Format must be: `"fn"` or `"MODIFIER+KEY"` (e.g., `"Option+Space"`)
  - Valid modifiers: CMD, OPTION, CONTROL, SHIFT, FN
  - Valid keys: A-Z, 0-9, F1-F20, SPACE, RETURN, TAB
  - Restart clawIsland after editing config

- **Hotkey conflicts with system shortcuts?**
  - Change your hotkey in config to avoid system defaults
  - Run: `./scripts/change-hotkey.sh` (interactive menu)

---

## Microphone Not Working / No Sound Detected

**Problem:** Microphone permission granted but recording fails or no speech detected.

**Diagnosis:**
1. Test microphone directly:
   ```bash
   ffmpeg -f avfoundation -i ":default" -t 3 /tmp/test.wav
   ```
   If this fails, ffmpeg isn't finding your mic.

2. List available audio input devices:
   ```bash
   ffmpeg -f avfoundation -list_devices true -i ""
   ```

3. Check microphone permission:
   - Go to **System Settings → Privacy & Security → Microphone**
   - Ensure clawIsland is in the allowed list

**Solutions:**

- **"ffmpeg not found" error?**
  ```bash
  brew install ffmpeg
  ```

- **Microphone permission not granted?**
  - Open System Settings → Privacy & Security → Microphone
  - Click the + button, find clawIsland.app, add it
  - Restart clawIsland

- **Built-in mic not working?**
  - Try a USB headset to test if it's a hardware issue
  - On M-series Macs, sometimes mic requires app restart after plugging in

- **Gain/volume too low?**
  - Microphone levels are auto-normalized via dB mapping
  - Try speaking louder or closer to the mic
  - Check System Sound Settings → Input and increase mic volume

---

## Speech Recognition Failing ("No speech detected")

**Problem:** Audio was recorded but transcription came back empty.

**Diagnosis:**
1. Check if speech recognition is authorized:
   ```bash
   # Go to System Settings → Privacy & Security → Speech Recognition
   # Ensure clawIsland has permission
   ```

2. Check logs for transcription details:
   ```bash
   grep -i "transcript\|whisper\|speech" ~/.openclaw/clawIsland.log | tail -20
   ```

**Solutions:**

- **"Speech recognizer unavailable" error?**
  - Grant Speech Recognition permission in System Settings
  - Restart clawIsland

- **Whisper fallback being used (slow transcription)?**
  - Install whisper-cpp for faster offline transcription:
    ```bash
    ./scripts/install-whisper.sh
    ```

- **Background noise causing issues?**
  - Transcription works best in quiet environments
  - Try recording in a quieter location
  - The audio level visualizer in the HUD helps gauge input

- **Short utterances ("hi", "yes") not being recognized?**
  - The app uses both live transcription (fast) and Whisper fallback (accurate)
  - Very short audio (<1 second) may not transcribe well
  - Try speaking complete phrases

---

## Slow TTS Response (Delayed Reply)

**Problem:** Long delay before the AI response starts playing.

**Diagnosis:**
1. Check which TTS engine is configured:
   ```bash
   grep ttsEngine ~/.openclaw/clawIsland.json
   ```

2. Check gateway latency:
   ```bash
   # Test connection to OpenClaw gateway
   curl -v http://localhost:18789/health
   ```

3. Look at latency metrics in logs:
   ```bash
   grep "First sentence latency\|latency" ~/.openclaw/clawIsland.log
   ```

**Solutions:**

- **Using system voices (slow)?**
  - System TTS is fine for casual use but has network latency
  - For faster responses, set up Kokoro:
    ```bash
    ./scripts/install-kokoro.sh
    ```

- **Gateway response is slow?**
  - Check that OpenClaw is running on localhost:18789
  - Use a faster network (avoid Wi-Fi interference)
  - Reduce `maxTokens` in config to get faster responses

- **Using Kokoro but still slow?**
  - First run of Kokoro loads Python venv (slower)
  - Subsequent requests should be faster
  - If still slow, check CPU usage: `top`

- **Speculative prewarm cooldown?**
  - App can send a "warmup" request while you're still recording
  - Configured via `speculativePrewarmCooldownSeconds` (default 90s)
  - Disable if it's causing issues:
    ```json
    { "speculativePrewarmEnabled": false }
    ```

---

## Gateway Connection Errors

**Problem:** "API error" or "gateway unreachable" messages.

**Diagnosis:**
1. Verify OpenClaw is running:
   ```bash
   curl http://localhost:18789/health
   ```

2. Check configured gateway URL:
   ```bash
   grep gatewayUrl ~/.openclaw/clawIsland.json
   ```

3. Check network connectivity:
   ```bash
   ping localhost
   nc -zv localhost 18789
   ```

**Solutions:**

- **"gateway unreachable" or connection refused?**
  - Start OpenClaw gateway:
    ```bash
    # If using local development
    openclaw server start
    ```
  - Verify port 18789 is not blocked by firewall

- **Wrong gateway URL?**
  - Edit `~/.openclaw/clawIsland.json`
  - Check `gatewayUrl` is correct (default: `"http://localhost:18789"`)
  - Ensure it's HTTP or HTTPS, not IP:port without scheme

- **Gateway token required but not provided?**
  - If gateway requires authentication, add token to config:
    ```json
    { "gatewayToken": "your-token-here" }
    ```

- **Network firewall blocking connection?**
  - If using remote gateway: ensure port 18789 is open
  - If behind proxy: configure proxy in system network settings

---

## Config Parsing Errors / Config Not Loading

**Problem:** Config changes not taking effect or malformed JSON error.

**Diagnosis:**
1. Validate JSON syntax:
   ```bash
   python3 -m json.tool ~/.openclaw/clawIsland.json
   ```

2. Check for invalid values:
   ```bash
   cat ~/.openclaw/clawIsland.json | jq .
   ```

3. Review logs for validation warnings:
   ```bash
   grep "⚠️" ~/.openclaw/clawIsland.log
   ```

**Solutions:**

- **"Invalid JSON" error when running?**
  - Fix the JSON syntax error shown in logs
  - Validate with: `jq . ~/.openclaw/clawIsland.json`
  - Common issues: missing commas, trailing commas, unquoted strings

- **Config changed but changes not taking effect?**
  - Restart clawIsland:
    ```bash
    killall clawIsland
    ./scripts/run.sh
    ```

- **Invalid TTS engine or voice name?**
  - Check valid engines: `"system"` or `"kokoro"`
  - List system voices:
    ```bash
    say -v "?"
    ```
  - Kokoro only supports `"af_heart"` voice

- **Out of bounds parameters?**
  - Values are automatically clamped to valid ranges
  - Examples:
    - `kokoroSpeed`: [0.6, 1.6]
    - `maxRecordingSeconds`: >= 1
    - `speculativePrewarmCooldownSeconds`: [10, 600]

- **Reset to defaults:**
  ```bash
  rm ~/.openclaw/clawIsland.json
  # Restart app - will load default config
  ```

---

## Kokoro TTS Setup Problems

**Problem:** Kokoro voice playing but with errors or delays.

**Diagnosis:**
1. Check Kokoro installation:
   ```bash
   ls -la ~/.openclaw/clawIsland/kokoro-venv/
   ```

2. Test Kokoro manually:
   ```bash
   ~/.openclaw/clawIsland/kokoro-venv/bin/python3 -c "import kokoro"
   ```

3. Check Kokoro config paths in JSON:
   ```bash
   jq '.kokoroPythonPath, .kokoroScriptPath' ~/.openclaw/clawIsland.json
   ```

**Solutions:**

- **"Kokoro python runtime not found"?**
  - Reinstall Kokoro:
    ```bash
    ./scripts/install-kokoro.sh
    ```

- **"Kokoro script not found"?**
  - Script should auto-locate at `~/.openclaw/clawIsland/kokoro_tts.py`
  - If missing, reinstall:
    ```bash
    ./scripts/install-kokoro.sh
    ```

- **Slow Kokoro on first run?**
  - First TTS request loads Python and model (can take 5-10 seconds)
  - Subsequent requests are faster
  - This is expected behavior

- **Python version mismatch?**
  - Kokoro requires Python 3.9+
  - Check installed version:
    ```bash
    ~/.openclaw/clawIsland/kokoro-venv/bin/python3 --version
    ```

---

## Desktop Actions Not Working (Selection Rewrite, etc.)

**Problem:** "Apply" or selection rewrite features not working.

**Diagnosis:**
1. Check if relayOnlyMode is enabled:
   ```bash
   grep relayOnlyMode ~/.openclaw/clawIsland.json
   ```

2. Verify bridge script exists:
   ```bash
   ls -la desktop-actions/claw_bridge.py
   ```

3. Check Accessibility permission:
   - Go to **System Settings → Privacy & Security → Accessibility**
   - Ensure clawIsland is allowed

**Solutions:**

- **"relayOnlyMode: true" (default)?**
  - This is the recommended safe setting
  - Local desktop actions are disabled by design
  - Change to `false` only for experimental local shortcuts:
    ```json
    { "relayOnlyMode": false }
    ```

- **Accessibility not granted?**
  - Enable Accessibility for clawIsland in System Settings
  - This permission is required for the Python bridge to send keystrokes

- **Python bridge script missing?**
  - Ensure you cloned the full repo including `desktop-actions/` folder
  - The bridge is included in releases

---

## Performance Issues (High CPU / Memory)

**Problem:** clawIsland using excessive resources.

**Diagnosis:**
1. Check resource usage:
   ```bash
   top -pid $(pgrep clawIsland)
   ```

2. Check active processes:
   ```bash
   ps aux | grep clawIsland
   ```

3. Review logs for warnings:
   ```bash
   grep -i "error\|failed\|warning" ~/.openclaw/clawIsland.log | tail -20
   ```

**Solutions:**

- **High CPU during audio processing?**
  - Normal during recording and transcription
  - If persists after recording stops, check logs for errors
  - Try restarting the app

- **Memory leak (growing memory over time)?**
  - Report the issue on GitHub with logs
  - Workaround: restart app periodically

- **Reduce speculative prewarm:**
  - Disable if you don't need it:
    ```json
    { "speculativePrewarmEnabled": false }
    ```

- **Use smaller Whisper model:**
  - Change in config:
    ```json
    { "whisperModel": "tiny.en" }
    ```

---

## Permissions Issues Summary

**Required permissions** (go to System Settings → Privacy & Security):

| Permission | Purpose | Required? |
|-----------|---------|-----------|
| Microphone | Audio input | ✅ Yes |
| Speech Recognition | Transcription | ✅ Yes |
| Accessibility | Global hotkey + desktop actions | ✅ Yes |
| Screen Recording | Screenshot context | ⚠️ Only if `screenshotOnTrigger: true` |

**Grant all permissions:**
```bash
./scripts/check-permissions.sh
```

---

## Getting Help

If you encounter an issue not covered here:

1. **Check logs:**
   ```bash
   tail -100 ~/.openclaw/clawIsland.log
   ```

2. **Gather debug info:**
   ```bash
   swift --version
   ffmpeg -version
   uname -a
   cat ~/.openclaw/clawIsland.json
   tail -50 ~/.openclaw/clawIsland.log
   ```

3. **Report on GitHub:** [Create an issue](https://github.com/ajeenkya/claw-island/issues) with:
   - Description of problem
   - Steps to reproduce
   - Debug info from above
   - Relevant log lines (without personal info)

---

## See Also

- [Configuration Guide](docs/CONFIG.md) - Config options and examples
- [Dependencies](docs/DEPENDENCIES.md) - Version requirements
- [Contributing](CONTRIBUTING.md) - Development setup
- [README](README.md) - Overview and features
