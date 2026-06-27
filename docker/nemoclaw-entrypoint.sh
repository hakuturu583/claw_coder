#!/usr/bin/env bash
set -euo pipefail

if [ -r /opt/nemoclaw/env ]; then
  . /opt/nemoclaw/env
fi
if [ -r /opt/nemoclaw/integrations.env ]; then
  set -a
  . /opt/nemoclaw/integrations.env
  set +a
fi

if [ -d /home/nemoclaw ]; then
  chown -R nemoclaw:nemoclaw /home/nemoclaw || true
fi
install -d -o nemoclaw -g nemoclaw -m 0755 /home/nemoclaw/.openclaw /home/nemoclaw/.openclaw/skills || true

if [ -n "${SLACK_BOT_TOKEN:-}" ] && [ -n "${SLACK_CHANNEL_ID:-}" ]; then
  /usr/local/bin/send-startup-notification.sh >/tmp/nemoclaw-startup-notification.log 2>&1 &
fi

exec gosu nemoclaw:nemoclaw sleep infinity
