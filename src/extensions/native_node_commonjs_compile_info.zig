//! Actual Info compiler completion ownership. Requires the separately reviewed
//! lexer-metadata C ABI; no code-cache, parser result or metadata is synthesized.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const body = @import("native_node_commonjs_body_compiler.zig");
const Boundary = @import("native_node_commonjs_owned_boundary.zig").Boundary;
extern fn JS_PiCompileCJSFunctionInfo(?*c.JSContext, c.JSValue, c.JSValue, *c_int, *c.JSValue, *c.JSValue) c.JSValue;
extern fn JS_PiCompileCommonJSScriptInfo(?*c.JSContext, c.JSValue, c.JSValue, *c.JSValue, *c.JSValue) c.JSValue;
pub const Info = struct {
    value: c.JSValue,
    source_url: c.JSValue,
    source_map_url: c.JSValue,
    pub fn deinit(self: Info, engine: *v.em.Engine) void {
        engine.freeValue(self.value); engine.freeValue(self.source_url); engine.freeValue(self.source_map_url);
    }
};
pub const Completion = union(enum) {
    compiled: Info,
    syntax: body.Syntax,
    pub fn deinit(self: Completion, engine: *v.em.Engine) void {
        switch (self) { .compiled => |info| info.deinit(engine), .syntax => |syntax| engine.freeValue(syntax.reason) }
    }
};
fn perform(engine: *v.em.Engine, source: c.JSValue, filename: c.JSValue, script_mode: bool) !Completion {
    var boundary = Boundary.begin(engine);
    var scope: v.Scope = .{ .engine = engine };
    var outputs = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined() };
    var syntax: ?body.SyntaxCategory = null;
    var host_error: ?anyerror = null;
    if (performBody(&boundary, engine, source, filename, script_mode)) |completion| {
        switch (completion) {
            .compiled => |info| outputs = .{ info.value, info.source_url, info.source_map_url },
            .syntax => |failure| { outputs[0] = failure.reason; syntax = failure.category; },
        }
    } else |err| host_error = err;
    try boundary.finishManyPending(host_error, &scope, &outputs);
    if (syntax) |category| return .{ .syntax = .{ .reason = outputs[0], .category = category } };
    return .{ .compiled = .{ .value = outputs[0], .source_url = outputs[1], .source_map_url = outputs[2] } };
}
fn performBody(boundary: *Boundary, engine: *v.em.Engine, source: c.JSValue, filename: c.JSValue, script_mode: bool) !Completion {
    // Own the actual native invocation before entering either real compiler.
    try boundary.checkCurrent();
    var url = c.pi_js_undefined();
    var map = c.pi_js_undefined();
    var category: c_int = 0;
    var value = if (script_mode)
        JS_PiCompileCommonJSScriptInfo(engine.context, source, filename, &url, &map)
    else
        JS_PiCompileCJSFunctionInfo(engine.context, source, filename, &category, &url, &map);
    if (!c.JS_IsException(value) and !c.JS_HasException(engine.context)) {
        if (category != 0) {
            boundary.release(&value);
            boundary.release(&url);
            boundary.release(&map);
            return error.ActualCompileInfoAbiMismatch;
        }
        return .{ .compiled = .{ .value = value, .source_url = url, .source_map_url = map } };
    }
    // Transfer the actual value/class pair before retiring any metadata output.
    // The same stable owner records private history even if cleanup replaces it.
    boundary.checkCurrent() catch {};
    boundary.release(&value);
    boundary.release(&url);
    boundary.release(&map);
    const reason = boundary.reason orelse return error.MissingActualCompileInfoReason;
    if (!boundary.reason_pending) return error.MissingActualCompileInfoReason;
    if (boundary.terminated or c.JS_PiIsExecutionTermination(reason))
        return error.ExecutionTerminated;
    if (boundary.fatal or script_mode or category == 0)
        return error.JavaScriptException;
    const syntax: body.SyntaxCategory = switch (category) {
        1 => .ordinary, 2 => .direct_module, 3 => .module_probe_required,
        else => return error.ActualCompileInfoAbiMismatch,
    };
    // Only this selected ordinary syntax completion becomes returned DATA.
    boundary.reason = null;
    boundary.reason_pending = false;
    boundary.fatal = false;
    return .{ .syntax = .{ .reason = reason, .category = syntax } };
}
pub fn compile(engine: *v.em.Engine, source: c.JSValue, filename: c.JSValue) !Completion { return perform(engine, source, filename, false); }
pub fn script(engine: *v.em.Engine, source: c.JSValue, filename: c.JSValue) !Info {
    return switch (try perform(engine, source, filename, true)) { .compiled => |info| info, .syntax => unreachable };
}
pub fn run(engine: *v.em.Engine, bytecode: c.JSValue) !c.JSValue {
    var boundary = Boundary.begin(engine);
    var scope: v.Scope = .{ .engine = engine };
    var values = [_]c.JSValue{c.pi_js_undefined()};
    var host_error: ?anyerror = null;
    // Start/check before guest script execution, retaining any genuine native
    // producer until the same boundary finishes all returned-value retirement.
    if (boundary.checkCurrent()) |_| {
        values[0] = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, bytecode));
        if (c.JS_IsException(values[0]) and !c.JS_HasException(engine.context)) host_error = error.MissingActualCompileInfoRunReason;
    } else |err| host_error = err;
    try boundary.finishManyPending(host_error, &scope, &values);
    return values[0];
}


test "native CommonJS compiler owners preserve genuine exhausted heap primitive fatal" {
    const std = @import("std");
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const Helpers = struct {
        fn text(host: *v.em.Engine, bytes: []const u8) !c.JSValue {
            return host.checked(c.JS_NewStringLen(host.context, bytes.ptr, bytes.len));
        }
        fn bodyCompile(host: *v.em.Engine, source_value: c.JSValue, name: c.JSValue) anyerror!void {
            const result = try body.compile(host, source_value, name);
            result.deinit(host);
        }
        fn moduleProbe(host: *v.em.Engine, source_value: c.JSValue, name: c.JSValue) anyerror!void {
            const result = try body.probe(host, source_value, name);
            result.deinit(host);
        }
        fn infoCompile(host: *v.em.Engine, source_value: c.JSValue, name: c.JSValue) anyerror!void {
            const result = try compile(host, source_value, name);
            result.deinit(host);
        }
        fn scriptCompile(host: *v.em.Engine, source_value: c.JSValue, name: c.JSValue) anyerror!void {
            const result = try script(host, source_value, name);
            result.deinit(host);
        }
    };
    const source_value = try Helpers.text(engine, "const value = 1;");
    defer engine.freeValue(source_value);
    const filename = try Helpers.text(engine, "primitive-compiler.js");
    defer engine.freeValue(filename);
    const operations = [_]*const fn (*v.em.Engine, c.JSValue, c.JSValue) anyerror!void{
        Helpers.bodyCompile, Helpers.moduleProbe, Helpers.infoCompile, Helpers.scriptCompile,
    };
    for (operations) |operation| {
        const before = c.JS_PiOutOfMemoryOccurrence(engine.runtime);
        c.JS_SetMemoryLimit(engine.runtime, 1);
        const outcome = operation(engine, source_value, filename);
        c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
        try std.testing.expectError(error.JavaScriptException, outcome);
        try std.testing.expect(c.JS_PiOutOfMemoryOccurrence(engine.runtime) > before);
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expect(c.JS_HasException(engine.context));
        try std.testing.expect(c.JS_PiIsPendingUncatchable(engine.context));
        var generic_fatal: bool = false;
        const reason = c.JS_PiGetExceptionWithFatal(engine.context, &generic_fatal);
        defer engine.freeValue(reason);
        try std.testing.expect(generic_fatal and c.JS_IsNull(reason));
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
}

test "native CommonJS ordinary syntax remains DATA and script null remains actual" {
    const std = @import("std");
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const Helpers = struct {
        fn text(host: *v.em.Engine, bytes: []const u8) !c.JSValue {
            return host.checked(c.JS_NewStringLen(host.context, bytes.ptr, bytes.len));
        }
    };
    const invalid = try Helpers.text(engine, "const = ;");
    defer engine.freeValue(invalid);
    const filename = try Helpers.text(engine, "ordinary-compiler.js");
    defer engine.freeValue(filename);

    const compiled_body = try body.compile(engine, invalid, filename);
    defer compiled_body.deinit(engine);
    try std.testing.expect(compiled_body == .syntax);
    try std.testing.expectEqual(body.SyntaxCategory.ordinary, compiled_body.syntax.category);
    try std.testing.expect(!c.JS_HasException(engine.context));
    const probed = try body.probe(engine, invalid, filename);
    defer probed.deinit(engine);
    try std.testing.expect(probed == .syntax);
    try std.testing.expect(!c.JS_HasException(engine.context));
    const compiled_info = try compile(engine, invalid, filename);
    defer compiled_info.deinit(engine);
    try std.testing.expect(compiled_info == .syntax);
    try std.testing.expectEqual(body.SyntaxCategory.ordinary, compiled_info.syntax.category);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(engine.native_fatal_invocation == null);

    const throwing_source = try Helpers.text(engine, "throw null;");
    defer engine.freeValue(throwing_source);
    const compiled_script = try script(engine, throwing_source, filename);
    defer compiled_script.deinit(engine);
    try std.testing.expectError(error.JavaScriptException, run(engine, compiled_script.value));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expect(c.JS_HasException(engine.context));
    var generic_fatal: bool = true;
    const reason = c.JS_PiGetExceptionWithFatal(engine.context, &generic_fatal);
    defer engine.freeValue(reason);
    try std.testing.expect(!generic_fatal and c.JS_IsNull(reason));
    try std.testing.expect(!c.JS_PiIsPendingUncatchable(engine.context));
}
