# Private Error stack prerequisite for native Messages

Status: proposal for Root review. Script32 is sealed at bc518be926f55ae6af0b5e5ceb54989dd11174a5. This proposal has not changed C/H, Engine, the private Error owner, or reporter installation. No native execution is authorized or claimed.

## Concrete next unit

Implement the native, read-only simple-stack lookup and correct the existing private stack state transition for the selected default uncaught-capture setting. This is the first part of Message unit 2 from the retained prerequisite plan. It uses the existing StackData/WeakMap owner; it does not add a second Error-to-stack registry.

The output needed by the following Message constructor is an independently retained JSNativeScript and actual UTF-16 start/end positions. The query must not read public Error.stack/name/message, invoke WeakMap.get as JavaScript, format a stack, adopt a C pending record, or retain copied CallSite receiver/function graphs.

This bounded unit does not create or report a Message. Native ThrowAt location fields, optional detailed traces, the fresh Message argument owner, text conversion, listeners and report-local catcher/restoration are separately reviewable successors. Their unresolved state remains explicit in the original plan.

## Existing owner and installation

The current owner is src/extensions/native_error_stack.zig, EC0002CEED53432B26BA135F2D4CDC6FFB8C2D0460ADE1C6B8D003C8194826BF (25,360 bytes). StackData owns captured, frames and formatted; markData/finalizeData own those actual roots. Its current lookup calls captured WeakMap.get through Frame.call, may allocate adoptPending, and walks prototypes. It cannot be used as a raw Message query.

The owner is installed by focused fixtures and native_worker only when fatal_lease is nonnull. Normal Engine initialization does not install it. The Message integration must receive the actual installed owner and later Root must select its real startup lifetime; this proposal adds no unconditional installation or inferred global owner.

The linked C recursion fallback is also precise. capture_error_stack stores an actual frame Array in Error.u.object_data only while the native stack hook is already active. Ordinary uninstalled QuickJS formatting is a different path. The existing JS_ReadPendingNativeErrorStack is a read/duplicate operation; it is not a generic V8 Error stack registry.

## Original state rules

The original private stack lookup uses the prototype chain while skipping interceptors; accessors, proxies and denied access stop without invoking guest code. A present private formatted or undefined value stops inheritance. Public stack properties are not the private state.

The default simple representation is a FixedArray or its replacement formatted value. ErrorStackData is a distinct original representation used with the detailed trace option. Its call_site_infos_or_formatted_stack is one union slot, while its detailed StackTraceInfo is separate. Our current two optional fields must not be treated as two simultaneously authoritative simple-stack states.

A formatter keeps a local handle to the original raw array across every guest callback. An ordinary reentrant stack setter therefore cannot retire that formatter-local owner early. On successful formatting, the default FixedArray branch writes the completed value to the originally selected holder. A reentrant CaptureStackTrace may have replaced that holder's private record; success still replaces its current private value. On formatting failure that final write is skipped.

The ErrorStackData branch instead updates the previously selected ErrorStackData handle. If reentrant capture installed a different private record, that new record remains distinct. The current proposal will not pretend that the port's implementation wrapper is an original ErrorStackData. Detailed capture needs its actual separate owner before that branch is admitted.

## Proposed C operation seams

The exact names below are proposed ABI names, not installed declarations.

1. int JS_PiReadWeakMapEntry(JSContext *ctx, JSValueConst map, JSValueConst key, JSValue *value).

   Factor the existing js_map_get read operation: genuine WeakMap brand, map_normalize_key_const, map_find_record and one duplicate of the existing value. Return 1 for an entry, 0 for a missing entry (writing owned undefined), and -1 for invalid map/output with output unchanged. No exception creation, allocation, guest call, pending-state operation or kept-object side effect. The selected owner uses its actual operation context; this does not claim a new cross-context Map hashing policy.

   The raw record result is owned while inspecting StackData. The native caller must not retain a borrowed StackData pointer beyond that record handle.

2. bool JS_PiHasPendingNativeErrorStack(JSValueConst error), and int JS_PiTakePendingNativeErrorStack(JSValueConst error, JSValue *frames).

   Add an explicitly initialized native presence bit for the actual recursion-fallback publication. Error.u.object_data starts as undefined before capture, so its tag alone is not evidence that capture occurred. Set this bit only when the successful fallback publishes its Array or captured undefined; clear it before a successful transfer. The allocation-free predicate reports that actual presence. Preserve the existing JS_ReadPendingNativeErrorStack ABI and its legacy read behavior; the new raw query checks actual presence before using that reader.

   The take operation is the consuming counterpart to the current pending-frame read, restricted to a marked real Error recursion-fallback Array/undefined publication. It clears presence and the native field before returning its former owned value; invalid inputs leave output/state unchanged. It allocates and calls nothing, changes no pending event and does not change the allocation-generation field.

   Existing adoptPending will continue to allocate/attach its normal record in the existing operation. Only after actual Map publication succeeds will it take and retire the old C entitlement. This removes the second lasting root while preserving rollback: failed adoption leaves the original C owner intact. Read-only Message lookup itself will never call this operation.

3. JSNativeScript *JS_PiFindCapturedStackScriptLocation(JSValueConst frames, int *start, int *end).

   Read the actual private captured frame Array through its intrinsic elements, then the existing opaque frame Script/position metadata. Select the first frame that has a genuine debuggable Script; native and filename-only synthetic records do not manufacture one. Return an owned Script with the actual selected position and its one-code-unit end, preserving an actual unavailable position rather than guessing from line/column. No allocation, guest lookup or pending change. Invalid/missing results leave outputs unchanged.

   The implementation will use the actual private capture Array representation and reject unsupported shapes. It will not invoke inherited numeric properties or array length getters. CallSiteInfo::ComputeLocation supplies the selected first-usable-frame order; Script32 supplies the actual position, origin and lifetime.

No C helper will poll a native entry, classify retained diagnostic DATA as an event, or dispatch a native API callback merely to read state.

## Existing owner changes

Retain the actual WeakMap handle directly in Owner at installation so a raw query can use it without public bindings lookup. Its mark/finalizer must account for that exact native root. Keep the owner/exception alive for the whole query.

Add a raw lookup returning an owned record handle plus selected holder/presence. It stops at a present formatted/undefined private state and at a Proxy, and does not invoke adoptPending. The actual C recursion fallback can supply frames directly only when its recorded presence bit is set. A recorded undefined value stops inheritance; a merely initialized undefined field is not converted into private provenance. Successful adoption leaves the normal Map record authoritative and clears the fallback presence before retiring its duplicate root. The caller immediately projects Script/position and releases temporary frame/record handles. The independent Script is the only added metadata owner.

Make the selected simple state exclusive: either raw frames, a completed formatted value (including JavaScript undefined as a present value), or no simple capture. A stack setter and a completed formatter publish their selected new state before retiring the old state. Keep a separate owned raw-array local through all formatting callbacks. Successful default formatting writes the originally selected holder's current private state; failure leaves a reentrant setter/recapture result intact.

The existing Frame is a plain rooted-temporary owner, not the canonical actual-pending reducer. New state replacement/retirement must explicitly use the current Engine/native owned-completion contract and clear fields before finalizable release. No broad Frame rewrite or shared Completion policy change is proposed. The detailed source packet must show the exact selected replacement and callback return cutpoints before intake.

A Message's eventual original argument root may itself keep an Error and its private stack alive, as the original does. This proposal avoids adding a second independent CallSite graph merely for location metadata; it does not claim the required argument root has no graph.

## Focused control surface

The proposed source root will use the actual installed owner and real linked C operations. It will cover:

- Raw WeakMap entry/missing/invalid behavior, an actual owned record result, heap limit 1, DisallowJS, and exact prior ordinary/generic/private pending identity.
- Genuine Error simple capture, inherited holder selection, a present undefined/disabled capture blocking an ancestor, a formatted value blocking an ancestor, and a Proxy trap that must remain uncalled.
- Poisoned public stack/name/message and WeakMap.prototype.get cannot affect the raw query.
- Simple stack setter replacement retires the original receiver/function holder only after publication.
- A formatter-local raw owner survives an ordinary reentrant setter until formatting returns.
- Successful formatting overwrites an ordinary reentrant setter; failed formatting preserves it.
- Successful default formatting after reentrant CaptureStackTrace targets the original holder's newly published simple state; failed formatting preserves the new capture.
- A real hook-recursion Error enters the C pending fallback; a raw query does not adopt it, disabled capture records present undefined without inventing frames, initialized-but-uncaptured native fields do not manufacture provenance, successful actual adoption transfers its lasting owner once, and failed adoption preserves the original owner.
- Script/position survives original Error/record/frame retirement without an extra CallSite receiver root.
- Native/synthetic/no-PC frames and cross-realm Script metadata retain their actual distinctions.
- Actual cleanup exceptions and native termination retain the current explicit event/native-abrupt semantics. Retained flagged DATA is not authority.
- All owned outputs/reasons are attached before fallible assertions; probes outlive Engine teardown. No guest query follows a fatal observation.

The eventual exact declaration count, build target/filter and source-only peer split will be fixed after implementation. No reserved target or fake test name is added by this proposal.

## Separate next steps after this unit

The original PendingCompilationErrorHandler creates a native SyntaxError and calls ThrowAt with the actual Script and start/end positions. That evidence is now retained at 6A68F859/0D7FD768. Current js_parse_error only builds a filename-based synthetic frame, and Script32 deliberately keeps that synthetic frame's Script null. A future native Error-location owner must attach the actual compile Script/span separately, at the successful native Error construction/ThrowAt boundary; it must not relabel the synthetic frame or attach metadata to an unrelated OOM/current reason.

The fresh Message owner will then select actual private location, simple stack location and current debuggable frame in the original order. Missing location remains a real invalid-position/empty-Script state. Optional detailed trace captures only its genuine primitive/Script metadata, independently of simple-stack replacement.

The reporter remains a separate source unit. Its report-local serviced termination can be discarded by the original ExceptionScope restoration plus Runtime clear, while an unserviced request survives. This is not the generic first-fatal Completion policy and must not use public Cancel as a shortcut.

## Review boundary

Root approval is requested for this concrete private-stack prerequisite before its C/H and existing-owner edits. Until then, only original-source acquisition and this review packet have been written. Both normal installation and complete Message/reporting composition remain unclaimed.

## Exact review evidence

- Original storage/lookup/formatter/location proof: authority/stack-data-source-proof.json, SHA256 1A66CB1C67B30BCDCEA75DE72BA42DAC8D260B453976E15103E32A94E82C08C8 (39,089 bytes). The ten selected ranges include the actual union offset and the distinct ErrorStackData versus FixedArray success writes.
- Existing linked owner and installation receipt: peers/existing-error-stack-owner.json, SHA256 EE9AE43FB142971E98DB3C8362BEC4B08A4D9E11900C12A144F7C6D6E24B3BA9 (12,626 bytes).
- Script32 production/control manifest: ../native-script-location-sourceonly-20261020/manifest.json, SHA256 CFBC2CCCA26ED4B419C78B1D23A5703D7034727EF76E4F58AE6828883B3F16DF.
- The prior Message creation/report prerequisite remains ../native-microtask-message-sourceonly-20261020/PREREQUISITE_PLAN.md, SHA256 97A06D2A68F9F296C15CFA44F63329825314796153C09FDF4ADA3E1009C685EA.
