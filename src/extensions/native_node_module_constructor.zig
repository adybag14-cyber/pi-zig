// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! One actual Node v24.14 Module constructor, cache and private lexical owner.
//! Public loader composition adopts this completed constructor; creation alone
//! does not install a partial node:module namespace.
const builtin = @import("builtin");
const a = @import("native_node_argument_values.zig");
const v = a.v;
const c = a.c;
const Scope = a.Scope;
const functions = @import("native_node_module_callable.zig");
const publication = @import("native_node_fs_private_publication.zig");
const module_key = "pi-native:actual-node-module-constructor";
const warning_message = "module.parent is deprecated due to accuracy issues. Please use require.main to find program entry point instead.";

pub const Inputs = struct {
    /// Actual default node:path object. Its public methods remain live.
    paths: c.JSValue,
    /// The genuine createRequire declaration linked to this same Module.
    create_require: c.JSValue,
    process: c.JSValue,
    pending_deprecation: bool,
    no_deprecation: bool,
};
pub const Graph = struct { module_constructor: c.JSValue, namespace_exports: c.JSValue };

fn statement(engine: *v.em.Engine, comptime body: anytype, args: anytype) !void {
    var s = Scope.init(engine);
    var failure: ?anyerror = null;
    @call(.auto, body, .{&s} ++ args) catch |err| { failure = err; };
    _ = try s.finish(if (failure) |err| @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
}
fn define(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    try s.define(target, name, value, c.JS_PROP_C_W_E);
}
fn global(s: *Scope, name: [*:0]const u8) !c.JSValue {
    try s.pending();
    return s.get(try s.checked(c.JS_GetGlobalObject(s.engine.context)), name);
}
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
    return roots[0];
}
fn freshCache(s: *Scope) !void {
    // Do not silently relabel already-loaded legacy plain objects as Modules.
    try s.pending();
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    const status = c.JS_GetOwnPropertyNames(s.engine.context, &names, &count,
        s.engine.commonjs_cache, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK);
    defer if (names != null) c.JS_FreePropertyEnum(s.engine.context, names, count);
    try s.pending();
    if (status < 0) return error.MissingActualModuleCacheEnumerationReason;
    if (count != 0) return error.ActualModuleRequiresFreshCommonJSCache;
}
fn selectCompleted(s: *Scope, incoming: c.JSValue, completed: c.JSValue) !c.JSValue {
    // Keep the selected owner before retiring the losing candidate.
    const selected = a.duplicate(s.engine, completed);
    var outputs = [_]c.JSValue{selected};
    var failure: ?anyerror = null;
    _ = s.own(incoming) catch |err| failed: { failure = err; break :failed c.pi_js_undefined(); };
    try s.boundary.finishMany(failure, &s.values, &outputs);
    return outputs[0];
}
fn acquireConstructor(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var s = Scope.init(engine);
    const candidate = try s.finish(createBody(&s, inputs));
    if (engine.native_module_values.get(module_key)) |completed| {
        var selection = Scope.init(engine);
        return selectCompleted(&selection, candidate, completed);
    }
    return publication.publish(engine, module_key, candidate);
}
/// The immutable Module lexical binding used by actual loader declarations.
/// It never follows mutable Module.Module or acquires an incomplete facade.
pub fn actualConstructor(engine: *v.em.Engine) !c.JSValue {
    return a.expression(engine, actualConstructorBody, .{});
}
fn actualConstructorBody(s: *Scope) !c.JSValue {
    try s.pending();
    const constructor = s.engine.native_module_values.get(module_key) orelse return error.ActualModuleConstructorNotReady;
    _ = try cachedOwner(s.engine, constructor);
    return a.duplicate(s.engine, constructor);
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Graph {
    var s = Scope.init(engine);
    var values = [_]c.JSValue{c.pi_js_undefined()} ** 2;
    var failure: ?anyerror = null;
    if (graphBody(&s, inputs)) |result| values = result else |err| failure = err;
    try s.boundary.finishMany(failure, &s.values, &values);
    return .{ .module_constructor = values[0], .namespace_exports = values[1] };
}
fn graphBody(s: *Scope, inputs: Inputs) ![2]c.JSValue {
    const constructor = try s.own(try acquireConstructor(s.engine, inputs));
    const owner = try cachedOwner(s.engine, constructor);
    const namespace = try s.get(owner, "namespaceExports");
    return .{ a.duplicate(s.engine, constructor), a.duplicate(s.engine, namespace) };
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    try s.pending();
    if (s.engine.native_module_values.get(module_key)) |constructor| {
        _ = try cachedOwner(s.engine, constructor);
        return a.duplicate(s.engine, constructor);
    }
    if (!c.JS_IsFunction(s.engine.context, inputs.create_require)) return error.RequiredActualCommonJSCreateRequire;
    _ = try method(s, inputs.paths, "dirname");
    _ = try method(s, inputs.paths, "resolve");
    if (!c.JS_IsObject(inputs.process)) return error.RequiredActualModuleProcess;
    try freshCache(s);
    const owner = try s.objectProto(c.pi_js_null());

    // The actual assembler runs this capture before any guest module. All
    // later public method lookups are distinct from these retained primordials.
    const weak_map = try global(s, "WeakMap");
    const weak_prototype = try s.get(weak_map, "prototype");
    try define(s, owner, "weakMapConstructor", weak_map);
    inline for (.{ "firstParents", "lastParents" }) |name|
        try define(s, owner, name, try s.construct(weak_map, &.{}));
    try define(s, owner, "weakGet", try method(s, weak_prototype, "get"));
    try define(s, owner, "weakSet", try method(s, weak_prototype, "set"));
    try define(s, owner, "weakHas", try method(s, weak_prototype, "has"));
    const map = try global(s, "Map");
    try define(s, owner, "mapConstructor", map);
    const map_prototype = try s.get(map, "prototype");
    try define(s, owner, "mapGet", try method(s, map_prototype, "get"));
    try define(s, owner, "mapSet", try method(s, map_prototype, "set"));
    const array = try global(s, "Array");
    const array_prototype = try s.get(array, "prototype");
    try define(s, owner, "arrayPush", try method(s, array_prototype, "push"));
    try define(s, owner, "arrayIncludes", try method(s, array_prototype, "includes"));
    try define(s, owner, "arrayIndexOf", try method(s, array_prototype, "indexOf"));
    try define(s, owner, "arraySplice", try method(s, array_prototype, "splice"));
    try define(s, owner, "arrayIsArray", try method(s, array, "isArray"));
    inline for (.{ .{"arraySlice", "slice"}, .{"arrayUnshift", "unshift"}, .{"arrayFilter", "filter"} }) |entry|
        try define(s, owner, entry[0], try method(s, array_prototype, entry[1]));
    // loader.js keeps this actual Array, including inherited reads after a
    // complete suffix match advances p beyond the twelve own elements.
    const nm_chars = try a.array(s);
    inline for (.{ 115, 101, 108, 117, 100, 111, 109, 95, 101, 100, 111, 110 }, 0..) |value, position|
        try a.index(s, nm_chars, @intCast(position), c.JS_NewInt32(s.engine.context, value));
    try define(s, owner, "nmChars", nm_chars);
    const string_prototype = try s.get(try global(s, "String"), "prototype");
    try define(s, owner, "charCodeAt", try method(s, string_prototype, "charCodeAt"));
    try define(s, owner, "stringSlice", try method(s, string_prototype, "slice"));
    inline for (.{ .{"stringCharAt", "charAt"}, .{"stringStartsWith", "startsWith"}, .{"stringSplit", "split"} }) |entry|
        try define(s, owner, entry[0], try method(s, string_prototype, entry[1]));
    try define(s, owner, "boolean", try global(s, "Boolean"));
    // This is loader.js's own lexical modulePaths, distinct from the public
    // Module.globalPaths clone produced by _initPaths.
    try define(s, owner, "modulePaths", try a.array(s));
    const set_constructor = try global(s, "Set");
    const set_prototype = try s.get(set_constructor, "prototype");
    try define(s, owner, "warningCodes", try s.construct(set_constructor, &.{}));
    try define(s, owner, "setHas", try method(s, set_prototype, "has"));
    try define(s, owner, "setAdd", try method(s, set_prototype, "add"));
    try define(s, owner, "reflectApply", try method(s, try global(s, "Reflect"), "apply"));
    try define(s, owner, "paths", inputs.paths);
    try define(s, owner, "process", inputs.process);
    try define(s, owner, "pendingDeprecation", a.boolean(s, inputs.pending_deprecation));
    try define(s, owner, "noDeprecation", a.boolean(s, inputs.no_deprecation));
    try define(s, owner, "isPreloading", a.boolean(s, false));
    try define(s, owner, "windows", a.boolean(s, builtin.os.tag == .windows));
    inline for (.{ .{ "bareNodeModules", "node_modules" }, .{ "windowsNodeModules", "\\node_modules" },
        .{ "posixNodeModules", "/node_modules" }, .{ "rootNodeModules", "/node_modules" },
        .{ "rootSlash", "/" }, .{ "emptyId", "" } }) |entry|
        try define(s, owner, entry[0], try s.text(entry[1]));

    const constructor = try s.own(try functions.create(s.engine, "Module", 0, true, construct, &.{owner}));
    const prototype = try s.get(constructor, "prototype");
    try accessor(s, prototype, "isPreloading",
        try s.own(try functions.create(s.engine, "get", 0, false, isPreloading, &.{owner})), c.pi_js_undefined());
    const parent_getter = try s.own(try a.expression(s.engine, parentFunction, .{ owner, false }));
    const parent_setter = try s.own(try a.expression(s.engine, parentFunction, .{ owner, true }));
    try accessor(s, prototype, "parent", parent_getter, parent_setter);
    try accessor(s, prototype, "constructor",
        try s.own(try functions.create(s.engine, "get", 0, true, getConstructor, &.{constructor})), c.pi_js_undefined());
    try s.put(constructor, "_cache", s.engine.commonjs_cache);
    try s.put(constructor, "_pathCache", try s.objectProto(c.pi_js_null()));
    try s.put(constructor, "_nodeModulePaths",
        try s.own(try functions.createWithArguments(s.engine, "", 1, true, @import("native_node_module_paths.zig").definition, &.{owner})));
    try s.put(constructor, "createRequire", inputs.create_require);
    try s.put(constructor, "Module", constructor);
    const exports = try s.object();
    try define(s, exports, "default", constructor);
    try define(s, exports, "Module", constructor);
    try define(s, exports, "createRequire", inputs.create_require);
    try define(s, owner, "namespaceExports", exports);
    // The caller finishes every staging root before publishing this owner.
    return a.duplicate(s.engine, constructor);
}
fn accessor(s: *Scope, target: c.JSValue, name: [*:0]const u8, getter: c.JSValue, setter: c.JSValue) !void {
    const generation = try s.beforeAllocation();
    const atom = c.JS_NewAtom(s.engine.context, name);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try s.boundary.checkPendingSince(generation);
    if (atom == c.JS_ATOM_NULL) return error.MissingActualModuleAccessorAtomReason;
    try s.pending();
    const status = c.JS_DefinePropertyGetSet(s.engine.context, target, atom,
        a.duplicate(s.engine, getter), a.duplicate(s.engine, setter), c.JS_PROP_THROW);
    try s.pending();
    if (status < 0) return error.MissingActualModuleAccessorReason;
}
fn setField(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    try s.put(target, name, value);
}
fn dirname(s: *Scope, paths: c.JSValue, id: c.JSValue) !c.JSValue {
    const function = try s.get(paths, "dirname");
    return a.duplicate(s.engine, try s.call(function, paths, &.{id}));
}
fn setPath(s: *Scope, receiver: c.JSValue, paths: c.JSValue, id: c.JSValue) !void {
    const value = try s.own(try a.expression(s.engine, dirname, .{ paths, id }));
    try s.put(receiver, "path", value);
}
fn setExports(s: *Scope, receiver: c.JSValue) !void {
    try define(s, receiver, "exports", try s.object());
}
fn setChildren(s: *Scope, receiver: c.JSValue) !void {
    try s.put(receiver, "children", try a.array(s));
}
fn weakSet(s: *Scope, owner: c.JSValue, name: [*:0]const u8, key: c.JSValue, value: c.JSValue) !void {
    _ = try s.call(try s.get(owner, "weakSet"), try s.get(owner, name), &.{ key, value });
}
fn updateChildren(s: *Scope, owner: c.JSValue, parent: c.JSValue, child: c.JSValue, scan: bool) !void {
    // This is the actual updateChildren function-local, retained through its
    // condition and push, then released before the caller's next statement.
    const children = if (v.nullish(parent)) c.pi_js_undefined() else try s.get(parent, "children");
    if (s.truthy(children) and !(scan and try a.condition(s.engine, includes, .{ owner, children, child })))
        _ = try s.call(try s.get(owner, "arrayPush"), children, &.{child});
}
fn includes(s: *Scope, owner: c.JSValue, children: c.JSValue, child: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.call(try s.get(owner, "arrayIncludes"), children, &.{child})));
}
fn construct(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, constructBody, .{ receiver, args, roots[0] });
}
fn constructBody(s: *Scope, receiver: c.JSValue, args: []const c.JSValue, owner: c.JSValue) !c.JSValue {
    const id = if (c.JS_IsUndefined(a.arg(args, 0))) try s.get(owner, "emptyId") else a.arg(args, 0);
    const parent = a.arg(args, 1);
    try statement(s.engine, setField, .{ receiver, @as([*:0]const u8, "id"), id });
    try statement(s.engine, setPath, .{ receiver, try s.get(owner, "paths"), id });
    try statement(s.engine, setExports, .{receiver});
    try statement(s.engine, weakSet, .{ owner, @as([*:0]const u8, "firstParents"), receiver, parent });
    try statement(s.engine, weakSet, .{ owner, @as([*:0]const u8, "lastParents"), receiver, parent });
    try statement(s.engine, updateChildren, .{ owner, parent, receiver, false });
    try statement(s.engine, setField, .{ receiver, @as([*:0]const u8, "filename"), c.pi_js_null() });
    try statement(s.engine, setField, .{ receiver, @as([*:0]const u8, "loaded"), a.boolean(s, false) });
    try statement(s.engine, setChildren, .{receiver});
    return c.pi_js_undefined();
}
fn parentFunction(s: *Scope, owner: c.JSValue, setter: bool) !c.JSValue {
    const local = try s.objectProto(c.pi_js_null());
    try define(s, local, "warned", a.boolean(s, false));
    const target = try s.own(try functions.create(s.engine, if (setter) "setModuleParent" else "getModuleParent",
        if (setter) 1 else 0, true, if (setter) setParent else getParent, &.{owner}));
    const wrapper = try s.own(try functions.create(s.engine, "deprecated", if (setter) 1 else 0, true,
        deprecatedParent, &.{ owner, local, target }));
    try define(s, local, "function", wrapper);
    return a.duplicate(s.engine, wrapper);
}
fn warned(s: *Scope, local: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.get(local, "warned")));
}
fn hasCode(s: *Scope, owner: c.JSValue, codes: c.JSValue, code: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.call(try s.get(owner, "setHas"), codes, &.{code})));
}
fn warn(s: *Scope, owner: c.JSValue, local: c.JSValue) !void {
    if (try a.condition(s.engine, warned, .{local}) or
        !s.truthy(try s.get(owner, "pendingDeprecation")) or s.truthy(try s.get(owner, "noDeprecation"))) return;
    try define(s, local, "warned", a.boolean(s, true));
    const codes = try s.get(owner, "warningCodes");
    const code = try s.text("DEP0144");
    if (try a.condition(s.engine, hasCode, .{ owner, codes, code })) return;
    // Source const emitWarning survives the call and codesWarned.add.
    const emit = try s.get(try s.get(owner, "process"), "emitWarning");
    try statement(s.engine, emitWarning, .{ emit, code, try s.get(local, "function") });
    _ = try s.call(try s.get(owner, "setAdd"), codes, &.{code});
}
fn emitWarning(s: *Scope, emit: c.JSValue, code: c.JSValue, deprecated: c.JSValue) !void {
    _ = try s.call(emit, c.pi_js_undefined(), &.{ try s.text(warning_message), try s.text("DeprecationWarning"), code, deprecated });
}
fn deprecatedParent(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, deprecatedParentBody, .{ receiver, args, roots });
}
fn deprecatedParentBody(s: *Scope, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    // OP_rest precedes the warning call. The real ReflectApply consumes this
    // actual VM array even when this ordinary wrapper is used as a constructor.
    const generation = try s.beforeAllocation();
    const rest = try s.checkedAllocation(c.JS_PiCreateRestArray(s.engine.context,
        @intCast(args.len), @constCast(args.ptr)), generation);
    try statement(s.engine, warn, .{ roots[0], roots[1] });
    return a.duplicate(s.engine, try s.call(try s.get(roots[0], "reflectApply"), c.pi_js_undefined(), &.{ roots[2], receiver, rest }));
}
fn parentBody(s: *Scope, receiver: c.JSValue, owner: c.JSValue) !c.JSValue {
    if (v.nullish(receiver))
        return a.duplicate(s.engine, try s.get(receiver, "node:module_first_parent"));
    return a.duplicate(s.engine, try s.call(try s.get(owner, "weakGet"), try s.get(owner, "firstParents"), &.{receiver}));
}
fn getParent(engine: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, parentBody, .{ receiver, roots[0] });
}
fn setParentBody(s: *Scope, receiver: c.JSValue, value: c.JSValue, owner: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(receiver)) return @as(anyerror!c.JSValue,
        v.js.typeError(s.engine, "Cannot assign Module private parent to a primitive receiver"));
    try weakSet(s, owner, "firstParents", receiver, value);
    return c.pi_js_undefined();
}
fn setParent(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, setParentBody, .{ receiver, a.arg(args, 0), roots[0] });
}
fn getConstructor(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.duplicate(engine, roots[0]);
}
fn isPreloading(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.field(engine, roots[0], "isPreloading");
}
fn weakReadBody(s: *Scope, constructor: c.JSValue, name: [*:0]const u8, module: c.JSValue) !c.JSValue {
    const owner = try cachedOwner(s.engine, constructor);
    return a.duplicate(s.engine, try s.call(try s.get(owner, "weakGet"), try s.get(owner, name), &.{module}));
}
pub fn lastParent(engine: *v.em.Engine, constructor: c.JSValue, module: c.JSValue) !c.JSValue {
    return a.expression(engine, weakReadBody, .{ constructor, @as([*:0]const u8, "lastParents"), module });
}
pub fn firstParent(engine: *v.em.Engine, constructor: c.JSValue, module: c.JSValue) !c.JSValue {
    return a.expression(engine, weakReadBody, .{ constructor, @as([*:0]const u8, "firstParents"), module });
}
fn setLastParentBody(s: *Scope, constructor: c.JSValue, module: c.JSValue, parent: c.JSValue) !void {
    try weakSet(s, try cachedOwner(s.engine, constructor), "lastParents", module, parent);
}
pub fn setLastParent(engine: *v.em.Engine, constructor: c.JSValue, module: c.JSValue, parent: c.JSValue) !void {
    try statement(engine, setLastParentBody, .{ constructor, module, parent });
}
fn ownerField(s: *Scope, constructor: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return a.duplicate(s.engine, try s.get(try cachedOwner(s.engine, constructor), name));
}
/// Owned private lexical record for the genuine loader assembler. Validation
/// requires the exact already-completed Module; no public property is used to
/// reconstruct its retained primordials or the modulePaths cell.
pub fn loaderEnvironment(engine: *v.em.Engine, constructor: c.JSValue) !c.JSValue {
    return a.expression(engine, loaderEnvironmentBody, .{constructor});
}
fn loaderEnvironmentBody(s: *Scope, constructor: c.JSValue) !c.JSValue {
    try s.pending();
    return a.duplicate(s.engine, try cachedOwner(s.engine, constructor));
}
pub fn commonJSState(engine: *v.em.Engine, constructor: c.JSValue) !c.JSValue {
    return a.expression(engine, ownerField, .{ constructor, @as([*:0]const u8, "commonJSState") });
}
fn retainState(s: *Scope, constructor: c.JSValue, state: c.JSValue) !void {
    if (!c.JS_IsObject(state)) return error.ActualCommonJSLexicalOwnerRequired;
    const owner = try cachedOwner(s.engine, constructor);
    const previous = try s.get(owner, "commonJSState");
    if (!c.JS_IsUndefined(previous) and !s.equal(previous, state)) return error.DifferentCommonJSLexicalState;
    try define(s, owner, "commonJSState", state);
}
pub fn retainCommonJSState(engine: *v.em.Engine, constructor: c.JSValue, state: c.JSValue) !void {
    try statement(engine, retainState, .{ constructor, state });
}
pub const LoaderKey = enum { format, url, is_main, is_executing, cached_by_esm, required_module };
fn keyBody(s: *Scope, constructor: c.JSValue, key: LoaderKey) !c.JSValue {
    const owner = try cachedOwner(s.engine, constructor);
    const name: [*:0]const u8 = switch (key) {
        .format => "kFormat", .url => "kURL", .is_main => "kIsMainSymbol",
        .is_executing => "kIsExecuting", .cached_by_esm => "kIsCachedByESMLoader", .required_module => "kRequiredModuleSymbol",
    };
    const previous = try s.get(owner, name);
    if (!c.JS_IsUndefined(previous)) return a.duplicate(s.engine, previous);
    const generation = try s.beforeAllocation();
    const symbol = try s.checkedAllocation(c.JS_NewSymbol(s.engine.context, name, false), generation);
    try define(s, owner, name, symbol);
    return a.duplicate(s.engine, symbol);
}
pub fn loaderKey(engine: *v.em.Engine, constructor: c.JSValue, key: LoaderKey) !c.JSValue {
    return a.expression(engine, keyBody, .{ constructor, key });
}
fn exportMapBody(s: *Scope, constructor: c.JSValue) !c.JSValue {
    const owner = try cachedOwner(s.engine, constructor);
    const previous = try s.get(owner, "moduleExportMap");
    if (!c.JS_IsUndefined(previous)) return a.duplicate(s.engine, previous);
    const map = try s.construct(try s.get(owner, "weakMapConstructor"), &.{});
    try define(s, owner, "moduleExportMap", map);
    return a.duplicate(s.engine, map);
}
pub fn moduleExportMap(engine: *v.em.Engine, constructor: c.JSValue) !c.JSValue {
    return a.expression(engine, exportMapBody, .{constructor});
}
fn snapshotBody(s: *Scope, constructor: c.JSValue, module: c.JSValue, exports: c.JSValue) !void {
    const owner = try cachedOwner(s.engine, constructor);
    const map = try s.own(try moduleExportMap(s.engine, constructor));
    _ = try s.call(try s.get(owner, "weakSet"), map, &.{ module, exports });
}
pub fn snapshotExports(engine: *v.em.Engine, constructor: c.JSValue, module: c.JSValue, exports: c.JSValue) !void {
    try statement(engine, snapshotBody, .{ constructor, module, exports });
}
fn snapshotRead(s: *Scope, constructor: c.JSValue, module: c.JSValue) !c.JSValue {
    const owner = try cachedOwner(s.engine, constructor);
    const map = try s.own(try moduleExportMap(s.engine, constructor));
    return a.duplicate(s.engine, try s.call(try s.get(owner, "weakGet"), map, &.{module}));
}
pub fn exportsSnapshot(engine: *v.em.Engine, constructor: c.JSValue, module: c.JSValue) !c.JSValue {
    return a.expression(engine, snapshotRead, .{ constructor, module });
}
fn hasRecord(s: *Scope, constructor: c.JSValue, module: c.JSValue) !c.JSValue {
    const owner = try cachedOwner(s.engine, constructor);
    return a.boolean(s, s.truthy(try s.call(try s.get(owner, "weakHas"), try s.get(owner, "firstParents"), &.{module})));
}
pub fn hasPrivateModuleRecord(engine: *v.em.Engine, constructor: c.JSValue, module: c.JSValue) !bool {
    return a.condition(engine, hasRecord, .{ constructor, module });
}
pub fn pathObject(engine: *v.em.Engine, constructor: c.JSValue) !c.JSValue {
    return a.expression(engine, ownerField, .{ constructor, @as([*:0]const u8, "paths") });
}
fn convertedRead(s: *Scope, constructor: c.JSValue, filename: c.JSValue) !c.JSValue {
    const owner = try cachedOwner(s.engine, constructor);
    const map = try s.get(owner, "convertedBodies");
    if (c.JS_IsUndefined(map)) return c.pi_js_undefined();
    return a.duplicate(s.engine, try s.call(try s.get(owner, "mapGet"), map, &.{filename}));
}
pub fn convertedBody(engine: *v.em.Engine, constructor: c.JSValue, filename: c.JSValue) !c.JSValue {
    return a.expression(engine, convertedRead, .{ constructor, filename });
}
fn retainConverted(s: *Scope, constructor: c.JSValue, filename: c.JSValue, body: c.JSValue) !void {
    const owner = try cachedOwner(s.engine, constructor);
    var map = try s.get(owner, "convertedBodies");
    if (c.JS_IsUndefined(map)) {
        map = try s.construct(try s.get(owner, "mapConstructor"), &.{});
        try define(s, owner, "convertedBodies", map);
    }
    _ = try s.call(try s.get(owner, "mapSet"), map, &.{ filename, body });
}
pub fn retainConvertedBody(engine: *v.em.Engine, constructor: c.JSValue, filename: c.JSValue, body: c.JSValue) !void {
    try statement(engine, retainConverted, .{ constructor, filename, body });
}
fn addChildBody(s: *Scope, constructor: c.JSValue, parent: c.JSValue, module: c.JSValue) !void {
    try updateChildren(s, try cachedOwner(s.engine, constructor), parent, module, true);
}
pub fn addCachedChild(engine: *v.em.Engine, constructor: c.JSValue, parent: c.JSValue, module: c.JSValue) !void {
    try statement(engine, addChildBody, .{ constructor, parent, module });
}
fn isArray(s: *Scope, owner: c.JSValue, value: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.call(try s.get(owner, "arrayIsArray"), c.pi_js_undefined(), &.{value})));
}
fn removeChildBody(s: *Scope, constructor: c.JSValue, parent: c.JSValue, module: c.JSValue) !void {
    const owner = try cachedOwner(s.engine, constructor);
    const children = if (v.nullish(parent)) c.pi_js_undefined() else try s.get(parent, "children");
    if (!try a.condition(s.engine, isArray, .{ owner, children })) return;
    const index = try s.call(try s.get(owner, "arrayIndexOf"), children, &.{module});
    if (!s.equal(index, c.JS_NewInt32(s.engine.context, -1)))
        _ = try s.call(try s.get(owner, "arraySplice"), children, &.{ index, c.JS_NewInt32(s.engine.context, 1) });
}
pub fn removeChild(engine: *v.em.Engine, constructor: c.JSValue, parent: c.JSValue, module: c.JSValue) !void {
    try statement(engine, removeChildBody, .{ constructor, parent, module });
}
pub fn warningCodes(engine: *v.em.Engine, constructor: c.JSValue) !c.JSValue {
    return a.expression(engine, ownerField, .{ constructor, @as([*:0]const u8, "warningCodes") });
}
fn publishBody(s: *Scope, constructor: c.JSValue, filename: c.JSValue, module: c.JSValue) !void {
    _ = try cachedOwner(s.engine, constructor);
    const cache = try s.get(constructor, "_cache");
    try s.pending();
    const atom = c.JS_ValueToAtom(s.engine.context, filename);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try s.pending();
    if (atom == c.JS_ATOM_NULL) return error.MissingActualModuleCacheKeyReason;
    const status = c.JS_SetProperty(s.engine.context, cache, atom, a.duplicate(s.engine, module));
    try s.pending();
    if (status < 0) return error.MissingActualModuleCacheSetReason;
}
pub fn publish(engine: *v.em.Engine, constructor: c.JSValue, filename: c.JSValue, module: c.JSValue) !void {
    try statement(engine, publishBody, .{ constructor, filename, module });
}
