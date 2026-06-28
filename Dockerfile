ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive
ARG NEMOCLAW_UID=1001

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

RUN curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install-cli.sh \
  | bash -s -- --prefix /opt/openclaw --no-onboard

RUN groupadd --gid "${NEMOCLAW_UID}" nemoclaw \
  && useradd --create-home --home-dir /home/nemoclaw --shell /bin/bash --uid "${NEMOCLAW_UID}" --gid "${NEMOCLAW_UID}" nemoclaw \
  && install -d -m 0755 /opt/nemoclaw /var/lib/nemoclaw /home/nemoclaw

COPY docker/inference-entrypoint.sh /usr/local/bin/inference-entrypoint.sh
COPY docker/install-nemoclaw-inference.sh /usr/local/bin/install-nemoclaw-inference.sh
COPY docker/install-openclaw-config.sh /usr/local/bin/install-openclaw-config.sh
COPY docker/nemoclaw-entrypoint.sh /usr/local/bin/nemoclaw-entrypoint.sh
RUN chmod 0755 /usr/local/bin/inference-entrypoint.sh /usr/local/bin/install-nemoclaw-inference.sh /usr/local/bin/install-openclaw-config.sh /usr/local/bin/nemoclaw-entrypoint.sh \
  && chown -R nemoclaw:nemoclaw /home/nemoclaw

ENV NEMOCLAW_UID=${NEMOCLAW_UID}
ENV PATH=/opt/openclaw/bin:${PATH}

WORKDIR /opt/nemoclaw
