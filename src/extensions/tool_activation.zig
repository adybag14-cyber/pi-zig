//! Owned registration transitions and independent active selection.
const std = @import("std");
pub const Selection = struct {
    allow: ?[]const []const u8 = null,
    exclude: ?[]const []const u8 = null,
    modifiers: ?[]const []const u8 = null,
    noTools: bool = false,
};

pub const Event = struct {
    pub const Kind = enum { registration, selection };
    kind: Kind = .registration,
    owner_generation: u64,
    sequence: u64,
    owner_id: u64,
    source_path: []const u8,
    name: []const u8,
    registered: bool = true,
    default_active: bool = true,
    declarable: bool = true,
    hidden: bool = false,
    /// Factory registrations establish the registry before the core binds.
    activate: bool = true,
    /// The producer records actual registration activation, so resetting an
    /// acknowledged context never loses intermediate false/true/false effects.
    activated: bool = false,
    active_tools: ?[]const []const u8 = null,

    pub fn eql(self: Event, other: Event) bool {
        inline for (.{ "kind", "owner_generation", "sequence", "owner_id", "registered", "default_active", "declarable", "hidden", "activate", "activated" }) |name| if (@field(self, name) != @field(other, name)) return false;
        if (!std.mem.eql(u8, self.source_path, other.source_path) or !std.mem.eql(u8, self.name, other.name)) return false;
        if ((self.active_tools == null) != (other.active_tools == null)) return false;
        if (self.active_tools) |names| {
            const other_names = other.active_tools.?;
            if (names.len != other_names.len) return false;
            for (names, other_names) |left, right| if (!std.mem.eql(u8, left, right)) return false;
        }
        return true;
    }

    pub fn clone(self: Event, gpa: std.mem.Allocator) !Event {
        var copy = self;
        copy.source_path = try gpa.dupe(u8, self.source_path);
        errdefer gpa.free(copy.source_path);
        copy.name = try gpa.dupe(u8, self.name);
        errdefer gpa.free(copy.name);
        if (self.active_tools) |names| {
            const owned = try gpa.alloc([]const u8, names.len);
            var initialized: usize = 0;
            errdefer {
                for (owned[0..initialized]) |name| gpa.free(name);
                gpa.free(owned);
            }
            for (names, owned) |name, *slot| {
                slot.* = try gpa.dupe(u8, name);
                initialized += 1;
            }
            copy.active_tools = owned;
        }
        return copy;
    }
    pub fn deinit(self: *Event, gpa: std.mem.Allocator) void {
        gpa.free(self.source_path);
        gpa.free(self.name);
        if (self.active_tools) |names| {
            for (names) |name| gpa.free(name);
            gpa.free(names);
        }
        self.* = undefined;
    }
    pub fn parse(gpa: std.mem.Allocator, value: std.json.Value) !Event {
        if (value != .object) return error.InvalidToolRegistrationEvent;
        const object = value.object;
        const name = object.get("name") orelse return error.InvalidToolRegistrationEvent;
        const source = object.get("source_path") orelse return error.InvalidToolRegistrationEvent;
        if (name != .string or source != .string) return error.InvalidToolRegistrationEvent;
        var event: Event = .{
            .owner_generation = try identifier(object.get("owner_generation") orelse return error.InvalidToolRegistrationEvent),
            .sequence = try identifier(object.get("sequence") orelse return error.InvalidToolRegistrationEvent),
            .owner_id = try identifier(object.get("owner_id") orelse return error.InvalidToolRegistrationEvent),
            .source_path = source.string,
            .name = name.string,
            .registered = try boolean(object, "registered", true),
            .default_active = try boolean(object, "default_active", true),
            .declarable = try boolean(object, "declarable", true),
            .hidden = try boolean(object, "hidden", false),
            .activate = try boolean(object, "activate", true),
            .activated = try boolean(object, "activated", false),
        };
        if (object.get("kind")) |kind| {
            if (kind != .string) return error.InvalidToolRegistrationEvent;
            event.kind = std.meta.stringToEnum(Kind, kind.string) orelse return error.InvalidToolRegistrationEvent;
        }
        var active: std.ArrayList([]const u8) = .empty;
        defer active.deinit(gpa);
        if (event.kind == .selection) {
            const values = object.get("active_tools") orelse return error.InvalidToolRegistrationEvent;
            if (values != .array or values.array.items.len > 65536) return error.InvalidToolRegistrationEvent;
            for (values.array.items) |entry| {
                if (entry != .string) return error.InvalidToolRegistrationEvent;
                try active.append(gpa, entry.string);
            }
            event.active_tools = active.items;
        } else if (name.string.len == 0) return error.InvalidToolRegistrationEvent;
        if (event.owner_generation == 0 or event.sequence == 0 or (event.registered and (event.owner_id == 0 or source.string.len == 0))) return error.InvalidToolRegistrationEvent;
        return event.clone(gpa);
    }
    pub fn identifier(value: std.json.Value) !u64 {
        const result = switch (value) {
            .integer => |number| if (number >= 0) @as(u64, @intCast(number)) else return error.InvalidToolRegistrationEvent,
            .string => |text| try std.fmt.parseUnsigned(u64, text, 10),
            else => return error.InvalidToolRegistrationEvent,
        };
        if (result > 9_007_199_254_740_991) return error.InvalidToolRegistrationEvent;
        return result;
    }
    fn boolean(object: std.json.ObjectMap, name: []const u8, fallback: bool) !bool {
        const value = object.get(name) orelse return fallback;
        if (value != .bool) return error.InvalidToolRegistrationEvent;
        return value.bool;
    }
};

pub const Definition = struct {
    name: []const u8,
    owner_id: u64,
    source_path: []const u8,
    default_active: bool,
    declarable: bool,
    activated_on_registration: bool,

    fn deinit(self: *Definition, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.source_path);
        self.* = undefined;
    }
};

pub const Policy = struct {
    context: ?*anyopaque = null,
    enabled_fn: ?*const fn (?*anyopaque, []const u8, bool) bool = null,
    /// An explicit allowed-tools selector activates matching definitions on
    /// every registry refresh, independent of their defaultActive value.
    selected_fn: ?*const fn (?*anyopaque, []const u8) bool = null,

    pub fn enabled(self: Policy, name: []const u8, default_active: bool, declarable: bool) bool {
        if (!declarable) return false;
        return if (self.enabled_fn) |call| call(self.context, name, default_active) else default_active;
    }
    pub fn selected(self: Policy, name: []const u8, declarable: bool) bool {
        return declarable and if (self.selected_fn) |call| call(self.context, name) else false;
    }
};

pub const Tracker = struct {
    gpa: std.mem.Allocator,
    owner_generation: u64,
    sequence: u64 = 0,
    definitions: std.ArrayList(Definition) = .empty,
    active: std.ArrayList([]const u8) = .empty,

    pub fn init(gpa: std.mem.Allocator, owner_generation: u64) Tracker {
        return .{ .gpa = gpa, .owner_generation = owner_generation };
    }
    pub fn deinit(self: *Tracker) void {
        for (self.definitions.items) |*definition| definition.deinit(self.gpa);
        self.definitions.deinit(self.gpa);
        for (self.active.items) |name| self.gpa.free(name);
        self.active.deinit(self.gpa);
        self.* = undefined;
    }
    pub fn clone(self: *const Tracker) !Tracker {
        var next = Tracker.init(self.gpa, self.owner_generation);
        errdefer next.deinit();
        next.sequence = self.sequence;
        try next.definitions.ensureTotalCapacity(self.gpa, self.definitions.items.len);
        for (self.definitions.items) |definition| {
            const name = try self.gpa.dupe(u8, definition.name);
            errdefer self.gpa.free(name);
            const source = try self.gpa.dupe(u8, definition.source_path);
            next.definitions.appendAssumeCapacity(.{ .name = name, .source_path = source, .owner_id = definition.owner_id, .default_active = definition.default_active, .declarable = definition.declarable, .activated_on_registration = definition.activated_on_registration });
        }
        try next.active.ensureTotalCapacity(self.gpa, self.active.items.len);
        for (self.active.items) |name| next.active.appendAssumeCapacity(try self.gpa.dupe(u8, name));
        return next;
    }
    pub fn commit(self: *Tracker, next: *Tracker) void {
        std.debug.assert(self.gpa.ptr == next.gpa.ptr and self.owner_generation == next.owner_generation);
        var old = self.*;
        self.* = next.*;
        next.* = undefined;
        old.deinit();
    }
    pub fn defaultActivation(self: *const Tracker, name: []const u8) ?bool {
        for (self.definitions.items) |definition| if (std.mem.eql(u8, definition.name, name)) return definition.default_active and definition.declarable;
        return null;
    }
    pub fn isActive(self: *const Tracker, name: []const u8) bool {
        for (self.active.items) |entry| if (std.mem.eql(u8, entry, name)) return true;
        return false;
    }
    fn addActive(self: *Tracker, name: []const u8) !bool {
        if (self.isActive(name)) return false;
        const owned = try self.gpa.dupe(u8, name);
        errdefer self.gpa.free(owned);
        try self.active.append(self.gpa, owned);
        return true;
    }
    fn removeActive(self: *Tracker, name: []const u8) void {
        for (self.active.items, 0..) |entry, index| if (std.mem.eql(u8, entry, name)) {
            self.gpa.free(self.active.orderedRemove(index));
            return;
        };
    }
    pub fn setActive(self: *Tracker, names: []const []const u8) !void {
        var prepared: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (prepared.items) |name| self.gpa.free(name);
            prepared.deinit(self.gpa);
        }
        for (names) |name| {
            var duplicate = false;
            for (prepared.items) |old| if (std.mem.eql(u8, old, name)) {
                duplicate = true;
                break;
            };
            if (duplicate) continue;
            const owned = try self.gpa.dupe(u8, name);
            errdefer self.gpa.free(owned);
            try prepared.append(self.gpa, owned);
        }
        for (self.active.items) |name| self.gpa.free(name);
        self.active.deinit(self.gpa);
        self.active = prepared;
    }
    /// For use only on an owned provisional clone. The outer commit is the
    /// allocation-atomic boundary; no borrowed names outlive this operation.
    pub fn applyPrepared(self: *Tracker, event: *Event, policy: Policy) !void {
        if (event.owner_generation != self.owner_generation) return error.StaleToolRegistrationOwner;
        if (event.sequence <= self.sequence) return error.StaleToolRegistrationSequence;
        const next_sequence = std.math.add(u64, self.sequence, 1) catch return error.InvalidToolRegistrationSequence;
        if (event.sequence != next_sequence or (event.kind == .registration and event.name.len == 0)) return error.InvalidToolRegistrationSequence;
        if (event.kind == .selection) {
            try self.setActive(event.active_tools orelse return error.InvalidToolRegistrationEvent);
            event.activated = false;
            self.sequence = event.sequence;
            return;
        }
        var index: ?usize = null;
        for (self.definitions.items, 0..) |definition, i| if (std.mem.eql(u8, definition.name, event.name)) {
            index = i;
            break;
        };
        event.activated = false;
        if (!event.registered) {
            if (index) |i| {
                var removed = self.definitions.orderedRemove(i);
                removed.deinit(self.gpa);
            }
            self.removeActive(event.name);
        } else {
            if (event.hidden) self.removeActive(event.name);
            const enabled = policy.enabled(event.name, event.default_active, event.declarable);
            const previously_enabled = if (index) |i| self.definitions.items[i].activated_on_registration else false;
            const source = try self.gpa.dupe(u8, event.source_path);
            var source_owned = false;
            errdefer if (!source_owned) self.gpa.free(source);
            if (index) |i| {
                self.gpa.free(self.definitions.items[i].source_path);
                self.definitions.items[i].source_path = source;
                self.definitions.items[i].owner_id = event.owner_id;
                self.definitions.items[i].default_active = event.default_active;
                self.definitions.items[i].declarable = event.declarable;
                self.definitions.items[i].activated_on_registration = enabled;
                source_owned = true;
            } else {
                if (self.definitions.items.len >= 65536) return error.ToolRegistrationLimit;
                const name = try self.gpa.dupe(u8, event.name);
                var name_owned = false;
                errdefer if (!name_owned) self.gpa.free(name);
                try self.definitions.append(self.gpa, .{ .name = name, .owner_id = event.owner_id, .source_path = source, .default_active = event.default_active, .declarable = event.declarable, .activated_on_registration = enabled });
                source_owned = true;
                name_owned = true;
            }
            if (!event.hidden and event.activate and ((!previously_enabled and enabled) or policy.selected(event.name, event.declarable))) {
                _ = try self.addActive(event.name);
                event.activated = true;
            }
        }
        self.sequence = event.sequence;
    }
    pub fn apply(self: *Tracker, events: []Event, policy: Policy) !void {
        var next = try self.clone();
        errdefer next.deinit();
        const prepared = try self.gpa.dupe(Event, events);
        defer self.gpa.free(prepared);
        for (prepared) |*event| try next.applyPrepared(event, policy);
        for (events, prepared) |*event, projected| event.activated = projected.activated;
        self.commit(&next);
    }
    /// A newer invocation can carry an older Host context. Apply its explicit
    /// active set, then replay only the unacknowledged registration effects.
    pub fn reconcileContext(self: *Tracker, names: []const []const u8, acknowledged: u64, pending: []const Event) !void {
        if (acknowledged > self.sequence) return error.InvalidToolRegistrationAcknowledgement;
        var next = try self.clone();
        errdefer next.deinit();
        try next.setActive(names);
        for (pending) |event| {
            if (event.sequence <= acknowledged) continue;
            if (event.kind == .selection) try next.setActive(event.active_tools orelse return error.InvalidToolRegistrationEvent) else if (!event.registered or event.hidden) next.removeActive(event.name) else if (event.activated) _ = try next.addActive(event.name);
        }
        self.commit(&next);
    }
};

test "native activation transition journal preserves false true false and explicit independent selection" {
    var tracker = Tracker.init(std.testing.allocator, 42);
    defer tracker.deinit();
    var events = [_]Event{
        .{ .owner_generation = 42, .sequence = 1, .owner_id = 1, .source_path = "first", .name = "late", .default_active = false },
        .{ .owner_generation = 42, .sequence = 2, .owner_id = 1, .source_path = "first", .name = "late", .default_active = true },
        .{ .owner_generation = 42, .sequence = 3, .owner_id = 1, .source_path = "first", .name = "late", .default_active = false },
    };
    try tracker.apply(&events, .{});
    try std.testing.expect(tracker.isActive("late"));
    try std.testing.expectEqual(@as(?bool, false), tracker.defaultActivation("late"));
    try std.testing.expect(!events[0].activated and events[1].activated and !events[2].activated);
    try tracker.reconcileContext(&.{"read"}, 1, &events);
    try std.testing.expect(tracker.isActive("read") and tracker.isActive("late"));
    try tracker.reconcileContext(&.{"read"}, 3, &events);
    try std.testing.expect(tracker.isActive("read") and !tracker.isActive("late"));
    var removed = [_]Event{.{ .owner_generation = 42, .sequence = 4, .owner_id = 0, .source_path = "", .name = "late", .registered = false }};
    try tracker.apply(&removed, .{});
    try std.testing.expect(tracker.defaultActivation("late") == null);
}

test "native activation transition application is allocation atomic across all owned registry and selection allocations" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var tracker = Tracker.init(gpa, 42);
            defer tracker.deinit();
            var initial = [_]Event{.{ .owner_generation = 42, .sequence = 1, .owner_id = 1, .source_path = "first", .name = "old" }};
            try tracker.apply(&initial, .{});
            var next = [_]Event{
                .{ .owner_generation = 42, .sequence = 2, .owner_id = 1, .source_path = "first", .name = "late", .default_active = false },
                .{ .owner_generation = 42, .sequence = 3, .owner_id = 2, .source_path = "second", .name = "late", .default_active = true },
                .{ .owner_generation = 42, .sequence = 4, .owner_id = 2, .source_path = "second", .name = "late", .default_active = false },
            };
            tracker.apply(&next, .{}) catch |err| {
                try std.testing.expectEqual(@as(u64, 1), tracker.sequence);
                try std.testing.expect(tracker.isActive("old") and !tracker.isActive("late"));
                try std.testing.expect(tracker.defaultActivation("late") == null);
                return err;
            };
            try std.testing.expect(tracker.isActive("late"));
            try std.testing.expectEqual(@as(u64, 4), tracker.sequence);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

test "native activation journal orders explicit setters with registrations and replays older contexts" {
    var tracker = Tracker.init(std.testing.allocator, 42);
    defer tracker.deinit();
    try tracker.setActive(&.{"read"});
    var events = [_]Event{
        .{ .owner_generation = 42, .sequence = 1, .owner_id = 1, .source_path = "first", .name = "one" },
        .{ .kind = .selection, .owner_generation = 42, .sequence = 2, .owner_id = 1, .source_path = "first", .name = "", .active_tools = &.{} },
        .{ .owner_generation = 42, .sequence = 3, .owner_id = 1, .source_path = "first", .name = "two" },
    };
    try tracker.apply(&events, .{});
    try std.testing.expect(!tracker.isActive("one") and !tracker.isActive("read") and tracker.isActive("two"));
    try tracker.reconcileContext(&.{"read"}, 0, &events);
    try std.testing.expect(!tracker.isActive("one") and !tracker.isActive("read") and tracker.isActive("two"));
}
