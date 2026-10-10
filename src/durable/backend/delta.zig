//! Decoded Chord tuples applied to a caller-owned native JSON tree.
const std = @import("std");
const json = @import("json.zig");
const Value = json.Value;
fn reserved(key: []const u8) bool {
    return std.mem.eql(u8, key, "__proto__") or std.mem.eql(u8, key, "constructor") or std.mem.eql(u8, key, "prototype");
}
fn pathOf(value: Value, nonempty: bool) ![]const Value {
    if (value != .array or (nonempty and value.array.items.len == 0)) return error.InvalidDeltaPath;
    for (value.array.items) |segment| switch (segment) {
        .string => |key| {
            if (reserved(key)) return error.UnsafeDeltaPath;
        },
        .float, .integer => {
            _ = try json.asInteger(segment);
        },
        else => return error.UnsafeDeltaPath,
    };
    return value.array.items;
}
fn asKey(gpa: std.mem.Allocator, segment: Value) ![]const u8 {
    return if (segment == .string) segment.string else std.fmt.allocPrint(gpa, "{d}", .{try json.asInteger(segment)});
}
fn child(gpa: std.mem.Allocator, parent: *Value, segment: Value) !*Value {
    return switch (parent.*) {
        .object => |*object| object.getPtr(try asKey(gpa, segment)) orelse error.UnresolvableDeltaPath,
        .array => |*array| blk: {
            if (segment == .string) return error.UnsafeDeltaPath;
            const index = try json.asInteger(segment);
            if (index >= array.items.len) return error.UnresolvableDeltaPath;
            break :blk &array.items[@intCast(index)];
        },
        else => error.UnresolvableDeltaPath,
    };
}
fn resolve(gpa: std.mem.Allocator, root: *Value, path: []const Value) !*Value {
    var current = root;
    for (path) |segment| current = try child(gpa, current, segment);
    if (current.* != .object and current.* != .array) return error.UnresolvableDeltaPath;
    return current;
}
fn stringSlice(gpa: std.mem.Allocator, input: []const u8, skip: u64) ![]const u8 {
    const units = try std.unicode.wtf8ToWtf16LeAlloc(gpa, input);
    return std.unicode.wtf16LeToWtf8Alloc(gpa, units[@intCast(@min(skip, units.len))..]);
}
pub fn apply(gpa: std.mem.Allocator, root: *Value, operations: Value) !void {
    if (operations != .array) return error.InvalidDelta;
    for (operations.array.items) |operation| {
        if (operation != .array or operation.array.items.len == 0) return error.InvalidDelta;
        const tuple = operation.array.items;
        const verb = try json.asString(tuple[0]);
        if (verb.len != 1) return error.InvalidDelta;
        if (verb[0] == 'r') {
            if (tuple.len != 2) return error.InvalidDelta;
            root.* = try json.clone(gpa, tuple[1]);
            continue;
        }
        const expected: usize = switch (verb[0]) {
            'd' => 2,
            's', 'a', 't', 'm' => 3,
            'p' => 5,
            else => return error.UnknownDeltaVerb,
        };
        if (tuple.len != expected) return error.InvalidDelta;
        const path = try pathOf(tuple[1], verb[0] != 'p' and verb[0] != 'm');
        if (verb[0] == 'p' or verb[0] == 'm') {
            const target = try resolve(gpa, root, path);
            if (target.* != .array) return error.UnresolvableDeltaPath;
            if (verb[0] == 'p') {
                const requested = try json.asInteger(tuple[2]);
                const remove = try json.asInteger(tuple[3]);
                if (tuple[4] != .array) return error.InvalidDelta;
                const at: usize = @intCast(@min(requested, target.array.items.len));
                const count: usize = @intCast(@min(remove, target.array.items.len - at));
                var result: std.array_list.Managed(Value) = .init(gpa);
                try result.appendSlice(target.array.items[0..at]);
                for (tuple[4].array.items) |item| try result.append(try json.clone(gpa, item));
                try result.appendSlice(target.array.items[at + count ..]);
                target.* = .{ .array = result };
            } else {
                if (tuple[2] != .array or tuple[2].array.items.len != target.array.items.len) return error.InvalidDeltaPermutation;
                const order = tuple[2].array.items;
                const seen = try gpa.alloc(bool, order.len);
                @memset(seen, false);
                const previous = target.array.items;
                var result: std.array_list.Managed(Value) = .init(gpa);
                for (order) |item| {
                    const index = try json.asInteger(item);
                    if (index >= previous.len or seen[@intCast(index)]) return error.InvalidDeltaPermutation;
                    seen[@intCast(index)] = true;
                    try result.append(previous[@intCast(index)]);
                }
                target.* = .{ .array = result };
            }
            continue;
        }
        const parent = try resolve(gpa, root, path[0 .. path.len - 1]);
        const segment = path[path.len - 1];
        var index: ?usize = null;
        var property: []const u8 = undefined;
        if (parent.* == .array) {
            if (segment == .string) return error.UnsafeDeltaPath;
            const number = try json.asInteger(segment);
            if (number > parent.array.items.len) return error.UnresolvableDeltaPath;
            index = @intCast(number);
        } else property = try asKey(gpa, segment);
        if (verb[0] == 'd') {
            if (index) |at| {
                if (at >= parent.array.items.len) return error.UnresolvableDeltaPath;
                _ = parent.array.orderedRemove(at);
            } else _ = parent.object.orderedRemove(property);
            continue;
        }
        var replacement: Value = undefined;
        if (verb[0] == 's') replacement = try json.clone(gpa, tuple[2]) else {
            const current = if (index) |at| if (at < parent.array.items.len) parent.array.items[at] else return error.UnresolvableDeltaPath else parent.object.get(property) orelse return error.UnresolvableDeltaPath;
            const contents = try json.asString(current);
            replacement = .{ .string = if (verb[0] == 'a') try std.fmt.allocPrint(gpa, "{s}{s}", .{ contents, try json.asString(tuple[2]) }) else try stringSlice(gpa, contents, try json.asInteger(tuple[2])) };
        }
        if (index) |at| {
            if (at == parent.array.items.len) try parent.array.append(replacement) else parent.array.items[at] = replacement;
        } else try parent.object.put(gpa, try gpa.dupe(u8, property), replacement);
    }
}

test "durable deltas preserve UTF16 truncation  and  reject sparse unsafe  and  nonbijective mutations" {
    const gpa = std.testing.allocator;
    var base = try json.Owned.parse(gpa, "{\"s\":\"A😀B\",\"list\":[1,2,3]}");
    defer base.deinit();
    var ops = try json.Owned.parse(gpa, "[[\"t\",[\"s\"],2],[\"m\",[\"list\"],[2,0,1]],[\"p\",[\"list\"],1,1,[9]]]");
    defer ops.deinit();
    try apply(base.arena.allocator(), &base.value, ops.value);
    const string = base.value.object.get("s").?.string;
    try std.testing.expectEqualStrings("\xed\xb8\x80B", string);
    try std.testing.expectEqual(@as(f64, 9), try json.asNumber(base.value.object.get("list").?.array.items[1]));
    var bad = try json.Owned.parse(gpa, "[[\"s\",[\"__proto__\",\"x\"],true]]");
    defer bad.deinit();
    try std.testing.expectError(error.UnsafeDeltaPath, apply(base.arena.allocator(), &base.value, bad.value));
}
