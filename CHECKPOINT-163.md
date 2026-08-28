# Pi Zig checkpoint 163

Checkpoint 163 continues from the uploaded native checkpoint 162 against the newly supplied original Pi coding-agent **0.84.1** source tree, using the supplied Zig **0.16.0** compiler. This pass ports Pi's provider-internal request retry boundary rather than relying on fixed transport-local retry constants or only the outer assistant-turn retry loop.

## Major native port additions

### Original nested provider retry settings

The native settings model now retains and deep-merges:

```json
{
  "retry": {
    "provider": {
      "timeoutMs": 300000,
      "maxRetries": 2,
      "maxRetryDelayMs": 60000
    }
  }
}
```

Implemented behavior includes:

- global/project deep merging of individual provider retry fields;
- camelCase and native snake_case compatibility;
- the original `retry.maxDelayMs` legacy fallback;
- `maxRetryDelayMs: 0` as an unlimited server-delay cap;
- explicit `timeoutMs: 0` as an immediate provider timeout;
- inheritance from the general HTTP idle timeout when `retry.provider.timeoutMs` is absent;
- a disabled general HTTP timeout mapping to no provider request deadline;
- formatted `/settings` visibility for all three effective values.

The live `ClientPool` owns one policy and publishes it to both already-created and subsequently switched provider clients. Transactional `/reload` captures, applies, and restores that policy together with credentials, endpoint, proxy, transport, and other client state.

### Shared provider response policy

`src/ai/retry.zig` now carries two deliberately separate policies:

- the outer assistant/summarization retry classifier retained from checkpoint 162;
- an SDK-compatible provider request policy for the initial HTTP operation.

The provider policy implements:

- `x-should-retry: true` and `x-should-retry: false` overrides;
- retryable undefined-status transport failures;
- HTTP 408, 409, 429, and 5xx defaults;
- `retry-after-ms` decimal milliseconds;
- `retry-after` decimal seconds;
- IMF-fixdate `retry-after` values;
- malformed-header fallback rather than accidental zero-delay retry;
- non-negative and overflow-safe numeric conversion;
- a 60-second default cap for server-requested waits;
- a dedicated `ProviderRetryDelayExceeded` failure when the cap is exceeded;
- bounded exponential backoff with upstream-style negative jitter;
- cooperative cancellation during retry waits.

### Controlled HTTP request lifetime

The new `src/ai/http_fetch.zig` preserves Zig's ordinary redirect, header, payload, writer, and certificate behavior while additionally returning the retry headers before `std.http` releases their backing response storage.

It also provides one controlled request boundary that races the complete HTTP operation against:

- the configured provider timeout;
- the shared agent abort flag.

Cancellation drains or cancels the selected task before the caller destroys the HTTP client or response writer. This avoids detached access to stack-owned transport state.

### Transport integration

The shared policy replaces hard-coded three-attempt loops in:

- OpenAI-compatible Chat Completions;
- OpenAI Responses;
- OpenAI Codex Responses over SSE;
- Anthropic Messages;
- Google Generative AI and Vertex-compatible requests;
- Mistral Conversations;
- Amazon Bedrock Converse Stream;
- Pi Messages;
- OpenRouter image generation.

The model transports now consistently apply configured retry counts, request deadlines, header-directed waits, cap enforcement, and abortable sleeps.

Streaming transports do **not** replay a request after model output has started. OpenAI, Anthropic, Mistral, Responses/Codex, Bedrock, and Pi Messages distinguish a pre-output transport failure from an interrupted stream, preventing duplicate text or tool deltas.

Codex retains its protocol-specific exponential fallback and quota/billing fail-fast checks while consuming the shared configured attempt budget, timeout, response metadata, and maximum server-directed delay.

### Request-local metadata without history pollution

Provider status and retry metadata are retained on `ModelResponse` only long enough for the transport-local policy to decide whether another HTTP request is allowed:

```text
provider_status
provider_retry_after_ms
provider_should_retry
```

These scalar fields are intentionally omitted from durable assistant/session serialization. The final provider error text and ordinary response metadata continue through the existing history path.

## Real executable provider-retry gate

`scripts/provider_retry_e2e.py` runs the built `pi` executable against loopback HTTP servers and validates:

1. `retry-after-ms` delays a retry and the second response succeeds;
2. `x-should-retry:true` forces retry of HTTP 400;
3. `x-should-retry:false` prevents provider retry of HTTP 503;
4. an excessive server delay fails before a second request;
5. an explicit provider timeout preempts two slow requests under a one-retry budget;
6. the general HTTP idle timeout is inherited when provider timeout is absent;
7. a persistent RPC process changes from zero provider retries to one retry after transactional `settings.json` replacement and `reload`.

The final development-tree run completed with process exit zero and zero stderr for every case.

## Development-tree validation

```text
Supplied Zig compiler:                     0.16.0
Native Zig source files:                   179
Native Zig logical lines:                  99,774
Named Zig test declarations:               882
Synthetic/generated feature shards:        0

Direct complete root closure:              884/884 passed
Normal all-package module process:          877 passed, 7 isolated, 0 failed
SQLite repository process:                 11/11 passed
SQLite CLI/schema process:                   8 passed, 6 isolated, 0 failed
Ordinary executable process:                 9/9 passed
SQLite live-persistence process:             5/5 passed
SQLite-enabled executable process:           9/9 passed

AI provider import graph:                  189/189 passed
Settings/live client import graph:         524/524 passed
Shared retry focused suite:                  7/7 passed
Controlled HTTP focused suite:               7/7 passed
Whole-tree Zig formatting:                 passed
Node bridge syntax validation:             passed
Real-source audit:                         passed
Static pi Debug build:                     passed
pi-sqlite Debug build:                     passed
pi-sqlite-live build:                      passed
Provider retry executable E2E:             passed
Provider retry E2E stderr:                  0 bytes
```

The direct root command linked SQLite and libc and executed every one of the
884 cases without skips. The normal multi-process build graph deliberately
isolates seven C-linked SQLite cases from the large module process: six execute
in the dedicated 11-test repository process and the remaining CLI integration
case executes in the linked SQLite CLI process. Both validation topologies
completed with zero failures.

Final archive, patch-reconstruction, executable, and transfer gates are recorded
in `VALIDATION-163.txt`.

## Exact archive and patch reproducibility

The frozen source contains 303 regular files beneath one
`pi-zig-v8-checkpoint-163/` root and excludes `.git`, `.zig-cache*`,
`.zig-global-cache*`, `zig-out`, and `__pycache__`.

The exact ZIP extraction independently passed:

```text
Frozen/extracted equivalence:              303/303 byte-for-byte
Direct root closure:                       884/884 passed
Normal multi-process build graph:          passed
All three executable rebuilds:             passed
Provider retry E2E:                        passed
E2E stderr:                                0 bytes
```

The binary patch was applied to a pristine extraction of the uploaded
checkpoint 162. The reconstructed tree matched all 303 frozen files
byte-for-byte, with no missing, extra, or changed files, and passed the source
format, Node bridge, and real-source audits.

## Executable and SQLite validation

The exact-extraction executables have these characteristics:

```text
pi:                 static Linux x86-64 Debug ELF
pi-sqlite:          Linux x86-64 Debug ELF linked to sqlite3/libc
pi-sqlite-live:     Linux x86-64 ELF linked to sqlite3/libc
```

A fresh database initialized with SQLite 3.46.1, exposed every canonical table,
and returned integrity `ok`.

## Remaining parity boundary

Checkpoint 163 closes the original nested provider retry settings and the initial provider-request retry policy across the implemented model transports. Complete Pi 0.84.1 monorepo equivalence is still not claimed.

The highest-value remaining areas are:

1. Propagating the same provider policy through every OAuth, cloud-credential, catalog-refresh, and update-check bootstrap request.
2. Complete provider-specific request/idle timeout distinctions and HTTP/2 keepalive behavior.
3. Token-budget cut points, full compaction prompt/file-operation policy, and extension `session_before_compact` overrides.
4. Full branch-summary settings and `session_before_tree`/`session_tree` extension hooks.
5. Complete package, model, login, settings, session, and tree fullscreen managers.
6. Complete npm, pnpm, and Bun workspace, lockfile, lifecycle-script, and platform behavior.
7. Arbitrary extension-owned retained component trees with asynchronous invalidation.
8. Function-valued provider transports and extension-owned OAuth/login callbacks.
9. Native server TLS and mutual TLS.
10. Automatic image resizing, EXIF-orientation normalization, and transcoding.
11. Remaining enterprise credential, telemetry, retry, and cross-language interoperability breadth.
