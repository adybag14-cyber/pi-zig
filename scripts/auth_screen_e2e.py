#!/usr/bin/env python3
"""Real PTY validation for checkpoint 177 login/logout account selectors."""
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


def wait_for(master: int, output: bytearray, process: subprocess.Popen[bytes], marker: bytes, start: int = 0, timeout: float = 45.0) -> int:
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
                output.extend(os.read(master, 65536))
            except OSError:
                pass
    raise AssertionError(f"marker {marker!r} missing; tail={output[-8000:].decode(errors='replace')}")


def run(binary: Path, report: Path | None) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pi-auth-screen-177-") as raw:
        root = Path(raw)
        agent_dir = root / "agent"
        sessions = root / "sessions"
        workspace = root / "workspace"
        home = root / "home"
        for directory in (agent_dir, sessions, workspace, home):
            directory.mkdir()
        mock = root / "mock.json"
        mock.write_text(json.dumps([{"content": "unused-auth-177"}]), encoding="utf-8")
        auth_path = agent_dir / "auth.json"
        secret = "screen-secret-177"

        env = os.environ.copy()
        env.update({
            "PI_AGENT_DIR": str(agent_dir),
            "TERM": "xterm-256color",
            "HOME": str(home),
            "NO_COLOR": "1",
            "PI_SKIP_VERSION_CHECK": "1",
            "PI_TELEMETRY": "0",
        })
        command = [
            str(binary), "--offline", "--mock-script", str(mock),
            "--session-dir", str(sessions), "--no-context-files", "--no-skills",
            "--no-prompt-templates", "--no-themes", "--no-extensions", "--approve",
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
            os.write(master, b"/login\r")
            screen_start = len(output)
            pos = wait_for(master, output, process, b"Select authentication method:", screen_start)
            require(b"\x1b[?1049h" in output[screen_start:] or b"\x1b[2J" in output[screen_start:], "login selector did not enter fullscreen")
            os.write(master, b"\x1b[B\r")
            pos = wait_for(master, output, process, b"Select API key provider to configure:", pos)
            os.write(master, b"openai")
            pos = wait_for(master, output, process, b"openai_", pos)
            pos = wait_for(master, output, process, b"OpenAI", pos)
            os.write(master, b"\r")
            pos = wait_for(master, output, process, b"Configure API key", pos)
            os.write(master, secret.encode("utf-8"))
            masked_start = len(output)
            pos = wait_for(master, output, process, b"Key: ", masked_start)
            require(secret.encode() not in output[masked_start:], "secret was rendered in fullscreen selector")
            os.write(master, b"\r")
            pos = wait_for(master, output, process, b"Credential stored in auth.json and activated for this process.", pos)
            pos = wait_for(master, output, process, b"> ", pos)

            require(auth_path.is_file(), "auth.json was not created")
            stored = json.loads(auth_path.read_text(encoding="utf-8"))
            openai = stored.get("openai", {})
            require(openai.get("type") == "api_key", f"wrong auth type: {stored}")
            require(openai.get("key") == secret, "stored API key mismatch")
            mode = auth_path.stat().st_mode & 0o777
            require(mode & 0o077 == 0, f"auth.json permissions too broad: {oct(mode)}")

            os.write(master, b"/logout\r")
            logout_start = len(output)
            pos = wait_for(master, output, process, b"Select provider to logout:", logout_start)
            require(b"OpenAI" in output[logout_start:], "stored provider absent from logout selector")
            require(b"configured" in output[logout_start:], "logout selector did not show configured status")
            os.write(master, b"\r")
            pos = wait_for(master, output, process, b"Stored provider credential removed.", pos, timeout=90.0)
            pos = wait_for(master, output, process, b"> ", pos, timeout=90.0)

            after = json.loads(auth_path.read_text(encoding="utf-8")) if auth_path.exists() else {}
            require("openai" not in after, f"logout did not remove openai: {after}")
            require(secret.encode() not in output, "secret leaked into PTY output")
            require(b"\x1b[?1049l" in output or b"\x1b[2J" in output, "selector did not restore terminal")

            os.write(master, b"/quit\r")
            deadline = time.monotonic() + 30.0
            while process.poll() is None and time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.1)
                if ready:
                    with contextlib.suppress(OSError):
                        output.extend(os.read(master, 65536))
            require(process.poll() is not None, "interactive process did not exit")
            assert process.stderr is not None
            stderr = process.stderr.read().decode("utf-8", errors="replace")
            require(process.returncode == 0, f"process exit {process.returncode}: {stderr}")
            require(stderr == "", f"unexpected stderr: {stderr}")

            result = {
                "loginFullscreen": True,
                "maskedSecret": True,
                "apiKeyStored": True,
                "authPermissionsPrivate": True,
                "logoutFullscreen": True,
                "storedStatusVisible": True,
                "credentialRemoved": True,
                "secretAbsentFromTerminal": True,
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
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = run(args.binary.resolve(), args.report.resolve() if args.report else None)
    print("AUTH_SCREEN_E2E_177=PASS")
    for key, value in result.items():
        print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
