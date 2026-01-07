# YouTube Stream Headless Stack

This repository provides install and runtime scripts to boot a headless Ubuntu server that:

- Spins up a sample React web app (port `3000`).
- Installs OBS Studio and configures it to stream the web page to YouTube via CLI.
- Runs continuously with auto-restart via `systemd` or the container supervisor.

## Repository layout

The project is script-driven. Key entry points live under `scripts/` (see [`scripts/README.md`](scripts/README.md) for the full catalog):

- **Provisioning (`scripts/install/`):**
  - `install_dependencies.sh` — installs Node.js (20.x), OBS Studio, Xvfb, FFmpeg, and a dedicated `streamer` service user.
  - `bootstrap_react_app.sh` — creates a sample React app under `/opt/youtube-stream/webapp` and prepares the UI.
- **Configuration (`scripts/config/`):**
  - `configure_obs.sh` — writes an OBS profile/scene that captures `APP_URL`, sets your RTMP key, and installs the preflight guard; also seeds systemd units.
  - `run_default_config.sh` — generates a throwaway OBS config with a placeholder stream key for local testing.
- **Services (`scripts/services/`):**
  - `setup_services.sh` — builds the React app and creates/enables systemd units (`react-web.service`, `obs-headless.service`).
  - `prepare_streamer.sh` / `streamer_clone_repo.sh` — manage the service user and repo checkout.
- **Operations (`scripts/ops/`):**
  - `container-entrypoint.sh` — Docker entrypoint that builds/serves the React app and launches OBS inside Xvfb for containerized runs.
  - `run-services.sh` — lightweight supervisor for non-systemd environments; starts the web app (dev or build) plus OBS and exits if either dies.
  - `diagnostics.sh` — sanity checks deps, OBS config, and service health.
  - `fix_permissions.sh` — repairs ownership/modes for generated assets.
- **Cleanup (`scripts/cleanup/`):**
  - `reset_environment.sh` — tears down services, packages, and generated assets to enable a clean reinstall.
  - `backup.sh` — archives key paths and configs for recovery.

The Dockerfile copies the repo into `/workspace/YouTube-Stream`, runs the provisioning scripts during build, and uses `tini` plus `scripts/ops/container-entrypoint.sh` at runtime.

## Prerequisites
- Ubuntu 20.04/22.04+ with sudo/root access.
- A YouTube RTMP stream key.

## Scripts overview
Most users will run the main provisioning flow:
- `scripts/install/install_dependencies.sh` — installs Node.js (20.x), OBS Studio, Xvfb, FFmpeg, and a dedicated `streamer` service user.
- `scripts/install/bootstrap_react_app.sh` — creates a sample React app under `/opt/youtube-stream/webapp` and prepares the UI.
- `scripts/config/configure_obs.sh` — writes an OBS profile/scene that captures `http://127.0.0.1:3000` via a browser source and uses your RTMP key.
- `scripts/services/setup_services.sh` — creates/enables `systemd` services for the React app and headless OBS streaming.

For operations, maintenance, and cleanup tasks, see the full catalog in [`scripts/README.md`](scripts/README.md).

## Quick start
```bash
# 1) Install deps (run as root or with sudo)
sudo bash scripts/install/install_dependencies.sh

# 2) Bootstrap the sample React app
sudo STREAM_USER=streamer APP_DIR=/opt/youtube-stream/webapp bash scripts/install/bootstrap_react_app.sh

# 3) Configure OBS with your stream key
sudo -E STREAM_USER=streamer OBS_HOME=/var/lib/streamer YOUTUBE_STREAM_KEY="YOUR_YT_STREAM_KEY" \
  bash scripts/config/configure_obs.sh

# 4) Create services (and populate /etc/youtube-stream/env for secrets)
sudo STREAM_USER=streamer APP_DIR=/opt/youtube-stream/webapp bash scripts/services/setup_services.sh

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
- **Create/repair the service user** — `sudo STREAM_USER=streamer OBS_HOME=/var/lib/streamer PASSWORD="new-strong-pass" bash scripts/services/prepare_streamer.sh` recreates the `streamer` account (or fixes its home/permissions) and sets the password. Override `PASSWORD` so the default value in the script is never used in production.
- **Clone this repo as the service user** — `sudo STREAM_USER=streamer bash scripts/services/streamer_clone_repo.sh` pulls the repo into `/var/lib/streamer/YouTube-Stream` so automated runs stay under the same UID/GID that owns OBS configs.
- **Tear everything down** — `sudo STREAM_USER=streamer APP_DIR=/opt/youtube-stream/webapp bash scripts/cleanup/reset_environment.sh` stops the systemd units, kills related processes, purges Node/OBS packages, and removes app/config paths so you can reinstall from scratch.
- **Test with a placeholder stream key** — `sudo STREAM_USER=streamer bash scripts/config/run_default_config.sh` calls `configure_obs.sh` with a sample key. Only use this for local validation and replace with a real key before going live.

### Customization
- Override defaults with environment variables when running the scripts:
  - `APP_DIR` (default `/opt/youtube-stream/webapp`)
  - `STREAM_USER` (default `streamer`)
  - `OBS_HOME` (default `/var/lib/<STREAM_USER>`, `/var/lib/streamer` by default)
  - `APP_URL` (default `http://127.0.0.1:3000` in `configure_obs.sh`)
  - `VIDEO_BITRATE` and `AUDIO_BITRATE` (defaults `1000`/`128` kbps) for lighter baseline output. `configure_obs.sh` caps video bitrate to `RECOMMENDED_VIDEO_BITRATE` (default `1000` kbps), warns if your values fall outside YouTube’s guidance for the chosen resolution, and checks that audio meets the recommended minimum.
  - `RECOMMENDED_VIDEO_BITRATE` (default `1000` kbps) to control the maximum video bitrate enforced by `configure_obs.sh`.
  - Force software OpenGL when headless/virtualized GPUs are unstable: `LIBGL_ALWAYS_SOFTWARE=1` (default) keeps OBS on software rendering to avoid swapchain failures.
- Browser source hardware acceleration:
  - Default **disabled** for stability in headless/virtualized environments where GPU drivers or OpenGL support may be limited.
  - Enable if you have a stable GPU/driver stack and want lower CPU usage: `ENABLE_BROWSER_SOURCE_HW_ACCEL=1 bash scripts/config/configure_obs.sh` or add `--enable-browser-hw-accel`.
  - Explicitly disable (default): `ENABLE_BROWSER_SOURCE_HW_ACCEL=0 bash scripts/config/configure_obs.sh` or add `--disable-browser-hw-accel`.
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
sudo bash scripts/ops/fix_permissions.sh
```
to normalize ownership/modes.

### Lightweight webapp guidance
The sample React app generated by `bootstrap_react_app.sh` is tuned for headless capture (no timers, animations, or background polling). If you customize the UI, keep it lightweight to protect FPS and CPU usage in Xvfb/OBS:

- Favor static text/images over loops, videos, or canvas/WebGL effects.
- Prefer simple CSS (avoid large blurs/shadows and complex gradients).
- Skip polling with `setInterval`/`setTimeout`; trigger updates when data changes or throttle to multi-minute intervals.
- Avoid auto-playing media and remote web fonts; system fonts and local assets keep startup faster.
- Use CSS for layout instead of JavaScript-driven measurement to minimize reflows.

### Manual runtime (without systemd)
```bash
# Start React app
HOST=127.0.0.1 PORT=3000 BROWSER=none CI=true npm start --prefix /opt/youtube-stream/webapp

# In another shell, stream with OBS in Xvfb
YOUTUBE_STREAM_KEY="YOUR_KEY" APP_URL=http://127.0.0.1:3000 \
  xvfb-run -a obs --collection YouTubeHeadless --profile YouTubeHeadless --scene WebScene --startstreaming \
  --minimize-to-tray --disable-updater --disable-shutdown-check
```

### Docker (all-in-one) workflow
The Docker image installs dependencies, builds the sample React app, provisions a virtual display, and launches OBS to capture the page.

1. **Build the image (from repo root):**
   ```bash
   docker build -t youtube-stream .
   ```
2. **Run the container with your stream key (required) and port mapping:**
   ```bash
   docker run --rm -it \
     -e YOUTUBE_STREAM_KEY="YOUR_YT_STREAM_KEY" \
     -e APP_URL="http://127.0.0.1:3000" \
     -p 3000:3000 \
     youtube-stream
   ```
   - The React app is served on port `3000` inside the container and forwarded to the host.
   - OBS starts in Xvfb and immediately streams the page at `APP_URL` to YouTube using `YOUTUBE_STREAM_KEY`.
3. **Stop the container:** `Ctrl+C` or `docker stop <container>` (tini forwards signals so OBS shuts down cleanly).

### Container runtime variables
When running the container image, these environment variables tune runtime behavior:

- `YOUTUBE_STREAM_KEY` (**required**) – RTMP key passed to OBS.
- `APP_URL` (default `http://127.0.0.1:3000`) – URL loaded by the OBS browser source.
- `VIDEO_BASE_WIDTH` / `VIDEO_BASE_HEIGHT` (defaults `1024`/`576`) – Xvfb/OBS resolution for the virtual display.
- `ENABLE_BROWSER_SOURCE_HW_ACCEL` (default `0`) – Enable (`1`) or disable (`0`) OBS browser source hardware acceleration.
- `LIBGL_ALWAYS_SOFTWARE` (default `1`) – Forces software rendering when GPU acceleration is unreliable.
- `STREAM_USER` / `OBS_HOME` (defaults `streamer`/`/var/lib/streamer`) – Service user and home used for OBS configs and logs.
- `APP_DIR` (default `/opt/youtube-stream/webapp`) – React app path used by the entrypoint.

The container exposes port `3000` and uses `tini` as PID 1 to forward signals to the React server and headless OBS process.

### Troubleshooting
If `obs-headless.service` is running under a different user than `streamer`, OBS will place its config and logs under that user’s home (for example, `/var/lib/<user>/.config/obs-studio` and `/var/lib/<user>/logs/obs-studio`). Rerun `scripts/services/setup_services.sh` with `STREAM_USER=streamer OBS_HOME=/var/lib/streamer` to reset the unit to the default user/path before restarting the service.

Run the diagnostics script to verify dependencies, config, and service health:
```bash
sudo bash scripts/ops/diagnostics.sh \
  --skip-systemd    # (optional) skip systemd checks in containers
  --skip-network    # (optional) skip HTTP probe to APP_URL
  --check-build     # (optional) run npm run build --if-present inside the app
```

Common OBS log signatures and fixes:
- `Encoder ID 'h264_nvenc' not found`: the profile is pointing at a hardware encoder that OBS cannot load. Rerun `scripts/config/configure_obs.sh` to regenerate the profile so it falls back to x264, or install a working NVIDIA driver/OBS build that exposes NVENC.
- `Swapchain window creation failed` / `gl_platform_init_swapchain failed`: OBS could not initialize GL in the virtual display. Ensure you launch via `xvfb-run` with a 24-bit screen depth (the scripts already use `-screen 0 1024x576x24 +extension GLX +render -noreset`) and keep `LIBGL_ALWAYS_SOFTWARE=1` to force software rendering when GPU/driver support is limited.

To avoid systemd restart loops, run diagnostics **before** starting the units. For example, in a container or fresh install:
```bash
sudo STREAM_USER=streamer APP_DIR=/opt/youtube-stream/webapp \
  bash scripts/ops/diagnostics.sh --skip-systemd --skip-network --check-build
```
This surfaces missing stream keys, OBS profiles, or build failures without repeatedly restarting `obs-headless.service`.

### Notes
- OBS relies on Xvfb for a virtual display; adjust resolution/FPS inside `scripts/config/configure_obs.sh` if desired.
- The sample React page is a placeholder—you can modify `/opt/youtube-stream/webapp/src` and redeploy.
- Future enhancements (audio sources, overlays, etc.) can be added by extending the generated OBS profile/scene JSON.
