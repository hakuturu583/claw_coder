#!/usr/bin/env bash
set -euo pipefail

if [ -d /home/nemoclaw ]; then
  chown -R nemoclaw:nemoclaw /home/nemoclaw || true
fi
install -d -o nemoclaw -g nemoclaw -m 0755 /home/nemoclaw/.openclaw /home/nemoclaw/.openclaw/skills || true

exec gosu nemoclaw:nemoclaw sleep infinity
