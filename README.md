# nemoclaw

`nemoclaw` builds a Docker Compose based local inference runtime for NemoClaw/OpenClaw-style coding agents. It splits the control plane and the model server into separate containers: `nemoclaw` runs the OpenClaw gateway and keeps the persistent OpenClaw state, and `inference` runs a prebuilt `llama.cpp` server image against `deepreinforce-ai/Ornith-1.0-35B-GGUF` as a local OpenAI-compatible endpoint. The server starts with `--jinja`, which is the `llama.cpp` side required for tool/function-call style prompts. The default character name is `Clawくん`.

The runtime keeps container state in named volumes:

- `/home/nemoclaw` for user-owned persistent runtime state
- `/home/nemoclaw/.openclaw/skills` for persistent OpenClaw skills
- `/home/nemoclaw/.openclaw/openclaw.json` for the gateway config
- `/home/nemoclaw/.openclaw/workspace` for OpenClaw's default workspace and
  default AGENTS instructions
- `/var/lib/nemoclaw/models` for Hugging Face model files
- `/var/lib/nemoclaw/huggingface` for the Hugging Face cache

The `nemoclaw` control container runs as the `nemoclaw` user at runtime. That keeps shell state and skill data separate from root while still letting the bootstrap/install steps run as root.

The OpenClaw agent workspace lives in `/home/nemoclaw/.openclaw/workspace`. The default OpenClaw agent instructions are mounted there from `openclaw/AGENTS.md`. The `repositories/` directory is bind-mounted into the `nemoclaw` control container at `/workspace/repositories`, and the image includes `gh` so you can run GitHub CLI commands from inside that container against any checkout under that directory.

If you want `gh` to work without running `gh auth login` inside the container, set `GH_TOKEN` or `GITHUB_TOKEN` in `.env` or the host environment. The control container forwards those variables and stores `gh` state under `/home/nemoclaw`.

If you need local git checkouts, keep them under `repositories/` in this repo root. That path is ignored by git, so it is safe for throwaway or mirrored clones used by the control container.

If a local `.env` file exists next to the command you run, it is sourced before option parsing. Set `NEMOCLAW_ENV_FILE` to point at another dotenv file, or set it to `none` to disable the auto-load.

## What It Creates

- Docker Compose project: `nemoclaw-vllm`
- Control container: `nemoclaw`
- Inference container: `inference`
- Persistent user home for NemoClaw/OpenClaw: `/home/nemoclaw`
- Persistent OpenClaw skill directory: `/home/nemoclaw/.openclaw/skills`
- Persistent OpenClaw gateway config: `/home/nemoclaw/.openclaw/openclaw.json`
- Persistent Hugging Face model directory: `/var/lib/nemoclaw/models`
- Persistent Hugging Face cache: `/var/lib/nemoclaw/huggingface`
- Optional host-local proxy port: `--host-port`
- Local agent endpoint config:
  - `/opt/nemoclaw/openai.env`

Default model settings:

```text
model:     deepreinforce-ai/Ornith-1.0-35B-GGUF:Q4_K_M
runtime:   llama.cpp
endpoint:  http://127.0.0.1:8000/v1
```

## Requirements

- Docker Engine with the Compose v2 plugin
- Enough RAM/VRAM for the selected GGUF quant
- NVIDIA Container Toolkit if GPU inference is required
- NVIDIA driver exposing CUDA 12.8 or newer for the default `llama.cpp` CUDA server image
- Network access from the container for apt, pip, Hugging Face, and model downloads

Check the host:

```bash
bin/setup_nemoclaw.bash doctor
```

## Quick Start

```bash
chmod +x bin/setup_nemoclaw.bash
bin/setup_nemoclaw.bash up
bin/setup_nemoclaw.bash test
```

If you want a smaller model for low-VRAM testing, run:

```bash
bin/setup_nemoclaw.bash --ornith-size 9b up
```

You can also run `docker compose up` directly. On the first start, a lightweight model-init service will download the GGUF file into the persistent model volume, the inference container will start the prebuilt `llama.cpp` CUDA 12 server image, and the control container will wait for inference, write `~/.openclaw/openclaw.json`, and start `openclaw gateway`.

For a gated/private download:

```bash
export HF_TOKEN=...
bin/setup_nemoclaw.bash --pass-hf-token up
```

You can keep credentials outside git in a local `.env` file:

```bash
cp .env.example .env
```

Put `GH_TOKEN` or `GITHUB_TOKEN` in that `.env` file if you want `gh` to work inside the `nemoclaw` container without an interactive login. Set `NEMOCLAW_CHARACTER_NAME=Clawくん` there if you want to override the default character name used by the gateway.
Set `NEMOCLAW_MODEL=deepreinforce-ai/Ornith-1.0-9B-GGUF:Q4_K_M` in `.env` if you want the smaller model for local testing; the compose stack and the setup script both read that value directly.
If a model needs a non-default chat template for tool use, set `NEMOCLAW_LLAMA_CHAT_TEMPLATE` in `.env` and the inference container will pass it through to `llama.cpp`.

The OpenClaw Slack Channel expects `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, and `SLACK_CHANNEL_ID` in `.env` or the host environment.
Brave web search expects `BRAVE_API_KEY` or `BRAVE_SEARCH_API_KEY`.
Set `NEMOCLAW_ORNITH_SIZE=9b` if you want the smaller preset by default when using `bin/setup_nemoclaw.bash` without an explicit `NEMOCLAW_MODEL`.

```bash
bin/setup_nemoclaw.bash configure-openclaw
```

By default the endpoint is only available inside the inference container. Add `--host-port` only when you want a host-local proxy published on `127.0.0.1`.

Clawくん or another coding agent should use:

```text
OPENAI_BASE_URL=http://127.0.0.1:8000/v1
OPENAI_API_KEY=nemoclaw-local
OPENAI_MODEL=deepreinforce-ai/Ornith-1.0-35B-GGUF:Q4_K_M
```

## Common Operations

```bash
bin/setup_nemoclaw.bash status
bin/setup_nemoclaw.bash logs
bin/setup_nemoclaw.bash stop
bin/setup_nemoclaw.bash start
bin/setup_nemoclaw.bash shell
bin/setup_nemoclaw.bash destroy
```

`shell` opens a shell in the persistent `nemoclaw` control container. That is where OpenClaw skill data and other per-user state should live. OpenClaw skills are stored under `/home/nemoclaw/.openclaw/skills`, and the OpenClaw workspace plus default AGENTS instructions live under `/home/nemoclaw/.openclaw/workspace`.

From that shell, you can work directly in `/workspace/repositories` and use `git` or `gh` against the mounted checkouts. OpenClaw's own workspace/bootstrap files live under `/home/nemoclaw/.openclaw/workspace`, and the default `AGENTS.md` is mounted there from `openclaw/AGENTS.md`, so repository checkouts stay separate from agent state.

For noninteractive GitHub access, set `GH_TOKEN` or `GITHUB_TOKEN` in `.env` before starting the container.

## OpenClaw Gateway

`configure-openclaw` writes `/home/nemoclaw/.openclaw/openclaw.json` with:

```text
gateway.bind = loopback
tools.profile = coding
tools.alsoAllow = ["group:plugins"]
tools.sandbox.tools.alsoAllow = ["group:plugins"]
tools.web.search.provider = brave
tools.web.search.maxResults = 5
plugins.entries.brave.enabled = true
plugins.entries.workboard.enabled = true
agents.defaults.workspace = /home/nemoclaw/.openclaw/workspace
models.providers.local.baseUrl = http://inference:8000/v1
models.providers.local.apiKey = nemoclaw-local
channels.slack.enabled = true
channels.slack.mode = socket
channels.slack.botToken = env:SLACK_BOT_TOKEN
channels.slack.appToken = env:SLACK_APP_TOKEN
channels.slack.channels.<id>.allow = true
channels.slack.channels.<id>.requireMention = false
```

The gateway reads its Slack credentials and Brave Search key from the container environment. The control container waits for inference to answer `/v1/models`, writes the config, and then starts `openclaw gateway` as the `nemoclaw` user.
The Brave plugin backs web search, and the Workboard plugin is enabled so OpenClaw Kanban-style task tracking is available inside OpenClaw. Plugin-owned tools are added through the main tool profile without removing the built-in coding tools.

## Tuning

Use CLI options or `NEMOCLAW_*` environment variables:

```bash
bin/setup_nemoclaw.bash \
  --instance nemoclaw-qwen36 \
  --gpu-id all \
  --n-gpu-layers 999 \
  --max-model-len 32768 \
  up
```

Expose the endpoint to the host only when explicitly needed:

```bash
bin/setup_nemoclaw.bash --host-port 18000 create
curl http://127.0.0.1:18000/v1/models
```

Disable GPU attachment:

```bash
bin/setup_nemoclaw.bash --gpu-id none up
```

Override the llama.cpp server image:

```bash
NEMOCLAW_LLAMA_IMAGE=ghcr.io/ggml-org/llama.cpp:server-cuda12 bin/setup_nemoclaw.bash up
```

Choose the smaller Ornith model preset:

```bash
bin/setup_nemoclaw.bash --ornith-size 9b up
```

The default inference backend is the prebuilt `llama.cpp` CUDA 12 server image. Override `NEMOCLAW_LLAMA_IMAGE` if you need a different `llama.cpp` server tag, such as a CPU-only image.

Tune GPU offload:

```bash
bin/setup_nemoclaw.bash --n-gpu-layers 999 up
```

## Notes

The `model-init` service resolves the GGUF file from the `repo_id:quant` form through Hugging Face Hub, and the inference container starts `llama-server` with the resulting local file path. The Hugging Face download cache and the local model directory are both backed by named Docker volumes, so downloads survive container recreation.

The persistent `nemoclaw` user is there so OpenClaw skill data and other per-user state can live across container rebuilds. OpenClaw skill data survives via the `/home/nemoclaw/.openclaw/skills` volume, and the gateway config survives via `/home/nemoclaw/.openclaw/openclaw.json`.

The control container can also be used for GitHub operations because the repository is mounted in-place and `gh` is installed in the image.

Sources used while choosing defaults:

- llama.cpp releases: https://github.com/ggml-org/llama.cpp/releases
- Ornith GGUF model page: https://huggingface.co/deepreinforce-ai/Ornith-1.0-35B-GGUF
- NVIDIA Container Toolkit: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/
