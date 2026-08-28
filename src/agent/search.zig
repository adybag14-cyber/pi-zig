//! Native session search shared by local JSONL stores and higher-level clients.
//!
//! The original TypeScript agent exposes a storage-neutral `SessionSearch`
//! contract.  This implementation keeps the same important semantics for the
//! file-backed session store: an empty query yields no hits, entry-type filters
//! are optional, malformed sessions do not poison an entire directory scan,
//! and results own all of their memory.  By default only the active branch is
//! searched so abandoned conversation branches are not surfaced as if they
//! were current context.
const std = @import("std");
const session_mod = @import("session.zig");
const Io = std.Io;

pub const SearchOptions = struct {
    /// Empty means all entry types.
    entry_types: []const session_mod.EntryType = &.{},
    /// Empty means all roles. Role matching is ASCII case-insensitive.
    roles: []const []const u8 = &.{},
    /// Global result limit. Zero has the same semantics as an empty query.
    limit: usize = 100,
    /// Search only the root-to-tip branch unless explicitly disabled.
    active_branch_only: bool = true,
    case_sensitive: bool = false,
    /// Bytes of surrounding text retained on each side of the first match.
    snippet_context: usize = 96,
    /// Include non-message entries such as labels and model changes. These are
    /// still subject to `entry_types` when that filter is present.
    include_auxiliary: bool = true,
};

pub const SearchHit = struct {
    session_id: []u8,
    session_path: []u8,
    session_name: []u8,
    cwd: []u8,
    entry_id: []u8,
    entry_type: session_mod.EntryType,
    role: []u8,
    timestamp: []u8,
    snippet: []u8,
    score: i64,
    /// Stable physical entry order within the source JSONL file.
    entry_ordinal: usize,
    /// Session modification time used only as a deterministic tie-breaker.
    session_mtime_ns: i96 = 0,

    pub fn deinit(self: *SearchHit, gpa: std.mem.Allocator) void {
        gpa.free(self.session_id);
        gpa.free(self.session_path);
        gpa.free(self.session_name);
        gpa.free(self.cwd);
        gpa.free(self.entry_id);
        gpa.free(self.role);
        gpa.free(self.timestamp);
        gpa.free(self.snippet);
        self.* = undefined;
    }
};

pub const SearchResult = struct {
    hits: []SearchHit,
    scanned_sessions: usize = 0,
    scanned_entries: usize = 0,
    malformed_sessions: usize = 0,

    pub fn deinit(self: *SearchResult, gpa: std.mem.Allocator) void {
        for (self.hits) |*hit| hit.deinit(gpa);
        gpa.free(self.hits);
        self.* = undefined;
    }
};

pub const TextMatch = struct {
    score: i64,
    first_index: usize,
    first_len: usize,
};

/// Storage-neutral text matcher used by local and remote search adapters.
pub fn matchText(haystack: []const u8, query: []const u8, case_sensitive: bool) ?TextMatch {
    return matchQuery(haystack, query, case_sensitive);
}

/// Create an owned, whitespace-normalized UTF-8-safe context snippet.
pub fn snippetForMatch(
    gpa: std.mem.Allocator,
    text: []const u8,
    matched: TextMatch,
    context: usize,
) ![]u8 {
    return makeSnippet(gpa, text, matched.first_index, matched.first_len, context);
}

/// Search one already-loaded session. Returned hits own all strings and remain
/// valid after the session is deinitialized.
pub fn searchSession(
    gpa: std.mem.Allocator,
    session: *const session_mod.Session,
    session_path: []const u8,
    query_raw: []const u8,
    options: SearchOptions,
) !SearchResult {
    const query = std.mem.trim(u8, query_raw, " \t\r\n");
    if (query.len == 0 or options.limit == 0) {
        return .{ .hits = try gpa.alloc(SearchHit, 0), .scanned_sessions = 1 };
    }

    var hits: std.ArrayList(SearchHit) = .empty;
    errdefer deinitHitList(gpa, &hits);

    const candidates = if (options.active_branch_only)
        try session.branchEntries(gpa)
    else blk: {
        const all = try gpa.alloc(*const session_mod.SessionEntry, session.entries.items.len);
        for (session.entries.items, 0..) |*entry, i| all[i] = entry;
        break :blk all;
    };
    defer gpa.free(candidates);

    var scanned_entries: usize = 0;
    for (candidates) |entry| {
        if (!entryAllowed(entry, options)) continue;
        scanned_entries += 1;

        var projected = try projectEntryText(gpa, entry);
        defer projected.deinit(gpa);
        const matched = matchQuery(projected.text, query, options.case_sensitive) orelse continue;
        const ordinal = physicalOrdinal(session, entry);
        const snippet = try makeSnippet(gpa, projected.text, matched.first_index, matched.first_len, options.snippet_context);
        errdefer gpa.free(snippet);
        try hits.append(gpa, .{
            .session_id = try gpa.dupe(u8, session.id),
            .session_path = try gpa.dupe(u8, session_path),
            .session_name = try gpa.dupe(u8, session.name),
            .cwd = try gpa.dupe(u8, session.cwd),
            .entry_id = try gpa.dupe(u8, entry.id),
            .entry_type = entry.entry_type,
            .role = try gpa.dupe(u8, entry.role),
            .timestamp = try gpa.dupe(u8, entry.timestamp),
            .snippet = snippet,
            .score = matched.score,
            .entry_ordinal = ordinal,
        });
    }

    sortHits(hits.items);
    if (hits.items.len > options.limit) {
        var i = options.limit;
        while (i < hits.items.len) : (i += 1) hits.items[i].deinit(gpa);
        hits.shrinkRetainingCapacity(options.limit);
    }
    return .{
        .hits = try hits.toOwnedSlice(gpa),
        .scanned_sessions = 1,
        .scanned_entries = scanned_entries,
    };
}

/// Search every JSONL session in a directory. Files that fail to parse are
/// counted and skipped, matching the fault isolation of the original scanning
/// backend. Results are globally ranked and limited after all sessions scan.
pub fn searchDirectory(
    gpa: std.mem.Allocator,
    io: Io,
    session_dir: []const u8,
    query_raw: []const u8,
    options: SearchOptions,
) !SearchResult {
    const query = std.mem.trim(u8, query_raw, " \t\r\n");
    if (query.len == 0 or options.limit == 0) {
        return .{ .hits = try gpa.alloc(SearchHit, 0) };
    }

    const infos = try session_mod.listSessions(gpa, io, session_dir);
    defer {
        for (infos) |*info| info.deinit(gpa);
        gpa.free(infos);
    }

    var all: std.ArrayList(SearchHit) = .empty;
    errdefer deinitHitList(gpa, &all);
    var scanned_sessions: usize = 0;
    var malformed_sessions: usize = 0;
    var scanned_entries: usize = 0;

    for (infos) |info| {
        var loaded = session_mod.Session.load(gpa, io, info.path) catch {
            malformed_sessions += 1;
            continue;
        };
        defer loaded.deinit();
        scanned_sessions += 1;

        // Do not apply the global limit per session: that would let an early
        // session suppress stronger matches in later files.
        var per_options = options;
        per_options.limit = std.math.maxInt(usize);
        var result = try searchSession(gpa, &loaded, info.path, query, per_options);
        scanned_entries += result.scanned_entries;
        var moved: usize = 0;
        errdefer {
            for (result.hits[moved..]) |*remaining| remaining.deinit(gpa);
            gpa.free(result.hits);
        }
        for (result.hits) |*source| {
            source.session_mtime_ns = info.mtime_ns;
            try all.append(gpa, source.*);
            source.* = undefined;
            moved += 1;
        }
        gpa.free(result.hits);
    }

    sortHits(all.items);
    if (all.items.len > options.limit) {
        var i = options.limit;
        while (i < all.items.len) : (i += 1) all.items[i].deinit(gpa);
        all.shrinkRetainingCapacity(options.limit);
    }
    return .{
        .hits = try all.toOwnedSlice(gpa),
        .scanned_sessions = scanned_sessions,
        .scanned_entries = scanned_entries,
        .malformed_sessions = malformed_sessions,
    };
}

fn deinitHitList(gpa: std.mem.Allocator, list: *std.ArrayList(SearchHit)) void {
    for (list.items) |*hit| hit.deinit(gpa);
    list.deinit(gpa);
}

fn entryAllowed(entry: *const session_mod.SessionEntry, options: SearchOptions) bool {
    if (!options.include_auxiliary and entry.entry_type != .message and entry.entry_type != .custom_message) return false;
    if (options.entry_types.len > 0) {
        var found = false;
        for (options.entry_types) |allowed| {
            if (allowed == entry.entry_type) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    if (options.roles.len > 0) {
        var found = false;
        for (options.roles) |role| {
            if (std.ascii.eqlIgnoreCase(role, entry.role)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

fn physicalOrdinal(session: *const session_mod.Session, needle: *const session_mod.SessionEntry) usize {
    for (session.entries.items, 0..) |*entry, i| if (entry == needle) return i;
    return 0;
}

const ProjectedText = struct {
    text: []u8,
    pub fn deinit(self: *ProjectedText, gpa: std.mem.Allocator) void {
        gpa.free(self.text);
        self.* = undefined;
    }
};

fn projectEntryText(gpa: std.mem.Allocator, entry: *const session_mod.SessionEntry) !ProjectedText {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    try appendField(gpa, &out, entry.content);
    if (entry.entry_type == .message and std.mem.eql(u8, entry.role, "assistant")) {
        try appendField(gpa, &out, entry.meta.thinking);
        try appendField(gpa, &out, entry.meta.error_message);
    }
    if (entry.tool_name) |value| try appendField(gpa, &out, value);
    if (entry.bash_command) |value| try appendField(gpa, &out, value);
    if (entry.label) |value| try appendField(gpa, &out, value);
    if (entry.custom_type) |value| try appendField(gpa, &out, value);
    // data_json is bounded metadata and can contain useful extension text.
    if (entry.data_json) |value| {
        if (value.len <= 256 * 1024) try appendField(gpa, &out, value);
    }

    return .{ .text = try out.toOwnedSlice(gpa) };
}

fn appendField(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    if (value.len == 0) return;
    if (out.items.len > 0) try out.append(gpa, '\n');
    try out.appendSlice(gpa, value);
}

fn matchQuery(haystack: []const u8, query: []const u8, case_sensitive: bool) ?TextMatch {
    var terms = std.mem.tokenizeAny(u8, query, " \t\r\n");
    var score: i64 = 0;
    var first_index: usize = std.math.maxInt(usize);
    var first_len: usize = 0;
    var term_count: usize = 0;
    while (terms.next()) |term| {
        if (term.len == 0) continue;
        term_count += 1;
        const index = findText(haystack, term, case_sensitive) orelse return null;
        if (index < first_index) {
            first_index = index;
            first_len = term.len;
        }
        score += 500;
        if (index == 0 or isWordBoundary(haystack[index - 1])) score += 220;
        if (index + term.len == haystack.len or isWordBoundary(haystack[index + term.len])) score += 120;
        score -= @intCast(@min(index, 200));
    }
    if (term_count == 0) return null;

    if (findText(haystack, query, case_sensitive)) |phrase_index| {
        score += 4000 + @as(i64, @intCast(@min(query.len, 1000)));
        first_index = phrase_index;
        first_len = query.len;
        if (phrase_index == 0 or isWordBoundary(haystack[phrase_index - 1])) score += 500;
    }
    // Prefer concise entries when otherwise equivalent.
    score -= @intCast(@min(haystack.len / 256, 500));
    return .{ .score = score, .first_index = first_index, .first_len = first_len };
}

fn findText(haystack: []const u8, needle: []const u8, case_sensitive: bool) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > haystack.len) return null;
    if (case_sensitive) return std.mem.indexOf(u8, haystack, needle);
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var matches = true;
        for (needle, 0..) |c, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(c)) {
                matches = false;
                break;
            }
        }
        if (matches) return i;
    }
    return null;
}

fn isWordBoundary(c: u8) bool {
    return !std.ascii.isAlphanumeric(c) and c != '_';
}

fn makeSnippet(
    gpa: std.mem.Allocator,
    text: []const u8,
    match_index: usize,
    match_len: usize,
    context: usize,
) ![]u8 {
    if (text.len == 0) return try gpa.dupe(u8, "");
    var start = match_index -| context;
    var end = @min(text.len, match_index + match_len + context);
    start = utf8StartBoundary(text, start);
    end = utf8EndBoundary(text, end);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    if (start > 0) try out.appendSlice(gpa, "…");

    var pending_space = false;
    for (text[start..end]) |c| {
        if (c == '\r' or c == '\n' or c == '\t') {
            pending_space = out.items.len > 0;
            continue;
        }
        if (pending_space and c != ' ') try out.append(gpa, ' ');
        pending_space = false;
        try out.append(gpa, c);
    }
    while (out.items.len > 0 and out.items[out.items.len - 1] == ' ') _ = out.pop();
    if (end < text.len) try out.appendSlice(gpa, "…");
    return try out.toOwnedSlice(gpa);
}

fn utf8StartBoundary(text: []const u8, proposed: usize) usize {
    var index = @min(proposed, text.len);
    while (index > 0 and index < text.len and (text[index] & 0xc0) == 0x80) index -= 1;
    return index;
}

fn utf8EndBoundary(text: []const u8, proposed: usize) usize {
    var index = @min(proposed, text.len);
    while (index < text.len and (text[index] & 0xc0) == 0x80) index += 1;
    return index;
}

fn sortHits(hits: []SearchHit) void {
    std.mem.sort(SearchHit, hits, {}, struct {
        fn lessThan(_: void, lhs: SearchHit, rhs: SearchHit) bool {
            if (lhs.score != rhs.score) return lhs.score > rhs.score;
            if (lhs.session_mtime_ns != rhs.session_mtime_ns) return lhs.session_mtime_ns > rhs.session_mtime_ns;
            const id_order = std.mem.order(u8, lhs.session_id, rhs.session_id);
            if (id_order != .eq) return id_order == .lt;
            return lhs.entry_ordinal < rhs.entry_ordinal;
        }
    }.lessThan);
}

pub fn entryTypeName(value: session_mod.EntryType) []const u8 {
    return switch (value) {
        .message => "message",
        .compaction => "compaction",
        .branch_summary => "branch_summary",
        .session_info => "session_info",
        .label => "label",
        .custom => "custom",
        .custom_message => "custom_message",
        .model_change => "model_change",
        .thinking_level_change => "thinking_level_change",
    };
}

pub fn parseEntryType(value: []const u8) ?session_mod.EntryType {
    inline for (std.meta.fields(session_mod.EntryType)) |field| {
        if (std.ascii.eqlIgnoreCase(value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

test "search session is case insensitive, ranked, filtered and branch aware" {
    const gpa = std.testing.allocator;
    var session = try session_mod.Session.init(gpa, "search-1", "/work");
    defer session.deinit();
    try session.setName("demo");

    const root = try session.appendMessage(null, "user", "Need a database migration plan", null, null);
    const active = try session.appendMessage(root, "assistant", "The migration plan uses a transaction and backup", null, null);
    const abandoned = try session.appendMessage(root, "assistant", "Dangerous migration without backup", null, null);
    try session.setTip(active);
    _ = abandoned;

    var result = try searchSession(gpa, &session, "/tmp/search-1.jsonl", "MIGRATION backup", .{});
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), result.hits.len);
    try std.testing.expectEqualStrings(active, result.hits[0].entry_id);
    try std.testing.expect(std.mem.indexOf(u8, result.hits[0].snippet, "migration") != null);

    var all_result = try searchSession(gpa, &session, "", "migration", .{ .active_branch_only = false, .roles = &.{"assistant"} });
    defer all_result.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 2), all_result.hits.len);
}

test "empty query and zero limit yield no hits" {
    const gpa = std.testing.allocator;
    var session = try session_mod.Session.init(gpa, "empty", "/");
    defer session.deinit();
    _ = try session.appendMessage(null, "user", "needle", null, null);
    var empty = try searchSession(gpa, &session, "", "  \n", .{});
    defer empty.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), empty.hits.len);
    var limited = try searchSession(gpa, &session, "", "needle", .{ .limit = 0 });
    defer limited.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), limited.hits.len);
}

test "entry type filters and auxiliary projection" {
    const gpa = std.testing.allocator;
    var session = try session_mod.Session.init(gpa, "types", "/");
    defer session.deinit();
    const message = try session.appendMessage(null, "user", "ordinary", null, null);
    _ = try session.appendLabelChange(message, "important release marker");

    var labels = try searchSession(gpa, &session, "", "release", .{ .entry_types = &.{.label} });
    defer labels.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), labels.hits.len);
    try std.testing.expectEqual(session_mod.EntryType.label, labels.hits[0].entry_type);

    var hidden = try searchSession(gpa, &session, "", "release", .{ .include_auxiliary = false });
    defer hidden.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), hidden.hits.len);
}

test "directory search isolates malformed JSONL and owns results" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    var first = try session_mod.Session.init(gpa, "one", root);
    defer first.deinit();
    try first.setName("first");
    _ = try first.appendMessage(null, "user", "alpha searchable token", null, null);
    const first_path = try std.fs.path.join(gpa, &.{ root, "one.jsonl" });
    defer gpa.free(first_path);
    try first.save(io, first_path);

    var second = try session_mod.Session.init(gpa, "two", root);
    defer second.deinit();
    _ = try second.appendMessage(null, "assistant", "searchable token twice", null, null);
    const second_path = try std.fs.path.join(gpa, &.{ root, "two.jsonl" });
    defer gpa.free(second_path);
    try second.save(io, second_path);

    const bad_path = try std.fs.path.join(gpa, &.{ root, "bad.jsonl" });
    defer gpa.free(bad_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = bad_path, .data = "{not-json}\n" });

    var result = try searchDirectory(gpa, io, root, "searchable token", .{ .limit = 1 });
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 2), result.scanned_sessions);
    try std.testing.expectEqual(@as(usize, 1), result.malformed_sessions);
    try std.testing.expectEqual(@as(usize, 1), result.hits.len);
    try std.testing.expect(result.hits[0].session_id.len > 0);
}

test "snippets retain valid UTF-8 boundaries" {
    const gpa = std.testing.allocator;
    const text = "prefix 🙂🙂 target 你好 suffix";
    const index = std.mem.indexOf(u8, text, "target").?;
    const snippet = try makeSnippet(gpa, text, index, "target".len, 3);
    defer gpa.free(snippet);
    try std.testing.expect(std.unicode.utf8ValidateSlice(snippet));
    try std.testing.expect(std.mem.indexOf(u8, snippet, "target") != null);
}
