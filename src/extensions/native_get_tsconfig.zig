//! Consumed get-tsconfig 4.14.0 getTsconfig/createPathsMatcher bindings.
//! Composition supplies actual native Node dependencies and retains one realm
//! namespace. This factory neither registers a package nor selects a host bridge.
const h = @import("native_tsconfig_values.zig");
const c = h.c;
const Scope = h.Scope;
pub const Inputs = struct { fs: c.JSValue, path: c.JSValue, module: c.JSValue, process: c.JSValue };
fn get(engine: *h.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const state = roots[0];
    // Jiti's pinned caller passes exactly one searchPath. Do not quietly select
    // findConfigApplicable/createFilesMatcher when an unported mode is requested.
    if (args.len > 1) return error.RequiredActualGetTsconfigOptionalModes;
    const search = if (c.JS_IsUndefined(h.arg(args, 0))) try s.invoke(try s.get(state, "process"), "cwd", &.{}) else args[0];
    const cache = try s.own(try h.v.js.builtin(engine, "Map", &.{}));
    const file = try s.own(try h.findUp(engine, state, try h.slash(&s, search), try s.text("tsconfig.json"), cache));
    if (!s.truthy(file)) return c.pi_js_null();
    const config = try s.own(try @import("native_tsconfig_parse.zig").parse(engine, state, file, cache));
    const result = try s.object(); try s.put(result, "path", file); try s.put(result, "config", config);
    return c.JS_DupValue(engine.context, result);
}
pub fn create(engine: *h.v.em.Engine, inputs: Inputs) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const state = try s.object();
    inline for (.{ "fs", "path", "module", "process" }) |name| {
        const value = @field(inputs, name); if (!c.JS_IsObject(value)) return h.v.js.typeError(engine, "Actual get-tsconfig dependencies must be objects");
        try s.put(state, name, value);
    }
    if (!c.JS_IsFunction(engine.context, inputs.module)) return error.RequiredActualTsconfigModuleDefaultConstructor;
    inline for (.{ "resolve", "relative", "join", "dirname", "isAbsolute" }) |name| if (!c.JS_IsFunction(engine.context, try s.get(inputs.path, name))) return error.RequiredActualTsconfigPathMethods;
    if (!c.JS_IsFunction(engine.context, try s.get(try s.get(inputs.path, "posix"), "join"))) return error.RequiredActualTsconfigPosixJoin;
    if (!c.JS_IsFunction(engine.context, try s.get(inputs.process, "cwd"))) return error.RequiredActualTsconfigProcessCwd;
    const methods = try s.object(); inline for (.{ "existsSync", "readFileSync", "statSync" }) |name| {
        const method = try s.get(inputs.fs, name); if (!c.JS_IsFunction(engine.context, method)) return error.RequiredActualTsconfigFilesystemMethods;
        try s.put(methods, name, method);
    }
    try s.put(state, "fsMethods", methods);
    try s.put(state, "implicitBaseUrl", try s.call(try s.global("Symbol"), c.pi_js_undefined(), &.{try s.text("implicitBaseUrl")}));
    try s.put(state, "slashFunction", try s.own(try h.functions.create(engine, "slash", 1, h.Boundary(h.slashCall).invoke, &.{})));
    inline for (.{ .{ "relativePattern", "^\\.{1,2}(/.*)?$", "" }, .{ "starPattern", "\\*", "g" }, .{ "packageSeparators", "/|\\\\", "" }, .{ "packageStars", "\\*", "g" }, .{ "badPackageSegment", "^(\\.{1,2}|node_modules)$", "i" }, .{ "numericPackageKey", "^\\d+$", "" }, .{ "packageScheme", "^\\w+:", "" } }) |spec| try s.put(state, spec[0], try h.regexp(&s, spec[1], spec[2]));
    const result = try s.object();
    try s.put(result, "getTsconfig", try s.own(try h.functions.createArrow(engine, "getTsconfig", 0, h.Boundary(get).invoke, &.{state})));
    try s.put(result, "createPathsMatcher", try s.own(try h.functions.createArrow(engine, "createPathsMatcher", 1, h.Boundary(@import("native_tsconfig_paths.zig").create).invoke, &.{state})));
    return c.JS_DupValue(engine.context, result);
}
