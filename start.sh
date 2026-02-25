#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Config (from env)
# -----------------------------
: "${DISPLAY:=:99}"
: "${WIDTH:=1920}"
: "${HEIGHT:=1080}"
: "${FPS:=30}"

: "${WEB_URL:?Set WEB_URL}"
: "${YT_RTMPS_URL:=rtmps://a.rtmps.youtube.com/live2}"
: "${YT_STREAM_KEY:?Set YT_STREAM_KEY}"

: "${VIDEO_BITRATE:=6500k}"
: "${VIDEO_MAXRATE:=7500k}"
: "${VIDEO_BUFSIZE:=13000k}"
: "${AUDIO_BITRATE:=160k}"

: "${CHROME_DEBUG_PORT:=9222}"
: "${LOGIN_TIMEOUT_MS:=30000}"

export DISPLAY

log() { echo "[$(date -Is)] $*" >&2; }

find_chromium_bin() {
  local candidate
  for candidate in "${CHROME_BIN:-}" chromium chromium-browser google-chrome; do
    [ -n "$candidate" ] || continue
    if command -v "$candidate" >/dev/null 2>&1; then
      if "$candidate" --version >/tmp/chrome-version.txt 2>&1; then
        printf '%s' "$candidate"
        return 0
      fi

      if grep -q "requires the chromium snap to be installed" /tmp/chrome-version.txt 2>/dev/null; then
        log "Skipping '${candidate}' because it is the Ubuntu snap wrapper, not a real Chromium binary."
      fi
    fi
  done
  return 1
}

url_host() {
  local url="$1"
  local rest host
  rest="${url#*://}"
  host="${rest%%/*}"
  host="${host%%:*}"
  printf '%s' "$host"
}


start_system_dbus() {
  # Chromium can spam DBus connection errors if no system bus exists in the container.
  if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && [[ ! "${DBUS_SESSION_BUS_ADDRESS}" =~ ^(unix|tcp): ]]; then
    log "Ignoring invalid DBUS_SESSION_BUS_ADDRESS='${DBUS_SESSION_BUS_ADDRESS}'"
    unset DBUS_SESSION_BUS_ADDRESS
  fi

  if [[ -S /run/dbus/system_bus_socket ]]; then
    return 0
  fi

  if command -v dbus-daemon >/dev/null 2>&1; then
    install -d /run/dbus
    dbus-daemon --system --fork >/dev/null 2>&1 || true
  fi
}

wait_for_chrome_debugger() {
  local debugger_url="http://127.0.0.1:${CHROME_DEBUG_PORT}/json/version"
  local attempts i

  attempts=$((LOGIN_TIMEOUT_MS / 500))
  if (( attempts < 20 )); then
    attempts=20
  fi

  for ((i=1; i<=attempts; i+=1)); do
    if curl -fsS --max-time 2 "$debugger_url" >/dev/null 2>&1; then
      log "Chromium DevTools endpoint is ready on port ${CHROME_DEBUG_PORT}."
      return 0
    fi

    if ! kill -0 "$CHROME_PID" >/dev/null 2>&1; then
      log "WARNING: Chromium exited before DevTools endpoint was reachable."
      return 1
    fi

    sleep 0.5
  done

  log "WARNING: Chromium DevTools endpoint did not become ready at ${debugger_url}."
  return 1
}

run_automated_login() {
  if [[ -z "${LOGIN_USER:-}" || -z "${LOGIN_PASS:-}" ]]; then
    log "LOGIN_USER/LOGIN_PASS not set; skipping automated login."
    return 0
  fi

  if ! command -v node >/dev/null 2>&1; then
    log "WARNING: Node.js is not available; skipping automated login."
    return 0
  fi

  log "Running Puppeteer automated login..."
  if ! node /app/login.mjs; then
    log "WARNING: Automated login failed; continuing with currently visible page."
  fi
}

check_web_url() {
  local host
  host="$(url_host "$WEB_URL")"

  log "Preflight check for WEB_URL=${WEB_URL}"
  if command -v getent >/dev/null 2>&1; then
    if getent hosts "$host" >/dev/null 2>&1; then
      log "DNS resolution OK for host '${host}'."
    else
      log "WARNING: DNS resolution failed for host '${host}'."
      log "If this is a host-local service, try host.docker.internal or add an extra_hosts entry in docker-compose.yml."
    fi
  fi

  if command -v curl >/dev/null 2>&1; then
    if curl -fsSIL --max-time 10 "$WEB_URL" >/dev/null 2>&1; then
      log "HTTP reachability check OK for ${WEB_URL}."
    else
      log "WARNING: Could not reach ${WEB_URL} with curl from inside the container."
      log "Chromium may show a blank/error page if the URL is not reachable from container networking."
    fi
  fi
}

# -----------------------------
# 1) Virtual monitor (Xvfb)
# -----------------------------
log "Starting Xvfb on DISPLAY=${DISPLAY} (${WIDTH}x${HEIGHT})..."
if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
  log "X display ${DISPLAY} is already active; reusing existing X server."
else
  Xvfb "$DISPLAY" -screen 0 "${WIDTH}x${HEIGHT}x24" -nolisten tcp -ac &
  XVFB_PID=$!
fi

for i in {1..100}; do
  if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    log "Xvfb is ready."
    break
  fi
  sleep 0.1
done

# -----------------------------
# 2) Virtual audio (PulseAudio)
# -----------------------------
log "Starting PulseAudio..."
if pulseaudio --check >/dev/null 2>&1; then
  log "PulseAudio daemon already running; reusing existing server."
else
  pulseaudio --daemonize=yes --log-level=warning --exit-idle-time=-1
fi

log "Creating virtual sink 'virtSink'..."
# Sink where Chromium will play audio
if ! pactl list short sinks 2>/dev/null | awk '{print $2}' | grep -Fxq "virtSink"; then
  pactl load-module module-null-sink sink_name=virtSink sink_properties=device.description=virtSink >/dev/null
else
  log "PulseAudio sink 'virtSink' already exists; reusing."
fi
pactl set-default-sink virtSink

# Capture source = sink monitor
AUDIO_SOURCE="virtSink.monitor"

# -----------------------------
# 3) Chromium kiosk
# -----------------------------
check_web_url
start_system_dbus

CHROMIUM_BIN="$(find_chromium_bin || true)"
if [[ -z "${CHROMIUM_BIN}" ]]; then
  log "ERROR: Could not find a Chromium binary. Set CHROME_BIN or install chromium."
  exit 1
fi

log "Launching Chromium kiosk with ${CHROMIUM_BIN} to ${WEB_URL} ..."
# Notes:
# - --autoplay-policy helps with pages that autoplay audio/video
# - background throttling flags improve kiosk smoothness
# - --disable-dev-shm-usage is a fallback; shm_size is also set in compose
"${CHROMIUM_BIN}" \
  --no-sandbox \
  --no-first-run \
  --no-default-browser-check \
  --disable-gpu \
  --disable-dev-shm-usage \
  --autoplay-policy=no-user-gesture-required \
  --disable-features=TranslateUI,MediaEngagementBypassAutoplayPolicies \
  --disable-background-timer-throttling \
  --disable-backgrounding-occluded-windows \
  --disable-renderer-backgrounding \
  --window-size="${WIDTH},${HEIGHT}" \
  --start-fullscreen \
  --kiosk \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port="${CHROME_DEBUG_PORT}" \
  "$WEB_URL" &
CHROME_PID=$!

# Give Chromium a moment to paint and start audio playback
sleep 2
if ! kill -0 "$CHROME_PID" >/dev/null 2>&1; then
  log "ERROR: Chromium exited before capture started."
  log "If you see a message about snap, install/use the apt chromium package and set CHROME_BIN=chromium."
  exit 1
fi

wait_for_chrome_debugger || true

run_automated_login

# -----------------------------
# 4) FFmpeg: capture X11 + PulseAudio -> YouTube RTMPS
# -----------------------------
log "Starting FFmpeg capture -> YouTube RTMPS..."
log "Video: ${WIDTH}x${HEIGHT}@${FPS} bitrate=${VIDEO_BITRATE} maxrate=${VIDEO_MAXRATE} buf=${VIDEO_BUFSIZE}"
log "Audio: source=${AUDIO_SOURCE} bitrate=${AUDIO_BITRATE}"

# Keyframe interval set to 2 seconds (common RTMP practice)
GOP=$((FPS*2))

exec ffmpeg \
  -hide_banner -loglevel info \
  -thread_queue_size 2048 \
  -f x11grab -framerate "$FPS" -video_size "${WIDTH}x${HEIGHT}" -i "${DISPLAY}.0" \
  -thread_queue_size 2048 \
  -f pulse -i "$AUDIO_SOURCE" \
  -c:v libx264 -preset veryfast -tune zerolatency \
  -b:v "$VIDEO_BITRATE" -maxrate "$VIDEO_MAXRATE" -bufsize "$VIDEO_BUFSIZE" \
  -pix_fmt yuv420p \
  -g "$GOP" -keyint_min "$GOP" \
  -c:a aac -b:a "$AUDIO_BITRATE" -ar 48000 \
  -f flv "${YT_RTMPS_URL}/${YT_STREAM_KEY}"
