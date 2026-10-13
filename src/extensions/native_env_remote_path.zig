//! Source remote path selection through the native Node path and URL adapters.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const awaiter = @import("native_durable_await.zig");
const files = @import("native_env_list_files.zig");
const c = js.c;
pub fn paths(scope: *Scope, bindings: c.JSValue, info: c.JSValue) !c.JSValue {
    const platform = try scope.call(try scope.get(bindings, "nodePlatform"), c.pi_js_undefined(), &.{info});
    const windows = scope.equal(try scope.get(platform, "platform"), try scope.text("win32"));
    return scope.get(try scope.get(bindings, "paths"), if (windows) "win32" else "posix");
}
fn normalized(scope: *Scope, captures: c.JSValue, info: c.JSValue) !c.JSValue {
    const bindings = try scope.get(captures, "bindings");
    const selected = try paths(scope, bindings, info);
    const windows = scope.equal(try scope.get(selected, "sep"), try scope.text("\\"));
    const input = try scope.get(captures, "input");
    var value = input;
    if (scope.equal(value, try scope.text("~"))) {
        value = try scope.get(info, "home");
    } else if (scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text("~/")})) or (windows and scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text("~\\")})))) {
        value = try scope.invoke(selected, "join", &.{ try scope.get(info, "home"), try scope.invoke(value, "slice", &.{c.JS_NewInt32(scope.engine.context, 2)}) });
    } else if (scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text("file://")}))) {
        const options = try scope.object();
        try scope.put(options, "windows", c.pi_js_bool(scope.engine.context, @intFromBool(windows)));
        value = scope.call(try scope.get(bindings, "fileURLToPath"), c.pi_js_undefined(), &.{ value, options }) catch |err| ignored: {
            if (err != error.JavaScriptException) return err;
            if (scope.engine.captured_exception) |reason| scope.engine.freeValue(reason);
            scope.engine.captured_exception = null;
            break :ignored input;
        };
    }
    if (scope.truthy(try scope.invoke(selected, "isAbsolute", &.{value}))) return scope.invoke(selected, "resolve", &.{value});
    const cwd = try scope.get(try scope.get(captures, "self"), "cwd");
    if (windows) {
        const pattern = try scope.text("^([a-zA-Z]:)(?![\\\\/])");
        const expression = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, 1, @constCast(&pattern))));
        const match = try scope.invoke(expression, "exec", &.{value});
        if (!c.JS_IsNull(match)) {
            const drive = try scope.own(try js.getKey(scope.engine, match, c.JS_NewInt32(scope.engine.context, 1)));
            const current_drive = try scope.invoke(cwd, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 2) });
            if (!scope.equal(try scope.invoke(drive, "toLowerCase", &.{}), try scope.invoke(current_drive, "toLowerCase", &.{}))) {
                const upper = try scope.invoke(drive, "toUpperCase", &.{});
                const given = try scope.own(try js.getKey(scope.engine, try scope.get(info, "driveCwds"), upper));
                var base = if (c.JS_IsNull(given) or c.JS_IsUndefined(given)) try scope.get(info, "cwd") else given;
                const base_drive = try scope.invoke(base, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 2) });
                if (!scope.equal(try scope.invoke(base_drive, "toLowerCase", &.{}), try scope.invoke(drive, "toLowerCase", &.{})) and scope.equal(try scope.own(try js.getKey(scope.engine, base, c.JS_NewInt32(scope.engine.context, 2))), try scope.text("\\"))) base = try scope.concat(drive, try scope.text("\\"));
                return scope.invoke(selected, "resolve", &.{ base, value });
            }
        }
    }
    return scope.invoke(selected, "resolve", &.{ cwd, value });
}
fn next(engine: *js.Engine, captures: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    if (rejected) {
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value));
        return js.capture(engine);
    }
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try normalized(&scope, captures, value));
}
pub fn resolve(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue, input: c.JSValue) !c.JSValue {
    const captures = try scope.object();
    try scope.put(captures, "bindings", bindings);
    try scope.put(captures, "self", receiver);
    try scope.put(captures, "input", input);
    const connection = try scope.get(receiver, "connection");
    const pending = try scope.invoke(connection, "info", &.{});
    var promises = try files.intrinsics(scope, captures);
    return scope.own(try awaiter.continueWith(next, scope.engine, &promises, captures, pending, 0));
}
