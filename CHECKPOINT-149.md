# Pi Zig V8 checkpoint 149

Checkpoint 149 continues the Zig 0.16.0 rewrite from the exact uploaded checkpoint-148 archive and uses the supplied Pi 0.84.1 source tree as the behavioral reference. This pass closes the largest extension boundary called out by checkpoint 148: original custom renderers now execute through the persistent script worker and participate in the real native terminal paths. It also extends deterministic action ordering from lifecycle/tool callbacks to script commands and shortcuts, including startup and RPC dispatch.

## Source measurements

```text
Native Zig files under src/:              170
Native Zig logical lines under src/:      83,452
Embedded JavaScript bridge lines:            775
All-package root test graph:                 757 cases
Implementation source files changed:           5
Implementation additions/deletions:       +1,126 / -94
Synthetic/generated feature shards:            0
```

## Original custom renderer execution

The JavaScript/TypeScript compatibility worker now retains and invokes:

- `registerMessageRenderer(customType, renderer)`;
- `registerEntryRenderer(customType, renderer)`;
- `registerMarkdownTransformer(transformer)`;
- tool `renderCall(args, theme, context)`;
- tool `renderResult(result, options, theme, context)`;
- tool `renderShell: "self"` metadata.

The native host validates renderer requests and results, owns every returned allocation, isolates extension failures, and preserves extension load order for Markdown transformations. Message and durable-entry actions render immediately in TUI mode while still persisting their canonical JSONL entries. Final assistant Markdown passes through the extension transformation chain before the native Markdown/LaTeX renderer.

The embedded component compatibility surface now renders useful retained structures rather than treating every component as a string. `Text`, `Box`, `Container`, `Markdown`, and `Spacer` preserve child ordering, padding, visible-width behavior, theme styling, and disposal. Unknown or unsupported components degrade to bounded text/empty output instead of taking down the agent.

## Stateful tool renderers

Tool call/result renderers execute in the same persistent worker as the extension. Per-tool-call state retains:

- arguments and tool-call identity;
- `context.state` across call and result rendering;
- the previous call/result component through `lastComponent`;
- expanded, partial, execution-started, argument-complete, image and error flags.

The native event sink renders only canonical `tool_execution_start` and `tool_execution_end` events. The loop also emits legacy `tool_call`/`tool_result` aliases; ignoring those aliases in the renderer prevents duplicate component state transitions and duplicate terminal rows.

## Renderer-only built-in tool overrides

Original Pi extensions commonly re-register `read`, `bash`, `edit`, or `write` to replace only their presentation. Checkpoint 149 accepts those registrations without allowing a script shim to displace the native Zig schema or execution implementation:

- built-in schemas stay in the model tool catalog;
- native Zig built-in dispatch remains authoritative;
- extension `renderCall`/`renderResult` functions are still discovered and used;
- ordinary non-built-in extension tools retain their existing schema and execution path.

The supplied original `built-in-tool-renderer.ts` ran unchanged against the native `read` tool in an executable E2E gate.

## Ordered command and shortcut actions

Script commands and shortcuts now use the same canonical action records as lifecycle hooks and extension tools. Actions are applied in their emitted order for:

- provider registration/unregistration;
- model and thinking changes;
- active-tool changes and immediate schema rebuilds;
- session names, entries and labels;
- custom, steering, follow-up and user messages;
- abort and shutdown requests.

Equivalent legacy mirror fields are suppressed when a canonical record exists, preventing duplicate session entries or prompts. Return-object-only fields from native/older extensions remain supported as a fallback.

## Startup and RPC ordering

Startup commands execute before the live provider/client graph exists. Checkpoint 149 therefore performs a side-effect-free preflight to select the command prompt and stop state, retains the canonical action batch, then replays it exactly once after the live graph is available. The prompt consumed during preflight is removed from the generated steering/follow-up queues, so it cannot run twice.

If startup terminates before model initialization, durable session actions emitted before the stop record are still applied and saved. RPC command dispatch uses the same ordered action application while keeping protocol output machine-safe and transferring additional steer/follow-up messages into the RPC queues.

## Executable evidence

Four real gates passed:

1. A print-mode startup command persisted session name → custom entry → custom message → one user prompt → one assistant response, with no duplicate prompt.
2. An interactive TypeScript extension rendered its custom entry, custom message, and transformed assistant Markdown through the native terminal path.
3. A stateful extension tool rendered exactly one call row and one result row, sharing `context.state`, while its tool result persisted normally.
4. The unchanged original `built-in-tool-renderer.ts` custom-rendered a native Zig `read` call and result.

## Validation closure

```text
Whole-tree Zig formatting:                 PASS
Node bridge syntax check:                  PASS
Real-source audit:                         PASS
All-package root graph:                    750 passed / 7 isolated / 0 failed
Root declarations:                         757
Dedicated SQLite repository:               11/11 passed
Dedicated SQLite CLI/ABI/schema:            8 passed / 6 isolated / 0 failed
Dedicated live SQLite persistence:           5/5 passed
Ordinary executable tests:                   5/5 passed
SQLite-enabled executable tests:             5/5 passed
Debug build `pi`:                           PASS
Debug build `pi-sqlite`:                    PASS
Debug build `pi-sqlite-live`:               PASS
Startup command ordering E2E:               PASS
Message/entry/Markdown renderer E2E:         PASS
Stateful tool renderer E2E:                  PASS
Original built-in renderer E2E:              PASS
```

The seven all-package isolates are the SQLite CLI live integration case and six C-backed repository cases. The CLI case passes in the linked SQLite CLI process and all six repository cases pass in the dedicated repository process.

## Remaining parity boundary

Checkpoint 149 materially closes original message, entry, Markdown and tool renderer behavior, but complete Pi 0.84.1 equivalence is not claimed. The largest remaining areas are:

1. fully arbitrary extension-owned component trees, overlays, dialogs, custom editors and asynchronous renderer invalidation;
2. complete tool-result `details`, image, partial-update and expansion-state fidelity in every renderer path;
3. executable replacement of built-in tools, function-valued providers, custom stream implementations and extension-owned OAuth/login callbacks;
4. automatic installation and lifecycle management of extension npm dependencies;
5. complete wiring of every original coding-agent selector, model, login, settings and session screen into the retained fullscreen shell;
6. native server-side TLS/mTLS, automatic image resize/transcoding and remaining enterprise credential/proxy/retry behavior;
7. broader remote-repository and cross-language byte-exact interoperability fixtures.
