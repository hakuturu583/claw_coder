#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import pathlib
import shlex
import sys

import yaml

DEFAULT_CONFIG_PATHS = (
    pathlib.Path(os.environ.get("NEMOCLAW_MODEL_SETTINGS_PATH", "")) if os.environ.get("NEMOCLAW_MODEL_SETTINGS_PATH") else None,
    pathlib.Path("/opt/nemoclaw/model-settings.yaml"),
    pathlib.Path(__file__).resolve().parent.parent / "config" / "model-settings.yaml",
)

FIELD_TO_ENV = {
    "context_window": "NEMOCLAW_MAX_MODEL_LEN",
    "compaction_reserve_tokens_floor": "NEMOCLAW_COMPACTION_RESERVE_TOKENS_FLOOR",
    "openclaw_max_tokens": "NEMOCLAW_OPENCLAW_MAX_TOKENS",
    "llama_n_gpu_layers": "NEMOCLAW_LLAMA_N_GPU_LAYERS",
    "llama_chat_template": "NEMOCLAW_LLAMA_CHAT_TEMPLATE",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Resolve model-specific runtime settings from YAML.")
    parser.add_argument("--config", help="Path to the model settings YAML file.")
    parser.add_argument("--model", help="Model id to resolve. Defaults to NEMOCLAW_MODEL.")
    parser.add_argument("--format", choices=("shell", "json"), default="shell")
    return parser.parse_args()


def load_config(path: pathlib.Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise SystemExit(f"error: model settings file must contain a mapping: {path}")
    return data


def first_existing_path(paths: tuple[pathlib.Path | None, ...]) -> pathlib.Path:
    for path in paths:
        if path is not None and path.is_file():
            return path
    raise SystemExit("error: model settings YAML was not found")


def resolve_settings(data: dict, model: str) -> dict[str, object]:
    defaults = data.get("defaults", {})
    models = data.get("models", {})
    if not isinstance(defaults, dict) or not isinstance(models, dict):
        raise SystemExit("error: model settings YAML must define mapping-valued defaults and models")
    merged: dict[str, object] = dict(defaults)
    model_settings = models.get(model, {})
    if model_settings and not isinstance(model_settings, dict):
        raise SystemExit(f"error: model settings for {model!r} must be a mapping")
    merged.update(model_settings or {})
    return merged


def coerce_env_value(value: object) -> str:
    if value is None:
        return ""
    return str(value)


def main() -> int:
    args = parse_args()
    model = args.model or os.environ.get("NEMOCLAW_MODEL") or ""
    if not model:
        raise SystemExit("error: model id is required")

    config_path = pathlib.Path(args.config) if args.config else first_existing_path(DEFAULT_CONFIG_PATHS)
    data = load_config(config_path)
    resolved = resolve_settings(data, model)

    result: dict[str, str] = {}
    for field, env_name in FIELD_TO_ENV.items():
        env_value = os.environ.get(env_name, "")
        if env_value != "":
            result[env_name] = env_value
            continue
        resolved_value = coerce_env_value(resolved.get(field, ""))
        if resolved_value != "":
            result[env_name] = resolved_value

    if args.format == "json":
        print(json.dumps(result, sort_keys=True))
        return 0

    for key in sorted(result):
        print(f"export {key}={shlex.quote(result[key])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
