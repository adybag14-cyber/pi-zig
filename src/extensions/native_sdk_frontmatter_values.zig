//! Real frontmatter/YAML values for Source resource parsers. Grammar, schema,
//! alias accounting and collection-key normalization reuse the native C parser.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const temp = @import("native_sdk_prompt_scope.zig");
const frontmatter = @import("../coding_agent/frontmatter.zig");
const yaml = frontmatter.yaml;
const c = em.c;
pub const Result = struct { frontmatter: c.JSValue, body: c.JSValue };
const Graph = struct {
    scope: *Scope,
    memo: std.AutoHashMapUnmanaged(*const yaml.Value, c.JSValue) = .empty,
    fn deinit(self: *Graph) void {
        self.memo.deinit(self.scope.engine.gpa);
    }
    fn value(self: *Graph, node: *const yaml.Value) anyerror!c.JSValue {
        if (self.memo.get(node)) |existing| return existing;
        const scope = self.scope;
        const engine = scope.engine;
        const result = switch (node.data) {
            .null => c.pi_js_null(),
            .boolean => |input| c.pi_js_bool(engine.context, @intFromBool(input)),
            .number => |input| c.JS_NewFloat64(engine.context, input),
            .string => |input| try string(scope, input),
            .timestamp => |input| try scope.own(try js.builtin(engine, "Date", &.{c.JS_NewFloat64(engine.context, input)})),
            .binary => |input| bytes: {
                try @import("node_buffer.zig").install(engine);
                break :bytes try scope.own(try @import("node_buffer.zig").fromBytes(engine, input));
            },
            .merge => try scope.invoke(try scope.global("Symbol"), "for", &.{try scope.text("<<")}),
            .sequence => try scope.array(),
            .mapping => try scope.object(),
            .set => try scope.own(try js.builtin(engine, "Set", &.{})),
            .ordered_mapping => try scope.own(try js.builtin(engine, "Map", &.{})),
        };
        // Insert before visiting children: aliases and recursive YAML values
        // retain actual JS graph identity rather than cloning metadata trees.
        try self.memo.put(engine.gpa, node, result);
        switch (node.data) {
            .sequence => |items| for (items, 0..) |item, index| try scope.index(result, @intCast(index), try self.value(item)),
            .mapping => |pairs| for (pairs) |pair| {
                const key = try self.value(pair.key);
                const item = try self.value(pair.value);
                const atom = try js.atom(engine, key);
                defer c.JS_FreeAtom(engine.context, atom);
                if (c.JS_DefinePropertyValue(engine.context, result, atom, c.JS_DupValue(engine.context, item), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
            },
            .ordered_mapping => |pairs| for (pairs) |pair| {
                const set = try scope.get(result, "set");
                _ = try scope.call(set, result, &.{ try self.value(pair.key), try self.value(pair.value) });
            },
            .set => |items| for (items) |item| {
                const add = try scope.get(result, "add");
                _ = try scope.call(add, result, &.{try self.value(item)});
            },
            else => {},
        }
        return result;
    }
};
fn string(scope: *Scope, input: []const u8) !c.JSValue {
    const units = try std.unicode.wtf8ToWtf16LeAlloc(scope.engine.gpa, input);
    defer scope.engine.gpa.free(units);
    return scope.own(try @import("native_utf16.zig").string(scope.engine, units));
}
fn throwDiagnostic(scope: *Scope, source: []const u8, diagnostic: yaml.Diagnostic) anyerror {
    const engine = scope.engine;
    const message = try frontmatter.prettyUnits(engine.gpa, source, diagnostic);
    defer engine.gpa.free(message);
    const reason = try scope.own(try engine.checked(c.JS_NewError(engine.context)));
    try scope.put(reason, "name", try scope.text(diagnostic.name));
    try scope.put(reason, "message", try scope.own(try @import("native_utf16.zig").string(engine, message)));
    if (diagnostic.code) |code| try scope.put(reason, "code", try scope.text(code));
    _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
    unreachable;
}
fn regex(scope: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ try scope.text(pattern), try scope.text("g") };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
pub fn parseValue(scope: *Scope, input: c.JSValue) !Result {
    const stripped = if (scope.truthy(try scope.invoke(input, "startsWith", &.{try scope.text("\xef\xbb\xbf")}))) try scope.invoke(input, "slice", &.{c.JS_NewInt32(scope.engine.context, 1)}) else input;
    const replace_first = try scope.get(stripped, "replace");
    const unix = try scope.call(replace_first, stripped, &.{ try regex(scope, "\\r\\n"), try scope.text("\n") });
    const replace_second = try scope.get(unix, "replace");
    const normalized = try scope.call(replace_second, unix, &.{ try regex(scope, "\\r"), try scope.text("\n") });
    if (!scope.truthy(try scope.invoke(normalized, "startsWith", &.{try scope.text("---")}))) return .{ .frontmatter = try scope.object(), .body = normalized };
    const end = try scope.invoke(normalized, "indexOf", &.{ try scope.text("\n---"), c.JS_NewInt32(scope.engine.context, 3) });
    if (scope.equal(end, c.JS_NewInt32(scope.engine.context, -1))) return .{ .frontmatter = try scope.object(), .body = normalized };
    const yaml_string = try scope.invoke(normalized, "slice", &.{ c.JS_NewInt32(scope.engine.context, 4), end });
    const start = try scope.concat(end, c.JS_NewInt32(scope.engine.context, 4));
    const body = try scope.invoke(try scope.invoke(normalized, "slice", &.{start}), "trim", &.{});
    if (!scope.truthy(yaml_string)) return .{ .frontmatter = try scope.object(), .body = body };
    if (!c.JS_IsString(yaml_string)) return js.typeError(scope.engine, "source is not a string");
    const bytes = try scope.engine.toString(yaml_string);
    defer scope.engine.gpa.free(bytes);
    var parsed = try yaml.parse(scope.engine.gpa, bytes);
    defer parsed.deinit();
    if (parsed.diagnostic) |diagnostic| return throwDiagnostic(scope, bytes, diagnostic);
    var graph: Graph = .{ .scope = scope };
    defer graph.deinit();
    const decoded = if (parsed.root) |root| try graph.value(root) else c.pi_js_null();
    return .{
        .frontmatter = if (temp.nullish(decoded)) try scope.object() else decoded,
        .body = body,
    };
}
/// Returned JS values belong to the caller's Scope; parsed C storage can be
/// released immediately after conversion without breaking aliases or strings.
pub fn parse(scope: *Scope, input: []const u8) !Result {
    return parseValue(scope, try string(scope, input));
}
pub fn create(engine: *em.Engine) !c.JSValue {
    return engine.checked(c.JS_NewCFunction(engine.context, invoke, "parseFrontmatter", 1));
}
fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return called(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn called(engine: *em.Engine, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const parsed = try parseValue(&scope, input);
    const result = try scope.object();
    try scope.put(result, "frontmatter", parsed.frontmatter);
    try scope.put(result, "body", parsed.body);
    return c.JS_DupValue(engine.context, result);
}
