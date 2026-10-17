# Implementation invariants and outcome matrix

This amendment supplements B7FC4891022106842F606325D20BC6BFE92E77FC7C5443F8F9E4344B86ADEC7E. Root explicitly authorized the source prototype incorporating these finite review invariants. It does not authorize generation/native/compiler/LLVM jobs. Original08bd source and raw evidence stay unchanged.

## Actual callable and descriptor provenance

Use the private NativeNode invoke-body hook chosen during review. Pass the actual function JSValue from NativeNode.call into private invoke. Perform original effective receiver selection (arrow -> undefined; ordinary/method -> actual target) and original constructor receiver creation FIRST. The invoke-body hook then routes a registered selected function to Machine.runRoot with that actual function/State/provenance, effective receiver, actual args and State.values. Keep the public Callback ABI and original constructor returned-object rules unchanged. Existing f_N bodies remain legacy fallback; the continuation descriptor is supplied explicitly at its known generated function creation point, never selected by callback-pointer/name scan. Multiple closures/code-folded functions remain separate exact-object registrations.

Before pi_js_object_identity, require JS_IsObject: that existing C helper is JS_VALUE_GET_PTR without a tag check. Verify stored class, State identity, descriptor, Engine, callback and captured-slice provenance after lookup. Weak registration owns no JS value. Finalizer removal is nonallocating and precedes State destruction/address reuse. Registry storage outlives all JS_FreeRuntime finalizers on NORMAL DEINIT AND Engine.init ERROR UNWINDS; only then free its host table. No new C helper, class sharing, public property or generic latch is introduced.

## Request and acknowledgement matrix

| VM call outcome | Child/request state | Required action |
| --- | --- | --- |
| JS_EXCEPTION or actual pending reason before class dispatch | request unconsumed | Legitimate VM interrupt/stack/allocation/other exception. Disarm, preserve/propagate actual reason; never manufacture protocol error. |
| JS_EXCEPTION/pending after preparation | child prepared | Disarm, destroy that uncommitted child exactly once, propagate actual reason. No logical suppression increment was committed. |
| Successful return + exact private undefined acknowledgement | scheduled child, request consumed once | Commit child's logical suppression ownership AFTER VM returns, then dispatch child's first Step. No acknowledgement store into Source/caller Scope. |
| Successful normal return | request unconsumed | No scheduled private body: take actual normal result only if the intended fallback path is legitimate; an unexpectedly unconsumed eligible call fails closed as a protocol invariant. Never treat a missing child as success. |
| Scheduled child with wrong/non-ack successful value or inconsistent identity | any | Destroy uncommitted child once and fail closed; no fabricated Source value. |
| Constructor/proxy/bound/unregistered/foreign/exotic call | not eligible | Original synchronous VM/invoke path; real result/error, with reentrant selected calls starting their own complete Machine. |

Disarm/restore the exact previous request on EVERY VM return, including failures. Consume before allocations so a preparation error hook cannot consume the same request twice. Native preparation before acknowledgement may allocate host records/slots and duplicate roots ONLY. It must not call rt.environment, bind parameters, evaluate defaults, create JS objects, read properties or execute Source/guest-capable operations. Those run in the first Step after acknowledgement. Suppression remains physically owned by root/reentrant NativeNode.call; scheduled logical children acquire their own one increment only at dispatch transition.

The stable private caller heap argument slice is borrowed only after verifying actual argv pointer/count; no arbitrary VM argv stack pointer escapes the short call. A normal/root wrapper may borrow its actual args while its synchronous invoke remains live. Retain the exact actual function value while an Activation is live, keeping State.values/captured roots valid. Arrow lexical receiver and method call receiver are separate: source receiver use follows original frozen flags/captures, not an accidental helper ABI argument.

## Owned completion and fatal matrix

Capture a fresh native-allocation generation boundary around EACH fallible preparation, step/VM operation and finally operation. Use current qualified trusted fatal transport: direct host error.OutOfMemory creates/marks its actual native reason once; an existing uncatchable reason or private allocation tag born inside that unsigned generation span propagates the SAME reason as fatal. Historical private tags and guest names/messages do not establish fresh fatal identity. Do not call a helper that clears uncatchability, retag a propagated reason, manipulate generation as a control counter or rely on legacy Node.fail's catchable private-OOM behavior.

| Completion | Source finally | Native activation teardown | Result |
| --- | --- | --- | --- |
| Ordinary return | Execute actual finally once; it may replace return with an ordinary throw or a trusted fatal | Always | Actual pending/overriding completion |
| Ordinary JS throw | Execute actual finally once; it may replace ordinary reason | Always | Exact original or actual overriding reason |
| Trusted host-fatal/uncatchable | SKIP guest Source catch/finally, matching current VM uncatchable policy | Always | Same fatal reason/uncatchability; cannot be replaced by ordinary finally error |
| New trusted fatal while ordinary finally executes | Stop guest finally/handlers; no further Source work | Always | New actual fatal reason, created once |

The real391 library Error is ORDINARY and executes every real InstantiationDecrement/reset; its recovery and129/792 remain hard acceptance. Skipping Source finally on a genuine fatal does NOT add a native decrement/reset shortcut. Cmalloc-null allocation frontiers remain explicitly unqualified; no new generic C latch/classifier is invented.

Completion owns each pending return/reason exactly once. Before transferring an owned return to parent Scope.own, MOVE/CLEAR it out of Completion: Scope.own already consumes/frees its input on append failure. A subsequent OOM cleanup cannot free it again. Keep pending ordinary reason/return rooted across finally; dispose the displaced owned payload when real finally overrides it. Fatal ownership is retained through all native teardown and rethrown through current trusted transport, without stale captured-slot lookup.

## Implementation now

Author a real native source kernel/private registry/request/invoke-body integration and focused causal controls in a NEW contained worktree from08bd. Then extend the official one-pass authoring source with typed CFG records for exactly34 selected callbacks, preserving original source operation order/IDs/slots/flags. Keep generated14C unchanged until Root separately grants owned generation and reviews output. Use bounded Step-table dispatch to retire source activations, not more helpers that remain live. No native/generation execution precedes independent source review and Root's explicit grant.
