# Skill Hub

This directory is baked into the `nemoclaw` image at `/opt/nemoclaw/skill-hub`.
OpenClaw loads it as a lower-precedence skill source through
`skills.load.extraDirs`, so it can provide curated defaults without replacing
the persistent skill directories under `/home/nemoclaw/.openclaw`.

Add shared, image-bundled skills under subdirectories here. Workspace-local or
per-user overrides should live under:

- `/home/nemoclaw/.openclaw/skills`
- `/home/nemoclaw/.openclaw/workspace/skills`
