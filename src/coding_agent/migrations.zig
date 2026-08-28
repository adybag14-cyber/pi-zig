//! One-time compatibility migrations run before settings and credentials load.
//!
//! These mirror the original coding-agent startup migrations while making
//! every write atomic and every move non-clobbering. The module also recovers
//! the hashed session directories produced by Pi-Zig before checkpoint 145.
const std = @import("std");
const Io = std.Io;
const config = @import("../config.zig");
const file_permissions = @import("../file_permissions.zig");

pub const Result = struct {
    gpa: std.mem.Allocator,
    migrated_auth_providers: std.ArrayList([]u8) = .empty,
    moved_sessions: usize = 0,
    moved_legacy_hash_entries: usize = 0,
    moved_binaries: usize = 0,
    renamed_prompt_dirs: usize = 0,
    keybindings_migrated: bool = false,
    warnings: std.ArrayList([]u8) = .empty,

    pub fn deinit(self: *Result) void {
        for (self.migrated_auth_providers.items) |value| self.gpa.free(value);
        self.migrated_auth_providers.deinit(self.gpa);
        for (self.warnings.items) |value| self.gpa.free(value);
        self.warnings.deinit(self.gpa);
        self.* = undefined;
    }
};

pub fn run(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, cwd: []const u8) !Result {
    var result = Result{ .gpa = gpa };
    errdefer result.deinit();
    config.ensureDir(io, agent_dir) catch {};
    migrateAuth(gpa, io, agent_dir, &result) catch {};
    migrateRootSessions(gpa, io, agent_dir, &result) catch {};
    migrateLegacyHashedSessions(gpa, io, agent_dir, cwd, &result) catch {};
    migrateTools(gpa, io, agent_dir, &result) catch {};
    migrateKeybindings(gpa, io, agent_dir, &result) catch {};
    migrateExtensionSystem(gpa, io, agent_dir, cwd, &result) catch {};
    return result;
}

fn exists(io: Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

fn atomicWrite(io: Io, path: []const u8, data: []const u8, permissions: std.Io.File.Permissions) !void {
    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, path, .{
        .replace = true,
        .make_path = true,
        .permissions = permissions,
    });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, data, 0);
    try atomic.replace(io);
}

fn cloneJson(a: std.mem.Allocator, value: std.json.Value) !std.json.Value {
    return switch (value) {
        .null => .null,
        .bool => |inner| .{ .bool = inner },
        .integer => |inner| .{ .integer = inner },
        .float => |inner| .{ .float = inner },
        .number_string => |inner| .{ .number_string = try a.dupe(u8, inner) },
        .string => |inner| .{ .string = try a.dupe(u8, inner) },
        .array => |inner| blk: {
            var out = std.json.Array.init(a);
            for (inner.items) |item| try out.append(try cloneJson(a, item));
            break :blk .{ .array = out };
        },
        .object => |inner| blk: {
            var out: std.json.ObjectMap = .empty;
            var iterator = inner.iterator();
            while (iterator.next()) |entry| {
                try out.put(a, try a.dupe(u8, entry.key_ptr.*), try cloneJson(a, entry.value_ptr.*));
            }
            break :blk .{ .object = out };
        },
    };
}

fn stringifyAlloc(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{ .whitespace = .indent_2 }, &out.writer);
    try out.writer.writeByte('\n');
    return out.toOwnedSlice();
}

fn migrateAuth(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, result: *Result) !void {
    const auth_path = try std.fs.path.join(gpa, &.{ agent_dir, "auth.json" });
    defer gpa.free(auth_path);
    if (exists(io, auth_path)) return;
    const oauth_path = try std.fs.path.join(gpa, &.{ agent_dir, "oauth.json" });
    defer gpa.free(oauth_path);
    const settings_path = try std.fs.path.join(gpa, &.{ agent_dir, "settings.json" });
    defer gpa.free(settings_path);

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var auth_root: std.json.ObjectMap = .empty;
    var settings_rewrite: ?[]u8 = null;
    defer if (settings_rewrite) |bytes| gpa.free(bytes);
    var oauth_valid = false;

    if (std.Io.Dir.cwd().readFileAlloc(io, oauth_path, gpa, .limited(8 * 1024 * 1024))) |raw| {
        defer gpa.free(raw);
        if (std.json.parseFromSlice(std.json.Value, gpa, raw, .{ .allocate = .alloc_always })) |parsed_value| {
            var parsed = parsed_value;
            defer parsed.deinit();
            if (parsed.value == .object) {
                oauth_valid = true;
                var iterator = parsed.value.object.iterator();
                while (iterator.next()) |entry| {
                    if (entry.value_ptr.* != .object) continue;
                    var credential = (try cloneJson(a, entry.value_ptr.*)).object;
                    try credential.put(a, "type", .{ .string = "oauth" });
                    try auth_root.put(a, try a.dupe(u8, entry.key_ptr.*), .{ .object = credential });
                    try result.migrated_auth_providers.append(gpa, try gpa.dupe(u8, entry.key_ptr.*));
                }
            }
        } else |_| {}
    } else |_| {}

    if (std.Io.Dir.cwd().readFileAlloc(io, settings_path, gpa, .limited(8 * 1024 * 1024))) |raw| {
        defer gpa.free(raw);
        if (std.json.parseFromSlice(std.json.Value, gpa, raw, .{ .allocate = .alloc_always })) |parsed_value| {
            var parsed = parsed_value;
            defer parsed.deinit();
            if (parsed.value == .object) {
                if (parsed.value.object.get("apiKeys")) |api_keys| if (api_keys == .object) {
                    var iterator = api_keys.object.iterator();
                    while (iterator.next()) |entry| {
                        if (entry.value_ptr.* != .string or auth_root.get(entry.key_ptr.*) != null) continue;
                        var credential: std.json.ObjectMap = .empty;
                        try credential.put(a, "type", .{ .string = "api_key" });
                        try credential.put(a, "key", .{ .string = try a.dupe(u8, entry.value_ptr.string) });
                        try auth_root.put(a, try a.dupe(u8, entry.key_ptr.*), .{ .object = credential });
                        try result.migrated_auth_providers.append(gpa, try gpa.dupe(u8, entry.key_ptr.*));
                    }
                    _ = parsed.value.object.orderedRemove("apiKeys");
                    settings_rewrite = try stringifyAlloc(gpa, parsed.value);
                };
            }
        } else |_| {}
    } else |_| {}

    if (auth_root.count() == 0) return;
    const auth_bytes = try stringifyAlloc(gpa, .{ .object = auth_root });
    defer gpa.free(auth_bytes);
    try atomicWrite(io, auth_path, auth_bytes, file_permissions.privateFile());
    // Removing apiKeys after auth.json is durable cannot lose credentials. A
    // failed cleanup merely leaves a harmless duplicate legacy source.
    if (settings_rewrite) |bytes| try atomicWrite(io, settings_path, bytes, .default_file);
    if (oauth_valid and exists(io, oauth_path)) {
        const migrated_path = try std.fmt.allocPrint(gpa, "{s}.migrated", .{oauth_path});
        defer gpa.free(migrated_path);
        if (!exists(io, migrated_path)) std.Io.Dir.renamePreserve(std.Io.Dir.cwd(), oauth_path, std.Io.Dir.cwd(), migrated_path, io) catch {};
    }
}

fn collectNames(gpa: std.mem.Allocator, io: Io, dir_path: []const u8, suffix: ?[]const u8) !std.ArrayList([]u8) {
    var names: std.ArrayList([]u8) = .empty;
    errdefer {
        for (names.items) |name| gpa.free(name);
        names.deinit(gpa);
    }
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return names;
    defer dir.close(io);
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (suffix) |ending| if (!std.mem.endsWith(u8, entry.name, ending)) continue;
        try names.append(gpa, try gpa.dupe(u8, entry.name));
    }
    return names;
}

fn freeNames(gpa: std.mem.Allocator, names: *std.ArrayList([]u8)) void {
    for (names.items) |name| gpa.free(name);
    names.deinit(gpa);
}

fn movePreserve(io: Io, old_path: []const u8, new_path: []const u8) bool {
    if (exists(io, new_path)) return false;
    std.Io.Dir.renamePreserve(std.Io.Dir.cwd(), old_path, std.Io.Dir.cwd(), new_path, io) catch return false;
    return true;
}

fn migrateRootSessions(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, result: *Result) !void {
    var names = try collectNames(gpa, io, agent_dir, ".jsonl");
    defer freeNames(gpa, &names);
    for (names.items) |name| {
        const old_path = try std.fs.path.join(gpa, &.{ agent_dir, name });
        defer gpa.free(old_path);
        const raw = std.Io.Dir.cwd().readFileAlloc(io, old_path, gpa, .limited(32 * 1024 * 1024)) catch continue;
        defer gpa.free(raw);
        const newline = std.mem.indexOfScalar(u8, raw, '\n') orelse raw.len;
        const first = std.mem.trim(u8, raw[0..newline], " \t\r\n");
        if (first.len == 0) continue;
        var parsed = std.json.parseFromSlice(std.json.Value, gpa, first, .{}) catch continue;
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const type_value = parsed.value.object.get("type") orelse continue;
        const cwd_value = parsed.value.object.get("cwd") orelse continue;
        if (type_value != .string or !std.mem.eql(u8, type_value.string, "session") or cwd_value != .string or cwd_value.string.len == 0) continue;
        const leaf = try config.encodedSessionLeaf(gpa, cwd_value.string);
        defer gpa.free(leaf);
        const destination_dir = try std.fs.path.join(gpa, &.{ agent_dir, "sessions", leaf });
        defer gpa.free(destination_dir);
        try config.ensureDir(io, destination_dir);
        const destination = try std.fs.path.join(gpa, &.{ destination_dir, name });
        defer gpa.free(destination);
        if (movePreserve(io, old_path, destination)) result.moved_sessions += 1;
    }
}

fn migrateLegacyHashedSessions(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, cwd: []const u8, result: *Result) !void {
    const legacy_leaf = try config.legacyHashedSessionLeaf(gpa, cwd);
    defer gpa.free(legacy_leaf);
    const current_leaf = try config.encodedSessionLeaf(gpa, cwd);
    defer gpa.free(current_leaf);
    if (std.mem.eql(u8, legacy_leaf, current_leaf)) return;
    const legacy_dir = try std.fs.path.join(gpa, &.{ agent_dir, "sessions", legacy_leaf });
    defer gpa.free(legacy_dir);
    if (!exists(io, legacy_dir)) return;
    const current_dir = try std.fs.path.join(gpa, &.{ agent_dir, "sessions", current_leaf });
    defer gpa.free(current_dir);
    try config.ensureDir(io, current_dir);
    var names = try collectNames(gpa, io, legacy_dir, null);
    defer freeNames(gpa, &names);
    for (names.items) |name| {
        const old_path = try std.fs.path.join(gpa, &.{ legacy_dir, name });
        defer gpa.free(old_path);
        const new_path = try std.fs.path.join(gpa, &.{ current_dir, name });
        defer gpa.free(new_path);
        if (movePreserve(io, old_path, new_path)) result.moved_legacy_hash_entries += 1;
    }
}

fn migrateTools(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, result: *Result) !void {
    const tools_dir = try std.fs.path.join(gpa, &.{ agent_dir, "tools" });
    defer gpa.free(tools_dir);
    if (!exists(io, tools_dir)) return;
    const bin_dir = try std.fs.path.join(gpa, &.{ agent_dir, "bin" });
    defer gpa.free(bin_dir);
    const binaries = [_][]const u8{ "fd", "rg", "fd.exe", "rg.exe" };
    for (binaries) |name| {
        const old_path = try std.fs.path.join(gpa, &.{ tools_dir, name });
        defer gpa.free(old_path);
        if (!exists(io, old_path)) continue;
        try config.ensureDir(io, bin_dir);
        const new_path = try std.fs.path.join(gpa, &.{ bin_dir, name });
        defer gpa.free(new_path);
        if (exists(io, new_path)) {
            std.Io.Dir.cwd().deleteFile(io, old_path) catch {};
        } else if (movePreserve(io, old_path, new_path)) {
            result.moved_binaries += 1;
        }
    }
}

const keybinding_names = [_]struct { legacy: []const u8, current: []const u8 }{
    .{ .legacy = "cursorUp", .current = "tui.editor.cursorUp" },                           .{ .legacy = "cursorDown", .current = "tui.editor.cursorDown" },
    .{ .legacy = "cursorLeft", .current = "tui.editor.cursorLeft" },                       .{ .legacy = "cursorRight", .current = "tui.editor.cursorRight" },
    .{ .legacy = "cursorWordLeft", .current = "tui.editor.cursorWordLeft" },               .{ .legacy = "cursorWordRight", .current = "tui.editor.cursorWordRight" },
    .{ .legacy = "cursorLineStart", .current = "tui.editor.cursorLineStart" },             .{ .legacy = "cursorLineEnd", .current = "tui.editor.cursorLineEnd" },
    .{ .legacy = "jumpForward", .current = "tui.editor.jumpForward" },                     .{ .legacy = "jumpBackward", .current = "tui.editor.jumpBackward" },
    .{ .legacy = "pageUp", .current = "tui.editor.pageUp" },                               .{ .legacy = "pageDown", .current = "tui.editor.pageDown" },
    .{ .legacy = "deleteCharBackward", .current = "tui.editor.deleteCharBackward" },       .{ .legacy = "deleteCharForward", .current = "tui.editor.deleteCharForward" },
    .{ .legacy = "deleteWordBackward", .current = "tui.editor.deleteWordBackward" },       .{ .legacy = "deleteWordForward", .current = "tui.editor.deleteWordForward" },
    .{ .legacy = "deleteToLineStart", .current = "tui.editor.deleteToLineStart" },         .{ .legacy = "deleteToLineEnd", .current = "tui.editor.deleteToLineEnd" },
    .{ .legacy = "yank", .current = "tui.editor.yank" },                                   .{ .legacy = "yankPop", .current = "tui.editor.yankPop" },
    .{ .legacy = "undo", .current = "tui.editor.undo" },                                   .{ .legacy = "newLine", .current = "tui.input.newLine" },
    .{ .legacy = "submit", .current = "tui.input.submit" },                                .{ .legacy = "tab", .current = "tui.input.tab" },
    .{ .legacy = "copy", .current = "tui.input.copy" },                                    .{ .legacy = "selectUp", .current = "tui.select.up" },
    .{ .legacy = "selectDown", .current = "tui.select.down" },                             .{ .legacy = "selectPageUp", .current = "tui.select.pageUp" },
    .{ .legacy = "selectPageDown", .current = "tui.select.pageDown" },                     .{ .legacy = "selectConfirm", .current = "tui.select.confirm" },
    .{ .legacy = "selectCancel", .current = "tui.select.cancel" },                         .{ .legacy = "interrupt", .current = "app.interrupt" },
    .{ .legacy = "clear", .current = "app.clear" },                                        .{ .legacy = "exit", .current = "app.exit" },
    .{ .legacy = "suspend", .current = "app.suspend" },                                    .{ .legacy = "cycleThinkingLevel", .current = "app.thinking.cycle" },
    .{ .legacy = "cycleModelForward", .current = "app.model.cycleForward" },               .{ .legacy = "cycleModelBackward", .current = "app.model.cycleBackward" },
    .{ .legacy = "selectModel", .current = "app.model.select" },                           .{ .legacy = "expandTools", .current = "app.tools.expand" },
    .{ .legacy = "toggleThinking", .current = "app.thinking.toggle" },                     .{ .legacy = "toggleSessionNamedFilter", .current = "app.session.toggleNamedFilter" },
    .{ .legacy = "externalEditor", .current = "app.editor.external" },                     .{ .legacy = "followUp", .current = "app.message.followUp" },
    .{ .legacy = "dequeue", .current = "app.message.dequeue" },                            .{ .legacy = "pasteImage", .current = "app.clipboard.pasteImage" },
    .{ .legacy = "newSession", .current = "app.session.new" },                             .{ .legacy = "tree", .current = "app.session.tree" },
    .{ .legacy = "fork", .current = "app.session.fork" },                                  .{ .legacy = "resume", .current = "app.session.resume" },
    .{ .legacy = "treeFoldOrUp", .current = "app.tree.foldOrUp" },                         .{ .legacy = "treeUnfoldOrDown", .current = "app.tree.unfoldOrDown" },
    .{ .legacy = "treeEditLabel", .current = "app.tree.editLabel" },                       .{ .legacy = "treeToggleLabelTimestamp", .current = "app.tree.toggleLabelTimestamp" },
    .{ .legacy = "toggleSessionPath", .current = "app.session.togglePath" },               .{ .legacy = "toggleSessionSort", .current = "app.session.toggleSort" },
    .{ .legacy = "renameSession", .current = "app.session.rename" },                       .{ .legacy = "deleteSession", .current = "app.session.delete" },
    .{ .legacy = "deleteSessionNoninvasive", .current = "app.session.deleteNoninvasive" },
};

fn migratedKeyName(name: []const u8) ?[]const u8 {
    for (keybinding_names) |mapping| if (std.mem.eql(u8, mapping.legacy, name)) return mapping.current;
    return null;
}

fn migrateKeybindings(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, result: *Result) !void {
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "keybindings.json" });
    defer gpa.free(path);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(4 * 1024 * 1024)) catch return;
    defer gpa.free(raw);
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{ .allocate = .alloc_always }) catch return;
    defer parsed.deinit();
    if (parsed.value != .object) return;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var output: std.json.ObjectMap = .empty;
    var changed = false;
    var iterator = parsed.value.object.iterator();
    while (iterator.next()) |entry| {
        const replacement = migratedKeyName(entry.key_ptr.*);
        const next = replacement orelse entry.key_ptr.*;
        if (replacement != null) changed = true;
        // A canonical key explicitly supplied by the user outranks its legacy alias.
        if (replacement != null and parsed.value.object.get(next) != null) continue;
        try output.put(a, try a.dupe(u8, next), try cloneJson(a, entry.value_ptr.*));
    }
    if (!changed) return;
    const bytes = try stringifyAlloc(gpa, .{ .object = output });
    defer gpa.free(bytes);
    try atomicWrite(io, path, bytes, .default_file);
    result.keybindings_migrated = true;
}

fn renamePromptDir(gpa: std.mem.Allocator, io: Io, base: []const u8, result: *Result) !void {
    const commands = try std.fs.path.join(gpa, &.{ base, "commands" });
    defer gpa.free(commands);
    const prompts = try std.fs.path.join(gpa, &.{ base, "prompts" });
    defer gpa.free(prompts);
    if (exists(io, commands) and !exists(io, prompts) and movePreserve(io, commands, prompts)) result.renamed_prompt_dirs += 1;
}

fn appendWarning(gpa: std.mem.Allocator, result: *Result, label: []const u8, message: []const u8) !void {
    try result.warnings.append(gpa, try std.fmt.allocPrint(gpa, "{s} {s}", .{ label, message }));
}

fn inspectDeprecated(gpa: std.mem.Allocator, io: Io, base: []const u8, label: []const u8, result: *Result) !void {
    const hooks = try std.fs.path.join(gpa, &.{ base, "hooks" });
    defer gpa.free(hooks);
    if (exists(io, hooks)) try appendWarning(gpa, result, label, "hooks/ directory found; hooks have been renamed to extensions.");
    const tools = try std.fs.path.join(gpa, &.{ base, "tools" });
    defer gpa.free(tools);
    var dir = std.Io.Dir.cwd().openDir(io, tools, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        if (std.ascii.eqlIgnoreCase(entry.name, "fd") or std.ascii.eqlIgnoreCase(entry.name, "rg") or
            std.ascii.eqlIgnoreCase(entry.name, "fd.exe") or std.ascii.eqlIgnoreCase(entry.name, "rg.exe")) continue;
        try appendWarning(gpa, result, label, "tools/ contains custom tools; custom tools have moved to extensions/.");
        break;
    }
}

fn migrateExtensionSystem(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, cwd: []const u8, result: *Result) !void {
    const project = try std.fs.path.join(gpa, &.{ cwd, config.CONFIG_DIR_NAME });
    defer gpa.free(project);
    try renamePromptDir(gpa, io, agent_dir, result);
    try renamePromptDir(gpa, io, project, result);
    try inspectDeprecated(gpa, io, agent_dir, "Global", result);
    try inspectDeprecated(gpa, io, project, "Project", result);
}

test "startup migrations preserve credentials and move legacy resources without clobbering" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const project = try std.fs.path.join(gpa, &.{ root, "project" });
    defer gpa.free(project);
    try config.ensureDir(io, agent_dir);
    try config.ensureDir(io, project);
    const oauth = try std.fs.path.join(gpa, &.{ agent_dir, "oauth.json" });
    defer gpa.free(oauth);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = oauth, .data = "{\"openai\":{\"refresh\":\"r\",\"access\":\"a\",\"expires\":7}}" });
    const settings = try std.fs.path.join(gpa, &.{ agent_dir, "settings.json" });
    defer gpa.free(settings);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = settings, .data = "{\"theme\":\"dark\",\"apiKeys\":{\"anthropic\":\"sk-ant\"}}" });
    const keys = try std.fs.path.join(gpa, &.{ agent_dir, "keybindings.json" });
    defer gpa.free(keys);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = keys, .data = "{\"cursorLeft\":\"alt+h\",\"tui.editor.cursorRight\":\"alt+l\"}" });

    const commands = try std.fs.path.join(gpa, &.{ agent_dir, "commands" });
    defer gpa.free(commands);
    try config.ensureDir(io, commands);
    const tools = try std.fs.path.join(gpa, &.{ agent_dir, "tools" });
    defer gpa.free(tools);
    try config.ensureDir(io, tools);
    const rg_path = try std.fs.path.join(gpa, &.{ tools, "rg" });
    defer gpa.free(rg_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = rg_path, .data = "binary" });
    const custom = try std.fs.path.join(gpa, &.{ tools, "custom.js" });
    defer gpa.free(custom);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = custom, .data = "custom" });
    const hooks = try std.fs.path.join(gpa, &.{ agent_dir, "hooks" });
    defer gpa.free(hooks);
    try config.ensureDir(io, hooks);

    const root_session = try std.fs.path.join(gpa, &.{ agent_dir, "legacy.jsonl" });
    defer gpa.free(root_session);
    const header = try std.fmt.allocPrint(gpa, "{{\"type\":\"session\",\"version\":3,\"id\":\"legacy\",\"timestamp\":\"2024-01-01T00:00:00Z\",\"cwd\":{f}}}\n", .{std.json.fmt(project, .{})});
    defer gpa.free(header);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = root_session, .data = header });

    const legacy_leaf = try config.legacyHashedSessionLeaf(gpa, project);
    defer gpa.free(legacy_leaf);
    const legacy_dir = try std.fs.path.join(gpa, &.{ agent_dir, "sessions", legacy_leaf });
    defer gpa.free(legacy_dir);
    try config.ensureDir(io, legacy_dir);
    const hashed_file = try std.fs.path.join(gpa, &.{ legacy_dir, "hashed.jsonl" });
    defer gpa.free(hashed_file);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = hashed_file, .data = header });

    var result = try run(gpa, io, agent_dir, project);
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.migrated_auth_providers.items.len);
    try std.testing.expectEqual(@as(usize, 1), result.moved_sessions);
    try std.testing.expectEqual(@as(usize, 1), result.moved_legacy_hash_entries);
    try std.testing.expectEqual(@as(usize, 1), result.moved_binaries);
    try std.testing.expectEqual(@as(usize, 1), result.renamed_prompt_dirs);
    try std.testing.expect(result.keybindings_migrated);
    try std.testing.expect(result.warnings.items.len >= 2);

    const auth = try std.fs.path.join(gpa, &.{ agent_dir, "auth.json" });
    defer gpa.free(auth);
    const auth_raw = try std.Io.Dir.cwd().readFileAlloc(io, auth, gpa, .limited(1024 * 1024));
    defer gpa.free(auth_raw);
    try std.testing.expect(std.mem.indexOf(u8, auth_raw, "\"type\": \"oauth\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, auth_raw, "\"type\": \"api_key\"") != null);
    const settings_raw = try std.Io.Dir.cwd().readFileAlloc(io, settings, gpa, .limited(1024 * 1024));
    defer gpa.free(settings_raw);
    try std.testing.expect(std.mem.indexOf(u8, settings_raw, "apiKeys") == null);
    const key_raw = try std.Io.Dir.cwd().readFileAlloc(io, keys, gpa, .limited(1024 * 1024));
    defer gpa.free(key_raw);
    try std.testing.expect(std.mem.indexOf(u8, key_raw, "tui.editor.cursorLeft") != null);

    var second = try run(gpa, io, agent_dir, project);
    defer second.deinit();
    try std.testing.expectEqual(@as(usize, 0), second.migrated_auth_providers.items.len);
    try std.testing.expectEqual(@as(usize, 0), second.moved_sessions);
    try std.testing.expectEqual(@as(usize, 0), second.moved_legacy_hash_entries);
}
