# Pi Zig checkpoint 146

Checkpoint 146 continues the native Zig 0.16.0 rewrite against the supplied original Pi 0.84.1 source. Its primary goal is to replace the previous manifest-only extension boundary with executable compatibility for the original JavaScript/TypeScript extension ecosystem while preserving the native Zig host's trust, lifecycle, validation, tool, session and terminal ownership.

## Reference and baseline

- Original reference: `pi-main (3)(6).zip` (Pi 0.84.1)
- Original SHA-256: `42162e1ea09cfaf78ec737862255b919789eef7defd73f413dbb58c8dee0aa1a`
- Exact patch baseline: uploaded `pi-zig-v8-checkpoint-145(1).zip`
- Baseline SHA-256: `82bc500a436d009647ba6e965260f79d4512f22246c2def62ca2b3ba1294572f`
- Compiler: supplied Zig 0.16.0 Linux x86-64 archive
- Toolchain SHA-256: `70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00`
- Script-runtime validation: Node.js 22.16.0

## Measurements

```text
Native Zig source files under src/:       167
Native Zig logical lines under src/:       79,230
Embedded JS bridge lines:                  358
Gain over checkpoint 145:                  1 Zig file / 1,720 Zig lines
Baseline-to-final implementation diff:     10 source files
Implementation additions/deletions:        +2,201 / -123
Zig test declarations (named + anonymous): 754
Net test-declaration gain:                 14
Synthetic/generated feature shards:        0
```

## Persistent original extension runtime

The native extension host now accepts original Pi script extensions in addition to the existing isolated `extension.json` executable ABI:

```text
*.ts  *.mts  *.cts
*.js  *.mjs  *.cjs
```

The bridge source is embedded in the static `pi` executable. A Node process is launched only when a script extension is loaded; ordinary native operation retains no hard Node library or process dependency.

Each script extension owns one persistent worker. This preserves module initialization, closures and mutable state across hook, tool, command and shortcut invocations rather than launching a fresh process for every event.

The Zig host remains authoritative for:

- extension discovery and project trust;
- registration validation and duplicate-name handling;
- per-extension flag state;
- tool and command integration;
- agent/session mutation;
- invocation serialization, output limits and timeouts;
- terminal shortcut precedence;
- process shutdown and error isolation.

The worker is deliberately bounded:

- JSON protocol records are prefixed with ASCII Record Separator so accidental direct stdout cannot corrupt the channel;
- console diagnostics are redirected to stderr;
- ordinary stdout discard and protocol record sizes are bounded;
- invocations have a hard deadline, after which the worker is killed and closed;
- requests are mutex-serialized so one persistent runtime cannot interleave protocol frames;
- extension errors remain extension-local rather than aborting the main agent.

## Original-style discovery and imports

Discovery now supports:

- explicit script paths;
- explicit extension directories;
- `package.json` `pi.extensions` entries, including multiple entry points;
- conventional `index.ts` and `index.js` package entries;
- trusted one-level extension directories;
- native `extension.json` precedence when both native and script forms exist;
- valid empty explicit extension directories as no-op sources.

The compatibility resolver first attempts the extension's real installed module. Only unresolved Pi ecosystem imports fall back to embedded compatibility modules. Covered import families include current and legacy Pi coding-agent, AI and TUI package names plus TypeBox-shaped schema helpers. This prevents a real extension dependency from being silently replaced with a fake package.

Node's native TypeScript transformation is used for interfaces, type annotations, enums and related erasable/transformable syntax. The validated runtime is Node.js 22.16.0; script extension execution requires a compatible Node 22+ installation.

## Registration and invocation surface

Original scripts can now register and execute:

- event hooks;
- tools with TypeBox-shaped parameter schemas and execution modes;
- slash commands with raw argument strings;
- typed flags with defaults and CLI overrides;
- keyboard shortcuts.

Registered closure state survives between all invocation kinds. The bridge also captures extension actions including notifications/messages, queued prompts, durable `setSessionName` and `appendEntry` mutations, and termination requests, and exposes stable compatibility context objects for noninteractive operation.

Native manifest extensions remain supported unchanged. Later extension shortcut registrations take precedence, matching the host's command/tool ordering policy.

## Agent lifecycle and context parity

The live coding-agent path now emits canonical upstream-shaped lifecycle events independently of the renderer:

- `agent_start` and `agent_end`;
- `turn_start` and `turn_end`;
- `message_start`, `message_update` and `message_end`;
- `tool_execution_start` and `tool_execution_end`.

Legacy compatibility aliases are translated without double-firing the canonical event.

`before_prompt` and the original `input` event can transform or handle interactive input. `before_tool`/`tool_call` and `after_tool`/`tool_result` can inspect or modify tool behavior and results.

### `before_agent_start`

Before each turn, extensions receive the raw/transformed prompt, assembled system prompt, current working directory and image attachments. They can:

- replace the complete assembled system prompt for that turn;
- inject durable custom context messages into the append-only session tree;
- keep those messages hidden from ordinary display while preserving their model context role.

Multiple handlers inside one persistent extension see the latest system prompt from earlier handlers.

### `context`

Before each provider request, extensions can filter, reorder or inject model-context messages without rewriting durable session history. Existing native messages carry a private projection index, so a filter-only transform preserves assistant metadata, tool calls, thinking/signatures, usage and multimodal content exactly. Injected text and image blocks are converted back to native `ChatMessage` values with custom types retained.

## Terminal shortcut integration

Extension keyboard shortcuts are dispatched before ordinary line-editor bindings. The path covers raw control bytes, printable input and Kitty CSI-u sequences, while ignoring key-release events. A shortcut can emit an immediate message, queue a prompt, set session state or request termination through the same native command-output path as slash commands.

## Original extension corpus probe

The supplied original coding-agent example corpus contains 78 extension entries. Registration probing produced:

```text
Loaded and registered:                   74
Qualified external-dependency failures:  4
Bridge/parser/import failures:            0
```

The four qualified failures require extension-specific packages absent from the supplied source snapshot:

- `custom-provider-anthropic`: `@anthropic-ai/sdk`
- `gondolin`: `@earendil-works/gondolin`
- `sandbox`: `@anthropic-ai/sandbox-runtime`
- `with-deps`: `ms` and its example-local installation

The resolver intentionally does not fabricate those third-party packages. See `EXTENSION-CORPUS-146.txt` for the complete entry list.

## Validation summary

The final source passed a fresh-cache validation graph:

```text
Whole-tree zig fmt --check:                 PASS
Node bridge syntax check:                   PASS
Real-source audit:                          PASS (167 Zig files, 79,230 lines, 0 synthetic)
All-package root graph:                     737 passed, 7 SQLite isolates, 0 failed
Dedicated SQLite repository suite:          11/11 passed
Dedicated live SQLite adapter suite:        5/5 passed
SQLite CLI/ABI/schema process:              8 active passed, 6 isolated, 0 failed
Executable/main suite:                      4/4 passed
Debug build: pi                             PASS
Debug build: pi-sqlite                      PASS
Debug build: pi-sqlite-live                 PASS
Ordinary pi hard Node/SQLite library deps:  NONE
Original extension corpus registration:     74/78; 4 missing external packages
```

The seven root-suite skips are exactly the SQLite CLI live case and six C-backed repository cases. Those behaviors execute successfully in their dedicated linked processes.

## Remaining parity boundary

Checkpoint 146 materially changes the extension status from manifest-only to a functioning original-script compatibility runtime, but complete extension-ecosystem equivalence is not claimed. The largest remaining areas are:

- interactive extension-owned overlays, dialogs, custom editors, headers, footers, widgets and renderer APIs on the retained fullscreen shell;
- complete provider registration, model injection, OAuth and reload-runtime semantics from scripts;
- arbitrary npm dependency installation/resolution beyond packages supplied by each extension;
- complete Node/TypeScript/ESM behavior outside the validated Node 22 compatibility boundary;
- wiring every original coding-agent screen into the native TUI;
- native server-side TLS/mTLS;
- automatic image resizing/transcoding and complete provider-specific multimodal limits;
- proxy propagation through every OAuth/cloud bootstrap path and the remaining enterprise credential/retry matrix;
- broader remote repository, auxiliary package and cross-language byte-level fixtures.
