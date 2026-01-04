#!/bin/bash

# Configure OBS for Headless YouTube Streaming
# Run as root. Generates scenes, profiles, services with fixes.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_JSON="${SCRIPT_DIR}/config.json"
COLLECTION_NAME="YouTubeHeadless"
CONFIG_ROOT="/var/lib/streamer/.config/obs-studio"
GLOBAL_INI="${CONFIG_ROOT}/global.ini"
APP_DIR="${APP_DIR:-/opt/youtube-stream/webapp}"
ENV_FILE="/etc/youtube-stream/env"
ENV_DIR="$(dirname "${ENV_FILE}")"
# Keep base/output aligned to avoid extra OBS rescaling.
VIDEO_BASE_WIDTH="${VIDEO_BASE_WIDTH:-1024}"
VIDEO_BASE_HEIGHT="${VIDEO_BASE_HEIGHT:-576}"
ENABLE_BROWSER_SOURCE_HW_ACCEL="${ENABLE_BROWSER_SOURCE_HW_ACCEL:-0}"
LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"

# Helper: Run as streamer user
run_as_streamer() {
    sudo -u streamer HOME=/var/lib/streamer bash -c "$1"
}

# Helper: Choose the best available hardware encoder (fallback to x264)
select_encoder() {
    local encoder="x264"

    if command -v ffmpeg >/dev/null 2>&1; then
        local ff_encoders
        ff_encoders="$(ffmpeg -hide_banner -encoders 2>/dev/null || true)"

        if grep -qE '(^|\s)h264_nvenc(\s|$)' <<<"$ff_encoders"; then
            encoder="h264_nvenc"
        elif grep -qE '(^|\s)h264_amf(\s|$)' <<<"$ff_encoders"; then
            encoder="h264_amf"
        elif grep -qE '(^|\s)h264_qsv(\s|$)' <<<"$ff_encoders"; then
            encoder="obs_qsv11"
        fi
    fi

    echo "$encoder"
}

encoder_available() {
    local encoder="$1" pattern=""
    case "$encoder" in
        h264_nvenc) pattern="nvenc" ;;
        h264_amf) pattern="amf" ;;
        obs_qsv11|h264_qsv) pattern="qsv" ;;
        *) return 0 ;;
    esac

    if find /usr/lib* -maxdepth 3 -type f -iname "*${pattern}*.so" 2>/dev/null | grep -q .; then
        return 0
    fi

    return 1
}

# Flags
for arg in "$@"; do
    case "$arg" in
        --enable-browser-hw-accel)
            ENABLE_BROWSER_SOURCE_HW_ACCEL=1
            ;;
        --disable-browser-hw-accel)
            ENABLE_BROWSER_SOURCE_HW_ACCEL=0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

if [[ "${ENABLE_BROWSER_SOURCE_HW_ACCEL}" != "0" && "${ENABLE_BROWSER_SOURCE_HW_ACCEL}" != "1" ]]; then
    echo "Error: ENABLE_BROWSER_SOURCE_HW_ACCEL must be 0 (default) or 1." >&2
    exit 1
fi

# Prompt or load config
if [[ -f "${CONFIG_JSON}" ]]; then
    source <(jq -r 'to_entries|map("\(.key)=\(.value)")|join("\n")' "${CONFIG_JSON}")
else
    echo "=== Configuration Prompts ==="
    read -p "Scene name [WebScene]: " SCENE_NAME
    SCENE_NAME=${SCENE_NAME:-WebScene}
    read -p "Source name [BrowserSource]: " SOURCE_NAME
    SOURCE_NAME=${SOURCE_NAME:-BrowserSource}
    read -p "App URL [http://localhost:3000]: " APP_URL
    APP_URL=${APP_URL:-http://localhost:3000}
    read -p "YouTube Stream Key: " YOUTUBE_STREAM_KEY

    # Save config
    jq -n \
        --arg scene "$SCENE_NAME" \
        --arg source "$SOURCE_NAME" \
        --arg url "$APP_URL" \
        --arg key "$YOUTUBE_STREAM_KEY" \
        '{scene: $scene, source: $source, url: $url, key: $key}' \
        > "${CONFIG_JSON}"
fi

# Validate inputs
if [[ -z "$YOUTUBE_STREAM_KEY" ]]; then
    echo "Error: Stream key required." >&2
    exit 1
fi
if ! [[ "$VIDEO_BASE_WIDTH" =~ ^[0-9]+$ && "$VIDEO_BASE_HEIGHT" =~ ^[0-9]+$ ]]; then
    echo "Error: VIDEO_BASE_WIDTH/VIDEO_BASE_HEIGHT must be integers." >&2
    exit 1
fi
if [[ ! -f "${APP_DIR}/package.json" ]]; then
    echo "Error: React app not found at ${APP_DIR}. Run scripts/bootstrap_react_app.sh first (or set APP_DIR)." >&2
    exit 1
fi

echo "Using: Scene=${SCENE_NAME}, Source=${SOURCE_NAME}, URL=${APP_URL}, Key=${YOUTUBE_STREAM_KEY:0:10}..."
if [[ "${ENABLE_BROWSER_SOURCE_HW_ACCEL}" == "1" ]]; then
    echo "Browser source hardware acceleration: ENABLED (requires GPU/driver support; may be less stable in headless/virtual environments)."
else
    echo "Browser source hardware acceleration: DISABLED (default for stability; higher CPU usage possible)."
fi

# Create dirs/ownership
mkdir -p "${ENV_DIR}"
chmod 750 "${ENV_DIR}"
chown root:root "${ENV_DIR}"
mkdir -p "${CONFIG_ROOT}/basic/scenes" "${CONFIG_ROOT}/basic/profiles/${COLLECTION_NAME}"
chown -R streamer:streamer /var/lib/streamer/.config
chmod 755 /var/lib/streamer
# Env file
echo "YOUTUBE_STREAM_KEY=${YOUTUBE_STREAM_KEY}" > "${ENV_FILE}"
chmod 640 "${ENV_FILE}"
chown root:root "${ENV_FILE}"

# Global.ini (browser source hardware acceleration configurable; defaults off)
cat > "${GLOBAL_INI}" << GLOBAL
[General]
EnableBrowserSourceHardwareAcceleration=${ENABLE_BROWSER_SOURCE_HW_ACCEL}

[BrowserSource]
CEFLogging=1
GLOBAL
run_as_streamer "touch '${GLOBAL_INI}'"  # Ensures ownership
chown streamer:streamer "${GLOBAL_INI}"

# Fixed scene JSON (hierarchical, with silent audio)
cat << SCENE | run_as_streamer tee "${CONFIG_ROOT}/basic/scenes/${COLLECTION_NAME}.json" >/dev/null
{
  "current_program": "${SCENE_NAME}",
  "current_preview": "${SCENE_NAME}",
  "current_transition": "Default",
  "groups": {},
  "modules": {},
  "preview_locked": false,
  "quick_transitions": [],
  "scene_order": ["${SCENE_NAME}"],
  "sources": {
    "${SOURCE_NAME}": {
      "balance": 0,
      "deinterlace_field_order": 0,
      "deinterlace_mode": 0,
      "enabled": true,
      "flags": 0,
      "hotkeys": {},
      "id": "browser_source",
      "mixers": 0,
      "muted": false,
      "name": "${SOURCE_NAME}",
      "settings": {
        "color": 1,
        "custom_css": "",
        "fps": 30,
        "height": ${VIDEO_BASE_HEIGHT},
        "is_local_file": false,
        "local_file": "",
        "reroute_audio": false,
        "refresh": true,
        "shutdown_source": true,
        "url": "${APP_URL}",
        "width": ${VIDEO_BASE_WIDTH}
      },
      "sync": 0,
      "type": "browser_source",
      "versioned_id": "browser_source_v2",
      "volume": 1
    },
    "${SCENE_NAME}": {
      "balance": 0,
      "deinterlace_field_order": 0,
      "deinterlace_mode": 0,
      "enabled": true,
      "flags": 2,
      "hotkeys": {},
      "id": "scene",
      "mixers": 0,
      "muted": false,
      "name": "${SCENE_NAME}",
      "settings": {},
      "sources": [
        {
          "balance": 0,
          "deinterlace_field_order": 0,
          "deinterlace_mode": 0,
          "enabled": true,
          "flags": 0,
          "hotkeys": {},
          "id": "${SOURCE_NAME}",
          "mixers": 0,
          "muted": false,
          "name": "${SOURCE_NAME}",
          "settings": {},
          "sync": 0,
          "type": "browser_source",
          "volume": 1
        },
        {
          "balance": 0,
          "deinterlace_field_order": 0,
          "deinterlace_mode": 0,
          "enabled": true,
          "flags": 264,
          "hotkeys": {},
          "id": "SilenceAudio",
          "mixers": 0,
          "muted": false,
          "name": "Silence",
          "settings": {
            "is_looping": true,
            "path": "",
            "restart_on_activate": false,
            "sync": 0,
            "sync_offset": 0
          },
          "sync": 0,
          "type": "vlc_source",
          "volume": 0
        }
      ],
      "sync": 0,
      "type": "scene",
      "versioned_id": "scene",
      "volume": 1
    }
  },
  "sources_version": 2,
  "transition_duration": 300,
  "transitions": {
    "Default": {
      "duration": 300,
      "id": "fade_transition"
    }
  },
  "uids": ["${SCENE_NAME}", "${SOURCE_NAME}", "SilenceAudio"],
  "version": 1
}
SCENE

# Validate JSON
if ! jq . "${CONFIG_ROOT}/basic/scenes/${COLLECTION_NAME}.json" >/dev/null; then
    echo "Error: Invalid JSON generated." >&2
    exit 1
fi

# Select encoder and bitrate defaults (lighter baseline; override with VIDEO_BITRATE/AUDIO_BITRATE)
ENCODER="$(select_encoder)"
AUDIO_BITRATE="${AUDIO_BITRATE:-128}"
VIDEO_BITRATE="${VIDEO_BITRATE:-2500}"
YOUTUBE_AUDIO_MIN=128

# Validate bitrate choices against YouTube's published guidance for common 30fps tiers
validate_youtube_recommendations() {
    local tier="1080p@30" min_video=4500 max_video=9000

    if (( VIDEO_BASE_HEIGHT <= 576 )); then
        tier="480p@30"
        min_video=1500
        max_video=4000
    elif (( VIDEO_BASE_HEIGHT <= 720 )); then
        tier="720p@30"
        min_video=2500
        max_video=6000
    fi

    if (( VIDEO_BITRATE < min_video || VIDEO_BITRATE > max_video )); then
        echo "Warning: VIDEO_BITRATE=${VIDEO_BITRATE}kbps falls outside YouTube's ${tier} guidance (${min_video}-${max_video}kbps)." >&2
    else
        echo "Video bitrate aligns with YouTube's ${tier} guidance (${min_video}-${max_video}kbps)."
    fi

    if (( AUDIO_BITRATE < YOUTUBE_AUDIO_MIN )); then
        echo "Warning: AUDIO_BITRATE=${AUDIO_BITRATE}kbps is below YouTube's recommended minimum (${YOUTUBE_AUDIO_MIN}kbps AAC-LC)." >&2
    else
        echo "Audio bitrate meets YouTube's recommended minimum (${YOUTUBE_AUDIO_MIN}kbps AAC-LC)."
    fi
}

validate_youtube_recommendations
if [[ "$ENCODER" == "x264" ]]; then
    ADV_PRESET="${ADV_PRESET:-superfast}"
else
    # Hardware encoders generally use vendor presets; keep to OBS default for compatibility.
    ADV_PRESET="${ADV_PRESET:-default}"
    if ! encoder_available "${ENCODER}"; then
        echo "OBS encoder ${ENCODER} not detected in available plugins; falling back to x264." >&2
        ENCODER="x264"
        ADV_PRESET="${ADV_PRESET:-superfast}"
    fi
fi

echo "OBS encoder selected: ${ENCODER} (video=${VIDEO_BITRATE}kbps, audio=${AUDIO_BITRATE}kbps, preset=${ADV_PRESET})"
echo "Video base/output resolution locked to ${VIDEO_BASE_WIDTH}x${VIDEO_BASE_HEIGHT} (RescaleOutput=0) to avoid extra scaling."

OUTPUT_ENCODER="${ENCODER}"
if [[ "$ENCODER" == "x264" ]]; then
    OUTPUT_ENCODER="obs_x264"
fi

# Profile basic.ini with YouTube opts
cat > "${CONFIG_ROOT}/basic/profiles/${COLLECTION_NAME}/basic.ini" << PROFILE
[General]
Name=${COLLECTION_NAME}

[Audio]
SampleRate=48000
Channels=2

[Video]
BaseCX=${VIDEO_BASE_WIDTH}
BaseCY=${VIDEO_BASE_HEIGHT}
OutputCX=${VIDEO_BASE_WIDTH}
OutputCY=${VIDEO_BASE_HEIGHT}

[Output]
Mode=Advanced
Encoder=${OUTPUT_ENCODER}
RescaleOutput=0
ColorFormat=NV12
ColorSpace=709
ColorRange=Partial
ApplyBitrate=1

[SimpleOutput]
VBitrate=${VIDEO_BITRATE}
ABitrate=${AUDIO_BITRATE}

[AdvOut]
Encoder=${OUTPUT_ENCODER}
Bitrate=${VIDEO_BITRATE}
KeyframeIntervalSeconds=2
Preset=${ADV_PRESET}
Profile=high
Tune=zerolatency
PsychoVisualTuning=0
Lookahead=0
Bframes=0
Track1Bitrate=${AUDIO_BITRATE}

[Service]
Projector=rtmp://a.rtmp.youtube.com/live2
Key=${YOUTUBE_STREAM_KEY}
PROFILE
chown -R streamer:streamer "${CONFIG_ROOT}/basic/profiles/${COLLECTION_NAME}"

# Registries
cat << REGISTRY | run_as_streamer tee "${CONFIG_ROOT}/basic/scene_collections.json" >/dev/null
{
  "current_scene_collection": "${COLLECTION_NAME}",
  "scene_collections": [
    {
      "name": "${COLLECTION_NAME}"
    }
  ]
}
REGISTRY

cat << REGISTRY | run_as_streamer tee "${CONFIG_ROOT}/basic/profiles.json" >/dev/null
{
  "current_profile": "${COLLECTION_NAME}",
  "profiles": [
    {
      "name": "${COLLECTION_NAME}"
    }
  ]
}
REGISTRY

# Services (with fixes)
cat > /etc/systemd/system/react-web.service << SERVICE
[Unit]
Description=React Web App
After=network.target

[Service]
Type=simple
User=streamer
WorkingDirectory=${APP_DIR}
Environment=HOST=0.0.0.0
Environment=PORT=3000
Environment=NODE_ENV=production
ExecStartPre=/bin/bash -lc 'cd ${APP_DIR} && [ -d node_modules ] || npm install'
ExecStartPre=/bin/bash -lc 'cd ${APP_DIR} && npm run build'
ExecStart=/usr/bin/npx --yes serve -s build -l tcp://0.0.0.0:3000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

cat > /etc/systemd/system/obs-headless.service << SERVICE
[Unit]
Description=OBS headless YouTube streaming
After=network.target react-web.service
Requires=react-web.service

[Service]
Type=simple
User=streamer
Group=streamer
Environment=HOME=/var/lib/streamer
Environment=DISPLAY=:99
Environment=CEF_DISABLE_SANDBOX=1
Environment=LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE}
ExecStart=/usr/bin/xvfb-run -a -s "-screen 0 ${VIDEO_BASE_WIDTH}x${VIDEO_BASE_HEIGHT}x24 -ac +extension GLX +render -noreset" obs --collection ${COLLECTION_NAME} --profile ${COLLECTION_NAME} --scene ${SCENE_NAME} --startstreaming
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable react-web.service obs-headless.service

echo "Configuration complete! Run 'systemctl start react-web obs-headless' to stream."
echo "Verify: ./diagnostics.sh"
