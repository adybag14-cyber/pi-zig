# Actual guest exception boundary correction

The selected Response OOM gate's original233-allocation sequence and its
offset232 negative are retained. Exact first-failure tracing on tested
`2a6adb26cdffa6f87b53583c02b701c62014c009` proves offset232 is the best-effort
diagnostic string copy in `Engine.captureValue`, reached while the guest handles
the expected immutable Headers TypeError. The native generation/tag remain0,
the original exception reaches the guest catch, the operation succeeds and all
host bytes are released. That diagnostic allocation is not a semantic native
OOM and is not reclassified as one. The strict OOM assertion correctly remained
negative in that historical test.

The trace also exposes a separate actual compatibility issue: formatting inside
the native Headers or Response boundary calls guest error `toString` before
the guest catch can receive the thrown value. This is observable user code and
can even invoke a guest GC hook. Existing Engine diagnostics suppression already
provides the required identity-preserving boundary; Engine.captureValue's
best-effort behavior is unchanged.

Headers owner source `938ecaff30ca2f66576c2ddef72b0000d958e9ae`, intaken as
`c3e7b435`, adds narrow suppression spans to callback/create/ordinary and the
fromRecord/convertInit outer-capture routes, plus a genuine thrown marker,
TypeError.toString and GC-hook regression. This new Header source is separate
from the immutable qualified2d checkpoint.

Response create/callback/fromTransport now use the same existing span. The
new actual regression preserves thrown object identity from ResponseInit
getters and explicit BodyInit string conversion, distinguishes required body
coercion from forbidden diagnostic coercion, and checks async brand rejection
without calling an overridden TypeError.toString before the guest catch.

The strict selected OOM requirement remains `error.OutOfMemory` for all five
measured critical operation probes. No offset is skipped, no success or
unsettled promise is accepted as OOM, and no expected Source189/114 row is
rewritten. Removing the product's premature formatting naturally changes its
host allocation count; the historical233/232 evidence remains explicit.

Root approved the six-target successor: the prior five Response/byte/tee targets
plus unchanged genuine Headers189 and its native identity/ownership controls.
Fresh matching compile/fullpost precedes every runtime. The normal resource
and complete frozen-input contract is retained, with Headers189's exact original
packet/input/bundled authority added. This candidate note asserts no new passes.
