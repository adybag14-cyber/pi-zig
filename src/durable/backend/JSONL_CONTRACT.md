# Portable durable JSONL storage

`jsonl.Jsonl` owns recovered in-memory state and path strings, and borrows the
supplied filesystem capability. Its provider, allocator and I/O instance must
outlive the store. Returned records, documents and pages own detached arenas.
`close` is idempotent and rejects subsequent reads and writes; `deinit` releases
the store once. `backend.Backend.jsonl` is accepted by the existing durable
Session transaction/publication boundary. This format is distinct from the
coding-agent's legacy SessionManager JSONL format.

The implementation follows durable source 7fb59f995b0a1db552001a8577b234e4105d7179:
format-v1 commit markers in `main.jsonl`, per-document and per-task sidecars,
commit-wide sidecar ordinals, and document-copy normalization to document-create
with detached materialized content. Commit preparation allocates and validates
state before writing. Sidecars append and optionally flush before the main
marker; state is adopted only after that marker append succeeds. Any append or
flush failure poisons the store. Subsequent reads and writes require reopening.
Reclamation is best effort after publication, uses a temporary `.reclaim` file
and rename, and flushes the main marker before reclamation when fsync is enabled.

Recovery truncates incomplete final lines before parsing complete UTF-8/JSON
lines. Main sequences and sidecar sequence/ordinal pairs must strictly increase.
Every referenced sidecar record is confirmed once; missing historical records
are allowed only for reclaimed current-only documents or final terminal tasks.
Confirmed records after an unconfirmed tail are corruption. Unconfirmed tails
are truncated, retained content is replayed at its original sequence, and
remaining reclamation files are cleaned up. An index keyed by file/sequence/
ordinal avoids repeatedly searching all sidecar lines.

Source scans preserve ascending/descending cursor order, validate continuation
order, support older orderless cursors, and traverse fork segments in source
order even when supplied IDs run backward across segments. Document scans keep
their source ascending default and ignore query/cursor order. Submission request
replacement follows write arrival order: moving the winning request away does
not resurrect an earlier duplicate. Recovery rebuilds that index by replay.

Verification includes actual latest original JsonlStorage captures, physical
11-commit marker/sidecar comparisons, source scans across all five tables,
original/native bidirectional file interoperability, local and remote daemon
persistence, actual Session publication, short and post-marker write failures,
torn tails, malformed complete UTF-8/JSON, missing sidecars, sequence reuse,
unconfirmed tails, best-effort reclamation failures, and every induced allocator
failure while opening/recovering/preparing commits. Reference programs run
outside repository implementation sources; runtime code remains Zig/C.

This slice does not certify hardware power-loss durability, exhaustive source
error-message/cause-object identity, or unchecked negative externally supplied
IDs accepted by the source's erased numeric brands; existing native IDs are u64.
Latest request-index and source-scan APIs are exposed by this JSONL backend.
Equivalent new APIs and request-index persistence for the existing SQLite
backend remain separate work. Platform-native watch gaps are documented in the
ENV contract and are not implied to be resolved by storage verification.
