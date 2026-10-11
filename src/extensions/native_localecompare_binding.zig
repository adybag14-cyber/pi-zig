//! Actual native localeCompare. Install during VM startup before guest code;
//! retained intrinsic symbols/constructors survive guest global replacement.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("native_tui_alt_frame.zig");
const js = a.js;
const c = a.c;
const Frame = a.Frame;
const utf16 = @import("native_utf16.zig");
const native = @import("native_icu_api");
const diagnostic = @import("native_v8_diagnostics.zig");
const Owner = struct { engine: *js.Engine, lookup: native.lookup.Lookup, bindings: c.JSValue };
var owners_created: std.atomic.Value(u64) = .init(0);
var owners_finalized: std.atomic.Value(u64) = .init(0);
pub fn ownerCountsForTest() struct { created: u64, finalized: u64 } {
    if (!builtin.is_test) @compileError("Owner diagnostics are test-only");
    return .{ .created = owners_created.load(.acquire), .finalized = owners_finalized.load(.acquire) };
}
fn owner(value: c.JSValue) *Owner {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    state.lookup.deinit();
    c.JS_FreeValueRT(runtime, state.bindings);
    state.engine.gpa.destroy(state);
    if (builtin.is_test) _ = owners_finalized.fetchAdd(1, .release);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.bindings, marker);
}
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    return c.JS_ThrowInternalError(engine.context, "Native localeCompare: %s", @as([*:0]const u8, @errorName(err)));
}
fn throwError(f: *Frame, kind: [*:0]const u8, message: c.JSValue) !void {
    const constructor = try f.get(f.bindings, kind);
    const value = try f.construct(constructor, &.{message});
    _ = try f.engine.checked(c.JS_Throw(f.engine.context, c.JS_DupValue(f.engine.context, value)));
    unreachable;
}
fn typeError(f: *Frame, message: []const u8) !void {
    return throwError(f, "typeError", try f.text(message));
}
fn tick(f: *Frame) !void {
    f.native_steps +|= 1;
    if (f.engine.cancelled.load(.acquire) or (f.native_steps % 256 == 0 and blk: {
        f.engine.interrupts +|= 1;
        break :blk f.engine.interrupts > f.engine.options.interrupt_budget;
    })) {
        _ = try f.engine.checked(c.JS_ThrowInternalError(f.engine.context, "interrupted"));
        unreachable;
    }
}
fn primitive(f: *Frame, value: c.JSValue, string_hint: bool) anyerror!c.JSValue {
    if (!c.JS_IsObject(value)) return value;
    const key = try f.get(f.bindings, "primitiveSymbol");
    const exotic = try diagnostic.getKey(f, value, key);
    if (!c.JS_IsNull(exotic) and !c.JS_IsUndefined(exotic)) {
        if (!c.JS_IsFunction(f.engine.context, exotic)) try diagnostic.propertyNotFunction(f, exotic, key, value);
        const result = try f.call(exotic, value, &.{try f.text(if (string_hint) "string" else "number")});
        if (!c.JS_IsObject(result)) return result;
        try typeError(f, "Cannot convert object to primitive value");
    }
    const names = if (string_hint) [_][*:0]const u8{ "toString", "valueOf" } else [_][*:0]const u8{ "valueOf", "toString" };
    for (names) |name| {
        const function = try diagnostic.get(f, value, name);
        if (c.JS_IsFunction(f.engine.context, function)) {
            const result = try f.call(function, value, &.{});
            if (!c.JS_IsObject(result)) return result;
        }
    }
    try typeError(f, "Cannot convert object to primitive value");
    unreachable;
}
fn string(f: *Frame, value: c.JSValue) !c.JSValue {
    const simple = try primitive(f, value, true);
    if (c.JS_IsSymbol(simple)) try typeError(f, "Cannot convert a Symbol value to a string");
    return f.own(try f.engine.checked(c.JS_ToString(f.engine.context, simple)));
}
fn length(f: *Frame, value: c.JSValue) !u64 {
    const simple = try primitive(f, value, false);
    if (c.JS_IsSymbol(simple)) try typeError(f, "Cannot convert a Symbol value to a number");
    if (c.JS_IsBigInt(simple)) try typeError(f, "Cannot convert a BigInt value to a number");
    var number: f64 = 0;
    if (c.JS_ToFloat64(f.engine.context, &number, simple) < 0) return js.capture(f.engine);
    if (std.math.isNan(number) or number <= 0) return 0;
    return @intFromFloat(@min(@floor(number), 9007199254740991));
}
fn canonical(f: *Frame, gpa: std.mem.Allocator, value: c.JSValue) ![]const u8 {
    if (!c.JS_IsString(value) and !c.JS_IsObject(value)) try typeError(f, "Language ID should be string or object.");
    const text = try string(f, value);
    const bytes = try f.engine.toString(text);
    defer f.engine.gpa.free(bytes);
    return native.aliases.canonicalize(gpa, bytes) catch |err| {
        switch (err) {
            error.IncorrectLocaleInformation => try throwError(f, "rangeError", try f.text("Incorrect locale information provided")),
            error.InvalidLanguageTag => try throwError(f, "rangeError", try f.concat(&.{ try f.text("Invalid language tag: "), text })),
            else => return err,
        }
        unreachable;
    };
}
fn localeList(f: *Frame, gpa: std.mem.Allocator, value: c.JSValue) ![][]const u8 {
    var seen: std.ArrayList([]const u8) = .empty;
    if (c.JS_IsUndefined(value)) return seen.toOwnedSlice(gpa);
    if (c.JS_IsString(value)) {
        try seen.append(gpa, try canonical(f, gpa, value));
        return seen.toOwnedSlice(gpa);
    }
    if (c.JS_IsNull(value)) try typeError(f, "Cannot convert undefined or null to object");
    const object = try f.own(try f.engine.checked(c.JS_ToObject(f.engine.context, value)));
    const count = try length(f, try diagnostic.get(f, object, "length"));
    var index: u64 = 0;
    while (index < count) : (index += 1) {
        try tick(f);
        var item: Frame = .{ .engine = f.engine, .object = f.object, .bindings = f.bindings };
        defer item.deinit();
        const key = item.num(@floatFromInt(index));
        if (!try js.hasKey(f.engine, object, key)) continue;
        const value_at = try item.own(try js.getKey(f.engine, object, key));
        const tag = try canonical(&item, gpa, value_at);
        var duplicate = false;
        for (seen.items) |known| if (std.mem.eql(u8, known, tag)) {
            duplicate = true;
            break;
        };
        if (!duplicate) try seen.append(gpa, tag);
    }
    return seen.toOwnedSlice(gpa);
}
fn optionString(f: *Frame, options: c.JSValue, key: [*:0]const u8, allowed: ?[]const []const u8, fallback: c.JSValue) !c.JSValue {
    const raw = try diagnostic.get(f, options, key);
    if (c.JS_IsUndefined(raw)) return fallback;
    const value = try string(f, raw);
    if (allowed) |values| {
        for (values) |expected| if (try f.is(value, expected)) return value;
        try throwError(f, "rangeError", try f.concat(&.{ try f.text("Value "), value, try f.text(" out of range for String.prototype.localeCompare options property "), try f.text(std.mem.span(key)) }));
    }
    return value;
}
fn optionBool(f: *Frame, options: c.JSValue, key: [*:0]const u8) !?bool {
    const raw = try diagnostic.get(f, options, key);
    return if (c.JS_IsUndefined(raw)) null else f.truth(raw);
}
fn collationSyntax(value: []const u8) bool {
    var fields = std.mem.splitScalar(u8, value, '-');
    while (fields.next()) |field| {
        if (field.len < 3 or field.len > 8) return false;
        for (field) |byte| if (!std.ascii.isAlphanumeric(byte)) return false;
    }
    return true;
}
fn body(f: *Frame, state: *Owner, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    if (c.JS_IsNull(receiver) or c.JS_IsUndefined(receiver)) try typeError(f, "String.prototype.localeCompare called on null or undefined");
    const left = try string(f, receiver);
    const right = try string(f, a.v.arg(args, 0));
    var arena: std.heap.ArenaAllocator = .init(f.engine.gpa);
    defer arena.deinit();
    const gpa = arena.allocator();
    const requested = try localeList(f, gpa, a.v.arg(args, 1));
    const raw_options = a.v.arg(args, 2);
    if (c.JS_IsNull(raw_options)) try typeError(f, "String.prototype.localeCompare called on null or undefined");
    const options = try f.own(try f.engine.checked(if (c.JS_IsUndefined(raw_options)) c.JS_NewObjectProto(f.engine.context, c.pi_js_null()) else c.JS_ToObject(f.engine.context, raw_options)));
    const usage = try optionString(f, options, "usage", &.{ "sort", "search" }, try f.text("sort"));
    const mode_value = try optionString(f, options, "localeMatcher", &.{ "lookup", "best fit" }, try f.text("best fit"));
    const mode: native.lookup.Mode = if (try f.is(mode_value, "lookup")) .lookup else .best_fit;
    const collation = try optionString(f, options, "collation", null, c.pi_js_undefined());
    var collation_bytes: ?[:0]const u8 = null;
    if (!c.JS_IsUndefined(collation)) {
        const raw = try f.engine.toString(collation);
        defer f.engine.gpa.free(raw);
        if (!collationSyntax(raw)) try throwError(f, "rangeError", try f.concat(&.{ try f.text("Invalid collation : "), collation }));
        collation_bytes = try gpa.dupeZ(u8, raw);
    }
    const numeric = try optionBool(f, options, "numeric");
    const first = try optionString(f, options, "caseFirst", &.{ "upper", "lower", "false" }, c.pi_js_undefined());
    const case_first: ?native.icu.CaseFirst = if (c.JS_IsUndefined(first)) null else if (try f.is(first, "upper")) .upper else if (try f.is(first, "lower")) .lower else .off;
    const matched = try state.lookup.match(gpa, requested, mode);
    var locale = matched.locale;
    if (collation_bytes != null or try f.is(usage, "search")) {
        var builder = try native.ids.Builder.init(locale);
        defer builder.deinit();
        if (collation_bytes) |value| if (try native.ids.unicodeKeyword(gpa, locale, "co")) |extension| {
            if (!std.mem.eql(u8, extension, value)) try builder.removeUnicodeKeyword("co");
        };
        if (try f.is(usage, "search")) {
            try builder.setUnicodeKeyword("co", "search");
        } else if (collation_bytes) |value| if (try native.lookup.Lookup.validCollation(gpa, locale, value)) try builder.setUnicodeKeyword("co", value);
        locale = try builder.build(gpa);
    }
    var collator = try native.icu.Collator.open(locale.id, .{ .sensitivity = null, .numeric = numeric, .case_first = case_first });
    defer collator.deinit();
    const sensitivity_value = try optionString(f, options, "sensitivity", &.{ "base", "accent", "case", "variant" }, c.pi_js_undefined());
    const sensitivity: ?native.icu.Sensitivity = if (c.JS_IsUndefined(sensitivity_value)) (if (try f.is(usage, "sort")) .variant else null) else if (try f.is(sensitivity_value, "base")) .base else if (try f.is(sensitivity_value, "accent")) .accent else if (try f.is(sensitivity_value, "case")) .case else .variant;
    try collator.setSensitivity(sensitivity);
    if (try optionBool(f, options, "ignorePunctuation")) |value| try collator.setIgnorePunctuation(value);
    const left_units = try utf16.unitsAlloc(f.engine, left);
    defer f.engine.gpa.free(left_units);
    const right_units = try utf16.unitsAlloc(f.engine, right);
    defer f.engine.gpa.free(right_units);
    return f.num(@floatFromInt(try collator.compare(left_units, right_units)));
}
fn compare(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const state = owner(data[0]);
    var f: Frame = .{ .engine = state.engine, .object = data[0], .bindings = state.bindings };
    defer f.deinit();
    const result = body(&f, state, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| return fail(state.engine, err);
    _ = ctx;
    return f.result(result);
}
pub fn create(engine: *js.Engine) !c.JSValue {
    var lookup = try native.lookup.Lookup.init(engine.gpa);
    var attached = false;
    errdefer if (!attached) lookup.deinit();
    const state = try engine.gpa.create(Owner);
    errdefer if (!attached) engine.gpa.destroy(state);
    const bindings = try js.object(engine);
    defer engine.freeValue(bindings);
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    try js.define(engine, bindings, "primitiveSymbol", try js.get(engine, symbol, "toPrimitive"));
    try js.define(engine, bindings, "tagSymbol", try js.get(engine, symbol, "toStringTag"));
    inline for (.{ .{ "Symbol", "symbolToString" }, .{ "Function", "functionToString" }, .{ "Object", "objectToString" }, .{ "Error", "errorToString" } }) |entry| {
        const constructor = try js.global(engine, entry[0]);
        defer engine.freeValue(constructor);
        const prototype = try js.get(engine, constructor, "prototype");
        defer engine.freeValue(prototype);
        try js.define(engine, bindings, entry[1], try js.get(engine, prototype, "toString"));
    }
    try js.define(engine, bindings, "typeError", try js.global(engine, "TypeError"));
    try js.define(engine, bindings, "rangeError", try js.global(engine, "RangeError"));
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Private native localeCompare owner", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, class));
    defer engine.freeValue(object);
    state.* = .{ .engine = engine, .lookup = lookup, .bindings = c.JS_DupValue(engine.context, bindings) };
    _ = c.JS_SetOpaque(object, state);
    attached = true;
    if (builtin.is_test) _ = owners_created.fetchAdd(1, .release);
    var data = [_]c.JSValue{object};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, compare, "localeCompare", 1, 0, 1, &data));
}
pub fn install(engine: *js.Engine) !void {
    const constructor = try js.global(engine, "String");
    defer engine.freeValue(constructor);
    const prototype = try js.get(engine, constructor, "prototype");
    defer engine.freeValue(prototype);
    const function = try create(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "localeCompare", function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
