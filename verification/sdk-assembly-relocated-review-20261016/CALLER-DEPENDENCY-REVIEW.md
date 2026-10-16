This is a source-only review after consolidation. It creates no caller, modifies
no production body, selects no SDK default and transfers no qualification.
The owned baseline is SDK8ab0773b. Main2584d41e was read only for integration
availability; main remains Root-exclusive. Runtime status is recovery_pending.

The existing native_sdk_default_real_assembly.create requires nineteen real
inputs. It builds ModelConfig, stores, RuntimeCredentials, ModelRuntime,
AgentSessionRuntime, ordinary AgentSession and the SDK factories over their
captured identities. Its select function is explicit and remains uncalled.
No worker/bindings call of this create, runtime_imports.create or
resource_loader_assembly.create was found in the reviewed main or owned tree.
Shapes/constructor checks do not establish real Source or native provenance.

| Caller/dependency layer | Concrete source already present | Remaining closure |
| --- | --- | --- |
| Platform/bootstrap | runtime_imports creates filesystem/path utilities, configuration, shell, one resolver, auth and timing | Real process/OS/URL/child-process namespaces and physical config URL must be supplied; native transport/filesystem gates remain separate |
| TypeBox/AI/provider graph | production TypeBox graph, real Models namespace and provider-factory APIs exist as explicit constructors | One actual Type/Memory/Settings/Compiler/schema graph, actual14 API constructors, canonical ModelsError/abort and compat registry must be assembled without synthetic defaults |
| Model/session graph | default_real_assembly composes actual classes and imports shared managers/AI | Real resource loader, managers, management HTTP fetchWithRetry and shared compat providers remain required inputs |
| Package manager | main has complete98-declaration caller assembly with genuine33 async methods | Actual semver/Git URL/ignore/minimatch, crypto, complete filesystem and real child streams/frontend stdio must be supplied and qualified; owned8ab still has the older partial intake |
| Resource loader | Ordinary constructor and37 named methods are assembled from actual body modules | SettingsManager, complete package constructor, chalk.default, loadExtensionFromFactory and loadExtensionsCached are required; several existing async bodies still use flow/prototype paths |
| Extension initialization | Actual transactional API, initializer, runtime, event bus, source info and cache token helpers exist | No installed native loadExtensionModule/loadExtensionsInternal/loadExtensionsCached caller closes these pieces over the Engine importer |
| Engine module importing | Graph2 b09 and adapterbeb88 are independently versioned source prototypes | C/TLA composition, genuine native/physical replay, default/Proxy/JSON interop, missing policy edges, allocation/lifetime and resource policy gates remain open |
| SDK factory entrypoints | Four orchestration bodies in native_sdk_factory_production | They still use JS_SetPrototype(AsyncFunctionPrototype) and native_agent_async flow; the actual caller layer is not genuinely async yet |

Identity obligations are concrete: the config resolver used by auth and composer
must be one namespace; provider schemas share the actual TypeBox graph; aliases
of a virtual namespace select one canonical C module; ModelRuntime and session
services retain the same real ModelsError/abort and actual compat dispatch; the
resource loader receives the same initializer and factory-cache owner.

There is a construction cycle to resolve at the caller boundary. An extension
import session requires all twenty real VIRTUAL_MODULES authorities, including
the completed coding-agent namespace. Building that namespace requires the real
SDK graph, whose resource-loader constructor requires loadExtensionsCached.
Constructing the importer eagerly with an empty namespace table or the old SDK
Kind exports would hide this cycle. The concrete resolution is a lazy lookup of
the completed real namespace authorities at import invocation, after module
composition finishes. Capture that real set once per actual session. Do not
invent mutable placeholder exports or manufacture another module alias.

The next importer caller should be a narrowly scoped actual loadExtensionModule
and cache-token bridge: preserve original cwd/generation checks, capture the
token before Await, return a successfully loaded factory even if its token became
stale, and populate the cache only if that exact token remains current. Clearing
the factory cache retires no old graph or shared CJS/JSON/ESM record. The existing
Engine prototype returns a namespace; a guessed `.default` read is not complete
jiti default/Proxy/JSON interop. Preserve Source's actual preliminary await and
getter order instead of inserting dummy resolved Promises or a fake jiti object.

Smallest immediately unblocked next source integration

Migrate only the four native_sdk_factory_production entrypoints onto the reviewed
native_async_function primitive, over their existing explicit genuine inputs.
This removes a known false async representation at the actual SDK caller boundary
without requiring the missing runtime, package transport, chalk or importer to
be substituted. Preserve each Source await individually; the separate
createAgentSessionFromServices body returns/adopts its inner call, and does not
gain an additional await. Keep all option/getter/callee ordering and exact fresh
allocation-error handling, and keep selection uncalled.

Then integrate the cache/import caller through the lazy real-namespace seam after
the C/TLA review and actual interop contract are ready. Complete
loadExtensionsInternal/cached orchestration before assembling DefaultResourceLoader;
only then add the application-owned caller of default_real_assembly.create.
Calling select or replacing public Kind paths is a separate final gate after
actual constructor/factory/store/session/loader/platform replay. This review does
not authorize a broad Engine copy or a production switch.

Prepared controls for that four-function source migration should retain the
original imports and supplied actual classes, observe all getters/callees in
Source order, distinguish immediate return from each true Await/adoption, preserve
raw ordinary errors and fresh native fatal identity, and assert genuine intrinsic
async branding. No new expected output is authored here. Runtime recovery must
validate all31,064 original bytes, workspace links and absences before any Node
reference becomes usable; any execution needs a newly sealed contained owner
and Root's explicit resource grant.

Original Source53/44/15/48/39 proof directories, goldens, captures, physical
versions and negative receipts remain unchanged. Historical documentation can
describe older partial intakes; this separate review records newer main caller
availability without rewriting those historical documents.
