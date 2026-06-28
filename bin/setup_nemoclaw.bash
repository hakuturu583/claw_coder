#!/usr/bin/env bash
set -euo pipefail

PROGRAM="${0##*/}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"
CONTROL_SERVICE="${NEMOCLAW_SERVICE_NAME:-nemoclaw}"
INFERENCE_SERVICE="${NEMOCLAW_INFERENCE_SERVICE_NAME:-inference}"
MODEL_INIT_SERVICE="${NEMOCLAW_MODEL_INIT_SERVICE_NAME:-model-init}"

load_env_file() {
  local file="${1:-}"
  [[ -n "$file" && "$file" != "none" && -f "$file" ]] || return 0
  set -a
  . "$file"
  set +a
}

ENV_FILE="${NEMOCLAW_ENV_FILE:-.env}"
if [[ -n "$ENV_FILE" && "$ENV_FILE" != "none" ]]; then
  load_env_file "$ENV_FILE"
fi

INSTANCE="${NEMOCLAW_INSTANCE:-nemoclaw-vllm}"
IMAGE="${NEMOCLAW_IMAGE:-ubuntu:24.04}"
ORNITH_SIZE="${NEMOCLAW_ORNITH_SIZE:-35b}"
case "$ORNITH_SIZE" in
  35b)
    ORNITH_MODEL_DEFAULT="deepreinforce-ai/Ornith-1.0-35B-GGUF:Q4_K_M"
    ORNITH_TOKENIZER_DEFAULT="deepreinforce-ai/Ornith-1.0-35B-GGUF"
    ORNITH_HF_CONFIG_DEFAULT="deepreinforce-ai/Ornith-1.0-35B-GGUF"
    ;;
  9b)
    ORNITH_MODEL_DEFAULT="deepreinforce-ai/Ornith-1.0-9B-GGUF:Q4_K_M"
    ORNITH_TOKENIZER_DEFAULT="deepreinforce-ai/Ornith-1.0-9B-GGUF"
    ORNITH_HF_CONFIG_DEFAULT="deepreinforce-ai/Ornith-1.0-9B-GGUF"
    ;;
  *)
    die "unsupported ornith size: $ORNITH_SIZE (expected 35b or 9b)"
    ;;
esac

MODEL="${NEMOCLAW_MODEL:-$ORNITH_MODEL_DEFAULT}"
TOKENIZER="${NEMOCLAW_TOKENIZER:-$ORNITH_TOKENIZER_DEFAULT}"
HF_CONFIG_PATH="${NEMOCLAW_HF_CONFIG_PATH:-$ORNITH_HF_CONFIG_DEFAULT}"
HF_OVERRIDES="${NEMOCLAW_HF_OVERRIDES:-}"
GGUF_FILE="${NEMOCLAW_GGUF_FILE:-}"
API_HOST="${NEMOCLAW_API_HOST:-0.0.0.0}"
API_PORT="${NEMOCLAW_API_PORT:-8000}"
HOST_PORT="${NEMOCLAW_HOST_PORT:-none}"
GPU_ID="${NEMOCLAW_GPU_ID:-all}"
TP_SIZE="${NEMOCLAW_TENSOR_PARALLEL_SIZE:-1}"
MAX_MODEL_LEN="${NEMOCLAW_MAX_MODEL_LEN:-32768}"
CUDA_VARIANT="${NEMOCLAW_CUDA_VARIANT:-cu130}"
LLAMA_CPP_TAG="${NEMOCLAW_LLAMA_CPP_TAG:-b9803}"
LLAMA_N_GPU_LAYERS="${NEMOCLAW_LLAMA_N_GPU_LAYERS:-999}"
PASS_HF_TOKEN=0

export INSTANCE IMAGE MODEL TOKENIZER HF_CONFIG_PATH HF_OVERRIDES GGUF_FILE
export API_HOST API_PORT HOST_PORT GPU_ID TP_SIZE MAX_MODEL_LEN CUDA_VARIANT
export LLAMA_CPP_TAG LLAMA_N_GPU_LAYERS
export NEMOCLAW_HOST_CUDA_VERSION="$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version: \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1 || true)"

usage() {
  cat <<EOF
Usage: $PROGRAM [global options] <command>

Build and run a Docker Compose isolated llama.cpp coding-agent runtime.

Global options:
  --instance NAME        Compose project name (default: $INSTANCE)
  --image IMAGE          Base image used by the Dockerfile (default: $IMAGE)
  --model MODEL          GGUF model id/path (default: $MODEL)
  --ornith-size SIZE     Ornith preset size: 35b or 9b (default: $ORNITH_SIZE)
  --tokenizer MODEL      tokenizer repo/path (default: $TOKENIZER)
  --hf-config-path MODEL  Deprecated compatibility option (default: $HF_CONFIG_PATH)
  --hf-overrides JSON    Deprecated compatibility option
  --gguf-file NAME       GGUF filename in the model repo
  --api-port PORT        llama.cpp port inside the container (default: $API_PORT)
  --host-port PORT       Optional host localhost proxy port, or "none" (default: $HOST_PORT)
  --gpu-id ID            Docker GPU request: all, auto, none, or device ids (default: $GPU_ID)
  --tp-size N            Deprecated compatibility option (default: $TP_SIZE)
  --max-model-len N      llama.cpp context size (default: $MAX_MODEL_LEN)
  --cuda-variant NAME    Legacy compatibility option retained for older configs (default: $CUDA_VARIANT)
  --llama-cpp-tag TAG    Legacy compatibility option retained for older configs (default: $LLAMA_CPP_TAG)
  --n-gpu-layers N       llama.cpp GPU offload layers (default: $LLAMA_N_GPU_LAYERS)
  --pass-hf-token        Pass only HF_TOKEN/HUGGING_FACE_HUB_TOKEN into setup
  -h, --help             Show help

Commands:
  init-host              Compose/Docker do not need host initialization
  doctor                 Check host-side requirements
  create                 Create the Compose project and both service containers
  install                Prepare the model cache and inference config
  configure-openclaw     Write the OpenClaw gateway config for the control container
  up                     create + install + start
  start                  Start the Compose service
  stop                   Stop the Compose service
  status                 Show Compose status
  logs                   Follow service logs
  test                   Query /v1/models inside the container, or through host port if enabled
  shell                  Open a scrubbed-env root shell in the control container
  destroy                Delete the Compose project and volumes

Environment overrides use the NEMOCLAW_* variables matching the option names.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

require_docker() {
  have docker || die "docker command is not installed or not on PATH"
  docker info >/dev/null 2>&1 || die "docker daemon is not available"
}

require_compose() {
  docker compose version >/dev/null 2>&1 || die "docker compose v2 is not available"
}

append_compose_env_if_set() {
  local -n target="$1"
  local name value
  shift
  for name in "$@"; do
    value="${!name:-}"
    if [[ -n "$value" ]]; then
      target+=(-e "${name}=${value}")
    fi
  done
}

compose_base_args() {
  printf '%s\n' docker compose -p "$INSTANCE" -f "$COMPOSE_FILE"
}

compose_run_cmd() {
  local -a args=(docker compose -p "$INSTANCE" -f "$COMPOSE_FILE")
  if [[ $# -gt 0 ]]; then
    args+=("$@")
  fi
  "${args[@]}"
}

check_cuda_variant_supported() {
  local variant="$1"
  local required=""
  case "$variant" in
    cpu|none) return 0 ;;
    cu129) required="12.9" ;;
    cu130) required="13.0" ;;
    cu126) required="12.6" ;;
    cu118) required="11.8" ;;
    pypi) return 0 ;;
    *) die "unsupported CUDA variant: $variant" ;;
  esac

  local current="${NEMOCLAW_HOST_CUDA_VERSION:-}"
  [[ -n "$current" ]] || die "could not detect CUDA version from nvidia-smi"
  awk -v current="$current" -v required="$required" 'BEGIN {
    split(current, c, "."); split(required, r, ".");
    exit !((c[1] + 0) > (r[1] + 0) || ((c[1] + 0) == (r[1] + 0) && (c[2] + 0) >= (r[2] + 0)))
  }' || {
    if [[ "${NEMOCLAW_ALLOW_UNSUPPORTED_DRIVER:-0}" == 1 ]]; then
      printf 'warning: CUDA %s is below required %s for %s; continuing because NEMOCLAW_ALLOW_UNSUPPORTED_DRIVER=1\n' "$current" "$required" "$variant" >&2
      return 0
    fi
    die "NVIDIA driver exposes CUDA $current, but llama.cpp $variant build needs CUDA $required or newer. Update the host NVIDIA driver, or set --cuda-variant cpu intentionally."
  }
}

gpu_request_value() {
  case "$GPU_ID" in
    none|"") printf '' ;;
    auto|all|nvidia.com/gpu=all) printf 'all' ;;
    nvidia.com/gpu=*) printf '%s' "${GPU_ID#nvidia.com/gpu=}" ;;
    *) printf '%s' "$GPU_ID" ;;
  esac
}

compose_runtime_override_file() {
  local gpu_value
  gpu_value="$(gpu_request_value)"
  if [[ "$HOST_PORT" == "none" || -z "$HOST_PORT" ]] && [[ -z "$gpu_value" ]]; then
    printf '%s\n' ""
    return 0
  fi

  local file
  file="$(mktemp)"
  {
    printf 'services:\n'
    printf '  %s:\n' "$INFERENCE_SERVICE"
    if [[ "$HOST_PORT" != "none" && -n "$HOST_PORT" ]]; then
      printf '    ports:\n'
      printf '      - "127.0.0.1:%s:%s"\n' "$HOST_PORT" "$API_PORT"
    fi
    if [[ -n "$gpu_value" ]]; then
      printf '    gpus: all\n'
      if [[ "$gpu_value" != "all" ]]; then
        printf '    environment:\n'
        printf '      NVIDIA_VISIBLE_DEVICES: "%s"\n' "$gpu_value"
      fi
    fi
  } >"$file"
  printf '%s\n' "$file"
}

compose() {
  compose_run_cmd "$@"
}

compose_with_runtime() {
  local override_file=""
  override_file="$(compose_runtime_override_file)"
  local -a args=(docker compose -p "$INSTANCE" -f "$COMPOSE_FILE")
  if [[ -n "$override_file" ]]; then
    args+=(-f "$override_file")
  fi
  if [[ $# -gt 0 ]]; then
    args+=("$@")
  fi
  local rc=0
  "${args[@]}" || rc=$?
  [[ -n "$override_file" ]] && rm -f "$override_file"
  return "$rc"
}

compose_run_with_env() {
  local -a env_args=()
  append_compose_env_if_set env_args "$@"
  compose run --rm --no-deps --build "${env_args[@]}"
}

cmd_init_host() {
  require_docker
  require_compose
  printf 'Docker Compose does not need host initialization.\n'
}

cmd_doctor() {
  require_docker
  require_compose
  printf 'docker: %s\n' "$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)"
  printf 'compose: %s\n' "$(docker compose version --short 2>/dev/null || docker compose version 2>/dev/null || true)"
  if have nvidia-smi; then
    nvidia-smi -L || true
    check_cuda_variant_supported "$CUDA_VARIANT"
  else
    printf 'nvidia-smi: not found; GPU support can still work if the Docker GPU runtime is configured.\n'
  fi
  printf 'doctor: ok\n'
}

cmd_create() {
  require_docker
  require_compose
  compose_with_runtime up -d --no-start --build
  printf 'created: %s\n' "$INSTANCE"
}

cmd_install() {
  require_docker
  require_compose

  local -a env_args=()
  if [[ "$PASS_HF_TOKEN" == 1 ]]; then
    local token="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
    [[ -n "$token" ]] || die "--pass-hf-token requires HF_TOKEN or HUGGING_FACE_HUB_TOKEN in the host environment"
    env_args+=(-e "HF_TOKEN=${token}" -e "HUGGING_FACE_HUB_TOKEN=${token}")
  fi

  compose run --rm --no-deps --build "${env_args[@]}" \
    --entrypoint /usr/local/bin/install-nemoclaw-inference.sh \
    "$MODEL_INIT_SERVICE"

  printf 'installed isolated llama.cpp runtime in %s\n' "$INSTANCE"
}

cmd_configure_openclaw() {
  require_docker
  require_compose
  compose run --rm --no-deps --build --entrypoint /usr/local/bin/install-openclaw-config.sh "$CONTROL_SERVICE"

  printf 'configured OpenClaw gateway metadata in %s\n' "$INSTANCE"
}

cmd_start() {
  require_docker
  require_compose
  compose_with_runtime up -d --build
  if [[ "$HOST_PORT" == "none" || -z "$HOST_PORT" ]]; then
    printf 'starting inside the container: http://127.0.0.1:%s/v1\n' "$API_PORT"
  else
    printf 'starting: http://127.0.0.1:%s/v1\n' "$HOST_PORT"
  fi
}

wait_for_runtime() {
  if [[ "$HOST_PORT" == "none" || -z "$HOST_PORT" ]]; then
    for _ in $(seq 1 120); do
      if compose exec -T "$INFERENCE_SERVICE" bash -lc 'curl -fsS "http://127.0.0.1:${NEMOCLAW_API_PORT}/v1/models" >/dev/null 2>&1'; then
        break
      fi
      sleep 5
    done
    if ! compose exec -T "$INFERENCE_SERVICE" bash -lc 'curl -fsS "http://127.0.0.1:${NEMOCLAW_API_PORT}/v1/models" >/dev/null 2>&1'; then
      echo "llama.cpp did not become ready at http://127.0.0.1:${API_PORT}/v1/models" >&2
      return 1
    fi
    for _ in $(seq 1 60); do
      local control_id control_status
      control_id="$(compose ps -q "$CONTROL_SERVICE" 2>/dev/null || true)"
      if [[ -n "$control_id" ]]; then
        control_status="$(docker inspect -f '{{.State.Status}}' "$control_id" 2>/dev/null || true)"
        if [[ "$control_status" == "running" ]]; then
          return 0
        fi
      fi
      sleep 2
    done
    echo "OpenClaw gateway did not reach running state" >&2
    return 1
  else
    for _ in $(seq 1 120); do
      if curl -fsS "http://127.0.0.1:${HOST_PORT}/v1/models" >/dev/null 2>&1; then
        break
      fi
      sleep 5
    done
    if ! curl -fsS "http://127.0.0.1:${HOST_PORT}/v1/models" >/dev/null 2>&1; then
      die "llama.cpp did not become ready at http://127.0.0.1:${HOST_PORT}/v1/models"
    fi
    for _ in $(seq 1 60); do
      local control_id control_status
      control_id="$(compose ps -q "$CONTROL_SERVICE" 2>/dev/null || true)"
      if [[ -n "$control_id" ]]; then
        control_status="$(docker inspect -f '{{.State.Status}}' "$control_id" 2>/dev/null || true)"
        if [[ "$control_status" == "running" ]]; then
          return 0
        fi
      fi
      sleep 2
    done
    die "OpenClaw gateway did not reach running state"
  fi
}

cmd_stop() {
  require_docker
  require_compose
  compose stop
}

cmd_status() {
  require_docker
  require_compose
  compose ps
}

cmd_logs() {
  require_docker
  require_compose
  compose logs -f "$CONTROL_SERVICE" "$INFERENCE_SERVICE"
}

cmd_test() {
  require_docker
  require_compose
  if [[ "$HOST_PORT" == "none" || -z "$HOST_PORT" ]]; then
    compose exec -T "$INFERENCE_SERVICE" curl -fsS "http://127.0.0.1:${API_PORT}/v1/models"
  elif have jq; then
    curl -fsS "http://127.0.0.1:${HOST_PORT}/v1/models" | jq .
  else
    have curl || die "curl command is required for host-proxy test"
    curl -fsS "http://127.0.0.1:${HOST_PORT}/v1/models"
  fi
}

cmd_shell() {
  require_docker
  require_compose
  if compose ps -q "$CONTROL_SERVICE" >/dev/null 2>&1 && [[ -n "$(compose ps -q "$CONTROL_SERVICE" 2>/dev/null || true)" ]]; then
    compose exec -u nemoclaw "$CONTROL_SERVICE" bash -l
  else
    compose run --rm --no-deps --build --user root --entrypoint bash "$CONTROL_SERVICE" -lc 'install -d -o nemoclaw -g nemoclaw -m 0755 /home/nemoclaw/.openclaw /home/nemoclaw/.openclaw/skills && exec gosu nemoclaw:nemoclaw bash -l'
  fi
}

cmd_destroy() {
  require_docker
  require_compose
  compose down -v --remove-orphans
}

cmd_up() {
  cmd_create
  cmd_start
  wait_for_runtime
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance) INSTANCE="${2:?missing value}"; shift 2 ;;
    --image) IMAGE="${2:?missing value}"; shift 2 ;;
    --model) MODEL="${2:?missing value}"; shift 2 ;;
    --ornith-size)
      ORNITH_SIZE="${2:?missing value}"
      case "$ORNITH_SIZE" in
        35b)
          MODEL="deepreinforce-ai/Ornith-1.0-35B-GGUF:Q4_K_M"
          TOKENIZER="deepreinforce-ai/Ornith-1.0-35B-GGUF"
          HF_CONFIG_PATH="deepreinforce-ai/Ornith-1.0-35B-GGUF"
          ;;
        9b)
          MODEL="deepreinforce-ai/Ornith-1.0-9B-GGUF:Q4_K_M"
          TOKENIZER="deepreinforce-ai/Ornith-1.0-9B-GGUF"
          HF_CONFIG_PATH="deepreinforce-ai/Ornith-1.0-9B-GGUF"
          ;;
        *)
          die "unsupported ornith size: $ORNITH_SIZE (expected 35b or 9b)"
          ;;
      esac
      shift 2
      ;;
    --tokenizer) TOKENIZER="${2:?missing value}"; shift 2 ;;
    --hf-config-path) HF_CONFIG_PATH="${2:?missing value}"; shift 2 ;;
    --hf-overrides) HF_OVERRIDES="${2:?missing value}"; shift 2 ;;
    --gguf-file) GGUF_FILE="${2:?missing value}"; shift 2 ;;
    --api-port) API_PORT="${2:?missing value}"; shift 2 ;;
    --host-port) HOST_PORT="${2:?missing value}"; shift 2 ;;
    --gpu-id) GPU_ID="${2:?missing value}"; shift 2 ;;
    --tp-size) TP_SIZE="${2:?missing value}"; shift 2 ;;
    --max-model-len) MAX_MODEL_LEN="${2:?missing value}"; shift 2 ;;
    --vllm-version) shift 2 ;;
    --cuda-variant) CUDA_VARIANT="${2:?missing value}"; shift 2 ;;
    --llama-cpp-tag) LLAMA_CPP_TAG="${2:?missing value}"; shift 2 ;;
    --n-gpu-layers) LLAMA_N_GPU_LAYERS="${2:?missing value}"; shift 2 ;;
    --pass-hf-token) PASS_HF_TOKEN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

export INSTANCE IMAGE MODEL TOKENIZER HF_CONFIG_PATH HF_OVERRIDES GGUF_FILE
export API_HOST API_PORT HOST_PORT GPU_ID TP_SIZE MAX_MODEL_LEN CUDA_VARIANT
export LLAMA_CPP_TAG LLAMA_N_GPU_LAYERS
export NEMOCLAW_INSTANCE="$INSTANCE"
export NEMOCLAW_IMAGE="$IMAGE"
export NEMOCLAW_MODEL="$MODEL"
export NEMOCLAW_TOKENIZER="$TOKENIZER"
export NEMOCLAW_HF_CONFIG_PATH="$HF_CONFIG_PATH"
export NEMOCLAW_HF_OVERRIDES="$HF_OVERRIDES"
export NEMOCLAW_GGUF_FILE="$GGUF_FILE"
export NEMOCLAW_API_HOST="$API_HOST"
export NEMOCLAW_API_PORT="$API_PORT"
export NEMOCLAW_HOST_PORT="$HOST_PORT"
export NEMOCLAW_GPU_ID="$GPU_ID"
export NEMOCLAW_TENSOR_PARALLEL_SIZE="$TP_SIZE"
export NEMOCLAW_MAX_MODEL_LEN="$MAX_MODEL_LEN"
export NEMOCLAW_CUDA_VARIANT="$CUDA_VARIANT"
export NEMOCLAW_LLAMA_CPP_TAG="$LLAMA_CPP_TAG"
export NEMOCLAW_LLAMA_N_GPU_LAYERS="$LLAMA_N_GPU_LAYERS"
export NEMOCLAW_HOST_CUDA_VERSION="$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version: \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1 || true)"

COMMAND="${1:-}"
[[ -n "$COMMAND" ]] || {
  usage
  exit 2
}
shift || true

case "$COMMAND" in
  init-host) cmd_init_host "$@" ;;
  doctor) cmd_doctor "$@" ;;
  create) cmd_create "$@" ;;
  install) cmd_install "$@" ;;
  configure-openclaw) cmd_configure_openclaw "$@" ;;
  up) cmd_up "$@" ;;
  start) cmd_start "$@" ;;
  stop) cmd_stop "$@" ;;
  status) cmd_status "$@" ;;
  logs) cmd_logs "$@" ;;
  test) cmd_test "$@" ;;
  shell) cmd_shell "$@" ;;
  destroy) cmd_destroy "$@" ;;
  *)
    die "unknown command: $COMMAND"
    ;;
esac
