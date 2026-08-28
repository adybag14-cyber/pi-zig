# Pi Zig V8 checkpoint 155

Checkpoint 155 continues the native Zig 0.16.0 rewrite against the supplied Pi 0.84.1 source and checkpoint 154. This pass focuses on the original package manager's scope, trust, command-wrapper, and temporary-extension behavior, then closes a TypeScript runtime failure exposed by an installed npm-package end-to-end test.

## Scope completed

### User, project, and temporary package scopes

Package configuration and installation now distinguish three original scopes:

- `user`: persistent configuration and managed installs below the Pi agent directory;
- `project`: persistent configuration and managed installs below the trusted project's `.pi/` directory;
- `temporary`: process-requested extension sources below the agent-private temporary root, with no persistent registry entry.

Project package storage is not opened or mutated unless project trust has been resolved for the current process. Package install and removal accept `-l`/`--local`, while `--approve` and `--no-approve` participate in the same trust policy used by normal startup.

### Cross-scope precedence and project deltas

Configured resources are resolved in project-before-user order. Package identity ignores npm versions and Git references, and normal project records replace matching user records.

A project record with `autoload: false` is treated as a selective delta over the corresponding user installation. The project record reuses the user package's installed path, applies ordered per-resource decisions first, and leaves unmentioned resources for the lower user record. Explicit disabled decisions become first-wins tombstones so a lower-precedence package cannot reintroduce a project-disabled resource.

### Legacy package settings compatibility

When a scope has no native `packages.json`, checkpoint 155 reads the original `settings.json` `packages` array. Both string entries and object entries are supported, including:

- `source`;
- `autoload`;
- `extensions`;
- `skills`;
- `prompts`;
- `themes`.

Local paths are resolved relative to the scope's configuration root. Npm and Git sources are mapped to their managed user or project locations. The first native mutation writes an atomic `packages.json`; that file then becomes authoritative without destructively rewriting the historical settings file.

### Configurable npm-compatible command

Settings now parse and merge argv-style `npmCommand` arrays. Empty, malformed, oversized, and NUL-containing entries are ignored rather than poisoning startup.

The configured command is used for:

- managed npm installation;
- managed npm removal;
- npm package updates;
- dependency installation inside managed Git packages;
- temporary npm extension sources.

The host recognizes npm, pnpm, and bun even when they appear after a wrapper separator such as:

```json
{"npmCommand":["mise","exec","node@20","--","pnpm"]}
```

Manager-specific peer-dependency and install-root arguments follow the original implementation's behavior.

### Package operation locking

Persistent and temporary package mutations acquire an advisory exclusive lock in the target package root. Lock acquisition is nonblocking with bounded retries and returns a specific operation-locked error instead of hanging indefinitely. Update reuses the already-held lock rather than recursively reacquiring it.

Atomic registry replacement and managed-path confinement from checkpoint 154 remain intact.

### Explicit package sources for `--extension`

`-e`/`--extension` now accepts:

- direct JavaScript or TypeScript files;
- local package directories;
- `npm:` package specifications;
- supported Git URLs.

Each source is resolved through the temporary package scope. Managed npm and Git sources can therefore be downloaded and loaded for the current process without modifying user or project package configuration. Offline mode remains a hard network gate, and installed-package manifests can contribute multiple extension entrypoints.

### TypeScript packages below `node_modules`

The temporary npm end-to-end gate exposed Node's `ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING`: Node 22's default TypeScript loader refuses to transform `.ts` files below `node_modules`, even though original Pi packages commonly publish extension source there.

The embedded extension bridge now registers a trusted synchronous load hook for `.ts`, `.mts`, and `.cts` file URLs. It reads the package entrypoint, applies Node's `stripTypeScriptTypes()` in transform mode, and returns an explicit module format. This preserves enum and other transform-requiring TypeScript syntax while keeping the existing Pi import shims and real extension-local dependency resolution.

A dedicated Zig regression test loads an enum-bearing TypeScript extension from `node_modules/package-155/index.ts`. A real executable test also installs a temporary npm package through a configured pnpm-compatible command and executes its TypeScript tool successfully.

## CLI additions and changes

```text
pi install <source> [-l|--local] [--approve|--no-approve] [--offline] [--json]
pi list [--approve|--no-approve] [--json]
pi update [name|source|path] [--approve|--no-approve] [--offline] [--json]
pi remove <name|source|path> [-l|--local] [--approve|--no-approve] [--json]
pi ... -e <path|npm:SPEC|GIT-URL>
```

Machine-readable package listings now include the package scope and autoload state.

## Validation summary

Completed validation includes:

- package/source/resource suite: 28/28;
- JavaScript runtime suite: 10/10;
- argument parser suite: 6/6;
- settings wrapper suite: 16/16;
- trust wrapper suite: 22/22;
- ordinary executable tests observed during the build-test attempt: 5/5;
- SQLite repository tests observed during the build-test attempt: 11/11;
- whole-tree formatting and Node bridge syntax checks;
- real-source audit: 172 Zig files, 91,221 Zig lines, zero synthetic files;
- Debug builds of `pi`, `pi-sqlite`, and `pi-sqlite-live`;
- direct local temporary extension end-to-end execution;
- configured pnpm user and project package lifecycle execution;
- temporary npm TypeScript extension end-to-end execution.

The monolithic all-package Debug test artifact was attempted through both the build graph and direct root compilation. Compilation exceeded the command deadline without emitting a failed test. Checkpoint 155 does not claim an aggregate pass that was not observed.

## Remaining parity boundary

Checkpoint 155 materially closes scoped package configuration, project package trust, temporary package extensions, package-manager command wrappers, and installed TypeScript entrypoints. Complete Pi 0.84.1 monorepo equivalence is not yet claimed.

The highest-value remaining areas are:

- the original package selector/configuration TUI and resource-origin editing workflows;
- richer interprocess package-operation coordination, repair markers, and interrupted-update recovery;
- automatic migration that removes old package entries from historical settings after verified native persistence;
- complete npm/pnpm/bun lockfile and update-result parity across platform-specific wrappers;
- arbitrary asynchronous extension component trees and invalidation;
- function-valued provider transports and extension-owned OAuth callbacks;
- complete fullscreen selector/login/settings/package screens;
- native server TLS and mutual TLS;
- automatic image resizing, orientation normalization, and transcoding;
- the remaining enterprise credential, retry, and cross-language interoperability matrix.
