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
