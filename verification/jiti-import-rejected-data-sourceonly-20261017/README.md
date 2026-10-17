# Local one-Await import revision2 — source only

This corrects the original reviewed926 native_jiti_import leaf before Root
intake. Its old exact bytes/review are retained unmodified. Original Source
jiti2.7 jiti.ts import method remains one real Await followed by the original
default selection; no extra Promise, thenable runner or shared AF policy is
introduced. No C/H, Engine, native_async_function/body or Main file is edited.

C2's `.thrown` action calls JS_Throw(output), which preserves an Error's hidden
uncatchable flag; native resume then tests the actual pending exception flag.
Therefore simply removing the old rejected-input flag test is insufficient.
An old flagged rejected DATA value would otherwise still become fatal at that
handoff. Its old flag is not evidence of a current host exception event.

On every local callback invocation, prior captured_exception ownership moves
to a local and the Engine slot becomes empty. Defer restores the prior capture
only if no current capture remains, otherwise frees that old owned reference.
A newly thrown SAME old object is a new capture, so pointer inequality is not
used as an event heuristic. The selected61C4 AF trampoline suppresses diagnostic
formatting before this private body callback, including its catch/fail path.

Before any scope, guest operation or input flag clear, an actual pending VM
exception is captured and propagated. This is necessary: C2 ExecutePendingJob
calls its execution-context hook before the reaction handler, and native step
does not guarantee that callback entry has an empty VM exception slot. A hook
or actual deferred interrupt can leave an active non-OOM fatal whose private
OOM tag is zero or predates this invocation. That event takes precedence over
all input DATA classification.

Ordinary inner JS failures may only use the new current-invocation capture.
A still-pending actual event is normalized without formatting; if neither new
capture nor pending event exists, an explicit Missing... internal error fails
closed rather than classifying a restored old diagnostic capture. Actual current
captured fatal and fresh private allocation handling stay separate from DATA.

At rejected completion, the saved START-generation fresh private allocation
check runs first. If it returns normally, and after the entry event guard, the
local historical flag is cleared before returning owned `.thrown` with the
SAME raw input identity. No Source property/getter or error name is consulted.

## Mandatory prepared controls

The actual user fixture creates a real cached Module exporting an intrinsic
pending Promise and exposes its actual executor resolve/reject functions.
The actual reviewed jitiRequire takes its real cache-hit branch, returning that
same exports Promise with interopDefault=false/tryNative=false. This reaches
the real one-Await callback directly. A dynamic-import path would add an earlier
`.then(success)` whose missing reject handler can fatalize old flagged data
before this target leaf; that is a separate C2 boundary, not a valid substitute
for this control. No fake require/importer/Module/cache is accepted as Subject.

Five causal controls (plus the explicit fault-probe installer) are prepared:

1. A genuine old Error/private tag exists before START, with a hidden old flag.
   Intrinsic reject delivers it as DATA; outer Promise rejects with same identity,
   no fatal job, no pending exception or diagnostic getter, historical flag cleared.
2. A non-enumerable Source options.default getter rethrows the SAME ordinary
   object held in the old diagnostic slot after fulfillment. New capture ownership
   produces the ordinary same-identity rejection and restores prior diagnostics.
3. A resumed Source getter invokes an explicit native fault probe that calls the
   actual Engine.throwNativeOutOfMemory. Exact fresh identity/generation escapes
   as a terminal owner/job fatal; outer Promise is not spuriously rejected/succeeded.
4. A scoped raw execution-context hook installs an actual pending non-OOM host
   fatal before the real rejection callback. That event wins with same identity
   and old DATA flag untouched, proving guard-before-clear ordering.
5. A separate hook triggers the genuine installed Engine interrupt handler with
   cancellation and an actual guest loop, then resets cancellation while retaining
   that real pending event. Non-OOM fatal identity wins, old DATA untouched, no
   new allocation tag/generation. No synthetic Error-name interrupt substitutes.

Raw hook controls require their OWN exclusive fresh Engine.init realm before
any application hook/owner is installed and an otherwise empty job queue. They
do not overwrite another owner's runtime hook. Tests consume terminal exceptions
directly to avoid conflating outer diagnostic formatting with native-body
formatting. Actual completed graph subjects, reviewed C2 integration and a native
resource grant remain prerequisites. Original user inputs and Node/reference
observations are prepared only; no output/expected is fabricated or written.

Review65c/f9c source and protected historical manifests are retained as their
immutable source-head proofs. This intentional one-leaf followup supersedes
only the old import product, not those historical observations. It does not
complete the private canonical require/eval bootstrap or public factory/default SDK.
