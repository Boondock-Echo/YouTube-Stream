# web2yt — Headless Webpage → YouTube Live (Docker)

This project runs a **virtual monitor** (Xvfb), launches **Chromium in kiosk mode** on that virtual display,
captures **video + webpage audio**, and streams it to **YouTube Live** via **RTMPS**.

## What’s in this repo
- `docker-compose.yml` — service definition and environment variables
- `Dockerfile` — container build instructions
- `start.sh` — starts Xvfb + PulseAudio + Chromium + FFmpeg
- `login.mjs` — optional Puppeteer automation for username/password login

## Prerequisites
- Docker Engine
- Docker Compose plugin (`docker compose`)
- A YouTube Live stream key

## Install Docker
If Docker is not installed, follow the official instructions for your OS:
- Docker Engine: https://docs.docker.com/engine/install/
- Docker Compose plugin: https://docs.docker.com/compose/install/

### Ubuntu install checklist (22.04/24.04/25.04/25.10)
Use the official Docker APT repository to install both Docker Engine and the Compose plugin.

#### Prerequisites
- Supported 64-bit Ubuntu versions: **Jammy 22.04 (LTS)**, **Noble 24.04 (LTS)**, **Plucky 25.04**, **Questing 25.10**
- Supported architectures: `x86_64 (amd64)`, `armhf`, `arm64`, `s390x`, `ppc64le`
- Firewall note: Docker bypasses `ufw`/`firewalld` for published ports and is only compatible with
  `iptables-nft` or `iptables-legacy`. Use the **DOCKER-USER** chain for custom rules.

#### Uninstall old versions (if present)
```bash
sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc | cut -f1)
```
This may report that none are installed, which is fine. Existing Docker data in `/var/lib/docker/` is not removed.

#### Install Docker Engine + Compose plugin
1) Add Docker’s official GPG key:
```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

2) Add the Docker APT repository:
```bash
sudo tee /etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
```

3) Install Docker packages:
```bash
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Optional: install a specific version instead of latest:
```bash
apt list --all-versions docker-ce
VERSION_STRING=5:29.1.3-1~ubuntu.24.04~noble
sudo apt install docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin
```

#### Verify installation
```bash
sudo systemctl status docker
```
If not running:
```bash
sudo systemctl start docker
```

Test Docker Engine:
```bash
sudo docker run hello-world
```

Test Docker Compose:
```bash
docker compose version
```

#### Post-install (optional): run Docker without sudo
```bash
sudo groupadd docker
sudo usermod -aG docker $USER
```
Log out/in (or run `newgrp docker`) to apply group changes, then test:
```bash
docker run hello-world
```

## Quick start
1) Clone or unzip this folder on the target machine.
2) Edit `docker-compose.yml` and set:
   - `WEB_URL` to the webpage you want to stream
   - `YT_STREAM_KEY` to your YouTube Live stream key
3) Build and start the container:

   ```bash
   docker compose up -d --build
   ```

4) Watch logs:

   ```bash
   docker logs -f web2yt
   ```

5) Stop the stream:

   ```bash
   docker compose down
   ```

## Configuration (docker-compose.yml)
You can adjust streaming quality or display settings via environment variables:

| Variable | Description | Default |
| --- | --- | --- |
| `WEB_URL` | Webpage to render and stream | `https://your-webpage.example.com` |
| `YT_RTMPS_URL` | YouTube ingest URL | `rtmps://a.rtmps.youtube.com/live2` |
| `YT_STREAM_KEY` | YouTube stream key | `xxxx-xxxx-xxxx-xxxx` |
| `WIDTH` | Capture width in pixels | `1920` |
| `HEIGHT` | Capture height in pixels | `1080` |
| `FPS` | Frames per second | `30` |
| `CHROME_BIN` | Chromium executable inside container | `google-chrome` |
| `VIDEO_BITRATE` | FFmpeg video bitrate | `6500k` |
| `VIDEO_MAXRATE` | FFmpeg max bitrate | `7500k` |
| `VIDEO_BUFSIZE` | FFmpeg buffer size | `13000k` |
| `AUDIO_BITRATE` | FFmpeg audio bitrate | `160k` |
| `LOGIN_USER` | Optional username for Puppeteer login | unset |
| `LOGIN_PASS` | Optional password for Puppeteer login | unset |
| `LOGIN_USER_SELECTOR` | CSS selector for username input | `input[placeholder="User ID"], input[autocomplete="username"]` |
| `LOGIN_PASS_SELECTOR` | CSS selector for password input | `input[placeholder="Password"], input[autocomplete="current-password"]` |
| `LOGIN_SUBMIT_SELECTOR` | CSS selector for submit button | `button[type="submit"]` |
| `LOGIN_COOKIE_ACCEPT_SELECTOR` | Optional CSS selector for cookie-consent accept button | unset |
| `LOGIN_SUCCESS_SELECTOR` | Optional selector that indicates login success | unset |
| `CHROME_DEBUG_PORT` | Chromium remote debugging port for Puppeteer | `9222` |
| `LOGIN_TIMEOUT_MS` | Login timeout in milliseconds | `30000` |


## Optional: automated login with Puppeteer
If your page requires credentials, set `LOGIN_USER` and `LOGIN_PASS` in `docker-compose.yml`.
When both are set, startup runs Puppeteer against the already-open Chromium session to:
- wait for the login form
- type username/password
- accept a cookie banner when detected (or via an explicit selector)
- press Enter

You can override selectors if your login form changes:
- `LOGIN_USER_SELECTOR`
- `LOGIN_PASS_SELECTOR`
- `LOGIN_SUBMIT_SELECTOR`
- `LOGIN_COOKIE_ACCEPT_SELECTOR` (optional explicit cookie-accept button)
- `LOGIN_SUCCESS_SELECTOR` (optional explicit post-login signal)

> Security: avoid committing production credentials into source control.

## Tuning tips (1080p30 with voice + animations)
Default settings are tuned for mixed motion UI + voice:
- `VIDEO_BITRATE=6500k`, `VIDEO_MAXRATE=7500k`, `VIDEO_BUFSIZE=13000k`
- `AUDIO_BITRATE=160k`

If CPU is high, try lowering to ~4500k and/or using `-preset superfast` (in `start.sh`).
If you have an NVIDIA GPU and want NVENC, replace the FFmpeg encode line in `start.sh`.

## Troubleshooting
### Chromium crashes / odd rendering
- Ensure `shm_size: "1g"` is present (it is by default).
- Try lowering resolution or FPS temporarily to debug.

### DBus errors in Chromium logs
If you see repeated lines like `Failed to connect to socket /run/dbus/system_bus_socket`, the container is missing a running DBus system bus.

Recent images start a lightweight system bus automatically before launching Chromium to reduce this log noise. If you still see it, rebuild and recreate the container so the latest image/script is running:
```bash
docker compose build --no-cache
docker compose up -d --force-recreate
```

### No audio
- Ensure the webpage is actually playing audio (not muted).
- Inside the container:
  ```bash
  pactl list short sinks
  pactl list short sources | grep virtSink.monitor
  ```

### Hostname works on host, but blank page in stream
If `WEB_URL` points to a hostname that only resolves on your host machine (for example `http://boondock-test:4000`), Chromium inside the container may not resolve or reach it.

Check from inside the running container:
```bash
docker exec -it web2yt getent hosts boondock-test
docker exec -it web2yt curl -I http://boondock-test:4000
```

If those fail, use one of these options:
- Use `http://host.docker.internal:4000` and map host gateway in `docker-compose.yml`:
  ```yaml
  extra_hosts:
    - "host.docker.internal:host-gateway"
  ```
- Or publish your local service on an address reachable from the container network.

### Chromium exits with "requires the chromium snap to be installed"
This means the container is invoking Ubuntu's snap wrapper (`chromium-browser`) instead of a real Chromium binary.

Use the bundled `google-chrome-stable` package in the image. You can also set an explicit binary path/name with:
```yaml
environment:
  CHROME_BIN: "google-chrome"
```

The startup script now fails fast if Chromium exits immediately, so you will see an explicit error in logs instead of streaming a blank screen.

### Black screen
- Confirm Xvfb is running and `DISPLAY=:99`:
  ```bash
  xdpyinfo -display :99 | head
  ```

## Security note
Your YouTube stream key is sensitive. Keep `docker-compose.yml` private.
