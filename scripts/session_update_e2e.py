#!/usr/bin/env python3
"""Real PTY session-resume and managed self-update validation for checkpoint 170."""
from __future__ import annotations

import argparse
import contextlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import threading
import time
from typing import Callable


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def session_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def run_captured(command: list[str], env: dict[str, str], cwd: Path, timeout: float = 30.0) -> subprocess.CompletedProcess[str]:
    stamp = time.time_ns()
    stdout_path = cwd / f".capture-{stamp}.stdout"
    stderr_path = cwd / f".capture-{stamp}.stderr"
    try:
        with stdout_path.open("wb") as stdout_file, stderr_path.open("wb") as stderr_file:
            process = subprocess.Popen(
                command,
                cwd=cwd,
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=stdout_file,
                stderr=stderr_file,
                start_new_session=True,
            )
            deadline = time.monotonic() + timeout
            while process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.05)
            if process.poll() is None:
                process.kill()
                process.wait(timeout=3)
                raise subprocess.TimeoutExpired(command, timeout)
        stdout = stdout_path.read_text(encoding="utf-8", errors="replace")
        stderr = stderr_path.read_text(encoding="utf-8", errors="replace")
        return subprocess.CompletedProcess(command, int(process.returncode), stdout, stderr)
    finally:
        with contextlib.suppress(OSError):
            stdout_path.unlink()
        with contextlib.suppress(OSError):
            stderr_path.unlink()


def run_pty(
    command: list[str],
    env: dict[str, str],
    cwd: Path,
    drive: Callable[[Callable[[bytes, int, float], int], Callable[[bytes], None], bytearray], None],
    timeout: float = 45.0,
) -> tuple[int, bytes, str]:
    master, slave = pty.openpty()
    stderr_path = cwd / f".pty-{time.time_ns()}.stderr"
    stderr_file = stderr_path.open("wb")
    process = subprocess.Popen(command, cwd=cwd, env=env, stdin=slave, stdout=slave, stderr=stderr_file, close_fds=True)
    os.close(slave)
    os.set_blocking(master, False)
    output = bytearray()

    def read_available(wait_time: float) -> None:
        ready, _, _ = select.select([master], [], [], wait_time)
        if not ready:
            return
        try:
            output.extend(os.read(master, 65536))
        except OSError:
            pass

    def wait(marker: bytes, start: int = 0, marker_timeout: float = 30.0) -> int:
        deadline = time.monotonic() + marker_timeout
        while time.monotonic() < deadline:
            found = output.find(marker, start)
            if found >= 0:
                return found + len(marker)
            if process.poll() is not None:
                break
            read_available(min(0.1, max(0.0, deadline - time.monotonic())))
        raise AssertionError(f"PTY marker {marker!r} missing; tail={output[-7000:].decode(errors='replace')}")

    def send(data: bytes) -> None:
        os.write(master, data)

    try:
        drive(wait, send, output)
        deadline = time.monotonic() + timeout
        while process.poll() is None and time.monotonic() < deadline:
            read_available(0.1)
        require(process.poll() is not None, f"PTY exit timeout; tail={output[-5000:].decode(errors='replace')}")
        for _ in range(10):
            read_available(0.02)
        stderr_file.flush()
        stderr_file.close()
        stderr = stderr_path.read_text(encoding="utf-8", errors="replace")
        with contextlib.suppress(OSError):
            stderr_path.unlink()
        return int(process.returncode), bytes(output), stderr
    finally:
        with contextlib.suppress(Exception):
            if not stderr_file.closed:
                stderr_file.close()
        with contextlib.suppress(OSError):
            stderr_path.unlink()
        with contextlib.suppress(OSError):
            os.close(master)
        if process.poll() is None:
            process.kill()
            with contextlib.suppress(Exception):
                process.wait(timeout=3)


class LatestState:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.requests = 0


class LatestHandler(BaseHTTPRequestHandler):
    server_version = "PiCheckpoint170/1"

    def do_GET(self) -> None:  # noqa: N802
        state: LatestState = self.server.state  # type: ignore[attr-defined]
        if self.path == "/latest":
            with state.lock:
                state.requests += 1
            body = json.dumps({
                "version": "0.85.0",
                "packageName": "@earendil-works/pi-coding-agent-next",
                "note": "checkpoint-170-self-update",
            }).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, _format: str, *_args: object) -> None:
        return


def run(binary: Path, report: Path | None) -> dict:
    with tempfile.TemporaryDirectory(prefix="pi-session-update-170-") as raw:
        root = Path(raw)
        workspace = root / "workspace"
        workspace.mkdir()
        agent_dir = root / "agent"
        agent_dir.mkdir()
        session_dir = root / "sessions"
        session_dir.mkdir()
        mock = root / "mock.json"
        mock.write_text(json.dumps([
            {"content": "mock-answer-170"},
            {"content": "second-answer-170"},
        ]), encoding="utf-8")

        env = os.environ.copy()
        env.update({
            "PI_AGENT_DIR": str(agent_dir),
            "PI_SKIP_VERSION_CHECK": "1",
            "PI_TELEMETRY": "0",
            "TERM": "xterm-256color",
            "NO_COLOR": "1",
        })
        common = [
            str(binary), "--mock-script", str(mock), "--session-dir", str(session_dir),
            "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes",
            "--no-extensions", "--no-tools", "--approve",
        ]

        for session_id, name in (("source-170", "Source Session 170"), ("target-170", "Target Session 170")):
            result = run_captured(common + ["-p", "--session-id", session_id, "--name", name, f"seed-{session_id}"], env, workspace)
            require(result.returncode == 0, f"create {session_id} failed: {result.stderr}\n{result.stdout}")
            require(result.stderr == "", f"create {session_id} stderr: {result.stderr}")

        source = session_dir / "source-170.jsonl"
        target = session_dir / "target-170.jsonl"
        require(source.is_file() and target.is_file(), f"missing sessions: {list(session_dir.iterdir())}")

        def drive_startup(wait, send, _output) -> None:
            pos = wait(b"Resume Session")
            send(b"Target Session 170")
            pos = wait(b"Target Session 170_", pos)
            send(b"\r")
            pos = wait(b"Type a prompt", pos)
            pos = wait(b"> ", pos)
            send(b"/name Startup Renamed 170\r")
            pos = wait(b"Session named.", pos)
            pos = wait(b"> ", pos)
            send(b"/quit\r")

        startup_code, startup_output, startup_stderr = run_pty(common + ["--resume"], env, workspace, drive_startup)
        require(startup_code == 0 and startup_stderr == "", f"startup resume failed: {startup_code} {startup_stderr}")
        require(b"Resume Session" in startup_output, "startup selector did not open")
        target_records = read_jsonl(target)
        require(any(r.get("type") == "session_info" and r.get("name") == "Startup Renamed 170" for r in target_records), "startup selected target was not renamed")
        require("Startup Renamed 170" not in session_text(source), "startup resume mutated the source session")

        def drive_live(wait, send, _output) -> None:
            pos = wait(b"Type a prompt")
            pos = wait(b"> ", pos)
            send(b"/resume Startup Renamed 170\r")
            pos = wait(b"Resume Session", pos)
            pos = wait(b"Startup Renamed 170_", pos)
            send(b"\r")
            pos = wait(b"Resumed session target-170", pos)
            pos = wait(b"> ", pos)
            send(b"after-live-resume-170\r")
            pos = wait(b"mock-answer-170", pos)
            pos = wait(b"> ", pos)
            send(b"/quit\r")

        live_code, live_output, live_stderr = run_pty(common + ["--session", str(source)], env, workspace, drive_live)
        require(live_code == 0 and live_stderr == "", f"live resume failed: {live_code} {live_stderr}")
        require(b"Resumed session target-170" in live_output, "live resume acknowledgement missing")
        source_text = session_text(source)
        target_text = session_text(target)
        require("after-live-resume-170" not in source_text, "post-resume prompt leaked into source session")
        require("after-live-resume-170" in target_text, "post-resume prompt missing from target session")
        require("mock-answer-170" in target_text, "post-resume response missing from target session")

        managed = root / "prefix" / "lib" / "node_modules" / "@earendil-works" / "pi-coding-agent" / "bin" / "pi"
        managed.parent.mkdir(parents=True)
        shutil.copy2(binary, managed)
        managed.chmod(0o755)
        manager_log = root / "manager.log"
        fake_manager = root / "fake-npm.sh"
        fake_manager.write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{manager_log}"\n', encoding="utf-8")
        fake_manager.chmod(0o755)
        (agent_dir / "settings.json").write_text(json.dumps({"npmCommand": [str(fake_manager)]}), encoding="utf-8")

        state = LatestState()
        server = ThreadingHTTPServer(("127.0.0.1", 0), LatestHandler)
        server.state = state  # type: ignore[attr-defined]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        update_env = env.copy()
        update_env["PI_LATEST_VERSION_URL"] = f"http://127.0.0.1:{server.server_address[1]}/latest"
        try:
            check = run_captured([str(managed), "update", "--self", "--check", "--json", "--approve"], update_env, workspace)
            require(check.returncode == 0 and check.stderr == "", f"self update check failed: {check.stderr}\n{check.stdout}")
            check_values = [json.loads(line) for line in check.stdout.splitlines() if line.strip().startswith("{")]
            require(len(check_values) == 1 and check_values[0].get("canSelfUpdate") is True, f"self update check plan invalid: {check_values}")
            require(" && " in str(check_values[0].get("command")), f"rename command is not multi-step: {check_values}")
            require(not manager_log.exists(), "self update --check executed the package manager")

            unsafe_check = run_captured([str(binary), "update", "--self", "--check", "--json", "--approve"], update_env, workspace)
            require(unsafe_check.returncode == 0 and unsafe_check.stderr == "", f"unsafe self update check failed: {unsafe_check.stderr}")
            unsafe_values = [json.loads(line) for line in unsafe_check.stdout.splitlines() if line.strip().startswith("{")]
            require(len(unsafe_values) == 1 and unsafe_values[0].get("canSelfUpdate") is False, f"source binary was treated as globally managed: {unsafe_values}")

            update = run_captured([str(managed), "update", "--self", "--force", "--json", "--approve"], update_env, workspace)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        require(update.returncode == 0, f"self update failed: {update.stderr}\n{update.stdout}")
        require(update.stderr == "", f"self update stderr: {update.stderr}")
        values = [json.loads(line) for line in update.stdout.splitlines() if line.strip().startswith("{")]
        require(any(v.get("target") == "self" and v.get("success") is True for v in values), f"self update success JSON missing: {values}")
        manager_lines = manager_log.read_text(encoding="utf-8").splitlines()
        require(len(manager_lines) == 2, f"expected uninstall/install migration, got {manager_lines}")
        require("uninstall -g @earendil-works/pi-coding-agent" in manager_lines[0], f"wrong uninstall: {manager_lines}")
        require("install -g --ignore-scripts --min-release-age=0 @earendil-works/pi-coding-agent-next@0.85.0" in manager_lines[1], f"wrong install: {manager_lines}")
        with state.lock:
            latest_requests = state.requests
        require(latest_requests == 3, f"latest request count: {latest_requests}")

        result = {
            "startupResume": True,
            "startupRenamePersistence": True,
            "liveResume": True,
            "sourceTargetIsolation": True,
            "selfUpdateCheckPlan": True,
            "unsafeSourceRejected": True,
            "selfUpdateMigration": True,
            "latestRequests": latest_requests,
            "managerSteps": len(manager_lines),
            "stderrBytes": len(startup_stderr.encode()) + len(live_stderr.encode()) + len(update.stderr.encode()),
        }
        text = "\n".join([
            "SESSION_UPDATE_E2E_170=PASS",
            "STARTUP_RESUME=PASS",
            "STARTUP_RENAME_PERSISTENCE=PASS",
            "LIVE_RESUME=PASS",
            "SOURCE_TARGET_ISOLATION=PASS",
            "SELF_UPDATE_CHECK_PLAN=PASS",
            "UNSAFE_SOURCE_INSTALL_REJECTED=PASS",
            "SELF_UPDATE_PACKAGE_MIGRATION=PASS",
            f"LATEST_REQUESTS={latest_requests}",
            f"MANAGER_STEPS={len(manager_lines)}",
            "STDERR_BYTES=0",
            "",
            json.dumps(result, sort_keys=True),
        ]) + "\n"
        if report is not None:
            report.write_text(text, encoding="utf-8")
        print(text, end="")
        return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    run(args.binary.resolve(), args.report.resolve() if args.report else None)


if __name__ == "__main__":
    main()
