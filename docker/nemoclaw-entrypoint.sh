#!/usr/bin/env bash
set -euo pipefail

if [ -r /opt/nemoclaw/env ]; then
  . /opt/nemoclaw/env
fi

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
fi

if [ ! -x /opt/openclaw/bin/openclaw ]; then
  echo "error: openclaw CLI is missing from /opt/openclaw/bin/openclaw" >&2
  exit 1
fi

LOG_DIR=/home/nemoclaw/.claw_coder/logs
install -d -o nemoclaw -g nemoclaw -m 0700 /home/nemoclaw/.claw_coder "$LOG_DIR"
LOG_FILE="$LOG_DIR/nemoclaw-$(date -u +%Y%m%dT%H%M%SZ).log"
touch "$LOG_FILE"
chown nemoclaw:nemoclaw "$LOG_FILE"
chmod 0600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "info: logging to $LOG_FILE"

gosu nemoclaw:nemoclaw /usr/local/bin/install-openclaw-config.sh

install -d -o nemoclaw -g nemoclaw -m 0700 /tmp/openclaw-1001 || true
export TMPDIR=/tmp/openclaw-1001

gosu nemoclaw:nemoclaw env HOME=/home/nemoclaw TMPDIR=/tmp/openclaw-1001 openclaw plugins install --force @openclaw/slack
gosu nemoclaw:nemoclaw env HOME=/home/nemoclaw TMPDIR=/tmp/openclaw-1001 openclaw plugins install --force @openclaw/brave-plugin

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

exec gosu nemoclaw:nemoclaw env HOME=/home/nemoclaw TMPDIR=/tmp/openclaw-1001 openclaw gateway
