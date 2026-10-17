//! Once-per-Engine canonical consumed jiti dependency graph. Real native
//! pathe/MLLY/syntax/crypto/colors/utils bodies and actual platform inputs only.
//! No public builtin/package registration, selector, C/Engine edit or fake TTY.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const module_key = "#pi-native:jiti2.7-shared-dependencies";
const profile = @import("native_jiti_profile.zig");
pub const Inputs = struct {
    /// Actual completed module export records/namespaces, including .default.
    filesystem: c.JSValue,
    node_path: c.JSValue,
    node_url: c.JSValue,
    tty: c.JSValue,
    /// Actual process default object and canonical Node24 builtinModules array.
    process: c.JSValue,
    builtin_modules: c.JSValue,
};
pub const Exports = struct {
    pathe: c.JSValue,
    pathe_utils: c.JSValue,
    mlly: c.JSValue,
    utilities: c.JSValue,
    /// Exact qualified ordinary raw C3 binding for SDK lazy import helpers.
    dynamic_import: c.JSValue,
    /// Actual consumed export objects for the real builtin/package assembler.
    /// They are not advertised as complete public node:crypto/yoctocolors APIs.
    crypto_bindings: c.JSValue,
    color_bindings: c.JSValue,
    pub fn deinit(self: Exports, engine: *v.em.Engine) void {
        inline for (std.meta.fields(Exports)) |field| engine.freeValue(@field(self, field.name));
    }
};
pub const JitiInputs = struct {
    shared: Inputs,
    node_module: c.JSValue,
    node_os: c.JSValue,
    performance: c.JSValue,
    library_require: c.JSValue,
    package_json: c.JSValue,
    physical_filename: c.JSValue,
    module_url: c.JSValue,
    babel_filename: c.JSValue,
    std_env_is_windows: bool,
};
/// Actual concrete caller of profile.prepare. It does not expose a namespace:
/// the owning real module calls revision2 complete only after the actual Node
/// lazy-provider/createRequire/compiler dependencies are assembled.
pub fn prepareJiti(engine: *v.em.Engine, actual: JitiInputs) !profile.Prepared {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    const shared = try create(engine, actual.shared); defer shared.deinit(engine);
    const catalog = try takeSuccess(engine, try v.js.get(engine, actual.node_module, "builtinModules")); defer engine.freeValue(catalog);
    if (!c.JS_IsStrictEqual(engine.context, catalog, actual.shared.builtin_modules)) return error.MismatchedCanonicalJitiBuiltinModules;
    return profile.prepare(engine, .{ .filesystem = actual.shared.filesystem, .node_url = actual.shared.node_url,
        .node_module = actual.node_module, .node_os = actual.node_os,
        .pathe = shared.pathe, .pathe_utils = shared.pathe_utils, .mlly = shared.mlly,
        .utilities = shared.utilities, .performance = actual.performance, .library_require = actual.library_require,
        .package_json = actual.package_json, .physical_filename = actual.physical_filename,
        .module_url = actual.module_url, .babel_filename = actual.babel_filename,
        .std_env_is_windows = actual.std_env_is_windows });
}
const Phase = enum { initializing, ready };
const State = struct { engine: *v.em.Engine, class_id: c.JSClassID, phase: Phase, inputs: Inputs, exports: Exports };
fn undefinedExports() Exports { var result: Exports = undefined; inline for (std.meta.fields(Exports)) |field| @field(result, field.name) = c.pi_js_undefined(); return result; }
fn finalize(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    const engine = state.engine;
    inline for (std.meta.fields(Inputs)) |field| c.JS_FreeValueRT(runtime, @field(state.inputs, field.name));
    inline for (std.meta.fields(Exports)) |field| c.JS_FreeValueRT(runtime, @field(state.exports, field.name));
    engine.gpa.destroy(state); c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
}
fn mark(runtime: ?*c.JSRuntime, holder: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    inline for (std.meta.fields(Inputs)) |field| c.JS_MarkValue(runtime, @field(state.inputs, field.name), marker);
    inline for (std.meta.fields(Exports)) |field| c.JS_MarkValue(runtime, @field(state.exports, field.name), marker);
}
fn takeSuccess(engine: *v.em.Engine, owned: c.JSValue) !c.JSValue {
    if (c.JS_HasException(engine.context)) {
        const pending = c.JS_GetException(engine.context); engine.freeValue(owned);
        return engine.checked(c.JS_Throw(engine.context, pending));
    }
    return owned;
}
fn get(s: *v.Scope, namespace: c.JSValue, name: [*:0]const u8) !c.JSValue { return s.own(try takeSuccess(s.engine, try v.js.get(s.engine, namespace, name))); }
fn function(s: *v.Scope, namespace: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const result = try get(s, namespace, name);
    if (!c.JS_IsFunction(s.engine.context, result)) return error.RequiredActualJitiSharedBinding;
    return result;
}
fn publication(s: *v.Scope, actual: c.JSValue, comptime names: anytype) !c.JSValue {
    const result = try s.object();
    inline for (names) |name| if (c.JS_DefinePropertyValueStr(s.engine.context, result, name,
        c.JS_DupValue(s.engine.context, try function(s, actual, name)), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
    return result;
}
fn ownHolder(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
    var attached = false; errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
    const state = try engine.gpa.create(State); errdefer if (!attached) engine.gpa.destroy(state);
    var id: c.JSClassID = 0; if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Private actual jiti shared dependency owner", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const holder = try engine.checked(c.JS_NewObjectProtoClass(engine.context, c.pi_js_null(), id));
    var retained: Inputs = undefined;
    inline for (std.meta.fields(Inputs)) |field| @field(retained, field.name) = c.JS_DupValue(engine.context, @field(inputs, field.name));
    state.* = .{ .engine = engine, .class_id = id, .phase = .initializing, .inputs = retained, .exports = undefinedExports() };
    _ = c.JS_SetOpaque(holder, state); attached = true;
    return holder;
}
fn stateOf(engine: *v.em.Engine, holder: c.JSValue) !*State {
    const id = c.JS_GetClassID(holder);
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, id) orelse return error.InvalidJitiSharedDependencyOwner));
    if (state.engine != engine or state.class_id != id) return error.ForeignJitiSharedDependencyOwner;
    return state;
}
fn duplicate(engine: *v.em.Engine, exports: Exports) Exports {
    var result: Exports = undefined;
    inline for (std.meta.fields(Exports)) |field| @field(result, field.name) = c.JS_DupValue(engine.context, @field(exports, field.name));
    return result;
}
/// No Source exports or package names are installed until actual owners choose
/// to consume this completed graph. The private in-progress owner is not a
/// registered module and contains no dummy outputs. Reentry fails closed;
/// failed initialization removes its reservation and releases retained roots.
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Exports {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    if (engine.native_module_values.get(module_key)) |holder| {
        const state = try stateOf(engine, holder);
        if (state.phase != .ready) return error.JitiSharedDependenciesInitializing;
        inline for (std.meta.fields(Inputs)) |field| if (!c.JS_IsStrictEqual(engine.context, @field(inputs, field.name), @field(state.inputs, field.name))) return error.JitiSharedDependenciesImportsChanged;
        if (engine.native_module_values.get("node:crypto")) |actual_crypto| {
            const actual_default = try takeSuccess(engine, try v.js.get(engine, actual_crypto, "default")); defer engine.freeValue(actual_default);
            if (!c.JS_IsStrictEqual(engine.context, actual_default, state.exports.crypto_bindings)) return error.JitiSharedCryptoIdentityChanged;
        }
        return duplicate(engine, state.exports);
    }
    // Reserve host map capacity before any Source getter. Static private key:
    // it is not in native_module_names and requires no separately owned key.
    try engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1);
    const holder = try ownHolder(engine, inputs); defer engine.freeValue(holder);
    engine.native_module_values.putAssumeCapacity(module_key, c.JS_DupValue(engine.context, holder));
    errdefer if (engine.native_module_values.fetchRemove(module_key)) |entry| engine.freeValue(entry.value);
    const state = try stateOf(engine, holder);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const fs_default = try get(&s, inputs.filesystem, "default");
    const path_default = try get(&s, inputs.node_path, "default");
    const tty_default = try get(&s, inputs.tty, "default");
    if (!c.JS_IsObject(fs_default) or !c.JS_IsObject(path_default) or !c.JS_IsObject(tty_default) or !c.JS_IsObject(inputs.process) or !c.JS_IsArray(inputs.builtin_modules)) return error.RequiredActualJitiPlatformNamespaces;
    // The actual named export survives legitimate guest edits of the mutable
    // default object's optional chain. An empty/missing TTY module is never
    // supplied merely to force the Source false-color fallback.
    _ = try function(&s, inputs.tty, "WriteStream");
    const file_url_to_path = try function(&s, inputs.node_url, "fileURLToPath");
    const path_to_file_url = try function(&s, inputs.node_url, "pathToFileURL");
    const stat_sync = try function(&s, inputs.filesystem, "statSync");
    const realpath_sync = try function(&s, inputs.filesystem, "realpathSync");
    inline for (.{ "lstatSync", "accessSync", "readFileSync" }) |name| _ = try function(&s, inputs.filesystem, name);
    const constants = try get(&s, inputs.filesystem, "constants"); if (!c.JS_IsObject(constants)) return error.RequiredActualJitiFilesystemConstants;
    const pathe = try s.own(try takeSuccess(engine, try @import("native_pathe.zig").create(engine)));
    const mlly = try s.own(try takeSuccess(engine, try @import("native_mlly_resolve.zig").create(engine, .{
        .fs = fs_default, .path = path_default, .process = inputs.process, .builtin_modules = inputs.builtin_modules,
        .file_url_to_path = file_url_to_path, .path_to_file_url = path_to_file_url, .stat_sync = stat_sync, .realpath_sync = realpath_sync,
        .pathe_is_absolute = try function(&s, pathe, "isAbsolute"), .pathe_normalize = try function(&s, pathe, "normalize") })));
    const syntax = try s.own(try takeSuccess(engine, try @import("native_mlly_syntax.zig").create(engine)));
    if (c.JS_DefinePropertyValueStr(engine.context, mlly, "hasESMSyntax", c.JS_DupValue(engine.context, syntax), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    // Preserve an existing actual crypto default-object identity. If bootstrap
    // has not assembled it yet, construct the real consumed provider and return
    // that SAME object to its module owner for later genuine publication.
    const crypto = if (engine.native_module_values.get("node:crypto")) |actual_crypto|
        try get(&s, actual_crypto, "default") else
        try s.own(try takeSuccess(engine, try @import("native_jiti_crypto.zig").create(engine)));
    _ = try function(&s, crypto, "createHash");
    const colors = try s.own(try takeSuccess(engine, try @import("native_jiti_colors.zig").create(engine, tty_default)));
    const utilities = try s.own(try takeSuccess(engine, try @import("native_jiti_utils.zig").create(engine, .{ .filesystem = inputs.filesystem, .paths = pathe, .node_crypto = crypto, .colors = colors })));
    const dynamic_import = try s.own(try takeSuccess(engine, try @import("native_extension_dynamic_import_graph0.zig").create(engine)));
    const path_exports = try publication(&s, pathe, .{ "normalize", "join", "dirname", "basename", "extname", "isAbsolute", "resolve" });
    const utility_exports = try publication(&s, pathe, .{ "normalizeAliases", "resolveAlias", "filename" });
    // All actual guest initialization (including hasColors +15 debug colors)
    // completes before creating any namespace. Existing Engine namespace/C
    // module lifetime/await policy applies; no new graph-GC claim is made.
    state.exports.pathe = try takeSuccess(engine, try engine.valueNamespace(path_exports));
    state.exports.pathe_utils = try takeSuccess(engine, try engine.valueNamespace(utility_exports));
    state.exports.mlly = try takeSuccess(engine, try engine.valueNamespace(mlly));
    state.exports.utilities = try takeSuccess(engine, try engine.valueNamespace(utilities));
    state.exports.dynamic_import = c.JS_DupValue(engine.context, dynamic_import);
    state.exports.crypto_bindings = c.JS_DupValue(engine.context, crypto);
    state.exports.color_bindings = c.JS_DupValue(engine.context, colors);
    state.phase = .ready;
    return duplicate(engine, state.exports);
}
