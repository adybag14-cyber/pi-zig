//! Actual agent-session-services applyExtensionFlagValues, including live Map
//! iteration, destructuring, and runtime flag assignment order.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn apply(engine: *em.Engine, loader: c.JSValue, supplied: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(supplied)) return sdk.array(engine);
    const diagnostics = try scope.array();
    const extensions = try scope.invoke(loader, "getExtensions", &.{});
    const map_ctor = try scope.global("Map");
    const registered = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, map_ctor, 0, null)));
    const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    var extension_iterator = try js.Iterator.init(engine, try scope.get(extensions, "extensions"), symbol);
    defer extension_iterator.deinit();
    errdefer extension_iterator.closePreserving();
    while (try extension_iterator.next()) |extension| {
        defer engine.freeValue(extension);
        var outer: Scope = .{ .engine = engine };
        defer outer.deinit();
        var flags = try js.Iterator.init(engine, try outer.get(extension, "flags"), symbol);
        defer flags.deinit();
        errdefer flags.closePreserving();
        while (try flags.next()) |row| {
            defer engine.freeValue(row);
            const pair = try js.pair(engine, row, symbol);
            defer for (pair) |value| engine.freeValue(value);
            var frame: Scope = .{ .engine = engine };
            defer frame.deinit();
            const set = try frame.get(registered, "set");
            const configured = try frame.object();
            try frame.put(configured, "type", try frame.get(pair[1], "type"));
            _ = try frame.call(set, registered, &.{ pair[0], configured });
        }
    }
    const unknown = try scope.array();
    var iterator = try js.Iterator.init(engine, supplied, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |row| {
        defer engine.freeValue(row);
        const pair = try js.pair(engine, row, symbol);
        defer for (pair) |value| engine.freeValue(value);
        var frame: Scope = .{ .engine = engine };
        defer frame.deinit();
        const flag = try frame.invoke(registered, "get", &.{pair[0]});
        if (!frame.truthy(flag)) {
            _ = try frame.invoke(unknown, "push", &.{pair[0]});
            continue;
        }
        if (frame.equal(try frame.get(flag, "type"), try frame.text("boolean"))) {
            _ = try frame.invoke(try frame.get(try frame.get(extensions, "runtime"), "flagValues"), "set", &.{ pair[0], c.pi_js_bool(engine.context, 1) });
            continue;
        }
        if (c.JS_IsString(pair[1])) {
            _ = try frame.invoke(try frame.get(try frame.get(extensions, "runtime"), "flagValues"), "set", &.{ pair[0], pair[1] });
            continue;
        }
        const push = try frame.get(diagnostics, "push");
        const diagnostic = try frame.object();
        try frame.put(diagnostic, "type", try frame.text("error"));
        try frame.put(diagnostic, "message", try frame.concat(try frame.concat(try frame.text("Extension flag \"--"), try frame.stringify(pair[0])), try frame.text("\" requires a value")));
        _ = try frame.call(push, diagnostics, &.{diagnostic});
    }
    if (try scope.positive(try scope.get(unknown, "length"))) {
        const push = try scope.get(diagnostics, "push");
        const diagnostic = try scope.object();
        try scope.put(diagnostic, "type", try scope.text("error"));
        const singular = scope.equal(try scope.get(unknown, "length"), c.JS_NewInt32(engine.context, 1));
        const head = try scope.concat(try scope.concat(try scope.text("Unknown option"), try scope.text(if (singular) "" else "s")), try scope.text(": "));
        const map = try scope.get(unknown, "map");
        const callback = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, flagName, "", 1)));
        const names = try scope.call(map, unknown, &.{callback});
        try scope.put(diagnostic, "message", try scope.concat(head, try scope.invoke(names, "join", &.{try scope.text(", ")})));
        _ = try scope.call(push, diagnostics, &.{diagnostic});
    }
    return c.JS_DupValue(engine.context, diagnostics);
}
fn flagName(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = scope.concat(scope.text("--") catch |err| return sdk.fail(engine, err), scope.stringify(if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err)) catch |err| return sdk.fail(engine, err);
    return c.JS_DupValue(context, result);
}
