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

The exact caf8ffae7765e4dd27721b786932d0d79e47f6eb Windows Debug successor passed all five compiled tests, including actual Source16 and GC plus the complete identical whole-Probe host failure sweep [0,1114). Diagnostic and sweep baselines both equal 1114; completed=1114, leaks=0, unexpected_errors=0. Native tests took 33 seconds under the original 120 second test, 300 second outer, and 10 second host deadlines. Full 5553 candidate, 1965 Original, and 19546 compiler file hashes, inventories, and controls had zero drift; compile PID50248 and runtime PID63244 were absent. Final postcheck completed 2026-10-14T22:21:36.5368791Z. Complete receipts are retained in `verification/chord-v4-b45-source-20261014/replicated-state-caf8ffae-debug-full-host/`.

This qualifies only actual Source16 with Windows Debug native GC and complete host allocator failure coverage. It does not claim exhaustive C allocation coverage, all upstream replicated-state parameterized cases, other native profiles, or full Chord/public activation. Additional actual Source fixtures must cover independent subscribers, overflow during running updates, repeated callback subscriptions, late callback rejection after unsubscribe, reporter failures, and revoked escaped drafts.

Prepared, uncaptured Source28 expands the original Source16 caller by appending twelve public factory cases for independent slow/fast subscribers, overflow while an update is running, repeated callback subscriptions, reentrant delivery (each mutable and attached), exact synchronous listener failure, exact late rejection after unsubscribe, raw callback rollback with revoked draft, and the default queued reporter. The original Source16 input and golden remain unchanged; no expanded golden or native parity is claimed. All expected failure observers rethrow unexpected errors unchanged and use actual raw identities where applicable. A separate coordinated genuine double capture is required before native use.

Actual Source28 double capture at87de2e6030dcbb5c0342a0174aa57e442ffce818 passed twice with byte-identical outputSHA256 F2322FD72C583B8FD213955578EC0CD1BEF0B5B675A319CC00BB24748D2D7629. All original16 observations are unchanged. Complete5574 candidate/1965 Source/31064 dependencies/1774 Node/control prepost hashes had zero drift; exact owned PIDs12320 and73708 were absent. Final postcheck completed2026-10-14T22:54:26.2139059Z. Complete receipts are retained in `verification/chord-v4-b45-source-20261014/replicated-state-expanded-87de2e60-source/` and the expanded golden is an exact copy of the actual capture.

The new native diagnostic preserves the captured caller and all28 observations, genuine context identity and timers, exact exception handling, native GC/teardown, and measures a fresh complete successful host baseline. Expected compiled inventory4: inventory, actual Source28/GC, measured baseline, anonymous durable storage. The existing Source16 complete1114 test and its historical proof are unchanged. Expanded native behavior and complete induced-failure coverage remain pending coordinated qualification; full Chord/public remains false.

The exact0a763ad1f93e1e35e90c48f0afbe79f2037577fb Windows Debug expanded State28 diagnostic compiled and passed all4 tests: all actual28 observations match, native GC passes, and measured complete host baseline=2061. All5597 candidate/1965 Original/19546 compiler hashes, inventories, and controls had zero drift; compilePID58668 and runtimePID60708 were absent. Final postcheck completed2026-10-14T23:01:50.3574841Z. Native tests took463ms. No induced allocation index ran. Receipts retained in `verification/chord-v4-b45-source-20261014/expanded-state-0a763ad1-debug-diagnostic/`.

The uncompiled complete Source28 allocation successor retains the original diagnostic4 selection and appends four separate whole-Probe GPA tests. Every index executes the unchanged actual28 caller, comparison, native GC, and teardown. Each partition remeasures successful baseline2061 and requires strict induced OutOfMemory and byte balance; unexpected/swallowed errors fail with first failing index and allocator stack. Windows ranges are[0,515),[515,1030),[1030,1545),[1545,2061). All four receipts and baseline markers are mandatory, exactly2061 completed indices with zero gaps/duplicates/leaks/unexpected errors. Original120s test/300s outer/10s host deadlines remain unchanged. The measured463ms diagnostic pair motivates bounded partitions without omitting any case or allocation site.

The strict partition collector passes one positive and14 deliberately malformed receipt controls (missing/duplicate/gapped/overlapped/incomplete/baseline-disagreeing/leaking/unexpected/invalid numeric receipts). This is collector verification only; no native GPA ran. Unique compiled inventory8 across diagnostic4 and four GPA3 selections gives16 selected executions. A compile-only aggregate target builds all five native artifacts before any runtime reservation. Production and both Source16/Source28 callers/goldens remain unchanged.
