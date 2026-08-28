#!/usr/bin/env python3
"""Persistent RPC E2E for token-budget compaction and setting persistence."""
from __future__ import annotations

import argparse
import contextlib
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time
from typing import Any, Callable


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

    def wait_for(self, predicate: Callable[[dict[str, Any]], bool], timeout: float = 20.0) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError(f"RPC timeout; recent output={self.raw[-30:]}")
            try:
                line = self.lines.get(timeout=remaining)
            except queue.Empty as exc:
                raise AssertionError(f"RPC timeout; recent output={self.raw[-30:]}") from exc
            self.raw.append(line)
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(item, dict) and predicate(item):
                return item

    def response(self, request_id: str, timeout: float = 20.0) -> dict[str, Any]:
        return self.wait_for(
            lambda item: item.get("type") == "response" and item.get("id") == request_id,
            timeout,
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
    const p = event.preparation;
    if (!event.signal || event.signal !== ctx.signal) throw new Error("signal mismatch");
    if (p.settings.enabled !== true || p.settings.reserveTokens !== 123 || p.settings.keepRecentTokens !== 20) {
      throw new Error(`settings mismatch: ${JSON.stringify(p.settings)}`);
    }
    if (p.isSplitTurn !== true) throw new Error(`expected split turn: ${JSON.stringify(p)}`);
    if (!Array.isArray(p.messagesToSummarize) || p.messagesToSummarize.length !== 4) {
      throw new Error(`history mismatch: ${p.messagesToSummarize?.length}`);
    }
    if (!Array.isArray(p.turnPrefixMessages) || p.turnPrefixMessages.length !== 1 || p.turnPrefixMessages[0].role !== "user") {
      throw new Error(`prefix mismatch: ${JSON.stringify(p.turnPrefixMessages)}`);
    }
    if (!p.fileOps || p.fileOps.read.length !== 0 || p.fileOps.written.length !== 0 || p.fileOps.edited.length !== 0) {
      throw new Error(`file ops mismatch: ${JSON.stringify(p.fileOps)}`);
    }
    pi.appendEntry("policy-before-165", {
      messages: p.messagesToSummarize.length,
      prefix: p.turnPrefixMessages.length,
      split: p.isSplitTurn,
      reserveTokens: p.settings.reserveTokens,
      keepRecentTokens: p.settings.keepRecentTokens,
    });
    return { compaction: {
      summary: "token budget summary 165",
      firstKeptEntryId: p.firstKeptEntryId,
      tokensBefore: p.tokensBefore,
      details: {
        splitTurn: p.isSplitTurn,
        summarizedMessages: p.messagesToSummarize.length,
        prefixMessages: p.turnPrefixMessages.length,
        reserveTokens: p.settings.reserveTokens,
        keepRecentTokens: p.settings.keepRecentTokens,
      }
    }};
  });

  pi.on("session_compact", async (event) => {
    if (event.compactionEntry.summary !== "token budget summary 165" || event.fromExtension !== true) {
      throw new Error("after compact mismatch");
    }
    pi.appendEntry("policy-after-165", { reason: event.reason, fromExtension: event.fromExtension });
    pi.setSessionName("token-budget-165");
  });
}
'''


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def run(binary: Path, report_path: Path | None) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pi-compaction-policy-165-") as raw:
        root = Path(raw)
        agent_dir = root / "agent"
        session_dir = root / "sessions"
        agent_dir.mkdir()
        session_dir.mkdir()
        settings_path = agent_dir / "settings.json"
        settings_path.write_text(json.dumps({
            "theme": "night",
            "compaction": {
                "enabled": True,
                "reserveTokens": 123,
                "keepRecentTokens": 20,
            },
        }), encoding="utf-8")
        extension = root / "policy.ts"
        extension.write_text(extension_source(), encoding="utf-8")
        mock = root / "mock.json"
        mock.write_text(json.dumps([
            {"content": "A" * 120},
            {"content": "B" * 120},
            {"content": "C" * 120},
        ]), encoding="utf-8")

        env = os.environ.copy()
        env.update({
            "PI_AGENT_DIR": str(agent_dir),
            "NO_COLOR": "1",
            "TERM": "xterm-256color",
        })
        command = [
            str(binary),
            "--offline",
            "--mock-script", str(mock),
            "--extension", str(extension),
            "--session-dir", str(session_dir),
            "--mode", "rpc",
            "--no-context-files",
            "--no-skills",
            "--no-prompt-templates",
            "--no-themes",
            "--approve",
        ]
        rpc = RpcHarness(command, env, root)
        try:
            rpc.send({"id": "state-initial", "type": "get_state"})
            initial = rpc.response("state-initial")
            require(initial.get("success") is True, f"initial state failed: {initial}")
            require(initial.get("data", {}).get("autoCompactionEnabled") is True, f"initial toggle mismatch: {initial}")

            rpc.send({"id": "disable", "type": "set_auto_compaction", "enabled": False})
            require(rpc.response("disable").get("success") is True, "disable failed")
            disabled_settings = json.loads(settings_path.read_text(encoding="utf-8"))
            require(disabled_settings["compaction"]["enabled"] is False, f"disable not persisted: {disabled_settings}")
            require(disabled_settings["compaction"]["reserveTokens"] == 123, "reserve token budget lost")
            require(disabled_settings["compaction"]["keepRecentTokens"] == 20, "retained token budget lost")
            require(disabled_settings["theme"] == "night", "unrelated setting lost")

            rpc.send({"id": "enable", "type": "set_auto_compaction", "enabled": True})
            require(rpc.response("enable").get("success") is True, "enable failed")
            enabled_settings = json.loads(settings_path.read_text(encoding="utf-8"))
            require(enabled_settings["compaction"]["enabled"] is True, f"enable not persisted: {enabled_settings}")

            for index in range(1, 4):
                request_id = f"p{index}"
                rpc.send({"id": request_id, "type": "prompt", "message": f"user-{index}"})
                require(rpc.response(request_id).get("success") is True, f"prompt {index} rejected")
                end = rpc.wait_for(lambda item: item.get("type") == "agent_end")
                require(chr(64 + index) * 40 in json.dumps(end), f"prompt {index} completion missing: {end}")

            rpc.send({"id": "before", "type": "get_entries"})
            before = rpc.response("before")
            before_entries = before.get("data", {}).get("entries", [])
            messages_before = [entry for entry in before_entries if entry.get("type") == "message"]
            require(len(messages_before) == 6, f"expected six durable messages: {len(messages_before)}")

            rpc.send({"id": "compact", "type": "compact", "customInstructions": "policy-165"})
            compact_response = rpc.response("compact")
            require(compact_response.get("success") is True, f"compact failed: {compact_response}")
            compact_data = compact_response.get("data", {})
            require(compact_data.get("summary") == "token budget summary 165", f"summary mismatch: {compact_data}")
            require(compact_data.get("details", {}).get("splitTurn") is True, f"split detail missing: {compact_data}")
            require(compact_data.get("details", {}).get("summarizedMessages") == 4, f"history detail mismatch: {compact_data}")
            require(compact_data.get("details", {}).get("prefixMessages") == 1, f"prefix detail mismatch: {compact_data}")

            rpc.send({"id": "entries", "type": "get_entries"})
            entries_response = rpc.response("entries")
            entries = entries_response.get("data", {}).get("entries", [])
            durable_messages = [entry for entry in entries if entry.get("type") == "message"]
            require(len(durable_messages) == 6, "compaction rewrote durable history")
            compactions = [entry for entry in entries if entry.get("type") == "compaction"]
            require(len(compactions) == 1, f"compaction entry count mismatch: {compactions}")
            boundary = compactions[0]
            require(boundary.get("fromHook") is True, f"hook marker lost: {boundary}")
            first_kept = boundary.get("firstKeptEntryId")
            kept_entry = next((entry for entry in entries if entry.get("id") == first_kept), None)
            require(isinstance(kept_entry, dict), f"first kept entry missing: {first_kept}")
            require(kept_entry.get("message", {}).get("role") == "assistant", f"cut was not split-turn assistant: {kept_entry}")
            custom_types = [entry.get("customType") for entry in entries if entry.get("type") == "custom"]
            require(custom_types.count("policy-before-165") == 1, f"before action missing: {custom_types}")
            require(custom_types.count("policy-after-165") == 1, f"after action missing: {custom_types}")

            rpc.send({"id": "messages", "type": "get_messages"})
            active_response = rpc.response("messages")
            active = active_response.get("data", {}).get("messages", [])
            require(active and active[0].get("role") == "compactionSummary", f"active summary missing: {active}")
            require(active[0].get("summary") == "token budget summary 165", f"active summary wrong: {active[0]}")
            active_text = json.dumps(active)
            require("user-1" not in active_text and "user-2" not in active_text, f"old history leaked into active context: {active}")
            require("C" * 40 in active_text, f"retained assistant suffix missing: {active}")

            rpc.send({"id": "state-final", "type": "get_state"})
            final_state = rpc.response("state-final")
            require(final_state.get("data", {}).get("autoCompactionEnabled") is True, f"final toggle mismatch: {final_state}")
            require(final_state.get("data", {}).get("sessionName") == "token-budget-165", f"after-hook name missing: {final_state}")
            session_file_raw = final_state.get("data", {}).get("sessionFile")
            require(isinstance(session_file_raw, str) and session_file_raw, f"session file missing: {final_state}")

            rpc.send({"id": "quit", "type": "quit"})
            require(rpc.response("quit").get("success") is True, "quit failed")
            code, stderr = rpc.finish()
            require(code == 0, f"RPC exit {code}")
            require(stderr == "", f"RPC stderr was not empty: {stderr}")
        except BaseException:
            rpc.kill()
            raise

        records = load_jsonl(Path(session_file_raw))
        require(len([record for record in records if record.get("type") == "message"]) == 6, "JSONL durable history changed")
        require(len([record for record in records if record.get("type") == "compaction"]) == 1, "JSONL boundary missing")
        result = {
            "directRootPolicy": "token-budget",
            "reserveTokens": 123,
            "keepRecentTokens": 20,
            "settingsPersistence": True,
            "unrelatedSettingsPreserved": True,
            "splitTurn": True,
            "messagesToSummarize": 4,
            "turnPrefixMessages": 1,
            "durableMessagesBefore": 6,
            "durableMessagesAfter": 6,
            "firstKeptRole": "assistant",
            "activeContextStartsWith": "compactionSummary",
            "oldHistoryExcludedFromActiveContext": True,
            "beforeHookActionImmediate": True,
            "afterHookActionImmediate": True,
            "processExit": 0,
            "stderrBytes": 0,
        }
        if report_path is not None:
            report_path.write_text("\n".join([
                "COMPACTION_POLICY_E2E_165=PASS",
                "RPC_SET_AUTO_COMPACTION_PERSISTENCE=PASS",
                "TOKEN_BUDGET_SETTINGS_PRESERVED=PASS",
                "SPLIT_TURN_SELECTION=PASS",
                "HOOK_MESSAGES_TO_SUMMARIZE=4",
                "HOOK_TURN_PREFIX_MESSAGES=1",
                "FIRST_KEPT_ROLE=assistant",
                "DURABLE_HISTORY_APPEND_ONLY=PASS",
                "ACTIVE_CONTEXT_PROJECTION=PASS",
                "PROCESS_EXIT=0",
                "STDERR_BYTES=0",
                "",
                json.dumps(result, indent=2, sort_keys=True),
                "",
            ]), encoding="utf-8")
        return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = run(args.binary.resolve(), args.report.resolve() if args.report else None)
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
