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

exec llama-server \
  --model "${NEMOCLAW_LLAMA_MODEL_PATH}" \
  --host "${NEMOCLAW_API_HOST:-0.0.0.0}" \
  --port "${NEMOCLAW_API_PORT:-8000}" \
  --alias "${NEMOCLAW_MODEL}" \
  --ctx-size "${NEMOCLAW_MAX_MODEL_LEN:-32768}" \
  --n-gpu-layers "${NEMOCLAW_LLAMA_N_GPU_LAYERS:-999}" \
  --reasoning off
