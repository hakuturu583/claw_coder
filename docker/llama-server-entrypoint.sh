#!/bin/sh
set -eu

if [ -r /opt/nemoclaw/env ]; then
  . /opt/nemoclaw/env
fi
if [ -s /opt/nemoclaw/huggingface.env ]; then
  set -a
  . /opt/nemoclaw/huggingface.env
  set +a
fi

export HF_HOME=/var/lib/nemoclaw/huggingface
export HUGGINGFACE_HUB_CACHE=/var/lib/nemoclaw/huggingface
export HF_HUB_CACHE=/var/lib/nemoclaw/huggingface

for _ in $(seq 1 600); do
  if [ -s /opt/nemoclaw/env ]; then
    . /opt/nemoclaw/env
    if [ -n "${NEMOCLAW_LLAMA_MODEL_PATH:-}" ] && [ -s "${NEMOCLAW_LLAMA_MODEL_PATH}" ]; then
      break
    fi
  fi
  sleep 2
done

if [ -z "${NEMOCLAW_LLAMA_MODEL_PATH:-}" ] || [ ! -s "${NEMOCLAW_LLAMA_MODEL_PATH}" ]; then
  echo "error: model was not prepared at /opt/nemoclaw/env" >&2
  exit 1
fi

if [ -x /app/llama-server ]; then
  llama_server_bin=/app/llama-server
elif command -v llama-server >/dev/null 2>&1; then
  llama_server_bin="$(command -v llama-server)"
else
  echo "error: llama-server binary not found in the llama.cpp image" >&2
  exit 1
fi

set -- "$llama_server_bin" \
  --jinja \
  --model "${NEMOCLAW_LLAMA_MODEL_PATH}" \
  --host "${NEMOCLAW_API_HOST:-0.0.0.0}" \
  --port "${NEMOCLAW_API_PORT:-8000}" \
  --alias "${NEMOCLAW_MODEL}" \
  --ctx-size "${NEMOCLAW_MAX_MODEL_LEN:-32768}" \
  --n-gpu-layers "${NEMOCLAW_LLAMA_N_GPU_LAYERS:-999}" \
  --reasoning off

if [ -n "${NEMOCLAW_LLAMA_CHAT_TEMPLATE:-}" ]; then
  set -- "$@" --chat-template "${NEMOCLAW_LLAMA_CHAT_TEMPLATE}"
fi

exec "$@"
