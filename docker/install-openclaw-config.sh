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

install -d -o nemoclaw -g nemoclaw -m 0700 /home/nemoclaw/.openclaw /home/nemoclaw/.openclaw/workspace
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
  agents: {
    defaults: {
      workspace: "/home/nemoclaw/.openclaw/workspace",
      compaction: {
        reserveTokensFloor: 20000,
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
            maxTokens: 8192,
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
