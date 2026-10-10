# Native durable storage and execution checkpoint

Authority is Pi `b7dfc049e917a265a5aefa9f3952a2dec9b81cfd` (1.0.3).
Storage, Session types and Chord delta are unchanged from `b78e6a9`; the retained
b78 storage captures remain valid. New captures invoke the actual latest
Session, Registry, agent resolution and pi-ai validation modules under Node.
Their TypeBox 1.3.27 dependency was fetched only for the external oracle,
verified against the upstream lockfile SHA-512, and is not a runtime dependency.

## Implemented native boundaries

- `json.zig`: owned movable JSON trees, JavaScript number rounding, escaped lone
  UTF-16 surrogate preservation in values and object keys. Strings use WTF-8
  internally. Output text has a separate USV conversion.
- `delta.zig`: decoded Chord `r/s/d/a/t/p/m` operations, own-property traversal,
  reserved-path rejection, sparse-array rejection, splice/permutation, UTF-16
  string truncation. Operations are applied inside owned staging arenas.
- `memory.zig`: numeric global ID ownership, monotonic sequences with explicit
  replay gaps, detached reads, immutable conversation/entry identity, mutable
  task/submission records, document incarnation membership, base/delta versions,
  retirement/recreation and definition-free copies. Preparing allocates and
  validates; publishing swaps owned state without allocation. Reapplying one
  prepared commit is idempotent; applying a superseded preparation fails closed.
- `query.zig`: ascending record/document pages, descending fork-aware entry
  pages with inclusive parent cutoffs, scoped entry reads and document lookup.
- `sqlite.zig`: dedicated `pi_durable_*` strict tables over the existing SQLite
  C ABI, transaction rollback, reopen, numeric allocation and monotonic writer
  fencing. Opening a writable handle claims a new fence; replaced writers are
  rejected. Read-only handles do not claim a fence. Legacy session databases
  containing `sessions` or `entries` are rejected without migration.
- `session.zig`: a serialized commit line, callback rollback and original native
  errors, read-after-table-write checks, retained transaction expiry, fork
  policies, preallocated table/document publications and invocation attribution.
  Cancellation is checked before admission; storage settlement is uninterrupted.
- `harness/*`: immutable registry snapshots, extension replacement/uninstall,
  capability retention, task-name collision reservations, source order and
  extension/tool selection, schema admission/coercion, invocation expiry,
  bounded text and diagnostic output, result persistence through Session, and
  actual read/write/edit/bash registrations over an explicit local environment.

The normal CLI continues to use its existing JSONL/session repository and text
adapters. New library exports are `durable_backend`, `durable_session`, and
`durable_harness`; dedicated gates are `test-durable-backend` and
`test-durable-harness`. The ordinary CLI retains its optional SQLite boundary.

## Ownership and limits

Caller-owned `json.Owned`, prepared commits, registry snapshots, transaction
references and invocation references have explicit cleanup. Retained transaction
and invocation methods reject calls after settlement and from another thread.
Registry resource retain/release functions are infallible lifetime operations;
they must not reenter registry construction. Execution callbacks run on the
invocation owner thread. The supplied environment outlives builtin bindings.
Builtin invocation and environment allocators must match.

JSON nesting is bounded to 512 and parsed nonfinite numbers fail closed. Native
IDs and sequences use the upstream safe-integer ceiling. Numeric JSON values
round as JavaScript numbers. Serialized spelling/order can differ while decoded
JSON values remain equivalent.

The new SQLite backend intentionally uses prefixed dedicated tables rather than
the upstream SQLite schema. It does not open upstream SQLite files or migrate
legacy CLI files. This first backend writes a complete staged snapshot in one
transaction; indexed incremental updates and large-store performance remain
subsequent work. A replacement writer invalidates prior writer handles.

The native schema policy supports the exercised plain object/array/union/type,
required/property/additional-property, enum/const, numeric limits, string limits
and native regexp rules. Known unsupported validation keywords (including
references, formats, conditionals, dependent/unevaluated schemas, contains,
uniqueItems and multipleOf) fail closed before execute. Complete TypeBox support
and an extension-language exception-value adapter are not claimed.

The Session API is a concrete low-level transaction/publication kernel. Typed
document-definition caches/migrations and proxy tracking, task-state admission
and ownership cascades, memo/submission deduplication, scheduler/recovery,
provider generation and compaction orchestration, prompt renderers/wrappers,
before/after tool hooks and asynchronous progress settlement are subsequent
increments. Reserved builtin task names do not imply those schedulers are
implemented. Tool progress retains and marks output; final result settlement is
implemented.

Current watches remain polling. Latest per-target traversal, unique directory
budgets, target permission errors and file/directory replacement signatures are
implemented. Forced native mode remains `not_supported`. Signatures use actual
inode/ctime/mtime/hash values; cross-volume identity needs a device-aware native
stat capability and is not claimed. The growing-read rule and one-time byte BOM
rule follow the latest source, with independent real-file/data captures.
