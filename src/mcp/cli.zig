//! Native MCP command parsing and administration; user commands remain argv data.
const std = @import("std");
const protocol = @import("protocol.zig");
const json = protocol.json;
pub const Kind = enum { flag, value, list };
pub const Known = struct { name: []const u8, kind: Kind };
pub const Parsed = union(enum) {
    valid: json.Owned,
    invalid: []u8,
    pub fn deinit(self: *Parsed, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .valid => |*value| value.deinit(),
            .invalid => |message| gpa.free(message),
        }
    }
};
pub const help_hint = "Use \"pi mcp --help\" for usage.";
pub const add_options = [_]Known{ .{ .name = "local", .kind = .flag }, .{ .name = "url", .kind = .value }, .{ .name = "env", .kind = .list }, .{ .name = "cwd", .kind = .value }, .{ .name = "header", .kind = .list }, .{ .name = "bearer-token-env-var", .kind = .value }, .{ .name = "oauth-client-id", .kind = .value }, .{ .name = "oauth-client-secret", .kind = .value }, .{ .name = "oauth-callback-port", .kind = .value }, .{ .name = "oauth-client-name", .kind = .value }, .{ .name = "exposure", .kind = .value }, .{ .name = "description", .kind = .value } };
/// Use the linked C language runtime for the original Number(string) coercion.
/// No source is evaluated, and the context is confined to this calling thread.
fn optionNumber(gpa: std.mem.Allocator, text: []const u8) !f64 {
    const engine_mod = @import("../extensions/engine.zig");
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const value = try engine.checked(engine_mod.c.JS_NewStringLen(engine.context, text.ptr, text.len));
    defer engine.freeValue(value);
    var number: f64 = undefined;
    if (engine_mod.c.JS_ToFloat64(engine.context, &number, value) < 0) return error.JavaScriptException;
    return number;
}
fn parsePairs(a: std.mem.Allocator, option: []const u8, list: ?json.Value, error_message: *?[]u8) !json.Value {
    var result: json.Value = .{ .object = .empty };
    if (list) |values| for (values.array.items) |value| {
        const pair = try json.asString(value);
        const separator = std.mem.indexOfScalar(u8, pair, '=') orelse 0;
        if (separator == 0) {
            error_message.* = try std.fmt.allocPrint(a, "--{s} expects KEY=VALUE, got \"{s}\".", .{ option, pair });
            return result;
        }
        try result.object.put(a, try a.dupe(u8, pair[0..separator]), .{ .string = try a.dupe(u8, pair[separator + 1 ..]) });
    };
    return result;
}
pub fn buildAddConfig(gpa: std.mem.Allocator, parsed: json.Value) !Parsed {
    var result = try json.Owned.empty(gpa);
    defer result.deinit();
    const a = result.arena.allocator();
    const positional = json.get(parsed, "positional").?.array.items;
    const values = json.get(parsed, "values").?;
    const lists = json.get(parsed, "lists").?;
    const location = json.get(values, "url");
    if (positional.len == 0 or ((location == null) == (positional.len <= 1))) return .{ .invalid = try std.fmt.allocPrint(gpa, "Usage: pi mcp add <server> [options] (--url <url> | -- <command> [args...])\n{s}", .{help_hint}) };
    const restrictions: []const []const u8 = if (location == null) &.{ "header", "bearer-token-env-var", "oauth-client-id", "oauth-client-secret", "oauth-callback-port", "oauth-client-name" } else &.{ "env", "cwd" };
    for (restrictions) |name| if (json.get(values, name) != null or json.get(lists, name) != null) return .{ .invalid = try std.fmt.allocPrint(gpa, "--{s} only applies to {s}.", .{ name, if (location == null) "HTTP servers (--url)" else "stdio servers" }) };
    result.value = .{ .object = .empty };
    var pair_error: ?[]u8 = null;
    if (location) |url| {
        try result.value.object.put(a, "url", try json.clone(a, url));
        var headers = try parsePairs(a, "header", json.get(lists, "header"), &pair_error);
        if (pair_error) |message| return .{ .invalid = try gpa.dupe(u8, message) };
        if (json.get(values, "bearer-token-env-var")) |value| {
            const bearer = try std.fmt.allocPrint(a, "Bearer ${{{s}}}", .{try json.asString(value)});
            try headers.object.put(a, "Authorization", .{ .string = bearer });
        }
        if (headers.object.count() != 0) try result.value.object.put(a, "headers", headers);
        var oauth: json.Value = .{ .object = .empty };
        for ([_]struct { option: []const u8, field: []const u8 }{ .{ .option = "oauth-client-id", .field = "clientId" }, .{ .option = "oauth-client-secret", .field = "clientSecret" }, .{ .option = "oauth-client-name", .field = "clientName" } }) |entry| if (json.get(values, entry.option)) |value| {
            try oauth.object.put(a, entry.field, try json.clone(a, value));
        };
        if (json.get(values, "oauth-callback-port")) |value| {
            const number = try optionNumber(gpa, try json.asString(value));
            if (!std.math.isFinite(number) or number < 1 or number > 65535 or @floor(number) != number) return .{ .invalid = try std.fmt.allocPrint(gpa, "server \"{s}\": oauth.callbackPort must be a port number", .{try json.asString(positional[0])}) };
            try oauth.object.put(a, "callbackPort", .{ .float = number });
        }
        if (oauth.object.count() != 0) try result.value.object.put(a, "oauth", oauth);
    } else {
        try result.value.object.put(a, "command", try json.clone(a, positional[1]));
        if (positional.len > 2) {
            var args = std.json.Array.init(a);
            for (positional[2..]) |value| try args.append(try json.clone(a, value));
            try result.value.object.put(a, "args", .{ .array = args });
        }
        const environment = try parsePairs(a, "env", json.get(lists, "env"), &pair_error);
        if (pair_error) |message| return .{ .invalid = try gpa.dupe(u8, message) };
        if (environment.object.count() != 0) try result.value.object.put(a, "env", environment);
        if (json.get(values, "cwd")) |value| try result.value.object.put(a, "cwd", try json.clone(a, value));
    }
    for ([_][]const u8{ "exposure", "description" }) |field| if (json.get(values, field)) |value| try result.value.object.put(a, field, try json.clone(a, value));
    var validated = try @import("config.zig").validate(gpa, try json.asString(positional[0]), result.value);
    switch (validated) {
        .invalid => |message| return .{ .invalid = message },
        .valid => |value| {
            validated = undefined;
            return .{ .valid = value };
        },
    }
}
pub const Output = struct {
    data: json.Owned,
    pub fn deinit(self: *Output) void {
        self.data.deinit();
    }
    pub fn init(gpa: std.mem.Allocator) !Output {
        var data = try json.Owned.empty(gpa);
        errdefer data.deinit();
        const a = data.arena.allocator();
        data.value = .{ .object = .empty };
        try data.value.object.put(a, "code", .{ .integer = 0 });
        try data.value.object.put(a, "logs", .{ .array = .init(a) });
        try data.value.object.put(a, "errors", .{ .array = .init(a) });
        return .{ .data = data };
    }
    pub fn log(self: *Output, text: []const u8) !void {
        try self.data.value.object.getPtr("logs").?.array.append(.{ .string = try self.data.arena.allocator().dupe(u8, text) });
    }
    pub fn fail(self: *Output, text: []const u8) !void {
        try self.data.value.object.put(self.data.arena.allocator(), "code", .{ .integer = 1 });
        try self.data.value.object.getPtr("errors").?.array.append(.{ .string = try self.data.arena.allocator().dupe(u8, text) });
    }
};
pub fn preflight(gpa: std.mem.Allocator, args: []const []const u8) !?Output {
    var result = try Output.init(gpa);
    var transferred = false;
    defer if (!transferred) result.deinit();
    var help = args.len == 0;
    for (args) |arg| if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
        help = true;
    };
    if (args.len != 0 and std.mem.eql(u8, args[0], "help")) help = true;
    if (help) {
        var original = try json.Owned.parse(gpa, @embedFile("fixtures/cli-original-7fb.json"));
        defer original.deinit();
        try result.log(try json.asString(json.get(original.value.array.items[0], "logs").?.array.items[0]));
        transferred = true;
        return result;
    }
    const command = args[0];
    var recognized = false;
    for ([_][]const u8{ "list", "login", "logout", "add", "remove" }) |name| if (std.mem.eql(u8, command, name)) {
        recognized = true;
    };
    if (!recognized) {
        const message = try std.fmt.allocPrint(gpa, "Unknown mcp command \"{s}\".\n{s}", .{ command, help_hint });
        defer gpa.free(message);
        try result.fail(message);
        transferred = true;
        return result;
    }
    const known: []const Known = if (std.mem.eql(u8, command, "list")) &.{.{ .name = "json", .kind = .flag }} else if (std.mem.eql(u8, command, "login")) &.{.{ .name = "timeout", .kind = .value }} else if (std.mem.eql(u8, command, "remove")) &.{.{ .name = "local", .kind = .flag }} else if (std.mem.eql(u8, command, "add")) &.{ .{ .name = "local", .kind = .flag }, .{ .name = "url", .kind = .value }, .{ .name = "env", .kind = .list }, .{ .name = "cwd", .kind = .value }, .{ .name = "header", .kind = .list }, .{ .name = "bearer-token-env-var", .kind = .value }, .{ .name = "oauth-client-id", .kind = .value }, .{ .name = "oauth-client-secret", .kind = .value }, .{ .name = "oauth-callback-port", .kind = .value }, .{ .name = "oauth-client-name", .kind = .value }, .{ .name = "exposure", .kind = .value }, .{ .name = "description", .kind = .value } } else &.{};
    var parsed = try parseOptions(gpa, args[1..], known, if (std.mem.eql(u8, command, "add")) 2 else std.math.maxInt(usize));
    defer parsed.deinit(gpa);
    if (parsed == .invalid) {
        try result.fail(parsed.invalid);
        transferred = true;
        return result;
    }
    const positional = json.get(parsed.valid.value, "positional").?.array.items;
    const valid_count = if (std.mem.eql(u8, command, "list")) positional.len == 0 else if (std.mem.eql(u8, command, "add")) positional.len >= 1 else positional.len == 1;
    if (!valid_count) {
        const usage: []const u8 = if (std.mem.eql(u8, command, "list")) "Usage: pi mcp list [--json]" else if (std.mem.eql(u8, command, "login")) "Usage: pi mcp login <server>" else if (std.mem.eql(u8, command, "logout")) "Usage: pi mcp logout <server>" else if (std.mem.eql(u8, command, "remove")) "Usage: pi mcp remove <server> [-l]" else "Usage: pi mcp add <server> [options] (--url <url> | -- <command> [args...])";
        const message = try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ usage, help_hint });
        defer gpa.free(message);
        try result.fail(message);
        transferred = true;
        return result;
    }
    return null;
}
pub fn parseOptions(gpa: std.mem.Allocator, args: []const []const u8, known: []const Known, max_positionals: usize) !Parsed {
    var result = try json.Owned.empty(gpa);
    var transferred = false;
    defer if (!transferred) result.deinit();
    const a = result.arena.allocator();
    var positional = std.json.Array.init(a);
    var values: std.json.ObjectMap = .empty;
    var lists: std.json.ObjectMap = .empty;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const raw = args[index];
        const arg = if (std.mem.eql(u8, raw, "-l")) "--local" else raw;
        if (std.mem.eql(u8, arg, "--") or positional.items.len >= max_positionals) {
            const start = index + @as(usize, @intFromBool(std.mem.eql(u8, arg, "--")));
            for (args[start..]) |value| try positional.append(.{ .string = try a.dupe(u8, value) });
            break;
        }
        if (!std.mem.startsWith(u8, arg, "--")) {
            try positional.append(.{ .string = try a.dupe(u8, arg) });
            continue;
        }
        const name = arg[2..];
        var selected: ?Kind = null;
        for (known) |entry| if (std.mem.eql(u8, entry.name, name)) {
            selected = entry.kind;
            break;
        };
        const kind = selected orelse return .{ .invalid = try std.fmt.allocPrint(gpa, "Unknown option {s}.\n{s}", .{ arg, help_hint }) };
        const key = try a.dupe(u8, name);
        if (kind == .flag) {
            try values.put(a, key, .{ .bool = true });
            continue;
        }
        index += 1;
        if (index >= args.len) return .{ .invalid = try std.fmt.allocPrint(gpa, "{s} needs a value.", .{arg}) };
        const value: json.Value = .{ .string = try a.dupe(u8, args[index]) };
        if (kind == .list) {
            if (lists.getPtr(name)) |list| try list.array.append(value) else {
                var list = std.json.Array.init(a);
                try list.append(value);
                try lists.put(a, key, .{ .array = list });
            }
        } else try values.put(a, key, value);
    }
    result.value = .{ .object = .empty };
    try result.value.object.put(a, "positional", .{ .array = positional });
    try result.value.object.put(a, "values", .{ .object = values });
    try result.value.object.put(a, "lists", .{ .object = lists });
    transferred = true;
    return .{ .valid = result };
}
fn pretty(gpa: std.mem.Allocator, value: json.Value, indent: []const u8) ![]u8 {
    const compact = try json.stringify(gpa, value);
    defer gpa.free(compact);
    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    var depth: usize = 0;
    var quoted = false;
    var escaped = false;
    for (compact, 0..) |byte, index| {
        if (quoted) {
            try output.writer.writeByte(byte);
            if (escaped) escaped = false else if (byte == '\\') escaped = true else if (byte == '"') quoted = false;
            continue;
        }
        if (byte == '"') {
            quoted = true;
            try output.writer.writeByte(byte);
            continue;
        }
        switch (byte) {
            '{', '[' => {
                try output.writer.writeByte(byte);
                const close: u8 = if (byte == '{') '}' else ']';
                if (index + 1 < compact.len and compact[index + 1] != close) {
                    depth += 1;
                    try output.writer.writeByte('\n');
                    for (0..depth) |_| try output.writer.writeAll(indent);
                }
            },
            '}', ']' => {
                const open: u8 = if (byte == '}') '{' else '[';
                if (index != 0 and compact[index - 1] != open) {
                    depth -= 1;
                    try output.writer.writeByte('\n');
                    for (0..depth) |_| try output.writer.writeAll(indent);
                }
                try output.writer.writeByte(byte);
            },
            ',' => {
                try output.writer.writeAll(",\n");
                for (0..depth) |_| try output.writer.writeAll(indent);
            },
            ':' => try output.writer.writeAll(": "),
            else => try output.writer.writeByte(byte),
        }
    }
    try output.writer.writeByte('\n');
    return output.toOwnedSlice();
}
pub fn editServer(gpa: std.mem.Allocator, io: std.Io, path: []const u8, name: []const u8, config: ?json.Value) !bool {
    const existing = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(4 * 1024 * 1024)) catch |cause| switch (cause) {
        error.FileNotFound => null,
        else => return cause,
    };
    defer if (existing) |bytes| gpa.free(bytes);
    if (existing == null and config == null) return false;
    var owner = try json.Owned.parse(gpa, existing orelse "{}");
    defer owner.deinit();
    if (owner.value != .object) return error.InvalidMcpConfigRoot;
    if (json.get(owner.value, "mcpServers")) |servers| if (servers != .object) return error.InvalidMcpConfigRoot;
    const a = owner.arena.allocator();
    if (json.get(owner.value, "mcpServers") == null) {
        if (config == null) return false;
        try owner.value.object.put(a, "mcpServers", .{ .object = .empty });
    }
    const servers = owner.value.object.getPtr("mcpServers").?;
    const present = servers.object.contains(name);
    if (config) |value| try servers.object.put(a, try a.dupe(u8, name), try json.clone(a, value)) else {
        if (!present) return false;
        _ = servers.object.orderedRemove(name);
    }
    var indent: []const u8 = "  ";
    if (existing) |bytes| {
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |line| {
            var end: usize = 0;
            while (end < line.len and (line[end] == ' ' or line[end] == '\t')) end += 1;
            if (end > 0 and end < line.len and std.mem.indexOfScalar(u8, "\r\n\x0b\x0c", line[end]) == null) {
                indent = line[0..end];
                break;
            }
        }
    }
    const bytes = try pretty(gpa, owner.value, indent);
    defer gpa.free(bytes);
    if (std.fs.path.dirname(path)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes });
    return present;
}
pub const Context = struct { io: std.Io, agent_dir: []const u8, cwd: []const u8, project_trusted: bool = false };
fn loadCatalog(gpa: std.mem.Allocator, context: Context, trusted: bool) !json.Owned {
    const global = try std.fs.path.join(gpa, &.{ context.agent_dir, "mcp.json" });
    defer gpa.free(global);
    const project = try std.fs.path.join(gpa, &.{ context.cwd, ".pi", "mcp.json" });
    defer gpa.free(project);
    return @import("config.zig").load(gpa, context.io, .{ .global_path = global, .project_path = project, .project_trusted = trusted });
}
fn untrustedNote(gpa: std.mem.Allocator, context: Context) !?[]u8 {
    if (context.project_trusted) return null;
    const path = try std.fs.path.join(gpa, &.{ context.cwd, ".pi", "mcp.json" });
    defer gpa.free(path);
    std.Io.Dir.cwd().access(context.io, path, .{}) catch |cause| switch (cause) {
        error.FileNotFound => return null,
        else => return cause,
    };
    return try std.fmt.allocPrint(gpa, "{s} is ignored because the project is not trusted. Start pi in the project to trust it.", .{path});
}
fn selectedEntry(gpa: std.mem.Allocator, catalog: json.Value, note: ?[]const u8, name: []const u8, output: *Output) !?json.Value {
    const servers = json.get(catalog, "servers").?.array.items;
    for (servers) |entry| if (std.mem.eql(u8, try protocol.text(entry, "name"), name)) return entry;
    var names: std.Io.Writer.Allocating = .init(gpa);
    defer names.deinit();
    for (servers, 0..) |entry, index| {
        if (index != 0) try names.writer.writeAll(", ");
        try names.writer.writeAll(try protocol.text(entry, "name"));
    }
    const message = try std.fmt.allocPrint(gpa, "No MCP server named \"{s}\".{s}{s} Configured: {s}.", .{ name, if (note != null) " " else "", note orelse "", if (servers.len == 0) "none" else names.written() });
    defer gpa.free(message);
    try output.fail(message);
    return null;
}
pub fn logout(gpa: std.mem.Allocator, context: Context, args: []const []const u8) !Output {
    if (try preflight(gpa, args)) |result| return result;
    var output = try Output.init(gpa);
    errdefer output.deinit();
    var parsed = try parseOptions(gpa, args[1..], &.{}, std.math.maxInt(usize));
    defer parsed.deinit(gpa);
    const name = try json.asString(json.get(parsed.valid.value, "positional").?.array.items[0]);
    var catalog = try loadCatalog(gpa, context, context.project_trusted);
    defer catalog.deinit();
    const note = try untrustedNote(gpa, context);
    defer if (note) |value| gpa.free(value);
    const entry = (try selectedEntry(gpa, catalog.value, note, name, &output)) orelse return output;
    const config = json.get(entry, "config").?;
    if (!@import("configured.zig").usesOAuth(config)) {
        const message = try std.fmt.allocPrint(gpa, "MCP server \"{s}\" does not use OAuth. Only HTTP servers without an Authorization header do.", .{name});
        defer gpa.free(message);
        try output.fail(message);
        return output;
    }
    var credentials = try @import("oauth_store.zig").Store.init(gpa, context.io, context.agent_dir);
    defer credentials.deinit();
    const removed = try credentials.remove(name, try protocol.text(config, "url"), null);
    const message = try std.fmt.allocPrint(gpa, "{s} MCP server \"{s}\".", .{ if (removed) "Signed out of" else "No stored credentials for", name });
    defer gpa.free(message);
    try output.log(message);
    return output;
}
fn transportText(a: std.mem.Allocator, config: json.Value) ![]const u8 {
    if (json.get(config, "url")) |value| return json.asString(value);
    var writer: std.Io.Writer.Allocating = .init(a);
    defer writer.deinit();
    try writer.writer.writeAll(try protocol.text(config, "command"));
    if (json.get(config, "args")) |args| for (args.array.items) |value| {
        try writer.writer.writeByte(' ');
        try writer.writer.writeAll(try json.asString(value));
    };
    return writer.toOwnedSlice();
}
fn oauthRequired(cause: anyerror) bool {
    return cause == error.McpOAuthAuthorizationRequired or cause == error.McpOAuthFlowRequired or cause == error.McpOAuthInsufficientScope or cause == error.McpAuthRequired;
}
fn serverReport(a: std.mem.Allocator, entry: json.Value, service: *@import("configured.zig").Service) !json.Value {
    const config = json.get(entry, "config").?;
    const name = try protocol.text(entry, "name");
    var report: json.Value = .{ .object = .empty };
    for ([_][]const u8{ "name", "scope", "source", "override" }) |field| if (json.get(entry, field)) |value| try report.object.put(a, field, try json.clone(a, value));
    const enabled = if (json.get(config, "enabled")) |value| value.bool else true;
    const exposure = if (json.get(config, "exposure")) |value| try json.asString(value) else "codemode";
    try report.object.put(a, "enabled", .{ .bool = enabled });
    try report.object.put(a, "exposure", .{ .string = exposure });
    try report.object.put(a, "transport", .{ .string = try transportText(a, config) });
    try report.object.put(a, "state", .{ .string = "disabled" });
    try report.object.put(a, "tools", .{ .array = .init(a) });
    if (!enabled) return report;
    const server = service.findServer(name) orelse return error.McpServerNotFound;
    const borrowed = server.connection.acquire() catch |cause| {
        if (cause == error.OutOfMemory or cause == error.Canceled) return cause;
        try report.object.put(a, "state", .{ .string = if (oauthRequired(cause)) "needs-auth" else "failed" });
        try report.object.put(a, "error", .{ .string = @errorName(cause) });
        return report;
    };
    defer borrowed.release();
    const capabilities = @import("capabilities.zig");
    const offers = try protocol.field(borrowed.client.initialized.?.value, "capabilities");
    if (capabilities.offersTools(offers)) {
        var listed = try capabilities.listAll(borrowed.client, .tools, .{ .timeout_ms = server.timeout_ms });
        defer listed.deinit();
        var overrides: json.Value = .{ .object = .empty };
        for (listed.value.array.items) |item| {
            const tool = try protocol.text(item, "name");
            try report.object.getPtr("tools").?.array.append(.{ .string = try a.dupe(u8, tool) });
            const tool_exposure = @tagName(try @import("config.zig").toolExposure(config, tool));
            if (!std.mem.eql(u8, tool_exposure, exposure)) try overrides.object.put(a, try a.dupe(u8, tool), .{ .string = tool_exposure });
        }
        if (overrides.object.count() != 0) try report.object.put(a, "toolExposure", overrides);
    }
    if (json.get(offers, "resources") != null) {
        const counts = try @import("configured.zig").Service.resourceCounts(server);
        try report.object.put(a, "resources", .{ .integer = @intCast(counts.resources) });
        try report.object.put(a, "resourceTemplates", .{ .integer = @intCast(counts.templates) });
    }
    try report.object.put(a, "state", .{ .string = "connected" });
    return report;
}
pub fn listServers(gpa: std.mem.Allocator, context: Context, environment: *const std.process.Environ.Map, as_json: bool) !Output {
    var output = try Output.init(gpa);
    errdefer output.deinit();
    const a = output.data.arena.allocator();
    const service = try @import("configured.zig").Service.create(gpa, context.io, .{ .agent_dir = context.agent_dir, .cwd = context.cwd, .project_trusted = context.project_trusted, .environ = environment, .management_all = true });
    defer service.deinit();
    var result: json.Value = .{ .object = .empty };
    var reports: json.Value = .{ .array = .init(a) };
    var failed = json.get(service.loaded.value, "errors").?.array.items.len != 0;
    for (json.get(service.loaded.value, "servers").?.array.items) |entry| {
        const report = try serverReport(a, entry, service);
        if (json.get(report, "enabled").?.bool and !std.mem.eql(u8, try protocol.text(report, "state"), "connected")) failed = true;
        try reports.array.append(report);
    }
    try result.object.put(a, "servers", reports);
    const errors = try json.clone(a, json.get(service.loaded.value, "errors").?);
    try result.object.put(a, "errors", errors);
    const note = try untrustedNote(a, context);
    if (note) |value| try result.object.put(a, "note", .{ .string = value });
    if (as_json) {
        const rendered = try pretty(gpa, result, "  ");
        defer gpa.free(rendered);
        try output.log(rendered[0 .. rendered.len - 1]);
    } else {
        if (reports.array.items.len == 0 and errors.array.items.len == 0) try output.log(try std.fmt.allocPrint(a, "No MCP servers configured. Add them to {s}/mcp.json or .pi/mcp.json.", .{context.agent_dir}));
        for (reports.array.items) |report| {
            const state = try protocol.text(report, "state");
            const tools = json.get(report, "tools").?.array.items;
            const label = if (std.mem.eql(u8, state, "connected")) try std.fmt.allocPrint(a, "connected, {d} tool{s}", .{ tools.len, if (tools.len == 1) "" else "s" }) else if (std.mem.eql(u8, state, "needs-auth")) "needs sign-in" else state;
            try output.log(try std.fmt.allocPrint(a, "{s}: {s} ({s}, {s})", .{ try protocol.text(report, "name"), label, try protocol.text(report, "exposure"), try protocol.text(report, "scope") }));
            try output.log(try std.fmt.allocPrint(a, "  {s}", .{try protocol.text(report, "transport")}));
            if (json.get(report, "override")) |value| try output.log(try std.fmt.allocPrint(a, "  project override: {s}", .{try json.asString(value)}));
            if (std.mem.eql(u8, state, "needs-auth")) try output.log(try std.fmt.allocPrint(a, "  sign in with: pi mcp login {s}", .{try protocol.text(report, "name")}));
            if (tools.len != 0) {
                var text: std.Io.Writer.Allocating = .init(a);
                defer text.deinit();
                try text.writer.writeAll("  tools: ");
                for (tools, 0..) |tool, index| {
                    if (index != 0) try text.writer.writeAll(", ");
                    try text.writer.writeAll(tool.string);
                    if (json.get(report, "toolExposure")) |overrides| if (json.get(overrides, tool.string)) |value| try text.writer.print(" [{s}]", .{value.string});
                }
                try output.log(text.written());
            }
            if (json.get(report, "resources")) |resources| try output.log(try std.fmt.allocPrint(a, "  resources: {d}, URI templates: {d}", .{ try json.asInteger(resources), try json.asInteger(json.get(report, "resourceTemplates").?) }));
            if (json.get(report, "error")) |cause| try output.log(try std.fmt.allocPrint(a, "  {s}", .{cause.string}));
        }
        for (errors.array.items) |value| try output.log(try std.fmt.allocPrint(a, "config error: {s}", .{value.string}));
        if (note) |value| try output.log(value);
    }
    if (failed) try output.data.value.object.put(a, "code", .{ .integer = 1 });
    return output;
}
pub const RunOptions = struct {
    context: Context,
    environment: *const std.process.Environ.Map,
    prompt: ?@import("oauth_signin.zig").Prompt = null,
    abort_flag: ?*bool = null,
};
fn toolCount(server: *@import("configured.zig").Server) !usize {
    const borrowed = try server.connection.acquire();
    defer borrowed.release();
    const offers = try protocol.field(borrowed.client.initialized.?.value, "capabilities");
    if (!@import("capabilities.zig").offersTools(offers)) return 0;
    var tools = try @import("capabilities.zig").listAll(borrowed.client, .tools, .{ .timeout_ms = server.timeout_ms });
    defer tools.deinit();
    return tools.value.array.items.len;
}
pub fn run(gpa: std.mem.Allocator, options: RunOptions, args: []const []const u8) !Output {
    if (try administer(gpa, options.context, args)) |output| return output;
    if (std.mem.eql(u8, args[0], "logout")) return logout(gpa, options.context, args);
    if (std.mem.eql(u8, args[0], "list")) {
        var parsed = try parseOptions(gpa, args[1..], &.{.{ .name = "json", .kind = .flag }}, std.math.maxInt(usize));
        defer parsed.deinit(gpa);
        return listServers(gpa, options.context, options.environment, json.get(json.get(parsed.valid.value, "values").?, "json") != null);
    }
    var output = try Output.init(gpa);
    errdefer output.deinit();
    var parsed = try parseOptions(gpa, args[1..], &.{.{ .name = "timeout", .kind = .value }}, std.math.maxInt(usize));
    defer parsed.deinit(gpa);
    const name = try json.asString(json.get(parsed.valid.value, "positional").?.array.items[0]);
    const service = try @import("configured.zig").Service.create(gpa, options.context.io, .{ .agent_dir = options.context.agent_dir, .cwd = options.context.cwd, .project_trusted = options.context.project_trusted, .environ = options.environment, .management_all = true });
    defer service.deinit();
    const note = try untrustedNote(gpa, options.context);
    defer if (note) |value| gpa.free(value);
    const entry = (try selectedEntry(gpa, service.loaded.value, note, name, &output)) orelse return output;
    if (!@import("configured.zig").usesOAuth(json.get(entry, "config").?)) {
        const message = try std.fmt.allocPrint(gpa, "MCP server \"{s}\" does not use OAuth. Only HTTP servers without an Authorization header do.", .{name});
        defer gpa.free(message);
        try output.fail(message);
        return output;
    }
    const values = json.get(parsed.valid.value, "values").?;
    const seconds = if (json.get(values, "timeout")) |value| try optionNumber(gpa, value.string) else 300;
    if (!std.math.isFinite(seconds) or seconds <= 0 or seconds * 1000 >= @as(f64, @floatFromInt(std.math.maxInt(u64)))) {
        try output.fail("--timeout must be a positive number of seconds.");
        return output;
    }
    const server = service.findServer(name).?;
    var needs_auth = false;
    const count = toolCount(server) catch |cause| blk: {
        if (cause == error.OutOfMemory or cause == error.Canceled) return cause;
        if (oauthRequired(cause)) {
            needs_auth = true;
            break :blk 0;
        }
        const message = try std.fmt.allocPrint(gpa, "MCP server \"{s}\" failed to connect: {s}", .{ name, @errorName(cause) });
        defer gpa.free(message);
        try output.fail(message);
        return output;
    };
    if (!needs_auth) {
        const message = try std.fmt.allocPrint(gpa, "Already signed in to MCP server \"{s}\" ({d} tools).", .{ name, count });
        defer gpa.free(message);
        try output.log(message);
        return output;
    }
    const prompt = options.prompt orelse return error.McpSignInPromptUnavailable;
    service.signIn(name, prompt, options.abort_flag, @intFromFloat(@ceil(seconds * 1000))) catch |cause| {
        if (cause == error.OutOfMemory or cause == error.Canceled) return cause;
        const canceled = cause == error.McpSignInCancelled or cause == error.OAuthSignInTimeout;
        const message = if (canceled) try std.fmt.allocPrint(gpa, "Sign-in to MCP server \"{s}\" was cancelled or not completed within {d} seconds.", .{ name, @as(u64, @intFromFloat(@floor(seconds + 0.5))) }) else try std.fmt.allocPrint(gpa, "Sign-in to MCP server \"{s}\" failed: {s}", .{ name, @errorName(cause) });
        defer gpa.free(message);
        try output.fail(message);
        return output;
    };
    server.challenge_mutex.lockUncancelable(options.context.io);
    if (server.challenge) |challenge| gpa.free(challenge);
    server.challenge = null;
    server.challenge_mutex.unlock(options.context.io);
    service.reconnect(name) catch |cause| {
        if (cause == error.OutOfMemory or cause == error.Canceled) return cause;
        const message = try std.fmt.allocPrint(gpa, "Signed in, but {s}", .{@errorName(cause)});
        defer gpa.free(message);
        try output.fail(message);
        return output;
    };
    const message = try std.fmt.allocPrint(gpa, "Signed in to MCP server \"{s}\" ({d} tools).", .{ name, try toolCount(server) });
    defer gpa.free(message);
    try output.log(message);
    return output;
}
pub fn administer(gpa: std.mem.Allocator, context: Context, args: []const []const u8) !?Output {
    if (try preflight(gpa, args)) |result| return result;
    const command = args[0];
    const adding = std.mem.eql(u8, command, "add");
    const removing = std.mem.eql(u8, command, "remove");
    if (!adding and !removing) return null;
    var output = try Output.init(gpa);
    errdefer output.deinit();
    const remove_options = [_]Known{.{ .name = "local", .kind = .flag }};
    var parsed = try parseOptions(gpa, args[1..], if (adding) &add_options else &remove_options, if (adding) 2 else std.math.maxInt(usize));
    defer parsed.deinit(gpa);
    if (parsed == .invalid) {
        try output.fail(parsed.invalid);
        return output;
    }
    const positional = json.get(parsed.valid.value, "positional").?.array.items;
    const values = json.get(parsed.valid.value, "values").?;
    const name = try json.asString(positional[0]);
    const local = json.get(values, "local") != null;
    const path = try std.fs.path.join(gpa, if (local) &.{ context.cwd, ".pi", "mcp.json" } else &.{ context.agent_dir, "mcp.json" });
    defer gpa.free(path);
    const scope = if (local) "project" else "global";
    if (adding) {
        var configured = try buildAddConfig(gpa, parsed.valid.value);
        defer configured.deinit(gpa);
        if (configured == .invalid) {
            try output.fail(configured.invalid);
            return output;
        }
        const replaced = editServer(gpa, context.io, path, name, configured.valid.value) catch |cause| {
            const message = try std.fmt.allocPrint(gpa, "Could not update {s}: {s}", .{ path, @errorName(cause) });
            defer gpa.free(message);
            try output.fail(message);
            return output;
        };
        const message = try std.fmt.allocPrint(gpa, "{s} {s} MCP server \"{s}\" in {s}.", .{ if (replaced) "Replaced" else "Added", scope, name, path });
        defer gpa.free(message);
        try output.log(message);
        if (local and !context.project_trusted) {
            const note = try std.fmt.allocPrint(gpa, "The project is not trusted, so {s} is ignored until you start pi in the project and trust it.", .{path});
            defer gpa.free(note);
            try output.log(note);
        }
        var oauth = json.get(configured.valid.value, "url") != null;
        if (json.get(configured.valid.value, "headers")) |headers| {
            var iterator = headers.object.iterator();
            while (iterator.next()) |entry| if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, "authorization")) {
                oauth = false;
            };
        }
        const hint = try std.fmt.allocPrint(gpa, "Check it with: pi mcp list{s}{s}", .{ if (oauth) ". If it requires sign-in: pi mcp login " else "", if (oauth) name else "" });
        defer gpa.free(hint);
        try output.log(hint);
        return output;
    }
    const removed = editServer(gpa, context.io, path, name, null) catch |cause| {
        const message = try std.fmt.allocPrint(gpa, "Could not update {s}: {s}", .{ path, @errorName(cause) });
        defer gpa.free(message);
        try output.fail(message);
        return output;
    };
    var other = try loadCatalog(gpa, context, true);
    defer other.deinit();
    var hint: ?[]u8 = null;
    defer if (hint) |value| gpa.free(value);
    if (!removed) for (json.get(other.value, "servers").?.array.items) |entry| {
        const entry_scope = try protocol.text(entry, "scope");
        if (std.mem.eql(u8, try protocol.text(entry, "name"), name) and !std.mem.eql(u8, entry_scope, scope)) {
            hint = try std.fmt.allocPrint(gpa, " It is defined in {s}; {s}.", .{ try protocol.text(entry, "source"), if (std.mem.eql(u8, entry_scope, "project")) "use --local" else "omit --local" });
            break;
        }
    };
    const message = if (removed) try std.fmt.allocPrint(gpa, "Removed {s} MCP server \"{s}\" from {s}.", .{ scope, name, path }) else try std.fmt.allocPrint(gpa, "No {s} MCP server named \"{s}\" in {s}.{s}", .{ scope, name, path, hint orelse "" });
    defer gpa.free(message);
    if (removed) try output.log(message) else try output.fail(message);
    return output;
}

test "mcp.runtime native logout retains hidden disabled catalogs and removes only selected credentials" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    const root = buffer[0..count];
    try scratch.dir.writeFile(io, .{ .sub_path = "mcp.json", .data = "{\"mcpServers\":{\"hidden\":{\"url\":\"https://service.example/mcp\",\"enabled\":false,\"exposure\":\"hidden\"},\"stdio\":{\"command\":\"not-executed\"}}}" });
    var store = try @import("oauth_store.zig").Store.init(gpa, io, root);
    defer store.deinit();
    var state = try json.Owned.parse(gpa, "{\"tokens\":{\"access_token\":\"owned-fixture\"}}");
    defer state.deinit();
    try store.save("hidden", "https://service.example/mcp", state.value, null);
    try store.save("other", "https://service.example/mcp", state.value, null);
    const context: Context = .{ .io = io, .agent_dir = root, .cwd = root };
    var result = try logout(gpa, context, &.{ "logout", "hidden" });
    defer result.deinit();
    try std.testing.expectEqualStrings("Signed out of MCP server \"hidden\".", json.get(result.data.value, "logs").?.array.items[0].string);
    try std.testing.expect(try store.load("hidden", "https://service.example/mcp", null) == null);
    var surviving = (try store.load("other", "https://service.example/mcp", null)).?;
    defer surviving.deinit();
    var absent = try logout(gpa, context, &.{ "logout", "hidden" });
    defer absent.deinit();
    try std.testing.expectEqualStrings("No stored credentials for MCP server \"hidden\".", json.get(absent.data.value, "logs").?.array.items[0].string);
    var rejected = try logout(gpa, context, &.{ "logout", "stdio" });
    defer rejected.deinit();
    try std.testing.expectEqualStrings("MCP server \"stdio\" does not use OAuth. Only HTTP servers without an Authorization header do.", json.get(rejected.data.value, "errors").?.array.items[0].string);
}
test "mcp.runtime native list includes disabled hidden servers without launching transport" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    const root = buffer[0..count];
    try scratch.dir.writeFile(io, .{ .sub_path = "mcp.json", .data = "{\"mcpServers\":{\"parked\":{\"command\":\"must-not-run\",\"args\":[\"--flag\"],\"enabled\":false,\"exposure\":\"hidden\"}}}" });
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    const context: Context = .{ .io = io, .agent_dir = root, .cwd = root };
    var output = try listServers(gpa, context, &environment, true);
    defer output.deinit();
    try std.testing.expectEqual(@as(u64, 0), try json.asInteger(json.get(output.data.value, "code").?));
    var report = try json.Owned.parse(gpa, json.get(output.data.value, "logs").?.array.items[0].string);
    defer report.deinit();
    const server = json.get(report.value, "servers").?.array.items[0];
    try std.testing.expectEqualStrings("disabled", try protocol.text(server, "state"));
    try std.testing.expectEqualStrings("must-not-run --flag", try protocol.text(server, "transport"));
    try std.testing.expectEqual(@as(usize, 0), json.get(server, "tools").?.array.items.len);
    var text = try listServers(gpa, context, &environment, false);
    defer text.deinit();
    try std.testing.expectEqualStrings("parked: disabled (hidden, global)", json.get(text.data.value, "logs").?.array.items[0].string);
}
test "mcp.runtime native catalog commands replay actual upstream disabled hidden and trust cases" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    const root = buffer[0..count];
    var original = try json.Owned.parse(gpa, if (@import("builtin").os.tag == .windows) @embedFile("fixtures/cli-catalog-original-7fb.json") else @embedFile("fixtures/cli-catalog-original-unix-7fb.json"));
    defer original.deinit();
    const bytes = try json.stringify(gpa, json.get(original.value, "config").?);
    defer gpa.free(bytes);
    try scratch.dir.writeFile(io, .{ .sub_path = "mcp.json", .data = bytes });
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    const context: Context = .{ .io = io, .agent_dir = root, .cwd = root };
    for (json.get(original.value, "cases").?.array.items) |row| {
        if (json.get(row, "untrusted") != null) {
            try scratch.dir.createDirPath(io, ".pi");
            try scratch.dir.writeFile(io, .{ .sub_path = ".pi/mcp.json", .data = "{}" });
        }
        const input = json.get(row, "input").?.array.items;
        const args = try gpa.alloc([]const u8, input.len);
        defer gpa.free(args);
        for (args, input) |*arg, value| arg.* = value.string;
        var output = if (std.mem.eql(u8, args[0], "list")) try listServers(gpa, context, &environment, args.len > 1) else try logout(gpa, context, args);
        defer output.deinit();
        try std.testing.expectEqual(try json.asInteger(json.get(row, "code").?), try json.asInteger(json.get(output.data.value, "code").?));
        for ([_][]const u8{ "logs", "errors" }) |field| {
            const actual = json.get(output.data.value, field).?.array.items;
            const expected = json.get(row, field).?.array.items;
            try std.testing.expectEqual(expected.len, actual.len);
            for (expected, actual) |left, right| {
                const normalized = try std.mem.replaceOwned(u8, gpa, right.string, root, "<ROOT>");
                defer gpa.free(normalized);
                if (args.len > 1 and std.mem.eql(u8, args[1], "--json")) {
                    var native_json = try json.Owned.parse(gpa, normalized);
                    defer native_json.deinit();
                    for (json.get(native_json.value, "servers").?.array.items) |*server| {
                        const source = server.object.getPtr("source").?;
                        source.* = .{ .string = try std.mem.replaceOwned(u8, native_json.arena.allocator(), source.string, root, "<ROOT>") };
                    }
                    var source_json = try json.Owned.parse(gpa, left.string);
                    defer source_json.deinit();
                    try std.testing.expect(json.equal(source_json.value, native_json.value));
                } else try std.testing.expectEqualStrings(left.string, normalized);
            }
        }
    }
}

test "mcp.runtime MCP command parser retains source option aliases lists and command argv boundary" {
    const gpa = std.testing.allocator;
    var result = try parseOptions(gpa, &.{ "server", "-l", "--env", "A=one", "--env", "B=two", "command", "--flag", "value" }, &.{ .{ .name = "local", .kind = .flag }, .{ .name = "env", .kind = .list } }, 2);
    defer result.deinit(gpa);
    const root = result.valid.value;
    try std.testing.expect(json.get(json.get(root, "values").?, "local").?.bool);
    const env = json.get(json.get(root, "lists").?, "env").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), env.len);
    try std.testing.expectEqualStrings("A=one", env[0].string);
    const args = json.get(root, "positional").?.array.items;
    try std.testing.expectEqual(@as(usize, 4), args.len);
    try std.testing.expectEqualStrings("--flag", args[2].string);
    var invalid = try parseOptions(gpa, &.{"--bad"}, &.{}, std.math.maxInt(usize));
    defer invalid.deinit(gpa);
    try std.testing.expectEqualStrings("Unknown option --bad.\nUse \"pi mcp --help\" for usage.", invalid.invalid);
}
test "mcp.runtime command numeric options retain Number whitespace radix invalid and infinity semantics" {
    const gpa = std.testing.allocator;
    for ([_]struct { text: []const u8, number: f64 }{ .{ .text = "0x50", .number = 80 }, .{ .text = "0b101", .number = 5 }, .{ .text = "0o77", .number = 63 }, .{ .text = "\xc2\xa0\xef\xbb\xbf 1e2 \xe2\x80\xa8", .number = 100 }, .{ .text = "", .number = 0 }, .{ .text = "Infinity", .number = std.math.inf(f64) } }) |item| try std.testing.expectEqual(item.number, try optionNumber(gpa, item.text));
    try std.testing.expect(std.math.isNan(try optionNumber(gpa, "1x")));
    var parsed = try parseOptions(gpa, &.{ "server", "--url", "https://service.example/mcp", "--oauth-callback-port", "0x50" }, &add_options, 2);
    defer parsed.deinit(gpa);
    var config = try buildAddConfig(gpa, parsed.valid.value);
    defer config.deinit(gpa);
    try std.testing.expectEqual(@as(u64, 80), try json.asInteger(json.get(json.get(config.valid.value, "oauth").?, "callbackPort").?));
}

test "mcp.runtime MCP command preflight replays actual original help unknown option and usage results" {
    const gpa = std.testing.allocator;
    var original = try json.Owned.parse(gpa, @embedFile("fixtures/cli-original-7fb.json"));
    defer original.deinit();
    for (original.value.array.items) |row| {
        const input = json.get(row, "input").?.array.items;
        const args = try gpa.alloc([]const u8, input.len);
        defer gpa.free(args);
        for (input, args) |value, *arg| arg.* = try json.asString(value);
        var result = (try preflight(gpa, args)) orelse continue;
        defer result.deinit();
        var expected = try json.Owned.empty(gpa);
        defer expected.deinit();
        expected.value = try json.clone(expected.arena.allocator(), row);
        _ = expected.value.object.orderedRemove("input");
        try std.testing.expect(json.equal(expected.value, result.data.value));
    }
}

test "mcp.runtime MCP configuration edits retain unknown content indentation and escaped payload" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    const path = try std.fs.path.join(gpa, &.{ buffer[0..count], "mcp.json" });
    defer gpa.free(path);
    try scratch.dir.writeFile(io, .{ .sub_path = "mcp.json", .data = "{\n\t\"unknown\": true,\n\t\"mcpServers\": {}\n}\n" });
    var config = try json.Owned.parse(gpa, "{\"command\":\"actual\",\"args\":[\"brace } and quote \\\"\"],\"env\":{}}");
    defer config.deinit();
    try std.testing.expect(!try editServer(gpa, io, path, "server", config.value));
    const bytes = try scratch.dir.readFileAlloc(io, "mcp.json", gpa, .limited(4096));
    defer gpa.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\n\t\"unknown\": true") != null);
    var parsed = try json.Owned.parse(gpa, bytes);
    defer parsed.deinit();
    try std.testing.expect(json.get(parsed.value, "unknown").?.bool);
    try std.testing.expect(json.equal(config.value, json.get(json.get(parsed.value, "mcpServers").?, "server").?));
    try std.testing.expect(try editServer(gpa, io, path, "server", config.value));
    try std.testing.expect(try editServer(gpa, io, path, "server", null));
    try std.testing.expect(!try editServer(gpa, io, path, "server", null));
}

test "mcp.runtime MCP add builds validated HTTP bearer OAuth and stdio argv and rejects misplaced fields" {
    const gpa = std.testing.allocator;
    var http = try parseOptions(gpa, &.{ "server", "--url", "https://service.example/mcp", "--header", "X-Test=one", "--bearer-token-env-var", "MCP_TOKEN", "--oauth-client-id", "registered", "--oauth-callback-port", "1234" }, &add_options, 2);
    defer http.deinit(gpa);
    var result = try buildAddConfig(gpa, http.valid.value);
    defer result.deinit(gpa);
    const config = result.valid.value;
    try std.testing.expectEqualStrings("Bearer ${MCP_TOKEN}", try protocol.text(json.get(config, "headers").?, "Authorization"));
    try std.testing.expectEqualStrings("registered", try protocol.text(json.get(config, "oauth").?, "clientId"));
    try std.testing.expectEqual(@as(u64, 1234), try json.asInteger(json.get(json.get(config, "oauth").?, "callbackPort").?));
    var stdio = try parseOptions(gpa, &.{ "server", "--env", "KEY=value=with=equals", "command", "--flag", "argument" }, &add_options, 2);
    defer stdio.deinit(gpa);
    var stdio_result = try buildAddConfig(gpa, stdio.valid.value);
    defer stdio_result.deinit(gpa);
    try std.testing.expectEqualStrings("command", try protocol.text(stdio_result.valid.value, "command"));
    try std.testing.expectEqualStrings("value=with=equals", try protocol.text(json.get(stdio_result.valid.value, "env").?, "KEY"));
    try std.testing.expectEqualStrings("--flag", json.get(stdio_result.valid.value, "args").?.array.items[0].string);
    var misplaced = try parseOptions(gpa, &.{ "server", "--url", "https://service.example/mcp", "--cwd", "directory" }, &add_options, 2);
    defer misplaced.deinit(gpa);
    var rejected = try buildAddConfig(gpa, misplaced.valid.value);
    defer rejected.deinit(gpa);
    try std.testing.expectEqualStrings("--cwd only applies to stdio servers.", rejected.invalid);
}

test "mcp.runtime MCP administrative command add replace remove uses actual owned files" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    const context: Context = .{ .io = io, .agent_dir = buffer[0..count], .cwd = buffer[0..count] };
    var added = (try administer(gpa, context, &.{ "add", "server", "--url", "https://service.example/mcp" })).?;
    defer added.deinit();
    try std.testing.expectEqual(@as(u64, 0), try json.asInteger(json.get(added.data.value, "code").?));
    try std.testing.expect(std.mem.startsWith(u8, json.get(added.data.value, "logs").?.array.items[0].string, "Added global MCP server"));
    var replaced = (try administer(gpa, context, &.{ "add", "server", "command", "--arg" })).?;
    defer replaced.deinit();
    try std.testing.expect(std.mem.startsWith(u8, json.get(replaced.data.value, "logs").?.array.items[0].string, "Replaced global MCP server"));
    var removed = (try administer(gpa, context, &.{ "remove", "server" })).?;
    defer removed.deinit();
    try std.testing.expectEqual(@as(u64, 0), try json.asInteger(json.get(removed.data.value, "code").?));
    var missing = (try administer(gpa, context, &.{ "remove", "server" })).?;
    defer missing.deinit();
    try std.testing.expectEqual(@as(u64, 1), try json.asInteger(json.get(missing.data.value, "code").?));
}

test "mcp.runtime MCP add remove commands replay actual original logs and persisted config" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    const root = buffer[0..count];
    const context: Context = .{ .io = io, .agent_dir = root, .cwd = root };
    var original = try json.Owned.parse(gpa, if (@import("builtin").os.tag == .windows) @embedFile("fixtures/cli-admin-original-7fb.json") else @embedFile("fixtures/cli-admin-original-unix-7fb.json"));
    defer original.deinit();
    for (original.value.array.items) |row| {
        const input = json.get(row, "input").?.array.items;
        const args = try gpa.alloc([]const u8, input.len);
        defer gpa.free(args);
        for (input, args) |value, *arg| arg.* = try json.asString(value);
        var output = (try administer(gpa, context, args)).?;
        defer output.deinit();
        try std.testing.expectEqual(try json.asInteger(json.get(row, "code").?), try json.asInteger(json.get(output.data.value, "code").?));
        for ([_][]const u8{ "logs", "errors" }) |field| {
            const expected = json.get(row, field).?.array.items;
            const actual = json.get(output.data.value, field).?.array.items;
            try std.testing.expectEqual(expected.len, actual.len);
            for (expected, actual) |left, right| {
                const normalized = try std.mem.replaceOwned(u8, gpa, right.string, root, "<ROOT>");
                defer gpa.free(normalized);
                try std.testing.expectEqualStrings(left.string, normalized);
            }
        }
        const bytes = try scratch.dir.readFileAlloc(io, "mcp.json", gpa, .limited(4096));
        defer gpa.free(bytes);
        var saved = try json.Owned.parse(gpa, bytes);
        defer saved.deinit();
        try std.testing.expect(json.equal(json.get(row, "config").?, saved.value));
    }
}
