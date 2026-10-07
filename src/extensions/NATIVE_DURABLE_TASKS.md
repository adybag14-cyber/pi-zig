# Native public task adapter

The adapter connects `defineTask`, transaction `createTask`, Harness resume,
task/idle waits and abort to the native phase scheduler. Runtime commits share
the public Session promise line. Runtime getTask, entry, outcomes and memo reads
also run on that line; memo candidates persist once and return the durable winner.
Native workers never invoke or read a QuickJS value. Each phase transfers owned
JSON through the broker and is identified by owner, task and invocation generation.
The owner validates that ledger entry before invoking the phase function.

Session is now held by an explicit native reference-counted lease. The scheduler
holds this lease independently of the public Session object's finalizer. Escaped
runtime objects retain native invocation entries, while their methods reject once
the phase ends. Their signal and JS roots are created, aborted and released on the
VM owner. Driver workers are canceled and joined before dropping roots or tearing
down transport notification. Scheduler publications cross to the owner as owned
JSON; owner commits flush publication order before returning to extension code.

Running records recover to pending without losing existing lifecycle times.
Native timestamps are optional in the kernel, preserving earlier non-VM callers.
The VM adapter stamps first running and terminal transitions, preserving supplied
startedAt/endedAt fields. The Harness clock is captured on the owner. Custom clock
values used by native reservation are prepared before a driver batch; arbitrary
clock callback side-effect/call-count equivalence is not certified here.

Registry snapshots refresh on the owner. Definitions and runtime roots from an
old phase remain retained while in use. Atomic native availability markers and an
owner-detected registry boundary requeue a task before a stale handler executes.
Migration functions run on the owner before reservation; native workers consume
only the prepared owned input/checkpoint result. The captured migration fixture
proves one successful version transition; exhaustive error/report and registry
retry edge cases remain additional work.

Independent captures from the exact 7fb official source build verify two phases
and attributed entries, abort signal plus fresh abort handler, memo winners and
detached values, running recovery with preserved startedAt, owned children/waits/
ordered outcomes, phase-boundary replacement and successful migration. The same
extension snippets execute in the C VM without Node. Forced GC tests retain a
runtime after close and reject late reads. GPA failure injection exercises owned
definitions, scheduler subscriptions and Session lease rollback.

This slice does not claim all public task/Harness parity. Full createRegistry and
built-in generation/tool/compaction definitions, runtime agent/settings/env/hooks/
conversation/context/sleep and document methods, observer APIs, arbitrary JS
storage adapters, Source error-object fidelity and original SQLite physical
schema interoperability remain ongoing. The full completion goal is active.
