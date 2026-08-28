from pathlib import Path

bridge = Path("src/extensions/js_bridge.mjs").read_text(encoding="utf-8")
js_runtime = Path("src/extensions/js_runtime.zig").read_text(encoding="utf-8")
registry = Path("src/extensions/provider_registry.zig").read_text(encoding="utf-8")
coordinator = Path("src/extensions/provider_models.zig").read_text(encoding="utf-8")
models_store = Path("src/extensions/models_store.zig").read_text(encoding="utf-8")
oauth = Path("src/extensions/provider_oauth.zig").read_text(encoding="utf-8")
auth_storage = Path("src/auth/storage.zig").read_text(encoding="utf-8")
main = Path("src/main.zig").read_text(encoding="utf-8")
root = Path("src/extensions/root.zig").read_text(encoding="utf-8")

refresh_start = bridge.index("async function invokeProviderRefreshModels")
refresh_end = bridge.index("async function invokeProviderOAuthLogin", refresh_start)
refresh_body = bridge[refresh_start:refresh_end]
install_start = bridge.index("const installProvider =")
install_end = bridge.index("const pi =", install_start)
install_body = bridge[install_start:install_end]
run_phase_start = coordinator.index("    fn runPhase(")
run_phase_end = coordinator.index("    fn buildContextJson", run_phase_start)
run_phase_body = coordinator[run_phase_start:run_phase_end]
persist_start = coordinator.index("    fn applyPersistencePublication")
persist_end = coordinator.index("    fn applyCatalogPublication", persist_start)
persist_body = coordinator[persist_start:persist_end]
refresh_one_start = coordinator.index("    fn refreshOne(")
refresh_one_end = coordinator.index("    fn runPhase(", refresh_one_start)
refresh_one_body = coordinator[refresh_one_start:refresh_one_end]
reload_start = main.index("const RuntimeResourceReloadContext")
reload_end = main.index("const ExtensionShortcutContext", reload_start)
reload_body = main[reload_start:reload_end]

checks = {
    "live provider objects are retained separately from JSON snapshots": (
        "const providerLiveConfigs = new Map()" in bridge
        and "providerLiveConfigs.set(name, liveConfig)" in install_body
        and "providers.set(name, encoded.config)" in install_body
    ),
    "refresh contexts clone and deeply freeze credential and stored snapshots": (
        "deepFreezeProviderJson(cloneProviderJson(rawContext.credential" in refresh_body
        and "deepFreezeProviderJson(cloneProviderJson(rawContext.stored" in refresh_body
    ),
    "offline refresh never exposes force": (
        "if (allowNetwork && Object.prototype.hasOwnProperty.call(rawContext, 'force'))" in refresh_body
    ),
    "every refresh receives a live AbortSignal": (
        "signal," in refresh_body and "signal?.throwIfAborted?.()" in refresh_body
    ),
    "publish persistence is native-acknowledged before synchronous update": (
        "requestHost('provider_models_publish'" in refresh_body
        and "if (accepted !== true) return false" in refresh_body
        and refresh_body.index("publication.update()") > refresh_body.index("requestHost('provider_models_publish'")
    ),
    "provider-private updates publish their resulting catalog": (
        "requestHost('provider_models_catalog'" in refresh_body
        and "currentProviderModels(provider)" in refresh_body
    ),
    "async publication updates are rejected": "provider model publication update must execute synchronously" in refresh_body,
    "config and object provider refresh results are both supported": (
        "Array.isArray(returned)" in refresh_body
        and "typeof providerLiveConfigs.get(provider)?.getModels === 'function'" in refresh_body
    ),
    "production dispatch reaches the refresh bridge": (
        "request.kind === 'provider_refresh_models'" in bridge
        and "invokeProviderRefreshModels(request.callbackId" in bridge
    ),
    "native worker invocation installs a scoped host bridge and abort protocol": (
        "pub fn invokeProviderRefreshModels(" in js_runtime
        and "defer self.ui_bridge = previous_bridge" in js_runtime
        and 'provider_refresh_models' in js_runtime
        and 'abortable' in js_runtime
    ),
    "model refresh remains caller-bounded rather than using the ordinary timeout": (
        "models_refresh_timeout_ms: u64 = 0" in js_runtime
        and "self.timeout_ms = self.models_refresh_timeout_ms" in js_runtime
        and "defer self.timeout_ms = previous_timeout" in js_runtime
    ),
    "registry invocation resolves callback ownership on the persistent worker": (
        "pub fn refreshModels(" in registry
        and 'valueAtProviderPath(parsed.value, "refreshModels")' in registry
        and "registration.callbackRuntime(method.callback_id, method.path)" in registry
    ),
    "refresh iteration owns provider names across transactional replacement": (
        "pub fn refreshProviderNames" in registry
        and "try gpa.dupe(u8, registration.name)" in registry
        and "dangling after the first catalog commit" in registry
    ),
    "dynamic models validate before transactional registry replacement": (
        "pub fn validateDynamicModels" in registry
        and "var candidate = try Registration.init" in registry
        and "pub fn applyDynamicModels" in registry
    ),
    "complete credential JSON is preserved for refresh context": (
        "pub fn readCredentialJson" in auth_storage
        and "std.json.Stringify.value(value" in auth_storage
    ),
    "offline OAuth never refreshes while online OAuth uses canonical locked modification": (
        "if (allow_network and is_oauth)" in oauth
        and "modifyOAuthJsonAbortable" in oauth
        and "credentialForModelRefresh" in oauth
    ),
    "credential-aware model projection runs after dynamic publication": (
        "applyModelsForCredential" in oauth
        and "applyModelsForCredential(provider_id, credential" in run_phase_body
    ),
    "models-store uses a sidecar lock and atomic replacement": (
        '"models-store.json"' in models_store
        and '"{s}.lock"' in models_store
        and "createFileAtomic" in models_store
        and "atomic.replace" in models_store
    ),
    "models-store validates and cancellation-checks before authoritative replace": (
        "validateEntryValue" in models_store
        and models_store.count("ensureNotAborted(abort_flag)") >= 5
        and "make that file authoritative after cancellation" in models_store
    ),
    "persistence semantics distinguish omit write and delete": (
        "if (!has_persist.bool) return true" in persist_body
        and ".null => try self.deleteStored" in persist_body
        and ".object =>" in persist_body
        and "writeStored(context.provider_id" in persist_body
    ),
    "persisted model entries are semantically validated before writes": (
        "validateEntryValue(persist)" in persist_body
        and "validateDynamicModels(context.provider_id" in persist_body
    ),
    "generation and sequence guards protect every publication": (
        "isCurrentLocked" in persist_body
        and "InvalidProviderModelsPublicationOrder" in coordinator
        and "state.generation == generation" in coordinator
    ),
    "provider refreshes serialize registry mutation while newer generations abort older ones": (
        "refresh_mutex: Io.Mutex" in coordinator
        and "const generation = self.begin(state, &invocation_abort)" in refresh_one_body
        and "self.refresh_mutex.lockUncancelable" in refresh_one_body
        and "setAborted(state.active_abort)" in coordinator
    ),
    "cache-only phase precedes online credential resolution": (
        "offline_credential" in refresh_one_body
        and "runPhase(state, generation" in refresh_one_body
        and "online_credential" in refresh_one_body
        and refresh_one_body.index("offline_credential") < refresh_one_body.index("online_credential")
    ),
    "force is passed only into the online phase": (
        "false, null" in refresh_one_body
        and "true, options.force" in refresh_one_body
    ),
    "catalog commits update registry clients and live selector snapshots": (
        "self.registry.applyDynamicModels" in coordinator
        and "pool.setRuntimeProviders(self.registry.runtimes())" in coordinator
        and "state.model_catalog = self.registry.catalog()" in coordinator
    ),
    "reload preparation makes registry commitment allocation-free": (
        "pub fn prepareRegistry" in coordinator
        and "pub fn commitPreparedRegistry" in coordinator
        and "commitPreparedRegistry(self.provider_registry" in reload_body
    ),
    "reload supersedes generations before worker shutdown": (
        "self.provider_models.supersedeAll()" in reload_body
        and reload_body.index("self.provider_models.supersedeAll()") < reload_body.index("sessionShutdown")
    ),
    "startup restores cached extension catalogs before client construction": (
        "extension_models_runtime.refresh(.{ .allow_network = false })" in main
        and main.index("extension_models_runtime.refresh(.{ .allow_network = false })") < main.index("var client_pool: coding.live_state.ClientPool")
    ),
    "dynamic registration and unregister flow through the coordinator": (
        "self.provider_models.registerProvider(name" in main
        and "self.provider_models.unregisterProvider(name)" in main
    ),
    "interactive model selection performs an online selective-capable refresh": (
        "provider_models: *extensions.provider_models.Runtime" in main
        and ".allow_network = true" in main[main.index("const ModelTargetPromptContext"):main.index("const SettingsTargetPromptContext")]
    ),
    "provider-model modules are exported by the extension package": (
        'pub const models_store = @import("models_store.zig")' in root
        and 'pub const provider_models = @import("provider_models.zig")' in root
    ),
}

missing = [name for name, ok in checks.items() if not ok]
if missing:
    raise SystemExit("production provider refreshModels integration checks failed: " + "; ".join(missing))
print(f"production provider refreshModels integration: {len(checks)}/{len(checks)} checks passed")
