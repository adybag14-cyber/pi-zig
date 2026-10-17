# Prospective completion retirement correction

Source-only preparation after frozen product checkpoint 32a2200475d42930ad6fe37b15e63d9bfa23f0d8 and prerequisite checkpoint d5bcc71e0da18b96491797c275dce3f137c2d580. These checkpoints are preserved as the recorded ordinary-unwind frontier, not accepted runtime candidates. No compiler, parser, formatter, Node, VM, native control or generator has run for this preparation. The two product leaves and the original observers/manifests remain byte-identical.

The finite review found that a local Scope may retire its last native carrier before the outer AF error handler owns ordinary error A. A carrier finalizer can publish ordinary B during retirement. The existing first-fatal invocation guard does not escrow ordinary A. Root authorized one SDK-owned completion helper, authored separately by API; this unit must consume that reviewed helper instead of copying its policy or changing Engine, Scope, Body, Iterator or generic callback adapters.

The intended API receives the untried result before retirement: `finishAction(scope, anyerror!Action)`, `finishValue(scope, anyerror!JSValue)`, `finishVoid(scope, anyerror!void)`. Helpers that already recorded an AF action require `finishRecorded(scope, anyerror!void, state)` so recorded rejection DATA is not translated into a current throw. These APIs are prospective until the helper's exact sealed source and independent reviews are available. The Auth provider Scope must retain its 32 inline roots and overflow ArrayList; Resource Scope retains its existing ArrayList. This document does not authorize a storage-layout rewrite.

The adapter inventory is:

| Owned computation | Required exit treatment |
| --- | --- |
| Auth methodStep, storageStep, memoryStep | Capture the actual returned/awaited/thrown Action or error before their Scope retires. |
| Auth wait and settle | Capture the newly recorded action before retiring writer roots. |
| Auth continued | Its independent nested Scope records wait/return/throw; use a recorded-action exit before this Scope retires, rather than waiting for methodStep's outer exit. |
| Auth fallback and clearReload callbacks; listMapper | Ordinary JSValue callback exits must own their actual result/error before local Scope retirement. Source callback catches/finally remain local and observable. |
| Resource reloadStep | Capture actual Action/error before its Scope retires. |
| Resource wait and settle | Capture the recorded action before writer Scope retirement. |
| Resource initialize, trustExtensionsLoaded, trustResolved, reloadSettings, settingsReloaded, packagesResolved, cliResolved, extensionsLoaded | Each independent nested Scope crosses a recorded-action exit; retiring only reloadStep's outer Scope is insufficient. |
| Resource observed | Own the callback value/error before its local Scope retires. |

Ordinary Source catches/finally must retain their existing precedence. For example Auth `latest` invokes `releaseReader` as actual Source finally before recording the result; that guest operation may replace an ordinary reason. This differs from native temporary-root retirement, where an ordinary cleanup event must not replace the completion already owned. An actual new native fatal event during retirement may promote. Historical captured diagnostics and flagged Promise rejection DATA are not new fatal events.

Iterator-owned roots and per-item direct frees inside Auth listMapper and Resource enabledResources/cliMetadata/missingExtensions/missingResourcePaths are additional boundaries. The outer Scope exit alone does not protect a reason before those direct retirements. Their exact treatment must use the same reviewed SDK-owned completion policy without delaying Source IteratorClose, changing observable callback order or copying a shared Iterator implementation. Existing broader iterator/proxy/cancellation frontiers are not qualified by this inventory.

`src/native_auth_resource_cleanup_controls.zig` prepares a concrete actual-method control. The caller supplies the genuine authenticated SDK Auth namespace, and the control obtains its real `AuthStorage.inMemory()` instance. A real getter on the returned data object creates a native credential carrier with no retained alias; the actual `read` continuation roots it before its actual signal check throws ordinary A. The carrier's native finalizer emits ordinary B in one profile and a newly produced native fatal C in the other. The profiles require exact original A versus exact new C, one getter, one finalizer and no diagnostic coercion. A counted heap probe remains alive if a failed control unexpectedly retains a carrier, avoiding a finalizer that borrows an expired stack frame.

The control is an unregistered integration entry, not an executed test, full SDK bootstrap substitute or authored expected capture. Each profile requires a fresh genuine SDK realm and the composed pending-first/data-safe C prerequisite documented in CRITICAL-VM-PREREQUISITE.md. Original Source captures remain absent. The helper's own core retirement controls and finite independent review are prerequisites for product adapter changes and any later Root-granted execution.
