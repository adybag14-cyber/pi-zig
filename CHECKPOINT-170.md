# Pi Zig checkpoint 170

Checkpoint 170 continues the native Zig 0.16.0 rewrite from checkpoint 169 against the supplied original Pi 0.84.1 source. This pass closes two high-value interactive and distribution-management gaps: the original shared session-resume workflow and a safe native self-update command surface.

No generated or synthetic feature shards were added. The implementation remains ordinary audited Zig source plus one executable Python end-to-end fixture.

## Fullscreen session resume selector

A new retained `session_tui` component is shared by startup `--resume` and the live interactive `/resume` command.

Implemented behavior includes:

- current-project and recursive all-session scopes;
- newest-first, threaded, and relevance sorting;
- fuzzy multi-token search and quoted phrase matching;
- names-only filtering and optional path display;
- current-session and startup-session markers;
- rename with append-only `session_info` persistence;
- guarded deletion with confirmation;
- prevention of active-session deletion;
- malformed-session visibility without unsafe resume or rename;
- required-working-directory filtering for live replacement;
- keyboard paging and navigation;
- mouse wheel, click, and bounded double-click selection;
- Unicode-cell-safe rendering;
- deterministic alternate-screen, raw-mode, mouse, paste, cursor, and reader-state restoration.

The all-session inventory uses a bounded recursive scan over encoded session roots. It deliberately skips dependency, VCS, build, cache, and Python cache directories so an all-session view does not become an unrestricted filesystem crawler.

## Startup `--resume`

Interactive startup now opens the same retained selector rather than a numbered text menu. The initial query can narrow the list immediately. Non-TTY startup retains deterministic newest-session behavior, and cancelling the selector exits without mutating a session.

The selected JSONL session is loaded through the existing append-only session implementation and remains compatible with existing model, thinking, compaction, branch, label, usage, and extension metadata.

## Transactional live `/resume`

Interactive `/resume [query]` now performs an actual live session replacement rather than only printing session paths.

The owner loop performs the replacement transaction in this order:

1. Load and validate the selected session.
2. Reject the current session and incompatible working directories.
3. Emit `session_shutdown("resume")` to the old extension runtime.
4. Drain and persist ordered old-runtime actions into the old session.
5. Save the old JSONL session.
6. Replace the live append-only session and session path.
7. Rebind agent session identity, file path, client affinity, shortcut context, and extension context.
8. Restore the selected session's provider/model and thinking level where available.
9. Emit `session_start("resume")` for the resumed session.
10. Drain and persist new-runtime actions into the resumed session.
11. Save the resumed JSONL session before continuing interaction.

Post-resume prompts and assistant responses therefore append only to the resumed target. The source session remains durable and unchanged after the hand-off.

## Native self-update command

`pi update` now follows the original target semantics. With no explicit target, it updates Pi itself. Supported forms include:

```text
pi update
pi update self
pi update --self
pi update --extensions
pi update --models
pi update --all
pi update --extension SOURCE
pi update SOURCE
```

Command controls include `--check`, `--force`, `--offline`, and `--json`. Conflicting targets and excess positional operands are rejected before performing work.

The self-update planner identifies npm, pnpm, Yarn, Bun, and unknown installations from the executable path. Configured package-manager wrappers are preserved for command construction but are not treated as proof that an arbitrary executable is package-manager-owned. It supports:

- npm and pnpm global-layout inference;
- configured wrapper commands;
- package-name migration through ordered uninstall/install steps;
- exact latest-release package names and versions;
- current-version no-op unless `--force` is used;
- safe managed-install path checks;
- parent/install-path writeability checks;
- platform-specific support boundaries;
- machine-readable plans and outcomes;
- actionable manual-update fallback when a standalone binary cannot be replaced safely;
- package extension updates and model-catalog refresh through the same command target parser.

The package manager is executed only after the bounded proxy/retry/timeout-aware release lookup and all safety checks succeed.

## Real executable end-to-end validation

The final test fixture creates two real JSONL sessions and exercises both selector entry points through pseudo-terminals.

Observed results:

```text
SESSION_UPDATE_E2E_170=PASS
STARTUP_RESUME=PASS
STARTUP_RENAME_PERSISTENCE=PASS
LIVE_RESUME=PASS
SOURCE_TARGET_ISOLATION=PASS
SELF_UPDATE_CHECK_PLAN=PASS
UNSAFE_SOURCE_INSTALL_REJECTED=PASS
SELF_UPDATE_PACKAGE_MIGRATION=PASS
LATEST_REQUESTS=3
MANAGER_STEPS=2
STDERR_BYTES=0
```

The managed-update phase copies the real Zig executable into an npm-global-shaped installation, performs a non-mutating managed-install check, rejects the ordinary source binary as unmanaged, then executes the exact two-step package-name migration through a deterministic package-manager wrapper. Those three exercised phases each use the bounded loopback release lookup.

## Validation summary

Development-tree closure before freezing:

```text
Supplied Zig compiler:                     0.16.0
Original Pi source:                        0.84.1
Native Zig source files:                   185
Native Zig logical lines:                  108,028
Named Zig test declarations:               930
Synthetic/generated source files:          0

Direct all-package process:                932/932 passed
Direct skipped/failed:                     0 / 0
Normal module process:                     925 passed / 7 isolated / 0 failed
SQLite repository process:                 11/11 passed
SQLite CLI/schema process:                 8 passed / 6 isolated / 0 failed
Ordinary executable process:               9/9 passed
SQLite live-persistence process:           5/5 passed
SQLite-enabled executable process:         9/9 passed
Build-test graph:                          passed

Focused session-related filter:            97/97 passed
Focused update-related filter:             35/35 passed
Whole-tree Zig formatting:                 passed
Git diff validation:                       passed
Embedded Node bridge syntax:               passed
Static pi Debug build:                     passed
pi-sqlite Debug build:                     passed
pi-sqlite-live Debug build:                passed
Real session/update E2E:                   passed
E2E stderr:                                0 bytes
```

The seven normal module-process isolates are intentional linked-SQLite cases. Six pass in the dedicated repository process, and the SQLite CLI integration case passes in its separately linked process. The direct root process explicitly links SQLite and libc and executes every case without skips.

## Remaining parity boundary

Checkpoint 170 materially closes the original startup/live session-resume workflow and native self-update planning/execution. Complete Pi 0.84.1 monorepo equivalence is not claimed.

The largest remaining areas are:

1. Exact upstream session-selector visual grammar, regex search mode, every threaded connector/loading state, and cross-project fork confirmation.
2. Complete Windows self-update replacement, quarantine, rollback, and restart behavior for standalone Zig distributions.
3. The complete fullscreen package install/update/remove manager and the remaining login, settings, and session-administration screens.
4. Exact npm, pnpm, Yarn, and Bun workspace, lockfile, lifecycle-script, global-store, and platform edge cases.
5. Arbitrary asynchronously invalidated extension-owned retained component trees.
6. Function-valued extension providers and extension-owned OAuth/login callbacks.
7. Native server TLS and mutual TLS.
8. Automatic image resizing, EXIF-orientation normalization, and transcoding.
9. Remaining enterprise credential, telemetry, update, retry, and cross-language interoperability breadth.
