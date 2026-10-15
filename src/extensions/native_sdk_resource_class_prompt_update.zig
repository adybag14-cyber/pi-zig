//! Ordinary Source prompt update with real parser, live dedupe and metadata callbacks.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var roots = [_]c.JSValue{try scope.own(try @import("native_sdk_prompt_loader.zig").create(engine))};
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "updatePromptsFromPaths", 2, 0, roots.len, &roots));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "updatePromptsFromPaths", function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, loader: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    update(engine, loader, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), roots[0]) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn mapped(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return attach(engine, roots[0], roots[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn attach(engine: *em.Engine, loader: c.JSValue, metadata: c.JSValue, prompt: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const copy = try scope.own(try js.spread(engine, prompt));
    const find = try scope.get(loader, "findSourceInfoForPath");
    const found = try scope.call(find, loader, &.{ try scope.get(prompt, "filePath"), try scope.get(loader, "extensionPromptSourceInfos"), metadata });
    const info = if (!temp.nullish(found)) found else selected: {
        const existing = try scope.get(prompt, "sourceInfo");
        if (!temp.nullish(existing)) break :selected existing;
        break :selected try scope.invoke(loader, "getDefaultSourceInfoForPath", &.{try scope.get(prompt, "filePath")});
    };
    try scope.put(copy, "sourceInfo", info);
    return c.JS_DupValue(engine.context, copy);
}
fn update(engine: *em.Engine, loader: c.JSValue, paths: c.JSValue, metadata: c.JSValue, load: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const base = if (scope.truthy(try scope.get(loader, "noPromptTemplates")) and scope.equal(try scope.get(paths, "length"), c.JS_NewInt32(engine.context, 0))) empty: {
        const result = try scope.object();
        try scope.put(result, "prompts", try scope.array());
        try scope.put(result, "diagnostics", try scope.array());
        break :empty result;
    } else loaded: {
        const options = try scope.object();
        try scope.put(options, "cwd", try scope.get(loader, "cwd"));
        try scope.put(options, "agentDir", try scope.get(loader, "agentDir"));
        try scope.put(options, "promptPaths", paths);
        try scope.put(options, "includeDefaults", c.pi_js_bool(engine.context, 0));
        const parsed = try scope.call(load, c.pi_js_undefined(), &.{options});
        const dedupe = try scope.get(loader, "dedupePrompts");
        const deduped = try scope.call(dedupe, loader, &.{try scope.get(parsed, "templates")});
        const result = try scope.object();
        try scope.put(result, "prompts", try scope.get(deduped, "prompts"));
        const diagnostics = try scope.array();
        var count: u32 = 0;
        try @import("native_sdk_resource_spread.zig").literal(&scope, diagnostics, try scope.get(parsed, "diagnostics"), &count);
        try @import("native_sdk_resource_spread.zig").literal(&scope, diagnostics, try scope.get(deduped, "diagnostics"), &count);
        try scope.put(result, "diagnostics", diagnostics);
        break :loaded result;
    };
    const resolved = if (scope.truthy(try scope.get(loader, "promptsOverride"))) try scope.invoke(loader, "promptsOverride", &.{base}) else base;
    const prompts = try scope.get(resolved, "prompts");
    const map = try scope.get(prompts, "map");
    var roots = [_]c.JSValue{ loader, metadata };
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, mapped, "", 1, 0, roots.len, &roots)));
    try scope.set(loader, "prompts", try scope.call(map, prompts, &.{callback}));
    try scope.set(loader, "promptDiagnostics", try scope.get(resolved, "diagnostics"));
}
