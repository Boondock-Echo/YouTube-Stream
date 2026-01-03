#!/usr/bin/env bash
set -euo pipefail

# Ensures the streamer service account exists with the expected home,
# permissions, and password.

STREAM_USER=${STREAM_USER:-streamer}
OBS_HOME=${OBS_HOME:-/var/lib/${STREAM_USER}}
PASSWORD=${PASSWORD:-BoondockEcho2025&}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script with sudo or as root." >&2
    exit 1
  fi
}

ensure_user() {
  if id -u "$STREAM_USER" >/dev/null 2>&1; then
    echo "User $STREAM_USER already exists."
  else
    useradd --create-home --home-dir "$OBS_HOME" --shell /bin/bash "$STREAM_USER"
    echo "Created user $STREAM_USER with home $OBS_HOME"
  fi

  mkdir -p "$OBS_HOME"
  chown -R "$STREAM_USER":"$STREAM_USER" "$OBS_HOME"
  chmod 755 "$OBS_HOME"

  echo "$STREAM_USER:${PASSWORD}" | chpasswd
}

main() {
  require_root
  ensure_user
  echo "User $STREAM_USER is ready with configured password and home at $OBS_HOME."
}

main "$@"
