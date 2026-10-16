# Actual SDK default assembly and concrete model dependencies

Base: `1097e7ff3fa72d3284a762d4ed4cb583ae20072f`. Source authority:
`4954d760504c11df9b2cbdc040346107b6a8153d`; the relevant package bodies are
unchanged in the inspected `0fb` successor. Toolchain remains Zig **0.16.0**.

The first intake retains exact ordinary ModelRuntime660c, AgentSessionRuntimefb97,
provider composer059c, virtual53c and remote catalogfb5bd implementation bytes.
The composer references a nonexistent `native_agent_async_api.zig` in its
published candidate. This lane repairs that import to the existing actual
`native_agent_async.zig` owner, whose create/wait/settle/rejectError interface it
uses. This is a source repair awaiting native compilation.

`native_sdk_models_store_production.zig` implements the actual coding-agent
InMemoryCodingAgentModelsStore and FileModelsStore ordinary classes. It retains
their declared fields, nonenumerable prototype methods, live structuredClone,
locked file backend import, bounded shared first-path readState, revision cache,
shared reload/readers, raw rejection reasons and reader finally cancellation.
It does not alias the older pi-ai model store.

`native_sdk_model_config_production.zig` constructs the actual latest schema
through the caller's shared TypeBox Type and provider schema namespaces and
invokes that same graph's real Compiler.Compile. Its ordinary ModelConfig.load
performs real readFile, comment/BOM handling, genuine Check/Errors formatting,
structuredClone and recursive freezing. No hand-written schema validator or
fallback checker participates. The Source text helpers have their own native
callbacks in `native_sdk_model_text_production.zig`.

`native_sdk_default_real_assembly.create(engine, inputs)` captures actual shared
AI/compat/agent/provider/path/filesystem/config/shell/HTTP/abort/auth/timing
namespaces. It creates composer, virtual/remote wrappers, actual all.ts catalog
bindings, concrete config/stores/credentials, ordinary ModelRuntime and static
create, ordinary AgentSessionRuntime, shared session AI, ordinary AgentSession
and actual sdk.ts factory in one graph. Constructor and callback identities are
retained in `graph.exports`, `graph.imports` and the component namespaces.
The application must retain this graph as its one module instance. There is no
second provider, TypeBox Memory/Settings, credential or model registry.

`select(engine, sdk_namespace, graph)` preflights all seven actual replacement
bindings before selecting ModelRuntime, AgentSession, AgentSessionRuntime and
their four actual factory functions. **It has not been invoked.** Default
public SDK paths still use their existing implementation until Root qualifies
all actual input namespaces and the composed native graph. Function-shape
checks are prerequisites and cannot establish collaborator provenance.

The real provider catalog comes from the Models lane's
`native_ai_provider_factories.create` result: all 42 original provider factories,
the exact providers/all.ts functions and the original generated catalog graph.
Its namespace bindings are shared directly; catalog rows are never promoted
into substitute providers. Remote wrapper historical Source64 proof used older
PI_PACKAGE_DIR metadata. That limitation remains explicit; the new graph takes
the application's actual VERSION/getPiUserAgent imports and requires its own
qualification.

The user-style `sdk-model-dependencies-4954.input.mjs` prepares **53 probes**:
ordinary metadata/field identity, memory and physical file mutations, clone
isolation, shared/bounded cache state, external BOM reload and parse recovery,
raw abort reasons, key/getter order, immutable ModelConfig snapshots, actual
TypeBox validation errors and schema fields. The external capture imports the
real original Source classes and checks their pinned bytes. Its physical files
and before/after metadata inventories are retained under its explicit output
path. No genuine output exists until the owned Source terminal passes with full
posthash/path/control freezes. The native comparator consumes those genuine
bytes and fails on the first changed row; it supplies no expected values.

Status: formatting, Zig AST and external probe/capture syntax checks passed.
Native semantic compilation/execution, host GPA, C malloc, whole SDK transport
qualification and default selection remain unrun. No C or shared Root source
was edited by this lane.
