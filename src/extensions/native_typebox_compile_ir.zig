//! Native expression/statement lowering for the actual TypeBox EmitGuard build.
//! Nodes retain captured scalar expressions and actual external VM values.
//! No generated JavaScript checker is evaluated by this backend.
const std = @import("std");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const o = @import("native_typebox_compile_ops.zig");
const ordinary = @import("native_node_function.zig");
const c = js.c;
const Engine = js.Engine;
const Op = enum(c_int) {
    And,
    Or,
    Not,
    IsArray,
    IsBigInt,
    IsBoolean,
    IsInteger,
    IsNull,
    IsNumber,
    IsObject,
    IsString,
    IsSymbol,
    IsUndefined,
    IsFunction,
    IsConstructor,
    IsEqual,
    IsGreaterThan,
    IsLessThan,
    IsLessEqualThan,
    IsGreaterEqualThan,
    IsMinLength,
    IsMaxLength,
    Every,
    Some,
    SomeAll,
    Counted,
    Entries,
    Keys,
    HasPropertyKey,
    IsDeepEqual,
    ArrayLiteral,
    ArrowFunction,
    Call,
    New,
    Member,
    Constant,
    Ternary,
    Statements,
    ConstDeclaration,
    If,
    Return,
    MultipleOf,
};
const Result = struct { value: c.JSValue, returned: bool = false };
const Parameter = enum(c_int) { identifier, array };
fn field(s: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return s.get(object, name);
}
fn at(s: *Scope, array: c.JSValue, index: u32) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, array, index)));
}
fn length(s: *Scope, array: c.JSValue) !u32 {
    var n: u32 = 0;
    if (c.JS_ToUint32(s.engine.context, &n, try field(s, array, "length")) < 0) return js.capture(s.engine);
    return n;
}
fn private(s: *Scope) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, c.pi_js_null())));
}
fn set(s: *Scope, obj: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    try s.put(obj, name, value);
}
fn snapshot(s: *Scope, array: c.JSValue) !c.JSValue {
    const out = try s.array();
    for (0..try length(s, array)) |i| try s.index(out, @intCast(i), try at(s, array, @intCast(i)));
    return out;
}
fn isUniqueParameter(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "var_") or name.len == 4) return false;
    const suffix = name[4..];
    if (suffix.len > 1 and suffix[0] == '0') return false;
    for (suffix) |char| if (!std.ascii.isDigit(char)) return false;
    return true;
}
fn lowerIdentifierParameter(s: *Scope, name: []const u8) !c.JSValue {
    // Pinned schema/engine emitters use only these six scalar names and Unique().
    // Reject other names, including reserved words and special literal/global
    // spellings, rather than admitting bindings identifier() cannot read back.
    const emitted = isUniqueParameter(name) or std.mem.eql(u8, name, "_") or
        std.mem.eql(u8, name, "refinement") or std.mem.eql(u8, name, "context") or
        std.mem.eql(u8, name, "value") or std.mem.eql(u8, name, "element") or
        std.mem.eql(u8, name, "index");
    if (!emitted) return error.NativeTypeBoxParameterPatternUnsupported;
    const node = try private(s);
    try set(s, node, "tag", c.JS_NewInt32(s.engine.context, @intFromEnum(Parameter.identifier)));
    try set(s, node, "name", try s.text(name));
    return node;
}
fn lowerParameter(s: *Scope, input: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(input)) return error.NativeTypeBoxParameterPatternUnsupported;
    const bytes = try s.engine.toString(input);
    defer s.engine.gpa.free(bytes);
    const name = std.mem.trim(u8, bytes, " \t\r\n");
    if (std.mem.startsWith(u8, name, "[") and std.mem.endsWith(u8, name, "]")) {
        // Only patternProperties/unevaluatedProperties emit destructuring:
        // two distinct Unique() variables, with no nesting, holes or rest.
        var parts = std.mem.splitScalar(u8, name[1 .. name.len - 1], ',');
        const first = std.mem.trim(u8, parts.next() orelse return error.NativeTypeBoxParameterPatternUnsupported, " \t\r\n");
        const second = std.mem.trim(u8, parts.next() orelse return error.NativeTypeBoxParameterPatternUnsupported, " \t\r\n");
        if (parts.next() != null or !isUniqueParameter(first) or !isUniqueParameter(second) or std.mem.eql(u8, first, second)) return error.NativeTypeBoxParameterPatternUnsupported;
        const node = try private(s);
        try set(s, node, "tag", c.JS_NewInt32(s.engine.context, @intFromEnum(Parameter.array)));
        const elements = try s.array();
        try s.index(elements, 0, try lowerIdentifierParameter(s, first));
        try s.index(elements, 1, try lowerIdentifierParameter(s, second));
        try set(s, node, "elements", elements);
        return node;
    }
    return lowerIdentifierParameter(s, name);
}
fn lowerParameters(s: *Scope, parameters: c.JSValue) !c.JSValue {
    const result = try s.array();
    for (0..try length(s, parameters)) |index| try s.index(result, @intCast(index), try lowerParameter(s, try at(s, parameters, @intCast(index))));
    return result;
}
fn bindParameter(s: *Scope, env: c.JSValue, parameter: c.JSValue, value: c.JSValue) anyerror!void {
    var tag: i32 = 0;
    if (c.JS_ToInt32(s.engine.context, &tag, try field(s, parameter, "tag")) < 0) return js.capture(s.engine);
    switch (@as(Parameter, @enumFromInt(tag))) {
        .identifier => try keyPut(s, env, try field(s, parameter, "name"), value),
        .array => {
            var cursor = try o.iterator(s.engine, value);
            defer cursor.deinit();
            errdefer cursor.closePreserving();
            const elements = try field(s, parameter, "elements");
            for (0..try length(s, elements)) |index| {
                const element = try s.own(if (cursor.closed) c.pi_js_undefined() else (try cursor.next()) orelse c.pi_js_undefined());
                try bindParameter(s, env, try at(s, elements, @intCast(index)), element);
            }
            try cursor.close();
        },
    }
}
fn keyPut(s: *Scope, obj: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    try o.defineKey(s, obj, key, value);
}
fn keyGet(s: *Scope, obj: c.JSValue, key: c.JSValue) !c.JSValue {
    return s.own(try js.getKey(s.engine, obj, key));
}
fn isText(s: *Scope, value: c.JSValue, text: []const u8) !bool {
    return s.equal(value, try s.text(text));
}
fn namespace(s: *Scope, graph: c.JSValue, path: [*:0]const u8) !c.JSValue {
    return field(s, try field(s, graph, "modules"), path);
}
fn record(e: *Engine, graph: c.JSValue, op: Op, args: []const c.JSValue, code: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const active = try field(&s, graph, "irActive");
    if (!c.JS_IsObject(active)) return;
    const node = try private(&s);
    try set(&s, node, "op", c.JS_NewInt32(e.context, @intFromEnum(op)));
    const inputs = try s.array();
    for (args, 0..) |item, i| try s.index(inputs, @intCast(i), item);
    // These arrays are compiler-owned source arrays. Retain their values as a
    // build-time snapshot; runtime external.variables remains a live VM array.
    switch (op) {
        .Every => try s.index(inputs, 2, try lowerParameters(&s, args[2])),
        .Some, .SomeAll, .Counted => try s.index(inputs, 1, try lowerParameters(&s, args[1])),
        .ArrayLiteral, .Statements => try s.index(inputs, 0, try snapshot(&s, args[0])),
        .ArrowFunction => try s.index(inputs, 0, try lowerParameters(&s, args[0])),
        .Call, .New => try s.index(inputs, 1, try snapshot(&s, args[1])),
        else => {},
    }
    try set(&s, node, "args", inputs);
    var current = active;
    while (c.JS_IsObject(current)) {
        try keyPut(&s, current, code, node);
        current = try field(&s, current, "@parentNodes");
    }
}
fn emit(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const result = try js.call(e, roots[1], receiver, args);
    errdefer e.freeValue(result);
    var tag: i32 = 0;
    if (c.JS_ToInt32(e.context, &tag, roots[2]) < 0) return js.capture(e);
    try record(e, roots[0], @enumFromInt(tag), args, result);
    return result;
}
/// Install lowering around genuine native EmitGuard bodies. Composed emitters
/// ReduceAnd/ReduceOr/IsObjectNotArray keep their actual recursive algorithms.
pub fn prepare(e: *Engine, graph: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const emit_namespace = try namespace(&s, graph, "guard/emit.mjs");
    inline for (std.meta.fields(Op)) |entry| {
        const original = try field(&s, emit_namespace, entry.name);
        const arity = try field(&s, original, "length");
        var n: i32 = 0;
        if (c.JS_ToInt32(e.context, &n, arity) < 0) return js.capture(e);
        const wrapper = try s.own(try ordinary.create(e, entry.name, n, emit, &.{ graph, original, c.JS_NewInt32(e.context, @intCast(entry.value)) }));
        try set(&s, emit_namespace, entry.name, wrapper);
        const frames = try field(&s, graph, "frames");
        const frame = try field(&s, frames, "guard/emit.mjs");
        const bindings = try field(&s, try field(&s, graph, "bindings"), "guard/emit.mjs");
        const binding = try field(&s, bindings, entry.name);
        try keyPut(&s, frame, binding, wrapper);
    }
    try set(&s, graph, "irActive", c.pi_js_undefined());
    const builds = try o.construct(&s, try s.global("WeakMap"), &.{});
    try set(&s, graph, "irBuilds", builds);
    try set(&s, graph, "irBuildSet", try field(&s, builds, "set"));
    try set(&s, graph, "irBuildGet", try field(&s, builds, "get"));
}
pub fn begin(e: *Engine, graph: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const previous = try field(&s, graph, "irActive");
    const active = try private(&s);
    try set(&s, active, "@parentNodes", previous);
    try set(&s, graph, "irActive", active);
    return c.JS_DupValue(e.context, previous);
}
pub fn finish(e: *Engine, graph: c.JSValue, built: c.JSValue, previous: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const active = try field(&s, graph, "irActive");
    const builds = try field(&s, graph, "irBuilds");
    _ = try s.call(try field(&s, graph, "irBuildSet"), builds, &.{ built, active });
    try set(&s, active, "@parentNodes", c.pi_js_undefined());
    try set(&s, graph, "irActive", previous);
}
pub fn restore(e: *Engine, graph: c.JSValue, previous: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    try set(&s, graph, "irActive", previous);
}
fn invokeNamespace(s: *Scope, graph: c.JSValue, path: [*:0]const u8, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return s.invoke(try namespace(s, graph, path), name, args);
}
fn evalArray(s: *Scope, graph: c.JSValue, nodes: c.JSValue, env: c.JSValue, expressions: c.JSValue) !c.JSValue {
    const out = try s.array();
    for (0..try length(s, expressions)) |i| try s.index(out, @intCast(i), (try evaluate(s, graph, nodes, env, try at(s, expressions, @intCast(i)))).value);
    return out;
}
fn identifier(s: *Scope, env: c.JSValue, code: c.JSValue) !c.JSValue {
    // Names emitted by CreateVariable have this exact fixed lexical form.
    const bytes = try s.engine.toString(code);
    defer s.engine.gpa.free(bytes);
    if (std.mem.startsWith(u8, bytes, "External[") and std.mem.endsWith(u8, bytes, "]")) {
        const i = std.fmt.parseInt(u32, bytes[9 .. bytes.len - 1], 10) catch return error.NativeTypeBoxInvalidExternalOperand;
        const external = try o.lookup(s, env, "External");
        return at(s, external, i);
    }
    if (std.mem.eql(u8, bytes, "true")) return o.boolean(s, true);
    if (std.mem.eql(u8, bytes, "false")) return o.boolean(s, false);
    if (std.mem.eql(u8, bytes, "undefined")) return c.pi_js_undefined();
    if (std.mem.eql(u8, bytes, "null")) return c.pi_js_null();
    if (std.fmt.parseFloat(f64, bytes)) |number| return c.JS_NewFloat64(s.engine.context, number) else |_| {}
    const atom = try js.atom(s.engine, code);
    defer c.JS_FreeAtom(s.engine.context, atom);
    var current = env;
    while (c.JS_IsObject(current)) {
        const has = c.JS_HasProperty(s.engine.context, current, atom);
        if (has < 0) return js.capture(s.engine);
        if (has != 0) return keyGet(s, current, code);
        current = try field(s, current, "@parent");
    }
    // NaN/Infinity and standard global constructors keep normal VM lookup.
    const global = try s.own(c.JS_GetGlobalObject(s.engine.context));
    return keyGet(s, global, code);
}
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return callArrow(e, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..5]) catch |err| @import("native_sdk.zig").fail(e, err);
}
fn callArrow(e: *Engine, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const env = try o.frame(&s, roots[2]);
    const params = roots[3];
    for (0..try length(&s, params)) |i| try bindParameter(&s, env, try at(&s, params, @intCast(i)), if (i < args.len) args[i] else c.pi_js_undefined());
    const result = try evaluate(&s, roots[0], roots[1], env, roots[4]);
    return c.JS_DupValue(e.context, if (result.returned) result.value else result.value);
}
fn arrayCallback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return arrayStep(e, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic), roots[0..7]) catch |err| @import("native_sdk.zig").fail(e, err);
}
fn arrayStep(e: *Engine, args: []const c.JSValue, op: Op, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const env = try o.frame(&s, roots[2]);
    const params = roots[3];
    const delta: usize = if (op == .Counted) 1 else 0;
    for (0..try length(&s, params)) |i| try bindParameter(&s, env, try at(&s, params, @intCast(i)), if (i + delta < args.len) args[i + delta] else c.pi_js_undefined());
    if (op == .Every and !(try isText(&s, roots[5], "0"))) {
        const offset = (try evaluate(&s, roots[0], roots[1], env, roots[5])).value;
        const index = if (args.len > 1) args[1] else c.pi_js_undefined();
        const below = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, index, offset)));
        if (s.truthy(below)) return o.boolean(&s, true);
    }
    const result = (try evaluate(&s, roots[0], roots[1], env, roots[4])).value;
    if (op == .SomeAll) {
        if (s.truthy(result)) try set(&s, roots[6], "result", o.boolean(&s, true));
        return c.pi_js_undefined();
    }
    if (op == .Counted) {
        const current = if (args.len > 0) args[0] else c.pi_js_undefined();
        return if (s.truthy(result)) e.checked(c.JS_PiIncrement(e.context, current)) else c.JS_DupValue(e.context, current);
    }
    return c.JS_DupValue(e.context, result);
}
fn evaluate(s: *Scope, graph: c.JSValue, nodes: c.JSValue, env: c.JSValue, code: c.JSValue) anyerror!Result {
    const e = s.engine;
    const node = try keyGet(s, nodes, code);
    if (!c.JS_IsObject(node)) return .{ .value = try identifier(s, env, code) };
    var raw: i32 = 0;
    if (c.JS_ToInt32(e.context, &raw, try field(s, node, "op")) < 0) return js.capture(e);
    const op: Op = @enumFromInt(raw);
    const args = try field(s, node, "args");
    const a = try at(s, args, 0);
    switch (op) {
        .Constant => {
            if (c.JS_IsBigInt(a) or c.JS_IsNumber(a)) {
                const bytes = try e.toString(code);
                defer e.gpa.free(bytes);
                const number = std.fmt.parseFloat(f64, bytes) catch return .{ .value = try identifier(s, env, code) };
                return .{ .value = c.JS_NewFloat64(e.context, number) };
            }
            return .{ .value = a };
        },
        .And, .Or => {
            const left = try evaluate(s, graph, nodes, env, a);
            if ((op == .And and !s.truthy(left.value)) or (op == .Or and s.truthy(left.value))) return left;
            return evaluate(s, graph, nodes, env, try at(s, args, 1));
        },
        .Not => return .{ .value = o.boolean(s, !s.truthy((try evaluate(s, graph, nodes, env, a)).value)) },
        .Ternary => return evaluate(s, graph, nodes, env, try at(s, args, if (s.truthy((try evaluate(s, graph, nodes, env, a)).value)) 1 else 2)),
        .Member => {
            const object = (try evaluate(s, graph, nodes, env, a)).value;
            return .{ .value = try keyGet(s, object, try at(s, args, 1)) };
        },
        .ArrayLiteral => return .{ .value = try evalArray(s, graph, nodes, env, a) },
        .ArrowFunction => {
            const parameters = a;
            const body = try at(s, args, 1);
            return .{ .value = try o.arrow(s, "", @intCast(try length(s, parameters)), callback, &.{ graph, nodes, env, parameters, body }) };
        },
        .Call, .New => {
            var receiver = c.pi_js_undefined();
            var function: c.JSValue = undefined;
            const callee = try keyGet(s, nodes, a);
            var member = false;
            if (c.JS_IsObject(callee)) {
                var tag: i32 = 0;
                if (c.JS_ToInt32(e.context, &tag, try field(s, callee, "op")) < 0) return js.capture(e);
                if (tag == @intFromEnum(Op.Member)) {
                    member = true;
                    const parts = try field(s, callee, "args");
                    receiver = (try evaluate(s, graph, nodes, env, try at(s, parts, 0))).value;
                    function = try keyGet(s, receiver, try at(s, parts, 1));
                }
            }
            if (!member) function = (try evaluate(s, graph, nodes, env, a)).value;
            const arguments = try evalArray(s, graph, nodes, env, try at(s, args, 1));
            if (op == .Call) return .{ .value = try o.callSpread(s, function, receiver, arguments) };
            const count = try length(s, arguments);
            const inputs = try e.gpa.alloc(c.JSValue, count);
            defer e.gpa.free(inputs);
            for (inputs, 0..) |*item, i| item.* = try at(s, arguments, @intCast(i));
            return .{ .value = try o.construct(s, function, inputs) };
        },
        .ConstDeclaration => {
            const result = (try evaluate(s, graph, nodes, env, try at(s, args, 1))).value;
            try keyPut(s, env, a, result);
            return .{ .value = c.pi_js_undefined() };
        },
        .Return => {
            const result = try evaluate(s, graph, nodes, env, a);
            return .{ .value = result.value, .returned = true };
        },
        .Statements => {
            for (0..try length(s, a)) |i| {
                const result = try evaluate(s, graph, nodes, env, try at(s, a, @intCast(i)));
                if (result.returned) return result;
            }
            return .{ .value = c.pi_js_undefined() };
        },
        .If => {
            if (s.truthy((try evaluate(s, graph, nodes, env, a)).value)) return evaluate(s, graph, nodes, env, try at(s, args, 1));
            return .{ .value = c.pi_js_undefined() };
        },
        .Every, .Some, .SomeAll, .Counted => {
            const array = (try evaluate(s, graph, nodes, env, a)).value;
            const method = try s.get(array, switch (op) {
                .Every => "every",
                .Some => "some",
                .SomeAll => "forEach",
                .Counted => "reduce",
                else => unreachable,
            });
            const params = try at(s, args, if (op == .Every) 2 else 1);
            const body = try at(s, args, if (op == .Every) 3 else 2);
            const offset = if (op == .Every) try at(s, args, 1) else c.pi_js_undefined();
            const state = try private(s);
            try set(s, state, "result", o.boolean(s, false));
            var roots = [_]c.JSValue{ graph, nodes, env, params, body, offset, state };
            const fn_value = try s.own(try e.checked(c.JS_NewCFunctionData2(e.context, arrayCallback, "", if (op == .Counted) 3 else 2, @intFromEnum(op), 7, &roots)));
            const result = try s.call(method, array, if (op == .Counted) &.{ fn_value, c.JS_NewInt32(e.context, 0) } else &.{fn_value});
            return .{ .value = if (op == .SomeAll) try field(s, state, "result") else result };
        },
        else => {},
    }
    if (op == .IsArray or op == .IsInteger or op == .IsNumber or op == .Keys or op == .Entries) {
        const receiver = try s.global(if (op == .IsArray) "Array" else if (op == .IsInteger or op == .IsNumber) "Number" else "Object");
        const method = try s.get(receiver, switch (op) {
            .IsArray => "isArray",
            .IsInteger => "isInteger",
            .IsNumber => "isFinite",
            .Keys => "getOwnPropertyNames",
            .Entries => "entries",
            else => unreachable,
        });
        const value = (try evaluate(s, graph, nodes, env, a)).value;
        return .{ .value = try s.call(method, receiver, &.{value}) };
    }
    if (op == .HasPropertyKey) {
        const raw_key = try at(s, args, 1);
        if ((try isText(s, raw_key, "\"__proto__\"")) or (try isText(s, raw_key, "\"constructor\""))) {
            const object = try s.global("Object");
            const prototype = try field(s, object, "prototype");
            const has = try field(s, prototype, "hasOwnProperty");
            const call = try field(s, has, "call");
            const value = (try evaluate(s, graph, nodes, env, a)).value;
            const key = (try evaluate(s, graph, nodes, env, raw_key)).value;
            return .{ .value = try s.call(call, has, &.{ value, key }) };
        }
        const key = (try evaluate(s, graph, nodes, env, raw_key)).value;
        const value = (try evaluate(s, graph, nodes, env, a)).value;
        return .{ .value = o.boolean(s, try js.hasKey(e, value, key)) };
    }
    if (op == .IsConstructor or op == .IsMinLength or op == .IsMaxLength or op == .IsDeepEqual or op == .MultipleOf) {
        const receiver = try namespace(s, graph, "guard/guard.mjs");
        const method = try s.get(receiver, switch (op) {
            .IsConstructor => "IsConstructor",
            .IsMinLength => "IsMinLength",
            .IsMaxLength => "IsMaxLength",
            .IsDeepEqual => "IsDeepEqual",
            .MultipleOf => "IsMultipleOf",
            else => unreachable,
        });
        const value = (try evaluate(s, graph, nodes, env, a)).value;
        if (op == .IsConstructor) return .{ .value = try s.call(method, receiver, &.{value}) };
        const right = (try evaluate(s, graph, nodes, env, try at(s, args, 1))).value;
        return .{ .value = try s.call(method, receiver, &.{ value, right }) };
    }
    const left = (try evaluate(s, graph, nodes, env, a)).value;
    if (op == .IsBigInt or op == .IsBoolean or op == .IsObject or op == .IsString or op == .IsSymbol or op == .IsFunction) {
        const kind = try o.typeOf(s, left);
        const expected = switch (op) {
            .IsBigInt => "bigint",
            .IsBoolean => "boolean",
            .IsObject => "object",
            .IsString => "string",
            .IsSymbol => "symbol",
            .IsFunction => "function",
            else => unreachable,
        };
        const same = try isText(s, kind, expected);
        if (op == .IsObject and same) {
            const second = (try evaluate(s, graph, nodes, env, a)).value;
            return .{ .value = o.boolean(s, !c.JS_IsNull(second)) };
        }
        return .{ .value = o.boolean(s, same) };
    }
    if (op == .IsNull or op == .IsUndefined) return .{ .value = o.boolean(s, if (op == .IsNull) c.JS_IsNull(left) else c.JS_IsUndefined(left)) };
    const right = (try evaluate(s, graph, nodes, env, try at(s, args, 1))).value;
    if (op == .IsEqual) return .{ .value = o.boolean(s, s.equal(left, right)) };
    if (op == .IsGreaterThan or op == .IsLessThan or op == .IsLessEqualThan or op == .IsGreaterEqualThan) return .{ .value = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, switch (op) {
        .IsGreaterThan => 6,
        .IsLessThan => 4,
        .IsLessEqualThan => 5,
        .IsGreaterEqualThan => 7,
        else => unreachable,
    }, left, right))) };
    return error.NativeTypeBoxUnknownIrOperation;
}
fn compiledCheck(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return check(e, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0..5]) catch |err| @import("native_sdk.zig").fail(e, err);
}
fn check(e: *Engine, input: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const env = try o.frame(&s, roots[2]);
    try set(&s, env, "value", input);
    if (s.truthy(roots[4])) {
        const ctor = try o.lookup(&s, env, "CheckContext");
        const context = try o.construct(&s, ctor, &.{ try s.object(), try s.object() });
        try set(&s, env, "context", context);
    }
    const result = try evaluate(&s, roots[0], roots[1], env, roots[3]);
    return c.JS_DupValue(e.context, result.value);
}
/// Lower the fixed factory scaffold emitted by actual CreateCode. Expression
/// nodes come from the native EmitGuard build, not from parsing/evaluating JS.
pub fn createCheck(e: *Engine, graph: c.JSValue, built: c.JSValue, code: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const builds = try field(&s, graph, "irBuilds");
    const nodes = try s.call(try field(&s, graph, "irBuildGet"), builds, &.{built});
    if (!c.JS_IsObject(nodes)) return error.NativeTypeBoxBuildIrUnavailable;
    const external_for_name = try s.invoke(built, "External", &.{});
    const external_name = try field(&s, external_for_name, "identifier");
    const context_ctor = try field(&s, try namespace(&s, graph, "schema/engine/index.mjs"), "CheckContext");
    const guard = try namespace(&s, graph, "guard/guard.mjs");
    const format = try field(&s, try namespace(&s, graph, "format/index.mjs"), "Format");
    const hashing = try field(&s, try namespace(&s, graph, "system/hashing/index.mjs"), "Hashing");
    const external_for_values = try s.invoke(built, "External", &.{});
    const external_values = try field(&s, external_for_values, "variables");
    const env = try o.frame(&s, c.pi_js_null());
    try set(&s, env, "CheckContext", context_ctor);
    try set(&s, env, "Guard", guard);
    try set(&s, env, "Format", format);
    try set(&s, env, "Hashing", hashing);
    try keyPut(&s, env, external_name, external_values);
    const source = try e.toString(code);
    defer e.gpa.free(source);
    const separator = "; return (value) => { ";
    const boundary = std.mem.lastIndexOf(u8, source, separator) orelse return error.NativeTypeBoxModifiedFactoryScaffold;
    var functions = std.mem.splitSequence(u8, source[0..boundary], ";\n");
    while (functions.next()) |declaration| {
        if (declaration.len == 0) continue;
        const expression = try s.text(declaration);
        const node = try keyGet(&s, nodes, expression);
        if (!c.JS_IsObject(node)) return error.NativeTypeBoxModifiedFunctionCode;
        _ = try evaluate(&s, graph, nodes, env, expression);
    }
    if (!std.mem.endsWith(u8, source, " }")) return error.NativeTypeBoxModifiedFactoryScaffold;
    const body = source[boundary + separator.len .. source.len - 2];
    const prefix = "const context = new CheckContext({}, {}); return ";
    const use_unevaluated = std.mem.startsWith(u8, body, prefix);
    const entry = if (use_unevaluated) body[prefix.len..] else if (std.mem.startsWith(u8, body, "return ")) body[7..] else return error.NativeTypeBoxModifiedFactoryScaffold;
    const expression = try s.text(entry);
    if (!c.JS_IsObject(try keyGet(&s, nodes, expression))) return error.NativeTypeBoxModifiedEntryCode;
    return c.JS_DupValue(e.context, try o.arrow(&s, "", 1, compiledCheck, &.{ graph, nodes, env, expression, o.boolean(&s, use_unevaluated) }));
}
