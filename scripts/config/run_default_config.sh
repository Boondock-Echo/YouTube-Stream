#!/usr/bin/env bash
set -euo pipefail

# Runs configure_obs.sh with a default YouTube stream key.

STREAM_USER=${STREAM_USER:-streamer}
OBS_HOME=${OBS_HOME:-/var/lib/${STREAM_USER}}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
YOUTUBE_STREAM_KEY=${YOUTUBE_STREAM_KEY:-kdyd-zy0c-57zu-9evj-25wj}

export STREAM_USER OBS_HOME YOUTUBE_STREAM_KEY

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi

"$SCRIPT_DIR/configure_obs.sh"
