//! Pi package resource discovery and manifest pattern semantics.
//!
//! The upstream package manifest accepts concrete files/directories, glob
//! sources, and ordered override selectors (`!`, `+`, and `-`).  This module
//! resolves those expressions to exact resource files so later loaders do not
//! accidentally execute helper modules that merely share a directory.
const std = @import("std");
const Io = std.Io;

pub const ResourceType = enum {
    extensions,
    skills,
    prompts,
    themes,
};

pub const PathList = struct {
    gpa: std.mem.Allocator,
    items: std.ArrayList([]u8) = .empty,

    pub fn init(gpa: std.mem.Allocator) PathList {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *PathList) void {
        for (self.items.items) |path| self.gpa.free(path);
        self.items.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn appendOwnedUnique(self: *PathList, path: []u8) !void {
        for (self.items.items) |existing| {
            if (samePath(existing, path)) {
                self.gpa.free(path);
                return;
            }
        }
        try self.items.append(self.gpa, path);
    }

    pub fn appendCopyUnique(self: *PathList, path: []const u8) !void {
        try self.appendOwnedUnique(try self.gpa.dupe(u8, path));
    }

    pub fn removeAt(self: *PathList, index: usize) void {
        self.gpa.free(self.items.items[index]);
        _ = self.items.orderedRemove(index);
    }
};

const Resolver = struct {
    gpa: std.mem.Allocator,
    io: Io,
    resource_type: ResourceType,
    out: *PathList,
    seen_collect_dirs: std.StringHashMap(void),
    seen_walk_dirs: std.StringHashMap(void),
    /// Root whose nested .gitignore/.ignore/.fdignore files govern the current
    /// directory-source traversal. Exact manifest files intentionally bypass
    /// ignore processing, matching the original package loader.
    ignore_root: ?[]const u8 = null,
    visited_nodes: usize = 0,

    const max_depth = 64;
    const max_nodes = 100_000;

    fn init(gpa: std.mem.Allocator, io: Io, resource_type: ResourceType, out: *PathList) Resolver {
        return .{
            .gpa = gpa,
            .io = io,
            .resource_type = resource_type,
            .out = out,
            .seen_collect_dirs = std.StringHashMap(void).init(gpa),
            .seen_walk_dirs = std.StringHashMap(void).init(gpa),
        };
    }

    fn deinit(self: *Resolver) void {
        freeStringMapKeys(self.gpa, &self.seen_collect_dirs);
        freeStringMapKeys(self.gpa, &self.seen_walk_dirs);
    }

    fn collectSourcePath(self: *Resolver, path: []const u8, depth: usize) anyerror!void {
        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return;
        if (stat.kind != .directory) return self.collectPath(path, depth);
        const previous_root = self.ignore_root;
        self.ignore_root = path;
        defer self.ignore_root = previous_root;
        return self.collectPath(path, depth);
    }

    fn collectPath(self: *Resolver, path: []const u8, depth: usize) anyerror!void {
        if (depth > max_depth) return;
        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return;
        switch (stat.kind) {
            .file => if (isResourceFile(self.resource_type, path)) try self.out.appendCopyUnique(path),
            .directory => try self.collectDirectory(path, depth),
            else => {},
        }
    }

    fn isIgnored(self: *Resolver, path: []const u8, is_directory: bool) !bool {
        const root = self.ignore_root orelse return false;
        return try isIgnoredByAncestorFiles(self.gpa, self.io, root, path, is_directory);
    }

    fn collectDirectory(self: *Resolver, dir_path: []const u8, depth: usize) anyerror!void {
        if (depth > max_depth) return;
        if (!try markDirectory(self.gpa, self.io, &self.seen_collect_dirs, dir_path)) return;
        switch (self.resource_type) {
            .extensions => try self.collectExtensions(dir_path, depth),
            .skills => try self.collectSkills(dir_path, dir_path, depth),
            .prompts, .themes => try self.collectFilesRecursive(dir_path, depth),
        }
    }

    /// Match original extension-directory discovery: a package manifest or
    /// index entry owns the directory; otherwise only top-level scripts and
    /// one-level child entry points are extension roots.
    fn collectExtensions(self: *Resolver, dir_path: []const u8, depth: usize) anyerror!void {
        if (try self.collectNativeExtensionManifest(dir_path)) return;
        if (try self.collectNestedPiExtensions(dir_path, depth)) return;
        if (try self.collectIndexExtension(dir_path)) return;

        var dir = std.Io.Dir.cwd().openDir(self.io, dir_path, .{ .iterate = true }) catch return;
        defer dir.close(self.io);
        var iterator = dir.iterate();
        while (try iterator.next(self.io)) |entry| {
            if (shouldSkipEntry(entry.name)) continue;
            const full = try std.fs.path.join(self.gpa, &.{ dir_path, entry.name });
            defer self.gpa.free(full);
            const kind = try followedKind(self.io, full, entry.kind);
            if (try self.isIgnored(full, kind == .directory)) continue;
            switch (kind) {
                .file => if (isScriptPath(full) or isNativeExtensionManifest(full)) try self.out.appendCopyUnique(full),
                .directory => {
                    if (depth + 1 > max_depth) continue;
                    if (!try markDirectory(self.gpa, self.io, &self.seen_collect_dirs, full)) continue;
                    if (try self.collectNativeExtensionManifest(full)) continue;
                    if (try self.collectNestedPiExtensions(full, depth + 1)) continue;
                    _ = try self.collectIndexExtension(full);
                },
                else => {},
            }
        }
    }

    fn collectNativeExtensionManifest(self: *Resolver, dir_path: []const u8) !bool {
        const path = try std.fs.path.join(self.gpa, &.{ dir_path, "extension.json" });
        defer self.gpa.free(path);
        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return false;
        if (stat.kind != .file) return false;
        try self.out.appendCopyUnique(path);
        return true;
    }

    fn collectIndexExtension(self: *Resolver, dir_path: []const u8) !bool {
        const candidates = [_][]const u8{ "index.ts", "index.js", "index.mts", "index.mjs", "index.cts", "index.cjs" };
        for (candidates) |name| {
            const path = try std.fs.path.join(self.gpa, &.{ dir_path, name });
            defer self.gpa.free(path);
            const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch continue;
            if (stat.kind == .file) {
                try self.out.appendCopyUnique(path);
                return true;
            }
        }
        return false;
    }

    fn collectNestedPiExtensions(self: *Resolver, dir_path: []const u8, depth: usize) anyerror!bool {
        const package_json = try std.fs.path.join(self.gpa, &.{ dir_path, "package.json" });
        defer self.gpa.free(package_json);
        const raw = std.Io.Dir.cwd().readFileAlloc(self.io, package_json, self.gpa, .limited(1024 * 1024)) catch return false;
        defer self.gpa.free(raw);
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, raw, .{}) catch return false;
        defer parsed.deinit();
        if (parsed.value != .object) return false;
        const pi_value = parsed.value.object.get("pi") orelse return false;
        if (pi_value != .object) return false;
        const extensions = pi_value.object.get("extensions") orelse return false;
        if (extensions != .array or extensions.array.items.len == 0) return false;
        for (extensions.array.items) |entry| if (entry != .string) return false;

        const before = self.out.items.items.len;
        try self.collectManifestEntries(dir_path, extensions.array.items, depth + 1);
        return self.out.items.items.len > before;
    }

    fn collectSkills(self: *Resolver, dir_path: []const u8, root_path: []const u8, depth: usize) !void {
        if (depth > max_depth) return;

        const direct = try std.fs.path.join(self.gpa, &.{ dir_path, "SKILL.md" });
        defer self.gpa.free(direct);
        if (std.Io.Dir.cwd().statFile(self.io, direct, .{})) |stat| {
            if (stat.kind == .file and !try self.isIgnored(direct, false)) {
                try self.out.appendCopyUnique(direct);
                return;
            }
        } else |_| {}

        var dir = std.Io.Dir.cwd().openDir(self.io, dir_path, .{ .iterate = true }) catch return;
        defer dir.close(self.io);
        var iterator = dir.iterate();
        while (try iterator.next(self.io)) |entry| {
            if (shouldSkipEntry(entry.name)) continue;
            const full = try std.fs.path.join(self.gpa, &.{ dir_path, entry.name });
            defer self.gpa.free(full);
            const kind = try followedKind(self.io, full, entry.kind);
            if (try self.isIgnored(full, kind == .directory)) continue;
            if (kind == .file and samePath(dir_path, root_path) and endsWithAsciiIgnoreCase(entry.name, ".md")) {
                try self.out.appendCopyUnique(full);
            }
        }

        var iterator_dirs = dir.iterate();
        while (try iterator_dirs.next(self.io)) |entry| {
            if (shouldSkipEntry(entry.name)) continue;
            const full = try std.fs.path.join(self.gpa, &.{ dir_path, entry.name });
            defer self.gpa.free(full);
            const kind = try followedKind(self.io, full, entry.kind);
            if (kind != .directory or try self.isIgnored(full, true)) continue;
            if (!try markDirectory(self.gpa, self.io, &self.seen_collect_dirs, full)) continue;
            try self.collectSkills(full, root_path, depth + 1);
        }
    }

    fn collectFilesRecursive(self: *Resolver, dir_path: []const u8, depth: usize) !void {
        if (depth > max_depth) return;
        var dir = std.Io.Dir.cwd().openDir(self.io, dir_path, .{ .iterate = true }) catch return;
        defer dir.close(self.io);
        var iterator = dir.iterate();
        while (try iterator.next(self.io)) |entry| {
            if (shouldSkipEntry(entry.name)) continue;
            const full = try std.fs.path.join(self.gpa, &.{ dir_path, entry.name });
            defer self.gpa.free(full);
            const kind = try followedKind(self.io, full, entry.kind);
            if (try self.isIgnored(full, kind == .directory)) continue;
            switch (kind) {
                .file => if (isResourceFile(self.resource_type, full)) try self.out.appendCopyUnique(full),
                .directory => {
                    if (!try markDirectory(self.gpa, self.io, &self.seen_collect_dirs, full)) continue;
                    try self.collectFilesRecursive(full, depth + 1);
                },
                else => {},
            }
        }
    }

    fn collectManifestEntries(self: *Resolver, root: []const u8, entries: []const std.json.Value, depth: usize) anyerror!void {
        for (entries) |entry_value| {
            if (entry_value != .string) continue;
            const entry = entry_value.string;
            if (entry.len == 0 or isOverridePattern(entry)) continue;
            if (hasGlobPattern(entry)) {
                try self.expandGlob(root, entry, depth);
            } else {
                const resolved = try resolvePackagePath(self.gpa, root, entry);
                defer self.gpa.free(resolved);
                try self.collectSourcePath(resolved, depth);
            }
        }
    }

    fn expandGlob(self: *Resolver, root: []const u8, pattern: []const u8, depth: usize) anyerror!void {
        try self.walkForGlob(root, root, pattern, depth);
    }

    fn walkForGlob(self: *Resolver, root: []const u8, dir_path: []const u8, pattern: []const u8, depth: usize) anyerror!void {
        if (depth > max_depth or self.visited_nodes >= max_nodes) return;
        if (!try markDirectory(self.gpa, self.io, &self.seen_walk_dirs, dir_path)) return;

        var dir = std.Io.Dir.cwd().openDir(self.io, dir_path, .{ .iterate = true }) catch return;
        defer dir.close(self.io);
        var iterator = dir.iterate();
        while (try iterator.next(self.io)) |entry| {
            if (self.visited_nodes >= max_nodes) return;
            self.visited_nodes += 1;
            if (entry.name.len > 0 and entry.name[0] == '.' and !patternAllowsDot(pattern)) continue;
            const full = try std.fs.path.join(self.gpa, &.{ dir_path, entry.name });
            defer self.gpa.free(full);
            const relative = std.fs.path.relative(self.gpa, ".", null, root, full) catch continue;
            defer self.gpa.free(relative);
            if (try globMatchAlloc(self.gpa, pattern, relative)) try self.collectSourcePath(full, depth + 1);

            const kind = try followedKind(self.io, full, entry.kind);
            if (kind == .directory) try self.walkForGlob(root, full, pattern, depth + 1);
        }
    }
};

const IgnoreDecision = struct {
    matched: bool,
    negated: bool,
};

fn isIgnoredByAncestorFiles(
    gpa: std.mem.Allocator,
    io: Io,
    root_raw: []const u8,
    path_raw: []const u8,
    is_directory: bool,
) !bool {
    const root = try normalizePath(gpa, root_raw);
    defer gpa.free(root);
    const path = try normalizePath(gpa, path_raw);
    defer gpa.free(path);
    const relative_raw = try std.fs.path.relative(gpa, ".", null, root, path);
    defer gpa.free(relative_raw);
    const relative = try normalizePath(gpa, relative_raw);
    defer gpa.free(relative);
    if (relative.len == 0 or std.mem.eql(u8, relative, ".") or std.mem.startsWith(u8, relative, "../")) return false;

    var ignored = false;
    // Rules in a parent directory apply before rules in nested directories.
    var scope_rel = try gpa.dupe(u8, "");
    defer gpa.free(scope_rel);
    var scope_dir = try gpa.dupe(u8, root);
    defer gpa.free(scope_dir);

    var component_iterator = std.mem.splitScalar(u8, relative, '/');
    var components: std.ArrayList([]const u8) = .empty;
    defer components.deinit(gpa);
    while (component_iterator.next()) |component| if (component.len > 0) try components.append(gpa, component);

    const ancestor_count = if (components.items.len == 0) 0 else components.items.len - 1;
    var depth: usize = 0;
    while (true) {
        const ignore_names = [_][]const u8{ ".gitignore", ".ignore", ".fdignore" };
        for (ignore_names) |ignore_name| {
            const ignore_path = try std.fs.path.join(gpa, &.{ scope_dir, ignore_name });
            defer gpa.free(ignore_path);
            const raw = std.Io.Dir.cwd().readFileAlloc(io, ignore_path, gpa, .limited(1024 * 1024)) catch continue;
            defer gpa.free(raw);
            var lines = std.mem.splitScalar(u8, raw, '\n');
            while (lines.next()) |line_raw| {
                const decision = try matchIgnoreRule(gpa, line_raw, scope_rel, relative, is_directory);
                if (decision.matched) ignored = !decision.negated;
            }
        }
        if (depth >= ancestor_count) break;

        const next_scope_rel = if (scope_rel.len == 0)
            try gpa.dupe(u8, components.items[depth])
        else
            try std.fs.path.join(gpa, &.{ scope_rel, components.items[depth] });
        gpa.free(scope_rel);
        scope_rel = next_scope_rel;

        const next_scope_dir = try std.fs.path.join(gpa, &.{ scope_dir, components.items[depth] });
        gpa.free(scope_dir);
        scope_dir = next_scope_dir;
        depth += 1;
    }
    return ignored;
}

fn matchIgnoreRule(
    gpa: std.mem.Allocator,
    line_raw: []const u8,
    scope_rel_raw: []const u8,
    target_rel_raw: []const u8,
    target_is_directory: bool,
) !IgnoreDecision {
    var line = std.mem.trim(u8, line_raw, " \t\r");
    if (line.len == 0) return .{ .matched = false, .negated = false };
    if (line[0] == '#' and !std.mem.startsWith(u8, line, "\\#")) return .{ .matched = false, .negated = false };

    var negated = false;
    if (line[0] == '!' and !std.mem.startsWith(u8, line, "\\!")) {
        negated = true;
        line = line[1..];
    } else if (std.mem.startsWith(u8, line, "\\!") or std.mem.startsWith(u8, line, "\\#")) {
        line = line[1..];
    }
    if (line.len == 0) return .{ .matched = false, .negated = negated };

    const anchored = line[0] == '/';
    if (anchored) line = line[1..];
    const directory_only = line.len > 0 and line[line.len - 1] == '/';
    if (directory_only) line = line[0 .. line.len - 1];
    if (line.len == 0) return .{ .matched = false, .negated = negated };

    const scope_rel = try normalizePath(gpa, scope_rel_raw);
    defer gpa.free(scope_rel);
    const target_rel = try normalizePath(gpa, target_rel_raw);
    defer gpa.free(target_rel);

    const local = if (scope_rel.len == 0)
        target_rel
    else blk: {
        if (!std.mem.startsWith(u8, target_rel, scope_rel)) return .{ .matched = false, .negated = negated };
        if (target_rel.len == scope_rel.len) break :blk target_rel[target_rel.len..];
        if (target_rel[scope_rel.len] != '/') return .{ .matched = false, .negated = negated };
        break :blk target_rel[scope_rel.len + 1 ..];
    };
    if (local.len == 0) return .{ .matched = false, .negated = negated };

    const has_slash = std.mem.indexOfScalar(u8, line, '/') != null;
    var component_end: usize = 0;
    while (component_end <= local.len) {
        const slash = std.mem.indexOfScalarPos(u8, local, component_end, '/') orelse local.len;
        const candidate = local[0..slash];
        const candidate_is_directory = slash < local.len or target_is_directory;
        if (!directory_only or candidate_is_directory) {
            const matched = if (anchored or has_slash)
                try globMatchAlloc(gpa, line, candidate)
            else
                try globMatchAlloc(gpa, line, std.fs.path.basename(candidate));
            if (matched) return .{ .matched = true, .negated = negated };
        }
        if (slash == local.len) break;
        component_end = slash + 1;
    }
    return .{ .matched = false, .negated = negated };
}

/// Resolve the package manifest field to exact, enabled resource files.
/// Resolve one explicit resource source. Files are validated by resource type;
/// directories use the same smart discovery rules as package-manifest entries.
pub fn resolveSourcePath(
    gpa: std.mem.Allocator,
    io: Io,
    path: []const u8,
    resource_type: ResourceType,
) !PathList {
    var out = PathList.init(gpa);
    errdefer out.deinit();
    var resolver = Resolver.init(gpa, io, resource_type, &out);
    defer resolver.deinit();
    try resolver.collectSourcePath(path, 0);
    sortPaths(out.items.items);
    return out;
}

pub fn resolveManifestEntries(
    gpa: std.mem.Allocator,
    io: Io,
    root: []const u8,
    entries: []const std.json.Value,
    resource_type: ResourceType,
) !PathList {
    var result = PathList.init(gpa);
    errdefer result.deinit();
    var resolver = Resolver.init(gpa, io, resource_type, &result);
    defer resolver.deinit();

    try resolver.collectManifestEntries(root, entries, 0);
    try applyOverridePatterns(gpa, root, &result, entries, resource_type);
    sortPaths(result.items.items);
    return result;
}

/// Resolve conventional package directories when no Pi manifest is present.
pub fn resolveConventional(
    gpa: std.mem.Allocator,
    io: Io,
    package_root: []const u8,
    resource_type: ResourceType,
) !PathList {
    var result = PathList.init(gpa);
    errdefer result.deinit();
    var resolver = Resolver.init(gpa, io, resource_type, &result);
    defer resolver.deinit();
    const name = @tagName(resource_type);
    const dir_path = try std.fs.path.join(gpa, &.{ package_root, name });
    defer gpa.free(dir_path);
    try resolver.collectSourcePath(dir_path, 0);
    sortPaths(result.items.items);
    return result;
}

/// Apply a package-level filter on top of already manifest-approved resources.
/// Null means no filter, an empty array disables the entire resource class.
pub fn applyUserFilter(
    gpa: std.mem.Allocator,
    root: []const u8,
    resources: *PathList,
    patterns: ?[]const []const u8,
    resource_type: ResourceType,
) !void {
    const configured = patterns orelse return;
    if (configured.len == 0) {
        while (resources.items.items.len > 0) resources.removeAt(resources.items.items.len - 1);
        return;
    }

    var has_plain_include = false;
    for (configured) |pattern| if (pattern.len > 0 and !isOverridePattern(pattern)) {
        has_plain_include = true;
        break;
    };

    var enabled = try gpa.alloc(bool, resources.items.items.len);
    defer gpa.free(enabled);
    @memset(enabled, !has_plain_include);

    if (has_plain_include) {
        for (resources.items.items, 0..) |path, index| {
            for (configured) |pattern| {
                if (pattern.len == 0 or isOverridePattern(pattern)) continue;
                if (try matchesPattern(gpa, path, pattern, root, resource_type)) {
                    enabled[index] = true;
                    break;
                }
            }
        }
    }

    for (configured) |pattern| {
        if (pattern.len < 2 or pattern[0] != '!') continue;
        for (resources.items.items, 0..) |path, index| {
            if (try matchesPattern(gpa, path, pattern[1..], root, resource_type)) enabled[index] = false;
        }
    }
    for (configured) |pattern| {
        if (pattern.len < 2 or pattern[0] != '+') continue;
        for (resources.items.items, 0..) |path, index| {
            if (try matchesExact(gpa, path, pattern[1..], root, resource_type)) enabled[index] = true;
        }
    }
    for (configured) |pattern| {
        if (pattern.len < 2 or pattern[0] != '-') continue;
        for (resources.items.items, 0..) |path, index| {
            if (try matchesExact(gpa, path, pattern[1..], root, resource_type)) enabled[index] = false;
        }
    }

    var index: usize = resources.items.items.len;
    while (index > 0) {
        index -= 1;
        if (!enabled[index]) resources.removeAt(index);
    }
}

/// Return the final decision made by an `autoload=false` package filter for
/// one manifest-approved resource. `null` means no selector matched and the
/// package delta must not claim the path, allowing a lower-precedence package
/// or scope to decide it. Later selectors override earlier selectors.
pub fn autoloadDisabledDecision(
    gpa: std.mem.Allocator,
    root: []const u8,
    path: []const u8,
    patterns: ?[]const []const u8,
    resource_type: ResourceType,
) !?bool {
    const configured = patterns orelse return null;
    var decision: ?bool = null;
    for (configured) |raw_pattern| {
        if (raw_pattern.len == 0) continue;
        const prefix = raw_pattern[0];
        const has_prefix = prefix == '!' or prefix == '+' or prefix == '-';
        const pattern = if (has_prefix) raw_pattern[1..] else raw_pattern;
        if (pattern.len == 0) continue;
        const exact = prefix == '+' or prefix == '-';
        const matches = if (exact)
            try matchesExact(gpa, path, pattern, root, resource_type)
        else
            try matchesPattern(gpa, path, pattern, root, resource_type);
        if (matches) decision = prefix != '!' and prefix != '-';
    }
    return decision;
}

/// Apply package patterns when `autoload` is disabled. All resources begin
/// disabled; each configured selector then sets the matching resources in
/// declaration order. Plain and `+` patterns enable, while `!` and `-`
/// patterns disable. `+` and `-` use exact resource matching.
pub fn applyAutoloadDisabledFilter(
    gpa: std.mem.Allocator,
    root: []const u8,
    resources: *PathList,
    patterns: ?[]const []const u8,
    resource_type: ResourceType,
) !void {
    var index: usize = resources.items.items.len;
    while (index > 0) {
        index -= 1;
        const decision = try autoloadDisabledDecision(
            gpa,
            root,
            resources.items.items[index],
            patterns,
            resource_type,
        );
        if (decision != true) resources.removeAt(index);
    }
}

fn applyOverridePatterns(
    gpa: std.mem.Allocator,
    root: []const u8,
    resources: *PathList,
    entries: []const std.json.Value,
    resource_type: ResourceType,
) !void {
    if (resources.items.items.len == 0) return;
    var enabled = try gpa.alloc(bool, resources.items.items.len);
    defer gpa.free(enabled);
    @memset(enabled, true);

    for (entries) |entry_value| {
        if (entry_value != .string) continue;
        const pattern = entry_value.string;
        if (pattern.len < 2 or pattern[0] != '!') continue;
        for (resources.items.items, 0..) |path, index| {
            if (try matchesPattern(gpa, path, pattern[1..], root, resource_type)) enabled[index] = false;
        }
    }
    for (entries) |entry_value| {
        if (entry_value != .string) continue;
        const pattern = entry_value.string;
        if (pattern.len < 2 or pattern[0] != '+') continue;
        for (resources.items.items, 0..) |path, index| {
            if (try matchesExact(gpa, path, pattern[1..], root, resource_type)) enabled[index] = true;
        }
    }
    for (entries) |entry_value| {
        if (entry_value != .string) continue;
        const pattern = entry_value.string;
        if (pattern.len < 2 or pattern[0] != '-') continue;
        for (resources.items.items, 0..) |path, index| {
            if (try matchesExact(gpa, path, pattern[1..], root, resource_type)) enabled[index] = false;
        }
    }

    var index: usize = resources.items.items.len;
    while (index > 0) {
        index -= 1;
        if (!enabled[index]) resources.removeAt(index);
    }
}

fn matchesPattern(
    gpa: std.mem.Allocator,
    file_path: []const u8,
    pattern: []const u8,
    base_dir: []const u8,
    resource_type: ResourceType,
) !bool {
    const relative = try std.fs.path.relative(gpa, ".", null, base_dir, file_path);
    defer gpa.free(relative);
    if (try globMatchAlloc(gpa, pattern, relative)) return true;
    if (try globMatchAlloc(gpa, pattern, std.fs.path.basename(file_path))) return true;
    if (try globMatchAlloc(gpa, pattern, file_path)) return true;

    if (resource_type == .skills and std.mem.eql(u8, std.fs.path.basename(file_path), "SKILL.md")) {
        const parent = std.fs.path.dirname(file_path) orelse return false;
        const parent_relative = try std.fs.path.relative(gpa, ".", null, base_dir, parent);
        defer gpa.free(parent_relative);
        if (try globMatchAlloc(gpa, pattern, parent_relative)) return true;
        if (try globMatchAlloc(gpa, pattern, std.fs.path.basename(parent))) return true;
        if (try globMatchAlloc(gpa, pattern, parent)) return true;
    }
    return false;
}

fn matchesExact(
    gpa: std.mem.Allocator,
    file_path: []const u8,
    pattern: []const u8,
    base_dir: []const u8,
    resource_type: ResourceType,
) !bool {
    const normalized_pattern = try normalizePath(gpa, stripLeadingDotSlash(pattern));
    defer gpa.free(normalized_pattern);
    const relative_raw = try std.fs.path.relative(gpa, ".", null, base_dir, file_path);
    defer gpa.free(relative_raw);
    const relative = try normalizePath(gpa, relative_raw);
    defer gpa.free(relative);
    const absolute = try normalizePath(gpa, file_path);
    defer gpa.free(absolute);
    if (std.mem.eql(u8, normalized_pattern, relative) or std.mem.eql(u8, normalized_pattern, absolute)) return true;

    if (resource_type == .skills and std.mem.eql(u8, std.fs.path.basename(file_path), "SKILL.md")) {
        const parent = std.fs.path.dirname(file_path) orelse return false;
        const parent_relative_raw = try std.fs.path.relative(gpa, ".", null, base_dir, parent);
        defer gpa.free(parent_relative_raw);
        const parent_relative = try normalizePath(gpa, parent_relative_raw);
        defer gpa.free(parent_relative);
        const parent_absolute = try normalizePath(gpa, parent);
        defer gpa.free(parent_absolute);
        return std.mem.eql(u8, normalized_pattern, parent_relative) or std.mem.eql(u8, normalized_pattern, parent_absolute);
    }
    return false;
}

fn globMatchAlloc(gpa: std.mem.Allocator, pattern_raw: []const u8, path_raw: []const u8) !bool {
    const pattern = try normalizePath(gpa, stripLeadingDotSlash(pattern_raw));
    defer gpa.free(pattern);
    const path = try normalizePath(gpa, path_raw);
    defer gpa.free(path);
    if (pattern.len == 0) return path.len == 0;

    const width = path.len + 1;
    const memo = try gpa.alloc(u8, (pattern.len + 1) * width);
    defer gpa.free(memo);
    @memset(memo, 0);
    return globMatchMemo(pattern, path, 0, 0, width, memo);
}

fn globMatchMemo(pattern: []const u8, path: []const u8, pi: usize, si: usize, width: usize, memo: []u8) bool {
    const memo_index = pi * width + si;
    if (memo[memo_index] != 0) return memo[memo_index] == 2;
    const matched = blk: {
        if (pi == pattern.len) break :blk si == path.len;
        const pc = pattern[pi];
        if (pc == '*') {
            var after = pi + 1;
            while (after < pattern.len and pattern[after] == '*') after += 1;
            const globstar = after - pi >= 2;
            if (globstar) {
                if (after < pattern.len and pattern[after] == '/') {
                    if (globMatchMemo(pattern, path, after + 1, si, width, memo)) break :blk true;
                    if (si < path.len and globMatchMemo(pattern, path, pi, si + 1, width, memo)) break :blk true;
                    break :blk false;
                }
                if (globMatchMemo(pattern, path, after, si, width, memo)) break :blk true;
                if (si < path.len and globMatchMemo(pattern, path, pi, si + 1, width, memo)) break :blk true;
                break :blk false;
            }
            if (globMatchMemo(pattern, path, after, si, width, memo)) break :blk true;
            if (si < path.len and path[si] != '/' and globMatchMemo(pattern, path, pi, si + 1, width, memo)) break :blk true;
            break :blk false;
        }
        if (pc == '?') {
            break :blk si < path.len and path[si] != '/' and globMatchMemo(pattern, path, pi + 1, si + 1, width, memo);
        }
        if (pc == '[') {
            if (si >= path.len or path[si] == '/') break :blk false;
            const class = parseCharacterClass(pattern, pi, path[si]) orelse break :blk pc == path[si] and globMatchMemo(pattern, path, pi + 1, si + 1, width, memo);
            break :blk class.matched and globMatchMemo(pattern, path, class.next_index, si + 1, width, memo);
        }
        if (pc == '\\' and pi + 1 < pattern.len) {
            break :blk si < path.len and pattern[pi + 1] == path[si] and globMatchMemo(pattern, path, pi + 2, si + 1, width, memo);
        }
        break :blk si < path.len and pc == path[si] and globMatchMemo(pattern, path, pi + 1, si + 1, width, memo);
    };
    memo[memo_index] = if (matched) 2 else 1;
    return matched;
}

const CharacterClassResult = struct { matched: bool, next_index: usize };

fn parseCharacterClass(pattern: []const u8, start: usize, candidate: u8) ?CharacterClassResult {
    var index = start + 1;
    if (index >= pattern.len) return null;
    var negated = false;
    if (pattern[index] == '!' or pattern[index] == '^') {
        negated = true;
        index += 1;
    }
    var any = false;
    var matched = false;
    while (index < pattern.len and pattern[index] != ']') {
        any = true;
        const first = pattern[index];
        if (index + 2 < pattern.len and pattern[index + 1] == '-' and pattern[index + 2] != ']') {
            const last = pattern[index + 2];
            if (candidate >= first and candidate <= last) matched = true;
            index += 3;
        } else {
            if (candidate == first) matched = true;
            index += 1;
        }
    }
    if (!any or index >= pattern.len or pattern[index] != ']') return null;
    return .{ .matched = if (negated) !matched else matched, .next_index = index + 1 };
}

fn followedKind(io: Io, path: []const u8, entry_kind: std.Io.File.Kind) !std.Io.File.Kind {
    if (entry_kind != .sym_link) return entry_kind;
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return entry_kind;
    return stat.kind;
}

fn markDirectory(gpa: std.mem.Allocator, io: Io, map: *std.StringHashMap(void), path: []const u8) !bool {
    // realPathFileAbsoluteAlloc returns a sentinel-terminated allocation. Store an
    // exact-length duplicate in the string map so the later allocator free uses
    // the same size that was originally allocated.
    const canonical_z = std.Io.Dir.realPathFileAbsoluteAlloc(io, path, gpa) catch null;
    const canonical = if (canonical_z) |resolved| blk: {
        defer gpa.free(resolved);
        break :blk try gpa.dupe(u8, resolved);
    } else try gpa.dupe(u8, path);
    errdefer gpa.free(canonical);
    if (map.contains(canonical)) {
        gpa.free(canonical);
        return false;
    }
    try map.put(canonical, {});
    return true;
}

fn freeStringMapKeys(gpa: std.mem.Allocator, map: *std.StringHashMap(void)) void {
    var iterator = map.keyIterator();
    while (iterator.next()) |key| gpa.free(key.*);
    map.deinit();
}

fn resolvePackagePath(gpa: std.mem.Allocator, root: []const u8, entry: []const u8) ![]u8 {
    // Manifest tildes are package-relative literals, not home-directory syntax.
    if (std.fs.path.isAbsolute(entry)) return try std.fs.path.resolve(gpa, &.{entry});
    return try std.fs.path.resolve(gpa, &.{ root, entry });
}

fn isResourceFile(resource_type: ResourceType, path: []const u8) bool {
    return switch (resource_type) {
        .extensions => isScriptPath(path) or isNativeExtensionManifest(path),
        .skills => std.mem.eql(u8, std.fs.path.basename(path), "SKILL.md") or endsWithAsciiIgnoreCase(path, ".md"),
        .prompts => endsWithAsciiIgnoreCase(path, ".md"),
        .themes => endsWithAsciiIgnoreCase(path, ".json"),
    };
}

fn isScriptPath(path: []const u8) bool {
    inline for (.{ ".ts", ".js", ".mts", ".cts", ".mjs", ".cjs" }) |suffix| {
        if (endsWithAsciiIgnoreCase(path, suffix)) return true;
    }
    return false;
}

fn isNativeExtensionManifest(path: []const u8) bool {
    return std.mem.eql(u8, std.fs.path.basename(path), "extension.json");
}

fn shouldSkipEntry(name: []const u8) bool {
    return name.len == 0 or name[0] == '.' or std.mem.eql(u8, name, "node_modules");
}

fn patternAllowsDot(pattern: []const u8) bool {
    var segment_start = true;
    for (pattern) |c| {
        if (segment_start and c == '.') return true;
        segment_start = c == '/' or c == '\\';
    }
    return false;
}

fn isOverridePattern(entry: []const u8) bool {
    return entry.len > 0 and (entry[0] == '!' or entry[0] == '+' or entry[0] == '-');
}

fn hasGlobPattern(entry: []const u8) bool {
    return std.mem.indexOfAny(u8, entry, "*?[") != null;
}

fn stripLeadingDotSlash(input: []const u8) []const u8 {
    if (std.mem.startsWith(u8, input, "./") or std.mem.startsWith(u8, input, ".\\")) return input[2..];
    return input;
}

fn normalizePath(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    const result = try gpa.alloc(u8, input.len);
    for (input, 0..) |c, index| result[index] = if (c == '\\') '/' else c;
    return result;
}

fn samePath(a: []const u8, b: []const u8) bool {
    if (@import("builtin").os.tag == .windows) return std.ascii.eqlIgnoreCase(a, b);
    return std.mem.eql(u8, a, b);
}

fn endsWithAsciiIgnoreCase(input: []const u8, suffix: []const u8) bool {
    if (suffix.len > input.len) return false;
    return std.ascii.eqlIgnoreCase(input[input.len - suffix.len ..], suffix);
}

fn sortPaths(paths: [][]u8) void {
    std.mem.sort([]u8, paths, {}, struct {
        fn lessThan(_: void, left: []u8, right: []u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.lessThan);
}

test "glob matcher supports minimatch-style globstar question and classes" {
    const gpa = std.testing.allocator;
    try std.testing.expect(try globMatchAlloc(gpa, "**/skip.ts", "skip.ts"));
    try std.testing.expect(try globMatchAlloc(gpa, "**/skip.ts", "extensions/nested/skip.ts"));
    try std.testing.expect(try globMatchAlloc(gpa, "plugins/*/skills", "plugins/pdf/skills"));
    try std.testing.expect(!(try globMatchAlloc(gpa, "plugins/*/skills", "plugins/a/b/skills")));
    try std.testing.expect(try globMatchAlloc(gpa, "themes/??rk.[jt]son", "themes/dark.json"));
    try std.testing.expect(!(try globMatchAlloc(gpa, "themes/??rk.[jt]son", "themes/light.json")));
}

test "manifest directories exclusions and force selectors resolve exact files" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    inline for (.{ "one.ts", "two.ts", "three.ts" }) |name| {
        const path = try std.fs.path.join(gpa, &.{ root, "extensions", name });
        defer gpa.free(path);
        if (std.fs.path.dirname(path)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "export default function() {}" });
    }
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa,
        \\["extensions","!**/two.ts","+extensions/two.ts","-extensions/three.ts"]
    , .{});
    defer parsed.deinit();
    var paths = try resolveManifestEntries(gpa, io, root, parsed.value.array.items, .extensions);
    defer paths.deinit();
    try std.testing.expectEqual(@as(usize, 2), paths.items.items.len);
    try std.testing.expect(std.mem.endsWith(u8, paths.items.items[0], "one.ts"));
    try std.testing.expect(std.mem.endsWith(u8, paths.items.items[1], "two.ts"));
}

test "manifest positive glob expands directories before recursive skill discovery" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    inline for (.{ "pdf-to-markdown", "document-processor" }) |name| {
        const path = try std.fs.path.join(gpa, &.{ root, "plugins", name, "skills", name, "SKILL.md" });
        defer gpa.free(path);
        if (std.fs.path.dirname(path)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "---\nname: demo\ndescription: demo\n---\n" });
    }
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, "[\"./plugins/*/skills\"]", .{});
    defer parsed.deinit();
    var paths = try resolveManifestEntries(gpa, io, root, parsed.value.array.items, .skills);
    defer paths.deinit();
    try std.testing.expectEqual(@as(usize, 2), paths.items.items.len);
}

test "extension directory discovery loads entry points but not helper modules" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    const direct = try std.fs.path.join(gpa, &.{ root, "extensions", "direct.ts" });
    defer gpa.free(direct);
    const index = try std.fs.path.join(gpa, &.{ root, "extensions", "nested", "index.ts" });
    defer gpa.free(index);
    const helper = try std.fs.path.join(gpa, &.{ root, "extensions", "nested", "helper.ts" });
    defer gpa.free(helper);
    for ([_][]const u8{ direct, index, helper }) |path| {
        if (std.fs.path.dirname(path)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "export default function() {}" });
    }
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, "[\"extensions\"]", .{});
    defer parsed.deinit();
    var paths = try resolveManifestEntries(gpa, io, root, parsed.value.array.items, .extensions);
    defer paths.deinit();
    try std.testing.expectEqual(@as(usize, 2), paths.items.items.len);
    for (paths.items.items) |path| try std.testing.expect(!std.mem.endsWith(u8, path, "helper.ts"));
}

test "autoload disabled selectors only enable explicitly matched resources" {
    const gpa = std.testing.allocator;
    var resources = PathList.init(gpa);
    defer resources.deinit();
    try resources.appendCopyUnique("/pkg/extensions/a.ts");
    try resources.appendCopyUnique("/pkg/extensions/b.ts");
    try resources.appendCopyUnique("/pkg/extensions/c.ts");

    const patterns = [_][]const u8{ "extensions/*.ts", "!extensions/b.ts", "+extensions/b.ts", "-extensions/c.ts" };
    try applyAutoloadDisabledFilter(gpa, "/pkg", &resources, &patterns, .extensions);
    try std.testing.expectEqual(@as(usize, 2), resources.items.items.len);
    try std.testing.expectEqualStrings("/pkg/extensions/a.ts", resources.items.items[0]);
    try std.testing.expectEqualStrings("/pkg/extensions/b.ts", resources.items.items[1]);
}

test "conventional discovery honors nested ignore files and negation" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const package_root = root_buf[0..root_len];

    const prompts = try std.fs.path.join(gpa, &.{ package_root, "prompts" });
    defer gpa.free(prompts);
    const nested = try std.fs.path.join(gpa, &.{ prompts, "nested" });
    defer gpa.free(nested);
    const private = try std.fs.path.join(gpa, &.{ prompts, "private" });
    defer gpa.free(private);
    try std.Io.Dir.cwd().createDirPath(io, nested);
    try std.Io.Dir.cwd().createDirPath(io, private);

    const root_ignore = try std.fs.path.join(gpa, &.{ prompts, ".gitignore" });
    defer gpa.free(root_ignore);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = root_ignore, .data = "ignored.md\nprivate/\n" });
    const nested_ignore = try std.fs.path.join(gpa, &.{ nested, ".ignore" });
    defer gpa.free(nested_ignore);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = nested_ignore, .data = "*.md\n!keep.md\n" });

    inline for (.{ "visible.md", "ignored.md" }) |name| {
        const path = try std.fs.path.join(gpa, &.{ prompts, name });
        defer gpa.free(path);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = name });
    }
    inline for (.{ "keep.md", "drop.md" }) |name| {
        const path = try std.fs.path.join(gpa, &.{ nested, name });
        defer gpa.free(path);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = name });
    }
    const private_file = try std.fs.path.join(gpa, &.{ private, "secret.md" });
    defer gpa.free(private_file);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = private_file, .data = "secret" });

    var resolved = try resolveConventional(gpa, io, package_root, .prompts);
    defer resolved.deinit();
    try std.testing.expectEqual(@as(usize, 2), resolved.items.items.len);
    const first_normalized = try normalizePath(gpa, resolved.items.items[0]);
    defer gpa.free(first_normalized);
    const second_normalized = try normalizePath(gpa, resolved.items.items[1]);
    defer gpa.free(second_normalized);
    try std.testing.expect(std.mem.endsWith(u8, first_normalized, "nested/keep.md") or std.mem.endsWith(u8, second_normalized, "nested/keep.md"));
    try std.testing.expect(std.mem.endsWith(u8, resolved.items.items[0], "visible.md") or std.mem.endsWith(u8, resolved.items.items[1], "visible.md"));
}

test "exact manifest files bypass directory ignore rules" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];

    const prompts = try std.fs.path.join(gpa, &.{ root, "prompts" });
    defer gpa.free(prompts);
    try std.Io.Dir.cwd().createDirPath(io, prompts);
    const ignored = try std.fs.path.join(gpa, &.{ prompts, "explicit.md" });
    defer gpa.free(ignored);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = ignored, .data = "explicit" });
    const ignore_path = try std.fs.path.join(gpa, &.{ prompts, ".gitignore" });
    defer gpa.free(ignore_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = ignore_path, .data = "explicit.md\n" });

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, "[\"prompts/explicit.md\"]", .{});
    defer parsed.deinit();
    var resolved = try resolveManifestEntries(gpa, io, root, parsed.value.array.items, .prompts);
    defer resolved.deinit();
    try std.testing.expectEqual(@as(usize, 1), resolved.items.items.len);
    try std.testing.expectEqualStrings(ignored, resolved.items.items[0]);
}
