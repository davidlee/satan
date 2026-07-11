"""Unit tests for the SATAN gptel harness.

No network. Stub Provider, stub stdin/stdout, verify protocol shape.
Run: cd satan/harness && python -m unittest test_gptel_harness
"""

from __future__ import annotations

import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bundle  # noqa: E402
import protocol  # noqa: E402
import runloop  # noqa: E402
from providers import build_provider  # noqa: E402
from providers.base import CompletionResult, Provider  # noqa: E402
from providers.deepseek import DeepSeekProvider  # noqa: E402
from providers.openrouter import OpenRouterProvider  # noqa: E402


def _stub_tool_schema(name: str, description: str = "") -> dict:
    return {
        "type": "function",
        "function": {
            "name": name,
            "description": description or f"stub {name}",
            "parameters": {"type": "object", "properties": {}, "required": []},
        },
    }


DEFAULT_MANIFEST_TOOLS = [
    _stub_tool_schema("org_read_context"),
    _stub_tool_schema("org_update_owned_block"),
    _stub_tool_schema("satan_final"),
]


def make_bundle(tmp: str, *, tools=None, timeout_seconds=0, **overrides) -> str:
    bundle_dict = {
        "prompt": "test prompt",
        "mode": "morning",
        "now": {
            "iso_date": "2026-05-19",
            "weekday": "Tuesday",
            "iso_week": "2026-W21",
            "time": "09:00",
            "tz_offset": "+1000",
            "tz_name": "AEST",
        },
        "today_path": "/satan/notes/today.org",
        "today_text": "",
    }
    bundle_dict.update(overrides)
    with open(os.path.join(tmp, "bundle.json"), "w", encoding="utf-8") as f:
        json.dump(bundle_dict, f)
    manifest = {
        "run_id": "test-run",
        "mode": {"name": "morning", "timeout_seconds": timeout_seconds},
        "tools": list(tools) if tools is not None else DEFAULT_MANIFEST_TOOLS,
    }
    with open(os.path.join(tmp, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f)
    return tmp


def emitted_lines(buf: io.StringIO) -> list[dict]:
    return [json.loads(line) for line in buf.getvalue().splitlines() if line.strip()]


class StubProvider(Provider):
    def __init__(self, results: list[CompletionResult]):
        self._results = list(results)
        self.calls: list[dict] = []

    def complete(self, messages, tools, model):
        self.calls.append({"messages": list(messages), "tools": list(tools), "model": model})
        return self._results.pop(0)


class HarnessTests(unittest.TestCase):
    def _run_with(self, provider, *, stdin_lines: list[str] = (), budget: int = 0):
        buf = io.StringIO()
        env = {
            "SATAN_RUN_ID": "test-run",
            "SATAN_BUDGET_TOKENS": str(budget),
            "SATAN_PROVIDER": "openrouter",
            "SATAN_MODEL": "test-model",
            "OPENROUTER_API_KEY": "test-key",
        }
        with tempfile.TemporaryDirectory() as tmp:
            make_bundle(tmp)
            env["SATAN_RUN_DIR"] = tmp
            with mock.patch.dict(os.environ, env, clear=False), \
                 mock.patch.object(runloop, "build_provider",
                                   return_value=(provider, "test-model")), \
                 mock.patch.object(sys, "stdin", io.StringIO("".join(stdin_lines))), \
                 redirect_stdout(buf):
                rc = runloop.run()
        return rc, emitted_lines(buf)

    def test_satan_final_terminates(self):
        provider = StubProvider([
            CompletionResult(
                content="",
                tool_calls=[{"id": "c1", "name": "satan_final",
                             "args": {"summary": "ok", "actions": []}}],
                input_tokens=10, output_tokens=5,
            ),
        ])
        rc, lines = self._run_with(provider)
        self.assertEqual(rc, 0)
        kinds = [m.get("type") for m in lines]
        self.assertIn("ready", kinds)
        self.assertIn("log", kinds)
        self.assertEqual(kinds[-1], "final")
        final = lines[-1]
        self.assertEqual(final["summary"], "ok")
        self.assertEqual(final["actions"], [])

    def test_tool_call_then_final(self):
        provider = StubProvider([
            CompletionResult(
                content="",
                tool_calls=[{"id": "c1", "name": "org_read_context",
                             "args": {"scope": "today"}}],
                input_tokens=10, output_tokens=5,
            ),
            CompletionResult(
                content="",
                tool_calls=[{"id": "c2", "name": "satan_final",
                             "args": {"summary": "done", "actions": []}}],
                input_tokens=20, output_tokens=8,
            ),
        ])
        tool_result = json.dumps({"type": "tool_result", "id": "c1",
                                   "ok": True, "result": {"content": ""}}) + "\n"
        rc, lines = self._run_with(provider, stdin_lines=[tool_result])
        self.assertEqual(rc, 0)
        types = [m["type"] for m in lines]
        self.assertEqual(types[0], "ready")
        self.assertIn("tool_call", types)
        self.assertEqual(types[-1], "final")
        tc = next(m for m in lines if m["type"] == "tool_call")
        self.assertEqual(tc["name"], "org_read_context")
        self.assertEqual(tc["args"], {"scope": "today"})

    def test_no_tool_calls_coerces_final(self):
        provider = StubProvider([
            CompletionResult(
                content="just text",
                tool_calls=[],
                input_tokens=10, output_tokens=5,
            ),
        ])
        rc, lines = self._run_with(provider)
        self.assertEqual(rc, 0)
        final = lines[-1]
        self.assertEqual(final["type"], "final")
        self.assertEqual(final["summary"], "just text")
        self.assertEqual(final["reason"], "no_tool_calls")

    def test_tier3_budget_then_model_finals(self):
        # Budget >= 95%: tier jumps to 3, model gets one turn to finalise.
        provider = StubProvider([
            CompletionResult(
                content="",
                tool_calls=[{"id": "c1", "name": "org_read_context",
                             "args": {"scope": "today"}}],
                input_tokens=900, output_tokens=200,  # 1100/1000 > 95%
            ),
            CompletionResult(
                content="",
                tool_calls=[{"id": "c2", "name": "satan_final",
                             "args": {"summary": "winding down", "actions": []}}],
                input_tokens=50, output_tokens=10,
            ),
        ])
        tool_result = json.dumps({"type": "tool_result", "id": "c1",
                                   "ok": True, "result": {"content": ""}}) + "\n"
        rc, lines = self._run_with(provider, stdin_lines=[tool_result], budget=1000)
        self.assertEqual(rc, 0)
        tier_changes = [m for m in lines
                        if m.get("type") == "log" and m.get("kind") == "tier_changed"]
        self.assertTrue(len(tier_changes) >= 1)
        last_tier = tier_changes[-1]
        self.assertEqual(last_tier["to_tier"], 3)
        final = lines[-1]
        self.assertEqual(final["type"], "final")
        self.assertEqual(final["summary"], "winding down")
        # Model saw the system message about exhaustion.
        self.assertEqual(len(provider.calls), 2)
        second_turn_systems = [m for m in provider.calls[1]["messages"]
                               if m["role"] == "system"]
        self.assertTrue(any("exhausted" in (m["content"] or "").lower()
                            for m in second_turn_systems))

    def test_tier3_model_ignores_forces_final(self):
        # Model ignores tier 3 warning → harness force-terminates.
        provider = StubProvider([
            CompletionResult(
                content="",
                tool_calls=[{"id": "c1", "name": "org_read_context",
                             "args": {"scope": "today"}}],
                input_tokens=900, output_tokens=200,
            ),
            CompletionResult(
                content="still working",
                tool_calls=[{"id": "c2", "name": "org_read_context",
                             "args": {"scope": "today"}}],
                input_tokens=50, output_tokens=10,
            ),
        ])
        tool_result = json.dumps({"type": "tool_result", "id": "c1",
                                   "ok": True, "result": {"content": ""}}) + "\n"
        rc, lines = self._run_with(provider, stdin_lines=[tool_result], budget=1000)
        self.assertEqual(rc, 0)
        final = lines[-1]
        self.assertEqual(final["type"], "final")
        self.assertEqual(final["reason"], "budget_tokens")
        self.assertIn("did not finalise", final["summary"])

    def test_build_tools_returns_manifest_tools(self):
        manifest = {
            "tools": [
                _stub_tool_schema("a_tool"),
                _stub_tool_schema("satan_final"),
            ],
        }
        tools = bundle.build_tools(manifest)
        names = [t["function"]["name"] for t in tools]
        self.assertEqual(names, ["a_tool", "satan_final"])

    def test_build_tools_missing_raises(self):
        with self.assertRaises(RuntimeError):
            bundle.build_tools({})
        with self.assertRaises(RuntimeError):
            bundle.build_tools({"tools": []})

    def test_system_prompt_returns_bundle_prompt_verbatim(self):
        # The broker hands the harness a fully-rendered system prompt
        # (scaffold + mode + bundle-section framing). The harness must
        # not modify it — every section header lives mind-side.
        rendered = (
            "SCAFFOLD\n\nMODE PROMPT\n\n# Now\ndate: 2026-05-19\n\n"
            "# Today (raw)\nbody\n\n# Source files\n## a.el\n```\nx\n```"
        )
        self.assertEqual(bundle.build_system_prompt({"prompt": rendered}),
                         rendered)

    def test_system_prompt_missing_key_raises(self):
        # `bundle["prompt"]` is now a hard contract from the broker.
        with self.assertRaises(KeyError):
            bundle.build_system_prompt({})


class ErrorClassificationTests(unittest.TestCase):
    """Tests for classify_error() and structured error payloads."""

    def test_classify_rate_limit_429(self):
        e = Exception("Error code: 429 - Too Many Requests")
        self.assertEqual(runloop.classify_error(e), "rate_limit")

    def test_classify_rate_limit_word(self):
        e = Exception("rate limit exceeded for model")
        self.assertEqual(runloop.classify_error(e), "rate_limit")

    def test_classify_rate_limit_quota(self):
        e = Exception("quota exceeded")
        self.assertEqual(runloop.classify_error(e), "rate_limit")

    def test_classify_auth_401(self):
        e = Exception("Error code: 401 - Unauthorized")
        self.assertEqual(runloop.classify_error(e), "auth")

    def test_classify_auth_403(self):
        e = Exception("Error code: 403 - Forbidden")
        self.assertEqual(runloop.classify_error(e), "auth")

    def test_classify_auth_word(self):
        e = Exception("authentication failed")
        self.assertEqual(runloop.classify_error(e), "auth")

    def test_classify_server_500(self):
        e = Exception("Error code: 500 - Internal Server Error")
        self.assertEqual(runloop.classify_error(e), "server")

    def test_classify_server_502(self):
        e = Exception("Error code: 502 - Bad Gateway")
        self.assertEqual(runloop.classify_error(e), "server")

    def test_classify_server_503(self):
        e = Exception("Error code: 503 - Service Unavailable")
        self.assertEqual(runloop.classify_error(e), "server")

    def test_classify_timeout(self):
        e = Exception("request timed out after 30s")
        self.assertEqual(runloop.classify_error(e), "timeout")

    def test_classify_unknown(self):
        e = Exception("something unexpected happened")
        self.assertEqual(runloop.classify_error(e), "unknown")


class StructuredErrorTests(unittest.TestCase):
    """Verify provider errors emit structured JSON in the error field."""

    def _run_with(self, provider, *, stdin_lines: list[str] = (), budget: int = 0):
        buf = io.StringIO()
        env = {
            "SATAN_RUN_ID": "test-run",
            "SATAN_BUDGET_TOKENS": str(budget),
            "SATAN_PROVIDER": "openrouter",
            "SATAN_MODEL": "test-model",
            "OPENROUTER_API_KEY": "test-key",
        }
        with tempfile.TemporaryDirectory() as tmp:
            make_bundle(tmp)
            env["SATAN_RUN_DIR"] = tmp
            with mock.patch.dict(os.environ, env, clear=False), \
                 mock.patch.object(runloop, "build_provider",
                                   return_value=(provider, "test-model")), \
                 mock.patch.object(sys, "stdin", io.StringIO("".join(stdin_lines))), \
                 redirect_stdout(buf):
                rc = runloop.run()
        return rc, emitted_lines(buf)

    def test_provider_error_emits_structured_payload(self):
        """Provider exception → error msg with JSON payload containing
        class, detail, token totals, and turn count."""
        class FailingProvider(Provider):
            def complete(self, messages, tools, model):
                raise Exception("Error code: 429 - Too Many Requests")

        rc, lines = self._run_with(FailingProvider())
        self.assertEqual(rc, 1)
        error_msg = next(m for m in lines if m["type"] == "error")
        payload = json.loads(error_msg["error"])
        self.assertEqual(payload["class"], "rate_limit")
        self.assertIn("429", payload["detail"])
        self.assertEqual(payload["tokens_total"], 0)
        self.assertEqual(payload["turn"], 0)

    def test_provider_error_after_tool_call_includes_state(self):
        """Provider fails on second turn — payload should reflect
        tokens accumulated from the first turn."""
        class SecondCallFails(Provider):
            def __init__(self):
                self.call_count = 0
            def complete(self, messages, tools, model):
                self.call_count += 1
                if self.call_count == 1:
                    return CompletionResult(
                        content="",
                        tool_calls=[{"id": "c1", "name": "org_read_context",
                                     "args": {"scope": "today"}}],
                        input_tokens=100, output_tokens=50,
                    )
                raise Exception("server error 500")

        tool_result = json.dumps({"type": "tool_result", "id": "c1",
                                   "ok": True, "result": {"content": ""}}) + "\n"
        rc, lines = self._run_with(SecondCallFails(), stdin_lines=[tool_result])
        self.assertEqual(rc, 1)
        error_msg = next(m for m in lines if m["type"] == "error")
        payload = json.loads(error_msg["error"])
        self.assertEqual(payload["class"], "server")
        self.assertEqual(payload["tokens_total"], 150)
        self.assertEqual(payload["turn"], 1)


class TierDegradationTests(unittest.TestCase):
    """Tests for progressive token exhaustion (tier system)."""

    def test_compute_tier_thresholds(self):
        # Below 70% → tier 0.
        self.assertEqual(runloop.compute_tier(6900, 10000, 0, 0, 0), 0)
        # At 70% → tier 1.
        self.assertEqual(runloop.compute_tier(7000, 10000, 0, 0, 0), 1)
        # At 85% → tier 2.
        self.assertEqual(runloop.compute_tier(8500, 10000, 0, 0, 0), 2)
        # At 95% → tier 3.
        self.assertEqual(runloop.compute_tier(9500, 10000, 0, 0, 0), 3)

    def test_compute_tier_never_decreases(self):
        self.assertEqual(runloop.compute_tier(5000, 10000, 0, 0, 2), 2)

    def test_compute_tier_timeout_triggers_tier3(self):
        # 85% of timeout → tier 3.
        self.assertEqual(runloop.compute_tier(0, 0, 85, 100, 0), 3)
        # Below 85% → no timeout trigger.
        self.assertEqual(runloop.compute_tier(0, 0, 84, 100, 0), 0)

    def test_compute_tier_no_budget_stays_0(self):
        self.assertEqual(runloop.compute_tier(50000, 0, 0, 0, 0), 0)

    def test_filter_tools_tier0_keeps_all(self):
        tools = [_stub_tool_schema("docs_search"),
                 _stub_tool_schema("hippocampus_write"),
                 _stub_tool_schema("satan_final")]
        filtered = runloop.filter_tools_for_tier(tools, 0)
        names = [t["function"]["name"] for t in filtered]
        self.assertEqual(names, ["docs_search", "hippocampus_write", "satan_final"])

    def test_filter_tools_tier1_drops_survey(self):
        tools = [_stub_tool_schema("docs_search"),
                 _stub_tool_schema("docs_read"),
                 _stub_tool_schema("activity_read"),
                 _stub_tool_schema("hippocampus_write"),
                 _stub_tool_schema("satan_final")]
        filtered = runloop.filter_tools_for_tier(tools, 1)
        names = [t["function"]["name"] for t in filtered]
        self.assertNotIn("docs_search", names)
        self.assertNotIn("docs_read", names)
        self.assertNotIn("activity_read", names)
        self.assertIn("hippocampus_write", names)
        self.assertIn("satan_final", names)

    def test_filter_tools_tier2_drops_reads(self):
        tools = [_stub_tool_schema("org_read_context"),
                 _stub_tool_schema("bough_read"),
                 _stub_tool_schema("memory_resonate"),
                 _stub_tool_schema("hippocampus_write"),
                 _stub_tool_schema("notify_send"),
                 _stub_tool_schema("satan_final")]
        filtered = runloop.filter_tools_for_tier(tools, 2)
        names = [t["function"]["name"] for t in filtered]
        self.assertNotIn("org_read_context", names)
        self.assertNotIn("bough_read", names)
        self.assertNotIn("memory_resonate", names)
        self.assertIn("hippocampus_write", names)
        self.assertIn("notify_send", names)
        self.assertIn("satan_final", names)

    def test_filter_tools_tier3_final_only(self):
        tools = [_stub_tool_schema("hippocampus_write"),
                 _stub_tool_schema("notify_send"),
                 _stub_tool_schema("satan_final")]
        filtered = runloop.filter_tools_for_tier(tools, 3)
        names = [t["function"]["name"] for t in filtered]
        self.assertEqual(names, ["satan_final"])

    def test_tier1_emits_tier_changed_log(self):
        """Crossing 70% budget emits a tier_changed log event."""
        provider = StubProvider([
            CompletionResult(
                content="",
                tool_calls=[{"id": "c1", "name": "org_read_context",
                             "args": {"scope": "today"}}],
                input_tokens=600, output_tokens=200,  # 800/1000 = 80% > 70%
            ),
            CompletionResult(
                content="",
                tool_calls=[{"id": "c2", "name": "satan_final",
                             "args": {"summary": "done", "actions": []}}],
                input_tokens=50, output_tokens=10,
            ),
        ])
        tool_result = json.dumps({"type": "tool_result", "id": "c1",
                                   "ok": True, "result": {"content": ""}}) + "\n"
        buf = io.StringIO()
        env = {
            "SATAN_RUN_ID": "test-run",
            "SATAN_BUDGET_TOKENS": "1000",
            "SATAN_PROVIDER": "openrouter",
            "SATAN_MODEL": "test-model",
            "OPENROUTER_API_KEY": "test-key",
        }
        with tempfile.TemporaryDirectory() as tmp:
            make_bundle(tmp)
            env["SATAN_RUN_DIR"] = tmp
            with mock.patch.dict(os.environ, env, clear=False), \
                 mock.patch.object(runloop, "build_provider",
                                   return_value=(provider, "test-model")), \
                 mock.patch.object(sys, "stdin", io.StringIO(tool_result)), \
                 redirect_stdout(buf):
                rc = runloop.run()
        lines = emitted_lines(buf)
        self.assertEqual(rc, 0)
        tier_changes = [m for m in lines
                        if m.get("type") == "log" and m.get("kind") == "tier_changed"]
        self.assertEqual(len(tier_changes), 1)
        tc = tier_changes[0]
        self.assertEqual(tc["from_tier"], 0)
        self.assertEqual(tc["to_tier"], 1)
        self.assertEqual(tc["trigger"], "budget_70")
        self.assertEqual(tc["tokens_budget"], 1000)
        # System message was injected.
        second_turn_systems = [m for m in provider.calls[1]["messages"]
                               if m["role"] == "system"]
        self.assertTrue(any("survey tools withdrawn" in (m["content"] or "").lower()
                            for m in second_turn_systems))

    def test_progressive_tiers_1_then_3(self):
        """Two turns: first crosses 70% (tier 1), second crosses 95% (tier 3)."""
        provider = StubProvider([
            CompletionResult(
                content="",
                tool_calls=[{"id": "c1", "name": "org_read_context",
                             "args": {"scope": "today"}}],
                input_tokens=350, output_tokens=50,  # 400/1000 = 40% < 70%
            ),
            CompletionResult(
                content="",
                tool_calls=[{"id": "c2", "name": "org_read_context",
                             "args": {"scope": "today"}}],
                input_tokens=500, output_tokens=100,  # 1000/1000 = 100% > 95%
            ),
            CompletionResult(
                content="",
                tool_calls=[{"id": "c3", "name": "satan_final",
                             "args": {"summary": "ok", "actions": []}}],
                input_tokens=10, output_tokens=5,
            ),
        ])
        tr1 = json.dumps({"type": "tool_result", "id": "c1",
                           "ok": True, "result": {"content": ""}}) + "\n"
        tr2 = json.dumps({"type": "tool_result", "id": "c2",
                           "ok": True, "result": {"content": ""}}) + "\n"
        buf = io.StringIO()
        env = {
            "SATAN_RUN_ID": "test-run",
            "SATAN_BUDGET_TOKENS": "1000",
            "SATAN_PROVIDER": "openrouter",
            "SATAN_MODEL": "test-model",
            "OPENROUTER_API_KEY": "test-key",
        }
        with tempfile.TemporaryDirectory() as tmp:
            make_bundle(tmp)
            env["SATAN_RUN_DIR"] = tmp
            with mock.patch.dict(os.environ, env, clear=False), \
                 mock.patch.object(runloop, "build_provider",
                                   return_value=(provider, "test-model")), \
                 mock.patch.object(sys, "stdin", io.StringIO(tr1 + tr2)), \
                 redirect_stdout(buf):
                rc = runloop.run()
        lines = emitted_lines(buf)
        self.assertEqual(rc, 0)
        tier_changes = [m for m in lines
                        if m.get("type") == "log" and m.get("kind") == "tier_changed"]
        # First turn: 400/1000=40%, no tier change.
        # Second turn: 1000/1000=100%, jumps through tiers.
        self.assertTrue(len(tier_changes) >= 1)
        self.assertEqual(tier_changes[-1]["to_tier"], 3)


class BackstopTests(unittest.TestCase):
    """Tests for hard backstop (max_budget_tokens)."""

    def _run_with(self, provider, *, stdin_lines: list[str] = (),
                  budget: int = 0, max_budget: int = 0):
        buf = io.StringIO()
        env = {
            "SATAN_RUN_ID": "test-run",
            "SATAN_BUDGET_TOKENS": str(budget),
            "SATAN_MAX_BUDGET_TOKENS": str(max_budget),
            "SATAN_PROVIDER": "openrouter",
            "SATAN_MODEL": "test-model",
            "OPENROUTER_API_KEY": "test-key",
        }
        with tempfile.TemporaryDirectory() as tmp:
            make_bundle(tmp)
            env["SATAN_RUN_DIR"] = tmp
            with mock.patch.dict(os.environ, env, clear=False), \
                 mock.patch.object(runloop, "build_provider",
                                   return_value=(provider, "test-model")), \
                 mock.patch.object(sys, "stdin", io.StringIO("".join(stdin_lines))), \
                 redirect_stdout(buf):
                rc = runloop.run()
        return rc, emitted_lines(buf)

    def test_max_budget_forces_immediate_final(self):
        """Exceeding max_budget_tokens terminates immediately, no tier
        system involved."""
        provider = StubProvider([
            CompletionResult(
                content="",
                tool_calls=[{"id": "c1", "name": "org_read_context",
                             "args": {"scope": "today"}}],
                input_tokens=800, output_tokens=300,  # 1100 > max 1000
            ),
        ])
        tool_result = json.dumps({"type": "tool_result", "id": "c1",
                                   "ok": True, "result": {"content": ""}}) + "\n"
        rc, lines = self._run_with(provider, stdin_lines=[tool_result],
                                   budget=5000, max_budget=1000)
        self.assertEqual(rc, 0)
        final = lines[-1]
        self.assertEqual(final["type"], "final")
        self.assertEqual(final["reason"], "max_budget_tokens")
        self.assertIn("backstop", final["summary"])

    def test_max_budget_not_triggered_below_limit(self):
        """Below max_budget_tokens, normal operation continues."""
        provider = StubProvider([
            CompletionResult(
                content="",
                tool_calls=[{"id": "c1", "name": "satan_final",
                             "args": {"summary": "ok", "actions": []}}],
                input_tokens=100, output_tokens=50,
            ),
        ])
        rc, lines = self._run_with(provider, max_budget=1000)
        self.assertEqual(rc, 0)
        final = lines[-1]
        self.assertEqual(final["type"], "final")
        self.assertEqual(final["summary"], "ok")
        self.assertNotIn("reason", final)

    def test_max_budget_fires_before_tier_system(self):
        """max_budget_tokens fires even when budget_tokens would trigger
        tier degradation — backstop takes priority."""
        provider = StubProvider([
            CompletionResult(
                content="",
                tool_calls=[{"id": "c1", "name": "org_read_context",
                             "args": {"scope": "today"}}],
                input_tokens=900, output_tokens=200,  # 1100 > max 1000
            ),
        ])
        tool_result = json.dumps({"type": "tool_result", "id": "c1",
                                   "ok": True, "result": {"content": ""}}) + "\n"
        # budget=500 would trigger tier 3, but max_budget=1000 fires first
        # (backstop check runs before tier check)
        rc, lines = self._run_with(provider, stdin_lines=[tool_result],
                                   budget=500, max_budget=1000)
        self.assertEqual(rc, 0)
        final = lines[-1]
        self.assertEqual(final["reason"], "max_budget_tokens")
        # No tier_changed events — backstop fired before tier check
        tier_changes = [m for m in lines
                        if m.get("type") == "log" and m.get("kind") == "tier_changed"]
        self.assertEqual(len(tier_changes), 0)


class ProtocolFixtureTests(unittest.TestCase):
    """Drive the python validator from protocol/fixtures.json.

    Every valid fixture must validate clean; every invalid fixture must
    fail with exactly the reason recorded in the fixture, so the python
    and elisp validators stay in lockstep.
    """

    def test_fixtures_load(self):
        fixtures = protocol.load_fixtures()
        self.assertTrue(fixtures)

    def test_valid_fixtures_pass(self):
        for entry in protocol.load_fixtures():
            if entry["kind"] != "valid" or entry["direction"] not in ("in", "out"):
                continue
            with self.subTest(name=entry["name"]):
                reason = protocol.check(entry["direction"], entry["message"])
                self.assertIsNone(reason)

    def test_invalid_fixtures_fail_with_expected_reason(self):
        for entry in protocol.load_fixtures():
            if entry["kind"] != "invalid" or entry["direction"] not in ("in", "out"):
                continue
            with self.subTest(name=entry["name"]):
                reason = protocol.check(entry["direction"], entry["message"])
                self.assertIsNotNone(reason, f"{entry['name']} unexpectedly passed")
                self.assertEqual(reason, entry["reason"])

    def test_valid_actions_fixtures_pass(self):
        seen = 0
        for entry in protocol.load_fixtures():
            if entry["kind"] != "valid" or entry["direction"] != "actions":
                continue
            seen += 1
            with self.subTest(name=entry["name"]):
                reason = protocol.check_actions_json(entry["message"])
                self.assertIsNone(reason)
        self.assertGreater(seen, 0,
                           "actions fixture suite is empty — fixtures.json regression?")

    def test_invalid_actions_fixtures_fail_with_expected_reason(self):
        seen = 0
        for entry in protocol.load_fixtures():
            if entry["kind"] != "invalid" or entry["direction"] != "actions":
                continue
            seen += 1
            with self.subTest(name=entry["name"]):
                reason = protocol.check_actions_json(entry["message"])
                self.assertIsNotNone(reason, f"{entry['name']} unexpectedly passed")
                self.assertEqual(reason, entry["reason"])
        self.assertGreater(seen, 0,
                           "invalid actions fixture suite is empty — fixtures.json regression?")

    def test_validate_actions_json_raises_on_invalid(self):
        with self.assertRaises(protocol.ProtocolError):
            protocol.validate_actions_json({"applied": "nope",
                                            "staged": [], "rejected": [], "failed": []})

    def test_validate_actions_json_passes_with_pre_spawn(self):
        protocol.validate_actions_json({
            "applied": [], "staged": [], "rejected": [], "failed": [],
            "pre_spawn": [{"kind": "sensor_alert"}],
        })

    def test_validate_raises_on_invalid(self):
        with self.assertRaises(protocol.ProtocolError):
            protocol.validate("in", {"type": "ready"})

    def test_validate_passes_on_valid(self):
        protocol.validate("in", {"type": "ready", "run_id": "x"})

    def test_bad_direction_raises(self):
        with self.assertRaises(ValueError):
            protocol.check("sideways", {"type": "ready", "run_id": "x"})


class FakeOpenAI:
    """Captures OpenAI(...) ctor kwargs so tests can assert wiring."""
    last_kwargs: dict = {}

    def __init__(self, **kwargs):
        type(self).last_kwargs = kwargs
        self.chat = mock.MagicMock()


def _fake_openai_module():
    import types
    mod = types.ModuleType("openai")
    mod.OpenAI = FakeOpenAI
    return mod


class ProviderFactoryTests(unittest.TestCase):
    """Verify build_provider dispatches to the right subclass + base_url.

    The real `openai` SDK is not in scope for these unit tests (and may
    be absent in the dev env). Inject a fake module into `sys.modules`
    so the `from openai import OpenAI` inside `OpenAICompatibleProvider`
    resolves to `FakeOpenAI`.
    """

    def _build(self, env: dict) -> tuple[Provider, str]:
        with mock.patch.dict(os.environ, env, clear=True), \
             mock.patch.dict(sys.modules, {"openai": _fake_openai_module()}):
            FakeOpenAI.last_kwargs = {}
            return build_provider()

    def test_openrouter_dispatch(self):
        provider, model = self._build({
            "SATAN_PROVIDER": "openrouter",
            "SATAN_MODEL": "x-ai/grok",
            "OPENROUTER_API_KEY": "or-key",
        })
        self.assertIsInstance(provider, OpenRouterProvider)
        self.assertEqual(model, "x-ai/grok")
        self.assertEqual(FakeOpenAI.last_kwargs["api_key"], "or-key")
        self.assertEqual(FakeOpenAI.last_kwargs["base_url"],
                         "https://openrouter.ai/api/v1")

    def test_deepseek_dispatch(self):
        provider, model = self._build({
            "SATAN_PROVIDER": "deepseek",
            "SATAN_MODEL": "deepseek-chat",
            "DEEPSEEK_API_KEY": "ds-key",
        })
        self.assertIsInstance(provider, DeepSeekProvider)
        self.assertEqual(model, "deepseek-chat")
        self.assertEqual(FakeOpenAI.last_kwargs["api_key"], "ds-key")
        self.assertEqual(FakeOpenAI.last_kwargs["base_url"],
                         "https://api.deepseek.com")

    def test_default_provider_is_openrouter(self):
        provider, _ = self._build({
            "SATAN_MODEL": "any",
            "OPENROUTER_API_KEY": "k",
        })
        self.assertIsInstance(provider, OpenRouterProvider)

    def test_unknown_provider_raises(self):
        with self.assertRaisesRegex(RuntimeError, "unknown SATAN_PROVIDER"):
            self._build({
                "SATAN_PROVIDER": "claude-native",
                "SATAN_MODEL": "x",
            })

    def test_missing_model_raises(self):
        with self.assertRaisesRegex(RuntimeError, "SATAN_MODEL not set"):
            self._build({"SATAN_PROVIDER": "deepseek",
                         "DEEPSEEK_API_KEY": "k"})

    def test_missing_key_raises(self):
        with self.assertRaisesRegex(RuntimeError, "DEEPSEEK_API_KEY not set"):
            self._build({"SATAN_PROVIDER": "deepseek",
                         "SATAN_MODEL": "deepseek-chat"})

    def test_unresolved_op_ref_key_raises(self):
        """Literal op:// reference must be rejected, not sent to provider.

        The broker has a scrubber that strips these before spawn; this
        is the harness-side belt-and-braces in case anything slips through.
        Without this guard a transient op-resolution failure produces an
        opaque provider 401 (`****tial`) rather than a diagnosable error.
        """
        with self.assertRaisesRegex(RuntimeError,
                                    "unresolved op:// reference"):
            self._build({
                "SATAN_PROVIDER": "deepseek",
                "SATAN_MODEL": "deepseek-chat",
                "DEEPSEEK_API_KEY":
                    "op://API_KEYS/DEEPSEEK_API_KEY/credential",
            })


if __name__ == "__main__":
    unittest.main()
