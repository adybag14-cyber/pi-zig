# Native suspended-frame retirement order

This additive control unit changes two native-AsyncFunction terminal blocks in
the linked QuickJS implementation. Its parent is the three-bridge source commit
7233b0a30da5866326163bbbf7f39cb745c24a9b (C SHA-256
62C055EEE7D3175A91CD847E3D52279529B85CB1663D52970D7283694A4ACA10).

## Actual source operation

In that exact C source, async_func_init places arguments before local variables
in the suspended frame. async_func_free closes any attached variable references,
frees arg_buf through cur_sp in ascending order, then releases cur_func,
receiver, and this_val. The function finalizer releases its closed captures
before its bytecode; therefore a separate capture holder can retire between the
local holder and the call receiver.

The native path previously released native_state and native_this before
native_argv. Both js_native_async_retire and the native branch of
js_async_function_terminate now release:

1. Argument values in argument order.
2. The native body state.
3. The native function, including its capture owner.
4. The retained effective this value.

The active terminal path still detaches all owned fields before the first
release and still reduces actual pending exceptions before and after every
release. Capability resolution, intrinsic Await/adoption, action payload
handling, cancellation checks and the raw finalization policy are unchanged.

## Authored causal controls

Target: build-native-vm-async-retirement.
Root: src/native_async_frame_retirement_test.zig.
Filter: VM async retirement.

Seven declared controls exercise actual linked-C operations:

- A literal Source async function and a real native async function suspend once,
  then retire two argument holders, one local holder, one captured holder and
  the receiver in the same order.
- The actual return-adoption then getter observes all five holders still alive.
- Ordinary rejection preserves reason identity during ordered retirement.
- Dropping the sole real awaited Promise releases its reactions and invokes
  termination of the abandoned coroutine, without depending on GC visitation
  order or settling the distinct outer Promise.
- Actual C finalizer pending events select the first argument-cleanup fatal over
  a later local-cleanup fatal after capability settlement.
- A preexisting current fatal prevents the resumed body and dominates cleanup.
- A real native OutOfMemory producer in the resumed body preserves its marked,
  generation-bearing identity through later argument and local cleanup.

The last three are direct pending-owner controls; they do not claim that merely
marking arbitrary DATA is an allocator producer. The body-allocation case uses
Engine.throwNativeOutOfMemoryFatal. Each Source/native comparison uses a fresh
Engine and actual C sole-holder finalizers. The unit has not been compiled or
executed by its author. Actual metadata, native execution and the existing AF
fatal/adoption/cancellation regression group require Root's separate grant.

## Explicit limits

This changes the order of roots actually owned by the VM. A body that releases
its own lexical locals before returning its final Action has a separate earlier
retirement problem; this C reordering cannot recover those released values.
The terminal-order commit did not retain an async arrow's ignored supplied
call receiver. The separate ownership successor below addresses that concrete
root; it does not change bodies that close their own locals too early.

The vendor change requires fresh compilation and qualification. Earlier BCDF
diagnostic-cache lineage and earlier artifact/runtime receipts do not qualify
this source.

## Separate call-site receiver ownership successor

Parent: 3892188c1f9806e40ba4ea5fde49127d24e9cfa4 (C SHA-256
8553C79A6CF93CCE446A6C3C33C73619FD199FF3E6C438350823B121512EB63D).

The actual bytecode async_func_init retains the supplied call-site receiver in
both frame.receiver and this_val. An arrow reads its lexical this from a closed
variable reference, while the supplied receiver is still retained by the
coroutine. The native body path previously kept only the effective lexical this.

The private native_receiver field now independently retains that supplied
receiver before the first fallible Promise allocation, participates in the
coroutine GC mark, and supplies the real running stack frame's receiver.
native_this remains the effective receiver passed to the body. Native bodies
are strict, so this new call-site root is a duplicate without boxing or a guest
operation. Both terminal paths release it after the function/capture owner and
effective this; the active path detaches it before any release and uses the
existing actual-pending reduction for its retirement.

Two additional controls in the same install-only target bring the declaration
count to nine. An ordinary factory supplies lexical-this holder 5 and captures
holder 3, then the returned real async arrow is called with distinct supplied
receiver holder 4 and argument holders 0 and 1. Its native body state owns local
holder 2 through settlement. Literal Source and native cases both check:

- All six holders survive the real Await and the return-adoption then getter;
  the resumed body receives holder 5 as lexical this.
- Arguments and the local retire before captures and lexical this, while the
  ignored supplied receiver retires last.
- Dropping the sole actual awaited Promise also releases the ignored receiver
  through the real abandoned-coroutine termination path.

The completed case additionally invokes the actual runtime GC while suspended.
The test's fixed capture-before-this order follows its literal body reference
order; it does not claim that all possible closure capture graphs share one
order. The generic Source/native controls retain the same five-holder behavior
and the unused sixth slot remains uncreated. No author-side native execution
or runtime qualification is claimed by this source successor.


## Optional terminal state-close hook

The following separate source unit adds an opt-in borrowed-state close callback.
Existing native async factories without a callback keep their prior terminal
behavior. `JS_PiNewNativeAsyncFunctionWithClose` records the callback on the
actual function bytecode and each genuine invocation. The active terminal owner
detaches it before any root retirement, invokes it after capability settlement
and ordered argument retirement, then releases state, function/captures,
effective this, supplied receiver and resolving functions. Hook-enabled
abandonment uses the same pending-exception reducer and detachment. A callback
failure cannot bypass the remaining releases; first actual fatal precedence is
unchanged.

The Zig `createResumableWithClose` and `createResumableArrowWithClose` factories
supply a cleanup trampoline which does not reject cleanup merely because an
actual fatal is already selected. `Frame.closeAtAsyncTerminal` is the concrete
adapter: it closes binding cells while preserving their captured values, retires
the original local slots, and skips a GC-zombie state/cell before opaque access.
The callback consumes no state reference and performs no guest operations.

Five additional declarations in `native_async_frame_retirement_test.zig` use the
existing install-only `build-native-vm-async-retirement` group. Actual literal
Source and native cases test final adoption before close, ordinary and arrow
receivers, escaped callbacks retaining only their closed captured binding, and
reference-driven abandoned Await with no escaped cells. Native causal controls
cover argument/local fatal precedence, preexisting fatal cleanup, and an actual
failed close that must still retire the state and receiver. The prior nine
declarations are unchanged.

This unit does not claim that an open native binding cell already retains the
actual suspended coroutine. That distinct owner edge, including real cyclic-GC
controls, is the authorized dependent implementation. No compiler, metadata or
runtime acceptance is asserted by this source note.
