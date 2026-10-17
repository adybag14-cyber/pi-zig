//! Connect the actual AI module graph to the ordinary SDK factory/session.
//! Host-only composition: no partial public factory, worker/backend selection,
//! legacy SDK.Kind AgentSession/Models fallback or placeholder collaborators.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const actual = @import("native_sdk_default_real_assembly.zig");
pub const Inputs = struct {
    /// Genuine completed Agent module; its method/AF qualification is separate.
    agent_core: c.JSValue,
    /// Supplies the actual existing SessionManager and SettingsManager imports.
    sdk_namespace: c.JSValue,
    resource_loader: c.JSValue,
    typebox_graph: c.JSValue,
    paths: c.JSValue,
    path_utilities: c.JSValue,
    filesystem: c.JSValue,
    filesystem_promises: c.JSValue,
    configuration: c.JSValue,
    process: c.JSValue,
    shell: c.JSValue,
    config_values: c.JSValue,
    management_http: c.JSValue,
    abort: c.JSValue,
    auth_storage: c.JSValue,
    timing: c.JSValue,
};

/// Caller owns this completed graph, retaining it once per application module
/// instance. Platform bootstrap precedes this call. Actual external imports
/// stay explicit; this composer never invents unavailable implementations.
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const ai = try s.own(try @import("native_sdk_ai_imports.zig").create(engine));
    return actual.create(engine, .{
        .ai = try s.get(ai, "ai"),
        .compat = try s.get(ai, "compat"),
        .provider_factories = try s.get(ai, "providerFactories"),
        .agent_core = inputs.agent_core,
        .sdk_namespace = inputs.sdk_namespace,
        .resource_loader = inputs.resource_loader,
        .typebox_graph = inputs.typebox_graph,
        .paths = inputs.paths,
        .path_utilities = inputs.path_utilities,
        .filesystem = inputs.filesystem,
        .filesystem_promises = inputs.filesystem_promises,
        .configuration = inputs.configuration,
        .process = inputs.process,
        .shell = inputs.shell,
        .config_values = inputs.config_values,
        .management_http = inputs.management_http,
        .abort = inputs.abort,
        .auth_storage = inputs.auth_storage,
        .timing = inputs.timing,
    });
}
