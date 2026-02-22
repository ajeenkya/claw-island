# Claw Island Dependencies

Complete list of required and optional dependencies for Claw Island.

## System Requirements

### macOS Version

| Component | Minimum | Tested | Notes |
|-----------|---------|--------|-------|
| macOS | 14.0 (Sonoma) | 14.0, 15.x | Intel and Apple Silicon (M-series) |
| Swift | 5.9 | 5.9+ | Included with Xcode Command Line Tools |

### Architecture Support

- ✅ **Apple Silicon** (M1, M2, M3, M4, etc.) - Native (arm64)
- ✅ **Intel** (x86_64) - Supported
- All recent Macs (2018+) are supported

## Required Dependencies

### macOS Built-in (No Installation Needed)

| Dependency | Source | Used For | Notes |
|-----------|--------|----------|-------|
| AVFoundation | macOS SDK | Microphone access, speech recognition | Built into macOS |
| ApplicationServices | macOS SDK | Accessibility, window info | Built into macOS |
| Cocoa | macOS SDK | UI, menus, system events | Built into macOS |
| Speech | macOS SDK | SFSpeechRecognizer (speech transcription) | Built into macOS; requires permission |

### External Tools - Installation Required

#### FFmpeg (Required for audio recording)

**Purpose:** Captures microphone audio and converts to WAV format

**Installation:**
```bash
brew install ffmpeg
```

**Version:** Any recent version (tested with 6.0+)

**Verify installation:**
```bash
ffmpeg -version
which ffmpeg
```

**Troubleshoot:**
```bash
# If not in PATH, find it:
find /opt/homebrew -name ffmpeg 2>/dev/null
find /usr/local -name ffmpeg 2>/dev/null
```

---

## Optional Dependencies

### Whisper (Local Speech Recognition - Recommended)

**Purpose:** Offline speech-to-text transcription (fallback when live transcription is empty)

**Installation:**
```bash
./scripts/install-whisper.sh
```

**What it installs:**
- `whisper-cpp` - Fast C++ implementation of OpenAI's Whisper
- Model files (base.en by default, ~140MB)

**Version:** Latest from whisper.cpp repository

**Verify installation:**
```bash
which whisper-cli
whisper-cli -h
```

**Models available:**
- `tiny.en` - Smallest, fastest (~39MB)
- `base.en` - Default, good balance (~140MB) ← Recommended
- `small.en` - More accurate (~466MB)
- `medium.en` - Very accurate (~1.5GB)

**Performance Notes:**
- Larger models are more accurate but slower
- `base.en` processes ~30 seconds of audio in 2-3 seconds
- `tiny.en` is ~2x faster but less accurate

**When Whisper is used:**
- Live transcription (SFSpeechRecognizer) returns empty
- Recorded audio is transcribed via whisper-cpp

---

### Kokoro TTS (Optional Text-to-Speech)

**Purpose:** Local, offline text-to-speech with higher quality voices than system `say`

**Installation:**
```bash
./scripts/install-kokoro.sh
```

**What it installs:**
- Python 3.9+ venv at `~/.openclaw/clawIsland/kokoro-venv/`
- Kokoro TTS library (pip package)
- Model weights (~850MB)

**Requirements:**
- Python 3.9 or later
- ~1.5GB disk space for venv + model

**Verify installation:**
```bash
~/.openclaw/clawIsland/kokoro-venv/bin/python3 -c "import kokoro"
```

**Voice Options:**
- `af_heart` - Balanced female voice (recommended)

**Speed:**
- First TTS request: ~3-5 seconds (loads Python + model)
- Subsequent requests: ~100-500ms per sentence

**When to use Kokoro:**
- You want higher quality voice than system voices
- You prefer local/offline TTS
- You have ~1.5GB spare disk space
- Network latency is a concern

**When system voices are fine:**
- Quick voice interactions
- Network latency is acceptable
- Disk space is limited

---

## Development Dependencies (For Building)

### Required for Building from Source

| Dependency | Purpose | Installation |
|-----------|---------|--------------|
| Swift 5.9+ | Compilation | Xcode or `xcode-select --install` |
| Xcode Command Line Tools | Build tools | `xcode-select --install` |
| Git | Version control | `brew install git` or built-in |

### Optional for Development

| Dependency | Purpose | Installation |
|-----------|---------|--------------|
| python3 | Config scripts, bridge | Usually pre-installed |

### Build Verification

```bash
# Check Swift version
swift --version

# Check Xcode tools
xcode-select -p

# Try building
cd src/clawIsland
swift build -c release
```

---

## Installation Checklist

### Minimal Setup (Voice Input Only)

```bash
# 1. Install FFmpeg
brew install ffmpeg

# 2. Grant system permissions (in System Settings):
# - Microphone ✅
# - Speech Recognition ✅
# - Accessibility ✅

# 3. Build and run
./scripts/build.sh
./scripts/run.sh
```

### Recommended Setup (Voice + Local Transcription)

```bash
# All of above, plus:

# 4. Install Whisper for offline transcription
./scripts/install-whisper.sh
```

### Full Setup (All Features)

```bash
# All of above, plus:

# 5. Install Kokoro for premium local TTS
./scripts/install-kokoro.sh

# 6. Grant Screen Recording permission for screenshots (optional):
# - System Settings → Privacy & Security → Screen Recording ✅
```

---

## Dependency Versions

### Tested and Known-Good

| Component | Version | Status | Notes |
|-----------|---------|--------|-------|
| macOS | 14.0 Sonoma | ✅ Tested | Latest: 15.x |
| macOS | 15.x Sequoia | ✅ Tested | Latest stable |
| Swift | 5.9 | ✅ Tested | Latest: 5.10+ |
| FFmpeg | 6.0, 7.0 | ✅ Tested | Latest recommended |
| whisper.cpp | Latest | ✅ Tested | Auto-installed |
| Kokoro | Latest | ✅ Tested | Auto-installed |
| Python | 3.9+ | ✅ Tested | For Kokoro venv |

---

## Disk Space Requirements

| Component | Space |
|-----------|-------|
| Base app | ~100MB |
| Whisper (base.en) | ~180MB |
| Kokoro (with model) | ~900MB |
| **Total (full install)** | **~1.2GB** |

---

## Network Requirements

| Scenario | Bandwidth | Latency |
|----------|-----------|---------|
| Text input → OpenClaw | Low (<1MB) | Tolerates 50-500ms |
| Microphone streaming | Low | Real-time |
| Model downloads (Whisper/Kokoro) | High (depends on model) | One-time during setup |

---

## M-series Mac Notes (Apple Silicon)

- ✅ Fully native (arm64) - no Rosetta translation
- ✅ FFmpeg installs natively: `brew install ffmpeg`
- ✅ Whisper and Kokoro install natively
- ✅ All performance is excellent on M1/M2/M3/M4

---

## Intel Mac Notes

- ✅ Fully supported (x86_64)
- ⚠️ Slightly slower than Apple Silicon for TTS/transcription
- ✅ All tools (FFmpeg, Whisper, Kokoro) available

---

## Troubleshooting Dependencies

### "ffmpeg not found"

```bash
# Install via Homebrew
brew install ffmpeg

# Or find existing installation
which ffmpeg
```

### "whisper-cli not found"

```bash
# Run the installer
./scripts/install-whisper.sh

# Or manually:
brew install whisper-cpp
```

### "Kokoro python not found"

```bash
# Run the installer
./scripts/install-kokoro.sh

# Or verify Python version:
python3 --version  # Should be 3.9+
```

### Swift Build Failures

```bash
# Update Xcode tools
xcode-select --install

# Or reinstall:
sudo rm -rf /Library/Developer/CommandLineTools
xcode-select --install
```

---

## End-of-Life & Deprecations

- **Minimum macOS**: 14.0 - no plans to support earlier versions
- **Minimum Swift**: 5.9 - tracks current Swift releases
- **Python 2.x**: Not supported; Kokoro requires Python 3.9+

---

## See Also

- [README.md](../README.md) - Installation and setup
- [CONFIG.md](CONFIG.md) - Configuration options
- [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) - Common issues
