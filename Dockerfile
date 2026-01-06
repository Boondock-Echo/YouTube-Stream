FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    APP_DIR=/opt/youtube-stream/webapp \
    STREAM_USER=streamer \
    OBS_HOME=/var/lib/streamer

# Base tools needed before the helper scripts run
RUN apt-get update && \
    apt-get install -y --no-install-recommends sudo tini supervisor && \
    rm -rf /var/lib/apt/lists/*

# Copy the entire repository into the image so scripts and config stay self-contained
WORKDIR /workspace/YouTube-Stream
COPY . /workspace/YouTube-Stream/

# Install Node/OBS/Xvfb and create the service user
RUN find scripts -type f -name "*.sh" -exec chmod +x {} + && \
    APP_DIR="$APP_DIR" STREAM_USER="$STREAM_USER" OBS_HOME="$OBS_HOME" bash scripts/install/install_dependencies.sh

# Bootstrap and build the sample React app
RUN APP_DIR="$APP_DIR" STREAM_USER="$STREAM_USER" bash scripts/install/bootstrap_react_app.sh && \
    su -p -s /bin/bash "$STREAM_USER" -c "cd \"$APP_DIR\" && npm run build"

# Entrypoint to configure OBS and launch services
EXPOSE 3000

ENTRYPOINT ["/usr/bin/tini", "--", "/workspace/YouTube-Stream/scripts/ops/container-entrypoint.sh"]
