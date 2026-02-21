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
