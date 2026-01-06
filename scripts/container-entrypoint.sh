#!/usr/bin/env bash
set -euo pipefail

STREAM_USER="${STREAM_USER:-streamer}"
OBS_HOME="${OBS_HOME:-/var/lib/${STREAM_USER}}"
APP_DIR="${APP_DIR:-/opt/youtube-stream/webapp}"
APP_URL="${APP_URL:-http://localhost:3000}"
YOUTUBE_STREAM_KEY="${YOUTUBE_STREAM_KEY:-REPLACE_ME}"
VIDEO_BASE_WIDTH="${VIDEO_BASE_WIDTH:-1024}"
VIDEO_BASE_HEIGHT="${VIDEO_BASE_HEIGHT:-576}"
ENABLE_BROWSER_SOURCE_HW_ACCEL="${ENABLE_BROWSER_SOURCE_HW_ACCEL:-0}"
LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
DISPLAY="${DISPLAY:-:99}"
CEF_DISABLE_SANDBOX="${CEF_DISABLE_SANDBOX:-1}"

WEB_PID=""
OBS_PID=""

run_as_streamer() {
  su -s /bin/bash -c "$1" "${STREAM_USER}"
}

start_web() {
  local cmd
  if [[ -d "${APP_DIR}/build" ]]; then
    cmd="cd ${APP_DIR} && exec serve -s build -l tcp://0.0.0.0:3000"
  else
    cmd="cd ${APP_DIR} && HOST=0.0.0.0 PORT=3000 BROWSER=none exec npm start"
  fi
  HOME="${OBS_HOME}" run_as_streamer "${cmd}" &
  WEB_PID=$!
  echo "Started web app (PID ${WEB_PID})"
}

start_obs() {
  local xvfb_opts="-screen 0 ${VIDEO_BASE_WIDTH}x${VIDEO_BASE_HEIGHT}x24 -ac +extension GLX +render -noreset"
  local cmd="cd ${OBS_HOME} && DISPLAY=${DISPLAY} LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE} CEF_DISABLE_SANDBOX=${CEF_DISABLE_SANDBOX} \
XDG_CONFIG_HOME=${OBS_HOME}/.config XDG_CACHE_HOME=${OBS_HOME}/.cache \
APP_URL=${APP_URL} YOUTUBE_STREAM_KEY=${YOUTUBE_STREAM_KEY} ENABLE_BROWSER_SOURCE_HW_ACCEL=${ENABLE_BROWSER_SOURCE_HW_ACCEL} \
exec xvfb-run -a -s \"${xvfb_opts}\" obs --collection YouTubeHeadless --profile YouTubeHeadless --scene WebScene --startstreaming"
  HOME="${OBS_HOME}" run_as_streamer "${cmd}" &
  OBS_PID=$!
  echo "Started OBS (PID ${OBS_PID})"
}

shutdown() {
  echo "Shutting down..."
  if [[ -n "${OBS_PID}" ]]; then
    kill -TERM "${OBS_PID}" 2>/dev/null || true
  fi
  if [[ -n "${WEB_PID}" ]]; then
    kill -TERM "${WEB_PID}" 2>/dev/null || true
  fi
}

trap shutdown SIGINT SIGTERM

start_web
start_obs

wait -n "${WEB_PID}" "${OBS_PID}"
status=$?

shutdown
wait || true

exit "${status}"
