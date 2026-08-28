//! Top-level Pi resource discovery, filtering, configuration, and runtime resolution.
//!
//! Pi resources do not only come from installed packages. Global and trusted
//! project settings can name extension, skill, prompt, and theme paths directly,
//! while conventional `extensions/`, `skills/`, `prompts/`, and `themes/`
//! directories are discovered automatically. This module keeps those origins
//! visible even when disabled and applies exact settings-backed mutations under
//! the same advisory lock used by package configuration.
const std = @import("std");
const Io = std.Io;
const packages = @import("packages.zig");
const package_resources = @import("package_resources.zig");

pub const ResourceType = package_resources.ResourceType;

pub const SourceKind = enum {
    auto,
    local,
};

pub const OverrideState = enum {
    inherit,
    load,
    unload,
};

pub const Item = struct {
    gpa: std.mem.Allocator,
    selector: []const u8,
    scope: packages.Scope,
    source: SourceKind,
    base_dir: []const u8,
    resource_type: ResourceType,
    path: []const u8,
    relative_path: []const u8,
    display_name: []const u8,
    enabled: bool,
    inherited_enabled: bool,
    inherited_from_user: bool,
    override_state: OverrideState,

    pub fn deinit(self: *Item) void {
        self.gpa.free(self.selector);
        self.gpa.free(self.base_dir);
        self.gpa.free(self.path);
        self.gpa.free(self.relative_path);
        self.gpa.free(self.display_name);
        self.* = undefined;
    }
};

pub const Inventory = struct {
    gpa: std.mem.Allocator,
    write_scope: packages.Scope,
    items: []Item,

    pub fn deinit(self: *Inventory) void {
        for (self.items) |*item| item.deinit();
        self.gpa.free(self.items);
        self.* = undefined;
    }
};

pub const Resources = struct {
    gpa: std.mem.Allocator,
    extensions: std.ArrayList([]const u8) = .empty,
    skills: std.ArrayList([]const u8) = .empty,
    prompts: std.ArrayList([]const u8) = .empty,
    themes: std.ArrayList([]const u8) = .empty,

    pub fn init(gpa: std.mem.Allocator) Resources {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Resources) void {
        freePaths(self.gpa, &self.extensions);
        freePaths(self.gpa, &self.skills);
        freePaths(self.gpa, &self.prompts);
        freePaths(self.gpa, &self.themes);
        self.* = undefined;
    }
};

const ScopeConfig = struct {
    gpa: std.mem.Allocator,
    extensions: []const []const u8 = &.{},
    skills: []const []const u8 = &.{},
    prompts: []const []const u8 = &.{},
    themes: []const []const u8 = &.{},

    fn deinit(self: *ScopeConfig) void {
        freeStrings(self.gpa, self.extensions);
        freeStrings(self.gpa, self.skills);
        freeStrings(self.gpa, self.prompts);
        freeStrings(self.gpa, self.themes);
        self.* = undefined;
    }

    fn entries(self: ScopeConfig, resource_type: ResourceType) []const []const u8 {
        return switch (resource_type) {
            .extensions => self.extensions,
            .skills => self.skills,
            .prompts => self.prompts,
            .themes => self.themes,
        };
    }
};

const Candidate = struct {
    gpa: std.mem.Allocator,
    scope: packages.Scope,
    source: SourceKind,
    base_dir: []const u8,
    resource_type: ResourceType,
    path: []const u8,
    enabled: bool,

    fn deinit(self: *Candidate) void {
        self.gpa.free(self.base_dir);
        self.gpa.free(self.path);
        self.* = undefined;
    }
};

fn freeStrings(gpa: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| gpa.free(value);
    if (values.len > 0) gpa.free(values);
}

fn freePaths(gpa: std.mem.Allocator, values: *std.ArrayList([]const u8)) void {
    for (values.items) |value| gpa.free(value);
    values.deinit(gpa);
}

fn normalizeSeparators(bytes: []u8) void {
    for (bytes) |*byte| if (byte.* == '\\') {
        byte.* = '/';
    };
}

fn samePath(left: []const u8, right: []const u8) bool {
    if (std.mem.eql(u8, left, right)) return true;
    if (left.len != right.len) return false;
    for (left, right) |a_raw, b_raw| {
        const a = if (a_raw == '\\') '/' else a_raw;
        const b = if (b_raw == '\\') '/' else b_raw;
        if (a != b) return false;
    }
    return true;
}

fn containsPath(items: []const []const u8, candidate: []const u8) bool {
    for (items) |item| if (samePath(item, candidate)) return true;
    return false;
}

fn appendPathUnique(gpa: std.mem.Allocator, out: *std.ArrayList([]const u8), path: []const u8) !void {
    if (containsPath(out.items, path)) return;
    try out.append(gpa, try gpa.dupe(u8, path));
}

fn appendOwnedCandidateUnique(gpa: std.mem.Allocator, out: *std.ArrayList(Candidate), candidate: Candidate) !void {
    for (out.items) |existing| if (samePath(existing.path, candidate.path) and existing.resource_type == candidate.resource_type) {
        var owned = candidate;
        owned.deinit();
        return;
    };
    try out.append(gpa, candidate);
}

fn resourceField(resource_type: ResourceType) []const u8 {
    return @tagName(resource_type);
}

fn isOverride(entry: []const u8) bool {
    return entry.len > 0 and (entry[0] == '!' or entry[0] == '+' or entry[0] == '-');
}

fn hasGlob(entry: []const u8) bool {
    return std.mem.indexOfAny(u8, entry, "*?[") != null;
}

fn cloneStringArray(gpa: std.mem.Allocator, value: std.json.Value) ![]const []const u8 {
    if (value != .array) return error.InvalidResourceSettings;
    if (value.array.items.len == 0) return &.{};
    var out = try gpa.alloc([]const u8, value.array.items.len);
    var initialized: usize = 0;
    errdefer {
        for (out[0..initialized]) |item| gpa.free(item);
        gpa.free(out);
    }
    for (value.array.items) |entry| {
        if (entry != .string) return error.InvalidResourceSettings;
        out[initialized] = try gpa.dupe(u8, entry.string);
        initialized += 1;
    }
    return out;
}

fn loadScopeConfig(gpa: std.mem.Allocator, io: Io, base_dir: []const u8) !ScopeConfig {
    var result: ScopeConfig = .{ .gpa = gpa };
    errdefer result.deinit();
    const path = try std.fs.path.join(gpa, &.{ base_dir, "settings.json" });
    defer gpa.free(path);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(8 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return result,
        else => return err,
    };
    defer gpa.free(raw);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidResourceSettings;
    inline for (.{ ResourceType.extensions, ResourceType.skills, ResourceType.prompts, ResourceType.themes }) |resource_type| {
        if (parsed.value.object.get(resourceField(resource_type))) |value| {
            const cloned = try cloneStringArray(gpa, value);
            switch (resource_type) {
                .extensions => result.extensions = cloned,
                .skills => result.skills = cloned,
                .prompts => result.prompts = cloned,
                .themes => result.themes = cloned,
            }
        }
    }
    return result;
}

fn scopeBase(gpa: std.mem.Allocator, agent_dir: []const u8, cwd: []const u8, scope: packages.Scope) ![]u8 {
    return switch (scope) {
        .user => gpa.dupe(u8, agent_dir),
        .project => std.fs.path.resolve(gpa, &.{ cwd, ".pi" }),
        .temporary => error.TemporaryPackageNotPersistent,
    };
}

fn inferredHome(agent_dir: []const u8) ?[]const u8 {
    if (!std.mem.eql(u8, std.fs.path.basename(agent_dir), "agent")) return null;
    const pi_dir = std.fs.path.dirname(agent_dir) orelse return null;
    if (!std.mem.eql(u8, std.fs.path.basename(pi_dir), ".pi")) return null;
    return std.fs.path.dirname(pi_dir);
}

fn resolveConfiguredPath(
    gpa: std.mem.Allocator,
    base_dir: []const u8,
    agent_dir: []const u8,
    entry: []const u8,
) ![]u8 {
    if (std.mem.eql(u8, entry, "~")) {
        const home = inferredHome(agent_dir) orelse return error.HomeDirectoryUnavailable;
        return std.fs.path.resolve(gpa, &.{home});
    }
    if (std.mem.startsWith(u8, entry, "~/") or std.mem.startsWith(u8, entry, "~\\")) {
        const home = inferredHome(agent_dir) orelse return error.HomeDirectoryUnavailable;
        return std.fs.path.resolve(gpa, &.{ home, entry[2..] });
    }
    if (std.fs.path.isAbsolute(entry)) return std.fs.path.resolve(gpa, &.{entry});
    return std.fs.path.resolve(gpa, &.{ base_dir, entry });
}

fn normalizedRelative(gpa: std.mem.Allocator, base_dir: []const u8, path: []const u8) ![]u8 {
    const raw = try std.fs.path.relative(gpa, ".", null, base_dir, path);
    defer gpa.free(raw);
    const result = try gpa.dupe(u8, raw);
    normalizeSeparators(result);
    return result;
}

fn displayName(gpa: std.mem.Allocator, resource_type: ResourceType, path: []const u8) ![]u8 {
    const name = std.fs.path.basename(path);
    if (resource_type == .skills and std.mem.eql(u8, name, "SKILL.md")) {
        const parent = std.fs.path.dirname(path) orelse return gpa.dupe(u8, name);
        return gpa.dupe(u8, std.fs.path.basename(parent));
    }
    if (resource_type == .extensions) {
        const parent = std.fs.path.dirname(path) orelse return gpa.dupe(u8, name);
        const parent_name = std.fs.path.basename(parent);
        if (!std.mem.eql(u8, parent_name, "extensions")) {
            return std.fmt.allocPrint(gpa, "{s}/{s}", .{ parent_name, name });
        }
    }
    return gpa.dupe(u8, name);
}

const ParsedSelector = struct {
    scope: packages.Scope,
    source: SourceKind,
    base_dir: []const u8,
};

fn parseSelector(selector: []const u8) ?ParsedSelector {
    const prefix = "top-level:";
    if (!std.mem.startsWith(u8, selector, prefix)) return null;
    const rest = selector[prefix.len..];
    const scope_end = std.mem.indexOfScalar(u8, rest, ':') orelse return null;
    const scope_text = rest[0..scope_end];
    const after_scope = rest[scope_end + 1 ..];
    const source_end = std.mem.indexOfScalar(u8, after_scope, ':') orelse return null;
    const source_text = after_scope[0..source_end];
    const base_dir = after_scope[source_end + 1 ..];
    if (base_dir.len == 0) return null;
    const scope: packages.Scope = if (std.mem.eql(u8, scope_text, "user"))
        .user
    else if (std.mem.eql(u8, scope_text, "project"))
        .project
    else
        return null;
    const source: SourceKind = if (std.mem.eql(u8, source_text, "auto"))
        .auto
    else if (std.mem.eql(u8, source_text, "local"))
        .local
    else
        return null;
    return .{ .scope = scope, .source = source, .base_dir = base_dir };
}
fn selectorFor(gpa: std.mem.Allocator, scope: packages.Scope, source: SourceKind, base_dir: []const u8) ![]u8 {
    return std.fmt.allocPrint(gpa, "top-level:{s}:{s}:{s}", .{ @tagName(scope), @tagName(source), base_dir });
}

fn overrideOnly(gpa: std.mem.Allocator, entries: []const []const u8) ![]const []const u8 {
    var count: usize = 0;
    for (entries) |entry| if (isOverride(entry)) {
        count += 1;
    };
    if (count == 0) return &.{};
    var out = try gpa.alloc([]const u8, count);
    var index: usize = 0;
    for (entries) |entry| if (isOverride(entry)) {
        out[index] = entry;
        index += 1;
    };
    return out;
}

fn candidateEnabled(
    gpa: std.mem.Allocator,
    base_dir: []const u8,
    path: []const u8,
    entries: []const []const u8,
    resource_type: ResourceType,
    source: SourceKind,
) !bool {
    var one = package_resources.PathList.init(gpa);
    defer one.deinit();
    try one.appendCopyUnique(path);
    if (source == .auto) {
        const filtered = try overrideOnly(gpa, entries);
        defer if (filtered.len > 0) gpa.free(filtered);
        if (filtered.len > 0) try package_resources.applyUserFilter(gpa, base_dir, &one, filtered, resource_type);
    } else {
        try package_resources.applyUserFilter(gpa, base_dir, &one, entries, resource_type);
    }
    return one.items.items.len == 1;
}

fn appendResolvedCandidates(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(Candidate),
    resolved: *package_resources.PathList,
    scope: packages.Scope,
    source: SourceKind,
    base_dir: []const u8,
    resource_type: ResourceType,
    entries: []const []const u8,
) !void {
    for (resolved.items.items) |path| {
        const enabled = try candidateEnabled(gpa, base_dir, path, entries, resource_type, source);
        try appendOwnedCandidateUnique(gpa, out, .{
            .gpa = gpa,
            .scope = scope,
            .source = source,
            .base_dir = try gpa.dupe(u8, base_dir),
            .resource_type = resource_type,
            .path = try gpa.dupe(u8, path),
            .enabled = enabled,
        });
    }
}

fn appendConfiguredCandidates(
    gpa: std.mem.Allocator,
    io: Io,
    out: *std.ArrayList(Candidate),
    agent_dir: []const u8,
    base_dir: []const u8,
    scope: packages.Scope,
    config: ScopeConfig,
    resource_type: ResourceType,
) !void {
    const entries = config.entries(resource_type);
    for (entries) |entry| {
        if (entry.len == 0 or isOverride(entry)) continue;
        if (hasGlob(entry)) {
            var value = [_]std.json.Value{.{ .string = entry }};
            var resolved = try package_resources.resolveManifestEntries(gpa, io, base_dir, &value, resource_type);
            defer resolved.deinit();
            try appendResolvedCandidates(gpa, out, &resolved, scope, .local, base_dir, resource_type, entries);
        } else {
            const source_path = resolveConfiguredPath(gpa, base_dir, agent_dir, entry) catch |err| switch (err) {
                error.HomeDirectoryUnavailable => continue,
                else => return err,
            };
            defer gpa.free(source_path);
            var resolved = try package_resources.resolveSourcePath(gpa, io, source_path, resource_type);
            defer resolved.deinit();
            try appendResolvedCandidates(gpa, out, &resolved, scope, .local, base_dir, resource_type, entries);
        }
    }
}

fn appendAutoBase(
    gpa: std.mem.Allocator,
    io: Io,
    out: *std.ArrayList(Candidate),
    base_dir: []const u8,
    scope: packages.Scope,
    config: ScopeConfig,
    resource_type: ResourceType,
) !void {
    var resolved = try package_resources.resolveConventional(gpa, io, base_dir, resource_type);
    defer resolved.deinit();
    try appendResolvedCandidates(gpa, out, &resolved, scope, .auto, base_dir, resource_type, config.entries(resource_type));
}

fn pathKindExists(io: Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

fn appendAgentSkillsBases(
    gpa: std.mem.Allocator,
    io: Io,
    out: *std.ArrayList(Candidate),
    agent_dir: []const u8,
    config: ScopeConfig,
) !void {
    const home = inferredHome(agent_dir) orelse return;
    const agents = try std.fs.path.resolve(gpa, &.{ home, ".agents" });
    defer gpa.free(agents);
    try appendAutoBase(gpa, io, out, agents, .user, config, .skills);
}

fn appendProjectAgentSkillBases(
    gpa: std.mem.Allocator,
    io: Io,
    out: *std.ArrayList(Candidate),
    cwd: []const u8,
    config: ScopeConfig,
) !void {
    var current = try std.fs.path.resolve(gpa, &.{cwd});
    defer gpa.free(current);
    var depth: usize = 0;
    while (depth < 64) : (depth += 1) {
        const agents = try std.fs.path.join(gpa, &.{ current, ".agents" });
        defer gpa.free(agents);
        try appendAutoBase(gpa, io, out, agents, .project, config, .skills);

        const git = try std.fs.path.join(gpa, &.{ current, ".git" });
        defer gpa.free(git);
        if (pathKindExists(io, git)) break;
        const parent_raw = std.fs.path.dirname(current) orelse break;
        if (std.mem.eql(u8, parent_raw, current)) break;
        const parent = try gpa.dupe(u8, parent_raw);
        gpa.free(current);
        current = parent;
    }
}

fn collectScopeCandidates(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    scope: packages.Scope,
    config: ScopeConfig,
) !std.ArrayList(Candidate) {
    var out: std.ArrayList(Candidate) = .empty;
    errdefer {
        for (out.items) |*candidate| candidate.deinit();
        out.deinit(gpa);
    }
    const base_dir = try scopeBase(gpa, agent_dir, cwd, scope);
    defer gpa.free(base_dir);

    inline for (.{ ResourceType.extensions, ResourceType.skills, ResourceType.prompts, ResourceType.themes }) |resource_type| {
        try appendConfiguredCandidates(gpa, io, &out, agent_dir, base_dir, scope, config, resource_type);
        try appendAutoBase(gpa, io, &out, base_dir, scope, config, resource_type);
    }
    if (scope == .user) {
        try appendAgentSkillsBases(gpa, io, &out, agent_dir, config);
    } else {
        try appendProjectAgentSkillBases(gpa, io, &out, cwd, config);
    }
    return out;
}

fn candidateKeysMatch(
    gpa: std.mem.Allocator,
    raw_target: []const u8,
    path: []const u8,
    item_base: []const u8,
    settings_base: []const u8,
) !bool {
    if (raw_target.len == 0 or hasGlob(raw_target)) return false;
    const target = if (std.mem.startsWith(u8, raw_target, "./") or std.mem.startsWith(u8, raw_target, ".\\")) raw_target[2..] else raw_target;
    if (std.fs.path.isAbsolute(target)) {
        const resolved = std.fs.path.resolve(gpa, &.{target}) catch return false;
        defer gpa.free(resolved);
        return samePath(resolved, path);
    }
    const from_item = std.fs.path.resolve(gpa, &.{ item_base, target }) catch null;
    if (from_item) |resolved| {
        defer gpa.free(resolved);
        if (samePath(resolved, path)) return true;
    }
    if (!samePath(item_base, settings_base)) {
        const from_settings = std.fs.path.resolve(gpa, &.{ settings_base, target }) catch null;
        if (from_settings) |resolved| {
            defer gpa.free(resolved);
            if (samePath(resolved, path)) return true;
        }
    }
    return false;
}

fn exactOverrideState(
    gpa: std.mem.Allocator,
    entries: []const []const u8,
    path: []const u8,
    item_base: []const u8,
    settings_base: []const u8,
) !OverrideState {
    var state: OverrideState = .inherit;
    for (entries) |entry| {
        if (!isOverride(entry)) continue;
        if (!try candidateKeysMatch(gpa, entry[1..], path, item_base, settings_base)) continue;
        state = if (entry[0] == '!' or entry[0] == '-') .unload else .load;
    }
    return state;
}

fn projectOverlayDecision(
    gpa: std.mem.Allocator,
    entries: []const []const u8,
    path: []const u8,
    project_base: []const u8,
    resource_type: ResourceType,
) !?bool {
    const filtered = try overrideOnly(gpa, entries);
    defer if (filtered.len > 0) gpa.free(filtered);
    return package_resources.autoloadDisabledDecision(gpa, project_base, path, filtered, resource_type);
}

fn appendItemFromCandidate(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(Item),
    candidate: Candidate,
    enabled: bool,
    inherited_enabled: bool,
    inherited_from_user: bool,
    override_state: OverrideState,
) !void {
    const relative_path = try normalizedRelative(gpa, candidate.base_dir, candidate.path);
    errdefer gpa.free(relative_path);
    const name = try displayName(gpa, candidate.resource_type, candidate.path);
    errdefer gpa.free(name);
    const selector = try selectorFor(gpa, candidate.scope, candidate.source, candidate.base_dir);
    errdefer gpa.free(selector);
    const base = try gpa.dupe(u8, candidate.base_dir);
    errdefer gpa.free(base);
    const path = try gpa.dupe(u8, candidate.path);
    errdefer gpa.free(path);
    try out.append(gpa, .{
        .gpa = gpa,
        .selector = selector,
        .scope = candidate.scope,
        .source = candidate.source,
        .base_dir = base,
        .resource_type = candidate.resource_type,
        .path = path,
        .relative_path = relative_path,
        .display_name = name,
        .enabled = enabled,
        .inherited_enabled = inherited_enabled,
        .inherited_from_user = inherited_from_user,
        .override_state = override_state,
    });
}

fn findCandidate(candidates: []const Candidate, resource_type: ResourceType, path: []const u8) ?usize {
    for (candidates, 0..) |candidate, index| if (candidate.resource_type == resource_type and samePath(candidate.path, path)) return index;
    return null;
}

fn deinitCandidates(gpa: std.mem.Allocator, candidates: *std.ArrayList(Candidate)) void {
    for (candidates.items) |*candidate| candidate.deinit();
    candidates.deinit(gpa);
}

/// Discover top-level resources for the selected write scope. Disabled
/// candidates remain present so the native config selector can re-enable them.
pub fn discover(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    write_scope: packages.Scope,
    project_trusted: bool,
) !Inventory {
    if (write_scope == .temporary) return error.TemporaryPackageNotPersistent;
    if (write_scope == .project and !project_trusted) return error.ProjectNotTrusted;

    const user_base = try scopeBase(gpa, agent_dir, cwd, .user);
    defer gpa.free(user_base);
    const project_base = try scopeBase(gpa, agent_dir, cwd, .project);
    defer gpa.free(project_base);
    var user_config = try loadScopeConfig(gpa, io, user_base);
    defer user_config.deinit();
    var project_config: ScopeConfig = if (project_trusted)
        try loadScopeConfig(gpa, io, project_base)
    else
        .{ .gpa = gpa };
    defer project_config.deinit();

    var user_candidates = try collectScopeCandidates(gpa, io, agent_dir, cwd, .user, user_config);
    defer deinitCandidates(gpa, &user_candidates);
    var project_candidates: std.ArrayList(Candidate) = if (project_trusted)
        try collectScopeCandidates(gpa, io, agent_dir, cwd, .project, project_config)
    else
        .empty;
    defer deinitCandidates(gpa, &project_candidates);

    var out: std.ArrayList(Item) = .empty;
    errdefer {
        for (out.items) |*item| item.deinit();
        out.deinit(gpa);
    }

    if (write_scope == .user) {
        for (user_candidates.items) |candidate| {
            try appendItemFromCandidate(
                gpa,
                &out,
                candidate,
                candidate.enabled,
                candidate.enabled,
                false,
                if (candidate.enabled) .load else .unload,
            );
        }
    } else {
        var user_used = try gpa.alloc(bool, user_candidates.items.len);
        defer gpa.free(user_used);
        @memset(user_used, false);

        // Project-local sources have precedence over inherited user sources.
        for (project_candidates.items) |candidate| {
            const user_index = findCandidate(user_candidates.items, candidate.resource_type, candidate.path);
            if (user_index) |index| user_used[index] = true;
            const inherited = if (user_index) |index| user_candidates.items[index].enabled else candidate.enabled;
            const state = try exactOverrideState(
                gpa,
                project_config.entries(candidate.resource_type),
                candidate.path,
                candidate.base_dir,
                project_base,
            );
            // A project override of an inherited user resource materializes an
            // absolute plain source in project settings. Keep the user source
            // identity in the inventory so subsequent load/inherit cycles can
            // remove that materialized source instead of turning it into a
            // permanent project-local entry.
            const identity = if (user_index) |index| user_candidates.items[index] else candidate;
            try appendItemFromCandidate(gpa, &out, identity, candidate.enabled, inherited, user_index != null, state);
        }
        for (user_candidates.items, 0..) |candidate, index| {
            if (user_used[index]) continue;
            const state = try exactOverrideState(
                gpa,
                project_config.entries(candidate.resource_type),
                candidate.path,
                candidate.base_dir,
                project_base,
            );
            const overlay = try projectOverlayDecision(
                gpa,
                project_config.entries(candidate.resource_type),
                candidate.path,
                project_base,
                candidate.resource_type,
            );
            try appendItemFromCandidate(
                gpa,
                &out,
                candidate,
                overlay orelse candidate.enabled,
                candidate.enabled,
                true,
                state,
            );
        }
    }

    return .{ .gpa = gpa, .write_scope = write_scope, .items = try out.toOwnedSlice(gpa) };
}

fn resourceList(resources: *Resources, resource_type: ResourceType) *std.ArrayList([]const u8) {
    return switch (resource_type) {
        .extensions => &resources.extensions,
        .skills => &resources.skills,
        .prompts => &resources.prompts,
        .themes => &resources.themes,
    };
}

/// Resolve the exact enabled top-level resource paths used by the live agent.
/// Trusted project sources precede inherited user sources; untrusted projects
/// receive only the user view.
pub fn resolve(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    project_trusted: bool,
) !Resources {
    var inventory = try discover(
        gpa,
        io,
        agent_dir,
        cwd,
        if (project_trusted) .project else .user,
        project_trusted,
    );
    defer inventory.deinit();
    var result = Resources.init(gpa);
    errdefer result.deinit();
    for (inventory.items) |item| {
        if (!item.enabled) continue;
        try appendPathUnique(gpa, resourceList(&result, item.resource_type), item.path);
    }
    return result;
}

fn stripPrefix(entry: []const u8) []const u8 {
    return if (isOverride(entry)) entry[1..] else entry;
}

fn plainEntryMatches(
    gpa: std.mem.Allocator,
    entry: []const u8,
    item: Item,
    settings_base: []const u8,
) !bool {
    if (isOverride(entry) or hasGlob(entry)) return false;
    return candidateKeysMatch(gpa, entry, item.path, item.base_dir, settings_base);
}

fn replaceSettingsArray(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    resource_type: ResourceType,
    item: Item,
    write_scope: packages.Scope,
    state: OverrideState,
) !void {
    const settings_path = try std.fs.path.join(gpa, &.{ registry_dir, "settings.json" });
    defer gpa.free(settings_path);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, settings_path, gpa, .limited(8 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => try gpa.dupe(u8, "{}"),
        else => return err,
    };
    defer gpa.free(raw);
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var parsed = try std.json.parseFromSlice(std.json.Value, arena, raw, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidResourceSettings;

    var current: std.ArrayList([]const u8) = .empty;
    defer {
        for (current.items) |entry| gpa.free(entry);
        current.deinit(gpa);
    }
    if (parsed.value.object.get(resourceField(resource_type))) |value| {
        if (value != .array) return error.InvalidResourceSettings;
        for (value.array.items) |entry| {
            if (entry != .string) return error.InvalidResourceSettings;
            try current.append(gpa, try gpa.dupe(u8, entry.string));
        }
    }

    var retained: std.ArrayList([]const u8) = .empty;
    defer {
        for (retained.items) |entry| gpa.free(entry);
        retained.deinit(gpa);
    }
    const inherited_user = write_scope == .project and item.scope == .user;
    for (current.items) |entry| {
        const matches = try candidateKeysMatch(gpa, stripPrefix(entry), item.path, item.base_dir, registry_dir);
        if (isOverride(entry) and matches) continue;
        if (inherited_user and state == .inherit and try plainEntryMatches(gpa, entry, item, registry_dir)) continue;
        try retained.append(gpa, try gpa.dupe(u8, entry));
    }

    if (state != .inherit) {
        const pattern: []u8 = if (inherited_user)
            try gpa.dupe(u8, item.path)
        else
            try normalizedRelative(gpa, item.base_dir, item.path);
        defer gpa.free(pattern);
        normalizeSeparators(pattern);

        if (inherited_user) {
            var has_plain = false;
            for (retained.items) |entry| if (!isOverride(entry) and try plainEntryMatches(gpa, entry, item, registry_dir)) {
                has_plain = true;
                break;
            };
            if (!has_plain) try retained.append(gpa, try gpa.dupe(u8, pattern));
        }
        try retained.append(gpa, try std.fmt.allocPrint(gpa, "{c}{s}", .{
            if (state == .load) @as(u8, '+') else @as(u8, '-'),
            pattern,
        }));
    }

    const key = resourceField(resource_type);
    if (retained.items.len == 0) {
        _ = parsed.value.object.orderedRemove(key);
    } else {
        var array = std.json.Array.init(arena);
        for (retained.items) |entry| try array.append(.{ .string = try arena.dupe(u8, entry) });
        try parsed.value.object.put(arena, try arena.dupe(u8, key), .{ .array = array });
    }

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try std.json.Stringify.value(parsed.value, .{ .whitespace = .indent_2 }, &out.writer);
    try out.writer.writeByte('\n');
    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, settings_path, .{
        .replace = true,
        .make_path = true,
        .permissions = .default_file,
    });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, out.written(), 0);
    try atomic.replace(io);
}

const Mutation = struct {
    resource_type: ResourceType,
    item: Item,
    write_scope: packages.Scope,
    state: OverrideState,
};

fn mutateLocked(gpa: std.mem.Allocator, io: Io, registry_dir: []const u8, mutation: Mutation) !void {
    try replaceSettingsArray(gpa, io, registry_dir, mutation.resource_type, mutation.item, mutation.write_scope, mutation.state);
}

/// Persist one exact top-level resource decision under the package-operation
/// lock. Project scope supports inherit/load/unload and materializes an
/// absolute explicit source only while overriding a user resource.
pub fn setResource(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    write_scope: packages.Scope,
    project_trusted: bool,
    selector: []const u8,
    resource_type: ResourceType,
    relative_path: []const u8,
    state: OverrideState,
) !void {
    if (write_scope == .user and state == .inherit) return error.InvalidOverrideState;
    const parsed_selector = parseSelector(selector) orelse return error.InvalidResourceSelector;
    const target_path = if (std.fs.path.isAbsolute(relative_path))
        try std.fs.path.resolve(gpa, &.{relative_path})
    else
        try std.fs.path.resolve(gpa, &.{ parsed_selector.base_dir, relative_path });
    defer gpa.free(target_path);

    var inventory = try discover(gpa, io, agent_dir, cwd, write_scope, project_trusted);
    defer inventory.deinit();
    var found: ?Item = null;
    for (inventory.items) |item| {
        if (item.resource_type != resource_type) continue;
        if ((std.mem.eql(u8, item.selector, selector) and std.mem.eql(u8, item.relative_path, relative_path)) or
            samePath(item.path, target_path))
        {
            found = item;
            break;
        }
    }
    var source = found orelse return error.ResourceNotFound;
    // A project override materializes an inherited user path as a project-local
    // explicit source. Preserve the caller's original source identity so
    // returning to `inherit` removes that materialized source again.
    source.scope = parsed_selector.scope;
    source.source = parsed_selector.source;
    source.base_dir = parsed_selector.base_dir;
    // The callback executes synchronously while `inventory` and `selector` own every slice.
    try packages.withScopeConfigurationLock(
        gpa,
        io,
        agent_dir,
        cwd,
        write_scope,
        project_trusted,
        Mutation{
            .resource_type = resource_type,
            .item = source,
            .write_scope = write_scope,
            .state = state,
        },
        mutateLocked,
    );
}

fn writeTextFile(io: Io, path: []const u8, data: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(path) orelse ".");
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
}

test "global auto resource remains configurable when disabled" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try tmp.dir.realPath(io, &buffer);
    const root = buffer[0..count];
    const agent = try std.fs.path.join(gpa, &.{ root, ".pi", "agent" });
    defer gpa.free(agent);
    const extension = try std.fs.path.join(gpa, &.{ agent, "extensions", "auto.ts" });
    defer gpa.free(extension);
    try writeTextFile(io, extension, "export default () => {};\n");

    var before = try discover(gpa, io, agent, root, .user, true);
    try std.testing.expectEqual(@as(usize, 1), before.items.len);
    try std.testing.expect(before.items[0].enabled);
    const selector = try gpa.dupe(u8, before.items[0].selector);
    const relative = try gpa.dupe(u8, before.items[0].relative_path);
    before.deinit();
    defer gpa.free(selector);
    defer gpa.free(relative);

    try setResource(gpa, io, agent, root, .user, true, selector, .extensions, relative, .unload);
    var after = try discover(gpa, io, agent, root, .user, true);
    defer after.deinit();
    try std.testing.expectEqual(@as(usize, 1), after.items.len);
    try std.testing.expect(!after.items[0].enabled);
    try std.testing.expectEqual(OverrideState.unload, after.items[0].override_state);

    var resolved = try resolve(gpa, io, agent, root, true);
    defer resolved.deinit();
    try std.testing.expectEqual(@as(usize, 0), resolved.extensions.items.len);
}

test "explicit top-level source and unrelated settings survive exact toggle" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try tmp.dir.realPath(io, &buffer);
    const root = buffer[0..count];
    const agent = try std.fs.path.join(gpa, &.{ root, ".pi", "agent" });
    defer gpa.free(agent);
    const extension = try std.fs.path.join(gpa, &.{ agent, "extra", "explicit.ts" });
    defer gpa.free(extension);
    try writeTextFile(io, extension, "export default () => {};\n");
    const settings = try std.fs.path.join(gpa, &.{ agent, "settings.json" });
    defer gpa.free(settings);
    try writeTextFile(io, settings,
        \\{"theme":"night","extensions":["extra/explicit.ts"]}
    );

    var inventory = try discover(gpa, io, agent, root, .user, true);
    try std.testing.expectEqual(@as(usize, 1), inventory.items.len);
    try std.testing.expectEqual(SourceKind.local, inventory.items[0].source);
    const selector = try gpa.dupe(u8, inventory.items[0].selector);
    const relative = try gpa.dupe(u8, inventory.items[0].relative_path);
    inventory.deinit();
    defer gpa.free(selector);
    defer gpa.free(relative);
    try setResource(gpa, io, agent, root, .user, true, selector, .extensions, relative, .unload);

    const raw = try std.Io.Dir.cwd().readFileAlloc(io, settings, gpa, .limited(1024 * 1024));
    defer gpa.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"theme\": \"night\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "extra/explicit.ts") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "-extra/explicit.ts") != null);
}

test "malformed settings are rejected without replacement" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const agent = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent);
    const extension = try std.fs.path.join(gpa, &.{ agent, "extensions", "demo.ts" });
    defer gpa.free(extension);
    try writeTextFile(io, extension, "export default () => {};\n");
    const settings = try std.fs.path.join(gpa, &.{ agent, "settings.json" });
    defer gpa.free(settings);
    try writeTextFile(io, settings, "{malformed\n");

    try std.testing.expectError(
        error.SyntaxError,
        discover(gpa, io, agent, root, .user, true),
    );
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, settings, gpa, .limited(1024));
    defer gpa.free(raw);
    try std.testing.expectEqualStrings("{malformed\n", raw);
}

test "project inherited resource override can return to inheritance" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try tmp.dir.realPath(io, &buffer);
    const root = buffer[0..count];
    const agent = try std.fs.path.join(gpa, &.{ root, ".pi", "agent" });
    defer gpa.free(agent);
    const extension = try std.fs.path.join(gpa, &.{ agent, "extensions", "global.ts" });
    defer gpa.free(extension);
    try writeTextFile(io, extension, "export default () => {};\n");
    const project_settings = try std.fs.path.join(gpa, &.{ root, ".pi", "settings.json" });
    defer gpa.free(project_settings);
    try writeTextFile(io, project_settings, "{\"model\":\"keep\"}\n");

    var inventory = try discover(gpa, io, agent, root, .project, true);
    try std.testing.expectEqual(@as(usize, 1), inventory.items.len);
    try std.testing.expect(inventory.items[0].inherited_from_user);
    const selector = try gpa.dupe(u8, inventory.items[0].selector);
    const relative = try gpa.dupe(u8, inventory.items[0].relative_path);
    inventory.deinit();
    defer gpa.free(selector);
    defer gpa.free(relative);

    try setResource(gpa, io, agent, root, .project, true, selector, .extensions, relative, .unload);
    var disabled = try discover(gpa, io, agent, root, .project, true);
    try std.testing.expect(!disabled.items[0].enabled);
    try std.testing.expectEqual(OverrideState.unload, disabled.items[0].override_state);
    const disabled_selector = try gpa.dupe(u8, disabled.items[0].selector);
    const disabled_relative = try gpa.dupe(u8, disabled.items[0].relative_path);
    disabled.deinit();
    defer gpa.free(disabled_selector);
    defer gpa.free(disabled_relative);

    try setResource(gpa, io, agent, root, .project, true, disabled_selector, .extensions, disabled_relative, .load);
    var loaded = try discover(gpa, io, agent, root, .project, true);
    try std.testing.expect(loaded.items[0].enabled);
    try std.testing.expectEqual(OverrideState.load, loaded.items[0].override_state);
    const loaded_selector = try gpa.dupe(u8, loaded.items[0].selector);
    const loaded_relative = try gpa.dupe(u8, loaded.items[0].relative_path);
    loaded.deinit();
    defer gpa.free(loaded_selector);
    defer gpa.free(loaded_relative);

    try setResource(gpa, io, agent, root, .project, true, loaded_selector, .extensions, loaded_relative, .inherit);
    var inherited = try discover(gpa, io, agent, root, .project, true);
    defer inherited.deinit();
    try std.testing.expect(inherited.items[0].enabled);
    try std.testing.expectEqual(OverrideState.inherit, inherited.items[0].override_state);
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, project_settings, gpa, .limited(1024 * 1024));
    defer gpa.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"model\": \"keep\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "global.ts") == null);
}
