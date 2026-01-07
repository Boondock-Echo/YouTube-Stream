#!/usr/bin/env bash
set -euo pipefail

STREAM_USER="${STREAM_USER:-streamer}"
OBS_HOME="${OBS_HOME:-/var/lib/${STREAM_USER}}"
APP_URL="${APP_URL:-http://127.0.0.1:3000}"
STREAM_URL="${STREAM_URL:-rtmp://a.rtmp.youtube.com/live2}"
VIDEO_BASE_WIDTH="${VIDEO_BASE_WIDTH:-1024}"
VIDEO_BASE_HEIGHT="${VIDEO_BASE_HEIGHT:-576}"
ENABLE_BROWSER_SOURCE_HW_ACCEL="${ENABLE_BROWSER_SOURCE_HW_ACCEL:-0}"
LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
DISPLAY="${DISPLAY:-:99}"
CEF_DISABLE_SANDBOX="${CEF_DISABLE_SANDBOX:-1}"
PATH="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"

export HOME="$OBS_HOME"
export XDG_CONFIG_HOME="$OBS_HOME/.config"
export XDG_CACHE_HOME="$OBS_HOME/.cache"
export APP_URL STREAM_URL VIDEO_BASE_WIDTH VIDEO_BASE_HEIGHT ENABLE_BROWSER_SOURCE_HW_ACCEL
export LIBGL_ALWAYS_SOFTWARE DISPLAY CEF_DISABLE_SANDBOX YOUTUBE_STREAM_KEY
export PATH

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

if ! command_exists obs; then
  cat >&2 <<'EOF'
Error: OBS Studio CLI ("obs") is not available in PATH.
- If you are running locally, install dependencies via scripts/install/install_dependencies.sh.
- In containers, rebuild the image or install the obs-studio package so /usr/bin/obs is present.
EOF
  exit 127
fi

xvfb_opts="-screen 0 ${VIDEO_BASE_WIDTH}x${VIDEO_BASE_HEIGHT}x24 -ac +extension GLX +render -noreset"

APP_URL="$APP_URL" \
STREAM_URL="$STREAM_URL" \
YOUTUBE_STREAM_KEY="${YOUTUBE_STREAM_KEY:?YOUTUBE_STREAM_KEY is required}" \
ENABLE_BROWSER_SOURCE_HW_ACCEL="$ENABLE_BROWSER_SOURCE_HW_ACCEL" \
LIBGL_ALWAYS_SOFTWARE="$LIBGL_ALWAYS_SOFTWARE" \
exec xvfb-run -a -s "$xvfb_opts" obs --collection YouTubeHeadless --profile YouTubeHeadless --scene WebScene --startstreaming --disable-updater --disable-shutdown-check --minimize-to-tray
