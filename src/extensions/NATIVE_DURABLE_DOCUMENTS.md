# Native public document drafts and snapshots

This additive slice builds on the frozen public task adapter. The implementation
is Zig with the linked C VM; no host JavaScript runtime executes these APIs.
Authority is durable and Chord source at 7fb59f995b0a1db552001a8577b234e4105d7179.

Implemented APIs are `defineDoc`, `defineDocFamily`, transaction `doc` and
`retireDoc`, Session/Harness `snapshot`, `snapshotAsOf`, and `unloadDocuments`.
Singleton initialization receives no arguments; a family receives its seed.
Definition identity, staged document IDs, migration bases, historical fork
lookup, retirement/recreation, and the committed cache are preserved.

Drafts hold their transaction through C VM roots. Nested handles, descriptors,
membership and enumeration revoke when preparation begins, before checkpoint
predicates. Escaped handles retain a closed transaction and reject later access.
Callback failure never adopts the draft cache. Prepared cache address and record
ownership and capacity are allocated before storage admission; successful
adoption transfers them without allocating.

Committed snapshots intentionally retain the original Source behavior: readonly
is a TypeScript contract, not a runtime freeze. A caller can mutate a cached
snapshot, and another warm read sees that same object. Unloading drops the cache
on the Session mutation line and cold reads materialize persisted storage again.
Cached records validate supplied scope/history/fork semantics before warm access.

Ordinary common edits emit decoded Chord set/delete, append and splice operations;
new documents and migrations emit bases. `checkpointWhen(value, ops, info)` sees
the persisted count of deltas since the base and can replace a delta with a base.
The authoritative fixture covers nested set, string append, array insertion,
no-op suppression, predicate counters and base reset.

Qualification includes original official built-source captures, linked native VM
fixtures without Node on PATH, and exhaustive native allocation failures for
creation, later mutation, delta assembly and cache adoption.

This is an incremental contract, not full document parity. Remaining work:

- Chord's full mutation-aware normalization, object replacement versus nested
  edits, reorder/permutation operations, string overlap truncation, dense-region
  folding and the 4096-operation budget. Current operations materialize the right
  JSON for the covered cases but do not claim all original operation shapes.
- Predicates currently run during facade preparation, before the native kernel's
  final owner/fork validation. Exact invalid-transaction predicate ordering needs
  a validation/finalization integration step.
- The native kernel derives publication operations from stored content. A
  checkpoint base therefore publishes a root replacement instead of retaining
  the original prepared delta operations; observer integration must preserve
  prepared operations independently of the chosen storage representation.
- `watchDoc`, replicated `documentState`, observer cancellation and runtime
  document forwarding, full task-scoped retirement/owner validation.
- The full set of Proxy reflection/mutator restrictions and source error objects,
  sparse array/prototype edge cases and pending document acquisition contracts.
- Original SQLite physical-format interoperability, arbitrary user Storage
  objects, complete registry/builtin/context/agent APIs.

Prior frozen donors are unchanged. This patch alone does not certify the full
distribution graph or macOS runtime; those remain Root composition gates.
