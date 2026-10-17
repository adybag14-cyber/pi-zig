# Actual ordinary frontend import-fallback correction — source only

This is a separate finite successor to source-closed65c and canonical363479d8.
It corrects only private eval_frontend.importFallback and adds its actual-subject
controls. The original Source eval.ts and all old expected/capture/proof bytes
remain intact. No shared ModuleCallable/AF/Engine/C policy or default selection
changes, no Node/generator/formatter/AST/compiler/native jobs are made.

The original65c ordinary rejection arrow inspected JS_IsUncatchableError on
its rejected argument and rethrew it as a current fatal. That argument is DATA;
an old hidden flag does not prove an active host exception event. It can be a
historical ordinary rejection even when a current allocation counter changed
for a different reason. Root explicitly kept this whole-frontend parity blocker
open; earlier source review was not runtime or full frontend qualification.

## Local ordinary-callback boundary

The private callback is still created by the actual native ModuleCallable
trampoline, which balances diagnostic suppression BEFORE callback/catch/failure.
The exact source of that helper is retained as authority; no second public
entry or fake callback calls the native body directly.

At each invocation it moves prior captured_exception ownership into a local
and empties the Engine slot. It restores the prior only when no current capture
remains, otherwise frees that prior reference. A newly thrown SAME old object
is a new capture; pointer inequality is never used to prove an event.

Before scope/root/input work, an actual pending VM event is captured and
propagated unchanged. No assumption that C2 callback entry has an empty VM slot
is made. Inner failures can only use a new capture or normalize an actual still-
pending event. If neither exists for a JSException, explicit Missing... fails
closed rather than consulting the restored old diagnostic slot. Actual current
fatal and current-generation private allocation checks precede ordinary flow.

The unchanged Source fallback body then reads its private saved operation
generation and tests the rejected DATA's fresh private allocation cause first.
Only when that check returns does it clear the DATA's historical hidden flag.
Its debug calls, original ctx/source/options captures, option spread with
forceTranspile=true, exact self identity/receiver and raw return all stay in
their original order. No error-name checks, manual Promise/Await, extra Promise
or unconditional throw simplify the actual fallback continuation.

This differs deliberately from the native AF import leaf: this is an ordinary
Source arrow, so current JS failure stays captured for its real trampoline;
success returns the exact raw evalModule result. No Action.thrown/adoption is
invented. Other frontend/native/sync branches are unchanged.

## Genuine causal controls

`original-input.mjs` observes the real completed actualJiti.evalModule call's
actual Promise.catch registration while delegating to the genuine original
catch. Real imports, require, core, Module, cache, transform orchestration and
self are never replaced. Driver first drains the real successful import of an
owned physical valid module, leaving the actual captured rejection callback.
The controls call that exact callback, avoiding unrelated earlier `.then`
missing-reject propagation that could fatalize flagged data before this target.
Source reference must capture the same actual arrow from original unchanged
jiti2.7/eval.ts, not extract/clone its implementation.

Five controls plus explicit native fault-probe installation are prepared:

1. Historical tagged/flagged data performs real fallback and returns the exact
   user-observed raw Source-tail result. Original Promise.then is called and
   its real completion retained while the legal user hook returns a raw marker;
   no native wrapper may replace that identity with another Promise.
2. After capture, an original enumerable user option getter throws the SAME
   ordinary reason held in a prior diagnostic slot during actual Source spread.
   New captured ownership preserves same-identity ordinary throw, no fatal flag
   and no diagnostic getter coercion. This is not an object-inequality test.
3. The actual Source option getter invokes Engine.throwNativeOutOfMemory through
   an explicit native-only fault probe. Exact fresh private cause/current reason
   escapes as fatal instead of Source fallback success or old-data escalation.
4. A genuine pending non-OOM VM event before actual callback invocation wins
   with exact identity before private roots/data flag/debug/spread; old DATA's
   flag and extra-getter counter remain untouched.
5. Another original getter triggers the actual installed Engine cancellation/
   interrupt handler through a real guest loop. Its current non-OOM fatal is
   preserved independently of input data or allocation tag; cancellation is
   restored by the owned driver.

Raw JS_Call/JS_GetException observations exclude outer test-host diagnostics,
so zero reason.toString reads measures the actual callback capture/catch path.
Each case requires a fresh actual completed Subject/owned physical filename
and exact original options object; faults are installed only after real callback
capture. The native allocation reason used as historical data must be born
BEFORE capture's saved generation, never synthesized with a guest field/name.
Native fault/interrupt cases do not manufacture Node expected failures.

All controls are UNRUN and expected is absent. Full actual subject, queued
import/nativeImportOrRequire declaration wrapper, public factory/default native
transformer/resolver/profile and native class/factory qualification remain
separate requirements. This finite patch does not claim them complete.
