//! Existing native YAML parser/value graph, separated from frontmatter's
//! actual Source call chain. Grammar, schema, aliases and diagnostics remain
//! the real native C implementation; graph guest operations share AF33/C435.
const std = @import("std");
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const frontmatter = @import("../coding_agent/frontmatter.zig");
const yaml = frontmatter.yaml;
const Ops = @import("native_sdk_catalog_values.zig").Ops;

const Graph = struct {
    scope: *h.Scope,
    memo: std.AutoHashMapUnmanaged(*const yaml.Value, c.JSValue) = .empty,
    fn deinit(self: *Graph) void { self.memo.deinit(self.scope.engine.gpa); }
    fn value(self: *Graph, node: *const yaml.Value) anyerror!c.JSValue {
        if (self.memo.get(node)) |existing| return existing;
        const s = self.scope;
        const engine = s.engine;
        const result = switch (node.data) {
            .null => c.pi_js_null(),
            .boolean => |input| v.boolean(s, input),
            .number => |input| v.number(s, input),
            .string => |input| try string(s, input),
            .timestamp => |input| try v.construct(s, try v.global(s, "Date"), &.{v.number(s, input)}),
            .binary => |input| bytes: {
                try @import("node_buffer.zig").install(engine);
                break :bytes try v.own(s, try @import("node_buffer.zig").fromBytes(engine, input));
            },
            .merge => try v.own(s, try h.expression(engine, mergeSymbol, .{})),
            .sequence => try v.array(s),
            .mapping => try v.object(s),
            .set => try v.construct(s, try v.global(s, "Set"), &.{}),
            .ordered_mapping => try v.construct(s, try v.global(s, "Map"), &.{}),
        };
        // Insert before walking children: aliases retain the exact same real
        // objects, including recursive collections.
        try self.memo.put(engine.gpa, node, result);
        switch (node.data) {
            .sequence => |items| for (items, 0..) |item, index| {
                try v.index(s, result, @intCast(index), try self.value(item));
            },
            .mapping => |pairs| for (pairs) |pair| {
                const key = try self.value(pair.key);
                const item = try self.value(pair.value);
                try defineKey(s, result, key, item);
            },
            .ordered_mapping => |pairs| for (pairs) |pair| {
                const setter = try v.get(s, result, "set");
                _ = try v.call(s, setter, result, &.{try self.value(pair.key), try self.value(pair.value)});
            },
            .set => |items| for (items) |item| {
                const add = try v.get(s, result, "add");
                _ = try v.call(s, add, result, &.{try self.value(item)});
            },
            else => {},
        }
        return result;
    }
};
fn mergeSymbol(s: *h.Scope) !c.JSValue {
    const receiver = try v.global(s, "Symbol");
    const method = try v.get(s, receiver, "for");
    return v.duplicate(s, try v.call(s, method, receiver, &.{try v.text(s, "<<")}));
}
fn defineKey(s: *h.Scope, target: c.JSValue, key: c.JSValue, item: c.JSValue) !void {
    var coercion: v.guest.Boundary = .{ .engine = s.engine };
    try coercion.begin();
    const atom = c.JS_ValueToAtom(s.engine.context, key);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try coercion.finishStatus(if (atom == c.JS_ATOM_NULL) -1 else 0);
    var definition: v.guest.Boundary = .{ .engine = s.engine };
    try definition.begin();
    return definition.finishStatus(c.JS_DefinePropertyValue(s.engine.context, target, atom, v.duplicate(s, item), c.JS_PROP_C_W_E));
}
pub fn string(s: *h.Scope, input: []const u8) !c.JSValue {
    const units = try std.unicode.wtf8ToWtf16LeAlloc(s.engine.gpa, input);
    defer s.engine.gpa.free(units);
    return stringUnits(s, units);
}
fn stringUnits(s: *h.Scope, units: []const u16) !c.JSValue {
    var ops: Ops = .{ .s = s };
    const generation = try ops.beforeAllocation();
    return ops.allocation(c.JS_NewStringUTF16(s.engine.context, units.ptr, units.len), generation);
}
fn throwDiagnostic(s: *h.Scope, source: []const u8, diagnostic: yaml.Diagnostic) anyerror {
    const message = try frontmatter.prettyUnits(s.engine.gpa, source, diagnostic);
    defer s.engine.gpa.free(message);
    var ops: Ops = .{ .s = s };
    const generation = try ops.beforeAllocation();
    const reason = try ops.allocation(c.JS_NewError(s.engine.context), generation);
    try v.put(s, reason, "name", try v.text(s, diagnostic.name));
    try v.put(s, reason, "message", try stringUnits(s, message));
    if (diagnostic.code) |code| try v.put(s, reason, "code", try v.text(s, code));
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    _ = try boundary.finishValue(s, c.JS_Throw(s.engine.context, v.duplicate(s, reason)));
    unreachable;
}
/// The genuine parser import consumed by frontmatter. This private callable
/// is the existing one-argument C parser route, not a full yaml namespace.
pub fn create(engine: *h.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    return h.expression(engine, createBody, .{});
}
fn createBody(s: *h.Scope) !c.JSValue {
    return v.duplicate(s, try v.ordinary(s, "parse", 3, parseCall, &.{}));
}
fn parseCall(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return parse(engine, v.arg(args, 0));
}
pub fn parse(engine: *h.Engine, input: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    return h.expression(engine, parseBody, .{input});
}
fn parseBody(s: *h.Scope, input: c.JSValue) !c.JSValue {
    // Preserve the existing native YAML input/diagnostic contract. This module
    // does not claim the entire public yaml package or a replacement JS host.
    if (!c.JS_IsString(input)) return v.typeError(s, "source is not a string");
    const bytes = try s.engine.toString(input);
    defer s.engine.gpa.free(bytes);
    var parsed = try yaml.parse(s.engine.gpa, bytes);
    defer parsed.deinit();
    if (parsed.diagnostic) |diagnostic| return throwDiagnostic(s, bytes, diagnostic);
    var graph: Graph = .{ .scope = s };
    defer graph.deinit();
    return if (parsed.root) |root| v.duplicate(s, try graph.value(root)) else c.pi_js_null();
}
