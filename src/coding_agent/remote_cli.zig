//! Native command-line client for protocol-v1 Pi servers over Unix sockets or TCP.
//!
//! The command intentionally uses the same Client and RemoteSession layers as
//! embedded consumers. Reads are bounded by absolute deadlines, every attached
//! session is detached on normal completion, and protocol-owned snapshots are
//! rendered before their connection arena is released.
const std = @import("std");
const Io = std.Io;
const protocol = @import("../protocol/root.zig");
const msg = protocol.messages;
const client_pkg = @import("../client/root.zig");
const remote_mod = @import("remote_session.zig");

pub const DEFAULT_TIMEOUT_MS: u64 = 30_000;
pub const MAX_TIMEOUT_MS: u64 = 24 * 60 * 60 * 1000;

pub const Error = error{
    MissingEndpoint,
    ConflictingEndpoint,
    TransportOptionRequiresTcp,
    ConflictingProxyOptions,
    MissingAction,
    MissingArgument,
    UnknownOption,
    UnknownAction,
    InvalidTimeout,
    InvalidModel,
    InvalidThinkingLevel,
    InvalidLimit,
    InvalidRole,
    EmptyPrompt,
    ConnectionClosed,
    OperationFailed,
    OperationDidNotSettle,
};

pub const Action = union(enum) {
    list,
    search: struct {
        query: []const u8,
        limit: usize = 100,
        case_sensitive: bool = false,
        session_id: ?[]const u8 = null,
        role_mask: u8 = 0,
    },
    open: struct { session_id: []const u8 },
    create: struct {
        cwd: ?[]const u8 = null,
        name: ?[]const u8 = null,
        model: ?msg.ModelRef = null,
        thinking: ?msg.ThinkingLevel = null,
        prompt: ?[]const u8 = null,
    },
    prompt: struct { session_id: []const u8, text: []const u8 },
    abort: struct { session_id: []const u8 },
    set_model: struct { session_id: []const u8, model: msg.ModelRef },
    set_thinking: struct { session_id: []const u8, thinking: msg.ThinkingLevel },
};

pub const Parsed = struct {
    gpa: std.mem.Allocator,
    socket_path: ?[]const u8 = null,
    tcp_address: ?[]const u8 = null,
    tls: bool = false,
    proxy: ?[]const u8 = null,
    disable_proxy: bool = false,
    timeout_ms: u64 = DEFAULT_TIMEOUT_MS,
    json: bool = false,
    action: Action,
    owned_text: ?[]u8 = null,

    pub fn deinit(self: *Parsed) void {
        if (self.owned_text) |value| self.gpa.free(value);
        self.* = undefined;
    }
};

pub const RunResult = struct {
    exit_code: u8 = 0,
};

pub fn usage(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\Usage:
        \\  pi remote (--socket PATH | --connect ADDRESS:PORT) [--tls] [--proxy URL|--no-proxy] [--timeout-ms N] [--json] list
        \\  pi remote (--socket PATH | --connect ADDRESS:PORT) [--tls] [--proxy URL|--no-proxy] [--timeout-ms N] [--json]
        \\            search [--limit N] [--case-sensitive] [--session ID]
        \\                   [--role user|assistant|tool] QUERY...
        \\  pi remote (--socket PATH | --connect ADDRESS:PORT) [--tls] [--proxy URL|--no-proxy] [--timeout-ms N] [--json] open SESSION
        \\  pi remote (--socket PATH | --connect ADDRESS:PORT) [--tls] [--proxy URL|--no-proxy] [--timeout-ms N] [--json] prompt SESSION TEXT...
        \\  pi remote (--socket PATH | --connect ADDRESS:PORT) [--tls] [--proxy URL|--no-proxy] [--timeout-ms N] [--json] create [--cwd PATH] [--name NAME]
        \\            [--model PROVIDER/ID] [--thinking LEVEL] [--prompt TEXT...]
        \\  pi remote (--socket PATH | --connect ADDRESS:PORT) [--tls] [--proxy URL|--no-proxy] [--timeout-ms N] [--json] abort SESSION
        \\  pi remote (--socket PATH | --connect ADDRESS:PORT) [--tls] [--proxy URL|--no-proxy] [--timeout-ms N] [--json] model SESSION PROVIDER/ID
        \\  pi remote (--socket PATH | --connect ADDRESS:PORT) [--tls] [--proxy URL|--no-proxy] [--timeout-ms N] [--json] thinking SESSION LEVEL
        \\
    );
}

pub fn parse(gpa: std.mem.Allocator, args: []const []const u8) !Parsed {
    var socket_path: ?[]const u8 = null;
    var tcp_address: ?[]const u8 = null;
    var tls = false;
    var proxy: ?[]const u8 = null;
    var disable_proxy = false;
    var timeout_ms: u64 = DEFAULT_TIMEOUT_MS;
    var json = false;
    var index: usize = 0;

    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--socket")) {
            index += 1;
            if (index >= args.len) return Error.MissingArgument;
            socket_path = args[index];
            index += 1;
        } else if (std.mem.startsWith(u8, arg, "--socket=")) {
            socket_path = arg["--socket=".len..];
            index += 1;
        } else if (std.mem.eql(u8, arg, "--connect")) {
            index += 1;
            if (index >= args.len) return Error.MissingArgument;
            tcp_address = args[index];
            index += 1;
        } else if (std.mem.startsWith(u8, arg, "--connect=")) {
            tcp_address = arg["--connect=".len..];
            index += 1;
        } else if (std.mem.eql(u8, arg, "--tls")) {
            tls = true;
            index += 1;
        } else if (std.mem.eql(u8, arg, "--proxy")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) return Error.MissingArgument;
            proxy = args[index];
            index += 1;
        } else if (std.mem.startsWith(u8, arg, "--proxy=")) {
            proxy = arg["--proxy=".len..];
            if (proxy.?.len == 0) return Error.MissingArgument;
            index += 1;
        } else if (std.mem.eql(u8, arg, "--no-proxy")) {
            disable_proxy = true;
            index += 1;
        } else if (std.mem.eql(u8, arg, "--timeout-ms")) {
            index += 1;
            if (index >= args.len) return Error.MissingArgument;
            timeout_ms = try parseTimeout(args[index]);
            index += 1;
        } else if (std.mem.startsWith(u8, arg, "--timeout-ms=")) {
            timeout_ms = try parseTimeout(arg["--timeout-ms=".len..]);
            index += 1;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json = true;
            index += 1;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return Error.UnknownOption;
        } else break;
    }

    if (socket_path != null and tcp_address != null) return Error.ConflictingEndpoint;
    if (socket_path == null and tcp_address == null) return Error.MissingEndpoint;
    if (proxy != null and disable_proxy) return Error.ConflictingProxyOptions;
    if (socket_path != null and (tls or proxy != null or disable_proxy)) return Error.TransportOptionRequiresTcp;
    if (socket_path) |value| if (value.len == 0) return Error.MissingEndpoint;
    if (tcp_address) |value| if (value.len == 0) return Error.MissingEndpoint;
    if (index >= args.len) return Error.MissingAction;
    const action_name = args[index];
    index += 1;

    var parsed = Parsed{
        .gpa = gpa,
        .socket_path = socket_path,
        .tcp_address = tcp_address,
        .tls = tls,
        .proxy = proxy,
        .disable_proxy = disable_proxy,
        .timeout_ms = timeout_ms,
        .json = json,
        .action = undefined,
    };
    errdefer parsed.deinit();

    if (std.mem.eql(u8, action_name, "list")) {
        if (index != args.len) return Error.UnknownOption;
        parsed.action = .list;
    } else if (std.mem.eql(u8, action_name, "search") or std.mem.eql(u8, action_name, "find")) {
        var limit: usize = 100;
        var case_sensitive = false;
        var session_id: ?[]const u8 = null;
        var role_mask: u8 = 0;
        var query_parts: std.ArrayList([]const u8) = .empty;
        defer query_parts.deinit(gpa);
        while (index < args.len) {
            const arg = args[index];
            if (std.mem.eql(u8, arg, "--limit")) {
                index += 1;
                if (index >= args.len) return Error.MissingArgument;
                limit = parseSearchLimit(args[index]) catch return Error.InvalidLimit;
                index += 1;
            } else if (std.mem.startsWith(u8, arg, "--limit=")) {
                limit = parseSearchLimit(arg["--limit=".len..]) catch return Error.InvalidLimit;
                index += 1;
            } else if (std.mem.eql(u8, arg, "--case-sensitive")) {
                case_sensitive = true;
                index += 1;
            } else if (std.mem.eql(u8, arg, "--session")) {
                index += 1;
                if (index >= args.len) return Error.MissingArgument;
                session_id = args[index];
                index += 1;
            } else if (std.mem.startsWith(u8, arg, "--session=")) {
                session_id = arg["--session=".len..];
                if (session_id.?.len == 0) return Error.MissingArgument;
                index += 1;
            } else if (std.mem.eql(u8, arg, "--role")) {
                index += 1;
                if (index >= args.len) return Error.MissingArgument;
                role_mask |= roleBit(args[index]) orelse return Error.InvalidRole;
                index += 1;
            } else if (std.mem.startsWith(u8, arg, "--role=")) {
                role_mask |= roleBit(arg["--role=".len..]) orelse return Error.InvalidRole;
                index += 1;
            } else if (std.mem.startsWith(u8, arg, "-")) {
                return Error.UnknownOption;
            } else {
                try query_parts.append(gpa, arg);
                index += 1;
            }
        }
        if (query_parts.items.len == 0) return Error.EmptyPrompt;
        const text = try joinArgs(gpa, query_parts.items);
        parsed.owned_text = text;
        if (std.mem.trim(u8, text, " \t\r\n").len == 0) return Error.EmptyPrompt;
        parsed.action = .{ .search = .{
            .query = text,
            .limit = limit,
            .case_sensitive = case_sensitive,
            .session_id = session_id,
            .role_mask = role_mask,
        } };
    } else if (std.mem.eql(u8, action_name, "open") or std.mem.eql(u8, action_name, "show")) {
        if (index >= args.len) return Error.MissingArgument;
        const session_id = args[index];
        index += 1;
        if (index != args.len) return Error.UnknownOption;
        parsed.action = .{ .open = .{ .session_id = session_id } };
    } else if (std.mem.eql(u8, action_name, "prompt")) {
        if (index >= args.len) return Error.MissingArgument;
        const session_id = args[index];
        index += 1;
        if (index >= args.len) return Error.EmptyPrompt;
        const text = try joinArgs(gpa, args[index..]);
        parsed.owned_text = text;
        if (std.mem.trim(u8, text, " \t\r\n").len == 0) return Error.EmptyPrompt;
        parsed.action = .{ .prompt = .{ .session_id = session_id, .text = text } };
    } else if (std.mem.eql(u8, action_name, "abort")) {
        if (index >= args.len) return Error.MissingArgument;
        const session_id = args[index];
        index += 1;
        if (index != args.len) return Error.UnknownOption;
        parsed.action = .{ .abort = .{ .session_id = session_id } };
    } else if (std.mem.eql(u8, action_name, "model")) {
        if (index + 1 >= args.len) return Error.MissingArgument;
        const session_id = args[index];
        const model = try parseModel(args[index + 1]);
        index += 2;
        if (index != args.len) return Error.UnknownOption;
        parsed.action = .{ .set_model = .{ .session_id = session_id, .model = model } };
    } else if (std.mem.eql(u8, action_name, "thinking")) {
        if (index + 1 >= args.len) return Error.MissingArgument;
        const session_id = args[index];
        const thinking = msg.parseThinkingLevel(args[index + 1]) orelse return Error.InvalidThinkingLevel;
        index += 2;
        if (index != args.len) return Error.UnknownOption;
        parsed.action = .{ .set_thinking = .{ .session_id = session_id, .thinking = thinking } };
    } else if (std.mem.eql(u8, action_name, "create")) {
        var create: @FieldType(Action, "create") = .{};
        while (index < args.len) {
            const arg = args[index];
            if (std.mem.eql(u8, arg, "--cwd")) {
                index += 1;
                if (index >= args.len) return Error.MissingArgument;
                create.cwd = args[index];
                index += 1;
            } else if (std.mem.eql(u8, arg, "--name")) {
                index += 1;
                if (index >= args.len) return Error.MissingArgument;
                create.name = args[index];
                index += 1;
            } else if (std.mem.eql(u8, arg, "--model")) {
                index += 1;
                if (index >= args.len) return Error.MissingArgument;
                create.model = try parseModel(args[index]);
                index += 1;
            } else if (std.mem.eql(u8, arg, "--thinking")) {
                index += 1;
                if (index >= args.len) return Error.MissingArgument;
                create.thinking = msg.parseThinkingLevel(args[index]) orelse return Error.InvalidThinkingLevel;
                index += 1;
            } else if (std.mem.eql(u8, arg, "--prompt")) {
                index += 1;
                if (index >= args.len) return Error.EmptyPrompt;
                const text = try joinArgs(gpa, args[index..]);
                parsed.owned_text = text;
                if (std.mem.trim(u8, text, " \t\r\n").len == 0) return Error.EmptyPrompt;
                create.prompt = text;
                index = args.len;
            } else return Error.UnknownOption;
        }
        parsed.action = .{ .create = create };
    } else return Error.UnknownAction;

    return parsed;
}

fn parseSearchLimit(raw: []const u8) !usize {
    const value = std.fmt.parseInt(usize, raw, 10) catch return Error.InvalidLimit;
    if (value == 0 or value > 100_000) return Error.InvalidLimit;
    return value;
}

fn roleBit(raw: []const u8) ?u8 {
    if (std.ascii.eqlIgnoreCase(raw, "user")) return 1 << 0;
    if (std.ascii.eqlIgnoreCase(raw, "assistant")) return 1 << 1;
    if (std.ascii.eqlIgnoreCase(raw, "tool")) return 1 << 2;
    return null;
}

fn roleEnabled(mask: u8, role: client_pkg.search.Role) bool {
    if (mask == 0) return true;
    return (mask & switch (role) {
        .user => @as(u8, 1 << 0),
        .assistant => @as(u8, 1 << 1),
        .tool => @as(u8, 1 << 2),
    }) != 0;
}

fn parseTimeout(raw: []const u8) !u64 {
    const value = std.fmt.parseInt(u64, raw, 10) catch return Error.InvalidTimeout;
    if (value == 0 or value > MAX_TIMEOUT_MS) return Error.InvalidTimeout;
    return value;
}

fn parseModel(raw: []const u8) !msg.ModelRef {
    const slash = std.mem.indexOfScalar(u8, raw, '/') orelse return Error.InvalidModel;
    if (slash == 0 or slash + 1 >= raw.len) return Error.InvalidModel;
    return .{ .provider = raw[0..slash], .id = raw[slash + 1 ..] };
}

fn joinArgs(gpa: std.mem.Allocator, args: []const []const u8) ![]u8 {
    var total: usize = 0;
    for (args, 0..) |part, i| {
        total = try std.math.add(usize, total, part.len);
        if (i != 0) total = try std.math.add(usize, total, 1);
    }
    const joined = try gpa.alloc(u8, total);
    var offset: usize = 0;
    for (args, 0..) |part, i| {
        if (i != 0) {
            joined[offset] = ' ';
            offset += 1;
        }
        @memcpy(joined[offset..][0..part.len], part);
        offset += part.len;
    }
    return joined;
}

pub fn execute(gpa: std.mem.Allocator, io: Io, args: []const []const u8, writer: *Io.Writer) !RunResult {
    return executeWithEnvironment(gpa, io, null, args, writer);
}

pub fn executeWithEnvironment(
    gpa: std.mem.Allocator,
    io: Io,
    environ: ?*const std.process.Environ.Map,
    args: []const []const u8,
    writer: *Io.Writer,
) !RunResult {
    if (args.len == 0 or std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h")) {
        try usage(writer);
        return .{};
    }
    var parsed = parse(gpa, args) catch |err| {
        try writer.print("remote: {s}\n", .{errorMessage(err)});
        try usage(writer);
        return .{ .exit_code = 2 };
    };
    defer parsed.deinit();

    if (parsed.tcp_address) |address| {
        var transport: client_pkg.secure_tcp.SecureTcpTransport = undefined;
        try transport.connect(gpa, io, .{
            .address = address,
            .tls = parsed.tls,
            .proxy = parsed.proxy,
            .disable_proxy = parsed.disable_proxy,
            .environ = environ,
        });
        defer transport.deinit();
        return executeConnected(gpa, io, &transport, parsed, writer);
    }

    var transport: client_pkg.unix.UnixTransport = undefined;
    try transport.connect(io, .{ .path = parsed.socket_path.? });
    defer transport.deinit();
    return executeConnected(gpa, io, &transport, parsed, writer);
}

fn executeConnected(gpa: std.mem.Allocator, io: Io, transport: anytype, parsed: Parsed, writer: *Io.Writer) !RunResult {
    var client = try client_pkg.Client.init(gpa, .{});
    defer client.deinit();
    try client.connect(transport.byteTransport());

    var scratch: [64 * 1024]u8 = undefined;
    try pumpHandshake(io, transport, &client, &scratch, parsed.timeout_ms);

    return switch (parsed.action) {
        .list => blk: {
            const snapshot = client.snapshot() orelse return Error.OperationDidNotSettle;
            try renderSessionList(writer, snapshot.sessions, parsed.json);
            break :blk .{};
        },
        .search => |action| runSearch(gpa, io, transport, &client, &scratch, parsed.timeout_ms, parsed.json, action, writer),
        .open => |action| runBoundAction(gpa, io, transport, &client, &scratch, parsed.timeout_ms, parsed.json, .{ .open = action }, writer),
        .create => |action| runBoundAction(gpa, io, transport, &client, &scratch, parsed.timeout_ms, parsed.json, .{ .create = action }, writer),
        .prompt => |action| runBoundAction(gpa, io, transport, &client, &scratch, parsed.timeout_ms, parsed.json, .{ .prompt = action }, writer),
        .abort => |action| runBoundAction(gpa, io, transport, &client, &scratch, parsed.timeout_ms, parsed.json, .{ .abort = action }, writer),
        .set_model => |action| runBoundAction(gpa, io, transport, &client, &scratch, parsed.timeout_ms, parsed.json, .{ .set_model = action }, writer),
        .set_thinking => |action| runBoundAction(gpa, io, transport, &client, &scratch, parsed.timeout_ms, parsed.json, .{ .set_thinking = action }, writer),
    };
}

fn runSearch(
    gpa: std.mem.Allocator,
    io: Io,
    transport: anytype,
    client: *client_pkg.Client,
    scratch: []u8,
    timeout_ms: u64,
    json: bool,
    action: @FieldType(Action, "search"),
    writer: *Io.Writer,
) !RunResult {
    var ids: std.ArrayList([]u8) = .empty;
    defer {
        for (ids.items) |id| gpa.free(id);
        ids.deinit(gpa);
    }
    if (action.session_id) |session_id| {
        try ids.append(gpa, try gpa.dupe(u8, session_id));
    } else {
        const snapshot = client.snapshot() orelse return Error.OperationDidNotSettle;
        for (snapshot.sessions) |session| try ids.append(gpa, try gpa.dupe(u8, session.id));
    }

    var role_buffer: [3]client_pkg.search.Role = undefined;
    var role_count: usize = 0;
    inline for (.{ client_pkg.search.Role.user, client_pkg.search.Role.assistant, client_pkg.search.Role.tool }) |role| {
        if (roleEnabled(action.role_mask, role)) {
            role_buffer[role_count] = role;
            role_count += 1;
        }
    }
    const roles: []const client_pkg.search.Role = if (action.role_mask == 0) &.{} else role_buffer[0..role_count];

    var all_hits: std.ArrayList(client_pkg.search.Hit) = .empty;
    defer {
        for (all_hits.items) |*hit| hit.deinit(gpa);
        all_hits.deinit(gpa);
    }
    var scanned_sessions: usize = 0;
    var scanned_items: usize = 0;
    var failed_sessions: usize = 0;

    for (ids.items) |session_id| {
        const acquisition = client_pkg.session_handle.Acquisition.begin(gpa, client, session_id, .shared, null) catch {
            failed_sessions += 1;
            continue;
        };
        while (acquisition.status() == .pending) {
            const timeout = absoluteTimeout(io, timeout_ms);
            if (!try transport.pumpOnceUntil(client, scratch, timeout)) {
                client.disconnect();
                acquisition.destroy() catch {};
                return Error.ConnectionClosed;
            }
        }
        if (acquisition.status() != .succeeded) {
            failed_sessions += 1;
            try acquisition.destroy();
            continue;
        }
        const handle = acquisition.takeHandle() orelse {
            try acquisition.destroy();
            failed_sessions += 1;
            continue;
        };
        try acquisition.destroy();

        const snapshot = handle.snapshot() orelse {
            disposeSearchHandle(io, transport, client, handle, scratch, timeout_ms) catch {};
            failed_sessions += 1;
            continue;
        };
        scanned_sessions += 1;
        scanned_items += snapshot.transcript.len;
        const local_hits = client_pkg.search.searchSnapshot(gpa, snapshot, action.query, .{
            .limit = action.limit,
            .case_sensitive = action.case_sensitive,
            .roles = roles,
        }) catch |err| {
            disposeSearchHandle(io, transport, client, handle, scratch, timeout_ms) catch {};
            return err;
        };
        appendOwnedSearchHits(gpa, &all_hits, local_hits) catch |err| {
            disposeSearchHandle(io, transport, client, handle, scratch, timeout_ms) catch {};
            return err;
        };
        try disposeSearchHandle(io, transport, client, handle, scratch, timeout_ms);
    }

    client_pkg.search.sortHits(all_hits.items);
    if (all_hits.items.len > action.limit) {
        for (all_hits.items[action.limit..]) |*hit| hit.deinit(gpa);
        all_hits.shrinkRetainingCapacity(action.limit);
    }
    try renderSearchResults(writer, action.query, all_hits.items, scanned_sessions, scanned_items, failed_sessions, json);
    return .{ .exit_code = if (all_hits.items.len == 0) 1 else 0 };
}

fn appendOwnedSearchHits(
    gpa: std.mem.Allocator,
    destination: *std.ArrayList(client_pkg.search.Hit),
    source: []client_pkg.search.Hit,
) !void {
    var moved: usize = 0;
    errdefer {
        for (source[moved..]) |*remaining| remaining.deinit(gpa);
        gpa.free(source);
    }
    for (source) |*hit| {
        try destination.append(gpa, hit.*);
        hit.* = undefined;
        moved += 1;
    }
    gpa.free(source);
}

fn disposeSearchHandle(
    io: Io,
    transport: anytype,
    client: *client_pkg.Client,
    handle: *client_pkg.session_handle.SessionHandle,
    scratch: []u8,
    timeout_ms: u64,
) !void {
    _ = handle.beginDispose(null) catch |err| {
        client.disconnect();
        if (handle.canDestroy()) try handle.destroy();
        return err;
    };
    if (!handle.canDestroy()) {
        const timeout = absoluteTimeout(io, @min(timeout_ms, 5_000));
        while (!handle.canDestroy()) {
            if (!try transport.pumpOnceUntil(client, scratch, timeout)) {
                client.disconnect();
                break;
            }
        }
    }
    if (!handle.canDestroy()) {
        client.disconnect();
        if (!handle.canDestroy()) return Error.OperationDidNotSettle;
    }
    try handle.destroy();
}

fn renderSearchResults(
    writer: *Io.Writer,
    query: []const u8,
    hits: []const client_pkg.search.Hit,
    scanned_sessions: usize,
    scanned_items: usize,
    failed_sessions: usize,
    json: bool,
) !void {
    if (json) {
        try writer.writeAll("{\"query\":");
        try writeJsonString(writer, query);
        try writer.print(",\"scannedSessions\":{d},\"scannedItems\":{d},\"failedSessions\":{d},\"hits\":[", .{
            scanned_sessions,
            scanned_items,
            failed_sessions,
        });
        for (hits, 0..) |hit, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.writeAll("{\"sessionId\":");
            try writeJsonString(writer, hit.session_id);
            try writer.writeAll(",\"sessionName\":");
            try writeJsonString(writer, hit.session_name);
            try writer.writeAll(",\"itemId\":");
            try writeJsonString(writer, hit.item_id);
            try writer.writeAll(",\"role\":");
            try writeJsonString(writer, client_pkg.search.roleName(hit.role));
            try writer.print(",\"timestamp\":{d},\"score\":{d},\"snippet\":", .{ hit.timestamp, hit.score });
            try writeJsonString(writer, hit.snippet);
            try writer.writeByte('}');
        }
        try writer.writeAll("]}\n");
        return;
    }
    for (hits) |hit| {
        try writer.print("{s}\t{s}\t{s}\t{s}\n", .{
            hit.session_id,
            client_pkg.search.roleName(hit.role),
            hit.item_id,
            hit.snippet,
        });
    }
    try writer.print("# {d} hit(s); scanned {d} item(s) in {d} session(s); failed {d}\n", .{
        hits.len,
        scanned_items,
        scanned_sessions,
        failed_sessions,
    });
}

fn pumpHandshake(io: Io, transport: anytype, client: *client_pkg.Client, scratch: []u8, timeout_ms: u64) !void {
    const timeout = absoluteTimeout(io, timeout_ms);
    while (!client.connected()) {
        if (!try transport.pumpOnceUntil(client, scratch, timeout)) return Error.ConnectionClosed;
    }
}

const BoundAction = union(enum) {
    open: @FieldType(Action, "open"),
    create: @FieldType(Action, "create"),
    prompt: @FieldType(Action, "prompt"),
    abort: @FieldType(Action, "abort"),
    set_model: @FieldType(Action, "set_model"),
    set_thinking: @FieldType(Action, "set_thinking"),
};

fn runBoundAction(
    gpa: std.mem.Allocator,
    io: Io,
    transport: anytype,
    client: *client_pkg.Client,
    scratch: []u8,
    timeout_ms: u64,
    json: bool,
    action: BoundAction,
    writer: *Io.Writer,
) !RunResult {
    const remote = try remote_mod.RemoteSession.create(gpa, client, .{});
    var destroyed = false;
    defer if (!destroyed) {
        _ = remote.beginDispose();
        client.disconnect();
        remote.destroy() catch {};
    };

    switch (action) {
        .open => |value| {
            _ = try remote.beginOpen(value.session_id);
            if (!try pumpRemote(io, transport, client, remote, scratch, timeout_ms, writer)) return .{ .exit_code = 1 };
            try renderSnapshot(writer, remote.snapshot().?, json, .transcript);
        },
        .create => |value| {
            _ = try remote.beginCreate(value.cwd, value.name, value.model, value.thinking);
            if (!try pumpRemote(io, transport, client, remote, scratch, timeout_ms, writer)) return .{ .exit_code = 1 };
            if (value.prompt) |prompt| {
                _ = try remote.beginSubmit(prompt);
                if (!try pumpRemote(io, transport, client, remote, scratch, timeout_ms, writer)) return .{ .exit_code = 1 };
                try renderSnapshot(writer, remote.snapshot().?, json, .last_assistant);
            } else try renderSnapshot(writer, remote.snapshot().?, json, .summary);
        },
        .prompt => |value| {
            _ = try remote.beginOpen(value.session_id);
            if (!try pumpRemote(io, transport, client, remote, scratch, timeout_ms, writer)) return .{ .exit_code = 1 };
            _ = try remote.beginSubmit(value.text);
            if (!try pumpRemote(io, transport, client, remote, scratch, timeout_ms, writer)) return .{ .exit_code = 1 };
            try renderSnapshot(writer, remote.snapshot().?, json, .last_assistant);
        },
        .abort => |value| {
            _ = try remote.beginOpen(value.session_id);
            if (!try pumpRemote(io, transport, client, remote, scratch, timeout_ms, writer)) return .{ .exit_code = 1 };
            _ = try remote.beginAbort();
            if (remote.lifecycle() == .busy and !try pumpRemote(io, transport, client, remote, scratch, timeout_ms, writer)) return .{ .exit_code = 1 };
            try renderSnapshot(writer, remote.snapshot().?, json, .summary);
        },
        .set_model => |value| {
            _ = try remote.beginOpen(value.session_id);
            if (!try pumpRemote(io, transport, client, remote, scratch, timeout_ms, writer)) return .{ .exit_code = 1 };
            _ = try remote.beginSetModel(value.model);
            if (!try pumpRemote(io, transport, client, remote, scratch, timeout_ms, writer)) return .{ .exit_code = 1 };
            try renderSnapshot(writer, remote.snapshot().?, json, .summary);
        },
        .set_thinking => |value| {
            _ = try remote.beginOpen(value.session_id);
            if (!try pumpRemote(io, transport, client, remote, scratch, timeout_ms, writer)) return .{ .exit_code = 1 };
            _ = try remote.beginSetThinking(value.thinking);
            if (!try pumpRemote(io, transport, client, remote, scratch, timeout_ms, writer)) return .{ .exit_code = 1 };
            try renderSnapshot(writer, remote.snapshot().?, json, .summary);
        },
    }

    try disposeRemote(io, transport, client, remote, scratch, @min(timeout_ms, 5_000));
    try remote.destroy();
    destroyed = true;
    return .{};
}

fn pumpRemote(
    io: Io,
    transport: anytype,
    client: *client_pkg.Client,
    remote: *remote_mod.RemoteSession,
    scratch: []u8,
    timeout_ms: u64,
    writer: *Io.Writer,
) !bool {
    const timeout = absoluteTimeout(io, timeout_ms);
    while (remote.lifecycle() == .busy) {
        if (!try transport.pumpOnceUntil(client, scratch, timeout)) return Error.ConnectionClosed;
    }
    if (remote.lastFailure()) |failure| {
        try writer.print("remote: {s}", .{failure.message});
        if (failure.code) |code| try writer.print(" ({s})", .{@tagName(code)});
        try writer.writeByte('\n');
        return false;
    }
    return remote.lifecycle() == .ready;
}

fn disposeRemote(
    io: Io,
    transport: anytype,
    client: *client_pkg.Client,
    remote: *remote_mod.RemoteSession,
    scratch: []u8,
    timeout_ms: u64,
) !void {
    _ = remote.beginDispose();
    if (remote.canDestroy()) return;
    const timeout = absoluteTimeout(io, timeout_ms);
    while (!remote.canDestroy()) {
        if (!try transport.pumpOnceUntil(client, scratch, timeout)) break;
    }
    if (!remote.canDestroy()) {
        client.disconnect();
        if (!remote.canDestroy()) return Error.OperationDidNotSettle;
    }
}

fn absoluteTimeout(io: Io, timeout_ms: u64) Io.Timeout {
    const bounded: i64 = @intCast(@min(timeout_ms, @as(u64, std.math.maxInt(i64))));
    return .{ .deadline = .fromNow(io, .{ .raw = Io.Duration.fromMilliseconds(bounded), .clock = .awake }) };
}

const RenderMode = enum { summary, transcript, last_assistant };

fn renderSessionList(writer: *Io.Writer, sessions: []const msg.SessionMetadata, json: bool) !void {
    if (json) {
        try writer.writeByte('[');
        for (sessions, 0..) |session, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.writeAll("{\"id\":");
            try writeJsonString(writer, session.id);
            try writer.print(",\"createdAt\":{d},\"updatedAt\":", .{session.created_at});
            if (session.updated_at) |value| try writer.print("{d}", .{value}) else try writer.writeAll("null");
            try writer.writeAll(",\"name\":");
            if (session.session_name) |value| try writeJsonString(writer, value) else try writer.writeAll("null");
            try writer.writeAll(",\"cwd\":");
            if (session.cwd) |value| try writeJsonString(writer, value) else try writer.writeAll("null");
            try writer.writeByte('}');
        }
        try writer.writeAll("]\n");
        return;
    }
    if (sessions.len == 0) {
        try writer.writeAll("(no remote sessions)\n");
        return;
    }
    for (sessions) |session| {
        try writer.writeAll(session.id);
        if (session.session_name) |name| try writer.print("\t{s}", .{name});
        if (session.cwd) |cwd| try writer.print("\t{s}", .{cwd});
        try writer.writeByte('\n');
    }
}

fn renderSnapshot(writer: *Io.Writer, snapshot: *const msg.SessionSnapshot, json: bool, mode: RenderMode) !void {
    if (json) return renderSnapshotJson(writer, snapshot);
    switch (mode) {
        .summary => try writer.print("{s}\t{s}\t{s}/{s}\t{s}\n", .{
            snapshot.id,
            @tagName(snapshot.phase),
            snapshot.model.provider,
            snapshot.model.id,
            @tagName(snapshot.thinking_level),
        }),
        .transcript => {
            try writer.print("session {s} ({s}/{s}, {s})\n", .{
                snapshot.id,
                snapshot.model.provider,
                snapshot.model.id,
                @tagName(snapshot.thinking_level),
            });
            for (snapshot.transcript) |item| try renderTranscriptItem(writer, item);
        },
        .last_assistant => {
            var index = snapshot.transcript.len;
            while (index > 0) {
                index -= 1;
                switch (snapshot.transcript[index]) {
                    .assistant => |assistant| {
                        var wrote = false;
                        for (assistant.content) |content| switch (content) {
                            .text => |text| {
                                try writer.writeAll(text.text);
                                wrote = true;
                            },
                            else => {},
                        };
                        if (wrote) try writer.writeByte('\n') else try writer.print("assistant finished with status {s}\n", .{@tagName(assistant.status)});
                        return;
                    },
                    else => {},
                }
            }
            try writer.writeAll("(no assistant response)\n");
        },
    }
}

fn renderTranscriptItem(writer: *Io.Writer, item: msg.TranscriptItem) !void {
    switch (item) {
        .user => |user| {
            try writer.writeAll("> ");
            for (user.content) |content| switch (content) {
                .text => |text| try writer.writeAll(text.text),
                .image => |image| try writer.print("[image:{s}]", .{image.mime_type}),
            };
            try writer.writeByte('\n');
        },
        .assistant => |assistant| {
            for (assistant.content) |content| switch (content) {
                .text => |text| try writer.writeAll(text.text),
                .thinking => |thinking| try writer.print("[thinking] {s}", .{thinking.thinking}),
                .toolCall => |tool| try writer.print("[tool call: {s}]", .{tool.tool_name}),
            };
            try writer.writeByte('\n');
        },
        .tool => |tool| {
            try writer.print("[tool {s}: {s}] ", .{ tool.tool_name, @tagName(tool.status) });
            for (tool.content) |content| switch (content) {
                .text => |text| try writer.writeAll(text.text),
                .image => |image| try writer.print("[image:{s}]", .{image.mime_type}),
            };
            try writer.writeByte('\n');
        },
    }
}

fn renderSnapshotJson(writer: *Io.Writer, snapshot: *const msg.SessionSnapshot) !void {
    try writer.writeAll("{\"id\":");
    try writeJsonString(writer, snapshot.id);
    try writer.writeAll(",\"name\":");
    if (snapshot.name) |value| try writeJsonString(writer, value) else try writer.writeAll("null");
    try writer.writeAll(",\"cwd\":");
    try writeJsonString(writer, snapshot.cwd);
    try writer.print(",\"phase\":\"{s}\",\"model\":{{\"provider\":", .{@tagName(snapshot.phase)});
    try writeJsonString(writer, snapshot.model.provider);
    try writer.writeAll(",\"id\":");
    try writeJsonString(writer, snapshot.model.id);
    try writer.print("}},\"thinkingLevel\":\"{s}\",\"revision\":{d},\"transcript\":[", .{ @tagName(snapshot.thinking_level), snapshot.revision });
    for (snapshot.transcript, 0..) |item, index| {
        if (index != 0) try writer.writeByte(',');
        try renderTranscriptItemJson(writer, item);
    }
    try writer.writeAll("]}\n");
}

fn renderTranscriptItemJson(writer: *Io.Writer, item: msg.TranscriptItem) !void {
    switch (item) {
        .user => |user| {
            try writer.writeAll("{\"role\":\"user\",\"id\":");
            try writeJsonString(writer, user.id);
            try writer.writeAll(",\"content\":[");
            for (user.content, 0..) |content, index| {
                if (index != 0) try writer.writeByte(',');
                switch (content) {
                    .text => |text| {
                        try writer.writeAll("{\"type\":\"text\",\"text\":");
                        try writeJsonString(writer, text.text);
                    },
                    .image => |image| {
                        try writer.writeAll("{\"type\":\"image\",\"mimeType\":");
                        try writeJsonString(writer, image.mime_type);
                    },
                }
                try writer.writeByte('}');
            }
            try writer.writeAll("]}");
        },
        .assistant => |assistant| {
            try writer.writeAll("{\"role\":\"assistant\",\"id\":");
            try writeJsonString(writer, assistant.id);
            try writer.print(",\"status\":\"{s}\",\"content\":[", .{@tagName(assistant.status)});
            for (assistant.content, 0..) |content, index| {
                if (index != 0) try writer.writeByte(',');
                switch (content) {
                    .text => |text| {
                        try writer.writeAll("{\"type\":\"text\",\"text\":");
                        try writeJsonString(writer, text.text);
                    },
                    .thinking => |thinking| {
                        try writer.writeAll("{\"type\":\"thinking\",\"thinking\":");
                        try writeJsonString(writer, thinking.thinking);
                    },
                    .toolCall => |tool| {
                        try writer.writeAll("{\"type\":\"toolCall\",\"toolName\":");
                        try writeJsonString(writer, tool.tool_name);
                    },
                }
                try writer.writeByte('}');
            }
            try writer.writeAll("]}");
        },
        .tool => |tool| {
            try writer.writeAll("{\"role\":\"tool\",\"id\":");
            try writeJsonString(writer, tool.id);
            try writer.writeAll(",\"toolName\":");
            try writeJsonString(writer, tool.tool_name);
            try writer.print(",\"status\":\"{s}\",\"isError\":{s},\"content\":[", .{ @tagName(tool.status), if (tool.is_error) "true" else "false" });
            for (tool.content, 0..) |content, index| {
                if (index != 0) try writer.writeByte(',');
                switch (content) {
                    .text => |text| {
                        try writer.writeAll("{\"type\":\"text\",\"text\":");
                        try writeJsonString(writer, text.text);
                    },
                    .image => |image| {
                        try writer.writeAll("{\"type\":\"image\",\"mimeType\":");
                        try writeJsonString(writer, image.mime_type);
                    },
                }
                try writer.writeByte('}');
            }
            try writer.writeAll("]}");
        },
    }
}

fn writeJsonString(writer: *Io.Writer, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, writer);
}

fn errorMessage(err: anyerror) []const u8 {
    return switch (err) {
        Error.MissingEndpoint => "exactly one of --socket PATH or --connect ADDRESS:PORT is required",
        Error.ConflictingEndpoint => "--socket and --connect cannot be used together",
        Error.TransportOptionRequiresTcp => "--tls, --proxy, and --no-proxy require --connect",
        Error.ConflictingProxyOptions => "--proxy and --no-proxy cannot be used together",
        Error.MissingAction => "an action is required",
        Error.MissingArgument => "an action or option is missing its argument",
        Error.UnknownOption => "unknown option or trailing argument",
        Error.UnknownAction => "unknown remote action",
        Error.InvalidTimeout => "--timeout-ms must be between 1 and 86400000",
        Error.InvalidModel => "model must be PROVIDER/ID",
        Error.InvalidThinkingLevel => "invalid thinking level",
        Error.InvalidLimit => "search limit must be between 1 and 100000",
        Error.InvalidRole => "search role must be user, assistant, or tool",
        Error.EmptyPrompt => "prompt or search text must not be empty",
        else => @errorName(err),
    };
}

test "remote CLI parses list prompt and create options" {
    const gpa = std.testing.allocator;
    var list = try parse(gpa, &.{ "--socket", "/tmp/pi.sock", "--json", "list" });
    defer list.deinit();
    try std.testing.expect(list.json);
    try std.testing.expect(list.action == .list);

    var tcp_list = try parse(gpa, &.{ "--connect", "127.0.0.1:3141", "--tls", "--proxy", "http://proxy.example:3128", "list" });
    defer tcp_list.deinit();
    try std.testing.expectEqualStrings("127.0.0.1:3141", tcp_list.tcp_address.?);
    try std.testing.expect(tcp_list.socket_path == null);
    try std.testing.expect(tcp_list.tls);
    try std.testing.expectEqualStrings("http://proxy.example:3128", tcp_list.proxy.?);

    var prompt = try parse(gpa, &.{ "--socket=/tmp/pi.sock", "--timeout-ms=42", "prompt", "s1", "hello", "world" });
    defer prompt.deinit();
    try std.testing.expectEqual(@as(u64, 42), prompt.timeout_ms);
    try std.testing.expectEqualStrings("hello world", prompt.action.prompt.text);

    var create = try parse(gpa, &.{ "--socket", "/tmp/pi.sock", "create", "--cwd", "/work", "--name", "demo", "--model", "test/model", "--thinking", "high", "--prompt", "do", "it" });
    defer create.deinit();
    try std.testing.expectEqualStrings("/work", create.action.create.cwd.?);
    try std.testing.expectEqualStrings("demo", create.action.create.name.?);
    try std.testing.expectEqualStrings("test", create.action.create.model.?.provider);
    try std.testing.expectEqual(msg.ThinkingLevel.high, create.action.create.thinking.?);
    try std.testing.expectEqualStrings("do it", create.action.create.prompt.?);

    var search = try parse(gpa, &.{ "--connect", "localhost:3141", "--json", "search", "--limit", "12", "--session=s1", "--role", "assistant", "--role=tool", "migration", "plan" });
    defer search.deinit();
    try std.testing.expect(search.action == .search);
    try std.testing.expectEqual(@as(usize, 12), search.action.search.limit);
    try std.testing.expectEqualStrings("s1", search.action.search.session_id.?);
    try std.testing.expectEqualStrings("migration plan", search.action.search.query);
    try std.testing.expect(search.action.search.role_mask & (1 << 1) != 0);
    try std.testing.expect(search.action.search.role_mask & (1 << 2) != 0);
}

test "remote CLI rejects malformed arguments" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(Error.MissingEndpoint, parse(gpa, &.{"list"}));
    try std.testing.expectError(Error.ConflictingEndpoint, parse(gpa, &.{ "--socket", "/tmp/pi.sock", "--connect", "127.0.0.1:3141", "list" }));
    try std.testing.expectError(Error.TransportOptionRequiresTcp, parse(gpa, &.{ "--socket", "/tmp/pi.sock", "--tls", "list" }));
    try std.testing.expectError(Error.ConflictingProxyOptions, parse(gpa, &.{ "--connect", "localhost:3141", "--proxy", "http://proxy", "--no-proxy", "list" }));
    try std.testing.expectError(Error.InvalidTimeout, parse(gpa, &.{ "--socket", "/tmp/pi.sock", "--timeout-ms", "0", "list" }));
    try std.testing.expectError(Error.InvalidModel, parse(gpa, &.{ "--socket", "/tmp/pi.sock", "model", "s1", "bad" }));
    try std.testing.expectError(Error.InvalidThinkingLevel, parse(gpa, &.{ "--socket", "/tmp/pi.sock", "thinking", "s1", "enormous" }));
    try std.testing.expectError(Error.EmptyPrompt, parse(gpa, &.{ "--socket", "/tmp/pi.sock", "prompt", "s1" }));
    try std.testing.expectError(Error.EmptyPrompt, parse(gpa, &.{ "--socket", "/tmp/pi.sock", "search" }));
    try std.testing.expectError(Error.InvalidLimit, parse(gpa, &.{ "--socket", "/tmp/pi.sock", "search", "--limit", "0", "x" }));
    try std.testing.expectError(Error.InvalidRole, parse(gpa, &.{ "--socket", "/tmp/pi.sock", "search", "--role", "system", "x" }));
}

test "remote CLI renders lists and snapshots as valid JSON" {
    var output: Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try renderSessionList(&output.writer, &.{.{
        .id = "s1",
        .created_at = 1,
        .updated_at = 2,
        .session_name = "demo",
        .cwd = "/tmp",
    }}, true);
    var parsed_list = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output.written(), .{});
    defer parsed_list.deinit();
    try std.testing.expect(parsed_list.value == .array);

    output.clearRetainingCapacity();
    const transcript = [_]msg.TranscriptItem{
        .{ .user = .{ .id = "u1", .content = &.{.{ .text = .{ .text = "hello" } }}, .timestamp = 1 } },
        .{ .assistant = .{
            .id = "a1",
            .content = &.{.{ .text = .{ .text = "world" } }},
            .model = .{ .provider = "test", .id = "model" },
            .timestamp = 2,
            .status = .complete,
            .stop_reason = .stop,
        } },
    };
    const snapshot = msg.SessionSnapshot{
        .id = "s1",
        .cwd = "/tmp",
        .created_at = 1,
        .updated_at = 2,
        .phase = .idle,
        .model = .{ .provider = "test", .id = "model" },
        .thinking_level = .off,
        .attached = true,
        .locked = false,
        .revision = 2,
        .transcript = &transcript,
        .queued_steer = &.{},
        .queued_steer_count = 0,
    };
    try renderSnapshot(&output.writer, &snapshot, true, .transcript);
    var parsed_snapshot = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output.written(), .{});
    defer parsed_snapshot.deinit();
    try std.testing.expect(parsed_snapshot.value == .object);
}

test "remote CLI renders search results as valid JSON" {
    const gpa = std.testing.allocator;
    var hit = client_pkg.search.Hit{
        .session_id = try gpa.dupe(u8, "s1"),
        .session_name = try gpa.dupe(u8, "demo"),
        .item_id = try gpa.dupe(u8, "a1"),
        .role = .assistant,
        .timestamp = 42,
        .snippet = try gpa.dupe(u8, "migration complete"),
        .score = 1234,
        .item_ordinal = 1,
    };
    defer hit.deinit(gpa);
    var output: Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    try renderSearchResults(&output.writer, "migration", &.{hit}, 1, 2, 0, true);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, output.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.object.get("hits").?.array.items.len);
}
