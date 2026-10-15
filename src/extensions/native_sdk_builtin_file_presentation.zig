//! Private composition of the actual read/write/edit rendering bodies.
//! Syntax must be installed by the real highlighter owner. No syntax substitute.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const themed = @import("native_sdk_themed_highlight.zig");
const read = @import("native_sdk_builtin_read_renderers.zig");
const write = @import("native_sdk_builtin_write_renderers.zig");
const edit = @import("native_sdk_builtin_edit_renderers.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const Kind = enum(c_int) { read_call, read_result, write_call, write_result, edit_call, edit_result, render_diff };
const highlighter: write.Highlighter = .{ .language = themed.language, .highlight = themed.highlight };
fn readme(engine: *em.Engine) !c.JSValue {
    return @import("native_sdk_prompt_render.zig").resolvePackagePath(engine, "README.md");
}
fn arg(argc: c_int, argv: [*c]c.JSValue, index: usize) c.JSValue {
    return if (index < @as(usize, @intCast(argc))) argv[index] else c.pi_js_undefined();
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const a = arg(argc, argv, 0);
    const b = arg(argc, argv, 1);
    const d = arg(argc, argv, 2);
    const e = arg(argc, argv, 3);
    const read_api: read.Runtime = .{ .highlighter = highlighter, .get_readme = readme };
    const result = switch (@as(Kind, @enumFromInt(magic))) {
        .read_call => read.renderCall(engine, read_api, a, b, d),
        .read_result => read.renderResult(engine, read_api, a, b, d, e),
        .write_call => write.renderCall(engine, highlighter, a, b, d),
        .write_result => write.renderResult(engine, a, d, e),
        .edit_call => edit.renderCall(engine, .{ .compute_edits_diff = roots[0], .render_diff = roots[1] }, a, b, d),
        .edit_result => edit.renderResult(engine, .{ .compute_edits_diff = roots[0], .render_diff = roots[1] }, a, d, e),
        .render_diff => liveDiff(engine, a),
    };
    return result catch |err| sdk.fail(engine, err);
}
fn liveDiff(engine: *em.Engine, diff: c.JSValue) !c.JSValue {
    const runtime = engine.native_module_values.get("pi-coding-agent") orelse return error.NativeThemeRuntimeRequired;
    const theme = try sdk.get(engine, runtime, "theme");
    defer engine.freeValue(theme);
    return @import("native_sdk_render_diff.zig").render(engine, diff, theme);
}
fn function(scope: *Scope, name: [*:0]const u8, arity: c_int, kind: Kind, roots: []const c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, name, arity, @intFromEnum(kind), @intCast(roots.len), @constCast(roots.ptr))));
}
/// A real async access/readFile/normalize/apply/display implementation is rooted
/// by both edit methods. Read/write remain dependent on installed native syntax.
pub fn create(engine: *em.Engine, name: []const u8) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const methods = try scope.object();
    const call_kind: Kind = if (std.mem.eql(u8, name, "read")) .read_call else if (std.mem.eql(u8, name, "write")) .write_call else if (std.mem.eql(u8, name, "edit")) .edit_call else return error.BuiltinPresentationBodyUnavailable;
    var roots: [2]c.JSValue = undefined;
    const captured: []const c.JSValue = if (call_kind == .edit_call) selected: {
        roots[0] = try scope.own(try @import("native_sdk_edit_preview.zig").createNative(engine));
        roots[1] = try function(&scope, "renderDiff", 1, .render_diff, &.{});
        break :selected &roots;
    } else &.{};
    try scope.put(methods, "renderCall", try function(&scope, "renderCall", 3, call_kind, captured));
    const result_kind: Kind = switch (call_kind) {
        .read_call => .read_result,
        .write_call => .write_result,
        .edit_call => .edit_result,
        else => unreachable,
    };
    try scope.put(methods, "renderResult", try function(&scope, "renderResult", 4, result_kind, captured));
    return c.JS_DupValue(engine.context, methods);
}
pub fn attach(engine: *em.Engine, definition: c.JSValue, name: []const u8) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const methods = try scope.own(try create(engine, name));
    inline for (.{ "renderCall", "renderResult" }) |method| try scope.put(definition, method, try scope.get(methods, method));
}
