# Pi Zig V8 checkpoint 153

Checkpoint 153 continues the native Zig 0.16.0 rewrite against the supplied Pi 0.84.1 source and checkpoint 152. Its principal goal is to close the former single-image compatibility boundary without breaking old source callers, session files, extensions, or protocol consumers.

## Scope completed

### Ordered image ownership

The agent/tool layer now has allocator-owned image values and deep-clone/deinitialization helpers. Tool partial updates, final results, result overrides, public agent events, session entries, and model chat messages can retain an ordered image sequence.

The legacy `image_b64` and `image_mime` fields remain supported and represent the first image. New `images` slices hold the remaining ordered images in agent/model/session values. This preserves source compatibility while allowing an arbitrary number of images without duplicating the first image internally.

### Canonical user and session representation

Multi-image prompts now create one durable user message containing text followed by every image in order. The previous compatibility behavior that could synthesize separate user entries for separate attachments is no longer needed.

JSONL session handling now:

- writes every user and tool-result image as an ordered content block;
- reads old single-image and new multi-image entries;
- deep-clones image arrays during branch and complete-tree forks;
- retains images through save, load, active-branch projection and model reconstruction;
- keeps exact MIME types and base64 payloads;
- preserves the legacy first-image view for existing Zig callers.

### Extension runtime and hooks

The persistent JavaScript/TypeScript bridge no longer truncates rich content at the first image. It retains complete image arrays for:

- extension tool `onUpdate()` values;
- final extension tool results;
- `tool_result` and `after_tool` hook input and replacement output;
- canonical lifecycle payloads;
- custom tool renderers;
- message/context projection.

The Zig extension host owns every image independently. Cross-allocator transfers clone the complete sequence, live update adapters expose the first image through legacy fields plus ordered extras, and hook replacements release displaced image allocations transactionally.

### Sequential and parallel execution

Both execution modes preserve all images, usage values, and `addedToolNames` through progress and terminal events. A final whole-tree audit found that the parallel queue correctly cloned the image array but omitted it when emitting the public progress event. Checkpoint 153 fixes that production path and adds a two-image, two-tool concurrency regression test.

### JSON, protocol and rendering

JSON mode and protocol-v1 tool events emit every image in original order for both running and terminal results. Interactive extension renderers receive complete content arrays rather than a first-image projection. Native terminal rendering iterates all images while respecting terminal image capability and `showImages` state.

### Provider transports

All implemented multimodal chat transports now serialize every ordered image:

- OpenAI Chat Completions;
- OpenAI Responses, including function-call outputs;
- Anthropic Messages;
- Google Generative AI and Vertex-compatible payloads;
- Mistral Conversations;
- Amazon Bedrock Converse;
- Pi Messages.

The implementation preserves each provider’s native image block shape and MIME handling. Request-hash calculation, context estimation, GitHub Copilot vision checks and unsupported-image transcript repair also account for the complete image sequence.

### Compatibility and safety

- Old singular-image constructors continue to compile and behave as before.
- Old JSONL sessions remain readable.
- New arrays use explicit allocator ownership and deep cloning.
- Empty text with one or more images remains a valid content sequence.
- Invalid or malformed extension image records are isolated without corrupting the worker protocol.
- A standalone executable build exposed one allocator field absent from a production-only live progress adapter; this was fixed and all three executables now compile.

## Validation summary

The frozen implementation was checked with the supplied Zig 0.16.0 toolchain.

```text
Native Zig source files:                   170
Native Zig logical lines:                  87,813
Embedded JavaScript bridge lines:          915
Source-level Zig test declarations:        800
Synthetic/generated feature shards:        0

All-package root graph:                    782 passed
Intentional root SQLite isolates:          7
Root failures:                             0
Root graph total:                          789

Dedicated SQLite repository:               11/11 passed
Dedicated SQLite persistence:              5/5 passed
SQLite CLI/ABI/schema process:              8 passed, 6 isolated, 0 failed
Ordinary executable suite:                 5/5 passed
SQLite-enabled executable suite:           5/5 passed

Whole-tree formatting:                     passed
Node bridge syntax:                        passed
Real-source audit:                         passed
Static pi Debug build:                     passed
pi-sqlite Debug build:                     passed
pi-sqlite-live Debug build:                passed
```

## Real executable multi-image gate

A trusted TypeScript extension was loaded by the built `pi` executable. Its tool streamed two images and returned three differently typed images. The exact run verified:

```text
MULTI_IMAGE_EXECUTABLE_E2E=PASS
Partial image count:                       2
Final image count:                         3
Persisted JSONL image count:               3
Final assistant completion:                passed
Process stderr:                            0 bytes
```

The test checked ordered payload and MIME fidelity in live JSON events and in the durable tool-result message.

## Remaining parity boundary

Checkpoint 153 closes the previously documented multiple-image boundary. Complete Pi 0.84.1 monorepo equivalence is still not claimed. The largest remaining areas are:

1. package-manifest glob/filter semantics and managed npm/git install, update and isolation;
2. arbitrary asynchronous extension component trees, invalidation and custom retained rendering;
3. function-valued provider transports, extension-owned OAuth callbacks and complete provider reload semantics;
4. complete native fullscreen model/login/settings/session/package screens;
5. native server TLS and mutual TLS;
6. automatic image resize, rotation normalization and transcoding before provider submission;
7. the remaining enterprise credential, proxy bootstrap, retry and cross-language interoperability matrix.
