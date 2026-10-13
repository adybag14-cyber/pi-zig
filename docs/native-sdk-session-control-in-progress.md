# Native session control and shared AI cleanup

Implementation 4a965b8b1f6ebbb72480ccee0e763204fb0949cc ports 19 ordinary
AgentSession idle, cancellation, disposal, queue-mode, settings and transcript
control methods, plus the shared pi-ai resource cleanup registry. Registry
functions preserve ordinary construction, live Set iteration, unregistering
and AggregateError identities. Native callbacks retain raw thrown values until
the actual VM catch or final host boundary; they do not call guest toString
prematurely from inside cleanup or disposal catches.

The e6220e1 fixture uses 35 genuine upstream factory sessions. It covers shared
idle promises and the ambient Promise constructor, live callback order, actual
Agent queues, cancellation and disposal, settings, real transcript projection,
original method/function descriptors, cleanup iteration/errors and two explicit
no-toString cases. Unexpected TypeErrors reject capture; only the deliberately
false abort controller observes the engine's TypeError category. Full original
1945-source/31064-runtime/1774-Node posthashes show zero drift.

Windows Debug and ReleaseSafe each passed all 12 selected tests, including the
complete 35-case comparator, explicit collection and both full native allocation
failure sweeps. The unchanged existing settings ownership suite also passed
10/10 in Debug, including real file merge and lock cleanup. All 4821 committed
input blobs match the ReleaseSafe snapshot; native source and 19546 compiler
file posthashes show zero drift. Runtime guards remain 120 seconds per test,
10000 ms host awaits and 300 seconds outer. Cold compilation is separately
bounded at 1320 seconds per artifact.

Preserved negatives explain the fixes: the first caller left its fake compaction
owners active; initial Debug finished 10/12 due to swallowed native allocation
failures; the narrowed Source35 run finished 11/12 and traced index376 to queued
settings persistence. Fresh privately tagged native allocator errors now keep
that queue rejected for flush instead of being recorded as ordinary storage
errors. Ordinary errors and older thrown identities retain their existing
handling. The allocation probe awaits the actual settings flush so every queued
operation belongs to its verified ownership graph. Original expectations and
deadlines were retained throughout. Low-memory admission failures are recorded
separately from test outcomes.

The private Windows/Linux/macOS candidate includes both the 12-test control
artifact and unchanged 10-test settings ownership regression in Debug and
ReleaseSafe. Hosted qualification of this complete head remains pending.
Automatic provider cleanup integration, complete session/runtime assembly,
successful full model runs and complete Pi parity still need validation.
No partial public factory activation or compatibility-bridge removal occurs.
