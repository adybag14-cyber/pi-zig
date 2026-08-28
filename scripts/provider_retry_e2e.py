#!/usr/bin/env python3
"""Loopback validation for native provider retry, delay cap, and timeout policy."""
from __future__ import annotations

import argparse
import contextlib
import http.server
import json
import os
import queue
from pathlib import Path
import subprocess
import tempfile
import threading
import time
from typing import Any

SUCCESS_SSE = (
    'data: {"id":"chatcmpl-163","choices":[{"delta":{"content":"provider-retry-ok"}}]}\n\n'
    'data: {"choices":[{"delta":{},"finish_reason":"stop"}],'
    '"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}\n\n'
    'data: [DONE]\n\n'
).encode()


def response(status: int, body: bytes, *, headers: dict[str, str] | None = None, delay: float = 0.0) -> dict[str, Any]:
    return {"status": status, "body": body, "headers": headers or {}, "delay": delay}


class PlanServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, plan: list[dict[str, Any]]):
        self.plan = plan
        self.requests: list[dict[str, Any]] = []
        self.lock = threading.Lock()
        super().__init__(("127.0.0.1", 0), PlanHandler)


class PlanHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_: object) -> None:
        return

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler contract
        server: PlanServer = self.server  # type: ignore[assignment]
        length = int(self.headers.get("content-length", "0"))
        payload = self.rfile.read(length)
        with server.lock:
            index = len(server.requests)
            server.requests.append({"time": time.monotonic(), "path": self.path, "body": payload})
            item = server.plan[min(index, len(server.plan) - 1)]
        if item["delay"]:
            time.sleep(item["delay"])
        body: bytes = item["body"]
        try:
            self.send_response(item["status"])
            for name, value in item["headers"].items():
                self.send_header(name, value)
            if "content-type" not in {name.lower() for name in item["headers"]}:
                self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass


@contextlib.contextmanager
def serving(plan: list[dict[str, Any]]):
    server = PlanServer(plan)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)


def run_pi(binary: Path, server: PlanServer, settings: dict[str, Any]) -> tuple[subprocess.CompletedProcess[str], float]:
    with tempfile.TemporaryDirectory(prefix="pi-provider-retry-163-") as raw:
        agent_dir = Path(raw) / "agent"
        agent_dir.mkdir()
        (agent_dir / "settings.json").write_text(json.dumps(settings), encoding="utf-8")
        env = os.environ.copy()
        env["PI_AGENT_DIR"] = str(agent_dir)
        command = [
            str(binary),
            "--provider", "openai",
            "--model", "checkpoint-163",
            "--base-url", f"http://127.0.0.1:{server.server_port}/v1",
            "--api-key", "test-key",
            "--mode", "json",
            "--print",
            "--no-session",
            "--no-tools",
            "provider retry e2e",
        ]
        started = time.monotonic()
        completed = subprocess.run(
            command,
            env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
        return completed, time.monotonic() - started


class RpcHarness:
    def __init__(self, command: list[str], env: dict[str, str]):
        self.process = subprocess.Popen(
            command,
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
        self.reader = threading.Thread(target=self._read_stdout, daemon=True)
        self.reader.start()
        self.seen: list[dict[str, Any]] = []
        self.raw: list[str] = []

    def _read_stdout(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.lines.put(line.rstrip("\n"))

    def send(self, payload: dict[str, Any]) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self.process.stdin.flush()

    def wait_for(self, predicate, *, timeout: float = 15.0) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError(f"RPC event timeout; raw={self.raw[-20:]}")
            try:
                line = self.lines.get(timeout=remaining)
            except queue.Empty as exc:
                raise AssertionError(f"RPC event timeout; raw={self.raw[-20:]}") from exc
            self.raw.append(line)
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            self.seen.append(item)
            if predicate(item):
                return item

    def finish(self) -> tuple[int, str]:
        assert self.process.stdin is not None
        self.process.stdin.close()
        code = self.process.wait(timeout=10)
        assert self.process.stderr is not None
        stderr = self.process.stderr.read()
        self.reader.join(timeout=2)
        return code, stderr


def run_rpc_reload(binary: Path, server: PlanServer) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pi-provider-reload-163-") as raw:
        agent_dir = Path(raw) / "agent"
        agent_dir.mkdir()
        settings_path = agent_dir / "settings.json"
        settings_path.write_text(json.dumps({
            "retry": {
                "enabled": False,
                "provider": {"maxRetries": 0, "maxRetryDelayMs": 1000},
            }
        }), encoding="utf-8")
        env = os.environ.copy()
        env["PI_AGENT_DIR"] = str(agent_dir)
        command = [
            str(binary),
            "--provider", "openai",
            "--model", "gpt-4o",
            "--base-url", f"http://127.0.0.1:{server.server_port}/v1",
            "--api-key", "test-key",
            "--mode", "rpc",
            "--no-session",
            "--no-tools",
        ]
        rpc = RpcHarness(command, env)
        try:
            rpc.send({"id": "p1", "type": "prompt", "message": "before reload"})
            rpc.wait_for(lambda item: item.get("type") == "response" and item.get("id") == "p1")
            first_end = rpc.wait_for(lambda item: item.get("type") == "agent_end")
            require(len(server.requests) == 1, f"reload initial requests={len(server.requests)}")
            require("HTTP 503" in json.dumps(first_end), "reload initial terminal error missing")

            settings_path.write_text(json.dumps({
                "retry": {
                    "enabled": False,
                    "provider": {"maxRetries": 1, "maxRetryDelayMs": 1000},
                }
            }), encoding="utf-8")
            rpc.send({"id": "r1", "type": "reload"})
            reload_response = rpc.wait_for(lambda item: item.get("type") == "response" and item.get("id") == "r1")
            require(reload_response.get("success") is True, f"reload failed: {reload_response}")

            rpc.send({"id": "p2", "type": "prompt", "message": "after reload"})
            rpc.wait_for(lambda item: item.get("type") == "response" and item.get("id") == "p2")
            second_end = rpc.wait_for(lambda item: item.get("type") == "agent_end")
            require(len(server.requests) == 3, f"reload final requests={len(server.requests)}")
            require(server.requests[2]["time"] - server.requests[1]["time"] >= 0.015, "reloaded retry delay missing")
            require("provider-retry-ok" in json.dumps(second_end), "reloaded provider retry did not succeed")

            rpc.send({"id": "q1", "type": "quit"})
            rpc.wait_for(lambda item: item.get("type") == "response" and item.get("id") == "q1")
            code, stderr = rpc.finish()
            require(code == 0, f"reload RPC exit={code}")
            require(stderr == "", f"reload RPC stderr={stderr}")
            return {"requestsBefore": 1, "requestsAfter": 2, "stderrBytes": 0}
        except BaseException:
            rpc.process.kill()
            with contextlib.suppress(Exception):
                rpc.process.wait(timeout=3)
            raise


def policy(*, timeout_ms: int = 3000, max_retries: int = 1, max_delay_ms: int = 1000) -> dict[str, Any]:
    return {
        "retry": {
            "enabled": False,
            "provider": {
                "timeoutMs": timeout_ms,
                "maxRetries": max_retries,
                "maxRetryDelayMs": max_delay_ms,
            },
        }
    }


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def validate_process(result: subprocess.CompletedProcess[str], marker: str) -> None:
    require(result.returncode == 0, f"{marker}: exit {result.returncode}: {result.stderr}")
    require(result.stderr == "", f"{marker}: unexpected stderr: {result.stderr}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    require(binary.is_file(), f"missing executable: {binary}")

    report: dict[str, Any] = {}

    with serving([
        response(429, b'{"error":{"message":"slow down"}}', headers={"retry-after-ms": "60"}),
        response(200, SUCCESS_SSE, headers={"content-type": "text/event-stream"}),
    ]) as server:
        result, elapsed = run_pi(binary, server, policy())
        validate_process(result, "retry-after-ms")
        require(len(server.requests) == 2, f"retry-after-ms: requests={len(server.requests)}")
        require(server.requests[1]["time"] - server.requests[0]["time"] >= 0.055, "retry-after-ms delay not honored")
        require("provider-retry-ok" in result.stdout, "retry-after-ms success missing")
        report["retryAfterMs"] = {"requests": 2, "elapsedMs": round(elapsed * 1000)}

    with serving([
        response(400, b'{"error":{"message":"explicit retry"}}', headers={"x-should-retry": "true"}),
        response(200, SUCCESS_SSE, headers={"content-type": "text/event-stream"}),
    ]) as server:
        result, elapsed = run_pi(binary, server, policy(max_retries=1))
        validate_process(result, "x-should-retry true")
        require(len(server.requests) == 2, f"x-should-retry true: requests={len(server.requests)}")
        require("provider-retry-ok" in result.stdout, "x-should-retry true success missing")
        report["forcedRetry"] = {"requests": 2, "elapsedMs": round(elapsed * 1000)}

    with serving([
        response(503, b'{"error":{"message":"unavailable"}}', headers={"x-should-retry": "false"}),
    ]) as server:
        result, elapsed = run_pi(binary, server, policy(max_retries=3))
        validate_process(result, "x-should-retry false")
        require(len(server.requests) == 1, f"x-should-retry false: requests={len(server.requests)}")
        require("HTTP 503" in result.stdout, "x-should-retry false terminal response missing")
        report["deniedRetry"] = {"requests": 1, "elapsedMs": round(elapsed * 1000)}

    with serving([
        response(429, b'{"error":{"message":"wait"}}', headers={"retry-after-ms": "5000"}),
    ]) as server:
        result, elapsed = run_pi(binary, server, policy(max_retries=3, max_delay_ms=100))
        validate_process(result, "retry delay cap")
        require(len(server.requests) == 1, f"retry delay cap: requests={len(server.requests)}")
        require("ProviderRetryDelayExceeded" in result.stdout, "retry delay cap error missing")
        report["delayCap"] = {"requests": 1, "elapsedMs": round(elapsed * 1000)}

    with serving([
        response(200, SUCCESS_SSE, headers={"content-type": "text/event-stream"}, delay=0.35),
    ]) as server:
        inherited_settings = {
            "httpIdleTimeoutMs": 50,
            "retry": {
                "enabled": False,
                "provider": {"maxRetries": 0, "maxRetryDelayMs": 1000},
            },
        }
        result, elapsed = run_pi(binary, server, inherited_settings)
        validate_process(result, "inherited provider timeout")
        require(len(server.requests) == 1, f"inherited provider timeout: requests={len(server.requests)}")
        require("ProviderRequestTimeout" in result.stdout, "inherited provider timeout error missing")
        require(elapsed < 2.0, f"inherited provider timeout did not preempt reads: {elapsed:.3f}s")
        report["inheritedTimeout"] = {"requests": 1, "elapsedMs": round(elapsed * 1000)}

    with serving([
        response(200, SUCCESS_SSE, headers={"content-type": "text/event-stream"}, delay=0.35),
        response(200, SUCCESS_SSE, headers={"content-type": "text/event-stream"}, delay=0.35),
    ]) as server:
        result, elapsed = run_pi(binary, server, policy(timeout_ms=50, max_retries=1))
        validate_process(result, "provider timeout")
        require(len(server.requests) == 2, f"provider timeout: requests={len(server.requests)}")
        require("ProviderRequestTimeout" in result.stdout, "provider timeout error missing")
        require(elapsed < 2.5, f"provider timeout did not preempt reads: {elapsed:.3f}s")
        report["timeout"] = {"requests": 2, "elapsedMs": round(elapsed * 1000)}

    with serving([
        response(503, b'{"error":{"message":"before reload"}}'),
        response(503, b'{"error":{"message":"after reload"}}', headers={"retry-after-ms": "20"}),
        response(200, SUCCESS_SSE, headers={"content-type": "text/event-stream"}),
    ]) as server:
        report["liveReload"] = run_rpc_reload(binary, server)

    print("PROVIDER_RETRY_E2E_163=PASS")
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
