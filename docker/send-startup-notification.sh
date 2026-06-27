#!/usr/bin/env bash
set -euo pipefail

token="${SLACK_BOT_TOKEN:-}"
channel="${SLACK_CHANNEL_ID:-}"
character_name="${NEMOCLAW_CHARACTER_NAME:-Clawくん}"
api_port="${NEMOCLAW_API_PORT:-8000}"
startup_text="${character_name} が起動しました。推論コンテナが Ready です。"

if [ -z "$token" ] || [ -z "$channel" ]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "warning: jq is missing; cannot send Slack startup notification" >&2
  exit 0
fi

for _ in $(seq 1 180); do
  if curl -fsS "http://inference:${api_port}/v1/models" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! curl -fsS "http://inference:${api_port}/v1/models" >/dev/null 2>&1; then
  echo "warning: inference did not become ready; skipping Slack startup notification" >&2
  exit 0
fi

payload="$(jq -nc --arg channel "$channel" --arg text "$startup_text" '{channel:$channel,text:$text}')"
response="$(
  curl -fsS \
    -X POST \
    -H "Authorization: Bearer ${token}" \
    -H "Content-type: application/json; charset=utf-8" \
    --data "$payload" \
    https://slack.com/api/chat.postMessage \
  || true
)"

if [ -n "$response" ] && ! jq -e '.ok == true' >/dev/null 2>&1 <<<"$response"; then
  echo "warning: Slack startup notification failed: ${response}" >&2
fi
