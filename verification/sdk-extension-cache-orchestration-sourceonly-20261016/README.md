# Actual extension cache orchestration, source only

This checkpoint implements loader.ts `loadExtensionModule`, `loadExtension`,
`loadExtensionsInternal`, `loadExtensions` and `loadExtensionsCached` over
explicit real imports. The authority is current upstream 4dd2b149d155d7369de16ea4dc77c84e9f5ffb24;
loader.ts and virtual-modules.ts remain byte-identical to the retained 4954/0fb
authorities. `prepared.json` records exact physical source and product hashes.

Each actual Source Await maps to one native AF awaited action: getCreateJiti,
conditional getVirtualModules, jiti.import, loadExtensionModule,
initializeExtension, and one loadExtension per iterator value. Public loader
exports return/adopt the internal original Promise without adding an Await.
The Source TypeScript optional parameters still count toward function length:
module importer2, per-extension loader5, internal/public list loader4.
No function prototype retagging or manual thenable driver is introduced.

Cache ownership remains the existing module-level opaque Map/cwd/generation
record. A current token is checked before factory lookup and again after import.
Invalid defaults are not cached. A cached factory still creates and initializes
a new actual Extension each time. A stale import can return its factory but
cannot repopulate the cache. Clearing does not destroy importer graphs, old
closures, shared native module caches, or the virtual-module import Promise.
The owner is registered as pi-native:extension-cache-owner; this packet does not
claim the opaque handle itself is unreachable to guests. Only native owner
lookup from known engine/function roots casts that handle.

The list loader creates actual arrays, resolves the cache token/cwd, creates the
real event bus and the original pre-bind extension runtime, then obtains the
synchronous iterator. It preserves iterator-next capture, extension/error getter
order, live array push calls, result property order and provided runtime identity.
IteratorStep failures do not close the iterator; abrupt loop-body failures close
it, suppressing ordinary close errors in favor of the original throw. Fatal
native failures bypass guest formatting and ordinary suppression.

The initializer has a host-only createGraph API returning two owned values:
the unchanged public namespace and its exact original initializeExtension
binding. The old create API retains its public shape. Checked local definitions
capture real pending reasons. Ordinary factory/commit/outer failures transfer
captured ownership before discard or downstream formatter hooks; ordinary
discard failures still override the original reason. Existing uncatchable and
fresh privately tagged allocation reasons retain their identity and fatal path.
The cache token's two local definitions now also capture pending failures.

`native_sdk_extension_virtual_modules.evaluate` reads nine required completed
registered namespace authorities when the real virtual module is evaluated.
It publishes no partial/empty registry. All twenty properties follow upstream
declaration order and share the exact original namespace objects across aliases.
Loader construction never calls evaluate or looks up the SDK namespace.
Its ordinary getVirtualModules caches the original real import().then(selector)
result, including rejection, without introducing a Promise facade.

Assembly inputs are intentionally explicit: actual transactional ExtensionAPI,
actual path/timing namespaces, physical loader URL/runtime mode, actual original
getCreateJiti, actual alias resolver, and the real lazy virtual-module import.
The application must retain this loader namespace once at its real module owner,
pass its original loadExtensionFromFactory/loadExtensionsCached identities to the
actual ResourceLoader assembler, complete the actual SDK namespaces, then allow
the lazy real virtual-module evaluator to run. Shape checks cannot prove those
inputs are genuine. There is no fake createJiti/import object, Node production
bridge, empty provider registry, or substitute runtime construction.

The final Engine Graph2 adapter is not composed here. Its current source-only
prototype returns namespaces and does not implement full jiti default/Proxy/JSON
interop; private graphs are context-pinned, not reclaimed. Completing and
qualifying that adapter, real lazy module-import cache ownership, exact physical
paths/attrs/old-graph policy, live importer traces, aggregate allocation,
cancellation and teardown are separate production gates. Existing ordinary
Engine external TypeBox resolution is untouched. Default selection remains off.

Nine prepared control entry points use actual assembled subjects. Six JS control
programs cover real empty runtime construction, IteratorStep/path failure reason
identity, actual physical valid/invalid extension imports, real subscription
discard cleanup/override, exact original native discard OOM and actual virtual
namespace order/alias identity. Native checks cover genuine AF brands/lengths,
stale token invalidation and cached real virtual-import Promise identity.
The fatal discard case requires a dedicated Engine because guest restoration is
bypassed. Physical replay inputs and per-version bytes must be retained by a
future bounded owner, never synthesized into accepted expectations.

No formatter, AST check, compiler, native runtime, Node capture or generator was
launched. All controls are uncompiled/unrun. Original Source53/44/15/48/39
observations, negatives, expected files and physical fixtures remain unchanged.
