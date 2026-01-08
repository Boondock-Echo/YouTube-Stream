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

export DISPLAY

log() { echo "[$(date -Is)] $*"; }

# -----------------------------
# 1) Virtual monitor (Xvfb)
# -----------------------------
log "Starting Xvfb on DISPLAY=${DISPLAY} (${WIDTH}x${HEIGHT})..."
Xvfb "$DISPLAY" -screen 0 "${WIDTH}x${HEIGHT}x24" -nolisten tcp -ac &
XVFB_PID=$!

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
pulseaudio --daemonize=yes --log-level=warning --exit-idle-time=-1

log "Creating virtual sink 'virtSink'..."
# Sink where Chromium will play audio
pactl load-module module-null-sink sink_name=virtSink sink_properties=device.description=virtSink >/dev/null
pactl set-default-sink virtSink

# Capture source = sink monitor
AUDIO_SOURCE="virtSink.monitor"

# -----------------------------
# 3) Chromium kiosk
# -----------------------------
log "Launching Chromium kiosk to ${WEB_URL} ..."
# Notes:
# - --autoplay-policy helps with pages that autoplay audio/video
# - background throttling flags improve kiosk smoothness
# - --disable-dev-shm-usage is a fallback; shm_size is also set in compose
chromium-browser \
  --no-sandbox \
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
  "$WEB_URL" &
CHROME_PID=$!

# Give Chromium a moment to paint and start audio playback
sleep 2

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
