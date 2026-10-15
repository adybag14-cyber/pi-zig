# Actual FileAuthStorageBackend production class

This isolated checkpoint starts at Root `4e128e2c8f33f5ef7aa299475adfe4b1e8e84f2b`
and ports the ordinary class in immutable latest Source
`4954d760504c11df9b2cbdc040346107b6a8153d`,
`packages/coding-agent/src/core/auth-storage.ts`.

`native_auth_file_storage_backend.create(engine, Dependencies{get_agent_dir})`
returns an owned ordinary class constructor. `createDefault(engine)` uses the
actual narrow `native_sdk_agent_directory.create(engine, Configuration{})`
binding with genuine selected package constants APP_NAME `pi` and CONFIG_DIR_NAME
`.pi`. Alternate genuine package metadata can supply those two constants.
The directory helper does not accept the legacy `PI_AGENT_DIR` fallback.

Instances have the Source own `authPath` field. Constructor length is zero and
newTarget/subclass allocation uses the real ordinary class helper. Prototype
declaration order is constructor, ensureParentDir, ensureFileExists,
acquireLockSyncWithRetry, withLock, acquireLockAsync, withLockAsync. All methods
are nonenumerable, writable, configurable and nonconstructible. TypeScript
private methods retain live receiver dispatch; no opaque backend state or
plain-record per-instance method replacements are used.

The bodies implement real file bootstrap, current-content reads and optional
next-content writes; ten synchronous 20ms acquisition attempts; asynchronous
30-second lock waiting with Source exponential jitter and a separate five-retry
Windows EPERM cap; live options/signal getters; compromise callbacks; active
callback lock retention through cancellation; ordered result/next destructuring;
and awaited release with the Source unlock-error suppression.

`native_auth_directory_lock.create(engine)` supplies the shared mutable native
proper-lockfile namespace consumed by this class. It uses atomic directory
creation in the real `<resolved-path>.lock` namespace, empty-directory stale
retirement, mtime precision probing, unreferenced owner-thread heartbeat timers,
compromise callbacks, explicit release and private lease GC roots. It reuses
only the existing Windows-safe native timestamp primitive. Teardown checks inode
and mtime before deleting an owned directory; no recursive lock removal occurs.
The module implements the realpath:false lock/lockSync surface required here;
it does not claim the entire third-party proper-lockfile package API.

The shared Root Node filesystem rejects a write mode, while Source always
passes mode 0600. `native_auth_storage_fs` provides actual mode-aware filesystem
write/mkdir bindings for this class, retaining existing read/exists operations.
Modes apply at creation only, preserving existing file modes/ACLs. Windows uses
native default writable attributes where POSIX creation mode bits do not apply.

The focused genuine Source32 controls use actual Source classes, actual Node
filesystem and proper-lockfile against one owned temporary root. Coverage
includes class/private-method metadata, default config path, normalization,
sync/async bootstrap/write/no-write, getter order, exception identity, dynamic
method dispatch, deletion after acquire, pre/active/wait cancellation, real
contention, compromise gating, unlock errors, EPERM caps, and retry classification.
Raw request paths and full original Error diagnostics are retained separately;
only the owned temporary root is bound in comparison rows. Controlled lock
namespace overrides are explicit protocol/error probes; ordinary success and
contention cases use genuine default lock/file collaborators.

The capture owner requires original Source1970/runtime31064/Node1774 and all 84
retained absences plus exact caller/input/new-native/control pre/post hashes. It
publishes no expected fixture until terminal success and zero-drift posthash.
The capture and native Source32/GC harness are authored, not executed. Native
semantic compilation, Source32 qualification, POSIX filesystem/mode coverage,
heartbeat/stale/compromise differential coverage, complete proper-lockfile
qualification, full SDK, full Pi, and activation remain false.

No Root/shared SDK/Engine/build file was modified. An assembler may add a narrow
test target for `src/native_file_auth_storage_backend_test.zig`, filtered on
`native FileAuthStorageBackend`, using the existing actual QuickJS/SQLite/catalog
link setup. The expected JSON is deliberately absent pending Root LIGHT grant.
