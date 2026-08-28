# Pi Zig checkpoint 168

Evidence base: the uploaded Pi coding-agent **0.84.1** source, uploaded Zig checkpoint 167, and the supplied native Zig **0.16.0** Linux x86-64 toolchain.

Checkpoint 168 closes the remaining split between model-request networking and OAuth, cloud-credential, and catalog bootstrap networking. It also advances the retained fullscreen session-tree selector toward the original interaction model and improves compact-context token estimation.

## Shared bounded bootstrap HTTP

A new native `src/ai/bootstrap_http.zig` path gives small management/bootstrap requests the same effective runtime controls used by model providers:

- provider retry budget;
- response-based retry classification;
- `Retry-After-Ms`, `Retry-After`, and `X-Should-Retry` metadata;
- bounded server-directed retry delay;
- per-attempt request timeout;
- cooperative cancellation;
- target-aware HTTP/HTTPS proxy selection;
- `NO_PROXY` and `no_proxy` matching;
- bounded response bodies;
- complete owned response lifetime.

Deterministic configuration, allocation, invalid-URL, unsupported-proxy, explicit cancellation, and response-size failures remain non-retryable. Transport failures without an HTTP status use a strictly bounded transient retry budget.

## OAuth and dynamic-catalog coverage

The shared request policy now covers the native implementations for:

- OpenAI Codex authorization-code exchange and refresh;
- Anthropic authorization-code exchange and refresh;
- OpenRouter authorization-code exchange;
- Radius discovery, authorization-code exchange, device authorization, device polling, refresh, and `/v1/config` catalog refresh;
- xAI device authorization, polling, and refresh;
- Kimi Coding device authorization, polling, and refresh;
- GitHub Copilot device flow, credential refresh, model discovery, and model-policy enablement.

Compatibility wrappers retain the earlier public function signatures. New `...WithOptions` entry points carry the effective live policy without forcing every caller to construct a separate network client.

## Live callers and noninteractive authentication

The policy is wired into:

- interactive login and device-login flows;
- pending-flow completion;
- live credential refresh in `ClientPool`;
- transactional runtime reload;
- Radius catalog refresh after login;
- custom `oauth:"radius"` providers;
- noninteractive `pi auth check` refreshes.

`pi auth check` now loads the same settings used by ordinary sessions, including provider timeout, retry count, maximum retry delay, settings proxy, environment proxy variables, and `NO_PROXY` rules.

## Cloud credential bootstrap

The same controlled request path now covers:

- Google ADC authorized-user refresh;
- Google service-account token exchange;
- AWS web-identity AssumeRoleWithWebIdentity;
- AWS STS AssumeRole;
- ECS/container credentials;
- EC2 IMDSv2 token and credential retrieval.

ECS/container and IMDS requests deliberately discard application proxy settings before contacting metadata endpoints. This prevents ambient cloud credentials from being sent through a general user-configured proxy while retaining timeout, retry, and cancellation policy.

## Compact-context token estimation

The estimator now serializes tool schemas as canonical compact JSON rather than relying on formatted or transport-specific representations. Assistant tool calls use one shared estimate that excludes transport-only wrapper fields such as provider call IDs while preserving name and argument cost.

Compaction uses the same estimator, eliminating a drift between threshold selection and provider-context accounting.

## Fuller fullscreen session-tree interaction

The retained `/tree` selector now adds:

- wrapped Up/Down movement;
- Escape clearing active search before cancelling;
- direct default/no-tools/user/labeled/all filters;
- forward and backward filter cycling;
- fold/unfold controls;
- mouse row selection;
- mouse-wheel movement;
- hit-component wheel dispatch through the retained application shell;
- interactive label creation, replacement, and clearing;
- optional label timestamps;
- OSC 52 clipboard copy for the selected entry;
- richer help and status rendering.

The existing append-only topology, active branch/tip markers, search, filtering, explicit-ID navigation, summary choice, editor prefill, lifecycle hooks, and deterministic alternate-screen restoration remain intact.

## Real executable validation

A real custom Radius provider was configured through `models.json`, an expired OAuth credential was written to `auth.json`, and the ordinary `pi auth check --json --credentials` executable path was tested against loopback HTTP servers.

```text
503 + Retry-After-Ms then success:          2 requests, PASS
Refreshed access/refresh token persisted:   PASS
X-Should-Retry:false on HTTP 503:           1 request, PASS
50 ms provider timeout pre-emption:         PASS
Settings HTTP proxy absolute-form request:  PASS
NO_PROXY target bypass:                     PASS
Process stderr:                             0 bytes
```

Two real pseudo-terminal gates were run after the selector changes. The first retained the existing provider-backed summary workflow; the second exercised the newly ported controls against a durable session:

```text
Fullscreen /tree selector opened:           PASS
Incremental search selected history:        PASS
Branch summary persisted:                   PASS
Durable label written to JSONL:              checkpoint-168
OSC 52 copied payload:                       tree-answer-168-1
Label timestamps toggled:                    PASS
Labeled-only filter toggled:                 PASS
RPC exits:                                   0 / 0
PTY exits:                                   0 / 0
Combined stderr:                             0 bytes
```

## Complete validation

```text
Native Zig source files:                    181
Native Zig logical lines:                   104197
Named Zig test declarations:                911
Synthetic/generated source files:           0

Direct all-package root tests:              913/913 passed
Direct skips/failures:                      0 / 0
Normal module process:                      906 passed, 7 isolated, 0 failed
SQLite repository process:                 11/11 passed
SQLite CLI/schema process:                  8 passed, 6 isolated, 0 failed
Ordinary executable process:                9/9 passed
SQLite live-persistence process:            5/5 passed
SQLite-enabled executable process:          9/9 passed
Build-test graph:                           13/13 steps succeeded

Whole-tree Zig formatting:                  passed
Embedded Node bridge syntax:               passed
Python fixture compilation:                 passed
Direct-fetch bypass audit:                  passed
Git diff validation:                        passed
Real-source audit:                          passed
Static pi Debug build:                      passed
pi-sqlite Debug build:                      passed
pi-sqlite-live Debug build:                 passed
```

The seven module-process isolates are intentional C-linked SQLite cases. Six pass in the dedicated repository process, while the SQLite CLI integration case passes in its dedicated linked process. The direct root command links SQLite and libc and executes every case without skips.

## Archive and patch reproducibility

The final cache-free archive and binary-safe checkpoint-167 patch are validated after freezing. Exact extraction and patch reconstruction must match all **336** frozen files byte-for-byte, pass the complete tests, rebuild all three executables, and rerun the executable network/tree gates before publication.

## Remaining parity boundary

Checkpoint 168 closes retry, timeout, cancellation, proxy, and `NO_PROXY` propagation for the implemented OAuth, cloud-credential, and dynamic-catalog paths, while materially improving original tree controls and token accounting. Complete Pi 0.84.1 monorepo equivalence is still not asserted.

The highest-value remaining areas are:

1. Update checks, install reporting, extension downloads, and any remaining management HTTP path not yet represented in the Zig executable.
2. Every provider-specific OAuth, enterprise endpoint, ADC, STS, catalog, and account-policy edge case beyond the implemented flows.
3. The original tree selector's complete connector grammar, every mouse action, summary progress/cancellation, help overlay, and editing surface.
4. Complete package, model, login, settings, and session fullscreen managers.
5. Complete npm, pnpm, and Bun workspace, lockfile, lifecycle-script, and platform behavior.
6. Arbitrary asynchronously invalidated extension-owned component trees.
7. Function-valued extension providers and extension-owned OAuth/login callbacks.
8. Native server TLS and mutual TLS.
9. Automatic image resizing, EXIF-orientation normalization, and transcoding.
10. Remaining enterprise credential, telemetry, update, retry, and cross-language interoperability coverage.
