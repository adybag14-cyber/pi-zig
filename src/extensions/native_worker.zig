//! Internal native extension process. The production runtime switches here
//! only after the complete compatibility surface is certified.
const std = @import("std");
const native_renderers = @import("native_renderers.zig");
const engine_mod = @import("engine.zig");
const bindings_mod = @import("native_bindings.zig");
const typescript = @import("typescript.zig");
const node_fs = @import("node_fs.zig");
const console = @import("console.zig");
const module_resolver = @import("module_resolver.zig");
const text_encoding = @import("text_encoding.zig");
const text_decoder = @import("text_decoder.zig");
const node_path = @import("node_path.zig");
const node_url = @import("node_url.zig");
const commonjs = @import("commonjs.zig");
const timers = @import("timers.zig");
const abort_signal = @import("abort_signal.zig");
const native_stream = @import("native_stream.zig");
const component_protocol = @import("component_protocol.zig");
const native_group = @import("native_group.zig");
const renderer_protocol = @import("renderer_protocol.zig");
const editor_protocol = @import("editor_protocol.zig");
const widget_protocol = @import("widget_protocol.zig");
const c = engine_mod.c;

const WireRecord = struct {
    const Kind = enum { request, abort, ui_response, component_control, provider_stream_ack, renderer_control, editor_control, widget_control, terminal_input, context_invalidate, shutdown };
    bytes: []u8,
    kind: Kind = .request,
};

// The reader task owns only bytes and synchronization. All C/QuickJS calls,
// including abort listeners and update serialization, stay on run()'s thread.
const Transport = struct {
    engine: *engine_mod.Engine,
    bindings: *bindings_mod.Bindings,
    io: std.Io,
    writer: *std.Io.Writer,
    group: *native_group.Group,
    initial_input: ?*std.Io.File.Reader = null,
    mutex: std.Io.Mutex = .init,
    available: std.Io.Event = .unset,
    records: std.ArrayList(WireRecord) = .empty,
    queued_bytes: usize = 0,
    finished: bool = false,
    reader_error: ?anyerror = null,
    active: bool = false,
    active_id: []const u8 = "",
    active_tool_call_id: ?[]const u8 = null,
    active_signal: ?c.JSValue = null,
    stream_updates: bool = false,
    updates: std.ArrayList([]u8) = .empty,
    terminal: bool = false,
    shutdown_requested: bool = false,
    terminal_abort_sent: bool = false,
    next_id: u64 = 1,
    seen_ids: std.StringHashMapUnmanaged(void) = .empty,
    metadata_revision: u64 = 0,
    metadata_snapshot: ?[]u8 = null,

    fn deinit(self: *Transport) void {
        if (self.metadata_snapshot) |snapshot| self.engine.gpa.free(snapshot);
        self.clearActive();
        for (self.records.items) |record| std.heap.page_allocator.free(record.bytes);
        self.records.deinit(std.heap.page_allocator);
        self.updates.deinit(self.engine.gpa);
        var ids = self.seen_ids.keyIterator();
        while (ids.next()) |id| self.engine.gpa.free(id.*);
        self.seen_ids.deinit(self.engine.gpa);
    }

    fn clearActive(self: *Transport) void {
        self.active = false;
        self.active_id = "";
        self.active_tool_call_id = null;
        self.bindings.clearInvocationOptions();
        if (self.active_signal) |signal| self.engine.freeValue(signal);
        self.active_signal = null;
        for (self.updates.items) |update| self.engine.gpa.free(update);
        self.updates.clearRetainingCapacity();
    }

    fn classify(bytes: []const u8) WireRecord.Kind {
        var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
        defer arena.deinit();
        const value = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), bytes, .{}) catch return .request;
        if (value != .object) return .request;
        const kind = value.object.get("kind") orelse return .request;
        if (kind != .string) return .request;
        if (std.mem.eql(u8, kind.string, "abort_current") or std.mem.eql(u8, kind.string, "abort")) return .abort;
        if (std.mem.eql(u8, kind.string, "shutdown")) return .shutdown;
        if (std.mem.eql(u8, kind.string, "ui_response")) return .ui_response;
        if (std.mem.eql(u8, kind.string, "provider_stream_ack")) return .provider_stream_ack;
        if (std.mem.eql(u8, kind.string, "component_control")) return .component_control;
        if (std.mem.eql(u8, kind.string, "renderer_control") or std.mem.eql(u8, kind.string, "renderer_subscribe")) return .renderer_control;
        if (std.mem.eql(u8, kind.string, "editor_control") or std.mem.eql(u8, kind.string, "editor_subscribe")) return .editor_control;
        if (std.mem.eql(u8, kind.string, "widget_control")) return .widget_control;
        if (std.mem.eql(u8, kind.string, "terminal_input")) return .terminal_input;
        if (std.mem.eql(u8, kind.string, "context_invalidate")) return .context_invalidate;
        return .request;
    }

    fn enqueue(self: *Transport, bytes: []u8) !void {
        const record: WireRecord = .{ .bytes = bytes, .kind = classify(bytes) };
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        // Apply backpressure through a bounded queue rather than allowing a
        // stopped extension to retain unbounded stdin in host memory.
        if (self.records.items.len >= 128 or bytes.len > 8 * 1024 * 1024 - self.queued_bytes) return error.NativeWorkerQueueLimit;
        try self.records.append(std.heap.page_allocator, record);
        self.queued_bytes += bytes.len;
        self.available.set(self.io);
    }

    fn finishReader(self: *Transport, err: ?anyerror) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.finished = true;
        self.reader_error = err;
        self.available.set(self.io);
    }

    fn readInput(self: *Transport) !void {
        var buffer: [4096]u8 = undefined;
        var default_input = std.Io.File.stdin().readerStreaming(self.io, &buffer);
        const input = self.initial_input orelse &default_input;
        while (true) {
            var line: std.ArrayList(u8) = .empty;
            defer line.deinit(std.heap.page_allocator);
            while (true) {
                const byte = input.interface.takeByte() catch |err| switch (err) {
                    error.EndOfStream => {
                        if (std.mem.trim(u8, line.items, " \t\r").len != 0) return error.IncompleteNativeWorkerRequest;
                        return;
                    },
                    else => return err,
                };
                if (byte == '\n') break;
                if (line.items.len >= 4 * 1024 * 1024) return error.NativeWorkerRequestTooLarge;
                try line.append(std.heap.page_allocator, byte);
            }
            if (std.mem.trim(u8, line.items, " \t\r").len == 0) continue;
            const bytes = try line.toOwnedSlice(std.heap.page_allocator);
            self.enqueue(bytes) catch |err| {
                std.heap.page_allocator.free(bytes);
                return err;
            };
        }
    }

    fn readerTask(self: *Transport) std.Io.Cancelable!void {
        self.readInput() catch |err| {
            self.finishReader(err);
            return;
        };
        self.finishReader(null);
    }

    fn next(self: *Transport) !?WireRecord {
        while (true) {
            self.engine.beginInvocation();
            self.pumpIdle() catch |err| {
                if (err != error.JavaScriptException) return err;
                var arena: std.heap.ArenaAllocator = .init(self.engine.gpa);
                defer arena.deinit();
                var object: std.json.ObjectMap = .empty;
                try object.put(arena.allocator(), "type", .{ .string = "native_owner_error" });
                try object.put(arena.allocator(), "error", .{ .string = self.engine.last_error orelse @errorName(err) });
                try writeRecord(self.writer, .{ .object = object });
            };
            try self.publishMetadataSafe();
            var deadline = try timers.nextDeadline(self.engine);
            if (self.group.ui.footer_data.next_poll) |footer_due| deadline = if (deadline) |due| @min(due, footer_due) else footer_due;
            if (self.group.renderers.nextRedrawDeadline()) |redraw_due| {
                deadline = if (deadline) |due| @min(due, redraw_due) else redraw_due;
            }
            self.mutex.lockUncancelable(self.io);
            self.available.reset();
            if (self.records.items.len != 0) {
                const record = self.records.orderedRemove(0);
                self.queued_bytes -= record.bytes.len;
                self.mutex.unlock(self.io);
                return record;
            }
            const finished = self.finished;
            const failure = self.reader_error;
            self.mutex.unlock(self.io);
            if (finished) {
                if (failure) |err| return err;
                return null;
            }
            // A background owner request may have notified between pumpIdle
            // and the wire queue reset. Drain after reset before waiting so
            // its notification cannot be lost while stdin is otherwise idle.
            if (self.engine.native_durable_control_pump != null and try self.engine.pumpControls()) continue;
            if (deadline) |due| {
                const remaining = due - std.Io.Clock.awake.now(self.io).toMilliseconds();
                if (remaining <= 0) continue;
                self.available.waitTimeout(self.io, .{ .duration = .{ .raw = .fromMilliseconds(remaining), .clock = .awake } }) catch |err| switch (err) {
                    error.Timeout => continue,
                    else => return err,
                };
            } else try self.available.wait(self.io);
        }
    }

    fn pumpIdle(self: *Transport) !void {
        _ = try self.engine.pumpControls();
        _ = try self.engine.drainReadyJobs();
        if (try timers.pumpReady(self.engine)) _ = try self.engine.drainReadyJobs();
        _ = try self.group.renderers.pumpDirtyReady();
        _ = try self.group.ui.editors.pumpDirty();
        _ = try self.group.ui.widgets.pumpDirty();
        _ = try self.group.ui.footer_data.poll();
    }
    fn notifyOwner(raw: ?*anyopaque) void {
        const self: *Transport = @ptrCast(@alignCast(raw.?));
        self.available.set(self.io);
    }

    fn publishMetadataSafe(self: *Transport) !void {
        self.publishMetadata() catch |err| {
            var arena: std.heap.ArenaAllocator = .init(self.engine.gpa);
            defer arena.deinit();
            var object: std.json.ObjectMap = .empty;
            try object.put(arena.allocator(), "type", .{ .string = "native_owner_error" });
            try object.put(arena.allocator(), "error", .{ .string = @errorName(err) });
            try writeRecord(self.writer, .{ .object = object });
        };
    }

    fn publishMetadata(self: *Transport) !void {
        if (self.group.registration_failure) |err| return err;
        const snapshot = try self.group.manifest();
        errdefer self.engine.gpa.free(snapshot);
        const pending_registrations = self.group.activation.sequence != self.group.published_registration_sequence;
        if (self.metadata_snapshot) |old| if (!pending_registrations and std.mem.eql(u8, old, snapshot)) {
            self.engine.gpa.free(snapshot);
            return;
        };
        const revision = std.math.add(u64, self.metadata_revision, 1) catch return error.NativeMetadataRevisionExhausted;
        try self.writer.print("\x1e{{\"type\":\"native_metadata\",\"version\":1,\"ownerGeneration\":\"{d}\",\"revision\":\"{d}\",\"extensions\":", .{ self.group.renderers.owner_generation, revision });
        try self.writer.writeAll(snapshot);
        try self.writer.print(",\"registrationSequence\":\"{d}\",\"toolRegistrations\":[", .{self.group.activation.sequence});
        var first = true;
        for (self.group.registration_journal.items) |event| {
            if (event.sequence <= self.group.published_registration_sequence) continue;
            if (!first) try self.writer.writeByte(',');
            first = false;
            try std.json.Stringify.value(event, .{}, self.writer);
        }
        try self.writer.writeByte(']');
        try self.writer.writeAll("}\n");
        try self.writer.flush();
        if (self.metadata_snapshot) |old| self.engine.gpa.free(old);
        self.metadata_snapshot = snapshot;
        self.metadata_revision = revision;
        self.group.published_registration_sequence = self.group.activation.sequence;
    }

    fn takeControl(self: *Transport) ?WireRecord {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.records.items, 0..) |record, index| {
            if (record.kind == .abort or record.kind == .ui_response or record.kind == .component_control or record.kind == .provider_stream_ack or record.kind == .renderer_control or record.kind == .editor_control or record.kind == .widget_control or record.kind == .terminal_input or record.kind == .context_invalidate or (self.active and record.kind == .shutdown and index == 0)) {
                const removed = self.records.orderedRemove(index);
                self.queued_bytes -= removed.bytes.len;
                return removed;
            }
        }
        return null;
    }

    fn inputEnded(self: *Transport) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.finished and self.records.items.len == 0;
    }

    fn abortActive(self: *Transport, reason: std.json.Value) !void {
        const signal = self.active_signal orelse return;
        const value = try self.engine.fromJsonValue(reason);
        defer self.engine.freeValue(value);
        try abort_signal.abort(self.engine, signal, value);
    }

    fn pump(engine: *engine_mod.Engine) !bool {
        const self: *Transport = @ptrCast(@alignCast(engine.host_control_context.?));
        var dispatched = false;
        while (self.takeControl()) |record| {
            defer std.heap.page_allocator.free(record.bytes);
            var arena: std.heap.ArenaAllocator = .init(engine.gpa);
            defer arena.deinit();
            const request = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), record.bytes, .{});
            if (record.kind == .context_invalidate) {
                try self.contextInvalidate(request);
                dispatched = true;
                continue;
            }
            if (record.kind == .terminal_input) {
                try self.terminalInput(request);
                dispatched = true;
                continue;
            }
            if (record.kind == .widget_control) {
                try self.widgetControl(request);
                dispatched = true;
                continue;
            }
            if (record.kind == .editor_control) {
                try self.editorControl(request);
                dispatched = true;
                continue;
            }
            if (record.kind == .renderer_control) {
                try self.rendererControl(request);
                dispatched = true;
                continue;
            }
            if (!self.active) continue;
            if (record.kind == .shutdown) {
                self.shutdown_requested = true;
                self.terminal = true;
            } else if (request == .object) {
                const id = request.object.get("invocationId") orelse continue;
                // Require an explicit identity: stale or untargeted controls
                // cannot cancel a later invocation that happens to be active.
                if (id != .string or !std.mem.eql(u8, id.string, self.active_id)) continue;
                if (record.kind == .component_control) {
                    var control = component_protocol.readControl(engine.gpa, &request.object) catch continue;
                    defer control.deinit();
                    _ = try self.bindings.ui_manager.componentControl(&control);
                } else if (record.kind == .provider_stream_ack) {
                    const sequence = request.object.get("sequence") orelse continue;
                    const success = request.object.get("ok") orelse continue;
                    if (sequence != .integer or sequence.integer <= 0 or success != .bool) continue;
                    const accepted = request.object.get("accepted") orelse std.json.Value{ .bool = true };
                    const reason = try engine.fromJsonValue(request.object.get("error") orelse std.json.Value{ .string = "Native host rejected provider stream event" });
                    defer engine.freeValue(reason);
                    try self.bindings.stream_runner.acknowledge(@intCast(sequence.integer), success.bool, accepted == .bool and accepted.bool, reason);
                } else if (record.kind == .ui_response) {
                    const request_id = request.object.get("id") orelse continue;
                    if (request_id != .integer or request_id.integer <= 0 or request_id.integer > std.math.maxInt(u32)) continue;
                    const success = request.object.get("ok") orelse continue;
                    if (success != .bool) continue;
                    const value = if (success.bool) try engine.fromJsonValue(request.object.get("result") orelse std.json.Value.null) else blk: {
                        const reason = request.object.get("error") orelse std.json.Value{ .string = "Native UI request failed" };
                        const text = if (reason == .string) try engine.gpa.dupe(u8, reason.string) else try encoded(engine.gpa, reason);
                        defer engine.gpa.free(text);
                        const failure = try engine.checked(c.JS_NewError(engine.context));
                        errdefer engine.freeValue(failure);
                        if (c.JS_DefinePropertyValueStr(engine.context, failure, "message", c.JS_NewStringLen(engine.context, text.ptr, text.len), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
                        break :blk failure;
                    };
                    defer engine.freeValue(value);
                    try self.bindings.ui_manager.respond(@intCast(request_id.integer), success.bool, value);
                } else try self.abortActive(request.object.get("reason") orelse std.json.Value{ .string = "Operation aborted" });
                dispatched = true;
            }
        }
        if (try self.bindings.ui_manager.poll()) dispatched = true;
        try self.bindings.stream_runner.poll();
        if (self.inputEnded()) self.terminal = true;
        if (self.terminal) {
            if (self.bindings.stream_runner.cleaning) return dispatched;
            if (self.terminal_abort_sent) {
                if (c.JS_IsJobPending(engine.runtime)) return true;
                return error.NativeWorkerInputClosed;
            }
            self.terminal_abort_sent = true;
            try self.abortActive(.{ .string = "Native extension transport closed" });
            return true;
        }
        return dispatched;
    }

    fn rendererControl(self: *Transport, request: std.json.Value) !void {
        if (request != .object) return error.InvalidRendererControl;
        const kind = try requiredText(request.object, "kind");
        if (std.mem.eql(u8, kind, "renderer_subscribe")) {
            const generation = component_protocol.identifier(request.object.get("ownerGeneration") orelse return error.InvalidRendererIdentity) catch return error.InvalidRendererIdentity;
            const version_value = request.object.get("version") orelse return error.InvalidRendererVersion;
            if (version_value != .integer or version_value.integer != renderer_protocol.version) return error.InvalidRendererVersion;
            if (generation != self.group.renderers.owner_generation) return;
            const enabled = request.object.get("enabled") orelse return error.InvalidRendererControl;
            if (enabled != .bool) return error.InvalidRendererControl;
            self.group.renderers.subscribe(enabled.bool);
        } else {
            var control = try renderer_protocol.readControl(self.engine.gpa, &request.object);
            defer control.deinit();
            _ = try self.group.renderers.control(&control);
        }
    }
    fn persistentControl(self: *Transport, kind: WireRecord.Kind, request: std.json.Value) !bool {
        switch (kind) {
            .context_invalidate => try self.contextInvalidate(request),
            .terminal_input => try self.terminalInput(request),
            .widget_control => try self.widgetControl(request),
            .renderer_control => try self.rendererControl(request),
            .editor_control => try self.editorControl(request),
            else => return false,
        }
        return true;
    }

    fn contextInvalidate(self: *Transport, request: std.json.Value) !void {
        if (request != .object) return error.InvalidContextInvalidation;
        const id = try component_protocol.identifier(request.object.get("id") orelse return error.InvalidContextInvalidation);
        const generation = try component_protocol.identifier(request.object.get("ownerGeneration") orelse return error.InvalidContextInvalidation);
        if (generation != self.group.ui.widgets.owner_generation) return;
        const message = if (request.object.get("message")) |value| if (value == .string) value.string else return error.InvalidContextInvalidation else @import("native_context_lifetime.zig").default_message;
        if (message.len > 65536) return error.InvalidContextInvalidation;
        const invalidated = self.group.invalidateContexts(message) catch |err| {
            try self.writer.print("\x1e{{\"type\":\"context_invalidate_result\",\"id\":\"{d}\",\"ownerGeneration\":\"{d}\",\"ok\":false,\"error\":", .{ id, generation });
            try std.json.Stringify.value(@errorName(err), .{}, self.writer);
            try self.writer.writeAll("}\n");
            try self.writer.flush();
            return;
        };
        try self.writer.print("\x1e{{\"type\":\"context_invalidate_result\",\"id\":\"{d}\",\"ownerGeneration\":\"{d}\",\"ok\":true,\"invalidated\":{d}}}\n", .{ id, generation, invalidated });
        try self.writer.flush();
    }
    fn widgetControl(self: *Transport, request: std.json.Value) !void {
        if (request != .object) return error.InvalidWidgetControl;
        const control = try widget_protocol.readControl(&request.object);
        if (control.owner_generation != self.group.ui.widgets.owner_generation) return;
        try self.group.ui.widgets.resize(control.width, control.height);
    }
    fn terminalInput(self: *Transport, request: std.json.Value) !void {
        if (request != .object) return error.InvalidTerminalInput;
        const id = try component_protocol.identifier(request.object.get("id") orelse return error.InvalidTerminalInput);
        const generation = try component_protocol.identifier(request.object.get("ownerGeneration") orelse return error.InvalidTerminalInput);
        if (generation != self.group.ui.widgets.owner_generation) return;
        const input = try requiredText(request.object, "data");
        const transformed = self.group.ui.terminal_input.dispatch(input) catch |err| {
            try self.writer.print("\x1e{{\"type\":\"terminal_input_result\",\"id\":\"{d}\",\"ownerGeneration\":\"{d}\",\"consume\":false,\"data\":", .{ id, generation });
            try std.json.Stringify.value(input, .{}, self.writer);
            try self.writer.writeAll(",\"error\":");
            try std.json.Stringify.value(self.engine.last_error orelse @errorName(err), .{}, self.writer);
            try self.writer.writeAll("}\n");
            try self.writer.flush();
            return;
        };
        defer self.engine.gpa.free(transformed.data);
        try self.writer.print("\x1e{{\"type\":\"terminal_input_result\",\"id\":\"{d}\",\"ownerGeneration\":\"{d}\",\"consume\":{},\"data\":", .{ id, generation, transformed.consume });
        try std.json.Stringify.value(transformed.data, .{}, self.writer);
        try self.writer.writeAll("}\n");
        try self.writer.flush();
    }
    fn widgetRecord(context: ?*anyopaque, record: widget_protocol.Record) !void {
        const self: *Transport = @ptrCast(@alignCast(context.?));
        try self.writer.writeByte(0x1e);
        try widget_protocol.write(self.writer, record);
        try self.writer.writeByte('\n');
        try self.writer.flush();
    }

    fn editorControl(self: *Transport, request: std.json.Value) !void {
        if (request != .object) return error.InvalidEditorControl;
        const kind = try requiredText(request.object, "kind");
        if (std.mem.eql(u8, kind, "editor_subscribe")) {
            const protocol_version = request.object.get("version") orelse return error.InvalidEditorVersion;
            if (protocol_version != .integer or protocol_version.integer != editor_protocol.version) return error.InvalidEditorVersion;
            const generation = try component_protocol.identifier(request.object.get("ownerGeneration") orelse return error.InvalidEditorIdentity);
            if (generation != self.group.ui.editors.owner_generation) return;
            const enabled = request.object.get("enabled") orelse return error.InvalidEditorControl;
            if (enabled != .bool) return error.InvalidEditorControl;
            self.group.ui.editors.record_fn = if (enabled.bool) editorRecord else null;
            self.group.ui.editors.dirty = enabled.bool;
            _ = try self.group.ui.editors.pumpDirty();
        } else {
            var control = try editor_protocol.readControl(self.engine.gpa, &request.object);
            defer control.deinit();
            _ = try self.group.ui.editors.control(control);
        }
    }
    fn editorRecord(context: ?*anyopaque, record: editor_protocol.Record) !void {
        const self: *Transport = @ptrCast(@alignCast(context.?));
        try self.writer.writeByte(0x1e);
        try editor_protocol.write(self.writer, record);
        try self.writer.writeByte('\n');
        try self.writer.flush();
    }

    fn rendererRecord(context: ?*anyopaque, record: renderer_protocol.Record) !void {
        const self: *Transport = @ptrCast(@alignCast(context.?));
        try self.writer.writeByte(0x1e);
        try renderer_protocol.write(self.writer, &record);
        try self.writer.writeByte('\n');
        try self.writer.flush();
        var owned = record;
        owned.deinit();
    }

    fn rendererActions(context: ?*anyopaque, owner_id: u64, result: []const u8) !void {
        const self: *Transport = @ptrCast(@alignCast(context.?));
        var arena: std.heap.ArenaAllocator = .init(self.engine.gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, allocator, result, .{});
        const queue = parsed.object.get("actionQueue") orelse return;
        if (queue != .array or queue.array.items.len == 0) return;
        var object: std.json.ObjectMap = .empty;
        try object.put(allocator, "type", .{ .string = "renderer_actions" });
        try object.put(allocator, "version", .{ .integer = 1 });
        try object.put(allocator, "ownerGeneration", .{ .integer = @intCast(self.group.renderers.owner_generation) });
        try object.put(allocator, "extensionId", .{ .integer = @intCast(owner_id) });
        try object.put(allocator, "actionQueue", queue);
        try writeRecord(self.writer, .{ .object = object });
    }

    fn start(self: *Transport, request: std.json.ObjectMap, generated_id: []const u8) !void {
        const id = if (request.get("invocationId")) |value| if (value == .string and value.string.len > 0 and value.string.len <= 256) value.string else return error.InvalidNativeInvocationId else generated_id;
        if (self.seen_ids.contains(id)) return error.DuplicateNativeInvocationId;
        if (self.seen_ids.count() >= 65_536) return error.NativeInvocationLimit;
        const owned_id = try self.engine.gpa.dupe(u8, id);
        var inserted = false;
        errdefer if (!inserted) self.engine.gpa.free(owned_id);
        try self.seen_ids.put(self.engine.gpa, owned_id, {});
        inserted = true;
        self.active_id = owned_id;
        self.active_tool_call_id = if (request.get("toolCallId")) |value| if (value == .string) value.string else null else null;
        self.bindings.ui_manager.invocation_id = std.fmt.parseUnsigned(u64, owned_id, 10) catch 0;
        self.active_signal = try abort_signal.create(self.engine);
        self.active = true;
        self.stream_updates = if (request.get("streamUpdates")) |value| value == .bool and value.bool else false;
        if (request.get("aborted")) |value| if (value == .bool and value.bool) try self.abortActive(request.get("abortReason") orelse std.json.Value{ .string = "Operation aborted" });
        try self.bindings.setInvocationOptions(self.active_signal.?, sendToolUpdate, self);
    }

    fn sendToolUpdate(context: ?*anyopaque, value: c.JSValue) !void {
        const self: *Transport = @ptrCast(@alignCast(context.?));
        const source = try self.engine.stringify(value);
        defer self.engine.gpa.free(source);
        const projected = try normalizeToolResult(self.engine.gpa, source, "");
        if (self.active_tool_call_id) |id| self.group.renderers.renderLiveUpdate(id, value) catch |err| {
            self.engine.gpa.free(projected);
            return err;
        };
        if (self.stream_updates) {
            defer self.engine.gpa.free(projected);
            var arena: std.heap.ArenaAllocator = .init(self.engine.gpa);
            defer arena.deinit();
            const allocator = arena.allocator();
            const object = try std.json.parseFromSliceLeaky(std.json.Value, allocator, projected, .{});
            var record: std.json.ObjectMap = .empty;
            try record.put(allocator, "type", .{ .string = "tool_update" });
            try record.put(allocator, "invocationId", .{ .string = self.active_id });
            try record.put(allocator, "update", object);
            writeRecord(self.writer, .{ .object = record }) catch |err| {
                self.terminal = true;
                return err;
            };
        } else self.updates.append(self.engine.gpa, projected) catch |err| {
            self.engine.gpa.free(projected);
            return err;
        };
    }

    fn withUpdates(self: *Transport, result: []const u8) ![]u8 {
        if (self.updates.items.len == 0) return self.engine.gpa.dupe(u8, result);
        var arena: std.heap.ArenaAllocator = .init(self.engine.gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        var root = try std.json.parseFromSliceLeaky(std.json.Value, allocator, result, .{});
        if (root != .object) return error.InvalidNativeToolResult;
        var updates: std.json.Array = .init(allocator);
        for (self.updates.items) |source| try updates.append(try std.json.parseFromSliceLeaky(std.json.Value, allocator, source, .{}));
        try root.object.put(allocator, "updates", .{ .array = updates });
        return encoded(self.engine.gpa, root);
    }

    fn uiRecord(self: *Transport, kind: []const u8, id: ?u32, method: ?[]const u8, arguments: ?[]const u8) !void {
        var arena: std.heap.ArenaAllocator = .init(self.engine.gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        var object: std.json.ObjectMap = .empty;
        try object.put(allocator, "type", .{ .string = kind });
        try object.put(allocator, "invocationId", .{ .string = self.active_id });
        if (id) |value| try object.put(allocator, "id", .{ .integer = value });
        if (method) |value| try object.put(allocator, "method", .{ .string = value });
        if (arguments) |value| try object.put(allocator, "args", try std.json.parseFromSliceLeaky(std.json.Value, allocator, value, .{}));
        writeRecord(self.writer, .{ .object = object }) catch |err| {
            self.terminal = true;
            return err;
        };
    }

    fn uiRequest(context: ?*anyopaque, id: u32, method: []const u8, args: []const u8) !void {
        const self: *Transport = @ptrCast(@alignCast(context.?));
        try self.uiRecord("ui_request", id, method, args);
    }

    fn uiAction(context: ?*anyopaque, method: []const u8, args: []const u8) !void {
        const self: *Transport = @ptrCast(@alignCast(context.?));
        if (self.active) return self.uiRecord("ui_action", null, method, args);
        var out: std.Io.Writer.Allocating = .init(self.engine.gpa);
        defer out.deinit();
        try out.writer.print("{{\"type\":\"widget_action\",\"ownerGeneration\":\"{d}\",\"method\":", .{self.group.ui.widgets.owner_generation});
        try std.json.Stringify.value(method, .{}, &out.writer);
        try out.writer.print(",\"args\":{s}}}", .{args});
        try self.writer.writeByte(0x1e);
        try self.writer.writeAll(out.written());
        try self.writer.writeByte('\n');
        try self.writer.flush();
    }

    fn uiCancel(context: ?*anyopaque, id: u32) !void {
        const self: *Transport = @ptrCast(@alignCast(context.?));
        try self.uiRecord("ui_cancel", id, null, null);
    }

    fn streamEvent(context: ?*anyopaque, sequence: u64, event: []const u8) !void {
        const self: *Transport = @ptrCast(@alignCast(context.?));
        var arena: std.heap.ArenaAllocator = .init(self.engine.gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        var record: std.json.ObjectMap = .empty;
        try record.put(allocator, "type", .{ .string = "provider_stream_event" });
        try record.put(allocator, "invocationId", .{ .string = self.active_id });
        try record.put(allocator, "sequence", .{ .integer = @intCast(sequence) });
        try record.put(allocator, "event", try std.json.parseFromSliceLeaky(std.json.Value, allocator, event, .{}));
        try writeRecord(self.writer, .{ .object = record });
    }

    fn componentScene(context: ?*anyopaque, scene: component_protocol.Scene) !void {
        const self: *Transport = @ptrCast(@alignCast(context.?));
        try self.writer.writeByte(0x1e);
        try component_protocol.writeScene(self.writer, &scene);
        try self.writer.writeByte('\n');
        try self.writer.flush();
        var owned = scene;
        owned.deinit();
    }

    fn componentClose(context: ?*anyopaque, fence: component_protocol.Fence) !void {
        const self: *Transport = @ptrCast(@alignCast(context.?));
        try self.writer.writeAll("\x1e{\"type\":\"component_close\",");
        try component_protocol.writeFence(self.writer, fence);
        try self.writer.writeAll("}\n");
        try self.writer.flush();
    }
    fn componentMouseOutcome(context: ?*anyopaque, value: component_protocol.MouseOutcome) !void {
        const self: *Transport = @ptrCast(@alignCast(context.?));
        try self.writer.writeByte(0x1e);
        try component_protocol.writeMouseOutcome(self.writer, value);
        try self.writer.writeByte('\n');
        try self.writer.flush();
    }
};

const Loader = struct {
    io: std.Io,
    engine: *engine_mod.Engine,
    fn normalize(context: ?*anyopaque, gpa: std.mem.Allocator, base: []const u8, specifier: []const u8) anyerror![]u8 {
        return normalizeMode(context, gpa, base, specifier, false);
    }
    fn normalizeRequire(context: ?*anyopaque, gpa: std.mem.Allocator, base: []const u8, specifier: []const u8) anyerror![]u8 {
        return normalizeMode(context, gpa, base, specifier, true);
    }
    fn normalizeMode(context: ?*anyopaque, gpa: std.mem.Allocator, base: []const u8, specifier: []const u8, require_mode: bool) anyerror![]u8 {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        var resolver: module_resolver.Resolver = .{ .io = self.io, .native_modules = &self.engine.native_module_names, .require_mode = require_mode };
        return gpa.dupe(u8, try resolver.resolve(arena.allocator(), base, specifier));
    }
    fn source(context: ?*anyopaque, gpa: std.mem.Allocator, name: []const u8) anyerror![]u8 {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        const bytes = try std.Io.Dir.cwd().readFileAlloc(self.io, name, gpa, .limited(16 * 1024 * 1024));
        errdefer gpa.free(bytes);
        if (std.mem.endsWith(u8, name, ".ts") or std.mem.endsWith(u8, name, ".mts") or std.mem.endsWith(u8, name, ".cts")) {
            const transformed = try typescript.transform(gpa, bytes);
            gpa.free(bytes);
            return transformed;
        }
        return bytes;
    }

    fn input(context: ?*anyopaque, engine: *engine_mod.Engine, name: []const u8) anyerror!engine_mod.ModuleInput {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        const bytes = try source(context, engine.gpa, name);
        errdefer engine.gpa.free(bytes);
        var is_commonjs = std.mem.endsWith(u8, name, ".cjs") or std.mem.endsWith(u8, name, ".cts");
        const json = std.mem.endsWith(u8, name, ".json");
        if (!is_commonjs and !json and std.mem.endsWith(u8, name, ".js")) {
            var directory = std.fs.path.dirname(name) orelse ".";
            var package_type: ?[]u8 = null;
            defer if (package_type) |owned| engine.gpa.free(owned);
            while (true) {
                const path = try std.fs.path.join(engine.gpa, &.{ directory, "package.json" });
                defer engine.gpa.free(path);
                const package_bytes = std.Io.Dir.cwd().readFileAlloc(self.io, path, engine.gpa, .limited(1024 * 1024)) catch |err| switch (err) {
                    error.FileNotFound, error.NotDir => null,
                    else => return err,
                };
                if (package_bytes) |content| {
                    defer engine.gpa.free(content);
                    var parsed = try std.json.parseFromSlice(std.json.Value, engine.gpa, content, .{});
                    defer parsed.deinit();
                    if (parsed.value != .object) return error.InvalidExtensionPackage;
                    if (parsed.value.object.get("type")) |value| {
                        if (value != .string) return error.InvalidExtensionPackage;
                        package_type = try engine.gpa.dupe(u8, value.string);
                    }
                    break;
                }
                if (std.mem.eql(u8, std.fs.path.basename(directory), "node_modules")) break;
                const parent = std.fs.path.dirname(directory) orelse break;
                if (std.mem.eql(u8, parent, directory)) break;
                directory = parent;
            }
            is_commonjs = if (package_type) |kind| std.mem.eql(u8, kind, "commonjs") else !try typescript.hasModuleSyntax(bytes);
        }
        if (is_commonjs or json) {
            const value = try commonjs.load(engine, bytes, name, json);
            engine.gpa.free(bytes);
            return .{ .exports = value };
        }
        return .{ .source = bytes };
    }
};

fn writeRecord(writer: *std.Io.Writer, value: std.json.Value) !void {
    try writer.writeByte(0x1e);
    try std.json.Stringify.value(value, .{}, writer);
    try writer.writeByte('\n');
    try writer.flush();
}

fn writeFailure(gpa: std.mem.Allocator, writer: *std.Io.Writer, message: []const u8) !void {
    var failure: std.json.ObjectMap = .empty;
    defer failure.deinit(gpa);
    try failure.put(gpa, "ok", .{ .bool = false });
    try failure.put(gpa, "error", .{ .string = message });
    try writeRecord(writer, .{ .object = failure });
}

fn writeInvocationFailure(gpa: std.mem.Allocator, writer: *std.Io.Writer, message: []const u8, actions_json: []const u8) !void {
    var failure = try std.json.parseFromSlice(std.json.Value, gpa, actions_json, .{});
    defer failure.deinit();
    if (failure.value != .object) return error.InvalidNativeExtensionActionQueue;
    try failure.value.object.put(gpa, "ok", .{ .bool = false });
    try failure.value.object.put(gpa, "error", .{ .string = message });
    try writeRecord(writer, failure.value);
}

fn requiredText(object: std.json.ObjectMap, name: []const u8) ![]const u8 {
    const value = object.get(name) orelse return error.MissingWorkerField;
    if (value != .string) return error.InvalidWorkerField;
    return value.string;
}

fn encoded(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    try std.json.Stringify.value(value, .{}, &output.writer);
    return output.toOwnedSlice();
}

pub fn normalizeToolResult(gpa: std.mem.Allocator, raw: []const u8, tool_name: []const u8) ![]u8 {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const result = try std.json.parseFromSliceLeaky(std.json.Value, allocator, raw, .{});
    const object = if (result == .object) result.object else std.json.ObjectMap.empty;
    if (object.get("__piDelegateBuiltin")) |delegate| {
        if (delegate == .string and std.mem.eql(u8, delegate.string, tool_name)) return gpa.dupe(u8, "{\"content\":\"\",\"isError\":false,\"delegateBuiltin\":true}");
    }
    var text: std.ArrayList(u8) = .empty;
    var images: std.json.Array = .init(allocator);
    const content = object.get("content") orelse std.json.Value.null;
    if (content == .string) {
        try text.appendSlice(allocator, content.string);
    } else if (content == .array) {
        var text_items: usize = 0;
        for (content.array.items) |item| {
            if (item == .string) {
                if (text_items > 0) try text.append(allocator, '\n');
                try text.appendSlice(allocator, item.string);
                text_items += 1;
            } else if (item == .object) {
                const kind = item.object.get("type") orelse continue;
                if (kind != .string) continue;
                if (std.mem.eql(u8, kind.string, "text")) {
                    const line = item.object.get("text") orelse std.json.Value{ .string = "" };
                    if (line != .string) return error.InvalidNativeToolText;
                    if (text_items > 0) try text.append(allocator, '\n');
                    try text.appendSlice(allocator, line.string);
                    text_items += 1;
                } else if (std.mem.eql(u8, kind.string, "image")) {
                    const data = item.object.get("data") orelse item.object.get("base64") orelse continue;
                    if (data != .string or data.string.len == 0) continue;
                    const mime = item.object.get("mimeType") orelse item.object.get("mime_type") orelse std.json.Value{ .string = "image/png" };
                    var image: std.json.ObjectMap = .empty;
                    try image.put(allocator, "dataBase64", data);
                    try image.put(allocator, "mimeType", mime);
                    try images.append(.{ .object = image });
                }
            }
        }
    } else if (content != .null) {
        const json = try encoded(allocator, content);
        try text.appendSlice(allocator, json);
    }
    var projected: std.json.ObjectMap = .empty;
    try projected.put(allocator, "content", .{ .string = text.items });
    const is_error = object.get("isError") orelse std.json.Value{ .bool = false };
    try projected.put(allocator, "isError", .{ .bool = is_error == .bool and is_error.bool });
    try projected.put(allocator, "details", object.get("details") orelse std.json.Value.null);
    const terminate = object.get("terminate") orelse std.json.Value{ .bool = false };
    try projected.put(allocator, "terminate", .{ .bool = terminate == .bool and terminate.bool });
    if (object.get("usage")) |usage| if (usage == .object) try projected.put(allocator, "usage", usage);
    if (object.get("addedToolNames")) |names| if (names == .array) {
        var valid: std.json.Array = .init(allocator);
        for (names.array.items) |name| if (name == .string and name.string.len > 0) try valid.append(name);
        try projected.put(allocator, "addedToolNames", .{ .array = valid });
    };
    if (object.get("actionQueue")) |actions| if (actions == .array) try projected.put(allocator, "actionQueue", actions);
    if (images.items.len > 0) {
        try projected.put(allocator, "imageBase64", images.items[0].object.get("dataBase64").?);
        try projected.put(allocator, "imageMime", images.items[0].object.get("mimeType").?);
        try projected.put(allocator, "images", .{ .array = images });
    }
    return encoded(gpa, .{ .object = projected });
}

fn invoke(gpa: std.mem.Allocator, bindings: *bindings_mod.Bindings, transport: *Transport, object: std.json.ObjectMap) ![]u8 {
    const kind = try requiredText(object, "kind");
    const snapshot = try encoded(gpa, object.get("context") orelse std.json.Value{ .object = .empty });
    defer gpa.free(snapshot);
    try bindings.setContext(snapshot);
    if (object.get("flags")) |flags| {
        const source = try encoded(gpa, flags);
        defer gpa.free(source);
        try bindings.setFlags(source);
    }
    if (std.mem.eql(u8, kind, "hook") or std.mem.eql(u8, kind, "tool")) {
        const source = try encoded(gpa, object.get("payload") orelse std.json.Value{ .object = .empty });
        defer gpa.free(source);
        const name = try requiredText(object, "name");
        if (std.mem.eql(u8, kind, "hook")) return bindings.invokeHook(name, source);
        const call_id = if (object.get("toolCallId")) |id| if (id == .string) id.string else "native-tool-call" else "native-tool-call";
        const result = try bindings.invokeTool(name, call_id, source);
        defer gpa.free(result);
        return normalizeToolResult(gpa, result, name);
    }
    if (std.mem.eql(u8, kind, "command")) {
        const arguments = if (object.get("rawArguments")) |value| if (value == .string) value.string else "" else "";
        return bindings.invokeCommand(try requiredText(object, "name"), arguments);
    }
    if (std.mem.eql(u8, kind, "provider_method")) {
        const append_signal = if (object.get("appendSignal")) |signal| signal == .bool and signal.bool else false;
        const aborted = if (object.get("aborted")) |value| value == .bool and value.bool else false;
        const arguments = try encoded(gpa, object.get("args") orelse std.json.Value{ .array = std.json.Array.init(gpa) });
        defer gpa.free(arguments);
        return bindings.invokeProviderMethodWithSignal(try requiredText(object, "callbackId"), arguments, append_signal, aborted);
    }
    if (std.mem.eql(u8, kind, "provider_callback_commit")) {
        const selected = try encoded(gpa, object.get("callbackIds") orelse std.json.Value{ .array = std.json.Array.init(gpa) });
        defer gpa.free(selected);
        return bindings.commitProviderCallbacks(try requiredText(object, "providerName"), selected);
    }
    if (std.mem.eql(u8, kind, "provider_oauth_login")) {
        const generation = object.get("callbackGeneration");
        if (generation) |value| if (value != .integer or value.integer <= 0) return error.InvalidWorkerField;
        const provider = if (object.contains("providerName")) try requiredText(object, "providerName") else null;
        return bindings.invokeProviderOAuth(try requiredText(object, "callbackId"), provider, if (generation) |value| @intCast(value.integer) else 0);
    }
    if (std.mem.eql(u8, kind, "provider_refresh_models")) {
        const generation = object.get("callbackGeneration");
        if (generation) |value| if (value != .integer or value.integer <= 0) return error.InvalidWorkerField;
        const context = try encoded(gpa, object.get("refreshContext") orelse return error.MissingWorkerField);
        defer gpa.free(context);
        return bindings.invokeProviderRefresh(try requiredText(object, "callbackId"), try requiredText(object, "providerName"), if (generation) |value| @intCast(value.integer) else 0, context);
    }
    if (std.mem.eql(u8, kind, "provider_stream_simple") or std.mem.eql(u8, kind, "provider_fetch_deferred") or std.mem.eql(u8, kind, "provider_cancel_deferred")) {
        const generation = object.get("callbackGeneration") orelse return error.MissingWorkerField;
        if (generation != .integer or generation.integer <= 0) return error.InvalidWorkerField;
        const model = try encoded(gpa, object.get("model") orelse std.json.Value{ .object = .empty });
        defer gpa.free(model);
        const context = try encoded(gpa, object.get(if (std.mem.eql(u8, kind, "provider_stream_simple")) "streamContext" else "handle") orelse std.json.Value{ .object = .empty });
        defer gpa.free(context);
        const options = try encoded(gpa, object.get("options") orelse std.json.Value{ .object = .empty });
        defer gpa.free(options);
        const bridge: native_stream.Bridge = .{ .context = transport, .event = Transport.streamEvent };
        return bindings.invokeProviderStream(try requiredText(object, "callbackId"), try requiredText(object, "providerName"), @intCast(generation.integer), model, context, options, transport.active_id, bridge, std.mem.eql(u8, kind, "provider_cancel_deferred"));
    }
    if (std.meta.stringToEnum(native_renderers.Kind, kind)) |renderer_kind| {
        const payload = try encoded(gpa, object.get("payload") orelse std.json.Value{ .object = .empty });
        defer gpa.free(payload);
        return bindings.invokeRenderer(renderer_kind, try requiredText(object, "name"), payload);
    }
    return error.UnsupportedNativeWorkerRequest;
}

test "renderer control arrives between idle pump and FIFO dequeue and retains control identity for both slot resize and subscription" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = io;
    try timers.install(engine, io);
    const group = try native_group.Group.init(engine);
    defer group.deinit();
    const binding = try group.add("late-renderer-control.mjs");
    try binding.installSchemas();
    try binding.loadFactory("export default pi=>pi.registerTool({name:'late',execute(){return {}},renderCall(){return {render(width){return ['LATE_CALL:'+width]}}},renderResult(){return {render(width){return ['LATE_RESULT:'+width]}}}})", "late-renderer-control.mjs");
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    var transport: Transport = .{ .engine = engine, .bindings = binding, .io = io, .writer = &output.writer, .group = group };
    defer transport.deinit();
    group.renderers.record_fn = Transport.rendererRecord;
    group.renderers.record_context = &transport;
    group.renderers.subscribe(true);
    const call = try binding.invokeRenderer(.render_tool_call, "late", "{\"toolCallId\":\"race-row\",\"args\":{},\"width\":80}");
    defer gpa.free(call);
    const result = try binding.invokeRenderer(.render_tool_result, "late", "{\"toolCallId\":\"race-row\",\"result\":{},\"width\":80}");
    defer gpa.free(result);
    const Probe = struct {
        var injected = false;
        var control_bytes: []const u8 = "";
        fn pump(current_engine: *engine_mod.Engine) !bool {
            const dispatched = try Transport.pump(current_engine);
            if (!injected) {
                injected = true;
                const current: *Transport = @ptrCast(@alignCast(current_engine.host_control_context.?));
                try current.enqueue(try std.heap.page_allocator.dupe(u8, control_bytes));
            }
            return dispatched;
        }
    };
    engine.host_control_context = &transport;
    engine.host_control_pump = Probe.pump;
    defer {
        engine.host_control_context = null;
        engine.host_control_pump = null;
    }
    for ([_][]const u8{
        "{\"kind\":\"renderer_control\",\"version\":1,\"ownerGeneration\":\"1\",\"extensionId\":\"1\",\"rowGeneration\":\"1\",\"toolCallId\":\"race-row\",\"control\":\"resize\",\"width\":55}",
        "{\"kind\":\"renderer_subscribe\",\"version\":1,\"ownerGeneration\":\"1\",\"enabled\":false}",
    }, 0..) |late_bytes, index| {
        Probe.injected = false;
        Probe.control_bytes = late_bytes;
        const received = (try transport.next()).?;
        defer std.heap.page_allocator.free(received.bytes);
        try std.testing.expectEqual(WireRecord.Kind.renderer_control, received.kind);
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, received.bytes, .{});
        defer parsed.deinit();
        try std.testing.expect(try transport.persistentControl(received.kind, parsed.value));
        if (index == 0) {
            _ = try group.renderers.pumpDirty();
            try std.testing.expect(std.mem.indexOf(u8, output.written(), "LATE_CALL:55") != null);
            try std.testing.expect(std.mem.indexOf(u8, output.written(), "LATE_RESULT:55") != null);
        } else try std.testing.expect(!group.renderers.subscribed);
    }
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\"ok\"") == null);
}

test "native tool result projection preserves text images details and usage" {
    const gpa = std.testing.allocator;
    const result = try normalizeToolResult(gpa, "{\"content\":[\"first\",{\"type\":\"text\",\"text\":\"second\"},{\"type\":\"image\",\"data\":\"YWJj\",\"mimeType\":\"image/jpeg\"}],\"details\":{\"marker\":42},\"usage\":{\"input\":1},\"addedToolNames\":[\"loaded\",\"\",3]}", "fixture");
    defer gpa.free(result);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, result, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("first\nsecond", parsed.value.object.get("content").?.string);
    try std.testing.expectEqualStrings("image/jpeg", parsed.value.object.get("imageMime").?.string);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.object.get("images").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.object.get("addedToolNames").?.array.items.len);
    try std.testing.expect(parsed.value.object.contains("details") and parsed.value.object.contains("usage"));
}

test "native durable VM background notifier survives the wire reset and drains on owner before idle wait" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = io;
    try timers.install(engine, io);
    const group = try native_group.Group.init(engine);
    defer group.deinit();
    const binding = try group.add("durable-owner-notifier-fixture.mjs");
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    var transport: Transport = .{ .engine = engine, .bindings = binding, .io = io, .writer = &output.writer, .group = group };
    defer transport.deinit();
    const Probe = struct {
        transport: *Transport,
        owner: std.Thread.Id,
        release_worker: std.Io.Event = .unset,
        notified: std.Io.Event = .unset,
        queued: std.atomic.Value(bool) = .init(false),
        first_pump: bool = true,
        reset_seen: bool = false,
        worker_thread: std.Thread.Id = 0,
        notify: *const fn (?*anyopaque) void,
        notify_context: ?*anyopaque,
        fn worker(self: *@This()) void {
            self.release_worker.waitUncancelable(self.transport.io);
            self.worker_thread = std.Thread.getCurrentId();
            self.queued.store(true, .release);
            self.notify(self.notify_context);
            self.notified.set(self.transport.io);
        }
        fn pump(current: *engine_mod.Engine) !bool {
            const self: *@This() = @ptrCast(@alignCast(current.native_durable_control_context.?));
            try std.testing.expectEqual(self.owner, std.Thread.getCurrentId());
            if (self.first_pump) {
                self.first_pump = false;
                self.release_worker.set(self.transport.io);
                self.notified.waitUncancelable(self.transport.io);
                try std.testing.expect(self.transport.available.isSet());
                return false; // Notification arrives after the first drain check.
            }
            if (!self.queued.swap(false, .acq_rel)) return false;
            self.reset_seen = !self.transport.available.isSet();
            const bytes = try std.heap.page_allocator.dupe(u8, "{\"kind\":\"durable-delivered\"}");
            errdefer std.heap.page_allocator.free(bytes);
            try self.transport.enqueue(bytes);
            return true;
        }
    };
    engine.host_owner_notify_context = &transport;
    engine.host_owner_notify = Transport.notifyOwner;
    var probe: Probe = .{ .transport = &transport, .owner = std.Thread.getCurrentId(), .notify = engine.host_owner_notify.?, .notify_context = engine.host_owner_notify_context };
    engine.native_durable_control_context = &probe;
    engine.native_durable_control_pump = Probe.pump;
    defer {
        engine.native_durable_control_context = null;
        engine.native_durable_control_pump = null;
        engine.host_owner_notify = null;
        engine.host_owner_notify_context = null;
    }
    const thread = try std.Thread.spawn(.{}, Probe.worker, .{&probe});
    const record = (try transport.next()).?;
    defer std.heap.page_allocator.free(record.bytes);
    thread.join();
    try std.testing.expect(probe.worker_thread != probe.owner);
    try std.testing.expect(probe.reset_seen);
    try std.testing.expectEqualStrings("{\"kind\":\"durable-delivered\"}", record.bytes);
}

fn loadSource(gpa: std.mem.Allocator, io: std.Io, engine: *engine_mod.Engine, loader: *Loader, binding: *bindings_mod.Bindings, extension_path: []const u8) !void {
    const absolute = try std.Io.Dir.cwd().realPathFileAlloc(io, extension_path, gpa);
    defer gpa.free(absolute);
    const filename = try gpa.dupeZ(u8, absolute);
    defer gpa.free(filename);
    for (filename) |*byte| if (byte.* == '\\') {
        byte.* = '/';
    };
    try binding.setSourcePath(filename);
    const input_module = try Loader.input(loader, engine, filename);
    defer switch (input_module) {
        .source => |source| gpa.free(source),
        .exports => |exports| engine.freeValue(exports),
    };
    const loaded_factory = switch (input_module) {
        .source => |source| binding.loadFactory(source, filename),
        .exports => |exports| binding.loadFactoryValue(exports),
    };
    try loaded_factory;
}

pub fn run(gpa: std.mem.Allocator, io: std.Io, extension_path: []const u8) !void {
    return runOwner(gpa, io, &.{extension_path}, null, false, 1);
}

/// Native programmatic embedding entrypoint. It evaluates a user SDK module
/// directly, without requiring an extension factory or a Node executable.
pub fn runSdkFile(gpa: std.mem.Allocator, io: std.Io, script_path: []const u8) !void {
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    return runSdkFileWithEnvironment(gpa, io, script_path, &environment, &.{script_path});
}
pub fn runSdkFileWithEnvironment(gpa: std.mem.Allocator, io: std.Io, script_path: []const u8, environment: *const std.process.Environ.Map, arguments: []const []const u8) !void {
    const engine = try engine_mod.Engine.init(gpa, .{ .main_module = true });
    defer engine.deinit();
    var loader: Loader = .{ .io = io, .engine = engine };
    engine.setSourceLoader(.{ .context = &loader, .load = Loader.source, .normalize = Loader.normalize, .normalize_require = Loader.normalizeRequire, .input = Loader.input });
    const group = try native_group.Group.init(engine);
    defer group.deinit();
    const binding = try group.add(script_path);
    engine.native_sdk_extension_group = group;
    defer engine.native_sdk_extension_group = null;
    try timers.install(engine, io);
    try binding.installSchemas();
    try node_path.install(engine, io);
    try node_url.install(engine);
    try node_fs.install(engine, io);
    try commonjs.install(engine);
    try console.install(engine, io);
    try text_encoding.install(engine);
    try text_decoder.install(engine);
    try @import("native_process.zig").install(engine, io, environment, arguments);
    engine.native_console_stdout = true;
    const filename = try std.Io.Dir.cwd().realPathFileAlloc(io, script_path, gpa);
    defer gpa.free(filename);
    for (filename) |*byte| if (byte.* == '\\') {
        byte.* = '/';
    };
    const terminated = try gpa.dupeZ(u8, filename);
    defer gpa.free(terminated);
    const input = try Loader.input(&loader, engine, filename);
    defer switch (input) {
        .source => |body| gpa.free(body),
        .exports => |exports| engine.freeValue(exports),
    };
    const evaluated = switch (input) {
        .source => |body| engine.evalModule(body, terminated) catch |err| {
            if (engine.last_error) |message| try std.Io.File.stderr().writeStreamingAll(io, message);
            return err;
        },
        .exports => return error.NativeSDKEntrypointMustBeModule,
    };
    defer engine.freeValue(evaluated);
    const settled = engine.awaitValue(evaluated) catch |err| {
        if (engine.last_error) |message| {
            var buffer: [4096]u8 = undefined;
            var output = std.Io.File.stderr().writerStreaming(io, &buffer);
            try output.interface.print("{s}\n", .{message});
            try output.interface.flush();
        }
        return err;
    };
    defer engine.freeValue(settled);
    _ = try engine.drainReadyJobs();
}

pub fn runGroup(gpa: std.mem.Allocator, io: std.Io) !void {
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(io, &input_buffer);
    var startup: std.ArrayList(u8) = .empty;
    defer startup.deinit(gpa);
    while (true) {
        const byte = try input.interface.takeByte();
        if (byte == '\n') break;
        if (startup.items.len >= 4 * 1024 * 1024) return error.NativeGroupStartupTooLarge;
        try startup.append(gpa, byte);
    }
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, startup.items, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidNativeGroupStartup;
    const kind = parsed.value.object.get("kind") orelse return error.InvalidNativeGroupStartup;
    if (kind != .string or !std.mem.eql(u8, kind.string, "load_group")) return error.InvalidNativeGroupStartup;
    const sources = parsed.value.object.get("sources") orelse return error.InvalidNativeGroupStartup;
    if (sources != .array or sources.array.items.len == 0 or sources.array.items.len > 4096) return error.InvalidNativeGroupStartup;
    const paths = try gpa.alloc([]const u8, sources.array.items.len);
    defer gpa.free(paths);
    for (sources.array.items, paths) |source, *path| {
        if (source != .string or source.string.len == 0 or source.string.len > std.Io.Dir.max_path_bytes) return error.InvalidNativeGroupStartup;
        path.* = source.string;
    }
    const owner_generation = if (parsed.value.object.get("ownerGeneration")) |value| try component_protocol.identifier(value) else 1;
    if (owner_generation > 9_007_199_254_740_991) return error.InvalidRendererIdentity;
    return runOwner(gpa, io, paths, &input, true, owner_generation);
}

fn runOwner(gpa: std.mem.Allocator, io: std.Io, sources: []const []const u8, initial_input: ?*std.Io.File.Reader, grouped: bool, owner_generation: u64) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    var loader: Loader = .{ .io = io, .engine = engine };
    engine.setSourceLoader(.{ .context = &loader, .load = Loader.source, .normalize = Loader.normalize, .normalize_require = Loader.normalizeRequire, .input = Loader.input });
    const group = try native_group.Group.init(engine);
    defer group.deinit();
    group.renderers.owner_generation = owner_generation;
    group.ui.editors.owner_generation = owner_generation;
    group.ui.widgets.owner_generation = owner_generation;
    group.activation.owner_generation = owner_generation;
    const bindings = try group.add(sources[0]);
    try timers.install(engine, io);
    try bindings.installSchemas();
    try node_path.install(engine, io);
    try node_url.install(engine);
    try node_fs.install(engine, io);
    try commonjs.install(engine);
    try console.install(engine, io);
    try text_encoding.install(engine);
    try text_decoder.install(engine);
    for (sources, 0..) |extension_path, index| {
        const source_binding = if (index == 0) bindings else try group.add(extension_path);
        const loaded_factory = loadSource(gpa, io, engine, &loader, source_binding, extension_path);
        loaded_factory catch |err| {
            if (engine.last_error) |message| {
                var error_buffer: [4096]u8 = undefined;
                var stderr = std.Io.File.stderr().writerStreaming(io, &error_buffer);
                try stderr.interface.print("Native extension load failed: {s}\n", .{message});
                try stderr.interface.flush();
            }
            return err;
        };
    }
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(io, &output_buffer);
    const writer = &output.interface;
    try group.initializeActivation();
    const manifest = if (grouped) try group.manifest() else try bindings.manifestJson(sources[0]);
    defer gpa.free(manifest);
    try writer.writeAll(if (grouped) "\x1e{\"type\":\"ready\",\"group\":true,\"extensions\":" else "\x1e{\"type\":\"ready\",\"manifest\":");
    try writer.writeAll(manifest);
    try writer.writeAll("}\n");
    try writer.flush();
    var transport: Transport = .{ .engine = engine, .bindings = bindings, .io = io, .writer = writer, .group = group, .initial_input = initial_input };
    defer transport.deinit();
    group.renderers.record_fn = Transport.rendererRecord;
    group.renderers.record_context = &transport;
    group.ui.editors.record_context = &transport;
    group.ui.widgets.record_context = &transport;
    group.ui.widgets.record_fn = Transport.widgetRecord;
    group.actions_fn = Transport.rendererActions;
    group.actions_context = &transport;
    defer {
        group.renderers.record_fn = null;
        group.ui.editors.record_fn = null;
        group.ui.widgets.record_fn = null;
        group.actions_fn = null;
    }
    engine.host_control_context = &transport;
    engine.host_control_pump = Transport.pump;
    engine.host_owner_notify_context = &transport;
    engine.host_owner_notify = Transport.notifyOwner;
    bindings.ui_manager.bridge = .{ .context = &transport, .request = Transport.uiRequest, .action = Transport.uiAction, .cancel = Transport.uiCancel, .component_scene = Transport.componentScene, .component_close = Transport.componentClose, .component_mouse_outcome = Transport.componentMouseOutcome };
    defer bindings.ui_manager.bridge = null;
    defer {
        // Retire and join durable workers while their notifier and transport
        // are still alive, before dropping owner control callbacks.
        engine.closeDurableOwner();
        engine.host_owner_notify = null;
        engine.host_owner_notify_context = null;
        engine.host_control_context = null;
        engine.host_control_pump = null;
    }
    var reader_group: std.Io.Group = .init;
    // The persistent stdin reader must not execute eagerly on the JS owner.
    try reader_group.concurrent(io, Transport.readerTask, .{&transport});
    defer {
        reader_group.cancel(io);
        reader_group.await(io) catch {};
    }
    while (true) {
        const record = (try transport.next()) orelse return;
        defer std.heap.page_allocator.free(record.bytes);
        // A late control is consumed without producing a final response that
        // could be mistaken for the next ordinary invocation's result.
        if (record.kind == .abort or record.kind == .ui_response or record.kind == .component_control or record.kind == .provider_stream_ack) continue;
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        const request = std.json.parseFromSliceLeaky(std.json.Value, allocator, record.bytes, .{}) catch |err| {
            try writeFailure(allocator, writer, @errorName(err));
            continue;
        };
        if (request != .object) {
            try writeFailure(allocator, writer, "InvalidWorkerRequest");
            continue;
        }
        // A persistent control can arrive after pumpIdle's control scan but
        // before next() dequeues its FIFO. It remains an owner-thread control,
        // never an ordinary invocation or an ordinary response-envelope entry.
        if (try transport.persistentControl(record.kind, request)) continue;
        const kind = requiredText(request.object, "kind") catch |err| {
            try writeFailure(allocator, writer, @errorName(err));
            continue;
        };
        if (std.mem.eql(u8, kind, "shutdown")) {
            try writer.writeAll("\x1e{\"ok\":true,\"result\":{}}\n");
            try writer.flush();
            return;
        }
        const extension_id: u64 = if (request.object.get("extensionId")) |value| component_protocol.identifier(value) catch {
            try writeFailure(allocator, writer, "InvalidNativeExtensionOwner");
            continue;
        } else 1;
        const selected_binding = group.selected(extension_id) catch |err| {
            try writeFailure(allocator, writer, @errorName(err));
            continue;
        };
        transport.bindings = selected_binding;
        engine.beginInvocation();
        var generated: [32]u8 = undefined;
        const generated_id = try std.fmt.bufPrint(&generated, "native-{d}", .{transport.next_id});
        transport.next_id = std.math.add(u64, transport.next_id, 1) catch return error.NativeInvocationLimit;
        transport.start(request.object, generated_id) catch |err| {
            transport.clearActive();
            try writeFailure(allocator, writer, @errorName(err));
            continue;
        };
        defer transport.clearActive();
        if (grouped and std.mem.eql(u8, kind, "sdk_availability_snapshot")) {
            const runtime_id: u64 = if (request.object.get("runtimeId")) |value| component_protocol.identifier(value) catch {
                try writeFailure(allocator, writer, "InvalidNativeSDKRuntime");
                continue;
            } else 0;
            const snapshot_json = group.sdk_availability.encode(allocator, runtime_id) catch |err| {
                try writeFailure(allocator, writer, @errorName(err));
                continue;
            };
            try writer.writeAll("\x1e{\"ok\":true,\"result\":{\"snapshot\":");
            try writer.writeAll(snapshot_json);
            try writer.writeAll("}}\n");
            try writer.flush();
            continue;
        }
        if (grouped and std.mem.eql(u8, kind, "group_remove_source")) {
            const value = request.object.get("ownerId") orelse {
                try writeFailure(allocator, writer, "MissingNativeExtensionOwner");
                continue;
            };
            const owner_id = component_protocol.identifier(value) catch {
                try writeFailure(allocator, writer, "InvalidNativeExtensionOwner");
                continue;
            };
            if (owner_id == 1) {
                try writeFailure(allocator, writer, "NativeGroupPrimaryOwnerRequired");
                continue;
            }
            // The request may target the same binding it removes. Release
            // its invocation signal and retarget transport before destruction;
            // the loop's deferred cleanup must never retain a freed binding.
            transport.clearActive();
            transport.bindings = try group.selected(1);
            group.remove(owner_id) catch |err| {
                try writeFailure(allocator, writer, @errorName(err));
                return err;
            };
            try transport.publishMetadataSafe();
            try writer.writeAll("\x1e{\"ok\":true,\"result\":{}}\n");
            try writer.flush();
            continue;
        }
        if (grouped and std.mem.eql(u8, kind, "group_add_source")) {
            const path = requiredText(request.object, "sourcePath") catch |err| {
                try writeFailure(allocator, writer, @errorName(err));
                continue;
            };
            const added = group.add(path) catch |err| {
                try writeFailure(allocator, writer, @errorName(err));
                continue;
            };
            const added_id = added.owner_id;
            loadSource(gpa, io, engine, &loader, added, path) catch |err| {
                group.remove(added_id) catch |cleanup_error| {
                    try writeFailure(allocator, writer, @errorName(cleanup_error));
                    return cleanup_error;
                };
                try writeFailure(allocator, writer, engine.last_error orelse @errorName(err));
                continue;
            };
            try group.refreshOwnerActivation(added_id, group.selection_received);
            const raw_manifest = try added.manifestJson(path);
            defer gpa.free(raw_manifest);
            var manifest_value = try std.json.parseFromSliceLeaky(std.json.Value, allocator, raw_manifest, .{});
            try manifest_value.object.put(allocator, "extensionId", .{ .integer = @intCast(added_id) });
            try transport.publishMetadataSafe();
            try writeRecord(writer, .{ .object = record: {
                var response: std.json.ObjectMap = .empty;
                try response.put(allocator, "ok", .{ .bool = true });
                try response.put(allocator, "result", manifest_value);
                break :record response;
            } });
            continue;
        }
        const previous_invocation_generation = selected_binding.invocation_generation;
        const result = invoke(gpa, selected_binding, &transport, request.object) catch |err| {
            // Own the primary diagnostic before serializing the admitted queue;
            // a secondary allocation/serialization failure cannot replace it.
            const diagnostic = try gpa.dupe(u8, engine.last_error orelse @errorName(err));
            defer gpa.free(diagnostic);
            const admitted = if (selected_binding.invocation_generation != previous_invocation_generation)
                try selected_binding.rejectedActions()
            else
                try gpa.dupe(u8, "{}");
            defer gpa.free(admitted);
            try transport.publishMetadataSafe();
            // C frames are absent from the user's JavaScript stack. Preserve
            // the original exception while naming the native invocation in
            // its wire diagnostic, as the upstream refreshModels stack does.
            if (std.mem.eql(u8, kind, "provider_refresh_models")) {
                const contextual = try std.fmt.allocPrint(gpa, "provider refreshModels: {s}", .{diagnostic});
                defer gpa.free(contextual);
                try writeInvocationFailure(allocator, writer, contextual, admitted);
            } else try writeInvocationFailure(allocator, writer, diagnostic, admitted);
            if (transport.terminal) {
                if (transport.shutdown_requested) {
                    try writer.writeAll("\x1e{\"ok\":true,\"result\":{}}\n");
                    try writer.flush();
                }
                return;
            }
            const interrupted = if (engine.captured_exception) |exception| c.JS_IsUncatchableError(exception) else false;
            if (interrupted or err == error.OutOfMemory or err == error.NativeHostPromiseTimeout or err == error.JavaScriptJobLimit or err == error.JavaScriptInterrupted) return;
            continue;
        };
        defer gpa.free(result);
        const projected = try transport.withUpdates(result);
        defer gpa.free(projected);
        try transport.publishMetadataSafe();
        try writer.writeAll("\x1e{\"ok\":true,\"result\":");
        try writer.writeAll(projected);
        try writer.writeAll("}\n");
        try writer.flush();
        if (transport.terminal) {
            if (transport.shutdown_requested) {
                try writer.writeAll("\x1e{\"ok\":true,\"result\":{}}\n");
                try writer.flush();
            }
            return;
        }
    }
}
