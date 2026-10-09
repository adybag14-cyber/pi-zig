//! A genuine Main owner's retained UI service. This never changes async tokens.
const std = @import("std");
const engine_mod = @import("engine.zig");
const ui = @import("native_ui.zig");
const protocol = @import("native_ui_service_protocol.zig");
const bindings = @import("native_bindings.zig");
const c = engine_mod.c;

pub const Service = struct {
    gpa: std.mem.Allocator,
    manager: ?*ui.Manager,
    identity: protocol.Lease,
    saved: ui.Manager.InvocationState,
    value: c.JSValue,
    owner_token: c.JSValue,
    owner_class: c.JSClassID,
    live: bool = true,
    depth: usize = 0,

    pub fn create(owner: *bindings.Bindings) !*Service {
        if (owner.sdk_resource_owner) return error.InvalidNativeUiServiceOwner;
        const manager = owner.ui_manager;
        if (!manager.active) return error.StaleNativeUi;
        try manager.ensureServiceFrontendOwner();
        if (manager.service_clock >= 9_007_199_254_740_991) return error.NativeUiServiceExhausted;
        var class: c.JSClassID = 0;
        _ = c.JS_NewClassID(owner.engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Native Main UI service", .finalizer = finalize, .gc_mark = mark };
        if (c.JS_NewClass(owner.engine.runtime, class, &definition) < 0) return error.OutOfMemory;
        const value = try owner.engine.checked(c.JS_NewObjectClass(owner.engine.context, @intCast(class)));
        errdefer owner.engine.freeValue(value);
        const self = try owner.gpa.create(Service);
        errdefer owner.gpa.destroy(self);
        manager.service_clock += 1;
        const identity: protocol.Lease = .{ .owner_generation = manager.widgets.owner_generation, .service_id = manager.service_clock, .service_generation = manager.service_epoch, .extension_id = owner.owner_id };
        const owner_token = c.JS_DupValue(owner.engine.context, owner.owner_token);
        errdefer owner.engine.freeValue(owner_token);
        self.* = .{ .gpa = owner.gpa, .manager = manager, .identity = identity, .saved = try manager.forkService(identity), .value = value, .owner_token = owner_token, .owner_class = owner.owner_class };
        self.saved.editor_owner_id = 0;
        self.saved.components.?.ui_service = c.JS_DupValue(owner.engine.context, value);
        errdefer {
            var guard = self.enter();
            manager.finish();
            guard.restore();
            self.saved.pending.deinit(owner.gpa);
            self.saved.customs.deinit(owner.gpa);
            self.saved.components.?.deinit();
        }
        try manager.services.ensureUnusedCapacity(owner.gpa, 1);
        if (manager.bridge) |bridge| if (bridge.service_open) |open| try open(bridge.context, identity);
        _ = c.JS_SetOpaque(value, self);
        manager.services.appendAssumeCapacity(self);
        return self;
    }
    pub const Guard = struct {
        service: *Service,
        exchanged: bool,
        pub fn restore(self: *Guard) void {
            const service = self.service;
            if (self.exchanged) service.manager.?.exchangeInvocation(&service.saved);
            service.depth -= 1;
            if (!service.live and service.depth == 0) service.closeState();
        }
    };
    fn enter(self: *Service) Guard {
        const manager = self.manager.?;
        const exchanged = if (manager.service) |active| !active.eql(self.identity) else true;
        if (exchanged) manager.exchangeInvocation(&self.saved);
        self.depth += 1;
        return .{ .service = self, .exchanged = exchanged };
    }
    /// Component handles retain this native token and mark that edge for GC.
    /// A retired handle follows its original late-factory disposal path.
    pub fn enterCallback(engine: *engine_mod.Engine, value: c.JSValue) !?Guard {
        const self: *Service = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return error.InvalidNativeUiService));
        if (!self.live or self.manager == null) return null;
        try @import("native_async_scope.zig").requireOwnedUiLive(engine);
        return self.enter();
    }
    fn closeState(self: *Service) void {
        const manager = self.manager orelse return;
        for (manager.services.items, 0..) |service, index| if (service == self) {
            _ = manager.services.swapRemove(index);
            break;
        };
        // Close only this service's pending requests, never the current command.
        manager.exchangeInvocation(&self.saved);
        manager.finish();
        if (manager.bridge) |bridge| if (bridge.service_close) |close| close(bridge.context, self.identity) catch {};
        manager.exchangeInvocation(&self.saved);
        self.saved.pending.deinit(self.gpa);
        self.saved.customs.deinit(self.gpa);
        self.saved.components.?.deinit();
        self.saved.components = null;
        self.manager = null;
    }
    pub fn retire(self: *Service, engine: *engine_mod.Engine) void {
        self.live = false;
        if (self.depth == 0) self.closeState();
        engine.freeValue(self.value);
    }
    fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
        const self: *Service = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
        c.JS_MarkValue(runtime, self.owner_token, marker);
    }
    fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
        const self: *Service = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
        std.debug.assert(self.manager == null);
        c.JS_FreeValueRT(runtime, self.owner_token);
        self.gpa.destroy(self);
    }
    pub fn createObject(self: *Service, owner: *bindings.Bindings) !c.JSValue {
        if (!self.live) return error.StaleNativeUiService;
        var guard = self.enter();
        defer guard.restore();
        const engine = owner.engine;
        const object = try self.manager.?.createObject();
        errdefer engine.freeValue(object);
        inline for (std.meta.fields(ui.Method)) |field| {
            const name: [:0]const u8 = field.name;
            const original = try engine.checked(c.JS_GetPropertyStr(engine.context, object, name));
            defer engine.freeValue(original);
            const length = try engine.checked(c.JS_GetPropertyStr(engine.context, original, "length"));
            defer engine.freeValue(length);
            var arity: i32 = 0;
            if (c.JS_ToInt32(engine.context, &arity, length) < 0) return error.JavaScriptException;
            if (comptime std.mem.eql(u8, name, "select") or std.mem.eql(u8, name, "confirm") or std.mem.eql(u8, name, "input")) arity = 3;
            if (comptime std.mem.eql(u8, name, "editor") or std.mem.eql(u8, name, "custom")) arity = 2;
            var data = [_]c.JSValue{ self.value, original, owner.owner_token, c.JS_NewInt64(engine.context, owner.owner_class) };
            const wrapper = try engine.checked(c.JS_NewCFunctionData2(engine.context, invoke, name, arity, 0, data.len, &data));
            if (c.JS_DefinePropertyValueStr(engine.context, object, name, wrapper, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        }
        return object;
    }
    fn invoke(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        var class: i64 = 0;
        if (c.JS_ToInt64(context, &class, data[3]) < 0) return engine.throwCaptured();
        const self: *Service = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], c.JS_GetClassID(data[0])) orelse return c.JS_ThrowTypeError(context, "invalid native UI service")));
        if (class != self.owner_class or !c.JS_IsStrictEqual(context, self.owner_token, data[2]) or c.JS_GetOpaque(data[2], self.owner_class) == null) return c.JS_ThrowTypeError(context, "invalid native UI service owner");
        if (!self.live or self.manager == null or self.manager.?.engine != engine or self.identity.owner_generation != self.manager.?.widgets.owner_generation) return c.JS_ThrowTypeError(context, "stale native UI service");
        @import("native_async_scope.zig").requireOwnedUiLive(engine) catch |err| {
            if (err == error.JavaScriptException) return engine.throwCaptured();
            return c.JS_ThrowTypeError(context, "%s", @as([*:0]const u8, @errorName(err)));
        };
        var guard = self.enter();
        defer guard.restore();
        return c.JS_Call(context, data[1], receiver, argc, argv);
    }
    pub fn poll(self: *Service) !void {
        if (!self.live or self.manager == null) return;
        var guard = self.enter();
        defer guard.restore();
        _ = try self.manager.?.poll();
    }
    pub fn respond(self: *Service, header: protocol.Header, ok: bool, value: c.JSValue) !void {
        if (!self.live or self.manager == null or !self.identity.eql(header.lease) or header.request_id > std.math.maxInt(u32)) return;
        var guard = self.enter();
        defer guard.restore();
        try self.manager.?.respond(@intCast(header.request_id), ok, value);
    }
    pub fn accepts(self: *Service, header: protocol.Header) bool {
        if (!self.live or self.manager == null or !self.identity.eql(header.lease) or header.request_id > std.math.maxInt(u32)) return false;
        var guard = self.enter();
        defer guard.restore();
        return self.manager.?.hasPending(@intCast(header.request_id));
    }
    pub fn cancel(self: *Service, id: u32) !void {
        if (!self.live or self.manager == null) return;
        var guard = self.enter();
        defer guard.restore();
        try self.manager.?.cancel(id);
    }
    pub fn componentControl(self: *Service, header: protocol.Header, object: std.json.ObjectMap) !void {
        if (!self.live or self.manager == null or !self.identity.eql(header.lease)) return;
        const fence = @import("component_protocol.zig").readFence(&object) catch return;
        if (fence.token != header.request_id or fence.invocation_id != self.saved.invocation_id) return;
        var guard = self.enter();
        defer guard.restore();
        var control = @import("component_protocol.zig").readControl(self.gpa, &object) catch |err| {
            if (err == error.OutOfMemory) return err;
            return;
        };
        defer control.deinit();
        _ = try self.manager.?.componentControl(&control);
    }
    pub fn deadline(self: *const Service) ?i64 {
        var result: ?i64 = null;
        for (self.saved.pending.items) |pending| if (pending.deadline) |due| {
            result = if (result) |previous| @min(previous, due) else due;
        };
        return result;
    }
};
