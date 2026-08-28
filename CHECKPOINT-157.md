# Pi Zig V8 checkpoint 157

Checkpoint 157 continues the native Zig 0.16.0 rewrite from the uploaded checkpoint 156 and compares it against the newly supplied original Pi 0.84.1 source tree. This pass closes the package-origin configuration-screen gap and makes package coordination observable without weakening the atomic package lifecycle completed in checkpoint 156.

## Scope completed

### Native package-resource inventory

The new allocator-owned configuration model discovers all manifest-approved or conventional package resources, including resources currently disabled by package filters. It records:

- package name, canonical source, installed path and source scope;
- extension, skill, prompt or theme resource type;
- exact and display-relative paths;
- effective enabled state;
- inherited user state in project mode;
- exact `inherit`, `load` or `unload` override state.

Inventory ordering is deterministic by package source, resource type, display name and path. The same model feeds fullscreen, plain-text and JSON output so those surfaces cannot drift semantically.

### Global and project-local resource editing

`pi config` now supports:

```text
pi config [-l|--local] [-a|--approve] [--json]
pi config ... --set PACKAGE TYPE PATH <load|unload|inherit>
```

Global mode toggles exact resources with the original `+path` / `-path` selectors. Trusted project mode creates `autoload:false` package deltas and cycles among inherited, explicit load and explicit unload. Returning the final resource to inheritance prunes the empty project delta.

Package selectors accept the configured package name, canonical source or installed path. Absolute or empty resource paths are rejected, project storage remains inaccessible without trust, and global `inherit` is rejected because only project scope has an inherited lower layer.

### Fullscreen package selector

When stdin and stdout are terminals, `pi config` opens a native retained alternate-screen selector with:

- incremental case-insensitive search across package, source, type, name and path;
- Up/Down, Home/End and Page Up/Page Down navigation;
- Space or Enter resource changes;
- Tab global/project scope switching when the project is trusted;
- project tri-state cycling that follows the inherited state;
- width-aware Unicode-safe truncation;
- disabled and inherited visual states;
- operation errors shown without terminating the selector;
- deterministic terminal restoration on Escape, Ctrl-C, Ctrl-D or EOF.

Non-TTY callers receive a grouped plain-text inventory. `--json` emits stable structured state suitable for automation.

### Lost-update-safe configuration transactions

The first selector implementation exposed a real concurrency issue during audit: it loaded `packages.json`, mutated the in-memory copy, and acquired the operation lock only for the final save. Two selectors could therefore read the same old registry and overwrite one another serially.

Checkpoint 157 replaces that boundary with `updateScopeConfiguration()`. The lock now covers:

1. registry read or legacy fallback;
2. resource mutation;
3. atomic `packages.json` replacement;
4. persistence verification;
5. legacy cleanup.

Allocator ownership is preserved when project delta arrays grow or shrink, including allocation-error paths. A twelve-round two-process executable stress gate disabled two different resources simultaneously and retained both selectors in every round.

### Observable package-operation ownership

The stable `.packages.lock` inode now carries synchronized JSON metadata while held:

```text
pid
operation
startedMs
registryDir
```

Supported operation identities include install, update, remove, repair and configure. A clean owner clears the payload before releasing the advisory lock. A non-empty payload on an unlocked file is classified as stale evidence rather than an active owner.

Native inspection returns active/stale state and owned metadata without blocking. The implementation does not infer ownership from PID existence: the advisory lock remains authoritative, avoiding PID-reuse errors.

### `pi repair --check` and startup diagnostics

The package administration surface now includes a non-mutating check:

```text
pi repair [-l|--local] [-a|--approve] --check [--json]
```

It reports:

- active operation and owner metadata;
- stale lock metadata;
- interrupted managed-Git repair-marker count;
- pending legacy `settings.json.packages` migration;
- native registry presence.

Interactive agent startup inspects user and trusted project scopes and prints actionable warnings for active owners, stale evidence, interrupted update journals and legacy migration state. Machine-readable commands remain free of unsolicited diagnostic text.

## Regression coverage

Checkpoint 157 adds native tests for:

- disabled package resources remaining visible in global inventory;
- exact global toggle persistence;
- project unload and return-to-inheritance pruning;
- independent selectors surviving locked sequential edits;
- fullscreen project-state cycle semantics;
- active operation-owner metadata and clean release;
- stale metadata, interrupted markers and legacy migration health;
- package command parsing for `config --set` and `repair --check`.

Focused results:

```text
packages.zig:             34/34 passed
package_config.zig graph: 37/37 passed
args.zig:                  9/9 passed
```

Complete build graph:

```text
all-package module graph: 823 passed, 7 skipped, 0 failed
SQLite repository:        11/11 passed
SQLite CLI/schema:         8 passed, 6 isolated, 0 failed
ordinary executable:       5/5 passed
SQLite persistence:        5/5 passed
SQLite executable:         5/5 passed
```

The seven aggregate skips remain the deliberate C-linked SQLite isolates executed successfully in the dedicated processes above.

## Executable gates

Real executable validation covers:

- install → inventory → global unload → project unload → inheritance → health check;
- a real pseudo-terminal alternate-screen render, Space toggle, Escape close and exact filter persistence;
- active lock-owner inspection followed by stale-metadata classification after an external unlock;
- twelve simultaneous two-process configuration rounds with zero lost updates.

The detailed record is in `CONFIG-E2E-157.txt`.

## Remaining parity boundary

Checkpoint 157 materially closes the package-origin selector and operation-observability gaps, but complete Pi 0.84.1 monorepo equivalence is not claimed. The highest-value remaining areas are:

- top-level auto and explicit extension/skill/prompt/theme origin editing in the selector;
- the full package source install/update/remove screen and richer resource grouping;
- complete npm/pnpm/Bun lockfile, workspace, lifecycle-script and platform behavior;
- arbitrary asynchronously invalidated extension component trees;
- function-valued provider transports and extension-owned OAuth callbacks;
- remaining fullscreen model, login, settings and session screens;
- native server TLS and mutual TLS;
- automatic image resizing, EXIF-orientation normalization and transcoding;
- the remaining enterprise credential, retry, telemetry and cross-language interoperability matrix.
