//! Configuration templates with native owner-thread Promise continuations.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const resolver = @import("../coding_agent/config_value.zig");
fn startChar(byte: u8) bool {
    return std.ascii.isAlphabetic(byte) or byte == '_';
}
fn nextChar(byte: u8) bool {
    return startChar(byte) or std.ascii.isDigit(byte);
}
pub fn names(gpa: std.mem.Allocator, raw: []const u8) ![][]const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    errdefer result.deinit(gpa);
    if (resolver.isCommandConfigValue(raw)) return result.toOwnedSlice(gpa);
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] != '$' or i + 1 >= raw.len) {
            i += 1;
            continue;
        }
        if (raw[i + 1] == '$' or raw[i + 1] == '!') {
            i += 2;
            continue;
        }
        var name: ?[]const u8 = null;
        if (raw[i + 1] == '{') {
            const end = std.mem.indexOfScalarPos(u8, raw, i + 2, '}') orelse {
                i += 1;
                continue;
            };
            const candidate = raw[i + 2 .. end];
            var valid = candidate.len > 0 and startChar(candidate[0]);
            for (candidate) |byte| valid = valid and nextChar(byte);
            if (valid) name = candidate;
            i = end + 1;
        } else if (startChar(raw[i + 1])) {
            var end = i + 2;
            while (end < raw.len and nextChar(raw[end])) end += 1;
            name = raw[i + 1 .. end];
            i = end;
        } else i += 1;
        if (name) |candidate| {
            var duplicate = false;
            for (result.items) |previous| if (std.mem.eql(u8, candidate, previous)) {
                duplicate = true;
                break;
            };
            if (!duplicate) try result.append(gpa, candidate);
        }
    }
    return result.toOwnedSlice(gpa);
}
pub fn processEnv(engine: *engine_mod.Engine) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const process = try sdk.get(engine, global, "process");
    defer engine.freeValue(process);
    return sdk.get(engine, process, "env");
}
fn environment(engine: *engine_mod.Engine, raw: []const u8, explicit: c.JSValue) !std.process.Environ.Map {
    var result: std.process.Environ.Map = .init(engine.gpa);
    errdefer result.deinit();
    const entries = try names(engine.gpa, raw);
    defer engine.gpa.free(entries);
    const ambient = try processEnv(engine);
    defer engine.freeValue(ambient);
    for (entries) |name| {
        const key = try sdk.text(engine, name);
        defer engine.freeValue(key);
        const provided = if (c.JS_IsObject(explicit)) try @import("native_sdk_models.zig").property(engine, explicit, key) else c.pi_js_undefined();
        defer engine.freeValue(provided);
        const fallback = if (c.JS_IsObject(ambient)) try @import("native_sdk_models.zig").property(engine, ambient, key) else c.pi_js_undefined();
        defer engine.freeValue(fallback);
        const value = if (c.JS_ToBool(engine.context, provided) == 1) provided else fallback;
        if (c.JS_ToBool(engine.context, value) != 1) continue;
        const text = try engine.toString(value);
        defer engine.gpa.free(text);
        try result.put(name, text);
    }
    return result;
}
pub fn configured(engine: *engine_mod.Engine, raw: []const u8) !bool {
    if (resolver.isCommandConfigValue(raw)) return true;
    var env = try environment(engine, raw, c.pi_js_undefined());
    defer env.deinit();
    const value = try resolver.resolveTemplate(engine.gpa, &env, raw);
    defer if (value) |owned| engine.gpa.free(owned);
    return value != null;
}
pub fn start(engine: *engine_mod.Engine, raw: c.JSValue, ctx: c.JSValue, explicit: c.JSValue, check: bool, description: c.JSValue) !c.JSValue {
    const job = try sdk.object(engine);
    defer engine.freeValue(job);
    try sdk.put(engine, job, "raw", c.JS_DupValue(engine.context, raw));
    try sdk.put(engine, job, "ctx", c.JS_DupValue(engine.context, ctx));
    try sdk.put(engine, job, "description", c.JS_DupValue(engine.context, description));
    const env = try sdk.object(engine);
    defer engine.freeValue(env);
    try @import("native_sdk_models.zig").copy(engine, env, explicit);
    try sdk.put(engine, job, "env", c.JS_DupValue(engine.context, env));
    try sdk.put(engine, job, "check", c.pi_js_bool(engine.context, @intFromBool(check)));
    try sdk.put(engine, job, "index", c.JS_NewInt32(engine.context, 0));
    const text = try engine.toString(raw);
    defer engine.gpa.free(text);
    const references = try names(engine.gpa, text);
    defer engine.gpa.free(references);
    const refs = try sdk.array(engine);
    defer engine.freeValue(refs);
    for (references) |name| try sdk.append(engine, refs, try sdk.text(engine, name));
    try sdk.put(engine, job, "names", c.JS_DupValue(engine.context, refs));
    return step(engine, job);
}
fn completed(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return received(engine, data[0], if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn received(engine: *engine_mod.Engine, job: c.JSValue, value: c.JSValue) !c.JSValue {
    const check = try sdk.get(engine, job, "check");
    defer engine.freeValue(check);
    if (c.JS_ToBool(engine.context, check) == 1 and c.JS_IsUndefined(value)) return c.pi_js_bool(engine.context, 0);
    const env = try sdk.get(engine, job, "env");
    defer engine.freeValue(env);
    const key = try sdk.get(engine, job, "current");
    defer engine.freeValue(key);
    const atom = c.JS_ValueToAtom(engine.context, key);
    if (atom == c.JS_ATOM_NULL) return error.JavaScriptException;
    defer c.JS_FreeAtom(engine.context, atom);
    if (!c.JS_IsUndefined(value) and c.JS_DefinePropertyValue(engine.context, env, atom, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    return step(engine, job);
}
fn step(engine: *engine_mod.Engine, job: c.JSValue) !c.JSValue {
    const references = try sdk.get(engine, job, "names");
    defer engine.freeValue(references);
    const position = try sdk.get(engine, job, "index");
    defer engine.freeValue(position);
    var index: u32 = 0;
    if (c.JS_ToUint32(engine.context, &index, position) < 0) return error.JavaScriptException;
    const env = try sdk.get(engine, job, "env");
    defer engine.freeValue(env);
    while (index < try sdk.length(engine, references)) {
        const key = try engine.checked(c.JS_GetPropertyUint32(engine.context, references, index));
        defer engine.freeValue(key);
        index += 1;
        try sdk.put(engine, job, "index", c.JS_NewUint32(engine.context, index));
        const existing = try @import("native_sdk_models.zig").property(engine, env, key);
        defer engine.freeValue(existing);
        if (!c.JS_IsUndefined(existing)) continue;
        const ctx = try sdk.get(engine, job, "ctx");
        defer engine.freeValue(ctx);
        try sdk.put(engine, job, "current", c.JS_DupValue(engine.context, key));
        const pending = try sdk.invoke(engine, ctx, "env", &.{key});
        defer engine.freeValue(pending);
        const adopted = try sdk.promise(engine, pending);
        defer engine.freeValue(adopted);
        var captured = [_]c.JSValue{job};
        const done = try engine.checked(c.JS_NewCFunctionData2(engine.context, completed, "configuredEnvironment", 1, 0, 1, &captured));
        defer engine.freeValue(done);
        return sdk.invoke(engine, adopted, "then", &.{done});
    }
    const check = try sdk.get(engine, job, "check");
    defer engine.freeValue(check);
    if (c.JS_ToBool(engine.context, check) == 1) return sdk.promise(engine, c.pi_js_bool(engine.context, 1));
    const raw_value = try sdk.get(engine, job, "raw");
    defer engine.freeValue(raw_value);
    const raw = try engine.toString(raw_value);
    defer engine.gpa.free(raw);
    var values = try environment(engine, raw, env);
    defer values.deinit();
    var native = resolver.Resolver.init(engine.gpa, engine.native_io orelse return error.NativeSDKRequiresIO, &values);
    defer native.deinit();
    const resolved = try native.resolveUncached(raw);
    defer if (resolved) |owned| engine.gpa.free(owned);
    if (resolved) |text| {
        const result = try sdk.text(engine, text);
        defer engine.freeValue(result);
        return sdk.promise(engine, result);
    }
    const description_value = try sdk.get(engine, job, "description");
    defer engine.freeValue(description_value);
    const description = try engine.toString(description_value);
    defer engine.gpa.free(description);
    var missing: std.Io.Writer.Allocating = .init(engine.gpa);
    defer missing.deinit();
    const entries = try names(engine.gpa, raw);
    defer engine.gpa.free(entries);
    var count: usize = 0;
    for (entries) |name| if (!values.contains(name)) {
        if (count != 0) try missing.writer.writeAll(", ");
        try missing.writer.writeAll(name);
        count += 1;
    };
    const message = if (resolver.isCommandConfigValue(raw)) try std.fmt.allocPrint(engine.gpa, "Failed to resolve {s} from shell command: {s}", .{ description, raw[1..] }) else try std.fmt.allocPrint(engine.gpa, "Failed to resolve {s} from environment variable{s}: {s}", .{ description, if (count == 1) "" else "s", missing.written() });
    defer engine.gpa.free(message);
    const exception = try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(exception);
    try sdk.put(engine, exception, "message", try sdk.text(engine, message));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const promise = try sdk.get(engine, global, "Promise");
    defer engine.freeValue(promise);
    return sdk.invoke(engine, promise, "reject", &.{exception});
}
