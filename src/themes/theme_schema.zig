//! Native validation of the actual Source6fb Theme JSON Schema.
//! Schema metadata is captured from the original TypeBox definitions.
const std = @import("std");
const Value = std.json.Value;
const Errors = struct {
    gpa: std.mem.Allocator,
    lines: std.ArrayList([]u8) = .empty,
    missing_colors: std.ArrayList([]const u8) = .empty,
    count: usize = 0,
    fn deinit(self: *Errors) void {
        for (self.lines.items) |line| self.gpa.free(line);
        self.lines.deinit(self.gpa);
        self.missing_colors.deinit(self.gpa);
    }
    fn add(self: *Errors, path: []const u8, message: []const u8) !void {
        if (self.count == 8) return;
        const line = try std.fmt.allocPrint(self.gpa, "  - {s}: {s}", .{ if (path.len == 0) "/" else path, message });
        errdefer self.gpa.free(line);
        try self.lines.append(self.gpa, line);
        self.count += 1;
    }
    fn changed(self: *const Errors, before_lines: usize, before_missing: usize) bool {
        return self.lines.items.len != before_lines or self.missing_colors.items.len != before_missing;
    }
};

fn pointerAlloc(gpa: std.mem.Allocator, path: []const u8, key: []const u8) ![]u8 {
    // Source TypeBox's error interpreter appends literal property names.
    return std.fmt.allocPrint(gpa, "{s}/{s}", .{ path, key });
}
fn number(value: Value) ?f64 {
    return switch (value) {
        .integer => |v| @floatFromInt(v),
        .float => |v| v,
        else => null,
    };
}
fn typeMatches(value: Value, name: []const u8) bool {
    if (std.mem.eql(u8, name, "object")) return value == .object;
    if (std.mem.eql(u8, name, "string")) return value == .string;
    if (std.mem.eql(u8, name, "integer")) return if (number(value)) |n| std.math.isFinite(n) and @floor(n) == n else false;
    return false;
}
fn check(errors: *Errors, schema: Value, value: Value, path: []const u8) anyerror!bool {
    if (errors.count == 8) return false;
    const before_lines = errors.lines.items.len;
    const before_missing = errors.missing_colors.items.len;
    if (schema == .bool) {
        if (!schema.bool) try errors.add(path, "schema is false");
        return schema.bool;
    }
    if (schema != .object) return error.UnsupportedThemeSchema;
    if (schema.object.get("anyOf")) |alternatives| {
        var failures: Errors = .{ .gpa = errors.gpa };
        defer failures.deinit();
        for (alternatives.array.items) |alternative| {
            var branch: Errors = .{ .gpa = errors.gpa };
            defer branch.deinit();
            if (try check(&branch, alternative, value, path)) return true;
            for (branch.lines.items) |line| {
                const owned = try errors.gpa.dupe(u8, line);
                errdefer errors.gpa.free(owned);
                try failures.lines.append(errors.gpa, owned);
            }
        }
        for (failures.lines.items) |line| {
            if (errors.count == 8) break;
            const owned = try errors.gpa.dupe(u8, line);
            errdefer errors.gpa.free(owned);
            try errors.lines.append(errors.gpa, owned);
            errors.count += 1;
        }
        try errors.add(path, "must match a schema in anyOf");
        return false;
    }
    if (schema.object.get("type")) |kind| if (!typeMatches(value, kind.string)) {
        const message = try std.fmt.allocPrint(errors.gpa, "must be {s}", .{kind.string});
        defer errors.gpa.free(message);
        try errors.add(path, message);
    };
    if (schema.object.get("const")) |constant| {
        if (constant != .string or value != .string or !std.mem.eql(u8, constant.string, value.string)) try errors.add(path, "must be equal to constant");
    }
    if (schema.object.get("pattern")) |pattern| if (value == .string) {
        if (!std.mem.eql(u8, pattern.string, "^[^/]+$")) return error.UnsupportedThemeSchema;
        if (value.string.len == 0 or std.mem.indexOfScalar(u8, value.string, '/') != null) try errors.add(path, "must match pattern \"^[^/]+$\"");
    };
    for ([_][]const u8{ "minimum", "maximum" }) |bound| if (schema.object.get(bound)) |limit| {
        const actual = number(value) orelse continue;
        const threshold = number(limit) orelse return error.UnsupportedThemeSchema;
        if (if (std.mem.eql(u8, bound, "minimum")) actual < threshold else actual > threshold) {
            const message = try std.fmt.allocPrint(errors.gpa, "must be {s} {d}", .{ if (std.mem.eql(u8, bound, "minimum")) ">=" else "<=", @as(i64, @intFromFloat(threshold)) });
            defer errors.gpa.free(message);
            try errors.add(path, message);
        }
    };
    if (value == .object) {
        if (schema.object.get("required")) |required| {
            var missing: std.ArrayList([]const u8) = .empty;
            defer missing.deinit(errors.gpa);
            for (required.array.items) |key| if (!value.object.contains(key.string)) try missing.append(errors.gpa, key.string);
            if (missing.items.len > 0) {
                if (std.mem.eql(u8, path, "/colors")) {
                    if (errors.count < 8) {
                        try errors.missing_colors.appendSlice(errors.gpa, missing.items);
                        errors.count += 1;
                    }
                } else {
                    const joined = try std.mem.join(errors.gpa, ", ", missing.items);
                    defer errors.gpa.free(joined);
                    const message = try std.fmt.allocPrint(errors.gpa, "must have required properties {s}", .{joined});
                    defer errors.gpa.free(message);
                    try errors.add(path, message);
                }
            }
        }
        const properties = schema.object.get("properties");
        const patterns = schema.object.get("patternProperties");
        var additional = false;
        var it = value.object.iterator();
        while (it.next()) |entry| {
            if (properties) |props| if (props.object.contains(entry.key_ptr.*)) continue;
            const child_path = try pointerAlloc(errors.gpa, path, entry.key_ptr.*);
            defer errors.gpa.free(child_path);
            if (patterns) |props| {
                var patterns_it = props.object.iterator();
                while (patterns_it.next()) |pattern| {
                    if (!std.mem.eql(u8, pattern.key_ptr.*, "^.*$")) return error.UnsupportedThemeSchema;
                    _ = try check(errors, pattern.value_ptr.*, entry.value_ptr.*, child_path);
                }
            } else if (schema.object.get("additionalProperties")) |rule| {
                if (!try check(errors, rule, entry.value_ptr.*, child_path)) additional = true;
            }
        }
        if (additional) try errors.add(path, "must not have additional properties");
        if (properties) |props| {
            var props_it = props.object.iterator();
            while (props_it.next()) |entry| if (value.object.get(entry.key_ptr.*)) |child| {
                const child_path = try pointerAlloc(errors.gpa, path, entry.key_ptr.*);
                defer errors.gpa.free(child_path);
                _ = try check(errors, entry.value_ptr.*, child, child_path);
            };
        }
    }
    return !errors.changed(before_lines, before_missing);
}

/// Null is valid. A non-null diagnostic is owned by the caller. JSON syntax
/// parsing is separate so callers retain the original file/parse-error context.
pub fn diagnosticAlloc(gpa: std.mem.Allocator, label: []const u8, value: Value) !?[]u8 {
    return diagnosticInner(gpa, label, value) catch |err| switch (err) {
        error.WriteFailed => error.OutOfMemory,
        else => err,
    };
}
fn diagnosticInner(gpa: std.mem.Allocator, label: []const u8, value: Value) !?[]u8 {
    if (value == .object) if (value.object.get("name")) |name| if (name == .string and std.mem.indexOfScalar(u8, name.string, '/') != null) {
        return try std.fmt.allocPrint(gpa, "Invalid theme name \"{s}\": theme names cannot contain \"/\" because it is reserved for automatic light/dark theme settings.", .{name.string});
    };
    const schema = try std.json.parseFromSlice(Value, gpa, @embedFile("fixtures/theme-schema-original-6fb.json"), .{});
    defer schema.deinit();
    var errors: Errors = .{ .gpa = gpa };
    defer errors.deinit();
    if (try check(&errors, schema.value, value, "")) return null;
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try out.writer.print("Invalid theme \"{s}\":\n", .{label});
    if (errors.missing_colors.items.len > 0) {
        std.mem.sort([]const u8, errors.missing_colors.items, {}, struct {
            fn less(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.less);
        try out.writer.writeAll("\nMissing required color tokens:\n");
        for (errors.missing_colors.items, 0..) |name, index| try out.writer.print("{s}  - {s}", .{ if (index == 0) "" else "\n", name });
        try out.writer.writeAll("\n\nPlease add these colors to your theme's \"colors\" object.\nSee the built-in themes (dark.json, light.json) for reference values.");
    }
    if (errors.lines.items.len > 0) {
        try out.writer.writeAll("\n\nOther errors:\n");
        for (errors.lines.items, 0..) |line, index| try out.writer.print("{s}{s}", .{ if (index == 0) "" else "\n", line });
    }
    return try out.toOwnedSlice();
}

test "native Source6fb Theme schema diagnostics exactly match actual TypeBox captures" {
    const fixture = try std.json.parseFromSlice(Value, std.testing.allocator, @embedFile("fixtures/theme-validation-original-6fb.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items) |item| {
        const actual = try diagnosticAlloc(std.testing.allocator, item.object.get("label").?.string, item.object.get("value").?);
        defer if (actual) |message| std.testing.allocator.free(message);
        try std.testing.expectEqual(item.object.get("ok").?.bool, actual == null);
        if (actual) |message| try std.testing.expectEqualStrings(item.object.get("message").?.string, message);
    }
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const parsed = try std.json.parseFromSlice(Value, gpa, "{\"name\":\"x\",\"colors\":{\"accent\":null,\"unknown\":1},\"export\":{\"extra\":true}}", .{});
    defer parsed.deinit();
    const message = try diagnosticAlloc(gpa, "failure", parsed.value);
    defer if (message) |text_| gpa.free(text_);
}
test "native Theme schema diagnostics release every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
