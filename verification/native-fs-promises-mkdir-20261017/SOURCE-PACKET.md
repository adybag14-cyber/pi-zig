# Genuine asynchronous fs/promises.mkdir

Contained branch native-fs-promises-mkdir-20261017 starts at Main authority
14775669ca4ad1155957114fec9bdd40b659ca3c. Child-process checkpoints remain in
their separate clean worktree. This unit adds only a new Zig module, prepared
controls, retained primary sources and this source packet. No existing module,
Main, shared C/H, Engine, formatter, compiler, AST, Node or native job is changed
or executed. All new controls are UNRUN; source/native observation fields are
unset. This packet is not execution evidence or a fabricated independent review.

## Actual callable and Promise behavior

native_node_fs_promises_mkdir.create(engine) returns the genuine C3
JS_PiNewNativeAsyncFunction through native_async_function.createResumable,
ordinary async declaration named mkdir with length2. It has the actual async
brand and real VM outer Promise/Await; no prototype branding, wrapper script or
mkdirSync dispatch is used. createWithInputs accepts a genuine captured
Error.captureStackTrace binding. The create convenience reads that binding during
trusted bootstrap before extensions can replace primordials.

On entry, options number/string is the mode shortcut. Otherwise Source's
recursive getter runs before mode. The actual path is validated next using the
existing Buffer/URL/string native validator, then recursive boolean and mode
uint32/octal validation. Ordinary abrupt completions reject the genuine async
outer Promise without synchronous throw or diagnostic toString. Native allocation
failure/pending-first classification preserves the actual owned reason and uses
native_async_body's fresh-allocation helper. Unknown option keys, including
signal, are not read: Node mkdir has no per-call AbortSignal option.

Only validated owned path bytes, mode and recursive state enter the native
request. The Windows path uses the existing genuine windowsNamespacedPath owner
helper, preserving trailing spaces/dots and native drive-directory acquisition.
Other targets preserve the original relative path bytes. Buffer mutation after
the function returns cannot change a queued native request.

The Env worker resolves/rejects an actual inner Promise on its VM owner. The
native body performs intrinsic PromiseThen with a real handleErrorFromBinding
reaction, then returns Action.awaited so C3 performs real Await. The rejection
reaction invokes captured Error.captureStackTrace(error, handler), then returns
an intrinsic rejected Promise as Source does, preserving rejection adoption job
ordering. Fulfilled/rejected resumptions return/throw their actual input values.

## Actual filesystem and lifetime

The existing Env Hub submits the request through std.Io.Group.concurrent.
Worker run() owns only native bytes/options/offsets/result and invokes actual
std.Io mkdir/stat operations. It performs no VM entry, guest coercion, user
callback or host allocator call. Task.finish uses the existing actual owner wake;
Promise settlement and error construction run only in owner completion, after
the Hub's queued-microtask check. Admission is bounded to64 live mkdir requests.

Nonrecursive mode makes one real directory operation and returns undefined.
Recursive mode first attempts the full raw native path, walks parent prefixes
only on actual ENOENT, then retries pending descendants. The worker records the
first prefix whose actual create succeeds. Existing directories are verified by
stat with symlink following; a final ordinary file is EEXIST and a blocking
intermediate file is ENOTDIR. Existing-only recursive calls return undefined;
created recursive calls return the actual first created path string. Permissions
use native mode narrowing/umask on POSIX; Windows ignores mode as libuv does.
There is no exists-before-create race and no inference that a directory was
created merely because it exists after a syscall failed.

Config, path, ancestor offsets, resolver roots and capacity admission transfer
only after Hub.submit succeeds. Before that, each has an owner cleanup defer.
Promise capability resolver ownership is established before checking a successful
return for pending completion. Worker terminal result is release-published via
Task.finish and read by the owner; completion destruction frees native storage
and JS resolver roots once. The existing Hub teardown marks tasks abandoned,
sets the request stop flag, cancels/joins its actual I/O group, and destroys
tasks only after workers return. Recursive operations check stop between actual
syscalls. Cancellation can leave directories already created; no rollback or
independent filesystem absence is claimed. No process or unrelated job is killed.

Native filesystem failures retain code, errno, syscall=mkdir and the actual
failing path. Windows error paths remove the native namespace prefix. Allocation
failures while constructing results/errors propagate through the scoped trusted
owner boundary rather than being converted to a successful mkdir. Error strings,
native errno translations, Windows NT/CreateDirectory equivalence and unusual
filesystem/race behavior remain execution-qualification scope; this packet
claims no original/native equality before those controls run.

## Wiring and prepared controls

install(engine, actualPromises) replaces only the mkdir member on the actual
shared namespace. Root must call it before fs/promises ESM exports are frozen;
patching an already frozen named export is not a valid integration. The existing
node_fs installer is intentionally not edited in this unit. The SQLite adapter
may receive the exact resulting binding via its existing Inputs.mkdir. Source
openNodeSqliteDatabase awaits mkdir(dirname(path), {recursive:true}) before
constructing DatabaseSync, and skips both operations for :memory:.

The Zig validation control checks the actual C3 async brand, async rejection
instead of synchronous throw, Source getter order, raw reason identity, error
codes and balanced diagnostic/capacity state. It launches no worker because all
its inputs fail validation. mkdir-controls.mjs is a shared original/native
physical control requiring an empty retained fixture root and the actual mkdir
binding. It checks physical recursive/nonrecursive effects, first-created return,
existing-directory return, error fields, URL/Buffer path handling, path snapshot,
microtask ordering and ignored signal getter. It deletes nothing. Future Root
owners must retain separate original/native fixture paths, seal actual namespace
installation and use existing resource/ownership gates. No expected JSON is
generated or original capture claimed here.

Primary files are immutable HTTP source retrievals from Node v24.14.0 and libuv
v1.51.0, not Node execution. They include fs promises, mkdir continuations,
validation, Windows namespaced path conversion, errno constants and Windows
mkdir implementation. The manifest also pins the actual Main147 AF primitive,
Hub, path validators and native filesystem dependencies. Independent source
review, compiler/runtime controls and integration remain required.
