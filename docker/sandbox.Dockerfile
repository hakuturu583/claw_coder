FROM node:24-bookworm-slim

ARG SANDBOX_UID=1000
ARG SANDBOX_GID=1000

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    python3 \
    ripgrep \
    tini \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd --non-unique --gid "${SANDBOX_GID}" sandbox \
  && useradd --create-home --home-dir /home/sandbox --shell /bin/bash --non-unique --uid "${SANDBOX_UID}" --gid "${SANDBOX_GID}" sandbox \
  && install -d -o sandbox -g sandbox -m 0755 /workspace

USER sandbox
WORKDIR /workspace

ENTRYPOINT ["/usr/bin/tini", "-s", "--"]
CMD ["sleep", "infinity"]
