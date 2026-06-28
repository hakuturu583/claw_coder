ARG BASE_IMAGE=ubuntu:24.04
ARG NEMOCLAW_UID=1000
ARG NEMOCLAW_GID=1000
FROM ${BASE_IMAGE}
ARG NEMOCLAW_UID
ARG NEMOCLAW_GID

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
    python3-yaml \
    python3-venv \
    tini \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install-cli.sh \
  | bash -s -- --prefix /opt/openclaw --no-onboard

RUN groupadd --non-unique --gid "${NEMOCLAW_GID}" nemoclaw \
  && useradd --create-home --home-dir /home/nemoclaw --shell /bin/bash --non-unique --uid "${NEMOCLAW_UID}" --gid "${NEMOCLAW_GID}" nemoclaw \
  && install -d -m 0755 /opt/nemoclaw /var/lib/nemoclaw /home/nemoclaw

COPY docker/inference-entrypoint.sh /usr/local/bin/inference-entrypoint.sh
COPY docker/install-nemoclaw-inference.sh /usr/local/bin/install-nemoclaw-inference.sh
COPY docker/install-openclaw-config.sh /usr/local/bin/install-openclaw-config.sh
COPY docker/model-settings.py /usr/local/bin/model-settings.py
COPY docker/nemoclaw-entrypoint.sh /usr/local/bin/nemoclaw-entrypoint.sh
RUN chmod 0755 /usr/local/bin/inference-entrypoint.sh /usr/local/bin/install-nemoclaw-inference.sh /usr/local/bin/install-openclaw-config.sh /usr/local/bin/model-settings.py /usr/local/bin/nemoclaw-entrypoint.sh \
  && chown -R nemoclaw:nemoclaw /home/nemoclaw

ENV NEMOCLAW_UID=${NEMOCLAW_UID}
ENV NEMOCLAW_GID=${NEMOCLAW_GID}
ENV PATH=/opt/openclaw/bin:${PATH}

WORKDIR /opt/nemoclaw
