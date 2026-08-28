#!/usr/bin/env python3
"""Real RPC + pseudo-terminal validation for checkpoint 166 branch summaries."""
from __future__ import annotations

import argparse
import contextlib
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

    def wait_for(self, predicate: Callable[[dict[str, Any]], bool], timeout: float = 25.0) -> dict[str, Any]:
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


def extension_source() -> str:
    return r'''export default function(pi) {
  pi.on("session_before_tree", async (event, ctx) => {
    if (!event.signal || event.signal !== ctx.signal) throw new Error("tree signal identity missing");
    if (event.preparation.userWantsSummary) {
      if (event.preparation.customInstructions !== "focus-166") throw new Error("custom tree focus missing");
      return {
        summary: {
          summary: "extension branch summary 166",
          details: { source: "branch-policy-166", instructions: event.preparation.customInstructions },
          usage: {
            input: 31, output: 32, cacheRead: 33, cacheWrite: 34, totalTokens: 130,
            cost: { input: 0.31, output: 0.32, cacheRead: 0.33, cacheWrite: 0.34, total: 1.30 }
          }
        },
        label: "branch-label-166"
      };
    }
    pi.appendEntry("skip-prompt-tree-166", { userWantsSummary: false });
  });
  pi.on("session_tree", async (event) => {
    pi.appendEntry("after-tree-166", {
      fromExtension: event.fromExtension,
      hasSummary: Boolean(event.summaryEntry)
    });
  });
}
'''


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def run_pty(command: list[str], env: dict[str, str], cwd: Path, driver: Callable[[int, bytearray, subprocess.Popen[bytes]], None]) -> tuple[int, str, str]:
    master, slave = pty.openpty()
    process = subprocess.Popen(command, env=env, cwd=cwd, stdin=slave, stdout=slave, stderr=subprocess.PIPE, close_fds=True)
    os.close(slave)
    os.set_blocking(master, False)
    output = bytearray()

    def read_available(timeout: float) -> bool:
        ready, _, _ = select.select([master], [], [], timeout)
        if not ready:
            return False
        try:
            chunk = os.read(master, 65536)
        except OSError:
            return False
        if chunk:
            output.extend(chunk)
            return True
        return False

    def wait(marker: bytes, start: int = 0, timeout: float = 25.0) -> int:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            found = output.find(marker, start)
            if found >= 0:
                return found + len(marker)
            if process.poll() is not None:
                break
            read_available(min(0.1, max(0.0, deadline - time.monotonic())))
        raise AssertionError(f"PTY marker {marker!r} missing; tail={output[-4000:].decode(errors='replace')}")

    try:
        wait(b"> ")
        driver(master, output, process)
        deadline = time.monotonic() + 25.0
        while process.poll() is None and time.monotonic() < deadline:
            read_available(0.1)
        if process.poll() is None:
            raise AssertionError(f"PTY exit timeout; tail={output[-4000:].decode(errors='replace')}")
        for _ in range(20):
            if not read_available(0.05):
                break
        assert process.stderr is not None
        stderr = process.stderr.read().decode("utf-8", errors="replace")
        return int(process.returncode), output.decode("utf-8", errors="replace"), stderr
    finally:
        with contextlib.suppress(OSError):
            os.close(master)
        if process.poll() is None:
            with contextlib.suppress(Exception):
                process.kill()
            with contextlib.suppress(Exception):
                process.wait(timeout=3)


def wait_for_bytes(master: int, output: bytearray, process: subprocess.Popen[bytes], marker: bytes, start: int = 0, timeout: float = 25.0) -> int:
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
                chunk = os.read(master, 65536)
            except OSError:
                chunk = b""
            output.extend(chunk)
    raise AssertionError(f"marker {marker!r} missing; tail={output[-4000:].decode(errors='replace')}")


def send(master: int, text: str) -> None:
    os.write(master, text.encode("utf-8") + b"\r")


def run(binary: Path, report: Path | None) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pi-branch-summary-166-") as raw:
        root = Path(raw)
        agent_dir = root / "agent"
        session_dir = root / "sessions"
        agent_dir.mkdir()
        session_dir.mkdir()
        settings = agent_dir / "settings.json"
        settings.write_text(json.dumps({
            "theme": "night",
            "branchSummary": {"reserveTokens": 77, "skipPrompt": False},
        }), encoding="utf-8")
        extension = root / "branch-policy.ts"
        extension.write_text(extension_source(), encoding="utf-8")
        mock = root / "mock.json"
        mock.write_text(json.dumps([{"content": f"assistant-166-{index}"} for index in range(1, 9)]), encoding="utf-8")

        env = os.environ.copy()
        env.update({"PI_AGENT_DIR": str(agent_dir), "TERM": "xterm-256color", "NO_COLOR": "1"})
        common = [
            str(binary), "--offline", "--mock-script", str(mock), "--extension", str(extension),
            "--session-dir", str(session_dir), "--no-context-files", "--no-skills",
            "--no-prompt-templates", "--no-themes", "--approve",
        ]

        rpc = RpcHarness(common + ["--mode", "rpc"], env, root)
        try:
            for index in range(1, 5):
                request_id = f"p{index}"
                rpc.send({"id": request_id, "type": "prompt", "message": f"user-166-{index}"})
                require(rpc.response(request_id).get("success") is True, f"prompt {index} rejected")
                rpc.wait_for(lambda value: value.get("type") == "agent_end")
            rpc.send({"id": "entries", "type": "get_entries"})
            entries = rpc.response("entries").get("data", {}).get("entries", [])
            assistants = [entry for entry in entries if entry.get("type") == "message" and entry.get("message", {}).get("role") == "assistant"]
            require(len(assistants) == 4, f"assistant entries missing: {assistants}")
            target = assistants[0]["id"]
            old_leaf = assistants[-1]["id"]
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

        def first_driver(master: int, output: bytearray, process: subprocess.Popen[bytes]) -> None:
            send(master, "/settings")
            pos = wait_for_bytes(master, output, process, b"branch_summary_reserve_tokens=77")
            wait_for_bytes(master, output, process, b"branch_summary_skip_prompt=false", pos)
            pos = wait_for_bytes(master, output, process, b"> ", pos)
            send(master, f"/tree {target}")
            pos = wait_for_bytes(master, output, process, b"Summarize branch?", pos)
            pos = wait_for_bytes(master, output, process, b"Choice [n]: ", pos)
            send(master, "c")
            pos = wait_for_bytes(master, output, process, b"Custom summarization instructions: ", pos)
            send(master, "focus-166")
            pos = wait_for_bytes(master, output, process, b"Summarized", pos)
            wait_for_bytes(master, output, process, b"> ", pos)
            send(master, "/quit")

        first_code, first_output, first_stderr = run_pty(common + ["--session", str(session_file)], env, root, first_driver)
        require(first_code == 0 and first_stderr == "", f"first PTY failed: {first_code} {first_stderr}")
        require("Summarize branch?" in first_output and "Custom summarization instructions:" in first_output, "interactive summary dialog missing")

        first_records = load_jsonl(session_file)
        summaries = [record for record in first_records if record.get("type") == "branch_summary"]
        require(len(summaries) == 1, f"expected one summary: {summaries}")
        summary = summaries[0]
        require(summary.get("summary") == "extension branch summary 166", f"summary mismatch: {summary}")
        require(summary.get("fromHook") is True, f"fromHook missing: {summary}")
        require(summary.get("details", {}).get("instructions") == "focus-166", f"custom focus lost: {summary}")
        require(summary.get("usage", {}).get("totalTokens") == 130, f"usage lost: {summary}")
        labels = [record for record in first_records if record.get("type") == "label" and record.get("targetId") == summary.get("id")]
        require(any(record.get("label") == "branch-label-166" for record in labels), f"label missing: {labels}")

        settings.write_text(json.dumps({
            "theme": "night",
            "branchSummary": {"reserveTokens": 77, "skipPrompt": True},
        }), encoding="utf-8")

        second_command_start = 0
        def second_driver(master: int, output: bytearray, process: subprocess.Popen[bytes]) -> None:
            nonlocal second_command_start
            send(master, "/settings")
            pos = wait_for_bytes(master, output, process, b"branch_summary_skip_prompt=true")
            pos = wait_for_bytes(master, output, process, b"> ", pos)
            second_command_start = len(output)
            send(master, f"/tree {old_leaf}")
            pos = wait_for_bytes(master, output, process, b"Tip set to", second_command_start)
            wait_for_bytes(master, output, process, b"> ", pos)
            send(master, "/quit")

        second_code, second_output, second_stderr = run_pty(common + ["--session", str(session_file)], env, root, second_driver)
        require(second_code == 0 and second_stderr == "", f"second PTY failed: {second_code} {second_stderr}")
        second_tail = second_output[second_command_start:]
        require("Summarize branch?" not in second_tail and "Choice [n]:" not in second_tail, f"skipPrompt still showed dialog: {second_tail[-2000:]}")

        final_records = load_jsonl(session_file)
        require(len([record for record in final_records if record.get("type") == "branch_summary"]) == 1, "skipPrompt appended another summary")
        custom_types = [record.get("customType") for record in final_records if record.get("type") == "custom"]
        require("skip-prompt-tree-166" in custom_types, f"no-summary hook action missing: {custom_types}")
        require(custom_types.count("after-tree-166") == 2, f"after-tree action count wrong: {custom_types}")

        result = {
            "rpcPrompts": 4,
            "reserveTokens": 77,
            "interactivePrompt": True,
            "customPrompt": "focus-166",
            "summaryFromHook": True,
            "summaryUsageTotal": 130,
            "summaryLabel": "branch-label-166",
            "skipPrompt": True,
            "skipPromptDialogSuppressed": True,
            "summaryCountAfterSkip": 1,
            "rpcExit": rpc_code,
            "firstInteractiveExit": first_code,
            "secondInteractiveExit": second_code,
            "stderrBytes": len(rpc_stderr.encode()) + len(first_stderr.encode()) + len(second_stderr.encode()),
        }
        lines = [
            "BRANCH_SUMMARY_POLICY_E2E_166=PASS",
            "RPC_PROMPTS=4",
            "RESERVE_TOKENS=77",
            "INTERACTIVE_SUMMARY_PROMPT=PASS",
            "CUSTOM_PROMPT=focus-166",
            "SUMMARY_FROM_HOOK=true",
            "SUMMARY_USAGE_TOTAL=130",
            "SUMMARY_LABEL=branch-label-166",
            "SKIP_PROMPT=true",
            "SKIP_PROMPT_DIALOG_SUPPRESSED=PASS",
            "SUMMARY_COUNT_AFTER_SKIP=1",
            "RPC_EXIT=0",
            "FIRST_INTERACTIVE_EXIT=0",
            "SECOND_INTERACTIVE_EXIT=0",
            "STDERR_BYTES=0",
            "",
            json.dumps(result, indent=2, sort_keys=True),
            "",
        ]
        text = "\n".join(lines)
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
