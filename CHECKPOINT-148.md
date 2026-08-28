# Pi Zig V8 checkpoint 148

Checkpoint 148 continues the native Zig 0.16.0 rewrite from the exact uploaded checkpoint-147 archive and uses the supplied Pi 0.84.1 source tree as the behavioral reference. This pass closes two high-value script-extension boundaries: deterministic side effects from lifecycle/tool callbacks and declarative provider registration.

## Source measurements

```text
Native Zig files under src/:              170
Native Zig logical lines under src/:      82,525
Embedded JavaScript bridge lines:            670
Zig test declarations:                       765
Gain over checkpoint 147:                  2 Zig files / 1,478 Zig lines
Implementation source files changed:           9
Implementation additions/deletions:       +1,609 / -63
Synthetic/generated feature shards:            0
```

## Ordered extension side-effect pipeline

Script extension handlers can execute on the agent thread, the persistent Node worker, or parallel tool workers. Checkpoint 148 no longer mutates native state directly from those callback contexts. Each invocation returns allocator-owned canonical action records, and the Zig host moves them through a mutex-protected FIFO with a monotonic sequence number.

Actions are drained only at deterministic safe points around prompt transformation, agent start, context projection, turn start/end, assistant completion and tool-batch completion. Supported ordered actions include:

- immediate/custom/user messages and steer/follow-up delivery;
- session names, custom entries and entry labels;
- exact active-tool sets with immediate schema rebuilding;
- model and thinking-level changes with durable session entries;
- provider registration and unregistration;
- abort and shutdown requests.

The queue transfers ownership rather than retaining callback arenas. Malformed action envelopes are isolated to the producing extension. Parallel extension tools preserve callback completion order without mutating the session tree from worker threads.

## Agent-end continuation and shutdown durability

The native loop now mirrors the original post-agent lifecycle more closely:

1. `agent_end` is emitted after the current cycle.
2. Actions produced by `agent_end` are drained.
3. A queued steering/follow-up message starts another agent cycle over the same durable session.
4. `session_shutdown` actions are drained after the final cycle and saved again.

An explicit `shouldStopAfterTurn` callback remains authoritative. The full root graph caught a regression where a pre-existing follow-up could be consumed after that stop decision; checkpoint 148 fixes the boundary while still flushing end-handler cleanup actions.

## Declarative extension provider registry

Serializable `pi.registerProvider()` and `pi.unregisterProvider()` definitions now alter the native model/runtime registry. The implementation deliberately reuses the existing `models.json` pipeline:

- identical provider/model schema validation;
- API identity, transport, endpoint, headers, compatibility and sampling metadata;
- literal or environment-backed API keys;
- context/output limits, costs, image support and thinking maps;
- transactional re-registration and baseline restoration on unregister;
- shallow re-registration merge matching extension object-spread behavior;
- live model-catalog and `ClientPool` runtime replacement;
- immediate model switching from a later action in the same ordered batch.

Module-load provider registrations are retained in extension manifests. Runtime registrations emitted from lifecycle/tool handlers enter the same ordered action queue. Invalid definitions are rejected without destroying the previous valid registration.

Function-valued provider callbacks, extension-owned OAuth handlers and arbitrary custom stream implementations are not represented as declarative JSON and remain outside this checkpoint's equivalence claim.

## End-to-end evidence

Three real executable gates passed:

- lifecycle actions persisted in exact order across two turns, including an `agent_end`-queued follow-up and final `session_shutdown` rename/entry;
- extension-tool execution actions preceded `tool_result` hook actions and persisted without a DebugAllocator leak;
- `before_agent_start` emitted `registerProvider → setModel → appendEntry`, then the native OpenAI-completions transport called a local SSE endpoint at `/v1/chat/completions` with model `fast` and `Authorization: Bearer extension-secret`.

The provider/model change and final assistant metadata were preserved in JSONL.

## Validation closure

```text
Whole-tree Zig formatting:                 PASS
Node bridge syntax check:                  PASS
Real-source audit:                         PASS
All-package root graph:                    748 passed / 7 isolated / 0 failed
Root declarations:                         755
Dedicated SQLite repository:               11/11 passed
Dedicated SQLite CLI/ABI/schema:            8 passed / 6 isolated / 0 failed
Dedicated live SQLite persistence:           5/5 passed
Ordinary executable tests:                   4/4 passed
SQLite-enabled executable tests:             4/4 passed
All 765 unique declarations executed:       PASS
Debug build `pi`:                           PASS
Debug build `pi-sqlite`:                    PASS
Debug build `pi-sqlite-live`:               PASS
Lifecycle action-order E2E:                 PASS
Tool callback action-order E2E:             PASS
Dynamic provider/SSE E2E:                   PASS
```

The seven all-package isolates are the SQLite CLI live integration case and six C-backed repository cases. The CLI case passes in the linked SQLite CLI process and all six repository cases pass in the dedicated repository process.

## Remaining parity boundary

Checkpoint 148 materially closes ordered lifecycle/tool mutations and declarative providers, but complete Pi 0.84.1 equivalence is not claimed. The largest remaining areas are:

1. arbitrary extension-defined component rendering, overlays, dialogs and custom message/tool renderers;
2. routing all legacy command/shortcut return-object side effects through the same strict ordered action semantics;
3. function-valued provider implementations, extension-owned OAuth/login callbacks and complete provider reload semantics;
4. automatic installation and lifecycle management of extension npm dependencies;
5. complete wiring of every original coding-agent screen into the retained fullscreen shell;
6. native server-side TLS/mTLS, automatic image resizing/transcoding and the remaining enterprise credential/proxy/retry matrix;
7. broader remote-repository and cross-language byte-exact fixtures.
