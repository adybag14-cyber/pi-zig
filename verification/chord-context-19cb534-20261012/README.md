# Chord2 Context foundation

Authority: genuine Pi `19cb534c3b6e3871458a8fa59e98f0312c50e995` and its unmodified Chord 1.1.0 modules. Native base: committed Root `07036735a29da746d6b665a4de4bd941a690a6d6` in an isolated worktree.

## Inventory and scope

The actual Chord root has no `Runtime` export or class. Its host owner is `createHost`, with root/installation/readiness/handle/registry/link/reload lifecycles. The root export inventory and complete eight-name Context subpath inventory are captured in the Source fixture. Existing native coverage consists of strict JSON and the Context helpers used by durable work; the durable harness registry is not a Chord `defineRegistry` or epoch registry view.

This increment implements the concrete missing Context object and cancellation foundation. It does not synthesize a Host, Runtime, contracts, cells, resources, remote handles or registry facade, and does not activate an incomplete public Chord package. Durable model services, default tools, four-slot execution and file environments remain outside this branch's ownership.

The previous Context objects stored a frozen own `abortSignal` snapshot and receiver-independent closure methods. `withContextValue` eagerly read `parent.abortSignal`. Actual Chord instead has `EmptyContext` and `ContextValue` classes inheriting a live `BaseContext.abortSignal` getter, private parent/key/value fields, and ordinary mutable prototype methods. The native classes now preserve those semantics, constructor/subclass identity, private brands, method descriptors and exported normal-function constructibility/arity. Context derivation no longer reads a parent signal eagerly; cleanup overrides the private abort key while retaining all other parent values.

`awaitWithContext` now observes the actual Promise-executor boundary: listener installation or a then getter/call failure rejects the waiter with the original value, without an extra cleanup callback or a synchronous throw. Cancellation still rejects only that waiter and leaves the original operation alive. Normal settlement removes the listener and preserves result/error identity.

Private Context state retains parent, key, value and name as traced owner-VM roots. Its finalizer releases them using `JS_FreeValueRT(runtime)`, without accessing a freed JSContext. Shared native constructor/function helpers use the same runtime-based finalization rule.

## Original evidence

The identical observer executes original unmodified Context functions/classes and imports the actual Chord root for its export inventory. No Source classes or methods are replaced. Thirteen cases cover class/prototype descriptors, function construction, live parent value lookup, a custom getter receiver, private brands/subclassing, cancellation and cleanup, original promise identity, Error and non-Error cancellation reasons, Promise-executor failures, and listener removal on settlement.

The owned Node capture uses heap 64 MiB, fresh 2 GiB admission and a 30-second deadline. Full pre/post hashes cover all 31,064 immutable runtime files and 1,774 tooling files. Every one of the 691 observed module/input hashes and all 16 workspace junction targets remains unchanged. Full manifests stay under `C:\Users\adyba\pi-zig-update-evidence-20261003`; their hashes are bound in `source-qualified.json`.

## Native qualification

Default-backend Debug qualification passed 11/11 discovered tests and 156/156 build steps. The gate includes the original thirteen-case replay, private-parent/key/value GC liveness, exhaustive native allocator failure ownership, two unchanged original Storage Context regressions, and imported anonymous checks. It used exact Zig 0.16.0, fresh 16 GiB RAM, `-j1`, test timeout 120 seconds and owned outer deadline 300 seconds. The first compiled run found a real constructor host-boundary allocation error mapping gap; the product repair uses Engine native generation tagging and retains every allocation assertion. The warm run passed with zero post-run drift across 4,223 source inputs and 19,546 tool inputs. Both owned process trees retired. Exact records and remaining Host/package limitations are in `native-validation.json`.
