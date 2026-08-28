#!/usr/bin/env python3
"""Real executable validation for native /copy and remote OSC 52 fallback."""
from __future__ import annotations

import argparse
import base64
import contextlib
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import time
import tempfile
from typing import Any


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)



def wait_for(master: int, output: bytearray, process: subprocess.Popen[bytes], marker: bytes, start: int = 0, timeout: float = 40.0) -> int:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = output.find(marker, start)
        if found >= 0:
            return found + len(marker)
        if process.poll() is not None:
            break
        ready, _, _ = select.select([master], [], [], min(0.1, max(0.0, deadline - time.monotonic())))
        if ready:
            with contextlib.suppress(OSError):
                output.extend(os.read(master, 65536))
    raise AssertionError(f"marker {marker!r} missing; tail={output[-7000:].decode(errors='replace')}")

def one_run(binary: Path, root: Path, *, remote: bool) -> dict[str, Any]:
    work = root / ("work-remote" if remote else "work-local")
    agent = root / ("agent-remote" if remote else "agent-local")
    home = root / ("home-remote" if remote else "home-local")
    fake_bin = root / ("bin-remote" if remote else "bin-local")
    for path in (work, agent, home, fake_bin):
        path.mkdir(parents=True, exist_ok=True)

    answer = "remote-copy-answer-176" if remote else "local-copy-answer-176"
    clipboard_path = root / ("remote-clipboard.txt" if remote else "local-clipboard.txt")
    calls_path = root / ("remote-calls.txt" if remote else "local-calls.txt")
    wl_copy = fake_bin / "wl-copy"
    wl_copy.write_text(
        "#!/bin/sh\n"
        "set -eu\n"
        "cat > \"$PI_COPY_E2E_OUTPUT\"\n"
        "printf 'call\\n' >> \"$PI_COPY_E2E_CALLS\"\n",
        encoding="utf-8",
    )
    wl_copy.chmod(0o755)

    (agent / "settings.json").write_text(
        json.dumps({
            "quietStartup": True,
            "enableInstallTelemetry": False,
            "collapseChangelog": True,
        }),
        encoding="utf-8",
    )
    mock = root / ("remote-mock.json" if remote else "local-mock.json")
    mock.write_text(json.dumps([{"content": answer, "tool_calls": []}]), encoding="utf-8")

    env = os.environ.copy()
    env.update({
        "PI_AGENT_DIR": str(agent),
        "PI_SKIP_VERSION_CHECK": "1",
        "PI_TELEMETRY": "0",
        "PI_COPY_E2E_OUTPUT": str(clipboard_path),
        "PI_COPY_E2E_CALLS": str(calls_path),
        "WAYLAND_DISPLAY": "wayland-176",
        "XDG_SESSION_TYPE": "wayland",
        "TERM": "xterm-256color",
        "NO_COLOR": "1",
        "HOME": str(home),
        "PATH": str(fake_bin) + os.pathsep + env.get("PATH", ""),
    })
    if remote:
        env["SSH_CONNECTION"] = "127.0.0.1 1 127.0.0.1 2"
    else:
        env.pop("SSH_CONNECTION", None)
        env.pop("SSH_CLIENT", None)
        env.pop("MOSH_CONNECTION", None)

    command = [
        str(binary), "--offline", "--mock-script", str(mock), "--no-session",
        "--no-context-files", "--no-skills", "--no-prompt-templates",
        "--no-themes", "--no-extensions", "--approve",
    ]
    master, slave = pty.openpty()
    process = subprocess.Popen(
        command,
        cwd=work,
        env=env,
        stdin=slave,
        stdout=slave,
        stderr=subprocess.PIPE,
        close_fds=True,
    )
    os.close(slave)
    os.set_blocking(master, False)
    output = bytearray()
    try:
        pos = wait_for(master, output, process, b"> ")
        os.write(master, b"question\r")
        pos = wait_for(master, output, process, answer.encode(), pos)
        pos = wait_for(master, output, process, b"> ", pos)
        os.write(master, b"/copy\r")
        pos = wait_for(master, output, process, b"Copied last agent message to clipboard", pos)
        pos = wait_for(master, output, process, b"> ", pos)
        os.write(master, b"/quit\r")

        deadline = time.monotonic() + 30.0
        while process.poll() is None and time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.1)
            if ready:
                with contextlib.suppress(OSError):
                    output.extend(os.read(master, 65536))
        require(process.poll() is not None, f"copy process did not exit; tail={output[-5000:].decode(errors='replace')}")
        assert process.stderr is not None
        stderr = process.stderr.read().decode("utf-8", errors="replace")
        stdout = output.decode("utf-8", errors="replace")
        require(process.returncode == 0, f"copy process exited {process.returncode}: {stderr}")
        require(stderr == "", f"unexpected stderr: {stderr}")
        require(clipboard_path.read_text(encoding="utf-8") == answer, "native clipboard bytes differ from assistant response")
        require(calls_path.read_text(encoding="utf-8").splitlines() == ["call"], "native clipboard command did not execute exactly once")
        require(stdout.count(answer) == 1, f"/copy reprinted assistant response: {stdout!r}")
        require("Copied last agent message to clipboard" in stdout, "copy success message missing")

        osc = "\x1b]52;c;" + base64.b64encode(answer.encode()).decode() + "\x07"
        if remote:
            require(osc in stdout, "remote OSC 52 fallback missing")
        else:
            require("\x1b]52;c;" not in stdout, "local native copy unexpectedly emitted OSC 52")

        result = {
            "remote": remote,
            "answer": answer,
            "nativeCalls": 1,
            "nativeBytes": len(answer.encode()),
            "osc52": remote,
            "assistantOccurrences": stdout.count(answer),
            "exit": int(process.returncode),
            "stderrBytes": len(stderr.encode()),
        }
        return result
    finally:
        with contextlib.suppress(OSError):
            os.close(master)
        if process.poll() is None:
            process.kill()
            with contextlib.suppress(Exception):
                process.wait(timeout=3)



def extension_run(binary: Path, root: Path) -> dict[str, Any]:
    work = root / "work-extension"
    agent = root / "agent-extension"
    home = root / "home-extension"
    fake_bin = root / "bin-extension"
    for path in (work, agent, home, fake_bin):
        path.mkdir(parents=True, exist_ok=True)

    clipboard_path = root / "extension-clipboard.txt"
    calls_path = root / "extension-calls.txt"
    wl_copy = fake_bin / "wl-copy"
    wl_copy.write_text(
        "#!/bin/sh\nset -eu\ncat > \"$PI_COPY_E2E_OUTPUT\"\nprintf 'call\\n' >> \"$PI_COPY_E2E_CALLS\"\n",
        encoding="utf-8",
    )
    wl_copy.chmod(0o755)
    extension = root / "copy-extension.ts"
    extension.write_text(
        "import { copyToClipboard } from '@mariozechner/pi-coding-agent';\n"
        "export default function(pi: any) {\n"
        "  pi.registerCommand('extension-copy', {\n"
        "    description: 'copy through compatibility export',\n"
        "    handler: async () => {\n"
        "      await copyToClipboard('extension-copy-176');\n"
        "      return { message: 'extension-copy-done-176' };\n"
        "    },\n"
        "  });\n"
        "}\n",
        encoding="utf-8",
    )
    (agent / "settings.json").write_text(json.dumps({
        "quietStartup": True,
        "enableInstallTelemetry": False,
        "collapseChangelog": True,
    }), encoding="utf-8")
    mock = root / "extension-mock.json"
    mock.write_text(json.dumps([{"content": "unused", "tool_calls": []}]), encoding="utf-8")
    env = os.environ.copy()
    env.update({
        "PI_AGENT_DIR": str(agent),
        "PI_SKIP_VERSION_CHECK": "1",
        "PI_TELEMETRY": "0",
        "PI_COPY_E2E_OUTPUT": str(clipboard_path),
        "PI_COPY_E2E_CALLS": str(calls_path),
        "WAYLAND_DISPLAY": "wayland-extension-176",
        "XDG_SESSION_TYPE": "wayland",
        "TERM": "xterm-256color",
        "NO_COLOR": "1",
        "HOME": str(home),
        "PATH": str(fake_bin) + os.pathsep + env.get("PATH", ""),
    })
    command = [
        str(binary), "--offline", "--mock-script", str(mock), "--no-session",
        "--no-context-files", "--no-skills", "--no-prompt-templates",
        "--no-themes", "--extension", str(extension), "--approve",
    ]
    master, slave = pty.openpty()
    process = subprocess.Popen(command, cwd=work, env=env, stdin=slave, stdout=slave, stderr=subprocess.PIPE, close_fds=True)
    os.close(slave)
    os.set_blocking(master, False)
    output = bytearray()
    try:
        pos = wait_for(master, output, process, b"> ")
        os.write(master, b"/extension-copy\r")
        pos = wait_for(master, output, process, b"extension-copy-done-176", pos)
        pos = wait_for(master, output, process, b"> ", pos)
        os.write(master, b"/quit\r")
        deadline = time.monotonic() + 30.0
        while process.poll() is None and time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.1)
            if ready:
                with contextlib.suppress(OSError):
                    output.extend(os.read(master, 65536))
        require(process.poll() is not None, "extension copy process did not exit")
        assert process.stderr is not None
        stderr = process.stderr.read().decode("utf-8", errors="replace")
        require(process.returncode == 0, f"extension copy exited {process.returncode}: {stderr}")
        require(stderr == "", f"extension copy stderr: {stderr}")
        require(clipboard_path.read_text(encoding="utf-8") == "extension-copy-176", "extension compatibility copy bytes differ")
        require(calls_path.read_text(encoding="utf-8").splitlines() == ["call"], "extension native clipboard command count differs")
        return {"nativeCalls": 1, "copied": True, "exit": int(process.returncode), "stderrBytes": 0}
    finally:
        with contextlib.suppress(OSError):
            os.close(master)
        if process.poll() is None:
            process.kill()
            with contextlib.suppress(Exception):
                process.wait(timeout=3)


def run(binary: Path, report: Path | None) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pi-copy-176-") as raw:
        root = Path(raw)
        local = one_run(binary, root, remote=False)
        remote = one_run(binary, root, remote=True)
        extension = extension_run(binary, root)
        result = {"local": local, "remote": remote, "extension": extension}
        if report is not None:
            report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = run(args.binary.resolve(), args.report)
    print("CLIPBOARD_COPY_E2E_176=PASS")
    print(f"LOCAL_NATIVE_CALLS={result['local']['nativeCalls']}")
    print(f"LOCAL_OSC52={str(result['local']['osc52']).lower()}")
    print(f"REMOTE_NATIVE_CALLS={result['remote']['nativeCalls']}")
    print(f"REMOTE_OSC52={str(result['remote']['osc52']).lower()}")
    print(f"ASSISTANT_REPRINTS={result['local']['assistantOccurrences'] - 1}")
    print(f"EXTENSION_COPY={str(result['extension']['copied']).lower()}")
    print(f"STDERR_BYTES={result['local']['stderrBytes'] + result['remote']['stderrBytes'] + result['extension']['stderrBytes']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
