#!/usr/bin/env bash
set -euo pipefail

LOG_DIR=/home/nemoclaw/.claw_coder/logs
install -d -o nemoclaw -g nemoclaw -m 0755 /home/nemoclaw/.claw_coder "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/nemoclaw-$(date -u +%Y%m%dT%H%M%SZ).log"
touch "$LOG_FILE" 2>/dev/null || true
chown nemoclaw:nemoclaw "$LOG_FILE" 2>/dev/null || true
chmod 0644 "$LOG_FILE" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'status=$?; echo "info: nemoclaw-entrypoint exiting status=$status log=$LOG_FILE"' EXIT
echo "info: logging to $LOG_FILE"

if [ -r /opt/nemoclaw/env ]; then
  . /opt/nemoclaw/env
fi

NEMOCLAW_UID="${NEMOCLAW_UID:-$(id -u nemoclaw 2>/dev/null || printf '1000')}"
OPENCLAW_TMPDIR="/tmp/openclaw-${NEMOCLAW_UID}"

if [ -z "${SLACK_BOT_TOKEN:-}" ] || [ -z "${SLACK_APP_TOKEN:-}" ] || [ -z "${SLACK_CHANNEL_ID:-}" ]; then
  echo "error: SLACK_BOT_TOKEN, SLACK_APP_TOKEN, and SLACK_CHANNEL_ID are required for the OpenClaw Slack Channel" >&2
  exit 1
fi

if [ -d /home/nemoclaw ]; then
  install -d -o nemoclaw -g nemoclaw -m 0755 \
    /home/nemoclaw \
    /home/nemoclaw/.npm \
    /home/nemoclaw/.openclaw \
    /home/nemoclaw/.openclaw/logs \
    /home/nemoclaw/.openclaw/npm \
    /home/nemoclaw/.openclaw/state \
    /home/nemoclaw/.openclaw/skills \
    /home/nemoclaw/.openclaw/workspace || true
  chown -R nemoclaw:nemoclaw /home/nemoclaw/.npm /home/nemoclaw/.claw_coder 2>/dev/null || true
  find /home/nemoclaw/.openclaw \
    -path /home/nemoclaw/.openclaw/workspace/AGENTS.md -prune -o \
    -exec chown nemoclaw:nemoclaw {} + 2>/dev/null || true
fi

if [ ! -x /opt/openclaw/bin/openclaw ]; then
  echo "error: openclaw CLI is missing from /opt/openclaw/bin/openclaw" >&2
  exit 1
fi

/usr/local/bin/install-openclaw-config.sh

install -d -o nemoclaw -g nemoclaw -m 0700 "${OPENCLAW_TMPDIR}" || true
export TMPDIR="${OPENCLAW_TMPDIR}"
export NPM_CONFIG_CACHE="${OPENCLAW_TMPDIR}/npm-cache"
export npm_config_cache="${OPENCLAW_TMPDIR}/npm-cache"
install -d -o nemoclaw -g nemoclaw -m 0700 "$NPM_CONFIG_CACHE" || true

gosu nemoclaw:nemoclaw env HOME=/home/nemoclaw TMPDIR="${OPENCLAW_TMPDIR}" NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE}" npm_config_cache="${npm_config_cache}" openclaw plugins install --force @openclaw/slack
gosu nemoclaw:nemoclaw env HOME=/home/nemoclaw TMPDIR="${OPENCLAW_TMPDIR}" NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE}" npm_config_cache="${npm_config_cache}" openclaw plugins install --force @openclaw/brave-plugin

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

exec gosu nemoclaw:nemoclaw env HOME=/home/nemoclaw TMPDIR="${OPENCLAW_TMPDIR}" NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE}" npm_config_cache="${npm_config_cache}" openclaw gateway
