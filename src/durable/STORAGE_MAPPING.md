# Durable storage, Session and Harness mapping

Authority: Pi `b78e6a9085343ec0f308c3d377da72528b4cf7ee`,
`packages/durable/src/types.ts`, `storage/memory.ts`, `storage/sqlite/*`,
`session/*`, and `harness/*`. This inventory distinguishes reusable native
mechanisms from interfaces that still require an implementation.

| Durable contract | Existing native mechanism | Required new behavior |
|---|---|---|
| Session-global numeric IDs, root conversation 1 | SQLite repository uses session/entry string IDs; JSONL Session IDs are strings | A distinct durable ID namespace; do not reinterpret existing IDs |
| Atomic `Storage.commit(StorageWrite[])` returning one Seq | SQLite transactions, writer fencing, session sequences | Validate and publish a complete multi-table batch; one sequence for every accepted atomic batch |
| Immutable conversation/entry records and ancestry visibility | Parent-linked JSONL entries, branch cache, lanes, forks | Conversation ownership and inclusive fork cutoffs; ascending conversation and descending visible-entry scans |
| Task scheduling records and transitions | Native Agent loop and tool execution lifecycle | Pending/running/waiting/completing/terminal durable states, abort marks, ownership, memos and terminal receipts |
| Submission placement and conversation-scoped deduplication | Native RPC requests and session append logic | Queued/placed/done/unanswered records and stable request-key lookup |
| Document create/change/copy/retire | Existing session facts/records/custom entries | Logical addresses plus distinct incarnation IDs, creation/retirement sequences, base/delta revisions and as-of reads |
| Detached values and storage rejection | Owned Zig JSON values and SQLite transaction rollback | Reads must not mutate stored state; failed validation/allocation must not partially publish |
| Session serialized commit line and publications | Native mutexes and append-only session writes | One transaction callback and immutable table/document publication for its successful Seq |
| Document watches and invocation lifetime | Filesystem polling watcher and native provider/extension invocation ownership | Document commit observation, invocation-bound cancellation, stale-operation rejection |
| Harness registry, scheduler and generation | Native model registry, provider streams, Agent loop | Conversation/task definitions, phase snapshots, recovery reservations, provider session UUID per conversation |
| Structured tools and progress | Native coding tools and new durable output gate | Diagnostics/details/output retention and skips, independent of legacy CLI rendering |

The existing SQLite `sessions`/`entries` schema is not the durable package's
schema. In particular, durable's `record_ids`, numeric `conversations`, `tasks`,
`submissions`, `documents`, and `document_revisions` have distinct ownership and
lifetime invariants. A new durable backend must use a dedicated schema or an
explicitly versioned migration; adding aliases to the old repository would
silently change stored-session meaning.

Implementation order for concrete, independently testable increments:

1. Complete local `ExecutionEnv` and structured tool contracts, with real-file
   and real-process captures.
2. Implement owned durable records and a small atomic memory backend. Check
   global ID ownership, rollback, detached reads, ordering and fork visibility
   against captured storage conformance cases.
3. Add dedicated SQLite schema/migrations using the existing native FFI and
   transaction primitives, plus reopen/rollback tests. Preserve the existing
   session database format.
4. Add Session transaction serialization and publication for implemented
   record/document types, then invocation/registry/scheduler Harness behavior.

This file is a source-backed boundary map. It does not claim that the new
storage, Session or Harness interfaces are already implemented.
