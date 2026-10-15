# Ordinary AuthStorage production class

This source checkpoint implements the `AuthStorage` outer class and the ordinary
`InMemoryAuthStorageBackend` class from immutable Source
`4954d760504c11df9b2cbdc040346107b6a8153d`,
`packages/coding-agent/src/core/auth-storage.ts`. It does not reuse the legacy
`native_auth_storage.install` plain state-object constructor as a default class.

`native_auth_storage_production.create(engine, imports)` returns owned exports
`AuthStorage`, `InMemoryAuthStorageBackend`, and the exact supplied
`FileAuthStorageBackend` constructor. Create and retain that namespace once for
each module realm, and reuse its `AuthStorage` constructor for standalone SDK
exports and the ModelRuntime static factory's `DefaultAuthStorage` import.

The mandatory imports are actual `FileAuthStorageBackend`, `getAgentDir`,
`getFileRevision`, and `resolveConfigValue` bindings. The first must be a real
constructor; the other three must be callable. Missing imports fail explicitly.
The `constructor(engine, imports)` convenience returns the owned AuthStorage
constructor from a newly created namespace.

`createDefault(engine, resolveConfigValue)` composes the actual new
`native_auth_file_storage_backend` constructor, the actual `pi`/`.pi`
`native_sdk_agent_directory` binding, and `native_file_revision`. Its config-value
resolver is still mandatory. No literal-only resolver, command-skipping resolver,
identity function, or fabricated backend is supplied to qualify a default path.
The native file backend dependency corresponds to source checkpoints `06055ee2`
and `1128df3e`; the actual five-field revision dependency corresponds to `5789f135`
and its native-allocation identity corrections `90ae8e2e` and `c438e526`.

The AuthStorage constructor defines exactly the Source own fields `storage`,
`authPath`, and `readState`, in order. Its ordinary prototype contains
`parseStorageData`, `updateReadState`, `reload`, `reloadFromStorageAsync`,
`readLatestData`, `read`, `modify`, `delete`, and `list`. TypeScript-private members
remain ordinary observable methods. Static `create`, `fromStorage`, and
`inMemory` retain their lexical constructor and live static method calls.

The implementation retains the Source first-path shared read state, revision
cache, shared reload promise/controller, independent aborting readers, final
reader cancellation, cached fallback without a signal, raw credential identity,
API-key spread and resolution, mutation serialization, no-write undefined
mutation, deletion, method/property getter order, subclass construction, and
non-enumerable method descriptors. State and callbacks are rooted VM values;
workers do not access guest JS. Original private native allocation failures are
preserved through best-effort reload and cached fallback boundaries.

The prepared genuine Source47 input exercises ordinary class fields and
descriptors, both constructors, live prototype/private methods, actual in-memory
queuing and recovery, credential identity and extra fields, environment updates,
fallback/error/abort behavior, actual default file backend creation, normalized
aliases, live external changes, five-field revisions, first-path cache sharing,
independent concurrent readers, final-reader cancellation, and malformed files.
Default file tests use real owned temporary files and the original Source file
backend. Observing filesystem wrappers delegate to the actual Node operations;
they do not supply success values. Raw filesystem effects, original Error
messages/stacks, and original revisions are retained separately from comparison
rows. Only the owned temporary root is normalized in display observations.

`src/native_auth_storage_production_test.zig` provides Source47 replay and pending
GC entrypoints that require actual assembler imports and real fixture bindings.
Its missing-dependency test is a negative control. It is not a synthetic positive
proof of standalone AuthStorage or default ModelRuntime construction.

Genuine Source47 capture passed under the Root LIGHT5 reservation against exact
clean candidate `6489aeab46cf17a9e29177c08b3408bc0e43750b`. The original Source
class, file backend, filesystem, and config resolver were used. Node PID 76420
exited naturally with code 0; its kernel handle and independent PID absence were
verified. The owned temporary root was removed and independently absent. All 47
ordered rows were accepted, including the two intended malformed-JSON rejection
observations. The original 70 filesystem effects, three Error stacks, and one
five-field revision remain in the packet without comparison normalization.

The full posthash completed at `2026-10-15T23:22:49.2370513Z`, with zero hash and
path inventory drift across the 7,718 candidate files, 19,546 compiler files,
1,970 Source files, 31,064 runtime files, and 1,774 Node files. Extra controls and
all 84 required dependency absences were unchanged. The expected file was absent
through that terminal posthash and was then created with SHA-256
`96828F1B1E1F8B275A871352086082E1F38A0B34285D2815E61E0707506E688B`.

The consumed ordinary package data is the original Source coding-agent package,
`@earendil-works/pi-coding-agent` version **1.3.0**, selected by the explicit
`PI_PACKAGE_DIR` pointing to the Source package directory. Its exact bytes were
frozen before execution and checked afterward; SHA-256 is
`83C3BB7619F590C213CC96A24216EB29A819A3EF6DC548607CC037ED276E8DC5`.
It is also covered by the full Source manifest. This records the selected Source
metadata role, rather than assigning the installed runtime metadata a different
version.

The portable proof is
[`verification/auth-storage-production-4954-captured-20261016`](../verification/auth-storage-production-4954-captured-20261016).
Its archive contains 46 payloads and a manifest, including the unchanged controls,
full inventories, module observation log, raw output, Source files, frozen package
data, and expected fixture. `Verify-AuthStorageSource47Packet.ps1` reopens every
payload, checks exact lengths and hashes, and validates terminal state, provenance,
cleanup, and row equality without importing Source or starting a test process.
The 2,986,845-byte archive SHA-256 is
`B3C9A4460DBCB1266D0AA2592AA6F67CAA1CA65F8636E4095B5BBB4BAF6F9AAA`;
its manifest SHA-256 is
`A8730F7C1874B549567C6FA8D4CB48C189C819D0FED8E68E35FA7250FF8F2B93`.

Formatting and AST checks also passed for the native source candidate. Native
compilation, native replay, complete native default factory construction, full Pi,
and activation remain unqualified. Actual native config resolver integration is
still required for a positive native default-path proof. Existing Browser7 and
Source35 OAuth proofs are unchanged.
