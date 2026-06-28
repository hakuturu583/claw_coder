#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

: "${NEMOCLAW_EMBEDDING_MODEL:=mradermacher/sarashina-embedding-v2-1b-GGUF:Q4_K_M}"
: "${NEMOCLAW_EMBEDDING_API_HOST:=0.0.0.0}"
: "${NEMOCLAW_EMBEDDING_API_PORT:=8010}"
: "${NEMOCLAW_EMBEDDING_MAX_MODEL_LEN:=8192}"
: "${NEMOCLAW_EMBEDDING_LLAMA_N_GPU_LAYERS:=999}"

install -d -m 0755 /opt/nemoclaw /var/lib/nemoclaw/models /var/lib/nemoclaw/huggingface

export HF_HOME=/var/lib/nemoclaw/huggingface
export HUGGINGFACE_HUB_CACHE=/var/lib/nemoclaw/huggingface
export HF_HUB_CACHE=/var/lib/nemoclaw/huggingface

rm -rf /opt/nemoclaw/venv-embeddings
python3 -m venv /opt/nemoclaw/venv-embeddings
. /opt/nemoclaw/venv-embeddings/bin/activate
python -m pip install --no-cache-dir --upgrade pip wheel "setuptools<80,>=77.0.3"
python -m pip install --no-cache-dir huggingface_hub

embedding_model_path="$NEMOCLAW_EMBEDDING_MODEL"
if [[ "$NEMOCLAW_EMBEDDING_MODEL" == *:* ]]; then
  model_repo="${NEMOCLAW_EMBEDDING_MODEL%%:*}"
  quant_name="${NEMOCLAW_EMBEDDING_MODEL#*:}"
  gguf_file="${NEMOCLAW_EMBEDDING_GGUF_FILE:-}"
  if [ -z "$gguf_file" ]; then
    repo_base="${model_repo##*/}"
    repo_base="${repo_base,,}"
    repo_base="${repo_base%-gguf}"
    gguf_file="${repo_base}-${quant_name}.gguf"
  fi
  embedding_model_path="$(python - "$model_repo" "$gguf_file" <<'PY'
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
  printf 'NEMOCLAW_EMBEDDING_MODEL=%q\n' "$NEMOCLAW_EMBEDDING_MODEL"
  printf 'NEMOCLAW_EMBEDDING_LLAMA_MODEL_PATH=%q\n' "$embedding_model_path"
  printf 'NEMOCLAW_EMBEDDING_API_HOST=%q\n' "$NEMOCLAW_EMBEDDING_API_HOST"
  printf 'NEMOCLAW_EMBEDDING_API_PORT=%q\n' "$NEMOCLAW_EMBEDDING_API_PORT"
  printf 'NEMOCLAW_EMBEDDING_MAX_MODEL_LEN=%q\n' "$NEMOCLAW_EMBEDDING_MAX_MODEL_LEN"
  printf 'NEMOCLAW_EMBEDDING_LLAMA_N_GPU_LAYERS=%q\n' "$NEMOCLAW_EMBEDDING_LLAMA_N_GPU_LAYERS"
} >/opt/nemoclaw/embeddings.env
chmod 0600 /opt/nemoclaw/embeddings.env

cat >/opt/nemoclaw/embeddings-openai.env <<EOF
OPENAI_BASE_URL=http://127.0.0.1:${NEMOCLAW_EMBEDDING_API_PORT}/v1
OPENAI_API_KEY=nemoclaw-local
OPENAI_MODEL=${NEMOCLAW_EMBEDDING_MODEL}
EOF
chmod 0600 /opt/nemoclaw/embeddings-openai.env
