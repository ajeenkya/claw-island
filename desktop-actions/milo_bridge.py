#!/usr/bin/env python3
"""Minimal desktop text bridge for Milo/OpenClaw voice workflows.

This script provides a stable, scriptable interface for common text editing operations:
- Read selected text, insert text, replace selection, press send keys
- Obtain frontmost app and window context
- All operations preserve clipboard content (best-effort)

Commands:
  get_context       Return frontmost app name and window title (context for agent)
  get_selection     Copy current selection and return it (clipboard-safe)
  replace_selection Paste provided text over current selection
  insert_text       Paste provided text at cursor position
  press_send        Press Enter or Command+Enter to submit

Design Notes:
  1. Clipboard-based text delivery:
     - Why: osascript keystroke/paste is stable, works across apps, no frameworks needed
     - Alternative (rejected): Direct Accessibility API has race conditions, requires complex
       permission handling, less reliable across macOS versions
     - Clipboard is atomic at the OS level; we preserve original content via decorator pattern

  2. UUID-based selection detection (in get_selection):
     - Set clipboard to unique marker, send Cmd+C, read clipboard
     - If clipboard still contains marker: no selection (user app didn't change it)
     - If clipboard changed: user's selection is in clipboard
     - Why: Robust across different app UIs without requiring app-specific logic

  3. osascript for keystrokes:
     - Why: System Events are stable, permission-based (Accessibility), works globally
     - Delays between operations (30-50ms): account for macOS event processing,
       clipboard delays, and app responsiveness

Accessibility Permissions:
  Requires 'Accessibility' permission in System Settings > Privacy & Security.
  This is requested automatically when the app first runs.

Return Format:
  All commands return JSON with structure:
  {
    "ok": true/false,           # Command succeeded
    "command": "...",           # Command name
    "error": "...",             # Error message (if ok=false)
    ... command-specific fields ...
  }
"""

import argparse
import json
import subprocess
import sys
import time
import uuid
from typing import Any, Dict, Optional


def run_cmd(cmd: list[str], input_text: Optional[str] = None) -> str:
    proc = subprocess.run(
        cmd,
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        stderr = proc.stderr.strip() or "unknown error"
        raise RuntimeError(f"{' '.join(cmd)} failed: {stderr}")
    return proc.stdout


def run_osascript(script: str) -> str:
    return run_cmd(["/usr/bin/osascript", "-e", script]).strip()


def get_clipboard_text() -> str:
    return run_cmd(["/usr/bin/pbpaste"])


def set_clipboard_text(value: str) -> None:
    run_cmd(["/usr/bin/pbcopy"], input_text=value)


def command_keystroke(key: str) -> None:
    # Accessibility permission is required for System Events keystrokes.
    script = f'tell application "System Events" to keystroke "{key}" using command down'
    run_osascript(script)


def command_key_code(code: int, modifiers: Optional[list[str]] = None) -> None:
    modifier_clause = ""
    if modifiers:
        modifier_clause = " using {" + ", ".join(modifiers) + "}"
    script = f'tell application "System Events" to key code {code}{modifier_clause}'
    run_osascript(script)


def get_frontmost_context() -> Dict[str, str]:
    app_name = ""
    window_title = ""

    try:
        app_name = run_osascript(
            'tell application "System Events" to get name of first application process whose frontmost is true'
        )
    except Exception:
        app_name = ""

    try:
        window_title = run_osascript(
            'tell application "System Events" to tell (first application process whose frontmost is true) to if (count of windows) > 0 then get name of front window'
        )
    except Exception:
        window_title = ""

    return {
        "frontmostApp": app_name,
        "windowTitle": window_title,
    }


def with_preserved_clipboard_text(func):
    """Decorator: preserve original clipboard content before and after operation.

    This ensures that clipboard-based text operations don't clobber the user's
    existing clipboard content. We read the original, run the operation, then restore.

    Design: Clipboard-based text delivery is preferred over direct API calls because:
    - osascript System Events keystroke/paste are more stable across macOS versions
    - No need for complex Accessibility API frameworks or custom bindings
    - Atomic at OS level (reliable for multi-threaded environments)
    - Works consistently across all apps (browser, terminal, IDE, etc.)

    Args:
        func: Function to execute with clipboard preservation

    Returns:
        Result of func() with clipboard restored afterward
    """
    original = ""
    had_original = False
    try:
        original = get_clipboard_text()
        had_original = True
    except Exception:
        # Keep going even if clipboard read fails; don't let this block execution.
        original = ""

    try:
        return func()
    finally:
        if had_original:
            try:
                set_clipboard_text(original)
            except Exception:
                pass


def cmd_get_context(args: argparse.Namespace) -> Dict[str, Any]:
    context = get_frontmost_context()
    return {
        "ok": True,
        "command": "get_context",
        "context": context,
    }


def cmd_get_selection(args: argparse.Namespace) -> Dict[str, Any]:
    """Get the user's current text selection from the active app.

    Technique: UUID-based marker detection
    1. Set clipboard to a unique marker string
    2. Send Cmd+C (copy) to the app
    3. Check if clipboard changed:
       - If still marker: no selection in app
       - If changed: clipboard now contains the user's selection

    Why this approach:
    - Works across all apps (no app-specific logic needed)
    - Doesn't require parsing app UI hierarchies
    - Robust to macOS version differences
    - Clipboard operation is atomic

    Args:
        args: argparse.Namespace with optional delay_ms (min 50ms)

    Returns:
        JSON dict with: selection (str), hasSelection (bool), context (app info)
    """
    def action() -> Dict[str, Any]:
        # Create unique marker unlikely to appear in user's clipboard
        marker = f"__MILO_SELECTION_MARKER_{uuid.uuid4()}__"
        set_clipboard_text(marker)
        time.sleep(0.03)  # Let clipboard settle

        # Send Cmd+C to copy selection
        command_keystroke("c")
        time.sleep(max(args.delay_ms, 50) / 1000.0)  # Wait for app to respond

        # Read clipboard—if marker is still there, there was no selection
        selected = get_clipboard_text()
        if selected == marker:
            selected = ""

        context = get_frontmost_context()
        return {
            "ok": True,
            "command": "get_selection",
            "selection": selected,
            "hasSelection": bool(selected.strip()),
            "context": context,
        }

    return with_preserved_clipboard_text(action)


def read_text_payload(args: argparse.Namespace) -> str:
    if args.stdin:
        return sys.stdin.read()
    if args.file:
        with open(args.file, "r", encoding="utf-8") as handle:
            return handle.read()
    return args.text or ""


def paste_text(text: str) -> None:
    """Paste text via clipboard and Cmd+V keystroke.

    Sequence:
    1. Set clipboard to desired text
    2. Wait for clipboard to stabilize (30ms)
    3. Send Cmd+V to paste
    4. Wait for app to process (50ms)

    This approach is more reliable than trying to type text character-by-character,
    which can fail or produce unexpected results with special characters, accents,
    or rapid input in some apps.

    Args:
        text: Text to paste into the active app
    """
    set_clipboard_text(text)
    time.sleep(0.03)  # Clipboard synchronization
    command_keystroke("v")
    time.sleep(0.05)  # App processing time


def cmd_replace_selection(args: argparse.Namespace) -> Dict[str, Any]:
    text = read_text_payload(args)
    if not text:
        raise RuntimeError("replace_selection requires non-empty text")

    def action() -> Dict[str, Any]:
        paste_text(text)
        return {
            "ok": True,
            "command": "replace_selection",
            "chars": len(text),
            "context": get_frontmost_context(),
        }

    return with_preserved_clipboard_text(action)


def cmd_insert_text(args: argparse.Namespace) -> Dict[str, Any]:
    text = read_text_payload(args)
    if not text:
        raise RuntimeError("insert_text requires non-empty text")

    def action() -> Dict[str, Any]:
        paste_text(text)
        return {
            "ok": True,
            "command": "insert_text",
            "chars": len(text),
            "context": get_frontmost_context(),
        }

    return with_preserved_clipboard_text(action)


def cmd_press_send(args: argparse.Namespace) -> Dict[str, Any]:
    requested_key = (args.key or "enter").strip().lower()
    key = "enter" if requested_key == "auto" else requested_key

    if key == "enter":
        key_code = 36
        modifiers: list[str] = []
    elif key == "command_enter":
        key_code = 36
        modifiers = ["command down"]
    else:
        raise RuntimeError(f"Unsupported send key: {requested_key}")

    context_before = get_frontmost_context()
    command_key_code(key_code, modifiers if modifiers else None)
    time.sleep(max(args.delay_ms, 35) / 1000.0)
    context_after = get_frontmost_context()

    return {
        "ok": True,
        "command": "press_send",
        "requestedKey": requested_key,
        "resolvedKey": key,
        "contextBefore": context_before,
        "contextAfter": context_after,
        "frontmostStable": context_before.get("frontmostApp", "") == context_after.get("frontmostApp", ""),
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Milo desktop text bridge")
    subparsers = parser.add_subparsers(dest="command", required=True)

    p_context = subparsers.add_parser("get_context", help="Frontmost app/window context")
    p_context.add_argument("--json", action="store_true", help="Emit JSON")
    p_context.set_defaults(handler=cmd_get_context)

    p_sel = subparsers.add_parser("get_selection", help="Get selected text")
    p_sel.add_argument("--delay-ms", type=int, default=120, help="Delay after Cmd+C")
    p_sel.add_argument("--json", action="store_true", help="Emit JSON")
    p_sel.set_defaults(handler=cmd_get_selection)

    for name, help_text, handler in [
        ("replace_selection", "Replace current selection", cmd_replace_selection),
        ("insert_text", "Insert text at cursor", cmd_insert_text),
    ]:
        p = subparsers.add_parser(name, help=help_text)
        p.add_argument("--text", type=str, default="", help="Text payload")
        p.add_argument("--file", type=str, default="", help="Read payload from file")
        p.add_argument("--stdin", action="store_true", help="Read payload from stdin")
        p.add_argument("--json", action="store_true", help="Emit JSON")
        p.set_defaults(handler=handler)

    p_send = subparsers.add_parser("press_send", help="Press send key (Enter / Command+Enter)")
    p_send.add_argument(
        "--key",
        type=str,
        default="enter",
        choices=["auto", "enter", "command_enter"],
        help="Send key variant",
    )
    p_send.add_argument("--delay-ms", type=int, default=120, help="Delay after key press")
    p_send.add_argument("--json", action="store_true", help="Emit JSON")
    p_send.set_defaults(handler=cmd_press_send)

    return parser


def emit(result: Dict[str, Any], as_json: bool) -> None:
    if as_json:
        print(json.dumps(result, ensure_ascii=True))
    else:
        if "selection" in result:
            print(result.get("selection", ""))
        else:
            print("ok")


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    as_json = bool(getattr(args, "json", False))

    try:
        result = args.handler(args)
        emit(result, as_json)
        return 0
    except Exception as exc:
        payload = {
            "ok": False,
            "error": str(exc),
            "command": getattr(args, "command", "unknown"),
        }
        emit(payload, True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
