#!/usr/bin/env python3
"""Executable validation for checkpoint 168 bootstrap HTTP policy.

The fixture exercises the ordinary ``pi auth check`` command rather than
calling Zig helpers directly.  It verifies Radius OAuth refresh retry headers,
request deadlines, target-aware proxying, NO_PROXY bypass, and durable token
replacement through the final executable.
"""
from __future__ import annotations

import argparse
import contextlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
from typing import Any, Iterable
from urllib.parse import urlsplit


TOKEN_BODY = {
    "access_token": "bootstrap-access-168",
    "refresh_token": "bootstrap-refresh-168",
    "expires_in": 3600,
    "scope": "gateway offline_access",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


class Reply:
    def __init__(
        self,
        status: int,
        body: bytes,
        *,
        headers: dict[str, str] | None = None,
        delay: float = 0.0,
    ) -> None:
        self.status = status
        self.body = body
        self.headers = headers or {}
        self.delay = delay


class PlanServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, replies: Iterable[Reply]) -> None:
        self.replies = list(replies)
        self.requests: list[dict[str, Any]] = []
        self.lock = threading.Lock()
        super().__init__(("127.0.0.1", 0), PlanHandler)


class PlanHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_: object) -> None:
        return

    def do_POST(self) -> None:  # noqa: N802
        server: PlanServer = self.server  # type: ignore[assignment]
        length = int(self.headers.get("content-length", "0"))
        request_body = self.rfile.read(length)
        with server.lock:
            index = len(server.requests)
            server.requests.append({
                "path": self.path,
                "host": self.headers.get("host", ""),
                "headers": {name.lower(): value for name, value in self.headers.items()},
                "body": request_body.decode("utf-8", errors="replace"),
                "time": time.monotonic(),
            })
            reply = server.replies[min(index, len(server.replies) - 1)]

        if reply.delay:
            time.sleep(reply.delay)
        try:
            self.send_response(reply.status)
            for name, value in reply.headers.items():
                self.send_header(name, value)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(reply.body)))
            self.send_header("connection", "close")
            self.end_headers()
            self.wfile.write(reply.body)
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass


@contextlib.contextmanager
def serving(replies: Iterable[Reply]):
    server = PlanServer(replies)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)


def token_reply() -> Reply:
    return Reply(200, json.dumps(TOKEN_BODY, separators=(",", ":")).encode())


def clean_env(agent_dir: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["PI_AGENT_DIR"] = str(agent_dir)
    for name in (
        "http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY",
        "all_proxy", "ALL_PROXY", "no_proxy", "NO_PROXY",
    ):
        env.pop(name, None)
    return env


def write_agent(
    agent_dir: Path,
    *,
    base_url: str,
    timeout_ms: int = 1000,
    max_retries: int = 2,
    max_retry_delay_ms: int = 1000,
    proxy: str | None = None,
) -> None:
    agent_dir.mkdir(parents=True, exist_ok=True)
    (agent_dir / "models.json").write_text(json.dumps({
        "providers": {
            "radius-bootstrap-168": {
                "name": "Radius Bootstrap 168",
                "baseUrl": base_url,
                "oauth": "radius",
            }
        }
    }), encoding="utf-8")
    (agent_dir / "auth.json").write_text(json.dumps({
        "radius-bootstrap-168": {
            "type": "oauth",
            "refresh": "old-refresh-168",
            "access": "old-access-168",
            "expires": 0,
        }
    }), encoding="utf-8")
    settings: dict[str, Any] = {
        "retry": {
            "provider": {
                "timeoutMs": timeout_ms,
                "maxRetries": max_retries,
                "maxRetryDelayMs": max_retry_delay_ms,
            }
        }
    }
    if proxy is not None:
        settings["httpProxy"] = proxy
    (agent_dir / "settings.json").write_text(
        json.dumps(settings, separators=(",", ":")), encoding="utf-8"
    )


def run_check(binary: Path, agent_dir: Path, env: dict[str, str]) -> tuple[subprocess.CompletedProcess[str], float]:
    started = time.monotonic()
    result = subprocess.run(
        [
            str(binary), "auth", "check",
            "--provider", "radius-bootstrap-168",
            "--json", "--credentials",
        ],
        env=env,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    return result, time.monotonic() - started


def assert_ready(result: subprocess.CompletedProcess[str]) -> dict[str, Any]:
    require(result.returncode == 0, f"ready exit={result.returncode}: {result.stdout} {result.stderr}")
    require(result.stderr == "", f"ready stderr={result.stderr}")
    payload = json.loads(result.stdout)
    require(payload.get("status") == "ready", f"ready payload={payload}")
    require(payload.get("credentials") == TOKEN_BODY["access_token"], f"ready credential={payload}")
    return payload


def assert_invalid(result: subprocess.CompletedProcess[str]) -> dict[str, Any]:
    require(result.returncode == 2, f"invalid exit={result.returncode}: {result.stdout} {result.stderr}")
    require(result.stderr == "", f"invalid stderr={result.stderr}")
    payload = json.loads(result.stdout)
    require(payload.get("status") == "invalid", f"invalid payload={payload}")
    return payload


def validate_persisted(agent_dir: Path) -> None:
    auth = json.loads((agent_dir / "auth.json").read_text(encoding="utf-8"))
    stored = auth["radius-bootstrap-168"]
    require(stored["access"] == TOKEN_BODY["access_token"], f"stored access={stored}")
    require(stored["refresh"] == TOKEN_BODY["refresh_token"], f"stored refresh={stored}")
    require(stored["scope"] == TOKEN_BODY["scope"], f"stored scope={stored}")
    require(int(stored["expires"]) > int(time.time() * 1000), f"stored expiry={stored}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    require(binary.is_file(), f"missing executable: {binary}")

    report: dict[str, Any] = {}

    # A real 503 response carrying Retry-After-Ms must be replayed and the new
    # OAuth token must replace the expired credential atomically.
    with tempfile.TemporaryDirectory(prefix="pi-bootstrap-retry-168-") as raw, serving([
        Reply(503, b'{"error":"temporary"}', headers={"Retry-After-Ms": "25"}),
        token_reply(),
    ]) as server:
        agent_dir = Path(raw) / "agent"
        write_agent(agent_dir, base_url=f"http://127.0.0.1:{server.server_port}")
        env = clean_env(agent_dir)
        env["NO_PROXY"] = env["no_proxy"] = "127.0.0.1,localhost"
        result, elapsed = run_check(binary, agent_dir, env)
        assert_ready(result)
        require(len(server.requests) == 2, f"retry requests={len(server.requests)}")
        require(server.requests[1]["time"] - server.requests[0]["time"] >= 0.020, "Retry-After-Ms delay not honoured")
        require(server.requests[0]["path"] == "/v1/oauth/token", f"retry path={server.requests[0]}")
        require("refresh_token=old-refresh-168" in server.requests[0]["body"], f"retry body={server.requests[0]}")
        validate_persisted(agent_dir)
        report["retryAndPersistence"] = {"requests": 2, "elapsedMs": round(elapsed * 1000)}

    # Explicit provider denial overrides an otherwise retryable 503.
    with tempfile.TemporaryDirectory(prefix="pi-bootstrap-deny-168-") as raw, serving([
        Reply(503, b'{"error":"terminal"}', headers={"X-Should-Retry": "false"}),
    ]) as server:
        agent_dir = Path(raw) / "agent"
        write_agent(agent_dir, base_url=f"http://127.0.0.1:{server.server_port}", max_retries=4)
        env = clean_env(agent_dir)
        env["NO_PROXY"] = env["no_proxy"] = "127.0.0.1,localhost"
        result, elapsed = run_check(binary, agent_dir, env)
        assert_invalid(result)
        require(len(server.requests) == 1, f"denied retry requests={len(server.requests)}")
        report["retryDenied"] = {"requests": 1, "elapsedMs": round(elapsed * 1000)}

    # Provider timeout must pre-empt a live response body and honour maxRetries=0.
    with tempfile.TemporaryDirectory(prefix="pi-bootstrap-timeout-168-") as raw, serving([
        Reply(200, json.dumps(TOKEN_BODY).encode(), delay=0.35),
    ]) as server:
        agent_dir = Path(raw) / "agent"
        write_agent(agent_dir, base_url=f"http://127.0.0.1:{server.server_port}", timeout_ms=50, max_retries=0)
        env = clean_env(agent_dir)
        env["NO_PROXY"] = env["no_proxy"] = "127.0.0.1,localhost"
        result, elapsed = run_check(binary, agent_dir, env)
        assert_invalid(result)
        require(len(server.requests) == 1, f"timeout requests={len(server.requests)}")
        require(elapsed < 1.5, f"provider timeout did not pre-empt response: {elapsed:.3f}s")
        report["timeout"] = {"requests": 1, "elapsedMs": round(elapsed * 1000)}

    # A settings-level HTTP proxy must carry the OAuth form request without
    # resolving the fake target hostname locally.
    with tempfile.TemporaryDirectory(prefix="pi-bootstrap-proxy-168-") as raw, serving([
        token_reply(),
    ]) as proxy:
        agent_dir = Path(raw) / "agent"
        write_agent(
            agent_dir,
            base_url="http://radius-bootstrap.invalid:8123",
            proxy=f"http://127.0.0.1:{proxy.server_port}",
            max_retries=0,
        )
        env = clean_env(agent_dir)
        result, elapsed = run_check(binary, agent_dir, env)
        assert_ready(result)
        require(len(proxy.requests) == 1, f"proxy requests={len(proxy.requests)}")
        proxy_path = proxy.requests[0]["path"]
        parsed = urlsplit(proxy_path)
        require(parsed.hostname == "radius-bootstrap.invalid", f"proxy absolute URI={proxy_path!r}")
        require(parsed.path == "/v1/oauth/token", f"proxy path={proxy_path!r}")
        validate_persisted(agent_dir)
        report["settingsProxy"] = {"requests": 1, "absoluteUri": proxy_path, "elapsedMs": round(elapsed * 1000)}

    # NO_PROXY is target-aware and must bypass a configured trap proxy.
    with tempfile.TemporaryDirectory(prefix="pi-bootstrap-no-proxy-168-") as raw, serving([
        token_reply(),
    ]) as target, serving([
        Reply(502, b'{"error":"proxy should not be used"}'),
    ]) as trap_proxy:
        agent_dir = Path(raw) / "agent"
        write_agent(
            agent_dir,
            base_url=f"http://127.0.0.1:{target.server_port}",
            proxy=f"http://127.0.0.1:{trap_proxy.server_port}",
            max_retries=0,
        )
        env = clean_env(agent_dir)
        env["NO_PROXY"] = env["no_proxy"] = "127.0.0.1"
        result, elapsed = run_check(binary, agent_dir, env)
        assert_ready(result)
        require(len(target.requests) == 1, f"NO_PROXY target requests={len(target.requests)}")
        require(len(trap_proxy.requests) == 0, f"NO_PROXY trap requests={len(trap_proxy.requests)}")
        report["noProxyBypass"] = {"targetRequests": 1, "proxyRequests": 0, "elapsedMs": round(elapsed * 1000)}

    print("BOOTSTRAP_NETWORK_E2E_168=PASS")
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
