#!/usr/bin/env bash
set -euo pipefail

if [ -z "${SLACK_BOT_TOKEN:-}" ] || [ -z "${SLACK_APP_TOKEN:-}" ] || [ -z "${SLACK_CHANNEL_ID:-}" ]; then
  echo "error: SLACK_BOT_TOKEN, SLACK_APP_TOKEN, and SLACK_CHANNEL_ID are required to write the OpenClaw Slack Channel config" >&2
  exit 1
fi

brave_secret_env=""
if [ -n "${BRAVE_API_KEY:-}" ]; then
  brave_secret_env="BRAVE_API_KEY"
elif [ -n "${BRAVE_SEARCH_API_KEY:-}" ]; then
  brave_secret_env="BRAVE_SEARCH_API_KEY"
else
  echo "error: BRAVE_API_KEY or BRAVE_SEARCH_API_KEY is required to enable Brave web search" >&2
  exit 1
fi

MODEL_SETTINGS_PATH="${NEMOCLAW_MODEL_SETTINGS_PATH:-/opt/nemoclaw/model-settings.yaml}"
if [ -x /usr/local/bin/model-settings.py ] && [ -s "$MODEL_SETTINGS_PATH" ]; then
  eval "$(/usr/local/bin/model-settings.py --config "$MODEL_SETTINGS_PATH" --model "${NEMOCLAW_MODEL:-}" --format shell)"
fi

echo "info: resolved OpenClaw model settings"
echo "info:   NEMOCLAW_MODEL=${NEMOCLAW_MODEL:-}"
echo "info:   NEMOCLAW_MAX_MODEL_LEN=${NEMOCLAW_MAX_MODEL_LEN:-32768}"
echo "info:   NEMOCLAW_COMPACTION_RESERVE_TOKENS_FLOOR=${NEMOCLAW_COMPACTION_RESERVE_TOKENS_FLOOR:-20000}"
echo "info:   NEMOCLAW_OPENCLAW_MAX_TOKENS=${NEMOCLAW_OPENCLAW_MAX_TOKENS:-8192}"

install -d -o nemoclaw -g nemoclaw -m 0755 \
  /home/nemoclaw/.openclaw \
  /home/nemoclaw/.openclaw/workspace \
  /home/nemoclaw/.claw_coder \
  /home/nemoclaw/.claw_coder/logs \
  /home/nemoclaw/.claw_coder/logs/sessions
cat >/home/nemoclaw/.openclaw/openclaw.json <<EOF
{
  gateway: {
    mode: "local",
    bind: "loopback",
  },
  tools: {
    profile: "coding",
    alsoAllow: ["group:plugins"],
    sandbox: {
      tools: {
        alsoAllow: ["group:plugins"],
      },
    },
    web: {
      search: {
        provider: "brave",
        maxResults: 5,
        timeoutSeconds: 30,
      },
    },
  },
  plugins: {
    entries: {
      brave: {
        enabled: true,
        config: {
          webSearch: {
            apiKey: { source: "env", provider: "default", id: "${brave_secret_env}" },
          },
        },
      },
      workboard: {
        enabled: true,
        config: {},
      },
    },
  },
  logging: {
    file: "/home/nemoclaw/.claw_coder/logs/openclaw.log",
  },
  session: {
    store: "/home/nemoclaw/.claw_coder/logs/sessions/sessions.json",
  },
  agents: {
    defaults: {
      workspace: "/home/nemoclaw/.openclaw/workspace",
      compaction: {
        reserveTokensFloor: ${NEMOCLAW_COMPACTION_RESERVE_TOKENS_FLOOR:-20000},
      },
      model: {
        primary: "local/nemoclaw-local",
      },
      models: {
        "local/nemoclaw-local": {
          alias: "${NEMOCLAW_CHARACTER_NAME:-Clawくん}",
        },
      },
    },
  },
  models: {
    mode: "merge",
    providers: {
      local: {
        baseUrl: "http://inference:${NEMOCLAW_API_PORT:-8000}/v1",
        apiKey: "nemoclaw-local",
        api: "openai-completions",
        timeoutSeconds: 600,
        models: [
          {
            id: "nemoclaw-local",
            name: "${NEMOCLAW_CHARACTER_NAME:-Clawくん}",
            reasoning: false,
            input: ["text"],
            cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
            contextWindow: ${NEMOCLAW_MAX_MODEL_LEN:-32768},
            maxTokens: ${NEMOCLAW_OPENCLAW_MAX_TOKENS:-8192},
          },
        ],
      },
    },
  },
  channels: {
    slack: {
      enabled: true,
      mode: "socket",
      botToken: { source: "env", provider: "default", id: "SLACK_BOT_TOKEN" },
      appToken: { source: "env", provider: "default", id: "SLACK_APP_TOKEN" },
      groupPolicy: "allowlist",
      channels: {
      "${SLACK_CHANNEL_ID}": {
        requireMention: false,
      },
      },
    },
  },
  messages: {
    ackReaction: "eyes",
  },
}
EOF
chmod 0600 /home/nemoclaw/.openclaw/openclaw.json
chown nemoclaw:nemoclaw /home/nemoclaw/.openclaw/openclaw.json
touch /home/nemoclaw/.claw_coder/logs/openclaw.log /home/nemoclaw/.claw_coder/logs/sessions/sessions.json
chown nemoclaw:nemoclaw /home/nemoclaw/.claw_coder/logs/openclaw.log /home/nemoclaw/.claw_coder/logs/sessions/sessions.json
chmod 0755 /home/nemoclaw/.claw_coder /home/nemoclaw/.claw_coder/logs /home/nemoclaw/.claw_coder/logs/sessions
chmod 0644 /home/nemoclaw/.claw_coder/logs/openclaw.log /home/nemoclaw/.claw_coder/logs/sessions/sessions.json
