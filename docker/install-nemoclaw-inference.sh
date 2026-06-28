#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

install -d -m 0755 /opt/nemoclaw /var/lib/nemoclaw/models /var/lib/nemoclaw/huggingface

export HF_HOME=/var/lib/nemoclaw/huggingface
export HUGGINGFACE_HUB_CACHE=/var/lib/nemoclaw/huggingface
export HF_HUB_CACHE=/var/lib/nemoclaw/huggingface

MODEL_SETTINGS_PATH="${NEMOCLAW_MODEL_SETTINGS_PATH:-/opt/nemoclaw/model-settings.yaml}"
if [ -x /usr/local/bin/model-settings.py ] && [ -s "$MODEL_SETTINGS_PATH" ]; then
  eval "$(/usr/local/bin/model-settings.py --config "$MODEL_SETTINGS_PATH" --model "${NEMOCLAW_MODEL}" --format shell)"
fi

: "${NEMOCLAW_MAX_MODEL_LEN:=32768}"
: "${NEMOCLAW_COMPACTION_RESERVE_TOKENS_FLOOR:=20000}"
: "${NEMOCLAW_OPENCLAW_MAX_TOKENS:=8192}"
: "${NEMOCLAW_LLAMA_N_GPU_LAYERS:=999}"

rm -rf /opt/nemoclaw/venv
python3 -m venv /opt/nemoclaw/venv
. /opt/nemoclaw/venv/bin/activate
python -m pip install --no-cache-dir --upgrade pip wheel "setuptools<80,>=77.0.3"
python -m pip install --no-cache-dir huggingface_hub

llama_model_path="$NEMOCLAW_MODEL"
if [[ "$NEMOCLAW_MODEL" == *:* ]]; then
  model_repo="${NEMOCLAW_MODEL%%:*}"
  quant_name="${NEMOCLAW_MODEL#*:}"
  gguf_file="${NEMOCLAW_GGUF_FILE:-}"
  if [ -z "$gguf_file" ]; then
    repo_base="${model_repo##*/}"
    repo_base="${repo_base,,}"
    repo_base="${repo_base%-gguf}"
    gguf_file="${repo_base}-${quant_name}.gguf"
  fi
  llama_model_path="$(python - "$model_repo" "$gguf_file" <<'PY'
import sys
from huggingface_hub import hf_hub_download

repo, filename = sys.argv[1], sys.argv[2]
print(hf_hub_download(
    repo_id=repo,
    filename=filename,
    local_dir="/var/lib/nemoclaw/models",
    local_dir_use_symlinks=False,
))
PY
)"
fi

{
  printf 'NEMOCLAW_MODEL=%q\n' "$NEMOCLAW_MODEL"
  printf 'NEMOCLAW_LLAMA_MODEL_PATH=%q\n' "$llama_model_path"
  printf 'NEMOCLAW_CHARACTER_NAME=%q\n' "$NEMOCLAW_CHARACTER_NAME"
  printf 'NEMOCLAW_API_HOST=%q\n' "$NEMOCLAW_API_HOST"
  printf 'NEMOCLAW_API_PORT=%q\n' "$NEMOCLAW_API_PORT"
  printf 'NEMOCLAW_MAX_MODEL_LEN=%q\n' "${NEMOCLAW_MAX_MODEL_LEN:-}"
  printf 'NEMOCLAW_COMPACTION_RESERVE_TOKENS_FLOOR=%q\n' "${NEMOCLAW_COMPACTION_RESERVE_TOKENS_FLOOR:-}"
  printf 'NEMOCLAW_OPENCLAW_MAX_TOKENS=%q\n' "${NEMOCLAW_OPENCLAW_MAX_TOKENS:-}"
  printf 'NEMOCLAW_LLAMA_N_GPU_LAYERS=%q\n' "${NEMOCLAW_LLAMA_N_GPU_LAYERS:-}"
} >/opt/nemoclaw/env
chmod 0600 /opt/nemoclaw/env

if [ -n "${HF_TOKEN:-}" ]; then
  printf 'HF_TOKEN=%s\nHUGGING_FACE_HUB_TOKEN=%s\n' "$HF_TOKEN" "$HF_TOKEN" >/opt/nemoclaw/huggingface.env
  chmod 0600 /opt/nemoclaw/huggingface.env
else
  : >/opt/nemoclaw/huggingface.env
  chmod 0600 /opt/nemoclaw/huggingface.env
fi

cat >/opt/nemoclaw/openai.env <<EOF
OPENAI_BASE_URL=http://127.0.0.1:${NEMOCLAW_API_PORT}/v1
OPENAI_API_KEY=nemoclaw-local
OPENAI_MODEL=${NEMOCLAW_MODEL}
EOF
chmod 0600 /opt/nemoclaw/openai.env
