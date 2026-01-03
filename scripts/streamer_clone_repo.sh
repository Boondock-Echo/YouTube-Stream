#!/usr/bin/env bash
set -euo pipefail

# Clones the YouTube Stream repository into the streamer user's home directory.

STREAM_USER=${STREAM_USER:-streamer}
OBS_HOME=${OBS_HOME:-/var/lib/${STREAM_USER}}
REPO_URL=${REPO_URL:-https://github.com/your-org/YouTube-Stream.git}
TARGET_DIR=${TARGET_DIR:-$OBS_HOME/YouTube-Stream}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script with sudo or as root." >&2
    exit 1
  fi
}

main() {
  require_root

  if [ -d "$TARGET_DIR" ]; then
    echo "Target directory $TARGET_DIR already exists; skipping clone."
    exit 0
  fi

  sudo -u "$STREAM_USER" git clone "$REPO_URL" "$TARGET_DIR"
  echo "Repository cloned to $TARGET_DIR as user $STREAM_USER."
}

main "$@"
