# Pi Zig V8 checkpoint 154

Checkpoint 154 continues the native Zig 0.16.0 rewrite against the supplied Pi 0.84.1 source and checkpoint 153. Its main objective is to close the package-resource and managed-package lifecycle gap identified in checkpoint 153 without weakening extension trust, path confinement, offline operation, or deterministic startup.

## Scope completed

### Original Pi package-resource resolution

Installed packages now expose extensions, skills, prompt templates, and themes through the same two broad mechanisms as the original implementation:

- authoritative `package.json` `pi` manifests;
- conventional `extensions/`, `skills/`, `prompts/`, and `themes/` directories when no Pi manifest is present.

Manifest entries support concrete files, directories, and resource-aware glob expansion. Extension discovery understands direct script files, native `extension.json` manifests, conventional `index.ts`/`index.js` variants, and nested package manifests. Skill, prompt, and theme discovery remains type-aware so a broad package pattern does not accidentally reinterpret unrelated helper files as executable extensions.

A valid Pi manifest is authoritative. When a manifest intentionally selects no resource of a given type, checkpoint 154 no longer falls back to package-root extension discovery and silently loads files the package author did not declare.

### Ordered resource selectors

Package records can persist per-resource selectors for:

- extensions;
- skills;
- prompt templates;
- themes.

The resolver implements the original selector forms:

- ordinary patterns select matching resources;
- `!pattern` excludes matches;
- `+pattern` force-includes exact or matching resources;
- `-pattern` removes resources from the accumulated set.

Selectors are evaluated in order, deduplicated stably, and retained across list, reinstall, and update operations. `autoload: false` disables implicit package loading while still allowing exact positive selectors to opt individual resources back in.

### Glob and ignore semantics

The new native resource resolver supports the package patterns needed by the supplied original source:

- `*`, `**`, and `?`;
- character classes and negated classes;
- normalized slash matching;
- files and directories;
- recursive resource discovery with bounded depth and node counts;
- symlink following with canonical cycle protection.

Resource walks honor `.gitignore`, `.ignore`, and `.fdignore` files in ancestor and nested directories. Later nested rules take precedence, negation is supported, and ignored directories are pruned when safe. A concrete manifest path remains authoritative and can select a file that broad ignore rules would otherwise hide.

### Native package-source parser

Checkpoint 154 adds a dedicated parser for:

- local paths and `path:` sources;
- direct JavaScript and TypeScript extension files;
- `npm:` package specifications;
- scoped npm packages and npm aliases;
- exact semver pins, including `v`-prefixed versions;
- HTTPS/SSH/Git-protocol repository URLs;
- the historical `git:` shorthand;
- optional Git references.

The parser keeps `git://` URLs distinct from the historical `git:` prefix, validates host/repository/reference components, rejects unsafe percent-decoded traversal, and avoids treating an arbitrary `git@host:path` token as a managed source when it should remain a local-path input.

### Atomic package registry

`packages.json` now stores source identity, resolved path, autoload state, and optional resource filters. Registry writes use atomic replacement and include a terminal newline. Reads remain tolerant of the earlier checkpoint format.

Reinstalling a source preserves the package's existing autoload and resource-filter configuration rather than resetting it. Local directory names are taken from `package.json` when available; direct extension files receive stable file-based identities.

### Managed npm lifecycle

Npm packages are installed into an agent-private managed project under the Pi agent directory. The implementation:

- creates a private package project and lockfile;
- installs package specifications with peer-dependency compatibility;
- resolves scoped and alias package paths;
- records the canonical managed source and resolved package directory;
- updates unpinned packages in place;
- recognizes and skips exact semver pins;
- uninstalls managed packages and removes their registry entries;
- refuses network work under `--offline` or `PI_OFFLINE`.

A real isolated npm-registry fixture installed version 1.0.0, changed the advertised package to 1.0.1, updated the managed package, and removed it successfully.

### Managed Git lifecycle

Git packages are stored beneath an agent-private host/repository hierarchy. Installation uses a temporary checkout, optional reference checkout, dependency installation, and replacement of the prior managed tree only after the new checkout succeeds.

Update, removal, and cleanup preserve root confinement. A tampered registry entry cannot cause deletion outside the managed Git root. Empty managed parent directories are pruned after removal.

A real local Git daemon fixture installed version 1.0.0, received a new 1.1.0 commit, updated the package, and removed the managed checkout successfully.

### Package CLI

The native executable now provides machine-readable and human-readable package administration:

```text
pi install <path:PATH|npm:SPEC|GIT-URL> [--offline] [--json]
pi list [--json]
pi update [name|source|path] [--offline] [--json]
pi remove <name|source|path> [--json]
```

`remove` also accepts the historical `uninstall` alias. Queries can match package name, canonical source, or resolved path. Update output distinguishes updated packages, local packages, exact pins, and offline skips.

## Safety and compatibility

- Existing checkpoint package records remain readable.
- Package filters survive reinstall and update.
- Managed deletions are confined to the native package roots.
- Local package removal changes configuration only; it never deletes the user's source tree.
- Invalid manifests, missing optional resources, and individual ignored files are isolated rather than aborting unrelated packages.
- Direct extension files can be installed and removed without manufacturing a package directory.
- Network package installation and updates have an explicit offline gate.
- Resource enumeration has deterministic ordering and traversal bounds.
- No generated feature shards or synthetic source inflation were introduced.

## Validation summary

The implementation was checked with the supplied Zig 0.16.0 toolchain.

```text
Native Zig source files:                   172
Native Zig logical lines:                  90,091
Embedded JavaScript bridge lines:          915
Source-level Zig test declarations:        801
Synthetic/generated feature shards:        0

All-package root graph:                    800 passed
Intentional root SQLite isolates:          7
Root failures:                             0
Root graph total:                          807

Dedicated SQLite repository:               11/11 passed
Dedicated SQLite persistence:              5/5 passed
SQLite CLI/ABI/schema process:              8 passed, 6 isolated, 0 failed
Ordinary executable suite:                 5/5 passed
SQLite-enabled executable suite:           5/5 passed

Whole-tree formatting:                     passed
Git diff validation:                       passed
Static pi Debug build:                     passed
pi-sqlite Debug build:                     passed
pi-sqlite-live Debug build:                passed
```

## Real package gates

Four executable-level package gates passed:

```text
Local package lifecycle:                   PASS
Direct TypeScript-file lifecycle:          PASS
Managed npm install/update/remove:          PASS
Managed Git clone/update/remove:            PASS
```

The managed npm gate upgraded `1.0.0` to `1.0.1`. The managed Git gate upgraded `1.0.0` to `1.1.0`. Both finished with empty package lists after removal.

## Archive and reconstruction validation

The exact source ZIP was extracted into a separate cache-free directory. Its 250 files matched the frozen committed tree by content and executable-bit identity, then passed the complete 807-case test topology and all three Debug builds.

The binary-safe checkpoint 153 → 154 patch was applied to a pristine extraction of the supplied checkpoint 153 archive. The reconstructed 250-file tree matched checkpoint 154 by content and executable-bit identity and independently passed the complete test topology and all three builds.

The package lifecycle E2Es were repeated with the executable built from the exact frozen source ZIP, using only loopback npm and Git fixtures.

## Remaining parity boundary

Checkpoint 154 closes the package-manifest glob/filter core and adds a real managed npm/Git lifecycle, but complete Pi 0.84.1 monorepo equivalence is still not claimed. The largest remaining areas are:

1. full user/project/temporary package scopes and the original trust/override merge model;
2. the original package selector/configuration screens, source-object editor, update suggestions, repair markers, and concurrent package-operation coordination;
3. configurable `npmCommand` wrappers and complete npm/pnpm/bun-specific installation behavior;
4. automatic installation of missing configured sources and complete legacy package migrations;
5. arbitrary asynchronous extension component trees and invalidation;
6. function-valued provider transports and extension-owned OAuth callbacks;
7. complete native fullscreen model/login/settings/session/package screen wiring;
8. native server TLS/mTLS, automatic image preprocessing, and the remaining enterprise credential/retry/interoperability matrix.
