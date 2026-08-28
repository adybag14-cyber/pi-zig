#!/usr/bin/env python3
"""Real PTY validation for staged authentication selection and source labels."""
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


def wait_for(master: int, output: bytearray, process: subprocess.Popen[bytes], marker: bytes, start: int = 0, timeout: float = 60.0) -> int:
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
    raise AssertionError(f"marker {marker!r} missing; tail={output[-12000:].decode(errors='replace')}")


def drain_until_exit(master: int, output: bytearray, process: subprocess.Popen[bytes], timeout: float = 30.0) -> None:
    deadline = time.monotonic() + timeout
    while process.poll() is None and time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.1)
        if ready:
            with contextlib.suppress(OSError):
                output.extend(os.read(master, 65536))
    require(process.poll() is not None, "interactive process did not exit")


def run(binary: Path, report: Path | None) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pi-auth-flow-178-") as raw:
        root = Path(raw)
        agent_dir = root / "agent"
        sessions = root / "sessions"
        workspace = root / "workspace"
        home = root / "home"
        for directory in (agent_dir, sessions, workspace, home):
            directory.mkdir()

        (agent_dir / "models.json").write_text(json.dumps({
            "providers": {
                "corp178": {
                    "name": "Corp 178",
                    "baseUrl": "https://corp.invalid/v1",
                    "api": "openai-completions",
                    "apiKey": "$CORP178_API_KEY",
                    "oauth": "radius",
                    "models": [{"id": "fast", "name": "Fast 178"}],
                }
            }
        }), encoding="utf-8")
        (agent_dir / "auth.json").write_text(json.dumps({
            "anthropic": {"type": "api_key", "key": "existing-anthropic-178"}
        }), encoding="utf-8")
        os.chmod(agent_dir / "auth.json", 0o600)
        mock = root / "mock.json"
        mock.write_text(json.dumps([{"content": "unused-auth-flow-178"}]), encoding="utf-8")
        corp_secret = "corp-entered-secret-178"
        anthropic_secret = "anthropic-entered-secret-178"

        env = os.environ.copy()
        env.update({
            "PI_AGENT_DIR": str(agent_dir),
            "TERM": "xterm-256color",
            "COLUMNS": "120",
            "LINES": "38",
            "HOME": str(home),
            "NO_COLOR": "1",
            "OPENAI_API_KEY": "openai-env-secret-178",
            "CORP178_API_KEY": "corp-env-secret-178",
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

            # Stage one: authentication type, then subscription providers.
            os.write(master, b"/login\r")
            stage_start = len(output)
            pos = wait_for(master, output, process, b"Select authentication method:", stage_start)
            require(b"Sign in with an account" in output[stage_start:], "account authentication type missing")
            require(b"Sign in with an API key" in output[stage_start:], "API-key authentication type missing")
            os.write(master, b"\r")
            pos = wait_for(master, output, process, b"Select subscription provider to configure:", pos)
            os.write(master, b"anthropic")
            pos = wait_for(master, output, process, b"anthropic_", pos)
            pos = wait_for(master, output, process, b"API key configured", pos)
            # Escape once clears search, again returns to type selection, again cancels.
            os.write(master, b"\x1b")
            pos = wait_for(master, output, process, b"1/7 options", pos)
            os.write(master, b"\x1b")
            pos = wait_for(master, output, process, b"Select authentication method:", pos)
            os.write(master, b"\x1b")
            pos = wait_for(master, output, process, b"\x1b[?2004h\r\x1b[2K> ", pos)

            # API-key type shows environment and models.json-backed status sources.
            os.write(master, b"/login\r")
            pos = wait_for(master, output, process, b"Select authentication method:", pos)
            os.write(master, b"\x1b[B\r")
            pos = wait_for(master, output, process, b"Select API key provider to configure:", pos)
            os.write(master, b"openai")
            pos = wait_for(master, output, process, b"openai_", pos)
            pos = wait_for(master, output, process, b"env: OPENAI_API_KEY", pos)
            os.write(master, b"\x1b[3~")
            pos = wait_for(master, output, process, b"options", pos)
            os.write(master, b"corp178")
            pos = wait_for(master, output, process, b"corp178_", pos)
            pos = wait_for(master, output, process, b"configured API key", pos)
            os.write(master, b"\r")
            pos = wait_for(master, output, process, b"Configure API key", pos)
            os.write(master, corp_secret.encode("utf-8"))
            masked_start = len(output)
            pos = wait_for(master, output, process, b"Key: ", masked_start)
            require(corp_secret.encode() not in output[masked_start:], "corp secret rendered in key editor")
            os.write(master, b"\r")
            pos = wait_for(master, output, process, b"Credential stored in auth.json and activated for this process.", pos)
            pos = wait_for(master, output, process, b"> ", pos)

            # Explicit provider with two methods opens the scoped type stage.
            os.write(master, b"/login anthropic\r")
            scoped_start = len(output)
            pos = wait_for(master, output, process, b"Select authentication method for anthropic:", scoped_start)
            require(b"Sign in with an account" in output[scoped_start:], "scoped account method missing")
            require(b"Sign in with an API key" in output[scoped_start:], "scoped API-key method missing")
            require(b"API key configured" in output[scoped_start:], "scoped status mismatch was not shown")
            os.write(master, b"\x1b[B\r")
            pos = wait_for(master, output, process, b"Configure API key", pos)
            os.write(master, anthropic_secret.encode("utf-8"))
            os.write(master, b"\r")
            pos = wait_for(master, output, process, b"Credential stored in auth.json and activated for this process.", pos)
            pos = wait_for(master, output, process, b"> ", pos)

            stored = json.loads((agent_dir / "auth.json").read_text(encoding="utf-8"))
            require(stored.get("corp178", {}).get("key") == corp_secret, f"corp key not stored: {stored}")
            require(stored.get("anthropic", {}).get("key") == anthropic_secret, f"anthropic key not replaced: {stored}")
            require(corp_secret.encode() not in output, "corp secret leaked to terminal")
            require(anthropic_secret.encode() not in output, "anthropic secret leaked to terminal")
            require(b"\x1b[?1049h" in output or b"\x1b[2J" in output, "selector did not enter fullscreen")
            require(b"\x1b[?1049l" in output or b"\x1b[2J" in output, "selector did not restore terminal")

            os.write(master, b"/quit\r")
            drain_until_exit(master, output, process)
            assert process.stderr is not None
            stderr = process.stderr.read().decode("utf-8", errors="replace")
            require(process.returncode == 0, f"process exit {process.returncode}: {stderr}")
            require(stderr == "", f"unexpected stderr: {stderr}")

            result = {
                "stagedAuthenticationType": True,
                "subscriptionProviderStage": True,
                "apiKeyProviderStage": True,
                "storedTypeMismatchVisible": True,
                "environmentSourceVisible": "OPENAI_API_KEY",
                "configuredSourceVisible": "configured API key",
                "explicitProviderScopedStage": "anthropic",
                "corpCredentialStored": True,
                "anthropicCredentialReplaced": True,
                "secretsAbsentFromTerminal": True,
                "terminalRestored": True,
                "exit": int(process.returncode),
                "stderrBytes": len(stderr.encode()),
            }
            if report is not None:
                report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            return result
        finally:
            debug_path = os.environ.get("PI_AUTH_FLOW_DEBUG_OUTPUT")
            if debug_path:
                Path(debug_path).write_bytes(bytes(output))
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
    print("AUTH_FLOW_E2E_178=PASS")
    for key, value in result.items():
        print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
