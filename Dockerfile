FROM ubuntu:22.04

ARG STREAM_USER=streamer
ARG OBS_HOME=/var/lib/${STREAM_USER}
ARG APP_DIR=/opt/youtube-stream/webapp
ARG NODE_MAJOR=20
ARG YOUTUBE_STREAM_KEY=REPLACE_ME

ENV DEBIAN_FRONTEND=noninteractive \
    STREAM_USER=${STREAM_USER} \
    OBS_HOME=${OBS_HOME} \
    APP_DIR=${APP_DIR}

WORKDIR /

# Copy helper scripts into the image
COPY scripts /scripts
RUN chmod +x /scripts/*.sh

# Install core dependencies, OBS Studio, Node.js, and create the service user
RUN STREAM_USER=${STREAM_USER} OBS_HOME=${OBS_HOME} APP_DIR=${APP_DIR} NODE_MAJOR=${NODE_MAJOR} \
    DEBIAN_FRONTEND=noninteractive bash /scripts/install_dependencies.sh

# Pre-bake the sample React app so the runtime can serve it immediately (build included)
RUN STREAM_USER=${STREAM_USER} APP_DIR=${APP_DIR} bash /scripts/bootstrap_react_app.sh && \
    su -s /bin/bash -c "cd ${APP_DIR} && npm run build" "${STREAM_USER}"

# Preconfigure OBS with a scene/profile pointing at the bundled web app
RUN APP_URL=http://localhost:3000 YOUTUBE_STREAM_KEY=${YOUTUBE_STREAM_KEY} \
    STREAM_USER=${STREAM_USER} OBS_HOME=${OBS_HOME} APP_DIR=${APP_DIR} \
    bash /scripts/configure_obs.sh --disable-browser-hw-accel

# Install a minimal init and a static file server for the React build
RUN apt-get update && \
    apt-get install -y tini && \
    npm install -g serve && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Entrypoint for running the React app and headless OBS
COPY scripts/container-entrypoint.sh /scripts/container-entrypoint.sh
RUN chmod +x /scripts/container-entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["tini", "--", "/scripts/container-entrypoint.sh"]
