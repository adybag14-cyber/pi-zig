//! Ordinary immutable latest ModelConfig class over mandatory actual imports.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const classes = @import("native_class.zig");
const Method = enum(c_int) { load, provider, ids, error_value };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn function(scope: *Scope, method: Method, name: [*:0]const u8, length: c_int, env: c.JSValue) !c.JSValue {
    var roots = [_]c.JSValue{env};
    const value = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, length, @intFromEnum(method), roots.len, &roots)));
    if (method == .load) {
        const prototype = try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)));
        if (c.JS_SetPrototype(scope.engine.context, value, prototype) < 0) return v.js.capture(scope.engine);
    }
    return value;
}
pub fn create(engine: *v.em.Engine, imports: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const env = try scope.object();
    inline for (.{ "readFile", "normalizePath", "Compile" }) |name| {
        const value = try scope.get(imports, name);
        if (!c.JS_IsFunction(engine.context, value)) return error.MissingActualModelConfigImport;
        try scope.put(env, name, value);
    }
    const schema = try scope.own(try @import("native_sdk_model_config_schema_production.zig").create(engine, imports));
    try scope.put(env, "validator", try scope.call(try scope.get(env, "Compile"), c.pi_js_undefined(), &.{schema}));
    const prototype = try scope.object();
    const constructor = try scope.own(try classes.constructor(engine, "ModelConfig", 2, prototype, construct, &.{}));
    inline for (.{ .{ Method.provider, "getProvider", 1 }, .{ Method.ids, "getProviderIds", 0 }, .{ Method.error_value, "getError", 0 } }) |entry| {
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, entry[1], c.JS_DupValue(engine.context, try function(&scope, entry[0], entry[1], entry[2], env)), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return v.js.capture(engine);
    }
    try scope.put(env, "constructor", constructor);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "load", c.JS_DupValue(engine.context, try function(&scope, .load, "load", 1, env)), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return v.js.capture(engine);
    const exports = try scope.object();
    try scope.put(exports, "ModelsConfigSchema", schema);
    try scope.put(exports, "ModelConfig", constructor);
    return c.JS_DupValue(engine.context, exports);
}
fn construct(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try classes.object(engine, target));
    try scope.put(result, "providers", arg(args, 0));
    try scope.put(result, "error", arg(args, 1));
    return c.JS_DupValue(engine.context, result);
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const method: Method = @enumFromInt(raw);
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return invoke(engine, receiver, method, args, roots[0]) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn invoke(engine: *v.em.Engine, receiver: c.JSValue, method: Method, args: []const c.JSValue, env: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (method) {
        .provider => return v.js.invoke(engine, try scope.get(receiver, "providers"), "get", &.{arg(args, 0)}),
        .ids => {
            const output = try scope.array();
            var iterator = try v.iterator(&scope, try scope.invoke(try scope.get(receiver, "providers"), "keys", &.{}));
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |entry| {
                defer engine.freeValue(entry);
                try scope.index(output, try v.length(&scope, output), entry);
            }
            return c.JS_DupValue(engine.context, output);
        },
        .error_value => return v.js.get(engine, receiver, "error"),
        .load => {
            const pending = try flow.create(engine, env);
            defer engine.freeValue(pending.owner);
            errdefer engine.freeValue(pending.promise);
            start(&scope, pending.owner, env, arg(args, 0)) catch |err| try flow.rejectError(engine, pending.owner, err);
            return pending.promise;
        },
    }
}
fn map(scope: *Scope) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.global("Map"), 0, null)));
}
fn instance(scope: *Scope, owner: c.JSValue, providers: c.JSValue, error_value: c.JSValue) !void {
    const env = try scope.get(owner, "agent");
    var args = [_]c.JSValue{ providers, error_value };
    const result = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(env, "constructor"), args.len, &args)));
    try flow.settle(scope.engine, owner, false, result);
}
fn start(scope: *Scope, owner: c.JSValue, env: c.JSValue, path: c.JSValue) !void {
    if (!scope.truthy(path)) return instance(scope, owner, try map(scope), c.pi_js_undefined());
    const normalized = try scope.call(try scope.get(env, "normalizePath"), c.pi_js_undefined(), &.{path});
    try scope.put(owner, "path", normalized);
    const read = scope.call(try scope.get(env, "readFile"), c.pi_js_undefined(), &.{ normalized, try scope.text("utf-8") }) catch |err| {
        const reason = try scope.own(flow.reason(scope.engine, err));
        return readFailure(scope, owner, reason);
    };
    try flow.wait(continued, scope.engine, owner, read, 0);
}
fn description(scope: *Scope, value: c.JSValue) !c.JSValue {
    const is_error = c.JS_IsInstanceOf(scope.engine.context, value, try scope.global("Error"));
    if (is_error < 0) return v.js.capture(scope.engine);
    return if (is_error != 0) scope.get(value, "message") else value;
}
fn message(scope: *Scope, owner: c.JSValue, prefix: []const u8, detail: c.JSValue) !c.JSValue {
    var text = try scope.concat(try scope.text(prefix), try scope.stringify(detail));
    text = try scope.concat(text, try scope.text("\n\nFile: "));
    return scope.concat(text, try scope.stringify(try scope.get(owner, "path")));
}
fn readFailure(scope: *Scope, owner: c.JSValue, failure: c.JSValue) !void {
    const code = try scope.get(failure, "code");
    if (try v.eq(scope, code, "ENOENT")) return instance(scope, owner, try map(scope), c.pi_js_undefined());
    return instance(scope, owner, try map(scope), try message(scope, owner, "Failed to load models.json: ", try description(scope, failure)));
}
fn regex(scope: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ try scope.text(pattern), try scope.text("g") };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn stripMatch(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(roots[0]) and !v.nullish(arg(args, 1))) return c.JS_DupValue(engine.context, arg(args, 1));
    const first = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, arg(args, 0), 0)));
    return if (try v.eq(&scope, first, "\"")) c.JS_DupValue(engine.context, arg(args, 0)) else @import("native_sdk.zig").text(engine, "");
}
fn strip(scope: *Scope, input: c.JSValue) !c.JSValue {
    const content = if (scope.truthy(try scope.invoke(input, "startsWith", &.{try scope.text("\xef\xbb\xbf")}))) try scope.invoke(input, "slice", &.{c.JS_NewInt32(scope.engine.context, 1)}) else input;
    const functions = @import("native_node_function.zig");
    const line = try scope.own(try functions.createArrow(scope.engine, "", 1, stripMatch, &.{c.pi_js_bool(scope.engine.context, 0)}));
    const tail = try scope.own(try functions.createArrow(scope.engine, "", 2, stripMatch, &.{c.pi_js_bool(scope.engine.context, 1)}));
    const no_comments = try scope.invoke(content, "replace", &.{ try regex(scope, "\"(?:\\\\.|[^\"\\\\])*\"|//[^\\n]*"), line });
    return scope.invoke(no_comments, "replace", &.{ try regex(scope, "\"(?:\\\\.|[^\"\\\\])*\"|,(\\s*[}\\]])"), tail });
}
fn frozen(scope: *Scope, value: c.JSValue) anyerror!c.JSValue {
    if (!c.JS_IsObject(value) or c.JS_IsNull(value) or c.JS_IsFunction(scope.engine.context, value) or scope.truthy(try scope.invoke(try scope.global("Object"), "isFrozen", &.{value}))) return value;
    const children = try scope.invoke(try scope.global("Object"), "values", &.{value});
    var iterator = try v.iterator(scope, children);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |child| {
        defer scope.engine.freeValue(child);
        _ = try frozen(scope, child);
    }
    return scope.invoke(try scope.global("Object"), "freeze", &.{value});
}
fn validationLine(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const error_value = arg(args, 0);
    var path = c.pi_js_undefined();
    if (try v.eq(&scope, try scope.get(error_value, "keyword"), "required")) {
        const properties = try scope.get(try scope.get(error_value, "params"), "requiredProperties");
        const required = if (v.nullish(properties)) c.pi_js_undefined() else try v.at(&scope, properties, 0);
        if (scope.truthy(required)) {
            const base = try validationPath(&scope, try scope.get(error_value, "instancePath"));
            path = if (scope.truthy(base)) try scope.concat(try scope.concat(base, try scope.text(".")), required) else required;
        }
    }
    if (c.JS_IsUndefined(path)) {
        path = try validationPath(&scope, try scope.get(error_value, "instancePath"));
        if (!scope.truthy(path)) path = try scope.text("root");
    }
    const output = try scope.concat(try scope.concat(try scope.text("  - "), path), try scope.text(": "));
    return c.JS_DupValue(engine.context, try scope.concat(output, try scope.get(error_value, "message")));
}
fn validationPath(scope: *Scope, path: c.JSValue) !c.JSValue {
    var args = [_]c.JSValue{try scope.text("^/")};
    const first = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
    return scope.invoke(try scope.invoke(path, "replace", &.{ first, try scope.text("") }), "replace", &.{ try regex(scope, "/"), try scope.text(".") });
}
fn parsedContent(scope: *Scope, content: c.JSValue) !c.JSValue {
    const json = try scope.global("JSON");
    const parse_fn = try scope.get(json, "parse");
    return scope.call(parse_fn, json, &.{try strip(scope, content)});
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, failed: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (failed) return readFailure(&scope, owner, value);
    const parsed = parsedContent(&scope, value) catch |err| {
        const reason = try scope.own(flow.reason(engine, err));
        return instance(&scope, owner, try map(&scope), try message(&scope, owner, "Failed to parse models.json: ", try description(&scope, reason)));
    };
    const env = try scope.get(owner, "agent");
    const validator = try scope.get(env, "validator");
    if (!scope.truthy(try scope.invoke(validator, "Check", &.{parsed}))) {
        const errors = try scope.invoke(validator, "Errors", &.{parsed});
        const mapper = try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 1, validationLine, &.{}));
        const lines = try scope.invoke(try scope.invoke(errors, "map", &.{mapper}), "join", &.{try scope.text("\n")});
        const detail = if (scope.truthy(lines)) lines else try scope.text("Unknown schema error");
        return instance(&scope, owner, try map(&scope), try message(&scope, owner, "Invalid models.json schema:\n", detail));
    }
    const providers = try map(&scope);
    const entries = try scope.invoke(try scope.global("Object"), "entries", &.{try scope.get(parsed, "providers")});
    var iterator = try v.iterator(&scope, entries);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        var pair = try v.iterator(&scope, entry);
        defer pair.deinit();
        errdefer pair.closePreserving();
        const id = try scope.own((try pair.next()) orelse c.pi_js_undefined());
        const provider = try scope.own((try pair.next()) orelse c.pi_js_undefined());
        try pair.close();
        const set = try scope.get(providers, "set");
        const cloned = try scope.call(try scope.global("structuredClone"), c.pi_js_undefined(), &.{provider});
        _ = try scope.call(set, providers, &.{ id, try frozen(&scope, cloned) });
    }
    try instance(&scope, owner, providers, c.pi_js_undefined());
}
