//! Local path packages: install / list / remove.
const std = @import("std");
const Io = std.Io;
const package_resources = @import("package_resources.zig");
const package_source = @import("package_source.zig");

/// Package configuration/install scope. User and project packages are
/// persistent. Temporary sources are resolved for one process and live below
/// the agent-private temporary root.
pub const Scope = enum {
    user,
    project,
    temporary,
};

pub const Package = struct {
    name: []const u8,
    path: []const u8,
    /// Registry/install scope. It is inferred from the registry file and is
    /// intentionally not serialized inside each record.
    scope: Scope = .user,
    /// Original source string (`path:`, `npm:`, or Git URL). Older checkpoint
    /// package records may leave this null and remain fully compatible.
    source: ?[]const u8 = null,
    /// Original package-source filtering. Null means no resource-class
    /// override; an allocated empty slice explicitly disables that class.
    autoload: bool = true,
    extensions: ?[]const []const u8 = null,
    skills: ?[]const []const u8 = null,
    prompts: ?[]const []const u8 = null,
    themes: ?[]const []const u8 = null,

    pub fn deinit(self: *Package, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.path);
        if (self.source) |source| gpa.free(source);
        freeOptionalPatterns(gpa, self.extensions);
        freeOptionalPatterns(gpa, self.skills);
        freeOptionalPatterns(gpa, self.prompts);
        freeOptionalPatterns(gpa, self.themes);
        self.* = undefined;
    }
};

fn freeOptionalPatterns(gpa: std.mem.Allocator, patterns: ?[]const []const u8) void {
    if (patterns) |items| {
        for (items) |item| gpa.free(item);
        gpa.free(items);
    }
}

fn cloneOptionalPatterns(gpa: std.mem.Allocator, patterns: ?[]const []const u8) !?[]const []const u8 {
    const items = patterns orelse return null;
    var out = try gpa.alloc([]const u8, items.len);
    var initialized: usize = 0;
    errdefer {
        for (out[0..initialized]) |item| gpa.free(item);
        gpa.free(out);
    }
    for (items, 0..) |item, index| {
        out[index] = try gpa.dupe(u8, item);
        initialized += 1;
    }
    return out;
}

fn clonePackage(gpa: std.mem.Allocator, package: Package) !Package {
    const name = try gpa.dupe(u8, package.name);
    errdefer gpa.free(name);
    const path = try gpa.dupe(u8, package.path);
    errdefer gpa.free(path);
    const source = if (package.source) |value| try gpa.dupe(u8, value) else null;
    errdefer if (source) |value| gpa.free(value);
    const extensions = try cloneOptionalPatterns(gpa, package.extensions);
    errdefer freeOptionalPatterns(gpa, extensions);
    const skills = try cloneOptionalPatterns(gpa, package.skills);
    errdefer freeOptionalPatterns(gpa, skills);
    const prompts = try cloneOptionalPatterns(gpa, package.prompts);
    errdefer freeOptionalPatterns(gpa, prompts);
    const themes = try cloneOptionalPatterns(gpa, package.themes);
    errdefer freeOptionalPatterns(gpa, themes);
    return .{
        .name = name,
        .path = path,
        .scope = package.scope,
        .source = source,
        .autoload = package.autoload,
        .extensions = extensions,
        .skills = skills,
        .prompts = prompts,
        .themes = themes,
    };
}

/// Resolved resources contributed by installed Pi packages. Paths are owned by
/// this value and may point at either individual resource files or resource
/// directories, matching the upstream package-manifest contract.
pub const Resources = struct {
    gpa: std.mem.Allocator,
    extensions: std.ArrayList([]const u8) = .empty,
    skills: std.ArrayList([]const u8) = .empty,
    prompts: std.ArrayList([]const u8) = .empty,
    themes: std.ArrayList([]const u8) = .empty,
    // First-wins tombstones used by higher-precedence package deltas. These
    // remain internal to resource resolution and are never exposed as active
    // resources.
    blocked_extensions: std.ArrayList([]const u8) = .empty,
    blocked_skills: std.ArrayList([]const u8) = .empty,
    blocked_prompts: std.ArrayList([]const u8) = .empty,
    blocked_themes: std.ArrayList([]const u8) = .empty,

    pub fn init(gpa: std.mem.Allocator) Resources {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Resources) void {
        freePathList(self.gpa, &self.extensions);
        freePathList(self.gpa, &self.skills);
        freePathList(self.gpa, &self.prompts);
        freePathList(self.gpa, &self.themes);
        freePathList(self.gpa, &self.blocked_extensions);
        freePathList(self.gpa, &self.blocked_skills);
        freePathList(self.gpa, &self.blocked_prompts);
        freePathList(self.gpa, &self.blocked_themes);
        self.* = undefined;
    }
};

fn freePathList(gpa: std.mem.Allocator, paths: *std.ArrayList([]const u8)) void {
    for (paths.items) |path| gpa.free(path);
    paths.deinit(gpa);
}

fn containsPath(items: []const []const u8, candidate: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, candidate)) return true;
    }
    return false;
}

fn appendResolvedPaths(
    gpa: std.mem.Allocator,
    target: *std.ArrayList([]const u8),
    blocked: *const std.ArrayList([]const u8),
    resolved: *const package_resources.PathList,
) !void {
    for (resolved.items.items) |path| {
        if (containsPath(target.items, path) or containsPath(blocked.items, path)) continue;
        try target.append(gpa, try gpa.dupe(u8, path));
    }
}

fn appendResourceDecision(
    gpa: std.mem.Allocator,
    target: *std.ArrayList([]const u8),
    blocked: *std.ArrayList([]const u8),
    path: []const u8,
    enabled: bool,
) !void {
    if (containsPath(target.items, path) or containsPath(blocked.items, path)) return;
    if (enabled) {
        try target.append(gpa, try gpa.dupe(u8, path));
    } else {
        try blocked.append(gpa, try gpa.dupe(u8, path));
    }
}

fn hasPackageFilter(package: Package) bool {
    return !package.autoload or package.extensions != null or package.skills != null or package.prompts != null or package.themes != null;
}

fn hasConventionalResourceDirectory(gpa: std.mem.Allocator, io: Io, root: []const u8) !bool {
    inline for (.{
        package_resources.ResourceType.extensions,
        package_resources.ResourceType.skills,
        package_resources.ResourceType.prompts,
        package_resources.ResourceType.themes,
    }) |resource_type| {
        const path = try std.fs.path.join(gpa, &.{ root, @tagName(resource_type) });
        defer gpa.free(path);
        if (std.Io.Dir.cwd().statFile(io, path, .{})) |stat| {
            if (stat.kind == .directory) return true;
        } else |_| {}
    }
    return false;
}

fn packagePatterns(package: Package, resource_type: package_resources.ResourceType) ?[]const []const u8 {
    return switch (resource_type) {
        .extensions => package.extensions,
        .skills => package.skills,
        .prompts => package.prompts,
        .themes => package.themes,
    };
}

fn resourcesTarget(resources: *Resources, resource_type: package_resources.ResourceType) *std.ArrayList([]const u8) {
    return switch (resource_type) {
        .extensions => &resources.extensions,
        .skills => &resources.skills,
        .prompts => &resources.prompts,
        .themes => &resources.themes,
    };
}

fn blockedResourcesTarget(resources: *Resources, resource_type: package_resources.ResourceType) *std.ArrayList([]const u8) {
    return switch (resource_type) {
        .extensions => &resources.blocked_extensions,
        .skills => &resources.blocked_skills,
        .prompts => &resources.blocked_prompts,
        .themes => &resources.blocked_themes,
    };
}

fn applyPackageFilter(
    gpa: std.mem.Allocator,
    package: Package,
    base_dir: []const u8,
    resolved: *package_resources.PathList,
    resource_type: package_resources.ResourceType,
) !void {
    const patterns = packagePatterns(package, resource_type);
    if (package.autoload) {
        if (patterns != null) try package_resources.applyUserFilter(gpa, base_dir, resolved, patterns, resource_type);
    } else {
        try package_resources.applyAutoloadDisabledFilter(gpa, base_dir, resolved, patterns, resource_type);
    }
}

fn resolvePackageResourceTypeBase(
    gpa: std.mem.Allocator,
    io: Io,
    package: Package,
    manifest: ?std.json.ObjectMap,
    resource_type: package_resources.ResourceType,
) !package_resources.PathList {
    return if (manifest) |object| blk: {
        const value = object.get(@tagName(resource_type)) orelse break :blk package_resources.PathList.init(gpa);
        if (value != .array) break :blk package_resources.PathList.init(gpa);
        // readPiManifest accepts a field only when every entry is a string.
        for (value.array.items) |entry| if (entry != .string) break :blk package_resources.PathList.init(gpa);
        break :blk try package_resources.resolveManifestEntries(gpa, io, package.path, value.array.items, resource_type);
    } else try package_resources.resolveConventional(gpa, io, package.path, resource_type);
}

fn resolvePackageResourceType(
    gpa: std.mem.Allocator,
    io: Io,
    package: Package,
    manifest: ?std.json.ObjectMap,
    resource_type: package_resources.ResourceType,
) !package_resources.PathList {
    var resolved = try resolvePackageResourceTypeBase(gpa, io, package, manifest, resource_type);
    errdefer resolved.deinit();
    try applyPackageFilter(gpa, package, package.path, &resolved, resource_type);
    return resolved;
}

/// Discover every manifest-approved resource contributed by one package before
/// applying package-level enable/disable filters. This is the authoritative
/// inventory used by the native `pi config` selector, so disabled resources
/// remain visible and can be re-enabled.
pub fn discoverResourceCandidates(
    gpa: std.mem.Allocator,
    io: Io,
    package: Package,
    resource_type: package_resources.ResourceType,
) !package_resources.PathList {
    const stat = std.Io.Dir.cwd().statFile(io, package.path, .{}) catch
        return package_resources.PathList.init(gpa);
    if (stat.kind == .file) {
        if (resource_type != .extensions) return package_resources.PathList.init(gpa);
        return package_resources.resolveSourcePath(gpa, io, package.path, .extensions);
    }
    if (stat.kind != .directory) return package_resources.PathList.init(gpa);

    const package_json = try std.fs.path.join(gpa, &.{ package.path, "package.json" });
    defer gpa.free(package_json);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, package_json, gpa, .limited(1024 * 1024)) catch null;
    if (raw) |json_bytes| {
        defer gpa.free(json_bytes);
        var parsed = std.json.parseFromSlice(std.json.Value, gpa, json_bytes, .{}) catch null;
        if (parsed) |*document| {
            defer document.deinit();
            if (document.value == .object) {
                if (document.value.object.get("pi")) |pi_value| {
                    if (pi_value == .object) {
                        return resolvePackageResourceTypeBase(gpa, io, package, pi_value.object, resource_type);
                    }
                }
            }
        }
    }

    var conventional = try resolvePackageResourceTypeBase(gpa, io, package, null, resource_type);
    if (resource_type == .extensions and conventional.items.items.len == 0 and
        !try hasConventionalResourceDirectory(gpa, io, package.path))
    {
        conventional.deinit();
        return package_resources.resolveSourcePath(gpa, io, package.path, .extensions);
    }
    return conventional;
}

fn appendPackageResources(
    gpa: std.mem.Allocator,
    io: Io,
    package: Package,
    manifest: ?std.json.ObjectMap,
    resources: *Resources,
) !void {
    inline for (.{
        package_resources.ResourceType.extensions,
        package_resources.ResourceType.skills,
        package_resources.ResourceType.prompts,
        package_resources.ResourceType.themes,
    }) |resource_type| {
        const target = resourcesTarget(resources, resource_type);
        const blocked = blockedResourcesTarget(resources, resource_type);
        if (package.scope == .project and !package.autoload) {
            var candidates = try resolvePackageResourceTypeBase(gpa, io, package, manifest, resource_type);
            defer candidates.deinit();
            const patterns = packagePatterns(package, resource_type);
            for (candidates.items.items) |path| {
                const decision = try package_resources.autoloadDisabledDecision(
                    gpa,
                    package.path,
                    path,
                    patterns,
                    resource_type,
                );
                if (decision) |enabled| try appendResourceDecision(gpa, target, blocked, path, enabled);
            }
        } else {
            var resolved = try resolvePackageResourceType(gpa, io, package, manifest, resource_type);
            defer resolved.deinit();
            try appendResolvedPaths(gpa, target, blocked, &resolved);
        }
    }
}

/// Resolve all resources from installed package roots.
///
/// When package.json contains a `pi` object, its resource arrays are
/// authoritative. Without a Pi manifest, conventional resource directories
/// are discovered. Package-level `autoload` and resource filters are then
/// applied on top of the manifest-approved file set.
pub fn resolveResources(gpa: std.mem.Allocator, io: Io, packages: []const Package) !Resources {
    var resources = Resources.init(gpa);
    errdefer resources.deinit();

    for (packages) |package| {
        const stat = std.Io.Dir.cwd().statFile(io, package.path, .{}) catch continue;
        const before_count = resources.extensions.items.len + resources.skills.items.len + resources.prompts.items.len + resources.themes.items.len;

        if (stat.kind == .file) {
            var direct = try package_resources.resolveSourcePath(gpa, io, package.path, .extensions);
            defer direct.deinit();
            const base_dir = std.fs.path.dirname(package.path) orelse package.path;
            try applyPackageFilter(gpa, package, base_dir, &direct, .extensions);
            try appendResolvedPaths(gpa, &resources.extensions, &resources.blocked_extensions, &direct);
            continue;
        }
        if (stat.kind != .directory) continue;

        var resolved_with_manifest = false;
        const package_json = try std.fs.path.join(gpa, &.{ package.path, "package.json" });
        defer gpa.free(package_json);
        const raw = std.Io.Dir.cwd().readFileAlloc(io, package_json, gpa, .limited(1024 * 1024)) catch null;
        if (raw) |json_bytes| {
            defer gpa.free(json_bytes);
            var parsed = std.json.parseFromSlice(std.json.Value, gpa, json_bytes, .{}) catch null;
            if (parsed) |*document| {
                defer document.deinit();
                if (document.value == .object) {
                    if (document.value.object.get("pi")) |pi_value| {
                        if (pi_value == .object) {
                            resolved_with_manifest = true;
                            try appendPackageResources(gpa, io, package, pi_value.object, &resources);
                        }
                    }
                }
            }
        }

        if (!resolved_with_manifest) try appendPackageResources(gpa, io, package, null, &resources);

        // A configured local/package source may itself be an extension entry
        // rather than containing conventional resource directories. Upstream
        // falls back to the source root only when no package resources exist.
        const after_count = resources.extensions.items.len + resources.skills.items.len + resources.prompts.items.len + resources.themes.items.len;
        if (!resolved_with_manifest and !hasPackageFilter(package) and
            !try hasConventionalResourceDirectory(gpa, io, package.path) and after_count == before_count)
        {
            var direct = try package_resources.resolveSourcePath(gpa, io, package.path, .extensions);
            defer direct.deinit();
            try appendResolvedPaths(gpa, &resources.extensions, &resources.blocked_extensions, &direct);
        }
    }
    return resources;
}

fn packagesJsonPath(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fs.path.join(gpa, &.{ agent_dir, "packages.json" });
}

fn scopeRoot(
    gpa: std.mem.Allocator,
    agent_dir: []const u8,
    cwd: []const u8,
    scope: Scope,
) ![]u8 {
    return switch (scope) {
        .user => try gpa.dupe(u8, agent_dir),
        .project => try std.fs.path.join(gpa, &.{ cwd, ".pi" }),
        .temporary => try std.fs.path.join(gpa, &.{ agent_dir, "tmp", "extensions" }),
    };
}

pub const PackageOperation = enum {
    install,
    update,
    remove,
    repair,
    configure,
};

pub const OperationStatus = struct {
    gpa: std.mem.Allocator,
    active: bool = false,
    metadata_present: bool = false,
    stale_metadata: bool = false,
    pid: u32 = 0,
    started_ms: i64 = 0,
    operation: []const u8 = "",
    registry_dir: []const u8 = "",

    pub fn deinit(self: *OperationStatus) void {
        if (self.operation.len > 0) self.gpa.free(self.operation);
        if (self.registry_dir.len > 0) self.gpa.free(self.registry_dir);
        self.* = undefined;
    }
};

fn currentProcessId() u32 {
    const builtin = @import("builtin");
    return switch (builtin.os.tag) {
        .linux => @intCast(std.os.linux.getpid()),
        .windows => std.os.windows.GetCurrentProcessId(),
        .plan9 => std.os.plan9.getpid(),
        else => 0,
    };
}

fn parseOperationStatus(gpa: std.mem.Allocator, raw: []const u8, active: bool) !OperationStatus {
    var result: OperationStatus = .{ .gpa = gpa, .active = active };
    errdefer result.deinit();
    if (std.mem.trim(u8, raw, " \t\r\n").len == 0) return result;
    result.metadata_present = true;
    result.stale_metadata = !active;
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return result;
    defer parsed.deinit();
    if (parsed.value != .object) return result;
    if (parsed.value.object.get("pid")) |value| switch (value) {
        .integer => {
            if (value.integer >= 0 and value.integer <= std.math.maxInt(u32)) result.pid = @intCast(value.integer);
        },
        else => {},
    };
    if (parsed.value.object.get("startedMs")) |value| switch (value) {
        .integer => result.started_ms = value.integer,
        else => {},
    };
    if (parsed.value.object.get("operation")) |value| switch (value) {
        .string => result.operation = try gpa.dupe(u8, value.string),
        else => {},
    };
    if (parsed.value.object.get("registryDir")) |value| switch (value) {
        .string => result.registry_dir = try gpa.dupe(u8, value.string),
        else => {},
    };
    return result;
}

fn readOperationMetadata(gpa: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.LockViolation => try gpa.alloc(u8, 0),
        else => return err,
    };
}

fn readOperationMetadataFromFile(gpa: std.mem.Allocator, io: Io, file: std.Io.File) ![]u8 {
    const length = try file.length(io);
    if (length > 64 * 1024) return error.PackageOperationMetadataTooLarge;
    const raw = try gpa.alloc(u8, @intCast(length));
    errdefer gpa.free(raw);
    const read = try file.readPositionalAll(io, raw, 0);
    if (read != raw.len) return error.UnexpectedEndOfFile;
    return raw;
}

fn operationMetadataPath(gpa: std.mem.Allocator, lock_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(gpa, "{s}.metadata", .{lock_path});
}

const OperationLock = struct {
    gpa: std.mem.Allocator,
    io: Io,
    file: std.Io.File,
    path: []u8,
    metadata_path: []u8,

    fn acquire(
        gpa: std.mem.Allocator,
        io: Io,
        registry_dir: []const u8,
        operation: PackageOperation,
    ) !OperationLock {
        try std.Io.Dir.cwd().createDirPath(io, registry_dir);
        const path = try std.fs.path.join(gpa, &.{ registry_dir, ".packages.lock" });
        errdefer gpa.free(path);
        const metadata_path = try operationMetadataPath(gpa, path);
        errdefer gpa.free(metadata_path);
        const max_attempts: usize = 10;
        var attempt: usize = 0;
        while (attempt < max_attempts) : (attempt += 1) {
            const file = std.Io.Dir.cwd().createFile(io, path, .{
                .read = true,
                .truncate = false,
                .lock = .exclusive,
                .lock_nonblocking = true,
            }) catch |err| switch (err) {
                error.WouldBlock => {
                    if (attempt + 1 == max_attempts) return error.PackageOperationLocked;
                    const pause: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(20), .clock = .real } };
                    pause.sleep(io) catch return error.PackageOperationLocked;
                    continue;
                },
                else => return err,
            };
            errdefer file.close(io);

            var out: std.Io.Writer.Allocating = .init(gpa);
            defer out.deinit();
            try std.json.Stringify.value(.{
                .pid = currentProcessId(),
                .operation = @tagName(operation),
                .startedMs = std.Io.Clock.real.now(io).toMilliseconds(),
                .registryDir = registry_dir,
            }, .{}, &out.writer);
            try out.writer.writeByte('\n');
            // Windows denies independent reads of a file carrying an exclusive
            // byte-range lock. Keep coordination on the stable lock file and
            // publish observable owner metadata through an atomic sidecar.
            try file.setLength(io, 0);
            try file.sync(io);
            try atomicWriteBytes(io, metadata_path, out.written());
            return .{ .gpa = gpa, .io = io, .file = file, .path = path, .metadata_path = metadata_path };
        }
        return error.PackageOperationLocked;
    }

    fn deinit(self: *OperationLock) void {
        // Remove owner metadata before unlocking. The lock file is retained so
        // all processes coordinate on one stable inode.
        std.Io.Dir.cwd().deleteFile(self.io, self.metadata_path) catch {};
        self.file.setLength(self.io, 0) catch {};
        self.file.sync(self.io) catch {};
        self.file.close(self.io);
        self.gpa.free(self.path);
        self.gpa.free(self.metadata_path);
        self.* = undefined;
    }
};

/// Inspect one package scope without blocking. When another process owns the
/// advisory lock, its atomically written operation metadata is returned. A
/// non-empty payload on an unlocked file is reported as stale evidence rather
/// than being mistaken for an active owner.
pub fn inspectOperation(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    scope: Scope,
    project_trusted: bool,
) !OperationStatus {
    if (scope == .temporary) return error.TemporaryPackageNotPersistent;
    if (scope == .project and !project_trusted) return error.ProjectNotTrusted;
    const registry_dir = try scopeRoot(gpa, agent_dir, cwd, scope);
    defer gpa.free(registry_dir);
    const path = try std.fs.path.join(gpa, &.{ registry_dir, ".packages.lock" });
    defer gpa.free(path);
    const metadata_path = try operationMetadataPath(gpa, path);
    defer gpa.free(metadata_path);
    try std.Io.Dir.cwd().createDirPath(io, registry_dir);

    const probe = std.Io.Dir.cwd().createFile(io, path, .{
        .read = true,
        .truncate = false,
        .lock = .exclusive,
        .lock_nonblocking = true,
    }) catch |err| switch (err) {
        error.WouldBlock => {
            const raw = try readOperationMetadata(gpa, io, metadata_path);
            defer gpa.free(raw);
            return parseOperationStatus(gpa, raw, true);
        },
        else => return err,
    };
    defer probe.close(io);
    var raw = try readOperationMetadata(gpa, io, metadata_path);
    if (raw.len == 0) {
        gpa.free(raw);
        raw = try readOperationMetadataFromFile(gpa, io, probe);
    }
    defer gpa.free(raw);
    return parseOperationStatus(gpa, raw, false);
}

const git_update_marker_suffix = ".pi-update-incomplete";

pub const RepairResult = struct {
    markers_found: usize = 0,
    committed_prepared_updates: usize = 0,
    restored_backups: usize = 0,
    cleaned_artifacts: usize = 0,
    removed_markers: usize = 0,
    migrated_legacy_packages: usize = 0,
    cleaned_legacy_settings: bool = false,
};

pub const ScopeHealth = struct {
    operation: OperationStatus,
    repair_markers: usize = 0,
    legacy_packages_pending: bool = false,
    native_registry_present: bool = false,

    pub fn deinit(self: *ScopeHealth) void {
        self.operation.deinit();
        self.* = undefined;
    }
};

fn pathExists(io: Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

fn pathEndsWithPortable(path: []const u8, suffix: []const u8) bool {
    if (path.len < suffix.len) return false;
    const tail = path[path.len - suffix.len ..];
    for (tail, suffix) |actual, expected| {
        const normalized = if (actual == '\\') '/' else actual;
        if (normalized != expected) return false;
    }
    return true;
}

fn removeAnyPath(io: Io, path: []const u8) !bool {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    switch (stat.kind) {
        .directory => try std.Io.Dir.cwd().deleteTree(io, path),
        else => try std.Io.Dir.cwd().deleteFile(io, path),
    }
    return true;
}

fn atomicWriteBytes(io: Io, path: []const u8, bytes: []const u8) !void {
    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, path, .{
        .replace = true,
        .make_path = true,
        .permissions = .default_file,
    });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, bytes, 0);
    try atomic.replace(io);
}

fn gitUpdateMarkerPath(gpa: std.mem.Allocator, target: []const u8) ![]u8 {
    const parent = std.fs.path.dirname(target) orelse return error.InvalidGitPackageSource;
    const basename = std.fs.path.basename(target);
    return std.fmt.allocPrint(gpa, "{s}" ++ std.fs.path.sep_str ++ ".{s}{s}", .{ parent, basename, git_update_marker_suffix });
}

fn validateGitRepairArtifact(
    gpa: std.mem.Allocator,
    target: []const u8,
    candidate: []const u8,
    label: []const u8,
) !void {
    const normalized_target = try normalizedPath(gpa, target);
    defer gpa.free(normalized_target);
    const normalized_candidate = try normalizedPath(gpa, candidate);
    defer gpa.free(normalized_candidate);
    const target_parent = std.fs.path.dirname(normalized_target) orelse return error.PackageRepairStateInvalid;
    const candidate_parent = std.fs.path.dirname(normalized_candidate) orelse return error.PackageRepairStateInvalid;
    if (!std.mem.eql(u8, target_parent, candidate_parent)) return error.PackageRepairStateInvalid;
    const expected_prefix = try std.fmt.allocPrint(gpa, "{s}.{s}-", .{ std.fs.path.basename(normalized_target), label });
    defer gpa.free(expected_prefix);
    if (!std.mem.startsWith(u8, std.fs.path.basename(normalized_candidate), expected_prefix))
        return error.PackageRepairStateInvalid;
}

fn writeGitRepairMarker(
    gpa: std.mem.Allocator,
    io: Io,
    marker_path: []const u8,
    target: []const u8,
    temporary: []const u8,
    backup: []const u8,
) !void {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try out.writer.writeAll("{\"version\":1,\"target\":");
    try std.json.Stringify.value(target, .{}, &out.writer);
    try out.writer.writeAll(",\"temporary\":");
    try std.json.Stringify.value(temporary, .{}, &out.writer);
    try out.writer.writeAll(",\"backup\":");
    try std.json.Stringify.value(backup, .{}, &out.writer);
    try out.writer.writeAll("}\n");
    try atomicWriteBytes(io, marker_path, out.written());
}

fn markerString(object: std.json.ObjectMap, field: []const u8) ![]const u8 {
    const value = object.get(field) orelse return error.PackageRepairStateInvalid;
    if (value != .string or value.string.len == 0) return error.PackageRepairStateInvalid;
    return value.string;
}

fn recoverGitRepairMarker(
    gpa: std.mem.Allocator,
    io: Io,
    marker_path: []const u8,
    result: *RepairResult,
) !void {
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, marker_path, gpa, .limited(64 * 1024));
    defer gpa.free(raw);
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return error.PackageRepairStateInvalid;
    defer parsed.deinit();
    if (parsed.value != .object) return error.PackageRepairStateInvalid;
    const target = try markerString(parsed.value.object, "target");
    const temporary = try markerString(parsed.value.object, "temporary");
    const backup = try markerString(parsed.value.object, "backup");

    const marker_name = std.fs.path.basename(marker_path);
    if (!std.mem.startsWith(u8, marker_name, ".") or
        !std.mem.endsWith(u8, marker_name, git_update_marker_suffix) or
        marker_name.len <= 1 + git_update_marker_suffix.len)
        return error.PackageRepairStateInvalid;
    const expected_name = marker_name[1 .. marker_name.len - git_update_marker_suffix.len];
    const marker_parent = std.fs.path.dirname(marker_path) orelse return error.PackageRepairStateInvalid;
    const expected_target_raw = try std.fs.path.join(gpa, &.{ marker_parent, expected_name });
    defer gpa.free(expected_target_raw);
    const expected_target = try normalizedPath(gpa, expected_target_raw);
    defer gpa.free(expected_target);
    const normalized_target = try normalizedPath(gpa, target);
    defer gpa.free(normalized_target);
    if (!std.mem.eql(u8, expected_target, normalized_target)) return error.PackageRepairStateInvalid;
    try validateGitRepairArtifact(gpa, target, temporary, "tmp");
    try validateGitRepairArtifact(gpa, target, backup, "old");

    result.markers_found += 1;
    if (pathExists(io, target)) {
        if (try removeAnyPath(io, temporary)) result.cleaned_artifacts += 1;
        if (try removeAnyPath(io, backup)) result.cleaned_artifacts += 1;
    } else if (pathExists(io, temporary)) {
        std.Io.Dir.renameAbsolute(temporary, target, io) catch return error.PackageRepairCommitFailed;
        result.committed_prepared_updates += 1;
        if (try removeAnyPath(io, backup)) result.cleaned_artifacts += 1;
    } else if (pathExists(io, backup)) {
        std.Io.Dir.renameAbsolute(backup, target, io) catch return error.PackageRepairCommitFailed;
        result.restored_backups += 1;
    } else {
        return error.PackageRepairStateInvalid;
    }
    try std.Io.Dir.cwd().deleteFile(io, marker_path);
    result.removed_markers += 1;
}

fn recoverGitTarget(
    gpa: std.mem.Allocator,
    io: Io,
    target: []const u8,
    result: *RepairResult,
) !void {
    const marker_path = try gitUpdateMarkerPath(gpa, target);
    defer gpa.free(marker_path);
    if (!pathExists(io, marker_path)) return;
    try recoverGitRepairMarker(gpa, io, marker_path, result);
}

fn collectGitRepairMarkers(
    gpa: std.mem.Allocator,
    io: Io,
    directory: []const u8,
    depth: usize,
    paths: *std.ArrayList([]u8),
) !void {
    if (depth > 12) return;
    var dir = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (std.mem.eql(u8, entry.name, ".git") or std.mem.eql(u8, entry.name, "node_modules")) continue;
        const path = try std.fs.path.join(gpa, &.{ directory, entry.name });
        errdefer gpa.free(path);
        if (entry.kind == .directory) {
            defer gpa.free(path);
            try collectGitRepairMarkers(gpa, io, path, depth + 1, paths);
        } else if (std.mem.startsWith(u8, entry.name, ".") and std.mem.endsWith(u8, entry.name, git_update_marker_suffix)) {
            try paths.append(gpa, path);
        } else {
            gpa.free(path);
        }
    }
}

fn recoverAllGitOperations(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    result: *RepairResult,
) !void {
    const git_root = try std.fs.path.join(gpa, &.{ registry_dir, "git" });
    defer gpa.free(git_root);
    var markers: std.ArrayList([]u8) = .empty;
    defer {
        for (markers.items) |path| gpa.free(path);
        markers.deinit(gpa);
    }
    try collectGitRepairMarkers(gpa, io, git_root, 0, &markers);
    std.mem.sort([]u8, markers.items, {}, struct {
        fn lessThan(_: void, a: []u8, b: []u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);
    for (markers.items) |marker_path| try recoverGitRepairMarker(gpa, io, marker_path, result);
}

/// Inspect package coordination and recovery state without modifying either
/// the registry or managed package trees. This is used by `pi repair --check`
/// and interactive startup diagnostics.
pub fn inspectScopeHealth(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    scope: Scope,
    project_trusted: bool,
) !ScopeHealth {
    if (scope == .temporary) return error.TemporaryPackageNotPersistent;
    if (scope == .project and !project_trusted) return error.ProjectNotTrusted;
    var operation = try inspectOperation(gpa, io, agent_dir, cwd, scope, project_trusted);
    errdefer operation.deinit();
    const registry_dir = try scopeRoot(gpa, agent_dir, cwd, scope);
    defer gpa.free(registry_dir);
    const git_root = try std.fs.path.join(gpa, &.{ registry_dir, "git" });
    defer gpa.free(git_root);
    var markers: std.ArrayList([]u8) = .empty;
    defer {
        for (markers.items) |path| gpa.free(path);
        markers.deinit(gpa);
    }
    try collectGitRepairMarkers(gpa, io, git_root, 0, &markers);
    const registry_path = try packagesJsonPath(gpa, registry_dir);
    defer gpa.free(registry_path);
    return .{
        .operation = operation,
        .repair_markers = markers.items.len,
        .legacy_packages_pending = try legacySettingsPackagesAreArray(gpa, io, registry_dir),
        .native_registry_present = pathExists(io, registry_path),
    };
}

fn legacyPackagePath(
    gpa: std.mem.Allocator,
    registry_dir: []const u8,
    parsed: package_source.Source,
) ![]u8 {
    return switch (parsed.kind) {
        .local => if (std.fs.path.isAbsolute(parsed.spec))
            try std.fs.path.resolve(gpa, &.{parsed.spec})
        else
            try std.fs.path.resolve(gpa, &.{ registry_dir, parsed.spec }),
        .npm => try std.fs.path.join(gpa, &.{ registry_dir, "npm", "node_modules", parsed.name }),
        .git => try std.fs.path.join(gpa, &.{ registry_dir, "git", parsed.host.?, parsed.repository_path.? }),
    };
}

fn parseLegacySettingsPackages(
    gpa: std.mem.Allocator,
    raw: []const u8,
    registry_dir: []const u8,
    scope: Scope,
) ![]Package {
    var parsed_settings = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return try gpa.alloc(Package, 0);
    defer parsed_settings.deinit();
    if (parsed_settings.value != .object) return try gpa.alloc(Package, 0);
    const configured = parsed_settings.value.object.get("packages") orelse return try gpa.alloc(Package, 0);
    if (configured != .array) return try gpa.alloc(Package, 0);

    var result: std.ArrayList(Package) = .empty;
    errdefer {
        for (result.items) |*package| package.deinit(gpa);
        result.deinit(gpa);
    }
    for (configured.array.items) |entry| {
        const source_value: ?[]const u8 = switch (entry) {
            .string => |value| value,
            .object => |object| blk: {
                const value = object.get("source") orelse break :blk null;
                break :blk if (value == .string) value.string else null;
            },
            else => null,
        };
        const source = source_value orelse continue;
        if (source.len == 0) continue;
        var parsed_source = package_source.parse(gpa, source) catch continue;
        defer parsed_source.deinit();
        const path = try legacyPackagePath(gpa, registry_dir, parsed_source);
        errdefer gpa.free(path);
        const name_slice = switch (parsed_source.kind) {
            .npm => parsed_source.name,
            .git => std.fs.path.basename(std.mem.trimEnd(u8, parsed_source.repository_path.?, "/\\")),
            .local => std.fs.path.basename(std.mem.trimEnd(u8, path, "/\\")),
        };
        if (name_slice.len == 0) {
            gpa.free(path);
            continue;
        }
        const name = try gpa.dupe(u8, name_slice);
        errdefer gpa.free(name);
        const owned_source = try gpa.dupe(u8, source);
        errdefer gpa.free(owned_source);

        var autoload = true;
        var extensions: ?[]const []const u8 = null;
        var skills: ?[]const []const u8 = null;
        var prompts: ?[]const []const u8 = null;
        var themes: ?[]const []const u8 = null;
        if (entry == .object) {
            if (entry.object.get("autoload")) |value| {
                if (value == .bool) autoload = value.bool;
            }
            extensions = try parsePatternField(gpa, entry.object, "extensions");
            errdefer freeOptionalPatterns(gpa, extensions);
            skills = try parsePatternField(gpa, entry.object, "skills");
            errdefer freeOptionalPatterns(gpa, skills);
            prompts = try parsePatternField(gpa, entry.object, "prompts");
            errdefer freeOptionalPatterns(gpa, prompts);
            themes = try parsePatternField(gpa, entry.object, "themes");
            errdefer freeOptionalPatterns(gpa, themes);
        }
        try result.append(gpa, .{
            .name = name,
            .path = path,
            .scope = scope,
            .source = owned_source,
            .autoload = autoload,
            .extensions = extensions,
            .skills = skills,
            .prompts = prompts,
            .themes = themes,
        });
    }
    return try result.toOwnedSlice(gpa);
}

fn listLegacySettings(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    scope: Scope,
) ![]Package {
    const settings_path = try std.fs.path.join(gpa, &.{ registry_dir, "settings.json" });
    defer gpa.free(settings_path);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, settings_path, gpa, .limited(8 * 1024 * 1024)) catch
        return try gpa.alloc(Package, 0);
    defer gpa.free(raw);
    return parseLegacySettingsPackages(gpa, raw, registry_dir, scope);
}

fn listAt(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    scope: Scope,
) ![]Package {
    const path = try packagesJsonPath(gpa, registry_dir);
    defer gpa.free(path);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024)) catch {
        return listLegacySettings(gpa, io, registry_dir, scope);
    };
    defer gpa.free(raw);
    return try parsePackages(gpa, raw, scope);
}

pub fn list(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8) ![]Package {
    return listAt(gpa, io, agent_dir, .user);
}

/// Read one persistent package scope. Project storage is inaccessible unless
/// the caller has already resolved project trust for this process.
pub fn listScope(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    scope: Scope,
    project_trusted: bool,
) ![]Package {
    if (scope == .project and !project_trusted) return error.ProjectNotTrusted;
    if (scope == .temporary) return try gpa.alloc(Package, 0);
    const root = try scopeRoot(gpa, agent_dir, cwd, scope);
    defer gpa.free(root);
    return listAt(gpa, io, root, scope);
}

fn packageIdentity(gpa: std.mem.Allocator, package: Package) ![]u8 {
    const source = package.source orelse package.path;
    var parsed = package_source.parse(gpa, source) catch {
        return try std.fmt.allocPrint(gpa, "local:{s}", .{package.path});
    };
    defer parsed.deinit();
    return switch (parsed.kind) {
        .npm => try std.fmt.allocPrint(gpa, "npm:{s}", .{parsed.name}),
        .git => try std.fmt.allocPrint(gpa, "git:{s}/{s}", .{ parsed.host.?, parsed.repository_path.? }),
        .local => try std.fmt.allocPrint(gpa, "local:{s}", .{package.path}),
    };
}

fn samePackageIdentity(gpa: std.mem.Allocator, left: Package, right: Package) !bool {
    const left_identity = try packageIdentity(gpa, left);
    defer gpa.free(left_identity);
    const right_identity = try packageIdentity(gpa, right);
    defer gpa.free(right_identity);
    return std.mem.eql(u8, left_identity, right_identity);
}

pub fn sameIdentity(gpa: std.mem.Allocator, left: Package, right: Package) !bool {
    return samePackageIdentity(gpa, left, right);
}

fn appendOwnedPackages(gpa: std.mem.Allocator, target: *std.ArrayList(Package), packages: []const Package) !void {
    for (packages) |package| try target.append(gpa, try clonePackage(gpa, package));
}

/// Resolve configured persistent scopes in original precedence order.
///
/// Project packages win collisions over user packages. A project record with
/// `autoload=false` is an explicit delta over the corresponding user package,
/// so both records are retained (project delta first, user base second).
/// Untrusted project storage is never opened.
pub fn listConfigured(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    project_trusted: bool,
) ![]Package {
    var result: std.ArrayList(Package) = .empty;
    errdefer {
        for (result.items) |*package| package.deinit(gpa);
        result.deinit(gpa);
    }

    if (project_trusted) {
        const project = try listScope(gpa, io, agent_dir, cwd, .project, true);
        defer {
            for (project) |*package| package.deinit(gpa);
            gpa.free(project);
        }
        try appendOwnedPackages(gpa, &result, project);
    }

    const user = try listScope(gpa, io, agent_dir, cwd, .user, project_trusted);
    defer {
        for (user) |*package| package.deinit(gpa);
        gpa.free(user);
    }
    for (user) |package| {
        var matching_project: ?usize = null;
        for (result.items, 0..) |existing, index| {
            if (existing.scope != .project) continue;
            if (try samePackageIdentity(gpa, existing, package)) {
                matching_project = index;
                break;
            }
        }
        if (matching_project) |index| {
            if (!result.items[index].autoload) {
                // A project autoload=false record is a filter delta over the
                // user installation, not a second package installation.
                gpa.free(result.items[index].path);
                result.items[index].path = try gpa.dupe(u8, package.path);
                try result.append(gpa, try clonePackage(gpa, package));
            }
            continue;
        }
        try result.append(gpa, try clonePackage(gpa, package));
    }
    return try result.toOwnedSlice(gpa);
}

fn parsePatternField(gpa: std.mem.Allocator, object: std.json.ObjectMap, field: []const u8) !?[]const []const u8 {
    const value = object.get(field) orelse return null;
    if (value != .array) return null;
    for (value.array.items) |entry| if (entry != .string) return null;

    var patterns = try gpa.alloc([]const u8, value.array.items.len);
    var initialized: usize = 0;
    errdefer {
        for (patterns[0..initialized]) |item| gpa.free(item);
        gpa.free(patterns);
    }
    for (value.array.items, 0..) |entry, index| {
        patterns[index] = try gpa.dupe(u8, entry.string);
        initialized += 1;
    }
    return patterns;
}

fn parsePackages(gpa: std.mem.Allocator, raw: []const u8, scope: Scope) ![]Package {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return try gpa.alloc(Package, 0);

    var list_out: std.ArrayList(Package) = .empty;
    errdefer {
        for (list_out.items) |*p| p.deinit(gpa);
        list_out.deinit(gpa);
    }
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const pth = item.object.get("path") orelse continue;
        if (pth != .string or pth.string.len == 0) continue;
        const name_value = item.object.get("name");
        const derived_name = std.fs.path.basename(std.mem.trimEnd(u8, pth.string, "/\\"));
        const name = if (name_value != null and name_value.? == .string and name_value.?.string.len > 0)
            name_value.?.string
        else
            derived_name;
        if (name.len == 0) continue;

        const owned_name = try gpa.dupe(u8, name);
        errdefer gpa.free(owned_name);
        const owned_path = try gpa.dupe(u8, pth.string);
        errdefer gpa.free(owned_path);
        const source = if (item.object.get("source")) |value|
            if (value == .string and value.string.len > 0) try gpa.dupe(u8, value.string) else null
        else
            null;
        errdefer if (source) |value| gpa.free(value);
        const extensions = try parsePatternField(gpa, item.object, "extensions");
        errdefer freeOptionalPatterns(gpa, extensions);
        const skills = try parsePatternField(gpa, item.object, "skills");
        errdefer freeOptionalPatterns(gpa, skills);
        const prompts = try parsePatternField(gpa, item.object, "prompts");
        errdefer freeOptionalPatterns(gpa, prompts);
        const themes = try parsePatternField(gpa, item.object, "themes");
        errdefer freeOptionalPatterns(gpa, themes);

        var autoload = true;
        if (item.object.get("autoload")) |value| {
            if (value == .bool) autoload = value.bool;
        }
        try list_out.append(gpa, .{
            .name = owned_name,
            .path = owned_path,
            .scope = scope,
            .source = source,
            .autoload = autoload,
            .extensions = extensions,
            .skills = skills,
            .prompts = prompts,
            .themes = themes,
        });
    }
    return try list_out.toOwnedSlice(gpa);
}

fn writePatternField(writer: *std.Io.Writer, field: []const u8, patterns: ?[]const []const u8) !void {
    const items = patterns orelse return;
    try writer.writeByte(',');
    try std.json.Stringify.value(field, .{}, writer);
    try writer.writeByte(':');
    try writer.writeByte('[');
    for (items, 0..) |item, index| {
        if (index > 0) try writer.writeByte(',');
        try std.json.Stringify.value(item, .{}, writer);
    }
    try writer.writeByte(']');
}

fn writePackagesFile(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, packages: []const Package) !void {
    try std.Io.Dir.cwd().createDirPath(io, agent_dir);
    var aw: std.Io.Writer.Allocating = .init(gpa);
    defer aw.deinit();
    try aw.writer.writeAll("[");
    for (packages, 0..) |p, i| {
        if (i > 0) try aw.writer.writeAll(",");
        try aw.writer.writeAll("{\"name\":");
        try std.json.Stringify.value(p.name, .{}, &aw.writer);
        try aw.writer.writeAll(",\"path\":");
        try std.json.Stringify.value(p.path, .{}, &aw.writer);
        if (p.source) |source| {
            try aw.writer.writeAll(",\"source\":");
            try std.json.Stringify.value(source, .{}, &aw.writer);
        }
        if (!p.autoload) try aw.writer.writeAll(",\"autoload\":false");
        try writePatternField(&aw.writer, "extensions", p.extensions);
        try writePatternField(&aw.writer, "skills", p.skills);
        try writePatternField(&aw.writer, "prompts", p.prompts);
        try writePatternField(&aw.writer, "themes", p.themes);
        try aw.writer.writeAll("}");
    }
    try aw.writer.writeAll("]");
    try aw.writer.writeByte('\n');
    const path = try packagesJsonPath(gpa, agent_dir);
    defer gpa.free(path);
    try atomicWriteBytes(io, path, aw.written());
}

fn verifyPackagesFile(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    expected_count: usize,
) !void {
    const path = try packagesJsonPath(gpa, agent_dir);
    defer gpa.free(path);
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(8 * 1024 * 1024));
    defer gpa.free(raw);
    const parsed = try parsePackages(gpa, raw, .user);
    defer {
        for (parsed) |*package| package.deinit(gpa);
        gpa.free(parsed);
    }
    if (parsed.len != expected_count) return error.PackageRegistryVerificationFailed;
}

fn legacySettingsPackagesAreArray(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
) !bool {
    const settings_path = try std.fs.path.join(gpa, &.{ registry_dir, "settings.json" });
    defer gpa.free(settings_path);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, settings_path, gpa, .limited(8 * 1024 * 1024)) catch return false;
    defer gpa.free(raw);
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .object) return false;
    const value = parsed.value.object.get("packages") orelse return false;
    return value == .array;
}

fn cleanupLegacySettingsPackages(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
) !bool {
    const settings_path = try std.fs.path.join(gpa, &.{ registry_dir, "settings.json" });
    defer gpa.free(settings_path);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, settings_path, gpa, .limited(8 * 1024 * 1024)) catch return false;
    defer gpa.free(raw);
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{ .allocate = .alloc_always }) catch return false;
    defer parsed.deinit();
    if (parsed.value != .object) return false;
    const packages_value = parsed.value.object.get("packages") orelse return false;
    if (packages_value != .array) return false;
    if (!parsed.value.object.orderedRemove("packages")) return false;

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try std.json.Stringify.value(parsed.value, .{ .whitespace = .indent_2 }, &out.writer);
    try out.writer.writeByte('\n');
    try atomicWriteBytes(io, settings_path, out.written());
    return true;
}

fn savePackages(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, packages: []const Package) !void {
    try writePackagesFile(gpa, io, agent_dir, packages);
    try verifyPackagesFile(gpa, io, agent_dir, packages.len);
    // The native registry is authoritative only after it has been atomically
    // persisted and re-read successfully. Legacy cleanup is deliberately
    // best-effort here: a cleanup failure leaves a harmless duplicate source
    // instead of failing a completed install or removal.
    _ = cleanupLegacySettingsPackages(gpa, io, agent_dir) catch false;
}

/// Atomically edit one persistent package scope under the package-operation
/// lock. The current registry is read only after the lock is owned, preventing
/// two resource selectors from performing stale read/modify/write cycles that
/// silently discard one another's changes.
/// Execute an arbitrary configuration mutation while holding the same stable
/// per-scope advisory lock used by package install/update/remove/configure.
/// The callback receives the persistent scope root (`agent_dir` or `.pi`) and
/// runs entirely while the lock is owned, so settings-backed resource edits
/// cannot race package-registry edits or other configuration selectors.
pub fn withScopeConfigurationLock(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    scope: Scope,
    project_trusted: bool,
    context: anytype,
    comptime callback: anytype,
) !void {
    if (scope == .temporary) return error.TemporaryPackageNotPersistent;
    if (scope == .project and !project_trusted) return error.ProjectNotTrusted;
    const registry_dir = try scopeRoot(gpa, agent_dir, cwd, scope);
    defer gpa.free(registry_dir);
    var operation_lock = try OperationLock.acquire(gpa, io, registry_dir, .configure);
    defer operation_lock.deinit();
    try callback(gpa, io, registry_dir, context);
}

pub fn updateScopeConfiguration(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    scope: Scope,
    project_trusted: bool,
    context: anytype,
    comptime mutate: anytype,
) !void {
    if (scope == .temporary) return error.TemporaryPackageNotPersistent;
    if (scope == .project and !project_trusted) return error.ProjectNotTrusted;
    const registry_dir = try scopeRoot(gpa, agent_dir, cwd, scope);
    defer gpa.free(registry_dir);
    var operation_lock = try OperationLock.acquire(gpa, io, registry_dir, .configure);
    defer operation_lock.deinit();

    var configured = try listAt(gpa, io, registry_dir, scope);
    defer {
        for (configured) |*package| package.deinit(gpa);
        gpa.free(configured);
    }
    try mutate(gpa, &configured, context);
    try savePackages(gpa, io, registry_dir, configured);
}

fn validateExistingPackagesFile(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
) !void {
    const path = try packagesJsonPath(gpa, registry_dir);
    defer gpa.free(path);
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(8 * 1024 * 1024));
    defer gpa.free(raw);
    const parsed = try parsePackages(gpa, raw, .user);
    defer {
        for (parsed) |*package| package.deinit(gpa);
        gpa.free(parsed);
    }
}

fn migrateLegacyPackagesAt(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    scope: Scope,
    result: *RepairResult,
) !void {
    if (!try legacySettingsPackagesAreArray(gpa, io, registry_dir)) return;
    const native_path = try packagesJsonPath(gpa, registry_dir);
    defer gpa.free(native_path);
    if (pathExists(io, native_path)) {
        // Never delete the historical source unless the native registry is
        // independently readable. This leaves recovery possible if a prior
        // write was truncated or externally corrupted.
        try validateExistingPackagesFile(gpa, io, registry_dir);
        result.cleaned_legacy_settings = try cleanupLegacySettingsPackages(gpa, io, registry_dir);
        return;
    }

    const legacy = try listLegacySettings(gpa, io, registry_dir, scope);
    defer {
        for (legacy) |*package| package.deinit(gpa);
        gpa.free(legacy);
    }
    try writePackagesFile(gpa, io, registry_dir, legacy);
    try verifyPackagesFile(gpa, io, registry_dir, legacy.len);
    result.migrated_legacy_packages = legacy.len;
    result.cleaned_legacy_settings = try cleanupLegacySettingsPackages(gpa, io, registry_dir);
}

const command_timeout_seconds: i64 = 180;

pub const RuntimeOptions = struct {
    offline: bool = false,
    /// argv-style npm-compatible command, for example
    /// { "mise", "exec", "node@20", "--", "npm" }.
    npm_command: ?[]const []const u8 = null,
};

const PackageManagerKind = enum { npm, pnpm, bun, other };

fn packageManagerKind(command: ?[]const []const u8) !PackageManagerKind {
    const configured = command orelse return .npm;
    if (configured.len == 0 or configured[0].len == 0) return error.InvalidNpmCommand;
    var manager = configured[0];
    var index = configured.len;
    while (index > 0) {
        index -= 1;
        if (std.mem.eql(u8, configured[index], "--") and index + 1 < configured.len) {
            manager = configured[index + 1];
            break;
        }
    }
    const separator_index = std.mem.lastIndexOfAny(u8, manager, "/\\");
    var basename = if (separator_index) |separator| manager[separator + 1 ..] else manager;
    inline for (.{ ".cmd", ".exe" }) |suffix| {
        if (basename.len > suffix.len and std.ascii.endsWithIgnoreCase(basename, suffix)) {
            basename = basename[0 .. basename.len - suffix.len];
            break;
        }
    }
    if (std.ascii.eqlIgnoreCase(basename, "npm")) return .npm;
    if (std.ascii.eqlIgnoreCase(basename, "pnpm")) return .pnpm;
    if (std.ascii.eqlIgnoreCase(basename, "bun")) return .bun;
    return .other;
}

fn runNpmExternal(
    gpa: std.mem.Allocator,
    io: Io,
    command: ?[]const []const u8,
    args: []const []const u8,
    cwd: []const u8,
) !void {
    const default_command = [_][]const u8{"npm"};
    const prefix: []const []const u8 = command orelse default_command[0..];
    if (prefix.len == 0 or prefix[0].len == 0) return error.InvalidNpmCommand;
    const argv = try gpa.alloc([]const u8, prefix.len + args.len);
    defer gpa.free(argv);
    @memcpy(argv[0..prefix.len], prefix);
    @memcpy(argv[prefix.len..], args);
    try runExternal(gpa, io, argv, cwd);
}

fn runExternal(
    gpa: std.mem.Allocator,
    io: Io,
    argv: []const []const u8,
    cwd: []const u8,
) !void {
    const result = std.process.run(gpa, io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .stdout_limit = .limited(2 * 1024 * 1024),
        .stderr_limit = .limited(2 * 1024 * 1024),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(command_timeout_seconds), .clock = .real } },
    }) catch |err| switch (err) {
        error.Timeout => return error.PackageCommandTimedOut,
        else => return error.PackageCommandFailed,
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    const succeeded = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!succeeded) return error.PackageCommandFailed;
}

fn packageNameAtPath(gpa: std.mem.Allocator, io: Io, path: []const u8, fallback: []const u8) ![]u8 {
    const package_json = try std.fs.path.join(gpa, &.{ path, "package.json" });
    defer gpa.free(package_json);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, package_json, gpa, .limited(1024 * 1024)) catch return try gpa.dupe(u8, fallback);
    defer gpa.free(raw);
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return try gpa.dupe(u8, fallback);
    defer parsed.deinit();
    if (parsed.value == .object) {
        if (parsed.value.object.get("name")) |name| {
            if (name == .string and name.string.len > 0) return try gpa.dupe(u8, name.string);
        }
    }
    return try gpa.dupe(u8, fallback);
}

fn persistResolvedPackage(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    scope: Scope,
    name: []const u8,
    path: []const u8,
    source: []const u8,
) !Package {
    const packages = try listAt(gpa, io, registry_dir, scope);
    defer {
        for (packages) |*package| package.deinit(gpa);
        gpa.free(packages);
    }

    var new_list: std.ArrayList(Package) = .empty;
    errdefer {
        for (new_list.items) |*package| package.deinit(gpa);
        new_list.deinit(gpa);
    }
    var previous: ?Package = null;
    for (packages) |package| {
        if (std.mem.eql(u8, package.name, name)) {
            previous = package;
            continue;
        }
        try new_list.append(gpa, try clonePackage(gpa, package));
    }

    const installed: Package = .{
        .name = try gpa.dupe(u8, name),
        .path = try gpa.dupe(u8, path),
        .scope = scope,
        .source = try gpa.dupe(u8, source),
        .autoload = if (previous) |package| package.autoload else true,
        .extensions = if (previous) |package| try cloneOptionalPatterns(gpa, package.extensions) else null,
        .skills = if (previous) |package| try cloneOptionalPatterns(gpa, package.skills) else null,
        .prompts = if (previous) |package| try cloneOptionalPatterns(gpa, package.prompts) else null,
        .themes = if (previous) |package| try cloneOptionalPatterns(gpa, package.themes) else null,
    };
    errdefer {
        var mutable = installed;
        mutable.deinit(gpa);
    }
    try new_list.append(gpa, try clonePackage(gpa, installed));
    try savePackages(gpa, io, registry_dir, new_list.items);
    for (new_list.items) |*package| package.deinit(gpa);
    new_list.deinit(gpa);
    return installed;
}

fn makeTransientPackage(
    gpa: std.mem.Allocator,
    name: []const u8,
    path: []const u8,
    source: []const u8,
) !Package {
    return .{
        .name = try gpa.dupe(u8, name),
        .path = try gpa.dupe(u8, path),
        .scope = .temporary,
        .source = try gpa.dupe(u8, source),
    };
}

fn finishResolvedPackage(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    scope: Scope,
    name: []const u8,
    path: []const u8,
    source: []const u8,
) !Package {
    if (scope == .temporary) return makeTransientPackage(gpa, name, path, source);
    return persistResolvedPackage(gpa, io, registry_dir, scope, name, path, source);
}

fn installLocal(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    scope: Scope,
    parsed: package_source.Source,
    cwd: []const u8,
) !Package {
    const absolute = if (std.fs.path.isAbsolute(parsed.spec))
        try std.fs.path.resolve(gpa, &.{parsed.spec})
    else
        try std.fs.path.resolve(gpa, &.{ cwd, parsed.spec });
    defer gpa.free(absolute);
    const stat = std.Io.Dir.cwd().statFile(io, absolute, .{}) catch return error.PackageNotFound;
    if (stat.kind != .directory and stat.kind != .file) return error.PackageNotFound;

    const fallback = std.fs.path.basename(std.mem.trimEnd(u8, absolute, "/\\"));
    const name = if (stat.kind == .directory)
        try packageNameAtPath(gpa, io, absolute, fallback)
    else
        try gpa.dupe(u8, fallback);
    defer gpa.free(name);
    const normalized_source = try std.fmt.allocPrint(gpa, "path:{s}", .{absolute});
    defer gpa.free(normalized_source);
    return finishResolvedPackage(gpa, io, registry_dir, scope, name, absolute, normalized_source);
}

fn ensureNpmProject(gpa: std.mem.Allocator, io: Io, root: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(io, root);
    const package_json = try std.fs.path.join(gpa, &.{ root, "package.json" });
    defer gpa.free(package_json);
    if (std.Io.Dir.cwd().statFile(io, package_json, .{})) |_| {} else |_| {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = package_json, .data = "{\"name\":\"pi-zig-packages\",\"private\":true}\n" });
    }
    const gitignore = try std.fs.path.join(gpa, &.{ root, ".gitignore" });
    defer gpa.free(gitignore);
    if (std.Io.Dir.cwd().statFile(io, gitignore, .{})) |_| {} else |_| {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = gitignore, .data = "*\n!.gitignore\n" });
    }
}

fn installNpm(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    scope: Scope,
    parsed: package_source.Source,
    options: RuntimeOptions,
) !Package {
    if (options.offline) return error.PackageNetworkDisabled;
    const root = try std.fs.path.join(gpa, &.{ registry_dir, "npm" });
    defer gpa.free(root);
    try ensureNpmProject(gpa, io, root);
    const manager = try packageManagerKind(options.npm_command);
    switch (manager) {
        .bun => {
            const args = [_][]const u8{ "install", parsed.spec, "--cwd", root, "--omit=peer" };
            try runNpmExternal(gpa, io, options.npm_command, &args, root);
        },
        .pnpm => {
            const args = [_][]const u8{
                "install",
                parsed.spec,
                "--prefix",
                root,
                "--config.auto-install-peers=false",
                "--config.strict-peer-dependencies=false",
                "--config.strict-dep-builds=false",
            };
            try runNpmExternal(gpa, io, options.npm_command, &args, root);
        },
        .npm, .other => {
            const args = [_][]const u8{ "install", parsed.spec, "--prefix", root, "--legacy-peer-deps" };
            try runNpmExternal(gpa, io, options.npm_command, &args, root);
        },
    }

    const installed_path = try std.fs.path.join(gpa, &.{ root, "node_modules", parsed.name });
    defer gpa.free(installed_path);
    const stat = std.Io.Dir.cwd().statFile(io, installed_path, .{}) catch return error.PackageNotFoundAfterInstall;
    if (stat.kind != .directory) return error.PackageNotFoundAfterInstall;
    const name = try packageNameAtPath(gpa, io, installed_path, parsed.name);
    defer gpa.free(name);
    return finishResolvedPackage(gpa, io, registry_dir, scope, name, installed_path, parsed.original);
}

var package_temp_counter: std.atomic.Value(u64) = .init(1);

fn uniqueSiblingPath(gpa: std.mem.Allocator, target: []const u8, label: []const u8) ![]u8 {
    const id = package_temp_counter.fetchAdd(1, .monotonic);
    return std.fmt.allocPrint(gpa, "{s}.{s}-{x}", .{ target, label, id });
}

fn installGitDependencies(
    gpa: std.mem.Allocator,
    io: Io,
    path: []const u8,
    npm_command: ?[]const []const u8,
) !void {
    const package_json = try std.fs.path.join(gpa, &.{ path, "package.json" });
    defer gpa.free(package_json);
    const stat = std.Io.Dir.cwd().statFile(io, package_json, .{}) catch return;
    if (stat.kind != .file) return;
    if (npm_command != null) {
        const args = [_][]const u8{"install"};
        try runNpmExternal(gpa, io, npm_command, &args, path);
    } else {
        const args = [_][]const u8{ "install", "--omit=dev", "--no-audit", "--no-fund" };
        try runNpmExternal(gpa, io, null, &args, path);
    }
}

fn installGit(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    scope: Scope,
    parsed: package_source.Source,
    options: RuntimeOptions,
) !Package {
    if (options.offline) return error.PackageNetworkDisabled;
    const target = try std.fs.path.join(gpa, &.{ registry_dir, "git", parsed.host.?, parsed.repository_path.? });
    defer gpa.free(target);
    const parent = std.fs.path.dirname(target) orelse return error.InvalidGitPackageSource;
    try std.Io.Dir.cwd().createDirPath(io, parent);

    // Complete or roll back a prior clone-and-swap before starting another
    // update for the same checkout. The marker is written only after a fresh
    // checkout and its dependencies are fully prepared.
    var prior_repair: RepairResult = .{};
    try recoverGitTarget(gpa, io, target, &prior_repair);

    const temporary = try uniqueSiblingPath(gpa, target, "tmp");
    defer gpa.free(temporary);
    std.Io.Dir.cwd().deleteTree(io, temporary) catch {};
    errdefer std.Io.Dir.cwd().deleteTree(io, temporary) catch {};
    const clone_argv = [_][]const u8{ "git", "clone", "--recurse-submodules", "--", parsed.spec, temporary };
    try runExternal(gpa, io, &clone_argv, parent);
    if (parsed.git_ref) |git_ref| {
        const checkout_argv = [_][]const u8{ "git", "-C", temporary, "checkout", "--detach", git_ref };
        try runExternal(gpa, io, &checkout_argv, parent);
    }
    try installGitDependencies(gpa, io, temporary, options.npm_command);

    const fallback = std.fs.path.basename(parsed.repository_path.?);
    const name = try packageNameAtPath(gpa, io, temporary, fallback);
    defer gpa.free(name);

    const backup = try uniqueSiblingPath(gpa, target, "old");
    defer gpa.free(backup);
    std.Io.Dir.cwd().deleteTree(io, backup) catch {};
    const marker_path = try gitUpdateMarkerPath(gpa, target);
    defer gpa.free(marker_path);
    try writeGitRepairMarker(gpa, io, marker_path, target, temporary, backup);

    var had_existing = false;
    if (std.Io.Dir.cwd().statFile(io, target, .{})) |_| {
        std.Io.Dir.renameAbsolute(target, backup, io) catch {
            var recovery: RepairResult = .{};
            recoverGitRepairMarker(gpa, io, marker_path, &recovery) catch {};
            return error.PackageInstallCommitFailed;
        };
        had_existing = true;
    } else |_| {}
    std.Io.Dir.renameAbsolute(temporary, target, io) catch {
        if (had_existing) std.Io.Dir.renameAbsolute(backup, target, io) catch {};
        var recovery: RepairResult = .{};
        recoverGitRepairMarker(gpa, io, marker_path, &recovery) catch {};
        return error.PackageInstallCommitFailed;
    };

    if (had_existing) {
        // A failed backup cleanup is recoverable: retain the marker so the next
        // package operation or explicit repair can remove the stale tree.
        if (removeAnyPath(io, backup)) |removed| {
            _ = removed;
            std.Io.Dir.cwd().deleteFile(io, marker_path) catch {};
        } else |_| {}
    } else {
        std.Io.Dir.cwd().deleteFile(io, marker_path) catch {};
    }
    return finishResolvedPackage(gpa, io, registry_dir, scope, name, target, parsed.original);
}

/// Install a local, npm, or Git package. `offline` is a hard network gate for
/// managed npm/Git sources while local packages remain available.
pub fn installAdvanced(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    source: []const u8,
    cwd: []const u8,
    offline: bool,
) !Package {
    return installScopedWithOptions(gpa, io, agent_dir, cwd, source, .user, true, .{ .offline = offline });
}

/// Install a package into the requested scope. Project writes require an
/// explicit trusted-project decision. Temporary packages are cached below the
/// agent-private temporary root but are never added to a persistent registry.
pub fn installScoped(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    source: []const u8,
    scope: Scope,
    project_trusted: bool,
    offline: bool,
) !Package {
    return installScopedWithOptions(gpa, io, agent_dir, cwd, source, scope, project_trusted, .{ .offline = offline });
}

pub fn installScopedWithOptions(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    source: []const u8,
    scope: Scope,
    project_trusted: bool,
    options: RuntimeOptions,
) !Package {
    if (scope == .project and !project_trusted) return error.ProjectNotTrusted;
    const registry_dir = try scopeRoot(gpa, agent_dir, cwd, scope);
    defer gpa.free(registry_dir);
    var operation_lock = try OperationLock.acquire(gpa, io, registry_dir, .install);
    defer operation_lock.deinit();
    return installScopedUnlocked(gpa, io, registry_dir, cwd, source, scope, options);
}

fn installScopedUnlocked(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    cwd: []const u8,
    source: []const u8,
    scope: Scope,
    options: RuntimeOptions,
) !Package {
    var parsed = try package_source.parse(gpa, source);
    defer parsed.deinit();
    return switch (parsed.kind) {
        .local => installLocal(gpa, io, registry_dir, scope, parsed, cwd),
        .npm => installNpm(gpa, io, registry_dir, scope, parsed, options),
        .git => installGit(gpa, io, registry_dir, scope, parsed, options),
    };
}

/// Backwards-compatible installation entry point. Network sources are enabled;
/// callers with an environment map should prefer installAdvanced and honor
/// PI_OFFLINE explicitly.
pub fn install(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, source: []const u8, cwd: []const u8) !Package {
    return installAdvanced(gpa, io, agent_dir, source, cwd, false);
}

pub const UpdateResult = struct {
    matched: usize = 0,
    updated: usize = 0,
    skipped_local: usize = 0,
    skipped_pinned: usize = 0,

    pub fn add(self: *UpdateResult, other: UpdateResult) void {
        self.matched += other.matched;
        self.updated += other.updated;
        self.skipped_local += other.skipped_local;
        self.skipped_pinned += other.skipped_pinned;
    }
};

fn packageMatches(package: Package, query: []const u8) bool {
    if (std.mem.eql(u8, package.name, query) or std.mem.eql(u8, package.path, query)) return true;
    if (package.source) |source| if (std.mem.eql(u8, source, query)) return true;
    return false;
}

/// Update one configured package (matched by name, source, or installed path)
/// or all configured packages when `query` is null. Local paths and exact npm
/// versions are intentionally stable. Git refs are reconciled because the
/// configured ref itself may have moved or changed between installs.
pub fn update(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    query: ?[]const u8,
    cwd: []const u8,
    offline: bool,
) !UpdateResult {
    return updateScopedWithOptions(gpa, io, agent_dir, cwd, query, .user, true, .{ .offline = offline });
}

pub fn updateScoped(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    query: ?[]const u8,
    scope: Scope,
    project_trusted: bool,
    offline: bool,
) !UpdateResult {
    return updateScopedWithOptions(gpa, io, agent_dir, cwd, query, scope, project_trusted, .{ .offline = offline });
}

pub fn updateScopedWithOptions(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    query: ?[]const u8,
    scope: Scope,
    project_trusted: bool,
    options: RuntimeOptions,
) !UpdateResult {
    if (scope == .temporary) return error.TemporaryPackageNotPersistent;
    if (scope == .project and !project_trusted) return error.ProjectNotTrusted;
    const registry_dir = try scopeRoot(gpa, agent_dir, cwd, scope);
    defer gpa.free(registry_dir);
    var operation_lock = try OperationLock.acquire(gpa, io, registry_dir, .update);
    defer operation_lock.deinit();
    const installed = try listAt(gpa, io, registry_dir, scope);
    defer {
        for (installed) |*package| package.deinit(gpa);
        gpa.free(installed);
    }

    var sources: std.ArrayList([]u8) = .empty;
    defer {
        for (sources.items) |source| gpa.free(source);
        sources.deinit(gpa);
    }
    var result: UpdateResult = .{};
    for (installed) |package| {
        if (query) |value| if (!packageMatches(package, value)) continue;
        result.matched += 1;
        const source = package.source orelse package.path;
        var parsed = try package_source.parse(gpa, source);
        defer parsed.deinit();
        switch (parsed.kind) {
            .local => result.skipped_local += 1,
            .npm => if (parsed.pinned) {
                result.skipped_pinned += 1;
            } else if (!options.offline) {
                try sources.append(gpa, try gpa.dupe(u8, source));
            },
            .git => if (!options.offline) try sources.append(gpa, try gpa.dupe(u8, source)),
        }
    }
    if (query != null and result.matched == 0) return error.PackageNotFound;
    if (options.offline) return result;

    // Reinstallation is transactional at the individual package level and
    // preserves the existing resource filters in persistResolvedPackage().
    for (sources.items) |source| {
        var refreshed = try installScopedUnlocked(gpa, io, registry_dir, cwd, source, scope, options);
        refreshed.deinit(gpa);
        result.updated += 1;
    }
    return result;
}

fn normalizedPath(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.path.resolve(gpa, &.{path});
}

fn pathInside(root: []const u8, candidate: []const u8) bool {
    if (std.mem.eql(u8, root, candidate)) return true;
    if (!std.mem.startsWith(u8, candidate, root) or candidate.len <= root.len) return false;
    return std.fs.path.isSep(candidate[root.len]);
}

fn pruneEmptyParents(io: Io, target: []const u8, stop_at: []const u8) void {
    var current = std.fs.path.dirname(target) orelse return;
    while (current.len > stop_at.len and pathInside(stop_at, current)) {
        var dir = std.Io.Dir.openDirAbsolute(io, current, .{ .iterate = true }) catch return;
        var iterator = dir.iterate();
        const has_entry = iterator.next(io) catch {
            dir.close(io);
            return;
        };
        dir.close(io);
        if (has_entry != null) return;
        std.Io.Dir.cwd().deleteDir(io, current) catch return;
        current = std.fs.path.dirname(current) orelse return;
    }
}

fn removeManagedPackage(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    package: Package,
    options: RuntimeOptions,
) !void {
    const source = package.source orelse return;
    var parsed = try package_source.parse(gpa, source);
    defer parsed.deinit();
    switch (parsed.kind) {
        .local => return,
        .npm => {
            const root_raw = try std.fs.path.join(gpa, &.{ registry_dir, "npm" });
            defer gpa.free(root_raw);
            const root = try normalizedPath(gpa, root_raw);
            defer gpa.free(root);
            const candidate = try normalizedPath(gpa, package.path);
            defer gpa.free(candidate);
            if (!pathInside(root, candidate)) return error.UnsafeManagedPackagePath;
            if (std.Io.Dir.cwd().statFile(io, root, .{})) |_| {
                const manager = try packageManagerKind(options.npm_command);
                switch (manager) {
                    .bun => {
                        const args = [_][]const u8{ "uninstall", parsed.name, "--cwd", root };
                        try runNpmExternal(gpa, io, options.npm_command, &args, root);
                    },
                    .pnpm => {
                        const args = [_][]const u8{ "uninstall", parsed.name, "--prefix", root };
                        try runNpmExternal(gpa, io, options.npm_command, &args, root);
                    },
                    .npm, .other => {
                        const args = [_][]const u8{ "uninstall", parsed.name, "--prefix", root, "--no-audit", "--no-fund", "--legacy-peer-deps" };
                        try runNpmExternal(gpa, io, options.npm_command, &args, root);
                    },
                }
            } else |_| {}
        },
        .git => {
            const root_raw = try std.fs.path.join(gpa, &.{ registry_dir, "git" });
            defer gpa.free(root_raw);
            const expected_raw = try std.fs.path.join(gpa, &.{ root_raw, parsed.host.?, parsed.repository_path.? });
            defer gpa.free(expected_raw);
            const root = try normalizedPath(gpa, root_raw);
            defer gpa.free(root);
            const expected = try normalizedPath(gpa, expected_raw);
            defer gpa.free(expected);
            const candidate = try normalizedPath(gpa, package.path);
            defer gpa.free(candidate);
            if (!std.mem.eql(u8, expected, candidate) or !pathInside(root, candidate)) return error.UnsafeManagedPackagePath;
            var repair_result: RepairResult = .{};
            try recoverGitTarget(gpa, io, expected, &repair_result);
            if (std.Io.Dir.cwd().statFile(io, candidate, .{})) |_| {
                try std.Io.Dir.cwd().deleteTree(io, candidate);
            } else |_| {}
            const marker_path = try gitUpdateMarkerPath(gpa, expected);
            defer gpa.free(marker_path);
            std.Io.Dir.cwd().deleteFile(io, marker_path) catch {};
            pruneEmptyParents(io, candidate, root);
        },
    }
}

pub fn remove(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, name: []const u8) !bool {
    return removeScopedWithOptions(gpa, io, agent_dir, ".", name, .user, true, .{});
}

pub fn removeScoped(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    name: []const u8,
    scope: Scope,
    project_trusted: bool,
) !bool {
    return removeScopedWithOptions(gpa, io, agent_dir, cwd, name, scope, project_trusted, .{});
}

pub fn removeScopedWithOptions(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    name: []const u8,
    scope: Scope,
    project_trusted: bool,
    options: RuntimeOptions,
) !bool {
    if (scope == .temporary) return error.TemporaryPackageNotPersistent;
    if (scope == .project and !project_trusted) return error.ProjectNotTrusted;
    const registry_dir = try scopeRoot(gpa, agent_dir, cwd, scope);
    defer gpa.free(registry_dir);
    var operation_lock = try OperationLock.acquire(gpa, io, registry_dir, .remove);
    defer operation_lock.deinit();
    const installed = try listAt(gpa, io, registry_dir, scope);
    defer {
        for (installed) |*package| package.deinit(gpa);
        gpa.free(installed);
    }

    var selected: ?Package = null;
    var new_list: std.ArrayList(Package) = .empty;
    errdefer {
        for (new_list.items) |*package| package.deinit(gpa);
        new_list.deinit(gpa);
    }
    for (installed) |package| {
        if (packageMatches(package, name)) {
            if (selected == null) selected = package;
            continue;
        }
        try new_list.append(gpa, try clonePackage(gpa, package));
    }
    const package = selected orelse return false;

    // Uninstall managed files first. The package record is changed only after
    // the external/local removal succeeds, so a failed package-manager command
    // does not silently orphan the configured source.
    try removeManagedPackage(gpa, io, registry_dir, package, options);
    try savePackages(gpa, io, registry_dir, new_list.items);
    for (new_list.items) |*remaining| remaining.deinit(gpa);
    new_list.deinit(gpa);
    return true;
}

/// Repair interrupted managed-package swaps and migrate legacy settings into
/// the verified native registry. Project repair never reads project package
/// state until trust has been resolved by the caller.
pub fn repairScope(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    scope: Scope,
    project_trusted: bool,
) !RepairResult {
    if (scope == .temporary) return error.TemporaryPackageNotPersistent;
    if (scope == .project and !project_trusted) return error.ProjectNotTrusted;
    const registry_dir = try scopeRoot(gpa, agent_dir, cwd, scope);
    defer gpa.free(registry_dir);
    var operation_lock = try OperationLock.acquire(gpa, io, registry_dir, .repair);
    defer operation_lock.deinit();

    var result: RepairResult = .{};
    try recoverAllGitOperations(gpa, io, registry_dir, &result);
    try migrateLegacyPackagesAt(gpa, io, registry_dir, scope, &result);
    return result;
}

pub fn repair(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
) !RepairResult {
    return repairScope(gpa, io, agent_dir, ".", .user, true);
}

/// Collect skills/ dirs from installed packages.
pub fn packageSkillDirs(gpa: std.mem.Allocator, packages: []const Package) ![]const []const u8 {
    var list_out: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (list_out.items) |p| gpa.free(p);
        list_out.deinit(gpa);
    }
    for (packages) |p| {
        const skills = try std.fs.path.join(gpa, &.{ p.path, "skills" });
        try list_out.append(gpa, skills);
    }
    return try list_out.toOwnedSlice(gpa);
}

test "install list remove package" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    const agent = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent);
    try std.Io.Dir.cwd().createDirPath(io, agent);

    const pkg = try std.fs.path.join(gpa, &.{ root, "mypkg" });
    defer gpa.free(pkg);
    try std.Io.Dir.cwd().createDirPath(io, pkg);
    const skills = try std.fs.path.join(gpa, &.{ pkg, "skills" });
    defer gpa.free(skills);
    try std.Io.Dir.cwd().createDirPath(io, skills);

    var installed = try install(gpa, io, agent, "path:mypkg", root);
    defer installed.deinit(gpa);
    try std.testing.expectEqualStrings("mypkg", installed.name);

    const packages = try list(gpa, io, agent);
    defer {
        for (packages) |*p| {
            var mut = p.*;
            mut.deinit(gpa);
        }
        gpa.free(packages);
    }
    try std.testing.expectEqual(@as(usize, 1), packages.len);

    try std.testing.expect(try remove(gpa, io, agent, "mypkg"));
    const after = try list(gpa, io, agent);
    defer {
        for (after) |*p| {
            var mut = p.*;
            mut.deinit(gpa);
        }
        gpa.free(after);
    }
    try std.testing.expectEqual(@as(usize, 0), after.len);
}

test "package Pi manifest resolves all resource types and suppresses conventional fallback" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];

    const ext = try std.fs.path.join(gpa, &.{ root, "src", "extension.ts" });
    defer gpa.free(ext);
    const skill = try std.fs.path.join(gpa, &.{ root, "capabilities", "demo", "SKILL.md" });
    defer gpa.free(skill);
    const prompt = try std.fs.path.join(gpa, &.{ root, "templates", "review.md" });
    defer gpa.free(prompt);
    const theme = try std.fs.path.join(gpa, &.{ root, "appearance", "night.json" });
    defer gpa.free(theme);
    for ([_][]const u8{ ext, skill, prompt, theme }) |path| {
        if (std.fs.path.dirname(path)) |dir| try std.Io.Dir.cwd().createDirPath(io, dir);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "resource" });
    }
    // This conventional directory must not be loaded because the Pi manifest
    // is authoritative, even though it omits an entry under this directory.
    const conventional = try std.fs.path.join(gpa, &.{ root, "prompts", "ignored.md" });
    defer gpa.free(conventional);
    if (std.fs.path.dirname(conventional)) |dir| try std.Io.Dir.cwd().createDirPath(io, dir);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = conventional, .data = "ignored" });

    const package_json = try std.fs.path.join(gpa, &.{ root, "package.json" });
    defer gpa.free(package_json);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = package_json, .data =
        \\{"name":"resource-package","pi":{"extensions":["src/extension.ts"],"skills":["capabilities/demo/SKILL.md"],"prompts":["templates/review.md"],"themes":["appearance/night.json"]}}
    });

    const packages = [_]Package{.{ .name = "resource-package", .path = root }};
    var resources = try resolveResources(gpa, io, &packages);
    defer resources.deinit();
    try std.testing.expectEqual(@as(usize, 1), resources.extensions.items.len);
    try std.testing.expectEqual(@as(usize, 1), resources.skills.items.len);
    try std.testing.expectEqual(@as(usize, 1), resources.prompts.items.len);
    try std.testing.expectEqual(@as(usize, 1), resources.themes.items.len);
    try std.testing.expectEqualStrings(ext, resources.extensions.items[0]);
    try std.testing.expectEqualStrings(skill, resources.skills.items[0]);
    try std.testing.expectEqualStrings(prompt, resources.prompts.items[0]);
    try std.testing.expectEqualStrings(theme, resources.themes.items[0]);
}

test "packages without Pi manifest use conventional resource directories" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const extension = try std.fs.path.join(gpa, &.{ root, "extensions", "demo", "index.ts" });
    defer gpa.free(extension);
    const skill = try std.fs.path.join(gpa, &.{ root, "skills", "demo", "SKILL.md" });
    defer gpa.free(skill);
    const prompt = try std.fs.path.join(gpa, &.{ root, "prompts", "review.md" });
    defer gpa.free(prompt);
    const theme = try std.fs.path.join(gpa, &.{ root, "themes", "night.json" });
    defer gpa.free(theme);
    for ([_][]const u8{ extension, skill, prompt, theme }) |path| {
        if (std.fs.path.dirname(path)) |dir| try std.Io.Dir.cwd().createDirPath(io, dir);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "resource" });
    }

    const packages = [_]Package{.{ .name = "conventional", .path = root }};
    var resources = try resolveResources(gpa, io, &packages);
    defer resources.deinit();
    try std.testing.expectEqual(@as(usize, 1), resources.extensions.items.len);
    try std.testing.expectEqual(@as(usize, 1), resources.skills.items.len);
    try std.testing.expectEqual(@as(usize, 1), resources.prompts.items.len);
    try std.testing.expectEqual(@as(usize, 1), resources.themes.items.len);
    try std.testing.expectEqualStrings(extension, resources.extensions.items[0]);
    try std.testing.expectEqualStrings(skill, resources.skills.items[0]);
    try std.testing.expectEqualStrings(prompt, resources.prompts.items[0]);
    try std.testing.expectEqualStrings(theme, resources.themes.items[0]);
}

test "package resource filters honor autoload and ordered selectors" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];

    const extension_dir = try std.fs.path.join(gpa, &.{ root, "extensions" });
    defer gpa.free(extension_dir);
    try std.Io.Dir.cwd().createDirPath(io, extension_dir);
    inline for (.{ "a.ts", "b.ts", "c.ts" }) |name| {
        const path = try std.fs.path.join(gpa, &.{ extension_dir, name });
        defer gpa.free(path);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "export default () => {};" });
    }
    const package_json = try std.fs.path.join(gpa, &.{ root, "package.json" });
    defer gpa.free(package_json);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = package_json, .data =
        \\{"name":"filtered","pi":{"extensions":["extensions"]}}
    });

    const enabled_patterns = [_][]const u8{
        "extensions/*.ts",
        "!extensions/b.ts",
        "+extensions/b.ts",
        "-extensions/c.ts",
    };
    const enabled_packages = [_]Package{.{
        .name = "filtered",
        .path = root,
        .extensions = &enabled_patterns,
    }};
    var enabled = try resolveResources(gpa, io, &enabled_packages);
    defer enabled.deinit();
    try std.testing.expectEqual(@as(usize, 2), enabled.extensions.items.len);
    try std.testing.expect(std.mem.endsWith(u8, enabled.extensions.items[0], "a.ts"));
    try std.testing.expect(std.mem.endsWith(u8, enabled.extensions.items[1], "b.ts"));

    const delta_patterns = [_][]const u8{"extensions/b.ts"};
    const delta_packages = [_]Package{.{
        .name = "filtered",
        .path = root,
        .autoload = false,
        .extensions = &delta_patterns,
    }};
    var delta = try resolveResources(gpa, io, &delta_packages);
    defer delta.deinit();
    try std.testing.expectEqual(@as(usize, 1), delta.extensions.items.len);
    try std.testing.expect(std.mem.endsWith(u8, delta.extensions.items[0], "b.ts"));
    try std.testing.expectEqual(@as(usize, 0), delta.skills.items.len);
}

test "packages json preserves empty filters and autoload false" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];

    const package_root = try std.fs.path.join(gpa, &.{ root, "package" });
    defer gpa.free(package_root);
    try std.Io.Dir.cwd().createDirPath(io, package_root);
    const empty = [_][]const u8{};
    const skill_patterns = [_][]const u8{ "skills/**", "!skills/private/**" };
    const configured = [_]Package{.{
        .name = "configured",
        .path = package_root,
        .autoload = false,
        .extensions = &empty,
        .skills = &skill_patterns,
    }};
    try savePackages(gpa, io, root, &configured);

    const loaded = try list(gpa, io, root);
    defer {
        for (loaded) |*package| package.deinit(gpa);
        gpa.free(loaded);
    }
    try std.testing.expectEqual(@as(usize, 1), loaded.len);
    try std.testing.expect(!loaded[0].autoload);
    try std.testing.expect(loaded[0].extensions != null);
    try std.testing.expectEqual(@as(usize, 0), loaded[0].extensions.?.len);
    try std.testing.expectEqual(@as(usize, 2), loaded[0].skills.?.len);
    try std.testing.expectEqualStrings("skills/**", loaded[0].skills.?[0]);
    try std.testing.expectEqualStrings("!skills/private/**", loaded[0].skills.?[1]);
}

test "local reinstall preserves package filters and package manifest name" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const package_dir = try std.fs.path.join(gpa, &.{ root, "folder-name" });
    defer gpa.free(package_dir);
    try std.Io.Dir.cwd().createDirPath(io, package_dir);
    const package_json = try std.fs.path.join(gpa, &.{ package_dir, "package.json" });
    defer gpa.free(package_json);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = package_json, .data =
        \\{"name":"manifest-name","pi":{"extensions":["extensions/*.ts"]}}
    });

    const extension_filter = [_][]const u8{"+extensions/main.ts"};
    const configured = [_]Package{.{
        .name = "manifest-name",
        .path = package_dir,
        .source = "path:old-location",
        .autoload = false,
        .extensions = &extension_filter,
    }};
    try savePackages(gpa, io, agent_dir, &configured);

    var installed = try installAdvanced(gpa, io, agent_dir, package_dir, root, false);
    defer installed.deinit(gpa);
    try std.testing.expectEqualStrings("manifest-name", installed.name);
    try std.testing.expect(!installed.autoload);
    try std.testing.expectEqual(@as(usize, 1), installed.extensions.?.len);
    try std.testing.expectEqualStrings("+extensions/main.ts", installed.extensions.?[0]);
    try std.testing.expect(std.mem.startsWith(u8, installed.source.?, "path:"));

    const persisted = try list(gpa, io, agent_dir);
    defer {
        for (persisted) |*package| package.deinit(gpa);
        gpa.free(persisted);
    }
    try std.testing.expectEqual(@as(usize, 1), persisted.len);
    try std.testing.expect(!persisted[0].autoload);
    try std.testing.expectEqualStrings("+extensions/main.ts", persisted[0].extensions.?[0]);
}

test "offline package update classifies local pinned and managed sources" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);

    const configured = [_]Package{
        .{ .name = "local", .path = root, .source = "path:." },
        .{ .name = "fixed", .path = "/managed/fixed", .source = "npm:fixed@1.2.3" },
        .{ .name = "moving", .path = "/managed/moving", .source = "npm:moving@^2" },
        .{ .name = "repo", .path = "/managed/repo", .source = "git:github.com/example/repo" },
    };
    try savePackages(gpa, io, agent_dir, &configured);

    const result = try update(gpa, io, agent_dir, null, root, true);
    try std.testing.expectEqual(@as(usize, 4), result.matched);
    try std.testing.expectEqual(@as(usize, 0), result.updated);
    try std.testing.expectEqual(@as(usize, 1), result.skipped_local);
    try std.testing.expectEqual(@as(usize, 1), result.skipped_pinned);
    try std.testing.expectError(error.PackageNotFound, update(gpa, io, agent_dir, "absent", root, true));
}

test "managed Git removal is root confined and prunes empty parents" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const checkout = try std.fs.path.join(gpa, &.{ agent_dir, "git", "github.com", "example", "repo" });
    defer gpa.free(checkout);
    try std.Io.Dir.cwd().createDirPath(io, checkout);
    const marker = try std.fs.path.join(gpa, &.{ checkout, "index.ts" });
    defer gpa.free(marker);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = marker, .data = "export default () => {};" });

    const configured = [_]Package{.{
        .name = "repo",
        .path = checkout,
        .source = "git:github.com/example/repo",
    }};
    try savePackages(gpa, io, agent_dir, &configured);
    try std.testing.expect(try remove(gpa, io, agent_dir, "repo"));
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, checkout, .{}));

    const after = try list(gpa, io, agent_dir);
    defer gpa.free(after);
    try std.testing.expectEqual(@as(usize, 0), after.len);
}

test "managed removal rejects tampered paths outside package roots" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const outside = try std.fs.path.join(gpa, &.{ root, "outside" });
    defer gpa.free(outside);
    try std.Io.Dir.cwd().createDirPath(io, outside);

    const configured = [_]Package{.{
        .name = "repo",
        .path = outside,
        .source = "git:github.com/example/repo",
    }};
    try savePackages(gpa, io, agent_dir, &configured);
    try std.testing.expectError(error.UnsafeManagedPackagePath, remove(gpa, io, agent_dir, "repo"));
    _ = try std.Io.Dir.cwd().statFile(io, outside, .{});
}

test "direct script packages and root extension directories are discovered" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    const script = try std.fs.path.join(gpa, &.{ root, "direct.ts" });
    defer gpa.free(script);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = script, .data = "export default () => {};" });
    const directory = try std.fs.path.join(gpa, &.{ root, "directory-extension" });
    defer gpa.free(directory);
    try std.Io.Dir.cwd().createDirPath(io, directory);
    const index = try std.fs.path.join(gpa, &.{ directory, "index.ts" });
    defer gpa.free(index);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = index, .data = "export default () => {};" });

    const configured = [_]Package{
        .{ .name = "direct.ts", .path = script, .source = "path:direct.ts" },
        .{ .name = "directory-extension", .path = directory, .source = "path:directory-extension" },
    };
    var resources = try resolveResources(gpa, io, &configured);
    defer resources.deinit();
    try std.testing.expectEqual(@as(usize, 2), resources.extensions.items.len);
    try std.testing.expect(containsPath(resources.extensions.items, script));
    try std.testing.expect(containsPath(resources.extensions.items, index));
}

test "direct script package install persists and removes only configuration" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const script = try std.fs.path.join(gpa, &.{ root, "direct.mts" });
    defer gpa.free(script);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = script, .data = "export default () => {};" });

    var installed = try installAdvanced(gpa, io, agent_dir, script, root, false);
    defer installed.deinit(gpa);
    try std.testing.expectEqualStrings("direct.mts", installed.name);
    try std.testing.expectEqualStrings(script, installed.path);
    try std.testing.expect(try remove(gpa, io, agent_dir, "direct.mts"));
    _ = try std.Io.Dir.cwd().statFile(io, script, .{});
}

test "manifest and package filters suppress root extension fallback" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    const manifest_root = try std.fs.path.join(gpa, &.{ root, "manifest" });
    defer gpa.free(manifest_root);
    try std.Io.Dir.cwd().createDirPath(io, manifest_root);
    const manifest_index = try std.fs.path.join(gpa, &.{ manifest_root, "index.ts" });
    defer gpa.free(manifest_index);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = manifest_index, .data = "export default () => {};" });
    const package_json = try std.fs.path.join(gpa, &.{ manifest_root, "package.json" });
    defer gpa.free(package_json);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = package_json, .data = "{\"name\":\"empty-manifest\",\"pi\":{}}" });

    const filtered_root = try std.fs.path.join(gpa, &.{ root, "filtered" });
    defer gpa.free(filtered_root);
    try std.Io.Dir.cwd().createDirPath(io, filtered_root);
    const filtered_index = try std.fs.path.join(gpa, &.{ filtered_root, "index.ts" });
    defer gpa.free(filtered_index);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = filtered_index, .data = "export default () => {};" });
    const skill_patterns = [_][]const u8{"skills/**"};

    const configured = [_]Package{
        .{ .name = "empty-manifest", .path = manifest_root },
        .{ .name = "filtered", .path = filtered_root, .skills = &skill_patterns },
    };
    var resources = try resolveResources(gpa, io, &configured);
    defer resources.deinit();
    try std.testing.expectEqual(@as(usize, 0), resources.extensions.items.len);
}

test "configured package scopes enforce trust and project precedence" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const project_root = try std.fs.path.join(gpa, &.{ root, "project" });
    defer gpa.free(project_root);
    const project_pi = try std.fs.path.join(gpa, &.{ project_root, ".pi" });
    defer gpa.free(project_pi);
    try std.Io.Dir.cwd().createDirPath(io, project_pi);

    const user_path = try std.fs.path.join(gpa, &.{ root, "user-demo" });
    defer gpa.free(user_path);
    const project_path = try std.fs.path.join(gpa, &.{ root, "project-demo" });
    defer gpa.free(project_path);
    try std.Io.Dir.cwd().createDirPath(io, user_path);
    try std.Io.Dir.cwd().createDirPath(io, project_path);

    const user_packages = [_]Package{.{
        .name = "demo-user",
        .path = user_path,
        .source = "npm:demo@1.0.0",
    }};
    const project_packages = [_]Package{.{
        .name = "demo-project",
        .path = project_path,
        .source = "npm:demo@2.0.0",
        .scope = .project,
    }};
    try savePackages(gpa, io, agent_dir, &user_packages);
    try savePackages(gpa, io, project_pi, &project_packages);

    const untrusted = try listConfigured(gpa, io, agent_dir, project_root, false);
    defer {
        for (untrusted) |*package| package.deinit(gpa);
        gpa.free(untrusted);
    }
    try std.testing.expectEqual(@as(usize, 1), untrusted.len);
    try std.testing.expectEqual(Scope.user, untrusted[0].scope);
    try std.testing.expectEqualStrings(user_path, untrusted[0].path);
    try std.testing.expectError(error.ProjectNotTrusted, listScope(gpa, io, agent_dir, project_root, .project, false));

    const trusted = try listConfigured(gpa, io, agent_dir, project_root, true);
    defer {
        for (trusted) |*package| package.deinit(gpa);
        gpa.free(trusted);
    }
    try std.testing.expectEqual(@as(usize, 1), trusted.len);
    try std.testing.expectEqual(Scope.project, trusted[0].scope);
    try std.testing.expectEqualStrings(project_path, trusted[0].path);
}

test "project autoload delta uses user installation and remains first" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const cwd = try std.fs.path.join(gpa, &.{ root, "project" });
    defer gpa.free(cwd);
    const project_pi = try std.fs.path.join(gpa, &.{ cwd, ".pi" });
    defer gpa.free(project_pi);
    try std.Io.Dir.cwd().createDirPath(io, project_pi);
    const installed_path = try std.fs.path.join(gpa, &.{ agent_dir, "npm", "node_modules", "demo" });
    defer gpa.free(installed_path);
    try std.Io.Dir.cwd().createDirPath(io, installed_path);

    const patterns = [_][]const u8{ "+extensions/only.ts", "-extensions/no.ts" };
    const user_packages = [_]Package{.{
        .name = "demo",
        .path = installed_path,
        .source = "npm:demo@1.0.0",
    }};
    const project_packages = [_]Package{.{
        .name = "demo",
        .path = "/must-not-be-used",
        .source = "npm:demo@latest",
        .scope = .project,
        .autoload = false,
        .extensions = &patterns,
    }};
    try savePackages(gpa, io, agent_dir, &user_packages);
    try savePackages(gpa, io, project_pi, &project_packages);

    const configured = try listConfigured(gpa, io, agent_dir, cwd, true);
    defer {
        for (configured) |*package| package.deinit(gpa);
        gpa.free(configured);
    }
    try std.testing.expectEqual(@as(usize, 2), configured.len);
    try std.testing.expectEqual(Scope.project, configured[0].scope);
    try std.testing.expect(!configured[0].autoload);
    try std.testing.expectEqualStrings(installed_path, configured[0].path);
    try std.testing.expectEqual(Scope.user, configured[1].scope);
}

test "project and temporary installs use scoped storage and trust" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const cwd = try std.fs.path.join(gpa, &.{ root, "project" });
    defer gpa.free(cwd);
    const extension = try std.fs.path.join(gpa, &.{ root, "scope.ts" });
    defer gpa.free(extension);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = extension, .data = "export default () => {};" });

    try std.testing.expectError(
        error.ProjectNotTrusted,
        installScoped(gpa, io, agent_dir, cwd, extension, .project, false, true),
    );

    var project_package = try installScoped(gpa, io, agent_dir, cwd, extension, .project, true, true);
    defer project_package.deinit(gpa);
    try std.testing.expectEqual(Scope.project, project_package.scope);
    const project_list = try listScope(gpa, io, agent_dir, cwd, .project, true);
    defer {
        for (project_list) |*package| package.deinit(gpa);
        gpa.free(project_list);
    }
    try std.testing.expectEqual(@as(usize, 1), project_list.len);
    try std.testing.expectEqual(Scope.project, project_list[0].scope);

    var temporary_package = try installScoped(gpa, io, agent_dir, cwd, extension, .temporary, false, true);
    defer temporary_package.deinit(gpa);
    try std.testing.expectEqual(Scope.temporary, temporary_package.scope);
    const user_list = try list(gpa, io, agent_dir);
    defer {
        for (user_list) |*package| package.deinit(gpa);
        gpa.free(user_list);
    }
    try std.testing.expectEqual(@as(usize, 0), user_list.len);
}

test "project autoload delta tombstones suppress lower scope resources" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    const package_root = try std.fs.path.join(gpa, &.{ root, "demo" });
    defer gpa.free(package_root);
    const extensions_dir = try std.fs.path.join(gpa, &.{ package_root, "extensions" });
    defer gpa.free(extensions_dir);
    try std.Io.Dir.cwd().createDirPath(io, extensions_dir);
    inline for (.{ "a.ts", "b.ts", "c.ts" }) |name| {
        const path = try std.fs.path.join(gpa, &.{ extensions_dir, name });
        defer gpa.free(path);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "export default () => {};" });
    }

    const delta_patterns = [_][]const u8{
        "!extensions/b.ts",
        "+extensions/c.ts",
    };
    const configured = [_]Package{
        .{
            .name = "demo-delta",
            .path = package_root,
            .scope = .project,
            .autoload = false,
            .extensions = &delta_patterns,
        },
        .{
            .name = "demo-base",
            .path = package_root,
            .scope = .user,
        },
    };
    var resources = try resolveResources(gpa, io, &configured);
    defer resources.deinit();

    try std.testing.expectEqual(@as(usize, 2), resources.extensions.items.len);
    try std.testing.expect(std.mem.endsWith(u8, resources.extensions.items[0], "c.ts"));
    try std.testing.expect(std.mem.endsWith(u8, resources.extensions.items[1], "a.ts"));
    for (resources.extensions.items) |path| {
        try std.testing.expect(!std.mem.endsWith(u8, path, "b.ts"));
    }
}

test "configured npm command identifies wrapped managers" {
    const npm = [_][]const u8{"npm"};
    const pnpm = [_][]const u8{ "mise", "exec", "node@22", "--", "pnpm" };
    const bun = [_][]const u8{"C:\\tools\\bun.exe"};
    const custom = [_][]const u8{ "wrapper", "--", "custom-pm" };
    try std.testing.expectEqual(PackageManagerKind.npm, try packageManagerKind(&npm));
    try std.testing.expectEqual(PackageManagerKind.pnpm, try packageManagerKind(&pnpm));
    try std.testing.expectEqual(PackageManagerKind.bun, try packageManagerKind(&bun));
    try std.testing.expectEqual(PackageManagerKind.other, try packageManagerKind(&custom));
    try std.testing.expectEqual(PackageManagerKind.npm, try packageManagerKind(null));
    const empty = [_][]const u8{};
    try std.testing.expectError(error.InvalidNpmCommand, packageManagerKind(&empty));
}

test "legacy settings package arrays remain loadable in both trusted scopes" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const cwd = try std.fs.path.join(gpa, &.{ root, "project" });
    defer gpa.free(cwd);
    const project_pi = try std.fs.path.join(gpa, &.{ cwd, ".pi" });
    defer gpa.free(project_pi);
    try std.Io.Dir.cwd().createDirPath(io, agent_dir);
    try std.Io.Dir.cwd().createDirPath(io, project_pi);

    const global_settings = try std.fs.path.join(gpa, &.{ agent_dir, "settings.json" });
    defer gpa.free(global_settings);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = global_settings,
        .data =
        \\{"packages":["npm:@scope/demo@1.2.3",{"source":"path:./local-extension","autoload":false,"extensions":["+index.ts"]}]}
        ,
    });
    const project_settings = try std.fs.path.join(gpa, &.{ project_pi, "settings.json" });
    defer gpa.free(project_settings);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = project_settings,
        .data =
        \\{"packages":["git:https://github.com/example/project-extension.git"]}
        ,
    });

    const untrusted = try listConfigured(gpa, io, agent_dir, cwd, false);
    defer {
        for (untrusted) |*package| package.deinit(gpa);
        gpa.free(untrusted);
    }
    try std.testing.expectEqual(@as(usize, 2), untrusted.len);
    try std.testing.expectEqual(Scope.user, untrusted[0].scope);
    try std.testing.expectEqualStrings("@scope/demo", untrusted[0].name);
    try std.testing.expect(pathEndsWithPortable(untrusted[0].path, "npm/node_modules/@scope/demo"));
    try std.testing.expect(!untrusted[1].autoload);
    try std.testing.expectEqualStrings("+index.ts", untrusted[1].extensions.?[0]);
    try std.testing.expect(pathEndsWithPortable(untrusted[1].path, "agent/local-extension"));

    const trusted = try listConfigured(gpa, io, agent_dir, cwd, true);
    defer {
        for (trusted) |*package| package.deinit(gpa);
        gpa.free(trusted);
    }
    try std.testing.expectEqual(@as(usize, 3), trusted.len);
    try std.testing.expectEqual(Scope.project, trusted[0].scope);
    try std.testing.expectEqualStrings("project-extension", trusted[0].name);
    try std.testing.expect(pathEndsWithPortable(trusted[0].path, ".pi/git/github.com/example/project-extension"));
}

test "package operation locks retry then recover after release" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var first = try OperationLock.acquire(gpa, io, root, .configure);
    try std.testing.expectError(error.PackageOperationLocked, OperationLock.acquire(gpa, io, root, .configure));
    first.deinit();
    var second = try OperationLock.acquire(gpa, io, root, .configure);
    second.deinit();
}

test "package repair migrates legacy settings only after verified native persistence" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    try std.Io.Dir.cwd().createDirPath(io, agent_dir);
    const settings_path = try std.fs.path.join(gpa, &.{ agent_dir, "settings.json" });
    defer gpa.free(settings_path);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = settings_path,
        .data =
        \\{"theme":"night","packages":[{"source":"npm:@scope/legacy@1.2.3","autoload":false,"skills":[]}]}
        ,
    });

    const result = try repair(gpa, io, agent_dir);
    try std.testing.expectEqual(@as(usize, 1), result.migrated_legacy_packages);
    try std.testing.expect(result.cleaned_legacy_settings);

    const installed = try list(gpa, io, agent_dir);
    defer {
        for (installed) |*package| package.deinit(gpa);
        gpa.free(installed);
    }
    try std.testing.expectEqual(@as(usize, 1), installed.len);
    try std.testing.expectEqualStrings("@scope/legacy", installed[0].name);
    try std.testing.expect(!installed[0].autoload);
    try std.testing.expectEqual(@as(usize, 0), installed[0].skills.?.len);

    const settings_raw = try std.Io.Dir.cwd().readFileAlloc(io, settings_path, gpa, .limited(1024 * 1024));
    defer gpa.free(settings_raw);
    var settings = try std.json.parseFromSlice(std.json.Value, gpa, settings_raw, .{});
    defer settings.deinit();
    try std.testing.expect(settings.value.object.get("packages") == null);
    try std.testing.expectEqualStrings("night", settings.value.object.get("theme").?.string);
}

test "package repair commits a prepared git swap and removes its backup" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const target = try std.fs.path.join(gpa, &.{ agent_dir, "git", "github.com", "owner", "repo" });
    defer gpa.free(target);
    const temporary = try std.fmt.allocPrint(gpa, "{s}.tmp-deadbeef", .{target});
    defer gpa.free(temporary);
    const backup = try std.fmt.allocPrint(gpa, "{s}.old-deadbeef", .{target});
    defer gpa.free(backup);
    try std.Io.Dir.cwd().createDirPath(io, temporary);
    try std.Io.Dir.cwd().createDirPath(io, backup);
    const prepared_file = try std.fs.path.join(gpa, &.{ temporary, "prepared.txt" });
    defer gpa.free(prepared_file);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = prepared_file, .data = "new" });
    const old_file = try std.fs.path.join(gpa, &.{ backup, "old.txt" });
    defer gpa.free(old_file);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = old_file, .data = "old" });
    const marker = try gitUpdateMarkerPath(gpa, target);
    defer gpa.free(marker);
    try writeGitRepairMarker(gpa, io, marker, target, temporary, backup);

    const result = try repair(gpa, io, agent_dir);
    try std.testing.expectEqual(@as(usize, 1), result.markers_found);
    try std.testing.expectEqual(@as(usize, 1), result.committed_prepared_updates);
    try std.testing.expectEqual(@as(usize, 1), result.cleaned_artifacts);
    try std.testing.expectEqual(@as(usize, 1), result.removed_markers);
    try std.testing.expect(pathExists(io, target));
    try std.testing.expect(!pathExists(io, temporary));
    try std.testing.expect(!pathExists(io, backup));
    try std.testing.expect(!pathExists(io, marker));
    const committed_file = try std.fs.path.join(gpa, &.{ target, "prepared.txt" });
    defer gpa.free(committed_file);
    try std.testing.expect(pathExists(io, committed_file));
}

test "package repair restores a backup when the prepared checkout disappeared" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const target = try std.fs.path.join(gpa, &.{ agent_dir, "git", "github.com", "owner", "repo" });
    defer gpa.free(target);
    const temporary = try std.fmt.allocPrint(gpa, "{s}.tmp-cafe", .{target});
    defer gpa.free(temporary);
    const backup = try std.fmt.allocPrint(gpa, "{s}.old-cafe", .{target});
    defer gpa.free(backup);
    try std.Io.Dir.cwd().createDirPath(io, backup);
    const old_file = try std.fs.path.join(gpa, &.{ backup, "old.txt" });
    defer gpa.free(old_file);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = old_file, .data = "old" });
    const marker = try gitUpdateMarkerPath(gpa, target);
    defer gpa.free(marker);
    try writeGitRepairMarker(gpa, io, marker, target, temporary, backup);

    const result = try repair(gpa, io, agent_dir);
    try std.testing.expectEqual(@as(usize, 1), result.restored_backups);
    try std.testing.expect(pathExists(io, target));
    try std.testing.expect(!pathExists(io, marker));
    const restored_file = try std.fs.path.join(gpa, &.{ target, "old.txt" });
    defer gpa.free(restored_file);
    try std.testing.expect(pathExists(io, restored_file));
}

test "package repair rejects marker artifacts outside the checkout parent" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const target = try std.fs.path.join(gpa, &.{ agent_dir, "git", "github.com", "owner", "repo" });
    defer gpa.free(target);
    const outside = try std.fs.path.join(gpa, &.{ root, "repo.tmp-escape" });
    defer gpa.free(outside);
    const backup = try std.fmt.allocPrint(gpa, "{s}.old-safe", .{target});
    defer gpa.free(backup);
    try std.Io.Dir.cwd().createDirPath(io, outside);
    const marker = try gitUpdateMarkerPath(gpa, target);
    defer gpa.free(marker);
    try writeGitRepairMarker(gpa, io, marker, target, outside, backup);

    try std.testing.expectError(error.PackageRepairStateInvalid, repair(gpa, io, agent_dir));
    try std.testing.expect(pathExists(io, outside));
    try std.testing.expect(pathExists(io, marker));
}

test "package operation inspection reports active owner and clean release" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var held = try OperationLock.acquire(gpa, io, root, .configure);
    var active = try inspectOperation(gpa, io, root, ".", .user, true);
    try std.testing.expect(active.active);
    try std.testing.expect(active.metadata_present);
    try std.testing.expectEqualStrings("configure", active.operation);
    try std.testing.expect(active.pid != 0);
    active.deinit();
    held.deinit();

    var released = try inspectOperation(gpa, io, root, ".", .user, true);
    defer released.deinit();
    try std.testing.expect(!released.active);
    try std.testing.expect(!released.metadata_present);
}

test "package scope health exposes stale metadata markers and legacy migration need" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const lock_path = try std.fs.path.join(gpa, &.{ root, ".packages.lock" });
    defer gpa.free(lock_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = lock_path, .data = "{\"pid\":42,\"operation\":\"update\",\"startedMs\":100,\"registryDir\":\"stale\"}\n" });
    const settings_path = try std.fs.path.join(gpa, &.{ root, "settings.json" });
    defer gpa.free(settings_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = settings_path, .data = "{\"packages\":[]}" });
    const marker_dir = try std.fs.path.join(gpa, &.{ root, "git", "host", "owner" });
    defer gpa.free(marker_dir);
    try std.Io.Dir.cwd().createDirPath(io, marker_dir);
    const marker = try std.fs.path.join(gpa, &.{ marker_dir, ".repo.pi-update-incomplete" });
    defer gpa.free(marker);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = marker, .data = "{}" });

    var health = try inspectScopeHealth(gpa, io, root, ".", .user, true);
    defer health.deinit();
    try std.testing.expect(!health.operation.active);
    try std.testing.expect(health.operation.stale_metadata);
    try std.testing.expectEqual(@as(usize, 1), health.repair_markers);
    try std.testing.expect(health.legacy_packages_pending);
    try std.testing.expect(!health.native_registry_present);
}
