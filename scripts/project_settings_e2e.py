#!/usr/bin/env python3
"""Checkpoint 173 real PTY coverage for global/project settings and live rendering."""
from __future__ import annotations
import argparse, contextlib, json, os, pty, select, subprocess, tempfile, time
from pathlib import Path


def require(value: bool, message: str) -> None:
    if not value:
        raise AssertionError(message)


def wait_for(master: int, out: bytearray, proc: subprocess.Popen[bytes], marker: bytes, start: int = 0, timeout: float = 40.0) -> int:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        pos = out.find(marker, start)
        if pos >= 0:
            return pos + len(marker)
        if proc.poll() is not None:
            break
        ready, _, _ = select.select([master], [], [], 0.1)
        if ready:
            with contextlib.suppress(OSError):
                out.extend(os.read(master, 65536))
    raise AssertionError(f"missing {marker!r}; tail={out[-6000:].decode(errors='replace')}")


def close_process(master: int, proc: subprocess.Popen[bytes], out: bytearray) -> str:
    deadline = time.monotonic() + 30
    while proc.poll() is None and time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.1)
        if ready:
            with contextlib.suppress(OSError):
                out.extend(os.read(master, 65536))
    require(proc.poll() is not None, "process did not exit")
    assert proc.stderr is not None
    stderr = proc.stderr.read().decode(errors="replace")
    require(proc.returncode == 0, f"exit={proc.returncode}: {stderr}")
    require(stderr == "", f"unexpected stderr: {stderr}")
    return stderr


def spawn(binary: Path, command: list[str], cwd: Path, env: dict[str, str]):
    master, slave = pty.openpty()
    proc = subprocess.Popen([str(binary), *command], cwd=cwd, env=env, stdin=slave, stdout=slave, stderr=subprocess.PIPE, close_fds=True)
    os.close(slave)
    os.set_blocking(master, False)
    return master, proc, bytearray()


def run(binary: Path, report: Path | None) -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix="pi-project-settings-173-") as raw:
        root = Path(raw)
        agent = root / "agent"
        workspace = root / "workspace"
        sessions = root / "sessions"
        (workspace / ".pi").mkdir(parents=True)
        agent.mkdir(); sessions.mkdir()
        global_path = agent / "settings.json"
        project_path = workspace / ".pi" / "settings.json"
        global_path.write_text(json.dumps({
            "customMarker": "global-preserve-173",
            "maxTurns": 32,
            "terminal": {"showTerminalProgress": False},
            "editorPaddingX": 0,
            "outputPad": 1,
        }), encoding="utf-8")
        project_path.write_text(json.dumps({"maxTurns": 16, "projectMarker": "preserve-173"}), encoding="utf-8")
        mock = root / "mock.json"
        mock.write_text(json.dumps([{"content": "assistant-project-173"}]), encoding="utf-8")
        env = os.environ.copy()
        env.update({"PI_AGENT_DIR": str(agent), "HOME": str(root / "home"), "TERM": "xterm-256color", "NO_COLOR": "1"})
        args = ["--offline", "--mock-script", str(mock), "--session-dir", str(sessions), "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--approve"]
        master, proc, out = spawn(binary, args, workspace, env)
        try:
            pos = wait_for(master, out, proc, b"> ")
            os.write(master, b"/settings\r")
            pos = wait_for(master, out, proc, b"Settings", pos)
            scope_start = len(out)
            os.write(master, b"\t")
            pos = wait_for(master, out, proc, b"PROJECT", scope_start)

            def choose(query: bytes, label: bytes) -> None:
                nonlocal pos
                begin = len(out)
                os.write(master, query)
                pos = wait_for(master, out, proc, label, begin)
                os.write(master, b"\r")
                time.sleep(0.12)
                clear = len(out)
                os.write(master, b"\x1b")
                # Clearing search preserves the selected setting, so it may be
                # outside the first viewport page. Wait for the unfiltered
                # inventory status rather than an unrelated top-row label.
                pos = wait_for(master, out, proc, b"mouse wheel/click supported", clear)

            choose(b"terminal progress", b"Terminal progress")
            # Selected item remains active after clearing the query: clear the
            # override, then add it again to exercise both project transactions.
            clear_start = len(out)
            os.write(master, b"\x7f")
            pos = wait_for(master, out, proc, b"Project override cleared", clear_start)
            os.write(master, b"\r")
            time.sleep(0.12)
            choose(b"editor padding", b"Editor padding")
            choose(b"output padding", b"Output padding")
            choose(b"tui mode", b"TUI mode")

            global_start = len(out)
            os.write(master, b"\t")
            pos = wait_for(master, out, proc, b"GLOBAL", global_start)
            choose(b"hide thinking", b"Hide thinking block")

            close_start = len(out)
            os.write(master, b"\x1b")
            pos = wait_for(master, out, proc, b"Reloaded:", close_start, timeout=60)
            prompt_start = pos
            pos = wait_for(master, out, proc, b" > ", prompt_start)
            os.write(master, b"hello-173\r")
            progress_start = len(out)
            pos = wait_for(master, out, proc, b"assistant-project-173", progress_start)
            require(b"\x1b]9;4;3\x07" in out[progress_start:], "terminal progress start missing")
            pos = wait_for(master, out, proc, b"\x1b]9;4;0\x07", progress_start)
            pos = wait_for(master, out, proc, b" > ", pos)
            os.write(master, b"/quit\r")
            stderr = close_process(master, proc, out)
        finally:
            with contextlib.suppress(OSError): os.close(master)
            if proc.poll() is None:
                proc.kill(); proc.wait(timeout=3)

        global_settings = json.loads(global_path.read_text(encoding="utf-8"))
        project_settings = json.loads(project_path.read_text(encoding="utf-8"))
        require(global_settings.get("hideThinkingBlock") is True, f"global edit missing: {global_settings}")
        require(global_settings.get("customMarker") == "global-preserve-173", "global sibling lost")
        require(project_settings.get("maxTurns") == 16, "project maxTurns lost")
        require(project_settings.get("projectMarker") == "preserve-173", "project sibling lost")
        require(project_settings.get("terminal", {}).get("showTerminalProgress") is True, f"project progress missing: {project_settings}")
        require(project_settings.get("editorPaddingX") == 1, f"project editor padding missing: {project_settings}")
        require(project_settings.get("outputPad") == 0, f"project output padding missing: {project_settings}")
        require(project_settings.get("tuiMode") == "fullscreen", f"project TUI mode missing: {project_settings}")

        # A fresh process must honor project tuiMode without a CLI override.
        master2, proc2, out2 = spawn(binary, args, workspace, env)
        try:
            pos2 = wait_for(master2, out2, proc2, b" > ")
            require(b"\x1b[?1049h" in out2[:pos2], "project fullscreen TUI setting was not applied")
            os.write(master2, b"/quit\r")
            stderr2 = close_process(master2, proc2, out2)
            require(b"\x1b[?1049l" in out2, "fullscreen terminal was not restored")
        finally:
            with contextlib.suppress(OSError): os.close(master2)
            if proc2.poll() is None:
                proc2.kill(); proc2.wait(timeout=3)

        result = {
            "projectScope": True,
            "projectClearAndRestore": True,
            "globalEdit": True,
            "maxTurnsProjectDefaultOverride": project_settings.get("maxTurns"),
            "terminalProgress": True,
            "editorPadding": project_settings.get("editorPaddingX"),
            "outputPad": project_settings.get("outputPad"),
            "settingsDrivenFullscreen": True,
            "terminalRestored": True,
            "stderrBytes": len(stderr.encode()) + len(stderr2.encode()),
        }
        if report:
            report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--binary", required=True, type=Path)
    ap.add_argument("--report", type=Path)
    ns = ap.parse_args()
    result = run(ns.binary.resolve(), ns.report.resolve() if ns.report else None)
    print("PROJECT_SETTINGS_E2E_173=PASS")
    for key, value in result.items(): print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
