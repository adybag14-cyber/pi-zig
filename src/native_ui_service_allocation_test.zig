const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const group_mod = @import("extensions/native_group.zig");
const ui = @import("extensions/native_ui.zig");
const protocol = @import("extensions/native_ui_service_protocol.zig");
const c = engine_mod.c;

const Driver = struct {
    manager: *ui.Manager,
    fn open(_: ?*anyopaque, _: protocol.Lease) !void {}
    fn close(_: ?*anyopaque, _: protocol.Lease) !void {}
    fn action(_: ?*anyopaque, _: []const u8, _: []const u8) !void {}
    fn cancel(_: ?*anyopaque, _: u32) !void {}
    fn request(raw: ?*anyopaque, id: u32, _: []const u8, _: []const u8) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        const engine = self.manager.engine;
        const value = try engine.checked(c.JS_NewString(engine.context, "allocation-service"));
        defer engine.freeValue(value);
        try self.manager.respond(id, true, value);
    }
};

fn exerciseDialog(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    _ = try group.add("control-allocation.mjs");
    const owner = try group.add("service-allocation.mjs");
    var driver: Driver = .{ .manager = group.ui };
    group.ui.bridge = .{ .context = &driver, .request = Driver.request, .action = Driver.action, .cancel = Driver.cancel, .service_open = Driver.open, .service_close = Driver.close };
    try owner.loadFactory("export default pi=>{pi.registerCommand('capture',{handler(_,ctx){globalThis.allocationUI=ctx.ui;return {captured:true}}});pi.registerCommand('dialog',{async handler(){const controller=new AbortController();return {value:await allocationUI.input('later','hint',{signal:controller.signal})}}})}", "service-allocation.mjs");
    try owner.setContext("{\"hasUI\":true}");
    const captured = try owner.invokeCommand("capture", "");
    defer gpa.free(captured);
    const result = try owner.invokeCommand("dialog", "");
    defer gpa.free(result);
    try std.testing.expectEqualStrings("{\"value\":\"allocation-service\"}", result);
    try group.remove(owner.owner_id);
    const module = try engine.evalModule("export const value=await allocationUI.input('after-remove','hint');", "service-allocation-after-remove.mjs");
    defer engine.freeValue(module);
    const value = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "value"));
    defer engine.freeValue(value);
    const actual = try engine.toString(value);
    defer gpa.free(actual);
    try std.testing.expectEqualStrings("allocation-service", actual);
}

fn dialogProbe(gpa: std.mem.Allocator) !void {
    exerciseDialog(gpa) catch |err| {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (failing.has_induced_failure and (err == error.JavaScriptException or err == error.OutOfMemory)) return error.OutOfMemory;
        return err;
    };
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
    if (failing.has_induced_failure) return error.OutOfMemory;
}

test "native Main UI service allocation covers class wrappers signal retirement and retained frontend" {
    try @import("test_support/sdk_allocation_shards.zig").check("main-ui-service-dialog", dialogProbe, .{});
}

const ComponentDriver = struct {
    const components = @import("extensions/component_protocol.zig");
    const Pending = struct { header: protocol.Header, fence: components.Fence };
    group: *group_mod.Group,
    input: ?Pending = null,
    close: ?Pending = null,
    fn request(_: ?*anyopaque, _: u32, method: []const u8, _: []const u8) !void {
        if (!std.mem.eql(u8, method, "custom_native")) return error.UnexpectedStandardDialog;
    }
    fn scene(raw: ?*anyopaque, received: components.Scene) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        var owned = received;
        defer owned.deinit();
        self.input = .{ .header = .{ .lease = self.group.ui.service.?, .request_id = received.fence.token }, .fence = received.fence };
    }
    fn closing(raw: ?*anyopaque, fence: components.Fence) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.close = .{ .header = .{ .lease = self.group.ui.service.?, .request_id = fence.token }, .fence = fence };
    }
    fn send(self: *@This(), pending: Pending, is_close: bool) !void {
        var control: components.Control = .{ .gpa = self.group.engine.gpa, .fence = pending.fence, .kind = if (is_close) .{ .close_ack = true } else .{ .input = try self.group.engine.gpa.dupe(u8, "finish") } };
        defer control.deinit();
        var out: std.Io.Writer.Allocating = .init(self.group.engine.gpa);
        defer out.deinit();
        try out.writer.writeAll("{\"kind\":\"native_ui_service_component_control\",");
        try pending.header.writeFields(&out.writer);
        try out.writer.writeAll(",\"control\":");
        try components.writeControl(&out.writer, &control);
        try out.writer.writeByte('}');
        var parsed = try std.json.parseFromSlice(std.json.Value, self.group.engine.gpa, out.written(), .{});
        defer parsed.deinit();
        try self.group.uiServiceResponse(parsed.value.object);
    }
    fn pump(engine: *engine_mod.Engine) !bool {
        const self: *@This() = @ptrCast(@alignCast(engine.host_control_context.?));
        var changed = false;
        if (self.close) |pending| {
            self.close = null;
            try self.send(pending, true);
            changed = true;
        } else if (self.input) |pending| {
            self.input = null;
            try self.send(pending, false);
            changed = true;
        }
        try self.group.pollUiServices();
        return changed or self.input != null or self.close != null;
    }
};

fn exerciseComponent(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const owner = try group.add("component-allocation.mjs");
    var driver: ComponentDriver = .{ .group = group };
    group.ui.bridge = .{ .context = &driver, .request = ComponentDriver.request, .action = Driver.action, .cancel = Driver.cancel, .service_open = Driver.open, .service_close = Driver.close, .component_scene = ComponentDriver.scene, .component_close = ComponentDriver.closing };
    engine.host_control_context = &driver;
    engine.host_control_pump = ComponentDriver.pump;
    defer {
        engine.host_control_context = null;
        engine.host_control_pump = null;
    }
    try owner.loadFactory("export default pi=>{let ui;pi.registerCommand('capture',{handler(_,ctx){ui=ctx.ui}});pi.registerCommand('component',{async handler(){let disposed=0;const value=await ui.custom(async(tui,theme,keys,done)=>{await Promise.resolve();return{render(){return ['allocation-component']},handleInput(data){if(data==='finish')done('component-value')},dispose(){disposed++}}});return{value,disposed}}})}", "component-allocation.mjs");
    try owner.setContext("{\"hasUI\":true}");
    group.ui.invocation_id = 17;
    const capture = try owner.invokeCommand("capture", "");
    defer gpa.free(capture);
    const result = owner.invokeCommand("component", "") catch |err| {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (!failing.has_induced_failure) std.debug.print("Service component baseline: {s}; {s}\n", .{ @errorName(err), engine.last_error orelse "no guest diagnostic" });
        return err;
    };
    defer gpa.free(result);
    try std.testing.expectEqualStrings("{\"value\":\"component-value\",\"disposed\":1}", result);
}

fn componentProbe(gpa: std.mem.Allocator) !void {
    exerciseComponent(gpa) catch |err| {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (failing.has_induced_failure and (err == error.JavaScriptException or err == error.OutOfMemory or err == error.WriteFailed)) return error.OutOfMemory;
        return err;
    };
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
    if (failing.has_induced_failure) return error.OutOfMemory;
}

test "native Main UI service allocation covers asynchronous factory native handle controls and close acknowledgement" {
    try @import("test_support/sdk_allocation_shards.zig").check("main-ui-service-component", componentProbe, .{});
}
