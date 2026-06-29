#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"
CONTROL_SERVICE="${NEMOCLAW_SERVICE_NAME:-nemoclaw}"
INFERENCE_SERVICE="${NEMOCLAW_INFERENCE_SERVICE_NAME:-inference}"

cd "$PROJECT_DIR"

echo "== host docker socket =="
ls -l /var/run/docker.sock || true
stat -c 'sock gid=%g mode=%a owner=%u:%g path=%n' /var/run/docker.sock || true
getent group docker || true
echo

echo "== compose config (group_add + volumes) =="
docker compose -f "$COMPOSE_FILE" config | awk '
  /group_add:/ {show=1}
  show {print}
  /environment:/ && show {show=0}
' || true
echo

echo "== compose status =="
docker compose -f "$COMPOSE_FILE" ps || true
echo

echo "== bring stack up =="
NEMOCLAW_MAX_MODEL_LEN="${NEMOCLAW_MAX_MODEL_LEN:-32768}" \
NEMOCLAW_LLAMA_N_GPU_LAYERS="${NEMOCLAW_LLAMA_N_GPU_LAYERS:-0}" \
docker compose -f "$COMPOSE_FILE" up -d --force-recreate --build
echo

echo "== wait for gateway =="
for _ in $(seq 1 60); do
  if docker compose -f "$COMPOSE_FILE" logs --tail=40 "$CONTROL_SERVICE" | grep -Eq 'gateway ready|socket mode connected'; then
    break
  fi
  sleep 2
done
docker compose -f "$COMPOSE_FILE" logs --tail=80 "$CONTROL_SERVICE" | grep -E 'gateway|ready|socket mode connected|permission denied|Failed to inspect sandbox image|error|failed' || true
echo

echo "== service user/groups =="
docker compose -f "$COMPOSE_FILE" exec -T "$CONTROL_SERVICE" bash -lc '
  set -euo pipefail
  echo "id:"
  id
  echo "---"
  echo "docker.sock:"
  ls -l /var/run/docker.sock
  stat -c "sock gid=%g mode=%a owner=%u:%g path=%n" /var/run/docker.sock
  echo "---"
  echo "groups:"
  getent group docker || true
  getent group "$(stat -c %g /var/run/docker.sock)" || true
  echo "---"
  echo "docker ps:"
  docker ps --format "{{.ID}} {{.Image}}" | head -n 5
' || true
echo

echo "== inference models =="
docker compose -f "$COMPOSE_FILE" exec -T "$INFERENCE_SERVICE" curl -fsS http://127.0.0.1:8000/v1/models || true
echo

echo "== tail gateway log =="
docker compose -f "$COMPOSE_FILE" logs --tail=120 "$CONTROL_SERVICE" || true
