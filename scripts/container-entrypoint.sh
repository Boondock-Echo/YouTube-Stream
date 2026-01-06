#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/youtube-stream/webapp}"
STREAM_USER="${STREAM_USER:-streamer}"
STREAM_GROUP="${STREAM_GROUP:-$STREAM_USER}"
OBS_HOME="${OBS_HOME:-/var/lib/${STREAM_USER}}"
APP_URL="${APP_URL:-http://localhost:3000}"
STREAM_URL="${STREAM_URL:-rtmp://a.rtmp.youtube.com/live2}"
VIDEO_BASE_WIDTH="${VIDEO_BASE_WIDTH:-1024}"
VIDEO_BASE_HEIGHT="${VIDEO_BASE_HEIGHT:-576}"
ENABLE_BROWSER_SOURCE_HW_ACCEL="${ENABLE_BROWSER_SOURCE_HW_ACCEL:-0}"
LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
DISPLAY="${DISPLAY:-:99}"

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Error: ${name} is required." >&2
    exit 1
  fi
}

require_var "YOUTUBE_STREAM_KEY"

ensure_permissions() {
  mkdir -p "$APP_DIR" "$OBS_HOME" "$OBS_HOME/.config" "$OBS_HOME/.cache"
  chown -R "$STREAM_USER:$STREAM_GROUP" "$APP_DIR" "$OBS_HOME"
}

run_as_streamer() {
  su -p -s /bin/bash "$STREAM_USER" -c "$*"
}

configure_obs() {
  local hw_flag="--disable-browser-hw-accel"
  if [[ "$ENABLE_BROWSER_SOURCE_HW_ACCEL" == "1" ]]; then
    hw_flag="--enable-browser-hw-accel"
  fi

  APP_DIR="$APP_DIR" \
  APP_URL="$APP_URL" \
  STREAM_USER="$STREAM_USER" \
  STREAM_GROUP="$STREAM_GROUP" \
  OBS_HOME="$OBS_HOME" \
  STREAM_URL="$STREAM_URL" \
  VIDEO_BASE_WIDTH="$VIDEO_BASE_WIDTH" \
  VIDEO_BASE_HEIGHT="$VIDEO_BASE_HEIGHT" \
  ENABLE_BROWSER_SOURCE_HW_ACCEL="$ENABLE_BROWSER_SOURCE_HW_ACCEL" \
  LIBGL_ALWAYS_SOFTWARE="$LIBGL_ALWAYS_SOFTWARE" \
  YOUTUBE_STREAM_KEY="$YOUTUBE_STREAM_KEY" \
    bash /workspace/YouTube-Stream/scripts/configure_obs.sh "$hw_flag"
}

start_react() {
  run_as_streamer "cd \"$APP_DIR\" && npm install && npm run build && HOST=0.0.0.0 PORT=3000 npx --yes serve -s build -l tcp://0.0.0.0:3000" &
  REACT_PID=$!
  echo "React server started (pid=${REACT_PID})."
}

start_obs() {
  local xvfb_opts="-screen 0 ${VIDEO_BASE_WIDTH}x${VIDEO_BASE_HEIGHT}x24 -ac +extension GLX +render -noreset"
  run_as_streamer "HOME=\"$OBS_HOME\" XDG_CONFIG_HOME=\"$OBS_HOME/.config\" XDG_CACHE_HOME=\"$OBS_HOME/.cache\" DISPLAY=\"$DISPLAY\" CEF_DISABLE_SANDBOX=1 LIBGL_ALWAYS_SOFTWARE=\"$LIBGL_ALWAYS_SOFTWARE\" xvfb-run -a -s \"$xvfb_opts\" obs --collection YouTubeHeadless --profile YouTubeHeadless --scene WebScene --startstreaming" &
  OBS_PID=$!
  echo "OBS started (pid=${OBS_PID})."
}

shutdown() {
  echo "Shutting down..."
  if [[ -n "${OBS_PID:-}" ]]; then
    kill "$OBS_PID" 2>/dev/null || true
  fi
  if [[ -n "${REACT_PID:-}" ]]; then
    kill "$REACT_PID" 2>/dev/null || true
  fi
  wait
}

ensure_permissions
configure_obs
start_react
start_obs

trap shutdown TERM INT

wait -n "$REACT_PID" "$OBS_PID"
EXIT_CODE=$?
shutdown
exit "$EXIT_CODE"
