# Native tracing event boundary and bootstrap source analysis

## Result and scope

This packet proposes two new native C ABI files and one source-membership insertion in the existing tracing recipe. The five entry bodies retain the selected original Node trace-event operations. The packet also identifies the concrete native value, producer, process, and Environment owners still required to assemble tracing. It does not install a process Agent, attach a production callback policy, or close the complete tracing link graph.

All source authority is the pinned Node revision `def0bdf8abee441cfcbf793a8dc24a6f3b899573`. Exact originals and notices are retained under `authority/`. Fourteen files, including the two license records, were copied from existing contained originals; five additional originals were acquired from the pinned official raw URLs with native fetch receipts. The process-methods source is retained as a search negative: it does not contain the GetProcessTitle definition, which is in util.cc.

The new files exist only under `proposal/src/extensions/`:

| Proposed file | Role |
| --- | --- |
| native_node_tracing_event_api.h | Five C declarations, borrowed-context contract, native ownership and pointer-lifetime requirements |
| native_node_tracing_event_api.cpp | Original event/category/metadata/duration bodies with the two required synchronous admission scopes |

`build-proposal.json` adds only native_node_tracing_event_api.cpp immediately after the existing native_node_tracing_api.cpp member. Its forward replacement and whole inverse both match byte-for-byte. The live recipe and all existing tracing source files remain unchanged. The source-only proposal has not been compiled, linked, installed, or executed.

## The five original operations

Line references below refer to the unchanged authority files within this packet.

| C entry | Original authority | Preserved operation |
| --- | --- | --- |
| pi_node_tracing_event_category_enabled | trace_event.h, TraceEventHelper::GetCategoryGroupEnabled, lines 313–329 | Resolve the published controller; return a separate static zero byte when no controller exists; otherwise call its genuine category registry |
| pi_node_tracing_event_add | trace_event.h, AddTraceEventImpl, lines 460–481 | Adopt up to two native convertible values before global lookup; return zero if no controller; otherwise call AddTraceEvent |
| pi_node_tracing_event_add_with_timestamp | trace_event.h, AddTraceEventWithTimestampImpl, lines 483–504 | The same ownership order, followed by the original timestamped controller call |
| pi_node_tracing_event_add_metadata | trace_event.h, AddMetadataEventImpl, lines 506–525 | Adopt up to two native convertible values before Agent lookup; if present, call the Node controller metadata operation |
| pi_node_tracing_event_update_duration | trace_event.h, macro lines 117–120, invoked at 692–693 | Dispatch to UpdateTraceEventDuration only when the global controller exists |

The duration entry preserves the raw dispatch operation. ScopedTracer's lifetime and enabled-byte guard at lines 690–694 belongs to the eventual producer. The proposal does not move that guard into the raw entry or imply that all arbitrary handles are valid.

`source-body-audit.py` is the exact source comparison recipe. It first checks that DiagnosticContextScope and AllocationScope are the first two declarations in every entry. It removes only those two declarations, applies four explicit namespace aliases, and ignores line comments and whitespace in these string-free bodies. The category comparison additionally qualifies the original class-local helper call through the same TraceEventHelper class. The duration comparison expands only the exact named original macro at its actual ScopedTracer invocation and substitutes the three parameter names. All five comparisons match; all five declaration/definition names match. The proof is `source-body-proof.json`.

These are static body comparisons, not C++ semantic or ABI qualification. Supported recipe selections use the original 32-bit int representation for the int32_t argument count and 64-bit payloads; compiler admission and actual target linkage remain outstanding.

## Lifetime, category gating, and payload representation

Every entry declares the borrowed DiagnosticContextScope first and AllocationScope second. The context is the actual immediate caller's JSContext, or null for a native call without one. Its scope outlives later local destructors. It is never queued, saved in an event, or retained in an observer. The live native allocation owner must match the selected Agent/controller owner, and must survive the synchronous call.

The first two CONVERTABLE arguments transfer actual native ConvertableToTraceFormat objects into local unique_ptr storage before the global owner is read. If the global controller or Agent is absent, those objects still die on the original early-return path. If insertion succeeds, the original controller/core moves the selected objects into native trace storage. Deferred formatting is performed by the native trace implementation and must not depend on a borrowed guest callback or a JSON proxy.

The original 0/1/2-argument template producers in trace_event.h, lines 586–682, remain separate from the raw insertion API. Their inputs use TraceValueUnion and SetTraceValue at lines 441–578. The tag values are preserved: BOOL 1, UINT 2, INT 3, DOUBLE 4, POINTER 5, STRING 6, COPY_STRING 7, and CONVERTABLE 8. Phases and flag constants come from trace_event_common.h, lines 1040–1097.

Ordinary STRING values, names, scopes and argument names retain the original long-lived pointer contract. FLAG_COPY copies names, scope and argument names and turns ordinary string values into copied values in TraceObject. COPY_STRING independently copies the selected string payload. Those two operations must not be collapsed. Input arrays are borrowed only until return; long-lived pointer requirements concern the retained objects they describe.

The original call-site category cache uses relaxed atomic pointer loads/stores at trace_event.h, lines 132–171. Its recording-mode gate precedes argument construction. The raw insertion API does not add a new gate. The separate disabled pointer returned before global publication is not an index into the process category-name registry. Caching that zero pointer before publication has the original cold-start consequence, which is one reason the process bootstrap order matters.

Original pointer TraceID conversion casts the native pointer to uintptr_t/u64 and adds MANGLE_ID; it does not invent a numeric hash. Integer IDs retain their original conversion and flags. The relevant overloads are trace_event.h, lines 334–438. FS synchronous macros first test the raw category byte for nonzero and then use the normal macro gate. AsyncWrap start has the same outer admission pattern. The eventual producer must preserve both checks and the order in which it evaluates values.

## Concrete Zig producer assembly points

Exact unchanged current consumer sources are preserved under `consumer-basis/`, with their original paths and hashes in `consumer-basis.json`. The Main basis was c764130caf2f2c7c63728bec0f6d1e16ac5c59a4 before and after capture. SDK's selected projected State and CloseReq snapshots are also retained, so a later delta can be layered onto the actual pending owner unit.

| Producer | Existing typed slot or missing insertion | Original operation and lifetime |
| --- | --- | --- |
| FileHandle read | native_node_file_handle_read.zig Trace.begin_read/end_read, called at lines 90 and 208 | node_file.cc 597–608: nestable begin/end for UV_FS_READ, using FileHandleReadWrap* identity; result is the original int conversion of req->result |
| FileHandle close promise | Selected CloseReq Trace.begin_async/end_async; end at line 244 | node_file.cc 478–497: begin uses CloseReq* before dispatch; end recovers the same request wrapper before retaining CloseReq and running AfterClose |
| FileHandle GC close | Selected GC close calls begin_sync, synchronous uv_fs_close, end_sync, then cleanup | node_file.cc 340–347: ordinary B/E events named fs.sync.close, no async request ID |
| AsyncWrap MakeCallback | Trace.before receives live State; Trace.after receives saved provider and async ID | async_wrap.cc 125–159 and 660–676: before reads its native ID after the category gate; after must not read an object that the callback may already have destroyed |
| AsyncWrap reset | Missing trace call between the selected State's completed resource Set and currentContextFrame at line 401 | async_wrap.cc 593–622: EmitTraceAsyncStart at line 618 precedes context-frame reset and EmitAsyncInit |
| AsyncWrap retire | Missing destroy trace immediately before Environment.emitDestroy at selected State line 489, after derived retirement | async_wrap.cc 544–560: base destructor emits its trace before EmitDestroy(true) |
| Environment begin/end | Separate native producer and typed Environment integration still needed | env.cc 896–903 and 1041–1049: EnvironmentArgs at begin and matching Environment* identity at end, with observer removal before the end event |

These observations do not change the scope or acceptance of the existing SDK FileHandle controls: their concrete production trace owner was already an explicit assembly dependency.

The FileHandle pointer IDs are wrapper identities, not uv_fs_t addresses. The existing read/close result truncations represent the original int conversion. AsyncWrap's original double-to-int64 conversion should remain native and occur after the original category gate; a generic eager Zig float-to-int conversion would change exceptional-domain behavior and evaluation order. Provider names and callback suffixes come from the original provider switch, not a synthesized guest string.

For the pending State delta, the selected SDK C195 projection hash is 48429726BE834396EFB669ABA15C90940CB024D3A2095DF27D1C4BA8CB297CE1. The earlier Main State 16C3B02F remains preserved separately. Any later trace insertion must retain all existing pending-operation, native member, environment retention and teardown behavior.

## Native TracedValue and metadata owners

The raw event boundary can consume actual native convertible objects. It does not yet create the three original concrete values needed by these producers.

The full original traced_value.cc is retained at SHA D3090ECDF316735A388C1A38DB70396D6A1B91B0108D493E40D8B9E91AF91EF8. It supplies the exact builder, escaping and numeric formatting bodies. EnvironmentArgs::Cast at lines 222–231 constructs native arrays from the actual native argument and exec-argument spans. AsyncWrapArgs::Cast at lines 233–238 writes two native IDs. ProcessMeta::Cast at lines 240–259 builds native versions, architecture, platform and release objects.

Several details are material to a faithful implementation:

- EscapeString has an explicit NODE_HAVE_I18N_SUPPORT selection. Its ICU branch uses U8_NEXT_OR_FFFD and the original uint16_t formatting behavior. The non-ICU branch has the original non-UTF8-aware char behavior. Neither branch should be replaced with a guest JSON serializer.
- DoubleToCString, lines 90–102, emits quoted NaN/infinities, normalizes zero to 0, and uses a classic-locale native output stream for other values.
- WriteName, lines 209–214, writes the selected native field name directly. Adding unrelated key escaping would change the original builder.
- AsyncWrapArgs stores int64 values, while TracedValue::SetInteger takes int. The original narrowing is part of this selected body; silently widening the resulting JSON integers would change behavior.
- EnvironmentArgs borrows native spans only during Cast; each string is immediately converted into owned trace data. Its original C-string conversion behavior must be retained.
- The eventual implementation must use the actual native allocation domain and native output-string owner already selected by the tracing packet.

The current tracing recipe does not define NODE_HAVE_I18N_SUPPORT. That omission does not authorize choosing the fallback branch as the final process behavior. The next native value unit must bind the intended Node feature selection and the matching contained ICU header dependency if I18N is selected.

ProcessMeta requires a native process metadata owner. The pinned node_metadata.h lists feature-dependent version keys; node_metadata.cc, lines 99–184, obtains the real native versions and sorts its native string-view pairs by key. Release and architecture/platform fields are selected at lines 186–204. The current Main native_process.zig, lines 41–61, exposes the actual Zig/QuickJS guest versions plus platform and arch; it is not that native ProcessMeta owner. Reading mutable guest process properties would introduce a different source and evaluation path.

GetProcessTitle is in util.cc, lines 188–211. It starts with a 16-byte native string, retries UV_ENOBUFS by doubling, stops at 1 MiB, falls back to the supplied default on failure, and trims the terminated result. The original process observer passes an empty default and omits process_name metadata if title retrieval fails. No fixed 512-byte title buffer is justified. node_process_object.cc, lines 31–47, contains the title getter/setter callers and the setter's metadata emission before uv_set_process_title.

## Actual process Agent and observer bootstrap

The full original order is in node_v8_platform-inl.h, lines 68–103. The currently committed 29-entry native API covers Agent/client/controller primitives and original StartTracingAgent operations, but it does not install the process owner.

Initialization must preserve this order:

1. Check and set the process initialized state.
2. Construct the actual native Agent.
3. Publish it with TraceEventHelper::SetAgent.
4. Construct and register the one-shot process trace observer.
5. Obtain the default client handle and optionally start the configured CLI categories/writer.
6. Only then create the original native platform producers/threads and initialize their platform owner.

Original disposal clears the global Agent pointer first, resets the tracing file client, shuts down and destroys the platform and its threads, destroys the Agent, and finally destroys the process observer. The allocation owner must outlive those destructors. A process owner must enforce that sequencing; installing a separate global Agent opportunistically in every Engine would not establish it. Current Engine construction/destruction owns an individual VM/native-memory domain and has no process tracing owner.

The process observer at node_v8_platform-inl.h, lines 23–62, emits process_name when available, native node version, JavaScriptMainThread, and ProcessMeta. It removes itself the first time it observes enabled tracing. OnTraceDisabled is an actual unreachable path. Registration can synchronously call OnTraceEnabled if the controller is already recording, so the observer and every field it needs must be fully formed before registration.

The selected controller copies its observer set under the actual mutex and invokes callbacks after releasing it; self-removal therefore uses the original operation. If tracing was never enabled, StopTracing returns before observer callbacks. The original process destruction order remains relevant even in that path. This packet does not add a generic observer callback bridge or relax the original single-process publication lifetime.

The replacement runtime still needs its actual producer/platform ownership composition. The existence of QuickJS Engine teardown does not itself implement NodePlatform::Shutdown or justify pretending those original producers exist.

## Environment observer is a distinct owner

TrackingTraceStateObserver in env.h, lines 467–481, updates on both enabled and disabled notifications. Its implementation in env.cc, lines 638–665, first requires owns_process_state and can_call_into_js, then a principal realm, then the real trace-category callback. It reads the actual async_hooks category byte and invokes the callback with a boolean through a native handle scope and verbose TryCatchScope behavior.

Environment construction registers this observer at env.cc, lines 882–886. Destruction removes it at lines 1041–1049 before emitting the Environment end event. Its Environment and callback must remain valid throughout any synchronous registration/start/stop notification.

The selected Zig callback Environment has real can-call and VM lifetime operations, but it has not yet assembled the exact owns_process_state, principal-realm/category callback and verbose exception-policy owner needed here. Hardcoding those predicates or supplying an empty callback would not implement the original observer. A typed Environment integration is required, with the actual retained VM handles and the real exception/reporting policy.

## Build and remaining owner boundaries

The proposed recipe change adds one translation unit and preserves existing flags, libraries and owner arguments. The recipe still consumes its explicit network, native-memory, diagnostic and Abseil owners. DiagnosticContext TLS, the V8 fatal owner and clock wrappers remain the already reviewed dependencies; they are not duplicated here.

| Boundary | Concrete status |
| --- | --- |
| Clock and immediate Agent/controller API | Existing source-only committed units, unchanged |
| Abseil mutex/condition, native platform/loop, Recorder and contained TraceLoggingProvider | Existing source-only platform packet, unchanged; real Windows SDK provenance retained |
| Core/controller/Agent/buffer/writer drafts | Ten earlier native source drafts remain byte-exact; complete composite source review/link admission remains separate |
| Raw event/category/metadata/duration ABI | Two proposed files and five exact body comparisons in this packet |
| Event producer adapters | Exact typed slots and missing State/Environment insertion points mapped above; not installed |
| Native TracedValue/I18N and process metadata | Original bodies acquired and concrete data requirements mapped; production owners still to be implemented |
| Process observer and process bootstrap | Original construction/publication/thread/teardown order mapped; no bootstrap installed |
| Environment observer | Actual callback and lifetime requirements mapped; no fabricated hook policy |
| Fatal bootstrap hooks | Native fatal callbacks exist in the reviewed owner; production hook installation remains separate |
| Target/compiler/native qualification | No claim; not performed in this packet |

The existing GNU C++20 recipe has no DEBUG, NDEBUG or OFFICIAL_BUILD definition. Its selected source behavior is the recorded release selection; Zig Debug optimization alone does not establish original V8 DEBUG semantics. Windows/Linux/Darwin source branches remain distinct. The current network/native-memory composition supplies Windows/Linux owners; Darwin still requires its real admitted owners. The one-line event insertion does not resolve those target dependencies.

The new source proof also rehashes all fifteen existing API/core/controller/Agent/buffer/writer/clock/recipe inputs against their stable pins. The packet's inventory retains every authority file, fetch/acquisition receipt, proposal, comparison, capture and analysis. No Main source, SDK source, submitted tracing production pin, earlier dirty draft, build configuration, or index was altered. No tests, compiler, preprocessor, native program, Node reference, or project generator were run.
