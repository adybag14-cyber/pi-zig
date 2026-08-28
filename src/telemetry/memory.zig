//! Deterministic in-memory reference telemetry adapter.
const std = @import("std");
const types = @import("types.zig");

pub const Attribute = types.Attribute;
pub const SpanOptions = types.SpanOptions;
pub const SpanStatus = types.SpanStatus;
pub const RecordedSpan = types.RecordedSpan;

const MutableEvent = struct {
    name: []u8,
    attributes: std.ArrayList(types.OwnedAttribute) = .empty,

    fn deinit(self: *MutableEvent, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        for (self.attributes.items) |*attribute| attribute.deinit(gpa);
        self.attributes.deinit(gpa);
        self.* = undefined;
    }
};

const MutableSpan = struct {
    id: u64,
    parent_id: ?u64,
    name: []u8,
    attributes: std.ArrayList(types.OwnedAttribute) = .empty,
    events: std.ArrayList(MutableEvent) = .empty,
    status: types.OwnedStatus = .ok,
    explicit_status: bool = false,
    settled: bool = false,
    end_sequence: ?u64 = null,

    fn deinit(self: *MutableSpan, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        for (self.attributes.items) |*attribute| attribute.deinit(gpa);
        self.attributes.deinit(gpa);
        for (self.events.items) |*event| event.deinit(gpa);
        self.events.deinit(gpa);
        self.status.deinit(gpa);
        self.* = undefined;
    }
};

pub const Span = struct {
    context: ?*InMemoryTelemetryContext = null,
    id: u64 = 0,

    pub fn isRecording(self: Span) bool {
        return self.context != null;
    }

    pub fn startSpan(self: Span, options: SpanOptions) Span {
        const context = self.context orelse return .{};
        return context.beginSpan(options, self.id);
    }

    pub fn addEvent(self: Span, name: []const u8, attributes: []const Attribute) void {
        const context = self.context orelse return;
        context.addEvent(self.id, name, attributes);
    }

    pub fn setAttributes(self: Span, attributes: []const Attribute) void {
        const context = self.context orelse return;
        context.setAttributes(self.id, attributes);
    }

    pub fn setStatus(self: Span, status: SpanStatus) void {
        const context = self.context orelse return;
        context.setStatus(self.id, status);
    }

    pub fn finish(self: Span) void {
        const context = self.context orelse return;
        context.settle(self.id, false, null, null);
    }

    pub fn finishError(self: Span, name: []const u8, message: []const u8) void {
        const context = self.context orelse return;
        context.settle(self.id, true, name, message);
    }

    /// Run a synchronous callback and settle the child automatically. Error
    /// unions preserve the exact returned error while recording a passive
    /// automatic error status, matching the source package's callback contract.
    pub fn run(self: Span, options: SpanOptions, callback: anytype) CallbackReturn(@TypeOf(callback)) {
        const child = self.startSpan(options);
        return runCallback(child, callback);
    }
};

pub const NoopTelemetryContext = struct {
    pub fn startSpan(_: NoopTelemetryContext, _: SpanOptions) Span {
        return .{};
    }

    pub fn run(_: NoopTelemetryContext, _: SpanOptions, callback: anytype) CallbackReturn(@TypeOf(callback)) {
        return callNoop(callback);
    }
};

pub const NOOP_TELEMETRY_CONTEXT: NoopTelemetryContext = .{};

pub const InMemoryTelemetryContext = struct {
    gpa: std.mem.Allocator,
    mutex: std.atomic.Mutex = .unlocked,
    spans: std.ArrayList(MutableSpan) = .empty,
    next_span_id: u64 = 1,
    next_end_sequence: u64 = 1,

    pub fn init(gpa: std.mem.Allocator) InMemoryTelemetryContext {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *InMemoryTelemetryContext) void {
        lock(&self.mutex);
        for (self.spans.items) |*span| span.deinit(self.gpa);
        self.spans.deinit(self.gpa);
        self.mutex.unlock();
        self.spans = .empty;
        self.next_span_id = 1;
        self.next_end_sequence = 1;
    }

    pub fn startSpan(self: *InMemoryTelemetryContext, options: SpanOptions) Span {
        return self.beginSpan(options, null);
    }

    pub fn run(self: *InMemoryTelemetryContext, options: SpanOptions, callback: anytype) CallbackReturn(@TypeOf(callback)) {
        const span = self.startSpan(options);
        return runCallback(span, callback);
    }

    pub fn snapshot(self: *InMemoryTelemetryContext, gpa: std.mem.Allocator) ![]RecordedSpan {
        lock(&self.mutex);
        defer self.mutex.unlock();

        const out = try gpa.alloc(RecordedSpan, self.spans.items.len);
        var initialized: usize = 0;
        errdefer {
            for (out[0..initialized]) |*span| span.deinit(gpa);
            gpa.free(out);
        }
        for (self.spans.items, 0..) |*source, index| {
            out[index] = try cloneSpan(gpa, source);
            initialized += 1;
        }
        return out;
    }

    fn beginSpan(self: *InMemoryTelemetryContext, options: SpanOptions, parent_id: ?u64) Span {
        // Prepare all fallible state before mutating the recording. Allocation
        // failures are deliberately passive and return one inert span.
        const name = self.gpa.dupe(u8, options.name) catch return .{};
        var attributes = cloneInputAttributes(self.gpa, options.attributes) catch {
            self.gpa.free(name);
            return .{};
        };
        var transferred = false;
        defer if (!transferred) {
            for (attributes.items) |*attribute| attribute.deinit(self.gpa);
            attributes.deinit(self.gpa);
            self.gpa.free(name);
        };

        lock(&self.mutex);
        defer self.mutex.unlock();
        if (parent_id) |id| {
            const parent = self.findLocked(id) orelse return .{};
            if (parent.settled) return .{};
        }
        const id = self.next_span_id;
        self.spans.append(self.gpa, .{
            .id = id,
            .parent_id = parent_id,
            .name = name,
            .attributes = attributes,
        }) catch return .{};
        transferred = true;
        self.next_span_id += 1;
        return .{ .context = self, .id = id };
    }

    fn addEvent(self: *InMemoryTelemetryContext, id: u64, name: []const u8, attributes: []const Attribute) void {
        const owned_name = self.gpa.dupe(u8, name) catch return;
        const owned_attributes = cloneInputAttributes(self.gpa, attributes) catch {
            self.gpa.free(owned_name);
            return;
        };
        var event = MutableEvent{ .name = owned_name, .attributes = owned_attributes };

        lock(&self.mutex);
        defer self.mutex.unlock();
        const span = self.findLocked(id) orelse {
            event.deinit(self.gpa);
            return;
        };
        if (span.settled) {
            event.deinit(self.gpa);
            return;
        }
        span.events.append(self.gpa, event) catch event.deinit(self.gpa);
    }

    fn setAttributes(self: *InMemoryTelemetryContext, id: u64, attributes: []const Attribute) void {
        lock(&self.mutex);
        defer self.mutex.unlock();
        const span = self.findLocked(id) orelse return;
        if (span.settled) return;

        // Clone and merge into a temporary list so an allocation failure cannot
        // leave a partially applied call behind.
        var merged = cloneOwnedAttributes(self.gpa, span.attributes.items) catch return;
        errdefer {
            for (merged.items) |*attribute| attribute.deinit(self.gpa);
            merged.deinit(self.gpa);
        }
        mergeInputAttributes(self.gpa, &merged, attributes) catch return;

        for (span.attributes.items) |*attribute| attribute.deinit(self.gpa);
        span.attributes.deinit(self.gpa);
        span.attributes = merged;
    }

    fn setStatus(self: *InMemoryTelemetryContext, id: u64, status: SpanStatus) void {
        var replacement = types.OwnedStatus.init(self.gpa, status) catch return;
        lock(&self.mutex);
        defer self.mutex.unlock();
        const span = self.findLocked(id) orelse {
            replacement.deinit(self.gpa);
            return;
        };
        if (span.settled) {
            replacement.deinit(self.gpa);
            return;
        }
        span.status.deinit(self.gpa);
        span.status = replacement;
        span.explicit_status = true;
    }

    fn settle(self: *InMemoryTelemetryContext, id: u64, failed: bool, error_name: ?[]const u8, error_message: ?[]const u8) void {
        var automatic: ?types.OwnedStatus = null;
        if (failed) {
            const borrowed: SpanStatus = if (error_name != null or error_message != null)
                .{ .error_status = .{
                    .name = error_name orelse "Error",
                    .message = error_message orelse "",
                } }
            else
                .{ .error_status = null };
            automatic = types.OwnedStatus.init(self.gpa, borrowed) catch null;
        }
        defer if (automatic) |*status| status.deinit(self.gpa);

        lock(&self.mutex);
        defer self.mutex.unlock();
        const span = self.findLocked(id) orelse return;
        if (span.settled) return;
        if (failed and !span.explicit_status) {
            if (automatic) |status| {
                span.status.deinit(self.gpa);
                span.status = status;
                automatic = null;
            } else {
                span.status.deinit(self.gpa);
                span.status = .{ .error_status = null };
            }
        }
        span.settled = true;
        span.end_sequence = self.next_end_sequence;
        self.next_end_sequence += 1;
    }

    fn findLocked(self: *InMemoryTelemetryContext, id: u64) ?*MutableSpan {
        for (self.spans.items) |*span| if (span.id == id) return span;
        return null;
    }
};

fn lock(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) std.atomic.spinLoopHint();
}

fn CallbackReturn(comptime Callback: type) type {
    const info = @typeInfo(Callback);
    if (info != .@"fn") @compileError("telemetry callback must be a function");
    return info.@"fn".return_type orelse @compileError("telemetry callback requires an explicit return type");
}

fn runCallback(span: Span, callback: anytype) CallbackReturn(@TypeOf(callback)) {
    const Return = CallbackReturn(@TypeOf(callback));
    return switch (@typeInfo(Return)) {
        .error_union => blk: {
            const value = @call(.auto, callback, .{span}) catch |err| {
                span.finishError(@errorName(err), @errorName(err));
                return err;
            };
            span.finish();
            break :blk value;
        },
        else => blk: {
            const value = @call(.auto, callback, .{span});
            span.finish();
            break :blk value;
        },
    };
}

fn callNoop(callback: anytype) CallbackReturn(@TypeOf(callback)) {
    return @call(.auto, callback, .{Span{}});
}

fn cloneInputAttributes(gpa: std.mem.Allocator, attributes: []const Attribute) !std.ArrayList(types.OwnedAttribute) {
    var out: std.ArrayList(types.OwnedAttribute) = .empty;
    errdefer {
        for (out.items) |*attribute| attribute.deinit(gpa);
        out.deinit(gpa);
    }
    for (attributes) |attribute| {
        if (findAttribute(out.items, attribute.name)) |index| {
            const replacement = try types.OwnedAttribute.init(gpa, attribute);
            out.items[index].deinit(gpa);
            out.items[index] = replacement;
        } else {
            try out.append(gpa, try types.OwnedAttribute.init(gpa, attribute));
        }
    }
    return out;
}

fn cloneOwnedAttributes(gpa: std.mem.Allocator, attributes: []const types.OwnedAttribute) !std.ArrayList(types.OwnedAttribute) {
    var out: std.ArrayList(types.OwnedAttribute) = .empty;
    errdefer {
        for (out.items) |*attribute| attribute.deinit(gpa);
        out.deinit(gpa);
    }
    for (attributes) |*attribute| try out.append(gpa, try attribute.clone(gpa));
    return out;
}

fn mergeInputAttributes(gpa: std.mem.Allocator, attributes: *std.ArrayList(types.OwnedAttribute), incoming: []const Attribute) !void {
    for (incoming) |attribute| {
        var replacement = try types.OwnedAttribute.init(gpa, attribute);
        if (findAttribute(attributes.items, attribute.name)) |index| {
            attributes.items[index].deinit(gpa);
            attributes.items[index] = replacement;
        } else {
            errdefer replacement.deinit(gpa);
            try attributes.append(gpa, replacement);
        }
    }
}

fn findAttribute(attributes: []const types.OwnedAttribute, name: []const u8) ?usize {
    for (attributes, 0..) |attribute, index| if (std.mem.eql(u8, attribute.name, name)) return index;
    return null;
}

fn cloneSpan(gpa: std.mem.Allocator, source: *const MutableSpan) !RecordedSpan {
    const name = try gpa.dupe(u8, source.name);
    errdefer gpa.free(name);
    var attributes = try cloneOwnedAttributes(gpa, source.attributes.items);
    errdefer {
        for (attributes.items) |*attribute| attribute.deinit(gpa);
        attributes.deinit(gpa);
    }
    const events = try gpa.alloc(types.RecordedEvent, source.events.items.len);
    var initialized_events: usize = 0;
    errdefer {
        for (events[0..initialized_events]) |*event| event.deinit(gpa);
        gpa.free(events);
    }
    for (source.events.items, 0..) |*source_event, index| {
        const event_name = try gpa.dupe(u8, source_event.name);
        errdefer gpa.free(event_name);
        var event_attributes = try cloneOwnedAttributes(gpa, source_event.attributes.items);
        events[index] = .{
            .name = event_name,
            .attributes = try event_attributes.toOwnedSlice(gpa),
        };
        initialized_events += 1;
    }
    return .{
        .id = source.id,
        .parent_id = source.parent_id,
        .name = name,
        .attributes = try attributes.toOwnedSlice(gpa),
        .events = events,
        .status = try source.status.clone(gpa),
        .settled = source.settled,
        .end_sequence = source.end_sequence,
    };
}

fn attributeNumber(attributes: []const types.OwnedAttribute, name: []const u8) ?f64 {
    const index = findAttribute(attributes, name) orelse return null;
    return switch (attributes[index].value) {
        .number => |value| value,
        else => null,
    };
}

fn attributeString(attributes: []const types.OwnedAttribute, name: []const u8) ?[]const u8 {
    const index = findAttribute(attributes, name) orelse return null;
    return switch (attributes[index].value) {
        .string => |value| value,
        else => null,
    };
}

test "in-memory telemetry preserves callback result and deterministic settlement" {
    const gpa = std.testing.allocator;
    var context = InMemoryTelemetryContext.init(gpa);
    defer context.deinit();

    const callbacks = struct {
        fn run(span: Span) usize {
            span.addEvent("started", &.{});
            return 42;
        }
    };
    try std.testing.expectEqual(@as(usize, 42), context.run(.{ .name = "success" }, callbacks.run));

    const spans = try context.snapshot(gpa);
    defer types.deinitSnapshots(gpa, spans);
    try std.testing.expectEqual(@as(usize, 1), spans.len);
    try std.testing.expectEqualStrings("success", spans[0].name);
    try std.testing.expect(spans[0].settled);
    try std.testing.expectEqual(@as(?u64, 1), spans[0].end_sequence);
    try std.testing.expect(spans[0].status == .ok);
}

test "in-memory telemetry preserves error union and automatic status" {
    const gpa = std.testing.allocator;
    var context = InMemoryTelemetryContext.init(gpa);
    defer context.deinit();

    const callbacks = struct {
        fn fail(_: Span) error{Expected}!void {
            return error.Expected;
        }
    };
    try std.testing.expectError(error.Expected, context.run(.{ .name = "failure" }, callbacks.fail));
    const spans = try context.snapshot(gpa);
    defer types.deinitSnapshots(gpa, spans);
    try std.testing.expect(spans[0].status == .error_status);
    try std.testing.expectEqualStrings("Expected", spans[0].status.error_status.?.name);
}

test "attributes merge last-write-wins and events remain ordered" {
    const gpa = std.testing.allocator;
    var context = InMemoryTelemetryContext.init(gpa);
    defer context.deinit();
    const span = context.startSpan(.{ .name = "recording", .attributes = &.{
        .{ .name = "start", .value = .{ .string = "value" } },
        .{ .name = "overwrite", .value = .{ .string = "start" } },
    } });
    span.setAttributes(&.{
        .{ .name = "count", .value = .{ .number = 1 } },
        .{ .name = "overwrite", .value = .{ .string = "middle" } },
    });
    span.setAttributes(&.{.{ .name = "overwrite", .value = .{ .string = "end" } }});
    span.addEvent("first", &.{.{ .name = "index", .value = .{ .number = 1 } }});
    span.addEvent("second", &.{.{ .name = "index", .value = .{ .number = 2 } }});
    span.finish();

    const spans = try context.snapshot(gpa);
    defer types.deinitSnapshots(gpa, spans);
    try std.testing.expectEqualStrings("end", attributeString(spans[0].attributes, "overwrite").?);
    try std.testing.expectEqual(@as(f64, 1), attributeNumber(spans[0].attributes, "count").?);
    try std.testing.expectEqual(@as(usize, 2), spans[0].events.len);
    try std.testing.expectEqualStrings("first", spans[0].events[0].name);
    try std.testing.expectEqualStrings("second", spans[0].events[1].name);
}

test "explicit status is last-write-wins and is not overwritten by failure" {
    const gpa = std.testing.allocator;
    var context = InMemoryTelemetryContext.init(gpa);
    defer context.deinit();
    const span = context.startSpan(.{ .name = "explicit" });
    span.setStatus(.{ .error_status = .{ .name = "First", .message = "one" } });
    span.setStatus(.ok);
    span.finishError("Ignored", "ignored");
    const spans = try context.snapshot(gpa);
    defer types.deinitSnapshots(gpa, spans);
    try std.testing.expect(spans[0].status == .ok);
}

test "nested and concurrent-shaped children retain explicit parentage" {
    const gpa = std.testing.allocator;
    var context = InMemoryTelemetryContext.init(gpa);
    defer context.deinit();
    const parent = context.startSpan(.{ .name = "parent" });
    const first = parent.startSpan(.{ .name = "first-child" });
    const second = parent.startSpan(.{ .name = "second-child" });
    second.finish();
    first.finish();
    parent.finish();
    const spans = try context.snapshot(gpa);
    defer types.deinitSnapshots(gpa, spans);
    try std.testing.expectEqual(@as(?u64, spans[0].id), spans[1].parent_id);
    try std.testing.expectEqual(@as(?u64, spans[0].id), spans[2].parent_id);
    try std.testing.expect(spans[2].end_sequence.? < spans[1].end_sequence.?);
    try std.testing.expect(spans[1].end_sequence.? < spans[0].end_sequence.?);
}

test "calls after settlement are inert including child recording" {
    const gpa = std.testing.allocator;
    var context = InMemoryTelemetryContext.init(gpa);
    defer context.deinit();
    const span = context.startSpan(.{ .name = "settled", .attributes = &.{.{ .name = "value", .value = .{ .string = "initial" } }} });
    span.finish();
    span.setAttributes(&.{.{ .name = "value", .value = .{ .string = "late" } }});
    span.addEvent("late", &.{});
    span.setStatus(.{ .error_status = null });
    const child = span.startSpan(.{ .name = "late-child" });
    try std.testing.expect(!child.isRecording());
    child.finish();
    const spans = try context.snapshot(gpa);
    defer types.deinitSnapshots(gpa, spans);
    try std.testing.expectEqual(@as(usize, 1), spans.len);
    try std.testing.expectEqualStrings("initial", attributeString(spans[0].attributes, "value").?);
    try std.testing.expectEqual(@as(usize, 0), spans[0].events.len);
}

test "noop telemetry admits callback and records nothing" {
    const callbacks = struct {
        fn run(span: Span) u8 {
            std.debug.assert(!span.isRecording());
            return 7;
        }
    };
    try std.testing.expectEqual(@as(u8, 7), NOOP_TELEMETRY_CONTEXT.run(.{ .name = "ignored" }, callbacks.run));
}
