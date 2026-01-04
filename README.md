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

### Helper scripts
- **Create/repair the service user** — `sudo STREAM_USER=streamer OBS_HOME=/var/lib/streamer PASSWORD="new-strong-pass" bash scripts/prepare_streamer.sh` recreates the `streamer` account (or fixes its home/permissions) and sets the password. Override `PASSWORD` so the default value in the script is never used in production.
- **Clone this repo as the service user** — `sudo STREAM_USER=streamer bash scripts/streamer_clone_repo.sh` pulls the repo into `/var/lib/streamer/YouTube-Stream` so automated runs stay under the same UID/GID that owns OBS configs.
- **Tear everything down** — `sudo STREAM_USER=streamer APP_DIR=/opt/youtube-stream/webapp bash scripts/reset_environment.sh` stops the systemd units, kills related processes, purges Node/OBS packages, and removes app/config paths so you can reinstall from scratch.
- **Test with a placeholder stream key** — `sudo STREAM_USER=streamer bash scripts/run_default_config.sh` calls `configure_obs.sh` with a sample key. Only use this for local validation and replace with a real key before going live.

### Customization
- Override defaults with environment variables when running the scripts:
  - `APP_DIR` (default `/opt/youtube-stream/webapp`)
  - `STREAM_USER` (default `streamer`)
  - `OBS_HOME` (default `/var/lib/<STREAM_USER>`, `/var/lib/streamer` by default)
  - `APP_URL` (default `http://localhost:3000` in `configure_obs.sh`)
- Browser source hardware acceleration:
  - Default **disabled** for stability in headless/virtualized environments where GPU drivers or OpenGL support may be limited.
  - Enable if you have a stable GPU/driver stack and want lower CPU usage: `ENABLE_BROWSER_SOURCE_HW_ACCEL=1 bash scripts/configure_obs.sh` or add `--enable-browser-hw-accel`.
  - Explicitly disable (default): `ENABLE_BROWSER_SOURCE_HW_ACCEL=0 bash scripts/configure_obs.sh` or add `--disable-browser-hw-accel`.
- The systemd services restart on failure and at boot to maintain 24/7 uptime.

### Ownership and permissions
The install expects the following owners and modes:

| Path | Owner:Group | Mode | Purpose |
| --- | --- | --- | --- |
| `/opt/youtube-stream/webapp` | `streamer:streamer` | `755` | React app tree |
| `/var/lib/streamer` and subdirs | `streamer:streamer` | `755` | OBS home/config/cache/logs |
| `/etc/youtube-stream` | `root:root` | `750` | Env directory |
| `/etc/youtube-stream/env` | `root:root` | `640` | Stream key env file |
| `/etc/systemd/system/react-web.service` | `root:root` | `644` | React systemd unit |
| `/etc/systemd/system/obs-headless.service` | `root:root` | `644` | OBS systemd unit |

If these drift (for example after copying files between hosts), run:
```bash
sudo bash scripts/fix_permissions.sh
```
to normalize ownership/modes.

### Manual runtime (without systemd)
```bash
# Start React app
HOST=0.0.0.0 PORT=3000 BROWSER=none CI=true npm start --prefix /opt/youtube-stream/webapp

# In another shell, stream with OBS in Xvfb
YOUTUBE_STREAM_KEY="YOUR_KEY" APP_URL=http://localhost:3000 \
  xvfb-run -a obs --collection YouTubeHeadless --profile YouTubeHeadless --scene WebScene --startstreaming \
  --minimize-to-tray --disable-updater --disable-shutdown-check
```

### Troubleshooting
If `obs-headless.service` is running under a different user than `streamer`, OBS will place its config and logs under that user’s home (for example, `/var/lib/<user>/.config/obs-studio` and `/var/lib/<user>/logs/obs-studio`). Rerun `scripts/setup_services.sh` with `STREAM_USER=streamer OBS_HOME=/var/lib/streamer` to reset the unit to the default user/path before restarting the service.

Run the diagnostics script to verify dependencies, config, and service health:
```bash
sudo bash scripts/diagnostics.sh \
  --skip-systemd    # (optional) skip systemd checks in containers
  --skip-network    # (optional) skip HTTP probe to APP_URL
  --check-build     # (optional) run npm run build --if-present inside the app
```

### Notes
- OBS relies on Xvfb for a virtual display; adjust resolution/FPS inside `scripts/configure_obs.sh` if desired.
- The sample React page is a placeholder—you can modify `/opt/youtube-stream/webapp/src` and redeploy.
- Future enhancements (audio sources, overlays, etc.) can be added by extending the generated OBS profile/scene JSON.
