#!/usr/bin/env python3
"""Real provider-body validation for checkpoint 167 summary request options."""
from __future__ import annotations

import argparse
import contextlib
import http.server
import json
import os
from pathlib import Path
import pty
import queue
import select
import subprocess
import tempfile
import threading
import time
from typing import Any, Callable


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


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
        raw = self.rfile.read(length)
        payload = json.loads(raw)
        headers = {name.lower(): value for name, value in self.headers.items()}
        with server.lock:
            index = len(server.requests) + 1
            server.requests.append({"path": self.path, "headers": headers, "body": payload})

        if payload.get("stream"):
            content = f"assistant-167-{index}"
            body = (
                f'data: {{"id":"chatcmpl-167-{index}","choices":[{{"delta":{{"content":{json.dumps(content)}}}}}]}}\n\n'
                'data: {"choices":[{"delta":{},"finish_reason":"stop"}],'
                '"usage":{"prompt_tokens":4,"completion_tokens":2,"total_tokens":6}}\n\n'
                'data: [DONE]\n\n'
            ).encode()
            content_type = "text/event-stream"
        else:
            body = json.dumps({
                "id": f"chatcmpl-summary-167-{index}",
                "choices": [{
                    "message": {"role": "assistant", "content": "summary-cap-167"},
                    "finish_reason": "stop",
                }],
                "usage": {"prompt_tokens": 9, "completion_tokens": 3, "total_tokens": 12},
            }, separators=(",", ":")).encode()
            content_type = "application/json"

        try:
            self.send_response(200)
            self.send_header("content-type", content_type)
            self.send_header("content-length", str(len(body)))
            self.send_header("connection", "close")
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass


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


class RpcHarness:
    def __init__(self, command: list[str], env: dict[str, str], cwd: Path):
        self.process = subprocess.Popen(
            command,
            env=env,
            cwd=cwd,
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


def run_pty(command: list[str], env: dict[str, str], cwd: Path) -> tuple[int, str, str]:
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
            chunk = os.read(master, 65536)
        except OSError:
            chunk = b""
        output.extend(chunk)

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
        os.write(master, b"assistant-167-1")
        time.sleep(0.15)
        read_available(0.15)
        os.write(master, b"\r")
        pos = wait(b"Summarize branch?", pos)
        pos = wait(b"Choice [n]: ", pos)
        os.write(master, b"s\r")
        pos = wait(b"Summarized", pos)
        wait(b"> ", pos)
        os.write(master, b"/quit\r")
        deadline = time.monotonic() + 30.0
        while process.poll() is None and time.monotonic() < deadline:
            read_available(0.1)
        require(process.poll() is not None, "PTY exit timeout")
        for _ in range(20):
            read_available(0.03)
        assert process.stderr is not None
        stderr = process.stderr.read().decode("utf-8", errors="replace")
        return int(process.returncode), output.decode("utf-8", errors="replace"), stderr
    finally:
        with contextlib.suppress(OSError):
            os.close(master)
        if process.poll() is None:
            process.kill()
            with contextlib.suppress(Exception):
                process.wait(timeout=3)


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def output_cap(body: dict[str, Any]) -> Any:
    return body.get("max_completion_tokens", body.get("max_tokens"))


def run(binary: Path, report: Path | None) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pi-summary-options-167-") as raw, serving() as server:
        root = Path(raw)
        agent_dir = root / "agent"
        session_dir = root / "sessions"
        agent_dir.mkdir()
        session_dir.mkdir()
        (agent_dir / "settings.json").write_text(json.dumps({
            "retry": {"enabled": False, "provider": {"maxRetries": 0}},
            "branchSummary": {"reserveTokens": 64, "skipPrompt": False},
        }), encoding="utf-8")
        (agent_dir / "models.json").write_text(json.dumps({
            "providers": {
                "summary167": {
                    "baseUrl": f"http://127.0.0.1:{server.server_port}/v1",
                    "api": "openai-completions",
                    "apiKey": "$SUMMARY167_KEY",
                    "compat": {
                        "sendSessionAffinityHeaders": True,
                        "sessionAffinityFormat": "openai",
                        "supportsLongCacheRetention": True,
                    },
                    "models": [{
                        "id": "fast",
                        "contextWindow": 128000,
                        "maxTokens": 4096,
                    }],
                }
            }
        }), encoding="utf-8")

        env = os.environ.copy()
        env.update({
            "PI_AGENT_DIR": str(agent_dir),
            "PI_CACHE_RETENTION": "long",
            "SUMMARY167_KEY": "summary-key-167",
            "TERM": "xterm-256color",
            "NO_COLOR": "1",
        })
        common = [
            str(binary),
            "--provider", "summary167", "--model", "fast",
            "--session-dir", str(session_dir),
            "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes",
            "--no-tools", "--approve",
        ]

        rpc = RpcHarness(common + ["--mode", "rpc"], env, root)
        try:
            for index in range(1, 4):
                request_id = f"p{index}"
                rpc.send({"id": request_id, "type": "prompt", "message": f"user-summary-167-{index}"})
                require(rpc.response(request_id).get("success") is True, f"prompt {index} rejected")
                rpc.wait_for(lambda value: value.get("type") == "agent_end")
            rpc.send({"id": "entries", "type": "get_entries"})
            entries = rpc.response("entries").get("data", {}).get("entries", [])
            assistants = [entry for entry in entries if entry.get("type") == "message" and entry.get("message", {}).get("role") == "assistant"]
            require(len(assistants) == 3, f"assistant entries missing: {assistants}")
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

        pty_code, pty_output, pty_stderr = run_pty(common + ["--session", str(session_file)], env, root)
        require(pty_code == 0 and pty_stderr == "", f"PTY failed: {pty_code} {pty_stderr}")
        require("Session Tree" in pty_output, "fullscreen tree selector did not open")
        require("Summarize branch?" in pty_output, "tree summary choice did not follow selection")
        require("Summarized" in pty_output, "tree summary did not complete")

        with server.lock:
            requests = list(server.requests)
        require(len(requests) == 4, f"unexpected request count: {len(requests)}")
        normal = requests[:3]
        summary = requests[3]
        require(all(item["body"].get("stream") is True for item in normal), f"normal requests were not streaming: {normal}")
        require(summary["body"].get("stream", False) is False, f"summary request unexpectedly streamed: {summary}")
        require(output_cap(summary["body"]) == 2048, f"summary output cap mismatch: {summary['body']}")

        affinity_names = {"session_id", "x-client-request-id", "x-session-id", "session-id"}
        normal_affinity = sorted(name for name in affinity_names if name in normal[0]["headers"])
        summary_affinity = sorted(name for name in affinity_names if name in summary["headers"])
        require(normal_affinity, f"normal request had no session affinity: {normal[0]['headers']}")
        require(not summary_affinity, f"summary request retained session affinity: {summary_affinity}")
        require("prompt_cache_key" not in summary["body"], f"summary retained prompt cache key: {summary['body']}")
        require("prompt_cache_retention" not in summary["body"], f"summary retained prompt cache retention: {summary['body']}")

        records = load_jsonl(session_file)
        summaries = [record for record in records if record.get("type") == "branch_summary"]
        require(len(summaries) == 1, f"branch summary missing: {summaries}")
        require(str(summaries[0].get("summary", "")).endswith("summary-cap-167"), f"summary content mismatch: {summaries[0]}")

        result = {
            "normalRequests": 3,
            "summaryRequests": 1,
            "summaryMaxTokens": output_cap(summary["body"]),
            "normalAffinityHeaders": normal_affinity,
            "summaryAffinityHeaders": summary_affinity,
            "summaryPromptCacheKey": summary["body"].get("prompt_cache_key"),
            "summaryPromptCacheRetention": summary["body"].get("prompt_cache_retention"),
            "fullscreenTreeSelector": True,
            "searchSelected": "assistant-167-1",
            "summaryPersisted": True,
            "rpcExit": rpc_code,
            "ptyExit": pty_code,
            "stderrBytes": len(rpc_stderr.encode()) + len(pty_stderr.encode()),
        }
        text = "\n".join([
            "SUMMARY_REQUEST_OPTIONS_E2E_167=PASS",
            "NORMAL_REQUESTS=3",
            "SUMMARY_REQUESTS=1",
            "SUMMARY_MAX_TOKENS=2048",
            f"NORMAL_AFFINITY_HEADERS={','.join(normal_affinity)}",
            "SUMMARY_AFFINITY_HEADERS=none",
            "SUMMARY_PROMPT_CACHE_KEY=absent",
            "SUMMARY_PROMPT_CACHE_RETENTION=absent",
            "FULLSCREEN_TREE_SELECTOR=PASS",
            "TREE_SEARCH_SELECTION=assistant-167-1",
            "SUMMARY_PERSISTED=PASS",
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
