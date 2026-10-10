//! Settings storage callbacks and queued writes remain on the VM owner.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const accessors = @import("native_sdk_settings.zig");
const models = @import("native_sdk_models.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Stage = enum(c_int) { memory, file, capture, persist, write, failed, reload };
fn function(engine: *engine_mod.Engine, captured: c.JSValue, stage: Stage) !c.JSValue {
    var values = [_]c.JSValue{captured};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "sdkSettingsStorage", 2, @intFromEnum(stage), 1, &values));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, capture: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return dispatch(engine, capture[0], @enumFromInt(magic), if (argc > 0) args[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn remove(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8) !void {
    const atom = c.JS_NewAtom(engine.context, name);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, object, atom, 0) < 0) return error.JavaScriptException;
}
fn has(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8) !bool {
    const atom = c.JS_NewAtom(engine.context, name);
    defer c.JS_FreeAtom(engine.context, atom);
    const found = c.JS_HasProperty(engine.context, object, atom);
    if (found < 0) return error.JavaScriptException;
    return found == 1;
}
fn nullish(value: c.JSValue) bool {
    return c.JS_IsUndefined(value) or c.JS_IsNull(value);
}
pub fn migrate(engine: *engine_mod.Engine, value: c.JSValue) !void {
    if (try has(engine, value, "queueMode") and !try has(engine, value, "steeringMode")) {
        try sdk.put(engine, value, "steeringMode", try sdk.get(engine, value, "queueMode"));
        try remove(engine, value, "queueMode");
    }
    const websockets = try sdk.get(engine, value, "websockets");
    defer engine.freeValue(websockets);
    if (!try has(engine, value, "transport") and c.JS_IsBool(websockets)) {
        try sdk.put(engine, value, "transport", try sdk.text(engine, if (c.JS_ToBool(engine.context, websockets) == 1) "websocket" else "sse"));
        try remove(engine, value, "websockets");
    }
    const skills = try sdk.get(engine, value, "skills");
    defer engine.freeValue(skills);
    if (c.JS_IsObject(skills) and !c.JS_IsArray(skills)) {
        const enabled = try sdk.get(engine, skills, "enableSkillCommands");
        defer engine.freeValue(enabled);
        const previous = try sdk.get(engine, value, "enableSkillCommands");
        defer engine.freeValue(previous);
        if (!c.JS_IsUndefined(enabled) and c.JS_IsUndefined(previous)) try sdk.put(engine, value, "enableSkillCommands", c.JS_DupValue(engine.context, enabled));
        const paths = try sdk.get(engine, skills, "customDirectories");
        defer engine.freeValue(paths);
        if (c.JS_IsArray(paths) and try sdk.length(engine, paths) > 0) try sdk.put(engine, value, "skills", c.JS_DupValue(engine.context, paths)) else try remove(engine, value, "skills");
    }
    const retry = try sdk.get(engine, value, "retry");
    defer engine.freeValue(retry);
    if (c.JS_IsObject(retry) and !c.JS_IsArray(retry)) {
        const delay = try sdk.get(engine, retry, "maxDelayMs");
        defer engine.freeValue(delay);
        const provider = try sdk.get(engine, retry, "provider");
        defer engine.freeValue(provider);
        const previous = if (c.JS_IsObject(provider)) try sdk.get(engine, provider, "maxRetryDelayMs") else c.pi_js_undefined();
        defer engine.freeValue(previous);
        if (c.JS_IsNumber(delay) and nullish(previous)) {
            const next = try sdk.object(engine);
            defer engine.freeValue(next);
            try models.copy(engine, next, provider);
            try sdk.put(engine, next, "maxRetryDelayMs", c.JS_DupValue(engine.context, delay));
            try sdk.put(engine, retry, "provider", c.JS_DupValue(engine.context, next));
        }
        try remove(engine, retry, "maxDelayMs");
    }
}
fn jsonText(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const json = try sdk.get(engine, global, "JSON");
    defer engine.freeValue(json);
    return sdk.invoke(engine, json, "stringify", &.{ value, c.pi_js_null(), c.JS_NewInt32(engine.context, 2) });
}
fn parse(engine: *engine_mod.Engine, input: c.JSValue) !c.JSValue {
    if (c.JS_ToBool(engine.context, input) != 1) return sdk.object(engine);
    const text = try engine.toString(input);
    defer engine.gpa.free(text);
    const raw = if (std.mem.startsWith(u8, text, "\xef\xbb\xbf")) text[3..] else text;
    const result = try sdk.jsonObject(engine, raw);
    errdefer engine.freeValue(result);
    try migrate(engine, result);
    return result;
}
fn capturedFailure(engine: *engine_mod.Engine, err: anyerror) !c.JSValue {
    if (err == error.JavaScriptException and engine.captured_exception != null) return c.JS_DupValue(engine.context, engine.captured_exception.?);
    const failure = try engine.checked(c.JS_NewError(engine.context));
    errdefer engine.freeValue(failure);
    try sdk.put(engine, failure, "message", try sdk.text(engine, @errorName(err)));
    return failure;
}
fn record(engine: *engine_mod.Engine, data: c.JSValue, scope: []const u8, failure: c.JSValue) !void {
    const errors = try sdk.get(engine, data, "errors");
    defer engine.freeValue(errors);
    const entry = try sdk.object(engine);
    defer engine.freeValue(entry);
    try sdk.put(engine, entry, "scope", try sdk.text(engine, scope));
    try sdk.put(engine, entry, "error", c.JS_DupValue(engine.context, failure));
    try sdk.put(engine, entry, "path", try sdk.get(engine, data, if (std.mem.eql(u8, scope, "global")) "settingsPath" else "projectPath"));
    try sdk.append(engine, errors, c.JS_DupValue(engine.context, entry));
}
fn read(engine: *engine_mod.Engine, data: c.JSValue, scope: []const u8) !c.JSValue {
    if (std.mem.eql(u8, scope, "project") and !try trusted(engine, data)) return sdk.object(engine);
    const job = try sdk.object(engine);
    defer engine.freeValue(job);
    const capture = try function(engine, job, .capture);
    defer engine.freeValue(capture);
    const storage = try sdk.get(engine, data, "storage");
    defer engine.freeValue(storage);
    const scope_value = try sdk.text(engine, scope);
    defer engine.freeValue(scope_value);
    const ignored = try sdk.invoke(engine, storage, "withLock", &.{ scope_value, capture });
    engine.freeValue(ignored);
    const current = try sdk.get(engine, job, "current");
    defer engine.freeValue(current);
    return parse(engine, current);
}
fn loadScope(engine: *engine_mod.Engine, data: c.JSValue, scope: []const u8, preserve: bool) !void {
    const loaded = read(engine, data, scope) catch |err| {
        if (err == error.OutOfMemory) return err;
        const failure = try capturedFailure(engine, err);
        defer engine.freeValue(failure);
        try sdk.put(engine, data, if (std.mem.eql(u8, scope, "global")) "globalLoadError" else "projectLoadError", c.JS_DupValue(engine.context, failure));
        try record(engine, data, scope, failure);
        if (!preserve) try sdk.put(engine, data, if (std.mem.eql(u8, scope, "global")) "global" else "project", try sdk.object(engine));
        return;
    };
    defer engine.freeValue(loaded);
    try sdk.put(engine, data, if (std.mem.eql(u8, scope, "global")) "global" else "project", c.JS_DupValue(engine.context, loaded));
    try sdk.put(engine, data, if (std.mem.eql(u8, scope, "global")) "globalLoadError" else "projectLoadError", c.pi_js_undefined());
}
pub fn initialize(engine: *engine_mod.Engine, data: c.JSValue, storage: c.JSValue, options: c.JSValue, initial: c.JSValue) !void {
    const trusted_value = if (c.JS_IsObject(options)) try sdk.get(engine, options, "projectTrusted") else c.pi_js_undefined();
    defer engine.freeValue(trusted_value);
    try sdk.put(engine, data, "projectTrusted", if (nullish(trusted_value)) c.pi_js_bool(engine.context, 1) else c.JS_DupValue(engine.context, trusted_value));
    try sdk.put(engine, data, "errors", try sdk.array(engine));
    try sdk.put(engine, data, "modifiedGlobal", try sdk.object(engine));
    try sdk.put(engine, data, "modifiedProject", try sdk.object(engine));
    try sdk.put(engine, data, "settingsQueue", try sdk.promise(engine, c.pi_js_undefined()));
    if (c.JS_IsObject(storage)) {
        try sdk.put(engine, data, "storage", c.JS_DupValue(engine.context, storage));
    } else {
        const memory = try sdk.object(engine);
        defer engine.freeValue(memory);
        const path = try sdk.get(engine, data, "settingsPath");
        defer engine.freeValue(path);
        try sdk.put(engine, memory, "withLock", try function(engine, data, if (c.JS_IsString(path)) .file else .memory));
        try sdk.put(engine, data, "storage", c.JS_DupValue(engine.context, memory));
        const settings = if (c.JS_IsObject(initial)) try accessors.clone(engine, initial) else try sdk.object(engine);
        defer engine.freeValue(settings);
        try migrate(engine, settings);
        try sdk.put(engine, data, "storageGlobal", try jsonText(engine, settings));
    }
    try loadScope(engine, data, "global", false);
    try loadScope(engine, data, "project", false);
    try rebuild(engine, data);
}
pub fn rebuild(engine: *engine_mod.Engine, data: c.JSValue) !void {
    const global = try sdk.get(engine, data, "global");
    defer engine.freeValue(global);
    const project = try sdk.get(engine, data, "project");
    defer engine.freeValue(project);
    try sdk.put(engine, data, "settings", try accessors.deepMerge(engine, global, project, 0));
}
pub fn mark(engine: *engine_mod.Engine, data: c.JSValue, path: []const u8, project: bool) !void {
    const modified = try sdk.get(engine, data, if (project) "modifiedProject" else "modifiedGlobal");
    defer engine.freeValue(modified);
    const split = std.mem.indexOfScalar(u8, path, '.');
    const root = try engine.gpa.dupeZ(u8, if (split) |index| path[0..index] else path);
    defer engine.gpa.free(root);
    if (split) |index| {
        var nested = try sdk.get(engine, modified, root);
        defer engine.freeValue(nested);
        if (!c.JS_IsObject(nested)) {
            engine.freeValue(nested);
            nested = try sdk.object(engine);
            try sdk.put(engine, modified, root, c.JS_DupValue(engine.context, nested));
        }
        const key = try engine.gpa.dupeZ(u8, path[index + 1 ..]);
        defer engine.gpa.free(key);
        try sdk.put(engine, nested, key, c.pi_js_bool(engine.context, 1));
    } else if (!try has(engine, modified, root)) try sdk.put(engine, modified, root, c.pi_js_null());
}
pub fn save(engine: *engine_mod.Engine, data: c.JSValue, project: bool) !void {
    try rebuild(engine, data);
    const failure = try sdk.get(engine, data, if (project) "projectLoadError" else "globalLoadError");
    defer engine.freeValue(failure);
    if (c.JS_ToBool(engine.context, failure) == 1) return;
    const job = try sdk.object(engine);
    defer engine.freeValue(job);
    try sdk.put(engine, job, "data", c.JS_DupValue(engine.context, data));
    try sdk.put(engine, job, "project", c.pi_js_bool(engine.context, @intFromBool(project)));
    const settings = try sdk.get(engine, data, if (project) "project" else "global");
    defer engine.freeValue(settings);
    const modified = try sdk.get(engine, data, if (project) "modifiedProject" else "modifiedGlobal");
    defer engine.freeValue(modified);
    try sdk.put(engine, job, "snapshot", try accessors.clone(engine, settings));
    try sdk.put(engine, job, "modified", try accessors.clone(engine, modified));
    const queue = try sdk.get(engine, data, "settingsQueue");
    defer engine.freeValue(queue);
    const write = try function(engine, job, .write);
    defer engine.freeValue(write);
    const pending = try sdk.invoke(engine, queue, "then", &.{write});
    defer engine.freeValue(pending);
    const failed = try function(engine, job, .failed);
    defer engine.freeValue(failed);
    try sdk.put(engine, data, "settingsQueue", try sdk.invoke(engine, pending, "catch", &.{failed}));
}
pub fn flush(engine: *engine_mod.Engine, data: c.JSValue) !c.JSValue {
    const queue = try sdk.get(engine, data, "settingsQueue");
    defer engine.freeValue(queue);
    return sdk.promise(engine, queue);
}
pub fn reload(engine: *engine_mod.Engine, data: c.JSValue) !c.JSValue {
    const queue = try sdk.get(engine, data, "settingsQueue");
    defer engine.freeValue(queue);
    const callback_value = try function(engine, data, .reload);
    defer engine.freeValue(callback_value);
    return sdk.invoke(engine, queue, "then", &.{callback_value});
}
pub fn trusted(engine: *engine_mod.Engine, data: c.JSValue) !bool {
    const value = try sdk.get(engine, data, "projectTrusted");
    defer engine.freeValue(value);
    return c.JS_ToBool(engine.context, value) == 1;
}
pub fn assertTrusted(engine: *engine_mod.Engine, data: c.JSValue) !void {
    if (try trusted(engine, data)) return;
    const failure = try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(failure);
    try sdk.put(engine, failure, "message", try sdk.text(engine, "Project is not trusted; refusing to write project settings"));
    const ignored = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, failure)));
    engine.freeValue(ignored);
}
pub fn setTrusted(engine: *engine_mod.Engine, data: c.JSValue, value: c.JSValue) !void {
    const previous = try sdk.get(engine, data, "projectTrusted");
    defer engine.freeValue(previous);
    if (c.JS_IsStrictEqual(engine.context, previous, value)) return;
    try sdk.put(engine, data, "projectTrusted", c.JS_DupValue(engine.context, value));
    try sdk.put(engine, data, "modifiedProject", try sdk.object(engine));
    if (c.JS_ToBool(engine.context, value) == 1) try loadScope(engine, data, "project", false) else {
        try sdk.put(engine, data, "project", try sdk.object(engine));
        try sdk.put(engine, data, "projectLoadError", c.pi_js_undefined());
    }
    try rebuild(engine, data);
}
fn persist(engine: *engine_mod.Engine, job: c.JSValue, current: c.JSValue) !c.JSValue {
    const parsed = try parse(engine, current);
    defer engine.freeValue(parsed);
    const merged = try sdk.object(engine);
    defer engine.freeValue(merged);
    try models.copy(engine, merged, parsed);
    const snapshot = try sdk.get(engine, job, "snapshot");
    defer engine.freeValue(snapshot);
    const modified = try sdk.get(engine, job, "modified");
    defer engine.freeValue(modified);
    var fields: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &fields, &count, modified, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, fields, count);
    for (0..count) |index| {
        const value = try engine.checked(c.JS_GetProperty(engine.context, snapshot, fields[index].atom));
        defer engine.freeValue(value);
        const nested = try engine.checked(c.JS_GetProperty(engine.context, modified, fields[index].atom));
        defer engine.freeValue(nested);
        if (c.JS_IsObject(nested) and c.JS_IsObject(value)) {
            const base = try engine.checked(c.JS_GetProperty(engine.context, parsed, fields[index].atom));
            defer engine.freeValue(base);
            const target = try sdk.object(engine);
            defer engine.freeValue(target);
            try models.copy(engine, target, base);
            var names: [*c]c.JSPropertyEnum = null;
            var length: u32 = 0;
            if (c.JS_GetOwnPropertyNames(engine.context, &names, &length, nested, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
            defer c.JS_FreePropertyEnum(engine.context, names, length);
            for (0..length) |n| {
                const changed = try engine.checked(c.JS_GetProperty(engine.context, value, names[n].atom));
                if (c.JS_DefinePropertyValue(engine.context, target, names[n].atom, changed, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
            }
            if (c.JS_DefinePropertyValue(engine.context, merged, fields[index].atom, c.JS_DupValue(engine.context, target), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        } else if (c.JS_IsUndefined(value)) {
            if (c.JS_DeleteProperty(engine.context, merged, fields[index].atom, 0) < 0) return error.JavaScriptException;
        } else if (c.JS_DefinePropertyValue(engine.context, merged, fields[index].atom, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    return jsonText(engine, merged);
}
fn dispatch(engine: *engine_mod.Engine, capture: c.JSValue, stage: Stage, args: []const c.JSValue) !c.JSValue {
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    if (stage == .file) return fileStorage(engine, capture, args);
    if (stage == .capture) {
        try sdk.put(engine, capture, "current", c.JS_DupValue(engine.context, first));
        return c.pi_js_undefined();
    }
    if (stage == .persist) return persist(engine, capture, first);
    if (stage == .memory) {
        if (args.len < 2) return error.NativeSDKMissingArgument;
        const scope = try engine.toString(first);
        defer engine.gpa.free(scope);
        const field: [*:0]const u8 = if (std.mem.eql(u8, scope, "global")) "storageGlobal" else "storageProject";
        const current = try sdk.get(engine, capture, field);
        defer engine.freeValue(current);
        var values = [_]c.JSValue{current};
        const next = try engine.checked(c.JS_Call(engine.context, args[1], c.pi_js_undefined(), 1, &values));
        defer engine.freeValue(next);
        if (!c.JS_IsUndefined(next)) try sdk.put(engine, capture, field, c.JS_DupValue(engine.context, next));
        return c.pi_js_undefined();
    }
    if (stage == .reload) {
        try loadScope(engine, capture, "global", true);
        try loadScope(engine, capture, "project", true);
        try sdk.put(engine, capture, "modifiedGlobal", try sdk.object(engine));
        try sdk.put(engine, capture, "modifiedProject", try sdk.object(engine));
        try rebuild(engine, capture);
        return c.pi_js_undefined();
    }
    const data = try sdk.get(engine, capture, "data");
    defer engine.freeValue(data);
    const project = try sdk.get(engine, capture, "project");
    defer engine.freeValue(project);
    const is_project = c.JS_ToBool(engine.context, project) == 1;
    if (stage == .failed) {
        try record(engine, data, if (is_project) "project" else "global", first);
        return c.pi_js_undefined();
    }
    if (is_project) try assertTrusted(engine, data);
    const storage = try sdk.get(engine, data, "storage");
    defer engine.freeValue(storage);
    const scope = try sdk.text(engine, if (is_project) "project" else "global");
    defer engine.freeValue(scope);
    const update = try function(engine, capture, .persist);
    defer engine.freeValue(update);
    const ignored = try sdk.invoke(engine, storage, "withLock", &.{ scope, update });
    engine.freeValue(ignored);
    try sdk.put(engine, data, if (is_project) "modifiedProject" else "modifiedGlobal", try sdk.object(engine));
    return c.pi_js_undefined();
}
fn acquire(engine: *engine_mod.Engine, io: std.Io, path: []const u8) !void {
    for (0..10) |attempt| {
        std.Io.Dir.cwd().createDir(io, path, .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
            if (attempt < 9) {
                try io.sleep(.fromMilliseconds(20), .awake);
                continue;
            }
            const failure = try engine.checked(c.JS_NewError(engine.context));
            defer engine.freeValue(failure);
            try sdk.put(engine, failure, "message", try sdk.text(engine, "Lock file is already being held"));
            try sdk.put(engine, failure, "code", try sdk.text(engine, "ELOCKED"));
            const ignored = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, failure)));
            engine.freeValue(ignored);
            return;
        };
        return;
    }
}
fn fileStorage(engine: *engine_mod.Engine, data: c.JSValue, args: []const c.JSValue) !c.JSValue {
    if (args.len < 2) return error.NativeSDKMissingArgument;
    const io = engine.native_io orelse return error.NativeSDKRequiresIO;
    const scope = try engine.toString(args[0]);
    defer engine.gpa.free(scope);
    const path_value = try sdk.get(engine, data, if (std.mem.eql(u8, scope, "global")) "settingsPath" else "projectPath");
    defer engine.freeValue(path_value);
    const path = try engine.toString(path_value);
    defer engine.gpa.free(path);
    const lock = try std.fmt.allocPrint(engine.gpa, "{s}.lock", .{path});
    defer engine.gpa.free(lock);
    const exists = existing: {
        std.Io.Dir.cwd().access(io, path, .{}) catch |err| {
            if (err == error.FileNotFound or err == error.AccessDenied) break :existing false;
            return err;
        };
        break :existing true;
    };
    var held = false;
    defer if (held) std.Io.Dir.cwd().deleteDir(io, lock) catch {};
    if (exists) {
        try acquire(engine, io, lock);
        held = true;
    }
    const raw = if (exists) try std.Io.Dir.cwd().readFileAlloc(io, path, engine.gpa, .limited(4 * 1024 * 1024)) else null;
    defer if (raw) |text| engine.gpa.free(text);
    const current = if (raw) |text| try sdk.text(engine, text) else c.pi_js_undefined();
    defer engine.freeValue(current);
    var input = [_]c.JSValue{current};
    const next = try engine.checked(c.JS_Call(engine.context, args[1], c.pi_js_undefined(), 1, &input));
    defer engine.freeValue(next);
    if (!c.JS_IsUndefined(next)) {
        if (std.fs.path.dirname(path)) |directory| try std.Io.Dir.cwd().createDirPath(io, directory);
        if (!held) {
            try acquire(engine, io, lock);
            held = true;
        }
        const text = try engine.toString(next);
        defer engine.gpa.free(text);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = text });
    }
    return c.pi_js_undefined();
}
