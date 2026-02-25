#!/usr/bin/env bash
set -euo pipefail

LOGIN_SCRIPT="${LOGIN_SCRIPT:-/app/login.mjs}"
FIXTURE_PORT="${LOGIN_FIXTURE_PORT:-4173}"
FIXTURE_HOST="${LOGIN_FIXTURE_HOST:-127.0.0.1}"
CHROME_BIN="${CHROME_BIN:-google-chrome}"
CHROME_DEBUG_PORT="${CHROME_DEBUG_PORT:-9222}"
LOGIN_TIMEOUT_MS="${LOGIN_TIMEOUT_MS:-8000}"
ARTIFACT_DIR="${LOGIN_ARTIFACT_DIR:-/tmp/login-debug}"
LOGIN_DEBUG="${LOGIN_DEBUG:-0}"

if [[ ! -f "$LOGIN_SCRIPT" ]]; then
  echo "[harness] LOGIN_SCRIPT not found at $LOGIN_SCRIPT"
  echo "[harness] Tip: for local repo runs use LOGIN_SCRIPT=./login.mjs"
  exit 1
fi

if ! command -v "$CHROME_BIN" >/dev/null 2>&1; then
  echo "[harness] CHROME_BIN ($CHROME_BIN) is not available in PATH"
  exit 1
fi

FIXTURE_LOG="$(mktemp -t login-fixture.XXXX.log)"
node fixtures/login-harness/server.mjs >"$FIXTURE_LOG" 2>&1 &
FIXTURE_PID=$!

cleanup() {
  kill "$FIXTURE_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_fixture() {
  for _ in {1..30}; do
    if curl -fsS "http://${FIXTURE_HOST}:${FIXTURE_PORT}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done

  echo "[harness] fixture server failed to start"
  cat "$FIXTURE_LOG"
  exit 1
}

wait_for_fixture

run_case() {
  local name="$1"
  local route="$2"
  local expected="$3"
  local user_selector="${4:-}"

  echo "[harness] Running case: $name"

  local profile_dir
  profile_dir="$(mktemp -d -t login-harness-profile.XXXXXX)"

  "$CHROME_BIN" \
    --headless=new \
    --no-sandbox \
    --disable-dev-shm-usage \
    --remote-debugging-address=127.0.0.1 \
    --remote-debugging-port="$CHROME_DEBUG_PORT" \
    --user-data-dir="$profile_dir" \
    about:blank >/tmp/login-harness-chrome.log 2>&1 &
  local chrome_pid=$!

  local rc=0
  rm -rf "$ARTIFACT_DIR"

  set +e
  WEB_URL="http://${FIXTURE_HOST}:${FIXTURE_PORT}${route}" \
  LOGIN_USER="demo-user" \
  LOGIN_PASS="demo-pass" \
  CHROME_DEBUG_PORT="$CHROME_DEBUG_PORT" \
  LOGIN_TIMEOUT_MS="$LOGIN_TIMEOUT_MS" \
  LOGIN_DEBUG="$LOGIN_DEBUG" \
  LOGIN_USER_SELECTOR="${user_selector:-input[placeholder=\"User ID\"], input[autocomplete=\"username\"]}" \
  node "$LOGIN_SCRIPT"
  rc=$?
  set -e

  kill "$chrome_pid" >/dev/null 2>&1 || true
  rm -rf "$profile_dir"

  if [[ "$expected" == "success" ]]; then
    if [[ $rc -ne 0 ]]; then
      echo "[harness] ❌ expected success but command failed: $name"
      return 1
    fi
    echo "[harness] ✅ success: $name"
    return 0
  fi

  if [[ $rc -eq 0 ]]; then
    echo "[harness] ❌ expected failure but command succeeded: $name"
    return 1
  fi

  if [[ ! -f "$ARTIFACT_DIR/failure.png" || ! -f "$ARTIFACT_DIR/failure.html" ]]; then
    echo "[harness] ❌ failure artifacts missing for case: $name"
    return 1
  fi

  echo "[harness] ✅ failure observed with artifacts: $name"
}

run_case "successful login in main DOM" "/main" "success"
run_case "delayed render of fields" "/delayed" "success"
run_case "iframe login form" "/iframe" "success"
run_case "wrong selector failure" "/main" "failure" "#user-does-not-exist"
run_case "cookie banner required" "/cookie" "success"

echo "[harness] All login fixture scenarios passed."
