# Separate continuation data for actual Node callback scopes

This source unit adds the runtime slot and propagation needed by Node's use of V8 continuation-preserved embedder data. It keeps that data separate from the port's existing application capability context. There are 23 authored linked-VM controls. This unit has no compilation, discovered test-metadata, runtime, or public Node Environment acceptance.

## Original source

The authority is original Node v24.13 at immutable commit `def0bdf8abee441cfcbf793a8dc24a6f3b899573`. The complete V8 reaction, microtask and task-allocation sources are retained unchanged under `authority/`. The exact Node context-frame implementation and applicable original license notices are retained there too. `authority/source-acquisition.json` records original HTTP metadata, complete body hashes, native readback and references to the already committed full V8 API and checkpoint sources.

`source-design.json` maps each behavior to its actual original source. The independently reviewed exception-report proof is retained unchanged as `authority/microtask-exception-continuation-proof.json`.

Original pending and already-settled Promise reactions capture the value present at registration. Thenable jobs capture after the live then getter, when the job is constructed. Native callback jobs also capture current data. A task with an undefined capture skips setup. Successful tasks clear current data; an escaped task failure leaves it in place. The actual exception-report runtime and builtin loop do not add a hidden reset. A following task with undefined capture can therefore observe the failed task's value.

The real outer checkpoint handles a different lifetime: only for a nonempty queue, it saves current data, installs undefined, processes tasks, and restores the saved value before completed callbacks. This is why restoring around each individual job would be incorrect.

## Native ownership

The new getter returns one owned JSValue. The setter borrows its input, duplicates and publishes it before releasing the prior root, and invokes no guest property operation. It remains available during pending/disallowed cleanup. Actual pending reasons are reduced around native retirement; a marked value stored as DATA does not become a thrown event merely because of its flag.

The runtime and native queue retain external counted roots. Promise reaction data contains a genuine internal graph edge and marks it during collection. The private reaction enqueue helper selects the saved continuation capture independently of the existing application capability token. Every native job retains both original owners separately.

During execution, the new continuation setup precedes the existing capability hook and body. Successful completion clears the current slot; failure preserves it. Job cleanup keeps the actual pending completion through root retirement. The added reaction root is also retired under a bounded pending escrow, preserving a failure already produced by original reaction owners. Existing root order and the VM's deferred finalization queue remain unchanged.

`production-delta.json` contains exact reversible C replacements and the header addition against DisallowJS commit fa30a9fc. `reaction-retirement-successor.json` separately records the finite peer finding and its causal successor.

## Controls

The first fourteen declarations cover native get/set identity and allocation-free operations, publication before finalization, runtime graph reachability, existing actual pending values, cleanup selection, native job capture, failed-task carryover, reaction registration, the live then getter, real Source and native AsyncFunction Awaits, and independent application capability hooks.

Declarations 15–22 cover blocked and empty checkpoints, real enqueue allocation failure, reachable and unreachable Promise/reaction cycles, complete runtime teardown, first-fatal selection across job and outer-root cleanup, returned marked DATA, contained ordinary Promise rejection, and a setup-finalizer fatal preventing actual hook/body entry.

Declaration 23 creates two real reaction records, then uses the original resolve hook to set the actual VM memory limit immediately before enqueue allocation. That enqueue fails. The earlier capability root's sole finalizer publishes one actual fatal and the new continuation root publishes another. The control requires the first identity to survive and both holders to retire once.

Each Probe remains allocated through runtime teardown. Post-fatal assertions read native counters and already held data; they do not start another guest program. The `Batch` helper is an explicit test adapter for the native get/set contract. It does not implement Node exception reporting, completed callbacks, or termination queue policy.

## Integration boundary

The six-line build addition exposes only `build-native-vm-continuation-data`, with the actual `VM continuation` filter, shared QuickJS dependency and install-only artifact. No run step or extra native library is added.

The existing `native_async_scope.zig` capability owner is unchanged. The genuine Node Environment must apply its own async-context-frame option gate, compose the whole checkpoint save/reset/restore, invoke its real reporting/completed callbacks, and handle termination policy. Those caller operations are deliberately outside this finite per-job C unit.

## Finite source review

SDK reviewed the runtime get/set owner, Promise capture/mark and reaction-retirement successor, plus declarations 1–14 and 23. Modules reviewed native job capture/execution/teardown, the Fixture/Probe/Batch and declarations 15–22, and the six-line install-only build seam. Both assigned source reviews are closed on the final C/H/control bytes. The final source pins and exact 23 declaration names are recorded in `source-status.json`. These are source review receipts; this unit has not been built or run.
