# nemoclaw

`nemoclaw` builds a Docker Compose based local inference runtime for NemoClaw/OpenClaw-style coding agents, then runs `deepreinforce-ai/Ornith-1.0-35B-GGUF` through llama.cpp as a local OpenAI-compatible endpoint.

The runtime keeps the container state in named volumes:

- `/home/nemoclaw` for Codex/NemoClaw state, including `~/.codex/skills`
- `/var/lib/nemoclaw/models` for Hugging Face model files
- `/var/lib/nemoclaw/huggingface` for the Hugging Face cache

The container runs as the `nemoclaw` user at runtime. That keeps shell state and skills separate from root while still letting the bootstrap/install steps run as root.

If a local `.env` file exists next to the command you run, it is sourced before option parsing. Set `NEMOCLAW_ENV_FILE` to point at another dotenv file, or set it to `none` to disable the auto-load.

The same explicit-forwarding rule applies to optional OpenClaw integrations. Use `--pass-brave-search` and `--pass-slack` to copy only the supported Brave Search and Slack variables into the container setup.

## What It Creates

- Docker Compose project: `nemoclaw-vllm`
- Persistent user home for NemoClaw/Codex: `/home/nemoclaw`
- Persistent Hugging Face model directory: `/var/lib/nemoclaw/models`
- Persistent Hugging Face cache: `/var/lib/nemoclaw/huggingface`
- Optional host-local proxy port: `--host-port`
- Local agent endpoint config:
  - `/opt/nemoclaw/openai.env`
  - `/opt/nemoclaw/agent.json`
  - `/opt/nemoclaw/integrations.env`

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
- NVIDIA driver exposing CUDA 13.0 or newer for the default llama.cpp `cu130` CUDA build
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

For a gated/private download:

```bash
export HF_TOKEN=...
bin/setup_nemoclaw.bash --pass-hf-token up
```

You can keep credentials outside git in a local `.env` file:

```bash
cp .env.example .env
```

To enable Brave Search for web search and Slack for user communication:

```bash
bin/setup_nemoclaw.bash --pass-brave-search --pass-slack configure-integrations
```

By default the endpoint is only available inside the container. Add `--host-port` only when you want a host-local proxy published on `127.0.0.1`.

NemoClaw or another coding agent should use:

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

`shell` opens a shell as the persistent `nemoclaw` user. That is where Codex skills and other per-user state should live.

## OpenClaw Integrations

`configure-integrations` writes `/opt/nemoclaw/integrations.env` with:

```text
OPENCLAW_SEARCH_PROVIDER=brave
OPENCLAW_COMMUNICATION_PROVIDER=slack
BRAVE_SEARCH_API_KEY=...
BRAVE_API_KEY=...
SLACK_BOT_TOKEN=...
SLACK_APP_TOKEN=...
SLACK_SIGNING_SECRET=...
SLACK_CLIENT_ID=...
SLACK_CLIENT_SECRET=...
SLACK_CHANNEL_ID=...
SLACK_TEAM_ID=...
```

Only variables present in the host environment and enabled by the matching pass-through flag are copied. The file is mode `0600` and is also symlinked at `/opt/nemoclaw/integrations.env` for runtime helpers. `agent.json` records Brave Search and Slack as the configured OpenClaw integrations and points clients at this env file.

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

Install a pinned llama.cpp release tag:

```bash
bin/setup_nemoclaw.bash --llama-cpp-tag b9803 up
```

Choose the llama.cpp CUDA build variant:

```bash
bin/setup_nemoclaw.bash --cuda-variant cu130 up
```

The default builds llama.cpp `b9803` with CUDA 13.0 support, which expects hosts whose `nvidia-smi` reports `CUDA Version: 13.0` or newer. Use `--cuda-variant cpu` to build without CUDA offload.

Tune GPU offload:

```bash
bin/setup_nemoclaw.bash --n-gpu-layers 999 up
```

## Notes

The tool resolves the GGUF file from the `repo_id:quant` form through Hugging Face Hub, then starts `llama-server` with the local file path. The Hugging Face download cache and the local model directory are both backed by named Docker volumes, so downloads survive container recreation.

The persistent `nemoclaw` user is there so Codex skills and other per-user state can live across container rebuilds.

Sources used while choosing defaults:

- llama.cpp releases: https://github.com/ggml-org/llama.cpp/releases
- Ornith GGUF model page: https://huggingface.co/deepreinforce-ai/Ornith-1.0-35B-GGUF
- NVIDIA Container Toolkit: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/
