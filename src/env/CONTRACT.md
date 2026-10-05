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
RemoteExecutionEnv adapters and packaged cross-platform distribution remain
subsequent work. A local PowerShell upload without EOF is not presented as actual
Windows SSH proof.

File dispatch is currently serialized. The upstream bounded file-worker pool,
per-handle concurrent admission/arrival-order lanes, robust blocking FIFO/device
operations and native watch subscription implementation remain pending. Unknown
operations fail with EINVAL; forced native watch is not silently emulated. The
daemon version follows the validated generated catalog pin, rather than a
hardcoded version string.

Independent original implementations are run outside repository implementation
sources. Reference scripts and toolchains are not runtime dependencies. Native
tests use compiled Zig peers and daemons; user-authored extension input remains
separate from host implementation language policy.
