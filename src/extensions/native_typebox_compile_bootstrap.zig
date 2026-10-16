//! Shared module seams for TypeBox's actual native compiler dependency graph.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const ordinary = @import("native_node_function.zig");
const o = @import("native_typebox_compile_ops.zig");
const ir = @import("native_typebox_compile_ir.zig");
const c = js.c;
const Engine = js.Engine;
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn match(e: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const actual = arg(args, 0);
    const table = arg(args, 1);
    const length = try s.get(actual, "length");
    const selected = try s.own(try js.getKey(e, table, length));
    if (!c.JS_IsUndefined(selected) and !c.JS_IsNull(selected)) {
        const result = try o.callSpread(&s, selected, c.pi_js_undefined(), actual);
        if (!c.JS_IsUndefined(result) and !c.JS_IsNull(result)) return c.JS_DupValue(e.context, result);
    }
    const error_ctor = try s.global("Error");
    const value = try s.call(error_ctor, c.pi_js_undefined(), &.{try s.text("Invalid Arguments")});
    _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, value));
    return js.capture(e);
}
fn environmentEvaluate(e: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    // Public Environment.Evaluate is the actual guest-language API. The native
    // compiler backend does not call this API with its generated checker source.
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const function = try s.get(try s.global("globalThis"), "Function");
    return c.JS_DupValue(e.context, try o.construct(&s, function, args));
}
fn canEvaluate(e: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const state = roots[0];
    var supported = try s.get(state, "supported");
    if (c.JS_IsUndefined(supported)) {
        const Outcome = struct {
            fn probe(engine: *Engine) !void {
                var scope: Scope = .{ .engine = engine };
                defer scope.deinit();
                const function = try scope.own(try environmentEvaluate(engine, c.pi_js_undefined(), &.{try scope.text("null")}, &.{}));
                _ = try scope.call(function, c.pi_js_undefined(), &.{});
            }
        };
        var works = true;
        Outcome.probe(e) catch |err| {
            if (err != error.JavaScriptException) return err;
            works = false;
            if (e.captured_exception) |exception| e.freeValue(exception);
            e.captured_exception = null;
        };
        supported = o.boolean(&s, works);
        try s.set(state, "supported", supported);
    }
    if (!s.truthy(supported)) return c.JS_DupValue(e.context, supported);
    const settings = try s.get(state, "Settings");
    const current = try s.invoke(settings, "Get", &.{});
    return js.get(e, current, "useAcceleration");
}
fn wrapBuild(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const graph = roots[0];
    const previous = try ir.begin(e, graph);
    defer e.freeValue(previous);
    const built = js.call(e, roots[1], receiver, args) catch |err| {
        ir.restore(e, graph, previous) catch {};
        return err;
    };
    errdefer e.freeValue(built);
    try ir.finish(e, graph, built, previous);
    return built;
}
pub fn external(e: *Engine, graph: c.JSValue, shared: c.JSValue) !void {
    if (e.url_class == 0) try @import("native_url.zig").install(e);
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const modules = try s.get(graph, "modules");
    const settings = try s.get(shared, "Settings");
    const memory = try s.get(shared, "Memory");
    const types = try s.get(shared, "Type");
    inline for (.{ "type/index.mjs", "type/type.mjs" }) |path| try s.put(modules, path, types);
    const type_schema = try s.object();
    inline for (.{ "IsSchema", "IsKind" }) |name| try s.put(type_schema, name, try s.get(types, name));
    try s.put(modules, "type/types/schema.mjs", type_schema);
    const template_literal = try s.object();
    try s.put(template_literal, "TemplateLiteralDecode", try s.get(types, "TemplateLiteralDecode"));
    try s.put(modules, "type/engine/template_literal/index.mjs", template_literal);
    const settings_module = try s.object();
    try s.put(settings_module, "Settings", settings);
    try s.put(modules, "system/settings/index.mjs", settings_module);
    const memory_module = try s.object();
    try s.put(memory_module, "Memory", memory);
    try s.put(modules, "system/memory/index.mjs", memory_module);
    const clone_module = try s.object();
    try s.put(clone_module, "Clone", try s.get(memory, "Clone"));
    try s.put(modules, "system/memory/clone.mjs", clone_module);
    const argument_namespace = try s.object();
    try s.put(argument_namespace, "Match", try s.own(try ordinary.create(e, "Match", 2, match, &.{})));
    const arguments_module = try s.object();
    try s.put(arguments_module, "Arguments", argument_namespace);
    try s.put(modules, "system/arguments/index.mjs", arguments_module);
    const state = try s.object();
    try s.put(state, "supported", c.pi_js_undefined());
    try s.put(state, "Settings", settings);
    const environment = try s.object();
    try s.put(environment, "CanEvaluate", try s.own(try ordinary.create(e, "CanEvaluate", 0, canEvaluate, &.{state})));
    try s.put(environment, "Evaluate", try s.own(try ordinary.create(e, "Evaluate", 0, environmentEvaluate, &.{})));
    const environment_module = try s.object();
    try s.put(environment_module, "Environment", environment);
    try s.put(modules, "system/environment/index.mjs", environment_module);
    try @import("native_schema_formats.zig").install(e);
    const format = try s.own(try js.get(e, e.native_module_values.get("typebox/format").?, "Format"));
    const format_module = try s.object();
    try s.put(format_module, "Format", format);
    try s.put(modules, "format/index.mjs", format_module);
    const hashing_namespace = if (e.native_module_values.get("typebox/system")) |system| try s.get(system, "Hashing") else c.pi_js_undefined();
    const hashing = if (c.JS_IsObject(hashing_namespace)) hashing_namespace else try s.object();
    if (!c.JS_IsObject(hashing_namespace)) try s.put(hashing, "Hash", try s.own(try @import("native_schema_hashing.zig").createFunction(e)));
    const hashing_module = try s.object();
    try s.put(hashing_module, "Hashing", hashing);
    try s.put(modules, "system/hashing/index.mjs", hashing_module);
    const system = try s.object();
    try s.put(system, "Settings", settings);
    try s.put(system, "Memory", memory);
    try s.put(system, "Environment", environment);
    try s.put(system, "Arguments", argument_namespace);
    try s.put(system, "Hashing", hashing);
    inline for (.{ "system/index.mjs", "system/system.mjs" }) |path| try s.put(modules, path, system);
}
pub fn lower(e: *Engine, graph: c.JSValue) !void {
    var codec_scope: Scope = .{ .engine = e };
    defer codec_scope.deinit();
    const types = try codec_scope.get(graph, "Type");
    const codec_module = try codec_scope.get(try codec_scope.get(graph, "modules"), "type/types/_codec.mjs");
    inline for (.{ "Codec", "Decode", "Encode", "IsCodec", "DecodeBuilder", "EncodeBuilder" }) |name| try codec_scope.put(types, name, try codec_scope.get(codec_module, name));
    try ir.prepare(e, graph);
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const modules = try s.get(graph, "modules");
    const namespace = try s.get(modules, "schema/build.mjs");
    const original = try s.get(namespace, "Build");
    const function = try s.own(try ordinary.create(e, "Build", 0, wrapBuild, &.{ graph, original }));
    try s.put(namespace, "Build", function);
    const frame = try s.get(try s.get(graph, "frames"), "schema/build.mjs");
    const binding = try s.get(try s.get(try s.get(graph, "bindings"), "schema/build.mjs"), "Build");
    try o.defineKey(&s, frame, binding, function);
}
