# Actual replicatedState source-only port

Authority is immutable b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb
packages/chord/src/state.ts. This separate worktree starts at4ac96be0 and
does not mutate the independently frozen Source21 allocation sweep tree.

Six Zig modules implement the actual factory, subscriber, publisher, mutable
Tracker-backed state, source attachment, and shared error/value operations.
The subscriber serializes asynchronous callbacks, keeps the original100-item
pending bound and overflow behavior, retains cold hydration, and drops pending
work on unsubscribe. It uses public Promise.resolve/then where Source does.
Listeners receive the actual subscriber receiver, matching private-field calls.

The publisher snapshots hydration sequence and actual background context,
queues reentrant publications, snapshots subscribers, and prevents delivering
an already hydrated revision twice. Mutable state uses the real existing
native overlay Tracker, rejects reentrant or asynchronous mutation, aborts
failed changes, adopts prepared revisions, and publishes only real operations.

Attached state uses the actual source attach/activate/dispose interface, checks
live Number.isSafeInteger cursor semantics, publishes exact incoming values
without applying or diffing operations, retains its last value after disposal,
and preserves aggregate cleanup errors. Error conversion/reporting follows
Source, with the existing narrow trusted fresh native allocation escape.

The factory requires the real context module's background value explicitly.
It does not create a placeholder context or replace any missing API. The
installer is not imported or called by the full graph yet. No native compile,
VM run, Source capture, GC/failure sweep, or public activation is claimed.

The genuine Source16 caller exercises root ownership, exact hydration context
and callback receiver, structural sharing and cloned assignments, empty
changes, replacement publication, reentrant/async mutation errors, serialized
callbacks, overflow, unsubscribe, buffered source attachment, ignored ops,
cursor-gap disposal, unsafe-snapshot cleanup, and ordinary factory construction.
It must be captured through the actual immutable b45 factory/context exports
before native differential qualification. Caller errors rethrow every error
outside the explicitly expected Source error class/message pair unchanged.

All authored modules currently have pinned Zig0.16 fmt/AST evidence only.
Full replicatedState qualification: false. Full Chord/Pi qualification: false.
Public activation: false.

First native compile at d7c05a5086ade1dc4c1b22278e2ab2bb68911d41 failed because the mutable-state reentrancy branch called nonexistent `h.runtimeError`. The complete failed receipt, compiler output, RSS samples, owners, and frozen manifests are retained in `verification/chord-v4-b45-source-20261014/replicated-state-d7c05a50-first-compile-negative/`. All 5525 candidate, 1965 Original, and 19546 compiler inputs and controls had zero post drift; owned PID 73332 was absent. No runtime ran.

The source-only repair uses the existing `h.ordinaryError` helper, matching upstream ordinary `Error` construction and preserving both exact error messages. Pinned Zig 0.16.0 formatting and AST checks pass. This does not establish semantic compilation, native Source16 behavior, GC, or host allocation qualification. A distinct reviewed compile retry and subsequent runtime reservation are still required.

The exact d5f9a01f5fc983a6fe692fe1c2774c4fa5fdd0e7 retry compiled and ran successfully on Windows Debug: all four selected tests passed, including the actual Source16 comparison and native GC. The complete successful host allocation baseline was 1114. All 5535 candidate, 1965 Original, and 19546 compiler files, inventories, and controls had zero final drift; owned compile PID53960 and runtime PID69880 were absent. Final pair postcheck completed 2026-10-14T22:16:27.1466072Z. Full receipts are retained in `verification/chord-v4-b45-source-20261014/replicated-state-d5f9a01f-debug-diagnostic/`. No induced host failure index ran in this diagnostic; complete host GPA remains unqualified.

The next uncompiled test candidate appends a complete host allocation failure sweep to the same target, increasing the compiled inventory from four to five. It reruns the identical complete Probe (unchanged Source16 caller, comparison, GC, and teardown) at every index in [0,1114) on Windows, requires the measured baseline to remain 1114, requires actual induced failure and exact OutOfMemory, rejects swallowed and unexpected errors, checks allocated and freed bytes at every index, and emits an explicit complete coverage receipt. The original 120 second test, 300 second outer, and 10 second host deadlines remain required. C heap failure exhaustiveness is not claimed.
