#!/usr/bin/env python3
"""Real pseudo-terminal validation for the native checkpoint 188 settings screen."""
from __future__ import annotations

import argparse
import contextlib
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import tempfile
import time
from typing import Any


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def wait_for(master: int, output: bytearray, process: subprocess.Popen[bytes], marker: bytes, start: int = 0, timeout: float = 30.0) -> int:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = output.find(marker, start)
        if found >= 0:
            return found + len(marker)
        if process.poll() is not None:
            break
        ready, _, _ = select.select([master], [], [], min(0.1, max(0.0, deadline - time.monotonic())))
        if ready:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                chunk = b""
            output.extend(chunk)
    raise AssertionError(f"marker {marker!r} missing; tail={output[-6000:].decode(errors='replace')}")


def run(binary: Path, report: Path | None) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pi-settings-171-") as raw:
        root = Path(raw)
        agent_dir = root / "agent"
        sessions = root / "sessions"
        workspace = root / "workspace"
        agent_dir.mkdir()
        sessions.mkdir()
        workspace.mkdir()
        settings_path = agent_dir / "settings.json"
        settings_path.write_text(json.dumps({
            "customMarker": "preserve-171",
            "collapseChangelog": True,
            "retry": {
                "enabled": True,
                "maxRetries": 4,
                "baseDelayMs": 17,
                "provider": {
                    "timeoutMs": 321,
                    "maxRetries": 2,
                    "maxRetryDelayMs": 654,
                },
            },
        }), encoding="utf-8")
        mock = root / "mock.json"
        mock.write_text(json.dumps([{"content": "unused-171"}]), encoding="utf-8")

        env = os.environ.copy()
        env.update({
            "PI_AGENT_DIR": str(agent_dir),
            "TERM": "xterm-256color",
            "NO_COLOR": "1",
            "HOME": str(root / "home"),
        })
        command = [
            str(binary), "--offline", "--mock-script", str(mock),
            "--session-dir", str(sessions), "--no-context-files", "--no-skills",
            "--no-prompt-templates", "--no-themes", "--approve",
        ]
        master, slave = pty.openpty()
        process = subprocess.Popen(
            command, cwd=workspace, env=env, stdin=slave, stdout=slave,
            stderr=subprocess.PIPE, close_fds=True,
        )
        os.close(slave)
        os.set_blocking(master, False)
        output = bytearray()
        try:
            pos = wait_for(master, output, process, b"> ")
            os.write(master, b"/settings\r")
            pos = wait_for(master, output, process, b"Settings", pos)
            require(b"\x1b[?1049h" in output or b"\x1b[2J" in output, "fullscreen settings screen did not start")

            def edit_setting(query: bytes, label: bytes) -> None:
                nonlocal pos
                screen_start = len(output)
                os.write(master, query)
                pos = wait_for(master, output, process, label, screen_start)
                os.write(master, b"\r")
                time.sleep(0.12)
                # Escape clears the query but keeps the selector open.
                clear_start = len(output)
                os.write(master, b"\x1b")
                pos = wait_for(master, output, process, b"mouse wheel/click supported", clear_start)

            edit_setting(b"automatic retry", b"Automatic retry")
            edit_setting(b"assistant retry attempts", b"Assistant retry attempts")
            edit_setting(b"steering mode", b"Steering mode")
            edit_setting(b"follow-up mode", b"Follow-up mode")
            edit_setting(b"tree filter mode", b"Tree filter mode")
            edit_setting(b"quiet startup", b"Quiet startup")

            # Query is already clear; close and trigger one transactional reload.
            close_start = len(output)
            os.write(master, b"\x1b")
            pos = wait_for(master, output, process, b"Reloaded:", close_start, timeout=45.0)
            pos = wait_for(master, output, process, b"> ", pos)

            # Prove live tree-filter application without restarting.
            os.write(master, b"hello-171\r")
            pos = wait_for(master, output, process, b"unused-171", pos)
            pos = wait_for(master, output, process, b"> ", pos)
            os.write(master, b"/tree\r")
            pos = wait_for(master, output, process, b"Session Tree", pos)
            pos = wait_for(master, output, process, b"no tools", pos)
            os.write(master, b"\x1b")
            pos = wait_for(master, output, process, b"Tree navigation cancelled.", pos)
            pos = wait_for(master, output, process, b"> ", pos)
            os.write(master, b"/quit\r")

            deadline = time.monotonic() + 30.0
            while process.poll() is None and time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.1)
                if ready:
                    with contextlib.suppress(OSError):
                        output.extend(os.read(master, 65536))
            require(process.poll() is not None, f"interactive process did not exit; tail={output[-4000:].decode(errors='replace')}")
            assert process.stderr is not None
            stderr = process.stderr.read().decode("utf-8", errors="replace")
            require(process.returncode == 0, f"process exit {process.returncode}: {stderr}")
            require(stderr == "", f"unexpected stderr: {stderr}")

            persisted = json.loads(settings_path.read_text(encoding="utf-8"))
            retry = persisted.get("retry", {})
            provider = retry.get("provider", {})
            require(retry.get("enabled") is False, f"retry enabled was not toggled: {persisted}")
            require(retry.get("maxRetries") == 5, f"retry count was not advanced: {persisted}")
            require(retry.get("baseDelayMs") == 17, f"nested retry sibling lost: {persisted}")
            require(provider == {"timeoutMs": 321, "maxRetries": 2, "maxRetryDelayMs": 654}, f"provider retry settings changed: {persisted}")
            require(persisted.get("customMarker") == "preserve-171", f"unrelated setting lost: {persisted}")
            require(persisted.get("collapseChangelog") is True, f"known sibling lost: {persisted}")
            require(persisted.get("steeringMode") == "all", f"steering mode not persisted: {persisted}")
            require(persisted.get("followUpMode") == "all", f"follow-up mode not persisted: {persisted}")
            require(persisted.get("treeFilterMode") == "no-tools", f"tree filter not persisted: {persisted}")
            require(persisted.get("quietStartup") is True, f"quiet startup not persisted: {persisted}")
            require(b"\x1b[?1049l" in output or b"\x1b[2J" in output, "fullscreen settings screen did not restore terminal")
            require(b"no tools" in output, "live /tree did not adopt the reloaded filter")

            # A fresh process must honor quietStartup and still reach the prompt.
            quiet_master, quiet_slave = pty.openpty()
            quiet = subprocess.Popen(
                command, cwd=workspace, env=env, stdin=quiet_slave, stdout=quiet_slave,
                stderr=subprocess.PIPE, close_fds=True,
            )
            os.close(quiet_slave)
            os.set_blocking(quiet_master, False)
            quiet_output = bytearray()
            try:
                quiet_pos = wait_for(quiet_master, quiet_output, quiet, b"> ")
                os.write(quiet_master, b"/quit\r")
                quiet_deadline = time.monotonic() + 20.0
                while quiet.poll() is None and time.monotonic() < quiet_deadline:
                    ready, _, _ = select.select([quiet_master], [], [], 0.1)
                    if ready:
                        with contextlib.suppress(OSError):
                            quiet_output.extend(os.read(quiet_master, 65536))
                require(quiet.poll() is not None and quiet.returncode == 0, "quiet-startup process did not exit cleanly")
                assert quiet.stderr is not None
                quiet_stderr = quiet.stderr.read().decode("utf-8", errors="replace")
                require(quiet_stderr == "", f"quiet-startup stderr: {quiet_stderr}")
                require(b"pi (pi-zig)" not in quiet_output[:quiet_pos], "quietStartup did not suppress the header")
            finally:
                with contextlib.suppress(OSError):
                    os.close(quiet_master)
                if quiet.poll() is None:
                    quiet.kill()
                    with contextlib.suppress(Exception):
                        quiet.wait(timeout=3)

            result = {
                "fullscreen": True,
                "retryEnabled": retry.get("enabled"),
                "retryMaxRetries": retry.get("maxRetries"),
                "nestedProviderPreserved": True,
                "unrelatedSettingPreserved": True,
                "liveReload": True,
                "steeringMode": persisted.get("steeringMode"),
                "followUpMode": persisted.get("followUpMode"),
                "treeFilterMode": persisted.get("treeFilterMode"),
                "liveTreeFilter": True,
                "quietStartup": True,
                "terminalRestored": True,
                "exit": int(process.returncode),
                "stderrBytes": len(stderr.encode()),
            }
            if report is not None:
                report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            return result
        finally:
            with contextlib.suppress(OSError):
                os.close(master)
            if process.poll() is None:
                process.kill()
                with contextlib.suppress(Exception):
                    process.wait(timeout=3)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = run(args.binary.resolve(), args.report.resolve() if args.report else None)
    print("SETTINGS_SCREEN_E2E_188=PASS")
    for key, value in result.items():
        print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
