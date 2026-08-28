# Pi 0.84.1 parity audit — checkpoint 152

Checkpoint 152 is compared directly with the supplied Pi 0.84.1 source tree. It is a native Zig rewrite with an embedded JavaScript/TypeScript compatibility worker, not a claim that every monorepo package and edge case is already reproduced.

## Closed in checkpoint 152

### Extension cancellation and identity

- Provider-issued `toolCallId` reaches script `tool.execute()` unchanged.
- The third `execute()` argument and `ctx.signal` reference one live cancellation signal.
- Native abort state is forwarded into a pending script promise through a correlated worker control frame.
- Cancellation works in headless/no-renderer execution.
- Late updates are ignored after abort and cooperatively settled workers remain reusable.
- Lifecycle contexts receive the same live abort state.

### Tool-result metadata

- Tool-local token usage, cache usage, reasoning usage and cost fields are owned and preserved.
- `addedToolNames` is retained through live/final extension results, hooks, JSON events and JSONL sessions.
- Metadata survives session load, fork and statistics.
- Strict protocol-v1 output includes only fields defined by the supplied protocol schema.

### Installed package resources

- Installed package `pi.extensions`, `pi.skills`, `pi.prompts` and `pi.themes` exact paths are resolved.
- A Pi manifest is authoritative; absent manifests use conventional resource directories.
- Package resources participate in startup, reload, RPC command discovery and project-environment loading.
- Direct `SKILL.md`, single-skill directory and parent skills-directory forms are accepted.
- Package precedence remains below local global/project resources.

## Retained native coverage

Checkpoint 152 retains the complete earlier native surface, including:

- multi-provider streaming model transports and provider/runtime separation;
- durable branch-aware JSONL sessions, migrations, search, stats and administration;
- native tools, filtering, cancellation and live bash progress;
- JSON, RPC and remote protocol clients/servers;
- optional canonical SQLite repository and live persistence server;
- retained Unicode-aware TUI layout, input, Markdown, LaTeX and terminal images;
- original JavaScript/TypeScript extension discovery, persistent execution, hooks, tools, commands, shortcuts, UI dialogs, runtime actions, providers and custom renderers;
- ordered extension action replay and executable replacement/delegation for built-in tools;
- rich live extension tool updates, details, first-image content, result hooks and deterministic worker teardown.

## Validated executable package path

One installed package supplied extension, skill, prompt and theme resources from one manifest. The real executable expanded the prompt, observed the package skill in `before_agent_start`, executed the package tool under the exact provider call ID, emitted tool usage plus `addedToolNames`, persisted those values to JSONL, and completed with zero stderr.

## Partial or intentionally bounded areas

- Package manifests currently resolve exact files/directories. Glob patterns and `!`, `+`, `-` filter overrides are recognized as non-path expressions but are not yet evaluated by the native package filter engine.
- Package configuration remains a user-level local-path registry; managed npm/git installation, updates, lock/install isolation and project-scoped configuration remain incomplete.
- Rich tool content retains one image through the current compatibility bridge rather than arbitrary image arrays.
- Extension UI supports native compatibility components and retained shell state, not every arbitrary upstream component/render invalidation behavior.
- Declarative providers are native; function-valued extension transports and complete extension-owned OAuth/login lifecycles remain incomplete.

## Highest-value remaining work

1. Multiple-image content arrays across extension, agent, provider, JSONL, protocol and renderer boundaries.
2. Arbitrary extension component trees with asynchronous invalidation and complete overlay/editor lifecycles.
3. Function-valued provider implementations, streaming callbacks and extension-owned OAuth.
4. Full package-source manager for npm/git/local sources, scopes, updates, filters and dependency isolation.
5. Remaining original fullscreen selectors, settings, login, session and package-management screens.
6. Native server TLS/mTLS, automatic image normalization and enterprise credential/retry interoperability.
