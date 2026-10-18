//! Genuine native Pipe lifetime record: unbound, bound to a real endpoint,
//! closing, closed. No placeholder fd or invented kernel endpoint is exposed.
const js = @import("native_js_values.zig");
const c = js.c;
const frontier = @import("native_child_process_scope.zig");
const Scope = frontier.Scope;
const fnc = @import("native_child_process_function.zig");
const completion = @import("native_child_process_completion_queue.zig");
const socket = @import("native_node_net_socket.zig");
pub const Binding = struct {
    context: *anyopaque,
    retain: *const fn (*anyopaque) void,
    release: *const fn (*anyopaque) void,
    close: *const fn (*anyopaque) anyerror!void,
    socket_hooks: *const fn (*anyopaque) anyerror!socket.Hooks,
    socket_created: *const fn (*anyopaque, *const socket.Owned) anyerror!void,
};
pub const State = struct {
    engine: *js.Engine, handle: c.JSValue, callback: c.JSValue,
    phase: enum { unbound, bound, closing, closed } = .unbound,
    binding: ?Binding = null,
    pub fn bind(self: *State, actual: Binding) !void {
        if (self.phase != .unbound or self.binding != null) return error.NativePipeRecordNotBindable;
        actual.retain(actual.context); self.binding = actual; self.phase = .bound;
    }
    /// Called only by the owner after actual endpoint retirement acknowledgement.
    /// Closed memory-only unbound records also use this path without a fake fd.
    pub fn acknowledgeClosed(self: *State) !void {
        self.phase = .closed;
        if (!c.JS_IsUndefined(self.callback)) {
            try completion.enqueue(self.engine, self.callback, self.handle, &.{});
            self.engine.freeValue(self.callback); self.callback = c.pi_js_undefined();
        }
    }
};
fn finalize(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    if (self.binding) |actual| { if (self.phase == .bound) actual.close(actual.context) catch {}; actual.release(actual.context); }
    c.JS_FreeValueRT(runtime, self.handle); c.JS_FreeValueRT(runtime, self.callback);
    const engine = self.engine; engine.gpa.destroy(self); c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
}
fn mark(runtime: ?*c.JSRuntime, holder: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    c.JS_MarkValue(runtime, self.handle, visitor); c.JS_MarkValue(runtime, self.callback, visitor);
}
fn known(scope: *Scope, handle: c.JSValue, roots: []const c.JSValue) !*State {
    var id: u32 = 0; if (c.JS_ToUint32(scope.engine.context, &id, roots[0]) < 0) return js.capture(scope.engine);
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(handle, id) orelse return error.NativePipeRecordBrand));
    if (self.engine != scope.engine or !scope.equal(self.handle, handle)) return error.NativePipeRecordOwner;
    return self;
}
fn construct(engine: *js.Engine, handle: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    var id: u32 = 0; if (c.JS_ToUint32(engine.context, &id, roots[0]) < 0) return js.capture(engine);
    const prototype = try frontier.prototype(&scope, handle);
    const actual = try scope.objectProtoClass(prototype, id);
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
    var attached = false; errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .handle = c.JS_DupValue(engine.context, actual), .callback = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(actual, state); attached = true;
    return c.JS_DupValue(engine.context, actual);
}
fn close(engine: *js.Engine, handle: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err); const state = try known(&scope, handle, roots);
    if (state.phase == .closed or state.phase == .closing) return c.pi_js_undefined();
    const callback = if (args.len > 0) args[0] else c.pi_js_undefined();
    if (!c.JS_IsUndefined(callback) and !c.JS_IsFunction(engine.context, callback)) return js.typeError(engine, "Pipe close callback must be a function");
    state.engine.freeValue(state.callback); state.callback = c.JS_DupValue(engine.context, callback);
    if (state.binding) |actual| {
        try actual.close(actual.context); state.phase = .closing;
    } else try state.acknowledgeClosed();
    return c.pi_js_undefined();
}
pub const Owned = struct {
    engine: *js.Engine, handle: c.JSValue, holder: c.JSValue, state: *State,
    pub fn deinit(self: *Owned) void { self.engine.freeValue(self.handle); self.engine.freeValue(self.holder); }
};
pub const Provider = struct {
    engine: *js.Engine, constructor: c.JSValue, brand: c.JSClassID,
    pub fn deinit(self: *Provider) void { self.engine.freeValue(self.constructor); }
    pub fn create(self: *Provider) !Owned {
        const handle = try self.engine.checked(c.JS_CallConstructor(self.engine.context, self.constructor, 0, null));
        defer self.engine.freeValue(handle); return self.own(handle);
    }
    pub fn own(self: *Provider, handle: c.JSValue) !Owned {
        var scope: Scope = .{ .engine = self.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
        const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(handle, self.brand) orelse return error.NativePipeRecordBrand));
        if (state.engine != self.engine or !scope.equal(state.handle, handle)) return error.NativePipeRecordOwner;
        return .{ .engine = self.engine, .handle = c.JS_DupValue(self.engine.context, handle), .holder = c.JS_DupValue(self.engine.context, handle), .state = state };
    }
    pub fn registerWithSocket(self: *Provider, sockets: *socket.Provider, owner: c.JSValue) !void {
        if (sockets.engine != self.engine) return error.NativePipeRecordOwner;
        try sockets.addHandleAdopter(.{ .brand = self.brand, .owner = owner, .context = self, .resolve = resolveSocket });
    }
    /// The actual current handle selects its endpoint subscriber. A wrapper of
    /// Process.spawn may replace stdio.handle before the Source Socket loop;
    /// delivery must not attach that Socket to a stale numeric descriptor index.
    pub fn attachSocket(self: *Provider, handle: c.JSValue, actual: *const socket.Owned) !void {
        var owned = try self.own(handle); defer owned.deinit();
        if (actual.engine != self.engine or owned.state.phase != .bound) return error.RequiredNativePipeEndpointBinding;
        const binding = owned.state.binding orelse return error.RequiredNativePipeEndpointBinding;
        try binding.socket_created(binding.context, actual);
    }
};
fn resolveSocket(raw: *anyopaque, engine: *js.Engine, _: c.JSValue, handle: c.JSValue, _: c.JSValue) !socket.Hooks {
    const provider: *Provider = @ptrCast(@alignCast(raw));
    if (provider.engine != engine) return error.NativePipeRecordOwner;
    var owned = try provider.own(handle); defer owned.deinit();
    if (owned.state.phase != .bound) return error.RequiredNativePipeEndpointBinding;
    const actual = owned.state.binding orelse return error.RequiredNativePipeEndpointBinding;
    return actual.socket_hooks(actual.context);
}
pub fn createProvider(engine: *js.Engine) !Provider {
    var id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Native Pipe lifetime", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const roots = [_]c.JSValue{c.JS_NewUint32(engine.context, id)};
    const constructor = try scope.own(try fnc.createClass(engine, "Pipe", 0, construct, &roots));
    const prototype = try scope.get(constructor, "prototype");
    try scope.put(prototype, "close", try scope.own(try fnc.create(engine, "close", 0, close, &roots)));
    return .{ .engine = engine, .constructor = c.JS_DupValue(engine.context, constructor), .brand = id };
}
