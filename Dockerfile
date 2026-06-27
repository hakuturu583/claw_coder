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

COPY docker/entrypoint.sh /opt/nemoclaw/entrypoint.sh
RUN chmod 0755 /opt/nemoclaw/entrypoint.sh

WORKDIR /opt/nemoclaw

ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/opt/nemoclaw/entrypoint.sh"]
