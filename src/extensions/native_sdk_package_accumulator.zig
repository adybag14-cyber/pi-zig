//! Ordinary Source package resource accumulation, precedence and canonical dedupe.
const std = @import("std");
const package_catch = @import("native_sdk_package_catch.zig");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Method = enum(c_int) { getTargetMap, addResource, createAccumulator, toResolvedPaths };
const Callback = enum(c_int) { entry, precedence, canonical };
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, engine.native_io orelse return error.NativePackageAccumulatorRequiresIo);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var roots = [_]c.JSValue{try scope.get(engine.native_module_values.get("node:fs").?, "realpathSync")};
    inline for (std.meta.fields(Method)) |field| {
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) {
            .getTargetMap => 2,
            .addResource => 4,
            .createAccumulator => 0,
            .toResolvedPaths => 1,
        };
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, length, field.value, roots.len, &roots));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return method(engine, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0]) catch |err| sdk.fail(engine, err);
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return observed(engine, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots) catch |err| sdk.fail(engine, err);
}
fn callbackFunction(scope: *Scope, kind: Callback, roots: []c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, "", if (kind == .precedence) 2 else 1, @intFromEnum(kind), @intCast(roots.len), roots.ptr)));
}
fn entry(scope: *Scope, value: c.JSValue) !c.JSValue {
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var it = try js.Iterator.init(scope.engine, value, symbol);
    defer it.deinit();
    errdefer it.closePreserving();
    const first = if (try it.next()) |item| try scope.own(item) else c.pi_js_undefined();
    const second = if (try it.next()) |item| try scope.own(item) else c.pi_js_undefined();
    // The nested object binding executes before IteratorClose in Source's
    // ([path, { metadata, enabled }]) callback parameter.
    const metadata = try scope.get(second, "metadata");
    const enabled = try scope.get(second, "enabled");
    try it.close();
    const result = try scope.object();
    try scope.put(result, "path", first);
    try scope.put(result, "enabled", enabled);
    try scope.put(result, "metadata", metadata);
    return result;
}
fn rank(scope: *Scope, metadata: c.JSValue) !i32 {
    if (scope.equal(try scope.get(metadata, "source"), try scope.text("builtin"))) return 5;
    if (scope.equal(try scope.get(metadata, "origin"), try scope.text("package"))) return 4;
    const base: i32 = if (scope.equal(try scope.get(metadata, "scope"), try scope.text("project"))) 0 else 2;
    return base + @as(i32, if (scope.equal(try scope.get(metadata, "source"), try scope.text("local"))) 0 else 1);
}
fn realpath(scope: *Scope, function_value: c.JSValue, input: c.JSValue) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    return scope.call(function_value, c.pi_js_undefined(), &.{input}) catch |err| {
        try package_catch.ignore(scope.engine, err, generation);
        return input;
    };
}
fn observed(engine: *em.Engine, kind: Callback, args: []const c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (kind) {
        .entry => {
            return c.JS_DupValue(engine.context, try entry(&scope, arg(args, 0)));
        },
        .precedence => {
            const left = try rank(&scope, try scope.get(arg(args, 0), "metadata"));
            const right = try rank(&scope, try scope.get(arg(args, 1), "metadata"));
            return c.JS_NewInt32(engine.context, left - right);
        },
        .canonical => {
            const path = try realpath(&scope, roots[1], try scope.get(arg(args, 0), "path"));
            if (scope.truthy(try scope.invoke(roots[0], "has", &.{path}))) return c.pi_js_bool(engine.context, 0);
            _ = try scope.invoke(roots[0], "add", &.{path});
            return c.pi_js_bool(engine.context, 1);
        },
    }
}
fn resolved(scope: *Scope, entries: c.JSValue, realpath_function: c.JSValue) !c.JSValue {
    const array_constructor = try scope.global("Array");
    const from = try scope.get(array_constructor, "from");
    const all = try scope.call(from, array_constructor, &.{try scope.invoke(entries, "entries", &.{})});
    const map = try scope.get(all, "map");
    const mapped = try scope.call(map, all, &.{try callbackFunction(scope, .entry, &.{})});
    const sort = try scope.get(mapped, "sort");
    _ = try scope.call(sort, mapped, &.{try callbackFunction(scope, .precedence, &.{})});
    const seen = try scope.own(try js.builtin(scope.engine, "Set", &.{}));
    const filter = try scope.get(mapped, "filter");
    var roots = [_]c.JSValue{ seen, realpath_function };
    return scope.call(filter, mapped, &.{try callbackFunction(scope, .canonical, &roots)});
}
fn method(engine: *em.Engine, kind: Method, args: []const c.JSValue, realpath_function: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = arg(args, 0);
    switch (kind) {
        .createAccumulator => {
            const result = try scope.object();
            inline for (.{ "extensions", "skills", "prompts", "themes" }) |field| try scope.put(result, field, try scope.own(try js.builtin(engine, "Map", &.{})));
            return c.JS_DupValue(engine.context, result);
        },
        .getTargetMap => {
            const selected = arg(args, 1);
            inline for (.{ "extensions", "skills", "prompts", "themes" }) |field| if (scope.equal(selected, try scope.text(field))) return c.JS_DupValue(engine.context, try scope.get(first, field));
            const message = try scope.concat(try scope.text("Unknown resource type: "), try scope.stringify(selected));
            return engine.checked(c.JS_Throw(engine.context, try js.builtin(engine, "Error", &.{message})));
        },
        .addResource => {
            const path = arg(args, 1);
            if (scope.truthy(path) and !scope.truthy(try scope.invoke(first, "has", &.{path}))) {
                const set = try scope.get(first, "set");
                const row = try scope.object();
                try scope.put(row, "metadata", arg(args, 2));
                try scope.put(row, "enabled", arg(args, 3));
                _ = try scope.call(set, first, &.{ path, row });
            }
            return c.pi_js_undefined();
        },
        .toResolvedPaths => {
            const result = try scope.object();
            inline for (.{ "extensions", "skills", "prompts", "themes" }) |field| try scope.put(result, field, try resolved(&scope, try scope.get(first, field), realpath_function));
            return c.JS_DupValue(engine.context, result);
        },
    }
}
