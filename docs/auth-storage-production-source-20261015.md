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
and its native-allocation identity correction `90ae8e2e`.

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

Formatting and AST checks are the available validation for this initial source
candidate. Source47 capture requires a separate Root LIGHT reservation. Native
compilation, native replay, complete default factory construction, full Pi, and
activation remain unqualified. Existing Browser7 and Source35 OAuth proofs are
unchanged.
