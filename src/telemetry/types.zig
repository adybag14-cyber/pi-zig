//! Vendor-neutral telemetry contracts and owned snapshot types.
//! This mirrors the observable contract of packages/telemetry without relying
//! on ambient global spans or a particular exporter.
const std = @import("std");

pub const AttributeValue = union(enum) {
    string: []const u8,
    number: f64,
    boolean: bool,
    strings: []const []const u8,
    numbers: []const f64,
    booleans: []const bool,
};

pub const Attribute = struct {
    name: []const u8,
    value: AttributeValue,
};

pub const SpanOptions = struct {
    name: []const u8,
    attributes: []const Attribute = &.{},
};

pub const ErrorStatus = struct {
    name: []const u8,
    message: []const u8,
};

pub const SpanStatus = union(enum) {
    ok,
    error_status: ?ErrorStatus,
};

pub const OwnedAttributeValue = union(enum) {
    string: []u8,
    number: f64,
    boolean: bool,
    strings: [][]u8,
    numbers: []f64,
    booleans: []bool,

    pub fn clone(gpa: std.mem.Allocator, value: AttributeValue) !OwnedAttributeValue {
        return switch (value) {
            .string => |v| .{ .string = try gpa.dupe(u8, v) },
            .number => |v| .{ .number = v },
            .boolean => |v| .{ .boolean = v },
            .strings => |values| blk: {
                const out = try gpa.alloc([]u8, values.len);
                var initialized: usize = 0;
                errdefer {
                    for (out[0..initialized]) |item| gpa.free(item);
                    gpa.free(out);
                }
                for (values, 0..) |item, index| {
                    out[index] = try gpa.dupe(u8, item);
                    initialized += 1;
                }
                break :blk .{ .strings = out };
            },
            .numbers => |values| .{ .numbers = try gpa.dupe(f64, values) },
            .booleans => |values| .{ .booleans = try gpa.dupe(bool, values) },
        };
    }

    pub fn cloneOwned(self: OwnedAttributeValue, gpa: std.mem.Allocator) !OwnedAttributeValue {
        return switch (self) {
            .string => |v| .{ .string = try gpa.dupe(u8, v) },
            .number => |v| .{ .number = v },
            .boolean => |v| .{ .boolean = v },
            .strings => |values| blk: {
                const out = try gpa.alloc([]u8, values.len);
                var initialized: usize = 0;
                errdefer {
                    for (out[0..initialized]) |item| gpa.free(item);
                    gpa.free(out);
                }
                for (values, 0..) |value, index| {
                    out[index] = try gpa.dupe(u8, value);
                    initialized += 1;
                }
                break :blk .{ .strings = out };
            },
            .numbers => |values| .{ .numbers = try gpa.dupe(f64, values) },
            .booleans => |values| .{ .booleans = try gpa.dupe(bool, values) },
        };
    }

    pub fn borrowed(self: *const OwnedAttributeValue) AttributeValue {
        return switch (self.*) {
            .string => |v| .{ .string = v },
            .number => |v| .{ .number = v },
            .boolean => |v| .{ .boolean = v },
            .strings => |v| .{ .strings = v },
            .numbers => |v| .{ .numbers = v },
            .booleans => |v| .{ .booleans = v },
        };
    }

    pub fn deinit(self: *OwnedAttributeValue, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .string => |v| gpa.free(v),
            .strings => |values| {
                for (values) |value| gpa.free(value);
                gpa.free(values);
            },
            .numbers => |values| gpa.free(values),
            .booleans => |values| gpa.free(values),
            .number, .boolean => {},
        }
        self.* = undefined;
    }
};

pub const OwnedAttribute = struct {
    name: []u8,
    value: OwnedAttributeValue,

    pub fn init(gpa: std.mem.Allocator, attribute: Attribute) !OwnedAttribute {
        const name = try gpa.dupe(u8, attribute.name);
        errdefer gpa.free(name);
        return .{ .name = name, .value = try .clone(gpa, attribute.value) };
    }

    pub fn clone(self: *const OwnedAttribute, gpa: std.mem.Allocator) !OwnedAttribute {
        const name = try gpa.dupe(u8, self.name);
        errdefer gpa.free(name);
        return .{ .name = name, .value = try self.value.cloneOwned(gpa) };
    }

    pub fn deinit(self: *OwnedAttribute, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        self.value.deinit(gpa);
        self.* = undefined;
    }
};

pub const OwnedStatus = union(enum) {
    ok,
    error_status: ?struct { name: []u8, message: []u8 },

    pub fn init(gpa: std.mem.Allocator, status: SpanStatus) !OwnedStatus {
        return switch (status) {
            .ok => .ok,
            .error_status => |maybe_error| if (maybe_error) |err| blk: {
                const name = try gpa.dupe(u8, err.name);
                errdefer gpa.free(name);
                break :blk .{ .error_status = .{
                    .name = name,
                    .message = try gpa.dupe(u8, err.message),
                } };
            } else .{ .error_status = null },
        };
    }

    pub fn clone(self: *const OwnedStatus, gpa: std.mem.Allocator) !OwnedStatus {
        return switch (self.*) {
            .ok => .ok,
            .error_status => |maybe_error| if (maybe_error) |err| blk: {
                const name = try gpa.dupe(u8, err.name);
                errdefer gpa.free(name);
                break :blk .{ .error_status = .{
                    .name = name,
                    .message = try gpa.dupe(u8, err.message),
                } };
            } else .{ .error_status = null },
        };
    }

    pub fn borrowed(self: *const OwnedStatus) SpanStatus {
        return switch (self.*) {
            .ok => .ok,
            .error_status => |maybe_error| if (maybe_error) |err|
                .{ .error_status = .{ .name = err.name, .message = err.message } }
            else
                .{ .error_status = null },
        };
    }

    pub fn deinit(self: *OwnedStatus, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .ok => {},
            .error_status => |maybe_error| if (maybe_error) |err| {
                gpa.free(err.name);
                gpa.free(err.message);
            },
        }
        self.* = undefined;
    }
};

pub const RecordedEvent = struct {
    name: []u8,
    attributes: []OwnedAttribute,

    pub fn deinit(self: *RecordedEvent, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        for (self.attributes) |*attribute| attribute.deinit(gpa);
        gpa.free(self.attributes);
        self.* = undefined;
    }
};

pub const RecordedSpan = struct {
    id: u64,
    parent_id: ?u64,
    name: []u8,
    attributes: []OwnedAttribute,
    events: []RecordedEvent,
    status: OwnedStatus,
    settled: bool,
    end_sequence: ?u64,

    pub fn deinit(self: *RecordedSpan, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        for (self.attributes) |*attribute| attribute.deinit(gpa);
        gpa.free(self.attributes);
        for (self.events) |*event| event.deinit(gpa);
        gpa.free(self.events);
        self.status.deinit(gpa);
        self.* = undefined;
    }
};

pub fn deinitSnapshots(gpa: std.mem.Allocator, snapshots: []RecordedSpan) void {
    for (snapshots) |*snapshot| snapshot.deinit(gpa);
    gpa.free(snapshots);
}

test "owned attribute values detach array and string storage" {
    const gpa = std.testing.allocator;
    var words = [_][]const u8{ "one", "two" };
    var owned = try OwnedAttributeValue.clone(gpa, .{ .strings = &words });
    defer owned.deinit(gpa);
    words[0] = "changed";
    try std.testing.expectEqualStrings("one", owned.strings[0]);
}
