# Smallest actual jiti orchestration — proposal only

No new factory, registry, default facade or selected shim is authored here.
This plan is tied to Root567 and reviewed Module8a/API12a. It requires review
before product authoring. Current runtime authority remains recovery_pending.

## Actual source authority and existing seams

jiti2.7 source commit fd3bb289b75ed207edfb686d671ed50144f7e90f is the authority.
The original8a packet retains the exact npm bundle and its full reference
package. Five additional primary source files in `jiti-orchestration-authority`
are immutable-commit reads for this proposal, with separate hashes. No source
execution or observations have been manufactured from them.

Root567's Engine exposes SourceLoader{context,load,normalize,normalize_require,
input}, loadModuleInput, normalizeRequire, requireBuiltin and real value-module
registration. Sources/exports returned by its loader are owned. Its physical
resolver supports require/import mode, packages and exports, but not the exact
per-call arbitrary conditions/extensions/paths requested by jiti's mlly call.
The normalizer alone therefore cannot be renamed jitiResolve/resolvePathSync.

Root567's real createRequire keeps engine.commonjs_cache identity, but lacks
extensions and resolve.paths; its loader's createModule still makes plain
records. Module8a intentionally refuses to bootstrap over populated legacy
records. Changing that loader/require surface is a separate narrow Root-owned
review, not part of this virtual patch. No legacy record is rebranded.

Reviewed926 supplies actual interop Proxy, JSON self-default, parent/native
cache operations and one-Await genuine import. These files are absent from
Root567 and need narrow exact-file intake with a fresh dependency census.
The 926 extension adapter is separate and uses newer Graph2 C symbols: do not
copy it into current C2 as a hidden dependency or roll vendor C backward.

Reviewed API12a4c7cfe61aa3360d4f9af7f9bc090cf0bbd55c supplies lower.Options
{typescript=true,async_mode=false}, lower.lower -> owned bytes, eval.prepare
-> Prepared{body,async_mode}, compile -> owned real seven-argument VM function,
and invoke -> raw owned completion/exact async Promise. invoke reads actual
Module exports,require,filename,dirname(second filename),nested.import and
nested.esmResolve in order, and uses undefined receiver. These are not a
createJiti factory or resolver. The lowering rejects unsupported syntax before
Module/cache publication; its rejection frontier is explicit and does not
claim full Babel transform/error-marker parity.

## Recommended next source unit: transformed evalModule orchestration

Author the actual transformed branch of eval.ts in one scoped Zig leaf, with
the reviewed Module/cache/lowering/eval leaves. This is the smallest real
orchestration body rather than prematurely exporting a complete createJiti.
All namespace/function inputs must be actual completed implementations.
Real nested createJiti is still missing and remains an explicit required
dependency; controls may not fabricate it to declare this unit qualified.

1. Preserve actual evalOptions id/filename/ext/cache reads and callee/receiver
   order; determine source/TypeScript/ESM/CommonJS conditions from real paths
   and nearest-package data. Source transformation happens before new Module.
   The supported native lower's prepare happens at that point. Unsupported
   syntax/options reject before publication with the documented native
   frontier, not an invented successful Babel transform.
2. `new actualModule(filename)`, set filename, read ctx.parentModule and assign
   parent, use actual Array.isArray/includes/push operations in Source order.
   Call the actual nested factory with filename, same opts and same parent
   cache/nativeImport/onError/createRequire identities. Assign that actual
   callable to mod.require. Set mod.path with actual pathe dirname and
   mod.paths with the live actual Module._nodeModulePaths.
3. Publish the exact real Module to the parent cache and, when moduleCache is
   truthy, the same nativeRequire.cache before compile/evaluation. Preserve
   publication through guest-visible setters. Cycles see that Module and its
   partial real exports; no surrogate cache or empty registry is permitted.
4. Compile with API12a after publication, invoke its exact real seven-argument
   wrapper, and preserve the raw returned Promise/value. Compile and synchronous
   evaluation catches use actual cache cleanup then actual ctx.onError. If
   onError returns, continue Source control flow; do not simplify every catch
   into an unconditional throw. Own the original ordinary reason before
   cleanup; a fresh cleanup throw can override it, while trusted host fatal
   reasons bypass ordinary Source catch using current-boundary classification.
5. Implement actual next(): when the marker is truthy, three observable
   mod.exports reads and two marker reads, real
   __JITI_ERROR__ getter/destructuring/error/stack behavior, loaded=true, then
   actual jitiInteropDefault. The parse-marker policy is genuine Source user
   behavior even where native lowering itself rejects unsupported syntax.
   Missing Error.captureStackTrace or formatter inputs cannot be stubbed.
6. evalModule is an ordinary function. Its async tail is Source's actual
   Promise.resolve(evalResult).then(next); do not replace it with an AF wrapper
   or a manual thenable runner. The distinct public jiti.import uses the
   reviewed genuine one-Await AF. The returned .then result and all guest
   getter/receiver/error ordering remain observable. Owner roots are traced,
   aggregate charged and lifetime-bound to actual continuations.
   A rejected async wrapper completion follows Source's rejected .then path;
   it does not retroactively enter the synchronous invoke catch or receive
   extra native-cache cleanup/onError calls.

Prepared real controls should combine the actual Module class, actual nested
factory and actual source files: hoisted-function/undefined-const cycle,
partial-cache identity, namespace/default identity, ordinary compile/eval
failure, onError returning/throwing, delete trap overriding prior reason,
then getter/rejection timing, getter reentry and retained old closures. No
positive construction is claimable until those concrete dependencies exist.

## Real resolver, require and factory closure after that unit

Implement jitiResolve's actual body with real pathe/utils resolveAlias, actual
mlly resolvePathSync/fileURLToPath, actual isDir and nativeRequire.resolve.
Preserve tsconfig candidate iteration, alias, parentURL, condition-set order,
extension and index fallbacks, JS-to-TS rewrite, options.paths and lastError
identity/try semantics. Pin the exact bundled dependency authority first.
Existing SourceLoader callbacks may perform owned reads/canonicalization only
where their accepted contract matches; they do not establish missing mlly
conditions or virtual resolution behavior. Any new SourceLoader option/API
surface or CommonJS resolve.paths/extensions repair needs separate Root review.

Then implement the actual ordinary jitiRequire body: protocol/builtin routing,
actual virtual module lookup, tryNative .then/.catch fallback, JSON self-default,
unknown/native-module routing, exact parent/native-cache reads, real physical
source read and eval orchestration. Reuse one existing CommonJS cache and the
actual namespaces. Native/shared CJS/JSON loading still needs the real Module
constructor loader integration. Unsupported dynamic syntax or module-kind
edges fail closed before effects; no fallback to a Node bridge or fake native
registry is allowed. The queued native-import binding must return the genuine
raw VM Promise after its C3 gate; JS_LoadModule is not a substitute.

Only then assemble createJiti from actual options.ts/cache.ts/transform.ts and
actual dirname/join/normalizeAliases/URLs/escape-regexp/isDir/debug dependencies.
Preserve environment/default/deprecated-option spread/getter ordering,
tsconfig-lazy setup, native/transform regexes, actual createRequire, context
field order, fsCache preparation and Object.assign property order. Expose the
real callable and actual resolve/transform/evalModule/import/esmResolve methods,
same live options/cache/main/extensions and resolve.paths. Missing dependency
behavior must reject or remain explicitly unavailable, never empty/fabricated.

## Gates left explicit

The full native jiti transpiler is limited to API12a's reviewed frontier.
Custom Babel, JSX, source maps, unsupported TypeScript binding/runtime syntax,
complete fsCache/esmEval temporary-file behavior and nearest-package policy
remain real work. No source-only plan qualifies them.

Module parent private-proxy/cross-realm diagnostics, wrapper allocation/root
collection/teardown, C3d2 queued Graph0 binding execution and actual entrypoint
composition remain separate. Graph2 default interop/importer cache/lifetime
and context-pinned resource/reclamation policy remain missing/unqualified.
Do not silently combine TS-to-CJS parent caches with private ESM ModuleDef
caches or claim either proves the other's Source39 reload policy. A concrete
mixed-graph proposal and actual old-closure/dynamic import controls are needed.

Default SDK selection remains off until real inputs and native/source gates
close. This proposal authorizes no new C/Engine/main edits or execution.
