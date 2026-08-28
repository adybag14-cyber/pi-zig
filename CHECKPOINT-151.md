# Pi Zig V8 checkpoint 151

Checkpoint 151 continues the native Zig 0.16.0 rewrite from the exact uploaded checkpoint-150 archive and uses the supplied Pi 0.84.1 tree as the behavioral reference. This pass closes the largest explicit checkpoint-150 gap: extension and built-in tool progress now crosses the process boundary while execution is still in progress instead of being returned as a batch only after the tool promise or command completes.

## Source measurements

```text
Native Zig files under src/:              170
Native Zig logical lines under src/:      85,795
Embedded JavaScript bridge lines:            867
Source-level test declarations:              785
All-package root graph:                      774 cases
Implementation source files changed:           7
Implementation additions/deletions:       +1,112 / -50
Synthetic/generated feature shards:            0
```

## True cross-process extension progress

Original JavaScript and TypeScript extension tools can call `onUpdate()` while their asynchronous `execute()` promise remains unresolved. Checkpoint 150 retained those updates but returned them with the final worker response. Checkpoint 151 changes the persistent worker protocol so each normalized update is emitted immediately as a framed `tool_update` record.

The Zig runtime now:

- requests streaming mode explicitly for live extension execution;
- accepts any number of framed update records before the terminal response;
- invokes a native callback as each update arrives;
- preserves text, first-image MIME/base64, structured details and error state;
- omits streamed records from the final response, preventing duplicate outward events;
- closes a worker after transport, framing or callback failure so a stale terminal response cannot desynchronize the next request;
- keeps ordinary script exceptions isolated without unnecessarily discarding a reusable worker.

A timing-sensitive Node fixture proves that the native callback runs before the JavaScript promise creates its completion marker. The test does not infer liveness merely from final event ordering.

## Deadlock-safe lifecycle delivery

A live update arrives while the persistent script worker owns its runtime mutex. Calling the same extension's `tool_execution_update` lifecycle handler recursively at that point would try to re-enter the worker and deadlock.

Checkpoint 151 introduces explicit event-delivery scopes:

```text
all
primary_only
observer_only
```

The user-facing primary sink receives the update immediately. The host also retains an owned copy in the final tool result. Once the originating worker has released its mutex, that copy is replayed only to lifecycle observers. This preserves both properties:

- JSON, RPC, print and interactive consumers receive genuinely live progress;
- extension lifecycle observers still receive ordered updates without runtime re-entry.

The replay flag is carried through allocator boundaries and is honored by sequential and parallel execution. Existing non-script updates continue to use ordinary all-sink delivery.

## Parallel live-tool event queue

Parallel tools execute on worker tasks but renderer, protocol, session and extension callbacks must remain on the agent thread. Checkpoint 151 adds a bounded native event queue containing:

- owned rich progress records;
- completion records identifying the originating tool.

Each worker clones progress into its own arena and enqueues it. The agent thread drains updates and completions in arrival order, emits each update against the correct tool-call identity, runs deferred lifecycle replay only after completion, then persists final results in original call order. The queue applies backpressure instead of allowing unbounded progress allocation.

Dedicated tests run two streaming tools concurrently and verify that each tool's update precedes its matching terminal event.

## Native bash streaming

The native bash tool previously returned complete stdout/stderr only after process termination during ordinary agent turns. It now uses the existing pipe-draining child path whenever a progress callback is present.

A native adapter converts byte deltas into replacement-style accumulated snapshots shared by TUI, JSON, RPC and extension renderers:

- the first available output is emitted immediately;
- subsequent output is throttled to approximately 100 ms;
- a dirty final snapshot is flushed when execution completes;
- stdout and stderr drain threads are serialized through an I/O mutex;
- retained progress is tail-bounded to 128 KiB;
- each update carries `{"kind":"output","mode":"snapshot"}` details;
- the final tool result still preserves the established complete stdout/stderr behavior.

Sequential bash execution runs in an I/O task and sends progress back through a queue, preventing UI and lifecycle callbacks from running on a pipe-drain thread. Parallel bash uses the shared parallel-tool event queue.

A real shell command writes `first`, pauses, creates a completion marker, then writes `second`. The executable emits a `first` snapshot while the marker is absent and a final `firstsecond` snapshot before `tool_execution_end`.

## Regression coverage

Checkpoint 151 adds seven source-level tests:

1. JavaScript runtime progress arrives before promise resolution.
2. The extension host forwards live updates and retains observer replay.
3. A streaming external update is emitted before tool execution returns.
4. Parallel streaming tools deliver each update before its matching end event.
5. Primary live delivery precedes deferred lifecycle-observer replay.
6. Native bash streams accumulated output before command completion.
7. Native progress snapshots are throttled and tail-bounded.

The complete all-package graph passes with 767 cases executed and seven intentional SQLite isolates. All isolates execute successfully in their dedicated linked processes.

## Executable evidence

The exact executable gate covers two independent paths.

### JavaScript/TypeScript extension

A TypeScript extension:

1. calls `onUpdate()`;
2. records that the call returned;
3. sleeps for 350 ms;
4. creates a resolution marker;
5. returns its final result;
6. observes the deferred `tool_execution_update` lifecycle event.

The verified extension log is:

```text
execute:onUpdate-returned
execute:resolved
hook:update:marker=true:text=partial:checkpoint151
```

The primary JSON update was observed while the marker did not yet exist. Exactly one outward progress event was emitted.

### Native bash

A real native bash call produced:

```text
first
firstsecond
```

The first snapshot was observed before the shell created its completion marker. The final accumulated snapshot and structured details were retained, followed by the final tool event and assistant turn.

## Archive and reconstruction guarantees

The checkpoint source archive has one root directory and excludes `.git`, `.zig-cache`, `zig-out` and `__pycache__`. Validation includes:

- whole-tree Zig formatting;
- embedded bridge syntax validation under Node.js 22.16.0;
- real-source audit with zero synthetic files;
- complete test topology;
- Debug builds of `pi`, `pi-sqlite` and `pi-sqlite-live`;
- exact-ZIP extension and native-bash live-progress gates;
- binary-safe patch application to the uploaded checkpoint-150 source;
- byte-for-byte reconstructed-source comparison;
- repeat tests and builds from the reconstructed source.

## Remaining parity boundary

Checkpoint 151 closes true live tool-update delivery for original script extensions and native bash, but complete Pi 0.84.1 monorepo equivalence is not claimed. The largest remaining areas are:

- live `AbortSignal` propagation and cancellation of JavaScript/TypeScript tool promises;
- multiple-image fidelity through every extension, provider, session and renderer path;
- fully arbitrary extension component trees, overlays, dialogs, editors and asynchronous invalidation;
- function-valued provider transports, custom extension streaming and extension-owned OAuth callbacks;
- automatic installation, isolation and lifecycle management of extension-owned npm dependencies;
- complete wiring of every original coding-agent selector, login, settings and package screen into the retained fullscreen shell;
- native server TLS/mTLS, automatic image resize/transcoding and the remaining enterprise credential/retry/interoperability matrix.
