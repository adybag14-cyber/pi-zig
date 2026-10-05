//! Native configuration validation and exposure policy, backed by the pinned Pi contract.
const std = @import("std");
const protocol = @import("protocol.zig");
const json = protocol.json;
const Value = protocol.Value;
const url = @import("../extensions/url_parser.zig");
pub const Exposure = enum { codemode, deferred, direct, hidden };
pub const Validation = union(enum) {
    valid: json.Owned,
    invalid: []u8,
    pub fn deinit(self: *Validation, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .valid => |*value| value.deinit(),
            .invalid => |message| gpa.free(message),
        }
    }
};
fn fail(gpa: std.mem.Allocator, name: []const u8, message: []const u8) !Validation {
    return .{ .invalid = try std.fmt.allocPrint(gpa, "server \"{s}\": {s}", .{ name, message }) };
}
fn alias(value: Value) Value {
    return if (value == .string and std.mem.eql(u8, value.string, "codemode-deferred")) .{ .string = "codemode" } else value;
}
fn exposure(value: Value) ?Exposure {
    return if (value == .string) std.meta.stringToEnum(Exposure, value.string) else null;
}
fn stringMap(value: Value) bool {
    if (value != .object) return false;
    var items = value.object.iterator();
    while (items.next()) |item| if (item.value_ptr.* != .string) return false;
    return true;
}
fn loopback(host: []const u8) bool {
    return std.mem.eql(u8, host, "localhost") or std.mem.eql(u8, host, "127.0.0.1") or std.mem.eql(u8, host, "[::1]");
}
fn httpUrl(gpa: std.mem.Allocator, value: Value) !?url.Record {
    if (value != .string) return null;
    var record = url.parse(gpa, value.string, null) catch |cause| {
        if (cause == error.OutOfMemory) return cause;
        return null;
    };
    if (!std.mem.eql(u8, record.scheme, "http") and !std.mem.eql(u8, record.scheme, "https")) {
        record.deinit(gpa);
        return null;
    }
    return record;
}
fn oauthError(gpa: std.mem.Allocator, value: Value) !?[]const u8 {
    if (value != .object) return "oauth must be an object";
    for ([_]struct { key: []const u8, message: []const u8 }{ .{ .key = "clientId", .message = "oauth.clientId must be a string" }, .{ .key = "clientSecret", .message = "oauth.clientSecret must be a string" }, .{ .key = "scope", .message = "oauth.scope must be a string" } }) |field| if (json.get(value, field.key)) |item| if (item != .string) return field.message;
    var port: ?u64 = null;
    if (json.get(value, "callbackPort")) |item| {
        port = json.asInteger(item) catch return "oauth.callbackPort must be a port number";
        if (port.? < 1 or port.? > 65535) return "oauth.callbackPort must be a port number";
    }
    if (json.get(value, "callbackUrl")) |item| {
        var record = (try httpUrl(gpa, item)) orelse return "oauth.callbackUrl must be an http URI on localhost, 127.0.0.1, or [::1] without query or fragment";
        defer record.deinit(gpa);
        if (!std.mem.eql(u8, record.scheme, "http") or !loopback(record.host orelse "") or (record.query != null and record.query.?.len > 0) or (record.fragment != null and record.fragment.?.len > 0)) return "oauth.callbackUrl must be an http URI on localhost, 127.0.0.1, or [::1] without query or fragment";
        if (record.port != null and port != null and record.port.? != port.?) return "oauth.callbackUrl and oauth.callbackPort name different ports";
    }
    if (json.get(value, "clientName")) |item| if (item != .string or std.mem.trim(u8, item.string, " \t\r\n").len == 0) return "oauth.clientName must be a non-empty string";
    if (json.get(value, "clientRegistration")) |item| if (item != .string or !std.mem.eql(u8, item.string, "dcr")) {
        if (item != .string or !std.mem.eql(u8, item.string, "cimd")) return "oauth.clientRegistration must be \"dcr\" or \"cimd\"";
        if (json.get(value, "clientId") != null or json.get(value, "clientName") != null) return "oauth.clientRegistration \"cimd\" cannot be combined with oauth.clientId or oauth.clientName";
        if (json.get(value, "callbackUrl")) |callback| {
            var record = (try httpUrl(gpa, callback)).?;
            defer record.deinit(gpa);
            if (std.mem.eql(u8, record.host orelse "", "[::1]") or !std.mem.eql(u8, record.path, "/callback")) return "oauth.clientRegistration \"cimd\" requires oauth.callbackUrl on localhost or 127.0.0.1 with path /callback";
        }
    };
    if (json.get(value, "authServerMetadataUrl")) |item| {
        var record = (try httpUrl(gpa, item)) orelse return "oauth.authServerMetadataUrl must be an https URL, or http on localhost, 127.0.0.1, or [::1]";
        defer record.deinit(gpa);
        if (!std.mem.eql(u8, record.scheme, "https") and !loopback(record.host orelse "")) return "oauth.authServerMetadataUrl must be an https URL, or http on localhost, 127.0.0.1, or [::1]";
    }
    return null;
}
pub fn validate(gpa: std.mem.Allocator, name: []const u8, raw: Value) !Validation {
    var valid_name = name.len > 0;
    for (name) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '-') valid_name = false;
    }
    if (!valid_name) return .{ .invalid = try std.fmt.allocPrint(gpa, "invalid server name \"{s}\" (use letters, digits, \"_\" and \"-\")", .{name}) };
    if (raw != .object) return .{ .invalid = try std.fmt.allocPrint(gpa, "server \"{s}\" must be an object", .{name}) };
    var owned = try json.Owned.empty(gpa);
    var transferred = false;
    defer if (!transferred) owned.deinit();
    const a = owned.arena.allocator();
    var value = try json.clone(a, raw);
    if (json.get(value, "exposure")) |item| {
        const resolved = alias(item);
        try value.object.put(a, "exposure", resolved);
        if (exposure(resolved) == null) return fail(gpa, name, "exposure must be one of \"codemode\", \"deferred\", \"direct\", \"hidden\"");
    }
    if (json.get(value, "toolExposure")) |items| {
        if (items != .object) return fail(gpa, name, "toolExposure must map tool names to exposures");
        var iterator = items.object.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.* = alias(entry.value_ptr.*);
            if (exposure(entry.value_ptr.*) == null) return .{ .invalid = try std.fmt.allocPrint(gpa, "server \"{s}\": toolExposure \"{s}\" must be one of \"codemode\", \"deferred\", \"direct\", \"hidden\"", .{ name, entry.key_ptr.* }) };
        }
    }
    if (json.get(value, "enabled")) |item| if (item != .bool) return fail(gpa, name, "enabled must be a boolean");
    if (json.get(value, "description")) |item| if (item != .string) return fail(gpa, name, "description must be a string");
    if (json.get(value, "timeout")) |item| {
        const timeout = json.asNumber(item) catch return fail(gpa, name, "timeout must be a positive number of seconds");
        if (!(timeout > 0)) return fail(gpa, name, "timeout must be a positive number of seconds");
    }
    const type_value = json.get(value, "type");
    const type_name = if (type_value != null and type_value.? == .string) type_value.?.string else "";
    if (std.mem.eql(u8, type_name, "sse")) return fail(gpa, name, "legacy SSE transport is not supported; use the streamable HTTP URL");
    if (json.get(value, "url")) |location| if (location == .string and (type_value == null or std.mem.eql(u8, type_name, "http") or std.mem.eql(u8, type_name, "streamable-http"))) {
        var record = (try httpUrl(gpa, location)) orelse return fail(gpa, name, "url must be an http or https URL");
        defer record.deinit(gpa);
        if (json.get(value, "headers")) |headers| if (!stringMap(headers)) return fail(gpa, name, "headers must map names to strings");
        if (json.get(value, "oauth")) |oauth| if (try oauthError(gpa, oauth)) |message| return fail(gpa, name, message);
        if (json.get(value, "auth")) |auth| {
            const provider = json.get(auth, "provider");
            if (auth != .object or provider == null or provider.? != .string or provider.?.string.len == 0) return fail(gpa, name, "auth.provider must be a provider name");
            if (!std.mem.eql(u8, record.scheme, "https") and !loopback(record.host orelse "")) return fail(gpa, name, "auth requires an https URL, or http on localhost, 127.0.0.1, or [::1]");
        }
        owned.value = value;
        transferred = true;
        return .{ .valid = owned };
    };
    if (json.get(value, "command")) |command| if (command == .string and (type_value == null or std.mem.eql(u8, type_name, "stdio"))) {
        if (json.get(value, "args")) |args| {
            if (args != .array) return fail(gpa, name, "args must be an array of strings");
            for (args.array.items) |arg| if (arg != .string) return fail(gpa, name, "args must be an array of strings");
        }
        if (json.get(value, "env")) |env| if (!stringMap(env)) return fail(gpa, name, "env must map names to strings");
        if (json.get(value, "cwd")) |cwd| if (cwd != .string) return fail(gpa, name, "cwd must be a string");
        owned.value = value;
        transferred = true;
        return .{ .valid = owned };
    };
    return .{ .invalid = try std.fmt.allocPrint(gpa, "server \"{s}\" needs either \"command\" (stdio) or \"url\" (streamable HTTP)", .{name}) };
}
pub fn namespace(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    const result = try std.fmt.allocPrint(gpa, "mcp__{s}", .{name});
    for (result[5..]) |*byte| if (byte.* == '-') {
        byte.* = '_';
    };
    return result;
}
pub fn matches(pattern: []const u8, name: []const u8) bool {
    var p: usize = 0;
    var n: usize = 0;
    var star: ?usize = null;
    var retry: usize = 0;
    while (n < name.len) {
        if (p < pattern.len and pattern[p] == name[n]) {
            p += 1;
            n += 1;
        } else if (p < pattern.len and pattern[p] == '*') {
            star = p;
            p += 1;
            retry = n;
        } else if (star) |index| {
            p = index + 1;
            retry += 1;
            n = retry;
        } else return false;
    }
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}
pub fn toolExposure(value: Value, name: []const u8) !Exposure {
    if (json.get(value, "toolExposure")) |items| {
        if (items != .object) return error.InvalidMcpExposure;
        if (json.get(items, name)) |exact| return exposure(alias(exact)) orelse error.InvalidMcpExposure;
        var iterator = items.object.iterator();
        while (iterator.next()) |entry| if (std.mem.indexOfScalar(u8, entry.key_ptr.*, '*') != null and matches(entry.key_ptr.*, name)) return exposure(alias(entry.value_ptr.*)) orelse error.InvalidMcpExposure;
    }
    return if (json.get(value, "exposure")) |item| exposure(alias(item)) orelse error.InvalidMcpExposure else .codemode;
}
pub const LoadOptions = struct { global_path: []const u8, project_path: ?[]const u8 = null, project_trusted: bool = false, max_bytes: usize = 4 * 1024 * 1024 };
pub fn load(gpa: std.mem.Allocator, io: std.Io, options: LoadOptions) !json.Owned {
    var owned = try json.Owned.empty(gpa);
    errdefer owned.deinit();
    const a = owned.arena.allocator();
    var servers: Value = .{ .object = .empty };
    var errors: Value = .{ .array = .init(a) };
    var auto_enable: ?bool = null;
    try loadFile(gpa, io, a, options.global_path, "global", options.max_bytes, &servers, &errors, &auto_enable);
    if (options.project_trusted) if (options.project_path) |path| try loadFile(gpa, io, a, path, "project", options.max_bytes, &servers, &errors, &auto_enable);
    var result: Value = .{ .object = .empty };
    var list: Value = .{ .array = .init(a) };
    var iterator = servers.object.iterator();
    while (iterator.next()) |entry| try list.array.append(entry.value_ptr.*);
    try result.object.put(a, "servers", list);
    try result.object.put(a, "errors", errors);
    if (auto_enable) |value| try result.object.put(a, "autoEnableCodemode", .{ .bool = value });
    if (options.project_trusted) if (options.project_path) |path| try result.object.put(a, "projectConfig", .{ .string = try a.dupe(u8, path) });
    owned.value = result;
    return owned;
}
fn configError(a: std.mem.Allocator, errors: *Value, path: []const u8, message: []const u8) !void {
    try errors.array.append(.{ .string = try std.fmt.allocPrint(a, "{s}: {s}", .{ path, message }) });
}
fn overrideOnly(value: Value) bool {
    return value == .object and json.get(value, "command") == null and json.get(value, "url") == null and json.get(value, "type") == null;
}
fn sameNamespace(first: []const u8, second: []const u8) bool {
    if (first.len != second.len) return false;
    for (first, second) |a, b| if ((if (a == '-') '_' else a) != (if (b == '-') '_' else b)) return false;
    return true;
}
fn loadFile(gpa: std.mem.Allocator, io: std.Io, a: std.mem.Allocator, path: []const u8, scope: []const u8, limit: usize, servers: *Value, errors: *Value, auto_enable: *?bool) !void {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(limit)) catch |cause| {
        if (cause == error.FileNotFound) return;
        if (cause == error.OutOfMemory) return cause;
        try configError(a, errors, path, @errorName(cause));
        return;
    };
    defer gpa.free(bytes);
    var parsed = json.Owned.parse(gpa, bytes) catch |cause| {
        if (cause == error.OutOfMemory) return cause;
        try configError(a, errors, path, @errorName(cause));
        return;
    };
    defer parsed.deinit();
    const configs = json.get(parsed.value, "mcpServers");
    if (parsed.value != .object or (configs != null and configs.? != .object)) {
        try configError(a, errors, path, "expected an object with an \"mcpServers\" object");
        return;
    }
    if (json.get(parsed.value, "autoEnableCodemode")) |value| {
        if (value == .bool) auto_enable.* = value.bool else try configError(a, errors, path, "autoEnableCodemode must be a boolean");
    }
    if (configs == null) return;
    var iterator = configs.?.object.iterator();
    while (iterator.next()) |entry| {
        const name = entry.key_ptr.*;
        const raw = entry.value_ptr.*;
        const is_project = std.mem.eql(u8, scope, "project");
        if (is_project and overrideOnly(raw)) {
            const base = json.get(servers.*, name) orelse {
                try configError(a, errors, path, try std.fmt.allocPrint(a, "server \"{s}\" needs \"command\" or \"url\", or a global server to override", .{name}));
                continue;
            };
            var extra = false;
            var fields = raw.object.iterator();
            while (fields.next()) |field| if (!std.mem.eql(u8, field.key_ptr.*, "enabled") and !std.mem.eql(u8, field.key_ptr.*, "exposure") and !std.mem.eql(u8, field.key_ptr.*, "toolExposure")) {
                extra = true;
            };
            if (extra) {
                try configError(a, errors, path, try std.fmt.allocPrint(a, "server \"{s}\": an override can only set enabled, exposure, toolExposure", .{name}));
                continue;
            }
            var merged = try json.clone(a, try protocol.field(base, "config"));
            fields = raw.object.iterator();
            while (fields.next()) |field| try merged.object.put(a, try a.dupe(u8, field.key_ptr.*), try json.clone(a, field.value_ptr.*));
            var result = try validate(gpa, name, merged);
            defer result.deinit(gpa);
            switch (result) {
                .invalid => |message| try configError(a, errors, path, message),
                .valid => |valid| {
                    var replacement = try json.clone(a, base);
                    try replacement.object.put(a, "config", try json.clone(a, valid.value));
                    try replacement.object.put(a, "override", .{ .string = try a.dupe(u8, path) });
                    try servers.object.put(a, try a.dupe(u8, name), replacement);
                },
            }
            continue;
        }
        var result = try validate(gpa, name, raw);
        defer result.deinit(gpa);
        switch (result) {
            .invalid => |message| {
                try configError(a, errors, path, message);
                continue;
            },
            .valid => |valid| {
                var clash: ?[]const u8 = null;
                var existing = servers.object.iterator();
                while (existing.next()) |other| if (!std.mem.eql(u8, other.key_ptr.*, name) and sameNamespace(other.key_ptr.*, name)) {
                    clash = other.key_ptr.*;
                    break;
                };
                if (clash) |other| {
                    try configError(a, errors, path, try std.fmt.allocPrint(a, "server \"{s}\" conflicts with \"{s}\"", .{ name, other }));
                    continue;
                }
                if (is_project and json.get(valid.value, "url") != null and json.get(valid.value, "auth") != null) {
                    try configError(a, errors, path, try std.fmt.allocPrint(a, "server \"{s}\": auth is only allowed in the global mcp.json", .{name}));
                    continue;
                }
                var server: Value = .{ .object = .empty };
                try server.object.put(a, "name", .{ .string = try a.dupe(u8, name) });
                try server.object.put(a, "config", try json.clone(a, valid.value));
                try server.object.put(a, "source", .{ .string = try a.dupe(u8, path) });
                try server.object.put(a, "scope", .{ .string = scope });
                try servers.object.put(a, try a.dupe(u8, name), server);
            },
        }
    }
}
