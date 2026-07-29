//! Builtin slash command handlers for interactive REPL.
const std = @import("std");
const Io = std.Io;
const session_mod = @import("../agent/session.zig");
const compaction = @import("../agent/compaction.zig");
const export_html = @import("export_html.zig");
const settings_mod = @import("settings.zig");
const context_mod = @import("context.zig");
const skills_mod = @import("skills.zig");
const tui_render = @import("../tui/render.zig");
const live_state = @import("live_state.zig");

pub const LiveState = live_state.LiveState;

pub const SlashResult = enum {
    handled,
    quit,
    not_command,
    run_prompt,
};

pub const SlashContext = struct {
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    sess: *session_mod.Session,
    session_path: ?[]const u8,
    session_dir: ?[]const u8,
    agent_dir: ?[]const u8,
    model: *?[]const u8,
    provider: *?[]const u8,
    settings_text: []const u8,
    trust_project: bool = true,
    /// When set, /model and /reload mutate live agent/client state for subsequent turns.
    live: ?*live_state.LiveState = null,
};

pub fn handle(ctx: SlashContext, line: []const u8) !SlashResult {
    if (line.len == 0 or line[0] != '/') return .not_command;

    const rest = line[1..];
    const space = std.mem.indexOfScalar(u8, rest, ' ');
    const cmd = if (space) |s| rest[0..s] else rest;
    const arg = if (space) |s| std.mem.trim(u8, rest[s + 1 ..], " \t") else "";

    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "?")) {
        try tui_render.printLine(ctx.io,
            \\Slash commands:
            \\  /help /quit /exit /session /new /name <n> /model <id>
            \\  /compact /export [path] /import <path> /fork /clone
            \\  /tree /reload /hotkeys /changelog /copy
            \\  /login <provider> <key> /logout /settings /resume
        );
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "quit") or std.mem.eql(u8, cmd, "exit")) {
        return .quit;
    }
    if (std.mem.eql(u8, cmd, "session")) {
        const msg = try std.fmt.allocPrint(ctx.gpa, "session id={s} name={s} messages={d} tip={s}", .{
            ctx.sess.id,
            if (ctx.sess.name.len > 0) ctx.sess.name else "(unnamed)",
            ctx.sess.entries.items.len,
            ctx.sess.lastEntryId() orelse "none",
        });
        defer ctx.gpa.free(msg);
        try tui_render.printLine(ctx.io, msg);
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "new")) {
        for (ctx.sess.entries.items) |*e| e.deinit(ctx.gpa);
        ctx.sess.entries.clearRetainingCapacity();
        ctx.gpa.free(ctx.sess.id);
        ctx.sess.id = try session_mod.generateSessionId(ctx.gpa);
        ctx.sess.next_seq = 1;
        if (ctx.sess.tip_id) |t| {
            ctx.gpa.free(t);
            ctx.sess.tip_id = null;
        }
        try tui_render.printLine(ctx.io, "Started new session.");
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "name")) {
        if (arg.len == 0) {
            try tui_render.printLine(ctx.io, "usage: /name <session-name>");
            return .handled;
        }
        try ctx.sess.setName(arg);
        try tui_render.printLine(ctx.io, "Session named.");
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "model")) {
        if (arg.len == 0) {
            const m = ctx.model.* orelse "(default)";
            const msg = try std.fmt.allocPrint(ctx.gpa, "model={s}", .{m});
            defer ctx.gpa.free(msg);
            try tui_render.printLine(ctx.io, msg);
            return .handled;
        }
        if (ctx.live) |live| {
            try live_state.applyModel(live, arg);
        } else {
            // Fallback when no live client is wired (should not happen in main REPL).
            ctx.model.* = try ctx.gpa.dupe(u8, arg);
        }
        try tui_render.printLine(ctx.io, "Model updated for subsequent turns.");
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "compact")) {
        try compaction.compact(ctx.sess, .{});
        try tui_render.printLine(ctx.io, "Session compacted.");
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "export")) {
        const path = if (arg.len > 0) arg else "session.html";
        const html = try export_html.exportHtml(ctx.gpa, ctx.sess);
        defer ctx.gpa.free(html);
        try std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = path, .data = html });
        const msg = try std.fmt.allocPrint(ctx.gpa, "Exported to {s}", .{path});
        defer ctx.gpa.free(msg);
        try tui_render.printLine(ctx.io, msg);
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "import")) {
        if (arg.len == 0) {
            try tui_render.printLine(ctx.io, "usage: /import <session.jsonl>");
            return .handled;
        }
        const loaded = session_mod.Session.load(ctx.gpa, ctx.io, arg) catch {
            try tui_render.printLine(ctx.io, "import failed");
            return .handled;
        };
        ctx.sess.deinit();
        ctx.sess.* = loaded;
        try tui_render.printLine(ctx.io, "Session imported.");
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "fork") or std.mem.eql(u8, cmd, "clone")) {
        const new_id = try session_mod.generateSessionId(ctx.gpa);
        defer ctx.gpa.free(new_id);
        var forked = try ctx.sess.fork(ctx.gpa, new_id);
        if (ctx.session_dir) |sd| {
            const path = try session_mod.newSessionPath(ctx.gpa, sd, new_id);
            defer ctx.gpa.free(path);
            try forked.save(ctx.io, path);
            const msg = try std.fmt.allocPrint(ctx.gpa, "Forked to {s}", .{path});
            defer ctx.gpa.free(msg);
            try tui_render.printLine(ctx.io, msg);
        } else {
            try tui_render.printLine(ctx.io, "Forked in-memory (no session-dir).");
        }
        ctx.sess.deinit();
        ctx.sess.* = forked;
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "tree")) {
        const tree = try ctx.sess.treeSummary(ctx.gpa);
        defer ctx.gpa.free(tree);
        try tui_render.writeAll(ctx.io, tree);
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "reload")) {
        if (ctx.live) |live| {
            const msg = try live_state.applyReload(live);
            defer ctx.gpa.free(msg);
            try tui_render.printLine(ctx.io, msg);
        } else {
            // Discovery-only fallback (no live agent_cfg) — still reports disk state.
            var bundle = try context_mod.discoverTrusted(ctx.gpa, ctx.io, ctx.cwd, ctx.agent_dir, ctx.trust_project);
            defer bundle.deinit(ctx.gpa);
            const skills = try skills_mod.discoverTrusted(ctx.gpa, ctx.io, ctx.cwd, ctx.agent_dir, &.{}, ctx.trust_project);
            defer {
                for (skills) |*s| {
                    var mut = s.*;
                    mut.deinit(ctx.gpa);
                }
                ctx.gpa.free(skills);
            }
            const msg = try std.fmt.allocPrint(
                ctx.gpa,
                "Reloaded (no live agent): {d} context file(s), {d} skill(s)",
                .{ bundle.files.len, skills.len },
            );
            defer ctx.gpa.free(msg);
            try tui_render.printLine(ctx.io, msg);
        }
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "hotkeys")) {
        try tui_render.printLine(ctx.io,
            \\Hotkeys (line REPL):
            \\  Enter — send  |  /quit — exit  |  /help — commands
        );
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "changelog")) {
        try tui_render.printLine(ctx.io,
            \\pi-zig changelog (summary):
            \\  0.2.0 — full multi-provider, 7 tools, sessions, skills, modes
            \\  0.1.0 — minimal agent loop
        );
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "copy")) {
        if (ctx.sess.lastAssistantText()) |t| {
            try tui_render.printLine(ctx.io, t);
        } else {
            try tui_render.printLine(ctx.io, "(no assistant message yet)");
        }
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "login")) {
        var it = std.mem.tokenizeAny(u8, arg, " \t");
        const prov = it.next() orelse {
            try tui_render.printLine(ctx.io, "usage: /login <provider> <api-key>");
            return .handled;
        };
        const key = it.next() orelse {
            try tui_render.printLine(ctx.io, "usage: /login <provider> <api-key>");
            return .handled;
        };
        if (ctx.agent_dir) |ad| {
            const env_key = if (std.mem.eql(u8, prov, "openai"))
                "OPENAI_API_KEY"
            else if (std.mem.eql(u8, prov, "anthropic"))
                "ANTHROPIC_API_KEY"
            else if (std.mem.eql(u8, prov, "google"))
                "GOOGLE_API_KEY"
            else
                "PI_API_KEY";
            try settings_mod.saveCredential(ctx.gpa, ctx.io, ad, env_key, key);
            try tui_render.printLine(ctx.io, "Credential stored.");
        } else {
            try tui_render.printLine(ctx.io, "No agent dir; cannot store credentials.");
        }
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "logout")) {
        if (ctx.agent_dir) |ad| {
            try settings_mod.clearCredentials(ctx.io, ad);
            try tui_render.printLine(ctx.io, "Credentials cleared.");
        }
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "settings")) {
        try tui_render.printLine(ctx.io, ctx.settings_text);
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "resume")) {
        if (ctx.session_dir) |sd| {
            const sessions = try session_mod.listSessions(ctx.gpa, ctx.io, sd);
            defer {
                for (sessions) |*s| {
                    var mut = s.*;
                    mut.deinit(ctx.gpa);
                }
                ctx.gpa.free(sessions);
            }
            if (sessions.len == 0) {
                try tui_render.printLine(ctx.io, "(no sessions)");
            } else {
                for (sessions) |s| {
                    const msg = try std.fmt.allocPrint(ctx.gpa, "  {s}  {s}  {s}", .{ s.id, s.name, s.path });
                    defer ctx.gpa.free(msg);
                    try tui_render.printLine(ctx.io, msg);
                }
            }
        } else {
            try tui_render.printLine(ctx.io, "No session directory configured.");
        }
        return .handled;
    }

    try tui_render.printLine(ctx.io, "Unknown command. Try /help");
    return .handled;
}

test "slash session new model quit drive real session state" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    tui_render.setSilent(true);
    defer tui_render.setSilent(false);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    var sess = try session_mod.Session.init(gpa, "slash-test", tmp_path);
    defer sess.deinit();
    _ = try sess.appendMessage(null, "user", "hello", null, null);
    _ = try sess.appendMessage(sess.lastEntryId(), "assistant", "hi there", null, null);

    var model: ?[]const u8 = null;
    defer if (model) |m| gpa.free(m);
    var provider: ?[]const u8 = null;
    var model_owned = false;
    var client_model: []const u8 = "initial";
    var cfg = @import("../agent/loop.zig").AgentConfig{};
    var owned_sys: ?[]u8 = null;
    defer if (owned_sys) |s| gpa.free(s);
    var owned_ctx: ?[]u8 = null;
    defer if (owned_ctx) |c| gpa.free(c);

    var live = live_state.LiveState{
        .gpa = gpa,
        .io = io,
        .cwd = tmp_path,
        .agent_dir = null,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .model_display = &model,
        .active_model = &client_model,
        .model_display_owned = &model_owned,
    };

    const ctx = SlashContext{
        .gpa = gpa,
        .io = io,
        .cwd = tmp_path,
        .sess = &sess,
        .session_path = null,
        .session_dir = null,
        .agent_dir = null,
        .model = &model,
        .provider = &provider,
        .settings_text = "settings:ok",
        .trust_project = true,
        .live = &live,
    };

    try std.testing.expect((try handle(ctx, "/model gpt-test")) == .handled);
    try std.testing.expectEqualStrings("gpt-test", model.?);
    try std.testing.expectEqualStrings("gpt-test", client_model);
    try std.testing.expect((try handle(ctx, "/name my-sess")) == .handled);
    try std.testing.expectEqualStrings("my-sess", sess.name);
    try std.testing.expect((try handle(ctx, "/compact")) == .handled);
    try std.testing.expect((try handle(ctx, "/new")) == .handled);
    try std.testing.expectEqual(@as(usize, 0), sess.entries.items.len);
    try std.testing.expect((try handle(ctx, "/quit")) == .quit);
    try std.testing.expect((try handle(ctx, "not a slash")) == .not_command);
}

test "handle /reload applies AGENTS.md into live agent_cfg" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    tui_render.setSilent(true);
    defer tui_render.setSilent(false);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    const agents = try std.fs.path.join(gpa, &.{ tmp_path, "AGENTS.md" });
    defer gpa.free(agents);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = agents, .data = "reload-v1" });

    var sess = try session_mod.Session.init(gpa, "reload-test", tmp_path);
    defer sess.deinit();
    var model: ?[]const u8 = null;
    var provider: ?[]const u8 = null;
    var model_owned = false;
    var cfg = @import("../agent/loop.zig").AgentConfig{};
    var owned_sys: ?[]u8 = null;
    defer if (owned_sys) |s| gpa.free(s);
    var owned_ctx: ?[]u8 = null;
    defer if (owned_ctx) |c| gpa.free(c);

    var live = live_state.LiveState{
        .gpa = gpa,
        .io = io,
        .cwd = tmp_path,
        .agent_dir = null,
        .trust_project = true,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .model_display = &model,
        .active_model = null,
        .model_display_owned = &model_owned,
    };
    const ctx = SlashContext{
        .gpa = gpa,
        .io = io,
        .cwd = tmp_path,
        .sess = &sess,
        .session_path = null,
        .session_dir = null,
        .agent_dir = null,
        .model = &model,
        .provider = &provider,
        .settings_text = "",
        .trust_project = true,
        .live = &live,
    };

    try std.testing.expect((try handle(ctx, "/reload")) == .handled);
    try std.testing.expect(std.mem.indexOf(u8, cfg.context_prompt, "reload-v1") != null);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = agents, .data = "reload-v2-APPLIED" });
    try std.testing.expect((try handle(ctx, "/reload")) == .handled);
    try std.testing.expect(std.mem.indexOf(u8, cfg.context_prompt, "reload-v2-APPLIED") != null);
}
