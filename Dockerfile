FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends     xvfb x11-utils     pulseaudio     chromium-browser     ffmpeg     fonts-dejavu-core fonts-noto-color-emoji     ca-certificates     tini   && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/start.sh"]
