#!/usr/bin/env bash
set -euo pipefail

# Installs Node.js, OBS Studio, and supporting dependencies for headless streaming.

APP_DIR=${APP_DIR:-/opt/youtube-stream/webapp}
STREAM_USER=${STREAM_USER:-streamer}
NODE_MAJOR=${NODE_MAJOR:-20}

export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo or as root so it can install packages and manage ${STREAM_USER}." >&2
  exit 1
fi

# Update apt metadata and install base tools
apt-get update
apt-get install -y ca-certificates curl gnupg software-properties-common build-essential ffmpeg xvfb git

# Install Node.js from NodeSource if missing or too old
if ! command_exists node || ! node -e "process.exit(Number(process.versions.node.split('.')[0]) >= ${NODE_MAJOR} ? 0 : 1)"; then
  NODE_KEYRING=/usr/share/keyrings/nodesource.gpg
  if [ ! -f "$NODE_KEYRING" ]; then
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o "$NODE_KEYRING"
  fi
  DISTRO_CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [signed-by=${NODE_KEYRING}] https://deb.nodesource.com/node_${NODE_MAJOR}.x ${DISTRO_CODENAME} main" > /etc/apt/sources.list.d/nodesource.list
  apt-get update
  apt-get install -y nodejs
fi

# Install OBS Studio (with PPA on Ubuntu LTS machines)
if ! command_exists obs; then
  add-apt-repository -y ppa:obsproject/obs-studio
  apt-get update
  apt-get install -y obs-studio
fi

# Ensure the service user exists
if ! id -u "$STREAM_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "/var/lib/${STREAM_USER}" --shell /bin/bash "$STREAM_USER"
fi

mkdir -p "$APP_DIR"
chown -R "$STREAM_USER":"$STREAM_USER" "$APP_DIR"

echo "Dependencies installed. Proceed with scripts/bootstrap_react_app.sh and scripts/configure_obs.sh." 
