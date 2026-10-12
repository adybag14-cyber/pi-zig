//! Source-shaped CodeMode tool factory and invocation prelude. Installation is
//! explicit until the complete public extension/export surface is qualified.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const vm = @import("native_values.zig");
const durable = @import("native_durable.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const awaiting = @import("native_durable_await.zig");
const journal = @import("native_durable_codemode_journal.zig");
const parser = @import("../mcp/codemode_source.zig");
const declarations = @import("../mcp/codemode_declarations.zig");
const discovery = @import("../mcp/codemode_discovery.zig");
const json = @import("../durable/backend/json.zig");
const c = em.c;
fn item(scope: *Scope, array: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, array, @intCast(index))));
}
fn append(scope: *Scope, array: c.JSValue, value: c.JSValue) !void {
    _ = try scope.invoke(array, "push", &.{value});
}
fn modelsEnabled(scope: *Scope, options: c.JSValue) !bool {
    return !scope.equal(try scope.get(options, "models"), c.pi_js_bool(scope.engine.context, 0));
}
pub fn createTool(engine: *em.Engine, exports: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bundle = try scope.object();
    try scope.put(bundle, "options", options);
    try scope.put(bundle, "documents", try scope.own(try journal.createDocuments(engine, exports)));
    var metadata = try json.Owned.parse(engine.gpa, @embedFile("../durable/fixtures/durable-19cb534-codemode-tool-metadata.json"));
    defer metadata.deinit();
    const definition = try scope.own(try durable.jsValue(engine, metadata.value.array.items[if (try modelsEnabled(&scope, options)) 1 else 0]));
    var captures = [_]c.JSValue{bundle};
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, execute, "execute", 3, 0, captures.len, &captures)));
    try scope.put(definition, "execute", function);
    return c.JS_DupValue(engine.context, try scope.invoke(exports, "defineTool", &.{definition}));
}
fn execute(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return begin(engine, captures[0], args[0..@intCast(argc)]) catch |err| durable.rejectedPromise(engine, err);
}
fn begin(engine: *em.Engine, bundle: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const source = try engine.toString(try scope.get(args[0], "code"));
    defer engine.gpa.free(source);
    const parsed = parser.parse(engine.gpa, source) catch |err| {
        if (err == error.OutOfMemory) return err;
        const message = try parser.diagnosticForInput(engine.gpa, source, err);
        defer engine.gpa.free(message);
        return @import("native_sdk.zig").sourceError(engine, message);
    };
    const state = try scope.object();
    try scope.put(state, "bundle", bundle);
    try scope.put(state, "api", args[1]);
    try scope.put(state, "context", args[2]);
    try scope.put(state, "code", try scope.text(parsed.code));
    if (parsed.max_output_tokens) |value| try scope.put(state, "maxOutputTokens", c.JS_NewFloat64(engine.context, @floatFromInt(value)));
    if (parsed.timeout_ms) |value| try scope.put(state, "timeoutMs", c.JS_NewFloat64(engine.context, @floatFromInt(value)));
    const docs = try scope.get(bundle, "documents");
    var captured: awaiting.Intrinsics = .{ .constructor = try scope.get(docs, "promiseConstructor"), .resolve = try scope.get(docs, "promiseResolve"), .then_function = try scope.get(docs, "promiseThen") };
    return awaiting.continueWith(agentReady, engine, &captured, state, try scope.invoke(args[1], "agent", &.{args[2]}), 0);
}
fn identifier(scope: *Scope, name: c.JSValue) !c.JSValue {
    const raw = try scope.engine.toString(name);
    defer scope.engine.gpa.free(raw);
    const id = try discovery.identifier(scope.engine.gpa, raw);
    defer scope.engine.gpa.free(id);
    return scope.text(id);
}
fn sample(scope: *Scope, tool: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const name = try engine.toString(try scope.get(tool, "name"));
    defer engine.gpa.free(name);
    const description = try engine.toString(try scope.get(tool, "description"));
    defer engine.gpa.free(description);
    var input = try durable.owned(engine, try scope.get(tool, "parameters"));
    defer input.deinit();
    const schema = try scope.get(tool, "structuredOutputSchema");
    var output = if (c.JS_IsUndefined(schema)) try json.Owned.parse(engine.gpa, "{\"type\":\"string\"}") else try durable.owned(engine, schema);
    defer output.deinit();
    const rendered = try declarations.sample(engine.gpa, name, description, input.value, output.value);
    defer engine.gpa.free(rendered);
    return scope.text(rendered);
}
fn namespace(scope: *Scope, name: c.JSValue, choices: c.JSValue) !c.JSValue {
    var found = c.pi_js_undefined();
    var length: f64 = -1;
    for (0..try vm.length(scope.engine, choices)) |i| {
        const entry = try item(scope, choices, i);
        const prefix = try scope.get(entry, "prefix");
        var count: f64 = 0;
        if (c.JS_ToFloat64(scope.engine.context, &count, try scope.get(prefix, "length")) < 0) return js.capture(scope.engine);
        if (scope.truthy(try scope.invoke(name, "startsWith", &.{prefix})) and count > length) {
            found = entry;
            length = count;
        }
    }
    return found;
}
fn agentReady(engine: *em.Engine, state: c.JSValue, agent: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, agent)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bundle = try scope.get(state, "bundle");
    const options = try scope.get(bundle, "options");
    const callable = try scope.get(agent, "callable");
    const tools = try scope.array();
    const namespaces = try scope.array();
    var choices = try scope.get(options, "namespaces");
    if (c.JS_IsUndefined(choices) or c.JS_IsNull(choices)) choices = try scope.array();
    for (0..try vm.length(engine, callable)) |i| {
        const tool = try item(&scope, callable, i);
        const name = try scope.get(tool, "name");
        const declaration = try scope.object();
        try scope.put(declaration, "name", name);
        try scope.put(declaration, "jsName", try identifier(&scope, name));
        try scope.put(declaration, "description", try sample(&scope, tool));
        const schema = try scope.get(tool, "structuredOutputSchema");
        if (!c.JS_IsUndefined(schema)) try scope.put(declaration, "structured", c.pi_js_bool(engine.context, 1));
        const hidden = scope.truthy(try scope.invoke(name, "startsWith", &.{try scope.text("pi.codemode.")}));
        if (hidden) try scope.put(declaration, "hidden", c.pi_js_bool(engine.context, 1));
        try append(&scope, tools, declaration);
        if (hidden) continue;
        const own = try namespace(&scope, name, choices);
        if (c.JS_IsUndefined(own)) continue;
        const namespace_name = try scope.get(own, "name");
        var group = c.pi_js_undefined();
        for (0..try vm.length(engine, namespaces)) |j| {
            const candidate = try item(&scope, namespaces, j);
            if (scope.equal(try scope.get(candidate, "name"), namespace_name)) {
                group = candidate;
                break;
            }
        }
        if (c.JS_IsUndefined(group)) {
            group = try scope.object();
            try scope.put(group, "name", namespace_name);
            inline for (.{ "description", "instructions" }) |key| {
                const value = try scope.get(own, key);
                if (!c.JS_IsUndefined(value)) try scope.put(group, key, value);
            }
            try scope.put(group, "tools", try scope.array());
            try append(&scope, namespaces, group);
        }
        try append(&scope, try scope.get(group, "tools"), name);
    }
    const globals = try scope.array();
    inline for (.{ "searchTools", "describeTool", "describeNamespace" }) |name| {
        const value = try scope.object();
        try scope.put(value, "name", try scope.text(name));
        try scope.put(value, "spread", c.pi_js_bool(engine.context, 1));
        try append(&scope, globals, value);
    }
    if (try modelsEnabled(&scope, options)) inline for (.{ "models.getModelsOfType", "models.getAvailableOfType", "models.getModelOfType", "models.classify", "models.generateImages" }) |name| {
        const value = try scope.object();
        try scope.put(value, "name", try scope.text(name));
        try scope.put(value, "spread", c.pi_js_bool(engine.context, 1));
        try append(&scope, globals, value);
    };
    var custom = try scope.get(options, "globals");
    if (c.JS_IsUndefined(custom) or c.JS_IsNull(custom)) custom = try scope.array();
    for (0..try vm.length(engine, custom)) |i| {
        const given = try item(&scope, custom, i);
        const value = try scope.object();
        try scope.put(value, "name", try scope.get(given, "name"));
        try scope.put(value, "spread", c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(given, "spread"), c.pi_js_bool(engine.context, 1)))));
        try append(&scope, globals, value);
    }
    const start = try scope.object();
    const now = try scope.invoke(try scope.global("Date"), "now", &.{});
    try scope.put(start, "version", c.JS_NewInt32(engine.context, 2));
    try scope.put(start, "startedAt", now);
    var seed_bytes: [4]u8 = undefined;
    try std.Io.randomSecure(engine.native_io orelse return error.NativeIoRequired, &seed_bytes);
    try scope.put(start, "seed", c.JS_NewFloat64(engine.context, @floatFromInt(std.mem.readInt(u32, &seed_bytes, .little))));
    const timeout = try scope.get(state, "timeoutMs");
    if (!c.JS_IsUndefined(timeout)) try scope.put(start, "deadline", try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 0, now, timeout))));
    try scope.put(start, "tools", tools);
    try scope.put(start, "namespaces", namespaces);
    try scope.put(start, "globals", globals);
    const budget = try scope.get(state, "maxOutputTokens");
    try scope.put(start, "maxOutputTokens", if (c.JS_IsUndefined(budget)) c.JS_NewInt32(engine.context, 10000) else budget);
    return @import("native_durable_codemode_call.zig").execute(engine, try scope.get(bundle, "documents"), try scope.get(state, "api"), try scope.get(state, "context"), try scope.get(options, "sandbox"), try scope.get(state, "code"), start, custom);
}
