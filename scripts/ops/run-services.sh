#!/usr/bin/env bash
set -euo pipefail

# Simple supervisor that starts the React frontend and headless OBS under the
# streamer account, relays logs to the container output, and terminates if
# either process exits unexpectedly.

STREAM_USER="${STREAM_USER:-streamer}"
OBS_HOME="${OBS_HOME:-/var/lib/${STREAM_USER}}"
APP_DIR="${APP_DIR:-/opt/youtube-stream/webapp}"
APP_URL="${APP_URL:-http://127.0.0.1:3000}"
YOUTUBE_STREAM_KEY="${YOUTUBE_STREAM_KEY:-REPLACE_ME}"
VIDEO_BASE_WIDTH="${VIDEO_BASE_WIDTH:-1024}"
VIDEO_BASE_HEIGHT="${VIDEO_BASE_HEIGHT:-576}"
ENABLE_BROWSER_SOURCE_HW_ACCEL="${ENABLE_BROWSER_SOURCE_HW_ACCEL:-0}"
LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
DISPLAY="${DISPLAY:-:99}"
CEF_DISABLE_SANDBOX="${CEF_DISABLE_SANDBOX:-1}"

WEB_PID=""
OBS_PID=""
SHUTTING_DOWN=false

run_as_streamer() {
  su -s /bin/bash -c "$1" "${STREAM_USER}"
}

start_web() {
  local cmd

  if [[ -d "${APP_DIR}/build" ]]; then
    cmd="cd ${APP_DIR} && exec serve -s build -l tcp://127.0.0.1:3000"
    echo "Starting React production build from ${APP_DIR}/build"
  else
    cmd="cd ${APP_DIR} && HOST=127.0.0.1 PORT=3000 BROWSER=none exec npm start"
    echo "Starting React dev server from ${APP_DIR}"
  fi

  HOME="${OBS_HOME}" run_as_streamer "${cmd}" &
  WEB_PID=$!
  echo "Started web app (PID ${WEB_PID})"
}

start_obs() {
  local xvfb_opts="-screen 0 ${VIDEO_BASE_WIDTH}x${VIDEO_BASE_HEIGHT}x24 -ac +extension GLX +render -noreset"
  local cmd

  cmd="cd ${OBS_HOME} && DISPLAY=${DISPLAY} LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE} CEF_DISABLE_SANDBOX=${CEF_DISABLE_SANDBOX} "
  cmd+="XDG_CONFIG_HOME=${OBS_HOME}/.config XDG_CACHE_HOME=${OBS_HOME}/.cache "
  cmd+="APP_URL=${APP_URL} YOUTUBE_STREAM_KEY=${YOUTUBE_STREAM_KEY} ENABLE_BROWSER_SOURCE_HW_ACCEL=${ENABLE_BROWSER_SOURCE_HW_ACCEL} "
  cmd+="exec xvfb-run -a -s \"${xvfb_opts}\" obs --collection YouTubeHeadless --profile YouTubeHeadless --scene WebScene "
  cmd+="--startstreaming --disable-updater --disable-shutdown-check --minimize-to-tray"

  HOME="${OBS_HOME}" run_as_streamer "${cmd}" &
  OBS_PID=$!
  echo "Started OBS (PID ${OBS_PID})"
}

shutdown_services() {
  if ${SHUTTING_DOWN}; then
    return
  fi

  SHUTTING_DOWN=true
  echo "Shutting down services..."

  if [[ -n "${OBS_PID}" ]]; then
    kill -TERM "${OBS_PID}" 2>/dev/null || true
  fi

  if [[ -n "${WEB_PID}" ]]; then
    kill -TERM "${WEB_PID}" 2>/dev/null || true
  fi
}

trap shutdown_services SIGINT SIGTERM

start_web
start_obs

set +e
wait -n "${WEB_PID}" "${OBS_PID}"
wait_status=$?
set -e

if ${SHUTTING_DOWN}; then
  wait || true
  exit 0
fi

echo "A managed service exited unexpectedly (status ${wait_status})."
shutdown_services
wait || true

if [[ ${wait_status} -eq 0 ]]; then
  wait_status=1
fi

exit "${wait_status}"
