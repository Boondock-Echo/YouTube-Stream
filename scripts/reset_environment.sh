#!/usr/bin/env bash
set -euo pipefail

# Stops the YouTube Stream services, removes generated assets, and purges the
# packages installed by install_dependencies.sh so the host is ready for a
# fresh install.

STREAM_USER=${STREAM_USER:-streamer}
APP_DIR=${APP_DIR:-/opt/youtube-stream/webapp}
OBS_HOME=${OBS_HOME:-/var/lib/${STREAM_USER}}
ENV_DIR=${ENV_DIR:-/etc/youtube-stream}
REACT_SERVICE=react-web.service
OBS_SERVICE=obs-headless.service

APT_PACKAGES=(obs-studio nodejs npm ffmpeg xvfb git)
NODESOURCE_LIST=/etc/apt/sources.list.d/nodesource.list
NODESOURCE_KEY=/usr/share/keyrings/nodesource.gpg

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script with sudo or as root." >&2
    exit 1
  fi
}

stop_service_if_present() {
  local unit=$1

  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "$unit" 2>/dev/null || true
    systemctl disable "$unit" 2>/dev/null || true
    rm -f "/etc/systemd/system/${unit}"
  fi
}

kill_processes() {
  pkill -f "xvfb-run.*obs" 2>/dev/null || true
  pkill -f "obs --collection" 2>/dev/null || true
  pkill -f "npm start" 2>/dev/null || true
}

purge_packages() {
  apt-get update
  apt-get remove --purge -y "${APT_PACKAGES[@]}" || true
  apt-get autoremove -y || true
  apt-get autoclean -y || true

  rm -f "$NODESOURCE_LIST" "$NODESOURCE_KEY"
}

clean_paths() {
  rm -rf "$APP_DIR" "$OBS_HOME" "$ENV_DIR"
}

main() {
  require_root

  stop_service_if_present "$REACT_SERVICE"
  stop_service_if_present "$OBS_SERVICE"
  kill_processes

  purge_packages

  clean_paths

  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
  fi

  echo "Environment reset complete. Re-run install_dependencies.sh to reinstall requirements."
}

main "$@"
