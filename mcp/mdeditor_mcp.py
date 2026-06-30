#!/usr/bin/env python3
"""
mdeditor MCP server (Phase 3) — drive Jason's markdown editor from the Claude desktop app.

This is a THIN piggyback on the same control surface the XCTest harness uses: it shells to the
`macdown` CLI's read-back transport (`macdown --control "x-macdown://<verb>…"`), which sends a
GetURL AppleEvent to the running app and prints the handler's JSON reply on stdout. One behaviour
path, not two (see docs/MCP-TRANSPORT.md + docs/MASTER-PLAN.md §6).

Because it talks to the *running* app via AppleEvents, this server must run inside the user's GUI
login session (the Claude desktop app does) — the first call triggers a one-time macOS Automation
("… wants to control mdeditor") consent prompt; click Allow once. It CANNOT work from a headless
ssh session (AppleEvents don't cross the session boundary).

Config (env, all optional):
    MDEDITOR_CLI     absolute path to the `macdown` CLI binary. If unset, we search PATH and the
                     usual build/install locations.
    MDEDITOR_BUNDLE  target app bundle id (default: com.jasoncbraatz.mdeditor — the release build;
                     set com.jasoncbraatz.mdeditor-debug to drive a Debug build).
    MDEDITOR_TIMEOUT per-call timeout seconds (default 20).

Registration (claude_desktop_config.json):
    "mdeditor": {
        "command": "/opt/homebrew/bin/python3",
        "args": ["/Users/jasoncbraatz/Desktop/downloads/strike-zone/1216089018004712/macdown/mcp/mdeditor_mcp.py"],
        "env": {"MDEDITOR_CLI": "/path/to/macdown"}
    }
"""

import asyncio
import json
import logging
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Optional
from urllib.parse import urlencode

from pydantic import BaseModel, ConfigDict, Field
from mcp.server.fastmcp import FastMCP

# ---------------------------------------------------------------------------
# Logging — stderr ONLY (stdout is reserved for the MCP stdio transport).
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s mdeditor-mcp %(levelname)s %(message)s",
)
log = logging.getLogger("mdeditor_mcp")

mcp = FastMCP("mdeditor")

DEFAULT_BUNDLE = "com.jasoncbraatz.mdeditor"


# ---------------------------------------------------------------------------
# Transport helper — shell to `macdown --control <url> [--bundle <id>]`.
# ---------------------------------------------------------------------------
def _cli_path() -> str:
    """Locate the `macdown` CLI: env override, then PATH, then known build/install spots."""
    env = os.environ.get("MDEDITOR_CLI")
    if env and Path(env).is_file():
        return env
    found = shutil.which("macdown")
    if found:
        return found
    repo = Path(__file__).resolve().parent.parent
    candidates = [
        repo / "build/ddata/Build/Products/Debug/macdown",
        repo / "build/ddata/Build/Products/Release/macdown",
        Path.home() / "Library/Developer/Xcode/DerivedData",  # searched below
    ]
    for c in candidates[:2]:
        if c.is_file():
            return str(c)
    raise FileNotFoundError(
        "macdown CLI not found. Set MDEDITOR_CLI to the built `macdown` binary "
        "(target macdown-cmd, product `macdown`)."
    )


def _bundle() -> str:
    return os.environ.get("MDEDITOR_BUNDLE", DEFAULT_BUNDLE)


def _timeout() -> float:
    try:
        return float(os.environ.get("MDEDITOR_TIMEOUT", "20"))
    except ValueError:
        return 20.0


def _control_sync(url: str) -> dict:
    """Run the CLI once and parse its single-line JSON reply. Raises on failure."""
    cli = _cli_path()
    cmd = [cli, "--control", url, "--bundle", _bundle()]
    log.info("control: %s", url)
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=_timeout())
    out = (proc.stdout or "").strip()
    if not out:
        raise RuntimeError(
            f"empty reply from CLI (rc={proc.returncode}). stderr: {(proc.stderr or '').strip()!r}"
        )
    try:
        return json.loads(out)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"non-JSON reply: {out!r}") from e


async def _control(url: str) -> dict:
    return await asyncio.to_thread(_control_sync, url)


def _url(verb: str, params: Optional[dict] = None) -> str:
    base = f"x-macdown://{verb}"
    if params:
        return base + "?" + urlencode(params)
    return base


def _result(d: dict) -> str:
    """Pretty JSON for the tool result; preserves the handler's ok/error contract."""
    return json.dumps(d, indent=2, ensure_ascii=False)


def _handle_error(e: Exception) -> str:
    log.exception("tool error")
    return json.dumps({"ok": False, "error": f"{type(e).__name__}: {e}"}, indent=2)


def _file_url(path: str) -> str:
    """Absolute file:// URL for a user-supplied path (expanduser + resolve)."""
    p = Path(path).expanduser()
    if not p.is_absolute():
        p = p.resolve()
    return p.as_uri()


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------
class NoInput(BaseModel):
    model_config = ConfigDict(extra="forbid")


class OpenFileInput(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")
    path: str = Field(description="Absolute path to a local .md/.markdown file to open.")


class NewDocumentInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    text: str = Field(description="Markdown text for a new document.")


class SetTextInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    text: str = Field(description="Markdown text to REPLACE the front document's contents with.")


class RunCommandInput(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")
    command_id: str = Field(
        description="An editing command id from the registry, e.g. strong, emphasis, code, "
        "h1..h6, ul, ol, blockquote, link, image, indent, unindent. Applied to the front document."
    )


class ExportHtmlInput(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")
    path: str = Field(description="Absolute output path ending in .html or .htm.")


_RO = {"readOnlyHint": True, "destructiveHint": False, "idempotentHint": True, "openWorldHint": True}
_WR = {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": False, "openWorldHint": True}


@mcp.tool(name="mdeditor_status", annotations={"title": "mdeditor status", **_RO})
async def mdeditor_status(params: NoInput) -> str:
    """Liveness/inventory of the running mdeditor: whether a document is front, whether its
    preview is ready, the command-registry size, and the front document's text length. Works even
    when no document is open (hasDocument=false). Use this first to confirm the app is reachable."""
    try:
        return _result(await _control(_url("status")))
    except Exception as e:
        return _handle_error(e)


@mcp.tool(name="mdeditor_get_text", annotations={"title": "Get front document markdown", **_RO})
async def mdeditor_get_text(params: NoInput) -> str:
    """Return the markdown text of the front mdeditor document (its editor contents)."""
    try:
        return _result(await _control(_url("get-text")))
    except Exception as e:
        return _handle_error(e)


@mcp.tool(name="mdeditor_render_html", annotations={"title": "Get rendered HTML", **_RO})
async def mdeditor_render_html(params: NoInput) -> str:
    """Return the rendered HTML of the front mdeditor document (the live preview's HTML body)."""
    try:
        return _result(await _control(_url("render-html")))
    except Exception as e:
        return _handle_error(e)


@mcp.tool(name="mdeditor_open_file", annotations={"title": "Open a markdown file", **_WR})
async def mdeditor_open_file(params: OpenFileInput) -> str:
    """Open a local markdown file in mdeditor (launches the app if needed). Path must be a local
    file; the app validates it is an absolute file:// URL (no http/remote)."""
    try:
        url = _url("open", {"url": _file_url(params.path)})
        return _result(await _control(url))
    except Exception as e:
        return _handle_error(e)


@mcp.tool(name="mdeditor_new_document", annotations={"title": "New document from text", **_WR})
async def mdeditor_new_document(params: NewDocumentInput) -> str:
    """Create a new markdown document with the given text and open it in mdeditor. Implemented by
    writing the text to a temp .md file and opening it (reuses the validated `open` verb), so the
    result JSON includes the temp file path. Great for 'make a doc that says X and open it'."""
    try:
        tmpdir = Path(tempfile.gettempdir()) / "mdeditor-mcp"
        tmpdir.mkdir(parents=True, exist_ok=True)
        fd, name = tempfile.mkstemp(suffix=".md", dir=str(tmpdir))
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(params.text)
        url = _url("open", {"url": _file_url(name)})
        reply = await _control(url)
        reply["tempPath"] = name
        return _result(reply)
    except Exception as e:
        return _handle_error(e)


@mcp.tool(name="mdeditor_set_text", annotations={"title": "Replace front document text", **_WR})
async def mdeditor_set_text(params: SetTextInput) -> str:
    """Replace the FRONT mdeditor document's entire markdown with the given text. The text is
    written to a temp file and passed by path (set-text?file=…), so arbitrarily large documents
    are safe (no URL limits). Requires a document already open (use open_file/new_document first)."""
    name = None
    try:
        tmpdir = Path(tempfile.gettempdir()) / "mdeditor-mcp"
        tmpdir.mkdir(parents=True, exist_ok=True)
        fd, name = tempfile.mkstemp(suffix=".md", dir=str(tmpdir))
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(params.text)
        # The app reads the file synchronously while handling the event, so it is safe to
        # remove the temp once _control returns.
        reply = await _control(_url("set-text", {"file": _file_url(name)}))
        return _result(reply)
    except Exception as e:
        return _handle_error(e)
    finally:
        if name:
            try:
                os.unlink(name)
            except OSError:
                pass


@mcp.tool(name="mdeditor_run_command", annotations={"title": "Run an editing command", **_WR})
async def mdeditor_run_command(params: RunCommandInput) -> str:
    """Run a registry editing command on the FRONT document (the same registry the toolbar/menus
    and the test harness use). Unknown ids are rejected server-side (ok=false). Examples: strong,
    emphasis, code, h1..h6, ul, ol, blockquote, link, image, indent, unindent."""
    try:
        url = _url("command", {"id": params.command_id})
        return _result(await _control(url))
    except Exception as e:
        return _handle_error(e)


@mcp.tool(name="mdeditor_export_html", annotations={"title": "Export rendered HTML to a file", **_WR})
async def mdeditor_export_html(params: ExportHtmlInput) -> str:
    """Write the front document's rendered HTML to an output file. The path must be absolute and
    end in .html/.htm (the app rejects other extensions so a typo can't clobber a dotfile/binary)."""
    try:
        url = _url("export-html", {"path": _file_url(params.path)})
        return _result(await _control(url))
    except Exception as e:
        return _handle_error(e)


if __name__ == "__main__":
    mcp.run()
