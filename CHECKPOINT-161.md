# Pi Zig checkpoint 161

Checkpoint 161 continues from the uploaded native checkpoint 160 against the newly supplied original Pi 0.84.1 tree, using the supplied Zig 0.16.0 compiler. The supplied original source is the same Pi 0.84.1 revision used by the immediately preceding continuation, so this checkpoint concentrates on a documented behavioral gap rather than reconciling an upstream source change.

## Native settings-driven assistant retry

The original coding agent exposes an outer retry policy under:

```json
{
  "retry": {
    "enabled": true,
    "maxRetries": 3,
    "baseDelayMs": 2000
  }
}
```

Checkpoint 161 ports that policy into the native Zig agent loop instead of relying only on individual provider transports.

Implemented behavior includes:

- retry enabled by default;
- three retries after the initial assistant request by default;
- exponential backoff using `baseDelayMs * 2^(attempt - 1)`;
- saturating delay arithmetic rather than integer wraparound;
- context-overflow compaction before ordinary transient retry classification;
- rebuilding the active session context before every retry attempt;
- preserving only the terminal assistant response in the active model context;
- support for provider-returned assistant errors and thrown Zig transport failures;
- immediate failure for quota, subscription, budget, billing, authentication, and deterministic request errors;
- whole-agent abort and retry-only abort during backoff;
- prompt responsiveness through 25 ms cancellation-aware sleep slices.

## Original retry classification

The native classifier covers the original Pi transient classes, including:

- overloaded, rate-limit, HTTP 429 and transient 5xx responses;
- provider/upstream wrapper failures;
- connection refusal/loss, DNS lookup failures, broken pipes, and socket closure;
- fetch, proxy, and upstream-connect failures;
- timeouts and terminated requests;
- WebSocket close/error paths;
- premature SSE/HTTP2 stream termination;
- explicit provider retry guidance;
- gRPC `ResourceExhausted` failures.

It also recognizes Zig error names such as `ConnectionResetByPeer` and `TemporaryNameServerFailure` without allocating a normalized copy. Original quota and billing exclusions remain authoritative even when the message also contains a retryable status such as 429.

## Settings and live reload

`settings.json` parsing now retains the original nested fields:

```text
compaction.enabled
retry.enabled
retry.maxRetries
retry.baseDelayMs
```

Global and trusted project settings merge field-by-field, so a project can override only `maxRetries` without discarding the inherited enabled flag or base delay. The existing compatibility aliases for automatic compaction and retry remain accepted.

The formatted `/settings` state now reports effective compaction and retry values. Transactional runtime reload applies all retry fields and the compaction enabled toggle to the live `AgentConfig` without restarting Pi.

## Retry events and UI surfaces

The native event vocabulary now includes:

```text
auto_retry_start
auto_retry_end
```

JSON and RPC output use the original wire shapes:

```json
{
  "type": "auto_retry_start",
  "attempt": 1,
  "maxAttempts": 3,
  "delayMs": 2000,
  "errorMessage": "HTTP 503 Service Unavailable"
}
```

```json
{
  "type": "auto_retry_end",
  "success": true,
  "attempt": 1
}
```

Final exhaustion and cancellation emit `success:false` with `finalError`. Print and interactive modes render retry status without corrupting machine-readable output. Retry bookkeeping is a session/runtime event and is not incorrectly replayed as an extension lifecycle hook.

## RPC controls

The existing RPC surface is now functional rather than state-only:

```text
set_auto_retry
abort_retry
get_state
reload
```

`set_auto_retry` immediately changes the next agent request. `abort_retry` works while an agent request is busy and cancels only the pending backoff. `get_state` reports the actual live retry state, and `reload` synchronizes the RPC state with newly read settings.

A concurrent RPC test verifies that retry cancellation does not consume the next scripted provider response.

## Regression coverage

New native tests cover:

- transient error recovery and exact retry event metadata;
- quota/billing fail-fast behavior;
- retry-only cancellation and aborted stop reason;
- exhausted retry budget and final error reporting;
- thrown Zig transport failure recovery;
- transient and non-transient classifier fixtures;
- saturating exponential delay;
- retry-only cancellation during sleep;
- nested settings parsing, field-preserving merge, formatting, and compatibility aliases.

Real executable RPC gates cover:

- retry to success;
- concurrent `abort_retry`;
- initial disabled behavior;
- runtime `set_auto_retry` enablement;
- settings-file replacement followed by live `reload` disablement;
- `get_state` synchronization;
- clean process exit with zero stderr.

## Measurements

```text
Native Zig source files:                   176
Native Zig logical lines:                  96,798
Embedded JavaScript bridge lines:          984
Named Zig test declarations:               850
Synthetic/generated feature shards:        0

Checkpoint 160 -> 161 implementation:
  Source files changed/added:                7
  Additions:                               793
  Deletions:                                14
```

## Complete validation

```text
Direct root closure:
  PI_SQLITE_CLI_TESTS=1 PI_SQLITE_REPOSITORY_TESTS=1
  zig test src/root.zig -fno-llvm -lsqlite3 -lc
  Result:                                  855/855 passed

Normal build-test graph:
  Module process:                          849 passed, 6 isolated, 0 failed
  SQLite repository process:              11/11 passed
  SQLite CLI/schema process:               8 passed, 6 isolated, 0 failed
  Ordinary executable process:             6/6 passed
  SQLite live-persistence process:          5/5 passed
  SQLite-enabled executable process:        6/6 passed
  Build steps:                             13/13 succeeded

Static gates:
  Whole-tree Zig formatting:               passed
  Node bridge syntax validation:           passed
  Real-source audit:                       passed
  Synthetic-source count:                  0

Debug builds:
  pi:                                      passed
  pi-sqlite:                               passed
  pi-sqlite-live:                          passed
```

The six module-process isolates are the C-backed SQLite repository declarations. They are not missing coverage: all execute in the dedicated 11-test linked repository process, while the direct root closure links SQLite/libc and executes all 855 cases with no skips.

## Remaining parity boundary

Checkpoint 161 closes the ordinary assistant-turn retry settings, classifier, backoff, events, live reload, and RPC-control boundary. Complete Pi 0.84.1 monorepo equivalence is still not claimed.

The highest-value remaining work includes:

1. Summarization retry events and retry policy for compaction/branch summaries.
2. Persisting RPC `set_auto_retry` changes back into global `settings.json`, matching the original settings manager rather than retaining only live process state.
3. Provider/SDK retry subsettings (`retry.provider`) and consistent propagation through every native transport.
4. Retaining intermediate failed assistant attempts in durable session history while excluding them from the active retry context, matching the original session-manager distinction.
5. The complete fullscreen package source manager and remaining model/login/settings/session screens.
6. Full npm, pnpm, and Bun workspace/lockfile/lifecycle/platform behavior.
7. Arbitrary asynchronously invalidated extension component trees.
8. Function-valued provider transports and extension-owned OAuth/login callbacks.
9. Native server TLS and mutual TLS.
10. Automatic image resizing, EXIF-orientation normalization, and transcoding.
11. Remaining enterprise credential, telemetry, retry, and cross-language interoperability coverage.

## Exact archive and patch reproducibility

The frozen source archive contains one `pi-zig-v8-checkpoint-161/` root with **289 files** and **309 total ZIP entries**. It excludes `.git`, `.zig-cache*`, `.zig-global-cache*`, `zig-out`, and `__pycache__`.

The exact archive bytes were extracted into a clean directory and matched the committed source **289/289 files byte-for-byte**. That extraction independently passed the 855-test direct root closure, the 13-step build-test graph, all three Debug builds, both retry RPC E2Es, and zero-stderr process shutdown.

The binary-safe checkpoint-160→161 patch was applied to a pristine extraction of the exact uploaded checkpoint 160 archive. The reconstruction matched the checkpoint-161 source **289/289 files byte-for-byte** and independently passed the same complete tests, builds, and retry E2Es.
