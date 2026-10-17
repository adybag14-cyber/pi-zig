# Actual SDK application AI composition — SOURCE only

Baseline4188de7b4190869cd3229f8544e291ab03867858. This unit connects actual native
AI implementations to the existing ordinary production AgentSession/factory.
It does not publish a partial factory, register a replacement public namespace,
change js_runtime.Backend, remove the Node bridge, or claim full application parity.

native_sdk_ai_imports.create constructs and retains one private consumed-import
graph using actual canonical Models/ModelsError/operations, all fourteen API
constructors, real provider factories and builtinModels, actual compat dispatch,
lazyStream and transcript normalization. Actual compat registration/builtinModels
order remains in its original body. No replacement provider registry, auth/error
family, catalog, completion callback or alias facade is supplied by the caller.
The consumed ai record is explicitly not the whole public pi-ai namespace.

native_sdk_application_assembly.create passes those exact AI/compat/factory
identities into native_sdk_default_real_assembly.create. It requires the actual
platform, resource-loader and Agent imports; it never substitutes SDK.Kind session,
Models, loader or Agent bodies. The caller retains the completed application graph
once per application module. Existing factory composition sets the actual shared
Agent default stream to the same compat stream, matching sdk.ts module execution.
Nothing invokes this composer or selects its exports at default worker startup.

A necessary identity correction caches the actual transcript-context module in
Engine.native_module_values under a private constant key. Previously ModelsImpl
and a separate SDK importer received distinct normalizeContext function objects.
The cache retains the original native callbacks, not wrappers, with Engine-owned
value lifetime; failed map insertion releases its extra retained root. No public
module registration or new Engine field is added. Partial construction never
publishes the new AI graph; already initialized genuine module caches survive a
failed higher-level attempt, and a later owner may retry.

Authority is exact Pi8efd314fa3d3232ce197d8d7a6a5660530b9d83e, coding-agent1.3.0.
Actual upstream Git diff4dd→8efd and4954→8efd is empty for sdk.ts,
agent-session-services.ts, agent-session.ts and packages/agent/src. This records
current1.3 source identity rather than assuming the older1.1 source is current.
Old Source27 factory/Original64 session/Source166 descriptor files are untouched.
The old integration14 docs describe a historical incomplete private assembly;
current production source installs those method families, which still requires
its full unchanged behavior/descriptor/runtime gates.

Concrete remaining end-state gaps found in current4188:

- native_sdk.install still publishes legacy Kind agent_session/model_runtime/
  resource_loader and synchronous factory callbacks. The new real assembly is
  unselected; public SDK/worker namespace activation remains Root's gate.
- js_runtime.Backend defaults to legacy and embeds js_bridge.mjs. Native worker
  installs timers/process/path/url/fs/CommonJS/text/fetch but does not construct
  and select the completed SDK application graph. Removing/switching these paths
  requires genuine integrated behavior, not a local API-presence check.
- native_agent_complete.install has actual loop/method bodies but still uses
  JS_SetPrototype to brand several C callbacks async; that does not establish
  true AsyncFunction execution. It cannot be advertised as completed genuine AF.
- Actual loader/package/extension/jiti graph and platform dependencies remain
  mandatory application inputs. Operators owns completed jiti public frontend;
  actual CommonJS/bootstrap/public Babel Module and esmEval dependencies remain
  under their existing owners. No Graph2/prototype namespace importer is used.
- Full factory/class/provider transport/stream/cancellation/allocation/GC behavior
  and CLI paths remain unqualified by this source composition. Shape checks in
  retained assemblies cannot prove provenance or runtime correctness.

Prepared checks (unrun): native_sdk_application_assembly_test.zig verifies exact
canonical callback identities across graph reuse and GC on a genuinely bootstrapped
Engine; its full-factory entry delegates the existing strict complete Source27
comparison. It supplies no fake platform or fallback positive fixture. The
additive reference-input.mjs uses actual Pi1.3 exports only, with no custom
transform or mock Models/Agent. It records error-brand, constructor/prototype,
registry/reset and transcript import observations. Expected data remains absent.

Further native control specifications: actual ordinary AgentSession full Source166
prototype+Original64 behavior; all provider IDs and real lazy constructor identity;
shared compat registration/reset visibility across two sessions and reload;
pending factory/summary callbacks retained across GC then released; every induced
host-allocation failure preserves actual pending/private reason identity and may
retry without a published partial application graph. Run complete existing gates,
not new hand-made native goldens. No runnable new test target/default registration
is asserted by these helper entrypoints/specifications.

No Node/compiler/AST/native/generator jobs, Main/C/H/Engine edits, default switch,
source-corpus edits, expected/observed data or CI/runtime pass occurred.
