const std = @import("std");
const rt = @import("pi_zig").extensions.js_runtime;
const ui = @import("pi_zig").extensions.ui;
const Io = std.Io;
test "native Main UI sync process blocks guest jobs preserves sibling replies and propagates actual frontend errors" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var inherited = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer inherited.deinit();
    const binary = inherited.get("PI_UI_SERVICE_TEST_BINARY") orelse return error.MissingNativeServiceFixtureBinary;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(io, .{ .sub_path = "sync.mjs", .data = "export default pi=>{pi.registerCommand('blocked',{handler(_args,ctx){const ui=ctx.ui;globalThis.savedUI=ui;ui.notify('before');Promise.resolve().then(()=>ui.notify('microtask'));void ui.input('sibling','').then(value=>ui.notify('sibling:'+value));const value=ui.getToolsExpanded();ui.notify('after');return{value}}});pi.registerCommand('failure',{handler(){try{savedUI.getToolsExpanded();return{missing:true}}catch(error){return{name:error.name,message:error.message}}}})}" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(io, &buffer);
    const source = try std.fs.path.join(gpa, &.{ buffer[0..length], "sync.mjs" });
    defer gpa.free(source);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", std.fs.path.dirname(binary).?);
    try environment.put("HOME", buffer[0..length]);
    try environment.put("USERPROFILE", buffer[0..length]);
    try environment.put("PI_OFFLINE", "1");
    if (inherited.get("SystemRoot")) |value| try environment.put("SystemRoot", value);
    var started = try rt.Runtime.startNativeGroup(gpa, io, &.{source}, .{ .executable = binary, .environ_map = &environment, .startup_context_json = "{\"hasUI\":true,\"mode\":\"interactive\"}" });
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try started.runtime.setContextJson("{\"hasUI\":true,\"mode\":\"interactive\"}");
    var controller = try ui.Controller.init(gpa, io, true, 80);
    defer controller.deinit();
    try controller.applyAction("setToolsExpanded", "{\"expanded\":true}");
    const Held = struct {
        controller: *ui.Controller,
        entered: Io.Event = .unset,
        release: Io.Event = .unset,
        sibling: Io.Event = .unset,
        microtask: std.atomic.Value(bool) = .init(false),
        after: std.atomic.Value(bool) = .init(false),
        failed: std.atomic.Value(bool) = .init(false),
        fn request(raw: ?*anyopaque, allocator: std.mem.Allocator, method: []const u8, args: []const u8) ![]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (std.mem.eql(u8, method, "input")) return allocator.dupe(u8, "\"original-sibling\"");
            if (!std.mem.eql(u8, method, "getToolsExpanded")) return error.UnexpectedSyncMethod;
            if (self.failed.load(.acquire)) return error.SourceThemeWriteFailure;
            self.entered.set(std.testing.io);
            try self.release.wait(std.testing.io);
            return self.controller.request(allocator, method, args);
        }
        fn action(raw: ?*anyopaque, _: std.mem.Allocator, method: []const u8, args: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (!std.mem.eql(u8, method, "notify")) return;
            if (std.mem.indexOf(u8, args, "microtask") != null) self.microtask.store(true, .release);
            if (std.mem.indexOf(u8, args, "after") != null) self.after.store(true, .release);
            if (std.mem.indexOf(u8, args, "sibling:original-sibling") != null) self.sibling.set(std.testing.io);
        }
    };
    var held: Held = .{ .controller = &controller };
    started.runtime.setUiBridge(.{ .context = &held, .request_fn = Held.request, .action_fn = Held.action });
    const Invoke = struct {
        runtime: *rt.Runtime,
        result: ?[]u8 = null,
        failure: ?anyerror = null,
        done: Io.Event = .unset,
        fn run(self: *@This()) Io.Cancelable!void {
            defer self.done.set(std.testing.io);
            self.result = self.runtime.invokeCommand("blocked", "", "{}") catch |err| {
                self.failure = err;
                return;
            };
        }
    };
    var invocation: Invoke = .{ .runtime = started.runtime };
    var tasks: Io.Group = .init;
    defer {
        held.release.set(io);
        tasks.cancel(io);
        tasks.await(io) catch {};
        if (invocation.result) |value| gpa.free(value);
    }
    try tasks.concurrent(io, Invoke.run, .{&invocation});
    try held.entered.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
    try std.testing.expect(!held.microtask.load(.acquire));
    try std.testing.expect(!held.after.load(.acquire));
    held.release.set(io);
    try invocation.done.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
    try tasks.await(io);
    if (invocation.failure) |failure| return failure;
    try std.testing.expect(std.mem.indexOf(u8, invocation.result.?, "\"value\":true") != null);
    try held.sibling.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
    try std.testing.expect(held.microtask.load(.acquire));
    try std.testing.expect(held.after.load(.acquire));
    held.failed.store(true, .release);
    const failed = try started.runtime.invokeCommand("failure", "", "{}");
    defer gpa.free(failed);
    try std.testing.expect(std.mem.indexOf(u8, failed, "\"name\":\"Error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, failed, "SourceThemeWriteFailure") != null);
}
