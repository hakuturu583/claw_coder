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
- Use the OpenClaw workspace for agent state, bootstrap files, and per-agent
  notes.
- Keep `repositories/` reserved for checked-out target repos.

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
