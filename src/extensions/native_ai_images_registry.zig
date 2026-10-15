//! Distinct original image registry and async global dispatcher. Construction
//! requires the actual image implementation but does not register a default;
//! the images-module import side effect calls registerBuiltInImagesApiProviders.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const Method = enum { registerImagesApiProvider, getImagesApiProvider, registerBuiltInImagesApiProviders, generateImages };
pub fn create(engine: *v.em.Engine, builtin_generate_images: c.JSValue) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, builtin_generate_images)) return error.NativeImageImplementationRequired;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "registry", try scope.own(try v.js.builtin(engine, "Map", &.{})));
    try scope.put(owner, "builtin", builtin_generate_images);
    const result = try scope.object();
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                var row: Scope = .{ .engine = host };
                defer row.deinit();
                const first = if (args.len > 0) args[0] else c.pi_js_undefined();
                switch (method) {
                    .registerImagesApiProvider => try register(&row, roots[0], first, if (args.len > 1) args[1] else c.pi_js_undefined()),
                    .getImagesApiProvider => return c.JS_DupValue(host.context, try lookup(&row, roots[0], first)),
                    .registerBuiltInImagesApiProviders => {
                        const provider = try row.object();
                        try row.put(provider, "api", try row.text("openrouter-images"));
                        try row.put(provider, "generateImages", try row.get(roots[0], "builtin"));
                        try register(&row, roots[0], provider, c.pi_js_undefined());
                    },
                    .generateImages => return generate(host, roots[0], args),
                }
                return c.pi_js_undefined();
            }
        };
        const length: c_int = switch (method) {
            .registerImagesApiProvider => 2,
            .getImagesApiProvider => 1,
            .registerBuiltInImagesApiProviders => 0,
            .generateImages => 3,
        };
        const function = try scope.own(if (method == .generateImages) try @import("native_node_function.zig").createArrow(engine, field.name, length, Adapter.call, &.{owner}) else try @import("native_node_function.zig").create(engine, field.name, length, Adapter.call, &.{owner}));
        if (method == .generateImages) {
            const prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
            if (c.JS_SetPrototype(engine.context, function, prototype) < 0) return v.js.capture(engine);
        }
        try scope.put(result, field.name, function);
    }
    return c.JS_DupValue(engine.context, result);
}
fn lookup(scope: *Scope, owner: c.JSValue, api: c.JSValue) !c.JSValue {
    const entry = try scope.invoke(try scope.get(owner, "registry"), "get", &.{api});
    return if (v.nullish(entry)) c.pi_js_undefined() else scope.get(entry, "provider");
}
fn register(scope: *Scope, owner: c.JSValue, provider: c.JSValue, source_id: c.JSValue) !void {
    const registry = try scope.get(owner, "registry");
    const setter = try scope.get(registry, "set");
    const key = try scope.get(provider, "api");
    const registered = try scope.object();
    const internal = try scope.object();
    try scope.put(internal, "api", try scope.get(provider, "api"));
    const api = try scope.get(provider, "api");
    const implementation = try scope.get(provider, "generateImages");
    const Wrapped = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            host.native_exception_diagnostics_suppressed += 1;
            defer host.native_exception_diagnostics_suppressed -= 1;
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
            for (args[0..@min(args.len, values.len)], 0..) |value, i| values[i] = value;
            if (!row.equal(try row.get(values[0], "api"), roots[0])) {
                const message = try row.concat(try row.concat(try row.concat(try row.text("Mismatched api: "), try row.stringify(try row.get(values[0], "api"))), try row.text(" expected ")), try row.stringify(roots[0]));
                return v.errorText(&row, message);
            }
            return v.js.call(host, roots[1], c.pi_js_undefined(), &values);
        }
    };
    try scope.put(internal, "generateImages", try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 3, Wrapped.call, &.{ api, implementation })));
    try scope.put(registered, "provider", internal);
    try scope.put(registered, "sourceId", source_id);
    _ = try scope.call(setter, registry, &.{ key, registered });
}
fn generate(engine: *v.em.Engine, owner: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, owner);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
    for (args[0..@min(args.len, values.len)], 0..) |value, i| values[i] = value;
    dispatch(&scope, owner, pending.owner, &values) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn dispatch(scope: *Scope, owner: c.JSValue, pending: c.JSValue, args: []const c.JSValue) !void {
    const api = try scope.get(args[0], "api");
    const provider = try lookup(scope, owner, api);
    if (!scope.truthy(provider)) return v.errorText(scope, try scope.concat(try scope.text("No API provider registered for api: "), try scope.stringify(api)));
    const promise = try scope.invoke(provider, "generateImages", args);
    try flow.wait(continued, scope.engine, pending, promise, 0);
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    try flow.settle(engine, owner, rejected, value);
}
