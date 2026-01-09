# web2yt — Headless Webpage → YouTube Live (Docker)

This project runs a **virtual monitor** (Xvfb), launches **Chromium in kiosk mode** on that virtual display,
captures **video + webpage audio**, and streams it to **YouTube Live** via **RTMPS**.

## What’s in this repo
- `docker-compose.yml` — service definition and environment variables
- `Dockerfile` — container build instructions
- `start.sh` — starts Xvfb + PulseAudio + Chromium + FFmpeg

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
| `VIDEO_BITRATE` | FFmpeg video bitrate | `6500k` |
| `VIDEO_MAXRATE` | FFmpeg max bitrate | `7500k` |
| `VIDEO_BUFSIZE` | FFmpeg buffer size | `13000k` |
| `AUDIO_BITRATE` | FFmpeg audio bitrate | `160k` |

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

### No audio
- Ensure the webpage is actually playing audio (not muted).
- Inside the container:
  ```bash
  pactl list short sinks
  pactl list short sources | grep virtSink.monitor
  ```

### Black screen
- Confirm Xvfb is running and `DISPLAY=:99`:
  ```bash
  xdpyinfo -display :99 | head
  ```

## Security note
Your YouTube stream key is sensitive. Keep `docker-compose.yml` private.
