Source-only settled-completion correction from Root56457347. Product change is
only native_sdk_extension_loader_production.zig: delete the old rejected-DATA
generation/flag classifier and ClearUncatchableError; call the existing FCAA
enterRejectedContinuation at each of the three rejected Inner entries before
Scope/state access; detach Captures.prior before ownership transfer/release.
No Scope/Engine/AF/C/H/API/runtime/cache/importer or default selection is changed.

Actual Source authority is 8efd314fa3d3232ce197d8d7a6a5660530b9d83e
packages/coding-agent/src/core/extensions/loader.ts, blob
bee134d35827b465a0f8521452cf528f923fd621, SHA0177DB97...2EB3A. The entire
retained historical loader authority and the actual immutable8efd snapshot match
byte-for-byte. Source catch formatting, Error/instanceof/message/String/getter
order, IteratorClose order/ordinary suppression and public return adoption are
unchanged. The raw rejection remains borrowed; only returned/thrown Action
ownership duplicates it. No rejection-input bit/tag is read, cleared or promoted.

Await map is unchanged: loadExtensionModule awaits getCreateJiti, conditional
getVirtualModules and jiti.import; loadExtension awaits loadExtensionModule and
initializeExtension; loadExtensionsInternal awaits each loadExtension. Public
loadExtensions/loadExtensionsCached still return-adopt the internal call with no
extra Await/Promise. Existing initializer's factory Await is a protected separate
leaf. Pending events win before rejected-state work; FCAA preserves owned actual
events and drains mutable diagnostics. Bfb AF/Engine invocation ownership retains
the first actual fatal across callback/temporary/captured retirement. Restoring
or freeing the detached prior diagnostic never makes that old DATA an event.

Prepared new controls require an exclusive fresh Engine and the genuine composed
loader, actual jiti/module import, actual transactional API/runtime and event bus.
Import controller.input.mjs as a real guest module before importing the physical
extension.input.mjs path supplied to loadExtensionsCached. The controller's gate
is a real guest Promise. Its user-defined message/iterator observers wrap real
objects; they are not replacement dependencies. No fake factory/importer/cache,
module registry, completed graph or runtime is created by the controls.

Seven new entry functions are prepared, uncompiled and unrun:
- verifyOrdinaryUserError: real user Error, exactly one Source message read,
  formatted result and actual transactional event subscription discarded.
- verifyCaughtInterruptData: catch an actual installed Engine interrupt at the
  host, reject the real guest gate with that owned value, preserve its existing
  uncatchable bit as DATA while Source formats it ordinarily.
- verifyFreshPrivateTagDataDuringAwait: create/catch actual fatal native OOM
  outside any native invocation while the genuine factory gate is pending. A
  tag born after START remains settled DATA; its bit/tag cannot classify resume.
- verifySameReasonThroughIteratorClose: actual message getter throws the same
  ordinary reason, then real user iterator return getter/call run once; ordinary
  close override is suppressed and raw primary identity survives.
- verifyFatalFormatterCompletion: actual formatter getter calls an explicit real
  native OOM probe. Current fatal bypasses aggregation, keeps exact identity and
  prior diagnostic DATA bit, leaving the genuine outer Promise pending. No guest
  cleanup/restoration follows fatal; the fresh realm owner must tear it down.
- verifyActualPendingFatalWins and verifyActualDeferredInterruptWins reuse only
  the still-valid genuine pending-hook controls from the historical module.

For import-rejection coverage, supply module-reject.input.mjs as the actual
physical path instead; its real top-level Await rejects before factory entry.
Run the first three DATA controls with that subject as a second profile. The
controller.calls observation counts real module entry in this profile and real
factory entry in the normal profile. Subject.factory is unused by these whole-
loader controls and need not publish an export from a rejected module.

For the IteratorClose case, actual.paths must be the real user iterable returned
by controller.makeClosingPaths(actual physical extension path). Other cases may
use a real ordinary array containing that path. Existing old verifyOldData's
bit-clearing assertion is C2 historical scope and is intentionally preserved,
not selected as a C3 control. No historical input/expected/receipt is rewritten.

The prior-diagnostic fatal control exercises owned slot retirement, not a new
last-reference native-finalizer stress harness. Bfb's independent native
invocation/finalizer controls remain separate authority. C1116's actual pending-
before-body VM semantic correction is also an explicit external prerequisite;
this leaf neither copies it nor claims runtime qualification on the retained C2
vendor bytes. Full SDK27/166, runtime, allocator/GC, default activation and the
original new inputs' capture remain unqualified. No expected JSON is authored.
