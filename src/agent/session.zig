//! JSONL tree session: header + messages, fork, branch tip, auto-save dir.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

/// Optional assistant metadata (upstream AgentMessage fields).
pub const AssistantMeta = struct {
    provider: []const u8 = "",
    model: []const u8 = "",
    stop_reason: []const u8 = "",
    usage_input: u64 = 0,
    usage_output: u64 = 0,
    usage_total: u64 = 0,

    pub fn deinit(self: *AssistantMeta, gpa: std.mem.Allocator) void {
        if (self.provider.len > 0) gpa.free(self.provider);
        if (self.model.len > 0) gpa.free(self.model);
        if (self.stop_reason.len > 0) gpa.free(self.stop_reason);
        self.* = .{};
    }

    pub fn dupe(self: AssistantMeta, gpa: std.mem.Allocator) !AssistantMeta {
        return .{
            .provider = if (self.provider.len > 0) try gpa.dupe(u8, self.provider) else "",
            .model = if (self.model.len > 0) try gpa.dupe(u8, self.model) else "",
            .stop_reason = if (self.stop_reason.len > 0) try gpa.dupe(u8, self.stop_reason) else "",
            .usage_input = self.usage_input,
            .usage_output = self.usage_output,
            .usage_total = self.usage_total,
        };
    }
};

pub const SessionEntry = struct {
    id: []const u8,
    parent_id: ?[]const u8,
    role: []const u8,
    content: []const u8,
    tool_call_id: ?[]const u8 = null,
    tool_calls_json: ?[]const u8 = null,
    /// Tool name for toolResult entries (needed for Google functionResponse replay).
    tool_name: ?[]const u8 = null,
    /// ISO-8601 timestamp owned string (persisted on save/load).
    timestamp: []const u8 = "",
    meta: AssistantMeta = .{},

    pub fn deinit(self: *SessionEntry, gpa: std.mem.Allocator) void {
        gpa.free(self.id);
        if (self.parent_id) |p| gpa.free(p);
        gpa.free(self.role);
        gpa.free(self.content);
        if (self.tool_call_id) |t| gpa.free(t);
        if (self.tool_calls_json) |t| gpa.free(t);
        if (self.tool_name) |t| gpa.free(t);
        if (self.timestamp.len > 0) gpa.free(self.timestamp);
        self.meta.deinit(gpa);
        self.* = undefined;
    }
};

pub const SessionInfo = struct {
    path: []const u8,
    id: []const u8,
    name: []const u8,
    mtime_hint: []const u8 = "",

    pub fn deinit(self: *SessionInfo, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        gpa.free(self.id);
        gpa.free(self.name);
        if (self.mtime_hint.len > 0) gpa.free(self.mtime_hint);
        self.* = undefined;
    }
};

pub const Session = struct {
    gpa: std.mem.Allocator,
    id: []const u8,
    cwd: []const u8,
    name: []const u8,
    /// Active leaf tip for tree navigation (entry id).
    tip_id: ?[]const u8 = null,
    entries: std.ArrayList(SessionEntry),
    next_seq: u64 = 1,

    pub fn init(gpa: std.mem.Allocator, id: []const u8, cwd: []const u8) !Session {
        return .{
            .gpa = gpa,
            .id = try gpa.dupe(u8, id),
            .cwd = try gpa.dupe(u8, cwd),
            .name = try gpa.dupe(u8, ""),
            .tip_id = null,
            .entries = .empty,
            .next_seq = 1,
        };
    }

    pub fn deinit(self: *Session) void {
        for (self.entries.items) |*e| e.deinit(self.gpa);
        self.entries.deinit(self.gpa);
        self.gpa.free(self.id);
        self.gpa.free(self.cwd);
        self.gpa.free(self.name);
        if (self.tip_id) |t| self.gpa.free(t);
        self.* = undefined;
    }

    pub fn setName(self: *Session, name: []const u8) !void {
        self.gpa.free(self.name);
        self.name = try self.gpa.dupe(u8, name);
    }

    pub fn setTip(self: *Session, entry_id: []const u8) !void {
        // Verify entry exists
        var found = false;
        for (self.entries.items) |e| {
            if (std.mem.eql(u8, e.id, entry_id)) {
                found = true;
                break;
            }
        }
        if (!found) return error.UnknownEntry;
        if (self.tip_id) |t| self.gpa.free(t);
        self.tip_id = try self.gpa.dupe(u8, entry_id);
    }

    pub fn appendMessage(
        self: *Session,
        parent_id: ?[]const u8,
        role: []const u8,
        content: []const u8,
        tool_call_id: ?[]const u8,
        tool_calls_json: ?[]const u8,
    ) ![]const u8 {
        return self.appendMessageMeta(parent_id, role, content, tool_call_id, tool_calls_json, null, .{});
    }

    pub fn appendToolResult(
        self: *Session,
        parent_id: ?[]const u8,
        content: []const u8,
        tool_call_id: []const u8,
        tool_name: []const u8,
    ) ![]const u8 {
        return self.appendMessageMeta(parent_id, "tool", content, tool_call_id, null, tool_name, .{});
    }

    pub fn appendMessageMeta(
        self: *Session,
        parent_id: ?[]const u8,
        role: []const u8,
        content: []const u8,
        tool_call_id: ?[]const u8,
        tool_calls_json: ?[]const u8,
        tool_name: ?[]const u8,
        meta: AssistantMeta,
    ) ![]const u8 {
        const id = try std.fmt.allocPrint(self.gpa, "m{d}", .{self.next_seq});
        self.next_seq += 1;
        errdefer self.gpa.free(id);

        var ts_buf: [32]u8 = undefined;
        const ts_now = formatIsoTimestamp(&ts_buf);
        try self.entries.append(self.gpa, .{
            .id = id,
            .parent_id = if (parent_id) |p| try self.gpa.dupe(u8, p) else null,
            .role = try self.gpa.dupe(u8, role),
            .content = try self.gpa.dupe(u8, content),
            .tool_call_id = if (tool_call_id) |t| try self.gpa.dupe(u8, t) else null,
            .tool_calls_json = if (tool_calls_json) |t| try self.gpa.dupe(u8, t) else null,
            .tool_name = if (tool_name) |t| try self.gpa.dupe(u8, t) else null,
            .timestamp = try self.gpa.dupe(u8, ts_now),
            .meta = try meta.dupe(self.gpa),
        });
        if (self.tip_id) |t| self.gpa.free(t);
        self.tip_id = try self.gpa.dupe(u8, id);
        return id;
    }

    pub fn lastEntryId(self: *const Session) ?[]const u8 {
        if (self.tip_id) |t| return t;
        if (self.entries.items.len == 0) return null;
        return self.entries.items[self.entries.items.len - 1].id;
    }

    /// Entries on the active branch (from root to tip).
    pub fn branchEntries(self: *const Session, gpa: std.mem.Allocator) ![]const *const SessionEntry {
        const tip = self.lastEntryId() orelse return try gpa.alloc(*const SessionEntry, 0);
        var chain: std.ArrayList(*const SessionEntry) = .empty;
        errdefer chain.deinit(gpa);

        var current: ?[]const u8 = tip;
        while (current) |cid| {
            var found: ?*const SessionEntry = null;
            for (self.entries.items) |*e| {
                if (std.mem.eql(u8, e.id, cid)) {
                    found = e;
                    break;
                }
            }
            const e = found orelse break;
            try chain.append(gpa, e);
            current = e.parent_id;
        }
        // reverse to root→tip
        std.mem.reverse(*const SessionEntry, chain.items);
        return try chain.toOwnedSlice(gpa);
    }

    /// Serialize as upstream pi session-format v3 JSONL (type:session header + nested message).
    pub fn toJsonl(self: *const Session, gpa: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);

        {
            var line: std.Io.Writer.Allocating = .init(gpa);
            defer line.deinit();
            // Upstream SessionHeader: {"type":"session","version":3,"id":"...","timestamp":"...","cwd":"..."}
            try line.writer.writeAll("{\"type\":\"session\",\"version\":3,\"id\":");
            try std.json.Stringify.value(self.id, .{}, &line.writer);
            try line.writer.writeAll(",\"timestamp\":");
            {
                var ts_buf: [32]u8 = undefined;
                const ts = formatIsoTimestamp(&ts_buf);
                try std.json.Stringify.value(ts, .{}, &line.writer);
            }
            try line.writer.writeAll(",\"cwd\":");
            try std.json.Stringify.value(self.cwd, .{}, &line.writer);
            if (self.name.len > 0) {
                try line.writer.writeAll(",\"name\":");
                try std.json.Stringify.value(self.name, .{}, &line.writer);
            }
            // Tip is an extension field for pi-zig (ignored by upstream)
            if (self.tip_id) |t| {
                try line.writer.writeAll(",\"tipId\":");
                try std.json.Stringify.value(t, .{}, &line.writer);
            }
            try line.writer.writeAll(",\"next_seq\":");
            try line.writer.print("{d}", .{self.next_seq});
            try line.writer.writeAll("}");
            try out.appendSlice(gpa, line.written());
            try out.append(gpa, '\n');
        }

        for (self.entries.items) |e| {
            var line: std.Io.Writer.Allocating = .init(gpa);
            defer line.deinit();
            try line.writer.writeAll("{\"type\":\"message\",\"id\":");
            try std.json.Stringify.value(e.id, .{}, &line.writer);
            try line.writer.writeAll(",\"parentId\":");
            if (e.parent_id) |p| {
                try std.json.Stringify.value(p, .{}, &line.writer);
            } else {
                try line.writer.writeAll("null");
            }
            try line.writer.writeAll(",\"timestamp\":");
            if (e.timestamp.len > 0) {
                try std.json.Stringify.value(e.timestamp, .{}, &line.writer);
            } else {
                var ts_buf: [32]u8 = undefined;
                try std.json.Stringify.value(formatIsoTimestamp(&ts_buf), .{}, &line.writer);
            }
            try line.writer.writeAll(",\"message\":{");
            // Map internal "tool" role → upstream "toolResult"
            const out_role: []const u8 = if (std.mem.eql(u8, e.role, "tool")) "toolResult" else e.role;
            try line.writer.writeAll("\"role\":");
            try std.json.Stringify.value(out_role, .{}, &line.writer);
            if (std.mem.eql(u8, out_role, "assistant")) {
                try line.writer.writeAll(",\"content\":[{\"type\":\"text\",\"text\":");
                try std.json.Stringify.value(e.content, .{}, &line.writer);
                try line.writer.writeAll("}]");
                if (e.tool_calls_json) |tcj| {
                    try line.writer.writeAll(",\"toolCalls\":");
                    try line.writer.writeAll(tcj);
                }
                // Upstream AssistantMessage metadata
                if (e.meta.provider.len > 0) {
                    try line.writer.writeAll(",\"provider\":");
                    try std.json.Stringify.value(e.meta.provider, .{}, &line.writer);
                }
                if (e.meta.model.len > 0) {
                    try line.writer.writeAll(",\"model\":");
                    try std.json.Stringify.value(e.meta.model, .{}, &line.writer);
                }
                const sr: []const u8 = if (e.meta.stop_reason.len > 0)
                    e.meta.stop_reason
                else if (e.tool_calls_json != null)
                    "toolUse"
                else
                    "stop";
                try line.writer.writeAll(",\"stopReason\":");
                try std.json.Stringify.value(sr, .{}, &line.writer);
                if (e.meta.usage_total > 0 or e.meta.usage_input > 0 or e.meta.usage_output > 0) {
                    try line.writer.writeAll(",\"usage\":{\"input\":");
                    try line.writer.print("{d}", .{e.meta.usage_input});
                    try line.writer.writeAll(",\"output\":");
                    try line.writer.print("{d}", .{e.meta.usage_output});
                    try line.writer.writeAll(",\"totalTokens\":");
                    try line.writer.print("{d}", .{e.meta.usage_total});
                    try line.writer.writeAll("}");
                }
            } else if (std.mem.eql(u8, out_role, "toolResult")) {
                try line.writer.writeAll(",\"toolCallId\":");
                try std.json.Stringify.value(e.tool_call_id orelse "", .{}, &line.writer);
                try line.writer.writeAll(",\"toolName\":");
                try std.json.Stringify.value(e.tool_name orelse "tool", .{}, &line.writer);
                try line.writer.writeAll(",\"content\":[{\"type\":\"text\",\"text\":");
                try std.json.Stringify.value(e.content, .{}, &line.writer);
                try line.writer.writeAll("}],\"isError\":false");
            } else {
                try line.writer.writeAll(",\"content\":");
                try std.json.Stringify.value(e.content, .{}, &line.writer);
            }
            try line.writer.writeAll("}}");
            try out.appendSlice(gpa, line.written());
            try out.append(gpa, '\n');
        }

        return try out.toOwnedSlice(gpa);
    }

    pub fn save(self: *const Session, io: Io, path: []const u8) !void {
        const data = try self.toJsonl(self.gpa);
        defer self.gpa.free(data);
        if (std.fs.path.dirname(path)) |parent| {
            if (parent.len > 0) try std.Io.Dir.cwd().createDirPath(io, parent);
        }
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
    }

    pub fn load(gpa: std.mem.Allocator, io: Io, path: []const u8) !Session {
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(32 * 1024 * 1024));
        defer gpa.free(raw);
        return try parseJsonl(gpa, raw);
    }

    /// Parse JSONL: accepts upstream v3 (`type:session` + nested `message`) and legacy pi-zig
    /// flat `type:header` / top-level role+content lines.
    pub fn parseJsonl(gpa: std.mem.Allocator, raw: []const u8) !Session {
        var session: ?Session = null;
        errdefer if (session) |*s| s.deinit();

        var it = std.mem.splitScalar(u8, raw, '\n');
        while (it.next()) |line_raw| {
            const line = std.mem.trim(u8, line_raw, " \t\r");
            if (line.len == 0) continue;
            var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
            defer parsed.deinit();
            if (parsed.value != .object) return error.InvalidSession;

            const typ = parsed.value.object.get("type") orelse return error.InvalidSession;
            if (typ != .string) return error.InvalidSession;

            // Header: upstream "session" or legacy "header"
            if (std.mem.eql(u8, typ.string, "session") or std.mem.eql(u8, typ.string, "header")) {
                const id = parsed.value.object.get("id") orelse return error.InvalidSession;
                const cwd = parsed.value.object.get("cwd") orelse return error.InvalidSession;
                if (id != .string or cwd != .string) return error.InvalidSession;
                var s = try Session.init(gpa, id.string, cwd.string);
                if (parsed.value.object.get("name")) |nm| {
                    if (nm == .string) {
                        gpa.free(s.name);
                        s.name = try gpa.dupe(u8, nm.string);
                    }
                }
                if (parsed.value.object.get("next_seq")) |ns| {
                    if (ns == .integer) s.next_seq = @intCast(ns.integer);
                }
                if (parsed.value.object.get("tipId")) |tip| {
                    if (tip == .string) s.tip_id = try gpa.dupe(u8, tip.string);
                }
                session = s;
                continue;
            }

            // Non-message entry types (model_change, compaction, …) — keep tree links as synthetic system notes
            if (std.mem.eql(u8, typ.string, "model_change") or
                std.mem.eql(u8, typ.string, "thinking_level_change") or
                std.mem.eql(u8, typ.string, "compaction") or
                std.mem.eql(u8, typ.string, "branch_summary") or
                std.mem.eql(u8, typ.string, "session_info") or
                std.mem.eql(u8, typ.string, "label") or
                std.mem.eql(u8, typ.string, "custom") or
                std.mem.eql(u8, typ.string, "custom_message"))
            {
                const s = &(session orelse return error.InvalidSession);
                const id = parsed.value.object.get("id") orelse continue;
                if (id != .string) continue;
                var parent_id: ?[]const u8 = null;
                if (parsed.value.object.get("parentId")) |p| {
                    if (p == .string) parent_id = p.string;
                }
                if (std.mem.eql(u8, typ.string, "session_info")) {
                    if (parsed.value.object.get("name")) |nm| {
                        if (nm == .string) {
                            gpa.free(s.name);
                            s.name = try gpa.dupe(u8, nm.string);
                        }
                    }
                }
                if (std.mem.eql(u8, typ.string, "compaction")) {
                    const summary = if (parsed.value.object.get("summary")) |sm|
                        (if (sm == .string) sm.string else "")
                    else
                        "";
                    try s.entries.append(gpa, .{
                        .id = try gpa.dupe(u8, id.string),
                        .parent_id = if (parent_id) |p| try gpa.dupe(u8, p) else null,
                        .role = try gpa.dupe(u8, "system"),
                        .content = try std.fmt.allocPrint(gpa, "[compaction] {s}", .{summary}),
                    });
                    if (s.tip_id) |t| gpa.free(t);
                    s.tip_id = try gpa.dupe(u8, id.string);
                }
                continue;
            }

            if (std.mem.eql(u8, typ.string, "message")) {
                const s = &(session orelse return error.InvalidSession);
                const id = parsed.value.object.get("id") orelse return error.InvalidSession;
                if (id != .string) return error.InvalidSession;

                var parent_id: ?[]const u8 = null;
                if (parsed.value.object.get("parentId")) |p| {
                    if (p == .string) parent_id = p.string;
                }

                // Nested upstream message object OR flat legacy fields
                var role_str: []const u8 = undefined;
                var content_owned: []u8 = undefined;
                var tool_call_id: ?[]const u8 = null;
                var tool_calls_json: ?[]u8 = null;

                if (parsed.value.object.get("message")) |msg| {
                    if (msg != .object) return error.InvalidSession;
                    const role = msg.object.get("role") orelse return error.InvalidSession;
                    if (role != .string) return error.InvalidSession;
                    // Map toolResult → tool for internal loop
                    role_str = if (std.mem.eql(u8, role.string, "toolResult")) "tool" else role.string;

                    content_owned = try extractMessageText(gpa, msg);
                    if (msg.object.get("toolCallId")) |t| {
                        if (t == .string) tool_call_id = t.string;
                    }
                    if (msg.object.get("toolCalls")) |tc| {
                        var aw: std.Io.Writer.Allocating = .init(gpa);
                        defer aw.deinit();
                        try std.json.Stringify.value(tc, .{}, &aw.writer);
                        tool_calls_json = try aw.toOwnedSlice();
                    } else if (msg.object.get("content")) |c| {
                        // Extract toolCall blocks from content array
                        if (c == .array) {
                            var tcs: std.ArrayList(u8) = .empty;
                            defer tcs.deinit(gpa);
                            try tcs.appendSlice(gpa, "[");
                            var first = true;
                            for (c.array.items) |block| {
                                if (block != .object) continue;
                                const bt = block.object.get("type") orelse continue;
                                if (bt != .string) continue;
                                if (!std.mem.eql(u8, bt.string, "toolCall") and !std.mem.eql(u8, bt.string, "tool_use")) continue;
                                if (!first) try tcs.appendSlice(gpa, ",");
                                first = false;
                                const tid = if (block.object.get("id")) |v| (if (v == .string) v.string else "") else "";
                                const nm = if (block.object.get("name")) |v| (if (v == .string) v.string else "") else "";
                                // arguments may be object or string
                                var args_aw: std.Io.Writer.Allocating = .init(gpa);
                                defer args_aw.deinit();
                                if (block.object.get("arguments")) |a| {
                                    if (a == .string) {
                                        try args_aw.writer.writeAll(a.string);
                                    } else {
                                        try std.json.Stringify.value(a, .{}, &args_aw.writer);
                                    }
                                } else if (block.object.get("input")) |inp| {
                                    try std.json.Stringify.value(inp, .{}, &args_aw.writer);
                                } else {
                                    try args_aw.writer.writeAll("{}");
                                }
                                try tcs.appendSlice(gpa, "{\"id\":");
                                var tmp: std.Io.Writer.Allocating = .init(gpa);
                                defer tmp.deinit();
                                try std.json.Stringify.value(tid, .{}, &tmp.writer);
                                try tcs.appendSlice(gpa, tmp.written());
                                try tcs.appendSlice(gpa, ",\"type\":\"function\",\"function\":{\"name\":");
                                tmp.deinit();
                                tmp = .init(gpa);
                                try std.json.Stringify.value(nm, .{}, &tmp.writer);
                                try tcs.appendSlice(gpa, tmp.written());
                                try tcs.appendSlice(gpa, ",\"arguments\":");
                                tmp.deinit();
                                tmp = .init(gpa);
                                try std.json.Stringify.value(args_aw.written(), .{}, &tmp.writer);
                                try tcs.appendSlice(gpa, tmp.written());
                                try tcs.appendSlice(gpa, "}}");
                            }
                            try tcs.appendSlice(gpa, "]");
                            if (!first) {
                                tool_calls_json = try tcs.toOwnedSlice(gpa);
                            }
                        }
                    }
                } else {
                    // Legacy flat format
                    const role = parsed.value.object.get("role") orelse return error.InvalidSession;
                    const content = parsed.value.object.get("content") orelse return error.InvalidSession;
                    if (role != .string or content != .string) return error.InvalidSession;
                    role_str = role.string;
                    content_owned = try gpa.dupe(u8, content.string);
                    if (parsed.value.object.get("toolCallId")) |t| {
                        if (t == .string) tool_call_id = t.string;
                    }
                    if (parsed.value.object.get("toolCalls")) |tc| {
                        var aw: std.Io.Writer.Allocating = .init(gpa);
                        defer aw.deinit();
                        try std.json.Stringify.value(tc, .{}, &aw.writer);
                        tool_calls_json = try aw.toOwnedSlice();
                    }
                }
                defer gpa.free(content_owned);
                defer if (tool_calls_json) |t| gpa.free(t);

                var meta: AssistantMeta = .{};
                // Nested message object carries assistant metadata
                if (parsed.value.object.get("message")) |msg| {
                    if (msg == .object) {
                        if (msg.object.get("provider")) |pv| {
                            if (pv == .string) meta.provider = try gpa.dupe(u8, pv.string);
                        }
                        if (msg.object.get("model")) |mv| {
                            if (mv == .string) meta.model = try gpa.dupe(u8, mv.string);
                        }
                        if (msg.object.get("stopReason")) |sr| {
                            if (sr == .string) meta.stop_reason = try gpa.dupe(u8, sr.string);
                        }
                        if (msg.object.get("usage")) |uv| {
                            if (uv == .object) {
                                if (uv.object.get("input")) |v| {
                                    if (v == .integer) meta.usage_input = @intCast(v.integer);
                                }
                                if (uv.object.get("output")) |v| {
                                    if (v == .integer) meta.usage_output = @intCast(v.integer);
                                }
                                if (uv.object.get("totalTokens") orelse uv.object.get("total_tokens")) |v| {
                                    if (v == .integer) meta.usage_total = @intCast(v.integer);
                                }
                            }
                        }
                    }
                }

                var tool_name_owned: ?[]const u8 = null;
                if (parsed.value.object.get("message")) |msg2| {
                    if (msg2 == .object) {
                        if (msg2.object.get("toolName")) |tn| {
                            if (tn == .string) tool_name_owned = try gpa.dupe(u8, tn.string);
                        }
                    }
                }
                var ts_owned: []const u8 = "";
                if (parsed.value.object.get("timestamp")) |tsv| {
                    if (tsv == .string) ts_owned = try gpa.dupe(u8, tsv.string);
                }
                try s.entries.append(gpa, .{
                    .id = try gpa.dupe(u8, id.string),
                    .parent_id = if (parent_id) |p| try gpa.dupe(u8, p) else null,
                    .role = try gpa.dupe(u8, role_str),
                    .content = try gpa.dupe(u8, content_owned),
                    .tool_call_id = if (tool_call_id) |t| try gpa.dupe(u8, t) else null,
                    .tool_calls_json = if (tool_calls_json) |t| try gpa.dupe(u8, t) else null,
                    .tool_name = tool_name_owned,
                    .timestamp = ts_owned,
                    .meta = meta,
                });
                if (s.tip_id) |t| gpa.free(t);
                s.tip_id = try gpa.dupe(u8, id.string);
            }
        }

        return session orelse error.InvalidSession;
    }

    /// Deep-copy session as a new fork with new id.
    pub fn fork(self: *const Session, gpa: std.mem.Allocator, new_id: []const u8) !Session {
        var s = try Session.init(gpa, new_id, self.cwd);
        errdefer s.deinit();
        try s.setName(self.name);
        s.next_seq = self.next_seq;
        for (self.entries.items) |e| {
            try s.entries.append(gpa, .{
                .id = try gpa.dupe(u8, e.id),
                .parent_id = if (e.parent_id) |p| try gpa.dupe(u8, p) else null,
                .role = try gpa.dupe(u8, e.role),
                .content = try gpa.dupe(u8, e.content),
                .tool_call_id = if (e.tool_call_id) |t| try gpa.dupe(u8, t) else null,
                .tool_calls_json = if (e.tool_calls_json) |t| try gpa.dupe(u8, t) else null,
                .tool_name = if (e.tool_name) |t| try gpa.dupe(u8, t) else null,
                .timestamp = if (e.timestamp.len > 0) try gpa.dupe(u8, e.timestamp) else "",
                .meta = try e.meta.dupe(gpa),
            });
        }
        if (self.tip_id) |t| s.tip_id = try gpa.dupe(u8, t);
        return s;
    }

    pub fn lastAssistantText(self: *const Session) ?[]const u8 {
        var i = self.entries.items.len;
        while (i > 0) {
            i -= 1;
            const e = self.entries.items[i];
            if (std.mem.eql(u8, e.role, "assistant") and e.content.len > 0) return e.content;
        }
        return null;
    }

    /// Tree summary for /tree (caller frees).
    pub fn treeSummary(self: *const Session, gpa: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        const tip = self.lastEntryId();
        for (self.entries.items) |e| {
            const mark: []const u8 = if (tip != null and std.mem.eql(u8, e.id, tip.?)) " *" else "";
            const line = try std.fmt.allocPrint(gpa, "{s} <- {s} [{s}] {s}{s}\n", .{
                e.id,
                e.parent_id orelse "null",
                e.role,
                truncate(e.content, 40),
                mark,
            });
            defer gpa.free(line);
            try out.appendSlice(gpa, line);
        }
        return try out.toOwnedSlice(gpa);
    }
};

fn truncate(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    return s[0..max];
}

/// Wall-clock Unix seconds when available; else monotonic fallback.
var timestamp_tick: i64 = 0;
const timestamp_anchor: i64 = 1_704_067_200; // 2024-01-01T00:00:00Z

fn wallishSeconds() i64 {
    if (builtin.os.tag == .windows) {
        // 100-ns intervals since 1601-01-01 UTC
        const ticks: i64 = std.os.windows.ntdll.RtlGetSystemTimePrecise();
        // Windows epoch → Unix epoch
        return @divTrunc(ticks - 11_644_473_600_000_0000, 10_000_000);
    }
    // POSIX: clock_gettime(CLOCK_REALTIME) via libc when linked
    if (builtin.link_libc) {
        const c = @cImport({
            @cInclude("time.h");
        });
        var ts: c.timespec = undefined;
        if (c.clock_gettime(c.CLOCK_REALTIME, &ts) == 0) {
            return @intCast(ts.tv_sec);
        }
    }
    // Fallback: process-local monotonic from 2024 anchor
    timestamp_tick += 1;
    return timestamp_anchor + timestamp_tick;
}

/// Public helper for protocol headers (JSON/RPC session line).
pub fn formatIsoNow(buf: *[32]u8) []const u8 {
    return formatIsoTimestamp(buf);
}

fn formatIsoTimestamp(buf: *[32]u8) []const u8 {
    const secs: i64 = wallishSeconds();
    const days = @divFloor(secs, 86400);
    var rem = @mod(secs, 86400);
    if (rem < 0) rem += 86400;
    const hour: u32 = @intCast(@divFloor(rem, 3600));
    const minute: u32 = @intCast(@divFloor(@mod(rem, 3600), 60));
    const second: u32 = @intCast(@mod(rem, 60));
    // Civil from days (Howard Hinnant algorithm)
    const z = days + 719468;
    const era = @divFloor(if (z >= 0) z else z - 146096, 146097);
    const doe: i64 = z - era * 146097;
    const yoe: i64 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    var y: i64 = yoe + era * 400;
    const doy: i64 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: i64 = @divFloor(5 * doy + 2, 153);
    const d: i64 = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m: i64 = mp + (if (mp < 10) @as(i64, 3) else -9);
    y += @intFromBool(m <= 2);
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.000Z", .{
        y, m, d, hour, minute, second,
    }) catch "2024-01-01T00:00:00.000Z";
}

/// Extract plain text from upstream message.content (string or content-block array).
fn extractMessageText(gpa: std.mem.Allocator, msg: std.json.Value) ![]u8 {
    const content = msg.object.get("content") orelse return try gpa.dupe(u8, "");
    if (content == .string) return try gpa.dupe(u8, content.string);
    if (content == .array) {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        for (content.array.items) |block| {
            if (block != .object) continue;
            const bt = block.object.get("type") orelse continue;
            if (bt != .string) continue;
            if (std.mem.eql(u8, bt.string, "text")) {
                if (block.object.get("text")) |tx| {
                    if (tx == .string) {
                        if (out.items.len > 0) try out.append(gpa, '\n');
                        try out.appendSlice(gpa, tx.string);
                    }
                }
            }
        }
        return try out.toOwnedSlice(gpa);
    }
    return try gpa.dupe(u8, "");
}

/// List session JSONL files in a directory.
pub fn listSessions(gpa: std.mem.Allocator, io: Io, dir_path: []const u8) ![]SessionInfo {
    var list: std.ArrayList(SessionInfo) = .empty;
    errdefer {
        for (list.items) |*s| s.deinit(gpa);
        list.deinit(gpa);
    }

    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch {
        return try list.toOwnedSlice(gpa);
    };
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".jsonl")) continue;
        const full = try std.fs.path.join(gpa, &.{ dir_path, entry.name });
        errdefer gpa.free(full);

        // Peek header for id/name
        const raw = std.Io.Dir.cwd().readFileAlloc(io, full, gpa, .limited(64 * 1024)) catch {
            gpa.free(full);
            continue;
        };
        defer gpa.free(raw);

        var id_owned = try gpa.dupe(u8, entry.name);
        errdefer gpa.free(id_owned);
        var name_owned = try gpa.dupe(u8, "");
        errdefer gpa.free(name_owned);
        if (std.mem.indexOfScalar(u8, raw, '\n')) |nl| {
            var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw[0..nl], .{}) catch {
                try list.append(gpa, .{
                    .path = full,
                    .id = id_owned,
                    .name = name_owned,
                });
                continue;
            };
            defer parsed.deinit();
            if (parsed.value == .object) {
                if (parsed.value.object.get("id")) |v| {
                    if (v == .string) {
                        gpa.free(id_owned);
                        id_owned = try gpa.dupe(u8, v.string);
                    }
                }
                if (parsed.value.object.get("name")) |v| {
                    if (v == .string) {
                        gpa.free(name_owned);
                        name_owned = try gpa.dupe(u8, v.string);
                    }
                }
            }
        }
        try list.append(gpa, .{
            .path = full,
            .id = id_owned,
            .name = name_owned,
        });
    }
    return try list.toOwnedSlice(gpa);
}

/// Most recently modified-looking session path (last in list for simplicity; name order).
pub fn mostRecentSessionPath(gpa: std.mem.Allocator, io: Io, dir_path: []const u8) !?[]u8 {
    const sessions = try listSessions(gpa, io, dir_path);
    defer {
        for (sessions) |*s| {
            var mut = s.*;
            mut.deinit(gpa);
        }
        gpa.free(sessions);
    }
    if (sessions.len == 0) return null;
    // Pick last by path name (sessions are often timestamp-named)
    return try gpa.dupe(u8, sessions[sessions.len - 1].path);
}

pub fn newSessionPath(gpa: std.mem.Allocator, session_dir: []const u8, id: []const u8) ![]u8 {
    const file = try std.fmt.allocPrint(gpa, "{s}.jsonl", .{id});
    defer gpa.free(file);
    return try std.fs.path.join(gpa, &.{ session_dir, file });
}

var session_id_counter: u64 = 1;

pub fn generateSessionId(gpa: std.mem.Allocator) ![]u8 {
    // Unique-enough id without depending on wall clock API.
    const n = session_id_counter;
    session_id_counter +%= 1;
    const mix: u64 = n *% 0x9e3779b97f4a7c15;
    return try std.fmt.allocPrint(gpa, "s{d}-{x}", .{ n, mix });
}

test "session save then load roundtrip" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const session_path = try std.fs.path.join(gpa, &.{ tmp_path, "session.jsonl" });
    defer gpa.free(session_path);

    var s = try Session.init(gpa, "sess-1", tmp_path);
    defer s.deinit();
    try s.setName("test");

    const user_id = try s.appendMessage(null, "user", "hello", null, null);
    _ = try s.appendMessage(user_id, "assistant", "hi there", null, null);

    try s.save(io, session_path);

    var loaded = try Session.load(gpa, io, session_path);
    defer loaded.deinit();

    try std.testing.expectEqualStrings("sess-1", loaded.id);
    try std.testing.expectEqualStrings("test", loaded.name);
    try std.testing.expectEqual(@as(usize, 2), loaded.entries.items.len);
    try std.testing.expectEqualStrings("user", loaded.entries.items[0].role);
    try std.testing.expectEqualStrings("hello", loaded.entries.items[0].content);
    try std.testing.expectEqualStrings("assistant", loaded.entries.items[1].role);
    try std.testing.expectEqualStrings(user_id, loaded.entries.items[1].parent_id.?);
}

test "per-entry timestamps persist across save/load" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const session_path = try std.fs.path.join(gpa, &.{ tmp_path, "ts.jsonl" });
    defer gpa.free(session_path);

    var s = try Session.init(gpa, "ts-1", tmp_path);
    defer s.deinit();
    _ = try s.appendMessage(null, "user", "with-ts", null, null);
    try std.testing.expect(s.entries.items[0].timestamp.len > 0);
    const ts_before = try gpa.dupe(u8, s.entries.items[0].timestamp);
    defer gpa.free(ts_before);

    try s.save(io, session_path);
    var loaded = try Session.load(gpa, io, session_path);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 1), loaded.entries.items.len);
    try std.testing.expect(loaded.entries.items[0].timestamp.len > 0);
    try std.testing.expectEqualStrings(ts_before, loaded.entries.items[0].timestamp);
}

test "session fork copies branch" {
    const gpa = std.testing.allocator;
    var s = try Session.init(gpa, "orig", "/tmp");
    defer s.deinit();
    const u = try s.appendMessage(null, "user", "hi", null, null);
    _ = try s.appendMessage(u, "assistant", "yo", null, null);

    var f = try s.fork(gpa, "forked");
    defer f.deinit();
    try std.testing.expectEqualStrings("forked", f.id);
    try std.testing.expectEqual(@as(usize, 2), f.entries.items.len);
    try std.testing.expectEqualStrings("hi", f.entries.items[0].content);
}

test "assistant metadata round-trip provider model stopReason usage" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const session_path = try std.fs.path.join(gpa, &.{ tmp_path, "meta.jsonl" });
    defer gpa.free(session_path);

    var s = try Session.init(gpa, "meta-sess", tmp_path);
    defer s.deinit();
    const uid = try s.appendMessage(null, "user", "go", null, null);
    _ = try s.appendMessageMeta(uid, "assistant", "calling tool", null,
        \\[{"id":"c1","type":"function","function":{"name":"ls","arguments":"{}"}}]
    , null, .{
        .provider = "openai",
        .model = "gpt-4o-mini",
        .stop_reason = "toolUse",
        .usage_input = 12,
        .usage_output = 4,
        .usage_total = 16,
    });
    const tip = s.lastEntryId().?;
    _ = try s.appendMessageMeta(tip, "assistant", "all done", null, null, null, .{
        .provider = "openai",
        .model = "gpt-4o-mini",
        .stop_reason = "stop",
        .usage_input = 20,
        .usage_output = 8,
        .usage_total = 28,
    });

    try s.save(io, session_path);
    var loaded = try Session.load(gpa, io, session_path);
    defer loaded.deinit();

    try std.testing.expectEqual(@as(usize, 3), loaded.entries.items.len);
    const a1 = loaded.entries.items[1];
    try std.testing.expectEqualStrings("assistant", a1.role);
    try std.testing.expectEqualStrings("openai", a1.meta.provider);
    try std.testing.expectEqualStrings("gpt-4o-mini", a1.meta.model);
    try std.testing.expectEqualStrings("toolUse", a1.meta.stop_reason);
    try std.testing.expectEqual(@as(u64, 12), a1.meta.usage_input);
    try std.testing.expectEqual(@as(u64, 16), a1.meta.usage_total);
    const a2 = loaded.entries.items[2];
    try std.testing.expectEqualStrings("stop", a2.meta.stop_reason);
    try std.testing.expectEqual(@as(u64, 28), a2.meta.usage_total);

    // Also assert serialized JSON contains fields
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, session_path, gpa, .limited(1024 * 1024));
    defer gpa.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"provider\":\"openai\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"stopReason\":\"toolUse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"totalTokens\":16") != null);
}

test "upstream v3 session fixture loads branch tip and roles" {
    const gpa = std.testing.allocator;
    // Shaped from packages/coding-agent/docs/session-format.md (version 3 nested message)
    const fixture =
        \\{"type":"session","version":3,"id":"uuid-upstream-1","timestamp":"2024-12-03T14:00:00.000Z","cwd":"/path/to/project"}
        \\{"type":"message","id":"a1b2c3d4","parentId":null,"timestamp":"2024-12-03T14:00:01.000Z","message":{"role":"user","content":"Hello"}}
        \\{"type":"message","id":"b2c3d4e5","parentId":"a1b2c3d4","timestamp":"2024-12-03T14:00:02.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Hi!"}],"provider":"anthropic","model":"claude","stopReason":"stop"}}
        \\{"type":"message","id":"c3d4e5f6","parentId":"b2c3d4e5","timestamp":"2024-12-03T14:00:03.000Z","message":{"role":"toolResult","toolCallId":"call_123","toolName":"bash","content":[{"type":"text","text":"output"}],"isError":false}}
        \\{"type":"model_change","id":"d4e5f6g7","parentId":"c3d4e5f6","timestamp":"2024-12-03T14:05:00.000Z","provider":"openai","modelId":"gpt-4o"}
        \\{"type":"session_info","id":"e5f6g7h8","parentId":"c3d4e5f6","timestamp":"2024-12-03T14:06:00.000Z","name":"Refactor auth"}
        \\{"type":"compaction","id":"f6g7h8i9","parentId":"c3d4e5f6","timestamp":"2024-12-03T14:10:00.000Z","summary":"User discussed Hello/Hi","tokensBefore":50000}
        \\
    ;
    var s = try Session.parseJsonl(gpa, fixture);
    defer s.deinit();

    try std.testing.expectEqualStrings("uuid-upstream-1", s.id);
    try std.testing.expectEqualStrings("/path/to/project", s.cwd);
    try std.testing.expectEqualStrings("Refactor auth", s.name);
    // messages + compaction synthetic entry
    try std.testing.expect(s.entries.items.len >= 3);
    try std.testing.expectEqualStrings("user", s.entries.items[0].role);
    try std.testing.expectEqualStrings("Hello", s.entries.items[0].content);
    try std.testing.expectEqualStrings("assistant", s.entries.items[1].role);
    try std.testing.expectEqualStrings("Hi!", s.entries.items[1].content);
    try std.testing.expectEqualStrings("a1b2c3d4", s.entries.items[1].parent_id.?);
    try std.testing.expectEqualStrings("tool", s.entries.items[2].role);
    try std.testing.expectEqualStrings("call_123", s.entries.items[2].tool_call_id.?);
    try std.testing.expectEqualStrings("output", s.entries.items[2].content);

    // Active tip after compaction
    try std.testing.expect(s.tip_id != null);
    try std.testing.expectEqualStrings("f6g7h8i9", s.tip_id.?);

    const branch = try s.branchEntries(gpa);
    defer gpa.free(branch);
    try std.testing.expect(branch.len >= 3);
    try std.testing.expectEqualStrings("user", branch[0].role);

    // Round-trip save→reload preserves topology
    const jsonl = try s.toJsonl(gpa);
    defer gpa.free(jsonl);
    var again = try Session.parseJsonl(gpa, jsonl);
    defer again.deinit();
    try std.testing.expectEqualStrings(s.id, again.id);
    try std.testing.expectEqual(@as(usize, s.entries.items.len), again.entries.items.len);
    try std.testing.expectEqualStrings(s.entries.items[0].id, again.entries.items[0].id);
    try std.testing.expectEqualStrings(s.entries.items[1].parent_id.?, again.entries.items[1].parent_id.?);
}

test "listSessions and mostRecentSessionPath" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const dir = path_buf[0..n];

    var s = try Session.init(gpa, "list-me", dir);
    defer s.deinit();
    _ = try s.appendMessage(null, "user", "x", null, null);
    const path = try newSessionPath(gpa, dir, "list-me");
    defer gpa.free(path);
    try s.save(io, path);

    const listed = try listSessions(gpa, io, dir);
    defer {
        for (listed) |*info| {
            var mut = info.*;
            mut.deinit(gpa);
        }
        gpa.free(listed);
    }
    try std.testing.expect(listed.len >= 1);
    try std.testing.expectEqualStrings("list-me", listed[0].id);

    const recent = try mostRecentSessionPath(gpa, io, dir);
    defer if (recent) |r| gpa.free(r);
    try std.testing.expect(recent != null);
    try std.testing.expect(std.mem.indexOf(u8, recent.?, "list-me") != null);
}
