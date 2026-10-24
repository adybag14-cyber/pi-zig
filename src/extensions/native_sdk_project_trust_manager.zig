//! Complete original trust-manager.ts evaluation over genuine imported owners.
//! Paths and Store share each named capture and one normalizeCwd closure. No
//! partial trust namespace or runtime policy is supplied by this private owner.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const Engine = h.Engine;
const Scope = h.Scope;
const paths = @import("native_sdk_project_trust_paths.zig");
const store = @import("native_sdk_project_trust_store.zig");

pub const Inputs = struct {
    filesystem: c.JSValue,
    os: c.JSValue,
    paths: c.JSValue,
    lockfile: c.JSValue,
    configuration: c.JSValue,
    path_utilities: c.JSValue,
    text_utilities: c.JSValue,
};
const input_names = .{
    "filesystem", "os", "paths", "lockfile",
    "configuration", "path_utilities", "text_utilities",
};
const cache_key = "pi-private:actual-sdk-project-trust-manager";
const Creating = struct { engine: *Engine, previous: ?*Creating };
threadlocal var creating: ?*Creating = null;

pub fn create(engine: *Engine, inputs: Inputs) anyerror!c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached|
        return h.expression(engine, cachedBody, .{ cached, inputs });
    var cursor = creating;
    while (cursor) |current| : (cursor = current.previous)
        if (current.engine == engine) return error.ActualProjectTrustManagerCreationReentry;
    var entry: Creating = .{ .engine = engine, .previous = creating };
    creating = &entry;
    defer creating = entry.previous;
    var invocation: Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const result = createOwned(engine, inputs) catch |err|
        return engine.checked(engine.leaveNativeInvocation(&invocation,
            @import("native_sdk.zig").fail(engine, err)));
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn cachedBody(s: *Scope, cached: c.JSValue, inputs: Inputs) anyerror!c.JSValue {
    inline for (input_names) |name|
        if (!v.equal(s, try v.get(s, cached, name), @field(inputs, name)))
            return error.ActualProjectTrustManagerImportsChanged;
    return v.duplicate(s, try v.get(s, cached, "exports"));
}
fn createOwned(engine: *Engine, inputs: Inputs) anyerror!c.JSValue {
    const graph = try h.expression(engine, createBody, .{inputs});
    const exports_value = h.get(engine, graph, "exports") catch |err| {
        var selected = v.owned.Completion.initValue(engine, err);
        selected.release(graph);
        return selected.finishValue();
    };
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var selected = v.owned.Completion.initValue(engine, err);
        selected.release(exports_value);
        selected.release(graph);
        return selected.finishValue();
    };
    // All import Gets, construction, export acquisition and local retirement
    // complete before the one private module is published.
    engine.native_module_values.putAssumeCapacity(cache_key, graph);
    return exports_value;
}
fn required(s: *Scope, owner: c.JSValue, name: [*:0]const u8) anyerror!c.JSValue {
    const value = try v.get(s, owner, name);
    if (!c.JS_IsFunction(s.engine.context, value))
        return error.ActualProjectTrustManagerImportRequired;
    return value;
}
fn createBody(s: *Scope, inputs: Inputs) anyerror!c.JSValue {
    // Root every genuine module before a named import getter can reenter or
    // retire the host owner. Preserve the original source import order.
    inline for (input_names) |name|
        _ = try v.own(s, v.duplicate(s, @field(inputs, name)));
    const exists_sync = try required(s, inputs.filesystem, "existsSync");
    const mkdir_sync = try required(s, inputs.filesystem, "mkdirSync");
    const read_sync = try required(s, inputs.filesystem, "readFileSync");
    const write_sync = try required(s, inputs.filesystem, "writeFileSync");
    const home_dir = try required(s, inputs.os, "homedir");
    const dirname = try required(s, inputs.paths, "dirname");
    const join = try required(s, inputs.paths, "join");
    // lockfile is the actual default-import object and is never snapshotted to
    // a lockSync function: each Store attempt still reads that property live.
    const config_dir = try v.get(s, inputs.configuration, "CONFIG_DIR_NAME");
    const canonicalize = try required(s, inputs.path_utilities, "canonicalizePath");
    const resolve_path = try required(s, inputs.path_utilities, "resolvePath");
    const strip_bom = try required(s, inputs.text_utilities, "stripBom");

    const built = try paths.fromCaptures(s, .{
        .exists_sync = exists_sync, .home_dir = home_dir, .dirname = dirname,
        .join = join, .canonicalize = canonicalize, .resolve = resolve_path,
        .config_dir = config_dir,
    });
    const constructor_value = try store.fromCaptures(s, .{
        .exists_sync = exists_sync, .mkdir_sync = mkdir_sync, .read_sync = read_sync,
        .write_sync = write_sync, .dirname = dirname, .join = join,
        .resolve_path = resolve_path, .strip_bom = strip_bom,
        .lockfile = inputs.lockfile, .normalize = built.normalize_function,
    });
    // All four original runtime exports are present before publication.
    try v.put(s, built.exports_value, "ProjectTrustStore", constructor_value);
    const graph = try v.stateObject(s);
    inline for (input_names) |name| try v.put(s, graph, name, @field(inputs, name));
    try v.put(s, graph, "exports", built.exports_value);
    return v.duplicate(s, graph);
}
