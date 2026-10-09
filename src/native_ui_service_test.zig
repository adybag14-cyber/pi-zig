const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const bindings_mod = @import("extensions/native_bindings.zig");
const ui = @import("extensions/native_ui.zig");
const protocol = @import("extensions/native_ui_service_protocol.zig");
const c = engine_mod.c;

const Frontend = struct {
    manager: *ui.Manager,
    opened: usize = 0,
    closed: usize = 0,
    calls: usize = 0,
    fn open(raw: ?*anyopaque, _: protocol.Lease) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.opened += 1;
    }
    fn close(raw: ?*anyopaque, _: protocol.Lease) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.closed += 1;
    }
    fn request(raw: ?*anyopaque, id: u32, _: []const u8, _: []const u8) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.calls += 1;
        if (self.manager.service == null) return error.MissingNativeServiceLease;
        const result = try self.manager.engine.checked(c.JS_NewString(self.manager.engine.context, "original-service"));
        defer self.manager.engine.freeValue(result);
        try self.manager.respond(id, true, result);
    }
    fn action(_: ?*anyopaque, _: []const u8, _: []const u8) !void {}
    fn cancel(_: ?*anyopaque, _: u32) !void {}
};

test "native UI service survives the completed Main invocation and preserves a denied SDK token" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const owner = try bindings_mod.Bindings.init(std.testing.allocator, engine);
    defer owner.deinit();
    var frontend: Frontend = .{ .manager = owner.ui_manager };
    owner.ui_manager.bridge = .{ .context = &frontend, .request = Frontend.request, .action = Frontend.action, .cancel = Frontend.cancel, .service_open = Frontend.open, .service_close = Frontend.close };
    try owner.loadFactory("export default pi=>{pi.registerCommand('capture',{handler(_args,ctx){globalThis.retainedMainUI=ctx.ui;return {same:ctx.ui===globalThis.retainedMainUI}}});pi.registerCommand('later',{async handler(){return {value:await retainedMainUI.input('retained','hint')}}})}", "main-ui-service.mjs");
    try owner.setContext("{\"hasUI\":true,\"mode\":\"interactive\"}");
    const captured = try owner.invokeCommand("capture", "");
    defer engine.gpa.free(captured);
    try std.testing.expectEqualStrings("{\"same\":true}", captured);
    try std.testing.expect(!owner.ui_manager.active);
    const later = try owner.invokeCommand("later", "");
    defer engine.gpa.free(later);
    try std.testing.expectEqualStrings("{\"value\":\"original-service\"}", later);
    try std.testing.expectEqual(@as(usize, 1), frontend.opened);
    try std.testing.expectEqual(@as(usize, 1), frontend.calls);
    const Scope = @import("extensions/native_async_scope.zig");
    const Noop = struct {
        fn change(_: ?*anyopaque) void {}
    };
    const token = try Scope.create(engine, null, Noop.change, Noop.change);
    defer engine.freeValue(token);
    Scope.markSdk(engine, token);
    try Scope.denyWithMessage(engine, token, "original stale SDK event");
    const scope = Scope.enter(engine, token);
    defer scope.restore();
    const result = try engine.evalModule("export const value=await retainedMainUI.input('stale-sdk','hint');", "retained-main-service-stale-sdk.mjs");
    defer engine.freeValue(result);
    const current = Scope.capture(engine);
    defer engine.freeValue(current);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, token, current));
    try std.testing.expectError(error.JavaScriptException, Scope.requireLive(engine));
    try std.testing.expectEqual(@as(usize, 2), frontend.calls);
}

test "native UI service foreign and replayed controls cannot settle an actual VM request" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const group = try @import("extensions/native_group.zig").Group.init(engine);
    defer group.deinit();
    const owner = try group.add("service-controls.mjs");
    const Held = struct {
        id: u32 = 0,
        fn request(raw: ?*anyopaque, id: u32, _: []const u8, _: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.id = id;
        }
        fn open(_: ?*anyopaque, _: protocol.Lease) !void {}
        fn close(_: ?*anyopaque, _: protocol.Lease) !void {}
        fn action(_: ?*anyopaque, _: []const u8, _: []const u8) !void {}
        fn cancel(_: ?*anyopaque, _: u32) !void {}
    };
    var held: Held = .{};
    group.ui.bridge = .{ .context = &held, .request = Held.request, .action = Held.action, .cancel = Held.cancel, .service_open = Held.open, .service_close = Held.close };
    try owner.loadFactory("export default pi=>pi.registerCommand('start',{handler(_args,ctx){const ui=ctx.ui;Object.assign(ui,{ownerGeneration:999,serviceId:999,serviceGeneration:999,extensionId:999});globalThis.actualServicePromise=ui.input('held','');void actualServicePromise.catch(()=>{});return {started:true}}})", "service-controls.mjs");
    try owner.setContext("{\"hasUI\":true}");
    const begun = try owner.invokeCommand("start", "");
    defer engine.gpa.free(begun);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const pending = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "actualServicePromise"));
    defer engine.freeValue(pending);
    const actual: protocol.Header = .{ .lease = group.ui.services.items[0].identity, .request_id = held.id };
    const Control = struct {
        fn send(target: *@import("extensions/native_group.zig").Group, header: protocol.Header, result: []const u8, ok: bool) !void {
            var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
            defer out.deinit();
            try out.writer.writeAll("{\"kind\":\"native_ui_service_response\",");
            try header.writeFields(&out.writer);
            try out.writer.writeAll(if (ok) ",\"ok\":true,\"result\":" else ",\"ok\":false,\"error\":");
            try std.json.Stringify.value(result, .{}, &out.writer);
            try out.writer.writeByte('}');
            var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, out.written(), .{});
            defer parsed.deinit();
            try target.uiServiceResponse(parsed.value.object);
        }
    };
    inline for (.{ "owner_generation", "service_id", "service_generation", "extension_id", "request_id" }) |field| {
        var foreign = actual;
        if (comptime std.mem.eql(u8, field, "request_id")) foreign.request_id += 1 else @field(foreign.lease, field) += 1;
        try Control.send(group, foreign, "foreign", true);
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
    }
    try Control.send(group, actual, "accepted", true);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, pending));
    try Control.send(group, actual, "replayed", true);
    const value = c.JS_PromiseResult(engine.context, pending);
    defer engine.freeValue(value);
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("accepted", text);
    const begun_again = try owner.invokeCommand("start", "");
    defer engine.gpa.free(begun_again);
    const rejected = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "actualServicePromise"));
    defer engine.freeValue(rejected);
    var failure_header = actual;
    failure_header.request_id = held.id;
    try Control.send(group, failure_header, "frontend failed", false);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, rejected));
    const exception = c.JS_PromiseResult(engine.context, rejected);
    defer engine.freeValue(exception);
    try std.testing.expect(c.JS_IsError(exception));
    const message = try engine.checked(c.JS_GetPropertyStr(engine.context, exception, "message"));
    defer engine.freeValue(message);
    const diagnostic = try engine.toString(message);
    defer engine.gpa.free(diagnostic);
    try std.testing.expectEqualStrings("frontend failed", diagnostic);
}

test {
    _ = protocol;
}
