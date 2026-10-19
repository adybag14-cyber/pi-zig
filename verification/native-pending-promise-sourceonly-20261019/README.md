# Intrinsic pending Promise allocation — source-only unit

This unit exposes `JS_PiNewPendingPromise(ctx)` for the real FileHandle request construction path. It returns one owned intrinsic Promise without allocating the two resolving functions created by `JS_NewPromiseCapability`.

## Original operation and bounded mapping

The pinned Node v24.13.0 V8 implementation creates the Promise directly in `Promise::Resolver::New`. `Resolver::GetPromise` is that same object. The intrinsic factory initializes a pending Promise and then invokes the real init hook with an undefined parent.

The complete original sources are already retained in the adjacent committed authority directories. `production-delta.json` records their exact hashes, immutable URLs and selected original bodies. This unit references those originals instead of making another copy.

The linked QuickJS change extracts only the initialized Promise object prefix from `js_promise_new`. The original resolving-function creation and parent-aware init-hook suffix remain byte-for-byte unchanged in the old operation. The new direct API selects the current realm's intrinsic Promise prototype, runs the actual init hook with undefined parent, and returns the owned result. A hook may retain, mutate or settle that result before the API returns.

The native API preserves an existing actual pending exception before allocation or hook entry. This is the native borrowed-operation policy; it does not claim the public V8 `PREPARE_FOR_EXECUTION` entry-clearing behavior. If the init hook leaves an exception, the API retires its owned result through the existing pending reducer. An ordinary hook reason yields to a real cleanup fatal, while an existing fatal survives later cleanup. Hook-retained values keep their independent ownership.

## Ownership and hook boundary

The direct result contains the real Promise state and reaction lists. No resolver pair, replacement Promise, public constructor lookup, species lookup, or hidden completion adapter is introduced. Foreign contexts use their own intrinsic prototype.

The init hook is a real guest-capable boundary. Consumers must check the ordinary owned result and pending exception after it. They must not classify the whole allocation operation as an intrinsic-only allocation span.

## Authored controls

The root contains 15 named controls over actual linked VM operations. They cover intrinsic prototype selection, object counts at real INIT, nested parent-aware allocation, hook modification and immediate settlement, independently retained results, exact ordinary and fatal hook failures, preexisting pending, heap allocation failure, first-fatal cleanup reduction, the existing DisallowJS guard, real thenable jobs, a foreign context, and returned flagged DATA with the original resolver latch.

Every expected-failure raw result has explicit retirement. Fatal progress assertions read pre-retained own primitive fields rather than evaluating another guest program. Native probe storage outlives runtime teardown.

The build addition is six install-only lines using the shared `linkQuickJs` graph:
`build-native-vm-pending-promise`, filter `VM pending Promise`. There is no execution step.

## Review and validation status

SDK and Modules independently closed the bounded production and all 15 control slices. SDK also closed the exact six-line build seam. `source-status.json` records current hashes, all declared names, peer scopes, dependencies and the final build receipt.

This is source-only work. No compilation, metadata query, control execution or FileHandle runtime qualification occurred in this unit. Root owns subsequent exact-artifact validation.

The C/H reversal is complete: replacing the single new C block and removing the single header addition reproduces parent `cb6303dc229d9c601be128e9cf746f19c5bd0f6b` exactly. The production packet preserves its earlier preparation status; the final status file records later peer closures.
