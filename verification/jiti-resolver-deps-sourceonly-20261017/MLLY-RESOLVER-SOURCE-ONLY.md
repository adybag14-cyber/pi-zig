# mlly resolver source checkpoint

This is authored, uncompiled native Zig source. No Node, guest evaluation,
formatter, generator, compiler, native test, reference capture or runtime job
was run. There is no expected observation JSON and no public/default module
registration. Source review and original/native execution remain required.

The entry point is `native_mlly_resolve.create(engine, imports)`. It returns
actual ordinary `resolveSync`, `resolvePathSync`, `fileURLToPath` and
`pathToFileURL` functions. Construct it once per Source module lifetime and
retain its functions across jiti instances. Its private owner retains actual
imports, module sets, package cache and regexes. It neither invents builtin
module IDs nor invokes a host Node process. `builtin_modules` must be the
actual Node catalog owned by the separate node:module seam.

The implementation includes the bundled import-meta-resolve4.2.0 algorithm:
relative/absolute/URL parsing, package self-reference, scoped and unscoped
node_modules walks, conditional targets, arrays/null targets, exports main
sugar, wildcard ranking, numeric-key rejection (including canonical numeric
fractions), internal imports, legacy main/index probing, physical file and
directory checks, realpath finalization, raw URL errors and deprecation calls.
It preserves this clone's imports pattern `key.slice(0,-1)` and trailing file
path `slice(-1)` behavior. These are not assumed equal to Node24 policy.

The package JSON reader uses its real private Map, caches absent package files,
calls the live default fs.readFileSync member, calls live JSON.parse, checks own
properties and retains the actual parsed exports/imports values. Named stat,
realpath and Node file URL functions are captured actual bindings. Only the
Source's specified ordinary errors are swallowed. Namespace-local iteration
uses checked fatal cancellation/quota; catch wrappers recognize fresh private
allocation reasons before Source catches, including failures inside catch code.
Entered abrupt iterator cleanup preserves the saved fatal identity and skips
the normal-result validation for throw-completion IteratorClose.

mlly's ufo joinURL dependency is the actual runtime-selected ufo1.6.4, not the
unselected ufo1.6.3 build-lock reference. Its real filter callback, for-of and
module-constant leading-slash regex are ported separately. Pathe's finite b5cd
checkpoint is retained unchanged by this commit. hasESMSyntax is owned by the
operators lane (`native_mlly_syntax.zig`); it must be wired once at module
lifetime, rather than reconstructed per jiti instance. No syntax implementation
or namespace fallback was added here.

## Unqualified boundaries

- The authored error leaf implements the resolver's consumed message templates,
  Error/TypeError base, own descriptors, code and toString. V8's stack-frame
  filtering, stackTraceLimit/startupSnapshot protocol, message Map/Reflect.apply
  interception and complete Node internal-error constructor reflection are
  not implemented. They are an explicit error-system parity gap, not a claim
  of full errors.js equivalence.
- Deep/adversarial recursive package targets, arbitrary replacement globals,
  proxy mutation and arbitrary nonstandard return values from replaced String,
  Array or URL methods require independent review and execution. Source loop
  condition reads/catches are present; this checkpoint does not establish a
  native-stack or complete reflection equivalence proof.
- The real Node filesystem/URL bindings and original builtin inventory are
  required. Their complete Node error-message, symlink and platform parity is
  not established by authoring these leaves.
- Async resolve/resolvePath, defaultResolve, readNearestPackageJSON, package
  loading/evaluation and full mlly exports are outside this consumed resolver
  component. No partial facade is installed as the public mlly module.

## Prepared controls

`jiti-mlly-1.8.2.input.mjs` has 51 planned observations: four function metadata,
30 package/path resolution, eight file URL wrappers, three protocol/builtin
bypasses and six live-getter/iterator/warning/cache observations. The 17 fixture
files are inert inputs; their JS/TS bodies are never imported/evaluated by this
subject. The original subject receives actual pinned mlly plus actual Node
bindings and a fixture root URL. Only the supplied fixture root string is
redacted to compare different physical worktrees. No expected answers are
encoded. The clone's trailer imports rule is observed without correcting it.

Five native entries are prepared: complete original51 replay, retained module
roots across GC, full Zig allocation failures through physical lookup, fresh
fatal identity from a caught fs error's code getter, and fresh fatal identity
from the Source JSON catch's message getter. They use actual imports; no fake
catalog or filesystem collaborator is supplied. All five are unrun. Allocation
classification in the test harness occurs only after the invocation returns,
not inside production Source catches.

Historical pathe manifests, 313+6 original input rows, nine native controls,
89 authority members, and both absent expected files are preserved. The new
manifest separately seals the authored mlly products/fixtures and records
unchanged original authorities. No historical receipt is rewritten.
