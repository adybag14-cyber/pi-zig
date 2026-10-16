# Actual Node Module constructor and lookup — prepared source only

This additive leaf implements the small real `Module` constructor/prototype
and `_nodeModulePaths` surface needed by jiti 2.7 `eval.ts`. It does not register
or select a replacement `node:module`, and the SDK default selector remains off.
All source/native/reference controls in this packet are **uncompiled/unrun**.
No historical expected observations were changed. The new expected file is
absent. No Zig, Node, generator, C, Engine or main integration job was launched.

## Product and authority

`native_node_module_constructor.create(engine, Inputs)` returns two owned values:
the real ordinary constructible `Module` callable and a publication record
`{default, Module, createRequire}`. The latter is explicitly not a linked ESM
namespace. `Inputs.paths` is the actual default `node:path` object;
`create_require` is the existing native CommonJS function; `process` is the
actual process object. The two immutable deprecation option booleans must come
from actual host options. Bootstrap must run before any legacy plain-object
CommonJS cache entries exist; a nonempty cache rejects explicitly.

The constructor preserves own field order, live `path.dirname` access and
receiver, an own define for `exports`, first/last private parents before the
parent's `children` getter, generic captured Array push, and trailing fields.
Normal calls and construction are distinct; newTarget supplies the instance
prototype. `parent` updates the first slot only. Two captured WeakMaps represent
Node's V8-private slots without public own strings or symbols. This is a
source-level implementation choice requiring genuine proxy/primitive controls,
not an already accepted V8 parity claim. Captured roots are VM marked, charged
in aggregate native memory, and freed by the callable finalizer. Root ownership
cycles are visible to the linked VM collector. No global ambient receiver/state
or uncharged host registry is introduced.
The parent setter explicitly rejects all primitive receivers after warning,
including Symbols that the underlying WeakMap would otherwise accept as keys.

The actual existing `engine.commonjs_cache` and `createRequire` identity are
reused. `publish(engine, constructor, filename, actualModule)` writes through
the live constructor `_cache`; it never changes a legacy record's prototype.
`lastParent` exposes a host-only read needed for future actual loader assembly.
`warningCodes` is a host-only composition seam for the actual shared internal
util deprecation set; only these two wrappers share it at present.

Path search is a direct Windows/POSIX scan from Node's pinned implementation,
using captured UTF16 charCodeAt/slice/push and genuine VM numeric/string actions.
It preserves the special root array literal and live `path.resolve` call. It
does not split UTF8 paths or manufacture a platform-independent expected array.

Primary Node authority is the official annotated v24.14.0 tag, peeled commit
`f657bb8ed86365ff3fdbe32e27563e778b41486a`. Every retained file was independently
compared with its immutable raw commit URL; `authority/primary-authority.json`
records exact hashes and the read-only Node executable identity. Node's full
LICENSE accompanies the excerpts. The pinned jiti 2.7 npm archive, SHA512,
dist/source/license authority from the unchanged earlier packet is retained.
The separate extracted primary reference package contains original npm bytes,
not a recovered-runtime substitute or production bridge.
The full staged whitespace check reports Node's original LICENSE line362
space-before-tab indentation. Those authority bytes are preserved deliberately;
the scoped product/control/document whitespace check is clean.

## Prepared controls

Six native entrypoints cover constructor/private-parent identity, receiver and
getter order, captured primordials, actual accepted lookup arrays, real cache
publication/createRequire identity, ordinary thrown reason/partial construction,
and separate pending-deprecation behavior. They require a fresh Engine with
actual namespaces and actual host flags. No plain object is used as a Module.
The six entrypoints contain five guest test programs; all are uncompiled/unrun.

`reference-input.mjs` has 43 ordered genuine Node/jiti observations: 23
constructor/metadata/cache effects, 14 physical platform lookup inputs, three
lookup edge cases, and three real jiti loading cases. The supplied actual jiti
entry must be the sealed extracted `lib/jiti.mjs`. Three retained physical
files (`root.ts`, `child.ts`, `plain.cjs`) are written with `wx` inside one
previously absent owned fixture directory. UTF8 bodies, size/SHA256 and final
metadata are emitted; files remain in place. No cleanup or outside writes.
`fsCache:false` and `tryNative:false` deliberately isolate this constructor
reference, with separate `moduleCache` true/false cases. These options are not
silently presented as the default SDK import policy.

`deprecation-reference-input.mjs` supplies three additional ordered observations
in a fresh process. Future separate actual `--pending-deprecation` and
`--pending-deprecation --no-deprecation` profiles must be sealed/admitted before
launch. It replaces/restores the actual guest-visible `emitWarning`, measures
raw reason identity, wrapper receiver, warned-before-throw ordering and shared
code behavior. Earlier constructor cases cannot consume this warning first.

All inputs pause at the explicit stdin admission fence before physical effects
or jiti loading. The future owner must validate the fixture parent, every input
and package byte, executable and actual flags before opening that fence.
`CAPTURE-PLAN.md` describes required admission/evidence; it is not a launch grant.

## Explicit integration and qualification gaps

The existing CommonJS loader still creates plain records and has not been
modified. Actual `_load`, `_resolveFilename`, `_compile`, require methods,
extensions handlers, preload mutation, globalPaths initialization and complete
node:module exports remain separate missing work. No empty handlers/globalPaths
or fake loading functions are exposed. Shared internal util deprecation
composition, exact Node diagnostic messages/cross-realm newTarget fallback,
complete symbol/private-slot proxy parity and allocation/GC/teardown coverage
remain gates. The actual native node:path error diagnostics are not yet Node
V8 message parity. No new expected diagnostic is invented here.

The API owner's separate TS→CJS prepare/compile/invoke leaves require this real
constructor/cache ownership, a real nested jiti and actual pathe dirname.
They are not registered as a full createJiti facade. Queued Graph0 ABI/binding,
Graph2 adapter policy, context-pinned graph reclamation/resource policy and
full default loader composition/native qualification remain explicit gates.
The reviewed `926d0840` interop/cache/retirement and `0d546939` raw import binding
checkpoints, original Source53/44/15/48/39 expected bytes, C/H, Engine, commonjs,
TypeScript, async primitive/Body and SDK files remain unchanged.
