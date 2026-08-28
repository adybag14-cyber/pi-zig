from pathlib import Path

bridge = Path("src/extensions/js_bridge.mjs").read_text(encoding="utf-8")
registry = Path("src/extensions/provider_registry.zig").read_text(encoding="utf-8")
runtime = Path("src/extensions/js_runtime.zig").read_text(encoding="utf-8")
main = Path("src/main.zig").read_text(encoding="utf-8")
host = Path("src/extensions/host.zig").read_text(encoding="utf-8")

register_start = bridge.index("  registerProvider(nameOrProvider, config) {")
unregister_start = bridge.index("  unregisterProvider(rawName) {", register_start)
register_body = bridge[register_start:unregister_start]
unregister_end = bridge.index("  events,", unregister_start)
unregister_body = bridge[unregister_start:unregister_end]

checks = {
    "production registerProvider calls the real codec": "installProvider(name, value, !named)" in register_body,
    "checkpoint-180 codec is absent from unregisterProvider": "checkpoint-180-provider-method-codec" not in unregister_body,
    "callbacks have a dedicated runtime map": "const providerCallbacks = new Map()" in bridge,
    "provider method requests dispatch through retained callbacks": "invokeProviderMethod(request.callbackId" in bridge,
    "unregister removes retained callbacks": "removeProviderCallbacks(name)" in unregister_body,
    "native runtime exposes provider invocation": "pub fn invokeProviderMethod(" in runtime,
    "native registry validates descriptor ownership": "callbackRuntime(method.callback_id, method.path)" in registry,
    "OAuth refresh adapter exists": "pub fn refreshOAuth(" in registry,
    "OAuth key adapter exists": "pub fn oauthApiKey(" in registry,
    "OAuth model projection adapter exists": "pub fn modifyOAuthModels(" in registry,
    "startup associates provider with owning worker": "registerJsonWithRuntime(registration.name, registration.config_json, extension.script_runtime)" in main,
    "dynamic actions resolve extension worker": "scriptRuntimeForExtension(record.extension_name)" in main,
    "host exposes worker ownership lookup": "pub fn scriptRuntimeForExtension(" in host,
}
missing = [name for name, ok in checks.items() if not ok]
if missing:
    raise SystemExit("production provider-method integration checks failed: " + "; ".join(missing))
print(f"production provider-method integration: {len(checks)}/{len(checks)} checks passed")
