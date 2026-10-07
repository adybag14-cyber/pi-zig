# Native environment checkpoint

This is an in-progress port of Pi protocol v1 and its local daemon/client. It
does not certify complete ExecutionEnv, SSH, watch or release parity.

Implemented native surfaces include bounded big-endian framing and fragmented
sync, owned JSON/payload records, connection-local retained file/directory and
write handles, scanLines, regular and whole-file reads, sequential/platform
cursor behavior, chunked writes with poisoned-handle failure, metadata identity,
directory paging/raw invalid-name bytes, local framed execution, original abort
versus kill distinction, stdin byte liveness and periodic pings. Filesystem
error codes and paths are carried in protocol replies; complete Node error-text
equivalence is not claimed.

The writer owns stdout. Small replies/pings have priority over bulk data;
command output and its terminal reply remain in one FIFO. Unwindowed output
waits above four MiB queued bulk data. Queues also have finite record and encoded
byte budgets. Actual paused-reader tests prove priority replies and cancellation
with a 64 MiB producer. Slow-link unsent-window coalescing remains incomplete.

Windows command and daemon lifetimes are distinct. Ordinary completed commands
can leave detached descendants, matching an independent original daemon capture.
The daemon's libuv-style job and a separate per-command job policy preserve that
behavior. Active cancellation selects an owned process handle/PID and its tree,
with a duplicated handle guarding concurrent Child.wait teardown. Generic local
Shell job policy remains unchanged. POSIX commands use separate process groups;
the original daemon tracks commands it has not reaped rather than completed
background groups.

The native client has one persistent reader, concurrent ticket routing, owned
ordered event/result records, broadcast-event retention, finite reply budgets,
heartbeat/start/silence bounds and session-fenced handles. A lazy factory starts
nothing at construction, reruns preparation after start failure or connection
loss, rejects old-session handle operations and stops retired processes while
preserving outstanding ticket records. Callers release tickets before destroying
their connection. The factory retains at most 64 failed session objects.

SSH helpers implement strict private trust arguments, platform-output parsing,
bounded simultaneous stdout/stderr/upload, and verified content-addressed
deployment commands with atomic replacement and upload markers. These helpers
have captured-source and local process/filesystem proof. Actual strict-key SSH
detection, verified upload/start and repeated verification have now crossed a
task-owned loopback OpenSSH server with a private home. Unknown/changed keys are
rejected before platform fallback. The lazy SSH factory starts nothing at
construction, caches successful platform detection, reports warnings once and
verifies/deploys on each restart. An eager verification is consumed once by the
next start. Actual Linux strict-key reconnect tests tamper with the remote
binary and prove verified replacement before a new framed session. Twenty
original launch-command captures cover POSIX/login-shell and CMD/PowerShell
quoting. Explicit target-specific daemon bytes are supplied by the caller.
Windows SSH server deployment, host-key scan/accept file management,
and packaged cross-platform distribution remain
subsequent work. A local PowerShell upload without EOF is not presented as actual
Windows SSH proof.

The native RemoteExecutionEnv adapter now exposes remote-system path resolution,
owned file and command failures, binary and text whole-file reads, retained
binary/line/directory readers, line scanning, depth-eight chunk reads and writes,
metadata/listing, mutations, temporary resources and a command facade with
output callbacks, timeout validation, abort/callback precedence and owned kill
cleanup. It borrows either the existing native connection or its lazy factory;
it does not own transport destruction. Readers are released before their env.
The caller provides UTF-8 bytes for text writes and a stable borrowed shellEnv.
Expected daemon failures preserve their message/path after reply-frame release;
error deinit is idempotent and borrowed local messages remain borrowed.

Latest original class captures select both platform path rules and verify actual
file/command behavior against a separately built original Rust daemon. Rooted
win32 inputs preserve an upstream implementation quirk: its no-base resolve
uses the caller's ambient process drive. The native resolver receives ambient
cwd explicitly; it does not substitute the remote cwd for that source behavior.
Durable now exposes borrowed FileSystem/ExecutionEnv capabilities over local or
remote providers. Binary, line and directory readers own their boxed leases;
watchers own their subscription wrappers. Provider, allocator and I/O lifetimes
outlive those leases. Generic bounded reads and Harness bindings use the same
facade, and mutable cwd forwards to its provider without changing its namespace.
Actual local and remote read/write/edit/bash registrations cross retained
registry snapshots, and every induced boxing/provider allocation failure closes
opened handles/subscriptions. Portable format-v1 durable JSONL storage now uses
this capability for local or remote persistence; its publication/recovery
boundary is described in `../durable/backend/JSONL_CONTRACT.md`.

File dispatch uses sixteen workers with a bounded queue. Registry access is
protected; admitted operations retain handle leases through concurrent close.
Chunk writes enter per-handle arrival-order lanes and failed writes poison that
handle. POSIX positional reads run concurrently; shared cursors and directory
iteration retain their own locks. Actual Linux tests occupy all sixteen slots
with FIFO opens, prove unrelated file traffic while one slot remains, release
one slot and validate FIFO bytes/EOF. Another blocked FIFO read completes after
its registry handle is closed. Polite transport EOF cancels workers blocked in
FIFO open and reaps the daemon with status zero. Unknown
operations fail with EINVAL. The
daemon version follows the validated generated catalog pin, rather than a
hardcoded version string.

Linux watch subscriptions now use an owned inotify backend. Native events only
trigger a debounced rescan and are filtered by target recursion/exclusions;
reads are not subscribed events. Snapshot differences and event paths are
reported in JavaScript UTF-16 sort order. Directory identity changes replace
their watches, and rescans cover files written before a new directory watch is
installed. Linux network/FUSE/9P file systems poll by default. Running out of
native watches switches to polling and reports overflow. The existing 100,000
snapshot-entry budget is explicit; original Node's unbounded entry count is not
claimed. Snapshot and installed-watch identity now compare device plus inode.
Actual private-namespace Linux remount captures replace a tmpfs root with the
same inode number on a different device, then prove a later write is observed.
Both the latest original Node environment and the native process pass; the
previous native implementation misses that later write in the same capture.
Windows identity uses the source daemon's volume serial and 64-bit file index,
with an owned zero-access metadata handle closed after every query. A real
rename retains identity while recreating the old name produces a distinct inode.
macOS identity is semantically cross-compiled; runtime is not claimed.

The remote watch facade owns its subscription and callback thread, waits for
ready coverage, ignores callback exceptions, cancels/settles on close and
reopens after transport loss with the original bounded reconnect delay and an
overflow notification. Actual Linux native and Windows polling file changes,
recursive installation, rename, close and session-loss tests pass both the
native daemon and independently built latest original Rust daemons. Native
constructor and remote constructor allocation-failure gates cover cleanup.
The connection's simultaneous ticket waits use a monotonic wake epoch, avoiding
reset of an event beneath another active waiter; eight actual concurrent
consumers and watch/RPC interleaving cross this boundary.

Windows uses polling by default and now supports forced native subscriptions
through owned overlapped ReadDirectoryChangesW requests. Cancellation settles
the exact request before freeing its buffer, event and directory handle. Actual
recursive UTF-8 writes, reads, exclusions and close followed by same-session
RPCs are checked against the latest original Windows daemon. Process handle
counts remain stable through every induced constructor allocation failure and
100 open/cancel/close cycles. The macOS candidate uses an aggregate FSEvents
stream with source notify FileEvents/NoDefer flags, zero latency, canonical-to-
lexical event mapping and an owned run loop. Stream stop, invalidation and release
precede context destruction. A 500 ms rescan covers stream startup and newly
installed directory coverage, matching the Node source contract. It selects
native mode by default. Its source is semantically checked, but hosted macOS
runtime qualification remains required; no runtime certification is claimed.

Independent original implementations are run outside repository implementation
sources. Reference scripts and toolchains are not runtime dependencies. Native
tests use compiled Zig peers and daemons; user-authored extension input remains
separate from host implementation language policy.
