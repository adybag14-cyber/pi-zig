#!/usr/bin/env python3
"""Checkpoint 175 clipboard paste E2E.

Exercises a real interactive PTY with a fake Wayland clipboard provider:
- Ctrl+V prefers image data and inserts a temporary @file attachment,
- the attachment reaches canonical image processing and durable JSONL,
- a later Ctrl+V falls back to clipboard text without restarting Pi,
- temporary clipboard files are removed on clean shutdown.
"""
from __future__ import annotations

import argparse
import base64
import contextlib
import json
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import tempfile
import time
import zlib
from typing import Any


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)


def tiny_png(width: int = 3, height: int = 2) -> bytes:
    # RGBA rows with filter byte 0. This is structurally valid, not merely a
    # magic-byte fixture, so the full attachment path remains realistic.
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            rows.extend(((x * 70 + 20) & 255, (y * 90 + 30) & 255, ((x + y) * 45 + 10) & 255, 255))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", zlib.compress(bytes(rows))) + png_chunk(b"IEND", b"")


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
            try:
                chunk = os.read(master, 65536)
            except OSError:
                chunk = b""
            output.extend(chunk)
    raise AssertionError(f"marker {marker!r} missing; tail={output[-7000:].decode(errors='replace')}")


def session_file(session_dir: Path) -> Path:
    files = sorted(session_dir.rglob("*.jsonl"))
    require(len(files) == 1, f"expected one session JSONL, found {files}")
    return files[0]


def user_messages(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for record in records:
        if record.get("type") != "message":
            continue
        message = record.get("message")
        if isinstance(message, dict) and message.get("role") == "user":
            out.append(message)
    return out


def blocks(message: dict[str, Any]) -> list[dict[str, Any]]:
    value = message.get("content")
    if isinstance(value, str):
        return [{"type": "text", "text": value}]
    require(isinstance(value, list), f"unexpected message content: {value!r}")
    return [item for item in value if isinstance(item, dict)]


def run(binary: Path, report: Path | None) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pi-clipboard-175-") as raw:
        root = Path(raw)
        work = root / "work"
        agent = root / "agent"
        sessions = root / "sessions"
        fake_bin = root / "bin"
        home = root / "home"
        for path in (work, agent, sessions, fake_bin, home):
            path.mkdir(parents=True)

        image = tiny_png()
        image_path = root / "clipboard.png"
        image_path.write_bytes(image)
        mode_path = root / "clipboard-mode"
        mode_path.write_text("image", encoding="utf-8")
        text_value = "clipboard\r\ntext\t175\x01"
        expected_text = "clipboard\ntext    175"
        preexisting_temp = {item.resolve() for item in Path("/tmp").glob("pi-clipboard-*.*")}

        wl_paste = fake_bin / "wl-paste"
        wl_paste.write_text(
            "#!/bin/sh\n"
            "set -eu\n"
            "mode=$(cat \"$PI_CLIPBOARD_E2E_MODE\")\n"
            "case \"${1-}\" in\n"
            "  --list-types)\n"
            "    if [ \"$mode\" = image ]; then printf 'text/plain\\nimage/png\\n'; else printf 'text/plain\\n'; fi ;;\n"
            "  *)\n"
            "    type=''\n"
            "    previous=''\n"
            "    for arg in \"$@\"; do\n"
            "      if [ \"$previous\" = --type ]; then type=$arg; break; fi\n"
            "      previous=$arg\n"
            "    done\n"
            "    if [ \"$mode\" = image ] && [ \"$type\" = image/png ]; then\n"
            "      cat \"$PI_CLIPBOARD_E2E_IMAGE\"\n"
            "    elif [ \"$type\" = text ] || [ \"$type\" = 'text/plain;charset=utf-8' ]; then\n"
            "      printf '%s' \"$PI_CLIPBOARD_E2E_TEXT\"\n"
            "    else\n"
            "      exit 3\n"
            "    fi ;;\n"
            "esac\n",
            encoding="utf-8",
        )
        wl_paste.chmod(0o755)

        (agent / "settings.json").write_text(json.dumps({
            "quietStartup": True,
            "enableInstallTelemetry": False,
            "collapseChangelog": True,
        }), encoding="utf-8")
        mock = root / "mock.json"
        mock.write_text(json.dumps([
            {"content": "clipboard-image-ok-175", "tool_calls": []},
            {"content": "clipboard-text-ok-175", "tool_calls": []},
        ]), encoding="utf-8")

        env = os.environ.copy()
        env.update({
            "PI_AGENT_DIR": str(agent),
            "PI_SKIP_VERSION_CHECK": "1",
            "PI_TELEMETRY": "0",
            "PI_CLIPBOARD_E2E_MODE": str(mode_path),
            "PI_CLIPBOARD_E2E_IMAGE": str(image_path),
            "PI_CLIPBOARD_E2E_TEXT": text_value,
            "WAYLAND_DISPLAY": "wayland-175",
            "XDG_SESSION_TYPE": "wayland",
            "TERM": "xterm-256color",
            "NO_COLOR": "1",
            "HOME": str(home),
            "PATH": str(fake_bin) + os.pathsep + env.get("PATH", ""),
        })
        command = [
            str(binary), "--offline", "--mock-script", str(mock),
            "--session-dir", str(sessions), "--no-context-files", "--no-skills",
            "--no-prompt-templates", "--no-themes", "--no-extensions", "--approve",
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

            # Ctrl+V is the upstream default outside Windows. The handler runs
            # synchronously; Enter can safely queue behind clipboard reading.
            os.write(master, b"\x16\r")
            pos = wait_for(master, output, process, b"clipboard-image-ok-175", pos)
            pos = wait_for(master, output, process, b"> ", pos)

            mode_path.write_text("text", encoding="utf-8")
            os.write(master, b"\x16\r")
            pos = wait_for(master, output, process, b"clipboard-text-ok-175", pos)
            pos = wait_for(master, output, process, b"> ", pos)
            os.write(master, b"/quit\r")

            deadline = time.monotonic() + 30.0
            while process.poll() is None and time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.1)
                if ready:
                    with contextlib.suppress(OSError):
                        output.extend(os.read(master, 65536))
            require(process.poll() is not None, f"interactive process did not exit; tail={output[-5000:].decode(errors='replace')}")
            assert process.stderr is not None
            stderr = process.stderr.read().decode("utf-8", errors="replace")
            require(process.returncode == 0, f"process exited {process.returncode}: {stderr}")
            require(stderr == "", f"unexpected stderr: {stderr}")

            records = [json.loads(line) for line in session_file(sessions).read_text(encoding="utf-8").splitlines() if line.strip()]
            users = user_messages(records)
            require(len(users) == 2, f"expected two user messages, found {len(users)}")

            first = blocks(users[0])
            image_blocks = [block for block in first if block.get("type") == "image"]
            require(len(image_blocks) == 1, f"clipboard image not persisted exactly once: {first}")
            image_block = image_blocks[0]
            require(image_block.get("mimeType") == "image/png", f"wrong clipboard MIME: {image_block}")
            require(base64.b64decode(str(image_block.get("data", ""))) == image, "clipboard image bytes changed")

            second = blocks(users[1])
            second_text = "".join(str(block.get("text", "")) for block in second if block.get("type") == "text")
            require(second_text == expected_text, f"clipboard text mismatch: {second_text!r}")

            # The session contains canonical image bytes and must not depend on
            # the temporary path after shutdown. Compare against the initial
            # /tmp state so unrelated concurrent Pi processes cannot make this
            # fixture flaky.
            current_temp = {item.resolve() for item in Path("/tmp").glob("pi-clipboard-*.*")}
            leftovers = sorted(current_temp - preexisting_temp)
            require(not leftovers, f"clipboard temporary files remain: {leftovers}")

            result = {
                "imagePaste": True,
                "imageMime": image_block.get("mimeType"),
                "imageBytes": len(image),
                "textFallback": second_text,
                "textSanitized": second_text == expected_text,
                "userMessages": len(users),
                "temporaryFilesRemaining": len(leftovers),
                "exit": int(process.returncode),
                "stderrBytes": len(stderr.encode()),
            }
            if report is not None:
                report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            return result
        finally:
            with contextlib.suppress(OSError):
                os.close(master)
            if process.poll() is None:
                process.kill()
                with contextlib.suppress(Exception):
                    process.wait(timeout=3)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = run(args.binary.resolve(), args.report.resolve() if args.report else None)
    print("CLIPBOARD_PASTE_E2E_175=PASS")
    for key, value in result.items():
        print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
