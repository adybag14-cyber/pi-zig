#!/usr/bin/env python3
"""Provider-image privacy and live skill-command validation for checkpoint 172."""
from __future__ import annotations

import argparse
import base64
import contextlib
import http.server
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time
from typing import Any

SUCCESS_SSE = (
    'data: {"id":"chatcmpl-172","choices":[{"delta":{"content":"media-policy-ok-172"}}]}\n\n'
    'data: {"choices":[{"delta":{},"finish_reason":"stop"}],'
    '"usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}}\n\n'
    'data: [DONE]\n\n'
).encode()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def tiny_bmp() -> bytes:
    """Return a valid 1x1 24-bit BMP without relying on image libraries."""
    data = bytearray(58)
    data[0:2] = b"BM"
    data[2:6] = (58).to_bytes(4, "little")
    data[10:14] = (54).to_bytes(4, "little")
    data[14:18] = (40).to_bytes(4, "little")
    data[18:22] = (1).to_bytes(4, "little", signed=True)
    data[22:26] = (1).to_bytes(4, "little", signed=True)
    data[26:28] = (1).to_bytes(2, "little")
    data[28:30] = (24).to_bytes(2, "little")
    data[34:38] = (4).to_bytes(4, "little")
    data[54:58] = bytes((0x33, 0x66, 0xCC, 0x00))
    return bytes(data)


class CaptureServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self) -> None:
        self.requests: list[dict[str, Any]] = []
        self.lock = threading.Lock()
        super().__init__(("127.0.0.1", 0), CaptureHandler)


class CaptureHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_: object) -> None:
        return

    def do_POST(self) -> None:  # noqa: N802
        server: CaptureServer = self.server  # type: ignore[assignment]
        length = int(self.headers.get("content-length", "0"))
        body = self.rfile.read(length)
        with server.lock:
            server.requests.append({
                "path": self.path,
                "headers": {name.lower(): value for name, value in self.headers.items()},
                "body": body,
            })
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.send_header("content-length", str(len(SUCCESS_SSE)))
        self.end_headers()
        self.wfile.write(SUCCESS_SSE)
        self.wfile.flush()


@contextlib.contextmanager
def serving():
    server = CaptureServer()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)


def json_contains_image(value: Any) -> bool:
    if isinstance(value, str):
        lowered = value.lower()
        return "data:image/" in lowered or lowered.startswith("image/") and len(value) > 20
    if isinstance(value, list):
        return any(json_contains_image(item) for item in value)
    if isinstance(value, dict):
        for key, item in value.items():
            lowered = key.lower()
            if lowered in {"image_url", "input_image", "image", "inline_data", "inlinedata"}:
                return True
            if json_contains_image(item):
                return True
    return False


def json_contains_text(value: Any, needle: str) -> bool:
    if isinstance(value, str):
        return needle in value
    if isinstance(value, list):
        return any(json_contains_text(item, needle) for item in value)
    if isinstance(value, dict):
        return any(json_contains_text(item, needle) for item in value.values())
    return False


def run_image_case(binary: Path, blocked: bool) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix=f"pi-media-172-{'blocked' if blocked else 'allowed'}-") as raw:
        root = Path(raw)
        workspace = root / "workspace"
        workspace.mkdir()
        agent_dir = root / "agent"
        agent_dir.mkdir()
        session_dir = root / "sessions"
        session_dir.mkdir()
        image_path = workspace / "pixel-renamed.dat"
        image_bytes = tiny_bmp()
        image_path.write_bytes(image_bytes)
        image_b64 = base64.b64encode(image_bytes).decode()

        (agent_dir / "settings.json").write_text(json.dumps({
            "images": {"blockImages": blocked},
            "terminal": {"showImages": False, "imageWidthCells": 80},
            "enableInstallTelemetry": False,
            "quietStartup": True,
        }), encoding="utf-8")

        with serving() as server:
            env = os.environ.copy()
            env["PI_AGENT_DIR"] = str(agent_dir)
            session_id = "media-blocked-172" if blocked else "media-allowed-172"
            command = [
                str(binary),
                "--provider", "baseten",
                "--model", "moonshotai/Kimi-K2.5",
                "--base-url", f"http://127.0.0.1:{server.server_port}/v1",
                "--api-key", "media-key-172",
                "--mode", "json",
                "--session-dir", str(session_dir),
                "--session-id", session_id,
                "--no-tools",
                "--no-extensions",
                "--no-context-files",
                "--no-skills",
                "--no-prompt-templates",
                "--print", "describe the attached checkpoint image",
                f"@{image_path}",
            ]
            result = subprocess.run(
                command,
                cwd=workspace,
                env=env,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )

        require(result.returncode == 0, f"image case blocked={blocked}: exit={result.returncode} stderr={result.stderr}")
        require(result.stderr == "", f"image case blocked={blocked}: stderr={result.stderr}")
        require(len(server.requests) == 1, f"image case blocked={blocked}: requests={len(server.requests)}")
        request = server.requests[0]
        require(request["path"].endswith("/chat/completions"), f"unexpected provider path: {request['path']}")
        payload = json.loads(request["body"])
        provider_has_image = json_contains_image(payload)
        provider_has_placeholder = json_contains_text(payload, "Image reading is disabled.")

        if blocked:
            require(not provider_has_image, f"blocked request leaked image payload: {payload}")
            require(provider_has_placeholder, f"blocked request missing placeholder: {payload}")
        else:
            require(provider_has_image, f"allowed request lost image payload: {payload}")
            require(not provider_has_placeholder, f"allowed request unexpectedly contains blocked placeholder: {payload}")

        session_path = session_dir / f"{session_id}.jsonl"
        require(session_path.is_file(), f"session file missing: {session_path}")
        session_text = session_path.read_text(encoding="utf-8")
        require(image_b64 in session_text, "durable session did not retain the exact image bytes")
        require("image/bmp" in session_text, "durable session did not retain image MIME type")
        require("media-policy-ok-172" in session_text, "assistant response missing from durable session")
        require("media-policy-ok-172" in result.stdout, "assistant response missing from JSON output")
        return {
            "blocked": blocked,
            "providerHasImage": provider_has_image,
            "providerHasPlaceholder": provider_has_placeholder,
            "durableImageRetained": True,
            "stderrBytes": 0,
        }


class RpcHarness:
    def __init__(self, command: list[str], env: dict[str, str], cwd: Path):
        self.process = subprocess.Popen(
            command,
            cwd=cwd,
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        assert self.process.stdin is not None
        assert self.process.stdout is not None
        self.lines: queue.Queue[str] = queue.Queue()
        self.raw: list[str] = []
        self.reader = threading.Thread(target=self._read_stdout, daemon=True)
        self.reader.start()

    def _read_stdout(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.lines.put(line.rstrip("\n"))

    def send(self, payload: dict[str, Any]) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self.process.stdin.flush()

    def wait_response(self, request_id: str, timeout: float = 20.0) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                line = self.lines.get(timeout=max(0.01, deadline - time.monotonic()))
            except queue.Empty as exc:
                raise AssertionError(f"RPC timeout id={request_id}; tail={self.raw[-20:]}") from exc
            self.raw.append(line)
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            if item.get("type") == "response" and str(item.get("id")) == request_id:
                return item
        raise AssertionError(f"RPC timeout id={request_id}; tail={self.raw[-20:]}")

    def finish(self) -> tuple[int, str]:
        assert self.process.stdin is not None
        self.process.stdin.close()
        code = self.process.wait(timeout=15)
        assert self.process.stderr is not None
        stderr = self.process.stderr.read()
        self.reader.join(timeout=2)
        return code, stderr


def command_names(response: dict[str, Any]) -> set[str]:
    require(response.get("success") is True, f"RPC command response failed: {response}")
    data = response.get("data")
    require(isinstance(data, dict), f"RPC command data is not an object: {response}")
    commands = data.get("commands")
    require(isinstance(commands, list), f"RPC commands is not an array: {response}")
    return {str(command.get("name")) for command in commands if isinstance(command, dict)}


def run_skill_reload(binary: Path) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pi-skill-settings-172-") as raw:
        root = Path(raw)
        workspace = root / "workspace"
        workspace.mkdir()
        agent_dir = root / "agent"
        skill_dir = agent_dir / "skills" / "checkpoint172"
        skill_dir.mkdir(parents=True)
        (skill_dir / "SKILL.md").write_text(
            "---\nname: checkpoint172\ndescription: Checkpoint 172 command-discovery fixture\n---\n\nUse this fixture.\n",
            encoding="utf-8",
        )
        settings_path = agent_dir / "settings.json"
        settings_path.write_text(json.dumps({
            "enableSkillCommands": False,
            "enableInstallTelemetry": False,
            "quietStartup": True,
        }), encoding="utf-8")
        mock = root / "mock.json"
        mock.write_text(json.dumps([{"content": "unused-172"}]), encoding="utf-8")

        env = os.environ.copy()
        env["PI_AGENT_DIR"] = str(agent_dir)
        command = [
            str(binary),
            "--offline",
            "--mock-script", str(mock),
            "--mode", "rpc",
            "--no-session",
            "--no-tools",
            "--no-extensions",
            "--no-context-files",
        ]
        rpc = RpcHarness(command, env, workspace)
        try:
            rpc.send({"id": "c1", "type": "get_commands"})
            disabled_response = rpc.wait_response("c1")
            disabled_names = command_names(disabled_response)
            require("skill:checkpoint172" not in disabled_names, f"disabled skill leaked into RPC commands: {disabled_names}")

            # Replace settings atomically so the persistent process must rebuild
            # its runtime command policy through the ordinary reload path.
            replacement = settings_path.with_suffix(".json.tmp")
            replacement.write_text(json.dumps({
                "enableSkillCommands": True,
                "enableInstallTelemetry": False,
                "quietStartup": True,
            }), encoding="utf-8")
            os.replace(replacement, settings_path)

            rpc.send({"id": "r1", "type": "reload"})
            reload_response = rpc.wait_response("r1")
            require(reload_response.get("success") is True, f"runtime reload failed: {reload_response}")

            rpc.send({"id": "c2", "type": "get_commands"})
            enabled_response = rpc.wait_response("c2")
            enabled_names = command_names(enabled_response)
            require("skill:checkpoint172" in enabled_names, f"enabled skill missing from RPC commands: {enabled_names}")

            rpc.send({"id": "q1", "type": "quit"})
            quit_response = rpc.wait_response("q1")
            require(quit_response.get("success") is True, f"RPC quit failed: {quit_response}")
            code, stderr = rpc.finish()
            require(code == 0, f"skill RPC exit={code}")
            require(stderr == "", f"skill RPC stderr={stderr}")
            return {
                "disabledCommandCount": len(disabled_names),
                "enabledSkillPresent": True,
                "liveReload": True,
                "stderrBytes": 0,
            }
        except BaseException:
            rpc.process.kill()
            with contextlib.suppress(Exception):
                rpc.process.wait(timeout=3)
            raise


def run(binary: Path, report: Path | None) -> dict[str, Any]:
    blocked = run_image_case(binary, True)
    allowed = run_image_case(binary, False)
    skills = run_skill_reload(binary)
    result = {
        "blockedProviderImage": not blocked["providerHasImage"],
        "blockedPlaceholder": blocked["providerHasPlaceholder"],
        "blockedDurableImage": blocked["durableImageRetained"],
        "allowedProviderImage": allowed["providerHasImage"],
        "allowedDurableImage": allowed["durableImageRetained"],
        "skillDisabledHidden": True,
        "skillEnabledAfterReload": skills["enabledSkillPresent"],
        "rpcReload": skills["liveReload"],
        "stderrBytes": 0,
    }
    if report is not None:
        report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = run(args.binary.resolve(), args.report.resolve() if args.report else None)
    print("MEDIA_SKILL_SETTINGS_E2E_172=PASS")
    for key, value in result.items():
        print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
