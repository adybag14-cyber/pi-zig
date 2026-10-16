//! Ordinary Source package path and project-trust helpers.
const data = @import("native_sdk_package_data.zig");
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const Method = enum(c_int) { assertProjectTrustedForScope, getBaseDirForScope, resolvePath, resolvePathFromBase };
pub fn install(engine: *em.Engine, prototype: c.JSValue, config_dir: c.JSValue) !void {
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, engine.native_io orelse return error.NativePackagePathsRequireIo);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var roots = [_]c.JSValue{ try scope.get(engine.native_module_values.get("node:path").?, "join"), config_dir };
    inline for (std.meta.fields(Method)) |field| {
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, if (field.value == @intFromEnum(Method.resolvePathFromBase)) 2 else 1, field.value, roots.len, &roots));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn dispatch(context: ?*c.JSContext, manager: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return method(engine, manager, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0], roots[1]) catch |err| sdk.fail(engine, err);
}
fn home(scope: *Scope) !c.JSValue {
    const process = try scope.global("process");
    const environment = try scope.get(process, "env");
    const supplied = try scope.get(environment, "HOME");
    return if (scope.truthy(supplied)) supplied else scope.own(try @import("native_home.zig").get(scope.engine));
}
fn trusted(scope: *Scope, manager: c.JSValue, selected: c.JSValue) !void {
    if (scope.equal(selected, try scope.text("project")) and !scope.truthy(try scope.invoke(try scope.get(manager, "settingsManager"), "isProjectTrusted", &.{}))) {
        const message = try scope.text("Project is not trusted; refusing to access project package storage");
        _ = try scope.engine.checked(c.JS_Throw(scope.engine.context, try js.builtin(scope.engine, "Error", &.{message})));
        unreachable;
    }
}
fn method(engine: *em.Engine, manager: c.JSValue, kind: Method, args: []const c.JSValue, join: c.JSValue, config_dir: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const result = switch (kind) {
        .assertProjectTrustedForScope => done: {
            try trusted(&scope, manager, first);
            break :done c.pi_js_undefined();
        },
        .getBaseDirForScope => value: {
            if (scope.equal(first, try scope.text("project"))) {
                _ = try scope.invoke(manager, "assertProjectTrustedForScope", &.{first});
                break :value try scope.call(join, c.pi_js_undefined(), &.{ try scope.get(manager, "cwd"), config_dir });
            }
            break :value try scope.get(manager, if (scope.equal(first, try scope.text("user"))) "agentDir" else "cwd");
        },
        .resolvePath, .resolvePathFromBase => value: {
            const base = if (kind == .resolvePath) try scope.get(manager, "cwd") else if (args.len > 1) args[1] else c.pi_js_undefined();
            const options = try scope.object();
            try data.put(scope.engine, options, "homeDir", try home(&scope));
            try data.put(scope.engine, options, "trim", c.pi_js_bool(engine.context, 1));
            break :value try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, first, base, options));
        },
    };
    return c.JS_DupValue(engine.context, result);
}
