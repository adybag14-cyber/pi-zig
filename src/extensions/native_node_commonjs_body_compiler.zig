//! Actual linked-VM CJS/probe completions, consumed by the Node wrapSafe owner.
//! These are raw parser/compiler completions, not a fabricated contextify record.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const functions = @import("native_node_module_callable.zig");
const allocation = @import("native_async_body.zig");

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

fn takeCurrent(engine: *v.em.Engine) !c.JSValue {
    if (!c.JS_HasException(engine.context)) return error.MissingActualCompilerCurrentReason;
    return c.JS_GetException(engine.context);
}

fn throwOwned(engine: *v.em.Engine, owned: c.JSValue, generation: u64) anyerror {
    defer engine.freeValue(owned);
    allocation.rethrowRecognizedAllocation(engine, owned, generation) catch |err| return err;
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, owned))) catch |err| return err;
    return error.ActualCompilerThrowDidNotFail;
}

fn protectCurrent(engine: *v.em.Engine, reason: c.JSValue, generation: u64) !void {
    // This is the just-taken actual current exception from the native operation,
    // never Promise rejection data or an unrelated captured_exception slot.
    try allocation.rethrowRecognizedAllocation(engine, reason, generation);
    if (c.JS_IsUncatchableError(reason)) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        return error.ActualCompilerThrowDidNotFail;
    }
}

/// Compile the original body with five real formal parameters and true EOF.
/// No body runs, no outer promise, source wrapper, cache record or realm shim.
pub fn compile(engine: *v.em.Engine, content: c.JSValue, physical_filename: c.JSValue) !Completion {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    if (c.JS_HasException(engine.context)) return throwOwned(engine, try takeCurrent(engine), generation);
    var category: c_int = 0;
    const result = JS_PiCompileCJSFunction(engine.context, content, physical_filename, &category);
    if (!c.JS_IsException(result) and !c.JS_HasException(engine.context)) {
        if (category != 0) {
            engine.freeValue(result);
            return error.ActualCompilerCompletionAbiMismatch;
        }
        return .{ .function = result };
    }
    const reason = takeCurrent(engine) catch |err| {
        engine.freeValue(result);
        return err;
    };
    errdefer engine.freeValue(reason);
    engine.freeValue(result); // Own the first actual reason before result cleanup.
    try protectCurrent(engine, reason, generation);
    const syntax: SyntaxCategory = switch (category) {
        1 => .ordinary,
        2 => .direct_module,
        3 => .module_probe_required,
        0 => return throwOwned(engine, c.JS_DupValue(engine.context, reason), generation),
        else => return error.ActualCompilerCompletionAbiMismatch,
    };
    return .{ .syntax = .{ .reason = reason, .category = syntax } };
}

/// Actual strict module syntax+semantic compilation of a detached module.
/// No resolving/loading/linking, namespaces, cache insertion, body or jobs.
pub fn probe(engine: *v.em.Engine, content: c.JSValue, physical_filename: c.JSValue) !Probe {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    if (c.JS_HasException(engine.context)) return throwOwned(engine, try takeCurrent(engine), generation);
    var flags: c_uint = 0;
    var diagnostic: c_int = 0;
    const status = JS_PiParseModuleSyntax(engine.context, content, physical_filename, &flags, &diagnostic);
    if (status == 0 and !c.JS_HasException(engine.context)) {
        if (diagnostic != 0 or flags & ~@as(c_uint, 7) != 0) return error.ActualCompilerProbeAbiMismatch;
        return .{ .parsed = flags };
    }
    const reason = try takeCurrent(engine);
    errdefer engine.freeValue(reason);
    try protectCurrent(engine, reason, generation);
    if (status == 1 and diagnostic == 1) return .{ .syntax = reason };
    return throwOwned(engine, c.JS_DupValue(engine.context, reason), generation);
}

/// An ordinary private host callable. A successful result is the exact compiled
/// function; syntax rejection throws the exact completed compiler reason. This
/// is deliberately not exposed as Node's richer compileFunctionForCJSLoader.
pub fn createBodyCompiler(engine: *v.em.Engine) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    if (c.JS_HasException(engine.context)) return throwOwned(engine, try takeCurrent(engine), generation);
    return functions.create(engine, "compileBody", 2, false, compileCall, &.{}) catch |err| {
        if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
            allocation.rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| return fatal;
        };
        return err;
    };
}
fn compileCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    const completion = try compile(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined());
    return switch (completion) {
        .function => |function| function,
        .syntax => |syntax| throwOwned(engine, syntax.reason, generation),
    };
}
