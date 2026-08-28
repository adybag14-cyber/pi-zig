//! Production command surface for the native SQLite session repository.
//!
//! The ordinary `pi` executable remains free of a system SQLite dependency.
//! `zig build sqlite` produces the companion `pi-sqlite` executable, which
//! opens/migrates canonical databases and exposes durable list/search/show and
//! integrity operations through the repository's public API.
const std = @import("std");
const Io = std.Io;
const repository_mod = @import("sqlite/repository.zig");
const schema = @import("sqlite/schema.zig");
const types = @import("sqlite/types.zig");
const config = @import("../config.zig");

pub const Error = error{
    MissingDatabase,
    MissingAction,
    MissingArgument,
    UnknownAction,
    UnknownOption,
    InvalidLimit,
    InvalidEntryType,
};

pub const RunResult = struct { exit_code: u8 = 0 };

const Kind = enum { help, version, init, list, search, show, doctor };

const Parsed = struct {
    gpa: std.mem.Allocator,
    kind: Kind = .help,
    db_path: ?[]const u8 = null,
    json: bool = false,
    cwd: ?[]const u8 = null,
    limit: usize = 100,
    entry_types: std.ArrayList(types.EntryType) = .empty,
    operand: ?[]const u8 = null,
    owned_operand: ?[]u8 = null,

    fn deinit(self: *Parsed) void {
        self.entry_types.deinit(self.gpa);
        if (self.owned_operand) |value| self.gpa.free(value);
        self.* = undefined;
    }
};

pub fn usage(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\Usage:
        \\  pi-sqlite --help
        \\  pi-sqlite --version
        \\  pi-sqlite --db PATH init [--json]
        \\  pi-sqlite --db PATH list [--json] [--cwd PATH] [--limit N]
        \\  pi-sqlite --db PATH search [--json] [--limit N] [--type TYPE] QUERY...
        \\  pi-sqlite --db PATH show [--json] [--limit N] SESSION
        \\  pi-sqlite --db PATH doctor [--json]
        \\
        \\Entry types: message, model_change, thinking_level_change,
        \\             active_tools_change, compaction, branch_summary, custom
        \\
        \\Build with: zig build sqlite
        \\
    );
}

pub fn execute(
    gpa: std.mem.Allocator,
    io: Io,
    args: []const []const u8,
    writer: *Io.Writer,
) !RunResult {
    var parsed = parse(gpa, args) catch |err| {
        try writer.print("pi-sqlite: {s}\n\n", .{@errorName(err)});
        try usage(writer);
        return .{ .exit_code = 2 };
    };
    defer parsed.deinit();
    if (parsed.kind == .help) {
        try usage(writer);
        return .{};
    }
    if (parsed.kind == .version) {
        try writer.print("pi-sqlite {s}\n", .{config.version});
        return .{};
    }

    var repo = repository_mod.Repository.open(gpa, io, parsed.db_path.?) catch |err| {
        try writer.print("pi-sqlite: cannot open {s}: {s}\n", .{ parsed.db_path.?, @errorName(err) });
        return .{ .exit_code = 1 };
    };
    defer repo.deinit();

    return switch (parsed.kind) {
        .help, .version => unreachable,
        .init => executeInit(&repo, parsed, writer),
        .list => executeList(gpa, &repo, parsed, writer),
        .search => executeSearch(gpa, &repo, parsed, writer),
        .show => executeShow(gpa, &repo, parsed, writer),
        .doctor => executeDoctor(gpa, &repo, parsed, writer),
    };
}

fn parse(gpa: std.mem.Allocator, args: []const []const u8) !Parsed {
    if (args.len == 0) return Error.MissingAction;
    var parsed = Parsed{ .gpa = gpa };
    errdefer parsed.deinit();
    var operands: std.ArrayList([]const u8) = .empty;
    defer operands.deinit(gpa);
    var saw_action = false;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "help")) {
            parsed.kind = .help;
            saw_action = true;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "version")) {
            parsed.kind = .version;
            saw_action = true;
        } else if (std.mem.eql(u8, arg, "--db")) {
            i += 1;
            if (i >= args.len) return Error.MissingArgument;
            parsed.db_path = args[i];
        } else if (std.mem.startsWith(u8, arg, "--db=")) {
            parsed.db_path = arg["--db=".len..];
        } else if (std.mem.eql(u8, arg, "--json")) {
            parsed.json = true;
        } else if (std.mem.eql(u8, arg, "--cwd")) {
            i += 1;
            if (i >= args.len) return Error.MissingArgument;
            parsed.cwd = args[i];
        } else if (std.mem.startsWith(u8, arg, "--cwd=")) {
            parsed.cwd = arg["--cwd=".len..];
        } else if (std.mem.eql(u8, arg, "--limit")) {
            i += 1;
            if (i >= args.len) return Error.MissingArgument;
            parsed.limit = std.fmt.parseInt(usize, args[i], 10) catch return Error.InvalidLimit;
        } else if (std.mem.startsWith(u8, arg, "--limit=")) {
            parsed.limit = std.fmt.parseInt(usize, arg["--limit=".len..], 10) catch return Error.InvalidLimit;
        } else if (std.mem.eql(u8, arg, "--type")) {
            i += 1;
            if (i >= args.len) return Error.MissingArgument;
            const entry_type = types.EntryType.parse(args[i]) orelse return Error.InvalidEntryType;
            try appendUniqueType(gpa, &parsed.entry_types, entry_type);
        } else if (std.mem.startsWith(u8, arg, "--type=")) {
            const entry_type = types.EntryType.parse(arg["--type=".len..]) orelse return Error.InvalidEntryType;
            try appendUniqueType(gpa, &parsed.entry_types, entry_type);
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return Error.UnknownOption;
        } else if (!saw_action) {
            parsed.kind = if (std.mem.eql(u8, arg, "init") or std.mem.eql(u8, arg, "migrate"))
                .init
            else if (std.mem.eql(u8, arg, "list") or std.mem.eql(u8, arg, "ls"))
                .list
            else if (std.mem.eql(u8, arg, "search") or std.mem.eql(u8, arg, "find"))
                .search
            else if (std.mem.eql(u8, arg, "show") or std.mem.eql(u8, arg, "open"))
                .show
            else if (std.mem.eql(u8, arg, "doctor") or std.mem.eql(u8, arg, "check"))
                .doctor
            else
                return Error.UnknownAction;
            saw_action = true;
        } else {
            try operands.append(gpa, arg);
        }
    }
    if (!saw_action) return Error.MissingAction;
    if (parsed.kind != .help and parsed.kind != .version and (parsed.db_path == null or parsed.db_path.?.len == 0)) return Error.MissingDatabase;
    switch (parsed.kind) {
        .help, .version => if (operands.items.len != 0) return Error.UnknownOption,
        .init, .list, .doctor => if (operands.items.len != 0) return Error.UnknownOption,
        .show => {
            if (operands.items.len != 1) return Error.MissingArgument;
            parsed.operand = operands.items[0];
        },
        .search => {
            if (operands.items.len == 0) return Error.MissingArgument;
            parsed.owned_operand = try joinArgs(gpa, operands.items);
            parsed.operand = parsed.owned_operand.?;
        },
    }
    if (parsed.cwd != null and parsed.kind != .list) return Error.UnknownOption;
    if (parsed.entry_types.items.len > 0 and parsed.kind != .search) return Error.UnknownOption;
    return parsed;
}

fn appendUniqueType(gpa: std.mem.Allocator, list: *std.ArrayList(types.EntryType), value: types.EntryType) !void {
    for (list.items) |existing| if (existing == value) return;
    try list.append(gpa, value);
}

fn joinArgs(gpa: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (parts, 0..) |part, index| {
        if (index > 0) try out.append(gpa, ' ');
        try out.appendSlice(gpa, part);
    }
    return out.toOwnedSlice(gpa);
}

fn executeInit(repo: *repository_mod.Repository, parsed: Parsed, writer: *Io.Writer) !RunResult {
    if (parsed.json) {
        try writer.writeAll("{\"ok\":true,\"database\":");
        try writeJsonString(writer, repo.path);
        try writer.writeAll(",\"sqliteVersion\":");
        try writeJsonString(writer, @import("sqlite/ffi.zig").Database.version());
        try writer.writeAll("}\n");
    } else {
        try writer.print("Initialized {s} (SQLite {s})\n", .{ repo.path, @import("sqlite/ffi.zig").Database.version() });
    }
    return .{};
}

fn executeList(gpa: std.mem.Allocator, repo: *repository_mod.Repository, parsed: Parsed, writer: *Io.Writer) !RunResult {
    const sessions = try repo.listSessions(parsed.cwd);
    defer deinitSessions(gpa, sessions);
    const count = @min(sessions.len, parsed.limit);
    if (parsed.json) {
        try writer.writeAll("{\"database\":");
        try writeJsonString(writer, repo.path);
        try writer.print(",\"total\":{d},\"sessions\":[", .{sessions.len});
        for (sessions[0..count], 0..) |session, index| {
            if (index > 0) try writer.writeByte(',');
            try writeSessionJson(writer, session);
        }
        try writer.writeAll("]}\n");
    } else if (count == 0) {
        try writer.print("No SQLite sessions in {s}\n", .{repo.path});
    } else {
        for (sessions[0..count]) |session| {
            try writer.print("{s}\t{s}\t{s}\t{d}\n", .{
                session.id,
                session.name orelse "-",
                session.cwd,
                session.created_at_ms,
            });
        }
        try writer.print("# {d} of {d} session(s)\n", .{ count, sessions.len });
    }
    return .{};
}

fn executeSearch(gpa: std.mem.Allocator, repo: *repository_mod.Repository, parsed: Parsed, writer: *Io.Writer) !RunResult {
    const entry_types: ?[]const types.EntryType = if (parsed.entry_types.items.len > 0) parsed.entry_types.items else null;
    const hits = try repo.search(parsed.operand.?, .{ .entry_types = entry_types, .limit = parsed.limit });
    defer deinitSearchHits(gpa, hits);
    if (parsed.json) {
        try writer.writeAll("{\"query\":");
        try writeJsonString(writer, parsed.operand.?);
        try writer.writeAll(",\"hits\":[");
        for (hits, 0..) |hit, index| {
            if (index > 0) try writer.writeByte(',');
            try writer.writeAll("{\"sessionId\":");
            try writeJsonString(writer, hit.session_id);
            try writer.writeAll(",\"entryId\":");
            try writeJsonString(writer, hit.entry_id);
            try writer.print(",\"timestampMs\":{d},\"score\":{d},\"name\":", .{ hit.timestamp_ms, hit.score });
            if (hit.name) |name| try writeJsonString(writer, name) else try writer.writeAll("null");
            try writer.writeAll(",\"cwd\":");
            try writeJsonString(writer, hit.cwd);
            try writer.writeAll(",\"snippet\":");
            const snippet = try hitSnippet(gpa, repo, hit, parsed.operand.?);
            defer gpa.free(snippet);
            try writeJsonString(writer, snippet);
            try writer.writeByte('}');
        }
        try writer.writeAll("]}\n");
    } else {
        for (hits) |hit| {
            const snippet = try hitSnippet(gpa, repo, hit, parsed.operand.?);
            defer gpa.free(snippet);
            try writer.print("{s}\t{s}\t{s}\t{s}\n", .{ hit.session_id, hit.entry_id, hit.name orelse "-", snippet });
        }
        try writer.print("# {d} hit(s)\n", .{hits.len});
    }
    return .{ .exit_code = if (hits.len == 0) 1 else 0 };
}

fn hitSnippet(
    gpa: std.mem.Allocator,
    repo: *repository_mod.Repository,
    hit: types.SearchHit,
    query: []const u8,
) ![]u8 {
    var entry = (try repo.getEntry(hit.session_id, hit.entry_id)) orelse return gpa.dupe(u8, "");
    defer entry.deinit(gpa);
    return snippetForQuery(gpa, entry.payload_json, query, 96);
}

fn executeShow(gpa: std.mem.Allocator, repo: *repository_mod.Repository, parsed: Parsed, writer: *Io.Writer) !RunResult {
    var metadata = repo.getSession(parsed.operand.?) catch |err| switch (err) {
        error.SessionNotFound => {
            try writer.print("Session not found: {s}\n", .{parsed.operand.?});
            return .{ .exit_code = 1 };
        },
        else => return err,
    };
    defer metadata.deinit(gpa);
    const stats = try repo.getStats(metadata.id);
    const lanes = try repo.listLanes(metadata.id);
    defer deinitLanes(gpa, lanes);
    const entries = try repo.findEntries(metadata.id, .{ .order = .newest_first, .limit = parsed.limit });
    defer deinitEntries(gpa, entries);

    if (parsed.json) {
        try writer.writeAll("{\"session\":");
        try writeSessionJson(writer, metadata);
        try writer.print(",\"stats\":{{\"messageCount\":{d},\"cachedTokens\":{d},\"uncachedTokens\":{d},\"totalTokens\":{d},\"costTotal\":{d}}},\"lanes\":[", .{
            stats.message_count,
            stats.cached_tokens,
            stats.uncached_tokens,
            stats.total_tokens,
            stats.cost_total,
        });
        for (lanes, 0..) |lane, index| {
            if (index > 0) try writer.writeByte(',');
            try writer.writeAll("{\"name\":");
            try writeJsonString(writer, lane.name);
            try writer.writeAll(",\"leafId\":");
            if (lane.leaf_id) |id| try writeJsonString(writer, id) else try writer.writeAll("null");
            try writer.writeAll(",\"openOperationId\":");
            if (lane.open_operation_id) |id| try writeJsonString(writer, id) else try writer.writeAll("null");
            try writer.writeByte('}');
        }
        try writer.writeAll("],\"entries\":[");
        for (entries, 0..) |entry, index| {
            if (index > 0) try writer.writeByte(',');
            try writeEntryJson(writer, entry);
        }
        try writer.writeAll("]}\n");
    } else {
        try writer.print("Session: {s}\nName: {s}\nCWD: {s}\nCreated: {d}\nMessages: {d}\nTokens: {d}\nCost: {d}\n", .{
            metadata.id,
            metadata.name orelse "-",
            metadata.cwd,
            metadata.created_at_ms,
            stats.message_count,
            stats.total_tokens,
            stats.cost_total,
        });
        try writer.print("Lanes: {d}; newest entries: {d}\n\n", .{ lanes.len, entries.len });
        for (entries) |entry| {
            const compact = try compactUtf8(gpa, entry.payload_json, 180);
            defer gpa.free(compact);
            try writer.print("{d}\t{s}\t{s}\t{s}\n", .{ entry.seq, entry.entry_type.wireName(), entry.id, compact });
        }
    }
    return .{};
}

fn executeDoctor(gpa: std.mem.Allocator, repo: *repository_mod.Repository, parsed: Parsed, writer: *Io.Writer) !RunResult {
    _ = gpa;
    const required_tables = [_][]const u8{
        "sessions",      "entries", "session_sequences", "session_stats", "branch_entries",
        "lanes",         "records", "lane_moves",        "facts",         "branch_tips",
        "writer_leases",
    };
    var missing: usize = 0;
    for (required_tables) |table| {
        if (!try schema.tableExists(&repo.db, table)) missing += 1;
    }

    var integrity = try repo.db.prepare("PRAGMA integrity_check");
    defer integrity.deinit();
    var integrity_ok = true;
    var messages: std.ArrayList([]u8) = .empty;
    defer {
        for (messages.items) |message| repo.gpa.free(message);
        messages.deinit(repo.gpa);
    }
    while (try integrity.step() == .row) {
        const text = (try integrity.columnText(0)) orelse "invalid integrity result";
        if (!std.mem.eql(u8, text, "ok")) integrity_ok = false;
        try messages.append(repo.gpa, try repo.gpa.dupe(u8, text));
    }
    const ok = integrity_ok and missing == 0;
    if (parsed.json) {
        try writer.print("{{\"ok\":{s},\"database\":", .{if (ok) "true" else "false"});
        try writeJsonString(writer, repo.path);
        try writer.print(",\"missingTables\":{d},\"integrity\":[", .{missing});
        for (messages.items, 0..) |message, index| {
            if (index > 0) try writer.writeByte(',');
            try writeJsonString(writer, message);
        }
        try writer.writeAll("]}\n");
    } else {
        try writer.print("Database: {s}\nSchema: {s} ({d} missing table(s))\nIntegrity: {s}\n", .{
            repo.path,
            if (missing == 0) "ok" else "invalid",
            missing,
            if (integrity_ok) "ok" else "invalid",
        });
        if (!integrity_ok) for (messages.items) |message| try writer.print("  {s}\n", .{message});
    }
    return .{ .exit_code = if (ok) 0 else 1 };
}

fn writeSessionJson(writer: *Io.Writer, session: types.SessionMetadata) !void {
    try writer.writeAll("{\"id\":");
    try writeJsonString(writer, session.id);
    try writer.print(",\"createdAtMs\":{d},\"cwd\":", .{session.created_at_ms});
    try writeJsonString(writer, session.cwd);
    try writer.writeAll(",\"path\":");
    try writeJsonString(writer, session.path);
    try writer.writeAll(",\"parentSessionId\":");
    if (session.parent_session_id) |id| try writeJsonString(writer, id) else try writer.writeAll("null");
    try writer.writeAll(",\"name\":");
    if (session.name) |name| try writeJsonString(writer, name) else try writer.writeAll("null");
    try writer.writeAll(",\"metadata\":");
    if (session.metadata_json) |raw| try writer.writeAll(raw) else try writer.writeAll("null");
    try writer.writeByte('}');
}

fn writeEntryJson(writer: *Io.Writer, entry: types.Entry) !void {
    try writer.writeAll("{\"id\":");
    try writeJsonString(writer, entry.id);
    try writer.print(",\"seq\":{d},\"parentId\":", .{entry.seq});
    if (entry.parent_id) |id| try writeJsonString(writer, id) else try writer.writeAll("null");
    try writer.writeAll(",\"type\":");
    try writeJsonString(writer, entry.entry_type.wireName());
    try writer.print(",\"timestampMs\":{d},\"customType\":", .{entry.timestamp_ms});
    if (entry.custom_type) |custom| try writeJsonString(writer, custom) else try writer.writeAll("null");
    try writer.writeAll(",\"payload\":");
    try writer.writeAll(entry.payload_json);
    try writer.writeByte('}');
}

fn compactUtf8(gpa: std.mem.Allocator, input: []const u8, max_bytes: usize) ![]u8 {
    if (input.len <= max_bytes) return gpa.dupe(u8, input);
    var end = @min(max_bytes, input.len);
    while (end > 0 and end < input.len and (input[end] & 0xc0) == 0x80) end -= 1;
    return std.fmt.allocPrint(gpa, "{s}…", .{input[0..end]});
}

fn snippetForQuery(gpa: std.mem.Allocator, input: []const u8, query: []const u8, context: usize) ![]u8 {
    const index = findAsciiInsensitive(input, query) orelse return compactUtf8(gpa, input, context * 2);
    var start = index -| context;
    var end = @min(input.len, index + query.len + context);
    while (start > 0 and start < input.len and (input[start] & 0xc0) == 0x80) start -= 1;
    while (end < input.len and (input[end] & 0xc0) == 0x80) end += 1;
    return if (start == 0 and end == input.len)
        gpa.dupe(u8, input)
    else if (start == 0)
        std.fmt.allocPrint(gpa, "{s}…", .{input[0..end]})
    else if (end == input.len)
        std.fmt.allocPrint(gpa, "…{s}", .{input[start..]})
    else
        std.fmt.allocPrint(gpa, "…{s}…", .{input[start..end]});
}

fn findAsciiInsensitive(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > haystack.len) return null;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        var equal = true;
        for (needle, 0..) |byte, offset| {
            if (std.ascii.toLower(haystack[index + offset]) != std.ascii.toLower(byte)) {
                equal = false;
                break;
            }
        }
        if (equal) return index;
    }
    return null;
}

fn writeJsonString(writer: *Io.Writer, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, writer);
}

fn deinitSessions(gpa: std.mem.Allocator, values: []types.SessionMetadata) void {
    for (values) |*value| value.deinit(gpa);
    gpa.free(values);
}

fn deinitEntries(gpa: std.mem.Allocator, values: []types.Entry) void {
    for (values) |*value| value.deinit(gpa);
    gpa.free(values);
}

fn deinitLanes(gpa: std.mem.Allocator, values: []types.Lane) void {
    for (values) |*value| value.deinit(gpa);
    gpa.free(values);
}

fn deinitSearchHits(gpa: std.mem.Allocator, values: []types.SearchHit) void {
    for (values) |*value| value.deinit(gpa);
    gpa.free(values);
}

fn requireCliIntegrationTests() !void {
    const value = std.process.Environ.getAlloc(
        std.testing.environ,
        std.testing.allocator,
        "PI_SQLITE_CLI_TESTS",
    ) catch |err| switch (err) {
        error.EnvironmentVariableMissing => return error.SkipZigTest,
        else => return err,
    };
    defer std.testing.allocator.free(value);
    if (!std.mem.eql(u8, value, "1")) return error.SkipZigTest;
}

test "SQLite CLI parses global options around actions" {
    const gpa = std.testing.allocator;
    var parsed = try parse(gpa, &.{ "--db", "demo.sqlite", "search", "--limit=5", "--type", "message", "hello", "world" });
    defer parsed.deinit();
    try std.testing.expectEqual(Kind.search, parsed.kind);
    try std.testing.expectEqualStrings("demo.sqlite", parsed.db_path.?);
    try std.testing.expectEqual(@as(usize, 5), parsed.limit);
    try std.testing.expectEqualStrings("hello world", parsed.operand.?);
}

test "SQLite CLI exposes standard help and version without a database" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var output: Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    var result = try execute(gpa, io, &.{"--version"}, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expectEqualStrings("pi-sqlite " ++ config.version ++ "\n", output.written());
    output.clearRetainingCapacity();
    result = try execute(gpa, io, &.{"--help"}, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "pi-sqlite --version") != null);
}

test "SQLite CLI init list search show and doctor" {
    try requireCliIntegrationTests();
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const db_path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "sessions.sqlite" });
    defer gpa.free(db_path);

    {
        var repo = try repository_mod.Repository.open(gpa, io, db_path);
        defer repo.deinit();
        var metadata = try repo.createSession(.{ .id = "cli-s", .cwd = "/project" });
        defer metadata.deinit(gpa);
        try repo.setName("cli-s", "CLI SQLite", null);
        var entry = try repo.appendEntry("cli-s", "main", .{
            .id = "entry-s",
            .entry_type = .message,
            .payload_json = "{\"message\":{\"role\":\"user\",\"content\":\"native database needle\"}}",
        }, null);
        defer entry.deinit(gpa);
    }

    var output: Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    var result = try execute(gpa, io, &.{ "--db", db_path, "list", "--json" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "CLI SQLite") != null);

    output.clearRetainingCapacity();
    result = try execute(gpa, io, &.{ "search", "--db", db_path, "needle", "--json" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "native database needle") != null);

    output.clearRetainingCapacity();
    result = try execute(gpa, io, &.{ "--db", db_path, "show", "cli-s", "--json" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "messageCount") != null);

    output.clearRetainingCapacity();
    result = try execute(gpa, io, &.{ "--db", db_path, "doctor", "--json" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\"ok\":true") != null);
}
