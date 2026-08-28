# Pi Zig checkpoint 174

Checkpoint 174 continues the native Zig 0.16.0 rewrite from checkpoint 173 against the newly supplied original Pi 0.84.1 source. This pass closes the largest remaining media-processing gap: the already-editable original `images.autoResize` setting now controls real image normalization across initial and interactive attachments, the built-in `read` tool, and extension or MCP-style tool results after result hooks have run.

No generated or synthetic feature shards were added. The implementation is ordinary Zig source plus one real executable regression fixture.

## Native image inspection and policy

A new bounded native image layer recognizes actual bytes rather than trusting a path extension or extension-provided MIME label. It handles dimensions for:

- PNG;
- JPEG;
- GIF87a and GIF89a;
- WebP;
- BMP.

JPEG and WebP EXIF orientation is parsed for provider-limit decisions. Inputs are rejected before conversion when their dimensions or total pixel area exceed conservative decoding bounds.

The provider-facing defaults match the original Pi policy:

```text
Maximum width:             2000 pixels
Maximum height:            2000 pixels
Maximum base64 payload:    4.5 MiB
JPEG quality:              80
```

Safe PNG, JPEG, GIF, and WebP images already within these limits remain byte-for-byte, including safe EXIF-oriented JPEGs. This avoids unnecessary generation loss and preserves exact durable attachment data.

When `images.autoResize` is disabled, provider-native formats remain exact even when oversized. Unsupported BMP input is still converted, matching the original behavior.

## Bounded conversion backend

Transformations that require decoding or re-encoding use an optional process-isolated ImageMagick executable. Discovery is deterministic:

1. an explicit internal/test override;
2. `PI_IMAGE_CONVERTER`;
3. `magick` or `convert` on `PATH`;
4. common private/system installation paths.

The converter is never invoked through a shell. Every request uses:

- a private temporary directory;
- unique input/output paths;
- first-frame selection for animated inputs;
- EXIF auto-orientation when transformation is required;
- metadata stripping;
- 8-bit output;
- bounded memory, map, disk, area, time, stdout, and stderr;
- deterministic subprocess timeout and cleanup.

Encoding attempts follow the original intent: PNG first, then descending JPEG quality, followed by progressive dimension reduction until the base64 payload fits or the image reaches 1×1.

Pi retains no hard image-library dependency. Without ImageMagick, safe provider-native images continue to work unchanged. Inputs requiring conversion or resizing are omitted from `@file` and `read` output with an explicit message. Arbitrary extension/tool-result payloads are retained instead of being silently destroyed when normalization is unavailable or decoding fails.

## Attachment and built-in `read` integration

Initial CLI and interactive `@file` processing now:

- reads actual image magic;
- applies the live `images.autoResize` value;
- converts BMP to PNG;
- normalizes EXIF orientation only when a transformation is needed;
- persists the resulting MIME type and base64 payload;
- appends original-compatible conversion and coordinate-mapping hints;
- reports conversion versus resize omission accurately.

The built-in `read` tool now recognizes image data before line slicing. Its image limit is raised to the existing 32 MiB file-input boundary, and image output is returned as structured tool content rather than corrupted UTF-8 text.

A 3200×1600 image therefore becomes a 2000×1000 structured image result with a durable mapping hint, while ordinary text retains the existing offset/limit behavior.

## Post-hook tool-result normalization

Tool images are normalized only after `tool_result` and `after_tool` hooks complete. This is important because an extension can replace the original result or reintroduce an oversized image.

Checkpoint 174 now:

- applies the live resize setting to legacy first-image fields and ordered image arrays;
- decodes base64 with a bounded input limit;
- treats image magic as authoritative over an incorrect declared MIME type;
- preserves exact extension base64 spelling when no transformation is needed;
- attaches conversion and coordinate hints to the tool text;
- performs the same behavior in sequential and parallel tool execution;
- retains malformed or unsupported extension images rather than dropping user data.

The normalized final result continues through JSON, protocol, terminal rendering, model context, and append-only JSONL persistence.

## Live settings propagation

`images.autoResize` now reaches:

- startup `@file` arguments;
- interactive inline `@file` turns;
- project-environment construction;
- built-in tools;
- direct RPC bash tool contexts;
- extension tool results;
- transactional runtime reload.

Changing the setting through the existing fullscreen settings editor therefore affects later turns without restarting Pi.

## Constrained build backend

Checkpoint 174 adds:

```text
-Duse-llvm=false
```

for all executable and test artifacts in `build.zig`. The default backend is unchanged. The option gives constrained builders an explicit Zig self-hosted backend path; the ordinary static Debug executable completed through this path in approximately 11 seconds in the validation container.

## Real executable image-processing validation

The final static executable passed a complete real-process fixture using ImageMagick 7.1.2-1:

```text
Oversized startup PNG:                    3000×1000 → 2000×667
BMP startup attachment:                   image/bmp → image/png, 32×16
EXIF orientation 6 JPEG:                  2400×1000 → 833×2000
Oversized encoded payload:                re-encoded below 4.5 MiB
Auto-resize disabled PNG:                  exact byte/base64 preservation
Auto-resize disabled BMP:                  still converted to PNG
Built-in read image:                      3200×1600 → 2000×1000
Post-hook extension image:                3600×900 → 2000×500
Durable JSONL checks:                     passed
All child-process stderr:                 0 bytes
```

The encoded-size fixture uses a valid PNG with a large ignored ancillary chunk, proving that the payload limit—not only dimensions—forces re-encoding.

## Validation closure

Completed gates:

```text
Native image-processing suite:             11/11 passed
Root @file/import filter:                  19/19 passed
Root read-image/import filter:             17/17 passed
Root tool-result/import filter:            18/18 passed
Ordinary executable process:               10/10 passed
SQLite repository process:                 11/11 passed
SQLite CLI/schema process:                  8 passed, 6 intentional isolates
Whole-tree Zig formatting:                 passed
Python fixture compilation:                passed
Embedded Node bridge syntax:               passed
Git diff validation:                       passed
Real-source audit:                         passed
Synthetic source files:                    0
Static Pi LLVM Debug build:                passed
Static Pi self-hosted Debug build:         passed
SQLite administration Debug build:         passed
Real image-processing E2E:                 passed
```

A cold direct all-package root test and both LLVM and self-hosted all-package module builds were attempted. Zig 0.16.0 compilation exceeded the individual command deadlines after the dedicated executable, SQLite repository, and SQLite CLI/schema processes had completed successfully. No aggregate pass or failure is claimed.

The optional `pi-sqlite-live` companion was also attempted through LLVM and self-hosted paths. Compilation exceeded the deadline, and one interrupted non-ELF output was explicitly deleted. No older executable is relabeled and no checkpoint-174 live-server artifact is published.

## Remaining parity boundary

Checkpoint 174 closes automatic attachment/read/tool-result resizing, EXIF-aware limits, unsupported-format conversion, provider payload limits, post-hook enforcement, durable hints, live setting propagation, and a constrained non-LLVM build path.

Complete Pi 0.84.1 monorepo equivalence is still not claimed. The largest remaining areas are:

1. An embedded decoder/encoder equivalent to the original Photon WASM path; checkpoint 174 uses optional external ImageMagick for transformations.
2. Clipboard image ingestion and all platform-specific clipboard formats.
3. Full structural decode validation for untouched safe images; the lightweight native inspector validates magic, dimensions, bounds, and transformation cases but intentionally avoids decoding byte-for-byte-preserved images.
4. The complete fullscreen package install/update/remove and login/account managers.
5. Complete npm, pnpm, Yarn, and Bun workspace, lockfile, lifecycle-script, global-store, and platform behavior.
6. Arbitrary asynchronously invalidated extension-owned retained component trees.
7. Function-valued extension providers and extension-owned OAuth/login callbacks.
8. Native server TLS and mutual TLS.
9. Remaining enterprise credential, telemetry, update, retry, and cross-language interoperability breadth.
