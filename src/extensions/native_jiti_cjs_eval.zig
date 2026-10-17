//! Compile/call the actual seven-argument jiti2.7 wrapper for lowered user code.
//! The caller owns real Module construction, cache publication and finalization.
//! No createJiti facade, resolver, namespace proxy or host JS implementation.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const lowering = @import("native_jiti_cjs_lower.zig");

pub const Prepared = struct {
    body: []u8,
    async_mode: bool,
    pub fn deinit(self: Prepared, gpa: std.mem.Allocator) void { gpa.free(self.body); }
};

/// Finish all syntax rejection before real Module/cache publication.
pub fn prepare(gpa: std.mem.Allocator, source: []const u8, options: lowering.Options) !Prepared {
    return .{ .body = try lowering.lower(gpa, source, options), .async_mode = options.async_mode };
}

/// Owned real VM function. Caller publishes its actual Module/cache after
/// prepare and before compile, matching eval.ts. No user body executes here.
pub fn compile(engine: *v.em.Engine, prepared: *const Prepared, filename: [:0]const u8) !c.JSValue {
    // Source vm.runInThisContext has displayErrors:false. Do not inspect a
    // caught reason's observable formatting getters before its owner handles it.
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const wrapped = try std.fmt.allocPrint(engine.gpa,
        "({s}function (exports, require, module, __filename, __dirname, jitiImport, jitiESMResolve) {{ {s}\n}});",
        .{ if (prepared.async_mode) "async " else "", prepared.body });
    defer engine.gpa.free(wrapped);
    const generation = engine.native_allocation_generation;
    return engine.eval(wrapped, filename, c.JS_EVAL_TYPE_GLOBAL) catch |err| return exactFailure(engine, err, generation);
}

/// Borrowed real Module and actual nested jiti binding; returns owned raw
/// wrapper completion, including the exact Promise in async mode. No adoption
/// wrapper or loaded/cache/interop mutation is added. dirname is the actual
/// pathe-compatible operation used by the caller, not an invented path policy.
pub fn invoke(engine: *v.em.Engine, compiled: c.JSValue, module: c.JSValue, nested_jiti: c.JSValue, dirname: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return invokeValues(engine, compiled, module, nested_jiti, dirname) catch |err| return exactFailure(engine, err, generation);
}
fn invokeValues(engine: *v.em.Engine, compiled: c.JSValue, module: c.JSValue, nested_jiti: c.JSValue, dirname: c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine };
    defer s.deinit();
    const exports = try s.get(module, "exports");
    const require = try s.get(module, "require");
    const filename = try s.get(module, "filename");
    const directory = try s.call(dirname, c.pi_js_undefined(), &.{try s.get(module, "filename")});
    const imported = try s.get(nested_jiti, "import");
    const resolve = try s.get(nested_jiti, "esmResolve");
    const wrapper_args = [_]c.JSValue{ exports, require, module, filename, directory, imported, resolve };
    return engine.checked(c.JS_Call(engine.context, compiled, c.pi_js_undefined(), wrapper_args.len, @constCast(&wrapper_args)));
}
fn exactFailure(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| return fatal;
    };
    return err;
}
