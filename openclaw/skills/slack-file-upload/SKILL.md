---
name: slack-file-upload
description: Send workspace or sandbox files to Slack with the built-in upload-file action.
metadata:
  openclaw:
    requires:
      config:
        - channels.slack.enabled
---

# Slack File Upload

Use this skill when the user wants to send a file, attachment, screenshot, log, or other artifact to Slack.

## Rules

- Slack is a channel, not a standalone tool provider.
- Do not invent or call `slack`, `openclaw:slack:message`, or any other fake Slack tool id.
- Use the Slack channel's built-in `upload-file` action for files.
- If the file lives in the workspace already, upload that exact path.
- If the file only exists in a sandbox or other isolated filesystem, stage it to a readable local path first with the available file, node, or exec tools, then upload it.
- Keep uploads within `channels.slack.mediaMaxMb`.
- If the file is too large, split it or send a compressed or trimmed version.

## Workflow

1. Identify the exact file path or artifact to send.
2. If needed, copy the artifact into a path the agent can read directly.
3. Upload the file with the Slack `upload-file` action.
4. If the user also wants a text reply, send a short Slack message with the upload.

## Notes

- Prefer terse messages when attaching logs or code, so the file remains the source of truth.
- For binary artifacts, avoid pasting raw content into chat unless the upload path is unavailable.
