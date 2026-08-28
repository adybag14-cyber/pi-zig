#!/usr/bin/env python3
"""Real PTY validation for checkpoint 168 session-tree controls."""
from __future__ import annotations

import argparse
import base64
import contextlib
import json
import os
from pathlib import Path
import pty
import queue
import re
import select
import subprocess
import tempfile
import threading
import time
from typing import Any, Callable


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


class RpcHarness:
    def __init__(self, command: list[str], env: dict[str, str], cwd: Path):
        self.process = subprocess.Popen(command, env=env, cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        assert self.process.stdin is not None and self.process.stdout is not None
        self.lines: queue.Queue[str] = queue.Queue()
        self.raw: list[str] = []
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.lines.put(line.rstrip("\n"))

    def send(self, value: dict[str, Any]) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write(json.dumps(value, separators=(",", ":")) + "\n")
        self.process.stdin.flush()

    def wait_for(self, predicate: Callable[[dict[str, Any]], bool], timeout: float = 30.0) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                line = self.lines.get(timeout=max(0.01, deadline - time.monotonic()))
            except queue.Empty as exc:
                raise AssertionError(f"RPC timeout; recent={self.raw[-20:]}") from exc
            self.raw.append(line)
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict) and predicate(value):
                return value
        raise AssertionError(f"RPC timeout; recent={self.raw[-20:]}")

    def response(self, request_id: str) -> dict[str, Any]:
        return self.wait_for(lambda value: value.get("type") == "response" and value.get("id") == request_id)

    def finish(self) -> tuple[int, str]:
        assert self.process.stdin is not None
        self.process.stdin.close()
        code = self.process.wait(timeout=20)
        assert self.process.stderr is not None
        stderr = self.process.stderr.read()
        self.reader.join(timeout=2)
        return code, stderr

    def kill(self) -> None:
        with contextlib.suppress(Exception):
            self.process.kill()
        with contextlib.suppress(Exception):
            self.process.wait(timeout=3)


def run_pty(command: list[str], env: dict[str, str], cwd: Path) -> tuple[int, bytes, str]:
    master, slave = pty.openpty()
    process = subprocess.Popen(command, env=env, cwd=cwd, stdin=slave, stdout=slave, stderr=subprocess.PIPE, close_fds=True)
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
        raise AssertionError(f"PTY marker {marker!r} missing; tail={output[-5000:].decode(errors='replace')}")

    try:
        pos = wait(b"> ")
        os.write(master, b"/tree\r")
        pos = wait(b"Session Tree", pos)
        os.write(master, b"tree-answer-168-1")
        pos = wait(b"tree-answer-168-1_", pos)
        time.sleep(0.20)
        read_available(0.20)

        # Shift+L opens the original label editor for the selected result.
        os.write(master, b"\x1b[108;2u")  # Kitty CSI-u Shift+L
        pos = wait(b"Editing label", pos)
        os.write(master, b"checkpoint-168\r")
        pos = wait(b"Label saved", pos)

        # Ctrl+X emits OSC 52 for the selected entry; Shift+T exposes timestamps.
        os.write(master, b"\x18")
        pos = wait(b"copied to clipboard", pos)
        os.write(master, b"\x1b[116;2u")  # Kitty CSI-u Shift+T
        pos = wait(b"Label timestamps shown", pos)

        # Ctrl+L switches directly to the original labeled-only filter.
        os.write(master, b"\x0c")
        pos = wait(b"Filter: ", pos)
        pos = wait(b"labeled", pos)

        # First Escape clears the active search; second closes the selector.
        os.write(master, b"\x1b")
        pos = wait(b"Search cleared", pos)
        os.write(master, b"\x1b")
        pos = wait(b"> ", pos)
        os.write(master, b"/quit\r")

        deadline = time.monotonic() + 30.0
        while process.poll() is None and time.monotonic() < deadline:
            read_available(0.1)
        require(process.poll() is not None, "PTY exit timeout")
        for _ in range(20):
            read_available(0.03)
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


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def run(binary: Path, report: Path | None) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pi-tree-controls-168-") as raw:
        root = Path(raw)
        agent_dir = root / "agent"
        session_dir = root / "sessions"
        agent_dir.mkdir()
        session_dir.mkdir()
        mock_path = root / "mock.json"
        mock_path.write_text(json.dumps([
            {"content": "tree-answer-168-1", "stream_chunks": ["tree-answer-", "168-1"]},
            {"content": "tree-answer-168-2"},
            {"content": "tree-answer-168-3"},
        ]), encoding="utf-8")
        (agent_dir / "settings.json").write_text(json.dumps({"retry": {"enabled": False}}), encoding="utf-8")

        env = os.environ.copy()
        env.update({"PI_AGENT_DIR": str(agent_dir), "TERM": "xterm-256color", "NO_COLOR": "1"})
        common = [
            str(binary), "--mock-script", str(mock_path), "--session-dir", str(session_dir),
            "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes",
            "--no-tools", "--approve",
        ]

        rpc = RpcHarness(common + ["--mode", "rpc"], env, root)
        try:
            for index in range(1, 4):
                request_id = f"p{index}"
                rpc.send({"id": request_id, "type": "prompt", "message": f"tree-user-168-{index}"})
                require(rpc.response(request_id).get("success") is True, f"prompt {index} rejected")
                rpc.wait_for(lambda value: value.get("type") == "agent_end")
            rpc.send({"id": "state", "type": "get_state"})
            state = rpc.response("state")
            session_file = Path(state.get("data", {}).get("sessionFile", ""))
            require(session_file.is_file(), f"session file missing: {session_file}")
            rpc.send({"id": "quit", "type": "quit"})
            require(rpc.response("quit").get("success") is True, "quit failed")
            rpc_code, rpc_stderr = rpc.finish()
            require(rpc_code == 0 and rpc_stderr == "", f"RPC failed: {rpc_code} {rpc_stderr}")
        except BaseException:
            rpc.kill()
            raise

        pty_code, raw_output, pty_stderr = run_pty(common + ["--session", str(session_file)], env, root)
        require(pty_code == 0 and pty_stderr == "", f"PTY failed: {pty_code} {pty_stderr}")
        text_output = raw_output.decode("utf-8", errors="replace")
        require("Session Tree" in text_output, "fullscreen tree selector did not open")
        require("Label saved" in text_output, "label editor did not persist")
        require("Label timestamps shown" in text_output, "timestamp toggle missing")
        require("labeled" in text_output, "labeled-only filter missing")

        osc_matches = re.findall(rb"\x1b\]52;c;([A-Za-z0-9+/=]+)\x07", raw_output)
        require(bool(osc_matches), "OSC 52 clipboard sequence missing")
        decoded = base64.b64decode(osc_matches[-1]).decode("utf-8")
        require(decoded == "tree-answer-168-1", f"clipboard payload mismatch: {decoded!r}")

        records = load_jsonl(session_file)
        labels = [record for record in records if record.get("type") == "label" and record.get("label") == "checkpoint-168"]
        require(len(labels) == 1, f"durable label missing or duplicated: {labels}")
        target_id = labels[0].get("targetId") or labels[0].get("target_id")
        require(isinstance(target_id, str) and target_id, f"label target missing: {labels[0]}")
        def message_text(record: dict[str, Any]) -> str:
            content = record.get("message", {}).get("content")
            if isinstance(content, str):
                return content
            if isinstance(content, list):
                return "".join(
                    str(block.get("text", ""))
                    for block in content
                    if isinstance(block, dict) and block.get("type") == "text"
                )
            return ""

        assistant_ids = {
            record.get("id") for record in records
            if record.get("type") == "message"
            and record.get("message", {}).get("role") == "assistant"
            and message_text(record) == "tree-answer-168-1"
        }
        require(target_id in assistant_ids, f"label attached to wrong entry: {target_id} vs {assistant_ids}")

        result = {
            "rpcExit": rpc_code,
            "ptyExit": pty_code,
            "fullscreenTreeSelector": True,
            "searchSelected": "tree-answer-168-1",
            "durableLabel": "checkpoint-168",
            "labelTarget": target_id,
            "osc52Payload": decoded,
            "labelTimestamps": True,
            "labeledOnlyFilter": True,
            "stderrBytes": len(rpc_stderr.encode()) + len(pty_stderr.encode()),
        }
        text = "\n".join([
            "TREE_CONTROLS_E2E_168=PASS",
            "FULLSCREEN_SELECTOR=PASS",
            "SEARCH_SELECTION=tree-answer-168-1",
            "DURABLE_LABEL=checkpoint-168",
            "OSC52_PAYLOAD=tree-answer-168-1",
            "LABEL_TIMESTAMPS=PASS",
            "LABELED_ONLY_FILTER=PASS",
            "RPC_EXIT=0",
            "PTY_EXIT=0",
            "STDERR_BYTES=0",
            "",
            json.dumps(result, indent=2, sort_keys=True),
            "",
        ])
        if report is not None:
            report.write_text(text, encoding="utf-8")
        print(json.dumps(result, sort_keys=True))
        return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    require(binary.is_file(), f"binary missing: {binary}")
    run(binary, args.report.resolve() if args.report else None)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
