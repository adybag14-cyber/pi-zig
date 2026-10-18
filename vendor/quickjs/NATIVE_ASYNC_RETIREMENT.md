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
The current native-arrow call-site receiver retention gap also requires its
separately authorized ownership successor. Neither is claimed fixed here.

The vendor change requires fresh compilation and qualification. Earlier BCDF
diagnostic-cache lineage and earlier artifact/runtime receipts do not qualify
this source.
