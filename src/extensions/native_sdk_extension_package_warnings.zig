//! Source package dependency diagnostics, using actual native filesystem reads.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Callback = enum(c_int) { root, present, host };
pub fn create(engine: *em.Engine) !c.JSValue {
    const module_name = "pi-native:resource-package-warnings";
    if (engine.native_module_values.get(module_name)) |exports| return sdk.get(engine, exports, "collectExtensionPackageWarnings");
    const io = engine.native_io orelse return error.NativePackageWarningsRequireIo;
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, io);
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, io);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const host = try scope.own(try js.builtin(engine, "Set", &.{}));
    inline for (.{ "@earendil-works/pi-agent-core", "@earendil-works/pi-ai", "@earendil-works/pi-coding-agent", "@earendil-works/pi-tui", "@mariozechner/pi-agent-core", "@mariozechner/pi-ai", "@mariozechner/pi-coding-agent", "@mariozechner/pi-tui", "@sinclair/typebox", "typebox" }) |name| _ = try scope.invoke(host, "add", &.{try scope.text(name)});
    const fs = engine.native_module_values.get("node:fs").?;
    const path = engine.native_module_values.get("node:path").?;
    const function = try scope.own(try @import("native_node_function.zig").create(engine, "collectExtensionPackageWarnings", 2, collect, &.{ host, try scope.get(path, "join"), try scope.get(fs, "existsSync"), try scope.get(fs, "readFileSync") }));
    const exports = try scope.object();
    try scope.put(exports, "collectExtensionPackageWarnings", function);
    try engine.registerValueModule(module_name, exports);
    return c.JS_DupValue(engine.context, function);
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return mapped(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn mapped(engine: *em.Engine, kind: Callback, value: c.JSValue, root: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = switch (kind) {
        .root => value: {
            const metadata = try scope.invoke(root, "get", &.{value});
            break :value if (temp.nullish(metadata)) c.pi_js_undefined() else try scope.get(metadata, "packageRoot");
        },
        .present => c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(value))),
        .host => try scope.invoke(root, "has", &.{value}),
    };
    return c.JS_DupValue(engine.context, result);
}
fn collection(scope: *Scope, values: c.JSValue, name: [*:0]const u8, kind: Callback, root: c.JSValue) !c.JSValue {
    const method = try scope.get(values, name);
    var roots = [_]c.JSValue{root};
    const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, "", 1, @intFromEnum(kind), roots.len, &roots)));
    return scope.call(method, values, &.{function});
}
fn stripBom(scope: *Scope, input: c.JSValue) !c.JSValue {
    return if (scope.truthy(try scope.invoke(input, "startsWith", &.{try scope.text("\xef\xbb\xbf")}))) scope.invoke(input, "slice", &.{c.JS_NewInt32(scope.engine.context, 1)}) else input;
}
fn collect(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, deps: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const paths = if (args.len > 0) args[0] else c.pi_js_undefined();
    const metadata = if (args.len > 1) args[1] else c.pi_js_undefined();
    const warnings = try scope.array();
    const set_constructor = try scope.global("Set");
    const roots = try collection(&scope, try collection(&scope, paths, "map", .root, metadata), "filter", .present, c.pi_js_undefined());
    var set_args = [_]c.JSValue{roots};
    const package_roots = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, set_constructor, set_args.len, &set_args)));
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var it = try js.Iterator.init(engine, package_roots, symbol);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |root| {
        defer engine.freeValue(root);
        const package_path = try scope.call(deps[1], c.pi_js_undefined(), &.{ root, try scope.text("package.json") });
        if (!scope.truthy(try scope.call(deps[2], c.pi_js_undefined(), &.{package_path}))) continue;
        const json = try scope.global("JSON");
        const parse = try scope.get(json, "parse");
        const bytes = try scope.call(deps[3], c.pi_js_undefined(), &.{ package_path, try scope.text("utf-8") });
        const manifest = try scope.call(parse, json, &.{try stripBom(&scope, bytes)});
        const first = try scope.get(manifest, "dependencies");
        if (!c.JS_IsObject(first) and !c.JS_IsNull(first)) continue;
        if (c.JS_IsFunction(engine.context, first)) continue;
        if (c.JS_IsNull(try scope.get(manifest, "dependencies"))) continue;
        const array = try scope.global("Array");
        if (scope.truthy(try scope.call(try scope.get(array, "isArray"), array, &.{try scope.get(manifest, "dependencies")}))) continue;
        const object = try scope.global("Object");
        const keys = try scope.get(object, "keys");
        const names = try scope.call(keys, object, &.{try scope.get(manifest, "dependencies")});
        const hosts = try collection(&scope, names, "filter", .host, deps[0]);
        const sorted = try scope.invoke(hosts, "sort", &.{});
        if (scope.equal(try scope.get(sorted, "length"), c.JS_NewInt32(engine.context, 0))) continue;
        const push = try scope.get(warnings, "push");
        const warning = try scope.object();
        try scope.put(warning, "path", package_path);
        const prefix = try scope.text("Host-provided extension packages must be declared in peerDependencies with a \"*\" range, not dependencies: ");
        const suffix = try scope.text(". Installed copies can bypass the extension loader and create duplicate runtime modules.");
        try scope.put(warning, "warning", try scope.concat(try scope.concat(prefix, try scope.invoke(sorted, "join", &.{try scope.text(", ")})), suffix));
        _ = try scope.call(push, warnings, &.{warning});
    }
    return c.JS_DupValue(engine.context, warnings);
}
