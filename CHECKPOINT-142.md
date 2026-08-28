# Pi Zig V8 checkpoint 142

Checkpoint 142 continues the native Zig 0.16.0 rewrite against the uploaded Pi 0.84.1 monorepo. It replaces two major checkpoint-141 gaps with executable native implementations: the SQLite session-backend package and the retained alternate-screen TUI application layer.

## Measured state

- 148 Zig source files under `src/`
- 67,949 lines of native Zig under `src/`
- 4,858 native Zig lines added over checkpoint 141
- no synthetic/generated feature shards
- no Node or TypeScript runtime dependency
- normal Linux executable remains self-contained; SQLite is linked only by consumers/tests of the optional backend

## Native SQLite session backend

Checkpoint 142 adds a real SQLite implementation against the stable platform ABI rather than extending the JSONL index stand-in. It includes:

- a dependency-free Zig SQLite ABI wrapper with prepared statements, typed binding/columns, transactions, savepoints, busy handling and mapped error classes;
- the original canonical schema for sessions, entries, sequences, statistics, branch entries/tips, lanes, lane moves, records, facts and fenced writer leases;
- idempotent migrations plus WAL, full synchronous durability and busy-timeout configuration;
- session create/read/list/delete and durable reopen;
- UUIDv7 identifiers and monotonic per-session sequence allocation;
- branch-aware entry append and querying, custom entry types, cursor/order/limit filters and branch-cache repair;
- lanes, moves, records, merged logs and open-operation discovery;
- append-only names, labels and general facts;
- message/token/cost statistics;
- writer lease acquisition, renewal, release, expiration takeover and fencing against stale owners;
- branch and complete-tree session forks;
- FTS5 session search with trigger maintenance and an index rebuild for pre-existing entries.

The default coding-agent session path remains its existing native JSONL tree. The SQLite repository is exposed as an optional native package, matching the original monorepo's separate session-backend package structure; it is not represented as though every CLI mode has already switched storage engines.

## Retained alternate-screen TUI application layer

The retained layout primitives from checkpoint 141 now have an application shell and reusable widgets:

- deterministic alternate-screen enter/leave lifecycle with bracketed paste, mouse tracking and cursor restoration;
- synchronized differential repainting with cursor-marker extraction;
- modal overlays with placement, focus transfer, focus restoration and hit testing;
- SGR 1006 and legacy X10 mouse decoding for press/release/drag/move/wheel events and modifiers;
- drag selection, Unicode-cell-safe text extraction and OSC 52 clipboard export;
- in-screen search, match highlighting and next/previous cycling;
- atomic IME pre-edit composition, update, commit and cancellation;
- retained box, input, select-list, settings-list and cancellable-loader widgets;
- disabled-item handling, fuzzy filtering, scrolling, password input and Unicode-safe horizontal input viewport behavior;
- a generic deep-cloning bounded undo stack;
- component callbacks for paste, mouse and focus state.

These APIs provide the core needed to port the original coding-agent dialogs and selectors. They do not yet claim that every original interactive-mode screen, extension-owned widget or platform-specific terminal integration is wired into the production CLI.

## Test topology

`zig build test -Doptimize=Debug -j1` performs three gates:

1. the all-package root suite declares 669 tests and records 663 passes plus six intentional SQLite repository skips;
2. a dedicated SQLite-linked process runs 11/11 tests, including all six isolated repository cases plus the ABI/schema/type conformance cases;
3. the executable test runs 1/1.

This validates all 670 unique declared tests. The SQLite cases are isolated only because Zig 0.16's server-style all-package test execution was unstable around a C-backed library; terminal-mode runners retain allocator and leak checks, and the dedicated backend process executes every isolated case rather than suppressing it.

## Build and dependency behavior

The ordinary `pi` executable does not link SQLite and therefore remains self-contained on Linux. Applications that instantiate `storage.sqlite.Repository` must link the platform `sqlite3` library, as expected for the original optional SQLite backend package. The supplied Linux toolchain and container library were used for the backend integration tests.

## Remaining parity boundary

Checkpoint 142 is materially closer to the original but does not claim complete monorepo equivalence. Major remaining areas include arbitrary JavaScript/TypeScript extension execution, wiring every original coding-agent interactive screen onto the new TUI shell, the remote session backend and every adapter/convenience API, automatic image resizing and remaining provider-specific multimodal limits, the complete enterprise authentication/proxy/retry matrix, and fuller auxiliary server/evaluation package breadth and byte-for-byte interoperability fixtures.
