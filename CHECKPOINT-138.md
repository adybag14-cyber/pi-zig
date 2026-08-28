# pi-zig V8 checkpoint 138

Checkpoint 138 continues the native Zig 0.16.0 rewrite from checkpoint 137. The supplied
Zig compiler archive and checkpoint were available in the container. The separately
referenced original `pi-main (2)(1).zip` was not present in `/mnt/data`, so parity work was
checked against the canonical upstream `earendil-works/pi` v0.84.1 source and protocol
documentation rather than inventing behavior from names or an incomplete local tree.

## Implemented in this checkpoint

### Project instructions and process identity

- `AGENTS.override.md` now replaces `AGENTS.md` / `CLAUDE.md` in its own directory while
  retaining parent and child directory layering.
- Every built-in bash invocation receives live Pi session, provider, model, and thinking
  metadata through its subprocess environment.

### Current provider catalogs and wire compatibility

- Imported 55 current generated models for Baseten and Qwen Token Plan international,
  China, and Individual identities.
- Preserved public provider identity separately from native transport.
- Added exact service endpoints, environment-key identities, context windows, output
  limits, image support, costs, thinking-level maps, and request compatibility metadata.
- Baseten models use the provider's `chat_template_args` thinking dialect.
- Qwen models use the provider's `enable_thinking` dialect, including model-specific
  supported-level holes.
- `ModelInfo` now retains custom `models.json` base URLs for RPC metadata as well as
  runtime resolution.

### Native `pi auth` command surface

- Added `pi auth`, `pi auth list`, `pi auth check`, and `pi auth print` command behavior.
- Supports text and JSON output, provider selection, duration parsing, exact exit status
  classification, OAuth refresh when allowed, and a strictly offline `--no-refresh` path.
- Reuses the existing native credential store and OAuth refresh implementations rather
  than introducing a second credential path.

### RPC model/thinking parity

- Expanded request parsing to retain current command-specific parameters instead of
  dropping unknown fields.
- `get_available_models`, `get_state`, `set_model`, and `cycle_model` now return full
  model objects with API identity, endpoint, capabilities, limits, and cost data.
- Explicit provider + model selection is resolved as one identity rather than changing
  only display metadata.
- `get_available_thinking_levels` and thinking cycling use the active model's actual
  capability map.
- Model and thinking changes are append-only native session-tree entries and survive
  JSONL save/load.

### RPC sessions and introspection

- Added durable entry cursors, active session trees, forkable user-message discovery,
  last-assistant retrieval, usage/cost/context statistics, and prompt/skill command
  descriptors.
- Session switching and forking update persistence, subprocess identity, and cache
  affinity.
- Manual compaction accepts custom instructions and reports summary, token/character,
  and kept-entry metadata.
- `get_messages` now follows the active branch and excludes auxiliary model/thinking,
  label, and custom metadata entries.

### RPC streaming, queues, and shell execution

- Prompt commands now require and honor `streamingBehavior` while a turn is active:
  steering is delivered during the turn and follow-up is delivered when the agent would
  otherwise stop.
- Steering/follow-up support upstream-style `one-at-a-time` and `all` queue modes.
- Replaced cross-thread plain `ArrayList` queues with mutex-protected FIFO queues and
  ownership-safe transfer.
- Deferred non-concurrent commands are held once and restored in arrival order, removing
  the previous requeue spin risk.
- Added direct RPC bash execution with correlated incremental events, process-group
  cancellation through `abort_bash`, structured completion data, context exclusion, and
  model-context insertion when not excluded.
- Shell executions persist as native `bashExecution` messages with command, raw output,
  exit code, cancellation/truncation flags, exclusion, timestamp, and optional full log
  path; save/load/fork preserves the exact shape.

### Correctness fixes

- Fixed ISO timestamp serialization that could emit signed civil components such as
  `+2024-+1-+1`.
- Updated a stale Anthropic adaptive-thinking assertion to the already-implemented
  summarized compatibility form without weakening serializer behavior.

## Validation

Executed with the supplied Zig 0.16.0 compiler:

```text
zig build test --summary all
487/487 tests passed

zig build --summary all
Debug executable build passed

scripts/audit_real_source.py
zig_files=112
zig_loc=47389
synthetic_files=0
```

A real JSONL RPC smoke verified the session header, full generated model catalog, full
active model state, and clean quit response. A ReleaseSafe build was started after the
full test pass but did not complete within the available command deadline; the source
checkpoint and last fully validated Debug binary are packaged instead of claiming an
unverified optimized artifact.

## Important remaining parity work

Checkpoint 138 is not a claim that every upstream feature is complete. The largest
remaining areas are:

- richer terminal UI parity: selectors, completion surfaces, Markdown/image rendering,
  and exact interactive ergonomics;
- full compatibility with the upstream JavaScript/TypeScript extension ecosystem and
  every extension hook;
- authoritative complete metadata for older built-in catalog rows that still carry
  zero/unknown context, output, or price values;
- remaining advanced provider behavior listed in `GAP_AUDIT.md`, including portions of
  cloud credential discovery, proxy/retry diagnostics, and specialized image APIs;
- complete byte-for-byte RPC event/message parity for every multimodal and retry edge
  case; direct RPC bash does not yet create a spill file when output exceeds the in-memory
  truncation threshold;
- broader cross-implementation and real-network provider fixtures beyond the native unit,
  integration, and smoke coverage in this repository.
