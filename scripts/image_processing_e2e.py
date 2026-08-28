#!/usr/bin/env python3
"""Checkpoint 174 image normalization E2E.

Exercises the exact published executable across:
- startup @file attachments (dimension and byte ceilings, BMP conversion, EXIF),
- images.autoResize=false preservation,
- native read-tool image results,
- post-hook extension tool results.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import struct
import zlib
import subprocess
import tempfile
from typing import Any

MAX_B64 = int(4.5 * 1024 * 1024)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def run(command: list[str], cwd: Path, env: dict[str, str], timeout: float = 45.0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
    require(result.returncode == 0, f"command failed ({result.returncode}): {command}\nstderr={result.stderr[-6000:]}\nstdout={result.stdout[-6000:]}")
    require(result.stderr == "", f"unexpected stderr for {command}: {result.stderr[-6000:]}")
    return result


def render(converter: Path, args: list[str]) -> None:
    result = subprocess.run([str(converter), *args], capture_output=True, text=True, timeout=30, check=False)
    require(result.returncode == 0, f"ImageMagick failed: {result.stderr}")


def tiny_bmp(width: int = 32, height: int = 16) -> bytes:
    row = ((width * 3 + 3) // 4) * 4
    pixel_bytes = row * height
    data = bytearray(54 + pixel_bytes)
    data[0:2] = b"BM"
    data[2:6] = len(data).to_bytes(4, "little")
    data[10:14] = (54).to_bytes(4, "little")
    data[14:18] = (40).to_bytes(4, "little")
    data[18:22] = width.to_bytes(4, "little", signed=True)
    data[22:26] = height.to_bytes(4, "little", signed=True)
    data[26:28] = (1).to_bytes(2, "little")
    data[28:30] = (24).to_bytes(2, "little")
    data[34:38] = pixel_bytes.to_bytes(4, "little")
    for y in range(height):
        for x in range(width):
            off = 54 + y * row + x * 3
            data[off : off + 3] = bytes(((x * 9) & 255, (y * 17) & 255, ((x + y) * 5) & 255))
    return bytes(data)


def add_exif_orientation(jpeg: bytes, orientation: int) -> bytes:
    require(jpeg.startswith(b"\xff\xd8"), "not JPEG")
    tiff = (
        b"II" + b"\x2a\x00" + b"\x08\x00\x00\x00" +
        b"\x01\x00" +
        b"\x12\x01" + b"\x03\x00" + b"\x01\x00\x00\x00" +
        orientation.to_bytes(2, "little") + b"\x00\x00" +
        b"\x00\x00\x00\x00"
    )
    payload = b"Exif\x00\x00" + tiff
    segment = b"\xff\xe1" + (len(payload) + 2).to_bytes(2, "big") + payload
    return jpeg[:2] + segment + jpeg[2:]


def add_large_png_ancillary(png: bytes, payload_bytes: int = 4_000_000) -> bytes:
    """Insert an ignored ancillary chunk that pushes base64 beyond 4.5 MiB.

    This exercises the encoded-size path without requiring an expensive noisy
    image. Re-encoding strips the unknown ancillary metadata quickly.
    """
    require(png.startswith(b"\x89PNG\r\n\x1a\n"), "not PNG")
    marker = png.rfind(b"IEND")
    require(marker >= 4, "PNG IEND missing")
    chunk_start = marker - 4
    require(int.from_bytes(png[chunk_start:marker], "big") == 0, "unexpected IEND length")
    kind = b"piDA"  # ancillary/private, reserved bit valid, safe-to-copy
    data = b"checkpoint174\x00" + b"x" * max(0, payload_bytes - len(b"checkpoint174\x00"))
    chunk = len(data).to_bytes(4, "big") + kind + data + (zlib.crc32(kind + data) & 0xFFFFFFFF).to_bytes(4, "big")
    return png[:chunk_start] + chunk + png[chunk_start:]


def image_dimensions(data: bytes) -> tuple[str, int, int]:
    if data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) >= 24:
        return "image/png", int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
    if data.startswith(b"\xff\xd8"):
        pos = 2
        sof = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
        while pos + 3 < len(data):
            if data[pos] != 0xFF:
                pos += 1
                continue
            while pos < len(data) and data[pos] == 0xFF:
                pos += 1
            if pos >= len(data):
                break
            marker = data[pos]
            pos += 1
            if marker in {0xD8, 0xD9} or 0xD0 <= marker <= 0xD7:
                continue
            if pos + 2 > len(data):
                break
            length = int.from_bytes(data[pos : pos + 2], "big")
            if length < 2 or pos + length > len(data):
                break
            if marker in sof and length >= 7:
                return "image/jpeg", int.from_bytes(data[pos + 5 : pos + 7], "big"), int.from_bytes(data[pos + 3 : pos + 5], "big")
            pos += length
    raise AssertionError(f"unsupported output image magic: {data[:16]!r}")


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def only_session_file(session_dir: Path) -> Path:
    files = sorted(session_dir.glob("*.jsonl"))
    require(len(files) == 1, f"expected one session file in {session_dir}, found {files}")
    return files[0]


def content_blocks(message: dict[str, Any]) -> list[dict[str, Any]]:
    content = message.get("content", [])
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    require(isinstance(content, list), f"unexpected content: {content!r}")
    return [item for item in content if isinstance(item, dict)]


def session_message(records: list[dict[str, Any]], role: str, *, tool_name: str | None = None) -> dict[str, Any]:
    for record in records:
        if record.get("type") != "message":
            continue
        message = record.get("message")
        if not isinstance(message, dict) or message.get("role") != role:
            continue
        if tool_name is not None and message.get("toolName") != tool_name:
            continue
        return message
    raise AssertionError(f"missing session message role={role} tool={tool_name}")


def base_command(binary: Path, root: Path, session_dir: Path, mock: Path) -> list[str]:
    return [
        str(binary), "--offline", "-p", "--mode", "json",
        "--mock-script", str(mock), "--session-dir", str(session_dir),
        "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes",
        "--approve",
    ]


def case_startup(binary: Path, converter: Path, root: Path, auto_resize: bool) -> dict[str, Any]:
    tag = "resize-on" if auto_resize else "resize-off"
    case = root / tag
    work = case / "work"
    agent = case / "agent"
    sessions = case / "sessions"
    for path in (work, agent, sessions):
        path.mkdir(parents=True)
    (agent / "settings.json").write_text(json.dumps({
        "images": {"autoResize": auto_resize},
        "quietStartup": True,
        "enableInstallTelemetry": False,
    }), encoding="utf-8")
    mock = case / "mock.json"
    mock.write_text(json.dumps([{"content": f"startup-{tag}-complete-174", "tool_calls": []}]), encoding="utf-8")

    large = work / "large.png"
    noisy = work / "byte-limit.png"
    rotated_base = work / "rotated-base.jpg"
    rotated = work / "rotated.jpg"
    bmp = work / "compat.bmp"
    render(converter, ["-size", "3000x1000", "gradient:#13579b-#fedcba", "-depth", "8", str(large)])
    render(converter, ["-size", "100x100", "xc:#6a2ca0", "-depth", "8", str(noisy)])
    noisy.write_bytes(add_large_png_ancillary(noisy.read_bytes()))
    render(converter, ["-size", "2400x1000", "gradient:#602080-#20a060", "-quality", "92", str(rotated_base)])
    rotated.write_bytes(add_exif_orientation(rotated_base.read_bytes(), 6))
    bmp.write_bytes(tiny_bmp())
    require(len(base64.b64encode(noisy.read_bytes())) >= MAX_B64, "byte-limit fixture did not exceed 4.5 MiB base64")

    env = os.environ.copy()
    env.update({
        "PI_AGENT_DIR": str(agent),
        "PI_IMAGE_CONVERTER": str(converter),
        "PI_SKIP_VERSION_CHECK": "1",
        "PI_TELEMETRY": "0",
        "NO_COLOR": "1",
    })
    command = base_command(binary, case, sessions, mock)
    command += ["--no-extensions", "--no-tools", "inspect startup images", f"@{large}", f"@{bmp}"]
    if auto_resize:
        command += [f"@{rotated}", f"@{noisy}"]
    result = run(command, work, env, timeout=90)
    require(f"startup-{tag}-complete-174" in result.stdout, "startup completion missing")

    records = load_jsonl(only_session_file(sessions))
    user = session_message(records, "user")
    blocks = content_blocks(user)
    images = [block for block in blocks if block.get("type") == "image"]
    text = "\n".join(str(block.get("text", "")) for block in blocks if block.get("type") == "text")

    if not auto_resize:
        require(len(images) == 2, f"resize-off image count: {len(images)}")
        require(images[0].get("mimeType") == "image/png", f"resize-off MIME: {images[0]}")
        require(images[0].get("data") == base64.b64encode(large.read_bytes()).decode(), "resize-off did not preserve exact PNG base64")
        bmp_data = base64.b64decode(str(images[1]["data"]), validate=True)
        require(image_dimensions(bmp_data) == ("image/png", 32, 16), "resize-off BMP was not converted")
        require("converted from image/bmp to image/png" in text, "resize-off BMP conversion hint missing")
        require("displayed at" not in text, f"resize-off unexpectedly emitted dimension hint: {text}")
        return {"exactPreservation": True, "bmpConversion": True, "images": 2, "stderrBytes": 0}

    require(len(images) == 4, f"resize-on image count: {len(images)}")
    decoded = [base64.b64decode(str(block["data"]), validate=True) for block in images]
    dimensions = [image_dimensions(data) for data in decoded]
    require(dimensions[0] == ("image/png", 2000, 667), f"large PNG result: {dimensions[0]}")
    require(dimensions[1] == ("image/png", 32, 16), f"BMP result: {dimensions[1]}")
    require(dimensions[2][1:] == (833, 2000), f"EXIF result: {dimensions[2]}")
    require(dimensions[3][1:] == (100, 100), f"byte-limit result dimensions: {dimensions[3]}")
    require(len(str(images[3]["data"]).encode()) < MAX_B64, "byte-limit output still exceeds inline ceiling")
    require("original 3000x1000, displayed at 2000x667" in text, "dimension hint missing")
    require("converted from image/bmp to image/png" in text, "BMP conversion hint missing")
    require("original 1000x2400, displayed at 833x2000" in text, f"EXIF-oriented hint missing: {text}")
    require("original 100x100, displayed at 100x100" in text, "byte-only resize hint missing")
    return {
        "images": 4,
        "large": dimensions[0],
        "bmp": dimensions[1],
        "exif": dimensions[2],
        "byteLimit": dimensions[3],
        "byteLimitBase64Bytes": len(str(images[3]["data"]).encode()),
        "stderrBytes": 0,
    }


def case_read(binary: Path, converter: Path, root: Path) -> dict[str, Any]:
    case = root / "read-tool"
    work = case / "work"
    agent = case / "agent"
    sessions = case / "sessions"
    for path in (work, agent, sessions):
        path.mkdir(parents=True)
    (agent / "settings.json").write_text(json.dumps({"images": {"autoResize": True}, "quietStartup": True, "enableInstallTelemetry": False}), encoding="utf-8")
    image = work / "large-read.png"
    render(converter, ["-size", "3200x1600", "gradient:#120030-#30d0f0", "-depth", "8", str(image)])
    mock = case / "mock.json"
    mock.write_text(json.dumps([
        {"content": "reading image", "tool_calls": [{"id": "read-image-174", "name": "read", "arguments": json.dumps({"path": image.name})}]},
        {"content": "read-image-complete-174", "tool_calls": []},
    ]), encoding="utf-8")
    env = os.environ.copy()
    env.update({"PI_AGENT_DIR": str(agent), "PI_IMAGE_CONVERTER": str(converter), "PI_SKIP_VERSION_CHECK": "1", "PI_TELEMETRY": "0", "NO_COLOR": "1"})
    command = base_command(binary, case, sessions, mock) + ["--no-extensions", "--tools", "read", "read the image"]
    result = run(command, work, env, timeout=60)
    events = [json.loads(line) for line in result.stdout.splitlines() if line.strip().startswith("{")]
    ends = [event for event in events if event.get("type") == "tool_execution_end" and event.get("toolName") == "read"]
    require(len(ends) == 1, f"read terminal events: {len(ends)}")
    blocks = ends[0]["result"]["content"]
    images = [block for block in blocks if block.get("type") == "image"]
    require(len(images) == 1, f"read result images: {len(images)}")
    dims = image_dimensions(base64.b64decode(images[0]["data"], validate=True))
    require(dims == ("image/png", 2000, 1000), f"read dimensions: {dims}")
    text = "\n".join(block.get("text", "") for block in blocks if block.get("type") == "text")
    require("original 3200x1600, displayed at 2000x1000" in text, "read hint missing")
    records = load_jsonl(only_session_file(sessions))
    tool = session_message(records, "toolResult", tool_name="read")
    persisted_images = [block for block in content_blocks(tool) if block.get("type") == "image"]
    require(len(persisted_images) == 1, "read image not persisted")
    return {"dimensions": dims, "persisted": True, "stderrBytes": 0}


def case_extension(binary: Path, converter: Path, root: Path) -> dict[str, Any]:
    case = root / "extension-hook"
    work = case / "work"
    agent = case / "agent"
    sessions = case / "sessions"
    for path in (work, agent, sessions):
        path.mkdir(parents=True)
    (agent / "settings.json").write_text(json.dumps({"images": {"autoResize": True}, "quietStartup": True, "enableInstallTelemetry": False}), encoding="utf-8")
    image = work / "large-hook.png"
    render(converter, ["-size", "3600x900", "gradient:#e03050-#103070", "-depth", "8", str(image)])
    extension = case / "extension.ts"
    extension.write_text('''import { readFileSync } from "node:fs";\nimport { join } from "node:path";\nexport default function (pi: any) {\n  pi.registerTool({\n    name: "image174", label: "Image 174",\n    description: "Return a result replaced by an oversized post-hook image",\n    parameters: { type: "object", properties: {}, additionalProperties: false },\n    async execute() { return { content: [{ type: "text", text: "pre-hook" }] }; },\n  });\n  pi.on("tool_result", (event: any) => {\n    if (event.toolName !== "image174") return;\n    const data = readFileSync(join(process.cwd(), "large-hook.png")).toString("base64");\n    return { content: [\n      { type: "text", text: "post-hook-174" },\n      { type: "image", data, mimeType: "image/png" },\n    ], details: { checkpoint: 174 } };\n  });\n}\n''', encoding="utf-8")
    mock = case / "mock.json"
    mock.write_text(json.dumps([
        {"content": "calling image extension", "tool_calls": [{"id": "image-call-174", "name": "image174", "arguments": "{}"}]},
        {"content": "extension-image-complete-174", "tool_calls": []},
    ]), encoding="utf-8")
    env = os.environ.copy()
    env.update({"PI_AGENT_DIR": str(agent), "PI_IMAGE_CONVERTER": str(converter), "PI_SKIP_VERSION_CHECK": "1", "PI_TELEMETRY": "0", "NO_COLOR": "1"})
    command = base_command(binary, case, sessions, mock) + ["--extension", str(extension), "--no-builtin-tools", "--tools", "image174", "run image hook"]
    result = run(command, work, env, timeout=60)
    events = [json.loads(line) for line in result.stdout.splitlines() if line.strip().startswith("{")]
    ends = [event for event in events if event.get("type") == "tool_execution_end" and event.get("toolName") == "image174"]
    require(len(ends) == 1, f"extension terminal events: {len(ends)}")
    blocks = ends[0]["result"]["content"]
    images = [block for block in blocks if block.get("type") == "image"]
    require(len(images) == 1, f"extension images: {len(images)}")
    dims = image_dimensions(base64.b64decode(images[0]["data"], validate=True))
    require(dims == ("image/png", 2000, 500), f"post-hook dimensions: {dims}")
    text = "\n".join(block.get("text", "") for block in blocks if block.get("type") == "text")
    require("post-hook-174" in text, "hook replacement text missing")
    require("original 3600x900, displayed at 2000x500" in text, "post-hook hint missing")
    records = load_jsonl(only_session_file(sessions))
    tool = session_message(records, "toolResult", tool_name="image174")
    persisted = [block for block in content_blocks(tool) if block.get("type") == "image"]
    require(len(persisted) == 1, "extension image not persisted")
    return {"dimensions": dims, "postHook": True, "persisted": True, "stderrBytes": 0}


def execute(binary: Path, converter: Path) -> dict[str, Any]:
    require(binary.is_file(), f"binary missing: {binary}")
    require(converter.is_file(), f"converter missing: {converter}")
    require(shutil.which("node") is not None, "Node is required for extension E2E")
    with tempfile.TemporaryDirectory(prefix="pi-image-processing-174-") as raw:
        root = Path(raw)
        return {
            "startupResizeOn": case_startup(binary, converter, root, True),
            "startupResizeOff": case_startup(binary, converter, root, False),
            "readTool": case_read(binary, converter, root),
            "extensionPostHook": case_extension(binary, converter, root),
        }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--converter", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = execute(args.binary.resolve(), args.converter.resolve())
    report = {
        "checkpoint": 174,
        "status": "PASS",
        **result,
    }
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.report:
        args.report.write_text(text, encoding="utf-8")
    print("IMAGE_PROCESSING_E2E_174=PASS")
    print(text, end="")


if __name__ == "__main__":
    main()
