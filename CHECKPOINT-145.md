# Pi Zig checkpoint 145

Checkpoint 145 continues the native Zig 0.16.0 rewrite against the supplied original Pi 0.84.1 source. It combines the session-compatibility, startup-migration and provider-proxy work with the independently completed secure-remote and live-SQLite branch, then validates the merged tree as one implementation.

## Reference and baseline

- Original reference: `pi-main (3)(5).zip` (Pi 0.84.1)
- Original SHA-256: `42162e1ea09cfaf78ec737862255b919789eef7defd73f413dbb58c8dee0aa1a`
- Exact patch baseline: uploaded `pi-zig-v8-checkpoint-144(1).zip`
- Baseline SHA-256: `933583d44190be32caf0b958de947fd798bb2faf23402ded2767a7c6f6da1e4e`
- Compiler: supplied Zig 0.16.0 Linux x86-64 archive
- Toolchain SHA-256: `70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00`

The uploaded checkpoint-144 archive is the exact reconstruction baseline. A later live-SQLite source tranche retained in the container was treated as an untrusted independent branch, merged through version control, and accepted only after complete compilation, tests, live restart persistence, and patch reconstruction.

## Measurements

```text
Native Zig source files under src/:       166
Native Zig source lines under src/:       77,510
Gain over uploaded checkpoint 144:        7 files / 3,269 lines
Unique declared native tests:             740
Gain over uploaded checkpoint 144:        26 tests
Synthetic/generated feature shards:       0
Baseline-to-final implementation diff:    32 files changed
Diff additions/deletions:                 +3,529 / -193
```

## Session format and administration parity

Checkpoint 145 adds the original upstream JSONL migration path and makes it production-accessible:

- v1 sessions gain deterministic entry IDs and parent chains;
- v1 compaction `firstKeptEntryIndex` becomes `firstKeptEntryId`;
- v2 `hookMessage` roles become v3 `custom` roles;
- malformed non-session lines are isolated while unrelated/future JSONL is never rewritten;
- opened legacy sessions are atomically rewritten as durable v3;
- session creation timestamps remain stable across repeated saves;
- `parentSession` provenance survives CLI, RPC and interactive forks;
- every save uses atomic replacement rather than in-place truncation;
- discovery reads the complete tree so later `session_info` renames take effect;
- corrupt files remain visible to `doctor` instead of disappearing from discovery;
- statistics include messages, tool activity, usage/cost, compaction and branch-summary billing.

The native administration surface now includes:

```text
pi sessions stats [--json] SESSION
pi sessions tree [--json] SESSION
pi sessions rename [--json] SESSION NAME...
pi sessions delete [--json] --force SESSION
pi sessions migrate [--json] [--dry-run] (--all | SESSION)
```

Guarded deletion, migration dry-runs, tree projection, durable renaming and statistics were exercised through the final executable against real JSONL files.

## Original startup migrations and canonical paths

Session directories now use the original human-readable cwd encoding (`--home-user-project--`) rather than the pre-145 Pi-Zig FNV leaf. Startup migration recovers the old hashed current-project directory and also ports the original one-time migrations for:

- `oauth.json` and legacy `settings.json.apiKeys` into canonical `auth.json`;
- 0600 credential-file permissions and no-loss settings cleanup;
- misplaced root JSONL sessions into their cwd-specific directory;
- `tools/rg`, `tools/fd` and Windows variants into `bin/`;
- legacy keybinding names into current names with canonical-key precedence;
- global and project `commands/` directories into `prompts/`;
- warnings for deprecated hooks and custom-tool layouts.

All migration writes are atomic and moves are no-clobber. A live two-start smoke validated credentials, permissions, settings cleanup, keybindings, prompts, binaries, misplaced sessions, hashed-session recovery and idempotence.

## Target-aware HTTP proxy support

A shared native proxy policy now mirrors the original environment dispatcher:

- lower-case protocol variables outrank upper-case variables;
- `http_proxy`, `https_proxy`, `HTTP_PROXY`, `HTTPS_PROXY` and `ALL_PROXY` are supported;
- `NO_PROXY`/`no_proxy` is evaluated per destination host and port;
- global `settings.json` `httpProxy` fills only missing protocol proxy settings;
- project settings cannot silently override the global proxy;
- settings diagnostics mask the proxy value;
- authenticated HTTP and HTTPS proxies use Zig's native CONNECT/TLS implementation;
- unsupported SOCKS/PAC-style proxy URLs are rejected explicitly.

The policy is wired into OpenAI Chat, Responses, persistent Codex WebSockets, Anthropic, Google, Mistral, Bedrock, Pi Messages and OpenRouter image requests. Live tests exercised lower-case precedence, `NO_PROXY`, global-settings fallback and actual request delivery through a local forward proxy.

## Secure remote protocol transport

`pi remote` now supports:

```text
pi remote --connect HOST:PORT [--tls] [--proxy URL|--no-proxy]
          [--timeout-ms N] [--json] ACTION ...
```

The native transport provides:

- direct TCP or certificate-verified target TLS;
- explicit proxy, environment proxy and `NO_PROXY` routing;
- authenticated HTTP/HTTPS CONNECT tunnels;
- nested TLS to a target after CONNECT;
- absolute protocol deadlines and deterministic close handling;
- strict rejection of TCP-only flags with Unix sockets;
- no certificate-verification bypass switch.

A live Pi server was reached through real CONNECT tunnels for both `list` and `create`. Server-side TLS/mTLS listening is not claimed in this checkpoint.

## Open-stream short-read correction

Zig 0.16 `readSliceShort` can wait to fill a large destination on an open stream. The affected HTTP, SSE and framed-protocol paths now read at least one byte and return currently buffered data. This prevents small health responses, low-volume SSE events and short protocol frames from waiting indefinitely for scratch-buffer completion.

## Live canonical SQLite server persistence

In addition to the `pi-sqlite` administration companion, checkpoint 145 publishes the complete optional SQLite-linked server executable:

```text
zig build sqlite
zig build sqlite-server

zig-out/bin/pi-sqlite --db sessions.db doctor --json
zig-out/bin/pi-sqlite-live serve --sqlite sessions.db [serve options]
```

The live adapter:

- restores canonical server snapshots at startup;
- writes complete session/transcript/native-JSONL state;
- skips unchanged snapshots;
- preserves names, model, thinking level, revisions and history;
- fences concurrent servers with renewable writer leases;
- releases leases after detach/disconnect;
- imports JSON session directories idempotently;
- isolates ordinary/corrupt repository records that are not server snapshots.

The ordinary `pi` binary remains statically linked and has no SQLite dependency. A live create/stop/restart/open smoke verified metadata and transcript recovery, followed by a successful SQLite doctor/integrity check.

## Validation summary

The final worktree passed:

```text
Whole-tree zig fmt --check:                 PASS
Real-source audit:                          PASS (166 files, 77,510 lines, 0 synthetic)
Complete root suite:                        723 passed, 7 isolated, 0 failed
Dedicated SQLite repository suite:          11/11 passed
Dedicated live SQLite adapter suite:        5/5 passed
SQLite CLI/ABI/schema process:              8 active passed, 6 isolated, 0 failed
Executable/main suite:                      4/4 passed
All 740 unique declarations executed:       PASS
Debug build: pi                             PASS
Debug build: pi-sqlite                      PASS
Debug build: pi-sqlite-live                 PASS
Ordinary pi hard SQLite dependency:         NONE
Provider proxy live smoke:                  PASS
Remote CONNECT protocol smoke:              PASS
Startup migration live/idempotence smoke:   PASS
Session administration live smoke:          PASS
SQLite stop/restart transcript smoke:        PASS
```

The seven root-suite skips are exactly the SQLite CLI live case and six C-backed repository cases. They all execute successfully in their dedicated linked processes; no behavior is counted as passed merely because it was skipped in the self-contained root process.

## Source archive and patch reconstruction

The cache-free checkpoint source ZIP was extracted from its exact bytes into a new directory and passed the complete test graph, all three Debug builds, formatting, source audit, executable help/version smokes, single-root validation and forbidden-directory checks. The binary-safe checkpoint-144 patch was applied to a separate pristine extraction of the uploaded baseline; the result matched checkpoint 145 byte-for-byte and independently passed the complete test graph and all three Debug builds.

## Remaining parity boundary

This is a substantially fuller native rewrite, but complete original-monorepo equivalence is not claimed. The largest remaining areas are:

- arbitrary upstream JavaScript/TypeScript extension execution;
- wiring every original coding-agent dialog and screen into the retained fullscreen shell;
- server-side TLS/mTLS policy;
- proxy propagation through every OAuth and cloud-credential bootstrap helper;
- automatic image resizing/transcoding and remaining provider-specific multimodal limits;
- the complete enterprise authentication, credential-source and retry matrix;
- remaining remote repository adapters and broader auxiliary/evaluation interoperability fixtures.
