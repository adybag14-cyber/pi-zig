//! Concrete utility composition for actual TTY error paths. Every installed
//! function is its genuine algorithm; unrelated util APIs are not advertised.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
const inspect = @import("native_node_util_inspect.zig");
pub fn createPrivateInspect(engine: *v.em.Engine, primordials: inspect.Inputs) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    const actual = try inspect.create(engine, primordials); defer actual.deinit(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const exports = try s.object(); try h.put(engine, exports, "inspect", actual.inspect); try h.put(engine, exports, "format", actual.format);
    return c.JS_DupValue(engine.context, exports);
}
/// Called with the actual public util carrier during its assembly. Public
/// copies share function identities with the PRIVATE exports, but replacing
/// util.inspect/util.format must not mutate internal/errors' private module.
pub fn installRequired(engine: *v.em.Engine, public_util: c.JSValue, private_inspect: c.JSValue, errors: @import("native_node_tty_errors.zig").Exports) !void {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    if (!c.JS_IsObject(public_util) or !c.JS_IsObject(private_inspect) or c.JS_IsStrictEqual(engine.context, public_util, private_inspect)) return error.RequiredDistinctActualUtilCarriers;
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const actual_inspect = try h.get(&s, private_inspect, "inspect"); const actual_format = try h.get(&s, private_inspect, "format");
    if (!c.JS_IsFunction(engine.context, actual_inspect) or !c.JS_IsFunction(engine.context, actual_format)) return error.RequiredActualPrivateInspectFunctions;
    const name = try s.own(try @import("native_node_util_error_name.zig").create(engine, .{ .invalid_arg_type = errors.invalid_arg_type, .out_of_range = errors.out_of_range }));
    try h.put(engine, public_util, "format", actual_format); try h.put(engine, public_util, "inspect", actual_inspect); try h.put(engine, public_util, "getSystemErrorName", name);
}
