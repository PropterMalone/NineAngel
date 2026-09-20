#!/usr/bin/env python3
"""Subscription reducer authentication, tool boundary, and event tests."""
import importlib.util
import json
import os
import subprocess
import unittest
from pathlib import Path
from unittest import mock

D = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("reducer_sandbox_test", D / "run-reducer-sandbox.py")
sandbox = importlib.util.module_from_spec(spec); spec.loader.exec_module(sandbox)


class SandboxTests(unittest.TestCase):
    def test_environment_scrubs_usage_billed_credentials(self):
        with mock.patch.dict(os.environ, {
                "OPENAI_API_KEY": "api-secret", "CODEX_API_KEY": "codex-secret",
                "CODEX_ACCESS_TOKEN": "access-secret", "OPENAI_BASE_URL": "https://api",
                "ANGEL_REDUCER_API_KEY": "old-secret", "CODEX_HOME": "/auth-home"},
                clear=False):
            env = sandbox._codex_env()
        self.assertEqual(env["CODEX_HOME"], "/auth-home")
        for name in sandbox.SENSITIVE_API_ENV:
            self.assertNotIn(name, env)

    def test_description_requires_chatgpt_auth(self):
        version = subprocess.CompletedProcess([], 0, "codex-cli 1.2.3\n", "")
        api_auth = subprocess.CompletedProcess([], 0, "Logged in using API key\n", "")
        with mock.patch.object(sandbox.shutil, "which", return_value=__file__), \
             mock.patch.object(sandbox, "_run", side_effect=(version, api_auth)):
            description, failure = sandbox._codex_description()
        self.assertIsNone(description)
        self.assertIn("ChatGPT", failure)

    def test_description_binds_binary_identity(self):
        version = subprocess.CompletedProcess([], 0, "codex-cli 1.2.3\n", "")
        auth = subprocess.CompletedProcess([], 0, "Logged in using ChatGPT\n", "")
        with mock.patch.object(sandbox.shutil, "which", return_value=__file__), \
             mock.patch.object(sandbox, "_run", side_effect=(version, auth)):
            description, failure = sandbox._codex_description()
        self.assertIsNone(failure)
        self.assertEqual(description["backend"], "codex")
        self.assertEqual(description["auth"], "chatgpt")
        self.assertIn("codex-cli 1.2.3", description["identity"])

    def test_command_disables_every_model_callable_surface(self):
        description = {"binary": "/trusted/codex"}
        command = sandbox._codex_command(
            description, Path("/empty"), Path("/input/schema"), Path("/output/result"))
        rendered = " ".join(command)
        self.assertIn("--ignore-user-config", command)
        self.assertIn("--ignore-rules", command)
        self.assertIn("--ephemeral", command)
        self.assertIn("read-only", command)
        self.assertIn("approval_policy=\"never\"", command)
        for feature in sandbox.DISABLED_FEATURES:
            self.assertIn(f"--disable {feature}", rendered)
        self.assertNotIn("API_KEY", rendered)

    def test_codex_schema_drops_only_remote_unsupported_annotations(self):
        source = {"$schema": "draft", "title": "x", "type": "object",
                  "properties": {"title": {"type": "string", "title": "annotation"},
                                 "values": {"type": "array", "uniqueItems": True,
                                            "items": {"enum": ["a", "b"]}},
                                 "status": {"const": "candidate"}}}
        self.assertEqual(sandbox._api_schema(source), {
            "type": "object", "properties": {
                "title": {"type": "string"},
                "values": {"type": "array", "items": {
                    "enum": ["a", "b"], "type": "string"}},
                "status": {"const": "candidate", "type": "string"}}})

    def test_event_parser_accepts_one_tool_free_turn(self):
        events = [
            {"type": "thread.started", "thread_id": "x"},
            {"type": "turn.started"},
            {"type": "item.completed", "item": {"type": "reasoning"}},
            {"type": "item.completed", "item": {"type": "agent_message", "text": "{}"}},
            {"type": "turn.completed", "usage": {"input_tokens": 10, "output_tokens": 2}},
        ]
        usage, blocked = sandbox._parse_events("\n".join(json.dumps(x) for x in events))
        self.assertEqual(usage["input_tokens"], 10)
        self.assertEqual(blocked, 0)

    def test_event_parser_accepts_only_the_known_fail_closed_tool_error(self):
        events = [
            {"type": "turn.started"},
            {"type": "item.completed", "item": {
                "type": "error", "message": sandbox.BLOCKED_TOOL_PREFIX + " denied"}},
            {"type": "item.completed", "item": {"type": "agent_message", "text": "{}"}},
            {"type": "turn.completed", "usage": {"input_tokens": 10, "output_tokens": 2}},
        ]
        _usage, blocked = sandbox._parse_events("\n".join(json.dumps(x) for x in events))
        self.assertEqual(blocked, 1)

    def test_event_parser_rejects_command_or_file_tool(self):
        events = [
            {"type": "turn.started"},
            {"type": "item.completed", "item": {"type": "command_execution"}},
            {"type": "turn.completed", "usage": {}},
        ]
        with self.assertRaisesRegex(ValueError, "tool event"):
            sandbox._parse_events("\n".join(json.dumps(x) for x in events))

    def test_timeout_kills_the_whole_process_group(self):
        class Process:
            pid = 4321
            returncode = None
            def communicate(self, _prompt, timeout=None):
                raise subprocess.TimeoutExpired("codex", timeout)
            def poll(self):
                return None
            def wait(self, timeout=None):
                self.returncode = -9

        with mock.patch.object(sandbox.subprocess, "Popen", return_value=Process()), \
             mock.patch.object(sandbox.os, "killpg") as killpg:
            with self.assertRaisesRegex(SystemExit, "exceeded wall timeout"):
                sandbox._execute(["codex"], "prompt", 1)
        killpg.assert_called_once_with(4321, sandbox.signal.SIGKILL)

    def test_unprovable_process_cleanup_refuses_retry(self):
        process = mock.Mock(pid=4321)
        with mock.patch.object(sandbox, "_stop_process_group",
                               side_effect=RuntimeError("still live")):
            with self.assertRaises(SystemExit) as raised:
                sandbox._cleanup_or_exit(process)
        self.assertEqual(raised.exception.code, 75)

    def test_disabled_backend_is_explicit(self):
        with self.assertRaisesRegex(RuntimeError, "explicitly disabled"):
            sandbox.describe_backend("disabled")


if __name__ == "__main__": unittest.main()
