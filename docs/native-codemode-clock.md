# Deterministic native CodeMode context

The optional Engine clock applies to one C runtime. Ordinary extension contexts
keep their existing host clocks and timezone. This is a context component;
public CodeMode start, host-driven delivery, fingerprints and durable replay
remain separate implementation requirements.

Clock input follows upstream `04566631c2b51fb688486bc1f040f60d1518c126`:
finite nonnegative start time and an integer unsigned 32-bit seed. Delivered
finite time cannot move virtual time backwards. Conversion preserves the actual
upstream WASI sequence: Math.round, exact integer conversion, multiplication to
nanoseconds and unsigned 64-bit wrapping. Huge finite inputs never undergo an
out-of-range native integer cast. The Date clock truncates to milliseconds;
performance uses the elapsed clock and starts with timeOrigin zero.

The narrow C APIs are host-only. Configuration must precede context creation;
attempting to reseed an existing context fails without mutation. Advance rejects
an ordinary runtime and nonfinite or out-of-range normalized clock values.
Runtime fields own the clock, UTC timezone and seed. No global timezone or
process environment is changed. Math.random uses the genuine QuickJS 0.17.0
generator, seeded at context creation exactly as the upstream WASI clock seeds
it. Date constructors, getters, setters and formatting keep their native C
implementation with an explicit context timezone.

The original current-upstream host and actual WASM produced 48 immutable clock
observations, including fractional boundaries, seed zero and maximum, huge
finite times, WASI wrapping, UTC dates and elapsed time. A default Node module
load observer verified all 12 loaded files against the full frozen 27,153-file
reference input set; all postchecks were unchanged. The fixture preserves actual
runtime output, including the ISO date representation without `.000`.

Windows Debug native qualification passed 8/8 actual tests: all 48 complete
context-value comparisons, two concurrent independent runtimes, invalid input
and late reseeding controls, exhaustive owner-allocation failure cleanup, the
clock arithmetic comparisons, and an explicit compiled inventory. All 3,985
candidate source and 19,546 Zig 0.16.0 tool files were unchanged. The initial
300-second cold dependency compilation timeout is preserved separately. A
compile-only step completed the exact test artifact before the unchanged
120-second per-test / 300-second runtime job; no runtime budget was raised.

Windows Debug Root integration passed 198/198 tests: 135 shared cases, eight
clock cases and the 55 retained UI cases. Independent compiled coverage and all
3,992 source / 19,546 tool input postchecks passed. The interrupted preceding
job had no terminal output and remains explicitly unqualified.

Cross-platform/ReleaseSafe qualification, intrinsic omission
for WeakRef/FinalizationRegistry in the sandbox, and complete deterministic run
lifecycle are not implied by this component result.
