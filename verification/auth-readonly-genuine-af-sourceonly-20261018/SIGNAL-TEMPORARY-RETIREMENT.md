# Completed signal-check retirement

The immutable cbda7 candidate used the parent method Scope for its completed
optional signal call. That kept the signal, live callee and ignored return
alive during later load/clone/map work. Source has completed that expression.

The corrective successor runs the actual check in a short Scope and records
its void/error outcome under canonical completion before releasing roots. It
preserves both checks and exact getters/receivers; no guard is skipped or
deferred. Earlier captured DATA is not classified as a current fatal event.

An additive genuine-owner control creates its WeakRef/target/take closure in a
prior VM job and clears that job's KeptObjects before testing. The actual
signal method returns the target and clears its lexical owner. A subsequent
live load method performs actual GC before its first deref, requiring the
ignored check result to have retired. The genuine class and constructor are
used; the load mutation is an explicit Source caller input, not a dependency
substitute. No WeakRef construction in the tested job masks the condition.

There are now four owner-required typed control bodies. They remain uncompiled
and unrun; the artifact target retains its fail-if-run sentinel and no run edge.
cbda7, original observer/Source pins, legacy fixtures and all shared paths other
than the exact already-reviewed canonical C435 dependency remain unchanged.
The latest corrective manifest supersedes only current byte/count metadata.
