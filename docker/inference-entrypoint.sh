#!/usr/bin/env bash
set -euo pipefail

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

if [ "${NEMOCLAW_CUDA_VARIANT:-cu130}" = "cu130" ]; then
  export LD_LIBRARY_PATH="/opt/nemoclaw/venv/lib/python3.12/site-packages/nvidia/cu13/lib:${LD_LIBRARY_PATH:-}"
fi

if [ ! -x /opt/nemoclaw/llama-server ]; then
  echo "llama-server is missing; installing it now." >&2
  /usr/local/bin/install-nemoclaw-inference.sh
fi

exec gosu nemoclaw:nemoclaw /opt/nemoclaw/llama-server \
  --model "${NEMOCLAW_LLAMA_MODEL_PATH:-$NEMOCLAW_MODEL}" \
  --host "$NEMOCLAW_API_HOST" \
  --port "$NEMOCLAW_API_PORT" \
  --alias "$NEMOCLAW_MODEL" \
  --ctx-size "$NEMOCLAW_MAX_MODEL_LEN" \
  --n-gpu-layers "$NEMOCLAW_LLAMA_N_GPU_LAYERS" \
  --reasoning off
