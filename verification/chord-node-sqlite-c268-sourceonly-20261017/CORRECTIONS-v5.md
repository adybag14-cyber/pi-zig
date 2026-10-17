# Current cleanup fatal before replacement OOM v5

This separately sealed successor preserves v4. Independent reviewers confirmed
a residual path: a real host allocator error can unwind a Scope whose finalizer
captures a new actual fatal B. The callback's error.OutOfMemory branch previously
ignored the newly captured reason and synthesized C before selecting B.

The one-line product correction selects that newly produced current fatal after
actual pending and before synthesizing a replacement. The prior diagnostic was
detached before the operation and is never a candidate; neither rejected Await
DATA nor historical flags are scanned. It does not materialize a new OOM earlier
in every Scope or change shared policy. The first actual owned fatal B survives.

The eleventh additive declaration arms the actual FailingAllocator only after a
Scope owns the sole native-finalizer object reference, performs an actual failing
GPA allocation and unwinds that object. Its real raw native-OOM finalizer produces
B. The control requires B's exact identity and only one native generation advance,
so replacing B with another OOM is detected. The first ten controls, four additive
original caller observations, original four tests and original 25 observations
remain unchanged. No job, output, expected data, compilation or qualification is
implied; actual metadata is still unknown. Previous scope limitations apply.
