//! Actual readPiManifest body, including its Source catch boundary and live
//! record/array/iterator/assignment behavior over genuine filesystem JSON.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub fn create(engine: *em.Engine) !c.JSValue {
    const module_name = "pi-native:pi-manifest";
    if (engine.native_module_values.get(module_name)) |exports| return sdk.get(engine, exports, "readPiManifest");
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, engine.native_io orelse return error.NativePiManifestRequiresIo);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const fields = try scope.array();
    inline for (.{ "extensions", "skills", "prompts", "themes" }, 0..) |field, index| try scope.index(fields, index, try scope.text(field));
    const read_file = try scope.get(engine.native_module_values.get("node:fs").?, "readFileSync");
    const function = try scope.own(try @import("native_node_function.zig").create(engine, "readPiManifest", 1, invoke, &.{ fields, read_file }));
    const exports = try scope.object();
    try scope.put(exports, "readPiManifest", function);
    try engine.registerValueModule(module_name, exports);
    return c.JS_DupValue(engine.context, function);
}
fn stringEntry(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, @intFromBool(argc > 0 and c.JS_IsString(argv[0])));
}
fn isArray(scope: *Scope, value: c.JSValue) !bool {
    return scope.truthy(try scope.invoke(try scope.global("Array"), "isArray", &.{value}));
}
fn record(scope: *Scope, value: c.JSValue) !bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(scope.engine.context, value) and !try isArray(scope, value);
}
fn read(scope: *Scope, path: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const json = try scope.global("JSON");
    const parse = try scope.get(json, "parse");
    const bytes = try scope.call(roots[1], c.pi_js_undefined(), &.{ path, try scope.text("utf-8") });
    const stripped = if (scope.truthy(try scope.invoke(bytes, "startsWith", &.{try scope.text("\xef\xbb\xbf")}))) try scope.invoke(bytes, "slice", &.{c.JS_NewInt32(scope.engine.context, 1)}) else bytes;
    const package = try scope.call(parse, json, &.{stripped});
    if (!try record(scope, package) or !try record(scope, try scope.get(package, "pi"))) return c.JS_NULL;
    const manifest = try scope.object();
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, roots[0], symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |field| {
        defer scope.engine.freeValue(field);
        const entries = try scope.own(try js.getKey(scope.engine, try scope.get(package, "pi"), field));
        if (!try isArray(scope, entries)) continue;
        const every = try scope.get(entries, "every");
        const predicate = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, stringEntry, "", 1)));
        if (!scope.truthy(try scope.call(every, entries, &.{predicate}))) continue;
        const atom = try js.atom(scope.engine, field);
        defer c.JS_FreeAtom(scope.engine.context, atom);
        if (c.JS_SetProperty(scope.engine.context, manifest, atom, c.JS_DupValue(scope.engine.context, entries)) < 0) return js.capture(scope.engine);
    }
    return manifest;
}
fn invoke(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const generation = engine.native_allocation_generation;
    const result = read(&scope, if (args.len > 0) args[0] else c.pi_js_undefined(), roots) catch |err| {
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        if (engine.captured_exception) |value| engine.freeValue(value);
        engine.captured_exception = null;
        return c.JS_NULL;
    };
    return c.JS_DupValue(engine.context, result);
}
