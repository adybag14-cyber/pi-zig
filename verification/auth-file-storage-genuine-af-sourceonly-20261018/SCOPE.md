# File backend and proper-lockfile genuine async functions

This is source-only preparation from Main
`283e5a3d7dc0f933ca7e535039ed69d40afbbc1c`. No compiler, parser, AST,
formatter, Node, VM, metadata probe, native test or generator has run. There is
no captured output or expected fixture in this packet. The seven named native
tests are authored controls, not seven observed results. The artifact build
step installs a test executable; it has no run edge.

## Actual authority and callable status

The inert originals under `authority/` come from official Pi commit
`c268154ca1171c2f9eefe75d3d7372a68aada2d5`, plus the original-manifest-verified
proper-lockfile 4.1.2 bytes in the accepted contained runtime. That runtime's
current-byte acceptance does not rehabilitate its failed reproduction lifecycle.
The Pi package pins exactly 4.1.2. Both upstream licenses are retained verbatim.

Pi really declares `acquireLockAsync` and `withLockAsync` as async methods.
Proper-lockfile index.js really declares `async function lock(file, options)`.
Its adapter.js `toPromise` returns an **ordinary** rest arrow with a live
`new Promise` executor. Its raw callback release is length one; only after the
public lock's actual inner Await resumes does `toPromise(release)` create the
ordinary length-zero returned wrapper. This repair preserves `lock.lock === lock`.
It does not brand the ordinary release as an AsyncFunction.

## Implementation and native retirement

The two Pi methods now record real VM Await/return/throw actions. Acquisition
retains actual lock, retry/sleep, abort and cancelled-release stages. The
with-lock path keeps the Source callback Await and the actual finally release
Await. It preserves Source's unconditional ordinary unlock-error suppression,
raw callback/acquire reason identity, signal order and result-before-next
destructuring. Rejected Await input is DATA even when it carries a historical
uncatchable bit or a private allocation tag. Only actual current pending events,
trusted failing-operation generations and Bfb's independently retained event
can bypass the guest finally.

Exactly the closed SDK-owned completion helper SHA256
`41AAFFBFED0B2B598D51E8B46432E1B53A373BA101DC7B0F4C396201E65432B6`
is used without editing it. Error/action ownership is recorded before native
Scope and caught-reason retirement. A distinct try-block Scope retires under
its ordinary completion before Source finally starts. Therefore ordinary A
survives native cleanup B even while a real release Promise is still awaited;
an actual new fatal C at a free can supersede it. Recorded rejection values in
private state remain DATA. Per-field state writes check actual pending state
before the next write. The action record's extra reference to the completed
Await value retires before new continuation guest work.

The proper-lockfile adapter now uses the live Promise constructor, live
`args.push`, and actual iterable spread before invoking its captured callback
method. Abrupt spread does not invent IteratorClose. Iterator method, done,
step and record temporaries retire at their completed expression boundaries;
yielded argument roots survive the actual call. Native loop interruption uses
the existing reviewed jiti budget policy. Success-with-pending native getter or
callee results are normalized before a later guest operation.

## Causal controls and original capture

The common observer constructs the genuine FileAuthStorageBackend with an
owned explicit physical path. It exercises actual directory creation, file
read/write, lock acquisition/release, held callback/finally Promises, preflight
throws and ignored ordinary unlock failures. Instance overrides in selected
cases are explicit Source caller mutations of that genuine instance. They do
not supply replacement filesystem, lockfile, timers, classes or namespaces.
The same observer is imported by the prepared original caller. That caller
requires a genuine upstream module URL and an already-owned empty directory;
no original execution or output has occurred.

Native controls independently require the VM async bit and nonconstructor
status for all three migrated functions. One intercepts the actual global
Promise construction to hold the inner raw-release resolution and distinguish
raw length-one release from the later ordinary length-zero wrapper. DATA
controls create actual marked private Error values successfully, then use real
Promise.reject; a separate actual native fatal must stop subsequent work.
Three sole-result carrier profiles contrast ordinary cleanup B, fatal C and an
initially unmarked private pending OOM created at the exact free boundary.
They retain a counted heap probe, check no diagnostic coercion, balanced
suppression/invocation ownership and exact fatal identity; no escaped stack
probe or stand-in completed graph is used.

## Explicit prerequisites and retained limits

Execution requires Root's accepted **DATA-safe AF1116/current producer C** and
**Bfb/current NativeInvocation** composition. The historical Main283e base's
C/H pins alone do not qualify marked rejection DATA. No C overlay, flag clear,
Engine, shared Body or Scope change is included here.

The real directory-lock algorithm already present (native synchronous host
I/O implementing selected atomic mkdir, precision, heartbeat, stale and release
behavior) is retained. This packet does not establish full proper-lockfile
custom-fs/retries/realpath interoperability, exact Node I/O callback scheduling,
whole-library descriptors, inherited constructor/synchronous-method cleanup or
all heartbeat/timer finalizer policy. Nor does it establish the new c268
ReadOnlyAuthStorage export, the full AuthStorage module, SDK bootstrap, genuine
FS/TTY/child-process composition, actual OS/GPA behavior or a default app pass.
Those boundaries remain separate. Original assertions and old Auth6/reload
proofs are preserved; their earlier closure is not transferred to these methods.
