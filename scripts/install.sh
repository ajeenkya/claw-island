#!/bin/bash
set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
REPO_URL="https://github.com/ajeenkya/claw-island.git"
INSTALL_DIR="$HOME/.openclaw/workspace/claw-island"
CONFIG_FILE="$HOME/.openclaw/clawIsland.json"
GATEWAY_URL="http://localhost:18789"
MIN_MACOS_MAJOR=14

# Step counts are phase-local to avoid confusing output across the exec
# boundary between Phase 1 (piped) and Phase 2 (from disk).
PHASE1_STEPS=3
PHASE2_STEPS=5

# ── Argument Parsing ─────────────────────────────────────────────────────────
PHASE2=0
NON_INTERACTIVE="${CLAW_ISLAND_NON_INTERACTIVE:-0}"

usage() {
  cat <<'USAGE'
Usage: install.sh [OPTIONS]

One-line installer for Claw Island — macOS menu-bar voice overlay for OpenClaw.

  curl -sSL https://raw.githubusercontent.com/ajeenkya/claw-island/main/scripts/install.sh | bash

Options:
  --non-interactive   Skip all optional prompts (install core components only)
  --help, -h          Show this help message

Environment:
  CLAW_ISLAND_NON_INTERACTIVE=1   Same as --non-interactive (useful with curl|bash)

When run interactively, the installer will offer optional components:
  • Kokoro TTS (local open-source voice synthesis)
  • Dedicated OpenClaw voice lane
  • Push-to-talk hotkey customization
  • TTS voice selection
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --phase2)          PHASE2=1 ;;             # internal: set by Phase 1 exec
    --non-interactive) NON_INTERACTIVE=1 ;;
    --help|-h)         usage; exit 0 ;;
  esac
done

# ── Color & Output Utilities ─────────────────────────────────────────────────
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  RED='\033[0;31m'  GREEN='\033[0;32m'  YELLOW='\033[0;33m'
  BLUE='\033[0;34m' BOLD='\033[1m'      RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' RESET=''
fi

info()    { printf "%b==>%b %b%s%b\n" "$BLUE" "$RESET" "$BOLD" "$*" "$RESET"; }
success() { printf " %b✓%b  %s\n" "$GREEN" "$RESET" "$*"; }
warn()    { printf " %b⚠%b  %s\n" "$YELLOW" "$RESET" "$*" >&2; }
fail()    { printf " %b✗%b  %s\n" "$RED" "$RESET" "$*" >&2; exit 1; }

STEP=0
TOTAL_STEPS=0
step() {
  STEP=$((STEP + 1))
  printf "\n%b[%d/%d]%b %s\n" "$BOLD" "$STEP" "$TOTAL_STEPS" "$RESET" "$*"
}
start_phase() { STEP=0; TOTAL_STEPS="$1"; }

# Read from /dev/tty explicitly so prompts work after `curl | bash` pipes
# stdin. In Phase 2 (exec'd with </dev/tty), this is redundant but harmless.
ask_yn() {
  local prompt="$1" default="${2:-n}"
  if [[ $NON_INTERACTIVE -eq 1 ]]; then
    [[ "$default" == "y" ]]
    return
  fi
  local yn
  read -r -p "$prompt [y/N] " yn </dev/tty || yn="$default"
  [[ "$yn" =~ ^[Yy] ]]
}

# Friendly message on Ctrl-C instead of silent exit
trap 'printf "\n"; warn "Installation interrupted. Re-run to resume safely."; exit 130' INT

print_banner() {
  printf "%b" "$BOLD"
  cat <<'BANNER'

   _____ _                   _____     _                 _
  / ____| |                 |_   _|   | |               | |
 | |    | | __ ___      __    | |  ___| | __ _ _ __   __| |
 | |    | |/ _` \ \ /\ / /    | | / __| |/ _` | '_ \ / _` |
 | |____| | (_| |\ V  V /    _| |_\__ \ | (_| | | | | (_| |
  \_____|_|\__,_| \_/\_/    |_____|___/_|\__,_|_| |_|\__,_|

BANNER
  printf "%b" "$RESET"
  echo "  macOS menu-bar voice overlay for OpenClaw"
  echo ""
}

# ── Prerequisite Checks ─────────────────────────────────────────────────────
check_prerequisites() {
  step "🔍 Checking prerequisites"

  # macOS version
  local macos_ver macos_major
  macos_ver="$(sw_vers -productVersion)"
  macos_major="${macos_ver%%.*}"
  if [[ "$macos_major" -lt "$MIN_MACOS_MAJOR" ]]; then
    fail "macOS $MIN_MACOS_MAJOR+ required (found $macos_ver)"
  fi
  success "macOS $macos_ver"

  # Xcode CLI tools
  if ! xcode-select -p &>/dev/null; then
    info "Installing Xcode Command Line Tools..."
    xcode-select --install 2>/dev/null || true
    fail "Xcode CLI tools installation started. Please re-run this installer after it completes."
  fi
  success "Xcode Command Line Tools found"

  # Homebrew
  if ! command -v brew &>/dev/null; then
    fail "Homebrew is required. Install from https://brew.sh"
  fi
  success "Homebrew found"

  # Swift
  if ! command -v swift &>/dev/null; then
    fail "Swift not found. Install Xcode or Xcode Command Line Tools."
  fi
  local swift_ver
  swift_ver="$(swift --version 2>&1 | head -1)"
  success "$swift_ver"
}

# ── Install Core Dependencies ────────────────────────────────────────────────
install_core_deps() {
  step "📦 Installing core dependencies"

  if ! command -v ffmpeg &>/dev/null; then
    info "Installing ffmpeg via Homebrew..."
    brew install ffmpeg
  fi
  success "ffmpeg available"
}

# ── Clone or Update Repo ────────────────────────────────────────────────────
clone_or_update() {
  step "📥 Fetching Claw Island source"

  if [[ -d "$INSTALL_DIR" ]] && [[ ! -d "$INSTALL_DIR/.git" ]]; then
    fail "$INSTALL_DIR exists but is not a git repository. Remove it and re-run."
  fi

  if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Updating existing clone..."
    git -C "$INSTALL_DIR" pull --ff-only 2>/dev/null || warn "Pull failed; continuing with existing code"
  else
    mkdir -p "$(dirname "$INSTALL_DIR")"
    info "Cloning repository..."
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
  success "Source at $INSTALL_DIR"
}

# ── Phase 1: Bootstrap (runs when piped via curl | bash) ─────────────────────
# When piped, stdin is consumed by the script content so interactive reads fail.
# Phase 1 does non-interactive work (prereqs, clone), then exec's the cloned
# copy with </dev/tty to restore terminal input for Phase 2's interactive prompts.
if [[ $PHASE2 -eq 0 ]] && ! [[ -t 0 ]]; then
  print_banner
  start_phase "$PHASE1_STEPS"

  check_prerequisites
  install_core_deps
  clone_or_update

  # Re-exec from cloned copy with terminal stdin restored
  info "Handing off to cloned installer..."
  if ! [[ -e /dev/tty ]]; then
    fail "No terminal available (/dev/tty missing). Re-run with: $INSTALL_DIR/scripts/install.sh --non-interactive"
  fi
  exec "$INSTALL_DIR/scripts/install.sh" --phase2 "$@" </dev/tty
fi

# ── Phase 2: Build and Configure ────────────────────────────────────────────

# When run directly (not piped, no --phase2), do everything in one pass with a
# combined step counter. When arriving from Phase 1, start a fresh counter.
if [[ $PHASE2 -eq 0 ]]; then
  print_banner
  start_phase "$((PHASE1_STEPS + PHASE2_STEPS))"
  check_prerequisites
  install_core_deps
  clone_or_update
else
  start_phase "$PHASE2_STEPS"
fi

# Resolve repo root from this script's location on disk
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/scripts"

# ── Build + .app bundle ──────────────────────────────────────────────────────
# install-app.sh already calls `swift build -c release` internally, so we do
# NOT call build.sh separately here.
step "🔨 Building and installing clawIsland.app"
"$SCRIPTS/install-app.sh"

# ── Whisper speech recognition ───────────────────────────────────────────────
step "🎙️ Installing Whisper speech recognition"
"$SCRIPTS/install-whisper.sh"

# ── Optional components ──────────────────────────────────────────────────────
step "⚙️ Optional components"

# Kokoro TTS
if ask_yn "  Install Kokoro TTS for local voice synthesis? (~500MB, requires Python 3.10-3.12)" "n"; then
  if command -v python3.11 &>/dev/null || [[ -x /opt/homebrew/bin/python3.11 ]]; then
    "$SCRIPTS/install-kokoro.sh"
  else
    warn "Python 3.11 not found (required by install-kokoro.sh). Install with: brew install python@3.11"
    info "You can install Kokoro later with: $INSTALL_DIR/scripts/install-kokoro.sh"
  fi
else
  info "Skipping Kokoro TTS (install later: $INSTALL_DIR/scripts/install-kokoro.sh)"
fi

# Voice lane (requires openclaw CLI)
if command -v openclaw &>/dev/null; then
  if ask_yn "  Set up dedicated OpenClaw voice lane?" "n"; then
    "$SCRIPTS/setup-voice-lane.sh"
  else
    info "Skipping voice lane (set up later: $INSTALL_DIR/scripts/setup-voice-lane.sh)"
  fi
else
  info "Skipping voice lane (openclaw CLI not found)"
fi

# Hotkey
if ask_yn "  Customize push-to-talk hotkey? (default: fn)" "n"; then
  "$SCRIPTS/change-hotkey.sh"
fi

# Voice
if ask_yn "  Customize TTS voice?" "n"; then
  "$SCRIPTS/change-voice.sh"
fi

# ── Gateway reachability ─────────────────────────────────────────────────────
step "📡 Checking OpenClaw gateway"
if curl -s --connect-timeout 3 "$GATEWAY_URL/health" &>/dev/null \
   || curl -s --connect-timeout 3 "$GATEWAY_URL" &>/dev/null; then
  success "OpenClaw gateway reachable at $GATEWAY_URL"
else
  warn "OpenClaw gateway not reachable at $GATEWAY_URL"
  echo "  Start your gateway, or update gatewayUrl in $CONFIG_FILE"
fi

# ── Permissions ──────────────────────────────────────────────────────────────
step "🔐 Checking permissions"
"$SCRIPTS/check-permissions.sh" || true

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
printf "%b%b" "$GREEN" "$BOLD"
echo "╔═══════════════════════════════════════════╗"
echo "║   Claw Island installation complete!     ║"
echo "╚═══════════════════════════════════════════╝"
printf "%b" "$RESET"
echo ""
echo "  App:      ~/Desktop/clawIsland.app"
echo "  Config:   $CONFIG_FILE"
echo "  Source:    $INSTALL_DIR"
echo ""
printf "%b  Next steps:%b\n" "$BOLD" "$RESET"
echo "  1. Ensure OpenClaw gateway is running at $GATEWAY_URL"
echo "  2. Launch:  open -a ~/Desktop/clawIsland.app"
echo "  3. Grant permissions when prompted (mic, accessibility)"
echo "  4. Press fn to talk!"
echo ""
printf "%b  Reconfigure anytime:%b\n" "$BOLD" "$RESET"
echo "    $INSTALL_DIR/scripts/change-hotkey.sh      # change push-to-talk key"
echo "    $INSTALL_DIR/scripts/change-voice.sh       # change TTS voice"
echo "    $INSTALL_DIR/scripts/install-kokoro.sh     # add Kokoro TTS"
echo "    $INSTALL_DIR/scripts/setup-voice-lane.sh   # dedicated voice gateway"
echo ""
