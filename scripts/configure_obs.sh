#!/usr/bin/env bash
set -euo pipefail

# Creates an OBS Studio profile and scene collection for headless streaming of the React app.
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"

# Initialize variables so `set -u` does not fail when they are unset in the environment.
STREAM_USER=${STREAM_USER:-}
OBS_HOME=${OBS_HOME:-}
COLLECTION_NAME=${COLLECTION_NAME:-}
SCENE_NAME=${SCENE_NAME:-}
SOURCE_NAME=${SOURCE_NAME:-}
STREAM_KEY=${YOUTUBE_STREAM_KEY:-${STREAM_KEY:-}}
STREAM_URL=${STREAM_URL:-}
APP_URL=${APP_URL:-}

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN=python
else
  echo "Python is required to run this script. Please install Python 3." >&2
  exit 1
fi

prompt_for_value() {
  local variable_name=$1
  local prompt_text=$2
  local default_value=$3
  local require_nonempty=${4:-false}

  local prompt_suffix=""
  if [[ -n "$default_value" ]]; then
    prompt_suffix=" [${default_value}]"
  fi

  local input
  while true; do
    read -r -p "${prompt_text}${prompt_suffix}: " input
    if [[ -z "$input" ]]; then
      input=$default_value
    fi

    if [[ "$require_nonempty" == "true" && -z "$input" ]]; then
      echo "This value is required."
      continue
    fi
    break
  done

  printf -v "$variable_name" '%s' "$input"
}

load_config() {
  eval "$(
    "$PYTHON_BIN" - <<'PY' "$CONFIG_FILE"
import json, shlex, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
for key in ["STREAM_USER", "OBS_HOME", "COLLECTION_NAME", "SCENE_NAME", "SOURCE_NAME", "STREAM_KEY", "STREAM_URL", "APP_URL"]:
    value = data.get(key, "")
    print(f"{key}={shlex.quote(str(value))}")
PY
  )"
}

write_config() {
  "$PYTHON_BIN" - <<'PY' "$CONFIG_FILE" "$STREAM_USER" "$OBS_HOME" "$COLLECTION_NAME" "$SCENE_NAME" "$SOURCE_NAME" "$STREAM_KEY" "$STREAM_URL" "$APP_URL"
import json, sys
path = sys.argv[1]
keys = ["STREAM_USER", "OBS_HOME", "COLLECTION_NAME", "SCENE_NAME", "SOURCE_NAME", "STREAM_KEY", "STREAM_URL", "APP_URL"]
values = sys.argv[2:]
payload = dict(zip(keys, values))
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
    f.write("\n")
PY
}

if [[ -f "$CONFIG_FILE" ]]; then
  echo "Loading OBS configuration from ${CONFIG_FILE}."
  load_config
else
  default_stream_user=${STREAM_USER:-streamer}
  prompt_for_value STREAM_USER "Enter the service user for OBS" "$default_stream_user" true

  default_obs_home=${OBS_HOME:-/var/lib/${STREAM_USER}}
  prompt_for_value OBS_HOME "Enter the OBS home directory" "$default_obs_home" true

  default_collection_name=${COLLECTION_NAME:-YouTubeHeadless}
  prompt_for_value COLLECTION_NAME "Enter the OBS collection name" "$default_collection_name" true

  default_scene_name=${SCENE_NAME:-WebScene}
  prompt_for_value SCENE_NAME "Enter the scene name" "$default_scene_name" true

  default_source_name=${SOURCE_NAME:-BrowserSource}
  prompt_for_value SOURCE_NAME "Enter the browser source name" "$default_source_name" true

  default_stream_url=${STREAM_URL:-rtmp://a.rtmp.youtube.com/live2}
  prompt_for_value STREAM_URL "Enter the RTMP server URL" "$default_stream_url" true

  default_app_url=${APP_URL:-http://localhost:3000}
  prompt_for_value APP_URL "Enter the app URL for the browser source" "$default_app_url" true

  prompt_for_value STREAM_KEY "Enter the YouTube stream key" "${STREAM_KEY:-}" true

  write_config
  echo "Saved OBS configuration to ${CONFIG_FILE}."
fi

CONFIG_ROOT="$OBS_HOME/.config/obs-studio"
CACHE_ROOT="$OBS_HOME/.cache/obs-studio"

current_user=$(id -un)
current_uid=$(id -u)

if [[ -z "$STREAM_KEY" ]]; then
  echo "Stream key is missing. Update ${CONFIG_FILE} or remove it to re-enter values." >&2
  exit 1
fi

if [[ "$current_user" != "$STREAM_USER" && "$current_uid" -ne 0 ]]; then
  echo "Run this script as root or ${STREAM_USER} so it can prepare the OBS profile." >&2
  exit 1
fi

# Ensure the service user exists and has a home directory. Without this, OBS will
# segfault on startup when it cannot resolve config paths (manifesting as
# `basic_string: construction from null is not valid`).
if ! id -u "$STREAM_USER" >/dev/null 2>&1; then
  if [[ "$current_uid" -eq 0 ]]; then
    useradd --system --create-home --home-dir "$OBS_HOME" --shell /bin/bash "$STREAM_USER"
  else
    echo "Service user ${STREAM_USER} is missing. Run this script as root or run install_dependencies.sh first." >&2
    exit 1
  fi
fi

mkdir -p "$OBS_HOME"
if [[ "$current_uid" -eq 0 ]]; then
  chown -R "$STREAM_USER":"$STREAM_USER" "$OBS_HOME"
fi

mkdir -p "$CONFIG_ROOT/basic/profiles/${COLLECTION_NAME}" "$CONFIG_ROOT/basic/scenes" "$OBS_HOME/logs" "$CACHE_ROOT"

run_as_streamer() {
  if [[ "$current_user" == "$STREAM_USER" ]]; then
    "$@"
  else
    sudo -u "$STREAM_USER" "$@"
  fi
}

# Scene collection with a single browser source pointing to the React app
cat <<SCENE | run_as_streamer tee "$CONFIG_ROOT/basic/scenes/${COLLECTION_NAME}.json" >/dev/null
{
  "current_program_scene": "${SCENE_NAME}",
  "current_scene": "${SCENE_NAME}",
  "name": "${COLLECTION_NAME}",
  "scene_order": [
    {"name": "${SCENE_NAME}"}
  ],
  "sources": [
    {
      "alignment": 5,
      "cx": 1280,
      "cy": 720,
      "id": 1,
      "locked": false,
      "muted": false,
      "name": "${SOURCE_NAME}",
      "render": true,
      "source_uuid": "${SOURCE_NAME}",
      "volume": 1.0,
      "x": 0.0,
      "y": 0.0,
      "mixers": 0,
      "deinterlace_field_order": 0,
      "deinterlace_mode": 0,
      "filters": [],
      "monitoring_type": 0,
      "settings": {
        "is_local_file": false,
        "url": "${APP_URL}",
        "width": 1280,
        "height": 720,
        "fps": 30
      },
      "type": "browser_source"
    },
    {
      "alignment": 5,
      "cx": 1280,
      "cy": 720,
      "id": 2,
      "locked": false,
      "muted": false,
      "name": "${SCENE_NAME}",
      "render": true,
      "source_uuid": "${SCENE_NAME}",
      "volume": 1.0,
      "mixers": 0,
      "deinterlace_field_order": 0,
      "deinterlace_mode": 0,
      "filters": [],
      "monitoring_type": 0,
      "settings": {
        "items": [
          {
            "align": 5,
            "bounds_align": 0,
            "bounds_height": 0.0,
            "bounds_type": 0,
            "bounds_width": 0.0,
            "crop_bottom": 0,
            "crop_left": 0,
            "crop_right": 0,
            "crop_top": 0,
            "id": 1,
            "name": "${SOURCE_NAME}",
            "pos": {"x": 0.0, "y": 0.0},
            "rot": 0.0,
            "scale": {"x": 1.0, "y": 1.0},
            "visible": true
          }
        ]
      },
      "type": "scene"
    }
  ]
}
SCENE

# Streaming profile pointing at YouTube RTMP with the supplied stream key
cat <<PROFILE | run_as_streamer tee "$CONFIG_ROOT/basic/profiles/${COLLECTION_NAME}/basic.ini" >/dev/null
[General]
Name=${COLLECTION_NAME}

[Video]
BaseCX=1280
BaseCY=720
OutputCX=1280
OutputCY=720
FPSType=0
FPSCommon=30

[Output]
Mode=Advanced
RecEncoder=obs_x264
Track1Bitrate=160

[AdvOut]
Encoder=obs_x264
Bitrate=4500
KeyIntSec=2
Preset=veryfast
RateControl=CBR
PROFILE

cat <<SERVICE | run_as_streamer tee "$CONFIG_ROOT/basic/profiles/${COLLECTION_NAME}/service.json" >/dev/null
{
  "settings": {
    "key": "${STREAM_KEY}",
    "server": "${STREAM_URL}"
  },
  "type": "rtmp_common"
}
SERVICE

cat <<COLLECTION | run_as_streamer tee "$CONFIG_ROOT/basic/scenes/Basic.json" >/dev/null
{"current_program_scene":"${SCENE_NAME}","current_scene":"${SCENE_NAME}","name":"${COLLECTION_NAME}","scene_order":[{"name":"${SCENE_NAME}"}],"sources":[]}
COLLECTION

cat <<SCENE_LIST | run_as_streamer tee "$CONFIG_ROOT/basic/scene_collections.json" >/dev/null
{
  "current_scene_collection": "${COLLECTION_NAME}",
  "scene_collections": [
    {
      "name": "${COLLECTION_NAME}"
    }
  ]
}
SCENE_LIST

cat <<PROFILE_LIST | run_as_streamer tee "$CONFIG_ROOT/basic/profiles.json" >/dev/null
{
  "current_profile": "${COLLECTION_NAME}",
  "profiles": [
    {
      "name": "${COLLECTION_NAME}"
    }
  ]
}
PROFILE_LIST

cat <<GLOBAL | run_as_streamer tee "$CONFIG_ROOT/global.ini" >/dev/null
[General]
ConfigDir=$CONFIG_ROOT
[Basic]
Profile=${COLLECTION_NAME}
Collection=${COLLECTION_NAME}
GLOBAL

if [[ "$current_uid" -eq 0 ]]; then
  chown -R "$STREAM_USER":"$STREAM_USER" "$OBS_HOME/.config" "$OBS_HOME/logs" "$CACHE_ROOT"
fi

echo "OBS profile '${COLLECTION_NAME}' created for user ${STREAM_USER}."
