# Native WritableStream state machine

This source checkpoint starts from Root `294d09b8`. It owns `native_writable_stream.zig`, a narrow Engine binding root and destructor hook, its dedicated test/build steps, and external Node24 differential controls. It does not modify ReadableStream, TransformStream, compression, the completed grammar checkpoint, main, releases, or the active installation.

The algorithm authority is the actual `internal/webstreams/writablestream` body and its `internal/webstreams/util`, `internal/validators`, and `internal/errors` dependencies from the pinned Node v24.14.0 builtin source artifact. The artifact SHA-256 is `0CD86676BB2A46A4E772D1FD8BB3D00FCA658383BC388846DCC796547DC79263`; its JSON contains 368 actual string bodies. Relevant raw original bodies are retained as reference text under this checkpoint's provenance directory. The implementation is Zig with direct QuickJS C calls; no Node or JavaScript implementation is evaluated.

The three public classes have genuine native opaque state with class brand checks, native constructors, shared public prototypes, real methods and accessors, and `Symbol.toStringTag` descriptors. Instance state retains the underlying sink and algorithms, controller and AbortSignal, writer, stored error, queue chunks and sizes, queued write capabilities, in-flight write/close operations, abort requests, and stream closure capability. Writer state retains its stream and stable `ready` and `closed` capabilities. Every retained VM edge is marked and freed by the class lifecycle hooks.

The implementation follows the writable/erroring/errored/closed transitions, start gating, serial sink writes, close ordering, size callback and numeric coercion ordering, queue-size backpressure, readiness promise replacement, writer release and lock reacquisition, stored-error identity, abort promise reuse, signal delivery, and successful/failed in-flight close races. Sink callbacks run with the real sink as receiver. Their returns use fresh intrinsic async promises; owner-thread VM reactions advance the queue. Internal failure retirement settles retained capabilities directly and does not allocate temporary Scope roots after permanent host allocator failure.

The composition APIs return owned JSValues and accept borrowed inputs:

| API | Result |
| --- | --- |
| `install(engine)` | Installs the three real global classes once per Engine |
| `exports(engine)` | Owned object containing only the three real constructors |
| `createNative(engine, sink, strategy)` | Owned stream without consulting a mutable guest global constructor |
| `isWritableStream(engine, stream)` | Genuine native brand boolean |
| `isWritableStreamLocked(engine, stream)` | Actual writer lock boolean |
| `isWritableNative(engine, stream)` | Actual writable-state boolean, distinct from the stream brand |
| `isClosedNative(engine, stream)` | Actual terminal closed-state boolean |
| `closeQueuedOrInFlightNative(engine, stream)` | Actual pending/in-flight close state for pipe shutdown ordering |
| `isErrored(engine, stream)` | Actual terminal errored-state boolean |
| `isErroringNative(engine, stream)` | Actual transitional erroring-state boolean |
| `isErroringOrErroredNative(engine, stream)` | Actual combined error-state boolean for transform backpressure continuations |
| `streamStoredErrorNative(engine, stream)` | Owned stored error |
| `acquireWriterNative(engine, stream)` | Owned genuine writer |
| `writerWriteNative(engine, writer, chunk)` | Owned write Promise |
| `writerCloseNative(engine, writer)` | Owned close Promise |
| `writerAbortNative(engine, writer, reason)` | Owned abort Promise |
| `writerReadyNative(engine, writer)` | Owned reference to the stable readiness Promise |
| `writerClosedNative(engine, writer)` | Owned reference to the stable closed Promise |
| `writerDesiredSizeNative(engine, writer)` | Owned JS number or null during erroring/errored |
| `releaseWriterNative(engine, writer)` | Releases the real lock and rejects writer capabilities as required |
| `closeWithErrorPropagationNative(engine, writer)` | Owned Promise using the Node pipe-close algorithm |
| `controllerErrorNative(engine, controller, reason)` | Errors an actual writable controller if still writable |
| `controllerErrorIfNeededNative(engine, controller, reason)` | Same terminal-safe controller operation |

The readable owner can merge the three constructors into its `node:stream/web` export graph and use these APIs for actual pipe operations. The transform owner can provide real sink callbacks to `createNative` and retain the controller received by `sink.start`. Each stream implementation owns its own queue and promises. This checkpoint adds no MessagePort transfer protocol or synthetic Node private transfer symbols; the current Pi application use requires the public standard stream composition path.

The prepared Source56 corpus covers public constructor/prototype descriptors, getters and receivers, parameter validation, start throws/rejection/gating, serial writes, readiness identity and backpressure, size conversion and reentrancy, release and reacquisition, queued failures, close and abort races, exact reason identity, default AbortSignal reasons, borrowed-method brand checks, subclass construction, thenable assimilation, mutated global Promise, and retained state across real GC. The expected fixture is absent until an admitted genuine Node24 source run passes its terminal and complete posthash controls. Native compilation and differential replay are separate later gates.

Pinned Zig 0.16.0 formatting and AST checks pass for the implementation and test harness. Node syntax checks pass for the external input and capture driver. The separately admitted genuine Source56 capture passed against exact clean candidate `55018c7877bd952bdc01a241efdccceca38f1474`: actual Node PID 47088 exited zero and retained all 56 raw observations with no unexpected failures.

The same process observed 369 builtin keys, 368 actual string bodies, and the own `configs` property whose value is `undefined`. Serializing its actual string bodies reproduced authority SHA-256 `0CD86676BB2A46A4E772D1FD8BB3D00FCA658383BC388846DCC796547DC79263`. Full posthash verification found zero drift in all 1774 Node/tool files, all 7044 tracked candidate files, controls, candidate paths/head/clean status, and the owned process script. The expected fixture remained absent during those checks and was accepted only afterward with SHA-256 `1325C1A9B672A3F206E7711C2A3AAC4A43DDC8E4B2B169F7461AA3F8CBEA8EE5`.

The source packet is `verification/writable-stream-node24-source56-captured-20261015`. A caller preparation initially failed before any prehash or Node launch because two installed `git.exe` applications resolved to an array. The successful frozen external caller selected one exact application and retained the preparation failure/correction record. The prepared caller now includes that correction and the actual builtin inventory observer.

Source capture establishes the genuine reference observations, not native runtime equivalence. The first separately admitted native Debug compile subsequently failed at exact candidate `ae17eba02d74beec606606e850f0ed5e1a05d6f7`: PID 73512 exited one with the concrete diagnostic that `native_highlight_scope.zig` was absent from this worktree's source closure. Runtime replay was not launched. Full posthash verified zero drift across candidate 7066 files, vendor 1316 files, compiler 19546 files, Node tools 1774 files, all 15 controls, all scoped path inventories, and candidate head/clean status. The failed attempt is retained under `verification/writable-stream-native-debug-first-failed-20261015`.

After that terminal failure and posthash, the implementation was corrected to use the existing `native_sdk_prompt_scope.zig`. A source ownership audit also corrected underlying-sink retirement: the sink is retained only while at least one bound write/close/abort algorithm exists, and it is released when algorithms are cleared. The executing sink callable and receiver remain rooted across reentrant error callbacks and GC. Genuine Source56 input and expected observations remain unchanged. A fresh native compile/runtime pair is still required; no native equivalence has been established.

`public_activation=false`, `full_factory_qualified=false`, and `full_pi_qualified=false` remain in effect.
