---
name: sandbox-docker
description: Build and refresh Docker-backed OpenClaw sandboxes for session-isolated work.
metadata:
  openclaw:
    requires:
      config:
        - agents.defaults.sandbox.mode
---

# Docker Sandbox

Use this skill when the current task needs a fresh per-session sandbox or a fast, Docker-prepared environment.

## Rules

- Treat sandboxes as session-scoped unless the user explicitly asks for broader reuse.
- Prefer the repo helper command `bin/setup_nemoclaw.bash sandbox-image` to build the reusable sandbox image.
- When running from an OpenClaw turn, invoke that helper with the built-in `exec` tool on `host=gateway` so the command executes where Docker is available.
- Use `openclaw sandbox explain --json` to inspect the active sandbox shape before changing anything.
- Use `openclaw sandbox recreate --session <sessionKey>` when the sandbox image or config changes and you need the new container immediately.
- Keep the default sandbox image lightweight and cache-friendly.

## Workflow

1. Build or refresh the sandbox image with `exec` on `host=gateway`:
   `bin/setup_nemoclaw.bash sandbox-image`.
2. Recreate the affected session sandbox with `openclaw sandbox recreate --session <sessionKey>`.
3. Verify the resulting policy with `openclaw sandbox explain --json`.
4. If a task needs more packages, extend the sandbox Dockerfile instead of installing ad hoc packages repeatedly in the session container.

## Notes

- Session sandboxes should be disposable.
- Use the sandbox image for repeatable tool availability, not for long-lived host state.
