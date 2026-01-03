#!/usr/bin/env bash
set -euo pipefail

# Repairs ownership and permissions for YouTube Stream install artifacts.
# This is useful when scripts were run as the wrong user or files were copied
# from another host and inherited unexpected owners/groups.

APP_DIR=${APP_DIR:-/opt/youtube-stream/webapp}
STREAM_USER=${STREAM_USER:-streamer}
OBS_HOME=${OBS_HOME:-/var/lib/${STREAM_USER}}
ENV_FILE=${ENV_FILE:-/etc/youtube-stream/env}
REACT_SERVICE=react-web.service
OBS_SERVICE=obs-headless.service

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo or as root so it can adjust ownership." >&2
  exit 1
fi

if ! id -u "$STREAM_USER" >/dev/null 2>&1; then
  echo "Service user ${STREAM_USER} does not exist. Run install_dependencies.sh first." >&2
  exit 1
fi

log_step() { printf '\n=== %s ===\n' "$1"; }
log_info() { printf '[INFO] %s\n' "$1"; }

ensure_dir() {
  local path="$1" owner="$2" group="$3" mode="$4"
  install -d -m "$mode" "$path"
  chown "$owner":"$group" "$path"
  log_info "Set $path -> $owner:$group ($mode)"
}

ensure_file() {
  local path="$1" owner="$2" group="$3" mode="$4" template="$5"
  mkdir -p "$(dirname "$path")"
  if [ ! -f "$path" ]; then
    printf '%s\n' "$template" >"$path"
  fi
  chown "$owner":"$group" "$path"
  chmod "$mode" "$path"
  log_info "Set $path -> $owner:$group ($mode)"
}

repair_app_tree() {
  log_step "App directory"
  ensure_dir "$APP_DIR" "$STREAM_USER" "$STREAM_USER" 755
  if [ -d "$APP_DIR" ]; then
    chown -R "$STREAM_USER":"$STREAM_USER" "$APP_DIR"
    log_info "Recursively ensured $APP_DIR is owned by ${STREAM_USER}:${STREAM_USER}"
  fi
}

repair_obs_tree() {
  log_step "OBS directories"
  ensure_dir "$OBS_HOME" "$STREAM_USER" "$STREAM_USER" 755
  ensure_dir "$OBS_HOME/.config" "$STREAM_USER" "$STREAM_USER" 755
  ensure_dir "$OBS_HOME/.config/obs-studio" "$STREAM_USER" "$STREAM_USER" 755
  ensure_dir "$OBS_HOME/.cache" "$STREAM_USER" "$STREAM_USER" 755
  ensure_dir "$OBS_HOME/logs" "$STREAM_USER" "$STREAM_USER" 755
  if [ -d "$OBS_HOME" ]; then
    chown -R "$STREAM_USER":"$STREAM_USER" "$OBS_HOME"
    log_info "Recursively ensured $OBS_HOME is owned by ${STREAM_USER}:${STREAM_USER}"
  fi
}

repair_env() {
  log_step "Environment file"
  ensure_dir "$(dirname "$ENV_FILE")" root root 750
  ensure_file "$ENV_FILE" root root 640 "# YOUTUBE_STREAM_KEY="
}

repair_systemd_units() {
  log_step "systemd units"
  for unit in "$REACT_SERVICE" "$OBS_SERVICE"; do
    local path="/etc/systemd/system/${unit}"
    if [ -f "$path" ]; then
      chown root:root "$path"
      chmod 644 "$path"
      log_info "Normalized $path ownership to root:root (644)"
    else
      log_info "Skipped $path (not present)"
    fi
  done
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
  else
    log_info "systemctl not available; skipped daemon-reload"
  fi
}

repair_app_tree
repair_obs_tree
repair_env
repair_systemd_units

log_step "Done"
log_info "Permissions normalized. Restart services if files changed."
