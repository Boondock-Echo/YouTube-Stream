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
