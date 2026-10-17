//! Node24.14 actual ordinary Module constructor/prototype and path lookup.
//! Broader _load/_resolveFilename/_compile/extensions are explicit missing
//! dependencies. This factory does not replace/select node:module or CommonJS.
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const functions = @import("native_node_module_callable.zig");
const module_key = "pi-native:actual-node-module-constructor";
const warning_message = "module.parent is deprecated due to accuracy issues. Please use require.main to find program entry point instead.";
pub const Inputs = struct {
    /// Actual default node:path object, whose dirname/resolve remain live.
    paths: c.JSValue,
    /// Existing actual native CommonJS createRequire, preserving identity/cache.
    create_require: c.JSValue,
    process: c.JSValue,
    /// Actual immutable host options, not mutable process.execArgv guesses.
    pending_deprecation: bool,
    no_deprecation: bool,
};
/// Both values owned. namespace_exports is a publication record for the real
/// module assembler; it is not presented as an already-linked ESM namespace.
pub const Graph = struct { module_constructor: c.JSValue, namespace_exports: c.JSValue };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn define(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, target, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
fn nullObject(s: *Scope) !c.JSValue { return s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, c.pi_js_null()))); }
fn method(s: *Scope, prototype: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const function = try s.get(prototype, name);
    if (!c.JS_IsFunction(s.engine.context, function)) return error.RequiredPristineNodeModulePrimordial;
    return function;
}
fn cachedOwner(engine: *v.em.Engine, constructor: c.JSValue) !c.JSValue {
    const known = engine.native_module_values.get(module_key) orelse return error.ModuleConstructorNotCreated;
    if (!c.JS_IsStrictEqual(engine.context, known, constructor)) return error.InvalidKnownModuleConstructor;
    const roots = try functions.capturedRoots(engine, known);
    if (roots.len != 1) return error.InvalidKnownModuleConstructor;
    return roots[0]; // Borrowed from the known native callable only.
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Graph {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (engine.native_module_values.get(module_key)) |constructor| {
        const owner = try cachedOwner(engine, constructor);
        return .{ .module_constructor = c.JS_DupValue(engine.context, constructor), .namespace_exports = c.JS_DupValue(engine.context, try s.get(owner, "namespaceExports")) };
    }
    if (!c.JS_IsFunction(engine.context, inputs.create_require)) return error.RequiredActualCommonJSCreateRequire;
    _ = try method(&s, inputs.paths, "dirname");
    _ = try method(&s, inputs.paths, "resolve");
    if (!c.JS_IsObject(inputs.process)) return error.RequiredActualModuleProcess;
    // Publishing real new Module instances over an already-populated legacy
    // plain-object cache would silently mix identities. Bootstrap first.
    var names: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, engine.commonjs_cache, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return v.js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    if (count != 0) return error.ActualModuleRequiresFreshCommonJSCache;
    const owner = try nullObject(&s);
    const weak_map = try s.global("WeakMap");
    const weak_prototype = try s.get(weak_map, "prototype");
    const weak_args = [_]c.JSValue{};
    inline for (.{ "firstParents", "lastParents" }) |name| try define(engine, owner, name, try s.own(try engine.checked(c.JS_CallConstructor(engine.context, weak_map, weak_args.len, @constCast(&weak_args)))));
    try define(engine, owner, "weakGet", try method(&s, weak_prototype, "get"));
    try define(engine, owner, "weakSet", try method(&s, weak_prototype, "set"));
    const array_prototype = try s.get(try s.global("Array"), "prototype");
    try define(engine, owner, "arrayPush", try method(&s, array_prototype, "push"));
    const string_prototype = try s.get(try s.global("String"), "prototype");
    try define(engine, owner, "charCodeAt", try method(&s, string_prototype, "charCodeAt"));
    try define(engine, owner, "stringSlice", try method(&s, string_prototype, "slice"));
    const set_constructor = try s.global("Set");
    const set_prototype = try s.get(set_constructor, "prototype");
    try define(engine, owner, "warningCodes", try s.own(try engine.checked(c.JS_CallConstructor(engine.context, set_constructor, 0, null))));
    try define(engine, owner, "setHas", try method(&s, set_prototype, "has"));
    try define(engine, owner, "setAdd", try method(&s, set_prototype, "add"));
    try define(engine, owner, "paths", inputs.paths);
    try define(engine, owner, "process", inputs.process);
    try define(engine, owner, "pendingDeprecation", c.pi_js_bool(engine.context, @intFromBool(inputs.pending_deprecation)));
    try define(engine, owner, "noDeprecation", c.pi_js_bool(engine.context, @intFromBool(inputs.no_deprecation)));
    try define(engine, owner, "isPreloading", c.pi_js_bool(engine.context, 0));
    try define(engine, owner, "windows", c.pi_js_bool(engine.context, @intFromBool(builtin.os.tag == .windows)));
    inline for (.{ .{ "bareNodeModules", "node_modules" }, .{ "windowsNodeModules", "\\node_modules" }, .{ "posixNodeModules", "/node_modules" }, .{ "rootNodeModules", "/node_modules" }, .{ "rootSlash", "/" }, .{ "emptyId", "" } }) |entry| try define(engine, owner, entry[0], try s.text(entry[1]));
    const constructor = try s.own(try functions.create(engine, "Module", 0, true, construct, &.{owner}));
    const prototype = try s.get(constructor, "prototype");
    try accessor(engine, prototype, "isPreloading", try s.own(try functions.create(engine, "get", 0, false, isPreloading, &.{owner})), c.pi_js_undefined());
    const parent_getter = try s.own(try parentFunction(&s, owner, false));
    const parent_setter = try s.own(try parentFunction(&s, owner, true));
    try accessor(engine, prototype, "parent", parent_getter, parent_setter);
    try accessor(engine, prototype, "constructor", try s.own(try functions.create(engine, "get", 0, true, getConstructor, &.{constructor})), c.pi_js_undefined());
    // These are actual Source initialized caches/identities. Missing extension
    // handlers/loader methods are not exposed as empty or renamed stand-ins.
    try s.set(constructor, "_cache", engine.commonjs_cache);
    try s.set(constructor, "_pathCache", try nullObject(&s));
    try s.set(constructor, "_nodeModulePaths", try s.own(try functions.create(engine, "", 1, true, @import("native_node_module_paths.zig").invoke, &.{owner})));
    try s.set(constructor, "createRequire", inputs.create_require);
    try s.set(constructor, "Module", constructor);
    const exports = try s.object();
    try define(engine, exports, "default", constructor);
    try define(engine, exports, "Module", constructor);
    try define(engine, exports, "createRequire", inputs.create_require);
    try define(engine, owner, "namespaceExports", exports);
    // Cache only the public constructor. Neither WeakMaps nor private owner are
    // a module export; the controlled node:module publication stays unselected.
    try engine.registerValueModule(module_key, constructor);
    return .{ .module_constructor = c.JS_DupValue(engine.context, constructor), .namespace_exports = c.JS_DupValue(engine.context, exports) };
}
fn accessor(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, getter: c.JSValue, setter: c.JSValue) !void {
    const atom = c.JS_NewAtom(engine.context, name); if (atom == c.JS_ATOM_NULL) return v.js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, target, atom, c.JS_DupValue(engine.context, getter), c.JS_DupValue(engine.context, setter), c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
fn construct(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const owner = roots[0];
    const id = if (c.JS_IsUndefined(arg(args, 0))) try s.get(owner, "emptyId") else arg(args, 0);
    try s.set(receiver, "id", id);
    try s.set(receiver, "path", try s.invoke(try s.get(owner, "paths"), "dirname", &.{id}));
    try define(engine, receiver, "exports", try s.object());
    _ = try s.call(try s.get(owner, "weakSet"), try s.get(owner, "firstParents"), &.{ receiver, arg(args, 1) });
    _ = try s.call(try s.get(owner, "weakSet"), try s.get(owner, "lastParents"), &.{ receiver, arg(args, 1) });
    if (!v.nullish(arg(args, 1))) {
        const children = try s.get(arg(args, 1), "children");
        if (s.truthy(children)) _ = try s.call(try s.get(owner, "arrayPush"), children, &.{receiver});
    }
    try s.set(receiver, "filename", c.pi_js_null());
    try s.set(receiver, "loaded", c.pi_js_bool(engine.context, 0));
    try s.set(receiver, "children", try s.array());
    return c.pi_js_undefined();
}
fn parentFunction(s: *Scope, owner: c.JSValue, setter: bool) !c.JSValue {
    const local = try nullObject(s);
    try define(s.engine, local, "warned", c.pi_js_bool(s.engine.context, 0));
    const function = try s.own(try functions.create(s.engine, "deprecated", if (setter) 1 else 0, true, if (setter) setParent else getParent, &.{ owner, local }));
    try define(s.engine, local, "function", function);
    return c.JS_DupValue(s.engine.context, function);
}
fn warn(s: *Scope, owner: c.JSValue, local: c.JSValue) !void {
    if (s.truthy(try s.get(local, "warned")) or !s.truthy(try s.get(owner, "pendingDeprecation")) or s.truthy(try s.get(owner, "noDeprecation"))) return;
    try define(s.engine, local, "warned", c.pi_js_bool(s.engine.context, 1));
    const codes = try s.get(owner, "warningCodes");
    const code_value = try s.text("DEP0144");
    if (s.truthy(try s.call(try s.get(owner, "setHas"), codes, &.{code_value}))) return;
    const emit = try s.get(try s.get(owner, "process"), "emitWarning");
    _ = try s.call(emit, c.pi_js_undefined(), &.{ try s.text(warning_message), try s.text("DeprecationWarning"), code_value, try s.get(local, "function") });
    _ = try s.call(try s.get(owner, "setAdd"), codes, &.{code_value});
}
fn getParent(engine: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    try warn(&s, roots[0], roots[1]);
    // Raise the actual VM nullish-property read failure rather than silently
    // using WeakMap.get(null)'s undefined result. Node/V8 diagnostic wording is
    // an explicit reference-control gate, not a fabricated expected message.
    if (v.nullish(receiver)) return v.js.get(engine, receiver, "node:module_first_parent");
    return c.JS_DupValue(engine.context, try s.call(try s.get(roots[0], "weakGet"), try s.get(roots[0], "firstParents"), &.{receiver}));
}
fn setParent(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    try warn(&s, roots[0], roots[1]);
    // V8's strict private-property store rejects primitive receivers. WeakMap
    // also accepts nonregistered Symbols, so it cannot enforce that boundary.
    if (!c.JS_IsObject(receiver)) return v.js.typeError(engine, "Cannot assign Module private parent to a primitive receiver");
    _ = try s.call(try s.get(roots[0], "weakSet"), try s.get(roots[0], "firstParents"), &.{ receiver, arg(args, 0) });
    return c.pi_js_undefined();
}
fn getConstructor(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return c.JS_DupValue(engine.context, roots[0]); }
fn isPreloading(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return v.js.get(engine, roots[0], "isPreloading"); }
/// Host integration reads the real last-parent slot without firing .parent's
/// pending-deprecation wrapper. Never casts a guest value to native storage.
pub fn lastParent(engine: *v.em.Engine, constructor: c.JSValue, module: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const owner = try cachedOwner(engine, constructor);
    return v.js.call(engine, try s.get(owner, "weakGet"), try s.get(owner, "lastParents"), &.{module});
}
/// Real internal util deprecators must share this code set when composed later.
pub fn warningCodes(engine: *v.em.Engine, constructor: c.JSValue) !c.JSValue { return v.js.get(engine, try cachedOwner(engine, constructor), "warningCodes"); }
/// Source Module._load publication, over the live public cache. Caller supplies
/// its newly constructed real Module; this does not relabel legacy cache data.
pub fn publish(engine: *v.em.Engine, constructor: c.JSValue, filename: c.JSValue, module: c.JSValue) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    _ = try cachedOwner(engine, constructor);
    try v.js.setKey(engine, try s.get(constructor, "_cache"), filename, module);
}
