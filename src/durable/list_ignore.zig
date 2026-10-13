//! Gitignore rules used by list_files, following ignore 0.4.33's source precedence and parsing.
const std = @import("std");
const Rule = struct { scope: []u8, pattern: []u8, negated: bool, directory: bool, category: enum { global, exclude, gitignore }, repo: u64 };
pub const Mark = struct { length: usize, repo: u64 };
pub const Stack = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    home: ?[]const u8,
    rules: std.ArrayList(Rule) = .empty,
    repo: u64 = 0,
    next_repo: u64 = 1,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, root: []const u8, home: ?[]const u8, enabled: bool) !Stack {
        var self: Stack = .{ .gpa = gpa, .io = io, .home = home };
        errdefer self.deinit();
        if (!enabled) return self;
        try self.global(root);
        var parents: std.ArrayList([]const u8) = .empty;
        defer parents.deinit(gpa);
        var cursor = std.fs.path.dirname(root);
        while (cursor) |parent| {
            try parents.append(gpa, parent);
            const next = std.fs.path.dirname(parent);
            if (next != null and std.mem.eql(u8, next.?, parent)) break;
            cursor = next;
        }
        var index = parents.items.len;
        while (index > 0) {
            index -= 1;
            try self.enter(parents.items[index]);
        }
        return self;
    }
    pub fn mark(self: Stack) Mark {
        return .{ .length = self.rules.items.len, .repo = self.repo };
    }
    pub fn restore(self: *Stack, checkpoint: Mark) void {
        for (self.rules.items[checkpoint.length..]) |rule| {
            self.gpa.free(rule.scope);
            self.gpa.free(rule.pattern);
        }
        self.rules.shrinkRetainingCapacity(checkpoint.length);
        self.repo = checkpoint.repo;
    }
    pub fn deinit(self: *Stack) void {
        self.restore(.{ .length = 0, .repo = 0 });
        self.rules.deinit(self.gpa);
    }
    fn read(self: Stack, path: []const u8) !?[]u8 {
        return std.Io.Dir.cwd().readFileAlloc(self.io, path, self.gpa, .unlimited) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => null,
        };
    }
    fn add(self: *Stack, path: []const u8, scope: []const u8, category: @FieldType(Rule, "category")) !void {
        const bytes = (try self.read(path)) orelse return;
        defer self.gpa.free(bytes);
        // ignore 0.4.33 retains earlier rules, then stops at an invalid UTF-8 line.
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        var first = true;
        while (lines.next()) |raw| {
            var line = raw;
            if (first) while (std.mem.startsWith(u8, line, "\xef\xbb\xbf")) {
                line = line[3..];
            };
            first = false;
            if (!std.unicode.utf8ValidateSlice(line)) break;
            if (std.mem.startsWith(u8, line, "#")) continue;
            if (!std.mem.endsWith(u8, line, "\\ ")) line = trimRight(line);
            if (line.len == 0) continue;
            var negated = false;
            if (std.mem.startsWith(u8, line, "\\!") or std.mem.startsWith(u8, line, "\\#")) {
                line = line[1..];
            } else if (line[0] == '!') {
                negated = true;
                line = line[1..];
            }
            const anchored = std.mem.startsWith(u8, line, "/");
            if (anchored) line = line[1..];
            const directory = std.mem.endsWith(u8, line, "/");
            if (directory) {
                line = line[0 .. line.len - 1];
                if (std.mem.endsWith(u8, line, "\\")) line = line[0 .. line.len - 1];
            }
            const prefix = !anchored and std.mem.indexOfScalar(u8, line, '/') == null;
            const suffix = std.mem.endsWith(u8, line, "/**");
            const pattern = try std.fmt.allocPrint(self.gpa, "{s}{s}{s}", .{ if (prefix) "**/" else "", line, if (suffix) "/*" else "" });
            errdefer self.gpa.free(pattern);
            const owned_scope = try self.gpa.dupe(u8, scope);
            errdefer self.gpa.free(owned_scope);
            try self.rules.append(self.gpa, .{ .scope = owned_scope, .pattern = pattern, .negated = negated, .directory = directory, .category = category, .repo = self.repo });
        }
    }
    fn exists(self: Stack, path: []const u8) bool {
        _ = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return false;
        return true;
    }
    pub fn enter(self: *Stack, dir: []const u8) !void {
        const git = try std.fs.path.join(self.gpa, &.{ dir, ".git" });
        defer self.gpa.free(git);
        const jj = try std.fs.path.join(self.gpa, &.{ dir, ".jj" });
        defer self.gpa.free(jj);
        if (self.exists(git) or self.exists(jj)) {
            self.repo = self.next_repo;
            self.next_repo += 1;
        }
        // The ignore crate also loads parent files outside a repository. They apply once a descendant is a worktree,
        // but rules above the nearest repository boundary are suppressed.
        const local = try std.fs.path.join(self.gpa, &.{ dir, ".gitignore" });
        defer self.gpa.free(local);
        try self.add(local, dir, .gitignore);
        const stat = std.Io.Dir.cwd().statFile(self.io, git, .{}) catch return;
        if (stat.kind == .file) {
            const marker = (try self.read(git)) orelse return;
            defer self.gpa.free(marker);
            const line = std.mem.trimEnd(u8, marker[0 .. std.mem.indexOfScalar(u8, marker, '\n') orelse marker.len], "\r");
            if (!std.mem.startsWith(u8, line, "gitdir: ")) return;
            // Preserve ignore 0.4.33's daemon-cwd resolution of the gitdir and commondir marker.
            const common_path = try std.fs.path.join(self.gpa, &.{ line[8..], "commondir" });
            defer self.gpa.free(common_path);
            const common = (try self.read(common_path)) orelse return;
            defer self.gpa.free(common);
            const common_line = std.mem.trimEnd(u8, common[0 .. std.mem.indexOfScalar(u8, common, '\n') orelse common.len], "\r");
            const common_dir = if (std.mem.startsWith(u8, common_line, ".")) try std.fs.path.join(self.gpa, &.{ line[8..], common_line }) else try self.gpa.dupe(u8, common_line);
            defer self.gpa.free(common_dir);
            const path = try std.fs.path.join(self.gpa, &.{ common_dir, "info", "exclude" });
            defer self.gpa.free(path);
            try self.add(path, dir, .exclude);
        } else {
            const path = try std.fs.path.join(self.gpa, &.{ git, "info", "exclude" });
            defer self.gpa.free(path);
            try self.add(path, dir, .exclude);
        }
    }
    /// null means no rule, false is a whitelist (which also overrides hidden filtering).
    pub fn decision(self: Stack, path: []const u8, directory: bool) !?bool {
        if (self.repo == 0) return null;
        inline for (.{ .gitignore, .exclude, .global }) |category| {
            var index = self.rules.items.len;
            while (index > 0) {
                index -= 1;
                const rule = self.rules.items[index];
                if (rule.category != category or (category != .global and rule.repo != self.repo) or (rule.directory and !directory)) continue;
                const relative_raw = try std.fs.path.relative(self.gpa, ".", null, rule.scope, path);
                defer self.gpa.free(relative_raw);
                if (std.mem.startsWith(u8, relative_raw, "..")) continue;
                if (@import("builtin").os.tag == .windows) for (relative_raw) |*byte| {
                    if (byte.* == '\\') byte.* = '/';
                };
                if (try glob(self.gpa, rule.pattern, relative_raw)) return !rule.negated;
            }
        }
        return null;
    }
    pub fn ignored(self: Stack, path: []const u8, directory: bool) !bool {
        return (try self.decision(path, directory)) orelse false;
    }
    fn global(self: *Stack, root: []const u8) !void {
        const env_home = try environment(self.gpa, if (@import("builtin").os.tag == .windows) "USERPROFILE" else "HOME");
        defer if (env_home) |path| self.gpa.free(path);
        const home = self.home orelse env_home;
        const xdg = try environment(self.gpa, "XDG_CONFIG_HOME");
        defer if (xdg) |path| self.gpa.free(path);
        const global_config = try environment(self.gpa, "GIT_CONFIG_GLOBAL");
        defer if (global_config) |path| self.gpa.free(path);
        const system_config = try environment(self.gpa, "GIT_CONFIG_SYSTEM");
        defer if (system_config) |path| self.gpa.free(path);
        const config_home = if (xdg) |path| try self.gpa.dupe(u8, path) else if (home) |path| try std.fs.path.join(self.gpa, &.{ path, ".config" }) else null;
        defer if (config_home) |path| self.gpa.free(path);
        var candidates: std.ArrayList([]u8) = .empty;
        defer {
            for (candidates.items) |path| self.gpa.free(path);
            candidates.deinit(self.gpa);
        }
        try candidates.ensureTotalCapacity(self.gpa, 4);
        if (global_config) |path| candidates.appendAssumeCapacity(try self.gpa.dupe(u8, path));
        if (home) |path| candidates.appendAssumeCapacity(try std.fs.path.join(self.gpa, &.{ path, ".gitconfig" }));
        if (config_home) |path| candidates.appendAssumeCapacity(try std.fs.path.join(self.gpa, &.{ path, "git", "config" }));
        candidates.appendAssumeCapacity(try self.gpa.dupe(u8, system_config orelse "/etc/gitconfig"));
        for (candidates.items) |path| {
            const bytes = (try self.read(path)) orelse continue;
            defer self.gpa.free(bytes);
            if (excludesConfig(bytes)) |value| {
                const expanded = if (home) |prefix| try std.mem.replaceOwned(u8, self.gpa, value, "~", prefix) else try self.gpa.dupe(u8, value);
                defer self.gpa.free(expanded);
                try self.add(expanded, root, .global);
                return;
            }
        }
        if (config_home) |path| {
            const default = try std.fs.path.join(self.gpa, &.{ path, "git", "ignore" });
            defer self.gpa.free(default);
            try self.add(default, root, .global);
        }
    }
};
fn environment(gpa: std.mem.Allocator, comptime key: [:0]const u8) !?[]u8 {
    if (@import("builtin").os.tag == .windows) {
        const value = std.process.Environ.getWindows(.{ .block = .global }, std.unicode.utf8ToUtf16LeStringLiteral(key)) orelse return null;
        if (value.len == 0) return null;
        return try std.unicode.wtf16LeToWtf8Alloc(gpa, value);
    }
    const value = std.c.getenv(key) orelse return null;
    const bytes = std.mem.span(value);
    return if (bytes.len > 0) try gpa.dupe(u8, bytes) else null;
}
fn trimRight(bytes: []const u8) []const u8 {
    var end = bytes.len;
    while (end > 0) {
        var start = end - 1;
        while (start > 0 and bytes[start] & 0xc0 == 0x80) start -= 1;
        const scalar = std.unicode.utf8Decode(bytes[start..end]) catch break;
        const whitespace = switch (scalar) {
            0x09...0x0d, 0x20, 0x85, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000 => true,
            else => false,
        };
        if (!whitespace) break;
        end = start;
    }
    return bytes[0..end];
}
fn excludesConfig(bytes: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r\x0b\x0c");
        const equals = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        if (!std.ascii.eqlIgnoreCase(std.mem.trimEnd(u8, line[0..equals], " \t\r"), "excludesfile")) continue;
        var value = std.mem.trim(u8, line[equals + 1 ..], " \t\r");
        if (std.mem.startsWith(u8, value, "\"")) value = std.mem.trimStart(u8, value[1..], " \t\r");
        if (std.mem.endsWith(u8, value, "\"")) value = std.mem.trimEnd(u8, value[0 .. value.len - 1], " \t\r");
        if (value.len > 0 and std.mem.indexOfAny(u8, value, " \t\r") == null and std.unicode.utf8ValidateSlice(value)) return value;
    }
    return null;
}

/// Memoized byte globbing: wildcards never cross separators except a whole-component **.
fn classEnd(pattern: []const u8, start: usize) ?usize {
    var index = start + 1;
    if (index < pattern.len and (pattern[index] == '!' or pattern[index] == '^')) index += 1;
    if (index < pattern.len and pattern[index] == ']') index += 1;
    return std.mem.indexOfScalarPos(u8, pattern, index, ']');
}
fn alternateEnd(pattern: []const u8, start: usize) ?usize {
    var depth: usize = 1;
    var index = start + 1;
    while (index < pattern.len) : (index += 1) {
        if (pattern[index] == '\\') {
            index += 1;
            continue;
        }
        if (pattern[index] == '[') if (classEnd(pattern, index)) |end| {
            index = end;
            continue;
        };
        if (pattern[index] == '{') depth += 1;
        if (pattern[index] == '}') {
            depth -= 1;
            if (depth == 0) return index;
        }
    }
    return null;
}
fn branchNonempty(pattern: []const u8) bool {
    var index: usize = 0;
    while (index < pattern.len) : (index += 1) {
        if (pattern[index] == ',') continue;
        if (pattern[index] == '{') {
            const end = alternateEnd(pattern, index) orelse return true;
            if (branchNonempty(pattern[index + 1 .. end])) return true;
            index = end;
        } else return true;
    }
    return false;
}
fn validGlob(pattern: []const u8) bool {
    var depth: usize = 0;
    var index: usize = 0;
    while (index < pattern.len) : (index += 1) {
        if (pattern[index] == '\\') {
            index += 1;
            if (index == pattern.len) return false;
            continue;
        }
        if (pattern[index] == '[') if (classEnd(pattern, index)) |end| {
            var cursor = index + 1;
            if (pattern[cursor] == '!' or pattern[cursor] == '^') cursor += 1;
            while (cursor < end) {
                if (cursor + 2 < end and pattern[cursor + 1] == '-') {
                    if (pattern[cursor] > pattern[cursor + 2]) return false;
                    cursor += 3;
                } else cursor += 1;
            }
            index = end;
            continue;
        };
        if (pattern[index] == '{') depth += 1;
        if (pattern[index] == '}') {
            if (depth == 0) return false;
            depth -= 1;
        }
    }
    return depth == 0;
}
pub fn glob(gpa: std.mem.Allocator, pattern: []const u8, text: []const u8) !bool {
    if (!validGlob(pattern)) return false;
    // globset's alternates are supported by ignore's GitignoreBuilder too.
    var cursor: usize = 0;
    while (cursor < pattern.len) : (cursor += 1) {
        if (pattern[cursor] == '\\') {
            cursor += 1;
            continue;
        }
        if (pattern[cursor] == '[') if (classEnd(pattern, cursor)) |end| {
            cursor = end;
            continue;
        };
        if (pattern[cursor] != '{') continue;
        const end = alternateEnd(pattern, cursor).?;
        var choice_start = cursor + 1;
        var index = choice_start;
        var depth: usize = 0;
        var nonempty = false;
        while (index <= end) : (index += 1) {
            if (index < end and pattern[index] == '\\') {
                index += 1;
                continue;
            }
            if (index < end and pattern[index] == '[') if (classEnd(pattern, index)) |class_end| {
                index = class_end;
                continue;
            };
            if (index < end and pattern[index] == '{') depth += 1;
            if (index < end and pattern[index] == '}') depth -= 1;
            if (index != end and !(depth == 0 and pattern[index] == ',')) continue;
            const choice = pattern[choice_start..index];
            choice_start = index + 1;
            if (!branchNonempty(choice)) continue;
            nonempty = true;
            const expanded = try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ pattern[0..cursor], choice, pattern[end + 1 ..] });
            defer gpa.free(expanded);
            if (try glob(gpa, expanded, text)) return true;
        }
        if (nonempty) return false;
        const expanded = try std.fmt.allocPrint(gpa, "{s}{s}", .{ pattern[0..cursor], pattern[end + 1 ..] });
        defer gpa.free(expanded);
        return glob(gpa, expanded, text);
    }
    const memo = try gpa.alloc(u8, (pattern.len + 1) * (text.len + 1));
    defer gpa.free(memo);
    @memset(memo, 0);
    return (Glob{ .pattern = pattern, .text = text, .memo = memo }).match(0, 0);
}
const Glob = struct {
    pattern: []const u8,
    text: []const u8,
    memo: []u8,
    fn match(self: Glob, p: usize, t: usize) bool {
        const key = p * (self.text.len + 1) + t;
        if (self.memo[key] != 0) return self.memo[key] == 2;
        const result = self.compute(p, t);
        self.memo[key] = if (result) 2 else 1;
        return result;
    }
    fn compute(self: Glob, p: usize, t: usize) bool {
        if (p == self.pattern.len) return t == self.text.len;
        const c = self.pattern[p];
        if (c == '*') {
            var end = p;
            while (end < self.pattern.len and self.pattern[end] == '*') : (end += 1) {}
            const recursive = end - p == 2 and (p == 0 or self.pattern[p - 1] == '/') and (end == self.pattern.len or self.pattern[end] == '/');
            if (recursive and end < self.pattern.len) {
                if (self.match(end + 1, t)) return true;
                var cursor = t;
                while (cursor < self.text.len) : (cursor += 1) if (self.text[cursor] == '/' and self.match(end + 1, cursor + 1)) return true;
                return false;
            }
            if (self.match(end, t)) return true;
            return t < self.text.len and (recursive or self.text[t] != '/') and self.match(p, t + 1);
        }
        if (c == '?') return t < self.text.len and self.text[t] != '/' and self.match(p + 1, t + 1);
        if (c == '\\') return p + 1 < self.pattern.len and t < self.text.len and self.pattern[p + 1] == self.text[t] and self.match(p + 2, t + 1);
        if (c == '[') {
            var end = p + 1;
            if (end < self.pattern.len and (self.pattern[end] == '!' or self.pattern[end] == '^')) end += 1;
            if (end < self.pattern.len and self.pattern[end] == ']') end += 1;
            while (end < self.pattern.len and self.pattern[end] != ']') : (end += 1) {}
            if (end < self.pattern.len) {
                if (t == self.text.len or self.text[t] == '/') return false;
                var cursor = p + 1;
                const negate = cursor < end and (self.pattern[cursor] == '!' or self.pattern[cursor] == '^');
                if (negate) cursor += 1;
                var matched = false;
                while (cursor < end) {
                    const low = self.pattern[cursor];
                    if (cursor + 2 < end and self.pattern[cursor + 1] == '-') {
                        const high = self.pattern[cursor + 2];
                        if (low <= self.text[t] and self.text[t] <= high) matched = true;
                        cursor += 3;
                    } else {
                        if (low == self.text[t]) matched = true;
                        cursor += 1;
                    }
                }
                return matched != negate and self.match(end + 1, t + 1);
            }
        }
        return t < self.text.len and c == self.text[t] and self.match(p + 1, t + 1);
    }
};

test "listFiles ignore globs retain hierarchy, escapes, recursive separators, and classes" {
    const gpa = std.testing.allocator;
    const cases = .{ .{ "**/*.log", "a/b.log", true }, .{ "a/**/b", "a/b", true }, .{ "a/**/b", "a/x/y/b", true }, .{ "a/*/b", "a/x/y/b", false }, .{ "[a-c]?.txt", "b2.txt", true }, .{ "[!a-c]", "b", false }, .{ "\\!name", "!name", true }, .{ "[abc", "[abc", true } };
    inline for (cases) |case| try std.testing.expectEqual(case[2], try glob(gpa, case[0], case[1]));
}
