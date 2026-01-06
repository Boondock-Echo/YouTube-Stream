#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/youtube-stream/webapp}"
OBS_HOME="${OBS_HOME:-/var/lib/${STREAM_USER:-streamer}}"

export HOME="$OBS_HOME"

cd "$APP_DIR"
npm install
npm run build

HOST=0.0.0.0 PORT=3000 exec npx --yes serve -s build -l tcp://0.0.0.0:3000
