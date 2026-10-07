# Original durable SQLite format

Source authority is the SQLite migrations/storage/Node adapter at
7fb59f995b0a1db552001a8577b234e4105d7179. `sqlite_source_schema.sql` contains
the exact version-one Source DDL and indexes. Public `openNodeSqliteStorage`
now uses this backend through the direct SQLite C ABI. The private fenced
numeric backend remains available to its existing native callers.

The original format uses durable_schema, durable_metadata, record_ids,
conversations, entries, tasks, submissions, documents and document_revisions.
Revision content stores the base value or decoded operations, with separate
version/kind columns. Indexed strings use JSON encoding so lone UTF16 surrogates
remain lossless. Original SQLite request lookup retains its lowest-matching-ID
policy. WAL, NORMAL synchronous mode, auto-checkpoint and busy timeout follow
the original Node adapter options.

ID allocation is local to an open storage object. A minted ID alone does not
persist; committing stores the maximum allocated/written next ID as TEXT.
Closing before commit permits that ID to be reused on reopen, as actual Source
captures demonstrate. Storage methods ignore caller Context like Source.
Snapshot/read reconstruction happens in one SQLite read transaction; commit
refresh, validation, prepared data and persistence occur in one write
transaction. Publication transfers only after every database effect succeeds.

Opening an earlier private numeric database imports its complete records and
revisions transactionally into the original schema, retains all prior tables,
and increments the old writer fence only on successful admission. A prior
private writer then rejects its next mutation. Allocation failures roll back
both schema/data effects and fence changes, leaving the old database usable.

Evidence includes an official-Source-created binary data fixture, native reads
of original history/UTF16 indexes, exact original/native seed-capture equality,
native append read by original Source, original append read by native, and
original reads of a migrated private file. The process fixture is Zig; original
Node executes only the independent reference oracle outside the repository.
GPA sweeps cover schema/read/persistence ownership, commit rollback and healthy
retry, and private migration rollback/fence preservation.

This incremental port is not the entire durable package certification. Remaining
work includes exhaustive source error-object/schema-corruption behavior, reader
and writer contention/abrupt process recovery qualification, performance under
large datasets, custom database executors and Cloudflare adapters, and every
source edge policy. Persistence currently rewrites the logical tables inside
the transaction. Full VM/registry/context/normalization gaps remain listed in
the preceding contracts. Root owns static SQLite distribution linking, hosted
macOS runtime evidence, and the exact composed release graphs.
