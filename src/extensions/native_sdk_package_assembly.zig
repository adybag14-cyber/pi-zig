//! Complete actual Source method assembly. Actual ignore/minimatch/semver/Git
//! and platform inputs remain mandatory. Shape/brand checks are prerequisites,
//! never a provenance or qualification claim; no default selection happens.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const order = @import("native_sdk_package_declaration_order.zig");
const manager = @import("native_sdk_package_manager.zig");
pub const Inputs = struct {
    paths: c.JSValue,
    filesystem: c.JSValue,
    process: c.JSValue,
    os: c.JSValue,
    path_utilities: c.JSValue,
    text: c.JSValue,
    crypto: c.JSValue,
    semver: c.JSValue,
    git: c.JSValue,
    ignore: c.JSValue,
    minimatch: c.JSValue,
    config_dir: c.JSValue,
    transport: @import("native_sdk_package_transport.zig").Inputs,
};
fn required(s: *Scope, namespace: c.JSValue, name: [*:0]const u8) !c.JSValue { if (!c.JS_IsObject(namespace)) return error.RequiredActualPackageAssemblyNamespace; const value = try s.get(namespace, name); if (!c.JS_IsFunction(s.engine.context, value)) return error.RequiredActualPackageAssemblyFunction; return value; }
fn expectedAsync(comptime name: []const u8) bool { inline for (order.async_names) |value| if (std.mem.eql(u8, name, value)) return true; return false; }
fn copy(s: *Scope, staging: c.JSValue, prototype: c.JSValue, comptime name: [:0]const u8) !void {
    const atom = c.JS_NewAtom(s.engine.context, name.ptr); if (atom == c.JS_ATOM_NULL) return v.js.capture(s.engine); defer c.JS_FreeAtom(s.engine.context, atom);
    var descriptor: c.JSPropertyDescriptor = undefined; const found = c.JS_GetOwnProperty(s.engine.context, &descriptor, staging, atom); if (found < 0) return v.js.capture(s.engine); if (found == 0) return error.RequiredActualCompletePackageMethod;
    defer s.engine.freeValue(descriptor.value); defer s.engine.freeValue(descriptor.getter); defer s.engine.freeValue(descriptor.setter);
    if (descriptor.flags & c.JS_PROP_GETSET != 0 or !c.JS_IsFunction(s.engine.context, descriptor.value)) return error.RequiredActualPackageClassMethod;
    if ((c.JS_IsAsyncFunction(descriptor.value) != 0) != expectedAsync(name)) return error.RequiredGenuinePackageAsyncBrand;
    const flags = descriptor.flags | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_ENUMERABLE | c.JS_PROP_HAS_WRITABLE | c.JS_PROP_HAS_VALUE;
    if (c.JS_DefineProperty(s.engine.context, prototype, atom, descriptor.value, descriptor.getter, descriptor.setter, flags) < 0) return v.js.capture(s.engine);
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (!c.JS_IsFunction(engine.context, inputs.ignore) or !c.JS_IsFunction(engine.context, inputs.minimatch) or !c.JS_IsString(inputs.config_dir)) return error.RequiredActualPackagePatternImplementations;
    const staging = try s.object();
    const read_manifest = try s.own(try @import("native_sdk_pi_manifest.zig").create(engine));
    const patterns = try s.own(try @import("native_sdk_package_patterns.zig").create(engine, .{ .paths = inputs.paths, .normalize_path = try required(&s, inputs.path_utilities, "normalizePath"), .minimatch = inputs.minimatch }));
    const discovery = try s.own(try @import("native_sdk_package_discovery.zig").create(engine, .{ .paths = inputs.paths, .filesystem = inputs.filesystem, .ignore = inputs.ignore, .read_pi_manifest = read_manifest, .homedir = try required(&s, inputs.os, "homedir"), .process = inputs.process }));
    const source = try s.own(try @import("native_sdk_package_source.zig").install(engine, staging, .{ .process = inputs.process, .is_local_path = try required(&s, inputs.path_utilities, "isLocalPath"), .parse_git_url = try required(&s, inputs.git, "parseGitUrl"), .valid = try required(&s, inputs.semver, "valid"), .valid_range = try required(&s, inputs.semver, "validRange") }));
    const exists_sync = try required(&s, inputs.filesystem, "existsSync");
    try manager.installProgress(engine, staging);
    try @import("native_sdk_package_accumulator.zig").install(engine, staging);
    try @import("native_sdk_package_identity.zig").install(engine, staging);
    try @import("native_sdk_package_paths.zig").install(engine, staging, inputs.config_dir);
    try @import("native_sdk_package_commands.zig").install(engine, staging, .{ .basename = try required(&s, inputs.paths, "basename"), .exists_sync = exists_sync });
    try @import("native_sdk_package_settings.zig").install(engine, staging, .{ .exists_sync = exists_sync, .relative = try required(&s, inputs.paths, "relative") });
    try @import("native_sdk_package_storage.zig").install(engine, staging, .{ .paths = inputs.paths, .filesystem = inputs.filesystem, .create_hash = try required(&s, inputs.crypto, "createHash"), .mark_cloud_ignored = try required(&s, inputs.path_utilities, "markPathIgnoredByCloudSync"), .strip_bom = try required(&s, inputs.text, "stripBom"), .config_dir = inputs.config_dir });
    try @import("native_sdk_package_concurrency.zig").install(engine, staging);
    const resource_helpers = try s.own(try v.js.spread(engine, discovery)); try v.js.spreadInto(engine, resource_helpers, patterns); try s.put(resource_helpers, "readPiManifest", read_manifest);
    try @import("native_sdk_package_resources.zig").install(engine, staging, .{ .paths = inputs.paths, .filesystem = inputs.filesystem, .helpers = resource_helpers });
    try @import("native_sdk_package_autoload.zig").install(engine, staging, .{ .paths = inputs.paths, .discovery = discovery, .is_enabled_by_overrides = try required(&s, patterns, "isEnabledByOverrides") });
    const offline = try required(&s, source, "isOfflineModeEnabled");
    try @import("native_sdk_package_install.zig").install(engine, staging, .{ .exists_sync = exists_sync, .rm_sync = try required(&s, inputs.filesystem, "rmSync"), .is_offline = offline });
    try @import("native_sdk_package_versions.zig").install(engine, staging, .{ .exists_sync = exists_sync, .is_offline = offline, .satisfies = try required(&s, inputs.semver, "satisfies"), .gt = try required(&s, inputs.semver, "gt"), .max_satisfying = try required(&s, inputs.semver, "maxSatisfying"), .rcompare = try required(&s, inputs.semver, "rcompare") });
    try @import("native_sdk_package_git.zig").install(engine, staging, .{ .paths = inputs.paths, .filesystem = inputs.filesystem });
    try @import("native_sdk_package_updates.zig").install(engine, staging, .{ .is_offline = offline, .exists_sync = exists_sync });
    try @import("native_sdk_package_resolve_sources.zig").install(engine, staging, .{ .exists_sync = exists_sync, .is_offline = offline });
    try @import("native_sdk_package_resolve.zig").install(engine, staging, .{ .apply_autoload_disabled_patterns = try required(&s, patterns, "applyAutoloadDisabledPatterns"), .get_override_patterns = try required(&s, patterns, "getOverridePatterns"), .is_enabled_by_overrides = try required(&s, patterns, "isEnabledByOverrides"), .config_dir = inputs.config_dir });
    try @import("native_sdk_package_extension_sources.zig").install(engine, staging);
    try @import("native_sdk_package_transport.zig").install(engine, staging, inputs.transport);
    const prototype = try s.object();
    const constructor = try s.own(try manager.constructor(engine, prototype));
    inline for (order.names[1..]) |name| try copy(&s, staging, prototype, name);
    const exports = try s.object(); try s.put(exports, "DefaultPackageManager", constructor); try s.put(exports, "getExtensionTempFolder", try required(&s, discovery, "getExtensionTempFolder"));
    const graph = try s.object(); try s.put(graph, "exports", exports); try s.put(graph, "patterns", patterns); try s.put(graph, "discovery", discovery); try s.put(graph, "source", source); try s.put(graph, "resourceHelpers", resource_helpers);
    return c.JS_DupValue(engine.context, graph);
}
