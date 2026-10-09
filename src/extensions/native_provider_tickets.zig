//! Owner-only typed callback tickets. Pending JS values and invocation state
//! remain rooted on one VM; process callers exchange bounded JSON records.
const std = @import("std");
const engine_mod = @import("engine.zig");
const bindings_mod = @import("native_bindings.zig");
const ui_mod = @import("native_ui.zig");
const operations = @import("native_provider_operations.zig");
const scopes = @import("native_async_scope.zig");
const signals = @import("abort_signal.zig");
const values = @import("native_values.zig");
const c = engine_mod.c;
pub const Ticket = struct {
    manager: *Manager,
    binding: *bindings_mod.Bindings,
    owner_id: u64,
    id: []u8,
    callback: []u8,
    provider: []u8,
    generation: u64,
    operation: ?operations.Operation,
    scope: c.JSValue,
    signal: c.JSValue,
    model: c.JSValue,
    pending: c.JSValue,
    invocation: bindings_mod.Bindings.InvocationState = .{},
    ui: ui_mod.Manager.InvocationState = .{},
    result: ?[]u8 = null,
    failure: ?[]u8 = null,
    retired: bool = false,
    scope_closed: bool = false,
    abort_sent: bool = false,
    deadline_ms: i64,

    fn activate(raw: ?*anyopaque) void {
        const self: *Ticket = @ptrCast(@alignCast(raw.?));
        self.binding.exchangeInvocation(&self.invocation);
        self.binding.ui_manager.exchangeInvocation(&self.ui);
        self.manager.active = self;
    }
    fn deactivate(raw: ?*anyopaque) void {
        const self: *Ticket = @ptrCast(@alignCast(raw.?));
        self.manager.active = null;
        self.binding.ui_manager.exchangeInvocation(&self.ui);
        self.binding.exchangeInvocation(&self.invocation);
    }
    pub fn enter(self: *Ticket) scopes.Guard {
        return scopes.enter(self.manager.engine, self.scope);
    }
    pub fn abort(self: *Ticket) !void {
        if (self.abort_sent or self.scope_closed or self.retired or self.result != null or self.failure != null) return;
        self.abort_sent = true;
        const guard = self.enter();
        defer guard.restore();
        try signals.abort(self.manager.engine, self.signal, c.pi_js_undefined());
    }
    pub fn retire(self: *Ticket, reason: []const u8) !void {
        if (self.retired) return;
        try self.abort();
        self.closeScope();
        self.retired = true;
        if (self.result) |result| self.manager.engine.gpa.free(result);
        self.result = null;
        if (self.failure == null) self.failure = try self.manager.engine.gpa.dupe(u8, reason);
    }
    fn closeScope(self: *Ticket) void {
        if (self.scope_closed) return;
        const guard = self.enter();
        self.binding.retireTicket();
        guard.restore();
        scopes.retire(self.manager.engine, self.scope);
        self.scope_closed = true;
    }
    fn deinit(self: *Ticket) void {
        const engine = self.manager.engine;
        self.retire("Native typed provider ticket retired") catch {};
        self.ui.pending.deinit(engine.gpa);
        self.ui.customs.deinit(engine.gpa);
        if (self.ui.components) |*components| components.deinit();
        if (self.result) |result| engine.gpa.free(result);
        if (self.failure) |failure| engine.gpa.free(failure);
        engine.freeValue(self.scope);
        engine.freeValue(self.signal);
        engine.freeValue(self.model);
        engine.freeValue(self.pending);
        engine.gpa.free(self.id);
        engine.gpa.free(self.callback);
        engine.gpa.free(self.provider);
        engine.gpa.destroy(self);
    }
};
pub const Manager = struct {
    engine: *engine_mod.Engine,
    io: std.Io,
    tickets: std.ArrayList(*Ticket) = .empty,
    active: ?*Ticket = null,
    pub fn deinit(self: *Manager) void {
        for (self.tickets.items) |ticket| ticket.deinit();
        self.tickets.deinit(self.engine.gpa);
    }
    pub fn find(self: *Manager, id: []const u8) ?*Ticket {
        for (self.tickets.items) |ticket| if (std.mem.eql(u8, ticket.id, id)) return ticket;
        return null;
    }
    pub fn retireOwner(self: *Manager, owner: ?u64) !void {
        for (self.tickets.items) |ticket| if (owner == null or ticket.owner_id == owner.?) try ticket.retire("Native typed provider owner retired");
    }
    pub fn begin(self: *Manager, binding: *bindings_mod.Bindings, id: []const u8, request: std.json.ObjectMap) !void {
        const engine = self.engine;
        if (self.tickets.items.len >= 32 or self.find(id) != null) return error.NativeProviderTicketLimit;
        const callback = try engine.gpa.dupe(u8, try text(request, "callbackId"));
        errdefer engine.gpa.free(callback);
        const provider = try engine.gpa.dupe(u8, try text(request, "providerName"));
        errdefer engine.gpa.free(provider);
        const owned_id = try engine.gpa.dupe(u8, id);
        errdefer engine.gpa.free(owned_id);
        const generation = try @import("component_protocol.zig").identifier(request.get("callbackGeneration") orelse return error.InvalidNativeTypedProviderRequest);
        try binding.providers.validate(callback, provider, generation);
        const signal = try signals.create(engine);
        errdefer engine.freeValue(signal);
        const model = try engine.fromJsonValue(request.get("model") orelse .null);
        errdefer engine.freeValue(model);
        const ticket = try engine.gpa.create(Ticket);
        errdefer engine.gpa.destroy(ticket);
        const kind = try text(request, "kind");
        const operation: ?operations.Operation = if (std.mem.eql(u8, kind, "provider_typed_begin")) std.meta.stringToEnum(operations.Operation, try text(request, "operation")) orelse return error.InvalidNativeTypedProviderRequest else null;
        ticket.* = .{ .manager = self, .binding = binding, .owner_id = binding.owner_id, .id = owned_id, .callback = callback, .provider = provider, .generation = generation, .operation = operation, .scope = c.pi_js_undefined(), .signal = signal, .model = model, .pending = c.pi_js_undefined(), .deadline_ms = std.Io.Clock.awake.now(self.io).toMilliseconds() + 300_000 };
        ticket.scope = try scopes.create(engine, ticket, Ticket.activate, Ticket.deactivate);
        ticket.ui.components = binding.ui_manager.components.forkInvocation();
        errdefer {
            const guard = ticket.enter();
            binding.retireTicket();
            guard.restore();
            scopes.retire(engine, ticket.scope);
            engine.freeValue(ticket.scope);
            ticket.ui.pending.deinit(engine.gpa);
            ticket.ui.customs.deinit(engine.gpa);
            ticket.ui.components.?.deinit();
        }
        try self.tickets.ensureUnusedCapacity(engine.gpa, 1);
        const guard = ticket.enter();
        defer guard.restore();
        const snapshot = try std.json.Stringify.valueAlloc(engine.gpa, request.get("context") orelse std.json.Value{ .object = .empty }, .{});
        defer engine.gpa.free(snapshot);
        try binding.beginTicket(signal, snapshot);
        binding.ui_manager.invocation_id = std.fmt.parseUnsigned(u64, id, 10) catch return error.InvalidNativeInvocationId;
        if (request.get("aborted")) |aborted| if (aborted == .bool and aborted.bool) try signals.abort(engine, signal, c.pi_js_undefined());
        const options = try engine.fromJsonValue(request.get("options") orelse .{ .object = .empty });
        defer engine.freeValue(options);
        ticket.pending = if (operation) |typed| pending: {
            const context = try engine.fromJsonValue(request.get("modelContext") orelse return error.InvalidNativeTypedProviderRequest);
            defer engine.freeValue(context);
            const rewritten = if (request.get("authRewritesModel")) |value| value == .bool and value.bool else false;
            break :pending operations.invokePending(engine, &binding.providers, callback, provider, generation, typed, model, context, options, signal, rewritten) catch |err| {
                if (err != error.JavaScriptException or engine.captured_exception == null) return err;
                break :pending try operations.failureResult(engine, typed, model, signal, engine.captured_exception.?);
            };
        } else pending: {
            const credential = try engine.fromJsonValue(request.get("credential") orelse .null);
            defer engine.freeValue(credential);
            const auth = std.meta.stringToEnum(operations.AuthOperation, try text(request, "operation")) orelse return error.InvalidNativeProviderAuthRequest;
            break :pending try operations.invokeAuthPending(engine, &binding.providers, callback, provider, generation, auth, credential, options, signal);
        };
        self.tickets.appendAssumeCapacity(ticket);
    }
    pub fn pump(self: *Manager) !void {
        const engine = self.engine;
        for (self.tickets.items) |ticket| {
            if (ticket.retired or ticket.result != null or ticket.failure != null) continue;
            ticket.binding.providers.validate(ticket.callback, ticket.provider, ticket.generation) catch {
                try ticket.retire("Native typed provider callback retired");
                continue;
            };
            if (std.Io.Clock.awake.now(self.io).toMilliseconds() >= ticket.deadline_ms) {
                try ticket.retire("Native typed provider operation deadline exceeded");
                continue;
            }
            {
                const guard = ticket.enter();
                defer guard.restore();
                _ = try ticket.binding.ui_manager.poll();
            }
            const status = c.JS_PromiseState(engine.context, ticket.pending);
            if (status == c.JS_PROMISE_PENDING) continue;
            try self.finish(ticket, status);
            ticket.closeScope();
        }
    }
    fn finish(self: *Manager, ticket: *Ticket, status: c.JSPromiseStateEnum) !void {
        const engine = self.engine;
        const guard = ticket.enter();
        defer guard.restore();
        const answer = if (status == c.JS_PROMISE_REJECTED) rejected: {
            const exception = c.JS_PromiseResult(engine.context, ticket.pending);
            defer engine.freeValue(exception);
            c.JS_PromiseMarkAsHandled(engine.context, ticket.pending);
            if (ticket.operation) |operation| break :rejected try operations.failureResult(engine, operation, ticket.model, ticket.signal, exception);
            ticket.failure = try engine.toString(exception);
            return;
        } else if (status == c.JS_PROMISE_FULFILLED) c.JS_PromiseResult(engine.context, ticket.pending) else c.JS_DupValue(engine.context, ticket.pending);
        defer engine.freeValue(answer);
        ticket.result = try ticket.binding.finishTicket(answer);
    }
    pub fn consume(self: *Manager, ticket: *Ticket) void {
        for (self.tickets.items, 0..) |item, index| if (item == ticket) {
            _ = self.tickets.orderedRemove(index);
            ticket.deinit();
            return;
        };
    }
};
fn text(object: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = object.get(key) orelse return error.InvalidNativeTypedProviderRequest;
    return if (value == .string) value.string else error.InvalidNativeTypedProviderRequest;
}
