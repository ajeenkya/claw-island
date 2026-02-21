#!/bin/bash
set -euo pipefail

DB_PATH="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
OPEN_SETTINGS=1
DO_RESET=0
RESET_TARGETS=()

usage() {
  cat <<'EOF'
Usage: ./scripts/screen-recording-doctor.sh [options]

Diagnose and fix macOS Screen Recording permissions used by OpenClaw workflows.

Options:
  --no-open                 Do not open System Settings automatically.
  --reset                   Reset Screen Recording permission for default targets.
  --reset-client <bundle>   Reset Screen Recording permission for a specific bundle id.
  -h, --help                Show this help.

Examples:
  ./scripts/screen-recording-doctor.sh
  ./scripts/screen-recording-doctor.sh --reset
  ./scripts/screen-recording-doctor.sh --reset-client com.openclaw.clawIsland
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-open)
      OPEN_SETTINGS=0
      shift
      ;;
    --reset)
      DO_RESET=1
      shift
      ;;
    --reset-client)
      if [[ $# -lt 2 ]]; then
        echo "❌ --reset-client requires a bundle id"
        exit 1
      fi
      DO_RESET=1
      RESET_TARGETS+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "❌ Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ ! -f "$DB_PATH" ]]; then
  echo "❌ TCC database not found at: $DB_PATH"
  exit 1
fi

can_read_tcc_db=1
auth_column="allowed"
if ! sqlite3 "$DB_PATH" "SELECT 1;" >/dev/null 2>&1; then
  can_read_tcc_db=0
else
  if sqlite3 "$DB_PATH" "PRAGMA table_info(access);" 2>/dev/null | awk -F'|' '$2=="auth_value"{found=1} END{exit(found?0:1)}'; then
    auth_column="auth_value"
  fi
fi

declare -a DEFAULT_CLIENTS=(
  "com.openclaw.clawIsland"
  "com.openclaw.vyom-overlay"
  "com.openai.codex"
  "com.mitchellh.ghostty"
  "com.apple.Terminal"
  "com.googlecode.iterm2"
)

shell_bundle_id=""
case "${TERM_PROGRAM:-}" in
  ghostty)
    shell_bundle_id="com.mitchellh.ghostty"
    ;;
  Apple_Terminal)
    shell_bundle_id="com.apple.Terminal"
    ;;
  iTerm.app|iTerm2)
    shell_bundle_id="com.googlecode.iterm2"
    ;;
esac

if [[ ${#RESET_TARGETS[@]} -eq 0 ]]; then
  if [[ $DO_RESET -eq 1 ]]; then
    RESET_TARGETS=("com.openclaw.clawIsland")
    if [[ -n "$shell_bundle_id" ]]; then
      RESET_TARGETS+=("$shell_bundle_id")
    fi
  fi
fi

status_for_client() {
  local client="$1"
  if [[ $can_read_tcc_db -ne 1 ]]; then
    echo "UNKNOWN(DB_BLOCKED)"
    return
  fi

  local raw
  raw=$(sqlite3 "$DB_PATH" "SELECT ${auth_column} FROM access WHERE service='kTCCServiceScreenCapture' AND client='${client}' ORDER BY last_modified DESC LIMIT 1;" 2>/dev/null || true)

  if [[ -z "$raw" ]]; then
    echo "UNKNOWN"
    return
  fi

  if [[ "$auth_column" == "auth_value" ]]; then
    case "$raw" in
      2) echo "GRANTED" ;;
      3) echo "LIMITED" ;;
      0|1) echo "DENIED" ;;
      *) echo "UNKNOWN(${raw})" ;;
    esac
  else
    case "$raw" in
      1) echo "GRANTED" ;;
      0) echo "DENIED" ;;
      *) echo "UNKNOWN(${raw})" ;;
    esac
  fi
}

echo "🖥️  Screen Recording Permission Doctor"
if [[ $can_read_tcc_db -eq 1 ]]; then
  echo "ℹ️  TCC auth column: ${auth_column}"
else
  echo "⚠️  TCC DB read is blocked for this process (macOS privacy guard)."
  echo "ℹ️  Status lines below are best-effort only; use probe + Settings pane."
fi
if [[ -n "$shell_bundle_id" ]]; then
  echo "ℹ️  Current shell host app: ${shell_bundle_id}"
fi
echo ""

echo "📋 Current status:"
for client in "${DEFAULT_CLIENTS[@]}"; do
  status="$(status_for_client "$client")"
  case "$status" in
    GRANTED) icon="✅" ;;
    DENIED) icon="❌" ;;
    LIMITED) icon="⚠️ " ;;
    *) icon="•" ;;
  esac
  printf "  %s %s -> %s\n" "$icon" "$client" "$status"
done
echo ""

if [[ $DO_RESET -eq 1 ]]; then
  echo "♻️  Resetting Screen Recording permissions:"
  for client in "${RESET_TARGETS[@]}"; do
    echo "  • tccutil reset ScreenCapture $client"
    tccutil reset ScreenCapture "$client" >/dev/null 2>&1 || true
  done
  echo "✅ Reset complete"
  echo ""
fi

echo "🧪 Triggering permission probe from current shell app (screencapture)..."
probe_file="/tmp/openclaw-screen-permission-probe-$$.png"
if /usr/sbin/screencapture -x "$probe_file" >/dev/null 2>&1; then
  if [[ -s "$probe_file" ]]; then
    echo "✅ Probe captured (${probe_file})"
  else
    echo "⚠️ Probe command returned success but image is empty"
  fi
else
  echo "❌ Probe failed (likely missing Screen Recording permission for this shell app)"
fi
rm -f "$probe_file"
echo ""

if [[ $OPEN_SETTINGS -eq 1 ]]; then
  echo "↗️  Opening System Settings → Privacy & Security → Screen Recording"
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" || true
  echo ""
fi

echo "Next steps:"
echo "1) Enable: clawIsland, your terminal app, and Codex (if present)."
echo "2) Quit and relaunch the apps after toggling."
echo "3) Retry your OpenClaw screenshot/screen action."
echo ""
echo "If it is still stuck, run:"
echo "  ./scripts/screen-recording-doctor.sh --reset"
