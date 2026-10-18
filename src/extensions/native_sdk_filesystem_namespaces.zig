//! Application bootstrap phases for actual SDK filesystem/path/auth imports.
//! These graphs retain real ordinary module/class identities. They supply no
//! SDK.Kind instance, substitute auth state record, or fabricated stat result.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const owned = @import("native_sdk_owned_completion.zig");
const guards = @import("native_agent_af_values.zig");
const sdk = @import("native_sdk.zig");
const platform_module = "pi-native:actual-sdk-filesystem-platform";
const auth_module = "pi-native:actual-sdk-auth-storage-owner";
const Creation = struct { engine: *em.Engine, auth: bool, previous: ?*Creation };
threadlocal var creating: ?*Creation = null;
fn enterCreation(entry: *Creation) !void {
    var cursor = creating;
    while (cursor) |current| : (cursor = current.previous)
        if (current.engine == entry.engine and current.auth == entry.auth) return error.ActualSdkFilesystemOwnerCreationReentry;
    entry.previous = creating;
    creating = entry;
}
pub const AuthDependencies = struct { get_agent_dir: c.JSValue, resolve_config_value: c.JSValue };
fn root(scope: *Scope, value: c.JSValue) !c.JSValue { return owned.ownRoot(scope, value); }
fn get(scope: *Scope, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    return root(scope, try guards.guard(scope.engine, generation, sdk.get(scope.engine, target, name)));
}
fn object(scope: *Scope) !c.JSValue { return root(scope, try sdk.object(scope.engine)); }
fn put(scope: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    const generation = scope.engine.native_allocation_generation;
    const status = c.JS_DefinePropertyValueStr(scope.engine.context, target, name, c.JS_DupValue(scope.engine.context, value), c.JS_PROP_C_W_E);
    const outcome: anyerror!c.JSValue = if (status < 0) js.capture(scope.engine) else scope.engine.checked(c.pi_js_undefined());
    _ = try guards.guard(scope.engine, generation, outcome);
}
fn publish(engine: *em.Engine, name: []const u8, graph: c.JSValue) !c.JSValue {
    const result: anyerror!c.JSValue = if (engine.registerValueModule(name, graph)) |_|
        c.JS_DupValue(engine.context, graph)
    else |err| err;
    var completion = owned.Completion.initValue(engine, result);
    completion.release(graph);
    return completion.finishValue();
}
fn requireFunctions(scope: *Scope, namespace: c.JSValue, comptime names: anytype) !void {
    inline for (names) |name| if (!c.JS_IsFunction(scope.engine.context, try get(scope, namespace, name))) return error.RequiredActualSdkFilesystemBinding;
}
/// Phase one precedes config.ts and the config-value resolver. The application
/// uses these exact fs/path namespaces for configuration and later assembly.
pub fn createPlatform(engine: *em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(platform_module)) |platform| return c.JS_DupValue(engine.context, platform);
    var creation: Creation = .{ .engine = engine, .auth = false, .previous = null };
    try enterCreation(&creation);
    defer creating = creation.previous;
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const result = platformOwned(engine) catch |err|
        return engine.checked(engine.leaveNativeInvocation(&invocation, sdk.fail(engine, err)));
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn platformOwned(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    const graph = try owned.finishValue(&scope, platformBody(&scope));
    return publish(engine, platform_module, graph);
}
fn platformBody(scope: *Scope) !c.JSValue {
    const engine = scope.engine;
    const io = engine.native_io orelse return error.ActualSdkFilesystemRequiresIo;
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, io);
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, io);
    if (!engine.native_module_values.contains("node:url")) try @import("node_url.zig").install(engine);
    const fs = engine.native_module_values.get("node:fs").?;
    const promises = engine.native_module_values.get("node:fs/promises") orelse return error.RequiredActualSdkFilesystemPromises;
    const path = engine.native_module_values.get("node:path").?;
    try requireFunctions(scope, fs, .{ "existsSync", "mkdirSync", "copyFileSync", "readFileSync", "writeFileSync", "readdirSync", "statSync", "realpathSync", "Stats" });
    try requireFunctions(scope, promises, .{"readFile"});
    try requireFunctions(scope, path, .{ "join", "dirname", "basename", "parse", "resolve", "relative", "isAbsolute" });
    if (!c.JS_IsStrictEqual(engine.context, promises, try get(scope, fs, "promises"))) return error.ActualSdkFilesystemPromisesIdentity;
    const result = try object(scope);
    try put(scope, result, "paths", path);
    try put(scope, result, "filesystem", fs);
    try put(scope, result, "filesystemPromises", promises);
    try put(scope, result, "pathUtilities", try root(scope, try @import("native_sdk_path_utilities_namespace.zig").create(engine, fs)));
    return c.JS_DupValue(engine.context, result);
}
/// Phase two follows genuine config.ts and shell/config-value composition.
/// The supplied resolver remains mandatory and is retained unchanged.
pub fn createAuth(engine: *em.Engine, platform: c.JSValue, dependencies: AuthDependencies) !c.JSValue {
    try engine.checkNativeEntry();
    var creation: Creation = .{ .engine = engine, .auth = true, .previous = null };
    try enterCreation(&creation);
    defer creating = creation.previous;
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const result = authOwned(engine, platform, dependencies) catch |err|
        return engine.checked(engine.leaveNativeInvocation(&invocation, sdk.fail(engine, err)));
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn authOwned(engine: *em.Engine, platform: c.JSValue, dependencies: AuthDependencies) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    // Cached lookup still performs the Source import-identity reads. Those
    // reads and their cleanup complete before any value escapes to the caller.
    if (engine.native_module_values.contains(auth_module))
        return owned.finishValue(&scope, authBody(&scope, platform, dependencies));
    const graph = try owned.finishValue(&scope, authBody(&scope, platform, dependencies));
    // Cold body returns its private owner; publish only after all temporaries
    // have retired. Preserve the actual exports result over owner retirement.
    const exports = sdk.get(engine, graph, "exports") catch |err| {
        var failed = owned.Completion.initValue(engine, err);
        failed.release(graph);
        return failed.finishValue();
    };
    const publication = engine.registerValueModule(auth_module, graph);
    const outcome: anyerror!c.JSValue = if (publication) |_| exports else |err| err;
    var selected = owned.Completion.initValue(engine, outcome);
    if (publication) |_| {} else |_| selected.release(exports);
    selected.release(graph);
    return selected.finishValue();
}
fn authBody(scope: *Scope, platform: c.JSValue, dependencies: AuthDependencies) !c.JSValue {
    const engine = scope.engine;
    const actual_platform = engine.native_module_values.get(platform_module) orelse return error.ActualSdkPlatformMustBeCreatedFirst;
    if (!c.JS_IsStrictEqual(engine.context, platform, actual_platform)) return error.ActualSdkPlatformIdentity;
    if (!c.JS_IsFunction(engine.context, dependencies.get_agent_dir) or !c.JS_IsFunction(engine.context, dependencies.resolve_config_value)) return error.RequiredActualSdkAuthDependency;
    if (engine.native_module_values.get(auth_module)) |owner| {
        if (!c.JS_IsStrictEqual(engine.context, try get(scope, owner, "getAgentDir"), dependencies.get_agent_dir) or !c.JS_IsStrictEqual(engine.context, try get(scope, owner, "resolveConfigValue"), dependencies.resolve_config_value)) return error.ActualSdkAuthModuleImportsChanged;
        return c.JS_DupValue(engine.context, try get(scope, owner, "exports"));
    }
    const imports = try object(scope);
    try put(scope, imports, "getAgentDir", dependencies.get_agent_dir);
    try put(scope, imports, "resolveConfigValue", dependencies.resolve_config_value);
    const utilities = try get(scope, platform, "pathUtilities");
    try put(scope, imports, "getFileRevision", try get(scope, utilities, "getFileRevision"));
    const backend = try root(scope, try @import("native_auth_file_storage_backend.zig").create(engine, .{ .get_agent_dir = dependencies.get_agent_dir }));
    try put(scope, imports, "FileAuthStorageBackend", backend);
    const exports = try root(scope, try @import("native_auth_storage_production.zig").create(engine, imports));
    if (!c.JS_IsStrictEqual(engine.context, backend, try get(scope, exports, "FileAuthStorageBackend"))) return error.ActualSdkFileBackendIdentity;
    const owner = try object(scope);
    try put(scope, owner, "getAgentDir", dependencies.get_agent_dir);
    try put(scope, owner, "resolveConfigValue", dependencies.resolve_config_value);
    try put(scope, owner, "exports", exports);
    return c.JS_DupValue(engine.context, owner);
}
