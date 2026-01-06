#!/usr/bin/env bash
set -euo pipefail

# Installs Node.js, OBS Studio, and supporting dependencies for headless streaming.

APP_DIR=${APP_DIR:-/opt/youtube-stream/webapp}
STREAM_USER=${STREAM_USER:-streamer}
OBS_HOME=${OBS_HOME:-/var/lib/${STREAM_USER}}
NODE_MAJOR=${NODE_MAJOR:-20}

export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

install_optional_packages() {
  local available=() missing=() pkg

  for pkg in "$@"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
      available+=("$pkg")
    else
      missing+=("$pkg")
    fi
  done

  if [[ ${#available[@]} -gt 0 ]]; then
    echo "Installing optional OBS plugin packages: ${available[*]}"
    apt-get install -y "${available[@]}"
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Optional OBS plugin packages not found in APT (browser/VLC sources may be unavailable): ${missing[*]}" >&2
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo or as root so it can install packages and manage ${STREAM_USER}." >&2
  exit 1
fi

# Update apt metadata and install base tools
apt-get update
apt-get install -y ca-certificates curl gnupg software-properties-common build-essential ffmpeg xvfb git jq curl

# Install Node.js from NodeSource if missing or too old
if ! command_exists node || ! node -e "process.exit(Number(process.versions.node.split('.')[0]) >= ${NODE_MAJOR} ? 0 : 1)"; then
  NODE_KEYRING=/etc/apt/keyrings/nodesource.gpg
  mkdir -p /etc/apt/keyrings
  if [ ! -f "$NODE_KEYRING" ]; then
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o "$NODE_KEYRING"
  fi
  echo "deb [signed-by=${NODE_KEYRING}] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list > /dev/null
  apt-get update
  apt-get install -y nodejs
fi

# Install OBS Studio (with PPA on Ubuntu LTS machines)
if ! command_exists obs; then
  add-apt-repository -y ppa:obsproject/obs-studio
  apt-get update
  apt-get install -y obs-studio
fi

# Ensure browser/vlc plugins are available for the generated scene collection
install_optional_packages obs-plugins obs-plugins-browser obs-plugins-vlc obs-browser obs-vlc

# Ensure the service user exists
if ! id -u "$STREAM_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "$OBS_HOME" --shell /bin/bash "$STREAM_USER"
fi

# Ensure the service account can read/write OBS and the app directory
usermod -a -G video,audio,render "$STREAM_USER" 2>/dev/null || true
mkdir -p "$OBS_HOME" "$OBS_HOME/.config/obs-studio" "$OBS_HOME/logs" "$APP_DIR"
chown -R "$STREAM_USER":"$STREAM_USER" "$OBS_HOME" "$APP_DIR"

echo "Dependencies installed. Proceed with scripts/install/bootstrap_react_app.sh and scripts/config/configure_obs.sh."
