#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
SUPERVISOR_CONF="${SCRIPT_ROOT}/config/supervisord.conf"

APP_DIR="${APP_DIR:-/opt/youtube-stream/webapp}"
STREAM_USER="${STREAM_USER:-streamer}"
STREAM_GROUP="${STREAM_GROUP:-$STREAM_USER}"
OBS_HOME="${OBS_HOME:-/var/lib/${STREAM_USER}}"
APP_URL="${APP_URL:-http://127.0.0.1:3000}"
STREAM_URL="${STREAM_URL:-rtmp://a.rtmp.youtube.com/live2}"
VIDEO_BASE_WIDTH="${VIDEO_BASE_WIDTH:-1024}"
VIDEO_BASE_HEIGHT="${VIDEO_BASE_HEIGHT:-576}"
ENABLE_BROWSER_SOURCE_HW_ACCEL="${ENABLE_BROWSER_SOURCE_HW_ACCEL:-0}"
LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
DISPLAY="${DISPLAY:-:99}"
CEF_DISABLE_SANDBOX="${CEF_DISABLE_SANDBOX:-1}"

export APP_DIR STREAM_USER STREAM_GROUP OBS_HOME APP_URL STREAM_URL VIDEO_BASE_WIDTH VIDEO_BASE_HEIGHT
export ENABLE_BROWSER_SOURCE_HW_ACCEL LIBGL_ALWAYS_SOFTWARE DISPLAY CEF_DISABLE_SANDBOX YOUTUBE_STREAM_KEY

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

prepare_supervisor() {
  mkdir -p /var/log/supervisor /var/run
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
    bash "${SCRIPT_ROOT}/config/configure_obs.sh" "$hw_flag"
}

ensure_permissions
prepare_supervisor
configure_obs

echo "Starting supervisord with ${SUPERVISOR_CONF}"
exec /usr/bin/supervisord -c "$SUPERVISOR_CONF"
