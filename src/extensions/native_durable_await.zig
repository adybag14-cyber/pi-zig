//! Native durable coroutine continuations capture the realm's Promise
//! intrinsics when the module is installed, as an async function would.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Intrinsics = struct {
    constructor: c.JSValue,
    resolve: c.JSValue,
    then_function: c.JSValue,
    pub fn init(engine: *Engine) !Intrinsics {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const constructor = try vm.get(engine, global, "Promise");
        errdefer engine.freeValue(constructor);
        const resolve = try vm.get(engine, constructor, "resolve");
        errdefer engine.freeValue(resolve);
        const prototype = try vm.get(engine, constructor, "prototype");
        defer engine.freeValue(prototype);
        return .{ .constructor = constructor, .resolve = resolve, .then_function = try vm.get(engine, prototype, "then") };
    }
    pub fn deinit(self: *Intrinsics, engine: *Engine) void {
        engine.freeValue(self.constructor);
        engine.freeValue(self.resolve);
        engine.freeValue(self.then_function);
    }
    pub fn mark(self: *Intrinsics, runtime: ?*c.JSRuntime, marker: ?*const c.JS_MarkFunc) void {
        c.JS_MarkValue(runtime, self.constructor, marker);
        c.JS_MarkValue(runtime, self.resolve, marker);
        c.JS_MarkValue(runtime, self.then_function, marker);
    }
    pub fn chain(self: *Intrinsics, engine: *Engine, awaited: c.JSValue, fulfilled: c.JSValue, rejected: c.JSValue) !c.JSValue {
        var argument = [_]c.JSValue{awaited};
        const promise = try engine.checked(c.JS_Call(engine.context, self.resolve, self.constructor, argument.len, &argument));
        defer engine.freeValue(promise);
        var continuations = [_]c.JSValue{ fulfilled, rejected };
        return engine.checked(c.JS_Call(engine.context, self.then_function, promise, continuations.len, &continuations));
    }
};

/// A state object is retained by the VM's function data for each continuation.
/// The callback is compiled Zig; no host pointer outlives an async stack frame.
pub fn continueWith(comptime next: *const fn (*Engine, c.JSValue, c.JSValue, bool, c_int) anyerror!c.JSValue, engine: *Engine, intrinsics: *Intrinsics, state: c.JSValue, awaited: c.JSValue, stage: c_int) !c.JSValue {
    const Adapter = struct {
        fn fulfilled(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
            const owner = Engine.fromContext(context.?);
            return next(owner, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), false, magic) catch |err| @import("native_durable.zig").reject(owner, err);
        }
        fn rejected(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
            const owner = Engine.fromContext(context.?);
            return next(owner, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), true, magic) catch |err| @import("native_durable.zig").reject(owner, err);
        }
    };
    var captures = [_]c.JSValue{state};
    const fulfilled = try engine.checked(c.JS_NewCFunctionData2(engine.context, Adapter.fulfilled, "", 1, stage, captures.len, &captures));
    defer engine.freeValue(fulfilled);
    const rejected = try engine.checked(c.JS_NewCFunctionData2(engine.context, Adapter.rejected, "", 1, stage, captures.len, &captures));
    defer engine.freeValue(rejected);
    return intrinsics.chain(engine, awaited, fulfilled, rejected);
}
