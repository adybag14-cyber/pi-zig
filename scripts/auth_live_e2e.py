#!/usr/bin/env python3
"""Live provider credential rebinding validation for checkpoint 177."""
from __future__ import annotations

import argparse
import contextlib
import http.server
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import tempfile
import threading
import time
from typing import Any


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self) -> None:
        self.requests: list[dict[str, Any]] = []
        self.lock = threading.Lock()
        super().__init__(("127.0.0.1", 0), Handler)


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_: object) -> None:
        return

    def do_POST(self) -> None:  # noqa: N802
        server: Server = self.server  # type: ignore[assignment]
        length = int(self.headers.get("content-length", "0"))
        body = self.rfile.read(length)
        with server.lock:
            request_index = len(server.requests) + 1
            server.requests.append({
                "path": self.path,
                "authorization": self.headers.get("authorization", ""),
                "body": body,
            })
        content = f"auth-live-{request_index}-177"
        payload = (
            f'data: {{"id":"chatcmpl-auth-{request_index}","choices":[{{"delta":{{"content":"{content}"}}}}]}}\n\n'
            'data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}}\n\n'
            'data: [DONE]\n\n'
        ).encode()
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.send_header("content-length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
        self.wfile.flush()


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
    raise AssertionError(f"marker {marker!r} missing; tail={output[-8000:].decode(errors='replace')}")


def run(binary: Path, report: Path | None) -> dict[str, Any]:
    server = Server()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="pi-auth-live-177-") as raw:
            root = Path(raw)
            agent_dir = root / "agent"
            sessions = root / "sessions"
            workspace = root / "workspace"
            home = root / "home"
            for directory in (agent_dir, sessions, workspace, home):
                directory.mkdir()
            old_key = "configured-old-177"
            new_key = "interactive-new-177"
            (agent_dir / "models.json").write_text(json.dumps({
                "providers": {
                    "corp177": {
                        "name": "Corp 177",
                        "baseUrl": f"http://127.0.0.1:{server.server_port}/v1",
                        "api": "openai-completions",
                        "apiKey": old_key,
                        "models": [{
                            "id": "fast",
                            "name": "Fast 177",
                            "contextWindow": 4096,
                            "maxTokens": 512,
                        }],
                    }
                }
            }), encoding="utf-8")
            (agent_dir / "settings.json").write_text(json.dumps({
                "quietStartup": True,
                "enableInstallTelemetry": False,
                "collapseChangelog": True,
            }), encoding="utf-8")
            auth_path = agent_dir / "auth.json"

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
                str(binary), "--provider", "corp177", "--model", "fast",
                "--session-dir", str(sessions), "--no-context-files", "--no-skills",
                "--no-prompt-templates", "--no-themes", "--no-extensions", "--no-tools", "--approve",
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
                pos = wait_for(master, output, process, b"Select authentication method:", pos)
                os.write(master, b"\x1b[B\r")
                pos = wait_for(master, output, process, b"Select API key provider to configure:", pos)
                os.write(master, b"corp177")
                pos = wait_for(master, output, process, b"corp177_", pos)
                os.write(master, b"\r")
                pos = wait_for(master, output, process, b"Configure API key", pos)
                os.write(master, new_key.encode())
                os.write(master, b"\r")
                pos = wait_for(master, output, process, b"Credential stored in auth.json and activated for this process.", pos)
                pos = wait_for(master, output, process, b"> ", pos)

                stored = json.loads(auth_path.read_text(encoding="utf-8"))
                require(stored.get("corp177", {}).get("key") == new_key, f"new key not stored: {stored}")
                os.write(master, b"first live auth request\r")
                pos = wait_for(master, output, process, b"auth-live-1-177", pos)
                pos = wait_for(master, output, process, b"> ", pos)

                os.write(master, b"/logout\r")
                pos = wait_for(master, output, process, b"Select provider to logout:", pos)
                os.write(master, b"\r")
                pos = wait_for(master, output, process, b"Stored provider credential removed.", pos, timeout=120.0)
                pos = wait_for(master, output, process, b"> ", pos, timeout=120.0)
                removed = json.loads(auth_path.read_text(encoding="utf-8")) if auth_path.exists() else {}
                require("corp177" not in removed, f"credential was not removed: {removed}")

                os.write(master, b"second live auth request\r")
                pos = wait_for(master, output, process, b"auth-live-2-177", pos)
                pos = wait_for(master, output, process, b"> ", pos)
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
                require(new_key.encode() not in output, "interactive key leaked to terminal output")
            finally:
                with contextlib.suppress(OSError):
                    os.close(master)
                if process.poll() is None:
                    process.kill()
                    with contextlib.suppress(Exception):
                        process.wait(timeout=3)

            with server.lock:
                requests = list(server.requests)
            require(len(requests) == 2, f"provider request count {len(requests)}")
            require(requests[0]["path"].endswith("/chat/completions"), f"wrong first path: {requests[0]['path']}")
            require(requests[0]["authorization"] == f"Bearer {new_key}", f"login did not rebind active client: {requests[0]['authorization']}")
            require(requests[1]["authorization"] == f"Bearer {old_key}", f"logout did not restore configured credential: {requests[1]['authorization']}")

            result = {
                "activeProvider": "corp177/fast",
                "interactiveKeyStored": True,
                "loginReboundActiveClient": True,
                "firstAuthorization": "interactive key",
                "logoutRemovedStoredCredential": True,
                "logoutReloadedConfiguredCredential": True,
                "secondAuthorization": "models.json key",
                "providerRequests": len(requests),
                "secretAbsentFromTerminal": True,
                "exit": 0,
                "stderrBytes": 0,
            }
            if report is not None:
                report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            return result
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = run(args.binary.resolve(), args.report.resolve() if args.report else None)
    print("AUTH_LIVE_E2E_177=PASS")
    for key, value in result.items():
        print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
