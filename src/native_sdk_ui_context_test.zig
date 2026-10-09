const std = @import("std");
const builtin = @import("builtin");
const engine_mod = @import("extensions/engine.zig");
const group_mod = @import("extensions/native_group.zig");
const json = @import("mcp/protocol.zig").json;
fn exercise(gpa: std.mem.Allocator, allocation_probe: bool) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const binding = try group.add("sdk-ui-allocation.mjs");
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try binding.installSchemas();
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    const source = try std.mem.replaceOwned(u8, gpa, @embedFile("extensions/fixtures/sdk-ui-context-6fb2e78.txt"), "__SDK_UI_CWD__", if (builtin.os.tag == .windows) "'C:/sdk-ui-allocation'" else "'/sdk-ui-allocation'");
    defer gpa.free(source);
    try binding.loadFactory(source, "sdk-ui-allocation.mjs");
    const result = try binding.invokeCommand("sdk-ui-result", "");
    defer gpa.free(result);
    if (allocation_probe) {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (failing.has_induced_failure) return error.OutOfMemory;
    }
    var envelope = try json.Owned.parse(gpa, result);
    defer envelope.deinit();
    const message = envelope.value.object.get("message") orelse return error.MissingSdkUiResult;
    var actual = try json.Owned.parse(gpa, message.string);
    defer actual.deinit();
    var expected = try json.Owned.parse(gpa, @embedFile("extensions/fixtures/sdk-ui-context-6fb2e78.json"));
    defer expected.deinit();
    try std.testing.expect(json.equal(expected.value, actual.value));
    engine_mod.c.JS_RunGC(engine.runtime);
}
test "native SDK UI event owners reproduce actual Source lifecycle under the testing allocator" {
    try exercise(std.testing.allocator, false);
}
test "native SDK UI owner retirement preserves ordinary pending JavaScript and stale context errors" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-ui-retirement-root");
    try root.installSchemas();
    const loaded = try engine.evalModule(
        "import {DefaultResourceLoader,createAgentSession,SessionManager,SettingsManager} from '@earendil-works/pi-coding-agent';" ++
            "const loader=new DefaultResourceLoader({cwd:'/sdk-ui-retirement',noExtensions:true,noSkills:true,noThemes:true,noPromptTemplates:true,extensionFactories:[pi=>pi.on('session_start',async(_event,ctx)=>{globalThis.removedEventStarted=true;await new Promise(resolve=>globalThis.releaseRemovedEvent=resolve);globalThis.removedEventBookkeeping=true;try{ctx.mode;globalThis.removedEventError='allowed'}catch(error){globalThis.removedEventError=error.message}})]});await loader.reload();" ++
            "const {session}=await createAgentSession({cwd:'/sdk-ui-retirement',resourceLoader:loader,sessionManager:SessionManager.inMemory('/sdk-ui-retirement'),settingsManager:SettingsManager.inMemory(),tools:[]});globalThis.startRemovedEvent=()=>session.bindExtensions({mode:'rpc'});",
        "sdk-ui-retirement.mjs",
    );
    defer engine.freeValue(loaded);
    const pending = try engine.eval("startRemovedEvent()", "sdk-ui-retirement-start.js", engine_mod.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(pending);
    try std.testing.expectEqual(engine_mod.c.JS_PROMISE_PENDING, engine_mod.c.JS_PromiseState(engine.context, pending));
    try std.testing.expectEqual(@as(usize, 2), group.entries.items.len);
    try group.remove(group.entries.items[1].id);
    const released = try engine.eval("releaseRemovedEvent()", "sdk-ui-retirement-release.js", engine_mod.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(released);
    const settled = try engine.awaitValue(pending);
    defer engine.freeValue(settled);
    const proof = try engine.eval("({started:removedEventStarted,bookkeeping:removedEventBookkeeping,error:removedEventError})", "sdk-ui-retirement-proof.js", engine_mod.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(proof);
    const actual = try engine.stringify(proof);
    defer std.testing.allocator.free(actual);
    var parsed = try json.Owned.parse(std.testing.allocator, actual);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("started").?.bool and parsed.value.object.get("bookkeeping").?.bool);
    try std.testing.expectEqualStrings(@import("extensions/native_context_lifetime.zig").default_message, parsed.value.object.get("error").?.string);
}
test "native SDK UI event owners release every failed host allocation" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa, true) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure) return error.OutOfMemory;
                return err;
            };
        }
    };
    const range = @import("sdk_ui_allocation_options").range;
    if (range == null) return std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try Probe.run(baseline.allocator());
    const count = baseline.alloc_index;
    var exercised: usize = 0;
    for (0..count) |index| {
        if (index % 8 != range.?) continue;
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        const outcome = Probe.run(failing.allocator());
        if (outcome) |_| return error.AllocationFailureNotObserved else |err| if (err != error.OutOfMemory) return err;
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        exercised += 1;
    }
    std.debug.print("SDK UI allocation range {d}/8 baseline {d} exercised {d}\n", .{ range.?, count, exercised });
}
