# Pi Zig V8 checkpoint 150

Checkpoint 150 continues the native Zig 0.16.0 rewrite from the exact uploaded checkpoint-149 archive and uses the supplied Pi 0.84.1 tree as the behavioral reference. This pass closes the executable built-in-tool replacement gap identified in checkpoint 149 and carries original extension tool preparation, partial results, images, structured details and result-hook mutations through the native agent, terminal, JSON and protocol paths.

## Source measurements

```text
Native Zig files under src/:              170
Native Zig logical lines under src/:      84,735
Embedded JavaScript bridge lines:            865
Source-level test declarations:              778
All-package root graph:                      767 cases
Implementation source files changed:           9
Implementation additions/deletions:       +1,476 / -103
Synthetic/generated feature shards:            0
```

## Executable replacement of built-in tools

Original Pi extensions can register a tool named `read`, `write`, `edit`, `bash`, `grep`, `find` or `ls` and replace the corresponding built-in implementation. Checkpoint 150 now preserves that behavior instead of treating same-name registrations as renderer-only metadata:

- an extension-owned schema replaces the duplicate native schema in the model-visible tool list;
- dispatch checks explicit extension ownership before native built-in dispatch;
- active-tool and no-tool restrictions still apply;
- extension errors stay isolated as tool errors;
- allocator ownership is transferred safely back to the agent thread.

Renderer-only extensions remain safe. The compatibility implementations of `createReadTool()`, `createWriteTool()`, `createEditTool()`, `createBashTool()`, `createGrepTool()`, `createFindTool()` and `createLsTool()` return an explicit native-delegation sentinel. The Zig dispatcher recognizes only that sentinel and falls back to the real native implementation. This lets the unchanged original `built-in-tool-renderer.ts` customize presentation without replacing secure native execution, while the unchanged original `tool-override.ts` genuinely replaces `read` and enforces its access policy.

## Original `prepareArguments()` semantics

Extension tools can now declare `prepareArguments()`. The persistent worker exports this capability in the manifest, and the native loop invokes it before schema validation and execution.

The transformed object becomes the authoritative arguments for validation and tool execution. A malformed return value or thrown error is converted into an isolated tool result rather than terminating the agent. Native built-in argument preparation continues unchanged when no extension owns the tool.

## Rich partial tool updates

Extension `onUpdate()` results now retain:

- ordered text updates;
- the first image payload and MIME type;
- structured `details` JSON;
- error state;
- termination state where applicable.

The worker owns updates until the tool promise resolves, then the host clones them across the worker/agent allocator boundary. The agent emits canonical `tool_execution_update` events in source order before `tool_execution_end`. Late updates after the tool promise resolves are ignored.

The current worker protocol returns updates as one ordered batch when execution completes; true cross-process live delivery while the JavaScript promise is still running remains a future parity item.

## Rich final results and `tool_result` hooks

Final extension tool results and original `tool_result`/compatibility `after_tool` hooks can now preserve or replace:

- text content;
- image content and MIME type;
- arbitrary structured details;
- `isError`;
- termination state.

The native loop applies hook replacements transactionally, releases displaced allocations, and persists the final image in the append-only session entry. Tool-result hooks receive the original content array and details rather than a flattened text-only projection.

## Terminal, JSON and protocol propagation

Rich tool progress now crosses every outward interface:

- JSON mode emits `tool_execution_update` with `partialResult` and a rich final result;
- print mode emits partial and final tool output;
- interactive mode passes partial state, images and details into extension renderers and native fallbacks;
- protocol v1 emits running `item_updated` and terminal `item_finished` tool items;
- strict protocol decoding accepts the generated details/image payloads;
- final session persistence retains tool text and image content.

## Deterministic script-worker teardown

Zig 0.16's POSIX `Child.kill()` sends `SIGTERM` and waits without escalation. An extension or dependency can install a `SIGTERM` handler and hold shutdown open indefinitely. The runtime now force-reaps the worker on POSIX and retains the native forced-termination path on Windows. A dedicated Node fixture that ignores `SIGTERM` completes and releases cleanly.

## Executable evidence

Three real executable gates passed:

1. The unchanged original `tool-override.ts` replaced native `read`, denied `.env`, returned `{ "blocked": true }`, wrote its audit record and did not expose the file secret.
2. The unchanged original `built-in-tool-renderer.ts` delegated `read` back to native Zig and returned the exact allowed file contents.
3. A TypeScript fixture transformed legacy arguments through `prepareArguments()`, emitted an ordered partial image/details update, returned a rich result, then replaced it through an original `tool_result` hook. JSON order was start → update → end.

## Validation closure

```text
Whole-tree Zig formatting:                 PASS
Node bridge syntax check:                  PASS
Real-source audit:                         PASS
All-package root graph:                    760 passed / 7 isolated / 0 failed
Root graph declarations:                   767
Dedicated SQLite repository:               11/11 passed
Dedicated SQLite CLI/ABI/schema:            8 passed / 6 isolated / 0 failed
Dedicated live SQLite persistence:           5/5 passed
Ordinary executable tests:                   5/5 passed
SQLite-enabled executable tests:             5/5 passed
All 778 source-level declarations:          executed through the complete topology
Affected extension filter:                  60/60 passed
Affected agent filter:                     273/273 passed
Affected server filter:                     31/31 passed
Affected coding-agent filter:              189/189 passed
Debug build `pi`:                           PASS
Debug build `pi-sqlite`:                    PASS
Debug build `pi-sqlite-live`:               PASS
Original tool replacement/delegation E2E:   PASS
Rich prepare/update/hook E2E:               PASS
```

The seven all-package isolates are the SQLite CLI live integration case and six C-backed repository cases. The CLI case passes in its linked SQLite CLI process, and all six repository cases pass in the dedicated repository process.

## Remaining parity boundary

Checkpoint 150 materially closes extension-owned built-in execution and rich tool-result fidelity, but complete Pi 0.84.1 equivalence is not claimed. The largest remaining areas are:

1. true live cross-process `onUpdate()` delivery while a JavaScript tool promise is still running, plus multiple-image result fidelity;
2. fully arbitrary extension component trees, overlays, dialogs, editors and asynchronous renderer invalidation;
3. function-valued provider transports, custom streaming implementations and extension-owned OAuth/login callbacks;
4. automatic installation and lifecycle management of extension npm dependencies;
5. complete wiring of every original selector, model, login, settings and session screen into the native fullscreen shell;
6. native server TLS/mTLS, automatic image resizing/transcoding and the remaining provider-specific multimodal edge cases;
7. the remaining enterprise credential, retry, remote-repository and cross-language byte-exact interoperability matrix.

## Frozen-archive and patch reconstruction

Before publication, the final single-root source ZIP was extracted into a separate cache-free directory. That exact extraction passed ZIP integrity, source equivalence, formatting, the real-source audit, the complete test topology, all three Debug builds, executable smokes and the extension replacement/rich-result E2E gates.

The binary-safe checkpoint-149 → checkpoint-150 patch was applied to a separate pristine extraction of the uploaded checkpoint 149 archive. The reconstructed source matched checkpoint 150 byte-for-byte and independently passed formatting, source audit, the complete test topology and all three Debug builds.

Every published artifact was copied to its final `/mnt/data` path in explicit chunks, flushed and `fsync`ed, atomically installed, re-read completely, independently hashed, compared byte-for-byte with its validated staging source and checked through three stable size/mtime/SHA-256 snapshots before this checkpoint was announced.
