# Pi Zig V8 checkpoint 158

Checkpoint 158 continues the native Zig 0.16.0 rewrite from the uploaded checkpoint 157 and compares it against the newly supplied original Pi 0.84.1 source tree. This pass closes the top-level non-package resource configuration gap: automatically discovered and explicitly configured extensions, skills, prompt templates, and themes now share the same inventory, filtering, trust, persistence, and runtime-loading semantics as package resources.

## Scope completed

### Native top-level resource model

A new allocator-owned `top_level_resources` subsystem discovers, resolves, configures, and deinitializes resources from:

- the user agent directory's `extensions/`, `skills/`, `prompts/`, and `themes/` trees;
- trusted project `.pi/extensions`, `.pi/skills`, `.pi/prompts`, and `.pi/themes` trees;
- user `~/.agents/skills` and trusted project ancestor `.agents/skills` directories;
- explicit files, directories, and glob patterns in user or project `settings.json`;
- exact positive and negative selectors already present in settings.

Disabled candidates remain in the inventory so they can be re-enabled. Inventory entries retain origin, scope, source kind, selector, base directory, relative path, effective state, inherited state, and override state.

### Unified configuration selector

`pi config` now merges two origins into one deterministic surface:

```text
package
 top_level
```

Package resources remain first, followed by top-level user and project resources. Fullscreen search, plain output, JSON output, and `--set` all use the same model. JSON records expose both `origin` and stable `selector` fields so automation can distinguish a package identity from a top-level resource base.

Global top-level changes persist exact original-style selectors such as:

```text
+extensions/example.ts
-extensions/example.ts
```

Trusted project mode supports the same inherit/load/unload tri-state as package resources. Returning a project override to inheritance removes the redundant exact decision rather than leaving a materialized copy behind.

### Settings-safe transactions

Top-level settings changes use the same package-operation advisory lock as package configuration. The lock covers the complete read-modify-write transaction, preventing a package selector and a top-level selector—or two top-level selectors—from overwriting one another.

Settings persistence is atomic and preserves unrelated fields. Missing files are treated as empty configuration only for `FileNotFound`; malformed JSON, permission errors, and other read failures propagate instead of being silently replaced with `{}`.

### Runtime-exact resource loading

The live agent no longer unconditionally scans default directories after configuration filtering. Startup now resolves exact enabled top-level paths and threads them into:

- JavaScript/TypeScript and native extension loading;
- skill discovery and project-context construction;
- prompt-template discovery and slash expansion;
- theme registry loading;
- RPC command discovery;
- project-environment loading.

The `/reload` skill path was separately audited and fixed so a settings change is reapplied rather than bypassed by a later default-directory scan. The no-live slash-command fallback uses the same filtered resource view.

### Scope and precedence

The resolver retains the original trust boundary and precedence model:

- trusted project resources precede user resources at runtime;
- project settings can override inherited user top-level resources;
- exact configured paths can opt resources back in after a broad exclusion;
- untrusted project directories are neither inventoried nor executed;
- duplicate canonical paths are stable and deterministic.

Windows separator normalization and colon-containing selector paths are handled without truncating the resource base.

## Regression coverage

Checkpoint 158 adds native tests for:

- disabled automatic resources remaining configurable;
- explicit top-level sources preserving unrelated settings;
- malformed settings rejection without destructive replacement;
- project unload, load, and return-to-inheritance after materialisation;
- mixed package/top-level inventory and stable origin ordering;
- settings-filtered project environment skills;
- `/reload` reapplying changed top-level skill settings;
- exact path loading with defaults disabled.

Complete build-test graph:

```text
all-package module graph: 830 passed, 7 skipped, 0 failed (837 cases)
SQLite repository:        11/11 passed
SQLite CLI/schema:         8 passed, 6 isolated, 0 failed
ordinary executable:       5/5 passed
SQLite persistence:        5/5 passed
SQLite executable:         5/5 passed
```

The seven aggregate skips remain deliberate C-linked SQLite isolates executed successfully in the dedicated processes above.

## Real executable gates

The exact executable validation covers:

- discovery of all four top-level resource classes;
- a TypeScript extension executing while enabled and disappearing from the real tool schema when disabled;
- a prompt template expanding while enabled and remaining literal when disabled;
- trusted project unload, load, and inheritance restoration;
- removal of the final project override;
- twelve simultaneous two-process settings mutations with both decisions preserved in every round;
- zero stderr from the enabled extension run.

The detailed record is in `RESOURCE-E2E-158.txt`.

## Remaining parity boundary

Checkpoint 158 materially closes top-level resource-origin editing and runtime filtering, but complete Pi 0.84.1 monorepo equivalence is not claimed. The highest-value remaining areas are:

- the complete package source install/update/remove fullscreen manager and richer origin grouping;
- reconstructing extension workers, prompt templates, and active theme state during a live `/reload`, rather than only reloading skills/context;
- complete npm/pnpm/Bun workspace, lockfile, lifecycle-script and platform behavior;
- arbitrary asynchronously invalidated extension component trees;
- function-valued provider transports and extension-owned OAuth callbacks;
- remaining fullscreen model, login, settings and session screens;
- native server TLS and mutual TLS;
- automatic image resizing, EXIF-orientation normalization and transcoding;
- the remaining enterprise credential, retry, telemetry and cross-language interoperability matrix.
