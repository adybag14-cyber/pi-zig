# Native AsyncFunction body proposal: independent static review

Reviewed against native-provider-foundations HEAD `1097e7ff3fa72d3284a762d4ed4cb583ae20072f`, from proposal HEAD `ee0a30b980792db7b5f6b61e3411c67cba8eb790`. This document records static review, focused repairs, and genuine Node Source observations. Changed C and native tests have not been compiled or executed at this checkpoint. Native qualification and whole-Pi qualification remain false.

The original proposal C/H hashes were `B9570521CC49C84962E2DCEB7279C7DE6D1051CD4391A9992482A4837F142867` and `E3189DA8F918993FB567D07DF32E91CECD12C6666D9E9B1D68A6C65A15CEC37E`. The reviewed final C/H hashes before committing this packet are `33DFB18C9A930D3967A089DF0B28B65AF88B7665B7ADD725AED30FCB8F046FD2` and `E3189DA8F918993FB567D07DF32E91CECD12C6666D9E9B1D68A6C65A15CEC37E`.

## Representation and ownership

`JS_PiNewNativeAsyncFunction` creates the actual `JS_CLASS_ASYNC_FUNCTION` and supplies valid `JSFunctionBytecode` metadata, including an explicit native-body discriminator. This preserves the class identity checked by `JS_IsAsyncFunction`, avoids NULL-bytecode consumers, and retains the creation realm. Ordinary compiler allocations use `js_mallocz`; the deserializer zeroes its temporary `bc` before copying it into the zero-allocated metadata. No additional metadata allocator requiring native-pointer initialization was found.

The existing bytecode-object GC/finalizer traverses and releases the two capture-pool roots and realm. Per-invocation native roots include the function, receiver, copied arguments and state while active, and a separately duplicated/marked context. Termination releases the active roots once; finalization releases resolving callbacks and context. Ordinary bytecode invocation state is zero-allocated, leaving the native discriminator NULL and preserving the ordinary termination/marking path.

Native calls use the function's creation context for the intrinsic Promise capability and native body. Dynamic receivers are preserved strictly; lexical receivers are retained in the capture pool. Return invokes the outer resolver, so returning a Promise adopts it into a distinct outer Promise. Await uses intrinsic PromiseResolve and the existing continuation/reaction machinery. Catchable abrupt await setup re-enters the body with the exact thrown completion; uncatchable native errors terminate and escape.

The function has no constructor bit or own prototype. Existing constructor checks reject construction before body execution, including bound/proxy constructor forwarding and use as new-target. Bound/proxy objects keep their own class and do not acquire the actual async-function brand.

`need_home_object` and `home_object` are deliberately absent. This API does not yet provide native `super` or private-method home-object semantics. Lowering those semantics requires an explicit additional contract. Direct native-body source/bytecode serialization is rejected. Ordinary bytecode serialization/deserialization is unchanged.

## Findings and focused repairs

1. `JS_CaptureCurrentStackFrames` initially still selected native async metadata as bytecode, then took its null-PC fallback. That lost the function name and marked the frame non-native, bypassing the corrected callsite helper. It now excludes native async bodies from that bytecode selection. Native-only regression coverage checks start and resumed frames for name, native status, constructor status and absent file/line/column.
2. The existing shared `perform_promise_then` ignores the settled-Promise job-enqueue return status. It can return zero while leaving an allocation exception pending. The native branch now accepts suspension only when the helper returns zero and there is no pending exception. Otherwise it follows the same abrupt await setup path once, preserving uncatchable propagation. The shared helper and ordinary bytecode/async-generator behavior were not rewritten. A native-only bounded C-quota sweep checks continuation, reaction and job-allocation pressure for pending exceptions or an outer Promise left pending without a queued continuation.
3. The allocation test was renamed to state its Zig-host scope. `std.testing.checkAllAllocationFailures` cannot inject failures into the separately configured QuickJS C allocator. Separate native-only gates now force C factory/call failure, copied-argument pressure, await continuation allocation failure and bounded successive await allocation failures. A resumed native OOM gate checks uncatchable propagation and raw exception identity. These gates are authored but unexecuted at this checkpoint.
4. The native metadata comment now correctly identifies the two roots as `cpool[0..1]`.

## Bound/proxy toString scope

The proposal normalizes `Function.prototype.toString` for all bound functions and callable proxies, including revoked callable proxies. This is broader than the new native async class, and is retained deliberately: genuine Node Source rows cover native-async wrappers, ordinary guest wrappers and revoked callable proxies. Additional native-only regression coverage checks throwing public bound names, proxy get traps, ordinary call forwarding, unchanged ordinary source, revoked invocation rejection and noncallable receiver rejection. This avoids reading guest name properties or invoking proxy traps during wrapper source inspection.

## Genuine Source42 evidence

The committed fixture contains 42 distinct observations produced by actual Node `v24.14.0` async syntax, intrinsic `node:util/types` branding, intrinsic Promises and a `node:vm` realm. The driver and observer use only Node builtins; no external package or native proposal was substituted. Both driver and observer passed owned Node syntax checks before capture.

The owned LIGHT6 capture admitted more than 2 GiB of available physical memory, used a 256 MiB heap cap and a 300-second deadline, and recorded the Node executable digest, PID, kernel start time and exact native argv. It exited successfully and its original identity was absent afterward. Before/after verification covered all 1,774 pinned Node installation files, 19,546 pinned compiler files, 8,003 candidate files and capture controls; every drift count was zero. The compiler was hashed only and was not executed. Exactly the observer and driver were observed as file modules; their dependencies were builtins.

Fixture SHA-256: `52DD975CA6C7CCE1D9BF8BB13B763122862B7849CFAACFAED8906038C3AF9653`. Shared input SHA-256: `2F8C0DAB4866BD0215A6B0CF968EA7567BB02B7D33D42425D8310E5B3E40B070`. The compact durable receipt is [native-async-function-source42-proof.json](native-async-function-source42-proof.json). Full inventories and terminal logs are retained under `C:\Users\adyba\pi-zig-update-evidence-20261003\async-function-body-node24-source42-review1-20261016-*`.

The native-only quota regression and settled-enqueue exception guard were added after this Source capture. The Source driver, shared input and observed fixture were unchanged. This Source result establishes reference behavior; it does not establish native parity or qualification of the later C/test changes.

## Integration constraint

`native_async_function.create` has a `return expression` callback contract. A callback returning an actual body expression's Promise should be adopted. Existing facade callbacks may already create a flow Promise representing the original whole async function; wrapping that completed model introduces another adoption boundary and may change microtask order. Such integrations must expose raw body completion or migrate to a reviewed resumable-body/explicit-capability contract before replacing a prototype-only counterfeit. The primitive's real class identity is not a substitute for that behavioral migration.
