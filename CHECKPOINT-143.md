# Pi Zig V8 checkpoint 143

Checkpoint 143 continues the native Zig 0.16.0 rewrite against the uploaded Pi 0.84.1 monorepo. It closes a major checkpoint-142 gap by porting the original high-level remote-client/session stack and making it usable through the native executable over both Unix-domain sockets and TCP.

## Measured state

- 154 Zig source files under `src/`
- 71,677 lines of native Zig under `src/`
- 3,728 native Zig lines added over checkpoint 142
- 26 additional unique test declarations
- no synthetic/generated feature shards
- no Node or TypeScript runtime dependency
- normal Linux executable remains statically linked and does not acquire a hard SQLite dependency

## Owned protocol model cloning

Protocol messages decoded by the client are arena-backed. Checkpoint 143 adds a complete allocator-directed cloning layer so higher-level sessions can safely retain protocol state after a callback returns. It covers:

- recursive JSON values;
- model references and complete model metadata;
- user, assistant and tool content blocks;
- all transcript item/status variants;
- streaming transcript progress and partial tool-call input;
- session metadata and complete session snapshots;
- server snapshots, protocol errors, command results and server events.

The clone tests deliberately mutate or release source storage after cloning and verify that nested text, arrays, optionals and JSON values remain independently owned.

## Remote transcript projection

The native `remote_transcript.State` ports the original coding-agent transcript reducer rather than directly mutating authoritative snapshots. It provides:

- authoritative snapshot replacement with revision checks;
- independent transient progress items keyed by transcript id;
- item-start, item-update and item-finish projection;
- assistant text/reasoning deltas;
- incremental tool-call JSON accumulation and parsing;
- queued steering projection;
- runtime reset semantics after detach/reacquire;
- bounded arena compaction by mutation count or retained bytes;
- stable visible ordering without modifying the source snapshot.

Fixtures cover partial JSON, progress replacement, stale snapshots, queued input, compaction and runtime revision reset behavior.

## High-level native RemoteSession

Checkpoint 143 adds the event-driven Zig counterpart of the original `RemoteSession`. It layers the following behavior over the protocol client:

- exclusive session ownership through local leases;
- open and create operations;
- transactional replacement that keeps the old binding until the candidate attach succeeds;
- prompt-versus-steer selection from the authoritative session phase;
- abort preemption of active submit operations;
- model and thinking-level changes;
- transcript subscription and projection;
- reconnect through a replacement transport followed by ownership reacquisition;
- session-removal and disconnect invalidation;
- durable, owned failure information;
- listener exception isolation;
- asynchronous detach/disposal with explicit destroy readiness;
- rollback and cleanup when attach, detach or replacement fails.

Operations are deliberately nonblocking at the API boundary: they queue a typed protocol frame, expose lifecycle state, and settle as the embedding application pumps transport data.

## Session handles and client conveniences

The low-level client now exposes lease state and cleanup reconciliation required by high-level wrappers. A new native session-handle package provides:

- shared and exclusive owned handles;
- command gating against active lease state;
- typed request dispatch bound to the handle's session id;
- explicit release with rollback if server detach fails;
- disposal that relinquishes local ownership while recording required cleanup;
- attach/acquire workflows;
- abandoned-cleanup reconciliation before reacquisition;
- create-session workflows that return an exclusive handle;
- compensating detach if exclusive handle adoption conflicts after creation;
- owned acquisition/creation errors safe beyond callback arenas.

## Unix and TCP transports

The existing Unix adapter and the new TCP adapter share the same byte-transport contract. Checkpoint 143 adds:

- absolute-deadline receive pumps for bounded command lifecycles;
- literal IPv4 and bracketed IPv6 endpoint parsing;
- cross-platform TCP stream setup;
- pending-frame limits and deterministic close behavior;
- fragmented protocol handshake tests over real stream pairs.

Both adapters now read through the socket receive API rather than a buffered “read exact/short” path that could wait for a buffer-sized read after a valid shorter protocol frame. This fixes a real short-read deadlock risk.

Zig 0.16.0's threaded I/O backend currently aborts if an IP-connect timeout option is supplied. The TCP adapter therefore uses the backend's portable OS-bounded connect operation and applies explicit absolute deadlines immediately to handshake and subsequent protocol traffic instead of triggering that runtime panic.

## Native `pi remote` command

The new executable command uses the same client, lease and `RemoteSession` layers exposed to embedders:

```text
pi remote (--socket PATH | --connect ADDRESS:PORT) [--timeout-ms N] [--json] list
pi remote (...) open SESSION
pi remote (...) create [--cwd PATH] [--name NAME] [--model PROVIDER/ID]
                    [--thinking LEVEL] [--prompt TEXT...]
pi remote (...) prompt SESSION TEXT...
pi remote (...) abort SESSION
pi remote (...) model SESSION PROVIDER/ID
pi remote (...) thinking SESSION LEVEL
```

Implemented command behavior includes:

- strict endpoint, timeout, action, model and thinking-level validation;
- ordered multi-argument prompt joining;
- text and machine-readable JSON rendering;
- complete transcript or final-assistant rendering as appropriate;
- absolute handshake/operation deadlines;
- automatic detach on normal completion;
- disconnect-assisted cleanup if a server does not settle disposal;
- Unix-domain and literal IP TCP endpoint selection.

## Live integration evidence

The final executable was exercised against separately running native servers, not only in memory:

1. Unix-domain server: handshake, empty list, create, streamed two-chunk mock completion, persisted list, reopen and automatic detach.
2. TCP server on `127.0.0.1`: the same lifecycle over the new TCP adapter.
3. Returned JSON was parsed independently and checked for session id, model, phase, revision and exact assistant text.
4. Reopened text output was checked against the persisted completion.

## Test topology

`zig build test -Doptimize=Debug --summary all` performs three gates:

1. the all-package root suite declares 695 tests and records 689 passes plus six intentional SQLite repository skips;
2. a dedicated SQLite-linked process runs 11/11 tests, including all six isolated repository cases;
3. the executable test runs 1/1.

Across the source tree there are 696 unique declared tests. Every declaration executes successfully in at least one gate; no test fails.

## Remaining parity boundary

Checkpoint 143 is materially closer to the original but does not claim complete monorepo equivalence. Major remaining areas include arbitrary JavaScript/TypeScript extension execution, wiring every original interactive coding-agent screen onto the retained TUI shell, selecting the SQLite repository through all production CLI/server paths, remote repository/search adapters beyond live protocol sessions, DNS/proxy/TLS transports for remote protocol clients, automatic image resizing and remaining provider-specific multimodal limits, the complete enterprise authentication/proxy/retry matrix, and fuller auxiliary server/evaluation/client interoperability fixtures.
