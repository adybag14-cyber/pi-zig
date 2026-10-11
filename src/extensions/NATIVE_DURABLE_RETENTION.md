# Native Durable retention and owner settlement

The document and scheduler-context retention contract comes from upstream
`cdaf6c227d4718a72b59ccd02152c9614df44cfc`. Existing EA ownership-index and
failed-open behavior remains in place. The later e6 input-entry and latest
compaction changes are separate work.

Document retention is an actual cache policy. `documentRetentionMs` defaults to
600000, preserves positive Infinity, clamps negative numbers to zero, and uses
the Source default for invalid or NaN values without coercing arbitrary values.
Harness settings are resolved dynamically at the actual use or sweep boundary.
`Session.documentCacheSizes` and `Harness.documentCacheSizes` expose the actual
cache, idle bookkeeping, observer pins, sweep and timer state. They do not count
historical Storage rows.

`durable/document_retention.zig` owns the ordered idle index. Its twelve methods
cover lifetime, address use, incarnation pinning and expiry selection. The VM
boundary owns the captured clock, retained settings values and actual timer.
The Session class marks those JS captures and releases them in its finalizer.
Tracker installation touches a newly cached incarnation. Actual committed
document publications touch their adopted records before observers run.
Explicit unload drops cached trackers while retaining observer incarnation
bookkeeping; retirement releases only the actual old record's pins.

The native Session adds two admission methods: `tryCommitWithAfter` and `tryRead`.
Existing `tryCommit` delegates to the former. `AfterOperation` is an optional
callback, and `owner_settlement` is registered before admitting workers and
detached after workers join. The order is:

1. Commit and publish with the original Transaction and mutation line.
2. Release the Transaction, retaining the same mutation line.
3. Run the facade callback and original-worker owner-settlement callback without
   an OS mutex. User clock/settings getters run only on the VM owner.
4. Perform native maintenance, then release the line and notify waiters.

A rejected operation retains its first error even if its settlement callback
also fails. `tryRead` admits an actual public reader or expiry job without
fabricating another Source commit-settlement event.

`durable/owner_settlement.zig` has six Channel methods. A worker sends its real
owner generation, thread, line epoch and success state while retaining its
original line. The owner validates that lease, adopts the actual document
publication, settles cache retention and acknowledges before the worker runs
maintenance or unlocks. It never reacquires a newer line on behalf of an older
publication. The original ownership-index readiness handshake remains intact.

The VM scheduler defers only its initial reconciliation. Pure native callers
keep the synchronous default. Three optional Scheduler hooks provide deferred
initial reconciliation, the actual scope-read completion boundary and completed
reconciliation. `tryReconcile` admits a real line without blocking an owner
whose worker may await that owner. A busy request remains in the existing
Storage Hub as `scheduler_reconcile` with five retained JS captures.

The initial owner microtask captures Session identity and a full-u64 BigInt
generation. It joins the existing Session Promise queue. Its scope-read hook
awaits a real intrinsic Promise reaction after native scope reads, keeping the
original Transaction and line on the C stack without holding an OS mutex.
Snapshot cache hits return a fresh intrinsic Promise; misses retain the actual
await continuation after queued loading. Writable guest `Promise.resolve` is
not used for those intrinsic async returns.

Scheduler contexts settle only after actual reconciliation, task publication or
their expiry timer. `settleIdle` and `scheduleExpiry` each resolve settings even
when there are no cached contexts, matching the Source call sites. A worker
reconciliation releases its line before using a separate owner context Broker;
that request carries page-owned JSON and no JS values. It is distinct from the
document settlement channel, which retains the original worker line.

Context and document timers use actual setTimeout/clearTimeout/unref operations.
Context callbacks verify Session identity, owner generation and expiry generation
before touching a live Manager. Retirement closes both Brokers, cancels timers,
clears contexts and waits for existing workers before deinitializing channels.
Owner cache/context guards prevent nested Hub pumping from modifying an active
settlement's arrays. No timer is retained when the host cannot unreference it.

Qualification is exact to the following source, rather than to every future
composition. Product source `b58dc0cb6a91cb54c3a0921f71c746187c61ae4b` passed:

- [Hosted Windows Debug settings gate](https://github.com/adybag14-cyber/pi-zig/actions/runs/38150912205):
  seven tests, including the unchanged original fifteen settings accesses and
  complete getter stage/field sequence. All 2407 tracked source inputs and
  19546 Zig tool inputs matched before and after.
- [Hosted Windows Debug observer/public-open GPA gate](https://github.com/adybag14-cyber/pi-zig/actions/runs/38152026675):
  six observer/unload/real timer tests and six public-open lifecycle tests,
  including the unchanged complete allocation-failure sweep. Complete source
  and tool pre/post hashes matched, and both owned Zig processes were gone.

The frozen original settings baseline remains a 5/7 runtime failure. The first
event candidate's syntax failure is also preserved. No fixture, deadline,
allocation index or expected getter count was weakened to obtain these passes.
Separate pure regressions cover two index cases, one Session operation-order
case and two owner-settlement cases, including a newer worker waiting on its
own next publication. Their historical proofs do not transfer automatically
to a new composed head.

The additive Root packet preserves Root's committed-live late-step decision,
Storage load-progress publications, synchronized index snapshot, serialized
read flush and inflight regression. It does not modify Engine, engine ABI C/h,
native_js_values, SDK, vendored QuickJS/ICU, Main, images or command behavior.
The composed Root source must run its own settings, pin, GPA and ownership gates.
Full worker bindings, constructor cleanup, close/reload races and other OS/modes
still need the corresponding actual runtime evidence. Complete untyped
string/BigInt context-retention arithmetic and exceptional clock/timer-host
behavior are not established by the current typed numeric fixtures.
