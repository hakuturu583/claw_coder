#!/usr/bin/env bash
set -euo pipefail

if [ -r /opt/nemoclaw/env ]; then
  . /opt/nemoclaw/env
fi

NEMOCLAW_UID="${NEMOCLAW_UID:-$(id -u nemoclaw 2>/dev/null || printf '1001')}"
OPENCLAW_TMPDIR="/tmp/openclaw-${NEMOCLAW_UID}"

if [ -z "${SLACK_BOT_TOKEN:-}" ] || [ -z "${SLACK_APP_TOKEN:-}" ] || [ -z "${SLACK_CHANNEL_ID:-}" ]; then
  echo "error: SLACK_BOT_TOKEN, SLACK_APP_TOKEN, and SLACK_CHANNEL_ID are required for the OpenClaw Slack Channel" >&2
  exit 1
fi

if [ -d /home/nemoclaw ]; then
  install -d -o nemoclaw -g nemoclaw -m 0755 \
    /home/nemoclaw \
    /home/nemoclaw/.openclaw \
    /home/nemoclaw/.openclaw/skills \
    /home/nemoclaw/.openclaw/workspace || true
  chown nemoclaw:nemoclaw \
    /home/nemoclaw \
    /home/nemoclaw/.openclaw \
    /home/nemoclaw/.openclaw/skills \
    /home/nemoclaw/.openclaw/workspace || true
fi

if [ ! -x /opt/openclaw/bin/openclaw ]; then
  echo "error: openclaw CLI is missing from /opt/openclaw/bin/openclaw" >&2
  exit 1
fi

gosu nemoclaw:nemoclaw /usr/local/bin/install-openclaw-config.sh

install -d -o nemoclaw -g nemoclaw -m 0700 "${OPENCLAW_TMPDIR}" || true
install -d -o nemoclaw -g nemoclaw -m 0700 "${OPENCLAW_TMPDIR}/npm" || true
export TMPDIR="${OPENCLAW_TMPDIR}"

gosu nemoclaw:nemoclaw env HOME=/home/nemoclaw TMPDIR="${OPENCLAW_TMPDIR}" NPM_CONFIG_CACHE="${OPENCLAW_TMPDIR}/npm" openclaw plugins install --force @openclaw/slack
gosu nemoclaw:nemoclaw env HOME=/home/nemoclaw TMPDIR="${OPENCLAW_TMPDIR}" NPM_CONFIG_CACHE="${OPENCLAW_TMPDIR}/npm" openclaw plugins install --force @openclaw/brave-plugin

for _ in $(seq 1 900); do
  if curl -fsS "http://inference:${NEMOCLAW_API_PORT:-8000}/v1/models" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! curl -fsS "http://inference:${NEMOCLAW_API_PORT:-8000}/v1/models" >/dev/null 2>&1; then
  echo "error: inference did not become ready at http://inference:${NEMOCLAW_API_PORT:-8000}/v1/models" >&2
  exit 1
fi

exec gosu nemoclaw:nemoclaw env HOME=/home/nemoclaw TMPDIR="${OPENCLAW_TMPDIR}" NPM_CONFIG_CACHE="${OPENCLAW_TMPDIR}/npm" openclaw gateway
