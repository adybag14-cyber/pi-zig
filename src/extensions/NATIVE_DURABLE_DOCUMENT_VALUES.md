# Source document values, owner checks and predicate finalization

Authority remains the durable/Chord source at 7fb59f995b0a1db552001a8577b234e4105d7179.
Root audited the newer 1cedd32724abfcb0915f76cc61b6827e2c16dbad/release1.1.0 delta:
durable, Chord and ENV runtime source is unchanged; package/version prose changed.
This additive slice follows frozen original SQLite05a0123.

Cold snapshot, historical snapshot and documentState reads follow the original
storage backends' ignored caller Context policy. Watch acquisition retains its
explicit cancellation guard. The original fixture returns all three values with
an aborted raw Context; the prior native guards failed that same fixture.

Object-property assignment of undefined deletes the property. Array element
undefined and sparse index assignment reject. Increasing array length fills null
values, as the actual Source capture demonstrates. Object data properties are
defined directly so __proto__ remains an own JSON property and never changes
the draft target prototype. Reserved property additions, changes and removals
fold into a containing-object/root replacement rather than unsafe delta paths.

New document acquisition validates the conversation/task before invoking its
initializer and minting an ID. A failed initializer preserves its original
exception identity and consumes no ID. The captured owner error messages match
Source for missing conversations and tasks.

Native transactions expose an optional owner facade finalization callback. The
default is null for native worker transactions; the document facade verifies its
transaction owner thread before touching VM roots. Predicates execute after
Runtime task-state and native task-owner assembly validation. Prepared drafts
are already revoked. Storage checkpoint representation and publication operations
remain independent, and predicate mutations of readonly-by-type values/operations
are serialized after the predicate returns.

Authentic fixtures cover canceled cold reads, undefined/array mutation policy,
reserved-key data/prototype behavior and operation folding, owner/initializer ID
ordering, and a self-wait Runtime transition that must reject before invoking a
checkpoint predicate. Existing allocator and lifecycle gates remain included.

Remaining work is explicit. This does not certify complete Chord tracking:
mutation-aware object replacement versus nested edits, array identity/permutation,
string overlap/truncation, dense-region folding, full operation budget and all
reflection/mutator restrictions remain. Complete fork-source write and task-doc
staged terminal/pending-acquisition contracts remain. Native task assembly also
performs storage prevalidation; exact predicate timing for every storage-level
rejection still needs an independent contract. Full registry/builtins/context/
agent/conversation/runtime, generic Chord exports, custom storage/executors/cloud
and all error/report/concurrency/crash edges remain outside this slice. Root
owns composed release and hosted macOS runtime qualification.
