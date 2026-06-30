#!/usr/bin/env python3
"""
Contract tests for the mdeditor MCP server — verb/URL mapping, JSON parsing, error handling.

These MOCK the `macdown` CLI subprocess, so they run anywhere (CI, ssh, no app/GUI needed):
they assert that each tool builds the correct `x-macdown://` URL and faithfully returns the
handler's JSON contract. The live cross-process path is covered separately by
Scripts/readback-smoke.sh (GUI-session only).

Run:  /opt/homebrew/bin/python3 -m unittest mcp/test_mdeditor_mcp.py -v
"""

import asyncio
import json
import os
import types
import unittest
from unittest import mock

os.environ["MDEDITOR_CLI"] = "/bin/echo"      # any real file; subprocess is mocked anyway
os.environ["MDEDITOR_BUNDLE"] = "com.jasoncbraatz.mdeditor-test"

import mdeditor_mcp as M  # noqa: E402


def _fake_run(stdout, returncode=0, stderr=""):
    def _run(cmd, capture_output=True, text=True, timeout=None):
        _run.cmd = cmd
        return types.SimpleNamespace(stdout=stdout, stderr=stderr, returncode=returncode)
    return _run


def call(coro):
    return asyncio.run(coro)


class UrlBuildingTests(unittest.TestCase):
    def test_file_url_absolute_and_spaces(self):
        self.assertEqual(M._file_url("/tmp/a note.md"), "file:///tmp/a%20note.md")

    def test_url_no_params(self):
        self.assertEqual(M._url("status"), "x-macdown://status")

    def test_url_with_params_encoded(self):
        u = M._url("command", {"id": "h1"})
        self.assertEqual(u, "x-macdown://command?id=h1")
        u2 = M._url("open", {"url": "file:///tmp/a b.md"})
        self.assertIn("open?url=file%3A%2F%2F", u2)


class VerbMappingTests(unittest.TestCase):
    """Each tool must shell to the right verb and pass the bundle through."""

    def _run_tool(self, coro, reply):
        with mock.patch.object(M.subprocess, "run", _fake_run(json.dumps(reply))) as _:
            out = call(coro)
        return out, M.subprocess.run.cmd if hasattr(M.subprocess.run, "cmd") else None

    def test_status(self):
        fake = _fake_run(json.dumps({"ok": True, "verb": "status", "hasDocument": False}))
        with mock.patch.object(M.subprocess, "run", fake):
            out = call(M.mdeditor_status(M.NoInput()))
            self.assertIn("--control", fake.cmd)
            self.assertIn("x-macdown://status", fake.cmd)
            self.assertIn("--bundle", fake.cmd)
            self.assertIn("com.jasoncbraatz.mdeditor-test", fake.cmd)
        self.assertEqual(json.loads(out)["verb"], "status")

    def test_get_text(self):
        fake = _fake_run(json.dumps({"ok": True, "verb": "get-text", "text": "# Hi"}))
        with mock.patch.object(M.subprocess, "run", fake):
            out = call(M.mdeditor_get_text(M.NoInput()))
            self.assertIn("x-macdown://get-text", fake.cmd)
        self.assertEqual(json.loads(out)["text"], "# Hi")

    def test_render_html(self):
        fake = _fake_run(json.dumps({"ok": True, "verb": "render-html", "html": "<p>x</p>"}))
        with mock.patch.object(M.subprocess, "run", fake):
            out = call(M.mdeditor_render_html(M.NoInput()))
            self.assertIn("x-macdown://render-html", fake.cmd)
        self.assertEqual(json.loads(out)["html"], "<p>x</p>")

    def test_open_file(self):
        fake = _fake_run(json.dumps({"ok": True, "verb": "open", "path": "/tmp/a.md"}))
        with mock.patch.object(M.subprocess, "run", fake):
            out = call(M.mdeditor_open_file(M.OpenFileInput(path="/tmp/a.md")))
            url = [a for a in fake.cmd if a.startswith("x-macdown://")][0]
            self.assertTrue(url.startswith("x-macdown://open?url=file%3A%2F%2F"))
        self.assertTrue(json.loads(out)["ok"])

    def test_run_command(self):
        fake = _fake_run(json.dumps({"ok": True, "verb": "command", "id": "h1"}))
        with mock.patch.object(M.subprocess, "run", fake):
            out = call(M.mdeditor_run_command(M.RunCommandInput(command_id="h1")))
            self.assertIn("x-macdown://command?id=h1", fake.cmd)
        self.assertEqual(json.loads(out)["id"], "h1")

    def test_export_html(self):
        fake = _fake_run(json.dumps({"ok": True, "verb": "export-html", "path": "/tmp/o.html", "bytes": 9}))
        with mock.patch.object(M.subprocess, "run", fake):
            out = call(M.mdeditor_export_html(M.ExportHtmlInput(path="/tmp/o.html")))
            url = [a for a in fake.cmd if a.startswith("x-macdown://")][0]
            self.assertTrue(url.startswith("x-macdown://export-html?path=file%3A%2F%2F"))
        self.assertEqual(json.loads(out)["bytes"], 9)

    def test_new_document_writes_temp_and_opens(self):
        fake = _fake_run(json.dumps({"ok": True, "verb": "open"}))
        with mock.patch.object(M.subprocess, "run", fake):
            out = call(M.mdeditor_new_document(M.NewDocumentInput(text="# Hello\n")))
        d = json.loads(out)
        self.assertIn("tempPath", d)
        self.assertTrue(d["tempPath"].endswith(".md"))
        with open(d["tempPath"], encoding="utf-8") as f:
            self.assertEqual(f.read(), "# Hello\n")
        os.unlink(d["tempPath"])


class ErrorHandlingTests(unittest.TestCase):
    def test_empty_reply_is_error(self):
        fake = _fake_run("", returncode=1, stderr="no reply from app")
        with mock.patch.object(M.subprocess, "run", fake):
            out = call(M.mdeditor_status(M.NoInput()))
        d = json.loads(out)
        self.assertFalse(d["ok"])
        self.assertIn("error", d)

    def test_non_json_reply_is_error(self):
        fake = _fake_run("not json at all")
        with mock.patch.object(M.subprocess, "run", fake):
            out = call(M.mdeditor_get_text(M.NoInput()))
        d = json.loads(out)
        self.assertFalse(d["ok"])

    def test_handler_failure_passthrough(self):
        # A well-formed ok:false from the app must pass through unchanged (not masked).
        fake = _fake_run(json.dumps({"ok": False, "verb": "command", "error": "unknown command id"}))
        with mock.patch.object(M.subprocess, "run", fake):
            out = call(M.mdeditor_run_command(M.RunCommandInput(command_id="bogus")))
        d = json.loads(out)
        self.assertFalse(d["ok"])
        self.assertEqual(d["error"], "unknown command id")


if __name__ == "__main__":
    unittest.main(verbosity=2)
