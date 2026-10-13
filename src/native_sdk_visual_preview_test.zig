const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const visual = @import("extensions/native_sdk_visual_line_preview.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;

fn truncateCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var args: [5]c.JSValue = @splat(c.pi_js_undefined());
    for (0..@min(args.len, @as(usize, @intCast(argc)))) |index| args[index] = argv[index];
    if (c.JS_IsUndefined(args[3])) args[3] = c.JS_NewInt32(engine.context, 0);
    if (c.JS_IsUndefined(args[4])) args[4] = scope.text("end") catch |err| return sdk.fail(engine, err);
    const result = visual.truncate(&scope, args[0], args[1], args[2], args[3], args[4]) catch |err| return sdk.fail(engine, err);
    return c.JS_DupValue(engine.context, result);
}
fn setup(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    var environment = try std.testing.environ.createMap(engine.gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-tool-visual-preview"});
    try @import("extensions/native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "VisualLinePreview", try visual.constructor(engine));
    try sdk.put(engine, global, "truncateToVisualLines", try engine.checked(c.JS_NewCFunction(engine.context, truncateCall, "truncateToVisualLines", 3)));
}
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-tool-visual-preview-e622.input.txt"), "visual-preview-source-cases.mjs") catch |err| {
        const original = engine.nativeAllocationError(err, generation);
        if (original != error.OutOfMemory) std.debug.print("VISUAL_PREVIEW_EXCEPTION error={s} generation_before={d} generation_after={d} captured_tag={d} diagnostic={s}\n", .{ @errorName(original), generation, engine.native_allocation_generation, if (engine.captured_exception) |value| c.pi_js_native_allocation_error_generation(value) else 0, engine.last_error orelse "none" });
        return original;
    };
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const rows = try sdk.get(engine, global, "sdkVisualPreviewRows");
    defer engine.freeValue(rows);
    const raw = try engine.stringify(rows);
    defer gpa.free(raw);
    var actual = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer actual.deinit();
    var expected = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/sdk-tool-visual-preview-e622.json"), .{});
    defer expected.deinit();
    const actual_json = try std.json.Stringify.valueAlloc(gpa, actual.value, .{});
    defer gpa.free(actual_json);
    const expected_json = try std.json.Stringify.valueAlloc(gpa, expected.value, .{});
    defer gpa.free(expected_json);
    if (!std.mem.eql(u8, actual_json, expected_json)) {
        std.debug.print("Actual VisualLinePreview Source mismatch:\n{s}\nExpected:\n{s}\n", .{ actual_json, expected_json });
        return error.VisualPreviewSourceMismatch;
    }
    const cleared = try engine.eval("delete globalThis.sdkVisualPreviewRows;", "visual-preview-release.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(cleared);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native SDK tool visual preview matches full original wrapped lines cache identities metadata and hints" {
    try exercise(std.testing.allocator);
}
test "native SDK tool visual preview retains real callback and component until reference disposal" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const setup_result = try engine.evalModule(
        \\(()=>{const marker={value:'alive'},preview=new VisualLinePreview({text:'a\nb\nc',maxVisualLines:1,keep:'end',formatHint:hidden=>marker.value+hidden});globalThis.visualPreviewHeld=preview;globalThis.visualPreviewWeak=new WeakRef(marker);globalThis.visualPreviewComponentWeak=new WeakRef(preview);})();
    , "visual-preview-gc-setup.mjs");
    engine.freeValue(setup_result);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval("if(!visualPreviewWeak.deref()||visualPreviewHeld.render(16)[0]!=='alive2')throw Error('visual preview callback lost');delete globalThis.visualPreviewHeld;", "visual-preview-gc-held.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(retained);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const released = try engine.eval("if(visualPreviewWeak.deref()!==undefined||visualPreviewComponentWeak.deref()!==undefined)throw Error('visual preview retained after disposal');delete globalThis.visualPreviewWeak;delete globalThis.visualPreviewComponentWeak;", "visual-preview-gc-released.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(released);
}
test "native SDK tool visual preview releases every original full-probe allocation failure" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa) catch |err| {
                if (err != error.OutOfMemory) {
                    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                    std.debug.print("VISUAL_PREVIEW_GPA_FAILURE fail_index={d} alloc_index={d} induced={any} error={s}\n", .{ failing.fail_index, failing.alloc_index, failing.has_induced_failure, @errorName(err) });
                    std.debug.print("VISUAL_PREVIEW_GPA_ALLOCATION_STACK={f}\n", .{std.debug.FormatStackTrace{ .stack_trace = failing.getStackTrace() }});
                }
                return err;
            };
        }
    };
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-tool-visual-preview", Probe.run, .{});
}
