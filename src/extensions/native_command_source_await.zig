//! Command-only coroutine adapters preserve genuine native allocator provenance.
const a = @import("native_tui_alt_frame.zig");
const js = a.js;
const c = a.c;
pub const Intrinsics = @import("native_durable_await.zig").Intrinsics;
pub fn continueWith(comptime next: *const fn (*js.Engine, c.JSValue, c.JSValue, bool, c_int) anyerror!c.JSValue, engine: *js.Engine, intrinsics: *Intrinsics, state: c.JSValue, value: c.JSValue, stage: c_int) !c.JSValue {
    const Adapter = struct {
        fn fulfilled(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
            const owner = js.Engine.fromContext(ctx.?);
            return next(owner, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), false, magic) catch |err| a.fail(owner, err);
        }
        fn rejected(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
            const owner = js.Engine.fromContext(ctx.?);
            return next(owner, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), true, magic) catch |err| a.fail(owner, err);
        }
    };
    var data = [_]c.JSValue{state};
    const fulfilled = try engine.checked(c.JS_NewCFunctionData2(engine.context, Adapter.fulfilled, "", 1, stage, 1, &data));
    defer engine.freeValue(fulfilled);
    const rejected = try engine.checked(c.JS_NewCFunctionData2(engine.context, Adapter.rejected, "", 1, stage, 1, &data));
    defer engine.freeValue(rejected);
    return intrinsics.chain(engine, value, fulfilled, rejected);
}
