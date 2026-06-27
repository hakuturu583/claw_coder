#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

install -d -m 0755 /opt/nemoclaw /var/lib/nemoclaw
rm -rf /opt/nemoclaw/venv
python3 -m venv /opt/nemoclaw/venv
. /opt/nemoclaw/venv/bin/activate
python -m pip install --upgrade pip wheel "setuptools<80,>=77.0.3"
python -m pip install huggingface_hub openai

case "${NEMOCLAW_CUDA_VARIANT}" in
  cu130)
    required_cuda="${NEMOCLAW_CUDA_VARIANT#cu}"
    required_cuda="${required_cuda:0:2}.${required_cuda:2:1}"
    current_cuda="${NEMOCLAW_HOST_CUDA_VERSION:-}"
    if [ -z "$current_cuda" ]; then
      current_cuda="$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version: \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1 || true)"
    fi
    if [ -z "$current_cuda" ]; then
      echo "could not detect CUDA version from host or container nvidia-smi" >&2
      exit 1
    fi
    if ! awk -v current="$current_cuda" -v required="$required_cuda" 'BEGIN { split(current,c,"."); split(required,r,"."); exit !((c[1]+0)>(r[1]+0)||((c[1]+0)==(r[1]+0)&&(c[2]+0)>=(r[2]+0))) }'; then
      if [ "${NEMOCLAW_ALLOW_UNSUPPORTED_DRIVER:-0}" != "1" ]; then
        echo "NVIDIA driver exposes CUDA ${current_cuda}, but llama.cpp ${NEMOCLAW_CUDA_VARIANT} build needs CUDA ${required_cuda} or newer." >&2
        echo "Update the host NVIDIA driver, set --cuda-variant cpu, or set NEMOCLAW_ALLOW_UNSUPPORTED_DRIVER=1 to force installation." >&2
        exit 1
      fi
    fi
    python -m pip install \
      nvidia-cuda-cccl nvidia-cuda-nvcc nvidia-cuda-runtime nvidia-cuda-nvrtc nvidia-cublas nvidia-curand \
      nvidia-cusolver nvidia-cusparse nvidia-nvjitlink nvidia-nvtx
    cuda_root="/opt/nemoclaw/venv/lib/python3.12/site-packages/nvidia/cu13"
    for lib in "$cuda_root"/lib/*.so.*; do
      base="${lib%%.so.*}.so"
      [ -e "$base" ] || ln -s "${lib##*/}" "$base"
    done
    build_cuda=1
    ;;
  cpu|none|pypi)
    build_cuda=0
    ;;
  *)
    echo "unsupported NEMOCLAW_CUDA_VARIANT: ${NEMOCLAW_CUDA_VARIANT}" >&2
    exit 1
    ;;
esac

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
  install -d -m 0755 /var/lib/nemoclaw/models
  llama_model_path="$(python - "$model_repo" "$gguf_file" <<'PY'
import sys
from huggingface_hub import hf_hub_download
repo, filename = sys.argv[1], sys.argv[2]
print(hf_hub_download(repo_id=repo, filename=filename,
                      local_dir="/var/lib/nemoclaw/models",
                      local_dir_use_symlinks=False))
PY
)"
fi

llama_tag="${NEMOCLAW_LLAMA_CPP_TAG:-b9803}"
rm -rf /opt/nemoclaw/llama.cpp /opt/nemoclaw/llama-build
git clone --depth 1 --branch "$llama_tag" https://github.com/ggml-org/llama.cpp.git /opt/nemoclaw/llama.cpp

cmake_args=(
  -S /opt/nemoclaw/llama.cpp
  -B /opt/nemoclaw/llama-build
  -DCMAKE_BUILD_TYPE=Release
  -DLLAMA_CURL=OFF
)
if [ "$build_cuda" = 1 ]; then
  cuda_root="/opt/nemoclaw/venv/lib/python3.12/site-packages/nvidia/cu13"
  cmake_args+=(
    -DGGML_CUDA=ON
    -DCMAKE_CUDA_COMPILER="${cuda_root}/bin/nvcc"
    -DCUDAToolkit_ROOT="${cuda_root}"
    -DCMAKE_EXE_LINKER_FLAGS="-L${cuda_root}/lib -Wl,-rpath,${cuda_root}/lib"
    -DCMAKE_SHARED_LINKER_FLAGS="-L${cuda_root}/lib -Wl,-rpath,${cuda_root}/lib"
  )
fi
cmake "${cmake_args[@]}"
cmake --build /opt/nemoclaw/llama-build --config Release -j"$(nproc)" --target llama-server
install -m 0755 /opt/nemoclaw/llama-build/bin/llama-server /opt/nemoclaw/llama-server

{
  printf 'NEMOCLAW_MODEL=%q\n' "$NEMOCLAW_MODEL"
  printf 'NEMOCLAW_LLAMA_MODEL_PATH=%q\n' "$llama_model_path"
  printf 'NEMOCLAW_CHARACTER_NAME=%q\n' "$NEMOCLAW_CHARACTER_NAME"
  printf 'NEMOCLAW_API_HOST=%q\n' "$NEMOCLAW_API_HOST"
  printf 'NEMOCLAW_API_PORT=%q\n' "$NEMOCLAW_API_PORT"
  printf 'NEMOCLAW_MAX_MODEL_LEN=%q\n' "$NEMOCLAW_MAX_MODEL_LEN"
  printf 'NEMOCLAW_LLAMA_N_GPU_LAYERS=%q\n' "$NEMOCLAW_LLAMA_N_GPU_LAYERS"
  printf 'NEMOCLAW_CUDA_VARIANT=%q\n' "$NEMOCLAW_CUDA_VARIANT"
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
