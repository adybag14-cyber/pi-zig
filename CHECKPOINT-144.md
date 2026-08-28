# Pi Zig V8 checkpoint 144

Checkpoint 144 continues the native Zig 0.16.0 rewrite against the uploaded Pi 0.84.1 monorepo. This pass closes concrete session-discovery, remote-search, network-framing and production-SQLite gaps while preserving the self-contained default executable.

## Measured state

- 159 native Zig source files under `src/`
- 74,241 native Zig source lines
- 5 source files and 2,564 native lines added over checkpoint 143
- 714 unique test declarations, 18 more than checkpoint 143
- no synthetic/generated feature shards
- no Node or TypeScript runtime dependency
- ordinary `pi` Debug executable remains free of a dynamic SQLite dependency
- optional `pi-sqlite` companion links the platform SQLite library explicitly

## Local JSONL session discovery

A storage-neutral native search layer now scans loaded sessions or complete JSONL session directories. It provides:

- active-branch search by default, with explicit all-branch search;
- message role and entry-type filters;
- case-sensitive or ASCII case-insensitive multi-term matching;
- exact-phrase and word-boundary ranking;
- deterministic cross-session ordering and global limits;
- UTF-8-safe, whitespace-normalized context snippets;
- projected assistant thinking/errors, tool names, bash commands, labels, custom types and bounded extension metadata;
- isolation and accounting for malformed session files;
- fully owned results that remain valid after source sessions are released.

The normal executable exposes this through:

```text
pi sessions list [--json] [--limit N]
pi sessions search [--json] [--limit N] [--all-branches]
                   [--case-sensitive] [--messages-only]
                   [--type TYPE] [--role ROLE] QUERY...
pi sessions show [--json|--raw] [--all-branches] SESSION
pi sessions doctor [--json]
```

`doctor` checks parseability, duplicate entry IDs, missing parents/tips and parent cycles without allowing one malformed file to abort the directory scan.

## Protocol snapshot and remote search

Protocol v1 intentionally has no search command. Checkpoint 144 therefore adds a client-side adapter over ordinary acquired `SessionSnapshot` values rather than extending the wire vocabulary. It searches user, assistant and tool transcript projections, supports role/case/session filters, owns every returned field and globally ranks results across sessions.

The native client command is:

```text
pi remote (--socket PATH | --connect ADDRESS:PORT) [--json]
          search [--limit N] [--case-sensitive] [--session ID]
                 [--role user|assistant|tool] QUERY...
```

Each session is acquired with a shared high-level lease, searched from its authoritative snapshot and deterministically detached/disposed. Attachment failures are isolated and reported rather than invalidating successful hits from other sessions.

## Network endpoint and HTTP hardening

The TCP client now accepts validated DNS hostnames in addition to literal IPv4 and bracketed IPv6 endpoints. Hostname connections use Zig 0.16's native resolver and address-racing path. The server accepts numeric IPv4, plain IPv6 and bracketed IPv6 bind addresses.

The diagnostic HTTP compatibility path was hardened substantially:

- authentication is accepted only from one `Authorization: Bearer` header;
- bearer scheme matching is case-insensitive, while token content remains exact;
- query parameters, unrelated headers and request bodies cannot satisfy authentication;
- duplicate authorization fields and obsolete folded headers are rejected;
- token comparisons use fixed-length SHA-256 digests with timing-safe equality;
- complete `Content-Length` bodies are read before RPC parsing;
- duplicate lengths, transfer codings, malformed lengths, truncation and extra body bytes are rejected;
- body size is bounded by the configured protocol frame limit;
- only exact diagnostic routes are accepted;
- 401 responses include `WWW-Authenticate: Bearer`.

This does not claim TLS, HTTP proxy tunnelling or binary-protocol authentication.

## Production SQLite companion

The canonical SQLite repository added in checkpoint 142 is now reachable through a real production executable while remaining optional:

```text
zig build sqlite
zig-out/bin/pi-sqlite --db PATH init [--json]
zig-out/bin/pi-sqlite --db PATH list [--json] [--cwd PATH] [--limit N]
zig-out/bin/pi-sqlite --db PATH search [--json] [--limit N] [--type TYPE] QUERY...
zig-out/bin/pi-sqlite --db PATH show [--json] [--limit N] SESSION
zig-out/bin/pi-sqlite --db PATH doctor [--json]
```

Opening a database applies the canonical migrations and durable WAL/full-synchronous configuration. Search uses the repository's FTS5 backend and returns contextual snippets. Show renders metadata, statistics, lanes and typed JSON payloads. Doctor runs SQLite integrity checks and verifies every required canonical table.

The default `zig build` still installs only `pi`. The optional `zig build sqlite` step links `sqlite3` and libc into the separate companion; this avoids silently adding a system dependency to normal agent deployments.

## Validation topology

The final worktree passed:

- complete source formatting check;
- real-source audit: 159 files, 74,241 lines, zero forbidden synthetic shards;
- clean Debug build of `pi`;
- Debug build and live init/doctor smoke of `pi-sqlite` against SQLite 3.46.1;
- 11/11 dedicated canonical SQLite repository tests;
- 8/8 active SQLite CLI/ABI/schema tests, with the six repository cases intentionally isolated to their dedicated process;
- 449/449 dependency-complete HTTP/session-command tests;
- 88/88 remote/client/TCP search tests;
- executable version, local-session help and remote-search help smokes.

The aggregate Debug root test executable was attempted from a cold cache but did not finish compiling within the command deadline. No failing test was observed. The final validation record distinguishes this timeout from the successful targeted gates rather than reporting an unearned 714/714 aggregate result.

## Remaining parity boundary

Checkpoint 144 is materially fuller but does not claim complete original-monorepo equivalence. The largest remaining areas are arbitrary upstream JavaScript/TypeScript extension execution, wiring every original coding-agent screen into the retained fullscreen shell, selecting SQLite as the live agent/server session store rather than through the companion administration path, original remote repository adapters beyond snapshot search, TLS/proxy transport support, automatic image resizing, the complete enterprise credential/proxy/retry matrix and broader auxiliary evaluation/server interoperability fixtures.
