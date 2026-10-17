//! Actual platform/bootstrap wiring for the ordinary SDK application owner.
//! Completed dependency graphs are explicit; missing imports are never replaced.
const std = @import("std");
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const application = @import("native_sdk_application_assembly.zig");

/// These are actual completed module values supplied by their production owners.
/// This struct is not a callback/stand-in injection scheme: no constructors or
/// methods are invented here. Full application tests require their real graphs.
pub const Completed = struct {
    resource_loader: c.JSValue,
    typebox_graph: c.JSValue,
    path_utilities: c.JSValue,
    configuration: c.JSValue,
    shell: c.JSValue,
    config_values: c.JSValue,
    management_http: c.JSValue,
    auth_storage: c.JSValue,
};

/// Remaining real imports of the Source DefaultResourceLoader module. The
/// application owner supplies these from actual PackageManager, extension
/// loader and chalk owners; this API neither manufactures nor selects them.
pub const ResourceImports = struct {
    package_manager: c.JSValue,
    chalk_default: c.JSValue,
    load_extension_from_factory: c.JSValue,
    load_extensions_cached: c.JSValue,
};

fn requireAsyncOwner(s: *Scope, prototype: c.JSValue, comptime names: anytype) !void {
    inline for (names) |name| if (!c.JS_IsAsyncFunction(try s.get(prototype, name))) return error.RequiredGenuineSdkAsyncOwner;
}

/// Concrete native owner route, as opposed to asking a caller to assemble eight
/// arbitrary Completed values. Platform and real SourceLoader/Node owners must
/// already be installed. No public/default namespace is published here.
pub fn createNativeFromOwners(engine: *em.Engine, runtime_inputs: @import("native_sdk_runtime_imports.zig").Inputs, resources: ResourceImports) !c.JSValue {
    try engine.checkNativeEntry();
    if (runtime_inputs.user_agent_runtime != .native_zig) return error.RequiredTruthfulNativeSdkRuntimeProfile;
    if (!c.JS_IsConstructor(engine.context, resources.package_manager) or !c.JS_IsFunction(engine.context, resources.load_extension_from_factory) or !c.JS_IsFunction(engine.context, resources.load_extensions_cached)) return error.RequiredActualResourceLoaderOwners;
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const value = nativeOwnerBody(engine, runtime_inputs, resources) catch |err| {
        const failed = @import("native_sdk.zig").fail(engine, err);
        return engine.checked(engine.leaveNativeInvocation(&invocation, failed));
    };
    return engine.checked(engine.leaveNativeInvocation(&invocation, value));
}
fn nativeOwnerBody(engine: *em.Engine, runtime_inputs: @import("native_sdk_runtime_imports.zig").Inputs, resources: ResourceImports) !c.JSValue {

    try engine.checkNativeEntry();
    var s: Scope = .{ .engine = engine };
    return @import("native_sdk_owned_completion.zig").finishValue(&s, nativeOwnerGraph(&s, runtime_inputs, resources));
}
fn nativeOwnerGraph(s: *Scope, runtime_inputs: @import("native_sdk_runtime_imports.zig").Inputs, resources: ResourceImports) !c.JSValue {
    const engine = s.engine;
    const runtime = try s.own(try @import("native_sdk_runtime_imports.zig").create(engine, runtime_inputs));
    const platform = try s.get(runtime, "platform");
    const auth_storage = try s.get(runtime, "authStorage");
    try requireAsyncOwner(s, try s.get(try s.get(auth_storage, "AuthStorage"), "prototype"), .{ "reloadFromStorageAsync", "readLatestData", "read", "modify", "delete", "list" });
    const managers = try s.own(try @import("native_sdk.zig").managerImports(engine));
    const loader = try s.own(try @import("native_sdk_resource_loader_assembly.zig").create(engine, .{
        .settings_manager = try s.get(managers, "SettingsManager"),
        .package_manager = resources.package_manager,
        .configuration = try s.get(runtime, "configuration"),
        .timing = try s.get(runtime, "timing"),
        .chalk_default = resources.chalk_default,
        .load_extension_from_factory = resources.load_extension_from_factory,
        .load_extensions_cached = resources.load_extensions_cached,
    }));
    try requireAsyncOwner(s, try s.get(loader, "prototype"), .{"reload"});
    return create(engine, .{
        .resource_loader = loader,
        .typebox_graph = try s.own(try @import("native_typebox_production_graph.zig").create(engine)),
        .path_utilities = try s.get(platform, "pathUtilities"),
        .configuration = try s.get(runtime, "configuration"),
        .shell = try s.get(runtime, "shell"),
        .config_values = try s.get(runtime, "configValues"),
        .management_http = try s.get(runtime, "managementHttp"),
        .auth_storage = auth_storage,
    });
}

/// Same genuine platform leaves used by native_worker, with process available
/// before consumers capture it. Caller retains environment through Engine life.
pub fn installPlatform(engine: *em.Engine, io: std.Io, environment: *const std.process.Environ.Map, arguments: []const []const u8) !void {
    try @import("timers.zig").install(engine, io);
    try @import("native_process.zig").install(engine, io, environment, arguments);
    try @import("node_path.zig").install(engine, io);
    try @import("node_url.zig").install(engine);
    try @import("node_fs.zig").install(engine, io);
    try @import("commonjs.zig").install(engine);
    try @import("console.zig").install(engine, io);
    try @import("text_encoding.zig").install(engine);
    try @import("text_decoder.zig").install(engine);
    try @import("native_crypto_random.zig").install(engine);
    try @import("native_web_fetch.zig").install(engine);
    try @import("native_node_os.zig").install(engine);
}

fn module(engine: *em.Engine, name: []const u8) !c.JSValue {
    return engine.native_module_values.get(name) orelse error.RequiredInstalledActualPlatformModule;
}

pub fn create(engine: *em.Engine, completed: Completed) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const root = try s.own(c.JS_GetGlobalObject(engine.context));
    const managers = try s.own(try @import("native_sdk.zig").managerImports(engine));
    const agent = try s.object();
    try @import("native_agent_complete.zig").install(engine, agent);
    const abort = try s.own(try @import("native_ai_auth_abort.zig").create(engine));
    const timing = try s.own(try @import("native_sdk_timings.zig").create(engine));
    return application.create(engine, .{
        .agent_core = agent,
        .sdk_namespace = managers,
        .resource_loader = completed.resource_loader,
        .typebox_graph = completed.typebox_graph,
        .paths = try module(engine, "node:path"),
        .path_utilities = completed.path_utilities,
        .filesystem = try module(engine, "node:fs"),
        .filesystem_promises = try module(engine, "node:fs/promises"),
        .configuration = completed.configuration,
        .process = try s.get(root, "process"),
        .shell = completed.shell,
        .config_values = completed.config_values,
        .management_http = completed.management_http,
        .abort = abort,
        .auth_storage = completed.auth_storage,
        .timing = timing,
    });
}
