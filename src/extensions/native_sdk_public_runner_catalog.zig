//! Public runner registry methods traverse the supplied real JS graph.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
pub fn invoke(engine: *em.Engine, runner: c.JSValue, method: []const u8, args: []const c.JSValue) !c.JSValue {
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    if (std.mem.eql(u8, method, "setFlagValue") or std.mem.eql(u8, method, "getFlagValues")) {
        const runtime = try sdk.get(engine, runner, "runtime");
        defer engine.freeValue(runtime);
        const flags = try sdk.get(engine, runtime, "flagValues");
        defer engine.freeValue(flags);
        if (std.mem.eql(u8, method, "getFlagValues")) return js.builtin(engine, "Map", &.{flags});
        const ignored = try js.invoke(engine, flags, "set", &.{ first, if (args.len > 1) args[1] else c.pi_js_undefined() });
        engine.freeValue(ignored);
        return c.pi_js_undefined();
    }
    const extensions = try sdk.get(engine, runner, "extensions");
    defer engine.freeValue(extensions);
    const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(symbol);
    if (std.mem.eql(u8, method, "getExtensionPaths")) {
        const mapper = try engine.checked(c.JS_NewCFunction(engine.context, path, "", 1));
        defer engine.freeValue(mapper);
        return js.invoke(engine, extensions, "map", &.{mapper});
    }
    const collecting_tools = std.mem.eql(u8, method, "getAllRegisteredTools");
    const collecting_flags = std.mem.eql(u8, method, "getFlags");
    const markdown = std.mem.eql(u8, method, "getMarkdownTransformers");
    const handlers = std.mem.eql(u8, method, "hasHandlers");
    const definition = std.mem.eql(u8, method, "getToolDefinition");
    const entries = std.mem.eql(u8, method, "getEntryRenderer");
    const collected = if (collecting_tools or collecting_flags) try js.builtin(engine, "Map", &.{}) else if (markdown) try sdk.array(engine) else c.pi_js_undefined();
    errdefer engine.freeValue(collected);
    var outer = try js.Iterator.init(engine, extensions, symbol);
    defer outer.deinit();
    errdefer outer.closePreserving();
    while (try outer.next()) |extension| {
        defer engine.freeValue(extension);
        if (markdown) {
            const transformer = try sdk.get(engine, extension, "markdownTransformer");
            defer engine.freeValue(transformer);
            if (c.JS_ToBool(engine.context, transformer) == 1) try js.push(engine, collected, transformer);
            continue;
        }
        const map = try sdk.get(engine, extension, if (collecting_tools or definition) "tools" else if (collecting_flags) "flags" else if (handlers) "handlers" else if (entries) "entryRenderers" else "messageRenderers");
        defer engine.freeValue(map);
        if (entries and (c.JS_IsUndefined(map) or c.JS_IsNull(map))) continue;
        if (!collecting_tools and !collecting_flags) {
            const item = try js.invoke(engine, map, "get", &.{first});
            defer engine.freeValue(item);
            if (c.JS_ToBool(engine.context, item) != 1) continue;
            if (handlers) {
                const length = try sdk.get(engine, item, "length");
                defer engine.freeValue(length);
                const more = try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, length, c.JS_NewInt32(engine.context, 0)));
                defer engine.freeValue(more);
                if (c.JS_ToBool(engine.context, more) != 1) continue;
            }
            try outer.close();
            return if (handlers) c.pi_js_bool(engine.context, 1) else if (definition) sdk.get(engine, item, "definition") else c.JS_DupValue(engine.context, item);
        }
        const iterable = if (collecting_tools) try js.invoke(engine, map, "values", &.{}) else c.JS_DupValue(engine.context, map);
        defer engine.freeValue(iterable);
        var inner = try js.Iterator.init(engine, iterable, symbol);
        defer inner.deinit();
        errdefer inner.closePreserving();
        while (try inner.next()) |raw| {
            defer engine.freeValue(raw);
            const pair = if (collecting_flags) try js.pair(engine, raw, symbol) else pair: {
                const tool = try sdk.get(engine, raw, "definition");
                defer engine.freeValue(tool);
                break :pair [2]c.JSValue{ try sdk.get(engine, tool, "name"), c.JS_DupValue(engine.context, raw) };
            };
            defer for (pair) |value| engine.freeValue(value);
            const present = try js.invoke(engine, collected, "has", &.{pair[0]});
            defer engine.freeValue(present);
            if (c.JS_ToBool(engine.context, present) != 1) {
                const ignored = try js.invoke(engine, collected, "set", &pair);
                engine.freeValue(ignored);
            }
        }
    }
    if (collecting_flags or markdown) return collected;
    if (collecting_tools) {
        defer engine.freeValue(collected);
        const values = try js.invoke(engine, collected, "values", &.{});
        defer engine.freeValue(values);
        const array = try js.global(engine, "Array");
        defer engine.freeValue(array);
        return js.invoke(engine, array, "from", &.{values});
    }
    return if (handlers) c.pi_js_bool(engine.context, 0) else c.pi_js_undefined();
}
fn path(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return sdk.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "path") catch |err| sdk.fail(engine, err);
}
