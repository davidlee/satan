"""Bundle + manifest loaders consumed by the run loop.

`bundle.json` and `manifest.json` are written into the run directory by
the broker before spawning the harness. The harness reads them once at
startup.  `build_system_prompt` is a passthrough: the broker has already
rendered the full system prompt (scaffold + mode + bundle-section
framing).
"""

from __future__ import annotations

import json
import os


def load_bundle(run_dir: str) -> dict:
    with open(os.path.join(run_dir, "bundle.json"), encoding="utf-8") as f:
        return json.load(f)


def load_manifest(run_dir: str) -> dict:
    with open(os.path.join(run_dir, "manifest.json"), encoding="utf-8") as f:
        return json.load(f)


def build_system_prompt(bundle: dict) -> str:
    # `bundle["prompt"]` is the fully-rendered system prompt — scaffold,
    # mode prompt, and every context-section (`# Now`, `# Today (raw)`,
    # `# Source files`) assembled by the broker. The harness consumes
    # it verbatim and adds no model-facing prose.
    return bundle["prompt"]


def build_tools(manifest: dict) -> list[dict]:
    """Return the manifest's tools list, validated minimally.

    The broker writes the full OpenAI-tools JSON Schema for every
    allowed tool (plus the synthetic `satan_final`) into
    `manifest.json["tools"]`. The harness consumes that list verbatim —
    descriptions, parameters, and all — so no canonical model-facing
    text lives in this file.
    """
    tools = manifest.get("tools")
    if not tools:
        raise RuntimeError("manifest missing 'tools' array")
    return list(tools)
