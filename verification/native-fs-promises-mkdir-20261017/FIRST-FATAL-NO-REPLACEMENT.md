# Do not synthesize a second OOM after an owned fatal

Finite source-only successor to5472 review. record(error.OutOfMemory) now keeps
an already escrowed actual fatal when no new pending/captured value exists,
instead of manufacturing another OOM and then discarding it. Current slots are
still snapshotted/drained and cleaned; first-fatal priority is unchanged.

The actual failing-allocator callback control already produces fatal B and
captures it into the newly isolated slot while returning a cleanup object. That
same causal control now propagates a raw OutOfMemory tag after value() has moved
B into escrow, and requires the native allocation generation to remain unchanged
before exact final identity is checked. No replacement OOM C is permitted.

Only the owned-exit helper product file changes. The worker, module/AF,
completion/resolver lifetime and all earlier evidence remain unchanged.
Controls remain UNRUN, with no Main/Engine/Hub/shared C/H or jobs modified.
