# Pi Zig V8 checkpoint 156

Checkpoint 156 continues the native Zig 0.16.0 rewrite from the uploaded checkpoint 155 and compares the result against the newly supplied original Pi 0.84.1 source tree. This pass closes the package durability gaps left explicitly open by checkpoint 155: interrupted managed-Git updates, verified legacy package migration, and an executable recovery surface.

## Scope completed

### Durable managed-Git update journals

Managed Git installation and update now use a durable sibling journal named:

```text
.<package>.pi-update-incomplete
```

The journal records the normalized target checkout, prepared replacement, and previous backup before any destructive rename. All three paths must remain in the target's parent directory and must use the expected target-derived `tmp`/`old` prefixes. A malformed or path-escaping journal is rejected rather than followed.

The swap sequence is now:

1. clone and prepare dependencies in a fresh sibling checkout;
2. atomically write the recovery journal;
3. move the existing target to a sibling backup when present;
4. move the prepared checkout into the canonical target path;
5. remove the backup;
6. remove the journal only after the target is committed.

If the process stops between those stages, the next repair can deterministically finish the prepared commit, restore the backup, or clean stale siblings when the canonical target already exists.

### Target recovery before later package operations

Git install/update/remove paths inspect the target-specific journal before mutating that package again. This prevents a later command from layering a second checkout swap over an unresolved first operation.

Cleanup remains root-confined. Managed package removal validates the expected host/repository path and now also clears a valid target journal after recovery.

### Explicit package repair command

The executable now exposes:

```text
pi repair [-l|--local] [--approve|--no-approve] [--json]
```

User repair scans only the agent-private managed Git root. Project repair is available only after the existing project-trust policy approves access to that project's `.pi` package root.

Machine-readable output reports:

```text
scope
markersFound
committedPreparedUpdates
restoredBackups
cleanedArtifacts
removedMarkers
migratedLegacyPackages
cleanedLegacySettings
```

Marker traversal is bounded, skips `.git` and `node_modules`, sorts discovered journals for deterministic handling, and never follows journal paths outside the corresponding package directory.

### Verified legacy package migration

When `packages.json` is absent and the historical `settings.json.packages` array exists, repair now:

1. parses the original string/object package entries;
2. writes native `packages.json` through atomic replacement;
3. reads the new registry back;
4. validates the persisted package count and identity-bearing fields;
5. only then atomically rewrites `settings.json` without `packages`;
6. preserves every unrelated settings field.

Normal package mutations also perform best-effort legacy cleanup only after their native registry write has been verified. A failed or malformed persistence step therefore cannot erase the user's only package configuration.

### Recovery behavior

A valid journal is resolved according to observable filesystem state:

- canonical target exists: remove stale prepared and backup siblings;
- target missing, prepared checkout exists: commit the prepared checkout and remove the backup;
- target and prepared checkout missing, backup exists: restore the backup;
- no usable target/prepared/backup state: return an explicit invalid-repair-state error and retain evidence.

The marker is removed only after successful recovery.

## Regression coverage

Checkpoint 156 adds native tests for:

- migration of legacy package settings only after verified native persistence;
- committing a prepared Git checkout and cleaning its backup;
- restoring a backup when the prepared checkout disappeared;
- rejecting a journal whose artifact path escapes the target parent;
- CLI recognition of `repair` with local/trust/JSON arguments.

Focused results:

```text
packages.zig:        32/32 passed
args.zig:             7/7 passed
js_runtime.zig:      10/10 passed
```

The complete build graph also finished:

```text
all-package module graph: 815 passed, 7 skipped, 0 failed
SQLite repository:        11/11 passed
SQLite CLI/schema:         8 passed, 6 isolated, 0 failed
ordinary executable:       5/5 passed
SQLite persistence:        5/5 passed
SQLite executable:         5/5 passed
build steps:              13/13 succeeded
```

The seven root-graph skips are the deliberate C-backed SQLite isolates already executed in their dedicated linked processes.

## Executable recovery gate

The real Debug `pi` executable was run against a temporary agent directory containing both:

- a prepared Git checkout, previous backup, and durable update journal;
- a legacy `settings.json.packages` record plus an unrelated `theme` setting.

`pi repair --json` committed the prepared checkout, removed the backup and marker, migrated the package to `packages.json`, removed only the legacy `packages` field, preserved `theme`, and returned the expected counters. The detailed record is in `PACKAGE-REPAIR-E2E-156.txt`.

## Remaining parity boundary

Checkpoint 156 materially closes the interrupted package-update and verified legacy-cleanup gaps, but complete Pi 0.84.1 monorepo equivalence is not claimed. The highest-value remaining areas are:

- the original package selector/configuration TUI and resource-origin editing;
- richer multi-process operation ownership, stale-owner diagnostics, and startup repair presentation;
- complete npm/pnpm/Bun lockfile and platform-specific update-result behavior;
- arbitrary asynchronously invalidated extension component trees;
- function-valued provider transports and extension-owned OAuth callbacks;
- complete fullscreen model/login/settings/session/package screens;
- native server TLS and mutual TLS;
- automatic image resizing, EXIF-orientation normalization, and transcoding;
- the remaining enterprise credential, retry, and cross-language interoperability matrix.
