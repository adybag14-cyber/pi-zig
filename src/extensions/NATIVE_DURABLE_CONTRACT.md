# Public durable VM storage and Session slice

Authority is upstream `7fb59f995b0a1db552001a8577b234e4105d7179`,
whose durable implementation is unchanged in the later source captured by the
release owner. Runtime implementation uses Zig and the embedded QuickJS C ABI;
the package exports contain native functions rather than generated JS or a
Node SDK bridge. JS snippets in tests are user extension inputs.

The native `@earendil-works/pi-durable` module exports `MemoryStorage` and
`createSession`. The JSONL and SQLite `storage/*/node` package paths export
`openNodeJsonlStorage` and `openNodeSqliteStorage`, respectively, backed by
native filesystem capabilities and the SQLite C ABI. The word `node` is the
upstream import-path ABI; it does not select a Node process.

Storage supports ID minting, atomic batch commit, close, the five table scans,
conversation/entry/task/submission reads, conversation-scoped request lookup,
document reads and address lookup, and latest head marker lookup. Owned
snapshots detach returned values from stored state. JSONL exposes its source
`fsync` option and SQLite exposes `busyTimeoutMs`. Storage opens capture the
ambient process cwd explicitly. Persistent opens and returned storage objects
own their native resources until close/finalization.

Session commits and close use a promise line built from native C callbacks.
The callback can await extension promises and return arbitrary JS object
identities. Failed callbacks roll back their staged writes. Escaped transaction
objects retain the native transaction allocation, which rejects operations
after settlement. Transactions expose conversation/entry/task reads, root and
ownerless/task-owned conversation creation, forks, and entry append. Read after
table write remains forbidden by the native transaction kernel.

Commit listeners retain the original context identity, use a snapshot for
delivery, and suppress duplicate function registrations. Close seals admission
and calls close listeners synchronously before already admitted callbacks finish;
storage closes after they settle. Cancellation checks the original abort reason
before a commit callback starts. The original source capture confirms that
aborting during a successful callback does not by itself roll back staged writes.

Request lookup deliberately preserves source backend differences. Memory and
JSONL select the latest arriving duplicate and remove its old request key when
it moves. SQLite's nonunique request index selects the lowest matching ID and
retains another matching row when that winner moves. The VM performs the SQLite
lookup against committed rows instead of applying the memory arrival index.

Independent original-source captures outside implementation sources verify async
callback ordering and rollback, cancellation/fork behavior, listener removal and
close ordering, and request lookup plus persistent reopen for all three backends.
The test graph includes these inline extension fixtures and exhaustive GPA
failure injection through module registration and owned constructors. Windows
gates use a PATH without Node; Linux gates use an empty task-owned PATH.

This slice does not yet implement the full public Harness, document token/draft
and observer facade, task orchestration, cancellation of a close waiter,
arbitrary JS Storage/FileSystem adapters, or all exported classes/errors.
Native IDs remain nonnegative safe integers; upstream erased numeric brands
also admit negative numbers. The existing native SQLite schema is a separate
physical format and is not original SQLite-file interoperability. Logical
request/reopen equivalence here does not certify that format. Mac-specific
runtime execution and the separate FSEvents candidate remain hosted gates.

## Additive Harness creation slice

The public `Harness.open` factory now accepts native storage plus a caller's
registry and validates its built-in task names. Qualified creation operations
are `root`, `createConversation`, `conversation`, `getTask`, queued `commit`,
`close`, and commit/close subscriptions. Conversation handles expose their
readonly ID, scoped `commit`, `entries`, and `fork`. Existing roots skip creation
hooks and initialization. This qualification uses idle storage; task recovery,
registry publication and phase dispatch are ongoing and are not implied by the
presence of the factory.

Every creation reserves the source's built-in live, inbox, usage, provider and
agent document identities before invoking `conversationCreated`. Forks reuse
the native kernel's historical agent copy and reserve four fresh initial
documents. Caller initialization follows that hook. Agent selections persist
extension/tool names, even when extension objects contain cycles, and ignore
unknown fields. Deferred plans own their strings, values and arenas. Callback
failure publishes no tables or documents while preserving source ID consumption.
Table publications precede document publications, including copies selected
while a fork record was being built.

The provider identity uses secure native entropy, a UUIDv7 timestamp and the
source's 41-bit sequence shared across Harness instances in the same VM owner.
No process or VM callback runs to generate it. Creation and rollback captures
come from the exact 7fb checkout's official offline build. The same inline caller
registry fixture produces exactly the same original result as `createRegistry()`.
The rollback capture exercises original GC; the native fixture forces QuickJS
GC with retained transaction objects. Constructor GPA failure gates include
Harness/conversation ownership cycles.

This additive slice does not certify task recovery/dispatch or the remaining
Registry, agent-resolution/configure, task, submission, draft/token, context,
view and observer APIs. Task-owned agent inheritance and caller agent changes
on a fork need further document-facade integration. The full public Harness
goal remains active; these creation proofs are a bounded incremental result.
