# nemolxd

`nemolxd` builds an LXD-isolated local inference container for NemoClaw/OpenClaw-style coding agents, then runs `unsloth/Qwen3.6-35B-A3B-GGUF` through llama.cpp as a local OpenAI-compatible endpoint.

The important security property is that setup and runtime commands enter the container with `env -i`. Host environment variables are not forwarded by default. If a Hugging Face token is needed, pass it explicitly with `--pass-hf-token`; only `HF_TOKEN`/`HUGGING_FACE_HUB_TOKEN` is copied into a root-only file inside the container.

If a local `.env` file exists next to the command you run, it is sourced before option parsing. Set `NEMOLXD_ENV_FILE` to point at another dotenv file, or set it to `none` to disable the auto-load.

The same explicit-forwarding rule applies to optional OpenClaw integrations. Use `--pass-brave-search` and `--pass-slack` to copy only the supported Brave Search and Slack variables into a root-only file inside the container.

## What It Creates

- LXD container: `nemoclaw-vllm`
- LXD nesting settings for sandbox-friendly inner runtimes
- Optional GPU device: defaults to `id=nvidia.com/gpu=all`
- No host-local proxy by default; add `--host-port` only when needed
- llama.cpp systemd service: `nemolxd-llama.service`
- Local agent endpoint config inside the container:
  - `/opt/nemoclaw/openai.env`
  - `/opt/nemoclaw/agent.json`
  - `/opt/nemoclaw/integrations.env`

Default model settings:

```text
model:     unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q4_K_M
runtime:   llama.cpp
endpoint:  http://127.0.0.1:8000/v1
```

## Requirements

- Linux host with LXD initialized for the current user
- Enough RAM/VRAM for the selected GGUF quant
- NVIDIA or AMD GPU exposed through LXD CDI if GPU inference is required
- NVIDIA driver exposing CUDA 13.0 or newer for the default llama.cpp `cu130` CUDA build
- Network access from the container for apt, pip, Hugging Face, and model downloads

Check the host:

```bash
bin/nemolxd doctor
```

## Quick Start

```bash
chmod +x bin/nemolxd
bin/nemolxd up
bin/nemolxd test
```

For a gated/private download:

```bash
export HF_TOKEN=...
bin/nemolxd --pass-hf-token up
```

You can keep credentials outside git in a local `.env` file:

```bash
cp .env.example .env
```

To enable Brave Search for web search and Slack for user communication:

```bash
bin/nemolxd --pass-brave-search --pass-slack configure-integrations
```

By default the endpoint is available only inside the LXD container. This avoids IDE or remote-port-forwarding features opening browser authentication pages.

NemoClaw or another coding agent should use:

```text
OPENAI_BASE_URL=http://127.0.0.1:8000/v1
OPENAI_API_KEY=nemolxd-local
OPENAI_MODEL=unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q4_K_M
```

## Common Operations

```bash
bin/nemolxd status
bin/nemolxd logs
bin/nemolxd stop
bin/nemolxd start
bin/nemolxd shell
bin/nemolxd destroy
```

No browser login or external setup flow is required by this tool. It only creates a local OpenAI-compatible llama.cpp endpoint in LXD.

`shell` also uses a scrubbed environment, so it is suitable for checking what the container can see without leaking the host session.

## OpenClaw Integrations

`configure-integrations` writes `/opt/nemoclaw/integrations.env` with:

```text
OPENCLAW_SEARCH_PROVIDER=brave
OPENCLAW_COMMUNICATION_PROVIDER=slack
BRAVE_SEARCH_API_KEY=...
SLACK_BOT_TOKEN=...
SLACK_APP_TOKEN=...
SLACK_SIGNING_SECRET=...
SLACK_CLIENT_ID=...
SLACK_CLIENT_SECRET=...
SLACK_CHANNEL_ID=...
SLACK_TEAM_ID=...
```

Only variables present in the host environment and enabled by the matching pass-through flag are copied. The file is mode `0600` and is also symlinked at `/opt/nemolxd/integrations.env` for runtime helpers. `agent.json` records Brave Search and Slack as the configured OpenClaw integrations and points clients at this env file.

## Tuning

Use CLI options or `NEMOLXD_*` environment variables:

```bash
bin/nemolxd \
  --instance nemoclaw-qwen36 \
  --gpu-id nvidia.com/gpu=0 \
  --n-gpu-layers 999 \
  --max-model-len 32768 \
  up
```

Expose the endpoint to the host only when explicitly needed:

```bash
bin/nemolxd --host-port 18000 create
curl http://127.0.0.1:18000/v1/models
```

Disable GPU attachment:

```bash
bin/nemolxd --gpu-id none up
```

Install a pinned llama.cpp release tag:

```bash
bin/nemolxd --llama-cpp-tag b9803 up
```

Choose the llama.cpp CUDA build variant:

```bash
bin/nemolxd --cuda-variant cu130 up
```

The default builds llama.cpp `b9803` with CUDA 13.0 support, which expects hosts whose `nvidia-smi` reports `CUDA Version: 13.0` or newer. Use `--cuda-variant cpu` to build without CUDA offload.

Tune GPU offload:

```bash
bin/nemolxd --n-gpu-layers 999 up
```

```bash
bin/nemolxd install
bin/nemolxd start
```

## Notes

The LXD container writes an OpenAI-compatible endpoint config for NemoClaw/OpenClaw-style clients:

```text
OPENAI_BASE_URL=http://127.0.0.1:8000/v1
OPENAI_API_KEY=nemolxd-local
OPENAI_MODEL=unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q4_K_M
```

This means local agents inside the LXD container see the llama.cpp endpoint directly. The host gets no listening proxy unless `--host-port` is provided.

The tool uses the `repo_id:quant_type` form to resolve the single GGUF file through Hugging Face Hub, then starts `llama-server` with the local file path. The default CUDA build uses Python-packaged NVIDIA CUDA 13 build components inside the isolated container.

LXD GPU passthrough is configured with a `gpu` device. By default the tool uses the CDI identifier `nvidia.com/gpu=all`; change it with `--gpu-id nvidia.com/gpu=0`, `--gpu-id amd.com/gpu=0`, or `--gpu-id auto` depending on the host.

Sources used while choosing defaults:

- llama.cpp releases: https://github.com/ggml-org/llama.cpp/releases
- LXD GPU device documentation: https://canonical.com/lxd/docs/latest/reference/devices_gpu/
- Unsloth Qwen3.6 GGUF model page: https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF
