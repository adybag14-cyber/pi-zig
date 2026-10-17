//! Explicit native consumed-profile composition of the REAL jiti declarations.
//! Completed actual dependency namespaces are required. No loader registration,
//! legacy CommonJS substitution, Graph2 alias or production default activation.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const public_factory = @import("native_jiti_public_factory.zig");
const resolving = @import("native_jiti_resolve.zig");
const cache = @import("native_jiti_fs_cache.zig");
const transform = @import("native_jiti_transform.zig");
const default_transform = @import("native_jiti_default_transform.zig");
pub const Inputs = struct {
    filesystem: c.JSValue,
    node_url: c.JSValue,
    node_module: c.JSValue,
    node_os: c.JSValue,
    pathe: c.JSValue,
    pathe_utils: c.JSValue,
    mlly: c.JSValue,
    /// Actual once-created utils.ts namespace, including real colors/crypto/IO.
    utilities: c.JSValue,
    performance: c.JSValue,
    /// Captured real CJS require of the jiti core module; must resolve the real
    /// get-tsconfig package namespace/cache identity when Source enables it.
    library_require: c.JSValue,
    package_json: c.JSValue,
    physical_filename: c.JSValue,
    module_url: c.JSValue,
    babel_filename: c.JSValue,
    /// Actual std-env module initialization capture, separate from os.platform.
    std_env_is_windows: bool,
};
const Phase = enum { prepared, completing, complete, failed, released };
/// Move-only, host-private preparation. It exposes NO Source namespace until
/// complete verifies genuine shared Module/cache publication of its backend.
/// Retain once for the actual jiti module lifetime, never once per createJiti.
pub const Prepared = struct {
    engine: *v.em.Engine,
    factory: public_factory.Exports,
    native_babel_exports: c.JSValue,
    module_constructor: c.JSValue,
    babel_filename: c.JSValue,
    namespace: c.JSValue,
    phase: Phase,
    pub fn deinit(self: *Prepared) void {
        self.factory.deinit(self.engine);
        self.engine.freeValue(self.native_babel_exports);
        self.engine.freeValue(self.module_constructor);
        self.engine.freeValue(self.babel_filename);
        self.engine.freeValue(self.namespace);
        self.phase = .released;
    }
};
fn imported(s: *v.Scope, namespace: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const value = try get(s, namespace, name);
    if (!c.JS_IsFunction(s.engine.context, value)) return error.RequiredActualJitiNamespaceExport;
    return value;
}
fn success(engine: *v.em.Engine, owned: c.JSValue) !c.JSValue {
    if (c.JS_HasException(engine.context)) {
        const pending = c.JS_GetException(engine.context);
        engine.freeValue(owned);
        return engine.checked(c.JS_Throw(engine.context, pending));
    }
    return owned;
}
fn get(s: *v.Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return s.own(try success(s.engine, try v.js.get(s.engine, receiver, name)));
}
/// Assemble real options/escape/resolve/cache/transform/core/frontend/require
/// declarations with SAME import identities. Native Babel output is already
/// lowered and must pass through evaluateLowered (the canonical frontend).
pub fn prepare(engine: *v.em.Engine, actual: Inputs) !Prepared {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    if (!c.JS_IsFunction(engine.context, actual.library_require)) return error.RequiredActualJitiLibraryRequire;
    if (!c.JS_IsObject(actual.performance) or !c.JS_IsObject(actual.package_json)) return error.RequiredActualJitiModuleDependency;
    if (!c.JS_IsString(actual.physical_filename) or !c.JS_IsString(actual.module_url) or !c.JS_IsString(actual.babel_filename)) return error.RequiredPhysicalJitiModuleIdentity;
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const create_require = try imported(&s, actual.node_module, "createRequire");
    const module_constructor = try imported(&s, actual.node_module, "Module");
    const builtin_modules = try get(&s, actual.node_module, "builtinModules");
    if (!c.JS_IsObject(builtin_modules)) return error.RequiredActualNodeBuiltinModules;
    const platform = try imported(&s, actual.node_os, "platform");
    const tmpdir = try imported(&s, actual.node_os, "tmpdir");
    const dirname = try imported(&s, actual.pathe, "dirname");
    const basename = try imported(&s, actual.pathe, "basename");
    const extname = try imported(&s, actual.pathe, "extname");
    const join = try imported(&s, actual.pathe, "join");
    const resolve = try imported(&s, actual.pathe, "resolve");
    const is_absolute = try imported(&s, actual.pathe, "isAbsolute");
    const normalize_aliases = try imported(&s, actual.pathe_utils, "normalizeAliases");
    const resolve_alias = try imported(&s, actual.pathe_utils, "resolveAlias");
    const filename = try imported(&s, actual.pathe_utils, "filename");
    const file_url_to_path = try imported(&s, actual.mlly, "fileURLToPath");
    const path_to_file_url = try imported(&s, actual.mlly, "pathToFileURL");
    const resolve_path = try imported(&s, actual.mlly, "resolvePathSync");
    const syntax = try imported(&s, actual.mlly, "hasESMSyntax");
    const debug = try imported(&s, actual.utilities, "debug");
    const is_dir = try imported(&s, actual.utilities, "isDir");
    const is_writable = try imported(&s, actual.utilities, "isWritable");
    const hash = try imported(&s, actual.utilities, "hash");
    const nearest = try imported(&s, actual.utilities, "readNearestPackageJSON");
    const read_file = try imported(&s, actual.filesystem, "readFileSync");
    const exists = try imported(&s, actual.filesystem, "existsSync");
    const mkdir = try imported(&s, actual.filesystem, "mkdirSync");
    const write = try imported(&s, actual.filesystem, "writeFileSync");
    const node_file_url_to_path = try imported(&s, actual.node_url, "fileURLToPath");
    const options = try s.own(try @import("native_jiti_options.zig").create(engine));
    const escape = try s.own(try @import("native_jiti_escape_regexp.zig").create(engine));
    const cached = try cache.create(engine, .{ .exists_sync = exists, .mkdir_sync = mkdir,
        .read_file_sync = read_file, .write_file_sync = write, .tmpdir = tmpdir,
        .pathe_dirname = dirname, .pathe_join = join, .pathe_basename = basename,
        .pathe_resolve = resolve, .pathe_filename = filename, .debug = debug,
        .is_writable = is_writable, .hash = hash });
    defer cached.deinit(engine);
    const transform_function = try s.own(try transform.create(engine, .{ .get_cache = cached.get_cache, .debug = debug }));
    const constants = try resolving.createConstants(engine);
    defer engine.freeValue(constants.js_ext_re); defer engine.freeValue(constants.ts_ext_re);
    const resolve_inputs: resolving.Inputs = .{ .pathe_resolve_alias = resolve_alias,
        .mlly_file_url_to_path = file_url_to_path, .mlly_resolve_path_sync = resolve_path,
        .pathe_join = join, .pathe_dirname = dirname, .is_dir = is_dir,
        .js_ext_re = constants.js_ext_re, .ts_ext_re = constants.ts_ext_re };
    const resolver = try s.own(try resolving.create(engine, resolve_inputs));
    const iterator = try s.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    const native_babel = try default_transform.create(engine, .{ .path_to_file_url = path_to_file_url,
        .file_url_to_path = file_url_to_path, .dirname = dirname });
    errdefer engine.freeValue(native_babel);
    const factory = try public_factory.create(engine, .{ .canonical = .{
        .core = .{ .resolve_options = options, .file_url_to_path = file_url_to_path,
            .path_to_file_url = path_to_file_url, .normalize_aliases = normalize_aliases,
            .escape_string_regexp = escape, .library_require = actual.library_require,
            .is_dir = is_dir, .pathe_dirname = dirname, .pathe_join = join, .debug = debug,
            .prepare_cache_dir = cached.prepare_cache_dir, .jiti_resolve = resolver,
            .transform = transform_function, .package_json = actual.package_json, .iterator_symbol = iterator },
        .frontend = .{ .module_constructor = module_constructor, .jiti_resolve = resolver,
            .pathe_dirname = dirname, .pathe_basename = basename, .pathe_extname = extname,
            .read_nearest_package_json = nearest, .has_esm_syntax = syntax,
            .performance = actual.performance, .debug = debug, .transform = transform_function },
        .require = .{ .resolve_inputs = resolve_inputs, .node_file_url_to_path = node_file_url_to_path,
            .pathe_extname = extname, .pathe_is_absolute = is_absolute,
            .mlly_path_to_file_url = path_to_file_url, .node_builtin_modules = builtin_modules,
            .read_file_sync = read_file, .debug = debug, .is_windows = actual.std_env_is_windows },
        .platform = platform }, .create_require = create_require,
        .physical_filename = actual.physical_filename, .module_url = actual.module_url });
    return .{ .engine = engine, .factory = factory, .native_babel_exports = native_babel,
        .module_constructor = c.JS_DupValue(engine.context, module_constructor),
        .babel_filename = c.JS_DupValue(engine.context, actual.babel_filename),
        .namespace = c.pi_js_undefined(), .phase = .prepared };
}
/// Actual Node/CommonJS owner supplies its REAL newly constructed native Babel
/// Module after normal publication. This function does not manufacture a cache,
/// fake Module or require callback, nor publish a half-assembled ESM namespace.
pub fn complete(engine: *v.em.Engine, staged: *Prepared, actual_babel_module: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    if (staged.engine != engine) return error.ForeignJitiPublicProfile;
    if (staged.phase == .complete) return c.JS_DupValue(engine.context, staged.namespace);
    if (staged.phase != .prepared) return error.JitiPublicProfileNotPrepared;
    staged.phase = .completing;
    errdefer staged.phase = .failed;
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    if (!c.JS_IsObject(actual_babel_module)) return error.RequiredActualPublishedNativeBabelModule;
    const cache_object = try get(&s, staged.module_constructor, "_cache");
    if (!c.JS_IsStrictEqual(engine.context, cache_object, engine.commonjs_cache)) return error.MismatchedActualCommonJSCache;
    const current = try s.own(try success(engine, try v.js.getKey(engine, cache_object, staged.babel_filename)));
    const exports = try get(&s, actual_babel_module, "exports");
    const loaded = try get(&s, actual_babel_module, "loaded");
    const filename = try get(&s, actual_babel_module, "filename");
    if (!c.JS_IsStrictEqual(engine.context, current, actual_babel_module) or
        !c.JS_IsStrictEqual(engine.context, exports, staged.native_babel_exports) or
        !c.JS_IsStrictEqual(engine.context, filename, staged.babel_filename) or
        !c.JS_IsStrictEqual(engine.context, loaded, c.pi_js_bool(engine.context, 1))) return error.RequiredActualPublishedNativeBabelModule;
    // A carrier is used ONLY to create Engine's real ESM exotic namespace.
    const bindings = try s.object();
    try define(engine, bindings, "createJiti", staged.factory.create_jiti);
    try define(engine, bindings, "default", staged.factory.create_jiti);
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    staged.namespace = try success(engine, try engine.valueNamespace(bindings));
    staged.phase = .complete;
    return c.JS_DupValue(engine.context, staged.namespace);
}
fn define(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, target, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
