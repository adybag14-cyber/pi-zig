//! Native package resource inventory and configuration.
//!
//! The original Pi configuration selector keeps disabled resources visible,
//! supports global toggles, and exposes project-local inherit/load/unload
//! overrides. This module provides that allocator-owned model independently of
//! the fullscreen frontend so CLI JSON, RPC, tests and the TUI share exactly
//! the same mutation semantics.
const std = @import("std");
const Io = std.Io;
const packages = @import("packages.zig");
const package_resources = @import("package_resources.zig");
const top_level_resources = @import("top_level_resources.zig");

pub const ResourceType = package_resources.ResourceType;

pub const OverrideState = top_level_resources.OverrideState;

pub const Origin = enum {
    package,
    top_level,
};

pub const Resource = struct {
    gpa: std.mem.Allocator,
    package_name: []const u8,
    package_source: []const u8,
    package_path: []const u8,
    package_scope: packages.Scope,
    selector: []const u8,
    origin: Origin,
    resource_type: ResourceType,
    path: []const u8,
    relative_path: []const u8,
    display_name: []const u8,
    enabled: bool,
    inherited_enabled: bool,
    override_state: OverrideState,

    pub fn deinit(self: *Resource) void {
        self.gpa.free(self.package_name);
        self.gpa.free(self.package_source);
        self.gpa.free(self.package_path);
        self.gpa.free(self.selector);
        self.gpa.free(self.path);
        self.gpa.free(self.relative_path);
        self.gpa.free(self.display_name);
        self.* = undefined;
    }
};

pub const Inventory = struct {
    gpa: std.mem.Allocator,
    write_scope: packages.Scope,
    resources: []Resource,

    pub fn deinit(self: *Inventory) void {
        for (self.resources) |*resource| resource.deinit();
        self.gpa.free(self.resources);
        self.* = undefined;
    }
};

fn freePackages(gpa: std.mem.Allocator, configured: []packages.Package) void {
    for (configured) |*package| package.deinit(gpa);
    gpa.free(configured);
}

fn packageSelectorMatches(package: packages.Package, selector: []const u8) bool {
    return std.mem.eql(u8, package.name, selector) or
        std.mem.eql(u8, package.path, selector) or
        (package.source != null and std.mem.eql(u8, package.source.?, selector));
}

fn findMatchingPackage(
    gpa: std.mem.Allocator,
    configured: []const packages.Package,
    package: packages.Package,
) !?usize {
    for (configured, 0..) |candidate, index| {
        if (try packages.sameIdentity(gpa, candidate, package)) return index;
    }
    return null;
}

fn resourcePatterns(package: packages.Package, resource_type: ResourceType) ?[]const []const u8 {
    return switch (resource_type) {
        .extensions => package.extensions,
        .skills => package.skills,
        .prompts => package.prompts,
        .themes => package.themes,
    };
}

fn resourcePatternsPtr(package: *packages.Package, resource_type: ResourceType) *?[]const []const u8 {
    return switch (resource_type) {
        .extensions => &package.extensions,
        .skills => &package.skills,
        .prompts => &package.prompts,
        .themes => &package.themes,
    };
}

fn packageBaseDir(package: packages.Package) []const u8 {
    const extension = std.fs.path.extension(package.path);
    if (extension.len > 0) return std.fs.path.dirname(package.path) orelse package.path;
    return package.path;
}

fn normalizedRelative(gpa: std.mem.Allocator, package: packages.Package, path: []const u8) ![]u8 {
    const raw = try std.fs.path.relative(gpa, ".", null, packageBaseDir(package), path);
    defer gpa.free(raw);
    const result = try gpa.dupe(u8, raw);
    for (result) |*byte| {
        if (byte.* == '\\') byte.* = '/';
    }
    return result;
}

fn strippedPattern(pattern: []const u8) []const u8 {
    if (pattern.len > 0 and (pattern[0] == '!' or pattern[0] == '+' or pattern[0] == '-')) return pattern[1..];
    return pattern;
}

fn normalizedPatternEquals(relative_path: []const u8, pattern: []const u8) bool {
    const target = strippedPattern(pattern);
    if (std.mem.eql(u8, relative_path, target)) return true;
    if (std.mem.startsWith(u8, target, "./") and std.mem.eql(u8, relative_path, target[2..])) return true;
    if (std.mem.indexOfScalar(u8, target, '\\') == null) return false;
    var index: usize = 0;
    if (relative_path.len != target.len) return false;
    while (index < target.len) : (index += 1) {
        const normalized = if (target[index] == '\\') '/' else target[index];
        if (normalized != relative_path[index]) return false;
    }
    return true;
}

fn explicitOverride(package: packages.Package, resource_type: ResourceType, relative_path: []const u8) OverrideState {
    const configured = resourcePatterns(package, resource_type) orelse return .inherit;
    if (configured.len == 0 and package.autoload) return .unload;
    var state: OverrideState = .inherit;
    for (configured) |entry| {
        if (!normalizedPatternEquals(relative_path, entry)) continue;
        state = if (entry.len > 0 and (entry[0] == '!' or entry[0] == '-')) .unload else .load;
    }
    return state;
}

fn resourceEnabled(
    gpa: std.mem.Allocator,
    package: packages.Package,
    resource_type: ResourceType,
    path: []const u8,
) !bool {
    var one = package_resources.PathList.init(gpa);
    defer one.deinit();
    try one.appendCopyUnique(path);
    if (package.autoload) {
        try package_resources.applyUserFilter(
            gpa,
            packageBaseDir(package),
            &one,
            resourcePatterns(package, resource_type),
            resource_type,
        );
    } else {
        try package_resources.applyAutoloadDisabledFilter(
            gpa,
            packageBaseDir(package),
            &one,
            resourcePatterns(package, resource_type),
            resource_type,
        );
    }
    return one.items.items.len == 1;
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

fn appendResource(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(Resource),
    package: packages.Package,
    resource_type: ResourceType,
    path: []const u8,
    enabled: bool,
    inherited_enabled: bool,
    override_state: OverrideState,
) !void {
    const relative_path = try normalizedRelative(gpa, package, path);
    errdefer gpa.free(relative_path);
    const display_name = try displayName(gpa, resource_type, path);
    errdefer gpa.free(display_name);
    const package_name = try gpa.dupe(u8, package.name);
    errdefer gpa.free(package_name);
    const source = try gpa.dupe(u8, package.source orelse package.path);
    errdefer gpa.free(source);
    const selector = try gpa.dupe(u8, package.source orelse package.path);
    errdefer gpa.free(selector);
    const package_path = try gpa.dupe(u8, package.path);
    errdefer gpa.free(package_path);
    const owned_path = try gpa.dupe(u8, path);
    errdefer gpa.free(owned_path);
    try out.append(gpa, .{
        .gpa = gpa,
        .package_name = package_name,
        .package_source = source,
        .package_path = package_path,
        .package_scope = package.scope,
        .selector = selector,
        .origin = .package,
        .resource_type = resource_type,
        .path = owned_path,
        .relative_path = relative_path,
        .display_name = display_name,
        .enabled = enabled,
        .inherited_enabled = inherited_enabled,
        .override_state = override_state,
    });
}

fn appendPackageInventory(
    gpa: std.mem.Allocator,
    io: Io,
    out: *std.ArrayList(Resource),
    base_package: packages.Package,
    inherited_package: ?packages.Package,
    project_package: ?packages.Package,
    write_scope: packages.Scope,
) !void {
    inline for (.{ ResourceType.extensions, ResourceType.skills, ResourceType.prompts, ResourceType.themes }) |resource_type| {
        var candidates = try packages.discoverResourceCandidates(gpa, io, base_package, resource_type);
        defer candidates.deinit();
        for (candidates.items.items) |path| {
            const relative = try normalizedRelative(gpa, base_package, path);
            defer gpa.free(relative);
            const inherited = if (inherited_package) |package|
                try resourceEnabled(gpa, package, resource_type, path)
            else
                false;
            var state: OverrideState = if (write_scope == .user)
                if (try resourceEnabled(gpa, base_package, resource_type, path)) .load else .unload
            else
                .inherit;
            var enabled = inherited;
            if (write_scope == .user) {
                enabled = state == .load;
            } else if (project_package) |project| {
                state = explicitOverride(project, resource_type, relative);
                if (!project.autoload) {
                    const decision = try package_resources.autoloadDisabledDecision(
                        gpa,
                        packageBaseDir(project),
                        path,
                        resourcePatterns(project, resource_type),
                        resource_type,
                    );
                    enabled = decision orelse inherited;
                } else {
                    enabled = try resourceEnabled(gpa, project, resource_type, path);
                }
            }
            try appendResource(gpa, out, base_package, resource_type, path, enabled, inherited, state);
        }
    }
}

fn appendTopLevelResource(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(Resource),
    item: top_level_resources.Item,
) !void {
    const group_name = if (item.source == .local)
        try std.fmt.allocPrint(gpa, "{s} settings", .{if (item.scope == .user) "User" else "Project"})
    else
        try std.fmt.allocPrint(gpa, "{s} ({s}/)", .{ if (item.scope == .user) "User" else "Project", item.base_dir });
    errdefer gpa.free(group_name);
    const source = try gpa.dupe(u8, @tagName(item.source));
    errdefer gpa.free(source);
    const base_dir = try gpa.dupe(u8, item.base_dir);
    errdefer gpa.free(base_dir);
    const selector = try gpa.dupe(u8, item.selector);
    errdefer gpa.free(selector);
    const path = try gpa.dupe(u8, item.path);
    errdefer gpa.free(path);
    const relative = try gpa.dupe(u8, item.relative_path);
    errdefer gpa.free(relative);
    const display = try gpa.dupe(u8, item.display_name);
    errdefer gpa.free(display);
    try out.append(gpa, .{
        .gpa = gpa,
        .package_name = group_name,
        .package_source = source,
        .package_path = base_dir,
        .package_scope = item.scope,
        .selector = selector,
        .origin = .top_level,
        .resource_type = item.resource_type,
        .path = path,
        .relative_path = relative,
        .display_name = display,
        .enabled = item.enabled,
        .inherited_enabled = item.inherited_enabled,
        .override_state = item.override_state,
    });
}

fn resourceLessThan(_: void, left: Resource, right: Resource) bool {
    if (left.origin != right.origin) return left.origin == .package;
    if (left.package_scope != right.package_scope) return left.package_scope == .user;
    const source_order = std.mem.order(u8, left.package_source, right.package_source);
    if (source_order != .eq) return source_order == .lt;
    const group_order = std.mem.order(u8, left.package_name, right.package_name);
    if (group_order != .eq) return group_order == .lt;
    if (@intFromEnum(left.resource_type) != @intFromEnum(right.resource_type)) {
        return @intFromEnum(left.resource_type) < @intFromEnum(right.resource_type);
    }
    const name_order = std.mem.order(u8, left.display_name, right.display_name);
    if (name_order != .eq) return name_order == .lt;
    return std.mem.lessThan(u8, left.path, right.path);
}

/// Build a complete package-resource inventory for one write scope. Disabled
/// candidates are retained. Project inventory overlays explicit project
/// selectors on the inherited user state and exposes the exact tri-state used
/// by the original selector.
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

    const user = try packages.listScope(gpa, io, agent_dir, cwd, .user, project_trusted);
    defer freePackages(gpa, user);
    const project = if (project_trusted)
        try packages.listScope(gpa, io, agent_dir, cwd, .project, true)
    else
        try gpa.alloc(packages.Package, 0);
    defer freePackages(gpa, project);

    var out: std.ArrayList(Resource) = .empty;
    errdefer {
        for (out.items) |*resource| resource.deinit();
        out.deinit(gpa);
    }

    if (write_scope == .user) {
        for (user) |package| try appendPackageInventory(gpa, io, &out, package, package, null, .user);
    } else {
        var project_used = try gpa.alloc(bool, project.len);
        defer gpa.free(project_used);
        @memset(project_used, false);
        for (user) |user_package| {
            const project_index = try findMatchingPackage(gpa, project, user_package);
            if (project_index) |index| project_used[index] = true;
            const project_package: ?packages.Package = if (project_index) |index| project[index] else null;
            const base = if (project_package) |candidate|
                if (candidate.autoload) candidate else user_package
            else
                user_package;
            try appendPackageInventory(gpa, io, &out, base, user_package, project_package, .project);
        }
        for (project, 0..) |project_package, index| {
            if (project_used[index]) continue;
            try appendPackageInventory(gpa, io, &out, project_package, null, project_package, .project);
        }
    }

    var top_level = try top_level_resources.discover(gpa, io, agent_dir, cwd, write_scope, project_trusted);
    defer top_level.deinit();
    for (top_level.items) |item| try appendTopLevelResource(gpa, &out, item);

    std.mem.sort(Resource, out.items, {}, resourceLessThan);
    return .{ .gpa = gpa, .write_scope = write_scope, .resources = try out.toOwnedSlice(gpa) };
}

fn freePatternArray(gpa: std.mem.Allocator, patterns: ?[]const []const u8) void {
    if (patterns) |items| {
        for (items) |item| gpa.free(item);
        gpa.free(items);
    }
}

fn setExactPattern(
    gpa: std.mem.Allocator,
    package: *packages.Package,
    resource_type: ResourceType,
    relative_path: []const u8,
    state: OverrideState,
) !void {
    const field = resourcePatternsPtr(package, resource_type);
    const old = field.*;
    var retained_count: usize = 0;
    if (old) |items| for (items) |item| if (!normalizedPatternEquals(relative_path, item)) {
        retained_count += 1;
    };
    const append_count: usize = if (state == .inherit) 0 else 1;
    if (retained_count + append_count == 0) {
        freePatternArray(gpa, old);
        field.* = null;
        return;
    }

    var replacement = try gpa.alloc([]const u8, retained_count + append_count);
    var initialized: usize = 0;
    errdefer {
        for (replacement[0..initialized]) |item| gpa.free(item);
        gpa.free(replacement);
    }
    if (old) |items| for (items) |item| {
        if (normalizedPatternEquals(relative_path, item)) continue;
        replacement[initialized] = try gpa.dupe(u8, item);
        initialized += 1;
    };
    if (state != .inherit) {
        replacement[initialized] = try std.fmt.allocPrint(gpa, "{c}{s}", .{
            if (state == .load) @as(u8, '+') else @as(u8, '-'),
            relative_path,
        });
        initialized += 1;
    }
    freePatternArray(gpa, old);
    field.* = replacement;
}

fn hasAnyPatterns(package: packages.Package) bool {
    return package.extensions != null or package.skills != null or package.prompts != null or package.themes != null;
}

fn cloneProjectDelta(gpa: std.mem.Allocator, package: packages.Package) !packages.Package {
    const name = try gpa.dupe(u8, package.name);
    errdefer gpa.free(name);
    const path = try gpa.dupe(u8, package.path);
    errdefer gpa.free(path);
    const source = if (package.source) |value| try gpa.dupe(u8, value) else try gpa.dupe(u8, package.path);
    errdefer gpa.free(source);
    return .{
        .name = name,
        .path = path,
        .scope = .project,
        .source = source,
        .autoload = false,
    };
}

const ResourceMutation = struct {
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    write_scope: packages.Scope,
    project_trusted: bool,
    package_selector: []const u8,
    resource_type: ResourceType,
    relative_path: []const u8,
    state: OverrideState,
};

fn mutateResourceConfiguration(
    gpa: std.mem.Allocator,
    configured_ptr: *[]packages.Package,
    mutation: ResourceMutation,
) !void {
    var configured = configured_ptr.*;
    var target_index: ?usize = null;
    for (configured, 0..) |package, index| if (packageSelectorMatches(package, mutation.package_selector)) {
        target_index = index;
        break;
    };

    if (mutation.write_scope == .project and target_index == null) {
        const user = try packages.listScope(
            gpa,
            mutation.io,
            mutation.agent_dir,
            mutation.cwd,
            .user,
            mutation.project_trusted,
        );
        defer freePackages(gpa, user);
        var source_package: ?packages.Package = null;
        for (user) |package| if (packageSelectorMatches(package, mutation.package_selector)) {
            source_package = package;
            break;
        };
        if (source_package == null) return error.PackageNotFound;
        for (configured, 0..) |project_package, index| {
            if (try packages.sameIdentity(gpa, project_package, source_package.?)) {
                target_index = index;
                break;
            }
        }
        if (target_index == null) {
            if (mutation.state == .inherit) return;
            var delta = try cloneProjectDelta(gpa, source_package.?);
            errdefer delta.deinit(gpa);
            configured = try gpa.realloc(configured, configured.len + 1);
            configured_ptr.* = configured;
            configured[configured.len - 1] = delta;
            target_index = configured.len - 1;
        }
    }

    const index = target_index orelse return error.PackageNotFound;
    try setExactPattern(gpa, &configured[index], mutation.resource_type, mutation.relative_path, mutation.state);

    if (mutation.write_scope == .project and !configured[index].autoload and !hasAnyPatterns(configured[index])) {
        const replacement = try gpa.alloc(packages.Package, configured.len - 1);
        if (index > 0) std.mem.copyForwards(packages.Package, replacement[0..index], configured[0..index]);
        if (index + 1 < configured.len) {
            std.mem.copyForwards(packages.Package, replacement[index..], configured[index + 1 ..]);
        }
        configured[index].deinit(gpa);
        gpa.free(configured);
        configured = replacement;
        configured_ptr.* = configured;
    }
}

/// Persist one exact resource decision. User scope accepts load/unload.
/// Project scope additionally accepts inherit, creating or pruning an
/// autoload=false project delta as required. The complete read/modify/write
/// transaction occurs under the package-operation lock.
pub fn setResource(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    write_scope: packages.Scope,
    project_trusted: bool,
    package_selector: []const u8,
    resource_type: ResourceType,
    relative_path: []const u8,
    state: OverrideState,
) !void {
    if (write_scope == .temporary) return error.TemporaryPackageNotPersistent;
    if (write_scope == .project and !project_trusted) return error.ProjectNotTrusted;
    if (write_scope == .user and state == .inherit) return error.InvalidGlobalResourceState;
    if (std.mem.startsWith(u8, package_selector, "top-level:")) {
        return top_level_resources.setResource(
            gpa,
            io,
            agent_dir,
            cwd,
            write_scope,
            project_trusted,
            package_selector,
            resource_type,
            relative_path,
            state,
        );
    }
    if (relative_path.len == 0 or std.fs.path.isAbsolute(relative_path)) return error.InvalidResourcePath;

    try packages.updateScopeConfiguration(
        gpa,
        io,
        agent_dir,
        cwd,
        write_scope,
        project_trusted,
        ResourceMutation{
            .io = io,
            .agent_dir = agent_dir,
            .cwd = cwd,
            .write_scope = write_scope,
            .project_trusted = project_trusted,
            .package_selector = package_selector,
            .resource_type = resource_type,
            .relative_path = relative_path,
            .state = state,
        },
        mutateResourceConfiguration,
    );
}

pub fn parseResourceType(value: []const u8) ?ResourceType {
    inline for (.{ ResourceType.extensions, ResourceType.skills, ResourceType.prompts, ResourceType.themes }) |resource_type| {
        if (std.ascii.eqlIgnoreCase(value, @tagName(resource_type))) return resource_type;
    }
    return null;
}

pub fn parseOverrideState(value: []const u8) ?OverrideState {
    if (std.ascii.eqlIgnoreCase(value, "inherit")) return .inherit;
    if (std.ascii.eqlIgnoreCase(value, "load") or std.ascii.eqlIgnoreCase(value, "on") or std.ascii.eqlIgnoreCase(value, "enable")) return .load;
    if (std.ascii.eqlIgnoreCase(value, "unload") or std.ascii.eqlIgnoreCase(value, "off") or std.ascii.eqlIgnoreCase(value, "disable")) return .unload;
    return null;
}

fn writeFixturePackage(gpa: std.mem.Allocator, io: Io, root: []const u8) !struct { package_root: []u8, extension: []u8 } {
    const package_root = try std.fs.path.join(gpa, &.{ root, "package" });
    errdefer gpa.free(package_root);
    const extension = try std.fs.path.join(gpa, &.{ package_root, "extensions", "demo.ts" });
    errdefer gpa.free(extension);
    try std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(extension).?);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = extension, .data = "export default () => {};" });
    const package_json = try std.fs.path.join(gpa, &.{ package_root, "package.json" });
    defer gpa.free(package_json);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = package_json, .data =
        \\{"name":"demo","pi":{"extensions":["extensions/*.ts"]}}
    });
    return .{ .package_root = package_root, .extension = extension };
}

test "global package config retains disabled resources and persists exact toggles" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const agent = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent);
    const fixture = try writeFixturePackage(gpa, io, root);
    defer gpa.free(fixture.package_root);
    defer gpa.free(fixture.extension);

    var installed = try packages.install(gpa, io, agent, fixture.package_root, root);
    installed.deinit(gpa);
    try setResource(gpa, io, agent, root, .user, true, "demo", .extensions, "extensions/demo.ts", .unload);

    var inventory = try discover(gpa, io, agent, root, .user, true);
    defer inventory.deinit();
    try std.testing.expectEqual(@as(usize, 1), inventory.resources.len);
    try std.testing.expect(!inventory.resources[0].enabled);
    try std.testing.expectEqual(OverrideState.unload, inventory.resources[0].override_state);
    try std.testing.expectEqualStrings("extensions/demo.ts", inventory.resources[0].relative_path);
}

test "shared inventory includes package and top-level origins" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const agent = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent);
    const fixture = try writeFixturePackage(gpa, io, root);
    defer gpa.free(fixture.package_root);
    defer gpa.free(fixture.extension);
    var installed = try packages.install(gpa, io, agent, fixture.package_root, root);
    installed.deinit(gpa);

    const local_extension = try std.fs.path.join(gpa, &.{ agent, "extensions", "local.ts" });
    defer gpa.free(local_extension);
    try std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(local_extension).?);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = local_extension, .data = "export default () => {};\n" });

    var inventory = try discover(gpa, io, agent, root, .user, true);
    defer inventory.deinit();
    var package_seen = false;
    var top_level_seen = false;
    for (inventory.resources) |resource| switch (resource.origin) {
        .package => {
            package_seen = true;
            try std.testing.expect(!std.mem.startsWith(u8, resource.selector, "top-level:"));
        },
        .top_level => {
            top_level_seen = true;
            try std.testing.expect(std.mem.startsWith(u8, resource.selector, "top-level:user:auto:"));
            try std.testing.expectEqualStrings("extensions/local.ts", resource.relative_path);
        },
    };
    try std.testing.expect(package_seen);
    try std.testing.expect(top_level_seen);
}

test "project package config cycles exact override back to inheritance" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const agent = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent);
    const fixture = try writeFixturePackage(gpa, io, root);
    defer gpa.free(fixture.package_root);
    defer gpa.free(fixture.extension);

    var installed = try packages.install(gpa, io, agent, fixture.package_root, root);
    installed.deinit(gpa);
    try setResource(gpa, io, agent, root, .project, true, "demo", .extensions, "extensions/demo.ts", .unload);
    var project_inventory = try discover(gpa, io, agent, root, .project, true);
    try std.testing.expectEqual(@as(usize, 1), project_inventory.resources.len);
    try std.testing.expect(!project_inventory.resources[0].enabled);
    try std.testing.expect(project_inventory.resources[0].inherited_enabled);
    try std.testing.expectEqual(OverrideState.unload, project_inventory.resources[0].override_state);
    project_inventory.deinit();

    try setResource(gpa, io, agent, root, .project, true, "demo", .extensions, "extensions/demo.ts", .inherit);
    const configured = try packages.listScope(gpa, io, agent, root, .project, true);
    defer freePackages(gpa, configured);
    try std.testing.expectEqual(@as(usize, 0), configured.len);
}

test "locked configuration updates preserve independent selectors" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const agent = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent);
    const package_root = try std.fs.path.join(gpa, &.{ root, "package" });
    defer gpa.free(package_root);
    const extensions = try std.fs.path.join(gpa, &.{ package_root, "extensions" });
    defer gpa.free(extensions);
    try std.Io.Dir.cwd().createDirPath(io, extensions);
    inline for (.{ "a.ts", "b.ts" }) |name| {
        const path = try std.fs.path.join(gpa, &.{ extensions, name });
        defer gpa.free(path);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "export default () => {};" });
    }
    const package_json = try std.fs.path.join(gpa, &.{ package_root, "package.json" });
    defer gpa.free(package_json);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = package_json, .data =
        \\{"name":"locked-demo","pi":{"extensions":["extensions/*.ts"]}}
    });

    var installed = try packages.install(gpa, io, agent, package_root, root);
    installed.deinit(gpa);
    try setResource(gpa, io, agent, root, .user, true, "locked-demo", .extensions, "extensions/a.ts", .unload);
    try setResource(gpa, io, agent, root, .user, true, "locked-demo", .extensions, "extensions/b.ts", .unload);

    const configured = try packages.listScope(gpa, io, agent, root, .user, true);
    defer freePackages(gpa, configured);
    try std.testing.expectEqual(@as(usize, 1), configured.len);
    try std.testing.expectEqual(@as(usize, 2), configured[0].extensions.?.len);
    try std.testing.expectEqualStrings("-extensions/a.ts", configured[0].extensions.?[0]);
    try std.testing.expectEqualStrings("-extensions/b.ts", configured[0].extensions.?[1]);
}
