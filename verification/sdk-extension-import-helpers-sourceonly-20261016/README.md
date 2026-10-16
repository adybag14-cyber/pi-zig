# Concrete extension import helpers, source only

This unit completes the Source loader's ordinary getAliases/getCreateJiti
bodies, actual lazy virtual/jiti re-export module definitions, and the concrete
ExtensionAPI-to-cached-loader assembly. Source authority is current upstream
4dd2b149d155d7369de16ea4dc77c84e9f5ffb24. Four authority files are independently
hashed against the retained 4954/0fb copies in prepared.json.

`native_sdk_extension_aliases.create` captures the actual named fileURLToPath
and createRequire imports, evaluates Source's top-level require once, then
creates ordinary getAliases, length0. Each uncached call preserves dirname and
physical package index resolution, three live require.resolve calls, five
workspace existence checks with import-meta fallback, twenty Source properties
in declaration order, compatibility-root aliases and the final object cache.
An ordinary failed call leaves the cache unset; a successful call returns the
same mutable object subsequently. Namespace and callee receivers remain live.

There was no existing import.meta.resolve binding in Engine metadata. The new
private alias resolver covers exactly the five Source getAliases package
specifiers. It uses the real captured SourceLoader import normalizer and
physical loader filename, requires physical absolute results, and formats real
file URLs through the existing native file URL implementation. Its stable owner
and retained filename are charged to the actual aggregate memory owner. It
rejects loader replacement before dereferencing the borrowed old context.
The application's SourceLoader context must outlive Engine/context teardown,
as for the existing worker and private importer contracts. This is not a
general Node import.meta.resolve implementation; unknown inputs fail closed.

The assembler uses the supplied exact physical loader metadata object. If its
resolve binding is missing, it installs this private resolver on that object
only. An existing real resolve function is preserved. Non-function bindings
are rejected. The ordinary Engine resolver and external TypeBox policy are
unchanged. createRequire is the existing actual node:module implementation;
the actual worker must provide its real require-mode source normalizer and real
external TypeBox package files. No package pathname is fabricated.

`native_sdk_extension_lazy_imports.create` registers three physical native C
module definitions through existing Engine.registerValueModule. Their export
accessors remain unread during registration. The virtual module's accessor
evaluates the actual twenty-entry object only when the real C module initializes,
reading the nine completed registered namespace authorities. The two jiti
modules re-export createJiti from their required actual completed native jiti
namespace authorities. They do not implement a facade around namespace import.
The real C module namespace/binding cache owns the evaluated export identity.
Module private roots retain accessors/names through context teardown. Existing
Engine reservations remain quarantined if registration fails partway; there
is no retry/global sweep or claim of transactional registry rollback.

Ordinary getCreateJiti chooses the real static/lazy module according to the
captured embedded-runtime condition, calls the actual dynamic import operation,
and caches the exact original importPromise.then(module => module.createJiti)
result, including rejection. The existing Source getVirtualModules helper does
the same for VIRTUAL_MODULES. A getter's raw module-initialization exception is
returned to the VM after removing its native captured slot. Preexisting fatal
and fresh privately tagged reasons retain their exact identity.

The new helper requires an actual queued dynamic_import(basename,specifier)
binding. Both arguments here are already-string physical Source module names;
these Source imports omit options/attributes and execute in shared graph0.
Public JS_LoadModule runs its loading path immediately and does not establish
guest import() timing, so this unit contains no JS_LoadModule fallback or manual
Promise shim. Root requested a separate tiny C ABI review from models_auth;
that ABI and its native qualification must precede composition. No C/Engine
file changes occur in this checkpoint.

`native_sdk_extension_loader_assembly.create` composes the real aliases, lazy
native modules, actual transactional ExtensionAPI and the reviewed cached loader.
It returns the original loader namespace whose loadExtensionFromFactory and
loadExtensionsCached identities can be passed to the actual ResourceLoader
assembler. The caller owns this graph once, completes and registers the real
SDK namespace, and then permits the genuine queued lazy import to evaluate it.
No default SDK selection is invoked here.

Explicit missing production dependencies are the reviewed/qualified queued
dynamic-import ABI and the complete actual native createJiti namespaces, including
Source default/Proxy/JSON interop. Their absence is rejected rather than filled
by an empty namespace or a retagged loader. The private Graph2 prototype remains
unselected and context-pinned; its policy, namespace identity, allocation and
reclamation gates remain separate. Exact namespace-exotic identity and complete
alias/import diagnostics require real composed native replay; registered-object
shape checks cannot prove those properties. The scoped alias normalizer likewise
cannot inherit full Node resolution/error parity from its existing host seam.

Six prepared control entry points use accepted genuine Source aliases and actual
composed namespaces/metadata/createJiti. Two JS programs compare all twenty real
aliases and raw metadata-getter failure identity. Native controls check the real
getCreateJiti Promise/factory cache, retained rejection identity, loader-change
guard and completing the actual SDK namespace after import() returns but before
its queued job. That last case detects a synchronous JS_LoadModule substitute.
The queue case needs an owned fresh Engine with the actual SDK namespace not yet
published; it registers the supplied completed real namespace, never a dummy.

No formatter/AST, compiler, native runtime, Node reference, source generator or
capture was launched. All controls are uncompiled/unrun; no expected file is
created or modified. Original Source53/44/15/48/39 proofs and physical fixtures
remain unchanged. Body's clean f12 review does not qualify these new helpers.
