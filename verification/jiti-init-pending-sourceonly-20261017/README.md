# Finite jiti color/utility initialization event correction

This source-only successor addresses the concrete dependency frontier reported
while reviewing SharedDependencycomposer3fffb. Its outer takeSuccess check was
too late: native_jiti_colors could allocate six functions after a successful
hasColors call left an actual exception pending, and native_jiti_utils could
write its map/call later colors/allocate functions after such a color result.
Main/Engine/C/H/shared Scope/callable/AF policies and selectors are untouched.

## Actual finite changes

colors.create first preserves an actual pending entry event. Its optional-chain
WriteStream/prototype/hasColors getters and real hasColors invocation now check
the VM slot IMMEDIATELY after the actual operation, BEFORE Scope.own can allocate
or the next getter/function allocation can occur. Nullish fallback, prototype
receiver, zero arguments, truthiness and the six real formatter bodies remain.

utils.create similarly preserves an entry event. Actual imported-function and
constants getters normalize immediately before retaining/validating/writing an
owner field. All15 color callee lookups and actual callbacks normalize before
map writes, the next call or utility-function allocation. Outside constructor
initialization, the existing utility methods and catch policy are unchanged.

Each new local initializationValue helper owns JS_GetException BEFORE freeing
the guest success value, then transfers that SAME event through Engine.checked
under the existing balanced diagnostic suppression. No historical input flag,
old diagnostic slot, public name/message, fake reason or extra Promise is used.
The ordinary and fresh-private native reasons retain exact identity. The helper
does not continue effects with an active event, nor infer a new fatal from DATA.

## Actual-delegate causal controls, all prepared/unrun

native_jiti_initialization_pending_controls requires an exclusive Engine and
actual completed real TTY/fs/pathe/crypto/color inputs. It never replaces a
provider with a fake successful implementation. Raw probes delegate to the
actual hasColors/color functions with original receivers/args, retain their
actual return, THEN leave an ordinary or genuine Engine.throwNativeOutOfMemory
event pending. A real hasColors getter returns the SAME delegated method; a
real color export getter returns its SAME delegated function.

The probe arms std.testing.FailingAllocator fail_index0 only AFTER the actual
return/event. The very next host allocation would replace/delay that cause in
the old code. Correct code must produce the exact captured JS reason with ZERO
decorator allocations/no induced allocation failure. The same backing allocator
is restored BEFORE assertions/GC/teardown; all installed descriptors are restored
and the scoped probe pointer cannot escape the synchronous test lifetime.

Prepared matrix:

- hasColors getter: SAME real method returned plus pending event; real method
  must NOT run, nor may formatter allocations happen (ordinary and fresh OOM).
- hasColors call: real method completes plus pending event; no subsequent host
  allocation, exact reason, balanced diagnostics (both causes).
- each of15 actual constructor color callbacks: fault_at1..15, both causes;
  exact calls stop at that index, no later callback or allocation replaces it.
- each of6 actual imported color getters: both causes; no color callback runs
  and no owner/map write or later allocation may replace the actual event.
- actual full shared composer using the real hasColors call: both causes;
  private reservation is removed and native namespace counter remains unchanged.

Unexpected successes are explicitly owned/freed before failing assertions.
The new controls are not execution evidence. Full actual TTY/backend/platform /
Node/createRequire/wrapSafe/provider integration and owned native qualification
remain required. Original source proofs/expected files are preserved.

Eventual Root intake is ONLY these two helper files and the new controls/proof
packet. Root's newer pathe/MLLY return-try fixes, actual_length and pi_js_null
corrections must remain; no old whole-file dependency copy is part of this unit.
