//! Application bootstrap phases for actual SDK filesystem/path/auth imports.
//! These graphs retain real ordinary module/class identities. They supply no
//! SDK.Kind instance, substitute auth state record, or fabricated stat result.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const platform_module = "pi-native:actual-sdk-filesystem-platform";
const auth_module = "pi-native:actual-sdk-auth-storage-owner";
pub const AuthDependencies = struct { get_agent_dir: c.JSValue, resolve_config_value: c.JSValue };
fn requireFunctions(scope: *Scope, namespace: c.JSValue, comptime names: anytype) !void {
    inline for (names) |name| if (!c.JS_IsFunction(scope.engine.context, try scope.get(namespace, name))) return error.RequiredActualSdkFilesystemBinding;
}
/// Phase one precedes config.ts and the config-value resolver. The application
/// uses these exact fs/path namespaces for configuration and later assembly.
pub fn createPlatform(engine: *em.Engine) !c.JSValue {
    if (engine.native_module_values.get(platform_module)) |platform| return c.JS_DupValue(engine.context, platform);
    const io = engine.native_io orelse return error.ActualSdkFilesystemRequiresIo;
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, io);
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, io);
    if (!engine.native_module_values.contains("node:url")) try @import("node_url.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const fs = engine.native_module_values.get("node:fs").?;
    const promises = engine.native_module_values.get("node:fs/promises") orelse return error.RequiredActualSdkFilesystemPromises;
    const path = engine.native_module_values.get("node:path").?;
    try requireFunctions(&scope, fs, .{ "existsSync", "mkdirSync", "copyFileSync", "readFileSync", "writeFileSync", "readdirSync", "statSync", "realpathSync", "Stats" });
    try requireFunctions(&scope, promises, .{"readFile"});
    try requireFunctions(&scope, path, .{ "join", "dirname", "basename", "parse", "resolve", "relative", "isAbsolute" });
    if (!c.JS_IsStrictEqual(engine.context, promises, try scope.get(fs, "promises"))) return error.ActualSdkFilesystemPromisesIdentity;
    const result = try scope.object();
    try scope.put(result, "paths", path);
    try scope.put(result, "filesystem", fs);
    try scope.put(result, "filesystemPromises", promises);
    try scope.put(result, "pathUtilities", try scope.own(try @import("native_sdk_path_utilities_namespace.zig").create(engine, fs)));
    try engine.registerValueModule(platform_module, result);
    return c.JS_DupValue(engine.context, result);
}
/// Phase two follows genuine config.ts and shell/config-value composition.
/// The supplied resolver remains mandatory and is retained unchanged.
pub fn createAuth(engine: *em.Engine, platform: c.JSValue, dependencies: AuthDependencies) !c.JSValue {
    const actual_platform = engine.native_module_values.get(platform_module) orelse return error.ActualSdkPlatformMustBeCreatedFirst;
    if (!c.JS_IsStrictEqual(engine.context, platform, actual_platform)) return error.ActualSdkPlatformIdentity;
    if (!c.JS_IsFunction(engine.context, dependencies.get_agent_dir) or !c.JS_IsFunction(engine.context, dependencies.resolve_config_value)) return error.RequiredActualSdkAuthDependency;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (engine.native_module_values.get(auth_module)) |owner| {
        if (!c.JS_IsStrictEqual(engine.context, try scope.get(owner, "getAgentDir"), dependencies.get_agent_dir) or !c.JS_IsStrictEqual(engine.context, try scope.get(owner, "resolveConfigValue"), dependencies.resolve_config_value)) return error.ActualSdkAuthModuleImportsChanged;
        return c.JS_DupValue(engine.context, try scope.get(owner, "exports"));
    }
    const imports = try scope.object();
    try scope.put(imports, "getAgentDir", dependencies.get_agent_dir);
    try scope.put(imports, "resolveConfigValue", dependencies.resolve_config_value);
    const utilities = try scope.get(platform, "pathUtilities");
    try scope.put(imports, "getFileRevision", try scope.get(utilities, "getFileRevision"));
    const backend = try scope.own(try @import("native_auth_file_storage_backend.zig").create(engine, .{ .get_agent_dir = dependencies.get_agent_dir }));
    try scope.put(imports, "FileAuthStorageBackend", backend);
    const exports = try scope.own(try @import("native_auth_storage_production.zig").create(engine, imports));
    if (!c.JS_IsStrictEqual(engine.context, backend, try scope.get(exports, "FileAuthStorageBackend"))) return error.ActualSdkFileBackendIdentity;
    const owner = try scope.object();
    try scope.put(owner, "getAgentDir", dependencies.get_agent_dir);
    try scope.put(owner, "resolveConfigValue", dependencies.resolve_config_value);
    try scope.put(owner, "exports", exports);
    try engine.registerValueModule(auth_module, owner);
    return c.JS_DupValue(engine.context, exports);
}
