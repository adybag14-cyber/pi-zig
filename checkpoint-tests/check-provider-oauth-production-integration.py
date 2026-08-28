from pathlib import Path

bridge = Path("src/extensions/js_bridge.mjs").read_text(encoding="utf-8")
runtime = Path("src/extensions/js_runtime.zig").read_text(encoding="utf-8")
registry = Path("src/extensions/provider_registry.zig").read_text(encoding="utf-8")
lifecycle = Path("src/extensions/provider_oauth.zig").read_text(encoding="utf-8")
storage = Path("src/auth/storage.zig").read_text(encoding="utf-8")
slash = Path("src/coding_agent/slash.zig").read_text(encoding="utf-8")
auth_tui = Path("src/coding_agent/auth_tui.zig").read_text(encoding="utf-8")
live = Path("src/coding_agent/live_state.zig").read_text(encoding="utf-8")
main = Path("src/main.zig").read_text(encoding="utf-8")
google = Path("src/ai/google.zig").read_text(encoding="utf-8")
mistral = Path("src/ai/mistral.zig").read_text(encoding="utf-8")
bedrock = Path("src/ai/bedrock.zig").read_text(encoding="utf-8")

login_start = bridge.index("async function invokeProviderOAuthLogin")
login_end = bridge.index("const toolRendererContext", login_start)
login_body = bridge[login_start:login_end]
request_start = bridge.index("const requestHost =")
request_end = bridge.index("globalThis.__piCompat.copyToClipboard", request_start)
request_body = bridge[request_start:request_end]
login_persist_start = lifecycle.index("    pub fn loginAndPersist(")
login_persist_end = lifecycle.index("    pub fn resolve(", login_persist_start)
login_persist_body = lifecycle[login_persist_start:login_persist_end]
resolve_start = lifecycle.index("    pub fn resolve(")
resolve_end = lifecycle.index("    fn applyCredentialModels", resolve_start)
resolve_body = lifecycle[resolve_start:resolve_end]

checks = {
    "production bridge dispatches OAuth login callbacks": "invokeProviderOAuthLogin(request.callbackId" in bridge,
    "OAuth callback receives the invocation AbortSignal": "signal," in login_body and "return await callback(callbacks)" in login_body,
    "all canonical OAuth interaction callbacks are exposed": all(marker in login_body for marker in (
        "onAuth(info", "onDeviceCode(info", "onPrompt(prompt", "onProgress(message", "onManualCodeInput()", "onSelect(prompt",
    )),
    "blocking OAuth host requests are signal-aware": all(marker in login_body for marker in (
        "requestHost('oauth_prompt'", "requestHost('oauth_manual_code'", "requestHost('oauth_select'",
    )) and login_body.count(", signal);\n") >= 3,
    "aborting a host request removes its pending promise": "pendingUi.delete(id)" in request_body and "signal?.addEventListener('abort'" in request_body,
    "OAuth login has a human-scale timeout": "oauth_login_timeout_ms: u64 = 15 * 60 * 1000" in runtime,
    "ordinary callback timeout is restored after OAuth login": "defer self.timeout_ms = previous_timeout" in runtime,
    "native runtime owns the OAuth UI bridge only during login": "pub fn invokeProviderOAuthLogin(" in runtime and "defer self.ui_bridge = previous_bridge" in runtime,
    "registry validates and unwraps OAuth login credentials": "pub fn loginOAuth(" in registry and "validateOAuthCredentialJson" in registry,
    "login persists through the abort-aware canonical store": "setOAuthJsonAbortable" in login_persist_body,
    "late canceled login results map to LoginCancelled": "abortRequested(abort_flag)" in login_persist_body and "error.LoginCancelled" in login_persist_body,
    "refresh is a serialized abort-aware credential transaction": "modifyOAuthJsonAbortable" in resolve_body,
    "request keys are derived after credential resolution": "oauthApiKey(provider_id, credential)" in resolve_body,
    "credential-dependent models are projected after resolution": "applyCredentialModels(provider_id, credential, abort_flag)" in resolve_body,
    "storage checks cancellation immediately before credential writes": storage.count("ensureOAuthCommitNotAborted(abort_flag)") >= 4,
    "slash login executes the extension OAuth lifecycle": "runtime.loginAndPersist(" in slash and "extensionOAuthAbortFlag(ctx)" in slash,
    "auth selector receives extension OAuth provider IDs": "runWithOAuthProviders" in auth_tui,
    "client pool exposes the cycle-free extension OAuth bridge": "pub const ExtensionOAuthBridge" in live and "resolveExtensionOAuth" in live,
    "OpenAI-compatible transports refresh through extension OAuth": all(marker in live for marker in (
        "refreshExtensionOpenAI", "refreshExtensionResponses", "refreshExtensionAnthropic", "refreshExtensionPiMessages",
    )),
    "Google Mistral and Bedrock expose refresh callbacks": "token_refresh_fn" in google and "token_refresh_fn" in mistral and "credential_refresh_fn" in bedrock,
    "main binds OAuth runtime to client pool and live catalog": "extension_oauth_runtime.bindClientPool(&client_pool)" in main and "extension_oauth_runtime.bindLiveState(&live)" in main,
    "reload routes OAuth through the replacement registry transactionally": "self.extension_oauth.registry = &new_provider_registry" in main and "self.extension_oauth.registry = self.provider_registry" in main,
}
missing = [name for name, ok in checks.items() if not ok]
if missing:
    raise SystemExit("production provider OAuth integration checks failed: " + "; ".join(missing))
print(f"production provider OAuth integration: {len(checks)}/{len(checks)} checks passed")
