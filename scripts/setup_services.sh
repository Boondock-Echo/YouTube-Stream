#!/usr/bin/env bash
set -euo pipefail

# Creates and enables systemd services for the built React frontend and headless OBS streaming.

STREAM_USER=${STREAM_USER:-streamer}
APP_DIR=${APP_DIR:-/opt/youtube-stream/webapp}
OBS_HOME=${OBS_HOME:-/var/lib/${STREAM_USER}}
ENV_FILE=${ENV_FILE:-/etc/youtube-stream/env}
COLLECTION_NAME=${COLLECTION_NAME:-YouTubeHeadless}
VIDEO_BASE_WIDTH=${VIDEO_BASE_WIDTH:-1024}
VIDEO_BASE_HEIGHT=${VIDEO_BASE_HEIGHT:-576}
LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE:-1}
REACT_SERVICE=react-web.service
OBS_SERVICE=obs-headless.service

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo or as root so it can create systemd units." >&2
  exit 1
fi

if [ ! -f "$APP_DIR/package.json" ]; then
  echo "React app not found at $APP_DIR. Run scripts/bootstrap_react_app.sh first." >&2
  exit 1
fi

normalize_stream_key() {
  local key="${1%$'\r'}"
  key="${key#"${key%%[![:space:]]*}"}"
  key="${key%"${key##*[![:space:]]}"}"

  if [[ ${#key} -ge 2 ]]; then
    local first=${key:0:1}
    local last=${key: -1}
    if [[ ( "$first" == '"' && "$last" == '"' ) || ( "$first" == "'" && "$last" == "'" ) ]]; then
      key="${key:1:-1}"
    fi
  fi

  printf '%s' "$key"
}

preflight_misconfig_warnings() {
  local raw_key normalized_key service_file
  service_file="$OBS_HOME/.config/obs-studio/basic/profiles/${COLLECTION_NAME}/service.json"

  if [[ -r "$ENV_FILE" ]]; then
    raw_key=$(grep -E "^YOUTUBE_STREAM_KEY=" "$ENV_FILE" | head -n1 | cut -d'=' -f2-)
    normalized_key=$(normalize_stream_key "$raw_key")
    if [[ -z "$normalized_key" ]]; then
      echo "WARNING: YOUTUBE_STREAM_KEY is empty in ${ENV_FILE}; obs-headless.service will restart until a key is provided."
    fi
  else
    echo "WARNING: Env file ${ENV_FILE} is missing or unreadable; obs-headless.service will restart until it exists."
  fi

  if [[ ! -f "$service_file" ]]; then
    echo "WARNING: OBS profile for ${COLLECTION_NAME} not found at ${service_file}. Run scripts/configure_obs.sh before starting obs-headless.service."
  fi
}

# Build the React app so the production bundle is available for the service.
echo "Installing dependencies and building React app at ${APP_DIR}..."
sudo -u "${STREAM_USER}" HOME="${OBS_HOME}" bash -c "cd '${APP_DIR}' && npm install && npm run build"

install -d -m 750 "$(dirname "$ENV_FILE")"
# Install/update the preflight guard used by obs-headless.service
install -m 755 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/obs_headless_preflight.sh" /usr/local/bin/obs-headless-preflight

if [ ! -f "$ENV_FILE" ]; then
  cat <<ENV | tee "$ENV_FILE" >/dev/null
# Insert your YouTube stream key and restart services after editing.
YOUTUBE_STREAM_KEY=
ENV
  chmod 640 "$ENV_FILE"
  chown root:root "$ENV_FILE"
else
  chmod 640 "$ENV_FILE"
  chown root:root "$ENV_FILE"
fi

cat <<UNIT | tee "/etc/systemd/system/${REACT_SERVICE}" >/dev/null
[Unit]
Description=React sample web frontend for YouTube streaming
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${STREAM_USER}
WorkingDirectory=${APP_DIR}
Environment=HOST=0.0.0.0
Environment=PORT=3000
Environment=NODE_ENV=production
ExecStartPre=/bin/bash -lc 'cd ${APP_DIR} && [ -d node_modules ] || npm install'
ExecStartPre=/bin/bash -lc 'cd ${APP_DIR} && npm run build'
ExecStart=/usr/bin/npx --yes serve -s build -l tcp://0.0.0.0:3000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
chmod 644 "/etc/systemd/system/${REACT_SERVICE}"
chown root:root "/etc/systemd/system/${REACT_SERVICE}"

cat <<UNIT | tee "/etc/systemd/system/${OBS_SERVICE}" >/dev/null
[Unit]
Description=OBS headless YouTube streaming
After=${REACT_SERVICE} network-online.target
Wants=${REACT_SERVICE} network-online.target

[Service]
Type=simple
User=${STREAM_USER}
WorkingDirectory=${OBS_HOME}
Environment=HOME=${OBS_HOME}
Environment=XDG_CONFIG_HOME=${OBS_HOME}/.config
Environment=XDG_CACHE_HOME=${OBS_HOME}/.cache
EnvironmentFile=${ENV_FILE}
Environment=LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE}
ExecStartPre=/usr/local/bin/obs-headless-preflight
ExecStart=/usr/bin/xvfb-run -a -s "-screen 0 ${VIDEO_BASE_WIDTH}x${VIDEO_BASE_HEIGHT}x24 -ac +extension GLX +render -noreset" obs --collection YouTubeHeadless --profile YouTubeHeadless --scene WebScene --startstreaming --minimize-to-tray --disable-updater --disable-shutdown-check
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
chmod 644 "/etc/systemd/system/${OBS_SERVICE}"
chown root:root "/etc/systemd/system/${OBS_SERVICE}"

systemctl daemon-reload
systemctl enable "${REACT_SERVICE}" "${OBS_SERVICE}"

preflight_misconfig_warnings

cat <<NEXT
Services created. To start immediately:
  sudo systemctl start react-web.service
  sudo systemctl start obs-headless.service

Set your stream key in ${ENV_FILE} before starting obs-headless.service.
NEXT
