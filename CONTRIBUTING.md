# Contributing to Claw Island

Thanks for contributing.

## Development Setup

1. Install prerequisites:
   - macOS 14+
   - Swift 5.9+
   - `ffmpeg` (`brew install ffmpeg`)
2. Build:
   ```bash
   cd src/clawIsland
   swift build -c debug
   ```
3. Run:
   ```bash
   cd /path/to/claw-island
   ./scripts/run.sh
   ```

## Test and Validation

Run before opening a PR:

```bash
cd src/clawIsland
swift test
swift build -c debug
```

For UI/permission-related changes, also include a short manual validation note:
- hotkey trigger works
- recording/transcription works
- response/TTS works
- overlay exits cleanly

## Pull Request Guidelines

- Keep PRs focused and reasonably small.
- Explain user impact and rollback plan.
- Update docs when behavior or config changes.
- Never commit secrets (`~/.openclaw/*`, API tokens, personal logs).

## Commit Style

Use clear, imperative commit messages, for example:
- `feat: add node-backed desktop rewrite bridge`
- `fix: remove corner halo during island expansion`
- `docs: clarify permission troubleshooting`

## Configuration Changes

When modifying config handling (Config.swift):

1. **Update defaults** in `MiloConfig.defaultConfig`
2. **Update validation** in the `validate()` method if adding validation
3. **Add tests** if validation logic changes
4. **Update docs**:
   - [docs/CONFIG.md](docs/CONFIG.md) - describe new field
   - [example-config.json](example-config.json) - add to example
5. **Update CHANGELOG** if user-facing change

**Testing config changes:**
```bash
# Test loading defaults
swift test

# Test invalid config loads with defaults
rm ~/.openclaw/clawIsland.json
./scripts/run.sh  # Should load defaults

# Test config modification
./scripts/change-hotkey.sh  # or other scripts
cat ~/.openclaw/clawIsland.json | jq .
```

## Adding New Tests

### Test Naming Convention

```swift
// Pattern: testFunctionName_Condition_ExpectedResult
func testIsSelectionRewriteRequest_EmptyString() {
    XCTAssertFalse(...)  // Empty string should NOT match
}

func testIsSelectionRewriteRequest_WithKeyword() {
    XCTAssertTrue(...)  // Text with "rewrite" SHOULD match
}
```

### Test Organization

- Place tests in `Tests/clawIslandTests/` directory
- Organize by class/function (e.g., `VoiceCommandIntentsTests.swift`)
- Use `// MARK:` comments to group related tests
- Include both happy path and error path tests

### Running Tests

```bash
cd src/clawIsland
swift test                      # Run all tests
swift test --filter VoiceCommandIntentsTests  # Run specific test class
swift test --filter testFunctionName # Run specific test
```

### Coverage Areas

Tests should cover:
- ✅ Happy path (normal input)
- ✅ Edge cases (empty, very long, whitespace-only)
- ✅ Special characters and Unicode
- ✅ Error paths (invalid input, boundary conditions)
- ✅ Case sensitivity variations

## Documentation Updates

When you change code, update related docs:

| Change Type | Documentation to Update |
|-------------|------------------------|
| Config field | `docs/CONFIG.md` + `example-config.json` |
| New feature | `README.md` features section |
| Permission requirement | `TROUBLESHOOTING.md` permissions table |
| Hotkey/command | `docs/CONFIG.md` hotkey section |
| Error message | `TROUBLESHOOTING.md` relevant section |
| Dependency | `docs/DEPENDENCIES.md` |
| Installation step | `README.md` installation section |

Quick doc update process:
```bash
# 1. Update relevant files
vim docs/CONFIG.md
vim example-config.json
vim TROUBLESHOOTING.md

# 2. Check for formatting issues
cat docs/CONFIG.md | head -50  # Verify no markdown errors

# 3. Mention in CHANGELOG
vim CHANGELOG.md
```

## Using Scripts

Several helper scripts are available for development:

| Script | Purpose |
|--------|---------|
| `./scripts/build.sh` | Build release binary |
| `./scripts/run.sh` | Run built app |
| `./scripts/install-app.sh` | Create .app bundle |
| `./scripts/change-hotkey.sh` | Interactive hotkey change |
| `./scripts/change-voice.sh` | Interactive voice selection |
| `./scripts/check-permissions.sh` | Verify system permissions |
| `./scripts/install-whisper.sh` | Install whisper-cpp |
| `./scripts/install-kokoro.sh` | Install Kokoro TTS |

Run `ls scripts/` to see all available scripts.

## Code Review Tips

**Before submitting a PR:**

1. ✅ Run tests: `swift test`
2. ✅ Build release: `swift build -c release`
3. ✅ Manual testing: Press hotkey, verify recording/transcription/TTS
4. ✅ Update docs: Check CONTRIBUTING.md, CONFIG.md, TROUBLESHOOTING.md
5. ✅ Check logs: `tail ~/.openclaw/clawIsland.log` for warnings
6. ✅ No secrets: Never commit tokens, API keys, or personal info

**During code review:**

- Be respectful and collaborative
- Request changes only for bugs or significant improvements
- Suggest rather than demand
- Explain the "why" not just the "what"

## Architecture Notes

### Key Components

| File | Purpose |
|------|---------|
| `clawIslandApp.swift` | Main app, state machine, HUD |
| `AudioRecorder.swift` | Microphone recording, level monitoring |
| `LiveTranscriber.swift` | macOS speech recognition |
| `Transcriber.swift` | Whisper fallback |
| `OpenClawClient.swift` | Gateway communication, streaming |
| `TTSEngine.swift` | Text-to-speech orchestration |
| `HotkeyManager.swift` | Global hotkey registration |
| `Config.swift` | Configuration loading/validation |

### State Machine

App states: `idle` → `recording` → `processing` → `speaking` → `idle`

See `MiloState` enum in `clawIslandApp.swift`.

## References

- [README.md](README.md) - Overview and features
- [docs/CONFIG.md](docs/CONFIG.md) - Configuration options
- [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) - Dependency info
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues
- [SECURITY.md](SECURITY.md) - Security policy
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) - Community standards
