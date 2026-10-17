# Actual CommonJS prototype bodies: prepared source

The three functions implement the pinned Node24 loader source bodies at
Module.prototype.require, load and _compile. They are ordinary anonymous
constructible declarations with lengths 1, 1 and 3. Borrowed receivers remain
live values. They are not bound to a hidden substitute Module.

The lexical owner is an aggregate-charged native record with traced roots and
stat-cache value. It is retained inside the existing authenticated Module
constructor callback owner. It is not registered as an importable module.
Callback roots keep the state alive across guest execution and GC. The native
require-depth cell implements try/finally with a nonallocating decrement even
when the wrapped load throws. First-parent and last-parent accessors continue
using the constructor's existing private WeakMaps. Public source keys kFormat,
kIsExecuting, kIsMainSymbol, kURL and kIsCachedByESMLoader are actual distinct VM
Symbols shared through the exact lexical owner, not lookups by description.
The export snapshot is a private WeakMap relation.

`load` reads id for the debug argument, asserts the live loaded flag, implements
both nullish assignments, captures _nodeModulePaths before evaluating dirname,
re-reads kFormat, finds the longest registered extension with the captured
string primordials, calls the live extension handler with its registry receiver,
then marks loaded and captures exports. Custom extension registries are live.

`_compile` preserves TypeScript format normalization, wrapper result getter
order, actual ESM branch, makeRequireFunction order, exports-as-this, top-level
stat cache and main/inspector branch. A wrapper throw deliberately skips the
Source's trailing executing=false and statCache=null operations: those source
lines are not in a finally block. Map storage is private and is not exposed as
a mutable substitute for a public SafeMap declaration.

Required collaborators are genuine actual implementations: debug/assert/Node
error validation, wrapModuleLoad and the real _load path, stripTypeScriptModuleTypes,
wrapSafe and its real CJS grammar compiler/source-map behavior,
loadESMFromCJS including synchronous ESM, makeRequireFunction,
setHasStartedUserCJSExecution, inspector callAndPauseOnStart, actual node:path.
Callable checks reject missing functions but do not establish their authenticity.
No fake namespace or always-failing default fills these dependencies. This unit
does not select or publish a default bootstrap, and no C/H/Engine changes occur.
Stat callers must use the same private lexical owner and captured Map methods;
the complete _load/stat/hook assembly remains pending.

The separate original observer calls genuine Node Module methods and performs
temporary test-local overrides of real public Module/path properties. It covers
raw Promise identity and throw identity, validation, callee capture, longest
extension and receiver, failed loaded-state publication, actual wrapper bindings,
throw-state retention and real JSON. It has no expected output and has not run.
There is no native compilation, runtime, full CommonJS or jiti qualification.
