"""SATAN JSONL protocol validator + wire helpers.

Single-file source of truth for the message-shape contract on the
harness side. Keep in lockstep with `../satan-protocol.el` and
`../../docs/satan/protocol.md`. Shared fixtures at `../protocol/fixtures.json`
drive both this validator's tests and the elisp validator's tests.
"""

from __future__ import annotations

import json
import os
import re
import sys
from typing import Any

TYPES_IN = frozenset({"ready", "log", "tool_call", "final", "error"})
TYPES_OUT = frozenset({"tool_result"})
TOOL_NAME_RE = re.compile(r"\A[a-zA-Z0-9_-]+\Z")


class ProtocolError(Exception):
    def __init__(self, type_: str | None, reason: str):
        self.type = type_
        self.reason = reason
        super().__init__(f"{type_}: {reason}" if type_ else reason)


def _require_string(obj: dict, key: str) -> str | None:
    if key not in obj:
        return f"missing required field: {key}"
    if not isinstance(obj[key], str):
        return f"field {key} must be string"
    return None


def _require_bool(obj: dict, key: str) -> str | None:
    if key not in obj:
        return f"missing required field: {key}"
    if not isinstance(obj[key], bool):
        return f"field {key} must be boolean"
    return None


def _validate_action(a: Any) -> str | None:
    if not isinstance(a, dict):
        return "action must be object"
    if "type" not in a:
        return "action missing type"
    if not isinstance(a["type"], str):
        return "action type must be string"
    return None


def _validate_ready(obj: dict) -> str | None:
    return _require_string(obj, "run_id")


def _validate_log(obj: dict) -> str | None:
    return _require_string(obj, "kind")


def _validate_tool_call(obj: dict) -> str | None:
    e = _require_string(obj, "id") or _require_string(obj, "name")
    if e:
        return e
    if not TOOL_NAME_RE.match(obj["name"]):
        return "field name must match ^[a-zA-Z0-9_-]+$"
    if "args" not in obj:
        return "missing required field: args"
    if not isinstance(obj["args"], dict):
        return "field args must be object"
    return None


def _validate_final(obj: dict) -> str | None:
    e = _require_string(obj, "summary")
    if e:
        return e
    if "actions" not in obj:
        return "missing required field: actions"
    if not isinstance(obj["actions"], list):
        return "field actions must be array"
    for a in obj["actions"]:
        e = _validate_action(a)
        if e:
            return e
    if "reason" in obj and not isinstance(obj["reason"], str):
        return "field reason must be string"
    return None


def _validate_error(obj: dict) -> str | None:
    return _require_string(obj, "error")


def _validate_tool_result(obj: dict) -> str | None:
    e = _require_string(obj, "id") or _require_bool(obj, "ok")
    if e:
        return e
    if obj["ok"] and "result" not in obj:
        return "ok=true requires result"
    if not obj["ok"] and "error" not in obj:
        return "ok=false requires error"
    return None


_DISPATCH = {
    "ready": _validate_ready,
    "log": _validate_log,
    "tool_call": _validate_tool_call,
    "final": _validate_final,
    "error": _validate_error,
    "tool_result": _validate_tool_result,
}


def check(direction: str, obj: dict) -> str | None:
    """Return None on valid, or a reason string on invalid."""
    if direction not in ("in", "out"):
        raise ValueError(f"bad direction: {direction!r}")
    allowed = TYPES_IN if direction == "in" else TYPES_OUT
    if not isinstance(obj, dict):
        return "message must be object"
    if "type" not in obj:
        return "missing required field: type"
    t = obj["type"]
    if not isinstance(t, str):
        return "field type must be string"
    if t not in allowed:
        if t in TYPES_IN or t in TYPES_OUT:
            return f"type {t} not valid for direction {direction}"
        return f"unknown message type: {t}"
    return _DISPATCH[t](obj)


def validate(direction: str, obj: dict) -> None:
    reason = check(direction, obj)
    if reason is not None:
        raise ProtocolError(obj.get("type") if isinstance(obj, dict) else None, reason)


# ----- actions.json shape (Phase 0.3 / 0.4) -----
#
# Mirror of `satan-audit-validate-actions` on the elisp side. The four
# model-action partition keys (`applied`, `staged`, `rejected`, `failed`)
# are each arrays of objects; missing keys are treated as empty (audit-close
# always writes them, but the validator stays lenient so fixtures can omit
# defaults). Optional `pre_spawn` is an array of objects each carrying a
# `kind` string discriminator. Unknown discriminant values are accepted
# gracefully (forward compatibility); only malformed STRUCTURE is rejected.


_ACTION_PARTITIONS = ("applied", "staged", "rejected", "failed")


def _check_pre_spawn(val: Any) -> str | None:
    if not isinstance(val, list):
        return "pre_spawn must be array"
    for i, entry in enumerate(val):
        if not isinstance(entry, dict):
            return f"pre_spawn[{i}] must be object"
        if "kind" not in entry:
            return f"pre_spawn[{i}] missing kind"
        if not isinstance(entry["kind"], str):
            return f"pre_spawn[{i}] kind must be string"
    return None


def check_actions_json(obj: Any) -> str | None:
    """Return None on valid actions.json shape, else a reason string."""
    if not isinstance(obj, dict):
        return "actions must be object"
    for key in _ACTION_PARTITIONS:
        v = obj.get(key, [])
        if not isinstance(v, list):
            return f"{key} must be array"
        for i, entry in enumerate(v):
            if not isinstance(entry, dict):
                return f"{key}[{i}] must be object"
    if "pre_spawn" in obj:
        return _check_pre_spawn(obj["pre_spawn"])
    return None


def validate_actions_json(obj: Any) -> None:
    reason = check_actions_json(obj)
    if reason is not None:
        raise ProtocolError(None, reason)


def fixtures_path() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.normpath(os.path.join(here, "..", "protocol", "fixtures.json"))


def load_fixtures(path: str | None = None) -> list[dict]:
    with open(path or fixtures_path(), encoding="utf-8") as f:
        return json.load(f)["fixtures"]


def emit(obj: dict) -> None:
    validate("in", obj)
    print(json.dumps(obj), flush=True)


def emit_ready(run_id: str) -> None:
    emit({"type": "ready", "run_id": run_id})


def emit_log(payload: dict) -> None:
    emit({"type": "log", **payload})


def emit_error(msg: str) -> None:
    emit({"type": "error", "error": msg})


def emit_final(summary: str, actions: list[dict], reason: str | None = None) -> None:
    rec: dict = {"type": "final", "summary": summary, "actions": actions}
    if reason is not None:
        rec["reason"] = reason
    emit(rec)


def emit_tool_call(call_id: str, name: str, args: dict) -> None:
    emit({"type": "tool_call", "id": call_id, "name": name, "args": args})


def read_tool_result() -> dict:
    """Read one JSON line from stdin; broker sends tool_result here."""
    line = sys.stdin.readline()
    if not line:
        raise RuntimeError("stdin closed before tool_result")
    obj = json.loads(line)
    validate("out", obj)
    return obj
