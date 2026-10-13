//! Original pi-ai session resource registry shared by native provider/session
//! owners within this VM. Guest callback errors aggregate; native OOM escapes.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
pub fn bindings(engine: *em.Engine) !c.JSValue {
    if (engine.native_ai_session_resources) |cached| return c.JS_DupValue(engine.context, cached);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const registry = try scope.own(try js.builtin(engine, "Set", &.{}));
    const exports = try scope.object();
    inline for (.{ "registerSessionResourceCleanup", "cleanupSessionResources" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
                return invoke(host, values[0], index, if (args.len > 0) args[0] else c.pi_js_undefined());
            }
        };
        const function = try scope.own(try @import("native_node_function.zig").create(engine, name, 1, Adapter.call, &.{registry}));
        try scope.put(exports, name, function);
    }
    engine.native_ai_session_resources = c.JS_DupValue(engine.context, exports);
    return c.JS_DupValue(engine.context, exports);
}
fn invoke(engine: *em.Engine, registry: c.JSValue, magic: c_int, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (magic == 0) {
        _ = try scope.invoke(registry, "add", &.{value});
        var roots = [_]c.JSValue{ registry, value };
        return engine.checked(c.JS_NewCFunctionData2(engine.context, unregister, "", 0, 0, roots.len, &roots));
    }
    const errors = try scope.array();
    const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, registry, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |cleanup| {
        defer engine.freeValue(cleanup);
        const generation = engine.native_allocation_generation;
        const result = js.call(engine, cleanup, c.pi_js_undefined(), &.{value}) catch |err| {
            if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
            const reason = flow.reason(engine, err);
            defer engine.freeValue(reason);
            _ = try scope.invoke(errors, "push", &.{reason});
            continue;
        };
        engine.freeValue(result);
    }
    if (try scope.positive(try scope.get(errors, "length"))) {
        const constructor = try scope.global("AggregateError");
        var args = [_]c.JSValue{ errors, try scope.text("Failed to cleanup session resources") };
        const reason = try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
        _ = try engine.checked(c.JS_Throw(engine.context, reason));
    }
    return c.pi_js_undefined();
}
fn unregister(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const result = js.invoke(engine, roots[0], "delete", &.{roots[1]}) catch |err| return sdk.fail(engine, err);
    engine.freeValue(result);
    return c.pi_js_undefined();
}
