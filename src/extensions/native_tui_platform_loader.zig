//! Native implementation of the exact target TUI helper/candidate algorithms.
//! Module identity is supplied from real installed files; no JS body executes.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_node_operation_scope.zig").Scope;
const callable = @import("native_node_module_callable.zig");
const private_binding = "#pi-native-tui-platform-module-origin";
pub const Identity = struct {
    platform_filename: []const u8,
    candidates_filename: []const u8,
    package_entry: []const u8,
};
const Owner = struct {
    engine: *js.Engine,
    helpers: c.JSValue,
    cjs_require: c.JSValue,
    candidate_require: c.JSValue,
    candidate_url: c.JSValue,
    path_namespace: c.JSValue,
    path_join: c.JSValue,
    path_dirname: c.JSValue,
    file_url_to_path: c.JSValue,
};
fn fromValue(value: c.JSValue) *Owner {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn owner(engine: *js.Engine) !*Owner {
    return fromValue(engine.native_module_values.get(private_binding) orelse return error.ActualTuiModuleIdentityRequired);
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ "helpers", "cjs_require", "candidate_require", "candidate_url", "path_namespace", "path_join", "path_dirname", "file_url_to_path" }) |field|
        c.JS_FreeValueRT(runtime, @field(state, field));
    const engine = state.engine;
    engine.gpa.destroy(state);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Owner));
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ "helpers", "cjs_require", "candidate_require", "candidate_url", "path_namespace", "path_join", "path_dirname", "file_url_to_path" }) |field|
        c.JS_MarkValue(runtime, @field(state, field), marker);
}
fn packageResolve(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(packageResolveBody(&stage, args, roots));
}
fn packageResolveBody(stage: *Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (args.len != 0 and stage.equal(args[0], try stage.text("@earendil-works/pi-tui")))
        return c.JS_DupValue(stage.engine.context, roots[0]);
    return c.JS_DupValue(stage.engine.context, try stage.call(roots[1], c.pi_js_undefined(), args));
}
fn requiredBuiltin(engine: *js.Engine, name: []const u8) !c.JSValue {
    return (try engine.requireBuiltin(name)) orelse error.ActualTuiLoaderDependencyRequired;
}
/// The resource provider validates manifest/name/main and all three actual
/// source-identity files before this call. Binding is once per engine and must
/// precede the public TUI aliases. No host path is synthesized from an alias.
pub fn bind(engine: *js.Engine, identity: Identity) !void {
    if (engine.native_module_values.contains(private_binding)) return error.NativeTuiModuleOriginAlreadyBound;
    if (!std.fs.path.isAbsolute(identity.platform_filename) or
        !std.fs.path.isAbsolute(identity.candidates_filename) or
        !std.fs.path.isAbsolute(identity.package_entry)) return error.ActualTuiModuleIdentityRequired;
    var stage = Scope.init(engine);
    const result = bindBody(&stage, identity);
    const returned = try stage.finish(result);
    engine.freeValue(returned);
}
fn bindBody(stage: *Scope, identity: Identity) !c.JSValue {
    const engine = stage.engine;
    const module = try stage.own(try requiredBuiltin(engine, "node:module"));
    const urls = try stage.own(try requiredBuiltin(engine, "node:url"));
    const paths = engine.native_module_values.get("node:path") orelse return error.ActualTuiLoaderDependencyRequired;
    const create_require = try stage.get(module, "createRequire");
    const path_to_url = try stage.get(urls, "pathToFileURL");
    const platform_url_object = try stage.call(path_to_url, c.pi_js_undefined(), &.{try stage.text(identity.platform_filename)});
    const platform_url = try stage.get(platform_url_object, "href");
    const candidates_url_object = try stage.call(path_to_url, c.pi_js_undefined(), &.{try stage.text(identity.candidates_filename)});
    const candidates_url = try stage.get(candidates_url_object, "href");
    const cjs_require = try stage.call(create_require, c.pi_js_undefined(), &.{platform_url});
    const candidate_require = try stage.call(create_require, c.pi_js_undefined(), &.{candidates_url});
    const original_resolve = try stage.get(candidate_require, "resolve");
    const package_entry = try stage.text(identity.package_entry);
    const resolver = try stage.own(try callable.create(engine, "resolve", 1, false, packageResolve, &.{ package_entry, original_resolve }));
    // This private require retains its real helper URL. Its package self-origin
    // is supplied by the verified physical resource provider, not an alias.
    try stage.put(candidate_require, "resolve", resolver);
    const map_constructor = try stage.own(try js.global(engine, "Map"));
    const helpers = try stage.construct(map_constructor, &.{});
    const values = [_]c.JSValue{
        helpers, cjs_require, candidate_require, candidates_url, paths,
        try stage.get(paths, "join"), try stage.get(paths, "dirname"), try stage.get(urls, "fileURLToPath"),
    };
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Owner)) == 0) return error.OutOfMemory;
    var attached = false;
    errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Owner));
    const state = try engine.gpa.create(Owner);
    errdefer if (!attached) engine.gpa.destroy(state);
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Native TUI module origin", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const object_generation = try stage.beforeAllocation();
    const object = try stage.checkedAllocation(c.JS_NewObjectClass(engine.context, @intCast(id)), object_generation);
    state.* = .{
        .engine = engine,
        .helpers = c.JS_DupValue(engine.context, values[0]),
        .cjs_require = c.JS_DupValue(engine.context, values[1]),
        .candidate_require = c.JS_DupValue(engine.context, values[2]),
        .candidate_url = c.JS_DupValue(engine.context, values[3]),
        .path_namespace = c.JS_DupValue(engine.context, values[4]),
        .path_join = c.JS_DupValue(engine.context, values[5]),
        .path_dirname = c.JS_DupValue(engine.context, values[6]),
        .file_url_to_path = c.JS_DupValue(engine.context, values[7]),
    };
    if (c.JS_SetOpaque(object, state) < 0) {
        inline for (.{ "helpers", "cjs_require", "candidate_require", "candidate_url", "path_namespace", "path_join", "path_dirname", "file_url_to_path" }) |field|
            engine.freeValue(@field(state, field));
        return error.InvalidNativeTuiModuleOwner;
    }
    attached = true;
    const retained = c.JS_DupValue(engine.context, object);
    errdefer engine.freeValue(retained);
    try engine.native_module_values.put(engine.gpa, private_binding, retained);
    return c.pi_js_undefined();
}
fn invoke(stage: *Scope, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return stage.call(try stage.get(object, name), object, args);
}
fn processField(stage: *Scope, name: [*:0]const u8) !c.JSValue {
    const process = try stage.own(try js.global(stage.engine, "process"));
    return stage.get(process, name);
}
fn swallowGuest(engine: *js.Engine, err: anyerror) !void {
    if (err != error.JavaScriptException) return err;
    // Only an ordinary caught completion is swallowed. The real invocation's
    // fatal producer remains authoritative, independent of diagnostic DATA.
    try engine.checkNativeEntry();
    if (engine.captured_exception) |reason| {
        engine.captured_exception = null;
        engine.freeValue(reason);
    }
    try engine.checkNativeEntry();
}
fn packageCandidate(engine: *js.Engine, state: *Owner, options: c.JSValue, candidate_list: c.JSValue, native_path: c.JSValue) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(packageCandidateBody(&stage, state, options, candidate_list, native_path));
}
fn packageCandidateBody(stage: *Scope, state: *Owner, options: c.JSValue, candidate_list: c.JSValue, native_path: c.JSValue) !c.JSValue {
    const option = try stage.get(options, "resolvePackage");
    const resolver = if (c.JS_IsNull(option) or c.JS_IsUndefined(option))
        try stage.get(state.candidate_require, "resolve") else option;
    const entry = try stage.call(resolver, c.pi_js_undefined(), &.{try stage.text("@earendil-works/pi-tui")});
    const push = try stage.get(candidate_list, "push");
    const directory = try stage.call(state.path_dirname, c.pi_js_undefined(), &.{entry});
    const path = try stage.call(state.path_join, c.pi_js_undefined(), &.{directory, try stage.text(".."), native_path});
    _ = try stage.call(push, candidate_list, &.{path});
    return c.pi_js_undefined();
}
fn candidates(stage: *Scope, state: *Owner, native_path: c.JSValue) !c.JSValue {
    // The omitted default argument is a fresh ordinary object. Its inherited
    // option getters and nullish fallbacks remain observable in source order.
    const options = try stage.object();
    const option_url = try stage.get(options, "moduleUrl");
    const module_url = if (c.JS_IsNull(option_url) or c.JS_IsUndefined(option_url)) state.candidate_url else option_url;
    const module_file = try stage.call(state.file_url_to_path, c.pi_js_undefined(), &.{module_url});
    const module_dir = try stage.call(state.path_dirname, c.pi_js_undefined(), &.{module_file});
    const array_generation = try stage.beforeAllocation();
    const list = try stage.checkedAllocation(c.JS_NewArray(stage.engine.context), array_generation);
    if (packageCandidate(stage.engine, state, options, list, native_path)) |returned| {
        stage.engine.freeValue(returned);
    } else |err| try swallowGuest(stage.engine, err);
    // The original member lookup precedes its three ordered arguments.
    const push = try stage.get(list, "push");
    const first = try stage.call(state.path_join, c.pi_js_undefined(), &.{module_dir, try stage.text(".."), native_path});
    const second = try stage.call(state.path_join, c.pi_js_undefined(), &.{module_dir, native_path});
    const option_exec = try stage.get(options, "execPath");
    const exec_path = if (c.JS_IsNull(option_exec) or c.JS_IsUndefined(option_exec))
        try processField(stage, "execPath") else option_exec;
    const executable_dir = try stage.call(state.path_dirname, c.pi_js_undefined(), &.{exec_path});
    const third = try stage.call(state.path_join, c.pi_js_undefined(), &.{executable_dir, native_path});
    _ = try stage.call(push, list, &.{first, second, third});
    const array_constructor = try stage.own(try js.global(stage.engine, "Array"));
    const from = try stage.get(array_constructor, "from");
    const set_constructor = try stage.own(try js.global(stage.engine, "Set"));
    const unique = try stage.construct(set_constructor, &.{list});
    return stage.call(from, array_constructor, &.{unique});
}
fn attempt(engine: *js.Engine, state: *Owner, module_path: c.JSValue, native_path: c.JSValue) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(attemptBody(&stage, state, module_path, native_path));
}
fn attemptBody(stage: *Scope, state: *Owner, module_path: c.JSValue, native_path: c.JSValue) !c.JSValue {
    const helper = try stage.call(state.cjs_require, c.pi_js_undefined(), &.{module_path});
    if (c.JS_IsNull(helper) or c.JS_IsUndefined(helper)) return c.pi_js_undefined();
    if (!c.JS_IsFunction(stage.engine.context, try stage.get(helper, "getText"))) return c.pi_js_undefined();
    if (!c.JS_IsFunction(stage.engine.context, try stage.get(helper, "getImage"))) return c.pi_js_undefined();
    _ = try invoke(stage, state.helpers, "set", &.{native_path, helper});
    return c.JS_DupValue(stage.engine.context, helper);
}
fn load(stage: *Scope, platform: c.JSValue, suffix: c.JSValue) !c.JSValue {
    const arch = try processField(stage, "arch");
    if (!stage.equal(arch, try stage.text("x64")) and !stage.equal(arch, try stage.text("arm64")))
        return c.pi_js_undefined();
    const state = try owner(stage.engine);
    const platform_arch = try stage.binary(0, try stage.binary(0, try stage.toString(platform), try stage.text("-")), try stage.toString(arch));
    const platform_file = try stage.binary(0, try stage.binary(0, try stage.binary(0, try stage.toString(platform), try stage.text("-platform")), try stage.toString(suffix)), try stage.text(".node"));
    const native_path = try stage.call(state.path_join, state.path_namespace, &.{
        try stage.text("native"), platform, try stage.text("prebuilds"), platform_arch, platform_file,
    });
    if (stage.truthy(try invoke(stage, state.helpers, "has", &.{native_path})))
        return c.JS_DupValue(stage.engine.context, try invoke(stage, state.helpers, "get", &.{native_path}));
    const paths = try candidates(stage, state, native_path);
    const symbol = try stage.checked(c.JS_GetIteratorSymbol(stage.engine.context));
    var iterator = try js.Iterator.init(stage.engine, paths, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |path| {
        defer stage.engine.freeValue(path);
        const found = attempt(stage.engine, state, path, native_path) catch |err| {
            try swallowGuest(stage.engine, err);
            continue;
        };
        if (!c.JS_IsUndefined(found)) {
            errdefer stage.engine.freeValue(found);
            try iterator.close();
            return found;
        }
        stage.engine.freeValue(found);
    }
    _ = try invoke(stage, state.helpers, "set", &.{native_path, c.pi_js_undefined()});
    return c.pi_js_undefined();
}
fn platformHelper(stage: *Scope) !c.JSValue {
    if (!stage.equal(try processField(stage, "platform"), try stage.text("darwin")) and
        !stage.equal(try processField(stage, "platform"), try stage.text("win32"))) return c.pi_js_undefined();
    return load(stage, try processField(stage, "platform"), try stage.text(""));
}
fn clipboardBody(stage: *Scope) !c.JSValue {
    if (!stage.equal(try processField(stage, "platform"), try stage.text("linux"))) return platformHelper(stage);
    const environment = try processField(stage, "env");
    if (!stage.truthy(try stage.get(environment, "DISPLAY"))) return c.pi_js_undefined();
    return load(stage, try stage.text("linux"), try stage.text("-x11"));
}
fn clipboard(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(clipboardBody(&stage));
}

/// Internal consumer entry: the same module-private Map and exact helper object
/// are shared with getNativeClipboard, including user cache replacements.
pub fn getNativePlatformHelper(engine: *js.Engine) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(platformHelper(&stage));
}
fn modifierCall(engine: *js.Engine, helper: c.JSValue, key: []const u8) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(modifierCallBody(&stage, helper, key));
}
fn modifierCallBody(stage: *Scope, helper: c.JSValue, key: []const u8) !c.JSValue {
    const result = try stage.call(try stage.get(helper, "isModifierPressed"), helper, &.{try stage.text(key)});
    return c.pi_js_bool(stage.engine.context, @intFromBool(stage.equal(result, c.pi_js_bool(stage.engine.context, 1))));
}
fn modifierBody(stage: *Scope, key: []const u8) !c.JSValue {
    const helper = try stage.own(try getNativePlatformHelper(stage.engine));
    // Source's first getter is outside its try; the second getter and method
    // call are inside. A thrown first getter must not be silently swallowed.
    if (c.JS_IsNull(helper) or c.JS_IsUndefined(helper) or
        !stage.truthy(try stage.get(helper, "isModifierPressed"))) return c.pi_js_bool(stage.engine.context, 0);
    return modifierCall(stage.engine, helper, key) catch |err| {
        try swallowGuest(stage.engine, err);
        return c.pi_js_bool(stage.engine.context, 0);
    };
}
pub fn isNativeModifierPressed(engine: *js.Engine, key: []const u8) !bool {
    var stage = Scope.init(engine);
    const result = try stage.finish(modifierBody(&stage, key));
    defer engine.freeValue(result);
    return c.JS_IsStrictEqual(engine.context, result, c.pi_js_bool(engine.context, 1));
}
fn enableInputBody(stage: *Scope) !c.JSValue {
    const helper = try stage.own(try getNativePlatformHelper(stage.engine));
    if (c.JS_IsNull(helper) or c.JS_IsUndefined(helper)) return c.pi_js_undefined();
    const enable = try stage.get(helper, "enableVirtualTerminalInput");
    if (c.JS_IsNull(enable) or c.JS_IsUndefined(enable)) return c.pi_js_undefined();
    _ = try stage.call(enable, helper, &.{});
    return c.pi_js_undefined();
}
pub fn enableWindowsVTInput(engine: *js.Engine) !void {
    var stage = Scope.init(engine);
    const result = stage.finish(enableInputBody(&stage)) catch |err| {
        try swallowGuest(engine, err);
        return;
    };
    engine.freeValue(result);
}

pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    try js.define(engine, exports, "getNativeClipboard",
        try callable.create(engine, "getNativeClipboard", 0, true, clipboard, &.{}));
}
