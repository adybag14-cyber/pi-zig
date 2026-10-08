//! Native Codemode declaration catalog and model-facing loadout preparation.
const std = @import("std");
const declarations = @import("codemode_declarations.zig");
const discovery = @import("codemode_discovery.zig");
const Value = std.json.Value;
const json = @import("protocol.zig").json;
pub const Mode = enum { on, only };
pub const Exposure = enum { direct, model_only, codemode, deferred };
pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    parameters: Value = .null,
    output_schema: ?Value = null,
    namespace: ?discovery.Namespace = null,
    guidelines: []const []const u8 = &.{},
    exposure: Exposure = .direct,
    declared: bool = false,
};
pub const Options = struct { models: bool = true, inline_budget: ?f64 = 3000, docs_path: []const u8 = "docs/codemode.md" };
const Entry = struct { tool: Tool, section: []const u8, cost: f64, shown: bool = false };
const Group = struct { namespace: ?discovery.Namespace, entries: std.ArrayList(Entry) = .empty };
fn units(text: []const u8) usize {
    var iterator = std.unicode.Wtf8View.initUnchecked(text).iterator();
    var count: usize = 0;
    while (iterator.nextCodepoint()) |point| count += if (point > 0xffff) @as(usize, 2) else 1;
    return count;
}
fn prose(a: std.mem.Allocator, tool: Tool) ![]const u8 {
    var bullets: std.ArrayList([]const u8) = .empty;
    for (tool.guidelines) |guideline| {
        const trimmed = declarations.trimJs(guideline);
        if (trimmed.len > 0) try bullets.append(a, try std.fmt.allocPrint(a, "- {s}", .{trimmed}));
    }
    return if (bullets.items.len == 0) tool.description else std.fmt.allocPrint(a, "{s}\n\n{s}", .{ declarations.trimJs(tool.description), try std.mem.join(a, "\n", bullets.items) });
}
fn textSchema(a: std.mem.Allocator) !Value {
    var object: std.json.ObjectMap = .empty;
    try object.put(a, "type", .{ .string = "string" });
    return .{ .object = object };
}
fn outputSchema(a: std.mem.Allocator, tool: Tool) !Value {
    return if (tool.output_schema) |schema| if (schema == .null) try textSchema(a) else schema else try textSchema(a);
}
fn section(a: std.mem.Allocator, tool: Tool) ![]const u8 {
    const id = try discovery.identifier(a, tool.name);
    const heading = if (std.mem.eql(u8, id, tool.name)) try std.fmt.allocPrint(a, "### `{s}`", .{id}) else try std.fmt.allocPrint(a, "### `{s}` (`{s}`)", .{ id, tool.name });
    return std.fmt.allocPrint(a, "{s}\n{s}", .{ heading, declarations.trimJs(try declarations.sample(a, tool.name, try prose(a, tool), tool.parameters, try outputSchema(a, tool))) });
}
fn arrayIndex(name: []const u8) ?u32 {
    if (name.len == 0 or (name.len > 1 and name[0] == '0')) return null;
    for (name) |byte| if (!std.ascii.isDigit(byte)) return null;
    const value = std.fmt.parseInt(u32, name, 10) catch return null;
    return if (value == std.math.maxInt(u32)) null else value;
}
fn objectKeys(a: std.mem.Allocator, object: std.json.ObjectMap) ![]const []const u8 {
    const keys = try a.alloc([]const u8, object.count());
    var indices: usize = 0;
    for (object.keys()) |name| if (arrayIndex(name) != null) {
        keys[indices] = name;
        indices += 1;
    };
    std.mem.sort([]const u8, keys[0..indices], {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return arrayIndex(left).? < arrayIndex(right).?;
        }
    }.less);
    var next = indices;
    for (object.keys()) |name| if (arrayIndex(name) == null) {
        keys[next] = name;
        next += 1;
    };
    return keys;
}
fn describeOutput(a: std.mem.Allocator, schema: Value) ![]const u8 {
    const rendered = try declarations.outputType(a, schema);
    if (std.mem.eql(u8, rendered, "string")) return "a string";
    if (schema == .object) {
        const kind = schema.object.get("type");
        const properties = schema.object.get("properties");
        if (kind != null and kind.? == .string and std.mem.eql(u8, kind.?.string, "object") and properties != null and properties.? == .object and !std.mem.startsWith(u8, rendered, "CallToolResult")) {
            var fields: std.ArrayList([]const u8) = .empty;
            for (try objectKeys(a, properties.?.object)) |name| {
                var required = false;
                if (schema.object.get("required")) |values| if (values == .array) for (values.array.items) |value| {
                    if (value == .string and std.mem.eql(u8, name, value.string)) required = true;
                };
                try fields.append(a, try std.fmt.allocPrint(a, "{s}{s}", .{ name, if (required) "" else "?" }));
            }
            return std.fmt.allocPrint(a, "`{{ {s} }}`", .{try std.mem.join(a, ", ", fields.items)});
        }
    }
    var collapsed: std.ArrayList(u8) = .empty;
    var iterator = std.unicode.Wtf8View.initUnchecked(rendered).iterator();
    var whitespace = false;
    while (iterator.nextCodepointSlice()) |part| {
        const space = declarations.trimJs(part).len == 0;
        if (!space) try collapsed.appendSlice(a, part) else if (!whitespace) try collapsed.append(a, ' ');
        whitespace = space;
    }
    return std.fmt.allocPrint(a, "`{s}`", .{collapsed.items});
}
pub fn prepare(gpa: std.mem.Allocator, tools: []const Tool, mode: Mode, options: Options) !json.Owned {
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    const a = result.arena.allocator();
    result.value = .{ .object = .empty };
    var descriptions: Value = .{ .object = .empty };
    var hidden: Value = .{ .array = .init(a) };
    var listed: std.ArrayList(Tool) = .empty;
    for (tools) |tool| {
        if (std.mem.eql(u8, tool.name, "codemode")) continue;
        if (mode == .on and tool.declared) {
            const text = try std.fmt.allocPrint(a, "{s}\n\nCodemode: `tools.{s}(args)` resolves to {s}.", .{ declarations.trimJs(tool.description), try discovery.identifier(a, tool.name), try describeOutput(a, try outputSchema(a, tool)) });
            try descriptions.object.put(a, tool.name, .{ .string = text });
        }
        if (mode == .only or tool.exposure != .direct) try listed.append(a, tool);
        if (mode == .only and tool.exposure == .direct and tool.declared) try hidden.array.append(.{ .string = tool.name });
    }
    const text = try description(a, listed.items, options);
    try descriptions.object.put(a, "codemode", .{ .string = text });
    try result.value.object.put(a, "descriptions", descriptions);
    try result.value.object.put(a, "hiddenDeclarations", hidden);
    return result;
}
// MCP namespaces have a restricted ASCII alphabet. Locale-sensitive custom
// namespaces remain an explicit integration boundary until collation is bound.
fn namespaceSupported(name: []const u8) bool {
    for (name) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '-') return false;
    return true;
}
fn primary(byte: u8) u16 {
    return switch (byte) {
        '_' => 1,
        '-' => 2,
        '0'...'9' => 10 + @as(u16, byte - '0'),
        'a'...'z' => 30 + @as(u16, byte - 'a'),
        'A'...'Z' => 30 + @as(u16, byte - 'A'),
        else => 0,
    };
}
fn namespaceLess(left: []const u8, right: []const u8) bool {
    for (left[0..@min(left.len, right.len)], right[0..@min(left.len, right.len)]) |a, b| {
        if (primary(a) != primary(b)) return primary(a) < primary(b);
    }
    if (left.len != right.len) return left.len < right.len;
    for (left, right) |a, b| if (a != b) return std.ascii.isLower(a);
    return false;
}
pub fn description(gpa: std.mem.Allocator, tools: []const Tool, options: Options) ![]u8 {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try std.json.parseFromSlice(Value, a, @embedFile("fixtures/codemode-description-base-original-6fb.json"), .{});
    const template = fixture.value.object.get(if (options.models) "withModels" else "withoutModels").?.string;
    const base = try std.mem.replaceOwned(u8, a, template, fixture.value.object.get("docsPath").?.string, options.docs_path);
    var groups: std.ArrayList(Group) = .empty;
    try groups.append(a, .{ .namespace = null });
    var count: usize = 0;
    for (tools) |tool| {
        if (std.mem.eql(u8, tool.name, "codemode") or tool.exposure == .deferred) continue;
        var group_index: usize = 0;
        if (tool.namespace) |namespace| {
            if (!namespaceSupported(namespace.name)) return error.UnsupportedCodemodeNamespaceCollation;
            var existing: ?usize = null;
            for (groups.items, 0..) |group, index| if (group.namespace) |value| if (std.mem.eql(u8, namespace.name, value.name)) {
                existing = index;
                break;
            };
            group_index = existing orelse groups.items.len;
            if (existing == null) try groups.append(a, .{ .namespace = namespace });
        }
        const rendered = try section(a, tool);
        try groups.items[group_index].entries.append(a, .{ .tool = tool, .section = rendered, .cost = @ceil(@as(f64, @floatFromInt(units(rendered))) / 4) });
        count += 1;
    }
    std.mem.sort(Group, groups.items, {}, struct {
        fn less(_: void, left: Group, right: Group) bool {
            if (left.namespace == null) return right.namespace != null;
            if (right.namespace == null) return false;
            return namespaceLess(left.namespace.?.name, right.namespace.?.name);
        }
    }.less);
    if (count == 0) return gpa.dupe(u8, base);
    var queues: std.ArrayList([]usize) = .empty;
    for (groups.items) |group| {
        const order = try a.alloc(usize, group.entries.items.len);
        for (order, 0..) |*index, value| index.* = value;
        std.mem.sort(usize, order, group.entries.items, struct {
            fn less(entries: []Entry, left: usize, right: usize) bool {
                return entries[left].cost < entries[right].cost or (entries[left].cost == entries[right].cost and left < right);
            }
        }.less);
        try queues.append(a, order);
    }
    const positions = try a.alloc(usize, groups.items.len);
    @memset(positions, 0);
    const active = try a.alloc(bool, groups.items.len);
    @memset(active, true);
    var remaining = options.inline_budget orelse std.math.inf(f64);
    var progressed = true;
    while (progressed) {
        progressed = false;
        for (groups.items, queues.items, positions, active) |*group, queue, *position, *enabled| {
            if (!enabled.* or position.* >= queue.len) continue;
            const entry = &group.entries.items[queue[position.*]];
            if (entry.cost > remaining) {
                enabled.* = false;
                continue;
            }
            entry.shown = true;
            remaining -= entry.cost;
            position.* += 1;
            progressed = true;
        }
    }
    var parts: std.ArrayList([]const u8) = .empty;
    try parts.append(a, base);
    var mcp = false;
    for (groups.items) |group| for (group.entries.items) |entry| if (entry.shown) {
        const output = try declarations.outputType(a, entry.tool.output_schema);
        mcp = mcp or std.mem.startsWith(u8, output, "CallToolResult");
    };
    if (mcp) try parts.append(a, try std.fmt.allocPrint(a, "Shared MCP Types:\n```ts\n{s}\n```", .{declarations.mcp_typescript_preamble}));
    try parts.append(a, "Nested tools:");
    for (groups.items) |group| {
        var visible: usize = 0;
        for (group.entries.items) |entry| if (entry.shown) {
            visible += 1;
        };
        if (group.namespace) |namespace| {
            const listing: []const u8 = if (visible == group.entries.items.len) "" else if (visible == 0) " (tools not listed)" else " (some tools not listed)";
            const text = declarations.trimJs(namespace.description);
            try parts.append(a, try std.fmt.allocPrint(a, "## {s}{s}{s}{s}", .{ namespace.name, listing, if (text.len > 0) "\n" else "", text }));
        }
        for (group.entries.items) |entry| if (entry.shown) try parts.append(a, entry.section);
    }
    return std.mem.join(gpa, "\n\n", parts.items);
}
test "native codemode loadout descriptions replay original MCP types namespaces guidelines and budgets" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try std.json.parseFromSlice(Value, a, @embedFile("fixtures/codemode-loadout-original-6fb.json"), .{});
    const root = fixture.value.object;
    const source_tools = root.get("tools").?.array.items;
    const tools = try a.alloc(Tool, source_tools.len);
    const info = root.get("namespace").?.object;
    const guidelines = root.get("guidelines").?.object;
    for (source_tools, tools) |value, *tool| {
        const name = value.object.get("name").?.string;
        var rows: std.ArrayList([]const u8) = .empty;
        if (guidelines.get(name)) |values| for (values.array.items) |item| try rows.append(a, item.string);
        tool.* = .{ .name = name, .description = value.object.get("description").?.string, .parameters = value.object.get("parameters").?, .output_schema = value.object.get("outputSchema"), .guidelines = rows.items, .exposure = if (std.mem.eql(u8, name, "notes-long")) .deferred else .direct, .namespace = if (std.mem.startsWith(u8, name, "mcp__")) .{ .name = info.get("name").?.string, .description = info.get("description").?.string, .instructions = info.get("instructions").?.string } else null };
    }
    for (root.get("descriptionRows").?.array.items) |row| {
        const budget = row.object.get("inlineBudget").?;
        const value = try description(gpa, tools, .{ .models = true, .inline_budget = if (budget == .null) null else @floatFromInt(budget.integer), .docs_path = root.get("docsPath").?.string });
        defer gpa.free(value);
        try std.testing.expectEqualStrings(row.object.get("result").?.string, value);
    }
}
test "native codemode loadout on and only prepare exact Source descriptions and hidden declarations" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try std.json.parseFromSlice(Value, a, @embedFile("fixtures/codemode-loadout-original-6fb.json"), .{});
    const root = fixture.value.object;
    const source_tools = root.get("tools").?.array.items;
    const tools = try a.alloc(Tool, source_tools.len);
    const info = root.get("namespace").?.object;
    const guidelines = root.get("guidelines").?.object;
    for (source_tools, tools) |value, *tool| {
        const name = value.object.get("name").?.string;
        var rows: std.ArrayList([]const u8) = .empty;
        if (guidelines.get(name)) |values| for (values.array.items) |item| try rows.append(a, item.string);
        const exposure = root.get("exposures").?.object.get(name).?.string;
        tool.* = .{ .name = name, .description = value.object.get("description").?.string, .parameters = value.object.get("parameters").?, .output_schema = value.object.get("outputSchema"), .guidelines = rows.items, .declared = std.mem.eql(u8, name, "read") or std.mem.eql(u8, name, "codemode"), .exposure = if (std.mem.eql(u8, exposure, "model-only")) .model_only else std.meta.stringToEnum(Exposure, exposure).?, .namespace = if (std.mem.startsWith(u8, name, "mcp__")) .{ .name = info.get("name").?.string, .description = info.get("description").?.string, .instructions = info.get("instructions").?.string } else null };
    }
    for (root.get("rows").?.array.items) |row| {
        var result = try prepare(gpa, tools, std.meta.stringToEnum(Mode, row.object.get("mode").?.string).?, .{ .inline_budget = @floatFromInt(row.object.get("inlineBudget").?.integer), .docs_path = root.get("docsPath").?.string });
        defer result.deinit();
        if (!json.equal(row.object.get("changes").?, result.value)) {
            std.debug.print("Original:\n{s}\nNative:\n{s}\n", .{ try json.stringify(a, row.object.get("changes").?), try json.stringify(a, result.value) });
            return error.OriginalLoadoutMismatch;
        }
    }
}
test "native codemode loadout namespace fair catalog matches Source ASCII collation cheapest rounds and omissions" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try std.json.parseFromSlice(Value, a, @embedFile("fixtures/codemode-catalog-groups-original-6fb.json"), .{});
    const root = fixture.value.object;
    const source_tools = root.get("tools").?.array.items;
    const tools = try a.alloc(Tool, source_tools.len);
    for (source_tools, tools) |value, *tool| {
        const name = value.object.get("name").?.string;
        const info = root.get("namespaces").?.object.get(name);
        tool.* = .{ .name = name, .description = value.object.get("description").?.string, .parameters = value.object.get("parameters").?, .namespace = if (info) |namespace| .{ .name = namespace.object.get("name").?.string, .description = namespace.object.get("description").?.string } else null };
    }
    for (root.get("rows").?.array.items) |row| {
        const value = try description(gpa, tools, .{ .models = false, .inline_budget = @floatFromInt(row.object.get("inlineBudget").?.integer) });
        defer gpa.free(value);
        try std.testing.expectEqualStrings(row.object.get("result").?.string, value);
    }
}
test "native codemode loadout allocation failures release description maps fair queues schemas and groups" {
    const Check = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const schema = try std.json.parseFromSlice(Value, gpa, "{\"type\":\"object\",\"properties\":{\"x\":{\"type\":\"string\",\"description\":\"Input\\nvalue\"}},\"required\":[\"x\"]}", .{});
            defer schema.deinit();
            var value = try prepare(gpa, &.{ .{ .name = "read", .description = "Read", .parameters = schema.value, .declared = true }, .{ .name = "mcp__b__lookup", .description = "Find records", .parameters = schema.value, .namespace = .{ .name = "mcp__b", .description = " Group B " }, .exposure = .codemode, .guidelines = &.{ " Use exact ids ", "" } }, .{ .name = "mcp__a__lookup", .description = "Find more", .parameters = schema.value, .namespace = .{ .name = "mcp__a" }, .exposure = .codemode } }, .only, .{ .inline_budget = 100 });
            defer value.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}

test "native codemode loadout output property summaries preserve Source numeric index ordering" {
    const gpa = std.testing.allocator;
    var fixture = try json.Owned.parse(gpa, @embedFile("fixtures/codemode-output-property-order-original-6fb.json"));
    defer fixture.deinit();
    for (fixture.value.object.get("rows").?.array.items) |row| {
        var schema = try json.Owned.parse(gpa, row.object.get("raw").?.string);
        defer schema.deinit();
        var result = try prepare(gpa, &.{.{ .name = "data", .description = "Produce data", .parameters = .{ .object = .empty }, .output_schema = schema.value, .declared = true }}, .on, .{ .models = false });
        defer result.deinit();
        try std.testing.expectEqualStrings(row.object.get("description").?.string, result.value.object.get("descriptions").?.object.get("data").?.string);
    }
}
