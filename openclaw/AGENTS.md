# OpenClaw Default AGENTS

This file defines the default behavior for OpenClaw agents when no repo-specific
instructions are available yet.

## Default Behavior

- Treat repo selection as optional at the beginning of a task.
- Do not assume a repository is present until the user names one or the task
  explicitly targets a checkout.
- For research, discussion, planning, and evaluation tasks, operate in a
  repo-agnostic mode.
- Only read repo-local `AGENTS.md` files after a specific checkout has been
  selected.

## Workspace Rules

- Keep OpenClaw workspace state separate from git checkouts.
- Use `/home/nemoclaw/.openclaw` for OpenClaw-standard settings, bootstrap
  files, skills, and per-agent notes.
- Use `/home/nemoclaw` for user-owned persistent runtime state that should
  survive container rebuilds.
- Keep `repositories/` reserved for checked-out target repos.

## State Layout

- `/home/nemoclaw/.openclaw/skills` for persistent OpenClaw skills.
- `/home/nemoclaw/.openclaw/openclaw.json` for gateway and tool policy.
- `/home/nemoclaw/.openclaw/workspace` for the OpenClaw agent workspace and
  default AGENTS instructions.
- `/home/nemoclaw/.claw_coder/logs` for persistent gateway logs, session
  transcripts, and tool/function-call records.
- `agents.defaults.compaction.reserveTokensFloor` is set high enough to keep
  enough reply headroom during automatic compaction.
- `/home/nemoclaw` for user-scoped runtime data that should not live in git.

## Task Handling

- If the task is repo-agnostic, answer from the shared workspace context.
- If the task targets a specific repo, clone or open that repo under
  `repositories/` and then read that repo's `AGENTS.md`.
- If multiple repos are involved, keep them isolated under separate checkout
  directories.

## Safety

- Do not create or modify repo-local instruction files unless the task is
  explicitly about that repo.
- Prefer explicit user intent over implicit workspace assumptions.
