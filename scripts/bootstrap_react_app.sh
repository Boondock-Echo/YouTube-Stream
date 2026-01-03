#!/usr/bin/env bash
set -euo pipefail

# Bootstraps a minimal React app served on port 3000.

APP_DIR=${APP_DIR:-/opt/youtube-stream/webapp}
STREAM_USER=${STREAM_USER:-mjhughes}

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
    <div className="App">
      <header className="App-header">
        <p>Headless YouTube Stream POC</p>
        <p>React app is live on port 3000.</p>
        <p>OBS will capture this page for streaming.</p>
      </header>
    </div>
  );
}

export default App;
APP

cat <<'CSS' | sudo -u "$STREAM_USER" tee "$APP_DIR/src/App.css" >/dev/null
.App {
  text-align: center;
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #0f172a, #111827);
  color: #e5e7eb;
  font-family: 'Inter', system-ui, -apple-system, sans-serif;
}

.App-header {
  display: grid;
  gap: 0.5rem;
  font-size: 1.25rem;
}

.App a {
  color: #38bdf8;
}
CSS

sudo -u "$STREAM_USER" npm install --prefix "$APP_DIR"

echo "React app ready at $APP_DIR. Use scripts/setup_services.sh to launch via systemd."
