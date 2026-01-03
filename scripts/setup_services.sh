#!/usr/bin/env bash
set -euo pipefail

# Creates and enables systemd services for the React dev server and headless OBS streaming.

STREAM_USER=${STREAM_USER:-mjhughes}
APP_DIR=${APP_DIR:-/opt/youtube-stream/webapp}
OBS_HOME=${OBS_HOME:-/var/lib/${STREAM_USER}}
ENV_FILE=${ENV_FILE:-/etc/youtube-stream/env}
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

install -d -m 750 "$(dirname "$ENV_FILE")"
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
Environment=BROWSER=none
Environment=CI=true
ExecStart=/usr/bin/npm start
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
ExecStart=/usr/bin/xvfb-run -a obs --collection YouTubeHeadless --profile YouTubeHeadless --scene WebScene --startstreaming --minimize-to-tray --disable-updater --disable-shutdown-check
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
chmod 644 "/etc/systemd/system/${OBS_SERVICE}"
chown root:root "/etc/systemd/system/${OBS_SERVICE}"

systemctl daemon-reload
systemctl enable "${REACT_SERVICE}" "${OBS_SERVICE}"

cat <<NEXT
Services created. To start immediately:
  sudo systemctl start react-web.service
  sudo systemctl start obs-headless.service

Set your stream key in ${ENV_FILE} before starting obs-headless.service.
NEXT
