#!/usr/bin/env bash
set -euo pipefail

# Creates an OBS Studio profile and scene collection for headless streaming of the React app.

STREAM_USER=${STREAM_USER:-mjhughes}
OBS_HOME=${OBS_HOME:-/var/lib/${STREAM_USER}}
CONFIG_ROOT="$OBS_HOME/.config/obs-studio"
CACHE_ROOT="$OBS_HOME/.cache/obs-studio"
COLLECTION_NAME=${COLLECTION_NAME:-YouTubeHeadless}
SCENE_NAME=${SCENE_NAME:-WebScene}
SOURCE_NAME=${SOURCE_NAME:-BrowserSource}
STREAM_KEY=${YOUTUBE_STREAM_KEY:-}
STREAM_URL=${STREAM_URL:-rtmp://a.rtmp.youtube.com/live2}
APP_URL=${APP_URL:-http://localhost:3000}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo or as root so it can write OBS config files." >&2
  exit 1
fi

if [ -z "$STREAM_KEY" ]; then
  echo "Set YOUTUBE_STREAM_KEY in the environment before running this script." >&2
  exit 1
fi

# Ensure the service user exists and has a home directory. Without this, OBS will
# segfault on startup when it cannot resolve config paths (manifesting as
# `basic_string: construction from null is not valid`).
if ! id -u "$STREAM_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "$OBS_HOME" --shell /bin/bash "$STREAM_USER"
fi

mkdir -p "$OBS_HOME"
chown -R "$STREAM_USER":"$STREAM_USER" "$OBS_HOME"

mkdir -p "$CONFIG_ROOT/basic/profiles/${COLLECTION_NAME}" "$CONFIG_ROOT/basic/scenes" "$OBS_HOME/logs" "$CACHE_ROOT"

# Scene collection with a single browser source pointing to the React app
cat <<SCENE | sudo -u "$STREAM_USER" tee "$CONFIG_ROOT/basic/scenes/${COLLECTION_NAME}.json" >/dev/null
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
cat <<PROFILE | sudo -u "$STREAM_USER" tee "$CONFIG_ROOT/basic/profiles/${COLLECTION_NAME}/basic.ini" >/dev/null
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

cat <<SERVICE | sudo -u "$STREAM_USER" tee "$CONFIG_ROOT/basic/profiles/${COLLECTION_NAME}/service.json" >/dev/null
{
  "settings": {
    "key": "${STREAM_KEY}",
    "server": "${STREAM_URL}"
  },
  "type": "rtmp_common"
}
SERVICE

cat <<COLLECTION | sudo -u "$STREAM_USER" tee "$CONFIG_ROOT/basic/scenes/Basic.json" >/dev/null
{"current_program_scene":"${SCENE_NAME}","current_scene":"${SCENE_NAME}","name":"${COLLECTION_NAME}","scene_order":[{"name":"${SCENE_NAME}"}],"sources":[]}
COLLECTION

cat <<SCENE_LIST | sudo -u "$STREAM_USER" tee "$CONFIG_ROOT/basic/scene_collections.json" >/dev/null
{
  "current_scene_collection": "${COLLECTION_NAME}",
  "scene_collections": [
    {
      "name": "${COLLECTION_NAME}"
    }
  ]
}
SCENE_LIST

cat <<PROFILE_LIST | sudo -u "$STREAM_USER" tee "$CONFIG_ROOT/basic/profiles.json" >/dev/null
{
  "current_profile": "${COLLECTION_NAME}",
  "profiles": [
    {
      "name": "${COLLECTION_NAME}"
    }
  ]
}
PROFILE_LIST

cat <<GLOBAL | sudo -u "$STREAM_USER" tee "$CONFIG_ROOT/global.ini" >/dev/null
[General]
ConfigDir=$CONFIG_ROOT
[Basic]
Profile=${COLLECTION_NAME}
Collection=${COLLECTION_NAME}
GLOBAL

chown -R "$STREAM_USER":"$STREAM_USER" "$OBS_HOME/.config" "$OBS_HOME/logs" "$CACHE_ROOT"

echo "OBS profile '${COLLECTION_NAME}' created for user ${STREAM_USER}."
