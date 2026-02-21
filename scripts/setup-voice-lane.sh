#!/bin/bash
set -euo pipefail

VOICE_PROFILE="${VOICE_PROFILE:-voice}"
VOICE_PORT="${VOICE_PORT:-18791}"
MILO_CONFIG_PATH="${MILO_CONFIG_PATH:-$HOME/.openclaw/clawIsland.json}"
OPENCLAW_BIN="${OPENCLAW_BIN:-$(command -v openclaw)}"
OPENCLAW_BIN_DIR="$(dirname "$OPENCLAW_BIN")"

oc() {
  PATH="$OPENCLAW_BIN_DIR:$PATH" "$OPENCLAW_BIN" "$@"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ Missing required command: $1"
    exit 1
  fi
}

set_profile_config() {
  local path="$1"
  local value="$2"
  oc --profile "$VOICE_PROFILE" config set "$path" "$value" >/dev/null
}

set_profile_config_json() {
  local path="$1"
  local value="$2"
  oc --profile "$VOICE_PROFILE" config set --json "$path" "$value" >/dev/null
}

try_profile_config_json() {
  local path="$1"
  local value="$2"
  if ! oc --profile "$VOICE_PROFILE" config set --json "$path" "$value" >/dev/null 2>&1; then
    echo "⚠️ Skipping optional config path: $path"
  fi
}

read_main_gateway_token() {
  oc config get gateway.auth.token 2>/dev/null || true
}

read_main_gateway_nodes() {
  oc config get gateway.nodes 2>/dev/null || true
}

read_main_config_json() {
  local path="$1"
  oc config get "$path" 2>/dev/null || true
}

sync_main_config_json() {
  local path="$1"
  local value
  value="$(read_main_config_json "$path")"
  if [[ -z "$value" ]]; then
    return
  fi
  if ! oc --profile "$VOICE_PROFILE" config set --json "$path" "$value" >/dev/null 2>&1; then
    echo "⚠️ Could not sync config path: $path"
  fi
}

sync_voice_agent_auth() {
  local source_base=""
  local target_base="$HOME/.openclaw-${VOICE_PROFILE}/agents/voice/agent"

  if [[ -d "$HOME/.openclaw/agents/voice/agent" ]]; then
    source_base="$HOME/.openclaw/agents/voice/agent"
  elif [[ -d "$HOME/.openclaw/agents/main/agent" ]]; then
    source_base="$HOME/.openclaw/agents/main/agent"
  fi

  if [[ -z "$source_base" ]]; then
    echo "⚠️ No source agent auth directory found in ~/.openclaw"
    return
  fi

  mkdir -p "$target_base"

  if [[ -f "$source_base/auth-profiles.json" ]]; then
    cp "$source_base/auth-profiles.json" "$target_base/auth-profiles.json"
  fi
  if [[ -f "$source_base/auth.json" ]]; then
    cp "$source_base/auth.json" "$target_base/auth.json"
  fi
}

sync_voice_agent_context() {
  local source_base=""
  local target_base="$HOME/.openclaw-${VOICE_PROFILE}/agents/voice"

  if [[ -d "$HOME/.openclaw/agents/voice" ]]; then
    source_base="$HOME/.openclaw/agents/voice"
  fi

  if [[ -z "$source_base" ]]; then
    return
  fi

  mkdir -p "$target_base/agent" "$target_base/sessions" "$target_base/qmd"

  if [[ -f "$source_base/agent/models.json" ]]; then
    cp "$source_base/agent/models.json" "$target_base/agent/models.json"
  fi

  # Mirror the qmd index so memory retrieval has the same prior context corpus.
  if [[ -d "$source_base/qmd" ]]; then
    if command -v rsync >/dev/null 2>&1; then
      rsync -a "$source_base/qmd/" "$target_base/qmd/"
    else
      cp -R "$source_base/qmd/." "$target_base/qmd/"
    fi
  fi
}

sync_main_session_mapping() {
  python3 - <<'PY'
import json
import os
import shutil

main_root = os.path.expanduser("~/.openclaw/agents/voice/sessions")
voice_root = os.path.expanduser("~/.openclaw-voice/agents/voice/sessions")
session_key = "agent:voice:main"

main_map_path = os.path.join(main_root, "sessions.json")
voice_map_path = os.path.join(voice_root, "sessions.json")

if not os.path.exists(main_map_path):
    raise SystemExit(0)

with open(main_map_path, "r", encoding="utf-8") as f:
    main_map = json.load(f)

entry = main_map.get(session_key)
if not isinstance(entry, dict):
    raise SystemExit(0)

os.makedirs(voice_root, exist_ok=True)
voice_map = {}
if os.path.exists(voice_map_path):
    with open(voice_map_path, "r", encoding="utf-8") as f:
        voice_map = json.load(f)

voice_map[session_key] = entry

with open(voice_map_path, "w", encoding="utf-8") as f:
    json.dump(voice_map, f, indent=2, sort_keys=True)
    f.write("\n")

session_id = entry.get("sessionId")
if session_id:
    src_file = os.path.join(main_root, f"{session_id}.jsonl")
    dst_file = os.path.join(voice_root, f"{session_id}.jsonl")
    if os.path.exists(src_file):
        shutil.copy2(src_file, dst_file)
PY
}

install_and_start_gateway() {
  local token="$1"
  local install_cmd=(oc --profile "$VOICE_PROFILE" gateway install --force --port "$VOICE_PORT")
  if [[ -n "$token" ]]; then
    install_cmd+=(--token "$token")
  fi
  "${install_cmd[@]}" >/dev/null

  if ! oc --profile "$VOICE_PROFILE" gateway restart --json >/dev/null 2>&1; then
    oc --profile "$VOICE_PROFILE" gateway start --json >/dev/null
  fi
}

write_claw_island_config() {
  local token="$1"
  python3 - "$MILO_CONFIG_PATH" "$VOICE_PORT" "$token" <<'PY'
import json
import os
import sys

config_path = os.path.expanduser(sys.argv[1])
port = int(sys.argv[2])
token = sys.argv[3]

cfg = {}
if os.path.exists(config_path):
    with open(config_path, "r", encoding="utf-8") as f:
        cfg = json.load(f)

cfg["gatewayUrl"] = f"http://localhost:{port}"
if token:
    cfg["gatewayToken"] = token

cfg.setdefault("agentId", "voice")
cfg.setdefault("sessionKey", "agent:voice:main")
cfg.setdefault("relayOnlyMode", True)
cfg.setdefault("maxTokens", 512)
cfg["adaptiveMaxTokensEnabled"] = True
cfg["adaptiveMaxTokensFloor"] = 128
cfg["speculativePrewarmEnabled"] = True
cfg["speculativePrewarmMinWords"] = 5
cfg["speculativePrewarmCooldownSeconds"] = 90

os.makedirs(os.path.dirname(config_path), exist_ok=True)
with open(config_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
    f.write("\n")
PY
}

print_status_summary() {
  local token="$1"
  if [[ -n "$token" ]]; then
    oc --profile "$VOICE_PROFILE" gateway status --json --token "$token"
  else
    oc --profile "$VOICE_PROFILE" gateway status --json
  fi
}

main() {
  require_command openclaw
  require_command python3

  echo "🛣️ Setting up dedicated OpenClaw voice lane"
  echo "   profile: $VOICE_PROFILE"
  echo "   port:    $VOICE_PORT"

  local token
  token="$(read_main_gateway_token)"
  local nodes_json
  nodes_json="$(read_main_gateway_nodes)"

  sync_main_config_json "agents.defaults"
  sync_main_config_json "agents.list"
  sync_main_config_json "memory"
  sync_main_config_json "hooks.internal"
  sync_main_config_json "plugins.load.paths"
  sync_main_config_json "plugins.entries[\"state-consistency-bridge\"]"

  set_profile_config "gateway.mode" "local"
  set_profile_config "gateway.bind" "loopback"
  set_profile_config "gateway.port" "$VOICE_PORT"
  set_profile_config "gateway.auth.mode" "token"
  if [[ -n "$token" ]]; then
    set_profile_config "gateway.auth.token" "$token"
  fi
  set_profile_config_json "gateway.http.endpoints.chatCompletions.enabled" "true"
  if [[ -n "$nodes_json" ]]; then
    oc --profile "$VOICE_PROFILE" config set --json "gateway.nodes" "$nodes_json" >/dev/null || true
  fi

  # Keep the voice lane lean: disable chat channel ingress and heavy plugins.
  set_profile_config_json "channels.telegram.enabled" "false"
  try_profile_config_json "plugins.entries.telegram.enabled" "false"
  try_profile_config_json "plugins.entries.whatsapp.enabled" "false"
  try_profile_config_json "plugins.entries[\"voice-call\"].enabled" "false"
  try_profile_config_json "plugins.entries[\"state-consistency-bridge\"].enabled" "true"

  sync_voice_agent_auth
  sync_voice_agent_context
  sync_main_session_mapping
  install_and_start_gateway "$token"
  write_claw_island_config "$token"

  echo "✅ Voice lane configured."
  echo "📡 clawIsland now targets http://localhost:$VOICE_PORT"
  echo "🔎 Current gateway status:"
  print_status_summary "$token"
}

main "$@"
