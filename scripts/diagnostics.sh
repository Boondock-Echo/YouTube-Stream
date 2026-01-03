#!/usr/bin/env bash
set -euo pipefail

# Diagnostics runner for the headless YouTube streaming stack.
# It checks dependencies, configuration, and systemd services to help pinpoint
# which step in the setup is failing.
#
# Usage:
#   sudo STREAM_USER=streamer APP_DIR=/opt/youtube-stream/webapp bash scripts/diagnostics.sh
# Flags:
#   --skip-systemd   Skip systemd unit checks (useful in containers without systemd)
#   --skip-network   Skip the HTTP check against APP_URL
#   --check-build    Run `npm run build --if-present` to validate the React app

APP_DIR=${APP_DIR:-/opt/youtube-stream/webapp}
STREAM_USER=${STREAM_USER:-streamer}
OBS_HOME=${OBS_HOME:-/var/lib/${STREAM_USER}}
ENV_FILE=${ENV_FILE:-/etc/youtube-stream/env}
APP_URL=${APP_URL:-http://localhost:3000}
STREAM_URL=${STREAM_URL:-rtmp://a.rtmp.youtube.com/live2}
COLLECTION_NAME=${COLLECTION_NAME:-YouTubeHeadless}
SCENE_NAME=${SCENE_NAME:-WebScene}
REACT_SERVICE=react-web.service
OBS_SERVICE=obs-headless.service

SKIP_SYSTEMD=0
SKIP_NETWORK=0
CHECK_BUILD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-systemd) SKIP_SYSTEMD=1 ;;
    --skip-network) SKIP_NETWORK=1 ;;
    --check-build) CHECK_BUILD=1 ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--skip-systemd] [--skip-network] [--check-build]" >&2
      exit 1
      ;;
  esac
  shift
done

passes=()
warnings=()
failures=()
ENV_STREAM_KEY=""
SERVICE_STREAM_KEY=""

log_pass() { passes+=("$1"); printf '[PASS] %s\n' "$1"; }
log_warn() { warnings+=("$1"); printf '[WARN] %s\n' "$1"; }
log_fail() { failures+=("$1"); printf '[FAIL] %s\n' "$1"; }

is_root() {
  [[ "$(id -u)" -eq 0 ]]
}

check_command() {
  local cmd="$1"
  local label="${2:-$cmd}"
  if command -v "$cmd" >/dev/null 2>&1; then
    log_pass "$label present ($(command -v "$cmd"))"
  else
    log_fail "$label missing (install_dependencies.sh should install it)"
  fi
}

check_node_version() {
  if ! command -v node >/dev/null 2>&1; then
    log_fail "Node.js not found (run scripts/install_dependencies.sh)"
    return
  fi
  local required_major=20
  local major
  major=$(node -p "process.versions.node.split('.')[0]")
  if [[ "$major" -ge "$required_major" ]]; then
    log_pass "Node.js version $major detected (>= $required_major)"
  else
    log_fail "Node.js version $major is below required $required_major"
  fi
}

check_user() {
  if is_root; then
    if id -u "$STREAM_USER" >/dev/null 2>&1; then
      log_pass "Service user ${STREAM_USER} exists"
    else
      log_fail "Service user ${STREAM_USER} missing (install_dependencies.sh should create it)"
    fi
  else
    log_warn "Not running as root; skipping user existence check for ${STREAM_USER}"
  fi
}

check_app() {
  if [[ -f "$APP_DIR/package.json" ]]; then
    log_pass "React app found at $APP_DIR"
  else
    log_fail "React app missing at $APP_DIR (run scripts/bootstrap_react_app.sh)"
    return
  fi

  if [[ -d "$APP_DIR/node_modules" ]]; then
    log_pass "Dependencies installed in $APP_DIR/node_modules"
  else
    log_warn "Dependencies not installed (run npm install --prefix \"$APP_DIR\")"
  fi

  if [[ "$CHECK_BUILD" -eq 1 ]]; then
    if (cd "$APP_DIR" && npm run build --if-present >/tmp/yt-stream-build.log 2>&1); then
      log_pass "React app build succeeded (logs in /tmp/yt-stream-build.log)"
    else
      log_fail "React app build failed (see /tmp/yt-stream-build.log)"
    fi
  fi
}

check_env_file() {
  if [[ -r "$ENV_FILE" ]]; then
    local key
    key=$(grep -E "^YOUTUBE_STREAM_KEY=" "$ENV_FILE" | head -n1 | cut -d'=' -f2-)
    ENV_STREAM_KEY="$key"
    if [[ -n "$key" ]]; then
      log_pass "YOUTUBE_STREAM_KEY set in $ENV_FILE"
    else
      log_warn "YOUTUBE_STREAM_KEY is empty in $ENV_FILE"
    fi
  else
    if [[ -f "$ENV_FILE" ]]; then
      log_warn "Env file $ENV_FILE exists but is not readable"
    else
      log_warn "Env file $ENV_FILE missing (setup_services.sh will create a template)"
    fi
  fi
}

check_obs_config() {
  local config_root="$OBS_HOME/.config/obs-studio"
  local profile_dir="$config_root/basic/profiles/${COLLECTION_NAME}"
  local scene_file="$config_root/basic/scenes/${COLLECTION_NAME}.json"
  local service_file="$profile_dir/service.json"
  local basic_ini="$profile_dir/basic.ini"
  local scene_registry="$config_root/basic/scene_collections.json"
  local profile_registry="$config_root/basic/profiles.json"

  if [[ -d "$config_root" ]]; then
    log_pass "OBS config directory present at $config_root"
  else
    log_fail "OBS config directory missing at $config_root (run scripts/configure_obs.sh)"
    return
  fi

  [[ -f "$scene_file" ]] && log_pass "Scene collection exists (${scene_file})" || log_fail "Scene collection missing (${scene_file})"
  [[ -f "$basic_ini" ]] && log_pass "Profile settings exist (${basic_ini})" || log_fail "Profile settings missing (${basic_ini})"
  [[ -f "$scene_registry" ]] && log_pass "Scene collection registry exists (${scene_registry})" || log_warn "Scene collection registry missing (${scene_registry})"
  [[ -f "$profile_registry" ]] && log_pass "Profile registry exists (${profile_registry})" || log_warn "Profile registry missing (${profile_registry})"

  if [[ -f "$service_file" ]]; then
    local key
    key=$(grep -oE '"key"[[:space:]]*:[[:space:]]*"[^"]*"' "$service_file" | head -n1 | sed 's/.*"key"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/')
    SERVICE_STREAM_KEY="$key"
    if [[ -n "$key" ]]; then
      log_pass "OBS service.json contains a stream key"
    else
      log_warn "OBS service.json is missing a stream key"
    fi
  else
    log_fail "OBS service.json missing (${service_file})"
  fi
}

compare_stream_keys() {
  if [[ -n "$ENV_STREAM_KEY" && -n "$SERVICE_STREAM_KEY" ]]; then
    if [[ "$ENV_STREAM_KEY" == "$SERVICE_STREAM_KEY" ]]; then
      log_pass "Stream key matches between $ENV_FILE and service.json"
    else
      log_warn "Stream key in $ENV_FILE differs from service.json (rerun configure_obs.sh)"
    fi
  fi
}

check_stream_target() {
  local proto host port hostport
  if [[ "$STREAM_URL" == rtmps://* ]]; then
    proto="rtmps"
    hostport="${STREAM_URL#rtmps://}"
  else
    proto="rtmp"
    hostport="${STREAM_URL#rtmp://}"
  fi

  hostport="${hostport%%/*}"
  host="${hostport%%:*}"
  port="${hostport##*:}"

  if [[ "$host" == "$hostport" ]]; then
    port=$([[ "$proto" == "rtmps" ]] && echo 443 || echo 1935)
  fi

  if [[ -z "$host" ]]; then
    log_warn "Unable to parse host from STREAM_URL ($STREAM_URL)"
    return
  fi

  if getent hosts "$host" >/dev/null 2>&1; then
    log_pass "Resolved RTMP host $host"
  else
    log_fail "Could not resolve RTMP host $host"
    return
  fi

  if command -v timeout >/dev/null 2>&1; then
    if timeout 5 bash -c ">/dev/tcp/$host/$port" 2>/dev/null; then
      log_pass "TCP connectivity to $host:$port for $proto verified"
    else
      log_warn "TCP check to $host:$port failed (firewall or network issue?)"
    fi
  else
    log_warn "timeout not available; skipping RTMP TCP connectivity check"
  fi
}

check_obs_permissions() {
  local config_root="$OBS_HOME/.config/obs-studio"
  local owner

  if [[ ! -d "$OBS_HOME" ]]; then
    log_warn "OBS home $OBS_HOME does not exist (configure_obs.sh should create it)"
    return
  fi

  if command -v stat >/dev/null 2>&1; then
    owner=$(stat -c '%U:%G' "$OBS_HOME" 2>/dev/null || true)
    if [[ -n "$owner" && "$owner" != "$STREAM_USER:$STREAM_USER" ]]; then
      log_warn "OBS home $OBS_HOME owned by $owner (expected ${STREAM_USER}:${STREAM_USER})"
    else
      log_pass "OBS home $OBS_HOME ownership is ${STREAM_USER}:${STREAM_USER}"
    fi
  fi

  if [[ -d "$config_root" ]]; then
    if sudo -u "$STREAM_USER" test -w "$config_root" 2>/dev/null; then
      log_pass "OBS config directory writable by ${STREAM_USER} ($config_root)"
    else
      log_fail "OBS config directory not writable by ${STREAM_USER} ($config_root)"
    fi
  else
    log_warn "OBS config directory missing at $config_root"
  fi
}

check_obs_logs() {
  local log_dir="$OBS_HOME/logs/obs-studio"
  [[ -d "$log_dir" ]] || log_dir="$OBS_HOME/logs"

  if [[ ! -d "$log_dir" ]]; then
    log_warn "OBS log directory not found at $log_dir"
    return
  fi

  local latest
  latest=$(find "$log_dir" -maxdepth 1 -type f -name "*.txt" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)

  if [[ -z "$latest" ]]; then
    log_warn "No OBS log files found in $log_dir"
    return
  fi

  if grep -Ei "rtmp|rtmps|connection failed|output fail" "$latest" >/dev/null 2>&1; then
    log_warn "Latest OBS log ($latest) contains RTMP or output error entries"
    grep -Ein "rtmp|rtmps|connection failed|output fail" "$latest" | head -n 5
  else
    log_pass "Latest OBS log ($latest) has no RTMP/output errors detected"
  fi
}

check_systemd_unit() {
  local unit="$1"
  if ! command -v systemctl >/dev/null 2>&1; then
    log_warn "systemctl not available; skipping $unit checks"
    return
  fi

  if ! systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q "$unit"; then
    log_fail "$unit not registered (run scripts/setup_services.sh)"
    return
  fi

  if systemctl is-enabled "$unit" >/dev/null 2>&1; then
    log_pass "$unit is enabled"
  else
    log_warn "$unit is disabled"
  fi

  local status
  status=$(systemctl is-active "$unit" 2>/dev/null || true)
  case "$status" in
    active) log_pass "$unit is active" ;;
    inactive) log_warn "$unit is inactive (start with: sudo systemctl start $unit)" ;;
    failed) log_fail "$unit is failed (inspect logs via: journalctl -u $unit --no-pager)" ;;
    *) log_warn "$unit status unknown ($status)" ;;
  esac
}

check_network() {
  if [[ "$SKIP_NETWORK" -eq 1 ]]; then
    log_warn "Skipping APP_URL check as requested"
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log_warn "curl not available; skipping APP_URL check"
    return
  fi

  if curl -fsS --max-time 5 "$APP_URL" >/dev/null 2>&1; then
    log_pass "HTTP check passed for $APP_URL"
  else
    log_warn "HTTP check failed for $APP_URL (service may be down)"
  fi
}

main() {
  echo "=== YouTube Stream Diagnostics ==="
  echo "User: $(whoami) (uid $(id -u))"
  echo "App dir: $APP_DIR"
  echo "OBS home: $OBS_HOME"
  echo "Env file: $ENV_FILE"
  echo "Systemd checks: $([[ "$SKIP_SYSTEMD" -eq 1 ]] && echo skipped || echo enabled)"
  echo "Network check: $([[ "$SKIP_NETWORK" -eq 1 ]] && echo skipped || echo enabled)"
  echo "Build check: $([[ "$CHECK_BUILD" -eq 1 ]] && echo enabled || echo skipped)"
  echo

  check_command curl "curl"
  check_command ffmpeg "ffmpeg"
  check_command xvfb-run "xvfb-run"
  check_command obs "obs"
  check_command npm "npm"
  check_command npx "npx"
  check_node_version
  check_user
  check_app
  check_env_file
  check_obs_config
  check_obs_permissions
  compare_stream_keys

  if [[ "$SKIP_SYSTEMD" -eq 0 ]]; then
    check_systemd_unit "$REACT_SERVICE"
    check_systemd_unit "$OBS_SERVICE"
  else
    log_warn "Skipping systemd unit checks"
  fi

  check_stream_target
  check_network
  check_obs_logs

  echo
  echo "=== Summary ==="
  for msg in "${passes[@]}"; do echo "PASS: $msg"; done
  for msg in "${warnings[@]}"; do echo "WARN: $msg"; done
  for msg in "${failures[@]}"; do echo "FAIL: $msg"; done

  if [[ ${#failures[@]} -gt 0 ]]; then
    echo
    echo "Failures detected. Review the FAIL items above for next steps."
    exit 1
  fi
}

main "$@"
