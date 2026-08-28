# Pi Zig V8 checkpoint 159

Checkpoint 159 continues the native Zig 0.16.0 rewrite from the uploaded checkpoint 158 and the newly supplied original Pi 0.84.1 source tree. This pass closes the largest checkpoint-158 runtime mismatch: `/reload` now reconstructs live extension workers, prompt templates, themes, declarative extension providers, commands, completion state, tool schemas, settings display, and interactive keybindings instead of refreshing only project context and skills.

## Scope completed

### Transactional live-runtime reconstruction

The existing context-and-skill reload path now invokes an application-owned runtime transaction. Before touching the active runtime, Pi prepares and validates a complete replacement containing:

- trusted user, project, package, and explicit CLI extension resources;
- temporary local, npm, and Git extension sources;
- native extension manifests and persistent JavaScript/TypeScript workers;
- extension commands and full RPC command metadata;
- prompt templates and theme registries;
- declarative extension provider registrations and projected model catalogs;
- active-tool selection, model-visible tool schemas, and dispatch bridges;
- extension invocation context, formatted settings text, and interactive keybindings.

Malformed extensions, prompts, themes, provider registrations, extension flags, active-model mappings, or other replacement resources abort preparation. The old workers, provider catalog, commands, prompts, themes, schemas, and tools remain usable. A recursion guard rejects a second reload while one is already being applied.

### Lifecycle-safe commit and rollback

After successful staging, the transaction performs a defined lifecycle boundary:

1. Send `session_shutdown` with reason `reload` to the old extension runner.
2. Drain its ordered lifecycle actions.
3. Rebind the active client pool to the staged provider snapshot.
4. Move the staged host, bridge, provider registry, prompts, themes, schemas, commands, settings text, keybindings, and active-tool state into stable live objects.
5. Repoint the agent loop, completion engine, RPC command provider, and action runtime.
6. Release displaced ownership only after all live references have been rebound.
7. Send `session_start` with reason `reload` to the replacement runner and drain its startup actions.

If active-provider rebinding fails before commit, the prior provider snapshot is restored and the old runner receives `session_start` with reason `reload_rollback`.

### Extension-side `ctx.reload()`

Original-style JavaScript and TypeScript extension commands and shortcuts now receive asynchronous `ctx.reload()`. The bridge records an ordered native reload action instead of recursively mutating its own locked worker. Zig applies that action after the invocation returns, avoiding worker-mutex re-entry.

The executable E2E invokes reload from the old TypeScript command itself, confirms that the requesting command disappears with the old worker, and then exercises a replacement prompt template and replacement extension tool in the same persistent process.

Lifecycle and tool contexts deliberately do not expose `ctx.reload()`, matching the supported command/shortcut boundary.

### Strict JSONL RPC reload

The RPC dispatcher now accepts:

```json
{"id":"reload-1","type":"reload"}
```

It executes the same transaction and returns the human-readable reload summary in structured response data. A following `get_commands` immediately observes the replacement extension commands and prompt templates.

### Live provider/client rebinding

Declarative providers registered by extensions are rebuilt with the new host. The transaction verifies that the active provider/model still exists, then rebinds the live client pool before freeing the old registry.

A real local OpenAI-compatible streaming E2E kept the active model `hot159/fast`, changed only the extension-owned credential from `extension-secret-v1` to `extension-secret-v2`, reloaded in place, and verified that the next HTTP request used the new Bearer credential.

### Commands, prompts, themes, keybindings, and settings

Interactive completion and RPC `get_commands` now reference mutable current inventories through stable owners. Successful reload therefore changes command discovery and slash-template expansion immediately.

The theme registry is rebuilt and the newly selected theme is applied. Worker-owned UI state is cleared—including notifications, statuses, widgets, custom surfaces, title, working indicator, pending editor replacement, hidden-thinking labels, and extension theme metadata—while terminal binding, dimensions, and editor contents remain valid.

Formatted settings text is rebuilt and swapped atomically. Interactive keybindings are replaced only when the new manager loads successfully; a keybinding load failure retains the prior manager.

### Reload status

Successful status reports reconstructed resources:

```text
Reloaded: N context file(s), N skill(s), N extension(s), N command(s), N prompt template(s), N theme(s)[, keybindings]
```

When context and skill reconstruction succeeds but runtime preparation fails, the response states that runtime resources were unchanged and includes the concrete Zig error name.

## Regression coverage added

Checkpoint 159 adds focused native coverage for:

- command and shortcut `ctx.reload()` action generation;
- reload UI reset ownership and editor-binding preservation;
- runtime reload count formatting, including commands and keybindings;
- runtime rollback-status formatting;
- top-level skill changes across reload;
- custom system and append-prompt preservation across thinking/reload changes.

## Validation summary

```text
Supplied Zig toolchain:                    0.16.0
Native Zig source files:                   175
Native Zig logical lines:                  95,532
Embedded JavaScript bridge lines:          941
Source-level Zig test declarations:        835
Synthetic/generated feature shards:        0

Complete direct root closure:              841/841 passed
Direct root failures/skips:                0 / 0
Build-test module graph:                   834 passed, 7 isolated, 0 failed
Build-test graph:                          13/13 steps succeeded
Dedicated SQLite repository:               11/11 passed
Dedicated SQLite CLI/schema:               8 passed, 6 isolated, 0 failed
Ordinary executable suite:                 5/5 passed
SQLite live-persistence suite:             5/5 passed
SQLite-enabled executable suite:           5/5 passed

Whole-tree Zig formatting:                 passed
Node bridge syntax validation:             passed
Real-source audit:                         passed
Static pi Debug build:                     passed
pi-sqlite Debug build:                     passed
pi-sqlite-live Debug build:                passed
```

The direct complete root closure was run with Zig's non-LLVM backend and explicit SQLite linkage:

```text
PI_SQLITE_CLI_TESTS=1 zig test src/root.zig -fno-llvm -lsqlite3 -lc
All 841 tests passed.
```

The normal `zig build test` graph also completed successfully. Its seven aggregate-process SQLite isolates are intentional; all isolated behavior passed in the separately linked dedicated SQLite processes.

## Real executable gates

### Replacement, rollback, and RPC

One persistent RPC process validated all of the following:

- initial commands `old-command`, `old-template`, and `reload-runtime`;
- malformed TypeScript replacement reports `JavaScriptExtensionReadFailed` and retains the old worker;
- the retained old command calls `await ctx.reload()` after the source is corrected;
- replacement commands become `new-command` and `new-template`;
- replacement prompt expansion produces `NEW TEMPLATE Bob`;
- the replacement extension tool returns `fresh:Bob:v2:fresh-call-159`;
- a second direct RPC reload replaces the runtime with `rpc-command` and `rpc-template`;
- no unexpected panic, allocator leak report, or protocol corruption occurs.

The malformed-TypeScript rollback intentionally causes Node to print `ERR_INVALID_TYPESCRIPT_SYNTAX`; the fixture checks that this is the only expected diagnostic class.

### Provider reconstruction

A second persistent process performed two real local streaming requests around a live reload:

```text
Provider/model:                            hot159/fast
First authorization:                      Bearer extension-secret-v1
Second authorization:                     Bearer extension-secret-v2
Requests:                                  2
Process stderr:                            0 bytes
```

The consolidated record is `RELOAD-E2E-159.txt`.

## Source archive and patch reproducibility

The frozen source archive contains one `pi-zig-v8-checkpoint-159/` root and excludes `.git`, `.zig-cache*`, `.zig-global-cache*`, `zig-out`, and `__pycache__`. A clean extraction matched all 278 source/report files and independently passed formatting, source audit, the complete 841-test closure, the 13-step build-test graph, all three Debug builds, and both persistent-process reload E2Es.

The binary-safe checkpoint-158→159 patch was applied to a pristine extraction of the uploaded checkpoint 158. The reconstructed tree matched the frozen checkpoint 159 extraction byte-for-byte across all 278 files and independently passed the same complete test and build topology.

## Remaining parity boundary

Checkpoint 159 materially closes live startup-resource reconstruction, extension-initiated reload, strict RPC reload, and declarative provider/client rebinding. Complete Pi 0.84.1 monorepo equivalence is not claimed.

The highest-value remaining areas are:

- stale-context rejection for additional actions emitted after `ctx.reload()` by the same old command or shortcut invocation;
- reapplication of every mutable scalar, network, retry, external model-source, and external authentication-source setting;
- the complete package install/update/remove fullscreen manager;
- complete npm, pnpm, and Bun workspace, lockfile, lifecycle-script, and platform behavior;
- arbitrary asynchronously invalidated extension component trees;
- function-valued provider transports and extension-owned OAuth/login callbacks;
- remaining fullscreen model, login, settings, and session screens;
- native server TLS and mutual TLS;
- automatic image resizing, EXIF-orientation normalization, and transcoding;
- the remaining enterprise credential, retry, telemetry, and cross-language interoperability matrix.
