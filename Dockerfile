ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    gh \
    git \
    gosu \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    tini \
  && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --home-dir /home/nemoclaw --shell /bin/bash nemoclaw \
  && install -d -m 0755 /opt/nemoclaw /var/lib/nemoclaw /home/nemoclaw \
  && chown -R nemoclaw:nemoclaw /home/nemoclaw

COPY docker/inference-entrypoint.sh /opt/nemoclaw/inference-entrypoint.sh
COPY docker/nemoclaw-entrypoint.sh /opt/nemoclaw/nemoclaw-entrypoint.sh
RUN chmod 0755 /opt/nemoclaw/inference-entrypoint.sh /opt/nemoclaw/nemoclaw-entrypoint.sh

WORKDIR /opt/nemoclaw
