#!/usr/bin/env python3
"""End-to-end validation for compaction/tree extension hooks in Pi Zig."""
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


class RpcHarness:
    def __init__(self, command: list[str], env: dict[str, str], cwd: Path | None = None):
        self.process = subprocess.Popen(
            command,
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            cwd=cwd,
        )
        assert self.process.stdin is not None
        assert self.process.stdout is not None
        self.lines: queue.Queue[str] = queue.Queue()
        self.raw: list[str] = []
        self.seen: list[dict[str, Any]] = []
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

    def wait_for(self, predicate: Callable[[dict[str, Any]], bool], *, timeout: float = 20.0) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError(f"RPC event timeout; recent output={self.raw[-30:]}")
            try:
                line = self.lines.get(timeout=remaining)
            except queue.Empty as exc:
                raise AssertionError(f"RPC event timeout; recent output={self.raw[-30:]}") from exc
            self.raw.append(line)
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(item, dict):
                self.seen.append(item)
                if predicate(item):
                    return item

    def response(self, request_id: str, *, timeout: float = 20.0) -> dict[str, Any]:
        return self.wait_for(
            lambda item: item.get("type") == "response" and item.get("id") == request_id,
            timeout=timeout,
        )

    def finish(self) -> tuple[int, str]:
        assert self.process.stdin is not None
        self.process.stdin.close()
        code = self.process.wait(timeout=15)
        assert self.process.stderr is not None
        stderr = self.process.stderr.read()
        self.reader.join(timeout=2)
        return code, stderr

    def kill(self) -> None:
        with contextlib.suppress(Exception):
            self.process.kill()
        with contextlib.suppress(Exception):
            self.process.wait(timeout=3)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def extension_source() -> str:
    return r'''export default function(pi) {
  pi.on("session_before_compact", async (event, ctx) => {
    if (event.type !== "session_before_compact") throw new Error("compact event type missing");
    if (!event.signal || event.signal !== ctx.signal) throw new Error("compact signal identity missing");
    if (!Array.isArray(event.branchEntries) || event.branchEntries.length < 8) throw new Error("compact branch incomplete");
    if (!Array.isArray(event.preparation.messagesToSummarize)) throw new Error("compact messages missing");
    if (event.customInstructions === "cancel-164") {
      pi.appendEntry("cancel-compact-164", { reason: event.reason, instructions: event.customInstructions });
      pi.setSessionName("cancel-hooked-164");
      return { cancel: true };
    }
    return {
      compaction: {
        summary: "extension compact summary 164",
        firstKeptEntryId: event.preparation.firstKeptEntryId,
        tokensBefore: event.preparation.tokensBefore,
        details: { source: "extension-164", instructions: event.customInstructions, reason: event.reason },
        usage: {
          input: 11,
          output: 12,
          cacheRead: 13,
          cacheWrite: 14,
          totalTokens: 50,
          cost: { input: 0.11, output: 0.12, cacheRead: 0.13, cacheWrite: 0.14, total: 0.50 }
        }
      }
    };
  });

  pi.on("session_compact", async (event) => {
    if (event.type !== "session_compact") throw new Error("compact after type missing");
    if (event.compactionEntry.summary !== "extension compact summary 164") throw new Error("compact summary mismatch");
    if (event.fromExtension !== true || event.reason !== "manual" || event.willRetry !== false) throw new Error("compact metadata mismatch");
    pi.appendEntry("after-compact-164", { fromExtension: event.fromExtension, reason: event.reason });
    pi.setSessionName("compact-hooked-164");
  });

  pi.on("session_before_tree", async (event, ctx) => {
    if (event.type !== "session_before_tree") throw new Error("tree event type missing");
    if (!event.signal || event.signal !== ctx.signal) throw new Error("tree signal identity missing");
    if (event.preparation.userWantsSummary !== true) throw new Error("tree summary flag missing");
    if (!Array.isArray(event.preparation.entriesToSummarize) || event.preparation.entriesToSummarize.length === 0) throw new Error("tree entries missing");
    return {
      summary: {
        summary: "extension tree summary 164",
        details: { source: "tree-extension-164", instructions: event.preparation.customInstructions },
        usage: {
          input: 21,
          output: 22,
          cacheRead: 23,
          cacheWrite: 24,
          totalTokens: 90,
          cost: { input: 0.21, output: 0.22, cacheRead: 0.23, cacheWrite: 0.24, total: 0.90 }
        }
      },
      label: "tree-label-164"
    };
  });

  pi.on("session_tree", async (event) => {
    if (event.type !== "session_tree") throw new Error("tree after type missing");
    if (!event.summaryEntry || event.summaryEntry.summary !== "extension tree summary 164") throw new Error("tree summary mismatch");
    if (event.fromExtension !== true) throw new Error("tree extension marker missing");
    pi.appendEntry("after-tree-164", { fromExtension: event.fromExtension, oldLeafId: event.oldLeafId });
    pi.setSessionName("tree-hooked-164");
  });
}
'''



def run_pty_commands(command: list[str], env: dict[str, str], commands: list[str], cwd: Path | None = None) -> tuple[int, str, str]:
    """Run Pi with a real controlling terminal and return decoded terminal output."""
    master_fd, slave_fd = pty.openpty()
    process = subprocess.Popen(
        command,
        env=env,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=subprocess.PIPE,
        close_fds=True,
        cwd=cwd,
    )
    os.close(slave_fd)
    os.set_blocking(master_fd, False)
    output = bytearray()

    def read_available(timeout: float) -> bool:
        ready, _, _ = select.select([master_fd], [], [], timeout)
        if not ready:
            return False
        try:
            chunk = os.read(master_fd, 65536)
        except OSError:
            return False
        if chunk:
            output.extend(chunk)
            return True
        return False

    def wait_for_prompt(start: int, timeout: float = 20.0) -> int:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if b"> " in output[start:]:
                return len(output)
            if process.poll() is not None:
                break
            read_available(min(0.1, max(0.0, deadline - time.monotonic())))
        raise AssertionError(f"interactive prompt timeout: {output[-2000:].decode(errors='replace')}")

    def wait_for_marker(marker: bytes, start: int, timeout: float = 20.0) -> int:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            found = output.find(marker, start)
            if found >= 0:
                return found + len(marker)
            if process.poll() is not None:
                break
            read_available(min(0.1, max(0.0, deadline - time.monotonic())))
        raise AssertionError(f"interactive marker {marker!r} timeout: {output[-4000:].decode(errors='replace')}")

    try:
        cursor = wait_for_prompt(0)
        for index, item in enumerate(commands):
            start = len(output)
            os.write(master_fd, item.encode("utf-8") + b"\r")
            if index + 1 < len(commands):
                marker = b"Summarized" if item.startswith("/tree ") else item.encode("utf-8")
                after_marker = wait_for_marker(marker, start)
                cursor = wait_for_prompt(after_marker)
        deadline = time.monotonic() + 20.0
        while process.poll() is None and time.monotonic() < deadline:
            read_available(0.1)
        if process.poll() is None:
            raise AssertionError(f"interactive exit timeout: {output[-4000:].decode(errors='replace')}")
        code = process.returncode
        for _ in range(20):
            if not read_available(0.05):
                break
        assert process.stderr is not None
        stderr = process.stderr.read().decode("utf-8", errors="replace")
        return int(code), output.decode("utf-8", errors="replace"), stderr
    finally:
        with contextlib.suppress(OSError):
            os.close(master_fd)
        if process.poll() is None:
            with contextlib.suppress(Exception):
                process.kill()
            with contextlib.suppress(Exception):
                process.wait(timeout=3)

def load_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.strip():
            value = json.loads(raw)
            require(isinstance(value, dict), f"non-object JSONL record: {value!r}")
            records.append(value)
    return records


def custom_types(records: list[dict[str, Any]]) -> list[str]:
    return [str(item.get("customType")) for item in records if item.get("type") == "custom"]


def last_session_name(records: list[dict[str, Any]]) -> str | None:
    names = [item.get("name") for item in records if item.get("type") == "session_info"]
    if names:
        value = names[-1]
        return value if isinstance(value, str) else None
    header = records[0] if records else {}
    value = header.get("name")
    return value if isinstance(value, str) else None


def validate_compaction(records: list[dict[str, Any]]) -> dict[str, Any]:
    compactions = [item for item in records if item.get("type") == "compaction"]
    require(len(compactions) == 1, f"expected one compaction, got {len(compactions)}")
    compact = compactions[0]
    require(compact.get("summary") == "extension compact summary 164", f"bad compact summary: {compact}")
    require(compact.get("fromHook") is True, f"compaction missing fromHook: {compact}")
    require(compact.get("details", {}).get("source") == "extension-164", f"compaction details lost: {compact}")
    usage = compact.get("usage", {})
    require(usage.get("input") == 11 and usage.get("output") == 12, f"compaction usage lost: {usage}")
    require(usage.get("totalTokens") == 50, f"compaction total tokens lost: {usage}")
    require(abs(float(usage.get("cost", {}).get("total", -1)) - 0.50) < 1e-9, f"compaction cost lost: {usage}")
    return compact


def validate_tree(records: list[dict[str, Any]]) -> dict[str, Any]:
    summaries = [item for item in records if item.get("type") == "branch_summary"]
    require(len(summaries) == 1, f"expected one branch summary, got {len(summaries)}")
    summary = summaries[0]
    require(summary.get("summary") == "extension tree summary 164", f"bad tree summary: {summary}")
    require(summary.get("fromHook") is True, f"branch summary missing fromHook: {summary}")
    require(summary.get("details", {}).get("source") == "tree-extension-164", f"tree details lost: {summary}")
    usage = summary.get("usage", {})
    require(usage.get("input") == 21 and usage.get("output") == 22, f"tree usage lost: {usage}")
    require(usage.get("totalTokens") == 90, f"tree total tokens lost: {usage}")
    labels = [item for item in records if item.get("type") == "label" and item.get("targetId") == summary.get("id")]
    require(any(item.get("label") == "tree-label-164" for item in labels), f"tree label missing: {labels}")
    return summary


def run(binary: Path, report_path: Path | None) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pi-session-hooks-164-") as raw:
        root = Path(raw)
        agent_dir = root / "agent"
        session_dir = root / "sessions"
        agent_dir.mkdir()
        session_dir.mkdir()
        extension = root / "hooks.ts"
        extension.write_text(extension_source(), encoding="utf-8")
        mock = root / "mock.json"
        mock.write_text(json.dumps([{"content": f"assistant-response-{index}"} for index in range(1, 10)]), encoding="utf-8")

        env = os.environ.copy()
        env.update({
            "PI_AGENT_DIR": str(agent_dir),
            "TERM": "xterm-256color",
            "NO_COLOR": "1",
        })
        common = [
            str(binary),
            "--offline",
            "--mock-script", str(mock),
            "--extension", str(extension),
            "--session-dir", str(session_dir),
            "--no-context-files",
            "--no-skills",
            "--no-prompt-templates",
            "--no-themes",
            "--approve",
        ]
        rpc = RpcHarness(common + ["--mode", "rpc"], env, root)
        try:
            for index in range(1, 5):
                request_id = f"p{index}"
                rpc.send({"id": request_id, "type": "prompt", "message": f"user-message-{index}"})
                response = rpc.response(request_id)
                require(response.get("success") is True, f"prompt response failed: {response}")
                end = rpc.wait_for(lambda item: item.get("type") == "agent_end")
                require(f"assistant-response-{index}" in json.dumps(end), f"prompt {index} did not finish: {end}")

            rpc.send({"id": "before", "type": "get_entries"})
            before = rpc.response("before")
            entries_before = before.get("data", {}).get("entries", [])
            require(len(entries_before) >= 8, f"insufficient entries before compact: {len(entries_before)}")
            assistant_targets = [item for item in entries_before if item.get("type") == "message" and isinstance(item.get("message"), dict) and item["message"].get("role") == "assistant"]
            require(assistant_targets, f"no assistant target in entries: {entries_before}")
            tree_target = assistant_targets[0].get("id")
            require(isinstance(tree_target, str) and tree_target, "tree target ID missing")

            rpc.send({"id": "compact", "type": "compact", "customInstructions": "focus-164"})
            compact_response = rpc.response("compact")
            require(compact_response.get("success") is True, f"compact failed: {compact_response}")
            require(compact_response.get("data", {}).get("summary") == "extension compact summary 164", f"RPC compact summary mismatch: {compact_response}")
            require(compact_response.get("data", {}).get("details", {}).get("source") == "extension-164", f"RPC compact details mismatch: {compact_response}")

            rpc.send({"id": "compact-state", "type": "get_state"})
            compact_state = rpc.response("compact-state")
            require(compact_state.get("data", {}).get("sessionName") == "compact-hooked-164", f"after-compact name not immediate: {compact_state}")
            session_file_raw = compact_state.get("data", {}).get("sessionFile")
            require(isinstance(session_file_raw, str) and session_file_raw, f"session file missing: {compact_state}")
            session_file = Path(session_file_raw)

            rpc.send({"id": "after", "type": "get_entries"})
            after = rpc.response("after")
            entries_after = after.get("data", {}).get("entries", [])
            require("after-compact-164" in custom_types(entries_after), f"after compact action not immediate: {entries_after[-5:]}")
            validate_compaction([{"type": "session"}] + entries_after)

            rpc.send({"id": "cancel", "type": "compact", "customInstructions": "cancel-164"})
            cancel = rpc.response("cancel")
            require(cancel.get("success") is False, f"cancel compact unexpectedly succeeded: {cancel}")
            require(cancel.get("data", {}).get("error") == "Compaction cancelled", f"cancel response mismatch: {cancel}")

            rpc.send({"id": "cancel-state", "type": "get_state"})
            cancel_state = rpc.response("cancel-state")
            require(cancel_state.get("data", {}).get("sessionName") == "cancel-hooked-164", f"cancel hook actions not immediate: {cancel_state}")
            rpc.send({"id": "cancel-entries", "type": "get_entries"})
            cancel_entries = rpc.response("cancel-entries").get("data", {}).get("entries", [])
            require("cancel-compact-164" in custom_types(cancel_entries), "cancel hook durable action missing")
            require(len([item for item in cancel_entries if item.get("type") == "compaction"]) == 1, "cancelled compact appended a boundary")

            rpc.send({"id": "quit", "type": "quit"})
            quit_response = rpc.response("quit")
            require(quit_response.get("success") is True, f"quit failed: {quit_response}")
            code, rpc_stderr = rpc.finish()
            require(code == 0, f"RPC process exit {code}")
            require(rpc_stderr == "", f"RPC stderr was not empty: {rpc_stderr}")
        except BaseException:
            rpc.kill()
            raise

        require(session_file.is_file(), f"session file not saved: {session_file}")
        records_after_rpc = load_jsonl(session_file)
        validate_compaction(records_after_rpc)
        require(last_session_name(records_after_rpc) == "cancel-hooked-164", f"cancel name not persisted: {last_session_name(records_after_rpc)}")

        interactive_code, interactive_stdout, interactive_stderr = run_pty_commands(
            common + ["--session", str(session_file)],
            env,
            [f"/tree {tree_target} --summary tree-focus-164", "/quit"],
            root,
        )
        require(interactive_code == 0, f"interactive tree exit {interactive_code}: {interactive_stderr}")
        require(interactive_stderr == "", f"interactive tree stderr was not empty: {interactive_stderr}")
        require("Summarized" in interactive_stdout, f"tree completion output missing: {interactive_stdout[-2000:]}")

        final_records = load_jsonl(session_file)
        compact = validate_compaction(final_records)
        tree = validate_tree(final_records)
        types = custom_types(final_records)
        require(types.count("after-compact-164") == 1, f"after compact action count wrong: {types}")
        require(types.count("cancel-compact-164") == 1, f"cancel action count wrong: {types}")
        require(types.count("after-tree-164") == 1, f"after tree action count wrong: {types}")
        require(last_session_name(final_records) == "tree-hooked-164", f"tree name not persisted: {last_session_name(final_records)}")

        result = {
            "rpcPrompts": 4,
            "rpcCompactReplacement": True,
            "rpcCompactSummary": compact.get("summary"),
            "rpcCompactFromHook": compact.get("fromHook"),
            "rpcAfterHookActionsImmediate": True,
            "rpcCancellation": True,
            "rpcCancellationActionsImmediate": True,
            "durableCompactionUsageTotal": compact.get("usage", {}).get("totalTokens"),
            "treeTargetId": tree_target,
            "treeSummary": tree.get("summary"),
            "treeFromHook": tree.get("fromHook"),
            "treeLabel": "tree-label-164",
            "durableTreeUsageTotal": tree.get("usage", {}).get("totalTokens"),
            "finalSessionName": last_session_name(final_records),
            "rpcExit": code,
            "interactiveExit": interactive_code,
            "stderrBytes": len(rpc_stderr.encode()) + len(interactive_stderr.encode()),
            "finalJsonlRecords": len(final_records),
        }
        lines = [
            "SESSION_HOOKS_E2E_164=PASS",
            "RPC_PROMPTS=4",
            "RPC_COMPACTION_REPLACEMENT=PASS",
            "RPC_COMPACTION_FROM_HOOK=true",
            "RPC_AFTER_COMPACT_ACTIONS_IMMEDIATE=PASS",
            "RPC_COMPACTION_CANCELLATION=PASS",
            "RPC_CANCELLATION_ACTIONS_IMMEDIATE=PASS",
            "DURABLE_COMPACTION_DETAILS=PASS",
            "DURABLE_COMPACTION_USAGE_TOTAL=50",
            "TREE_SUMMARY_REPLACEMENT=PASS",
            "TREE_SUMMARY_FROM_HOOK=true",
            "TREE_LABEL=tree-label-164",
            "TREE_AFTER_HOOK_ACTIONS=PASS",
            "DURABLE_TREE_DETAILS=PASS",
            "DURABLE_TREE_USAGE_TOTAL=90",
            "FINAL_SESSION_NAME=tree-hooked-164",
            f"FINAL_JSONL_RECORDS={len(final_records)}",
            "RPC_EXIT=0",
            "INTERACTIVE_EXIT=0",
            "STDERR_BYTES=0",
        ]
        report = "\n".join(lines) + "\n"
        if report_path is not None:
            report_path.write_text(report, encoding="utf-8")
        print(report, end="")
        return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    require(binary.is_file(), f"binary not found: {binary}")
    run(binary, args.report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
