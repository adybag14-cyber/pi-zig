Source-only application import closure, based on assembly
`bd994a6b790a844c887f8ceb159d5c0dbeb76bab`. Existing FileRevision and FS metadata
qualification worktrees remain separate and unchanged.

`native_sdk_filesystem_namespaces.createPlatform(engine)` returns one cached
ordinary graph with `paths`, `filesystem`, `filesystemPromises` and
`pathUtilities`. It takes the existing real native Node namespaces, requires
their concrete functions, retains the same `fs.promises` identity, and exposes
actual Source utils/paths.ts bodies as ordinary functions. The application must
already supply its actual native IO on the engine.

The application then creates genuine config.ts, shell and resolve-config-value
namespaces. `createAuth(engine, platform, AuthDependencies{get_agent_dir,
resolve_config_value})` consumes those exact bindings and returns the actual
ordinary AuthStorage and FileAuthStorageBackend namespace. The same resolver
namespace must feed the provider composer; creating a second resolver would
split Source module cache and identity. Repeated creation reuses the module
only when the supplied dependency identities match.

The ordinary FileAuthStorageBackend body and directory-lock body are exact
`1128df3e` bytes. The ordinary AuthStorage body is exact `6489aeab` bytes. The
private auth FS boundary has a scoped correction: ordinary strings and Buffer
paths now use the actual native Node path validator rather than the URL-only
converter. Creation-only 0600/0700 permissions and existing ACL/mode behavior
are retained. No legacy native_auth_storage or native_auth_file_backend proxy
is imported by the new namespace factory.

Shared node:fs installs the prepared genuine stat/Stats/realpath implementation
from `8beca65d`. It also gains a concrete ordinary copyFileSync function and
COPYFILE_EXCL constant. Default and exclusive copies operate on real files:
Windows CopyFileW with exact namespaced paths, and owned file descriptors on
POSIX. The source/destination path labels remain distinct. Clone flags are an
explicit unsupported scope; this does not claim the complete Node copy API.

`import-provenance.json` records original commit/blob identities and candidate
SHA-256 values. The genuine FileAuth Source32, AuthStorage Source47,
FileRevision Source30 and Node metadata Source22 controls are preserved from
their original checkpoints. Node metadata Source22 remains pinned Node24.14
with Pi5ab reference scope, without a latest4954 capture claim. The new
`sdk-filesystem-namespaces-4954.input.txt` is a 12-case caller-only control for
future genuine Source capture; no expected rows have been manufactured.

Root's Google65 hold was observed: no Zig formatter, AST check, compiler,
native runtime or Source capture was launched for this successor. Static
literal import paths were checked for presence and git whitespace checks
passed. Compilation, Source12 capture, native comparisons, full SDK assembly,
public activation and release are unqualified.
