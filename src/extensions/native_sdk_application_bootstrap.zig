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
