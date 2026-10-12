//! Pinned Node24 own Error.stack descriptors and lazy formatting. Uninstalled
//! private candidate; C only provides creation timing and actual frame capture.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const Frame = @import("native_tui_alt_frame.zig").Frame;
const Owner = struct { engine: *js.Engine, bindings: c.JSValue, data_class: c.JSClassID, formatting: bool = false };
const StackData = struct { engine: *js.Engine, captured: bool = false, frames: ?c.JSValue = null, formatted: ?c.JSValue = null };
fn owner(value: c.JSValue) *Owner {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn data(value: c.JSValue, class: c.JSClassID) *StackData {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, class).?));
}
fn finalizeOwner(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.bindings);
    state.engine.gpa.destroy(state);
}
fn markOwner(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.bindings, marker);
}
fn finalizeData(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *StackData = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    if (state.frames) |frames| c.JS_FreeValueRT(runtime, frames);
    if (state.formatted) |formatted| c.JS_FreeValueRT(runtime, formatted);
    state.engine.gpa.destroy(state);
}
fn markData(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *StackData = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    if (state.frames) |frames| c.JS_MarkValue(runtime, frames, marker);
    if (state.formatted) |formatted| c.JS_MarkValue(runtime, formatted, marker);
}
fn failure(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    return c.JS_ThrowInternalError(engine.context, "Native Error stack: %s", @as([*:0]const u8, @errorName(err)));
}
fn mapGet(f: *Frame, key: c.JSValue) !c.JSValue {
    return f.call(try f.get(f.bindings, "mapGet"), try f.get(f.bindings, "map"), &.{key});
}
fn dataProperty(f: *Frame, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const atom = c.JS_NewAtom(f.engine.context, name);
    if (atom == c.JS_ATOM_NULL) return js.capture(f.engine);
    defer c.JS_FreeAtom(f.engine.context, atom);
    var current = value;
    while (c.JS_IsObject(current)) {
        if (c.JS_IsProxy(current)) return c.pi_js_undefined();
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(f.engine.context, &descriptor, current, atom);
        if (present < 0) return js.capture(f.engine);
        if (present != 0) {
            defer f.engine.freeValue(descriptor.value);
            defer f.engine.freeValue(descriptor.getter);
            defer f.engine.freeValue(descriptor.setter);
            if (descriptor.flags & c.JS_PROP_GETSET != 0) return c.pi_js_undefined();
            return f.own(c.JS_DupValue(f.engine.context, descriptor.value));
        }
        current = try f.own(try f.engine.checked(c.JS_GetPrototype(f.engine.context, current)));
    }
    return c.pi_js_undefined();
}
fn installOwn(f: *Frame, state: *Owner, target: c.JSValue, recapture: bool) !c.JSValue {
    if (recapture) {
        if (!c.JS_IsObject(target) or c.JS_IsProxy(target)) return js.typeError(f.engine, "invalid_argument");
        const extensible = c.JS_IsExtensible(f.engine.context, target);
        if (extensible < 0) return js.capture(f.engine);
        if (extensible == 0) return js.typeError(f.engine, "Cannot define property stack, object is not extensible");
    }
    const record = try f.engine.gpa.create(StackData);
    var attached = false;
    errdefer if (!attached) f.engine.gpa.destroy(record);
    record.* = .{ .engine = f.engine };
    const value = try f.own(try f.engine.checked(c.JS_NewObjectClass(f.engine.context, state.data_class)));
    _ = c.JS_SetOpaque(value, record);
    attached = true;
    const atom = c.JS_NewAtom(f.engine.context, "stack");
    if (atom == c.JS_ATOM_NULL) return js.capture(f.engine);
    defer c.JS_FreeAtom(f.engine.context, atom);
    const getter_value = try f.get(f.bindings, "getStack");
    const setter_value = try f.get(f.bindings, "setStack");
    if (c.JS_DefinePropertyGetSet(f.engine.context, target, atom, c.JS_DupValue(f.engine.context, getter_value), c.JS_DupValue(f.engine.context, setter_value), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(f.engine);
    _ = try f.call(try f.get(f.bindings, "mapSet"), try f.get(f.bindings, "map"), &.{ target, value });
    return value;
}
fn capture(f: *Frame, state: *Owner, target: c.JSValue, filter: c.JSValue, filename: [*c]const u8, line: c_int, column: c_int, flags: c_int, recapture: bool) !void {
    var value = try mapGet(f, target);
    if (recapture or c.JS_IsUndefined(value)) value = try installOwn(f, state, target, recapture);
    const record = data(value, state.data_class);
    if (record.captured) return;
    const error_constructor = try f.get(f.bindings, "error");
    const limit_value = try dataProperty(f, error_constructor, "stackTraceLimit");
    record.captured = true;
    if (!c.JS_IsNumber(limit_value)) return;
    var number: f64 = undefined;
    if (c.JS_ToFloat64(f.engine.context, &number, limit_value) < 0) return js.capture(f.engine);
    const limit: u32 = if (std.math.isNan(number) or number <= 0) 0 else if (std.math.isInf(number) or number >= std.math.maxInt(u32)) std.math.maxInt(u32) else @intFromFloat(number);
    const frames = try f.engine.checked(c.JS_CaptureCurrentStackFrames(f.engine.context, limit, filter, filename, line, column, flags));
    record.frames = frames;
}
fn hook(context: ?*c.JSContext, target: c.JSValue, phase: c_int, filter: c.JSValue, filename: [*c]const u8, line: c_int, column: c_int, flags: c_int, raw: ?*anyopaque) callconv(.c) c_int {
    const state: *Owner = @ptrCast(@alignCast(raw.?));
    _ = context;
    var f: Frame = .{ .engine = state.engine, .object = target, .bindings = state.bindings };
    defer f.deinit();
    const result = if (phase == c.JS_ERROR_STACK_PREPARE) prepared: {
        _ = installOwn(&f, state, target, false) catch |err| break :prepared @as(anyerror!void, err);
        break :prepared @as(anyerror!void, {});
    } else capture(&f, state, target, filter, filename, line, column, flags, phase == c.JS_ERROR_STACK_RECAPTURE);
    result catch |err| {
        _ = failure(state.engine, err);
        return -1;
    };
    return 0;
}
fn adoptPending(f: *Frame, state: *Owner, target: c.JSValue) !?c.JSValue {
    var frames: c.JSValue = undefined;
    const pending = c.JS_ReadPendingNativeErrorStack(f.engine.context, target, &frames);
    if (pending == 0) return null;
    if (pending < 0) return js.capture(f.engine);
    const rooted_frames = try f.own(frames);
    const record = try f.engine.gpa.create(StackData);
    var attached = false;
    errdefer if (!attached) f.engine.gpa.destroy(record);
    record.* = .{ .engine = f.engine, .captured = true, .frames = if (c.JS_IsUndefined(rooted_frames)) null else c.JS_DupValue(f.engine.context, rooted_frames) };
    errdefer if (!attached) if (record.frames) |value| f.engine.freeValue(value);
    const value = try f.own(try f.engine.checked(c.JS_NewObjectClass(f.engine.context, state.data_class)));
    _ = c.JS_SetOpaque(value, record);
    attached = true;
    _ = try f.call(try f.get(f.bindings, "mapSet"), try f.get(f.bindings, "map"), &.{ target, value });
    return value;
}
const Found = struct { holder: c.JSValue, record: *StackData };
fn lookup(f: *Frame, state: *Owner, receiver: c.JSValue) !?Found {
    var current = receiver;
    while (c.JS_IsObject(current)) {
        if (c.JS_IsProxy(current)) return null;
        var value = try mapGet(f, current);
        if (c.JS_IsUndefined(value)) if (try adoptPending(f, state, current)) |adopted| {
            value = adopted;
        };
        if (!c.JS_IsUndefined(value)) return .{ .holder = current, .record = data(value, state.data_class) };
        current = try f.own(try f.engine.checked(c.JS_GetPrototype(f.engine.context, current)));
    }
    return null;
}
fn getter(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, values: [*c]c.JSValue) callconv(.c) c.JSValue {
    const state = owner(values[0]);
    _ = context;
    var f: Frame = .{ .engine = state.engine, .object = receiver, .bindings = state.bindings };
    defer f.deinit();
    state.engine.native_exception_diagnostics_suppressed += 1;
    defer state.engine.native_exception_diagnostics_suppressed -= 1;
    const value = getStack(&f, state, receiver) catch |err| return failure(state.engine, err);
    return f.result(value);
}
fn setter(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, values: [*c]c.JSValue) callconv(.c) c.JSValue {
    const state = owner(values[0]);
    _ = context;
    var f: Frame = .{ .engine = state.engine, .object = receiver, .bindings = state.bindings };
    defer f.deinit();
    const found = lookup(&f, state, receiver) catch |err| return failure(state.engine, err);
    if (found) |selected| {
        if (selected.record.formatted) |previous| state.engine.freeValue(previous);
        selected.record.formatted = c.JS_DupValue(state.engine.context, if (argc > 0) argv[0] else c.pi_js_undefined());
    }
    return c.pi_js_undefined();
}
fn asString(f: *Frame, value: c.JSValue) !c.JSValue {
    return f.own(try f.engine.checked(c.JS_ToString(f.engine.context, value)));
}
fn defaultPrepare(f: *Frame, error_value: c.JSValue, frames: c.JSValue) !c.JSValue {
    const symbol = try f.get(f.bindings, "nodeErrorSymbol");
    const atom = try js.atom(f.engine, symbol);
    defer c.JS_FreeAtom(f.engine.context, atom);
    const is_node = c.JS_HasProperty(f.engine.context, error_value, atom);
    if (is_node < 0) return js.capture(f.engine);
    const header = if (is_node != 0)
        try f.concat(&.{ try asString(f, try f.get(error_value, "name")), try f.text(" ["), try asString(f, try f.get(error_value, "code")), try f.text("]: "), try asString(f, try f.get(error_value, "message")) })
    else
        try f.call(try f.get(f.bindings, "errorToString"), error_value, &.{});
    const length = try f.get(frames, "length");
    if (f.equal(length, c.JS_NewInt32(f.engine.context, 0))) return header;
    const joined = try f.call(try f.get(f.bindings, "arrayJoin"), frames, &.{try f.text("\n    at ")});
    return f.concat(&.{ header, try f.text("\n    at "), joined });
}
fn defaultPrepareCall(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    const state = owner(values[0]);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var f: Frame = .{ .engine = engine, .object = values[0], .bindings = state.bindings };
    defer f.deinit();
    const result = try defaultPrepare(&f, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined());
    return f.result(result);
}
fn prepare(f: *Frame, error_value: c.JSValue, frames: c.JSValue) !c.JSValue {
    const global = try f.get(f.bindings, "global");
    const first_constructor = try f.get(global, "Error");
    const first = if (f.nullish(first_constructor)) c.pi_js_undefined() else try f.get(first_constructor, "prepareStackTrace");
    if (c.JS_IsFunction(f.engine.context, first)) {
        const constructor = try f.get(global, "Error");
        const function = try f.get(constructor, "prepareStackTrace");
        return f.call(function, constructor, &.{ error_value, frames });
    }
    const main_constructor = try f.get(f.bindings, "error");
    const main_first = try f.get(main_constructor, "prepareStackTrace");
    if (c.JS_IsFunction(f.engine.context, main_first)) {
        const function = try f.get(main_constructor, "prepareStackTrace");
        return f.call(function, main_constructor, &.{ error_value, frames });
    }
    return defaultPrepare(f, error_value, frames);
}
fn preparedFrames(f: *Frame, raw_frames: c.JSValue) !c.JSValue {
    const frames = try f.array();
    const length = try f.get(raw_frames, "length");
    var count: u32 = undefined;
    if (c.JS_ToUint32(f.engine.context, &count, length) < 0) return js.capture(f.engine);
    for (0..count) |index| {
        const raw = try f.own(try f.engine.checked(c.JS_GetPropertyUint32(f.engine.context, raw_frames, @intCast(index))));
        const clone = try f.engine.checked(c.JS_CloneCapturedStackFrame(f.engine.context, raw));
        if (c.JS_DefinePropertyValueUint32(f.engine.context, frames, @intCast(index), clone, c.JS_PROP_C_W_E) < 0) return js.capture(f.engine);
    }
    return frames;
}
fn fallbackHeader(f: *Frame, error_value: c.JSValue) !c.JSValue {
    const to_string = try f.get(f.bindings, "errorToString");
    const generation = f.engine.native_allocation_generation;
    return f.call(to_string, error_value, &.{}) catch |err| {
        const restored = f.engine.nativeAllocationError(err, generation);
        if (restored != error.JavaScriptException) return restored;
        const original = f.engine.captured_exception orelse return err;
        const rooted = try f.own(c.JS_DupValue(f.engine.context, original));
        const secondary_generation = f.engine.native_allocation_generation;
        const text = f.call(to_string, rooted, &.{}) catch |secondary| {
            const restored_secondary = f.engine.nativeAllocationError(secondary, secondary_generation);
            if (restored_secondary != error.JavaScriptException) return restored_secondary;
            return f.text("<error>");
        };
        return f.concat(&.{ try f.text("<error: "), text, try f.text(">") });
    };
}
fn fallbackFormat(f: *Frame, error_value: c.JSValue, raw_frames: c.JSValue) !c.JSValue {
    var pieces: std.ArrayList(c.JSValue) = .empty;
    defer pieces.deinit(f.engine.gpa);
    try pieces.append(f.engine.gpa, try fallbackHeader(f, error_value));
    var count: u32 = undefined;
    if (c.JS_ToUint32(f.engine.context, &count, try f.get(raw_frames, "length")) < 0) return js.capture(f.engine);
    for (0..count) |index| {
        const raw = try f.own(try f.engine.checked(c.JS_GetPropertyUint32(f.engine.context, raw_frames, @intCast(index))));
        try pieces.append(f.engine.gpa, try f.text("\n    at "));
        try pieces.append(f.engine.gpa, try frameString(f, raw));
    }
    return f.concat(pieces.items);
}
fn getStack(f: *Frame, state: *Owner, receiver: c.JSValue) !c.JSValue {
    const found = try lookup(f, state, receiver) orelse return c.pi_js_undefined();
    if (found.record.formatted) |formatted| return formatted;
    const frames = found.record.frames orelse return c.pi_js_undefined();
    const reentrant = state.formatting;
    state.formatting = true;
    defer state.formatting = reentrant;
    const formatted = if (reentrant) try fallbackFormat(f, found.holder, frames) else try prepare(f, found.holder, try preparedFrames(f, frames));
    found.record.formatted = c.JS_DupValue(f.engine.context, formatted);
    return formatted;
}
fn frameStringCall(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, values: [*c]c.JSValue) callconv(.c) c.JSValue {
    const state = owner(values[0]);
    _ = context;
    var f: Frame = .{ .engine = state.engine, .object = receiver, .bindings = state.bindings };
    defer f.deinit();
    const result = frameString(&f, receiver) catch |err| return failure(state.engine, err);
    return f.result(result);
}
fn frameString(f: *Frame, receiver: c.JSValue) !c.JSValue {
    var filename: c.JSValue = undefined;
    var function_name: c.JSValue = undefined;
    var line: c_int = undefined;
    var column: c_int = undefined;
    var native: c_int = undefined;
    var constructor: c_int = undefined;
    if (c.JS_ReadCapturedStackFrame(f.engine.context, receiver, &filename, &function_name, &line, &column, &native, &constructor) < 0)
        return js.typeError(f.engine, "Method CallSite.prototype.toString called on incompatible receiver");
    const file = try f.own(filename);
    const name = try f.own(function_name);
    const location = if (native != 0) try f.text("native") else if (line < 0)
        (if (c.JS_IsString(file)) file else try f.text("<anonymous>"))
    else
        try f.concat(&.{ if (c.JS_IsString(file)) file else try f.text("<anonymous>"), try f.text(":"), try asString(f, c.JS_NewInt32(f.engine.context, line)), try f.text(":"), try asString(f, c.JS_NewInt32(f.engine.context, column)) });
    if (c.JS_IsString(name) and !try f.is(name, "")) return f.concat(&.{ if (constructor != 0) try f.text("new ") else try f.text(""), name, try f.text(" ("), location, try f.text(")") });
    return location;
}
fn remove(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8) !void {
    const atom = c.JS_NewAtom(engine.context, name);
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, object, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
}
fn reorderPrototype(f: *Frame, object: c.JSValue, keys: []const [*:0]const u8) !void {
    var entries: std.ArrayList(struct { key: [*:0]const u8, value: c.JSValue, flags: c_int }) = .empty;
    defer entries.deinit(f.engine.gpa);
    for (keys) |key| {
        const atom = c.JS_NewAtom(f.engine.context, key);
        if (atom == c.JS_ATOM_NULL) return js.capture(f.engine);
        defer c.JS_FreeAtom(f.engine.context, atom);
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(f.engine.context, &descriptor, object, atom);
        if (present < 0) return js.capture(f.engine);
        if (present == 0) continue;
        defer f.engine.freeValue(descriptor.value);
        defer f.engine.freeValue(descriptor.getter);
        defer f.engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_GETSET != 0) return error.UnexpectedPristineErrorAccessor;
        try entries.append(f.engine.gpa, .{ .key = key, .value = try f.own(c.JS_DupValue(f.engine.context, descriptor.value)), .flags = descriptor.flags & c.JS_PROP_C_W_E });
    }
    for (entries.items) |entry| try remove(f.engine, object, entry.key);
    for (entries.items) |entry| if (c.JS_DefinePropertyValueStr(f.engine.context, object, entry.key, c.JS_DupValue(f.engine.context, entry.value), entry.flags) < 0) return js.capture(f.engine);
}
/// Caller retains the returned private owner until uninstall precedes its release.
/// This candidate is installed only by focused tests, not Engine.init or workers.
pub fn install(engine: *js.Engine) !c.JSValue {
    const bindings = try js.object(engine);
    defer engine.freeValue(bindings);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, bindings, "global", c.JS_DupValue(engine.context, global));
    const error_constructor = try js.get(engine, global, "Error");
    defer engine.freeValue(error_constructor);
    try js.define(engine, bindings, "error", c.JS_DupValue(engine.context, error_constructor));
    const error_prototype = try js.get(engine, error_constructor, "prototype");
    defer engine.freeValue(error_prototype);
    try js.define(engine, bindings, "errorToString", try js.get(engine, error_prototype, "toString"));
    const array = try js.get(engine, global, "Array");
    defer engine.freeValue(array);
    const array_prototype = try js.get(engine, array, "prototype");
    defer engine.freeValue(array_prototype);
    try js.define(engine, bindings, "arrayJoin", try js.get(engine, array_prototype, "join"));
    const weak_constructor = try js.get(engine, global, "WeakMap");
    defer engine.freeValue(weak_constructor);
    const weak_prototype = try js.get(engine, weak_constructor, "prototype");
    defer engine.freeValue(weak_prototype);
    try js.define(engine, bindings, "mapGet", try js.get(engine, weak_prototype, "get"));
    try js.define(engine, bindings, "mapSet", try js.get(engine, weak_prototype, "set"));
    try js.define(engine, bindings, "map", try engine.checked(c.JS_CallConstructor(engine.context, weak_constructor, 0, null)));
    const symbol = try js.get(engine, global, "Symbol");
    defer engine.freeValue(symbol);
    const label = try engine.checked(c.JS_NewString(engine.context, "kIsNodeError"));
    defer engine.freeValue(label);
    try js.define(engine, bindings, "nodeErrorSymbol", try js.call(engine, symbol, c.pi_js_undefined(), &.{label}));
    var data_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &data_class);
    const data_definition: c.JSClassDef = .{ .class_name = "Private native Error stack data", .finalizer = finalizeData, .gc_mark = markData };
    if (c.JS_NewClass(engine.runtime, data_class, &data_definition) < 0) return error.OutOfMemory;
    var owner_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &owner_class);
    const owner_definition: c.JSClassDef = .{ .class_name = "Private native Error stack owner", .finalizer = finalizeOwner, .gc_mark = markOwner };
    if (c.JS_NewClass(engine.runtime, owner_class, &owner_definition) < 0) return error.OutOfMemory;
    const state = try engine.gpa.create(Owner);
    var attached = false;
    errdefer if (!attached) engine.gpa.destroy(state);
    const owner_value = try engine.checked(c.JS_NewObjectClass(engine.context, owner_class));
    errdefer engine.freeValue(owner_value);
    state.* = .{ .engine = engine, .bindings = c.JS_DupValue(engine.context, bindings), .data_class = data_class };
    _ = c.JS_SetOpaque(owner_value, state);
    attached = true;
    var values = [_]c.JSValue{owner_value};
    try js.define(engine, bindings, "getStack", try engine.checked(c.JS_NewCFunctionData2(engine.context, getter, "", 0, 0, values.len, &values)));
    try js.define(engine, bindings, "setStack", try engine.checked(c.JS_NewCFunctionData2(engine.context, setter, "", 1, 0, values.len, &values)));
    const default_function = try @import("native_node_function.zig").create(engine, "ErrorPrepareStackTrace", 2, defaultPrepareCall, &.{owner_value});
    defer engine.freeValue(default_function);
    var f: Frame = .{ .engine = engine, .object = owner_value, .bindings = bindings };
    defer f.deinit();
    const capture_function = try f.get(error_constructor, "captureStackTrace");
    const is_error = try f.get(error_constructor, "isError");
    const initial_limit = try f.get(error_constructor, "stackTraceLimit");
    inline for (.{ "captureStackTrace", "prepareStackTrace", "isError", "stackTraceLimit" }) |key| try remove(engine, error_constructor, key);
    if (c.JS_DefinePropertyValueStr(engine.context, error_constructor, "captureStackTrace", c.JS_DupValue(engine.context, capture_function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0 or
        c.JS_DefinePropertyValueStr(engine.context, error_constructor, "prepareStackTrace", c.JS_DupValue(engine.context, default_function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0 or
        c.JS_DefinePropertyValueStr(engine.context, error_constructor, "isError", c.JS_DupValue(engine.context, is_error), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0 or
        c.JS_DefinePropertyValueStr(engine.context, error_constructor, "stackTraceLimit", c.JS_DupValue(engine.context, initial_limit), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    try remove(engine, error_prototype, "stack");
    try reorderPrototype(&f, error_prototype, &.{ "constructor", "name", "message", "toString" });
    inline for (.{ "EvalError", "RangeError", "ReferenceError", "SyntaxError", "TypeError", "URIError", "AggregateError" }) |name| {
        const constructor = try f.get(global, name);
        const prototype = try f.get(constructor, "prototype");
        try reorderPrototype(&f, prototype, &.{ "constructor", "name", "message" });
    }
    const callsite_prototype = try f.own(try engine.checked(c.JS_GetCapturedStackFramePrototype(engine.context)));
    const to_string = try engine.checked(c.JS_NewCFunctionData2(engine.context, frameStringCall, "toString", 0, 0, values.len, &values));
    if (c.JS_DefinePropertyValueStr(engine.context, callsite_prototype, "toString", to_string, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    c.JS_SetNativeErrorStackAccessors(engine.context, try f.get(bindings, "getStack"), try f.get(bindings, "setStack"));
    c.JS_SetNativeErrorStackHook(engine.runtime, hook, state);
    return owner_value;
}
pub fn uninstall(engine: *js.Engine) void {
    c.JS_SetNativeErrorStackHook(engine.runtime, null, null);
    c.JS_SetNativeErrorStackAccessors(engine.context, c.pi_js_undefined(), c.pi_js_undefined());
}
