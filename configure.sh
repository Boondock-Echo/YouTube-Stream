#!/usr/bin/env bash
set -euo pipefail

# Wrapper that ensures the OBS scene collection JSON can be recreated cleanly
# before delegating to the main configuration script.
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTION_NAME="${COLLECTION_NAME:-YouTubeHeadless}"
CONFIG_ROOT="/var/lib/streamer/.config/obs-studio"
SCENE_FILE="${CONFIG_ROOT}/basic/scenes/${COLLECTION_NAME}.json"

# Remove the existing scene collection so configure_obs.sh rewrites it with the
# latest settings instead of keeping stale content.
if [[ -f "${SCENE_FILE}" ]]; then
  echo "Removing existing scene file at ${SCENE_FILE} to recreate it."
  rm -f "${SCENE_FILE}"
fi

exec "${SCRIPT_DIR}/scripts/configure_obs.sh" "$@"
