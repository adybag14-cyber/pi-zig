# Actual native execution termination — source-only unit

This unit adds a dedicated native request and private execution-termination event to the linked QuickJS runtime. It does not classify ordinary Error DATA, generic interruption, allocation failure, Engine cancellation, or a diagnostic slot as this event.

The production delta, raw controls, native-owner intake snippets and selected immutable Node/V8 authority have finite source review. Nothing in this unit has been built, queried, or executed. Previous VM or Promise passes do not transfer to these changed bytes.

## Exact intake

- Base donor commit: `5ddf165d802280e22c3a1efd4c048b956bbbacf4`.
- Production: `vendor/quickjs/quickjs.c`, `vendor/quickjs/quickjs.h`.
- Raw root: `src/native_vm_execution_termination_test.zig`, 30 declared names.
- Build: six additive lines in `build.zig`; install-only target `build-native-vm-execution-termination`, filter `VM termination`.
- `complete-source-intake.json` contains 85 ordered edit steps / 96 actual matches. Forward replay produces the complete current C/H bytes; reverse replay reproduces both original base files exactly. Recorded offsets are donor-base reversal evidence. Main composition uses the exact before/after strings and match counts.
- Main's independently added private-property setter is absent from the donor base and must remain intact during composition.
- `engine-intake.json` supplies 19 exact edits over the preserved actual Main Engine base. `callback-gateway-intake.json` supplies five actual outer fail branches. Their complete before/after bytes are retained beside those packets. These snippets are not silently installed in this donor's Engine or gateway files.

The raw root uses only the actual C runtime, native callbacks/finalizers, actual Promise hooks, real jobs and actual allocation/interrupt controls. Its Batch helper saves/restores an outer continuation around raw job calls; it is not the Node checkpoint/reporting owner.

## Native contract

| API or state | Contract |
| --- | --- |
| `JS_PiRequestExecutionTermination(rt)` | Requests service. It does not create a pending event, increment the event generation, or make the active-event query true. The admitted atomic build supports the native worker request path. |
| `JS_PiCheckExecutionTermination(ctx)` | Services the dedicated request at a real entry/checkpoint boundary. Existing actual pending reasons retain entry priority. An active event held by an owner prevents reentry without inventing a second event. |
| `JS_PiIsExecutionTerminating(rt)` | True only for the actual private event currently published in the runtime while its lease is active. A detached owner, unserviced request, generic fatal, and cancelled abrupt completion are distinct. |
| `JS_PiCancelExecutionTermination(rt)` | Clears the request. It cancels the active event only when that actual event is currently published; it does not search arbitrary detached owners. |
| `JS_PiNativeTerminationResult()` | Allocation-free result projection for an already-observed native abrupt unwind, including after actual Cancel. It creates no event, lease, request or generation. It is never guest DATA. |
| `JS_PiNativePendingPriority` | Classifies a proven owned actual pending reason. It must not be called on diagnostic/rejected/returned DATA to manufacture authority. |
| `JS_PiNativePendingReplaceClassified` | Reduces two proven actual pending owners using established generic classifications and dynamic private-event activity. It does not mutate public Error flags. A discarded private lease is retired without erasing a later request. |
| `JS_PI_JOB_TERMINATED` | Distinct `-2` native-abrupt job result. It is not a Promise rejection and does not by itself mean the active-event query is true after Cancel. |
| `JS_PiFinishTerminatedMicrotasks(rt)` | Owner-thread queue/current-task retirement after the caller restores its outer continuation. Nested active-job/finalizer calls make no progress. Active termination detaches the old queue before releasing it, then emits the selected deferred native Promise AFTER. Cancelled unwind retires held owners without clearing live queued work or inventing AFTER. |

The private immediate cannot be stored as a Promise fulfillment or rejection. Public `JS_IsUncatchableError` retains its original Error predicate. Internal unwind checks additionally recognize the dedicated private native completion.

Normal Promise reaction jobs now retain their actual capability result; thenable jobs retain the actual target Promise. Native BEFORE/AFTER notifications filter genuine Promises, including species/custom-capability cases. Ignored Await capability results stay undefined. A terminating task retains its real Promise/context until the owning checkpoint restores outer continuation and performs ordered queue/current-task retirement.

Actual payload, Promise and context retirement runs while the current job remains selected. This prevents a finalizer from prematurely calling the termination-finishing operation before the checkpoint's outer-continuation restoration. Newly enqueued cleanup jobs belong to a fresh queue and survive old-queue retirement. Runtime destruction detaches and drains native owners without Promise hooks.

## Host owner integration and limits

The Engine intake keeps actual native exceptions separate from captured diagnostic DATA, preserves established generic first-fatal authority, and uses dynamic private-lease activity. A cancelled explicit native error still unwinds through `error.ExecutionTerminated`; it does not become an InternalError or a thrown Action payload.

The five outer gateway changes cover SDK, actual native AF, ModuleCallable, ordinary NodeFunction, and the outer planned-TypeBox fail gateway. **The TypeBox Machine's internal Reason/failure/finally algorithm is a distinct source successor.** Its closure is not claimed here.

SDK's separate coherent host-owner donor `f596f333dc868a0887b8ba5b7df641eacae39dbd` contains the actual Completion/Node Boundary integration and 16 controls. This unit does not duplicate that donor or install its consumers.

The genuine Node checkpoint, native completed-callback list, ordinary failed-microtask reporting, Node fatal reporting/bootstrap, and context-JavaScript Promise hooks are separate owners. Root's checkpoint source was separately reviewed; its required actual reporting operation remains explicit. A full Node checkpoint may acknowledge a cancelled private completion at its real stopped-run boundary. Raw job and callback gateways continue to preserve that abrupt completion until that boundary; they do not turn an absent ordinary reason into success.

Constructor-name metadata work remains separately preserved and is not in this C/H delta. Generic cancellation, budget and allocation producers keep their established paths.

## Evidence and review

`source-investigation.json` preserves the original request/event/cancel investigation against immutable Node v24.13 revision `def0bdf8abee441cfcbf793a8dc24a6f3b899573`. The authority directory includes the actual stack-guard/isolate sources, full selected microtask queue, and unchanged SDK proof packets for current-task Promise metadata, native hook filtering, current TryCatch cancellation and deferred AFTER order.

`peer-review-record.json` records the actual assigned peer closures. Original Modules receipts are copied byte-for-byte under `peer-receipts/`. `retained-peer-and-authority-copies.json` pins the copied originals and paths. `manifest.json` pins this unit's source, controls and evidence; `test-names.json` is only the declared source-name inventory, not discovered test metadata.

All control corrections preserve their original names and assertions. The small successors establish real fatal provenance and give drained actual reasons cleanup ownership before fallible assertions. No expected runtime result has been inferred from source review.
