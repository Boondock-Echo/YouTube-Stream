#!/usr/bin/env bash
set -euo pipefail

# Bootstraps a minimal React app served on port 3000.

APP_DIR=${APP_DIR:-/opt/youtube-stream/webapp}
STREAM_USER=${STREAM_USER:-streamer}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo or as root so it can manage ${APP_DIR} ownership." >&2
  exit 1
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "npx is required (install Node.js first)." >&2
  exit 1
fi

if [ ! -d "$APP_DIR" ]; then
  echo "Creating app directory at $APP_DIR"
  mkdir -p "$APP_DIR"
fi

# Create the React app if it doesn't already exist
if [ ! -f "$APP_DIR/package.json" ]; then
  echo "Initializing React app in $APP_DIR"
  sudo -u "$STREAM_USER" npx create-react-app "$APP_DIR"
fi

echo "Updating sample React content."
cat <<'APP' | sudo -u "$STREAM_USER" tee "$APP_DIR/src/App.js" >/dev/null
import './App.css';

function App() {
  return (
    <main className="App">
      <section className="Card">
        <p className="Eyebrow">Headless YouTube Stream</p>
        <h1>Stable preview for OBS</h1>
        <p className="Lead">
          This page is intentionally lightweight so Xvfb and OBS can capture it with minimal CPU/GPU load.
          There are no animations, timers, or background polling.
        </p>
        <ul className="Tips">
          <li>Use static text and images instead of video loops or canvas effects.</li>
          <li>Keep CSS simple (no heavy shadows, blurs, or gradients).</li>
          <li>Avoid setInterval/setTimeout polling; push updates only when the data changes.</li>
          <li>Disable auto-playing media and large fonts pulled from remote CDNs.</li>
          <li>Prefer CSS over JavaScript-driven layout to reduce reflows.</li>
        </ul>
        <p className="Footnote">
          Need dynamic data? Throttle refreshes (e.g., once every few minutes) and cache responses.
        </p>
      </section>
    </main>
  );
}

export default App;
APP

cat <<'CSS' | sudo -u "$STREAM_USER" tee "$APP_DIR/src/App.css" >/dev/null
:root {
  color-scheme: dark;
}

*,
*::before,
*::after {
  box-sizing: border-box;
}

body {
  margin: 0;
  background: #0b1224;
  color: #e5e7eb;
  font-family: 'Inter', system-ui, -apple-system, sans-serif;
  line-height: 1.5;
}

.App {
  min-height: 100vh;
  display: grid;
  place-items: center;
  padding: 1.5rem;
}

.Card {
  width: min(720px, 100%);
  background: #0f172a;
  border: 1px solid #1f2937;
  border-radius: 16px;
  padding: 1.75rem;
  display: grid;
  gap: 0.75rem;
  box-shadow: 0 12px 40px rgba(0, 0, 0, 0.25);
}

.Eyebrow {
  text-transform: uppercase;
  letter-spacing: 0.08em;
  font-size: 0.85rem;
  color: #9ca3af;
  margin: 0;
}

h1 {
  margin: 0;
  font-size: clamp(1.75rem, 3vw, 2.25rem);
  color: #e5e7eb;
}

.Lead {
  margin: 0;
  color: #cbd5e1;
  font-size: 1rem;
}

.Tips {
  list-style: disc;
  padding-left: 1.25rem;
  margin: 0.5rem 0 0;
  display: grid;
  gap: 0.35rem;
}

.Tips li {
  color: #d1d5db;
}

.Footnote {
  margin: 0;
  color: #9ca3af;
  font-size: 0.95rem;
  border-top: 1px solid #1f2937;
  padding-top: 0.75rem;
}

@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0s !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0s !important;
  }
}
CSS

sudo -u "$STREAM_USER" npm install --prefix "$APP_DIR"

echo "React app ready at $APP_DIR. Use scripts/setup_services.sh to launch via systemd."
