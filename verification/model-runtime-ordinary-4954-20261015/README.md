# Ordinary ModelRuntime source checkpoint

The new `src/extensions/native_sdk_model_runtime_production.zig` implements the ordinary class from latest pinned `4954d760504c11df9b2cbdc040346107b6a8153d` `packages/coding-agent/src/core/model-runtime.ts` (SHA256 `BA6DB976A8947167CB867EDED70DFA96475182A3723CE2C7C9A88DB5AFEAB756`). It also implements explicit `operationSignal` and `raceWithAbortSignal` exports from `packages/coding-agent/src/utils/abort.ts`.

This is a source-only checkpoint: pinned Zig 0.16.0 formatting, AST checks and whitespace checks are permitted and recorded; no semantic compilation, native execution or Source capture has been run for this new class. The original expected output is absent. The default SDK route is unchanged and still requires Root integration and qualification.

Public composition APIs:

- `exports(engine, actualImports) !JSValue` returns `ModelRuntime` and `CredentialSynchronizationError` constructor identities.
- `constructor(engine, actualImports) !JSValue` returns the same ordinary six-argument class for a single assembly call.
- `abortHelpers(engine) !JSValue` returns the actual two ordinary helper functions. The assembler passes this namespace's functions explicitly; the constructor supplies no fallback functions.

The constructor accepts `(credentials, config, modelsPath, modelsStore, providers, modelNetworkEnabled)`. It initializes the 17 Source fields and calls the actual supplied `createModels({credentials, modelsStore})`, then its live `rebuildProviders()`. The 57 prototype methods retain Source declaration order, nonenumerable writable/configurable descriptors, function lengths and async-function prototypes. It creates no SDK.State object, seeds no builtins, and performs no `Engine.awaitValue` inside production implementation.

Static `ModelRuntime.create()` is deliberately outside this module. The static orchestration owner installs its actual implementation on the exact returned ordinary constructor identity through `native_sdk_model_runtime_create_production.install(engine, actualRuntimeConstructor, imports)`.

Required actual imports are validated explicitly: `createModels`, `ModelsError`, `lazyStream`, `normalizeContext`, `clampThinkingLevel`; chat/image/classifier assertion and error-result helpers; five provider-composer functions; `createVirtualModel`, `withVirtualModels`, `isVirtualModel`, `findLatestResponse`; the two abort functions; `ModelConfig.load`; and `builtinProviderCatalog.radiusProvider`. Missing imports fail composition. The caller is responsible for the actual namespace provenance; presence validation is not a qualification claim.

Dependency intake and current gaps:

- Actual Models namespace: `ai_anthropic_federation_15`'s `native_ai_models_namespace`, constructor/getter/core prototype qualification pending. The Models42/provider factory assembly remains its owner's scope.
- Actual lazy-stream, transcript normalization and model-operation exports: central AI/Codecs assembly must provide the real helper identities. No synthetic forwarding or empty stream is supplied here.
- Actual provider-composer/config-value namespace: `sdk_provider_composer_15`'s new production modules; Source retry and native qualification pending at this checkpoint.
- Actual virtual-model namespace: `sdk_virtual_models_15`'s `native_sdk_virtual_models_production`; genuine Source36 captured by its owner, native compilation/runtime pending.
- Actual ModelConfig and schema prerequisites: `oauth_chatgpt_15`; class/schema assembly qualification remains with that owner.
- Actual RuntimeCredentials and static create: `sdk_boundaries_15`; ordinary credentials Source20 captured, native qualification pending.
- Actual AuthStorage/backend and ModelsStore inputs: the auth/store owners and static-create assembler supply these objects. This ordinary class never manufactures them.
- Shared SDK/Engine assembly: Root must replace the synthetic `Kind.model_runtime`/`seedBuiltins` default route with these explicit actual namespace exports after qualification. This checkpoint changes no shared SDK, Engine or build file.

The new test entry contains missing-import and actual abort-helper checks. `captureActualAssembly(engine, imports)` requires the complete production assembler's actual imports and executes the same caller program as the genuine Source driver. Caller objects control credentials, config, provider data, request headers, held availability passes and queued cancellation; the Source method bodies and module imports are not rewritten. The planned observations cover prototype/field metadata, live access, request getter/rest behavior, stale refresh rejection, per-provider credential cancellation, committed credential synchronization errors and abort listener ownership.

Publication of this source checkpoint does not qualify default SDK activation, full factory composition, full Pi or a release. No Source/native job should be launched until Root grants its resource slot and immutable Source/control manifests are ready.
