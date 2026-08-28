# Pi 0.84.1 → native Zig parity audit — checkpoint 174

## Closed in checkpoint 174

| Original surface | Native Zig checkpoint 174 |
|---|---|
| `images.autoResize` runtime behavior | The existing typed setting now controls startup and interactive `@file`, built-in `read`, and final extension/tool images. |
| Magic-byte detection | PNG, JPEG, GIF, WebP, and BMP are identified from content rather than filename or declared MIME alone. |
| Provider limits | Native policy enforces 2000×2000 dimensions and a 4.5 MiB base64 ceiling. |
| Safe input preservation | Provider-native images already within limits remain byte-for-byte, including safe EXIF-oriented JPEGs. |
| Unsupported input conversion | BMP is converted to PNG even when automatic resizing is disabled. |
| EXIF orientation | JPEG/WebP orientation is included in limit decisions and normalized when a transformation is required. |
| Encoded-size fallback | PNG and descending JPEG quality/dimension attempts continue until the payload fits or no useful size remains. |
| Original-compatible hints | Conversion notes and coordinate mapping notes are added to durable attachment/tool text. |
| Built-in `read` images | Image bytes become structured tool image content before line offset/limit processing. |
| Extension result enforcement | Normalization runs after `tool_result`/`after_tool`, including sequential and parallel execution. |
| Tool-result safety | Incorrect MIME is corrected from magic bytes; malformed arbitrary extension payloads are retained instead of silently dropped. |
| Live reload | The merged setting updates subsequent attachments and tools without process restart. |
| Constrained build backend | `-Duse-llvm=false` is available for all build/test artifacts while preserving the default backend. |

## Conversion architecture

The original Pi snapshot uses Photon WASM in a worker thread. Checkpoint 174 deliberately keeps the static Zig executable free of a hard image-library dependency and uses an optional process-isolated ImageMagick backend when actual decoding/re-encoding is required.

The backend is bounded, shell-free, temporary-directory isolated, first-frame-only, timeout controlled, and configured with explicit memory/map/disk/area limits. Safe supported images do not invoke it.

This closes executable behavior in the validated environment, but it is not represented as an embedded-decoder parity claim.

## Validation status

```text
Native image-processing tests:             11/11 passed
Root @file/import filter:                  19/19 passed
Root read-image/import filter:             17/17 passed
Root tool-result/import filter:            18/18 passed
Ordinary executable process:               10/10 passed
SQLite repository process:                 11/11 passed
SQLite CLI/schema process:                  8 passed, 6 intentional isolates
Static Pi default Debug build:              passed
Static Pi `-Duse-llvm=false` build:         passed
SQLite administration build:               passed
Real image-processing E2E:                 passed, zero stderr
Synthetic source files:                    0
```

Cold aggregate artifacts exceeded Zig 0.16.0 compilation deadlines after the dedicated processes above completed. No aggregate pass or failure is claimed. The optional SQLite-live companion also exceeded the deadline; no incomplete or older binary is published as checkpoint 174.

## Real executable results

```text
3000×1000 PNG:                             2000×667
32×16 BMP:                                 PNG conversion
2400×1000 EXIF-orientation-6 JPEG:          833×2000
Oversized encoded PNG:                     reduced below 4.5 MiB
Auto-resize disabled native PNG:            exact preservation
Auto-resize disabled BMP:                   PNG conversion
3200×1600 built-in read image:              2000×1000
3600×900 post-hook extension image:         2000×500
JSONL persistence:                          passed
Child-process stderr:                       0 bytes
```

## Largest remaining gaps

1. Embedded Photon-equivalent decoding and encoding rather than an optional external ImageMagick process.
2. Clipboard-image ingestion and platform-specific clipboard conversion.
3. Complete structural decoding of untouched safe inputs rather than bounded header inspection.
4. Fullscreen package and account/login administration.
5. Complete package-manager behavior across supported platforms.
6. Asynchronously invalidated extension component trees.
7. Function-valued providers and extension-owned OAuth.
8. Native server TLS/mTLS.
9. Enterprise credential, telemetry, update, retry, and interoperability breadth.
