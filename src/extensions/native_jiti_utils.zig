//! Finite actual jiti2.7 utils.ts bodies. MIT, Pooya Parsa.
//! Actual native imports are required; no filesystem, colors or crypto stubs.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const functions = @import("native_node_module_callable.zig");
const fatal = @import("native_async_body.zig");
pub const Inputs = struct { filesystem: c.JSValue, paths: c.JSValue, node_crypto: c.JSValue, colors: c.JSValue };
const Method = enum(c_int) { isDir, isWritable, hash, readNearestPackageJSON, debug };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn nil(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
fn put(engine: *v.em.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
fn capture(s: *Scope, owner: c.JSValue, namespace: c.JSValue, comptime names: anytype) !void {
    inline for (names) |name| {
        const value = try s.get(namespace, name);
        if (!c.JS_IsFunction(s.engine.context, value)) return error.RequiredActualJitiUtilityImport;
        try put(s.engine, owner, name, value);
    }
}
fn imported(s: *Scope, owner: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return s.call(try s.get(owner, name), c.pi_js_undefined(), args);
}
fn ignoreOrdinary(engine: *v.em.Engine, err: anyerror, generation: u64) !void {
    if (err != error.JavaScriptException) return err;
    const reason = engine.captured_exception orelse return error.MissingJitiUtilityReason;
    if (c.JS_IsUncatchableError(reason)) return err;
    try fatal.rethrowRecognizedAllocation(engine, reason, generation);
    engine.captured_exception = null;
    engine.freeValue(reason);
}
fn discardCall(engine: *v.em.Engine, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !void {
    const value = try v.js.call(engine, function, receiver, args); engine.freeValue(value);
}
pub fn create(engine: *v.em.Engine, actual: Inputs) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const owner = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try capture(&s, owner, actual.filesystem, .{ "lstatSync", "accessSync", "readFileSync" });
    try capture(&s, owner, actual.paths, .{"join"});
    try capture(&s, owner, actual.colors, .{ "gray", "green", "blue", "yellow", "cyan", "red" });
    try put(engine, owner, "constants", try s.get(actual.filesystem, "constants"));
    try put(engine, owner, "crypto", actual.node_crypto);
    try put(engine, owner, "fipsMode", c.pi_js_undefined());
    const map = try s.object();
    inline for (.{ .{ "true", "green" }, .{ "false", "yellow" }, .{ "[rebuild]", "yellow" }, .{ "[esm]", "blue" }, .{ "[cjs]", "green" }, .{ "[import]", "blue" }, .{ "[require]", "green" }, .{ "[native]", "cyan" }, .{ "[transpile]", "yellow" }, .{ "[fallback]", "red" }, .{ "[unknown]", "red" }, .{ "[hit]", "green" }, .{ "[miss]", "yellow" }, .{ "[json]", "green" }, .{ "[data]", "green" } }) |entry| {
        const text = try s.text(entry[0]);
        // Literal property creation bypasses inherited setters. The real color
        // calls happen at module initialization even when ctx.opts.debug=false.
        const value = try v.js.call(engine, try s.get(owner, entry[1]), c.pi_js_undefined(), &.{text});
        defer engine.freeValue(value);
        try put(engine, map, entry[0], value);
    }
    try put(engine, owner, "debugMap", map);
    const namespace = try s.object();
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const function = try s.own(try functions.create(engine, field.name, 1, true, invoke, &.{ owner, c.JS_NewInt32(engine.context, field.value) }));
        try put(engine, namespace, field.name, function);
    }
    return c.JS_DupValue(engine.context, namespace);
}
fn invoke(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    var operation: i32 = 0;
    if (c.JS_ToInt32(engine.context, &operation, roots[1]) < 0) return v.js.capture(engine);
    return switch (@as(Method, @enumFromInt(operation))) {
        .isDir => isDir(&s, roots[0], arg(args, 0)),
        .isWritable => isWritable(&s, roots[0], arg(args, 0)),
        .hash => hash(&s, roots[0], arg(args, 0), if (c.JS_IsUndefined(arg(args, 1))) c.JS_NewInt32(engine.context, 8) else args[1]),
        .readNearestPackageJSON => nearest(&s, roots[0], arg(args, 0)),
        .debug => debug(&s, roots[0], arg(args, 0), if (args.len > 1) args[1..] else &.{}),
    };
}
fn directoryAttempt(s: *Scope, owner: c.JSValue, filename: c.JSValue) !c.JSValue {
    const stat = try imported(s, owner, "lstatSync", &.{filename});
    return v.js.invoke(s.engine, stat, "isDirectory", &.{});
}
fn isDir(s: *Scope, owner: c.JSValue, filename: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(filename)) return c.pi_js_bool(s.engine.context, 0);
    if (s.truthy(try s.invoke(filename, "startsWith", &.{try s.text("file://")}))) return c.pi_js_bool(s.engine.context, 0);
    const generation = s.engine.native_allocation_generation;
    return directoryAttempt(s, owner, filename) catch |err| {
        try ignoreOrdinary(s.engine, err, generation);
        return c.pi_js_bool(s.engine.context, 0);
    };
}
fn writableAttempt(s: *Scope, owner: c.JSValue, filename: c.JSValue) !void {
    const function = try s.get(owner, "accessSync");
    const mode = try s.get(try s.get(owner, "constants"), "W_OK");
    try discardCall(s.engine, function, c.pi_js_undefined(), &.{ filename, mode });
}
fn isWritable(s: *Scope, owner: c.JSValue, filename: c.JSValue) !c.JSValue {
    const generation = s.engine.native_allocation_generation;
    writableAttempt(s, owner, filename) catch |err| {
        try ignoreOrdinary(s.engine, err, generation);
        return c.pi_js_bool(s.engine.context, 0);
    };
    return c.pi_js_bool(s.engine.context, 1);
}
fn fipsAttempt(engine: *v.em.Engine, owner: c.JSValue) !bool {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const crypto = try s.get(owner, "crypto");
    const function = try s.get(crypto, "getFips");
    if (nil(function)) return false;
    const value = try v.js.call(engine, function, crypto, &.{}); defer engine.freeValue(value);
    return s.truthy(value);
}
fn fips(s: *Scope, owner: c.JSValue) !bool {
    const saved = try s.get(owner, "fipsMode");
    if (!c.JS_IsUndefined(saved)) return s.truthy(saved);
    const generation = s.engine.native_allocation_generation;
    const value = fipsAttempt(s.engine, owner) catch |err| result: {
        try ignoreOrdinary(s.engine, err, generation);
        break :result false;
    };
    try put(s.engine, owner, "fipsMode", c.pi_js_bool(s.engine.context, @intFromBool(value)));
    return value;
}
fn hash(s: *Scope, owner: c.JSValue, content: c.JSValue, length: c.JSValue) !c.JSValue {
    // Source decides FIPS before reading the chosen createHash callee.
    const algorithm = try s.text(if (try fips(s, owner)) "sha256" else "md5");
    const crypto = try s.get(owner, "crypto");
    const state = try v.js.invoke(s.engine, crypto, "createHash", &.{algorithm}); defer s.engine.freeValue(state);
    const digested = result: {
        const updated = try v.js.invoke(s.engine, state, "update", &.{content}); defer s.engine.freeValue(updated);
        break :result try v.js.invoke(s.engine, updated, "digest", &.{try s.text("hex")});
    };
    defer s.engine.freeValue(digested);
    return v.js.invoke(s.engine, digested, "slice", &.{ c.JS_NewInt32(s.engine.context, 0), length });
}
fn readPackage(s: *Scope, owner: c.JSValue, path: c.JSValue) !c.JSValue {
    const function = try s.get(owner, "readFileSync");
    const filename = try imported(s, owner, "join", &.{ path, try s.text("package.json") });
    return v.js.call(s.engine, function, c.pi_js_undefined(), &.{ filename, try s.text("utf8") });
}
fn parsePackage(engine: *v.em.Engine, pkg: c.JSValue) !c.JSValue {
    const json = try v.js.global(engine, "JSON"); defer engine.freeValue(json);
    return v.js.invoke(engine, json, "parse", &.{pkg});
}
fn nearest(s: *Scope, owner: c.JSValue, initial: c.JSValue) !c.JSValue {
    var path = c.JS_DupValue(s.engine.context, initial); defer s.engine.freeValue(path);
    const dot = try s.text("."); const slash = try s.text("/");
    var steps: usize = 0;
    while (s.truthy(path) and !s.equal(path, dot) and !s.equal(path, slash)) {
        steps +|= 1;
        try @import("native_jiti_budget.zig").check(s.engine, steps);
        const parent = try v.js.call(s.engine, try s.get(owner, "join"), c.pi_js_undefined(), &.{ path, try s.text("..") });
        s.engine.freeValue(path); path = parent;
        var iteration: Scope = .{ .engine = s.engine }; defer iteration.deinit();
        const generation = s.engine.native_allocation_generation;
        const pkg = readPackage(&iteration, owner, path) catch |err| {
            try ignoreOrdinary(s.engine, err, generation);
            continue;
        };
        defer s.engine.freeValue(pkg);
        const parse_generation = s.engine.native_allocation_generation;
        const parsed = parsePackage(s.engine, pkg) catch |err| {
            try ignoreOrdinary(s.engine, err, parse_generation);
            break;
        };
        return parsed;
    }
    return c.pi_js_undefined();
}
fn debugArgument(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const value = arg(args, 0);
    if (try v.js.hasKey(engine, roots[0], value)) return v.js.getKey(engine, roots[0], value);
    if (!c.JS_IsString(value)) {
        const json = try v.js.global(engine, "JSON"); defer engine.freeValue(json);
        return v.js.invoke(engine, json, "stringify", &.{value});
    }
    const dot = try tryText(engine, "."); defer engine.freeValue(dot);
    return v.js.invoke(engine, value, "replace", &.{ roots[1], dot });
}
fn tryText(engine: *v.em.Engine, text: [*:0]const u8) !c.JSValue { return engine.checked(c.JS_NewString(engine.context, text)); }
fn debug(s: *Scope, owner: c.JSValue, context: c.JSValue, args: []const c.JSValue) !c.JSValue {
    if (!s.truthy(try s.get(try s.get(context, "opts"), "debug"))) return c.pi_js_undefined();
    const cwd = try s.invoke(try s.global("process"), "cwd", &.{});
    // Source resolves console.log before evaluating gray/map/join arguments.
    const console = try s.global("console"); const log = try s.get(console, "log");
    const arguments = try s.array();
    for (args, 0..) |value, index| if (c.JS_DefinePropertyValueUint32(s.engine.context, arguments, @intCast(index), c.JS_DupValue(s.engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) { return v.js.capture(s.engine); };
    const text = try s.array();
    if (c.JS_DefinePropertyValueUint32(s.engine.context, text, 0, c.JS_DupValue(s.engine.context, try s.text("[jiti]")), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
    const map_function = try s.get(arguments, "map");
    const mapper = try s.own(try functions.create(s.engine, "", 1, false, debugArgument, &.{ try s.get(owner, "debugMap"), cwd }));
    const mapped = try s.call(map_function, arguments, &.{mapper});
    var iterator = try v.js.Iterator.init(s.engine, mapped, try s.own(try s.engine.checked(c.JS_GetIteratorSymbol(s.engine.context)))); defer iterator.deinit();
    var index: u32 = 1;
    while (try @import("native_jiti_budget.zig").next(&iterator)) |value| {
        defer s.engine.freeValue(value);
        if (c.JS_DefinePropertyValueUint32(s.engine.context, text, index, c.JS_DupValue(s.engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
        index += 1;
    }
    const joined = try s.invoke(text, "join", &.{try s.text(" ")});
    const gray = try s.get(owner, "gray");
    const colored = try v.js.call(s.engine, gray, c.pi_js_undefined(), &.{joined}); defer s.engine.freeValue(colored);
    try discardCall(s.engine, log, console, &.{colored});
    return c.pi_js_undefined();
}
