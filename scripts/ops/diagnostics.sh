#!/usr/bin/env bash
set -euo pipefail

# Diagnostics runner for the headless YouTube streaming stack.
# It checks dependencies, configuration, and systemd services to help pinpoint
# which step in the setup is failing.
#
# Usage:
#   sudo STREAM_USER=streamer APP_DIR=/opt/youtube-stream/webapp bash scripts/ops/diagnostics.sh
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
LATEST_OBS_LOG=""
INSTALLED_OBS_MODULES=()
INSTALLED_OBS_PLUGIN_DIRS=()
SCENE_FILE=""

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
obs_log_notes=()
ENV_STREAM_KEY=""
SERVICE_STREAM_KEY=""

log_pass() { passes+=("$1"); printf '[PASS] %s\n' "$1"; }
log_warn() { warnings+=("$1"); printf '[WARN] %s\n' "$1"; }
log_fail() { failures+=("$1"); printf '[FAIL] %s\n' "$1"; }
append_obs_log_note() { obs_log_notes+=("$1"); }

format_stream_key() {
  local key="$1"
  local len=${#key}
  local escaped
  escaped=$(printf '%q' "$key")

  if [[ -z "$key" ]]; then
    echo "<empty>"
  elif [[ "$len" -le 6 ]]; then
    printf "'%s' (len=%d, shell-escaped=%s)" "$key" "$len" "$escaped"
  else
    printf "'%s...%s' (len=%d, shell-escaped=%s)" "${key:0:3}" "${key: -3}" "$len" "$escaped"
  fi
}

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

is_root() {
  [[ "$(id -u)" -eq 0 ]]
}

check_command() {
  local cmd="$1"
  local label="${2:-$cmd}"
  if command -v "$cmd" >/dev/null 2>&1; then
    log_pass "$label present ($(command -v "$cmd"))"
  else
    log_fail "$label missing (scripts/install/install_dependencies.sh should install it)"
  fi
}

check_node_version() {
  if ! command -v node >/dev/null 2>&1; then
    log_fail "Node.js not found (run scripts/install/install_dependencies.sh)"
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

collect_obs_plugins() {
  local -A seen dir_seen
  local modules=() candidates=()
  INSTALLED_OBS_PLUGIN_DIRS=()

  # Common OBS plugin roots across distros (Debian/Ubuntu use multiarch paths).
  candidates=(
    /usr/lib/obs-plugins
    /usr/lib64/obs-plugins
    /usr/local/lib/obs-plugins
    /usr/local/lib64/obs-plugins
  )

  # Discover additional obs-plugins directories within /usr/lib* (e.g. /usr/lib/x86_64-linux-gnu/obs-plugins).
  while IFS= read -r -d '' found; do
    candidates+=("$found")
  done < <(find /usr/lib* -maxdepth 3 -type d -name obs-plugins -print0 2>/dev/null || true)

  for dir in "${candidates[@]}"; do
    [[ -d "$dir" ]] || continue
    if [[ -z "${dir_seen[$dir]:-}" ]]; then
      dir_seen[$dir]=1
      INSTALLED_OBS_PLUGIN_DIRS+=("$dir")
    fi

    while IFS= read -r plugin; do
      [[ -z "$plugin" ]] && continue
      local base="${plugin%.so}"
      local lower=${base,,}
      if [[ -z "${seen[$lower]:-}" ]]; then
        seen[$lower]=1
        modules+=("$lower")
      fi
    done < <(find "$dir" -maxdepth 1 -type f -name "*.so" -printf '%f\n' 2>/dev/null | sort -u)
  done

  INSTALLED_OBS_MODULES=("${modules[@]}")
}

check_obs_installation() {
  collect_obs_plugins

  if command -v obs >/dev/null 2>&1; then
    local version output
    output=$(obs --version 2>&1 || true)
    version=$(grep -oE 'OBS [^ ]+' <<<"$output" | head -n1 || true)
    if [[ -n "$version" ]]; then
      log_pass "OBS detected (${version})"
    else
      log_pass "OBS detected; version output: ${output%%$'\n'*}"
    fi
  else
    log_fail "obs binary not found (install OBS Studio)"
  fi

  if [[ ${#INSTALLED_OBS_PLUGIN_DIRS[@]} -gt 0 ]]; then
    log_pass "OBS plugin directories: ${INSTALLED_OBS_PLUGIN_DIRS[*]}"
  else
    log_warn "No OBS plugin directories found under /usr/lib*/obs-plugins"
  fi

  if [[ ${#INSTALLED_OBS_MODULES[@]} -gt 0 ]]; then
    log_pass "Detected OBS plugins/modules: ${INSTALLED_OBS_MODULES[*]}"
  else
    log_warn "No OBS plugin shared libraries detected; browser/vlc sources will fail to load"
  fi
}

check_user() {
  if is_root; then
    if id -u "$STREAM_USER" >/dev/null 2>&1; then
      log_pass "Service user ${STREAM_USER} exists"
    else
      log_fail "Service user ${STREAM_USER} missing (scripts/install/install_dependencies.sh should create it)"
    fi
  else
    log_warn "Not running as root; skipping user existence check for ${STREAM_USER}"
  fi
}

check_user_permissions() {
  if ! id -u "$STREAM_USER" >/dev/null 2>&1; then
    log_warn "Skipping permission checks; service user ${STREAM_USER} not found"
    return
  fi

  if ! is_root; then
    log_warn "Run as root to verify ${STREAM_USER} directory permissions"
    return
  fi

  local checks=(
    "$OBS_HOME:1:OBS home directory"
    "$OBS_HOME/.config:1:OBS config parent"
    "$OBS_HOME/.config/obs-studio:1:OBS Studio config root"
    "$APP_DIR:0:React app directory"
  )

  for entry in "${checks[@]}"; do
    IFS=":" read -r path requires_write description <<<"$entry"

    if [[ ! -d "$path" ]]; then
      log_warn "Cannot check permissions; ${description} missing at $path"
      continue
    fi

    if ! sudo -u "$STREAM_USER" test -r "$path" -a -x "$path"; then
      log_fail "${STREAM_USER} cannot read/enter ${description} at $path"
      continue
    fi

    if [[ "$requires_write" -eq 1 ]] && ! sudo -u "$STREAM_USER" test -w "$path"; then
      log_fail "${STREAM_USER} cannot write to ${description} at $path"
      continue
    fi

    if [[ "$requires_write" -eq 1 ]]; then
      log_pass "${STREAM_USER} has read/write access to ${description} at $path"
    else
      log_pass "${STREAM_USER} has read access to ${description} at $path"
    fi
  done
}

describe_permissions() {
  if ! is_root; then
    log_warn "Run as root to verify detailed ownership and permissions"
    return
  fi

  local entries=(
    "$APP_DIR:${STREAM_USER}:${STREAM_USER}:755:App directory"
    "$OBS_HOME:${STREAM_USER}:${STREAM_USER}:755:OBS home directory"
    "$OBS_HOME/.config:${STREAM_USER}:${STREAM_USER}:755:OBS config parent"
    "$OBS_HOME/.config/obs-studio:${STREAM_USER}:${STREAM_USER}:755:OBS Studio config root"
    "$(dirname "$ENV_FILE"):root:root:750:Env directory"
    "$ENV_FILE:root:root:640:Env file"
    "/etc/systemd/system/${REACT_SERVICE}:root:root:644:Systemd unit (${REACT_SERVICE})"
    "/etc/systemd/system/${OBS_SERVICE}:root:root:644:Systemd unit (${OBS_SERVICE})"
  )

  for entry in "${entries[@]}"; do
    IFS=":" read -r path owner group mode label <<<"$entry"
    if [[ ! -e "$path" ]]; then
      log_warn "Cannot inspect $label at $path (missing)"
      continue
    fi
    local actual_owner actual_group actual_mode
    actual_owner=$(stat -c '%U' "$path")
    actual_group=$(stat -c '%G' "$path")
    actual_mode=$(stat -c '%a' "$path")

    if [[ "$actual_owner" == "$owner" && "$actual_group" == "$group" && "$actual_mode" == "$mode" ]]; then
      log_pass "$label ownership ${owner}:${group} with mode ${mode}"
    else
      log_warn "$label ownership/mode is ${actual_owner}:${actual_group} (${actual_mode}), expected ${owner}:${group} (${mode})"
    fi
  done
}

check_app() {
  if [[ -f "$APP_DIR/package.json" ]]; then
    log_pass "React app found at $APP_DIR"
  else
    log_fail "React app missing at $APP_DIR (run scripts/install/bootstrap_react_app.sh)"
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
  local raw_key file_key env_key
  if [[ -r "$ENV_FILE" ]]; then
    raw_key=$(grep -E "^YOUTUBE_STREAM_KEY=" "$ENV_FILE" | head -n1 | cut -d'=' -f2-)
    file_key=$(normalize_stream_key "$raw_key")
    if [[ -n "$file_key" ]]; then
      log_pass "YOUTUBE_STREAM_KEY set in $ENV_FILE"
      ENV_STREAM_KEY="$file_key"
    else
      log_warn "YOUTUBE_STREAM_KEY is empty in $ENV_FILE"
    fi
  else
    if [[ -f "$ENV_FILE" ]]; then
      log_warn "Env file $ENV_FILE exists but is not readable"
    else
      log_warn "Env file $ENV_FILE missing (setup_services.sh will create a template); edit it as root (sudo) and keep ownership root:root, mode 640"
    fi
  fi

  env_key=$(normalize_stream_key "${YOUTUBE_STREAM_KEY:-}")
  if [[ -n "$env_key" ]]; then
    if [[ -n "$file_key" && "$file_key" != "$env_key" ]]; then
      log_warn "YOUTUBE_STREAM_KEY in environment differs from $ENV_FILE: env $(format_stream_key "$env_key") vs file $(format_stream_key "$file_key")"
    fi
    if [[ -z "$ENV_STREAM_KEY" ]]; then
      ENV_STREAM_KEY="$env_key"
      log_pass "Using YOUTUBE_STREAM_KEY from environment"
    fi
  fi

  if [[ -z "$ENV_STREAM_KEY" ]]; then
    log_warn "YOUTUBE_STREAM_KEY not set in environment or $ENV_FILE"
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
  SCENE_FILE="$scene_file"

  if [[ -d "$config_root" ]]; then
    log_pass "OBS config directory present at $config_root"
  else
    log_fail "OBS config directory missing at $config_root (run scripts/config/configure_obs.sh)"
    return
  fi

  [[ -f "$scene_file" ]] && log_pass "Scene collection exists (${scene_file})" || log_fail "Scene collection missing (${scene_file})"
  [[ -f "$basic_ini" ]] && log_pass "Profile settings exist (${basic_ini})" || log_fail "Profile settings missing (${basic_ini})"
  [[ -f "$scene_registry" ]] && log_pass "Scene collection registry exists (${scene_registry})" || log_warn "Scene collection registry missing (${scene_registry})"
  [[ -f "$profile_registry" ]] && log_pass "Profile registry exists (${profile_registry})" || log_warn "Profile registry missing (${profile_registry})"

  if [[ -f "$service_file" ]]; then
    local key
    key=$(grep -oE '"key"[[:space:]]*:[[:space:]]*"[^"]*"' "$service_file" | head -n1 | sed 's/.*"key"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/')
    key=$(normalize_stream_key "$key")
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
      local diff_note="Stream key mismatch detected:"
      diff_note+=" ENV: $(format_stream_key "$ENV_STREAM_KEY"), OBS service.json: $(format_stream_key "$SERVICE_STREAM_KEY")"
      log_warn "$diff_note (rerun configure_obs.sh)"
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

check_obs_logs() {
  if ! find_latest_obs_log; then
    return
  fi

  local latest="$LATEST_OBS_LOG"
  log_pass "Latest OBS log detected at $latest"

  # Catch common RTMP/output failures (connection refusals, auth errors, timeouts)
  local rtmp_error_pattern="((rtmp|rtmps).*(fail|error|refused|timeout|disconnect|denied|auth|invalid|could not|failed to connect))|(output.*(fail|error))"
  if grep -Ei "$rtmp_error_pattern" "$latest" >/dev/null 2>&1; then
    log_warn "Latest OBS log ($latest) contains RTMP or output error entries (see OBS log excerpts below)"
    local rtmp_matches log_tail
    rtmp_matches=$(grep -Ein "$rtmp_error_pattern" "$latest" | head -n 5 || true)
    log_tail=$(tail -n 25 "$latest" || true)
    append_obs_log_note "$(cat <<EOF
Latest OBS log ($latest) RTMP/output excerpts:
$rtmp_matches
--- Recent OBS log tail ---
$log_tail
---------------------------
EOF
)"
  else
    log_pass "Latest OBS log ($latest) has no RTMP/output errors detected"
  fi

  warn_on_obs_crash "$latest"
  warn_on_missing_encoders "$latest"
  warn_on_swapchain_failure "$latest"
}

warn_on_obs_crash() {
  local log_file="$1"
  local crash_patterns="basic_string: construction from null|std::logic_error|terminate called|core dumped"

  if grep -Eiq "$crash_patterns" "$log_file"; then
    log_warn "Latest OBS log ($log_file) shows a crash signature (see OBS log excerpts below)"
    local crash_matches log_tail
    crash_matches=$(grep -Ein "$crash_patterns" "$log_file" | head -n 5 || true)
    log_tail=$(tail -n 25 "$log_file" || true)
    append_obs_log_note "$(cat <<EOF
Latest OBS log ($log_file) crash excerpts:
$crash_matches
--- Recent OBS log tail ---
$log_tail
---------------------------
EOF
)"
  fi
}

warn_on_missing_encoders() {
  local log_file="$1"
  local missing_encoders
  missing_encoders=$(grep -Ein "Encoder ID '[^']+' not found" "$log_file" | head -n 5 || true)

  if [[ -n "$missing_encoders" ]]; then
    log_warn "Latest OBS log ($log_file) reports missing encoders (for example NVENC) — rerun configure_obs.sh to reset to x264 or install the matching GPU driver."
    append_obs_log_note "$(cat <<EOF
Latest OBS log ($log_file) encoder availability excerpts:
$missing_encoders
--- Recent OBS log tail ---
$(tail -n 25 "$log_file" || true)
---------------------------
EOF
)"
  fi
}

warn_on_swapchain_failure() {
  local log_file="$1"
  local swapchain_hits
  swapchain_hits=$(grep -Ein "Swapchain window creation failed|gl_platform_init_swapchain|obs_display_init: Failed to create swap chain" "$log_file" | head -n 5 || true)

  if [[ -n "$swapchain_hits" ]]; then
    log_warn "Latest OBS log ($log_file) shows swapchain/GL init failures — ensure obs runs under xvfb-run with GLX and depth 24, and set LIBGL_ALWAYS_SOFTWARE=1."
    append_obs_log_note "$(cat <<EOF
Latest OBS log ($log_file) swapchain/GL excerpts:
$swapchain_hits
--- Recent OBS log tail ---
$(tail -n 25 "$log_file" || true)
---------------------------
EOF
)"
  fi
}

plugin_is_builtin() {
  local id="${1,,}"
  case "$id" in
    ""|scene|group|transition|studio_mode|browser|audio_line|audio_input_capture|audio_output_capture|monitor_capture|fade_transition|cut_transition|swipe_transition|slide_transition|stinger_transition|fade_to_color_transition|luma_wipe_transition)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

plugin_candidates() {
  local id="${1,,}"
  case "$id" in
    browser_source) echo "browser_source obs-browser browser" ;;
    vlc_source) echo "vlc_source vlc-video vlc" ;;
    ffmpeg_source) echo "ffmpeg_source obs-ffmpeg" ;;
    text_ft2_source) echo "text_ft2_source text-freetype2" ;;
    image_source) echo "image_source image-source" ;;
    image_slide_show) echo "image_slide_show image-slideshow slideshow" ;;
    *) echo "$id" ;;
  esac
}

is_plugin_installed() {
  local primary="${1,,}"
  local alt=${2:-}
  alt="${alt,,}"
  if plugin_is_builtin "$primary"; then
    return 0
  fi

  local candidates=()
  read -r -a candidates <<<"$(plugin_candidates "$primary")"
  if [[ -n "$alt" && "$alt" != "$primary" ]]; then
    candidates+=("$alt")
  fi

  for candidate in "${candidates[@]}"; do
    local normalized="${candidate,,}"
    for mod in "${INSTALLED_OBS_MODULES[@]}"; do
      if [[ "$mod" == "$normalized" || "$mod" == "obs-$normalized" || "obs-$mod" == "$normalized" ]]; then
        return 0
      fi
    done
  done

  return 1
}

check_builtin_transitions() {
  local builtin_transitions=(fade_transition cut_transition swipe_transition slide_transition stinger_transition fade_to_color_transition luma_wipe_transition)
  local missing=()

  for transition in "${builtin_transitions[@]}"; do
    if ! plugin_is_builtin "$transition"; then
      missing+=("$transition")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    log_pass "Built-in transition IDs recognized as internal: ${builtin_transitions[*]}"
  else
    log_warn "Expected built-in transition IDs were not recognized: ${missing[*]} (update plugin_is_builtin)"
  fi
}

check_scene_plugins() {
  if [[ -z "$SCENE_FILE" || ! -f "$SCENE_FILE" ]]; then
    log_warn "Cannot analyze scene plugins; scene file missing (${SCENE_FILE:-unset})"
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    log_warn "jq not available; skipping scene plugin enumeration"
    return
  fi

  local modules_required scene_entries browser_seen=0 vlc_seen=0 missing_plugins=()

  modules_required=$(jq -r '.modules? // [] | .[]' "$SCENE_FILE" 2>/dev/null || true)
  if [[ -n "$modules_required" ]]; then
    local missing_modules=()
    while IFS= read -r mod; do
      [[ -z "$mod" ]] && continue
      if ! is_plugin_installed "$mod"; then
        missing_modules+=("$mod")
      fi
    done <<<"$modules_required"

    if [[ ${#missing_modules[@]} -gt 0 ]]; then
      log_fail "Scene modules listed in ${SCENE_FILE} not installed: ${missing_modules[*]}"
    else
      log_pass "All scene-declared modules present"
    fi
  fi

  scene_entries=$(jq -r '
    [
      .. | objects
      | select(has("id") or has("type"))
      | {id:(.id // ""), type:(.type // ""), name:(.name // .settings?.name // "")}
    ]
    | map("\(.id)|\(.type)|\(.name)") | unique[]
  ' "$SCENE_FILE" 2>/dev/null || true)

  if [[ -z "$scene_entries" ]]; then
    log_warn "No sources with id/type fields found in scene file $SCENE_FILE"
    return
  fi

  while IFS="|" read -r sid stype sname; do
    local label="${sname:-$sid}"
    [[ "$sid" == "browser_source" || "$stype" == "browser_source" ]] && browser_seen=1
    [[ "$sid" == "vlc_source" || "$stype" == "vlc_source" ]] && vlc_seen=1

    if ! is_plugin_installed "${stype:-$sid}" "$sid"; then
      local desc="${stype:-$sid}"
      missing_plugins+=("${desc:-unknown} (source=${label:-unnamed})")
    fi
  done <<<"$scene_entries"

  if [[ ${#missing_plugins[@]} -gt 0 ]]; then
    log_fail "Scene references missing or unknown plugin types: ${missing_plugins[*]}"
  else
    log_pass "All scene source ids/types appear to match installed plugins"
  fi

  if [[ $browser_seen -eq 1 ]] && ! is_plugin_installed "browser_source"; then
    log_fail "Scene references browser sources but obs-browser plugin is not installed (install obs-browser or obs-plugins-browser package)."
  fi

  if [[ $vlc_seen -eq 1 ]] && ! is_plugin_installed "vlc_source"; then
    log_fail "Scene references VLC sources but vlc-video plugin is not installed (install obs-vlc or obs-plugins-vlc package)."
  fi
}

normalize_url() {
  local url="$1"
  # Trim surrounding whitespace and trailing slashes
  url="${url#"${url%%[![:space:]]*}"}"
  url="${url%"${url##*[![:space:]]}"}"
  url="${url%/}"
  printf '%s' "$url"
}

fetch_browser_url() {
  local url="$1" label="$2"
  if [[ "$SKIP_NETWORK" -eq 1 ]]; then
    log_warn "Skipping browser source reachability check for ${label} due to --skip-network"
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log_warn "curl not available; cannot verify ${label} reachability (${url})"
    return
  fi

  local cmd=(curl -fsSL --max-time 8 "$url")
  local run_as="current user"
  if is_root && id -u "$STREAM_USER" >/dev/null 2>&1; then
    cmd=(sudo -u "$STREAM_USER" "${cmd[@]}")
    run_as="$STREAM_USER"
  fi

  local output status
  set +e
  output=$("${cmd[@]}" 2>/tmp/yt-stream-browser-check.err)
  status=$?
  set -e

  local trimmed="${output//[[:space:]]/}"
  if [[ $status -eq 0 && -n "$trimmed" ]]; then
    log_pass "Browser source URL reachable for ${label} (${url}) as ${run_as}"
  else
    local err=""
    if [[ -s /tmp/yt-stream-browser-check.err ]]; then
      err=$(head -n 1 /tmp/yt-stream-browser-check.err)
    fi
    log_warn "Browser source URL unreachable or empty for ${label} (${url}) as ${run_as} (status=${status}${err:+; curl: $err})"
  fi

  rm -f /tmp/yt-stream-browser-check.err
}

check_browser_scene_target() {
  if [[ -z "$SCENE_FILE" || ! -f "$SCENE_FILE" ]]; then
    log_warn "Cannot validate browser source target; scene file missing (${SCENE_FILE:-unset})"
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    log_warn "jq not available; skipping browser source target validation"
    return
  fi

  local expected_url expected_normalized
  expected_url="${APP_URL:-http://localhost:3000}"
  expected_normalized=$(normalize_url "$expected_url")
  [[ -z "$expected_normalized" ]] && expected_normalized="http://localhost:3000"

  local browser_entries
  browser_entries=$(jq -r '
    (.sources? // {} | to_entries[]
     | select((.value.id // "") == "browser_source" or (.value.type // "") == "browser_source")
     | "\(.key)|\(.value.name // .key)|\(.value.settings.url // "")")
  ' "$SCENE_FILE" 2>/dev/null || true)

  if [[ -z "$browser_entries" ]]; then
    log_fail "No browser_source entries found in scene file ${SCENE_FILE} (expected a source pointing at the React app)"
    return
  fi

  local matching=() mismatched=() missing_url=() urls=()
  while IFS="|" read -r source_key source_name source_url; do
    [[ -z "$source_key" ]] && continue
    local normalized_url
    normalized_url=$(normalize_url "$source_url")
    urls+=("${source_name:-$source_key}:${normalized_url}")

    if [[ -z "$normalized_url" ]]; then
      missing_url+=("${source_name:-$source_key}")
    elif [[ "$normalized_url" == "$expected_normalized" ]]; then
      matching+=("${source_name:-$source_key}")
    else
      mismatched+=("${source_name:-$source_key} (${normalized_url})")
    fi
  done <<<"$browser_entries"

  if [[ ${#missing_url[@]} -gt 0 ]]; then
    log_fail "Browser source(s) missing URL in ${SCENE_FILE}: ${missing_url[*]}"
  fi

  if [[ ${#matching[@]} -gt 0 ]]; then
    log_pass "Browser source URL matches expected React app (${expected_normalized}) for: ${matching[*]}"
  else
    log_fail "No browser sources point at expected React app URL (${expected_normalized}); found: ${urls[*]:-none}"
  fi

  if [[ ${#mismatched[@]} -gt 0 ]]; then
    log_warn "Browser sources with unexpected URLs (expected ${expected_normalized}): ${mismatched[*]}"
  fi

  # Reachability check against the first available URL (prefer matched, otherwise first non-empty)
  local probe_url probe_label
  if [[ ${#matching[@]} -gt 0 ]]; then
    probe_url="$expected_normalized"
    probe_label="${matching[0]}"
  else
    # Use the first non-empty URL
    for entry in "${urls[@]}"; do
      probe_label="${entry%%:*}"
      probe_url="${entry#*:}"
      [[ -n "$probe_url" ]] && break
    done
  fi

  if [[ -n "$probe_url" ]]; then
    fetch_browser_url "$probe_url" "$probe_label"
  fi
}

run_obs_dry_run() {
  if [[ -z "$SCENE_FILE" || ! -f "$SCENE_FILE" ]]; then
    log_warn "Skipping OBS dry-run load; scene file missing (${SCENE_FILE:-unset})"
    return
  fi

  if ! command -v obs >/dev/null 2>&1; then
    log_warn "Skipping OBS dry-run load; obs binary not found"
    return
  fi

  if ! command -v xvfb-run >/dev/null 2>&1; then
    log_warn "Skipping OBS dry-run load; xvfb-run not available"
    return
  fi

  local run_log="/tmp/obs-headless-dry-run.log"
  local cmd=(obs --collection "$COLLECTION_NAME" --profile "$COLLECTION_NAME" --scene "$SCENE_NAME" --unfiltered_log --disable-updater --disable-shutdown-check --minimize-to-tray --quit)

  if is_root && id -u "$STREAM_USER" >/dev/null 2>&1; then
    cmd=(sudo -E -u "$STREAM_USER" HOME="$OBS_HOME" XDG_CONFIG_HOME="$OBS_HOME/.config" XDG_CACHE_HOME="$OBS_HOME/.cache" "${cmd[@]}")
  fi

  cmd=(xvfb-run -a -s "-screen 0 1920x1080x24 -ac +extension GLX +render -noreset" "${cmd[@]}")

  echo "Running OBS dry-run load to validate scene collection (logs: $run_log)"
  local status
  set +e
  if command -v timeout >/dev/null 2>&1; then
    timeout 45s "${cmd[@]}" >"$run_log" 2>&1
    status=$?
  else
    "${cmd[@]}" >"$run_log" 2>&1
    status=$?
  fi
  set -e

  if [[ $status -eq 0 ]]; then
    log_pass "OBS dry-run load succeeded (see $run_log for details)"
    return
  fi

  log_fail "OBS dry-run load failed (exit $status). Review $run_log for loader errors."
  local run_log_tail=""
  if [[ -s "$run_log" ]]; then
    run_log_tail=$(tail -n 40 "$run_log" 2>/dev/null || true)
  fi

  local note="OBS dry-run load failed (exit $status). Check $run_log for parser/loader errors. Ensure plugins referenced in ${SCENE_FILE} are installed and the collection/profile names match (${COLLECTION_NAME}/${COLLECTION_NAME})."
  if [[ -n "$run_log_tail" ]]; then
    note+=$'\n--- Tail of dry-run log ---\n'"${run_log_tail}"$'\n------------------------'
  fi

  append_obs_log_note "$note"

  if find_latest_obs_log; then
    print_latest_obs_log_tail
    append_obs_log_note "If OBS cannot find plugins (browser/vlc), install obs-browser or vlc-video packages and rerun configure_obs.sh."
  fi
}

check_systemd_unit() {
  local unit="$1"
  if ! command -v systemctl >/dev/null 2>&1; then
    log_warn "systemctl not available; skipping $unit checks"
    return
  fi

  if ! systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q "$unit"; then
    log_fail "$unit not registered (run scripts/services/setup_services.sh)"
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

  describe_unit_result "$unit"

  if [[ "$unit" == "$OBS_SERVICE" ]]; then
    check_obs_unit_alignment
    stream_journal_snippet "$unit"
    if [[ "$status" != "active" ]]; then
      print_latest_obs_log_tail
    fi
  fi
}

describe_unit_result() {
  local unit="$1"
  local info result exec_code exec_status active_state sub_state status_text active_enter inactive_enter active_exit inactive_exit

  info=$(systemctl show "$unit" -p Result -p ExecMainCode -p ExecMainStatus -p ActiveState -p SubState -p StatusText -p ActiveEnterTimestamp -p InactiveEnterTimestamp -p ActiveExitTimestamp -p InactiveExitTimestamp 2>/dev/null || true)
  result=$(echo "$info" | awk -F= '/^Result=/ {print $2}')
  exec_code=$(echo "$info" | awk -F= '/^ExecMainCode=/ {print $2}')
  exec_status=$(echo "$info" | awk -F= '/^ExecMainStatus=/ {print $2}')
  active_state=$(echo "$info" | awk -F= '/^ActiveState=/ {print $2}')
  sub_state=$(echo "$info" | awk -F= '/^SubState=/ {print $2}')
  status_text=$(echo "$info" | awk -F= '/^StatusText=/ {print $2}')
  active_enter=$(echo "$info" | awk -F= '/^ActiveEnterTimestamp=/ {print $2}')
  inactive_enter=$(echo "$info" | awk -F= '/^InactiveEnterTimestamp=/ {print $2}')
  active_exit=$(echo "$info" | awk -F= '/^ActiveExitTimestamp=/ {print $2}')
  inactive_exit=$(echo "$info" | awk -F= '/^InactiveExitTimestamp=/ {print $2}')

  if [[ -z "$result" && -z "$exec_code" && -z "$exec_status" && -z "$active_state" ]]; then
    log_warn "$unit status details unavailable (systemctl show returned no data)"
    return
  fi

  local state_summary="state=${active_state:-n/a}/${sub_state:-n/a}"
  if [[ "$result" == "success" || "$exec_status" == "0" ]]; then
    log_pass "$unit last result=${result:-n/a} exit=${exec_code:-n/a}/${exec_status:-n/a} (${state_summary})"
  else
    log_warn "$unit last result=${result:-n/a} exit=${exec_code:-n/a}/${exec_status:-n/a} (${state_summary}, recent failure)"
    if [[ -n "$status_text" && "$status_text" != "-" ]]; then
      log_warn "$unit status text: $status_text"
    fi

    local timeline=()
    [[ -n "$inactive_enter" && "$inactive_enter" != "-" ]] && timeline+=("inactive since $inactive_enter")
    [[ -n "$active_enter" && "$active_enter" != "-" ]] && timeline+=("last active at $active_enter")
    [[ -n "$active_exit" && "$active_exit" != "-" ]] && timeline+=("last exit at $active_exit")
    [[ -n "$inactive_exit" && "$inactive_exit" != "-" ]] && timeline+=("last restart from inactive at $inactive_exit")
    if [[ ${#timeline[@]} -gt 0 ]]; then
      log_warn "$unit transition history: ${timeline[*]}"
    fi
  fi
}

check_obs_unit_alignment() {
  local info user workdir envs home_var xdg_cfg_var xdg_cache_var
  info=$(systemctl show "$OBS_SERVICE" -p User -p WorkingDirectory -p Environment 2>/dev/null || true)
  user=$(echo "$info" | awk -F= '/^User=/ {print $2}')
  workdir=$(echo "$info" | awk -F= '/^WorkingDirectory=/ {print $2}')
  envs=$(echo "$info" | awk -F= '/^Environment=/ {print $2}')

  home_var=$(tr ' ' '\n' <<<"$envs" | awk -F= '/^HOME=/ {print $2; exit}')
  xdg_cfg_var=$(tr ' ' '\n' <<<"$envs" | awk -F= '/^XDG_CONFIG_HOME=/ {print $2; exit}')
  xdg_cache_var=$(tr ' ' '\n' <<<"$envs" | awk -F= '/^XDG_CACHE_HOME=/ {print $2; exit}')

  if [[ -n "$user" && "$user" != "$STREAM_USER" ]]; then
    log_warn "obs-headless.service runs as user '$user' (expected '${STREAM_USER}')"
  else
    log_pass "obs-headless.service runs as expected user '${STREAM_USER}'"
  fi

  if [[ -n "$home_var" && "$home_var" != "$OBS_HOME" ]]; then
    log_warn "obs-headless.service HOME=$home_var (expected $OBS_HOME); logs/config will be under that path"
  else
    log_pass "obs-headless.service HOME points to $OBS_HOME"
  fi

  if [[ -n "$xdg_cfg_var" && "$xdg_cfg_var" != "$OBS_HOME/.config" ]]; then
    log_warn "obs-headless.service XDG_CONFIG_HOME=$xdg_cfg_var (expected $OBS_HOME/.config)"
  fi

  if [[ -n "$xdg_cache_var" && "$xdg_cache_var" != "$OBS_HOME/.cache" ]]; then
    log_warn "obs-headless.service XDG_CACHE_HOME=$xdg_cache_var (expected $OBS_HOME/.cache)"
  fi

  if [[ -n "$workdir" && "$workdir" != "$OBS_HOME" ]]; then
    log_warn "obs-headless.service WorkingDirectory=$workdir (expected $OBS_HOME)"
  fi
}

stream_journal_snippet() {
  local unit="$1"
  if ! command -v journalctl >/dev/null 2>&1; then
    return
  fi

  echo "--- Last 20 journal entries for ${unit} ---"
  journalctl -u "$unit" -n 20 --no-pager 2>/dev/null || true
  echo "------------------------------------------"
}

find_latest_obs_log() {
  local log_dir=""
  local candidates=(
    "$OBS_HOME/.config/obs-studio/logs"
    "$OBS_HOME/logs/obs-studio"
    "$OBS_HOME/logs"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate" ]]; then
      log_dir="$candidate"
      break
    fi
  done

  if [[ ! -d "$log_dir" ]]; then
    log_warn "OBS log directory not found (checked: ${candidates[*]})"
    return 1
  fi

  local latest
  latest=$(find "$log_dir" -maxdepth 1 -type f -name "*.txt" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)

  if [[ -z "$latest" ]]; then
    log_warn "No OBS log files found in $log_dir"
    return 1
  fi

  LATEST_OBS_LOG="$latest"
  return 0
}

print_latest_obs_log_tail() {
  if [[ -z "$LATEST_OBS_LOG" ]]; then
    find_latest_obs_log || return
  fi

  echo "--- Tail of latest OBS log (${LATEST_OBS_LOG}) ---"
  tail -n 40 "$LATEST_OBS_LOG" 2>/dev/null || true
  echo "-----------------------------------------------"
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
  check_command jq "jq"
  check_command npm "npm"
  check_command npx "npx"
  check_node_version
  check_user
  check_user_permissions
  check_app
  check_env_file
  check_obs_installation
  describe_permissions
  check_obs_config
  check_builtin_transitions
  check_scene_plugins
  check_browser_scene_target
  run_obs_dry_run
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

  if [[ ${#obs_log_notes[@]} -gt 0 ]]; then
    echo
    echo "=== OBS Log Excerpts ==="
    for note in "${obs_log_notes[@]}"; do
      printf "%s\n" "$note"
    done
  fi

  if [[ ${#failures[@]} -gt 0 ]]; then
    echo
    echo "Failures detected. Review the FAIL items above for next steps."
    exit 1
  fi
}

main "$@"
