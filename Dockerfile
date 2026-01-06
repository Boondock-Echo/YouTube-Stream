FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    APP_DIR=/opt/youtube-stream/webapp \
    STREAM_USER=streamer \
    OBS_HOME=/var/lib/streamer

# Base tools needed before the helper scripts run
RUN apt-get update && \
    apt-get install -y --no-install-recommends sudo tini && \
    rm -rf /var/lib/apt/lists/*

# Copy scripts into the image
WORKDIR /workspace/YouTube-Stream
COPY scripts/ ./scripts/

# Install Node/OBS/Xvfb and create the service user
RUN chmod +x scripts/*.sh && \
    APP_DIR="$APP_DIR" STREAM_USER="$STREAM_USER" OBS_HOME="$OBS_HOME" bash scripts/install_dependencies.sh

# Bootstrap and build the sample React app
RUN APP_DIR="$APP_DIR" STREAM_USER="$STREAM_USER" bash scripts/bootstrap_react_app.sh && \
    su -p -s /bin/bash "$STREAM_USER" -c "cd \"$APP_DIR\" && npm run build"

# Entrypoint to configure OBS and launch services
COPY scripts/container-entrypoint.sh /scripts/container-entrypoint.sh
RUN chmod +x /scripts/container-entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/usr/bin/tini", "--", "/scripts/container-entrypoint.sh"]
