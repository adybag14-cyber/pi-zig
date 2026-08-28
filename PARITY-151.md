# Pi 0.84.1 parity audit — checkpoint 151

Checkpoint 151 is compared directly with the supplied Pi 0.84.1 source tree. It is a native Zig rewrite with an embedded JavaScript/TypeScript compatibility bridge, not a claim that every package and edge case has already been reproduced.

## Closed in checkpoint 151

### Live extension `onUpdate()` delivery

The original agent invokes a tool's `onUpdate` callback during execution and emits `tool_execution_update` before the tool settles. The Zig bridge previously accumulated updates and returned them only with the final response. The worker protocol now emits framed progress immediately, and the native runtime consumes those frames while the extension promise is unresolved.

Status: **implemented and timing-validated**.

### Safe extension update hooks

The original coding-agent forwards tool updates to interactive rendering and extension event handlers. A process bridge creates a re-entry hazard because the originating worker is still locked when an update arrives. Checkpoint 151 delivers progress to primary consumers immediately and replays an owned copy to script lifecycle observers after the worker releases.

Status: **implemented with explicit primary/observer delivery scopes and deadlock regression coverage**.

### Parallel streaming tools

Original tool calls can run in parallel and emit independent updates. The Zig agent now queues owned progress and completion records from worker tasks, emits them on the agent thread, and persists final results in call order.

Status: **implemented with bounded backpressure and two-tool concurrency tests**.

### Native bash progress

The original core bash tool periodically emits accumulated output while a process runs. Native Zig bash now drains pipes during execution, emits accumulated 100 ms snapshots, flushes the final dirty snapshot and retains only the latest 128 KiB for progress rendering.

Status: **implemented and validated against a real delayed shell process**.

## Retained parity from earlier checkpoints

The rewrite retains the previously validated areas, including:

- native provider transports and model catalog behavior;
- append-only sessions, branching, compaction, migration and administration;
- JSON, RPC and remote-session protocol surfaces;
- terminal Unicode, Markdown, LaTeX, image transport and retained layout primitives;
- optional canonical SQLite repository and live SQLite server;
- proxy-aware HTTP/TLS clients and secure remote transport;
- original JavaScript/TypeScript extension discovery and persistent workers;
- extension hooks, tools, commands, flags, shortcuts, dialogs and runtime actions;
- declarative provider registration;
- custom renderers and built-in renderer overrides;
- executable replacement or safe native delegation of built-in tools;
- `prepareArguments`, rich partial/final results, first-image/details propagation and result-hook mutation.

## Qualified or partial areas

### Script tool cancellation

Native tools observe the shared abort flag, but the persistent JavaScript bridge does not yet expose a fully live `AbortSignal` whose state changes while an extension promise is executing.

Status: **partial**.

### Multiple images

The compatibility bridge retains a rich image payload but the complete original content-array multiplicity is not preserved consistently through every provider, progress, renderer and persistence path.

Status: **partial**.

### Arbitrary extension UI components

Useful retained compatibility exists for text, boxes, containers, Markdown, spacers, dialogs and shell mutations. Arbitrary custom component trees, asynchronous invalidation and every original TUI rendering contract are not yet equivalent.

Status: **partial**.

### Function-valued providers and OAuth

Declarative providers, model injection and native transport reuse are implemented. Extension-defined streaming functions, custom OAuth/login callbacks and every provider reload edge case remain incomplete.

Status: **partial**.

### Dependency management

Real extension-local dependencies are resolved when installed. The Zig executable does not yet automatically install, isolate, upgrade or remove extension-owned npm packages.

Status: **partial**.

### Fullscreen coding-agent screens

The retained shell has layout, overlays, focus, input, mouse, selection, search, IME and common widgets, but not every original selector, settings, login, model, session and package-management screen is wired end to end.

Status: **partial**.

### Server and enterprise matrix

Client TLS and authenticated proxy paths exist. Native server TLS/mTLS, every cloud credential bootstrap path, all retry policies and exhaustive cross-language interoperability fixtures remain incomplete.

Status: **partial**.

## Evidence summary

```text
Native Zig files:                         170
Native Zig lines:                         85,795
Embedded JavaScript bridge lines:         867
Source-level test declarations:           785
All-package graph:                        767 passed / 7 isolated / 0 failed
Dedicated SQLite repository:              11/11 passed
Dedicated SQLite live persistence:        5/5 passed
SQLite CLI/ABI/schema:                    8 passed / 6 isolated / 0 failed
Ordinary executable suite:                5/5 passed
SQLite-enabled executable suite:          5/5 passed
Live extension timing E2E:                passed
Live native-bash timing E2E:              passed
Synthetic/generated feature shards:       0
```

The seven aggregate-process isolates are the six C-backed SQLite repository cases and one SQLite CLI integration case. All execute successfully in dedicated linked processes and are not omitted behavior.
