# Source20 raw Google wire ordering

The original Source20 runtime on 28c434c288d57f17c92136f2aff0b82526a4e2ec
compiled and exposed exactly nine tests. Five passed and four failed with full
zero-drift inventories. The first Source12 functional failure was a raw wire
byte comparison: the pinned SDK wrote each contents entry as parts then role,
while the native request reused the payload-hook object ordered role then parts.
The raw comparison remains unchanged; JSON canonicalization is not substituted.

The pinned SDK's contentToMldev$1 and contentToVertex$1 read and emit parts before
role. Native wire conversion now maps contents with that read/write order,
without reordering the actual onPayload objects. Parts remain the original live
values in this narrow repair; broader SDK part/schema conversion is not newly
qualified. Original75 and Source20 snapshots, wire expectations and fixtures
remain unchanged. This successor is source-only until a fresh admitted pair.

The remaining Source20 strict negatives include durationMs appearing too early
in mistral-trailing-event text_start, and durationMs/errorMessage/aborted state
appearing too early in custom abort-after-chunk text_start. The complete custom
request/reader allocation graph also failed and still needs exact failing-index
diagnostics. Custom-fetch functional/getter/reader, retained-GC and pending-GC
controls passed. Neither full Source30 nor full Source20 is qualified.
