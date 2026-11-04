//! Actual linked-VM CJS/probe completions, consumed by the Node wrapSafe owner.
//! These are raw parser/compiler completions, not a fabricated contextify record.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const functions = @import("native_node_module_callable.zig");
const Boundary = @import("native_node_commonjs_owned_boundary.zig").Boundary;

// Additive compiler ABI from the separately sealed direct-C implementation.
// No C/H is copied into this 1fd8-based product worktree. Composition and actual
// native qualification of that ABI remain explicit prerequisites.
extern fn JS_PiCompileCJSFunction(?*c.JSContext, c.JSValue, c.JSValue, *c_int) c.JSValue;
extern fn JS_PiParseModuleSyntax(?*c.JSContext, c.JSValue, c.JSValue, *c_uint, *c_int) c_int;

pub const SyntaxCategory = enum { ordinary, direct_module, module_probe_required };
pub const Syntax = struct { reason: c.JSValue, category: SyntaxCategory };
/// Move-only ownership: exactly one deinit, or transfer the contained value.
pub const Completion = union(enum) {
    function: c.JSValue,
    syntax: Syntax,
    pub fn deinit(self: Completion, engine: *v.em.Engine) void {
        switch (self) {
            .function => |value| engine.freeValue(value),
            .syntax => |value| engine.freeValue(value.reason),
        }
    }
};
pub const Probe = union(enum) {
    parsed: c_uint,
    syntax: c.JSValue,
    pub fn deinit(self: Probe, engine: *v.em.Engine) void {
        if (self == .syntax) engine.freeValue(self.syntax);
    }
};
pub const static_import_export: c_uint = 1;
pub const import_meta: c_uint = 2;
pub const top_level_await: c_uint = 4;

/// Consume only a selected actual ordinary compiler event as syntax DATA.
/// Generic fatal policy and observed private unwind never enter this route.
fn takeSyntaxReason(boundary: *Boundary) !c.JSValue {
    if (boundary.terminated) return error.ExecutionTerminated;
    if (boundary.fatal) return error.JavaScriptException;
    const reason = boundary.reason orelse return error.MissingActualCompilerCurrentReason;
    if (!boundary.reason_pending) return error.MissingActualCompilerCurrentReason;
    if (c.JS_PiIsExecutionTermination(reason)) return error.ExecutionTerminated;
    boundary.reason = null;
    boundary.reason_pending = false;
    boundary.fatal = false;
    return reason;
}

fn observeFailure(boundary: *Boundary, result: *c.JSValue) !void {
    // checkCurrent takes the value and policy together into the stable owner.
    // It is deliberately observed before any returned root is retired.
    boundary.checkCurrent() catch {};
    boundary.release(result);
    if (boundary.reason == null or !boundary.reason_pending)
        return error.MissingActualCompilerCurrentReason;
    if (boundary.terminated) return error.ExecutionTerminated;
    if (boundary.fatal) return error.JavaScriptException;
    if (c.JS_PiIsExecutionTermination(boundary.reason.?)) return error.ExecutionTerminated;
}

/// Compile the original body with five real formal parameters and true EOF.
/// The local stable owner spans the actual C compiler and every result root.
pub fn compile(engine: *v.em.Engine, content: c.JSValue, physical_filename: c.JSValue) !Completion {
    var boundary = Boundary.begin(engine);
    var scope: v.Scope = .{ .engine = engine };
    var roots = [_]c.JSValue{c.pi_js_undefined()};
    var syntax: ?SyntaxCategory = null;
    var host_error: ?anyerror = null;
    if (compileBody(&boundary, engine, content, physical_filename)) |completion| {
        switch (completion) {
            .function => |value| roots[0] = value,
            .syntax => |value| {
                roots[0] = value.reason;
                syntax = value.category;
            },
        }
    } else |err| host_error = err;
    try boundary.finishManyPending(host_error, &scope, &roots);
    if (syntax) |category| return .{ .syntax = .{ .reason = roots[0], .category = category } };
    return .{ .function = roots[0] };
}

fn compileBody(boundary: *Boundary, engine: *v.em.Engine, content: c.JSValue, physical_filename: c.JSValue) !Completion {
    try boundary.checkCurrent();
    var category: c_int = 0;
    var result = JS_PiCompileCJSFunction(engine.context, content, physical_filename, &category);
    if (!c.JS_IsException(result) and !c.JS_HasException(engine.context)) {
        if (category != 0) {
            boundary.release(&result);
            return error.ActualCompilerCompletionAbiMismatch;
        }
        return .{ .function = result };
    }
    try observeFailure(boundary, &result);
    const syntax: SyntaxCategory = switch (category) {
        1 => .ordinary,
        2 => .direct_module,
        3 => .module_probe_required,
        0 => return error.JavaScriptException,
        else => return error.ActualCompilerCompletionAbiMismatch,
    };
    return .{ .syntax = .{ .reason = try takeSyntaxReason(boundary), .category = syntax } };
}

/// Actual strict module syntax and semantic compilation of a detached module.
/// No resolving/loading/linking, namespaces, cache insertion, body or jobs.
pub fn probe(engine: *v.em.Engine, content: c.JSValue, physical_filename: c.JSValue) !Probe {
    var boundary = Boundary.begin(engine);
    var scope: v.Scope = .{ .engine = engine };
    var roots = [_]c.JSValue{c.pi_js_undefined()};
    var flags: c_uint = 0;
    var syntax = false;
    var host_error: ?anyerror = null;
    if (probeBody(&boundary, engine, content, physical_filename)) |completion| {
        switch (completion) {
            .parsed => |value| flags = value,
            .syntax => |reason| {
                roots[0] = reason;
                syntax = true;
            },
        }
    } else |err| host_error = err;
    try boundary.finishManyPending(host_error, &scope, &roots);
    return if (syntax) .{ .syntax = roots[0] } else .{ .parsed = flags };
}

fn probeBody(boundary: *Boundary, engine: *v.em.Engine, content: c.JSValue, physical_filename: c.JSValue) !Probe {
    try boundary.checkCurrent();
    var flags: c_uint = 0;
    var diagnostic: c_int = 0;
    const status = JS_PiParseModuleSyntax(engine.context, content, physical_filename, &flags, &diagnostic);
    if (status == 0 and !c.JS_HasException(engine.context)) {
        if (diagnostic != 0 or flags & ~@as(c_uint, 7) != 0) return error.ActualCompilerProbeAbiMismatch;
        return .{ .parsed = flags };
    }
    var unused = c.pi_js_undefined();
    try observeFailure(boundary, &unused);
    if (status == 1 and diagnostic == 1)
        return .{ .syntax = try takeSyntaxReason(boundary) };
    return error.JavaScriptException;
}

/// An ordinary private host callable. The actual module callable owns its ABI
/// return; a completed syntax reason becomes a new ordinary source throw.
pub fn createBodyCompiler(engine: *v.em.Engine) !c.JSValue {
    var boundary = Boundary.begin(engine);
    var scope: v.Scope = .{ .engine = engine };
    var roots = [_]c.JSValue{c.pi_js_undefined()};
    var host_error: ?anyerror = null;
    if (boundary.checkCurrent()) |_| {
        roots[0] = functions.create(engine, "compileBody", 2, false, compileCall, &.{}) catch |err| blk: {
            host_error = err;
            break :blk c.pi_js_undefined();
        };
    } else |err| host_error = err;
    try boundary.finishManyPending(host_error, &scope, &roots);
    return roots[0];
}

fn compileCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const completion = try compile(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined());
    return switch (completion) {
        .function => |function| function,
        .syntax => |syntax| blk: {
            _ = c.JS_PiThrowExceptionData(engine.context, syntax.reason);
            break :blk error.JavaScriptException;
        },
    };
}
