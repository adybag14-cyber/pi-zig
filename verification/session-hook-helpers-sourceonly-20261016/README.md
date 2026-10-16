# Four ordinary AgentSession hook helpers: source-only migration

Base: `7cd5153e093da160c3c21bb8ad8c143d05426747`. Authority:
`0fbdbd3f8ab1876ac260c0f08226a400759323b8`, actual
`packages/coding-agent/src/core/agent-session.ts`, file SHA256
`E0FA206E8C49A98C024708068DF39C0E4944F4251633425FC083B2FBB5EC0AC6`.

The selected cluster was announced and approved before source edits. Only the
four installed prototype helpers are migrated. The new
`native_sdk_session_hook_helpers.zig` leaf uses genuine resumable async bodies
and the reviewed outer trusted-boundary wrapper. The existing installer
delegates the four entries to that leaf and removes their obsolete flow bodies
and private continuation cases. Six synchronous installers and their assigned
hook closures remain a separate migration surface.

## Exact original await map

| Method | Source await | Native stage and return behavior |
|---|---|---|
| `_beforeToolCall` | 669, `return await runner.emitToolCall(...)` | No-handler branch returns undefined with no await. Handler branch enters the Source try before resolving the callee, awaits once at `before`, then returns its value. Ordinary rejection or synchronous failure inside that try enters the original Error/wrapping catch. |
| `_afterToolCall` | 691, conditional `emitToolResult` await | Handler branch awaits once at `after_hook`; no-handler branch skips this await entirely and starts normalization synchronously. |
| `_afterToolCall` | 708, normalizer await | Both paths await normalization exactly once at `after_normalize`, then preserve content identity and optional hook-result fields. |
| `_compactBeforeNextAssistantResponse` | 784, `_runAutoCompaction` await | No-model, virtual, and below-threshold branches return the current projection without await. Compaction branch awaits once at `compact`, then rebuilds the projection before constructing the returned context. |
| `_dispatchTurnEndBoundary` | 867, `emitBoundary` await | Missing handler/entry branches return false with no await. Emission awaits once at `boundary`, commits entries, checks continuation, then reads the live continuation value for the final return. |

There is one intrinsic outer Promise for each helper invocation. No helper
creates a flow Promise or adds an undefined await. Private state is a
null-prototype record from the inherited `native_async_body.init`; values
returned in Action payloads own duplicates of borrowed VM values.

## Catch boundaries and exact fatal identity

The outer callback snapshots its invocation generation and wraps the entire
`bodyWithSourceCatch` call. Its catch calls leaf-local `trustedBoundary` before
`failureSince`, matching the reviewed initializer and idle/settlement pattern.
Failures inside Source error wrapping are therefore covered by the same outer
boundary, not merely failures from the initial body.

`_beforeToolCall` parameter destructuring and `hasHandlers` remain outside its
Source try. The try flag is set before resolving `emitToolCall` or reading event
properties. The catch retains an owned duplicate of a captured guest reason
before constructing a replacement. Error reasons are returned unchanged;
non-Error reasons use the Source's ambient String conversion and new Error.
The Error constructor is read again after instanceof, as in the original.
Failures raised from this catch body escape directly to the trusted outer
wrapper rather than being caught and wrapped a second time.

Resumed rejections are checked against the private START generation before
Source rejection handling. Fresh private native reasons are marked/rethrown
as the exact value. A preexisting uncatchable historical reason stays fatal;
ordinary historical tags and guest lookalikes remain ordinary. Direct native
OOM stays an error union. No C, Engine, global flow, or shared-helper change is
included.

## Live property and callback behavior

- Tool emission method getters resolve before event property getters.
- The structured-content condition and value perform the original repeated
  getter reads; fallback `result.content` is read only when required by `??`.
- The normalizer captures the supplied imported function once when the helper
  is created. Production passes its actual existing normalizer binding; test
  collaborators do not replace the public graph's normalizer.
- Boundary outcome preserves the original conditional repeated `stopReason`
  reads. Extension runner fields are reread at the original call sites.
- `toolResults.flatMap` remains a live ordinary method call with the original
  callback shape and receiver. The old manual length/index traversal is gone.
- Boundary commit resolves its callee before reading `boundary.entries`.
  Continuation is read separately for the condition and the final return.
- FlatMap and boundary-context callbacks are ordinary nonconstructible arrows;
  no async branding or extra Promise is attached to them.

## Existing authority and explicit capture gaps

`source-only-controls.json` records exact UTF-8 equivalence from actual 19cb
fixture authority to actual Source0fb for all four selected methods:

| Method | Equal method SHA256 |
|---|---|
| `_beforeToolCall` | `D87CD7303CD427F907A51A43A0F3AA13EB9730350451F8C7A1A170AB657E07EF` |
| `_afterToolCall` | `8B120F7442854B1612804AF33C6C9307F02B1013B71E1A82E5425D9359C4EC57` |
| `_compactBeforeNextAssistantResponse` | `22BA1D1B8DD12AC54650C7FF9D01CF05E528746E9BFA4C9D5096249659247125` |
| `_dispatchTurnEndBoundary` | `789D4ECACFF302C594AD2710790072C7FFDD60D19B1490C7871CF0A2FEBDA704` |

The unchanged Source16 hook fixture observes original factory/runner/manager,
assigned projection/request/boundary hooks, and before-tool scenarios. The
unchanged callable hook fixture remains auxiliary coverage. A direct positive
original capture of result normalization and compaction helper behavior was
not found. Byte-equivalent selected bodies do not replace that missing capture
or qualify their dependencies, the full class, or its application route.

Thirty unselected native functions are recorded byte-identical with normalized
LF to the base. Eighteen frozen C/Engine/shared-helper/constructor/normalizer/
fixture/test files retain their exact base Git blobs. Legacy assigned async
hook closures still use their existing flow/prototype paths; this checkpoint
does not claim that the whole hooks module is genuinely async or qualified.

## Prepared controls, unrun

`native_sdk_hook_helpers_realasync_test.zig` contains five tests exposed by
`build-native-sdk-hook-helpers-realasync` and
`test-native-sdk-hook-helpers-realasync`. Seven prepared programs cover:

- No-handler normalization beginning before the first original await.
- Emission getter order, repeated structured-content reads, and parameter
  failures staying outside the before-tool Source catch.
- Conditional compaction, its original await, and projection rebuilding.
- Overridden flatMap, boundary field/callee order, and live continuation reads.
- Exact real native fatal identity on synchronous emission, resumed rejection,
  and failure from within the Source String/error-wrapping catch.

These are component controls with explicit receiver/normalizer collaborators.
They are not captured Source goldens, normalizer qualification, or full class
qualification. Existing immutable fixtures and assertions were not changed.

Only source inspection, historical byte comparison, frozen-file/function
comparison, static prepared-JS delimiter balance, and `git diff --check` were
performed. No Zig/Node invocation, AST/semantic compile, source capture, native
runtime, or qualification job was run.

`native_qualified=false`, `full_factory_qualified=false`,
`full_pi_qualified=false`, `public_activation=false`.

Root source review additionally found that the synchronous Source catch kept
the ordinary raw reason in the Engine capture slot after wrapping it. The local
correction transfers that owned reason out of the slot before guest Error/String
callbacks and retires only the local reference afterward. A callback that throws
the same object anew retains its new capture. Fatal and resumed-input paths are
unchanged. The added component control inspects the capture boundary and same
object rethrow identity. This correction and control remain native-unrun.
