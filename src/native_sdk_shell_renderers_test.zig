const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const shell = @import("extensions/native_sdk_builtin_shell_renderers.zig");
const utils = @import("extensions/native_sdk_builtin_render_utils.zig");
const c = em.c;

fn createCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return shell.create(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn durationCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: utils.Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = utils.formatDuration(&scope, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.JS_DupValue(engine.context, value);
}

fn setup(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    var environment = try std.testing.environ.createMap(engine.gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-tool-shell-renderers"});
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/native_tui.zig").install(engine);
    const theme = try @import("extensions/native_theme.zig").fromJson(engine, @embedFile("extensions/fixtures/sdk-tool-renderers-e622-dark.json"), "C:/Users/adyba/pi-sdk-loadout-source-e6220e1-20261013/packages/coding-agent/src/modes/interactive/theme/dark.json", .truecolor);
    defer engine.freeValue(theme);
    try @import("extensions/native_theme.zig").setThemeInstance(engine, theme);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "actualRendererTheme", c.JS_DupValue(engine.context, theme));
    try sdk.put(engine, global, "createShellRenderers", try engine.checked(c.JS_NewCFunction(engine.context, createCall, "createShellRenderers", 1)));
    try sdk.put(engine, global, "formatToolDuration", try engine.checked(c.JS_NewCFunction(engine.context, durationCall, "formatToolDuration", 1)));
    try sdk.put(engine, global, "ignoredRendererTheme", c.pi_js_undefined());
    const configured = try engine.evalModule("import{setCapabilityOverrides}from'pi-tui';setCapabilityOverrides({images:null,hyperlinks:false});", "shell-renderers-capabilities.mjs");
    engine.freeValue(configured);
}
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    setup(engine) catch |err| return engine.nativeAllocationError(err, generation);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-tool-shell-renderers-e622.input.txt"), "shell-renderers-source-cases.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const rows = try sdk.get(engine, global, "sdkShellRendererRows");
    defer engine.freeValue(rows);
    const raw = try engine.stringify(rows);
    defer gpa.free(raw);
    var actual = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer actual.deinit();
    var expected = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/sdk-tool-shell-renderers-e622.json"), .{});
    defer expected.deinit();
    const actual_json = try std.json.Stringify.valueAlloc(gpa, actual.value, .{});
    defer gpa.free(actual_json);
    const expected_json = try std.json.Stringify.valueAlloc(gpa, expected.value, .{});
    defer gpa.free(expected_json);
    if (!std.mem.eql(u8, actual_json, expected_json)) {
        std.debug.print("Actual ShellRenderer Source mismatch:\n{s}\nExpected:\n{s}\n", .{ actual_json, expected_json });
        return error.ShellRendererSourceMismatch;
    }
    const cleared = try engine.eval("delete globalThis.sdkShellRendererRows;", "shell-renderers-release.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(cleared);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native SDK tool shell renderers match full original53 Bash PowerShell timers durations metadata and visual output" {
    try exercise(std.testing.allocator);
}
test "native SDK tool shell renderers retain prompt preview and live interval roots until final reuse then release" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const initial = try engine.evalModule(
        "globalThis.shellFactory=createShellRenderers('PS>');globalThis.shellContext={state:{startedAt:1000,endedAt:5000},durationMs:4250};" ++
            "globalThis.shellHeld=shellFactory.renderResult({content:[{type:'text',text:'kept'}]},{isPartial:true,expanded:false},undefined,shellContext);" ++
            "shellContext.lastComponent=shellHeld;globalThis.shellWeak=new WeakRef(shellHeld);if(!shellContext.state.interval)throw Error('missing live interval');",
        "shell-renderers-gc-setup.mjs",
    );
    engine.freeValue(initial);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval(
        "if(shellFactory.renderCall({command:'kept'},undefined,{state:{}}).text.indexOf('PS>')<0)throw Error('shell prompt lost');" ++
            "if(shellFactory.renderResult({content:[{type:'text',text:'done'}]},{isPartial:false,expanded:false},undefined,shellContext)!==shellHeld)throw Error('shell result identity lost');" ++
            "if(shellContext.state.interval!==undefined||!shellHeld.render(40).join('').includes('done'))throw Error('shell final timer/render lost');" ++
            "delete globalThis.shellHeld;delete globalThis.shellContext;delete globalThis.shellFactory;",
        "shell-renderers-gc-held.js",
        c.JS_EVAL_TYPE_GLOBAL,
    );
    engine.freeValue(retained);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const released = try engine.eval("if(shellWeak.deref()!==undefined)throw Error('shell timer retained disposed component');delete globalThis.shellWeak;", "shell-renderers-gc-released.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(released);
}
test "native SDK tool shell renderers release every original full-probe allocation failure" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-tool-shell-renderers", exercise, .{});
}
