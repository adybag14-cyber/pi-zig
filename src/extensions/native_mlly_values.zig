//! Private values for the actual mlly1.8.2/import-meta-resolve4.2 resolver.
//! Imports are real captured Node bindings. No host loader/normalizer fallback.
const std = @import("std");
pub const v = @import("native_ai_provider_values.zig");
pub const c = v.c;
pub const Scope = v.Scope;
pub const functions = @import("native_mlly_function.zig");
const allocation = @import("native_async_body.zig");
pub const Imports = struct {
    fs: c.JSValue, path: c.JSValue, process: c.JSValue, builtin_modules: c.JSValue,
    file_url_to_path: c.JSValue, path_to_file_url: c.JSValue,
    stat_sync: c.JSValue, realpath_sync: c.JSValue,
    pathe_is_absolute: c.JSValue, pathe_normalize: c.JSValue,
};
pub const Context = struct {
    engine: *v.em.Engine,
    owner: c.JSValue,
    pub fn get(self: Context, s: *Scope, name: [*:0]const u8) !c.JSValue { return s.get(self.owner, name); }
    pub fn file(self: Context, s: *Scope, value: c.JSValue) !c.JSValue { return s.call(try self.get(s, "fileURLToPath"), c.pi_js_undefined(), &.{value}); }
    pub fn fileURL(self: Context, s: *Scope, value: c.JSValue) !c.JSValue { return s.call(try self.get(s, "pathToFileURL"), c.pi_js_undefined(), &.{value}); }
    pub fn regexTest(self: Context, s: *Scope, name: [*:0]const u8, value: c.JSValue) !bool { return s.truthy(try s.invoke(try self.get(s, name), "test", &.{value})); }
    pub fn regexExec(self: Context, s: *Scope, name: [*:0]const u8, value: c.JSValue) !bool { return !c.JS_IsNull(try s.invoke(try self.get(s, name), "exec", &.{value})); }
    pub fn constructURL(self: Context, s: *Scope, constructor: c.JSValue, args: []const c.JSValue) !c.JSValue { return s.own(try self.engine.checked(c.JS_CallConstructor(self.engine.context, constructor, @intCast(args.len), @constCast(args.ptr)))); }
    pub fn url(self: Context, s: *Scope, target: c.JSValue, base: ?c.JSValue) !c.JSValue {
        const constructor = try s.global("URL");
        return self.constructURL(s, constructor, if (base) |value| &.{ target, value } else &.{target});
    }
    pub fn own(self: Context, s: *Scope, value: c.JSValue, name: c.JSValue) !bool { return s.truthy(try s.invoke(try self.get(s, "hasOwn"), "call", &.{ value, name })); }
};
pub fn define(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try v.js.define(s.engine, target, name, c.JS_DupValue(s.engine.context, value)); }
pub fn at(s: *Scope, target: c.JSValue, name: c.JSValue) !c.JSValue { return s.own(try v.js.getKey(s.engine, target, name)); }
pub fn integer(s: *Scope, value: i64) c.JSValue { return c.JS_NewInt64(s.engine.context, value); }
pub fn binary(s: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue { return s.own(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, operation, left, right))); }
pub fn equal(s: *Scope, value: c.JSValue, text: []const u8) !bool { return s.equal(value, try s.text(text)); }
pub fn object(value: c.JSValue, engine: *v.em.Engine) bool { return c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value); }
pub fn regex(s: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    const args = [_]c.JSValue{ try s.text(pattern), try s.text(flags) };
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, @constCast(&args))));
}
pub fn exact(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| allocation.rethrowRecognizedAllocation(engine, reason, functions.trustedGeneration(engine, generation)) catch |fatal| return fatal;
    return err;
}
pub fn trusted(engine: *v.em.Engine, err: anyerror, generation: u64) !void {
    if (err == error.OutOfMemory) return err;
    if (err != error.JavaScriptException) return err;
    if (engine.captured_exception) |reason| {
        try allocation.rethrowRecognizedAllocation(engine, reason, functions.trustedGeneration(engine, generation));
        if (c.JS_IsUncatchableError(reason)) return err;
    }
}
/// Transfer the caught ordinary reason out of the engine before any Source
/// catch getter/callback can overwrite it. Native failures never enter here.
pub fn caught(s: *Scope, err: anyerror, generation: u64) !c.JSValue {
    try trusted(s.engine, err, generation);
    const reason = s.engine.captured_exception orelse return err;
    s.engine.captured_exception = null;
    return s.own(reason);
}
pub fn throwReason(engine: *v.em.Engine, reason: c.JSValue) anyerror {
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))) catch |err| return err; unreachable;
}
pub fn budget(engine: *v.em.Engine, steps: *usize) !void {
    steps.* +|= 1;
    if (engine.cancelled.load(.acquire) or (steps.* % 256 == 0 and blk: { engine.interrupts +|= 1; break :blk engine.interrupts > engine.options.interrupt_budget; })) {
        _ = c.JS_ThrowInternalError(engine.context, "interrupted"); const reason = c.JS_GetException(engine.context);
        c.JS_SetUncatchableError(engine.context, reason); _ = try engine.checked(c.JS_Throw(engine.context, reason)); unreachable;
    }
}
pub fn advance(engine: *v.em.Engine, iterator: *v.js.Iterator) !?c.JSValue {
    try budget(engine, &iterator.native_steps); errdefer iterator.closed = true;
    const step = try v.js.call(engine, iterator.next_function, iterator.iterator, &.{}); defer engine.freeValue(step);
    if (!c.JS_IsObject(step)) return v.js.typeError(engine, "Iterator result is not an object");
    const done = try v.js.get(engine, step, "done"); defer engine.freeValue(done);
    if (c.JS_ToBool(engine.context, done) != 0) { iterator.closed = true; return null; }
    return v.js.get(engine, step, "value");
}
fn restore(engine: *v.em.Engine, value: ?c.JSValue) void {
    const previous = engine.captured_exception; engine.captured_exception = null; if (previous) |reason| engine.freeValue(reason);
    engine.captured_exception = if (value) |reason| c.JS_DupValue(engine.context, reason) else null;
}
pub fn closeAbrupt(engine: *v.em.Engine, iterator: *v.js.Iterator, failure: anyerror, generation: u64) anyerror {
    const primary_error = exact(engine, failure, generation);
    const primary = if (primary_error == error.JavaScriptException) if (engine.captured_exception) |reason| c.JS_DupValue(engine.context, reason) else null else null;
    defer if (primary) |reason| engine.freeValue(reason);
    const fatal = primary_error == error.OutOfMemory or if (primary) |reason| c.JS_IsUncatchableError(reason) else false;
    closeThrow(engine, iterator) catch |err| {
        // closeThrow has already classified only the getter/call that failed.
        // The loop-start generation must not promote an older tagged reason.
        const cleanup_error = err;
        if (!fatal and (cleanup_error == error.OutOfMemory or (cleanup_error == error.JavaScriptException and if (engine.captured_exception) |reason| c.JS_IsUncatchableError(reason) else false))) return cleanup_error;
    };
    restore(engine, primary); return primary_error;
}
fn closeThrow(engine: *v.em.Engine, iterator: *v.js.Iterator) !void {
    if (iterator.closed) return; iterator.closed = true;
    const getter_generation = engine.native_allocation_generation;
    const method = v.js.get(engine, iterator.iterator, "return") catch |err| return exact(engine, err, getter_generation);
    defer engine.freeValue(method);
    if (v.nullish(method)) return;
    const call_generation = engine.native_allocation_generation;
    const returned = v.js.call(engine, method, iterator.iterator, &.{}) catch |err| return exact(engine, err, call_generation);
    engine.freeValue(returned);
}
fn normalCloseFailure(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror {
    const classified = exact(engine, err, generation);
    if (classified == error.JavaScriptException) if (engine.captured_exception) |reason| {
        if (!c.JS_IsUncatchableError(reason)) functions.ordinaryBoundary(engine);
    };
    return classified;
}
/// Normal/break completion validates the actual return result. Each abrupt
/// getter/call is classified at its own boundary before enclosing catches see it.
pub fn closeNormal(engine: *v.em.Engine, iterator: *v.js.Iterator) !void {
    if (iterator.closed) return; iterator.closed = true;
    const getter_generation = engine.native_allocation_generation;
    const method = v.js.get(engine, iterator.iterator, "return") catch |err| return normalCloseFailure(engine, err, getter_generation);
    defer engine.freeValue(method);
    if (v.nullish(method)) return;
    const call_generation = engine.native_allocation_generation;
    const returned = v.js.call(engine, method, iterator.iterator, &.{}) catch |err| return normalCloseFailure(engine, err, call_generation);
    defer engine.freeValue(returned);
    if (!c.JS_IsObject(returned)) return v.js.typeError(engine, "Iterator return result is not an object");
}
pub fn array(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| if (c.JS_DefinePropertyValueUint32(s.engine.context, result, @intCast(index), c.JS_DupValue(s.engine.context, value), c.JS_PROP_C_W_E) < 0) return v.js.capture(s.engine);
    return result;
}
pub fn collect(s: *Scope, iterable: c.JSValue) !c.JSValue {
    var iterator = try v.iterator(s, iterable); defer iterator.deinit(); const generation = s.engine.native_allocation_generation;
    return collectLoop(s, &iterator) catch |err| return closeAbrupt(s.engine, &iterator, err, generation);
}
fn collectLoop(s: *Scope, iterator: *v.js.Iterator) !c.JSValue {
    const result = try s.array(); var index: u32 = 0;
    while (try advance(s.engine, iterator)) |value| {
        if (c.JS_DefinePropertyValueUint32(s.engine.context, result, index, value, c.JS_PROP_C_W_E) < 0) return v.js.capture(s.engine);
        index += 1;
    }
    return result;
}
pub fn initialize(engine: *v.em.Engine, imports: Imports) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const owner = try s.object();
    inline for (std.meta.fields(Imports)) |field| try define(&s, owner, field.name.ptr, @field(imports, field.name));
    // Explicit aliases preserve private Source names without changing imports.
    try define(&s, owner, "fileURLToPath", imports.file_url_to_path); try define(&s, owner, "pathToFileURL", imports.path_to_file_url);
    try define(&s, owner, "statSync", imports.stat_sync); try define(&s, owner, "realpathSync", imports.realpath_sync);
    try define(&s, owner, "builtinModules", imports.builtin_modules); try define(&s, owner, "patheIsAbsolute", imports.pathe_is_absolute); try define(&s, owner, "patheNormalize", imports.pathe_normalize);
    try define(&s, owner, "builtinSet", try s.own(try v.js.builtin(engine, "Set", &.{imports.builtin_modules})));
    try define(&s, owner, "defaultConditions", try s.own(try v.js.builtin(engine, "Set", &.{try array(&s, &.{ try s.text("node"), try s.text("import") })})));
    try define(&s, owner, "defaultExtensions", try array(&s, &.{ try s.text(".mjs"), try s.text(".cjs"), try s.text(".js"), try s.text(".json") }));
    try define(&s, owner, "notFound", try s.own(try v.js.builtin(engine, "Set", &.{try array(&s, &.{ try s.text("ERR_MODULE_NOT_FOUND"), try s.text("ERR_UNSUPPORTED_DIR_IMPORT"), try s.text("MODULE_NOT_FOUND"), try s.text("ERR_PACKAGE_PATH_NOT_EXPORTED") })})));
    try define(&s, owner, "packageCache", try s.own(try v.js.builtin(engine, "Map", &.{}))); try define(&s, owner, "emittedWarnings", try s.own(try v.js.builtin(engine, "Set", &.{})));
    try define(&s, owner, "hasOwn", try s.get(try s.object(), "hasOwnProperty"));
    try define(&s, owner, "baseError", try s.global("Error")); try define(&s, owner, "baseTypeError", try s.global("TypeError"));
    const regexp_prototype = try s.get(try s.global("RegExp"), "prototype");
    const replace_symbol = try s.get(try s.global("Symbol"), "replace");
    try define(&s, owner, "regexpReplace", try at(&s, regexp_prototype, replace_symbol));
    try @import("native_mlly_format.zig").initialize(&s,owner);
    try define(&s, owner, "invalidSegment", try regex(&s, "(^|\\\\|/)((\\.|%2e)(\\.|%2e)?|(n|%6e|%4e)(o|%6f|%4f)(d|%64|%44)(e|%65|%45)(_|%5f)(m|%6d|%4d)(o|%6f|%4f)(d|%64|%44)(u|%75|%55)(l|%6c|%4c)(e|%65|%45)(s|%73|%53))?(\\\\|/|$)", "i"));
    try define(&s, owner, "deprecatedInvalidSegment", try regex(&s, "(^|\\\\|/)((\\.|%2e)(\\.|%2e)?|(n|%6e|%4e)(o|%6f|%4f)(d|%64|%44)(e|%65|%45)(_|%5f)(m|%6d|%4d)(o|%6f|%4f)(d|%64|%44)(u|%75|%55)(l|%6c|%4c)(e|%65|%45)(s|%73|%53))(\\\\|/|$)", "i"));
    try define(&s, owner, "invalidPackageName", try regex(&s, "^\\.|%|\\\\", ""));
    try define(&s, owner, "pattern", try regex(&s, "\\*", "g"));
    try define(&s, owner, "encodedSeparator", try regex(&s, "%2f|%5c", "i"));
    try define(&s, owner, "doubleSlash", try regex(&s, "[/\\\\]{2}", ""));
    return c.JS_DupValue(engine.context, owner);
}
