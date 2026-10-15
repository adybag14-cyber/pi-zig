# Shared body collector source checkpoint

`native_body_collect.collect(engine, source, options)` returns a native promise.
It accepts a reader with `read()` or the existing HTTP byte-event iterator with
`next()`, and produces an owned Uint8Array, ArrayBuffer or decoded UTF-8 string.
Chunks stay in a GC-visible private array through EOF. Their final contents are
copied at EOF, retaining source-visible mutation ordering. Reader rejection
objects remain unchanged. The collector does not release a reader lock.

The original Node 24.14.0 bundled Undici `readAllBytes` authority is retained in
`web-body-node24-source-first-20261015-bundled-undici.js.txt`, lines 5816-5839,
with its identity recorded in the separate Source176 Body evidence. Only genuine
Uint8Array chunks pass the brand check. The wrong-chunk diagnostic is the actual
source TypeError text. Native UTF-8 decoding shares TextDecoder's replacement,
BOM and final incomplete-sequence logic without consulting a mutable global.
JSON parsing and web BodyUsed/locking/clone semantics belong to the calling
facade. Buffer-specific validation diagnostics and resized/detached chunk edge
cases remain outside the currently prepared control scope.

The native retained-byte budget is `min(32 MiB, Engine.memory_limit / 4)`;
callers can request a smaller limit. Exceeding it rejects with a RangeError whose
code is `NativeBodyLimit` and whose limit is recorded. No bytes are silently
truncated. This is an explicit native resource policy, separate from source
fidelity. Source ordinary `chunk.length` observations are retained separately
from intrinsic byte-size accounting. Abort/cancel is optional and preserves the
original reason; cancellation failures cannot replace a published result.

The independent native target prepares large (>512 KiB) success, UTF-8/BOM/EOF,
binary ownership, chunk mutation, shared HTTP byte framing, pending-GC roots,
wrong brands, read-error identity, budget rejection and abort/cancel controls.
This checkpoint is source-only: no compilation, runtime or allocation-failure
qualification is claimed. HTTP image integration requires the shared worker's
opt-in byte streaming for error bodies; standard worker framing is unchanged.
