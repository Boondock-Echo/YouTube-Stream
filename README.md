# web2yt — Headless Webpage → YouTube Live (Docker)

This container runs a **virtual monitor** (Xvfb), launches **Chromium in kiosk mode** on that virtual display,
captures **video + webpage audio**, and streams it to **YouTube Live** via **RTMPS**.

## Files
- `docker-compose.yml` — service definition and env vars
- `Dockerfile` — builds the container
- `start.sh` — starts Xvfb + PulseAudio + Chromium + FFmpeg

## Prereqs
- Docker + docker compose plugin on the target machine.

## Setup
1) Unzip this folder on the target machine.
2) Edit `docker-compose.yml`:
   - Set `WEB_URL` to your webpage.
   - Set `YT_STREAM_KEY` to your YouTube stream key.

## Run
From the folder:

    docker compose up -d --build

Logs:

    docker logs -f web2yt

Stop:

    docker compose down

## Tuning (1080p30 with voice + animations)
Default settings are tuned for mixed motion UI + voice:
- `VIDEO_BITRATE=6500k`, `VIDEO_MAXRATE=7500k`, `VIDEO_BUFSIZE=13000k`
- `AUDIO_BITRATE=160k`

If CPU is high, try lowering to ~4500k and/or using `-preset superfast` (in `start.sh`).
If you have an NVIDIA GPU and want NVENC, tell ChatGPT and we can swap in a GPU-accelerated FFmpeg line.

## Troubleshooting
### Chromium crashes / odd rendering
- Ensure `shm_size: "1g"` is present (it is by default).
- Try lowering resolution or FPS temporarily to debug.

### No audio
- Ensure the webpage is actually playing audio (not muted).
- Inside container you can inspect:
    pactl list short sinks
    pactl list short sources | grep virtSink.monitor

### Black screen
- Confirm Xvfb is running and `DISPLAY=:99`:
    xdpyinfo -display :99 | head

## Security note
Your YouTube stream key is sensitive. Keep `docker-compose.yml` private.
