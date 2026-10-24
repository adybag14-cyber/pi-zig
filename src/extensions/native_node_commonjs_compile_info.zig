//! Actual Info compiler completion ownership. Requires the separately reviewed
//! lexer-metadata C ABI; no code-cache, parser result or metadata is synthesized.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const body = @import("native_node_commonjs_body_compiler.zig");
const allocation = @import("native_async_body.zig");
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
fn throwOwned(engine: *v.em.Engine, reason: c.JSValue, generation: u64) anyerror {
    defer engine.freeValue(reason);
    allocation.rethrowRecognizedAllocation(engine, reason, generation) catch |err| return err;
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))) catch |err| return err;
    return error.ActualCompileInfoThrowDidNotFail;
}
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
    try boundary.finishMany(host_error, &scope, &outputs);
    if (syntax) |category| return .{ .syntax = .{ .reason = outputs[0], .category = category } };
    return .{ .compiled = .{ .value = outputs[0], .source_url = outputs[1], .source_map_url = outputs[2] } };
}
fn performBody(boundary: *Boundary, engine: *v.em.Engine, source: c.JSValue, filename: c.JSValue, script_mode: bool) !Completion {
    // Enter the caller-stable native frame before the real compiler. A retained
    // producer is current even after its raw VM exception was taken elsewhere.
    try boundary.checkCurrent();
    const generation = engine.native_allocation_generation;
    if (c.JS_HasException(engine.context)) return throwOwned(engine, c.JS_GetException(engine.context), generation);
    var url = c.pi_js_undefined();
    var map = c.pi_js_undefined();
    var category: c_int = 0;
    const value = if (script_mode) JS_PiCompileCommonJSScriptInfo(engine.context, source, filename, &url, &map) else JS_PiCompileCJSFunctionInfo(engine.context, source, filename, &category, &url, &map);
    if (!c.JS_IsException(value) and !c.JS_HasException(engine.context)) {
        if (category != 0) {
            engine.freeValue(value); engine.freeValue(url); engine.freeValue(map);
            return error.ActualCompileInfoAbiMismatch;
        }
        return .{ .compiled = .{ .value = value, .source_url = url, .source_map_url = map } };
    }
    if (!c.JS_HasException(engine.context)) {
        engine.freeValue(value); engine.freeValue(url); engine.freeValue(map);
        return error.MissingActualCompileInfoReason;
    }
    const reason = c.JS_GetException(engine.context); // Own before all output cleanup.
    errdefer engine.freeValue(reason);
    engine.freeValue(value); engine.freeValue(url); engine.freeValue(map);
    try allocation.rethrowRecognizedAllocation(engine, reason, generation);
    if (c.JS_IsUncatchableError(reason) or script_mode or category == 0)
        return throwOwned(engine, c.JS_DupValue(engine.context, reason), generation);
    const syntax: body.SyntaxCategory = switch (category) {
        1 => .ordinary, 2 => .direct_module, 3 => .module_probe_required,
        else => return error.ActualCompileInfoAbiMismatch,
    };
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
    try boundary.finishMany(host_error, &scope, &values);
    return values[0];
}
