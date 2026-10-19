// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual Node v24.14 loader.js createRequire/createRequireFromPath.
//! The declaration is built before Module and resolves only the one completed
//! private Module constructor when invoked. It never delegates to a legacy
//! require facade or creates a second cache.
const a = @import("native_node_argument_values.zig");
const v = a.v;
const c = a.c;
const Scope = a.Scope;
const functions = @import("native_node_module_callable.zig");
const modules = @import("native_node_module_constructor.zig");
const require_function = @import("native_node_commonjs_require_function.zig");
const caught = @import("native_agent_af_values.zig").caught;
const publication = @import("native_node_fs_private_publication.zig");
const declaration_key = "pi-native:private/commonjs-create-require-declaration";
const RequestFrame = a.frames.Frame(enum { filepath, file_url });
const PathFrame = a.frames.Frame(enum { proxy_path, module });

pub const Inputs = struct {
    paths: c.JSValue,
    process: c.JSValue,
    /// The completed actual internal/url owner, retaining URL/isURL/fileURLToPath.
    url_owner: c.JSValue,
    invalid_arg_type: c.JSValue,
    invalid_arg_value: c.JSValue,
    validate_string: c.JSValue,
    /// Original StringPrototypeEndsWith captured by the real bootstrap.
    string_ends_with: c.JSValue,
};
fn statement(engine: *v.em.Engine, comptime body: anytype, args: anytype) !void {
    var s = Scope.init(engine);
    var failure: ?anyerror = null;
    @call(.auto, body, .{&s} ++ args) catch |err| { failure = err; };
    _ = try s.finish(if (failure) |err| @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(declaration_key)) |known| return a.duplicate(engine, known);
    const candidate = try a.expression(engine, createBody, .{inputs});
    if (engine.native_module_values.get(declaration_key)) |known| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, known));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, declaration_key, candidate);
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    inline for (.{ inputs.invalid_arg_type, inputs.invalid_arg_value, inputs.validate_string, inputs.string_ends_with }) |value|
        if (!c.JS_IsFunction(s.engine.context, value)) return error.ActualCreateRequirePrimordialRequired;
    if (!c.JS_IsObject(inputs.paths) or !c.JS_IsObject(inputs.process) or !c.JS_IsObject(inputs.url_owner))
        return error.ActualCreateRequireImportOwnerRequired;
    const record = try s.objectProto(c.pi_js_null());
    try s.put(record, "paths", inputs.paths);
    try s.put(record, "process", inputs.process);
    inline for (.{ "URL", "isURL", "fileURLToPath" }) |name| {
        const value = try s.get(inputs.url_owner, name);
        if (!c.JS_IsFunction(s.engine.context, value)) return error.ActualCreateRequireURLImportRequired;
        try s.put(record, name, value);
    }
    try s.put(record, "invalidArgType", inputs.invalid_arg_type);
    try s.put(record, "invalidArgValue", inputs.invalid_arg_value);
    try s.put(record, "validateString", inputs.validate_string);
    try s.put(record, "endsWith", inputs.string_ends_with);
    try s.put(record, "isWindows", a.boolean(s, s.equal(try s.get(inputs.process, "platform"), try s.text("win32"))));
    try s.put(record, "createRequireError", try s.text("must be a file URL object, file URL string, or absolute path string"));
    return a.duplicate(s.engine, try s.own(try functions.create(s.engine, "createRequire", 1, true, invoke, &.{record})));
}
fn callMember(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const function = try s.get(receiver, name);
    return a.duplicate(s.engine, try s.call(function, receiver, args));
}
fn callCaptured(s: *Scope, owner: c.JSValue, name: [*:0]const u8, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(try s.get(owner, name), receiver, args));
}
fn isURLCondition(s: *Scope, owner: c.JSValue, value: c.JSValue) !c.JSValue {
    const result = try s.own(try a.expression(s.engine, callCaptured,
        .{ owner, @as([*:0]const u8, "isURL"), c.pi_js_undefined(), @as([]const c.JSValue, &.{value}) }));
    return a.boolean(s, s.truthy(result));
}
fn absoluteCondition(s: *Scope, paths: c.JSValue, value: c.JSValue) !c.JSValue {
    const result = try s.own(try a.expression(s.engine, callMember,
        .{ paths, @as([*:0]const u8, "isAbsolute"), @as([]const c.JSValue, &.{value}) }));
    return a.boolean(s, s.truthy(result));
}
fn constructURL(s: *Scope, owner: c.JSValue, value: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.construct(try s.get(owner, "URL"), &.{value}));
}
fn convertURL(s: *Scope, owner: c.JSValue, frame: *RequestFrame, input: c.JSValue) !c.JSValue {
    try frame.take(.file_url, a.expression(s.engine, constructURL, .{ owner, input }));
    try frame.take(.filepath, a.expression(s.engine, callCaptured,
        .{ owner, @as([*:0]const u8, "fileURLToPath"), c.pi_js_undefined(), @as([]const c.JSValue, &.{frame.get(.file_url)}) }));
    return c.pi_js_undefined();
}
fn invalidReason(s: *Scope, owner: c.JSValue, input: c.JSValue) !c.JSValue {
    const constructor = try s.get(owner, "invalidArgValue");
    return a.duplicate(s.engine, try s.construct(constructor, &.{ try s.text("filename"), input, try s.get(owner, "createRequireError") }));
}
fn invalid(s: *Scope, owner: c.JSValue, input: c.JSValue) anyerror {
    const reason = s.own(a.expression(s.engine, invalidReason, .{ owner, input }) catch |err| return err) catch |err| return err;
    return a.raise(s, reason);
}
fn invoke(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = RequestFrame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, invokeBody(&s, frame, roots[0], a.arg(args, 0)));
}
fn invokeBody(s: *Scope, frame: *RequestFrame, owner: c.JSValue, input: c.JSValue) !c.JSValue {
    const paths = try s.get(owner, "paths");
    const module_constructor = try s.own(try modules.actualConstructor(s.engine));
    // The parameter stays borrowed from the real callback argv. The two Source
    // let slots start undefined and survive the ordinary catch and final call.
    try frame.clear(.filepath);
    try frame.clear(.file_url);
    if (try a.condition(s.engine, isURLCondition, .{ owner, input }) or
        (c.JS_IsString(input) and !try a.condition(s.engine, absoluteCondition, .{ paths, input }))) {
        // The assignment source for the URL constructor is still the original
        // parameter, not a prior coercion or a host-parsed path.
        _ = a.expression(s.engine, convertURL, .{ owner, frame, input }) catch |err| {
            const reason = try caught(s.engine, err);
            // Source catch has no binding: discard its ordinary reason before
            // constructing the replacement ERR_INVALID_ARG_VALUE.
            var retirement = a.owned.Completion.initVoid(s.engine, {});
            retirement.release(reason);
            try retirement.finishVoid();
            return @as(anyerror!c.JSValue, invalid(s, owner, input));
        };
    } else if (!c.JS_IsString(input)) {
        return @as(anyerror!c.JSValue, invalid(s, owner, input));
    } else {
        try frame.copy(.filepath, input);
    }
    return fromPath(s.engine, owner, module_constructor, frame.get(.filepath), frame.get(.file_url));
}
fn endsWith(s: *Scope, owner: c.JSValue, filename: c.JSValue, suffix: []const u8) !c.JSValue {
    const result = try s.call(try s.get(owner, "endsWith"), filename, &.{try s.text(suffix)});
    return a.boolean(s, s.truthy(result));
}
fn joinPath(s: *Scope, paths: c.JSValue, filename: c.JSValue) !c.JSValue {
    const function = try s.get(paths, "join");
    return a.duplicate(s.engine, try s.call(function, paths, &.{ filename, try s.text("noop.js") }));
}
fn newModule(s: *Scope, module_constructor: c.JSValue, path: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.construct(module_constructor, &.{path}));
}
fn setFilename(s: *Scope, module: c.JSValue, filename: c.JSValue) !void {
    try s.put(module, "filename", filename);
}
fn setURL(s: *Scope, module_constructor: c.JSValue, module: c.JSValue, file_url: c.JSValue) !void {
    const key = try s.own(try modules.loaderKey(s.engine, module_constructor, .url));
    try s.pending();
    const atom = c.JS_ValueToAtom(s.engine.context, key);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try s.pending();
    if (atom == c.JS_ATOM_NULL) return error.MissingActualCreateRequireURLKey;
    const href = try s.get(file_url, "href");
    const status = c.JS_SetProperty(s.engine.context, module, atom, a.duplicate(s.engine, href));
    try s.pending();
    if (status < 0) return error.MissingActualCreateRequireURLStoreReason;
}
fn modulePaths(s: *Scope, module_constructor: c.JSValue, module: c.JSValue) !c.JSValue {
    const function = try s.get(module_constructor, "_nodeModulePaths");
    const path = try s.get(module, "path");
    return a.duplicate(s.engine, try s.call(function, module_constructor, &.{path}));
}
fn setModulePaths(s: *Scope, module_constructor: c.JSValue, module: c.JSValue) !void {
    const result = try s.own(try a.expression(s.engine, modulePaths, .{ module_constructor, module }));
    try s.put(module, "paths", result);
}
fn fromPath(engine: *v.em.Engine, owner: c.JSValue, module_constructor: c.JSValue, filename: c.JSValue, file_url: c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = PathFrame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, fromPathBody(&s, frame, owner, module_constructor, filename, file_url));
}
fn fromPathBody(s: *Scope, frame: *PathFrame, owner: c.JSValue, module_constructor: c.JSValue, filename: c.JSValue, file_url: c.JSValue) !c.JSValue {
    const trailing_slash = try a.condition(s.engine, endsWith, .{ owner, filename, @as([]const u8, "/") }) or
        (s.truthy(try s.get(owner, "isWindows")) and try a.condition(s.engine, endsWith, .{ owner, filename, @as([]const u8, "\\") }));
    if (trailing_slash)
        try frame.take(.proxy_path, a.expression(s.engine, joinPath, .{ try s.get(owner, "paths"), filename }))
    else
        try frame.copy(.proxy_path, filename);
    try frame.take(.module, a.expression(s.engine, newModule, .{ module_constructor, frame.get(.proxy_path) }));
    try statement(s.engine, setFilename, .{ frame.get(.module), frame.get(.proxy_path) });
    if (!c.JS_IsUndefined(file_url))
        try statement(s.engine, setURL, .{ module_constructor, frame.get(.module), file_url });
    try statement(s.engine, setModulePaths, .{ module_constructor, frame.get(.module) });
    return require_function.create(s.engine, .{
        .module_constructor = module_constructor,
        .process = try s.get(owner, "process"),
        .invalid_arg_type = try s.get(owner, "invalidArgType"),
        .validate_string = try s.get(owner, "validateString"),
    }, frame.get(.module));
}
