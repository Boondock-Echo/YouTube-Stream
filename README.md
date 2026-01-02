# YouTube Stream Headless Stack

This repository provides install and runtime scripts to boot a headless Ubuntu server that:

- Spins up a sample React web app (port `3000`).
- Installs OBS Studio and configures it to stream the web page to YouTube via CLI.
- Runs continuously with auto-restart via `systemd`.

## Prerequisites
- Ubuntu 20.04/22.04+ with sudo/root access.
- A YouTube RTMP stream key.

## Scripts overview
- `scripts/install_dependencies.sh` — installs Node.js (20.x), OBS Studio, Xvfb, FFmpeg, and a dedicated `streamer` service user.
- `scripts/bootstrap_react_app.sh` — creates a sample React app under `/opt/youtube-stream/webapp` and prepares the UI.
- `scripts/configure_obs.sh` — writes an OBS profile/scene that captures `http://localhost:3000` via a browser source and uses your RTMP key.
- `scripts/setup_services.sh` — creates/enables `systemd` services for the React app and headless OBS streaming.

## Quick start
```bash
# 1) Install deps (run as root or with sudo)
sudo bash scripts/install_dependencies.sh

# 2) Bootstrap the sample React app
sudo STREAM_USER=streamer APP_DIR=/opt/youtube-stream/webapp bash scripts/bootstrap_react_app.sh

# 3) Configure OBS with your stream key
sudo -E STREAM_USER=streamer OBS_HOME=/var/lib/streamer YOUTUBE_STREAM_KEY="YOUR_YT_STREAM_KEY" \
  bash scripts/configure_obs.sh

# 4) Create services (and populate /etc/youtube-stream/env for secrets)
sudo STREAM_USER=streamer APP_DIR=/opt/youtube-stream/webapp bash scripts/setup_services.sh

# 5) Start services
sudo systemctl start react-web.service
sudo systemctl start obs-headless.service
```

### Updating the stream key
Edit `/etc/youtube-stream/env` and set `YOUTUBE_STREAM_KEY=your_key`, then run:
```bash
sudo systemctl restart obs-headless.service
```

### Customization
- Override defaults with environment variables when running the scripts:
  - `APP_DIR` (default `/opt/youtube-stream/webapp`)
  - `STREAM_USER` (default `streamer`)
  - `OBS_HOME` (default `/var/lib/<STREAM_USER>`)
  - `APP_URL` (default `http://localhost:3000` in `configure_obs.sh`)
- The systemd services restart on failure and at boot to maintain 24/7 uptime.

### Manual runtime (without systemd)
```bash
# Start React app
HOST=0.0.0.0 PORT=3000 BROWSER=none CI=true npm start --prefix /opt/youtube-stream/webapp

# In another shell, stream with OBS in Xvfb
YOUTUBE_STREAM_KEY="YOUR_KEY" APP_URL=http://localhost:3000 \
  xvfb-run -a obs --collection YouTubeHeadless --profile YouTubeHeadless --scene WebScene --startstreaming \
  --minimize-to-tray --disable-updater --disable-shutdown-check
```

### Notes
- OBS relies on Xvfb for a virtual display; adjust resolution/FPS inside `scripts/configure_obs.sh` if desired.
- The sample React page is a placeholder—you can modify `/opt/youtube-stream/webapp/src` and redeploy.
- Future enhancements (audio sources, overlays, etc.) can be added by extending the generated OBS profile/scene JSON.
