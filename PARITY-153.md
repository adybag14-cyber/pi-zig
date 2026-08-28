# Pi 0.84.1 → Zig checkpoint 153 parity audit

## Closed in checkpoint 153

### Multiple images as first-class ordered content

The original Pi model represents user and tool content as arrays of text and image blocks. Checkpoint 153 now retains that cardinality and ordering throughout the Zig implementation rather than projecting only the first image.

Closed paths:

- initial CLI/RPC/user prompt images;
- model-context construction;
- append-only session save/load/fork;
- extension live updates and final tool results;
- `tool_result` and `after_tool` replacement;
- sequential and parallel tool execution;
- lifecycle and observer replay;
- JSON output;
- protocol-v1 progress and terminal items;
- extension custom rendering and native terminal image iteration;
- OpenAI Chat and Responses;
- Anthropic;
- Google;
- Mistral;
- Bedrock;
- Pi Messages;
- image-aware token estimation, capability checks and transcript repair.

### Backward compatibility

The old singular Zig fields remain accepted as the first image. Existing session files and source callers therefore continue to work, while new content can add ordered image arrays. The canonical persisted form remains the original content-block array.

### Ownership and concurrency

Every retained image has explicit allocator ownership. Clone and teardown helpers cover tool updates, tool results, hook overrides, queue records, session entries and forks. Parallel progress now emits the cloned images, usage and deferred tool names instead of dropping those fields after queue transfer.

## Evidence

- 800 source-level Zig test declarations in the frozen tree.
- Root graph: 782 pass, 7 intentional SQLite isolates, 0 fail.
- Dedicated SQLite and executable suites pass.
- Seven new Zig tests plus strengthened provider, extension, JSON and protocol fixtures.
- Real built-executable TypeScript extension gate: two partial images, three final images, three persisted images, zero stderr.
- All three Debug executables compile with the supplied Zig 0.16.0 toolchain.

## Still partial or absent

### Package lifecycle

Exact Pi manifest resource paths and conventional fallback are supported. Manifest globs, `!`/`+`/`-` filter semantics, managed npm/git installation, updates and dependency isolation remain incomplete.

### Extension UI/runtime breadth

The bridge supports a broad original extension surface, but fully arbitrary async component trees, invalidation, custom overlays/editors and every renderer lifecycle are not complete.

### Provider extensibility and enterprise authentication

Declarative providers are native. Function-valued extension transports, extension-owned OAuth/login callbacks, complete cloud bootstrap proxying and the full enterprise retry/credential matrix remain incomplete.

### Image preprocessing

Cardinality and transport fidelity are closed. Automatic resize, EXIF rotation normalization, format conversion and provider-limit adaptation remain incomplete.

### Server and fullscreen application breadth

Native server-side TLS/mTLS and complete wiring of every original fullscreen selector, login, settings, package and session-management screen remain incomplete.

## Assessment

Checkpoint 153 materially closes a cross-cutting semantic gap rather than adding a provider-specific workaround. The remaining image work is preprocessing and provider-limit adaptation, not loss of image count or ordering inside the Zig runtime.
