//! Production commands for inspecting and searching local JSONL sessions.
//!
//! These commands deliberately operate through the storage-neutral agent
//! session/search APIs rather than re-parsing JSONL in the CLI. That keeps the
//! same branch, metadata and ownership semantics available to future SQLite or
//! remote adapters.
const std = @import("std");
const Io = std.Io;
const session_mod = @import("../agent/session.zig");
const search_mod = @import("../agent/search.zig");
const migration_mod = @import("../agent/session_migration.zig");

pub const Error = error{
    MissingAction,
    MissingArgument,
    UnknownAction,
    UnknownOption,
    InvalidLimit,
    InvalidEntryType,
    SessionNotFound,
    ForceRequired,
};

pub const RunResult = struct {
    exit_code: u8 = 0,
};

const Kind = enum { help, list, search, show, stats, tree, rename, delete, migrate, doctor };

const Parsed = struct {
    gpa: std.mem.Allocator,
    kind: Kind,
    json: bool = false,
    raw: bool = false,
    limit: usize = 100,
    all_branches: bool = false,
    case_sensitive: bool = false,
    messages_only: bool = false,
    all_sessions: bool = false,
    dry_run: bool = false,
    force: bool = false,
    entry_types: std.ArrayList(session_mod.EntryType) = .empty,
    roles: std.ArrayList([]const u8) = .empty,
    operand: ?[]const u8 = null,
    value: ?[]const u8 = null,
    owned_operand: ?[]u8 = null,

    fn deinit(self: *Parsed) void {
        self.entry_types.deinit(self.gpa);
        self.roles.deinit(self.gpa);
        if (self.owned_operand) |value| self.gpa.free(value);
        self.* = undefined;
    }
};

pub fn usage(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\Usage:
        \\  pi sessions list [--json] [--limit N]
        \\  pi sessions search [--json] [--limit N] [--all-branches]
        \\      [--case-sensitive] [--messages-only] [--type TYPE] [--role ROLE] QUERY...
        \\  pi sessions show [--json|--raw] [--all-branches] SESSION
        \\  pi sessions stats [--json] SESSION
        \\  pi sessions tree [--json] SESSION
        \\  pi sessions rename [--json] SESSION NAME...
        \\  pi sessions delete [--json] --force SESSION
        \\  pi sessions migrate [--json] [--dry-run] (--all | SESSION)
        \\  pi sessions doctor [--json]
        \\
        \\Entry types: message, compaction, branch_summary, session_info, label,
        \\             custom, custom_message, model_change, thinking_level_change
        \\
    );
}

pub fn execute(
    gpa: std.mem.Allocator,
    io: Io,
    session_dir: []const u8,
    args: []const []const u8,
    writer: *Io.Writer,
) !RunResult {
    var parsed = parse(gpa, args) catch |err| {
        try writer.print("sessions: {s}\n\n", .{@errorName(err)});
        try usage(writer);
        return .{ .exit_code = 2 };
    };
    defer parsed.deinit();

    return switch (parsed.kind) {
        .help => blk: {
            try usage(writer);
            break :blk .{};
        },
        .list => executeList(gpa, io, session_dir, parsed, writer),
        .search => executeSearch(gpa, io, session_dir, parsed, writer),
        .show => executeShow(gpa, io, session_dir, parsed, writer),
        .stats => executeStats(gpa, io, session_dir, parsed, writer),
        .tree => executeTree(gpa, io, session_dir, parsed, writer),
        .rename => executeRename(gpa, io, session_dir, parsed, writer),
        .delete => executeDelete(gpa, io, session_dir, parsed, writer),
        .migrate => executeMigrate(gpa, io, session_dir, parsed, writer),
        .doctor => executeDoctor(gpa, io, session_dir, parsed, writer),
    };
}

fn parse(gpa: std.mem.Allocator, args: []const []const u8) !Parsed {
    if (args.len == 0) return Error.MissingAction;
    if (std.mem.eql(u8, args[0], "help") or std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h")) {
        return .{ .gpa = gpa, .kind = .help };
    }
    var parsed = Parsed{
        .gpa = gpa,
        .kind = if (std.mem.eql(u8, args[0], "list"))
            .list
        else if (std.mem.eql(u8, args[0], "search") or std.mem.eql(u8, args[0], "find"))
            .search
        else if (std.mem.eql(u8, args[0], "show") or std.mem.eql(u8, args[0], "open"))
            .show
        else if (std.mem.eql(u8, args[0], "stats") or std.mem.eql(u8, args[0], "status"))
            .stats
        else if (std.mem.eql(u8, args[0], "tree"))
            .tree
        else if (std.mem.eql(u8, args[0], "rename"))
            .rename
        else if (std.mem.eql(u8, args[0], "delete") or std.mem.eql(u8, args[0], "remove"))
            .delete
        else if (std.mem.eql(u8, args[0], "migrate"))
            .migrate
        else if (std.mem.eql(u8, args[0], "doctor") or std.mem.eql(u8, args[0], "check"))
            .doctor
        else
            return Error.UnknownAction,
    };
    errdefer parsed.deinit();

    var operands: std.ArrayList([]const u8) = .empty;
    defer operands.deinit(gpa);
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            parsed.json = true;
        } else if (std.mem.eql(u8, arg, "--all")) {
            if (parsed.kind != .migrate) return Error.UnknownOption;
            parsed.all_sessions = true;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            if (parsed.kind != .migrate) return Error.UnknownOption;
            parsed.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--force")) {
            if (parsed.kind != .delete) return Error.UnknownOption;
            parsed.force = true;
        } else if (std.mem.eql(u8, arg, "--raw")) {
            if (parsed.kind != .show) return Error.UnknownOption;
            parsed.raw = true;
        } else if (std.mem.eql(u8, arg, "--all-branches")) {
            if (parsed.kind != .search and parsed.kind != .show) return Error.UnknownOption;
            parsed.all_branches = true;
        } else if (std.mem.eql(u8, arg, "--case-sensitive")) {
            if (parsed.kind != .search) return Error.UnknownOption;
            parsed.case_sensitive = true;
        } else if (std.mem.eql(u8, arg, "--messages-only")) {
            if (parsed.kind != .search) return Error.UnknownOption;
            parsed.messages_only = true;
        } else if (std.mem.eql(u8, arg, "--limit")) {
            if (parsed.kind != .list and parsed.kind != .search) return Error.UnknownOption;
            i += 1;
            if (i >= args.len) return Error.MissingArgument;
            parsed.limit = std.fmt.parseInt(usize, args[i], 10) catch return Error.InvalidLimit;
        } else if (std.mem.startsWith(u8, arg, "--limit=")) {
            if (parsed.kind != .list and parsed.kind != .search) return Error.UnknownOption;
            parsed.limit = std.fmt.parseInt(usize, arg["--limit=".len..], 10) catch return Error.InvalidLimit;
        } else if (std.mem.eql(u8, arg, "--type")) {
            if (parsed.kind != .search) return Error.UnknownOption;
            i += 1;
            if (i >= args.len) return Error.MissingArgument;
            const entry_type = search_mod.parseEntryType(args[i]) orelse return Error.InvalidEntryType;
            try appendUniqueType(gpa, &parsed.entry_types, entry_type);
        } else if (std.mem.startsWith(u8, arg, "--type=")) {
            if (parsed.kind != .search) return Error.UnknownOption;
            const entry_type = search_mod.parseEntryType(arg["--type=".len..]) orelse return Error.InvalidEntryType;
            try appendUniqueType(gpa, &parsed.entry_types, entry_type);
        } else if (std.mem.eql(u8, arg, "--role")) {
            if (parsed.kind != .search) return Error.UnknownOption;
            i += 1;
            if (i >= args.len) return Error.MissingArgument;
            try parsed.roles.append(gpa, args[i]);
        } else if (std.mem.startsWith(u8, arg, "--role=")) {
            if (parsed.kind != .search) return Error.UnknownOption;
            try parsed.roles.append(gpa, arg["--role=".len..]);
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return Error.UnknownOption;
        } else {
            try operands.append(gpa, arg);
        }
    }

    switch (parsed.kind) {
        .help, .list, .doctor => if (operands.items.len != 0) return Error.UnknownOption,
        .show => {
            if (operands.items.len != 1) return Error.MissingArgument;
            if (parsed.raw and parsed.json) return Error.UnknownOption;
            parsed.operand = operands.items[0];
        },
        .stats, .tree, .delete => {
            if (operands.items.len != 1) return Error.MissingArgument;
            if (parsed.kind == .delete and !parsed.force) return Error.ForceRequired;
            parsed.operand = operands.items[0];
        },
        .rename => {
            if (operands.items.len < 2) return Error.MissingArgument;
            parsed.operand = operands.items[0];
            const joined = try joinArgs(gpa, operands.items[1..]);
            parsed.owned_operand = joined;
            parsed.value = joined;
        },
        .migrate => {
            if (parsed.all_sessions) {
                if (operands.items.len != 0) return Error.UnknownOption;
            } else {
                if (operands.items.len != 1) return Error.MissingArgument;
                parsed.operand = operands.items[0];
            }
        },
        .search => {
            if (operands.items.len == 0) return Error.MissingArgument;
            const joined = try joinArgs(gpa, operands.items);
            parsed.owned_operand = joined;
            parsed.operand = joined;
        },
    }
    return parsed;
}

fn appendUniqueType(gpa: std.mem.Allocator, list: *std.ArrayList(session_mod.EntryType), value: session_mod.EntryType) !void {
    for (list.items) |existing| if (existing == value) return;
    try list.append(gpa, value);
}

fn joinArgs(gpa: std.mem.Allocator, values: []const []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (values, 0..) |value, i| {
        if (i > 0) try out.append(gpa, ' ');
        try out.appendSlice(gpa, value);
    }
    return try out.toOwnedSlice(gpa);
}

fn executeList(
    gpa: std.mem.Allocator,
    io: Io,
    session_dir: []const u8,
    parsed: Parsed,
    writer: *Io.Writer,
) !RunResult {
    const sessions = try session_mod.listSessions(gpa, io, session_dir);
    defer {
        for (sessions) |*info| info.deinit(gpa);
        gpa.free(sessions);
    }
    const count = @min(sessions.len, parsed.limit);
    if (parsed.json) {
        try writer.writeAll("{\"sessionDir\":");
        try writeJsonString(writer, session_dir);
        try writer.print(",\"total\":{d},\"sessions\":[", .{sessions.len});
        for (sessions[0..count], 0..) |info, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.writeAll("{\"id\":");
            try writeJsonString(writer, info.id);
            try writer.writeAll(",\"name\":");
            try writeJsonString(writer, info.name);
            try writer.writeAll(",\"cwd\":");
            try writeJsonString(writer, info.cwd);
            try writer.writeAll(",\"parentSessionPath\":");
            if (info.parent_session_path) |parent| try writeJsonString(writer, parent) else try writer.writeAll("null");
            try writer.writeAll(",\"created\":");
            try writeJsonString(writer, info.created_at);
            try writer.writeAll(",\"firstMessage\":");
            try writeJsonString(writer, info.first_message);
            try writer.writeAll(",\"allMessagesText\":");
            try writeJsonString(writer, info.all_messages_text);
            try writer.writeAll(",\"path\":");
            try writeJsonString(writer, info.path);
            try writer.print(",\"messageCount\":{d},\"valid\":{s},\"mtimeNs\":{d}}}", .{
                info.message_count,
                if (info.valid) "true" else "false",
                info.mtime_ns,
            });
        }
        try writer.writeAll("]}\n");
    } else if (count == 0) {
        try writer.print("No sessions in {s}\n", .{session_dir});
    } else {
        for (sessions[0..count]) |info| {
            try writer.print("{s}\t{s}\t{d}\t{s}\t{s}\n", .{
                if (info.valid) "OK" else "INVALID",
                info.id,
                info.message_count,
                if (info.name.len > 0) info.name else "-",
                info.path,
            });
        }
        try writer.print("# {d} of {d} session(s)\n", .{ count, sessions.len });
    }
    return .{};
}

fn executeSearch(
    gpa: std.mem.Allocator,
    io: Io,
    session_dir: []const u8,
    parsed: Parsed,
    writer: *Io.Writer,
) !RunResult {
    const query = parsed.operand.?;
    var result = try search_mod.searchDirectory(gpa, io, session_dir, query, .{
        .entry_types = parsed.entry_types.items,
        .roles = parsed.roles.items,
        .limit = parsed.limit,
        .active_branch_only = !parsed.all_branches,
        .case_sensitive = parsed.case_sensitive,
        .include_auxiliary = !parsed.messages_only,
    });
    defer result.deinit(gpa);

    if (parsed.json) {
        try writer.writeAll("{\"query\":");
        try writeJsonString(writer, query);
        try writer.print(",\"scannedSessions\":{d},\"scannedEntries\":{d},\"malformedSessions\":{d},\"hits\":[", .{
            result.scanned_sessions,
            result.scanned_entries,
            result.malformed_sessions,
        });
        for (result.hits, 0..) |hit, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.writeAll("{\"sessionId\":");
            try writeJsonString(writer, hit.session_id);
            try writer.writeAll(",\"sessionName\":");
            try writeJsonString(writer, hit.session_name);
            try writer.writeAll(",\"sessionPath\":");
            try writeJsonString(writer, hit.session_path);
            try writer.writeAll(",\"entryId\":");
            try writeJsonString(writer, hit.entry_id);
            try writer.writeAll(",\"entryType\":");
            try writeJsonString(writer, search_mod.entryTypeName(hit.entry_type));
            try writer.writeAll(",\"role\":");
            try writeJsonString(writer, hit.role);
            try writer.writeAll(",\"timestamp\":");
            try writeJsonString(writer, hit.timestamp);
            try writer.writeAll(",\"snippet\":");
            try writeJsonString(writer, hit.snippet);
            try writer.print(",\"score\":{d}}}", .{hit.score});
        }
        try writer.writeAll("]}\n");
    } else {
        for (result.hits) |hit| {
            try writer.print("{s}\t{s}\t{s}\t{s}\n", .{
                hit.session_id,
                search_mod.entryTypeName(hit.entry_type),
                if (hit.role.len > 0) hit.role else "-",
                hit.snippet,
            });
        }
        try writer.print("# {d} hit(s); scanned {d} entries in {d} session(s); malformed {d}\n", .{
            result.hits.len,
            result.scanned_entries,
            result.scanned_sessions,
            result.malformed_sessions,
        });
    }
    return .{ .exit_code = if (result.hits.len == 0) 1 else 0 };
}

fn executeShow(
    gpa: std.mem.Allocator,
    io: Io,
    session_dir: []const u8,
    parsed: Parsed,
    writer: *Io.Writer,
) !RunResult {
    const path = try resolveSessionPath(gpa, io, session_dir, parsed.operand.?);
    defer gpa.free(path);
    if (parsed.raw) {
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(32 * 1024 * 1024));
        defer gpa.free(raw);
        try writer.writeAll(raw);
        if (raw.len == 0 or raw[raw.len - 1] != '\n') try writer.writeByte('\n');
        return .{};
    }

    var session = try session_mod.Session.load(gpa, io, path);
    defer session.deinit();
    const entries = if (parsed.all_branches)
        try allEntryPointers(gpa, &session)
    else
        try session.branchEntries(gpa);
    defer gpa.free(entries);
    const active = try session.activeSettings(gpa);

    if (parsed.json) {
        try writer.writeAll("{\"id\":");
        try writeJsonString(writer, session.id);
        try writer.writeAll(",\"name\":");
        try writeJsonString(writer, session.name);
        try writer.writeAll(",\"cwd\":");
        try writeJsonString(writer, session.cwd);
        try writer.writeAll(",\"path\":");
        try writeJsonString(writer, path);
        try writer.print(",\"physicalEntryCount\":{d},\"selectedEntryCount\":{d},\"tipId\":", .{ session.entries.items.len, entries.len });
        if (session.tip_id) |tip| try writeJsonString(writer, tip) else try writer.writeAll("null");
        try writer.writeAll(",\"activeModel\":");
        if (active.provider != null and active.model_id != null) {
            try writer.writeAll("{\"provider\":");
            try writeJsonString(writer, active.provider.?);
            try writer.writeAll(",\"id\":");
            try writeJsonString(writer, active.model_id.?);
            try writer.writeByte('}');
        } else try writer.writeAll("null");
        try writer.writeAll(",\"thinkingLevel\":");
        if (active.thinking_level) |level| try writeJsonString(writer, level) else try writer.writeAll("null");
        try writer.writeAll(",\"entries\":[");
        for (entries, 0..) |entry, i| {
            if (i > 0) try writer.writeByte(',');
            try writeEntryJson(writer, entry);
        }
        try writer.writeAll("]}\n");
    } else {
        try writer.print("Session: {s}\nName: {s}\nCWD: {s}\nPath: {s}\nEntries: {d} selected / {d} physical\n", .{
            session.id,
            if (session.name.len > 0) session.name else "-",
            session.cwd,
            path,
            entries.len,
            session.entries.items.len,
        });
        if (active.provider != null and active.model_id != null) {
            try writer.print("Model: {s}/{s}\n", .{ active.provider.?, active.model_id.? });
        }
        if (active.thinking_level) |level| try writer.print("Thinking: {s}\n", .{level});
        try writer.writeByte('\n');
        for (entries) |entry| {
            const snippet = try compactText(gpa, entry.content, 180);
            defer gpa.free(snippet);
            try writer.print("{s}  {s:<22} {s:<12} {s}\n", .{
                if (entry.timestamp.len > 0) entry.timestamp else "-",
                search_mod.entryTypeName(entry.entry_type),
                if (entry.role.len > 0) entry.role else "-",
                snippet,
            });
        }
    }
    return .{};
}

fn executeStats(
    gpa: std.mem.Allocator,
    io: Io,
    session_dir: []const u8,
    parsed: Parsed,
    writer: *Io.Writer,
) !RunResult {
    const path = try resolveSessionPath(gpa, io, session_dir, parsed.operand.?);
    defer gpa.free(path);
    var session = try session_mod.Session.load(gpa, io, path);
    defer session.deinit();
    const value = session.stats();
    if (parsed.json) {
        try writer.writeAll("{\"sessionFile\":");
        try writeJsonString(writer, path);
        try writer.writeAll(",\"sessionId\":");
        try writeJsonString(writer, session.id);
        try writer.print(",\"userMessages\":{d},\"assistantMessages\":{d},\"toolCalls\":{d},\"toolResults\":{d},\"totalMessages\":{d}", .{
            value.user_messages,
            value.assistant_messages,
            value.tool_calls,
            value.tool_results,
            value.total_messages,
        });
        try writer.print(",\"tokens\":{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d},\"total\":{d}}},\"cost\":{d}}}\n", .{
            value.tokens.input,
            value.tokens.output,
            value.tokens.cache_read,
            value.tokens.cache_write,
            value.tokens.total,
            value.cost,
        });
    } else {
        try writer.print(
            "Session: {s}\nFile: {s}\nMessages: {d} user, {d} assistant, {d} tool results ({d} total)\nTool calls: {d}\nTokens: {d} input, {d} output, {d} cache read, {d} cache write ({d} total)\nCost: ${d:.6}\n",
            .{
                session.id,
                path,
                value.user_messages,
                value.assistant_messages,
                value.tool_results,
                value.total_messages,
                value.tool_calls,
                value.tokens.input,
                value.tokens.output,
                value.tokens.cache_read,
                value.tokens.cache_write,
                value.tokens.total,
                value.cost,
            },
        );
    }
    return .{};
}

fn executeTree(
    gpa: std.mem.Allocator,
    io: Io,
    session_dir: []const u8,
    parsed: Parsed,
    writer: *Io.Writer,
) !RunResult {
    const path = try resolveSessionPath(gpa, io, session_dir, parsed.operand.?);
    defer gpa.free(path);
    var session = try session_mod.Session.load(gpa, io, path);
    defer session.deinit();
    if (parsed.json) {
        try writer.writeAll("{\"sessionId\":");
        try writeJsonString(writer, session.id);
        try writer.writeAll(",\"tipId\":");
        if (session.tip_id) |tip| try writeJsonString(writer, tip) else try writer.writeAll("null");
        try writer.writeAll(",\"entries\":[");
        for (session.entries.items, 0..) |*entry, i| {
            if (i > 0) try writer.writeByte(',');
            try writeEntryJson(writer, entry);
        }
        try writer.writeAll("]}\n");
    } else {
        const tree = try session.treeSummary(gpa);
        defer gpa.free(tree);
        try writer.writeAll(tree);
    }
    return .{};
}

fn executeRename(
    gpa: std.mem.Allocator,
    io: Io,
    session_dir: []const u8,
    parsed: Parsed,
    writer: *Io.Writer,
) !RunResult {
    const path = try resolveSessionPath(gpa, io, session_dir, parsed.operand.?);
    defer gpa.free(path);
    var session = try session_mod.Session.load(gpa, io, path);
    defer session.deinit();
    _ = try session.appendSessionInfo(parsed.value.?);
    try session.save(io, path);
    if (parsed.json) {
        try writer.writeAll("{\"renamed\":true,\"sessionId\":");
        try writeJsonString(writer, session.id);
        try writer.writeAll(",\"name\":");
        try writeJsonString(writer, session.name);
        try writer.writeAll(",\"path\":");
        try writeJsonString(writer, path);
        try writer.writeAll("}\n");
    } else {
        try writer.print("Renamed {s} to {s}\n", .{ session.id, session.name });
    }
    return .{};
}

fn executeDelete(
    gpa: std.mem.Allocator,
    io: Io,
    session_dir: []const u8,
    parsed: Parsed,
    writer: *Io.Writer,
) !RunResult {
    const path = try resolveSessionPath(gpa, io, session_dir, parsed.operand.?);
    defer gpa.free(path);
    try std.Io.Dir.cwd().deleteFile(io, path);
    if (parsed.json) {
        try writer.writeAll("{\"deleted\":true,\"path\":");
        try writeJsonString(writer, path);
        try writer.writeAll("}\n");
    } else {
        try writer.print("Deleted {s}\n", .{path});
    }
    return .{};
}

const MigrationReport = struct {
    from_version: u32,
    changed: bool,
    applied: bool,
    skipped_malformed_lines: usize,
};

fn migrateOne(
    gpa: std.mem.Allocator,
    io: Io,
    path: []const u8,
    dry_run: bool,
) !MigrationReport {
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(32 * 1024 * 1024));
    defer gpa.free(raw);
    var migrated = try migration_mod.migrateJsonl(gpa, raw);
    defer migrated.deinit(gpa);

    // Never publish a migration that the durable v3 decoder cannot consume.
    var validated = try session_mod.Session.parseJsonl(gpa, migrated.jsonl);
    defer validated.deinit();
    if (migrated.changed and !dry_run) {
        var atomic = try std.Io.Dir.cwd().createFileAtomic(io, path, .{
            .make_path = true,
            .replace = true,
        });
        defer atomic.deinit(io);
        try atomic.file.writePositionalAll(io, migrated.jsonl, 0);
        try atomic.replace(io);
    }
    return .{
        .from_version = migrated.from_version,
        .changed = migrated.changed,
        .applied = migrated.changed and !dry_run,
        .skipped_malformed_lines = migrated.skipped_malformed_lines,
    };
}

fn executeMigrate(
    gpa: std.mem.Allocator,
    io: Io,
    session_dir: []const u8,
    parsed: Parsed,
    writer: *Io.Writer,
) !RunResult {
    var paths: std.ArrayList([]u8) = .empty;
    defer {
        for (paths.items) |path| gpa.free(path);
        paths.deinit(gpa);
    }
    if (parsed.all_sessions) {
        const infos = try session_mod.listSessions(gpa, io, session_dir);
        defer {
            for (infos) |*info| info.deinit(gpa);
            gpa.free(infos);
        }
        for (infos) |info| try paths.append(gpa, try gpa.dupe(u8, info.path));
    } else {
        try paths.append(gpa, try resolveSessionPath(gpa, io, session_dir, parsed.operand.?));
    }

    var changed: usize = 0;
    var applied: usize = 0;
    var failed: usize = 0;
    if (parsed.json) {
        try writer.writeAll("{\"dryRun\":");
        try writer.writeAll(if (parsed.dry_run) "true" else "false");
        try writer.writeAll(",\"sessions\":[");
    }
    for (paths.items, 0..) |path, index| {
        const report = migrateOne(gpa, io, path, parsed.dry_run) catch |err| {
            failed += 1;
            if (parsed.json) {
                if (index > 0) try writer.writeByte(',');
                try writer.writeAll("{\"path\":");
                try writeJsonString(writer, path);
                try writer.writeAll(",\"error\":");
                try writeJsonString(writer, @errorName(err));
                try writer.writeByte('}');
            } else {
                try writer.print("ERROR\t{s}\t{s}\n", .{ path, @errorName(err) });
            }
            continue;
        };
        if (report.changed) changed += 1;
        if (report.applied) applied += 1;
        if (parsed.json) {
            if (index > 0) try writer.writeByte(',');
            try writer.writeAll("{\"path\":");
            try writeJsonString(writer, path);
            try writer.print(",\"fromVersion\":{d},\"changed\":{s},\"applied\":{s},\"skippedMalformedLines\":{d}}}", .{
                report.from_version,
                if (report.changed) "true" else "false",
                if (report.applied) "true" else "false",
                report.skipped_malformed_lines,
            });
        } else {
            const state = if (report.applied) "MIGRATED" else if (report.changed) "WOULD_MIGRATE" else "CURRENT";
            try writer.print("{s}\t{s}\tv{d}\tskipped={d}\n", .{ state, path, report.from_version, report.skipped_malformed_lines });
        }
    }
    if (parsed.json) {
        try writer.print("],\"total\":{d},\"changed\":{d},\"applied\":{d},\"failed\":{d}}}\n", .{ paths.items.len, changed, applied, failed });
    } else {
        try writer.print("# total {d}; changed {d}; applied {d}; failed {d}\n", .{ paths.items.len, changed, applied, failed });
    }
    return .{ .exit_code = if (failed > 0) 1 else 0 };
}

fn executeDoctor(
    gpa: std.mem.Allocator,
    io: Io,
    session_dir: []const u8,
    parsed: Parsed,
    writer: *Io.Writer,
) !RunResult {
    const infos = try session_mod.listSessions(gpa, io, session_dir);
    defer {
        for (infos) |*info| info.deinit(gpa);
        gpa.free(infos);
    }
    var issues: std.ArrayList(Issue) = .empty;
    defer {
        for (issues.items) |*issue| issue.deinit(gpa);
        issues.deinit(gpa);
    }
    var valid: usize = 0;
    for (infos) |info| {
        var loaded = session_mod.Session.load(gpa, io, info.path) catch |err| {
            try issues.append(gpa, try Issue.init(gpa, info.path, @errorName(err)));
            continue;
        };
        defer loaded.deinit();
        validateTopology(gpa, &loaded) catch |err| {
            try issues.append(gpa, try Issue.init(gpa, info.path, @errorName(err)));
            continue;
        };
        valid += 1;
    }

    if (parsed.json) {
        try writer.print("{{\"sessionDir\":", .{});
        try writeJsonString(writer, session_dir);
        try writer.print(",\"total\":{d},\"valid\":{d},\"invalid\":{d},\"issues\":[", .{ infos.len, valid, issues.items.len });
        for (issues.items, 0..) |issue, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.writeAll("{\"path\":");
            try writeJsonString(writer, issue.path);
            try writer.writeAll(",\"error\":");
            try writeJsonString(writer, issue.message);
            try writer.writeByte('}');
        }
        try writer.writeAll("]}\n");
    } else {
        for (issues.items) |issue| try writer.print("INVALID\t{s}\t{s}\n", .{ issue.path, issue.message });
        try writer.print("# valid {d}; invalid {d}; total {d}\n", .{ valid, issues.items.len, infos.len });
    }
    return .{ .exit_code = if (issues.items.len > 0) 1 else 0 };
}

const Issue = struct {
    path: []u8,
    message: []u8,
    fn init(gpa: std.mem.Allocator, path: []const u8, message: []const u8) !Issue {
        return .{ .path = try gpa.dupe(u8, path), .message = try gpa.dupe(u8, message) };
    }
    fn deinit(self: *Issue, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        gpa.free(self.message);
        self.* = undefined;
    }
};

fn validateTopology(gpa: std.mem.Allocator, session: *const session_mod.Session) !void {
    var ids: std.StringHashMapUnmanaged(void) = .empty;
    defer ids.deinit(gpa);
    for (session.entries.items) |entry| {
        const put = try ids.getOrPut(gpa, entry.id);
        if (put.found_existing) return error.DuplicateEntryId;
    }
    for (session.entries.items) |entry| {
        if (entry.parent_id) |parent| if (!ids.contains(parent)) return error.UnknownParent;
    }
    if (session.tip_id) |tip| if (!ids.contains(tip)) return error.UnknownTip;

    // Walk every ancestry chain. A valid append-only tree cannot revisit an id.
    for (session.entries.items) |entry| {
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        defer seen.deinit(gpa);
        var current: ?[]const u8 = entry.id;
        while (current) |id| {
            const put = try seen.getOrPut(gpa, id);
            if (put.found_existing) return error.ParentCycle;
            const node = session.getEntry(id) orelse return error.UnknownParent;
            current = node.parent_id;
        }
    }
}

fn allEntryPointers(gpa: std.mem.Allocator, session: *const session_mod.Session) ![]const *const session_mod.SessionEntry {
    const result = try gpa.alloc(*const session_mod.SessionEntry, session.entries.items.len);
    for (session.entries.items, 0..) |*entry, i| result[i] = entry;
    return result;
}

fn resolveSessionPath(gpa: std.mem.Allocator, io: Io, session_dir: []const u8, path_or_id: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, path_or_id, '/') != null or
        std.mem.indexOfScalar(u8, path_or_id, '\\') != null or
        std.mem.endsWith(u8, path_or_id, ".jsonl"))
    {
        _ = std.Io.Dir.cwd().statFile(io, path_or_id, .{}) catch return Error.SessionNotFound;
        return try gpa.dupe(u8, path_or_id);
    }
    return (try session_mod.findExactSessionPath(gpa, io, session_dir, path_or_id)) orelse Error.SessionNotFound;
}

fn compactText(gpa: std.mem.Allocator, input: []const u8, max_bytes: usize) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var pending_space = false;
    var source_index: usize = 0;
    while (source_index < input.len) {
        const sequence_len = std.unicode.utf8ByteSequenceLength(input[source_index]) catch 1;
        const safe_len = if (source_index + sequence_len <= input.len) sequence_len else 1;
        const sequence = input[source_index .. source_index + safe_len];
        source_index += safe_len;
        const c = sequence[0];
        if (c == '\r' or c == '\n' or c == '\t') {
            pending_space = out.items.len > 0;
            continue;
        }
        if (pending_space and c != ' ') {
            if (out.items.len + 1 > max_bytes) break;
            try out.append(gpa, ' ');
        }
        pending_space = false;
        if (out.items.len + sequence.len > max_bytes) break;
        try out.appendSlice(gpa, sequence);
    }
    if (source_index < input.len) try out.appendSlice(gpa, "…");
    return try out.toOwnedSlice(gpa);
}

fn writeEntryJson(writer: *Io.Writer, entry: *const session_mod.SessionEntry) !void {
    try writer.writeAll("{\"id\":");
    try writeJsonString(writer, entry.id);
    try writer.writeAll(",\"parentId\":");
    if (entry.parent_id) |parent| try writeJsonString(writer, parent) else try writer.writeAll("null");
    try writer.writeAll(",\"type\":");
    try writeJsonString(writer, search_mod.entryTypeName(entry.entry_type));
    try writer.writeAll(",\"role\":");
    try writeJsonString(writer, entry.role);
    try writer.writeAll(",\"content\":");
    try writeJsonString(writer, entry.content);
    try writer.writeAll(",\"timestamp\":");
    try writeJsonString(writer, entry.timestamp);
    try writer.writeByte('}');
}

fn writeJsonString(writer: *Io.Writer, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, writer);
}

test "parse search options and query" {
    const gpa = std.testing.allocator;
    const args = [_][]const u8{ "search", "--limit", "7", "--all-branches", "--type", "message", "--role=assistant", "hello", "world" };
    var parsed = try parse(gpa, &args);
    defer parsed.deinit();
    try std.testing.expectEqual(Kind.search, parsed.kind);
    try std.testing.expectEqual(@as(usize, 7), parsed.limit);
    try std.testing.expect(parsed.all_branches);
    try std.testing.expectEqual(@as(usize, 1), parsed.entry_types.items.len);
    try std.testing.expectEqualStrings("hello world", parsed.operand.?);
}

test "session commands list search show and doctor" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    var session = try session_mod.Session.init(gpa, "cli-session", root);
    defer session.deinit();
    try session.setName("CLI demo");
    _ = try session.appendMessage(null, "user", "needle for native search", null, null);
    const path = try std.fs.path.join(gpa, &.{ root, "cli-session.jsonl" });
    defer gpa.free(path);
    try session.save(io, path);

    var output: Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    var result = try execute(gpa, io, root, &.{ "list", "--json" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "cli-session") != null);

    output.clearRetainingCapacity();
    result = try execute(gpa, io, root, &.{ "search", "--json", "needle" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "native search") != null);

    output.clearRetainingCapacity();
    result = try execute(gpa, io, root, &.{ "show", "--json", "cli-session" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "selectedEntryCount") != null);

    output.clearRetainingCapacity();
    result = try execute(gpa, io, root, &.{ "doctor", "--json" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\"invalid\":0") != null);
}

test "doctor reports malformed sessions without aborting" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const bad = try std.fs.path.join(gpa, &.{ root, "bad.jsonl" });
    defer gpa.free(bad);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = bad, .data = "not-json\n" });

    var output: Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    const result = try execute(gpa, io, root, &.{"doctor"}, &output.writer);
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "INVALID") != null);
}

test "session commands migrate stats tree rename and guarded delete" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const path = try std.fs.path.join(gpa, &.{ root, "legacy-admin.jsonl" });
    defer gpa.free(path);
    const legacy =
        \\{"type":"session","id":"legacy-admin","timestamp":"2024-01-01T00:00:00.000Z","cwd":"/tmp"}
        \\{"type":"message","timestamp":"2024-01-01T00:00:01.000Z","message":{"role":"user","content":"hello"}}
        \\{"type":"message","timestamp":"2024-01-01T00:00:02.000Z","message":{"role":"assistant","content":[{"type":"text","text":"done"}],"usage":{"input":7,"output":3,"cacheRead":1,"cacheWrite":0,"cost":{"total":0.1}}}}
        \\
    ;
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = legacy });

    var output: Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    var result = try execute(gpa, io, root, &.{ "migrate", "--dry-run", "--json", "legacy-admin" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\"changed\":true") != null);
    var raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024));
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"version\":3") == null);
    gpa.free(raw);

    output.clearRetainingCapacity();
    result = try execute(gpa, io, root, &.{ "migrate", "--json", "legacy-admin" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\"applied\":true") != null);
    raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024));
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"version\":3") != null);
    gpa.free(raw);

    output.clearRetainingCapacity();
    result = try execute(gpa, io, root, &.{ "stats", "--json", "legacy-admin" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\"userMessages\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\"total\":11") != null);

    output.clearRetainingCapacity();
    result = try execute(gpa, io, root, &.{ "rename", "--json", "legacy-admin", "Renamed", "session" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "Renamed session") != null);

    output.clearRetainingCapacity();
    result = try execute(gpa, io, root, &.{ "tree", "--json", "legacy-admin" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\"entries\"") != null);

    output.clearRetainingCapacity();
    result = try execute(gpa, io, root, &.{ "delete", "legacy-admin" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 2), result.exit_code);
    _ = try std.Io.Dir.cwd().statFile(io, path, .{});

    output.clearRetainingCapacity();
    result = try execute(gpa, io, root, &.{ "delete", "--force", "--json", "legacy-admin" }, &output.writer);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, path, .{}));
}
