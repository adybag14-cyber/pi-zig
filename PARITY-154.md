# Pi 0.84.1 → Zig checkpoint 154 parity audit

## Closed in checkpoint 154

### Manifest and conventional package resources

The Zig package loader now resolves the four original resource classes—extensions, skills, prompt templates, and themes—from authoritative Pi manifests or conventional directories. It supports direct files, directories, recursive patterns, native extension manifests, script entrypoints, and nested package extension declarations.

### Globs, ignores, and ordered filters

The new resolver implements the package pattern behavior needed by the supplied original source:

- `*`, `**`, `?`, and character classes;
- ordered `!`, `+`, and `-` selectors;
- stable deduplication;
- package `autoload` gating with explicit positive opt-in;
- `.gitignore`, `.ignore`, and `.fdignore` traversal rules;
- nested ignore precedence and negation;
- concrete manifest paths overriding broad ignores;
- canonical symlink-cycle protection and traversal bounds.

A broad extension pattern no longer promotes helper modules into runnable extension entries. Resource discovery is type-aware.

### Package source identity

Local paths, direct scripts, npm specifications, scoped/aliased npm packages, Git URLs, historical Git shorthand, and optional references now have native parsed identities. Unsafe encoded traversal, malformed repositories, and unsafe references are rejected.

### Managed lifecycle

The executable now performs:

- local and direct-script registration;
- npm installation into an agent-private project;
- Git clone/checkout into an agent-private tree;
- update by name, source, or resolved path;
- exact npm-pin and local-source classification;
- offline-safe update reporting;
- managed npm uninstall;
- confined managed Git removal and parent pruning;
- atomic registry writes;
- filter-preserving reinstall and update.

### Evidence

- 801 source-level Zig test declarations.
- Root graph: 800 pass, 7 intentional SQLite isolates, 0 fail.
- Dedicated SQLite and executable suites pass.
- 21 focused package/source/resource tests pass.
- Local-directory and direct-script executable gates pass.
- Isolated npm registry: 1.0.0 install → 1.0.1 update → removal.
- Local Git daemon: 1.0.0 clone → 1.1.0 update → removal.
- All three Debug executables compile with supplied Zig 0.16.0.
- Exact ZIP extraction and checkpoint-153 patch reconstruction each match 250 source/report files and independently pass the complete topology.
- Package lifecycle E2Es pass again using the executable built from the exact source ZIP.

## Still partial or absent

### Package scopes and trust merge

Checkpoint 154 uses one persistent agent package registry. The original's full user/project/temporary scope merge, project override entries, trust-dependent loading, and scope-specific source normalization are not yet complete.

### Package management UX and coordination

The CLI lifecycle is functional, but the original package/config selectors, source-object editor, background update suggestions, repair markers, operation locks, progress surfaces, and full concurrent install/update coordination remain incomplete.

### Package manager variants and migrations

The managed npm path currently uses npm. Configurable `npmCommand` execution, pnpm/bun-specific linking and cleanup, legacy globally installed package migration, and all self-update/package-manager inference cases remain incomplete.

### Extension UI/runtime breadth

The JavaScript/TypeScript bridge is broad, but fully arbitrary asynchronous component trees, invalidation, custom overlays/editors, and every renderer lifecycle are not complete.

### Provider extensibility and enterprise authentication

Declarative providers are native. Function-valued transports, extension-owned OAuth/login callbacks, complete cloud bootstrap proxying, and the full enterprise retry/credential matrix remain incomplete.

### Image preprocessing, TLS, and fullscreen breadth

Ordered multi-image fidelity is complete in the implemented paths, but automatic resize, EXIF rotation, format conversion, provider-limit adaptation, native server TLS/mTLS, and every original fullscreen screen remain incomplete.

## Assessment

Checkpoint 154 replaces the prior manifest-only package approximation with a deterministic resource resolver and an executable managed lifecycle. The remaining package work is primarily scope/trust integration, package-manager variants, repair/concurrency behavior, and native UX—not absence of npm/Git installation or resource filtering.
