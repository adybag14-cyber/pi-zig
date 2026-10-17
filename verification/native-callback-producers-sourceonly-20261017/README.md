# Shared native callback producers / Engine cleanup / cold-class correction

Source-only successor of merge535e1b480784dc92b556de0f51cd62a00fca0f7b,
which unions reviewed-source tracks b6a8/1116/6d4 with exact Root Main
1fd8dd40100cb41b44d94e09fffe12ed1412f32e. No Main/qualification edit or job.
The Root union preserves actual Node61B695/EngineFA18 heap registry, provenance,
planned failFor -> heap.fail dispatch, owner teardown and every new SQLite leaf.
This unit is a minimal per-function patch over that union, never replacement
with old c720 Engine/Node snapshots. All older packets remain immutable.

## Actual producer and DATA contract

Engine.throwNativeOutOfMemoryFatal marks the newly created exact error BEFORE
old native-allocation tracking is released. First actual pending fatal takes
precedence before new allocation. A selected reason remains owned outside the
pending slot during finite old-tracking/native-finalizer cleanup. Tracking is
published/tagged before old ownership is released, so reentrant later tracking
cannot be overwritten by an earlier invocation. Unsigned wrap still skips zero.
The existing raw throwNativeOutOfMemory transport remains unmarked; retained
native DATA controls are not universally cleared or reclassified.

Common Node ordinary/arrow callbacks, real class callbacks, SDK.fail and realAF
adapter direct Zig OutOfMemory exits now use this same producer method. The
Root-authorized TypeBox failureReason directOOM hunk does likewise, without
changing planned dispatch/provenance/registration/ack/lifecycle. The existing
Agent executor producer, actual AbortSignal/registration/publication adapters and
intrinsic-parser diagnostic GPA exits reuse it as well. Already retained Agent
executor first-fatal holders are NOT removed.

Engine.checked now normalizes an actual pending event before returning an owned
successful value to Scope.own/GPA allocation. Normalization owns first actual
fatal across returned-result cleanup; a flagged result alone remains DATA.
Node/class call entry checks pending before body/planned dispatch, and their
successful exits normalize actual cleanup events before returning to C.

Engine capture consumes its owned input instead of leaving a duplicate whose
later release could overwrite a selected fatal. captureException supplies actual
JS_GetException origin; awaitValue supplies settled rejection DATA origin. Only
an actual pending event can gain fatal priority. Old captured diagnostic values
are moved out before release, never classified by their data flags. A cleanup
fatal can replace an ordinary input; the first actual fatal survives later
ordinary/fatal cleanup. Marked rejection DATA retains raw identity/flag and its
ordinary diagnostic conversion. Actual fatal capture suppresses guest ToString
and clears optional diagnostic text rather than running guest work after abort.
Native callback JS_EXCEPTION without pending becomes an explicit InternalError.

Four audited failed-operation producers (Models refresh, provider retry,
Anthropic parse and cache-warmer catch) preserve a recognized exact current fatal
before legacy host-only error-union recovery could clear/replace it. These are
captured actual failed operations, not settled input/data classification. Legacy
nativeAllocationError remains available unchanged for explicit outer host/test
error-union recovery; no input DATA is sent through it here.

## Genuine cold-class realm prototype and entry

The actual existing C3 export JS_GetFunctionProto(ctx), quickjs.c3062-3065,
returns owned js_dup(ctx->function_proto). native_class.constructor now uses
that genuine creation-realm intrinsic instead of live global Function/prototype.
No new Engine field, C ABI, fake constructor/prototype or bootstrap capture is
added. Its owned duplicate is released by the existing defer; all partial
constructor allocation/error cleanup remains in place. Factory and actual
newTarget-object entry preserve pending before class-ID/GPA/guest effects.
Ordinary constructor receiver/newTarget metadata and per-realm prototype remain.

## Eight new real VM declarations; total24, all UNRUN

- Genuine FailingAllocator failure inside Node function, arrow, real class and
  SDK raw callback; guest catch counter stays zero and exact tagged error exits.
- Typed callback temporary's real native finalizer publishes A after its return
  value R is computed. Node/class producer exit releases sole-owned R, producing
  fatal B. Ordinary A yields to B; fatal A wins B. Counts/identities/empty exit.
- Engine.checked actual temporary/result/old-captured finalizers prove pending
  capture precedes result release and diagnostic cleanup.
- Old sole-owned tracking finalizer publishes fatal during newborn OOM release;
  the newborn is already fatal, stays first and preserves exact identity/wrap.
- Actual Engine capture old diagnostic and displaced Error-token finalizers;
  ordinary original promotes to fatal B, already-fatal original stays first.
- Marked Promise rejection DATA uses ordinary ToString once with unchanged raw
  flag/identity; its data bit is not treated as an actual host event.
- Three fresh-engine cold factories poison global Function data, its getter and
  its prototype getter. Actual native C getters could leave pending+success if
  invoked; intrinsic factory must never call them. Actual constructor/instance
  prototypes are checked. No recovery of work inside bad C callbacks is claimed.
- Already-pending cold factory with armed GPA failure and adjacent real class IDs
  proves rejection before class-ID allocation/body/GPA and exact captured reason.

No compiler/parser/AST/native/Node/generator command has run. No expected or
observed output exists. These declarations are not allocator-stage C VM emergency
OOM qualification, concurrent/foreign-thread validation or a full SDK/Agent gate.

## Separate remaining boundaries

C3 Promise constructor still consumes executor exceptions into rejection DATA;
marking a producer alone cannot retain that event across later guest constructor
work. Existing per-invocation fatal holders remain required. The generator C3
producer-exit packet is also separate/uncomposed. Other legacy leaf-specific raw
OOM adapters, Promise-based worker settlements and older error-union wrappers
are not silently claimed corrected by these common producer exits. They need
actual producer-side event transport and their own bounded source/runtime gates,
not resurrection of fatal authority from later rejected DATA.

C1116 remains exact and independently source-reviewed by Min453C3147; b6a8 four
DATA files are independently source-reviewed by Async61563468. The14caller6d4
unit and this producer/class unit need their own exact finite review. No source
closure implies C component/composed qualification, activation or default switch.
