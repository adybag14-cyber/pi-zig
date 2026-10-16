# Shared thenable fatal source candidate over E334

Root authorized source-only implementation of independently reviewed design
1ECEEF3A458D4B6C7E5BB2A053404C99C43BD9A7B20D7A785888B512C479F3A2.
This is a separate candidate from E334, C409 and F06. Their historical source,
controls, proofs and negatives retain their original identities. No compiler,
formatter, Node, Source generator or native runtime job ran for this candidate.

## Product scope

Only vendor/quickjs/quickjs.c changes: 34 additions and one deletion, confined
to js_promise_resolve_function_call and js_promise_resolve_thenable_job.
Header, Engine, Promise state representation, serialization, generation tags,
module attribution and context ownership are unchanged.

The getter helper checks for an actually pending uncatchable reason immediately
after reading resolution.then, before ordinary rejection conversion. It holds
that exact reason over freeing its owned getter result, then returns it as
JS_EXCEPTION. An ordinary raw/historical/lookalike getter error keeps the old
ordinary rejected-Promise behavior.

The deferred job initializes owned result/args with undefined. A pending fatal
after BEFORE stops then and AFTER. Once then was invoked, the job keeps the
paired AFTER notification and re-reads the currently configured callback/opaque
as before. If then left an active fatal, an allocation-free owned duplicate
retains it BEFORE AFTER, while current_exception remains visible to the hook.
A later hook failure or cleanup cannot replace that first owned reason. A new
AFTER fatal is captured only when no earlier fatal was retained. The fatal
cleanup frees the owned result and two resolving functions exactly once and
returns the same first reason via JS_Throw, without rejection conversion.

No guard interprets a supplied value's uncatchable bit/name/tag as an active
operation failure. Every new branch uses JS_HasException and the actual current
exception. No-native-fatal paths retain existing ordinary/catchable behavior.

The job context remains a raw pointer under the existing host lifetime rule;
no new ctx pin or inferred owner is introduced. Engine keeps its own main
context alive through the pump. The borrowed job argv and owned local values
follow existing C API ownership, with the fatal value retained over all local
cleanup. Broader host cancellation/lifetime guarantees are not claimed.

## Prepared controls: eight declarations, all unexecuted

The new standalone src/native_shared_thenable_fatal_test.zig prepares:

1. Fatal getter at direct native START and resumed native return: exact fresh
   host reason and actual negative return/job status.
2. Deferred fatal then call after normal native return, GC before execution,
   paired BEFORE/AFTER notifications and exact active failure delivery.
3. BEFORE fatal skips body/AFTER; AFTER fatal follows normal body invocation.
4. First then fatal versus a distinct AFTER fatal: the hook sees the original
   current reason, the first identity survives, and private classification at
   the original boundary survives a later native generation.
5. Ordinary raw, cleared historical native and named lookalike getter/then
   throws remain exact rejection values and do not become a fresh native OOM.
6. Error values carrying an uncatchable flag, but with no pending exception,
   remain ordinary rejection data through reject(value) and rejected-Promise
   adoption. This explicitly tests against inference from data alone.
7. Normal BEFORE/then/AFTER ordering, hook replacement/removal, and the new
   replacement opaque's explicit identity. These exercise the actual public
   JS_SetPromiseHook API.
8. A queued ordinary foreign callable remains valid through GC after the host
   releases its foreign context and removes its function from the thenable
   property. The queued callable/bytecode realm supplies its existing foreign
   root; the main job context remains explicitly host-owned.

The harness owns unexpected raw results and pending exceptions before fatal
assertions. Normal pumps record whether an exception was actually pending
before taking its value; JS_GetException's no-exception sentinel is not treated
as a null/error value. No extra Promise or job is introduced to inspect failure.

The prepared snippet is separate from shared build.zig. Actual metadata must
discover all selected/imported mandatory tests before execution; the eight
source declarations do not substitute for that capture. Tests have not been
syntax-checked or run, and no resource/allocation position success is claimed.

## Explicit remaining edges

Catchable enqueue/adoption allocation pressure is unchanged and does not gain
private native fatal classification. General Promise helper failure outside
these getter/then/public-hook boundaries remains separate. In particular, a
host rejection tracker leaving a new pending fatal during the deferred job's
ordinary-error-to-rejection conversion is not included in this design's new
boundaries; a separate control/direction is needed before widening the claim.
Likewise this patch does not attribute nested ordinary async jobs to modules.

Independent async C review of the sealed complete implementation is required
before Root composition or any native execution grant. No whole-AF/core or
application qualification follows from source review alone.
