//! Actual public classifier-shared module helpers.
const v = @import("native_ai_provider_values.zig");
const values = @import("native_ai_classifier_values.zig");
const c = v.c;
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    inline for (.{ "isRecord", "requiredNumber", "parseClassifierUsage" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                var row: v.Scope = .{ .engine = host };
                defer row.deinit();
                var items = [_]c.JSValue{c.pi_js_undefined()} ** 3;
                for (args[0..@min(args.len, items.len)], 0..) |item, i| items[i] = item;
                const output = switch (index) {
                    0 => c.pi_js_bool(host.context, @intFromBool(try values.record(&row, items[0]))),
                    1 => try values.required(&row, items[0], items[1], items[2]),
                    else => try values.usage(&row, items[0], items[1]),
                };
                return c.JS_DupValue(host.context, output);
            }
        };
        try scope.put(result, name, try scope.own(try @import("native_node_function.zig").create(engine, name, if (index == 0) 1 else if (index == 1) 3 else 2, Adapter.call, &.{})));
    }
    try scope.put(result, "postClassifierRequest", try scope.own(try @import("native_ai_classifier_request.zig").create(engine)));
    return c.JS_DupValue(engine.context, result);
}
