# Pi Zig V8 checkpoint 152

Checkpoint 152 continues the native Zig 0.16.0 rewrite from the exact uploaded checkpoint-151 archive and compares behavior directly with the supplied Pi 0.84.1 source tree. This pass closes three concrete compatibility gaps: exact extension-tool call identity with cooperative cancellation, complete tool-local usage/deferred-tool metadata, and package-manifest resources beyond skills.

## Source measurements

```text
Native Zig files under src/:              170
Native Zig logical lines under src/:      87,103
Embedded JavaScript bridge lines:            906
Source-level test declarations:              793
All-package root graph:                      782 cases
Implementation source files changed:          14
Implementation additions/deletions:       +1,456 / -109
Synthetic/generated feature shards:            0
```

## Exact extension tool identity and live cancellation

The upstream extension contract supplies the provider-issued tool call ID and one live `AbortSignal` to `tool.execute()`. Checkpoint 151 still synthesized a tool ID inside the script worker and did not interrupt a pending JavaScript/TypeScript promise.

Checkpoint 152 now:

- carries the exact model/provider tool call ID through the agent loop, extension bridge, persistent worker request, execution callback and renderer state;
- exposes one shared signal as both the third `execute()` argument and `ctx.signal`;
- sends a correlated `abort_current` control record to the persistent worker while a tool promise remains pending;
- aborts without depending on a visible progress/event sink, so print, JSON, RPC and headless embedders retain the same cancellation behavior;
- ignores late progress emitted after cancellation;
- leaves a cooperatively settled worker reusable for later extension calls;
- invalidates a worker after framing or cancellation-protocol corruption rather than allowing stale responses to desynchronize the next invocation;
- exposes the same live signal in lifecycle contexts, including `before_agent_start`, prompt transforms, context transforms, tool hooks and turn/session events.

The compatibility callback remains additive: existing native embedders keep their earlier callback ABI, while the agent prefers the full-fidelity dispatcher when available.

Focused tests verify that the extension receives the literal provider ID, that `signal === ctx.signal`, that the abort event fires before the pending promise settles, that cancellation works with no renderer, and that the worker handles a subsequent request successfully.

## Tool-local usage and deferred tool metadata

Original Pi tool results may carry their own usage/cost accounting and `addedToolNames`. These fields were previously dropped at one or more Zig ownership boundaries.

Checkpoint 152 adds allocator-owned representations for:

```text
usage.input
usage.output
usage.cacheRead
usage.cacheWrite
usage.cacheWrite1h
usage.reasoning
usage.totalTokens
usage.cost.input
usage.cost.output
usage.cost.cacheRead
usage.cost.cacheWrite
usage.cost.total
addedToolNames[]
```

The fields now survive:

- JavaScript/TypeScript live updates and final tool results;
- native extension-host parsing;
- parallel and sequential agent execution;
- `tool_result` / `after_tool` inspection and transactional replacement;
- primary and deferred lifecycle delivery;
- JSON mode progress and terminal events;
- protocol-v1 usage projection where the strict upstream schema defines usage;
- append-only JSONL session persistence;
- session load, fork and statistics;
- allocator cloning and teardown across worker, agent and session ownership domains.

`addedToolNames` remains in the extension/JSON/session contracts but is not injected into protocol-v1 transcript objects because the supplied strict protocol schema does not define that property.

## Full installed-package resource manifests

The earlier Zig package layer persisted local package roots but only exposed conventional `skills/` directories. Checkpoint 152 ports the original `package.json` Pi manifest surface for installed packages:

```json
{
  "pi": {
    "extensions": ["..."],
    "skills": ["..."],
    "prompts": ["..."],
    "themes": ["..."]
  }
}
```

Implemented behavior includes:

- exact manifest-selected files and directories for all four resource classes;
- authoritative manifest semantics: when a valid `pi` object exists, unlisted conventional resources are not silently auto-loaded;
- conventional `extensions/`, `skills/`, `prompts/` and `themes/` fallback when no Pi manifest exists;
- missing-resource isolation;
- stable path deduplication;
- package resources loaded after local project/global resources, preserving the original lower package precedence;
- package extensions in the real startup host;
- package prompts in slash-command template expansion;
- package themes in the native theme registry;
- package skills in startup, `/reload`, RPC `get_commands`, and standalone project-environment loading;
- direct manifest references to either `SKILL.md`, a single skill directory, or a conventional parent skills directory.

The current native package source registry remains local-path based. Manifest glob/filter expressions and managed npm/git install/update lifecycles remain explicit follow-on work rather than being misreported as complete.

## Regression coverage

Checkpoint 152 adds eight source-level declarations over checkpoint 151, including:

1. exact script tool call ID and live signal identity;
2. lifecycle-context abort propagation and worker reuse;
3. full-fidelity dispatch without a visible event sink;
4. rich tool usage and deferred-tool metadata through the JavaScript host;
5. hook replacement of usage and `addedToolNames`;
6. session JSONL reload/fork/statistics preservation;
7. Pi package-manifest resource resolution and authoritative fallback behavior;
8. real project-environment loading of a manifest-selected `SKILL.md` file.

The complete root graph passes 775 cases with seven intentional SQLite process isolates and zero failures. The isolated cases all pass in their dedicated C-linked processes.

## Executable evidence

A real installed package contributed all four resource classes from one `package.json` manifest:

- `extension.ts` registered the executable tool `pkg_meta`;
- a nonconventional exact `skills/pkg-skill/SKILL.md` entry entered the assembled system prompt;
- `prompts/package-prompt.md` expanded `/package-prompt friend` to `CHECKPOINT152_PACKAGE_PROMPT:friend`;
- `themes/package-night.json` loaded as the selected theme without diagnostics.

The mock provider issued tool call ID `provider-call-152`. The extension rejected any other identity and asserted that its two signal references were the same object. The emitted JSON and saved JSONL retained:

```text
usage.input:          11
usage.output:         12
usage.cacheRead:      13
usage.cacheWrite:     14
usage.cacheWrite1h:   15
usage.reasoning:      16
usage.totalTokens:    81
addedToolNames:       ["package-added"]
```

The package skill hook appended a durable `package-resource-check` entry, the expanded user prompt was persisted, the final assistant response was `package-e2e-complete`, and stderr remained empty.

## Archive and reconstruction guarantees

The final checkpoint archive is validated with:

- one top-level `pi-zig-v8-checkpoint-152/` directory;
- no `.git`, Zig caches, `zig-out`, `__pycache__`, or generated build products;
- whole-tree Zig formatting;
- Node.js syntax checking of the embedded bridge;
- real-source audit with zero synthetic feature shards;
- the complete test topology;
- Debug builds of `pi`, `pi-sqlite` and `pi-sqlite-live`;
- exact-ZIP extension/package metadata E2E;
- binary-safe patch application to the uploaded checkpoint-151 source;
- byte-for-byte reconstruction comparison;
- repeat tests/builds from both exact ZIP extraction and patch reconstruction.

## Remaining parity boundary

Checkpoint 152 closes the previously explicit script-tool cancellation gap and extends package resources across all four original classes, but complete Pi 0.84.1 monorepo equivalence is not claimed. The largest remaining areas are:

- multiple-image fidelity through every extension, provider, session and renderer path;
- fully arbitrary extension component trees, overlays, dialogs, editors and asynchronous invalidation;
- function-valued provider transports, custom extension streaming and extension-owned OAuth callbacks;
- automatic installation, isolation, update and removal of extension-owned npm/git dependencies;
- package manifest glob/filter override semantics and user/project package scopes;
- complete wiring of every original coding-agent selector, login, settings and package-management screen into the fullscreen shell;
- native server TLS/mTLS, automatic image resize/transcoding, and the remaining enterprise credential/retry/interoperability matrix.
