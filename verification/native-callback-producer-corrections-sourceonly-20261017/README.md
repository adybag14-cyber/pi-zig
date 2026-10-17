# Current-event retention / reentrant diagnostic corrective successor

Parent e39677392982aace92ebfaedd45ef152b6897640 is preserved as the exact
independent SOURCE negative (Google4AFA2027). No jobs or Main/C/H changes.
Root specifically approved one private Engine pointer for a stack-linked
per-native-invocation current-event retention boundary after concrete G1.

G1: actual Node new receiver cleanup could overwrite captured fatal A with B on
an ERROR exit; direct GPA failure followed by Scope cleanup capturing fatal B
could then synthesize replacement OOM C. Success-only pending normalization did
not protect these paths. The new NativeInvocation boundary owns first actual
fatal by allocation-free JS_DupValue. Events enter only through trusted direct
OOM birth, actual pending take, or actual fatal captureException. PromiseResult
DATA, old diagnostic values and ordinary caught reasons cannot record events.
Nested invocations inherit the existing actual first event. Same-object actual
new throw can record, irrespective of its prior DATA identity.

Ordinary Node/class calls and genuine native AF/AG step callbacks enter the
boundary and leave on all result/error paths. Capture/root/receiver cleanup can
update mutable pending/captured fields without replacing first actual reason.
Trusted failure exits consult the live event before synthesizing new OOM. The
recorded first reason also survives an inner legacy host error-union operation
clearing its flag: restoring this explicitly recorded actual event is distinct
from inferring authority from DATA's bit/tag. Existing per-executor holders remain.

Leave detaches the Engine pointer BEFORE holder reference release and before
returning any Await/yield/result. The selected owned reason survives cleanup
outside mutable slots. No stack pointer is retained by a suspended invocation;
no allocation is used for event recording. Holder unwind is idempotent; entry
asserts a fresh holder and Engine deinit asserts no live invocation. Engine init
has only a default-null pointer, no new owned allocation/initialization resource.
No Context/C API/ordinary function metadata or heap plan/provenance changes.

G2: an old captured object's native finalizer can reenter engine.checked, creating
both another captured value and an owned last_error string. The old one-time
message clear leaked or retained the nested string. Capture now drains actual
pending, captured ownership and message ownership together, detaching each before
release, and only then commits its selected reason/current diagnostic text.

Six additive real VM declarations (producer suite14; aggregate30), all UNRUN:

- Real generic native function NEW receiver and class callback internal receiver
  have sole-owned finalizer tokens. Current captured fatal A survives ordinary
  and fatal B emitted by error unwinding. No old-slot flag priority is used.
- Genuine armed GPA failure occurs after receiver/token setup; cleanup performs
  current checked fatal capture B. It exits exact B with no new OOM generation C.
- Marked rejected DATA capture while a boundary is active records nothing. An
  actual new throw of the same object records the current event and exits fatal.
- Only the holder retains the current Error across real GC; unwind pops cleanly
  and a genuine AF Await/resume leaves no live stack pointer. Repeat cleanup
  does not release the holder twice.
- Reentrant native finalizer calls actual Engine.checked, producing a distinct
  nested diagnostic. Fatal outer clears it; ordinary outer preserves its own
  text. std.testing.allocator detects nested diagnostic leakage.
- Existing actual private OOM converted by legacy host union recovery still
  exits the recorded same object/generation, without a synthesized replacement.
  This is a transport-identity control, separate from real GPA failure coverage.

The eight previous e396 controls and all older source packets/results/fixtures
are unchanged except the additive shared control-file code. The wrong old
source assertions stay immutable historical negatives, not new goldens.
The generator wrapper's producer retention does NOT compose the separately
pending C3 generator producer-exit correction. C3 Promise constructor consumed
executor event/extra guest work remains a separate VM frontier; retention is not
a claim to undo guest work performed by a C intrinsic after it consumed an event.
VM emergency OOM representation/allocator-stage qualification, foreign-thread
access, wholeSDK/Agent/default activation remain unqualified.

No compiler/AST/parser/native/Node/generator command has run. This successor
requires exact independent re-review; no source/runtime closure is inferred.
