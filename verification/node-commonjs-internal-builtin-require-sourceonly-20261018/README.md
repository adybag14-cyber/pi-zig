# Genuine native internal builtin require producer

Source only. No compiler, parser, Node, metadata query or native execution.
Base6be88e853ba3b2d43450cd176e585933e42cd637 remains frozen. This new owner
does not edit Engine, C/H, shared Scope, existing loader leaves or Main. Its
install-only target is `build-native-node-internal-builtin-require`.

The pinned Node24 f657bb8ed86365ff3fdbe32e27563e778b41486a realm.js primary is
retained inert at authority/realm.js (15448 bytes,
SHA2566B19B7E820C099E28748019277B1CFDCDF2F1167C4F937F2645072764D2AC421).
Its requireBuiltin looks up the private BuiltinModule map and calls
compileForInternalLoader. Internal/errors receives this private callable;
ErrnoException lazily calls it with bare `util`. No public createRequire,
physical file URL, public Module._load/cache/hooks or global require belongs
to that consumed operation. authority/internal-errors.js and LICENSE.txt
retain the exact original FS primary/licensing bytes. The public72 catalog
does not establish a complete private builtin registry and is not consulted.

## Actual API and ordering

`native_node_internal_builtin_require.acquire(engine, .{ .bindings = &.{
    .{ .id = "util", .module_name = "node:util" },
} })` returns an owned ordinary `requireBuiltin` function. These are explicit
trusted converted-native provider admissions, not caller-supplied exports,
handler functions or claims that a Node module has completed. IDs and registry
names are copied into a private real Map; the existing aggregate-charged native
callable roots/marks that Map and its captured primordial operations. The
capability itself is retained once in the Engine's existing private value
carrier. Subset reacquisition validates provider names and returns the same
function. It does not extend or silently replace the original admissions.
The finite host interface admits at most512 bindings and bounds names; no
guest list is accepted. Bootstrap must acquire it before guest exposure.

Acquisition can precede installation of util. This closes the actual dependency
cycle: the shared Errno class retains its real internal require first; the
real util provider can then be constructed with the same class/error graph.
On invocation, an admitted id resolves its genuine existing
`engine.native_module_values[module_name].default`. No replacement util object
or fabricated completed Module is constructed. A successful lookup retains
that exact native-completed export object for the loaded fast path. Failed
lookup commits no loaded value and can be retried after real backend setup.
Neither ESM namespace initialization nor a JS builtin compiler is invoked.

After actual provider installation, `validateInstalled(engine, sameInputs)`
checks the genuine default exports without creating or marking a missing
backend. The host must perform this check before selecting Auth/frontends
whose later Errno calls need util. Every scope enters the existing stable Bfb
boundary before effects; rollback stays in the same frame. Captured-only
diagnostics remain DATA under the independently reviewed6be policy.

FS confirmed the actual util producer is
`native_node_util_tty_dependencies.installRequired(engine, public_util,
private_inspect, sameTTYerrorView)`, followed by native util/node:util
publication in the real TTY assembler. A new TTY composition must inject this
exact internal require into the shared error bundle before that producer runs.
Frozen6db/934f TTY candidates, which used public createRequire for this lexical
capability, remain historical and are not silently relabeled. There is no
duplicate error bundle, Errno class or Module/CJS cache in this producer.

## Finite support boundary

This is the already converted-native backend route of the internal loader.
It does not claim Node's complete builtinIds registry, self realm exports,
C++ internalBinding graph, JS builtin compileFunction, in-progress JS builtin
cycles, native addon support or first-JS-compilation moduleLoadList history.
An admitted backend called before its real installation fails explicitly;
no partial or undefined exports are returned as success. Unadmitted requests
are explicit native capability failures, not fabricated Node missing-module
observations. The API is private and must not be exposed as a public loader.

Actual util is not installed in this historical6be base. This unit cannot
declare a complete util or Auth graph. Real native util installation, new TTY
internal-require injection, shared registry identity and selected host inputs
remain separate composition prerequisites. Public same-Module CJS composition
continues separately; it is not a substitute for this internal capability.

## Prepared controls

Four static declarations use actual native path/fs installers and real VM
callbacks. They verify canonical export identity, same owner reacquisition,
no public constructor/global require/cache dependency, no ESM/jobs, GC-safe
retention, actual absent-backend first-call failure followed by genuine backend
installation/retry, refusal of unadmitted IDs, and actual incoming pending
identity under a one-byte VM quota before owner allocation. They install no
fake util. Original Errno lazy-one-time util/getSystemErrorName integration
needs the real utility/error assembly described above and remains unrun.

The target installs canonical test.exe/test.pdb without executing it. Actual
metadata count is unknown, including any imported anonymous storage test.
No expected output, source capture, runtime proof or default activation exists.
The inherited C453 compiler negatives are preserved; this producer calls none
of the private CJS compiler APIs and cannot repair or qualify that compiler.
