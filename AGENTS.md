# AGENTS.md

This repository is the `claw_coder` workspace for the NemoClaw/OpenClaw runtime.
Use this file as the repo-local instruction set for agents operating in this checkout.

## Project Layout

- `bin/setup_nemoclaw.bash` is the main entrypoint for setup, start, stop, status, and test flows.
- `docker-compose.yml` defines the runtime services.
- `docker/` contains container entrypoints and bootstrap scripts.
- `repositories/` is intentionally ignored by git and is reserved for checked-out target repos used by the control container.

## Working Rules

- Prefer `bin/setup_nemoclaw.bash` over ad hoc `docker compose` commands when you need a full lifecycle action.
- Keep secrets in `.env`; do not commit them.
- Treat `repositories/` as workspace data, not source for this repo.
- Do not change persistent volume behavior unless the task explicitly asks for it.
- If you modify OpenClaw or runtime behavior, update the matching README section and any example env values.

## Verification

- For compose/runtime changes, verify with `docker compose up` or the relevant `bin/setup_nemoclaw.bash` command.
- For OpenClaw config changes, check `docker logs claw_coder-nemoclaw-1` and confirm the gateway reaches `ready`.
- For inference changes, confirm `curl http://127.0.0.1:8000/v1/models` works inside the inference container.

## Notes

- This repo intentionally keeps the OpenClaw agent workspace separate from `repositories/`.
- If you add repo-specific workflow notes, keep them short and actionable.
