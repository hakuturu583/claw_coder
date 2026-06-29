#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"
CONTROL_SERVICE="${NEMOCLAW_SERVICE_NAME:-nemoclaw}"

cd "$PROJECT_DIR"

echo "== host socket =="
ls -l /var/run/docker.sock || true
stat -c 'sock gid=%g mode=%a owner=%u:%g path=%n' /var/run/docker.sock || true
getent group docker || true
echo

echo "== compose group_add =="
docker compose -f "$COMPOSE_FILE" config | awk '
  /group_add:/ {show=1}
  show {print}
  /environment:/ && show {show=0}
' || true
echo

echo "== service status =="
docker compose -f "$COMPOSE_FILE" ps || true
echo

echo "== container identity =="
docker compose -f "$COMPOSE_FILE" exec -T -u nemoclaw "$CONTROL_SERVICE" bash -lc '
  set -euo pipefail
  echo "id:"
  id
  echo "---"
  echo "/var/run/docker.sock:"
  ls -l /var/run/docker.sock
  stat -c "sock gid=%g mode=%a owner=%u:%g path=%n" /var/run/docker.sock
  echo "---"
  echo "groups:"
  getent group docker || true
  getent group "$(stat -c %g /var/run/docker.sock)" || true
  echo "---"
  echo "groups for nemoclaw:"
  id -nG
  echo "---"
  echo "docker ps:"
  docker ps --format "{{.ID}} {{.Image}}" | head -n 5
' || true
echo

echo "== gateway logs =="
docker compose -f "$COMPOSE_FILE" logs --tail=80 "$CONTROL_SERVICE" | grep -E 'gateway|ready|socket mode connected|Failed to inspect sandbox image|permission denied|error|failed' || true
