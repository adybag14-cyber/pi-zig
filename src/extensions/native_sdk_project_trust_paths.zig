//! Complete private trust-manager.ts path/resource/option suppliers.
//! The application owner passes its genuine imported modules. The original
//! mutable resource array and import captures belong to one Engine evaluation;
//! no Store, policy decision, runtimeFactory or public namespace is fabricated.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const Engine = h.Engine;
const Scope = h.Scope;

pub const Inputs = struct {
    filesystem: c.JSValue,
    paths: c.JSValue,
    os: c.JSValue,
    path_utilities: c.JSValue,
    config_dir: c.JSValue,
};

const cache_key = "pi-private:actual-sdk-project-trust-paths";
const input_names = .{ "filesystem", "paths", "os", "path_utilities", "config_dir" };
const Creating = struct { engine: *Engine, previous: ?*Creating };
threadlocal var creating: ?*Creating = null;

pub fn create(engine: *Engine, inputs: Inputs) anyerror!c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached|
        return h.expression(engine, cachedBody, .{ cached, inputs });
    var cursor = creating;
    while (cursor) |current_creation| : (cursor = current_creation.previous)
        if (current_creation.engine == engine) return error.ActualProjectTrustPathsCreationReentry;
    var entry: Creating = .{ .engine = engine, .previous = creating };
    creating = &entry;
    defer creating = entry.previous;
    var invocation: Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const result = createOwned(engine, inputs) catch |err|
        return engine.checked(engine.leaveNativeInvocation(&invocation,
            @import("native_sdk.zig").fail(engine, err)));
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}

fn cachedBody(s: *Scope, cached: c.JSValue, inputs: Inputs) anyerror!c.JSValue {
    inline for (input_names) |name| {
        if (!v.equal(s, try v.get(s, cached, name), @field(inputs, name)))
            return error.ActualProjectTrustPathsImportsChanged;
    }
    return v.duplicate(s, try v.get(s, cached, "exports"));
}

fn createOwned(engine: *Engine, inputs: Inputs) anyerror!c.JSValue {
    const graph = try h.expression(engine, createBody, .{inputs});
    const exports_value = h.get(engine, graph, "exports") catch |err| {
        var completion = v.owned.Completion.initValue(engine, err);
        completion.release(graph);
        return completion.finishValue();
    };
    // All guest-capable imports, local retirement and export acquisition finish
    // before this single private publication. Reserve after possible reentry.
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = v.owned.Completion.initValue(engine, err);
        completion.release(exports_value);
        completion.release(graph);
        return completion.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, graph);
    return exports_value;
}

fn requiredFunction(s: *Scope, owner: c.JSValue, name: [*:0]const u8) anyerror!c.JSValue {
    const binding = try v.get(s, owner, name);
    if (!c.JS_IsFunction(s.engine.context, binding))
        return error.ActualProjectTrustPathImportRequired;
    return binding;
}

fn createBody(s: *Scope, inputs: Inputs) anyerror!c.JSValue {
    // Retain each real module before any imported property can execute guest JS.
    inline for (input_names) |name| _ = try v.own(s, v.duplicate(s, @field(inputs, name)));
    const exists_sync = try requiredFunction(s, inputs.filesystem, "existsSync");
    const home_dir = try requiredFunction(s, inputs.os, "homedir");
    const dirname = try requiredFunction(s, inputs.paths, "dirname");
    const join = try requiredFunction(s, inputs.paths, "join");
    const canonicalize = try requiredFunction(s, inputs.path_utilities, "canonicalizePath");
    const resolve = try requiredFunction(s, inputs.path_utilities, "resolvePath");
    const built = try fromCaptures(s, .{
        .exists_sync = exists_sync, .home_dir = home_dir, .dirname = dirname,
        .join = join, .canonicalize = canonicalize, .resolve = resolve,
        .config_dir = inputs.config_dir,
    });
    const exports_value = built.exports_value;
    const graph = try v.stateObject(s);
    inline for (input_names) |name| try v.put(s, graph, name, @field(inputs, name));
    try v.put(s, graph, "exports", exports_value);
    return v.duplicate(s, graph);
}

/// Scoped, already-rooted genuine named imports from one trust-manager
/// evaluation. No guest carrier or replacement import namespace is constructed.
pub const Captures = struct {
    exists_sync: c.JSValue, home_dir: c.JSValue, dirname: c.JSValue,
    join: c.JSValue, canonicalize: c.JSValue, resolve: c.JSValue,
    config_dir: c.JSValue,
};
pub const Built = struct { exports_value: c.JSValue, normalize_function: c.JSValue };

/// Both values are borrowed from s. The complete module also uses this exact
/// normalize function for its Store callbacks; all operation bodies stay shared.
pub fn fromCaptures(s: *Scope, imports: Captures) anyerror!Built {
    try s.engine.checkNativeEntry();
    const exists_sync = imports.exists_sync;
    const home_dir = imports.home_dir;
    const dirname = imports.dirname;
    const join = imports.join;
    const canonicalize = imports.canonicalize;
    const resolve = imports.resolve;
    const resource_names = try v.array(s);
    inline for (.{
        "settings.json", "mcp.json", "extensions", "skills",
        "prompts", "themes", "SYSTEM.md", "APPEND_SYSTEM.md",
    }, 0..) |name, index| try v.index(s, resource_names, @intCast(index), try v.text(s, name));
    const normalize_function = try v.ordinary(s, "normalizeCwd", 1, normalizeCallback,
        &.{ canonicalize, resolve });
    const parent_function = try v.ordinary(s, "getProjectTrustParentPath", 1,
        parentCallback, &.{ normalize_function, dirname });
    const options_function = try v.ordinary(s, "getProjectTrustOptions", 2,
        optionsCallback, &.{ normalize_function, parent_function });
    const resources_function = try v.ordinary(s, "hasTrustRequiringProjectResources", 1,
        resourcesCallback, &.{
            exists_sync, home_dir, dirname, join, imports.config_dir,
            canonicalize, resolve, resource_names,
        });
    const exports_value = try v.object(s);
    try v.put(s, exports_value, "getProjectTrustParentPath", parent_function);
    try v.put(s, exports_value, "getProjectTrustOptions", options_function);
    try v.put(s, exports_value, "hasTrustRequiringProjectResources", resources_function);
    return .{ .exports_value = exports_value, .normalize_function = normalize_function };
}

fn normalizeCallback(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return h.expression(engine, normalizeBody, .{ roots[0], roots[1], v.arg(args, 0) });
}
fn normalizeBody(s: *Scope, canonicalize: c.JSValue, resolve: c.JSValue,
    cwd: c.JSValue) anyerror!c.JSValue
{
    const resolved = try v.call(s, resolve, c.pi_js_undefined(), &.{cwd});
    return v.duplicate(s, try v.call(s, canonicalize, c.pi_js_undefined(), &.{resolved}));
}
fn callOwned(engine: *Engine, function_value: c.JSValue,
    args: []const c.JSValue) anyerror!c.JSValue
{
    return h.expression(engine, callBody, .{ function_value, args });
}
fn callBody(s: *Scope, function_value: c.JSValue,
    args: []const c.JSValue) anyerror!c.JSValue
{
    return v.duplicate(s, try v.call(s, function_value, c.pi_js_undefined(), args));
}

const ParentFrame = h.Frame(enum { trust_path, parent_dir });
fn parentCallback(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    var frame = ParentFrame.init(engine);
    return frame.finish(parentBody(&frame, v.arg(args, 0), roots));
}
fn parentBody(frame: *ParentFrame, cwd: c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    try frame.set(.trust_path, callOwned(frame.engine, roots[0], &.{cwd}));
    try frame.set(.parent_dir, callOwned(frame.engine, roots[1], &.{frame.get(.trust_path)}));
    if (c.JS_IsStrictEqual(frame.engine.context, frame.get(.parent_dir), frame.get(.trust_path)))
        return c.pi_js_undefined();
    return h.duplicate(frame.engine, frame.get(.parent_dir));
}

const OptionKind = enum { trust, parent, trust_session, distrust, distrust_session };
fn updateRow(s: *Scope, path_value: c.JSValue, decision: c.JSValue) anyerror!c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "path", path_value);
    try v.put(s, result, "decision", decision);
    return result;
}
fn optionRow(s: *Scope, trust_path: c.JSValue, parent_path: c.JSValue,
    comptime kind: OptionKind) anyerror!c.JSValue
{
    const result = try v.object(s);
    const label = if (kind == .parent) blk: {
        const text = try v.stringify(s, parent_path);
        const prefix = try v.binary(s, 0, try v.text(s, "Trust parent folder ("), text);
        break :blk try v.binary(s, 0, prefix, try v.text(s, ")"));
    } else try v.text(s, switch (kind) {
        .trust => "Trust", .trust_session => "Trust (this session only)",
        .distrust => "Do not trust", .distrust_session => "Do not trust (this session only)",
        .parent => unreachable,
    });
    try v.put(s, result, "label", label);
    const trusted = kind == .trust or kind == .parent or kind == .trust_session;
    try v.put(s, result, "trusted", v.boolean(s, trusted));
    const updates = try v.array(s);
    const session_only = kind == .trust_session or kind == .distrust_session;
    if (!session_only) {
        try v.index(s, updates, 0, try updateRow(s,
            if (kind == .parent) parent_path else trust_path, v.boolean(s, trusted)));
        if (kind == .parent)
            try v.index(s, updates, 1, try updateRow(s, trust_path, c.pi_js_null()));
    }
    try v.put(s, result, "updates", updates);
    if (!session_only)
        try v.put(s, result, "savedPath", if (kind == .parent) parent_path else trust_path);
    return result;
}
fn firstOptionsBody(s: *Scope, trust_path: c.JSValue) anyerror!c.JSValue {
    const result = try v.array(s);
    try v.index(s, result, 0, try optionRow(s, trust_path, c.pi_js_undefined(), .trust));
    return v.duplicate(s, result);
}
fn pushOptionBody(s: *Scope, target: c.JSValue, trust_path: c.JSValue,
    parent_path: c.JSValue, comptime kind: OptionKind) anyerror!void
{
    // Original Get(push) happens before its object-literal argument is built.
    const push = try v.get(s, target, "push");
    const row = try optionRow(s, trust_path, parent_path, kind);
    _ = try v.call(s, push, target, &.{row});
}
fn includeSessionBody(s: *Scope, options_value: c.JSValue) anyerror!c.JSValue {
    return v.boolean(s, !v.nullish(options_value) and
        v.truthy(s, try v.get(s, options_value, "includeSessionOnly")));
}
const OptionsFrame = h.Frame(enum { trust_path, trust_options, parent_path });
fn optionsCallback(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    var frame = OptionsFrame.init(engine);
    return frame.finish(optionsBody(&frame, v.arg(args, 0), v.arg(args, 1), roots));
}
fn optionsBody(frame: *OptionsFrame, cwd: c.JSValue, options_value: c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    const engine = frame.engine;
    try frame.set(.trust_path, callOwned(engine, roots[0], &.{cwd}));
    try frame.set(.trust_options, h.expression(engine, firstOptionsBody, .{frame.get(.trust_path)}));
    // This is a second normalization, as in getProjectTrustParentPath(cwd).
    try frame.set(.parent_path, callOwned(engine, roots[1], &.{cwd}));
    if (!c.JS_IsUndefined(frame.get(.parent_path)))
        try h.statement(engine, pushOptionBody, .{
            frame.get(.trust_options), frame.get(.trust_path), frame.get(.parent_path), .parent,
        });
    if (h.truthy(engine, try h.expression(engine, includeSessionBody, .{options_value})))
        try h.statement(engine, pushOptionBody, .{
            frame.get(.trust_options), frame.get(.trust_path), frame.get(.parent_path), .trust_session,
        });
    try h.statement(engine, pushOptionBody, .{
        frame.get(.trust_options), frame.get(.trust_path), frame.get(.parent_path), .distrust,
    });
    // Keep this second optional Get separate, including its possible reentry.
    if (h.truthy(engine, try h.expression(engine, includeSessionBody, .{options_value})))
        try h.statement(engine, pushOptionBody, .{
            frame.get(.trust_options), frame.get(.trust_path), frame.get(.parent_path), .distrust_session,
        });
    return h.duplicate(engine, frame.get(.trust_options));
}

const ResourceImport = enum { exists_sync, home_dir, dirname, join, config_dir, canonicalize, resolve, resource_names };
fn resourceRoot(roots: []const c.JSValue, comptime name: ResourceImport) c.JSValue {
    return roots[@intFromEnum(name)];
}
fn homeBody(s: *Scope, roots: []const c.JSValue) anyerror!c.JSValue {
    // process is an ordinary live global in the original module, not a frozen
    // HOME string or a captured replacement. The imported homedir is separate.
    const process = try v.global(s, "process");
    const environment = try v.get(s, process, "env");
    const supplied_home = try v.get(s, environment, "HOME");
    const home = if (v.truthy(s, supplied_home)) supplied_home else
        try v.call(s, resourceRoot(roots, .home_dir), c.pi_js_undefined(), &.{});
    return normalizeBody(s, resourceRoot(roots, .canonicalize),
        resourceRoot(roots, .resolve), home);
}
fn resourceCwdBody(s: *Scope, roots: []const c.JSValue, cwd: c.JSValue) anyerror!c.JSValue {
    return normalizeBody(s, resourceRoot(roots, .canonicalize), resourceRoot(roots, .resolve), cwd);
}
fn skillsPathBody(s: *Scope, roots: []const c.JSValue, directory: c.JSValue) anyerror!c.JSValue {
    return v.duplicate(s, try v.call(s, resourceRoot(roots, .join), c.pi_js_undefined(),
        &.{ directory, try v.text(s, ".agents"), try v.text(s, "skills") }));
}
fn configPathBody(s: *Scope, roots: []const c.JSValue, directory: c.JSValue) anyerror!c.JSValue {
    return v.duplicate(s, try v.call(s, resourceRoot(roots, .join), c.pi_js_undefined(),
        &.{ directory, resourceRoot(roots, .config_dir) }));
}
fn someCallback(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return h.expression(engine, someCallbackBody, .{ roots, v.arg(args, 0) });
}
fn someCallbackBody(s: *Scope, roots: []const c.JSValue, resource_name: c.JSValue) anyerror!c.JSValue {
    const joined = try v.call(s, roots[1], c.pi_js_undefined(), &.{ roots[2], resource_name });
    return v.duplicate(s, try v.call(s, roots[0], c.pi_js_undefined(), &.{joined}));
}
fn anyConfigBody(s: *Scope, roots: []const c.JSValue, directory: c.JSValue) anyerror!c.JSValue {
    const names = resourceRoot(roots, .resource_names);
    // Keep the original live Array.prototype.some Get and fresh arrow. A
    // replacement some may retain the arrow or mutate the private source array.
    const some = try v.get(s, names, "some");
    const callback = try v.arrow(s, "", 1, someCallback, &.{
        resourceRoot(roots, .exists_sync), resourceRoot(roots, .join), directory,
    });
    return v.duplicate(s, try v.call(s, some, names, &.{callback}));
}
fn hasSkillsBody(s: *Scope, roots: []const c.JSValue, skills_path: c.JSValue,
    user_skills_path: c.JSValue) anyerror!c.JSValue
{
    return v.boolean(s, !v.equal(s, skills_path, user_skills_path) and
        v.truthy(s, try v.call(s, resourceRoot(roots, .exists_sync),
            c.pi_js_undefined(), &.{skills_path})));
}
const ResourcesFrame = h.Frame(enum {
    home_dir, user_skills_dir, current_dir, config_dir, agents_skills_dir, parent_dir,
});
fn resourcesCallback(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    var frame = ResourcesFrame.init(engine);
    return frame.finish(resourcesBody(&frame, v.arg(args, 0), roots));
}
fn resourcesBody(frame: *ResourcesFrame, cwd: c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    const engine = frame.engine;
    try frame.set(.home_dir, h.expression(engine, homeBody, .{roots}));
    try frame.set(.user_skills_dir, h.expression(engine, skillsPathBody, .{ roots, frame.get(.home_dir) }));
    try frame.set(.current_dir, h.expression(engine, resourceCwdBody, .{ roots, cwd }));
    try frame.set(.config_dir, h.expression(engine, configPathBody, .{ roots, frame.get(.current_dir) }));
    const config_result = try h.expression(engine, anyConfigBody, .{ roots, frame.get(.config_dir) });
    // The original if consumes the returned value before entering the loop.
    var config_completion = v.owned.Completion.initVoid(engine, {});
    const has_config = h.truthy(engine, config_result);
    config_completion.release(config_result);
    try config_completion.finishVoid();
    if (has_config) return c.JS_NewBool(engine.context, true);
    var steps: usize = 0;
    while (true) {
        try v.poll(engine, &steps);
        try frame.set(.agents_skills_dir,
            h.expression(engine, skillsPathBody, .{ roots, frame.get(.current_dir) }));
        if (h.truthy(engine, try h.expression(engine, hasSkillsBody,
            .{ roots, frame.get(.agents_skills_dir), frame.get(.user_skills_dir) })))
            return c.JS_NewBool(engine.context, true);
        try frame.set(.parent_dir, callOwned(engine, resourceRoot(roots, .dirname),
            &.{frame.get(.current_dir)}));
        if (c.JS_IsStrictEqual(engine.context, frame.get(.parent_dir), frame.get(.current_dir)))
            return c.JS_NewBool(engine.context, false);
        try frame.set(.current_dir, h.duplicate(engine, frame.get(.parent_dir)));
    }
}
