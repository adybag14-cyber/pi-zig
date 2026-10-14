//! Actual Source highlight.js10.7.3 error/warn/deprecated arrow bodies.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}, magic, roots[0]) catch |err| sdk.fail(engine, err);
}
fn invoke(engine: *em.Engine, args: []const c.JSValue, kind: c_int, seen: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    if (kind == 0) {
        _ = try s.invoke(try s.global("console"), "error", &.{first});
    } else if (kind == 1) {
        const console = try s.global("console");
        const log = try s.get(console, "log");
        const message = try s.concat(try s.text("WARN: "), try s.stringify(first));
        const values = try engine.gpa.alloc(c.JSValue, if (args.len > 0) args.len else 1);
        defer engine.gpa.free(values);
        values[0] = message;
        if (args.len > 1) @memcpy(values[1..], args[1..]);
        _ = try s.call(log, console, values);
    } else {
        const second = if (args.len > 1) args[1] else c.pi_js_undefined();
        const key = try s.concat(try s.concat(try s.stringify(first), try s.text("/")), try s.stringify(second));
        if (s.truthy(try s.own(try js.getKey(engine, seen, key)))) return c.pi_js_undefined();
        const console = try s.global("console");
        const log = try s.get(console, "log");
        const message = try s.concat(try s.concat(try s.concat(try s.text("Deprecated as of "), try s.stringify(first)), try s.text(". ")), try s.stringify(second));
        _ = try s.call(log, console, &.{message});
        const after_key = try s.concat(try s.concat(try s.stringify(first), try s.text("/")), try s.stringify(second));
        try js.setKey(engine, seen, after_key, c.pi_js_bool(engine.context, 1));
    }
    return c.pi_js_undefined();
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const module = "pi-native:highlight-loggers";
    if (!engine.native_module_values.contains(module)) {
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const exports = try s.object();
        const seen = try s.object();
        var roots = [_]c.JSValue{seen};
        inline for (.{ .{ "error", 1 }, .{ "warn", 1 }, .{ "deprecated", 2 } }, 0..) |entry, index| try s.put(exports, entry[0], try s.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, entry[0], entry[1], @intCast(index), roots.len, &roots))));
        try engine.registerValueModule(module, exports);
    }
    return c.JS_DupValue(engine.context, engine.native_module_values.get(module).?);
}
