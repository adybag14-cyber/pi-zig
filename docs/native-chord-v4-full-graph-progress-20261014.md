# Chord protocol4 full graph work in progress

Authority: immutable upstream `b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb`.
This isolated branch starts at component source checkpoint
`102b031a71abcf2e3d481a10b6896cb8d59b2ab8`. Its separate Windows Debug
Cells57 proof is published as `3e71fdf1` on `work/chord-v4-b45e0eb-20261014`.
The component proof does not qualify the changes on this branch.

The actual Object/Self/Ctx/Host files are being ported here. The historical
1692 and e622 trees and their proofs remain separate and unchanged. No JS/TS
implementation body or missing-method fallback is introduced.

## Authored native behavior

- Intrinsic owned asynchronous capabilities and void continuation stages,
  preserving the existing narrow fresh native allocation escape.
- Source activation ordering: optional predecessor cleanup, factory, resource
  and reference opens, exposed/derived hydration, parallel deferred cell roots,
  finalization/publication. Rollback drains invocations before resource unwind.
- Public `.then` and `.catch` remain public where the original Source uses
  them. Internal awaits use the actual VM intrinsic await bridge.
- Resource dependency opens and collective reference readiness use the actual
  public `Promise.all`/`allSettled`, declaration-order first rejection, actual
  iterator spread, and bounded reference-ready timeout.
- Self state declarations box immediate values, record genuine initializers,
  and reuse retained cells without rerunning their initializer.
- Ctx.get awaits the acquired view, with its signal and closing signal; closing
  aborts pending view acquisition with the actual expired ChordError.
- MemberReadable throws not_ready before live state, not_in_variant outside
  its variant, exposes the shared hydration symbol, tracks unseen snapshots,
  and keeps a boxed last-seen value so undefined is a real observed value.
- Host requires `self`, records `principalKey(self)`, exposes key-based isSelf,
  has separate asynchronous get and immediate hold, and records readyTimeout
  and linger settings. Local host-lifetime identity and invalidation use isSelf.
- Caller placement is resolved from normalized contract input. Local providers
  check their own placement. Remote identity uses type/input/principal key and
  fingerprint, without a caller-selected host name or options.at.
- The new RemoteBinding class owns shared views, one hold, state demand,
  hydration waiters, per-member decoders, atomic pending shape/snapshot units,
  retained values through reconnect, terminal and linger cleanup, and calls
  waiting for a live hold. Its channel return uses actual async-return promise
  adoption. Its installer is not yet called by the factory.
- RemoteRef now has its own owner, status, ready settlement, proxy, method
  callers, and release boundary over a shared binding. ViewReadable owns
  listeners and unseen snapshots while reading the binding's member values.
  Consumer Host bindingIdle/forgetBinding implement timeout and capped LRU
  ownership. Routing creates/reuses bindings by key and adds independent views.

## Qualification boundary and remaining integration

All changed Zig files have pinned Zig0.16 fmt/AST checks only. There has been
no semantic compile, Source differential capture, GC run, or allocator sweep
for this full graph branch. No native lane is requested for this incomplete
assembly. The existing private factory still imports protocol2 and historical
cells/contracts: it must not be used to claim protocol4 runtime parity.

The next coherent integration includes provider/relay protocol4 state units and flow
control, connection authorization/route principals, consumer linger ownership,
and reload prepare hydration/init ordering. The remote routing function now
constructs shared bindings and independent views; the existing protocol2
channel cannot yet carry these protocol4 holds and must be replaced before
factory assembly.
Remaining observable getter/callback/error order must be audited against the
actual Source, including rollback-finally behavior under overridden public
methods, reentrant publication, and pending reference aborts.
In particular, audit live pending-map iteration across view callbacks and the
precise safe-callback boundary around observable member value getters. Source
fixtures must establish these behaviors before runtime qualification.

The next Source fixtures must invoke the actual b45 factories and full object
graph, with the existing official resolver and full1965/31064/1774 closure
checks. No original Source body or previously captured caller/golden may be
replaced to accommodate native behavior. Full host failure sweeps, GC/teardown,
and exact raw exception identities remain required after coherent compilation.

Full v4 graph qualification: false. Full Pi qualification: false. Public
activation: false. Latest generated catalog qualification: false.
