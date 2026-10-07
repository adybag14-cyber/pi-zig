//! Extension renderer callbacks and visual-row state on the QuickJS owner.
const std = @import("std");
const engine_mod = @import("engine.zig");
const components = @import("native_components.zig");
const native_tui = @import("native_tui.zig");
const protocol = @import("renderer_protocol.zig");
const c = engine_mod.c;

pub const Kind = enum { render_message, render_entry, transform_markdown, render_tool_call, render_tool_result, prepare_tool_arguments, renderer_retire };
const Token = struct { gpa: std.mem.Allocator, manager: ?*Manager };
pub const RegistrationKind = enum { message, entry, markdown, resolver };
pub const Registration = struct { owner_id: u64, name: []u8, callback: c.JSValue };
const Row = struct {
    generation: u64,
    tool: []u8,
    args: c.JSValue,
    state: c.JSValue,
    call: c.JSValue,
    result: c.JSValue,
    owner_id: u64 = 0,
    source_tool: c.JSValue,
    snapshot: c.JSValue,
    call_payload: c.JSValue,
    result_payload: c.JSValue,
    width: usize = 80,
    sequence: u64 = 0,
    revision: u64 = 0,
    dirty: bool = true,
    registered: bool = false,
    duration_ms: ?f64 = null,
};
/// Borrowed/rooted only for the owner-thread replay callback; never a DTO.
pub const Replay = struct { owner_id: u64, id: []const u8, name: []const u8, generation: u64, kind: Kind, payload: c.JSValue, snapshot: ?c.JSValue, tool: c.JSValue };
fn tokenFinalizer(_: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    token.gpa.destroy(token);
}

pub const Manager = struct {
    engine: *engine_mod.Engine,
    messages: std.ArrayList(Registration) = .empty,
    entries: std.ArrayList(Registration) = .empty,
    resolvers: std.ArrayList(Registration) = .empty,
    transformers: std.ArrayList(Registration) = .empty,
    rows: std.StringHashMapUnmanaged(*Row) = .empty,
    next_row: u64 = 1,
    next_resolution: u64 = 1,
    active_resolution: u64 = 0,
    token: c.JSValue,
    token_class: c.JSClassID,
    array_predicate: c.JSValue,
    theme: c.JSValue,
    owner_generation: u64 = 1,
    subscribed: bool = false,
    record_fn: ?*const fn (?*anyopaque, protocol.Record) anyerror!void = null,
    record_context: ?*anyopaque = null,
    replay_fn: ?*const fn (?*anyopaque, Replay) anyerror!void = null,
    replay_context: ?*anyopaque = null,
    sink_failure: ?anyerror = null,
    redraw_due_ms: ?i64 = null,

    pub fn init(engine: *engine_mod.Engine) !*Manager {
        var class: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Native Renderer Owner", .finalizer = tokenFinalizer, .gc_mark = null, .call = null, .exotic = null };
        if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
        const token = try engine.checked(c.JS_NewObjectClass(engine.context, @intCast(class)));
        errdefer engine.freeValue(token);
        const handle = try engine.gpa.create(Token);
        handle.* = .{ .gpa = engine.gpa, .manager = null };
        _ = c.JS_SetOpaque(token, handle);
        const predicate = try components.arrayPredicate(engine);
        errdefer engine.freeValue(predicate);
        const theme = try native_tui.createTheme(engine);
        errdefer engine.freeValue(theme);
        const self = try engine.gpa.create(Manager);
        self.* = .{ .engine = engine, .token = token, .token_class = class, .array_predicate = predicate, .theme = theme };
        handle.manager = self;
        return self;
    }

    fn freeRegistrations(self: *Manager, records: *std.ArrayList(Registration)) void {
        for (records.items) |entry| {
            self.engine.gpa.free(entry.name);
            self.engine.freeValue(entry.callback);
        }
        records.deinit(self.engine.gpa);
    }

    pub fn deinit(self: *Manager) void {
        const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(self.token, self.token_class).?));
        token.manager = null;
        while (self.rows.count() != 0) {
            var keys = self.rows.keyIterator();
            _ = self.retire(keys.next().?.*, null);
        }
        self.rows.deinit(self.engine.gpa);
        self.freeRegistrations(&self.messages);
        self.freeRegistrations(&self.entries);
        self.freeRegistrations(&self.resolvers);
        self.freeRegistrations(&self.transformers);
        self.engine.freeValue(self.token);
        self.engine.freeValue(self.array_predicate);
        self.engine.freeValue(self.theme);
        self.engine.gpa.destroy(self);
    }

    pub fn register(self: *Manager, kind: RegistrationKind, name: []const u8, callback: c.JSValue) !void {
        return self.registerOwned(0, kind, name, callback);
    }

    pub fn registerOwned(self: *Manager, owner_id: u64, kind: RegistrationKind, name: []const u8, callback: c.JSValue) !void {
        if (!c.JS_IsFunction(self.engine.context, callback)) return error.InvalidNativeRendererCallback;
        if ((kind == .message or kind == .entry) and (name.len == 0 or name.len > 4096)) return error.InvalidNativeRendererName;
        const records = switch (kind) {
            .message => &self.messages,
            .entry => &self.entries,
            .markdown => &self.transformers,
            .resolver => &self.resolvers,
        };
        if (kind != .resolver) for (records.items) |*entry| if (entry.owner_id == owner_id and std.mem.eql(u8, entry.name, name)) {
            const retained = c.JS_DupValue(self.engine.context, callback);
            self.engine.freeValue(entry.callback);
            entry.callback = retained;
            return;
        };
        if (records.items.len == 4096) return error.NativeRendererLimit;
        const key = try self.engine.gpa.dupe(u8, name);
        errdefer self.engine.gpa.free(key);
        const retained = c.JS_DupValue(self.engine.context, callback);
        errdefer self.engine.freeValue(retained);
        try records.append(self.engine.gpa, .{ .owner_id = owner_id, .name = key, .callback = retained });
    }

    pub fn removeOwner(self: *Manager, owner_id: u64) void {
        // A resolved row may retain wrappers from any resolver owner in the
        // global chain. Unloading one origin retires those rooted components
        // and capabilities before its registration closures are released.
        while (self.rows.count() != 0) {
            var keys = self.rows.keyIterator();
            _ = self.retire(keys.next().?.*, null);
        }
        inline for (.{ &self.messages, &self.entries, &self.transformers, &self.resolvers }) |records| {
            var index: usize = 0;
            while (index < records.items.len) {
                if (records.items[index].owner_id != owner_id) {
                    index += 1;
                    continue;
                }
                const removed = records.orderedRemove(index);
                self.engine.gpa.free(removed.name);
                self.engine.freeValue(removed.callback);
            }
        }
    }

    pub fn hasOwner(self: *Manager, kind: RegistrationKind, owner_id: u64) bool {
        const records = switch (kind) {
            .message => self.messages.items,
            .entry => self.entries.items,
            .markdown => self.transformers.items,
            .resolver => self.resolvers.items,
        };
        for (records) |entry| if (entry.owner_id == owner_id) return true;
        return false;
    }

    fn put(self: *Manager, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        if (c.JS_DefinePropertyValueStr(self.engine.context, object, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    fn get(self: *Manager, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, object, name));
    }
    fn flag(self: *Manager, payload: c.JSValue, name: [*:0]const u8, fallback: bool) !c.JSValue {
        const value = try self.get(payload, name);
        defer self.engine.freeValue(value);
        return c.pi_js_bool(self.engine.context, @intFromBool(if (c.JS_IsUndefined(value)) fallback else c.JS_ToBool(self.engine.context, value) != 0));
    }
    fn objectOrDefault(self: *Manager, payload: c.JSValue, name: [*:0]const u8) !c.JSValue {
        const value = try self.get(payload, name);
        if (!c.JS_IsNull(value) and !c.JS_IsUndefined(value)) return value;
        self.engine.freeValue(value);
        return self.engine.checked(c.JS_NewObject(self.engine.context));
    }
    fn isArray(self: *Manager, value: c.JSValue) !bool {
        var args = [_]c.JSValue{value};
        const result = try self.engine.checked(c.JS_Call(self.engine.context, self.array_predicate, c.pi_js_undefined(), 1, &args));
        defer self.engine.freeValue(result);
        return c.JS_ToBool(self.engine.context, result) != 0;
    }
    fn invoke(self: *Manager, callback: c.JSValue, receiver: c.JSValue, args: []c.JSValue) !c.JSValue {
        const promise = try self.engine.checked(c.JS_Call(self.engine.context, callback, receiver, @intCast(args.len), args.ptr));
        defer self.engine.freeValue(promise);
        return self.engine.awaitValue(promise);
    }

    pub fn retire(self: *Manager, id: []const u8, generation: ?u64) bool {
        const selected = self.rows.get(id) orelse return false;
        if (generation) |actual| if (actual != selected.generation) return false;
        if (selected.registered) self.emitRetirement(id, selected) catch |err| {
            self.sink_failure = err;
        };
        const removed = self.rows.fetchRemove(id).?;
        self.engine.gpa.free(removed.key);
        self.engine.gpa.free(selected.tool);
        for ([_]c.JSValue{ selected.args, selected.state, selected.call, selected.result, selected.source_tool, selected.snapshot, selected.call_payload, selected.result_payload }) |value| self.engine.freeValue(value);
        self.engine.gpa.destroy(selected);
        return true;
    }

    fn fence(self: *Manager, id: []const u8, row_value: *const Row) !protocol.Fence {
        return .{ .owner_generation = self.owner_generation, .extension_id = row_value.owner_id, .row_generation = row_value.generation, .tool_call_id = try self.engine.gpa.dupe(u8, id) };
    }

    fn emit(self: *Manager, record: protocol.Record) !void {
        var owned = record;
        var transferred = false;
        defer if (!transferred) owned.deinit();
        if (self.record_fn) |send| {
            try send(self.record_context, record);
            transferred = true;
        }
    }

    fn emitRetirement(self: *Manager, id: []const u8, row_value: *const Row) !void {
        try self.emit(.{ .gpa = self.engine.gpa, .fence = try self.fence(id, row_value), .kind = .retire });
    }

    fn emitFailure(self: *Manager, id: []const u8, row_value: *const Row, err: anyerror) !void {
        const message = try self.engine.gpa.dupe(u8, self.engine.last_error orelse @errorName(err));
        var transferred = false;
        defer if (!transferred) self.engine.gpa.free(message);
        const identity = try self.fence(id, row_value);
        transferred = true;
        try self.emit(.{ .gpa = self.engine.gpa, .fence = identity, .kind = .{ .failure = message } });
    }

    fn emitFrame(self: *Manager, id: []const u8, row_value: *Row, slot: protocol.Slot, frame: *const components.Frame) !void {
        if (!self.subscribed or self.record_fn == null) return;
        if (!row_value.registered) {
            const name = try self.engine.gpa.dupe(u8, row_value.tool);
            var transferred = false;
            defer if (!transferred) self.engine.gpa.free(name);
            const identity = try self.fence(id, row_value);
            transferred = true;
            try self.emit(.{ .gpa = self.engine.gpa, .fence = identity, .kind = .{ .register = .{ .tool_name = name, .width = row_value.width } } });
            row_value.registered = true;
        }
        if (row_value.sequence >= 9_007_199_254_740_991 or row_value.revision >= 9_007_199_254_740_991) return error.NativeRendererGenerationLimit;
        const copied = try frame.clone(self.engine.gpa);
        var transferred = false;
        defer if (!transferred) {
            var owned = copied;
            owned.deinit();
        };
        const identity = try self.fence(id, row_value);
        row_value.sequence += 1;
        transferred = true;
        try self.emit(.{ .gpa = self.engine.gpa, .fence = identity, .kind = .{ .frame = .{ .sequence = row_value.sequence, .revision = row_value.revision + 1, .slot = slot, .width = row_value.width, .frame = copied } } });
    }

    pub fn subscribe(self: *Manager, enabled: bool) void {
        self.subscribed = enabled;
        var values = self.rows.valueIterator();
        while (values.next()) |value| {
            value.*.registered = false;
            if (enabled) value.*.dirty = true;
        }
        self.redraw_due_ms = if (enabled and self.engine.native_io != null) std.Io.Clock.awake.now(self.engine.native_io.?).toMilliseconds() else null;
    }

    pub fn hasDirty(self: *Manager) bool {
        var values = self.rows.valueIterator();
        while (values.next()) |value| if (value.*.dirty) return true;
        return false;
    }

    fn scheduleRedraw(self: *Manager) void {
        if (self.redraw_due_ms == null) if (self.engine.native_io) |io| {
            self.redraw_due_ms = std.Io.Clock.awake.now(io).toMilliseconds() + 16;
        };
    }

    pub fn nextRedrawDeadline(self: *Manager) ?i64 {
        if (!self.subscribed or !self.hasDirty()) {
            self.redraw_due_ms = null;
            return null;
        }
        self.scheduleRedraw();
        return self.redraw_due_ms;
    }

    pub fn pumpDirtyReady(self: *Manager) !bool {
        const due = self.nextRedrawDeadline() orelse return false;
        if (self.engine.native_io) |io| if (std.Io.Clock.awake.now(io).toMilliseconds() < due) return false;
        return self.pumpDirty();
    }

    pub fn control(self: *Manager, value: *const protocol.Control) !bool {
        if (value.fence.owner_generation != self.owner_generation) return false;
        const selected = self.rows.get(value.fence.tool_call_id) orelse return false;
        if (selected.generation != value.fence.row_generation or selected.owner_id != value.fence.extension_id) return false;
        switch (value.kind) {
            .retire => return self.retire(value.fence.tool_call_id, value.fence.row_generation),
            .invalidate => {},
            .resize => |width_value| {
                if (width_value > 16_384) return error.NativeComponentViewportLimit;
                selected.width = width_value;
                for ([_]c.JSValue{ selected.call_payload, selected.result_payload }) |payload| if (c.JS_IsObject(payload)) try self.put(payload, "width", c.JS_NewInt64(self.engine.context, @intCast(width_value)));
            },
        }
        if (selected.revision >= 9_007_199_254_740_991) return error.NativeRendererGenerationLimit;
        selected.revision += 1;
        selected.dirty = true;
        self.scheduleRedraw();
        return true;
    }

    /// Tool onUpdate already runs in the selected invocation's owner/broker.
    /// Render here without another Runtime request or another beginActions.
    pub fn renderLiveUpdate(self: *Manager, id: []const u8, result: c.JSValue) !void {
        if (!self.subscribed) return;
        const row_value = self.rows.get(id) orelse return;
        const generation = row_value.generation;
        const owner_id = row_value.owner_id;
        const name = try self.engine.gpa.dupe(u8, row_value.tool);
        defer self.engine.gpa.free(name);
        const tool_value = c.JS_DupValue(self.engine.context, row_value.source_tool);
        defer self.engine.freeValue(tool_value);
        const snapshot = c.JS_DupValue(self.engine.context, row_value.snapshot);
        defer self.engine.freeValue(snapshot);
        const previous = c.JS_DupValue(self.engine.context, if (c.JS_IsUndefined(row_value.result_payload)) row_value.call_payload else row_value.result_payload);
        defer self.engine.freeValue(previous);
        const available_width = row_value.width;
        const payload = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(payload);
        try self.put(payload, "toolCallId", try self.engine.checked(c.JS_NewStringLen(self.engine.context, id.ptr, id.len)));
        try self.put(payload, "result", c.JS_DupValue(self.engine.context, result));
        try self.put(payload, "isPartial", c.pi_js_bool(self.engine.context, 1));
        try self.put(payload, "width", c.JS_NewInt64(self.engine.context, @intCast(available_width)));
        const pad = try self.get(previous, "outputPad");
        defer self.engine.freeValue(pad);
        try self.put(payload, "outputPad", c.JS_DupValue(self.engine.context, pad));
        inline for (.{ "expanded", "showImages", "executionStarted", "argsComplete" }) |field| {
            try self.put(payload, field, try self.flag(previous, field, comptime std.mem.eql(u8, field, "showImages") or std.mem.eql(u8, field, "executionStarted") or std.mem.eql(u8, field, "argsComplete")));
        }
        try self.put(payload, "isError", try self.flag(result, "isError", false));
        const value = self.runOwned(owner_id, .render_tool_result, name, payload, if (c.JS_IsUndefined(snapshot)) null else snapshot, tool_value) catch |err| {
            if (err == error.OutOfMemory or err == error.JavaScriptInterrupted or err == error.JavaScriptJobLimit or err == error.NativeHostPromiseTimeout) return err;
            if (self.rows.get(id)) |active| if (active.generation == generation) try self.emitFailure(id, active, err);
            return;
        };
        self.engine.freeValue(value);
    }

    pub fn pumpDirty(self: *Manager) !bool {
        if (!self.subscribed or self.replay_fn == null) return false;
        var ids: std.ArrayList([]u8) = .empty;
        defer {
            for (ids.items) |id| self.engine.gpa.free(id);
            ids.deinit(self.engine.gpa);
        }
        var entries = self.rows.iterator();
        while (entries.next()) |entry| if (entry.value_ptr.*.dirty) {
            const id = try self.engine.gpa.dupe(u8, entry.key_ptr.*);
            ids.append(self.engine.gpa, id) catch |err| {
                self.engine.gpa.free(id);
                return err;
            };
        };
        for (ids.items) |id| {
            const selected = self.rows.get(id) orelse continue;
            const generation = selected.generation;
            const revision = selected.revision;
            for ([_]Kind{ .render_tool_call, .render_tool_result }) |kind| {
                const current = self.rows.get(id) orelse break;
                if (current.generation != generation) break;
                const payload = c.JS_DupValue(self.engine.context, if (kind == .render_tool_call) current.call_payload else current.result_payload);
                defer self.engine.freeValue(payload);
                if (c.JS_IsUndefined(payload)) continue;
                const tool_value = c.JS_DupValue(self.engine.context, current.source_tool);
                defer self.engine.freeValue(tool_value);
                const snapshot = c.JS_DupValue(self.engine.context, current.snapshot);
                defer self.engine.freeValue(snapshot);
                const name = try self.engine.gpa.dupe(u8, current.tool);
                defer self.engine.gpa.free(name);
                self.replay_fn.?(self.replay_context, .{ .owner_id = current.owner_id, .id = id, .name = name, .generation = generation, .kind = kind, .payload = payload, .snapshot = if (c.JS_IsUndefined(snapshot)) null else snapshot, .tool = tool_value }) catch |err| {
                    if (err == error.OutOfMemory or err == error.JavaScriptJobLimit or err == error.JavaScriptInterrupted or err == error.NativeHostPromiseTimeout) return err;
                    if (self.rows.get(id)) |active| if (active.generation == generation) try self.emitFailure(id, active, err);
                };
            }
            if (self.rows.get(id)) |current| if (current.generation == generation) {
                current.dirty = current.revision != revision;
            };
        }
        self.redraw_due_ms = null;
        if (self.hasDirty()) self.scheduleRedraw();
        return ids.items.len != 0;
    }

    fn owner(context: ?*c.JSContext, data: [*c]c.JSValue) !*Manager {
        var class: i64 = 0;
        if (c.JS_ToInt64(context, &class, data[1]) < 0) return error.JavaScriptException;
        const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], @intCast(class)) orelse return error.StaleNativeRendererOwner));
        return token.manager orelse error.StaleNativeRendererOwner;
    }
    fn failure(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
        return c.JS_ThrowTypeError(engine.context, "Native renderer: %s", @as([*:0]const u8, @errorName(err)));
    }

    fn resolverNext(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        const self = owner(context, data) catch |err| return failure(engine, err);
        var scope: i64 = 0;
        var index: i64 = 0;
        if (c.JS_ToInt64(context, &scope, data[2]) < 0 or c.JS_ToInt64(context, &index, data[3]) < 0) return engine.throwCaptured();
        if (scope <= 0 or self.active_resolution != @as(u64, @intCast(scope))) return failure(engine, error.StaleNativeRendererResolution);
        return self.resolveAt(data[4], data[5], data[6], @intCast(index), @intCast(scope)) catch |err| failure(engine, err);
    }

    fn resolveAt(self: *Manager, name: c.JSValue, base: c.JSValue, snapshot: c.JSValue, index: usize, scope: u64) !c.JSValue {
        const callback = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, snapshot, @intCast(index)));
        defer self.engine.freeValue(callback);
        if (c.JS_IsUndefined(callback)) return c.JS_DupValue(self.engine.context, base);
        var data = [_]c.JSValue{ self.token, c.JS_NewInt64(self.engine.context, self.token_class), c.JS_NewInt64(self.engine.context, @intCast(scope)), c.JS_NewInt64(self.engine.context, @intCast(index + 1)), name, base, snapshot };
        defer for (data[1..4]) |value| self.engine.freeValue(value);
        const next = try self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, resolverNext, "next", 0, 0, data.len, &data));
        defer self.engine.freeValue(next);
        var args = [_]c.JSValue{ name, next };
        // Upstream resolver is synchronous. Return actual functions/components
        // from this owner, preserving next() and base object identity.
        const result = try self.engine.checked(c.JS_Call(self.engine.context, callback, c.pi_js_undefined(), 2, &args));
        errdefer self.engine.freeValue(result);
        if (c.JS_IsObject(result)) {
            const then = try self.get(result, "then");
            defer self.engine.freeValue(then);
            if (c.JS_IsFunction(self.engine.context, then)) return error.NativeRendererResolverMustBeSynchronous;
        }
        return result;
    }

    pub fn resolve(self: *Manager, name: []const u8, base: c.JSValue) !c.JSValue {
        if (self.next_resolution == 9_007_199_254_740_991) return error.NativeRendererGenerationLimit;
        const scope = self.next_resolution;
        self.next_resolution += 1;
        const previous = self.active_resolution;
        self.active_resolution = scope;
        defer self.active_resolution = previous;
        const snapshot = try self.engine.checked(c.JS_NewArray(self.engine.context));
        defer self.engine.freeValue(snapshot);
        for (self.resolvers.items, 0..) |entry, index| if (c.JS_SetPropertyUint32(self.engine.context, snapshot, @intCast(index), c.JS_DupValue(self.engine.context, entry.callback)) < 0) return error.JavaScriptException;
        const text = try self.engine.checked(c.JS_NewStringLen(self.engine.context, name.ptr, name.len));
        defer self.engine.freeValue(text);
        return self.resolveAt(text, base, snapshot, 0, scope);
    }

    fn row(self: *Manager, id: []const u8, tool: []const u8, args: c.JSValue) !*Row {
        if (self.rows.get(id)) |existing| {
            if (!std.mem.eql(u8, existing.tool, tool)) return error.NativeRendererRowOwnerMismatch;
            return existing;
        }
        if (self.rows.count() == 16_384 or self.next_row == 9_007_199_254_740_991) return error.NativeRendererLimit;
        const key = try self.engine.gpa.dupe(u8, id);
        errdefer self.engine.gpa.free(key);
        const owner_name = try self.engine.gpa.dupe(u8, tool);
        errdefer self.engine.gpa.free(owner_name);
        const state = try self.engine.checked(c.JS_NewObject(self.engine.context));
        errdefer self.engine.freeValue(state);
        const created = try self.engine.gpa.create(Row);
        errdefer self.engine.gpa.destroy(created);
        try self.rows.ensureUnusedCapacity(self.engine.gpa, 1);
        created.* = .{ .generation = self.next_row, .tool = owner_name, .args = c.JS_DupValue(self.engine.context, args), .state = state, .call = c.pi_js_undefined(), .result = c.pi_js_undefined(), .source_tool = c.pi_js_undefined(), .snapshot = c.pi_js_undefined(), .call_payload = c.pi_js_undefined(), .result_payload = c.pi_js_undefined() };
        self.next_row += 1;
        self.rows.putAssumeCapacityNoClobber(key, created);
        return created;
    }

    fn invalidateRow(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        const self = owner(context, data) catch return c.pi_js_undefined();
        const id = engine.toString(data[2]) catch |err| return failure(engine, err);
        defer engine.gpa.free(id);
        var generation: i64 = 0;
        if (c.JS_ToInt64(context, &generation, data[3]) < 0) return engine.throwCaptured();
        const selected = self.rows.get(id) orelse return c.pi_js_undefined();
        if (selected.generation != @as(u64, @intCast(generation))) return c.pi_js_undefined();
        selected.dirty = true;
        selected.revision +%= 1;
        self.scheduleRedraw();
        return c.pi_js_undefined();
    }

    fn rowContext(self: *Manager, id: []const u8, selected: *Row, payload: c.JSValue, snapshot: ?c.JSValue, call_slot: bool) !c.JSValue {
        const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
        errdefer self.engine.freeValue(object);
        try self.put(object, "args", c.JS_DupValue(self.engine.context, selected.args));
        try self.put(object, "toolCallId", try self.engine.checked(c.JS_NewStringLen(self.engine.context, id.ptr, id.len)));
        try self.put(object, "state", c.JS_DupValue(self.engine.context, selected.state));
        try self.put(object, "lastComponent", c.JS_DupValue(self.engine.context, if (call_slot) selected.call else selected.result));
        inline for (.{ "executionStarted", "argsComplete", "isPartial", "expanded", "showImages", "isError" }) |name| {
            try self.put(object, name, try self.flag(payload, name, comptime std.mem.eql(u8, name, "executionStarted") or std.mem.eql(u8, name, "argsComplete") or std.mem.eql(u8, name, "showImages")));
        }
        const pad = try self.get(payload, "outputPad");
        defer self.engine.freeValue(pad);
        try self.put(object, "outputPad", if (c.JS_IsUndefined(pad)) c.JS_NewInt32(self.engine.context, 1) else c.JS_DupValue(self.engine.context, pad));
        const partial = try self.get(object, "isPartial");
        defer self.engine.freeValue(partial);
        if (!call_slot) {
            const duration = try self.get(payload, "durationMs");
            defer self.engine.freeValue(duration);
            selected.duration_ms = null;
            if (c.JS_ToBool(self.engine.context, partial) == 0 and !c.JS_IsNull(duration) and !c.JS_IsUndefined(duration)) {
                var milliseconds: f64 = 0;
                if (c.JS_ToFloat64(self.engine.context, &milliseconds, duration) < 0) return error.JavaScriptException;
                selected.duration_ms = milliseconds;
            }
        }
        try self.put(object, "durationMs", if (selected.duration_ms) |duration| c.JS_NewFloat64(self.engine.context, duration) else c.pi_js_undefined());
        const cwd = if (snapshot) |current| try self.get(current, "cwd") else c.pi_js_undefined();
        defer self.engine.freeValue(cwd);
        try self.put(object, "cwd", if (c.JS_IsUndefined(cwd)) try self.engine.checked(c.JS_NewString(self.engine.context, ".")) else c.JS_DupValue(self.engine.context, cwd));
        var data = [_]c.JSValue{ self.token, c.JS_NewInt64(self.engine.context, self.token_class), try self.engine.checked(c.JS_NewStringLen(self.engine.context, id.ptr, id.len)), c.JS_NewInt64(self.engine.context, @intCast(selected.generation)) };
        defer for (data[1..]) |value| self.engine.freeValue(value);
        try self.put(object, "invalidate", try self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, invalidateRow, "invalidate", 0, 0, data.len, &data)));
        return object;
    }

    fn width(self: *Manager, payload: c.JSValue, snapshot: ?c.JSValue) !usize {
        var value = try self.get(payload, "width");
        defer self.engine.freeValue(value);
        if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) if (snapshot) |context| {
            self.engine.freeValue(value);
            value = try self.get(context, "width");
        };
        if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) return 80;
        var number: f64 = 0;
        if (c.JS_ToFloat64(self.engine.context, &number, value) < 0) return error.JavaScriptException;
        if (!std.math.isFinite(number) or number < 0 or number > 16_384) return error.NativeComponentViewportLimit;
        return @intFromFloat(number);
    }

    fn render(self: *Manager, component: c.JSValue, available_width: usize) !components.Frame {
        if (c.JS_IsNull(component) or c.JS_IsUndefined(component)) return .{ .gpa = self.engine.gpa, .lines = try self.engine.gpa.alloc([]u8, 0), .bytes = 0 };
        if (c.JS_IsObject(component) and !try self.isArray(component)) {
            const renderer = try self.get(component, "render");
            defer self.engine.freeValue(renderer);
            if (c.JS_IsFunction(self.engine.context, renderer)) {
                var args = [_]c.JSValue{c.JS_NewInt64(self.engine.context, @intCast(available_width))};
                defer self.engine.freeValue(args[0]);
                const lines = try self.invoke(renderer, component, &args);
                defer self.engine.freeValue(lines);
                return components.normalizeWithPredicate(self.engine, lines, self.array_predicate);
            }
        }
        return components.normalizeWithPredicate(self.engine, component, self.array_predicate);
    }

    fn output(self: *Manager, found: bool, frame: ?*components.Frame) !c.JSValue {
        const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
        errdefer self.engine.freeValue(object);
        try self.put(object, "found", c.pi_js_bool(self.engine.context, @intFromBool(found)));
        try self.put(object, "lines", if (frame) |actual| try components.frameToValue(actual, self.engine) else try self.engine.checked(c.JS_NewArray(self.engine.context)));
        return object;
    }

    pub fn run(self: *Manager, kind: Kind, name: []const u8, payload: c.JSValue, snapshot: ?c.JSValue, tool: c.JSValue) !c.JSValue {
        return self.runOwned(0, kind, name, payload, snapshot, tool);
    }

    pub fn runOwned(self: *Manager, owner_id: u64, kind: Kind, name: []const u8, payload: c.JSValue, snapshot: ?c.JSValue, tool: c.JSValue) !c.JSValue {
        if (kind == .renderer_retire) {
            const value = try self.get(payload, "toolCallId");
            defer self.engine.freeValue(value);
            const id = try self.engine.toString(value);
            defer self.engine.gpa.free(id);
            if (self.rows.get(id)) |selected| if (!std.mem.eql(u8, selected.tool, name)) return error.NativeRendererRowOwnerMismatch;
            const expected = try self.get(payload, "rowGeneration");
            defer self.engine.freeValue(expected);
            var generation: ?u64 = null;
            if (!c.JS_IsUndefined(expected)) {
                var number: f64 = 0;
                if (c.JS_ToFloat64(self.engine.context, &number, expected) < 0) return error.JavaScriptException;
                if (!std.math.isFinite(number) or number <= 0 or number > 9_007_199_254_740_991 or @floor(number) != number) return error.InvalidNativeRendererGeneration;
                generation = @intFromFloat(number);
            }
            const removed = self.retire(id, generation);
            const object = try self.output(removed, null);
            errdefer self.engine.freeValue(object);
            try self.put(object, "retired", c.pi_js_bool(self.engine.context, @intFromBool(removed)));
            return object;
        }
        if (kind == .prepare_tool_arguments) {
            const args = try self.objectOrDefault(payload, "args");
            defer self.engine.freeValue(args);
            const callback = if (c.JS_IsObject(tool)) try self.get(tool, "prepareArguments") else c.pi_js_undefined();
            defer self.engine.freeValue(callback);
            var parameters = [_]c.JSValue{args};
            const found = c.JS_IsFunction(self.engine.context, callback);
            const prepared = if (found) try self.invoke(callback, tool, &parameters) else c.JS_DupValue(self.engine.context, args);
            defer self.engine.freeValue(prepared);
            if (found and (!c.JS_IsObject(prepared) or try self.isArray(prepared))) return error.InvalidPreparedToolArguments;
            const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
            errdefer self.engine.freeValue(object);
            try self.put(object, "found", c.pi_js_bool(self.engine.context, @intFromBool(found)));
            try self.put(object, "arguments", c.JS_DupValue(self.engine.context, prepared));
            return object;
        }
        if (kind == .transform_markdown) {
            const original = try self.get(payload, "markdown");
            defer self.engine.freeValue(original);
            const text = if (c.JS_IsNull(original) or c.JS_IsUndefined(original)) try self.engine.checked(c.JS_NewString(self.engine.context, "")) else try self.engine.checked(c.JS_ToString(self.engine.context, original));
            defer self.engine.freeValue(text);
            const context = try self.engine.checked(c.JS_NewObject(self.engine.context));
            defer self.engine.freeValue(context);
            const message_type = try self.get(payload, "messageType");
            defer self.engine.freeValue(message_type);
            try self.put(context, "messageType", if (c.JS_IsNull(message_type) or c.JS_IsUndefined(message_type)) try self.engine.checked(c.JS_NewString(self.engine.context, "assistant")) else c.JS_DupValue(self.engine.context, message_type));
            try self.put(context, "isStreaming", try self.flag(payload, "isStreaming", false));
            const available = try self.get(payload, "availableWidth");
            defer self.engine.freeValue(available);
            try self.put(context, "availableWidth", if (c.JS_IsUndefined(available)) c.JS_NewInt64(self.engine.context, @intCast(try self.width(payload, snapshot))) else c.JS_DupValue(self.engine.context, available));
            var parameters = [_]c.JSValue{ text, context };
            const callback = for (self.transformers.items) |entry| {
                if (entry.owner_id == owner_id) break c.JS_DupValue(self.engine.context, entry.callback);
            } else null;
            defer if (callback) |value| self.engine.freeValue(value);
            const result = if (callback) |value| try self.invoke(value, c.pi_js_undefined(), &parameters) else c.JS_DupValue(self.engine.context, text);
            defer self.engine.freeValue(result);
            const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
            errdefer self.engine.freeValue(object);
            try self.put(object, "found", c.pi_js_bool(self.engine.context, @intFromBool(callback != null)));
            try self.put(object, "markdown", if (c.JS_IsNull(result) or c.JS_IsUndefined(result)) c.JS_DupValue(self.engine.context, text) else try self.engine.checked(c.JS_ToString(self.engine.context, result)));
            return object;
        }
        if (kind == .render_message or kind == .render_entry) {
            const registered = for ((if (kind == .render_message) &self.messages else &self.entries).items) |entry| {
                if (entry.owner_id == owner_id and std.mem.eql(u8, entry.name, name)) break entry.callback;
            } else return self.output(false, null);
            const callback = c.JS_DupValue(self.engine.context, registered);
            defer self.engine.freeValue(callback);
            const value = try self.objectOrDefault(payload, if (kind == .render_message) "message" else "entry");
            defer self.engine.freeValue(value);
            const options = try self.engine.checked(c.JS_NewObject(self.engine.context));
            defer self.engine.freeValue(options);
            try self.put(options, "expanded", try self.flag(payload, "expanded", false));
            if (kind == .render_message) {
                const pad = try self.get(payload, "outputPad");
                defer self.engine.freeValue(pad);
                try self.put(options, "outputPad", if (c.JS_IsUndefined(pad)) c.JS_NewInt32(self.engine.context, 0) else c.JS_DupValue(self.engine.context, pad));
            }
            var parameters = [_]c.JSValue{ value, options, self.theme };
            const component = try self.invoke(callback, c.pi_js_undefined(), &parameters);
            defer self.engine.freeValue(component);
            if (kind == .render_message and c.JS_ToBool(self.engine.context, component) == 0) return self.output(false, null);
            var frame = try self.render(component, try self.width(payload, snapshot));
            defer frame.deinit();
            return self.output(true, &frame);
        }
        return self.renderTool(owner_id, kind, name, payload, snapshot, tool);
    }

    fn renderTool(self: *Manager, owner_id: u64, kind: Kind, name: []const u8, payload: c.JSValue, snapshot: ?c.JSValue, tool: c.JSValue) !c.JSValue {
        const resolved = try self.resolve(name, tool);
        defer self.engine.freeValue(resolved);
        if (!c.JS_IsObject(resolved)) return self.output(false, null);
        const call_slot = kind == .render_tool_call;
        const callback = try self.get(resolved, if (call_slot) "renderCall" else "renderResult");
        defer self.engine.freeValue(callback);
        if (!c.JS_IsFunction(self.engine.context, callback)) return self.output(false, null);
        const identifier = try self.get(payload, "toolCallId");
        defer self.engine.freeValue(identifier);
        const id = if (c.JS_IsNull(identifier) or c.JS_IsUndefined(identifier)) try std.fmt.allocPrint(self.engine.gpa, "{s}:default", .{name}) else try self.engine.toString(identifier);
        defer self.engine.gpa.free(id);
        if (id.len == 0 or id.len > 4096) return error.InvalidNativeRendererRow;
        const args = try self.get(payload, "args");
        defer self.engine.freeValue(args);
        const initial_args = if (c.JS_IsNull(args) or c.JS_IsUndefined(args)) try self.engine.checked(c.JS_NewObject(self.engine.context)) else c.JS_DupValue(self.engine.context, args);
        defer self.engine.freeValue(initial_args);
        const selected = try self.row(id, name, initial_args);
        const generation = selected.generation;
        if (!c.JS_IsNull(args) and !c.JS_IsUndefined(args)) {
            const retained = c.JS_DupValue(self.engine.context, args);
            self.engine.freeValue(selected.args);
            selected.args = retained;
        }
        const context = try self.rowContext(id, selected, payload, snapshot, call_slot);
        defer self.engine.freeValue(context);
        const value = if (call_slot) try self.get(context, "args") else try self.objectOrDefault(payload, "result");
        defer self.engine.freeValue(value);
        const options = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(options);
        try self.put(options, "expanded", try self.flag(payload, "expanded", false));
        try self.put(options, "isPartial", try self.flag(payload, "isPartial", false));
        var call_args = [_]c.JSValue{ value, self.theme, context };
        var result_args = [_]c.JSValue{ value, options, self.theme, context };
        const component = try self.invoke(callback, resolved, if (call_slot) &call_args else &result_args);
        defer self.engine.freeValue(component);
        const active = self.rows.get(id) orelse return error.NativeRendererRowRetired;
        if (active.generation != generation) return error.NativeRendererRowRetired;
        const captured_tool = c.JS_DupValue(self.engine.context, tool);
        const captured_snapshot = if (snapshot) |saved_context| c.JS_DupValue(self.engine.context, saved_context) else c.pi_js_undefined();
        const captured_payload = c.JS_DupValue(self.engine.context, payload);
        self.engine.freeValue(active.source_tool);
        self.engine.freeValue(active.snapshot);
        const previous_payload = if (call_slot) &active.call_payload else &active.result_payload;
        self.engine.freeValue(previous_payload.*);
        previous_payload.* = captured_payload;
        active.source_tool = captured_tool;
        active.snapshot = captured_snapshot;
        active.owner_id = owner_id;
        const previous = if (call_slot) &active.call else &active.result;
        const retained = c.JS_DupValue(self.engine.context, component);
        self.engine.freeValue(previous.*);
        previous.* = retained;
        const revision = active.revision;
        const available_width = try self.width(payload, snapshot);
        var frame = try self.render(component, available_width);
        defer frame.deinit();
        const current = self.rows.get(id) orelse return error.NativeRendererRowRetired;
        if (current.generation != generation) return error.NativeRendererRowRetired;
        current.width = available_width;
        if (current.revision == revision) current.dirty = false;
        try self.emitFrame(id, current, if (call_slot) .call else .result, &frame);
        const object = try self.output(true, &frame);
        errdefer self.engine.freeValue(object);
        try self.put(object, "rowGeneration", c.JS_NewInt64(self.engine.context, @intCast(generation)));
        return object;
    }
};

test "native renderer owner preserves original getters errors and fences retained next and row invalidation across GC" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try native_tui.install(engine);
    const manager = try Manager.init(engine);
    defer manager.deinit();
    const module = try engine.evalModule("export const original={identity:true};export let savedNext;export function bad(){return {get render(){throw original}}};export function line(){return {render(){return new Proxy(['x'],{get(target,key){if(key==='0')throw original;return Reflect.get(target,key)}})}}};export function resolver(name,next){savedNext=next;const first=next(),second=next();if(first!==second)throw Error('base identity');return first};export const tool={renderCall(args,theme,ctx){return {render(width){ctx.invalidate();return [String(width)]}}}};", "renderer-original-values.mjs");
    defer engine.freeValue(module);
    const bad = try manager.get(module, "bad");
    defer engine.freeValue(bad);
    try manager.register(.message, "bad", bad);
    const line = try manager.get(module, "line");
    defer engine.freeValue(line);
    try manager.register(.message, "line", line);
    const original = try manager.get(module, "original");
    defer engine.freeValue(original);
    const payload = try engine.fromJsonValue(.{ .object = .empty });
    defer engine.freeValue(payload);
    for ([_][]const u8{ "bad", "line" }) |name| {
        try std.testing.expectError(error.JavaScriptException, manager.run(.render_message, name, payload, null, c.pi_js_undefined()));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, original));
        engine.beginInvocation();
    }
    const resolver = try manager.get(module, "resolver");
    defer engine.freeValue(resolver);
    try manager.register(.resolver, "", resolver);
    const tool = try manager.get(module, "tool");
    defer engine.freeValue(tool);
    const resolved = try manager.resolve("tool", tool);
    defer engine.freeValue(resolved);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, resolved, tool));
    const saved = try manager.get(module, "savedNext");
    defer engine.freeValue(saved);
    try std.testing.expectError(error.JavaScriptException, engine.checked(c.JS_Call(engine.context, saved, c.pi_js_undefined(), 0, null)));
    engine.beginInvocation();
    const rendered = try manager.run(.render_tool_call, "tool", payload, null, tool);
    defer engine.freeValue(rendered);
    const selected = manager.rows.get("tool:default").?;
    try std.testing.expect(selected.dirty and selected.revision == 1);
    const generation = selected.generation;
    c.JS_RunGC(engine.runtime);
    try std.testing.expect(manager.retire("tool:default", generation));
    c.JS_RunGC(engine.runtime);
    try std.testing.expectEqual(@as(usize, 0), manager.rows.count());
}

fn rendererAllocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try native_tui.install(engine);
    const manager = try Manager.init(engine);
    defer manager.deinit();
    const module = try engine.evalModule("import {Text} from 'pi-tui';export const tool={renderCall(args,theme,ctx){ctx.state.saved='owned';return ctx.lastComponent??new Text('call',0,0)},renderResult(value,options,theme,ctx){return new Text(ctx.state.saved,0,0)},prepareArguments(args){return {value:'prepared'}}};export function message(){return new Text('message',0,0)};export function resolver(name,next){return next()};export function transform(text){return text+'!'}", "renderer-allocation.mjs");
    defer engine.freeValue(module);
    const tool = try manager.get(module, "tool");
    defer engine.freeValue(tool);
    const callback = try manager.get(module, "message");
    defer engine.freeValue(callback);
    try manager.register(.message, "message", callback);
    try manager.register(.entry, "entry", callback);
    const transformer = try manager.get(module, "transform");
    defer engine.freeValue(transformer);
    try manager.register(.markdown, "", transformer);
    const resolver = try manager.get(module, "resolver");
    defer engine.freeValue(resolver);
    try manager.register(.resolver, "", resolver);
    const payload = try engine.fromJsonValue(.{ .object = .empty });
    defer engine.freeValue(payload);
    inline for (.{ Kind.prepare_tool_arguments, Kind.render_message, Kind.render_entry, Kind.transform_markdown, Kind.render_tool_call, Kind.render_tool_result }) |kind| {
        const result = try manager.run(kind, if (kind == .render_message) "message" else if (kind == .render_entry) "entry" else "tool", payload, null, tool);
        engine.freeValue(result);
    }
    c.JS_RunGC(engine.runtime);
    try std.testing.expect(manager.retire("tool:default", null));
    c.JS_RunGC(engine.runtime);
}

test "native renderer registrations row states and callback captures release every failed allocation" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            rendererAllocationProbe(gpa) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.JavaScriptException or err == error.OutOfMemory)) return error.OutOfMemory;
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
