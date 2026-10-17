//! Actual bootstrap order for filesystem -> config -> shell/shared resolver ->
//! ordinary auth -> timing. No successful child process or metadata substitute.
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub const Inputs = struct { process: c.JSValue, os: c.JSValue, url: c.JSValue, child_process: c.JSValue, config_module_url: c.JSValue, user_agent_runtime: @import("native_sdk_configuration_production.zig").UserAgentRuntime = .source };
pub fn create(engine: *em.Engine, inputs: Inputs) !c.JSValue {
    try engine.checkNativeEntry();
    const module_name = if (inputs.user_agent_runtime == .native_zig) "pi-native:sdk-runtime-imports-native-zig" else "pi-native:sdk-runtime-imports";
    if (engine.native_module_values.get(module_name)) |cached| return c.JS_DupValue(engine.context, cached);
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const value = createOwned(engine, inputs, module_name) catch |err| {
        const failed = @import("native_sdk.zig").fail(engine, err);
        return engine.checked(engine.leaveNativeInvocation(&invocation, failed));
    };
    return engine.checked(engine.leaveNativeInvocation(&invocation, value));
}
fn createOwned(engine: *em.Engine, inputs: Inputs, module_name: []const u8) !c.JSValue {
    const owned = @import("native_sdk_owned_completion.zig");
    var scope: Scope = .{ .engine = engine };
    const graph = try owned.finishValue(&scope, createBody(&scope, inputs));
    // A completed graph is not published until all construction temporaries
    // retire successfully. A warm dependency may ignore a freshly read value.
    const published: anyerror!c.JSValue = if (engine.registerValueModule(module_name, graph)) |_|
        c.JS_DupValue(engine.context, graph)
    else |err| err;
    var completion = owned.Completion.initValue(engine, published);
    completion.release(graph);
    return completion.finishValue();
}
fn createBody(scope: *Scope, inputs: Inputs) !c.JSValue {
    const engine = scope.engine;
    const platform = try scope.own(try @import("native_sdk_filesystem_namespaces.zig").createPlatform(engine));
    const configuration = try scope.own(try @import("native_sdk_configuration_production.zig").create(engine, .{
        .process = inputs.process,
        .os = inputs.os,
        .url = inputs.url,
        .paths = try scope.get(platform, "paths"),
        .filesystem = try scope.get(platform, "filesystem"),
        .path_utilities = try scope.get(platform, "pathUtilities"),
        .module_url = inputs.config_module_url,
        .user_agent_runtime = inputs.user_agent_runtime,
    }));
    const shell = try scope.own(try @import("native_sdk_shell_production.zig").create(engine, .{
        .process = inputs.process,
        .paths = try scope.get(platform, "paths"),
        .filesystem = try scope.get(platform, "filesystem"),
        .child_process = inputs.child_process,
        .configuration = configuration,
    }));
    const config_values = try scope.object();
    try @import("native_resolve_config_value_production.zig").install(engine, config_values, .{
        .process = inputs.process,
        .getShellConfig = try scope.get(shell, "getShellConfig"),
        .spawnSync = try scope.get(shell, "spawnSync"),
        .execSync = try scope.get(shell, "execSync"),
    });
    const auth = try scope.own(try @import("native_sdk_filesystem_namespaces.zig").createAuth(engine, platform, .{
        .get_agent_dir = try scope.get(configuration, "getAgentDir"),
        .resolve_config_value = try scope.get(config_values, "resolveConfigValue"),
    }));
    const timing = try scope.own(try @import("native_sdk_timings.zig").create(engine));
    const management_http = try scope.own(try @import("native_sdk_management_http.zig").create(engine));
    const result = try scope.object();
    try scope.put(result, "platform", platform);
    try scope.put(result, "configuration", configuration);
    try scope.put(result, "shell", shell);
    try scope.put(result, "configValues", config_values);
    try scope.put(result, "authStorage", auth);
    try scope.put(result, "timing", timing);
    try scope.put(result, "managementHttp", management_http);
    try scope.put(result, "process", inputs.process);
    return c.JS_DupValue(engine.context, result);
}
