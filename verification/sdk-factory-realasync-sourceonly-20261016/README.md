This source-only unit migrates the four actual SDK factory exports in
native_sdk_factory_production.zig. It does not construct substitute classes or
select a default SDK path. Runtime recovery remains pending; no formatter, AST,
Node, source generator, native compile or runtime job has run.

The authority files sdk.ts, agent-session-services.ts and
agent-session-runtime.ts are byte-identical in the retained4954,0fb and current
reviewed4dd source trees. Their SHA256 values are recorded in prepared.json.

| Export | Source boundary | Native action |
| --- | --- | --- |
| createAgentSession | sdk.ts198 conditional ModelRuntime.create | Await only when modelRuntime is nullish |
| createAgentSession | sdk.ts205 newly constructed loader.reload | Await only when no resourceLoader is supplied |
| createAgentSession | sdk.ts236 findInitialModel | Await only when no model was restored/supplied |
| createAgentSessionServices | services.ts142 conditional ModelRuntime.create | Conditional Await |
| createAgentSessionServices | services.ts154 loader.reload(options) | One Await after the live reload callee/argument reads |
| createAgentSessionServices | services.ts194 refresh({allowNetwork:false}) | One Await after pending registration loops |
| createAgentSessionFromServices | services.ts217 return createAgentSession(object) | Return/adopt the original captured function's result; no added Await |
| createAgentSessionRuntime | runtime.ts430 createRuntime(options) | One Await, then construct the exact supplied AgentSessionRuntime |

Native AsyncFunction entry creates the one outer Promise. The seven Await
stages return raw awaited expressions to the reviewed primitive; the small local
state recorder creates no Promise and never reads/invokes a thenable manually.
Old dispatch/begin/continueFactory, flow.create/wait/settle/reject and prototype
tagging are removed from this leaf. Function names/lengths remain0,1,1,2 and
the captured ordinary AgentSession constructor is unchanged.

Module import validation and setDefaultStreamFn still run synchronously during
create/compose. Errors from called async bodies enter their genuine outer
Promise; default options are created inside START. FromServices reads services
independently for each of its five fields, then its other options in Source
order, before calling the captured original createAgentSession with undefined
receiver. The runtime wrapper calls its actual cwd assertion before its callback,
preserves callback/options identity and reads the result fields in Source order
before invoking the captured real constructor.

Per-invocation state has a null prototype and owns every retained value. Each
resume releases the old Await operand before Source work continues; borrowed
completion values are duplicated before storage or return. Local checked data
definitions capture the current pending VM reason. At failure boundaries, an
existing uncatchable or current privately tagged allocation reason is protected
before normalizing another pending reason or classifying the error.

Ordinary registration catches transfer/null the captured slot immediately, then
own the reason through Error/instanceof/message/String/diagnostic formatting.
An ordinary outer body error similarly transfers its owned reason into the
primitive's thrown action. No deferred identity-based cleanup can erase a new
throw of the same object. Direct host OOM and trusted fatal reasons propagate;
no guest name/message is used for allocation classification. Shared Scope,
native_async_body, Engine and C remain unchanged.

Prepared controls in native_sdk_factory_realasync_controls.zig accept the
actual composed factory namespace and real runtime/session/service inputs.
They create no fake Models, registry, manager, loader or session constructor.
Nine programs cover four intrinsic brands/early rejection boundaries, raw
Proxy options identity, START/resumed wrapped native failure identity, lifecycle
callee/Await/result getter ordering and real provider-catch slot ownership.
The last control requires a legitimate extension registration in the real
resource loader. Actual compiled counts remain unknown.

Positive complete session/services construction, full Source getter/trace
comparison, rejection/cancellation/teardown accounting and exact allocation
positions still need an admitted actual-input gate. Nested callbacks in other
factory helper modules are unchanged and are not qualified by this migration.
The lazy completed-namespace/import cycle, importer interop, package/child
transport, C/TLA composition and default selection remain separate explicit
work. Original Source53/44/15/48/39 expected files and proofs are untouched.
