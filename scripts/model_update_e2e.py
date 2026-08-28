#!/usr/bin/env python3
"""Real PTY and loopback HTTP validation for checkpoint 169 model/update parity."""
from __future__ import annotations

import argparse
import contextlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import tarfile
import tempfile
import threading
import time
from typing import Any


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


class State:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.latest = 0
        self.report = 0
        self.report_query = ""
        self.rg_release = 0
        self.rg_download = 0
        self.rg_archive = b""


class Handler(BaseHTTPRequestHandler):
    server_version = "PiCheckpoint169/1"

    def do_GET(self) -> None:  # noqa: N802
        state: State = self.server.state  # type: ignore[attr-defined]
        if self.path == "/latest":
            with state.lock:
                state.latest += 1
            body = json.dumps({
                "version": "0.85.0",
                "packageName": "@earendil-works/pi-coding-agent",
                "note": "checkpoint-169-update-note",
            }).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path.startswith("/report?"):
            with state.lock:
                state.report += 1
                state.report_query = self.path
            self.send_response(204)
            self.end_headers()
            return
        if self.path == "/rg-release":
            with state.lock:
                state.rg_release += 1
            body = json.dumps({"tag_name": "v14.1.1"}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == "/rg-download":
            with state.lock:
                state.rg_download += 1
                body = state.rg_archive
            self.send_response(200)
            self.send_header("Content-Type", "application/gzip")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, _format: str, *_args: object) -> None:
        return


def run_pty(command: list[str], env: dict[str, str], cwd: Path) -> tuple[int, bytes, str]:
    master, slave = pty.openpty()
    process = subprocess.Popen(
        command,
        env=env,
        cwd=cwd,
        stdin=slave,
        stdout=slave,
        stderr=subprocess.PIPE,
        close_fds=True,
    )
    os.close(slave)
    os.set_blocking(master, False)
    output = bytearray()

    def read_available(timeout: float) -> None:
        ready, _, _ = select.select([master], [], [], timeout)
        if not ready:
            return
        try:
            output.extend(os.read(master, 65536))
        except OSError:
            pass

    def wait(marker: bytes, start: int = 0, timeout: float = 30.0) -> int:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            found = output.find(marker, start)
            if found >= 0:
                return found + len(marker)
            if process.poll() is not None:
                break
            read_available(min(0.1, max(0.0, deadline - time.monotonic())))
        raise AssertionError(f"PTY marker {marker!r} missing; tail={output[-6000:].decode(errors='replace')}")

    try:
        pos = wait(b"Type a prompt")
        pos = wait(b"> ", pos)
        os.write(master, b"/model gpt-4.1-mini\r")
        pos = wait(b"Select Model", pos)
        pos = wait(b"gpt-4.1-mini", pos)
        os.write(master, b"\r")
        pos = wait(b"Model switched to openai/gpt-4.1-mini.", pos)
        # Give the intentionally detached anonymous install ping time to reach
        # the loopback endpoint before ending this short-lived fixture.
        time.sleep(0.35)
        read_available(0.15)
        os.write(master, b"/quit\r")
        deadline = time.monotonic() + 30.0
        while process.poll() is None and time.monotonic() < deadline:
            read_available(0.1)
        require(process.poll() is not None, "PTY exit timeout")
        for _ in range(10):
            read_available(0.02)
        assert process.stderr is not None
        stderr = process.stderr.read().decode("utf-8", errors="replace")
        return int(process.returncode), bytes(output), stderr
    finally:
        with contextlib.suppress(OSError):
            os.close(master)
        if process.poll() is None:
            process.kill()
            with contextlib.suppress(Exception):
                process.wait(timeout=3)


def make_rg_archive() -> bytes:
    script = b'#!/bin/sh\nprintf \'managed-rg-169:%s\\n\' "$*"\n'
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w:gz") as archive:
        info = tarfile.TarInfo("ripgrep-14.1.1-x86_64-unknown-linux-musl/rg")
        info.mode = 0o755
        info.size = len(script)
        archive.addfile(info, io.BytesIO(script))
    return stream.getvalue()


def run_captured(command: list[str], cwd: Path, env: dict[str, str], root: Path, label: str) -> subprocess.CompletedProcess[str]:
    stdout_path = root / f"{label}.stdout"
    stderr_path = root / f"{label}.stderr"
    with stdout_path.open("wb") as stdout_file, stderr_path.open("wb") as stderr_file:
        process = subprocess.Popen(
            command, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=stdout_file, stderr=stderr_file,
            start_new_session=True,
        )
        deadline = time.monotonic() + 30.0
        while process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.05)
        if process.poll() is None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, 9)
            for _ in range(100):
                if process.poll() is not None:
                    break
                time.sleep(0.01)
            output = stdout_path.read_text(encoding="utf-8", errors="replace")
            errors = stderr_path.read_text(encoding="utf-8", errors="replace")
            raise AssertionError(f"{label} timed out; stdout={output[-4000:]} stderr={errors[-4000:]}")
        returncode = int(process.returncode)
    return subprocess.CompletedProcess(
        command, returncode,
        stdout_path.read_text(encoding="utf-8", errors="replace"),
        stderr_path.read_text(encoding="utf-8", errors="replace"),
    )


def run_managed_rg(
    binary: Path,
    root: Path,
    agent_dir: Path,
    port: int,
    state: State,
) -> tuple[int, int, str]:
    helper_dir = root / "tool-path"
    helper_dir.mkdir(exist_ok=True)
    for name in ("tar", "gzip"):
        target = subprocess.check_output(["/usr/bin/env", "sh", "-c", f"command -v {name}"], text=True).strip()
        require(bool(target), f"missing host extraction helper {name}")
        link = helper_dir / name
        if not link.exists():
            link.symlink_to(target)

    workspace = root / "tool-workspace"
    workspace.mkdir(exist_ok=True)
    (workspace / "fixture.txt").write_text("needle-169\n", encoding="utf-8")
    script_path = root / "managed-rg-mock.json"
    script_path.write_text(json.dumps([
        {
            "content": "running managed grep",
            "tool_calls": [{
                "id": "managed-rg-call-169",
                "name": "grep",
                "arguments": json.dumps({"pattern": "needle-169", "path": "."}),
            }],
        },
        {"content": "managed-tool-complete-169", "tool_calls": []},
    ]), encoding="utf-8")

    env = os.environ.copy()
    env.update({
        "PI_AGENT_DIR": str(agent_dir),
        "PI_TOOL_RG_RELEASE_URL": f"http://127.0.0.1:{port}/rg-release",
        "PI_TOOL_RG_DOWNLOAD_URL": f"http://127.0.0.1:{port}/rg-download",
        "PI_SKIP_VERSION_CHECK": "1",
        "PI_TELEMETRY": "0",
        "PATH": str(helper_dir),
        "NO_COLOR": "1",
    })
    command = [
        str(binary), "-p", "--mode", "json",
        "--mock-script", str(script_path),
        "--session-dir", str(root / "tool-sessions"),
        "--no-context-files", "--no-skills", "--no-prompt-templates",
        "--no-themes", "--no-extensions", "--tools", "grep", "--approve",
        "exercise managed grep",
    ]

    first = run_captured(command, workspace, env, root, "managed-rg-first")
    require(first.returncode == 0, f"first managed rg exit {first.returncode}: {first.stderr}")
    require(first.stderr == "", f"first managed rg stderr: {first.stderr}")
    require("managed-rg-169:" in first.stdout, f"managed rg output missing: {first.stdout[-4000:]}")
    require("managed-tool-complete-169" in first.stdout, "managed rg final response missing")
    installed = agent_dir / "bin" / "rg"
    require(installed.is_file(), f"managed rg not installed: {installed}")
    require(os.access(installed, os.X_OK), "managed rg is not executable")

    with state.lock:
        release_after_first = state.rg_release
        download_after_first = state.rg_download
    require(release_after_first == 1, f"rg release requests after first run: {release_after_first}")
    require(download_after_first == 1, f"rg download requests after first run: {download_after_first}")

    second = run_captured(command, workspace, env, root, "managed-rg-second")
    require(second.returncode == 0, f"second managed rg exit {second.returncode}: {second.stderr}")
    require(second.stderr == "", f"second managed rg stderr: {second.stderr}")
    require("managed-rg-169:" in second.stdout, "cached managed rg did not execute")
    with state.lock:
        release_final = state.rg_release
        download_final = state.rg_download
    require(release_final == 1, f"cached run repeated release request: {release_final}")
    require(download_final == 1, f"cached run repeated download: {download_final}")
    return release_final, download_final, str(installed)


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def run(binary: Path, report: Path | None) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pi-model-update-169-") as raw:
        root = Path(raw)
        agent_dir = root / "agent"
        session_dir = root / "sessions"
        agent_dir.mkdir()
        session_dir.mkdir()
        mock = root / "mock.json"
        mock.write_text(json.dumps([{"content": "unused-169"}]), encoding="utf-8")
        (agent_dir / "settings.json").write_text(json.dumps({
            "lastChangelogVersion": "0.84.0",
            "collapseChangelog": True,
            "enableInstallTelemetry": True,
            "retry": {"enabled": False},
        }), encoding="utf-8")

        state = State()
        state.rg_archive = make_rg_archive()
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        server.state = state  # type: ignore[attr-defined]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        port = server.server_address[1]

        env = os.environ.copy()
        env.update({
            "PI_AGENT_DIR": str(agent_dir),
            "PI_LATEST_VERSION_URL": f"http://127.0.0.1:{port}/latest",
            "PI_REPORT_INSTALL_URL": f"http://127.0.0.1:{port}/report",
            "OPENAI_API_KEY": "checkpoint-169-test-key",
            "TERM": "xterm-256color",
            "NO_COLOR": "1",
        })
        command = [
            str(binary),
            "--mock-script", str(mock),
            "--session-dir", str(session_dir),
            "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes",
            "--no-tools", "--approve",
        ]
        try:
            code, raw_output, stderr = run_pty(command, env, root)
            rg_release_requests, rg_download_requests, rg_path = run_managed_rg(
                binary, root, agent_dir, port, state
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        text = raw_output.decode("utf-8", errors="replace")
        require(code == 0, f"process exit {code}")
        require(stderr == "", f"stderr not empty: {stderr}")
        require("Updated to upstream Pi v0.84.1" in text, "condensed changelog notice missing")
        require("Upstream Pi update available: v0.85.0" in text, "latest release notice missing")
        require("checkpoint-169-update-note" in text, "release note missing")
        require("Select Model" in text, "fullscreen model selector missing")
        require("Model switched to openai/gpt-4.1-mini." in text, "model switch acknowledgement missing")

        with state.lock:
            latest_requests = state.latest
            report_requests = state.report
            report_query = state.report_query
        require(latest_requests == 1, f"latest request count {latest_requests}")
        require(report_requests == 1, f"report request count {report_requests}")
        require("version=0.84.1" in report_query, f"report version missing: {report_query}")

        settings = json.loads((agent_dir / "settings.json").read_text(encoding="utf-8"))
        require(settings.get("lastChangelogVersion") == "0.84.1", f"lifecycle version not persisted: {settings}")
        require(settings.get("collapseChangelog") is True, "unrelated lifecycle setting changed")

        session_files = sorted(session_dir.rglob("*.jsonl"))
        require(len(session_files) == 1, f"unexpected session files: {session_files}")
        records = load_jsonl(session_files[0])
        changes = [entry for entry in records if entry.get("type") == "model_change"]
        require(len(changes) == 1, f"model change missing/duplicated: {changes}")
        require(changes[0].get("provider") == "openai", f"wrong provider: {changes[0]}")
        require(changes[0].get("modelId") == "gpt-4.1-mini", f"wrong model: {changes[0]}")

        result = {
            "exit": code,
            "latestRequests": latest_requests,
            "reportRequests": report_requests,
            "lifecycleVersion": settings.get("lastChangelogVersion"),
            "fullscreenModelSelector": True,
            "selectedModel": "openai/gpt-4.1-mini",
            "modelChangeEntries": len(changes),
            "managedRgReleaseRequests": rg_release_requests,
            "managedRgDownloadRequests": rg_download_requests,
            "managedRgPath": "agent/bin/rg",
            "stderrBytes": len(stderr.encode()),
        }
        text_report = "\n".join([
            "MODEL_UPDATE_E2E_169=PASS",
            f"LATEST_REQUESTS={latest_requests}",
            f"REPORT_REQUESTS={report_requests}",
            "LIFECYCLE_VERSION=0.84.1",
            "FULLSCREEN_MODEL_SELECTOR=PASS",
            "SELECTED_MODEL=openai/gpt-4.1-mini",
            f"MODEL_CHANGE_ENTRIES={len(changes)}",
            "MANAGED_RG_INSTALL=PASS",
            f"MANAGED_RG_RELEASE_REQUESTS={rg_release_requests}",
            f"MANAGED_RG_DOWNLOAD_REQUESTS={rg_download_requests}",
            "MANAGED_RG_CACHE_REUSE=PASS",
            "STDERR_BYTES=0",
            "",
            json.dumps(result, sort_keys=True),
        ]) + "\n"
        if report is not None:
            report.write_text(text_report, encoding="utf-8")
        print(text_report, end="")
        return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    run(args.binary.resolve(), args.report.resolve() if args.report else None)


if __name__ == "__main__":
    main()
