# Pi Zig V8 checkpoint 160

Checkpoint 160 continues the native Zig 0.16.0 rewrite from the uploaded checkpoint 159 and the newly supplied original Pi 0.84.1 source tree. This pass closes the two highest-priority checkpoint-159 reload gaps: stale use of the old JavaScript/TypeScript command context after `ctx.reload()`, and live reconstruction of externally changed settings, model catalogs, endpoints, and credentials.

## Reload becomes a terminal action boundary

The original extension contract treats a command or shortcut context as stale once it replaces or reloads the session/runtime. Checkpoint 160 now enforces that boundary in both halves of the compatibility layer.

The embedded JavaScript bridge:

- marks the producing context invalid immediately after `await ctx.reload()`;
- rejects later mutating calls through the captured `pi` object or command context;
- reports the original-style stale-context diagnostic;
- retains the already requested reload action;
- omits later prompts, session changes, custom entries, shutdown requests, or other mutations from the worker result.

The Zig action pipeline independently treats the first reload action as terminal. Startup preview, command output application, shortcut handling, lifecycle queues, and compatibility-field replay stop at that barrier. Even a malformed or nonconforming worker therefore cannot smuggle old-runtime actions across the replacement boundary.

Focused tests cover a TypeScript command that calls `await ctx.reload()` and then attempts to append a durable entry and return a prompt/session mutation. Only the reload action survives; all later effects are quarantined.

## On-disk model and provider reconstruction

Runtime reload now stages a fresh effective model catalog from:

- `models.json`;
- Radius model caches;
- Pi Messages identities;
- GitHub Copilot catalog/auth filtering;
- currently supported built-in catalog entries.

Every on-disk `models.json` provider is re-resolved per model, including its public identity, API dialect, native transport, endpoint, API key source, context/output limits, capabilities, compatibility metadata, and sampling configuration.

Providers removed from `models.json` no longer survive as stale runtime entries. Extension-owned declarative providers are then reconstructed against this fresh disk-backed baseline. The active provider/model must still exist in the staged catalog before commit.

An explicit command-line key remains scoped only to the public provider for which it was supplied; it is never reused merely because another provider shares the same transport implementation.

## Credential reconstruction and owned client state

Reload now re-reads built-in OpenAI, Anthropic, and Google credentials from the same precedence chain used at startup:

1. matching explicit CLI override;
2. process environment;
3. upstream-compatible `auth.json`;
4. legacy credential fallback.

Dynamic/custom providers are re-resolved through `models.json`, `auth.json`, environment-backed key references, and their provider-specific runtime resolver.

The client pool now owns reload-installed copies of:

- OpenAI key;
- Anthropic key;
- Google key;
- settings-level HTTP proxy URL.

This removes borrowed slices whose backing reload arena could otherwise disappear after commit. Allocation is transactional: a failed replacement leaves the currently published values untouched.

## Reloadable settings and transport state

A reload now re-reads merged trusted user/project settings and applies the following live state transactionally:

- settings-defined active tool allow-list, unless a CLI or extension action owns the selection;
- maximum agent turns;
- compaction keep-recent count;
- global HTTP proxy fallback;
- Codex transport selection;
- HTTP idle timeout;
- WebSocket connect timeout;
- selected theme;
- formatted `/settings` display;
- interactive keybindings;
- package-manager command used while rebuilding explicit temporary sources.

The tool registry and extension schemas are rebuilt immediately, so the next request observes the replacement allow-list rather than the startup list.

## Atomic client rollback

Before publishing replacement network/provider state, checkpoint 160 captures owned copies of the current credentials and proxy together with the active transport and timeout settings.

The transaction then:

1. installs the staged runtime-provider list;
2. installs fresh built-in credentials and proxy/timeout settings;
3. reconstructs the active provider/model client;
4. commits the new catalog, extension host, commands, templates, themes, tools, settings, and keybindings only after all prior steps succeed.

If any client or provider rebinding step fails, Pi restores the previous runtime list, credentials, proxy, transport, timeouts, and active client identity before restarting the old extension lifecycle with `reload_rollback`.

## RPC stdin ownership correction

The real persistent RPC E2E exposed an existing DebugAllocator leak in the detached stdin-reader context. More importantly, the detached reader retained a pointer to an Inbox that the main RPC routine could destroy after `quit`.

Checkpoint 160 makes that lifecycle safe:

- reader-owned input lines use a process-safe page allocator rather than the main DebugAllocator;
- the reader reaches the Inbox only through a guarded optional pointer;
- RPC teardown atomically severs that pointer before releasing Inbox state;
- queued and deferred line ownership is released with the allocator that created it;
- a reader blocked in the process stdin syscall can remain detached until process exit without retaining or racing DebugAllocator-owned objects.

The final RPC E2E exits with zero stderr and no allocator diagnostic.

## Real persistent RPC reload gate

A local OpenAI-compatible SSE server and one persistent `pi --mode rpc` process exercised two complete turns.

Initial disk state:

```text
Provider/model:       disk160/fast
Endpoint:             /one/chat/completions
Authorization:        Bearer token-v1
Active tool schema:   read
```

While the process remained alive, the test atomically replaced `models.json`, `auth.json`, and `settings.json`, then sent:

```json
{"id":"r1","type":"reload"}
```

The next turn observed:

```text
Provider/model:       disk160/fast
Endpoint:             /two/chat/completions
Authorization:        Bearer token-v2
Active tool schema:   bash
```

The reload response explicitly reported settings, models, and credentials. `get_available_models` returned the changed `disk160/fast` endpoint and context limit. Both streamed completions succeeded, the process exited normally, and stderr was empty.

The concise record is `RELOAD-E2E-160.txt`.

## Validation

```text
Supplied Zig toolchain:                    0.16.0
Native Zig source files:                   175
Native Zig logical lines:                  96,019
Embedded JavaScript bridge lines:          984
Source-level named test declarations:      839
Synthetic/generated feature shards:        0

Direct complete root closure:              844/844 passed
Build-test module graph:                   837 passed, 7 isolated, 0 failed
Build-test graph:                          13/13 steps succeeded
Ordinary executable tests:                 6/6 passed
SQLite repository tests:                  11/11 passed
SQLite CLI/schema process:                 8 passed, 6 isolated, 0 failed
SQLite live-persistence tests:             5/5 passed
SQLite-enabled executable tests:           6/6 passed

Whole-tree Zig formatting:                 passed
Node bridge syntax validation:             passed
Real-source audit:                         passed
Static pi Debug build:                     passed
pi-sqlite Debug build:                     passed
pi-sqlite-live Debug build:                passed
Persistent disk reload E2E:                passed
RPC clean-shutdown/allocator gate:          passed
```

The seven build-graph isolates are deliberate C-linked SQLite cases and all execute successfully in their dedicated linked processes. The direct non-LLVM root closure links SQLite/libc explicitly and executes every one of the 844 cases without skips.

## Reproducibility boundary

The checkpoint source archive is cache-free and uses one `pi-zig-v8-checkpoint-160/` root. `.git`, `.zig-cache*`, `.zig-global-cache*`, `zig-out`, and `__pycache__` are excluded. Its 283 frozen source/report files were extracted byte-for-byte and independently passed formatting, source audit, the 844-test direct root closure, the 13-step build-test graph, all three Debug builds, and the persistent RPC reload gate with zero stderr.

The binary-safe checkpoint-159→160 patch was applied independently to a pristine extraction of the uploaded checkpoint 159. The 283-file reconstruction matched checkpoint 160 byte-for-byte and independently passed the same complete tests, builds, and persistent reload E2E.

## Remaining parity boundary

Checkpoint 160 materially closes stale post-reload extension actions and externally changed model/auth/settings reconstruction. Complete Pi 0.84.1 monorepo equivalence is not claimed.

The highest-value remaining areas are:

1. Reloading every remaining mutable automatic-retry, compaction-toggle, UI scalar, and externally refreshed OAuth/account source with the same all-or-nothing transaction.
2. The complete package install, update, and removal fullscreen manager.
3. Complete npm, pnpm, and Bun workspace, lockfile, lifecycle-script, and platform behavior.
4. Arbitrary extension-owned retained component trees with asynchronous invalidation.
5. Function-valued provider transports and extension-owned OAuth/login callbacks.
6. Remaining fullscreen model, login, settings, and session screens.
7. Native server TLS and mutual TLS.
8. Automatic image resizing, EXIF-orientation normalization, and transcoding.
9. The remaining enterprise credential, retry, telemetry, and cross-language interoperability matrix.
