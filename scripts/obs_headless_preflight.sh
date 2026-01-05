#!/usr/bin/env bash
set -euo pipefail

# Preflight guard for obs-headless.service
# Ensures the OBS profile, scene collection, and stream key are present before
# launching OBS with --startstreaming to avoid crashes like
# `basic_string: construction from null is not valid` when output settings are
# missing.

STREAM_USER=${STREAM_USER:-streamer}
OBS_HOME=${OBS_HOME:-/var/lib/${STREAM_USER}}
CONFIG_ROOT=${CONFIG_ROOT:-${OBS_HOME}/.config/obs-studio}
COLLECTION_NAME=${COLLECTION_NAME:-YouTubeHeadless}
SCENE_FILE="$CONFIG_ROOT/basic/scenes/${COLLECTION_NAME}.json"
PROFILE_DIR="$CONFIG_ROOT/basic/profiles/${COLLECTION_NAME}"
SERVICE_FILE="$PROFILE_DIR/service.json"

normalize_key() {
  local key="${1:-}"
  key="${key%$'\r'}"
  key="${key#${key%%[![:space:]]*}}"
  key="${key%${key##*[![:space:]]}}"

  if [[ ${#key} -ge 2 ]]; then
    local first=${key:0:1}
    local last=${key: -1}
    if [[ ( "$first" == '"' && "$last" == '"' ) || ( "$first" == "'" && "$last" == "'" ) ]]; then
      key="${key:1:-1}"
    fi
  fi

  printf '%s' "$key"
}

fail() {
  echo "[obs-headless-preflight] $*" >&2
  exit 1
}

if ! command -v jq >/dev/null 2>&1; then
  fail "jq is required (install_dependencies.sh installs it)."
fi

[[ -f "$SCENE_FILE" ]] || fail "Scene collection missing at $SCENE_FILE (run scripts/configure_obs.sh)."
[[ -f "$SERVICE_FILE" ]] || fail "OBS service configuration missing at $SERVICE_FILE (run scripts/configure_obs.sh)."

service_key=$(normalize_key "$(jq -r '.settings.key // empty' "$SERVICE_FILE" 2>/dev/null || true)")
service_server=$(jq -r '.settings.server // empty' "$SERVICE_FILE" 2>/dev/null || true)
env_key=$(normalize_key "${YOUTUBE_STREAM_KEY:-}")

if [[ -z "$service_key" && -z "$env_key" ]]; then
  fail "Stream key missing (service.json empty and YOUTUBE_STREAM_KEY not provided)."
fi

[[ -n "$service_server" ]] || fail "Stream server missing in $SERVICE_FILE."

echo "[obs-headless-preflight] OBS profile and stream target are present."
