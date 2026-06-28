#!/bin/sh
set -eu

if [ -r /opt/nemoclaw/embeddings.env ]; then
  . /opt/nemoclaw/embeddings.env
fi
if [ -s /opt/nemoclaw/embeddings-openai.env ]; then
  set -a
  . /opt/nemoclaw/embeddings-openai.env
  set +a
fi

export HF_HOME=/var/lib/nemoclaw/huggingface
export HUGGINGFACE_HUB_CACHE=/var/lib/nemoclaw/huggingface
export HF_HUB_CACHE=/var/lib/nemoclaw/huggingface

for _ in $(seq 1 600); do
  if [ -s /opt/nemoclaw/embeddings.env ]; then
    . /opt/nemoclaw/embeddings.env
    if [ -n "${NEMOCLAW_EMBEDDING_LLAMA_MODEL_PATH:-}" ] && [ -s "${NEMOCLAW_EMBEDDING_LLAMA_MODEL_PATH}" ]; then
      break
    fi
  fi
  sleep 2
done

if [ -z "${NEMOCLAW_EMBEDDING_LLAMA_MODEL_PATH:-}" ] || [ ! -s "${NEMOCLAW_EMBEDDING_LLAMA_MODEL_PATH}" ]; then
  echo "error: embedding model was not prepared at /opt/nemoclaw/embeddings.env" >&2
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
  --embeddings \
  --pooling last \
  --model "${NEMOCLAW_EMBEDDING_LLAMA_MODEL_PATH}" \
  --host "${NEMOCLAW_EMBEDDING_API_HOST:-0.0.0.0}" \
  --port "${NEMOCLAW_EMBEDDING_API_PORT:-8010}" \
  --alias "${NEMOCLAW_EMBEDDING_MODEL}" \
  --ctx-size "${NEMOCLAW_EMBEDDING_MAX_MODEL_LEN:-8192}" \
  --n-gpu-layers "${NEMOCLAW_EMBEDDING_LLAMA_N_GPU_LAYERS:-999}"

exec "$@"
