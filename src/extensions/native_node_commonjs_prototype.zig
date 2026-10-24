// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual Node24 Module.prototype require/load/_compile bodies.
//! No default publication: wrapSafe/sync ESM/inspector/TS must be real inputs.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const functions = @import("native_node_module_callable.zig");
const lexical = @import("native_node_commonjs_state.zig");
const constructor = @import("native_node_module_constructor.zig");
pub const Inputs = struct {
    module_constructor: c.JSValue,
    path: c.JSValue,
    debug: c.JSValue,
    assert: c.JSValue,
    validate_string: c.JSValue,
    invalid_arg_value: c.JSValue,
    wrap_module_load: c.JSValue,
    strip_typescript_module_types: c.JSValue,
    wrap_safe: c.JSValue,
    load_esm_from_cjs: c.JSValue,
    make_require_function: c.JSValue,
    call_and_pause_on_start: c.JSValue,
    inspect_brk: bool,
};
/// All four values are owned. Host ESM/hook composition shares these exact
/// symbol values through the retained private state, never by description.
pub const Graph = struct { require: c.JSValue, load: c.JSValue, compile: c.JSValue, lexical_owner: c.JSValue };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Graph {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const previous = try s.own(try constructor.commonJSState(engine, inputs.module_constructor));
    if (!c.JS_IsUndefined(previous)) return error.CommonJSPrototypeAlreadyCreated;
    const roots = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    inline for (std.meta.fields(Inputs)) |field| {
        if (comptime std.mem.eql(u8, field.name, "inspect_brk")) {
            try s.put(roots, field.name, c.pi_js_bool(engine.context, @intFromBool(inputs.inspect_brk)));
        } else {
            const value = @field(inputs, field.name);
            if (comptime !std.mem.eql(u8, field.name, "module_constructor") and !std.mem.eql(u8, field.name, "path")) {
                if (!c.JS_IsFunction(engine.context, value)) return error.ActualCommonJSPrototypeDependencyRequired;
            }
            try s.put(roots, field.name, value);
        }
    }
    // Original internal/modules/helpers owns this lexical fact. It is shared
    // with its getters/ESM sibling and is not supplied by the embedding caller.
    const execution_state = try s.own(try @import("native_node_module_execution_state.zig").acquire(engine));
    try s.put(roots, "set_started_user_cjs", try s.get(execution_state, "setHasStartedUserCJSExecution"));
    inline for (.{ .{ "kFormat", constructor.LoaderKey.format }, .{ "kIsMainSymbol", constructor.LoaderKey.is_main }, .{ "kIsExecuting", constructor.LoaderKey.is_executing }, .{ "kURL", constructor.LoaderKey.url }, .{ "kIsCachedByESMLoader", constructor.LoaderKey.cached_by_esm } }) |entry| try s.put(roots, entry[0], try s.own(try constructor.loaderKey(engine, inputs.module_constructor, entry[1])));
    // Private Module export snapshot is not a public Symbol property. A VM
    // WeakMap provides the matching non-enumerable, GC-aware private relation.
    const weak = try s.global("WeakMap");
    try s.put(roots, "moduleExport", try s.own(try constructor.moduleExportMap(engine, inputs.module_constructor)));
    try s.put(roots, "weakSet", try s.get(try s.get(weak, "prototype"), "set"));
    const map = try s.global("Map");
    try s.put(roots, "mapConstructor", map);
    const map_prototype = try s.get(map, "prototype");
    try s.put(roots, "mapGet", try s.get(map_prototype, "get"));
    try s.put(roots, "mapSet", try s.get(map_prototype, "set"));
    const strings = try s.get(try s.global("String"), "prototype");
    try s.put(roots, "stringIndexOf", try s.get(strings, "indexOf"));
    try s.put(roots, "stringSlice", try s.get(strings, "slice"));
    const owner = try s.own(try lexical.create(engine, roots));
    const require = try s.own(try functions.create(engine, "", 1, true, requireBody, &.{owner}));
    const load = try s.own(try functions.create(engine, "", 1, true, loadBody, &.{owner}));
    const compile = try s.own(try functions.create(engine, "", 3, true, compileBody, &.{owner}));
    try constructor.retainCommonJSState(engine, inputs.module_constructor, owner);
    return .{ .require = c.JS_DupValue(engine.context, require), .load = c.JS_DupValue(engine.context, load), .compile = c.JS_DupValue(engine.context, compile), .lexical_owner = c.JS_DupValue(engine.context, owner) };
}
fn requireBody(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const state = try lexical.known(engine, roots[0]);
    const id = arg(args, 0);
    _ = try s.call(try s.get(state.roots, "validate_string"), c.pi_js_undefined(), &.{ id, try s.text("id") });
    if (try v.eq(&s, id, "")) {
        var parameters = [_]c.JSValue{ try s.text("id"), id, try s.text("must be a non-empty string") };
        const reason = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, try s.get(state.roots, "invalid_arg_value"), parameters.len, &parameters)));
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        unreachable;
    }
    if (state.require_depth == std.math.maxInt(u64)) return error.CommonJSRequireDepthOverflow;
    state.require_depth += 1;
    defer state.require_depth -= 1; // No allocation or fallible cleanup over a raw throw.
    return v.js.call(engine, try s.get(state.roots, "wrap_module_load"), c.pi_js_undefined(), &.{ id, receiver, c.pi_js_bool(engine.context, 0) });
}
fn keyGet(s: *Scope, state: *lexical.State, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return s.own(try v.js.getKey(s.engine, receiver, try s.get(state.roots, name)));
}
fn keySet(s: *Scope, state: *lexical.State, receiver: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    return v.js.setKey(s.engine, receiver, try s.get(state.roots, name), value);
}
fn longestExtension(s: *Scope, state: *lexical.State, filename: c.JSValue) !c.JSValue {
    const path = try s.get(state.roots, "path");
    const name = try s.invoke(path, "basename", &.{filename});
    var start: i32 = 0;
    var steps: usize = 0;
    while (true) {
        var iteration: Scope = .{ .engine = s.engine }; defer iteration.deinit();
        try @import("native_node_commonjs_interrupt.zig").step(s.engine, &steps);
        const found = try iteration.call(try iteration.get(state.roots, "stringIndexOf"), name, &.{ try iteration.text("."), c.JS_NewInt32(s.engine.context, start) });
        var index: i32 = 0;
        if (c.JS_ToInt32(s.engine.context, &index, found) < 0) return v.js.capture(s.engine);
        if (index == -1) return s.text(".js");
        start = index + 1;
        if (index == 0) continue;
        const extension = try iteration.call(try iteration.get(state.roots, "stringSlice"), name, &.{found});
        const registry = try iteration.get(try iteration.get(state.roots, "module_constructor"), "_extensions");
        if (iteration.truthy(try iteration.own(try v.js.getKey(s.engine, registry, extension)))) return s.own(c.JS_DupValue(s.engine.context, extension));
    }
}
fn loadBody(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const state = try lexical.known(engine, roots[0]);
    const filename = arg(args, 0);
    _ = try s.call(try s.get(state.roots, "debug"), c.pi_js_undefined(), &.{ try s.text("load %j for module %j"), filename, try s.get(receiver, "id") });
    _ = try s.call(try s.get(state.roots, "assert"), c.pi_js_undefined(), &.{c.pi_js_bool(engine.context, @intFromBool(!s.truthy(try s.get(receiver, "loaded"))))});
    if (v.nullish(try s.get(receiver, "filename"))) try s.set(receiver, "filename", filename);
    if (v.nullish(try s.get(receiver, "paths"))) {
        const module = try s.get(state.roots, "module_constructor");
        // Capture the live _nodeModulePaths callee before dirname's getter/call.
        const paths = try s.get(module, "_nodeModulePaths");
        const dirname = try s.invoke(try s.get(state.roots, "path"), "dirname", &.{filename});
        try s.set(receiver, "paths", try s.call(paths, module, &.{dirname}));
    }
    var extension: c.JSValue = undefined;
    if (!c.JS_IsUndefined(try keyGet(&s, state, receiver, "kFormat"))) {
        const format = try keyGet(&s, state, receiver, "kFormat");
        extension = try s.text(if (try v.eq(&s, format, "addon")) ".node" else if (try v.eq(&s, format, "json")) ".json" else ".js");
    } else extension = try longestExtension(&s, state, filename);
    const registry = try s.get(try s.get(state.roots, "module_constructor"), "_extensions");
    const handler = try s.own(try v.js.getKey(engine, registry, extension));
    _ = try s.call(handler, registry, &.{ receiver, filename });
    try s.set(receiver, "loaded", c.pi_js_bool(engine.context, 1));
    const exports = try s.get(receiver, "exports");
    _ = try s.call(try s.get(state.roots, "weakSet"), try s.get(state.roots, "moduleExport"), &.{ receiver, exports });
    return c.pi_js_undefined();
}
fn compileBody(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const state = try lexical.known(engine, roots[0]);
    var content = arg(args, 0);
    const filename = arg(args, 1);
    var format = arg(args, 2);
    if (try v.eq(&s, format, "commonjs-typescript") or try v.eq(&s, format, "module-typescript") or try v.eq(&s, format, "typescript")) {
        content = try s.call(try s.get(state.roots, "strip_typescript_module_types"), c.pi_js_undefined(), &.{ content, filename });
        format = if (try v.eq(&s, format, "commonjs-typescript")) try s.text("commonjs") else if (try v.eq(&s, format, "module-typescript")) try s.text("module") else c.pi_js_undefined();
    }
    var wrapper = c.pi_js_undefined();
    if (!try v.eq(&s, format, "module")) {
        wrapper = try s.own(try @import("native_node_commonjs_converted_provider.zig").compiledBody(engine, try s.get(state.roots, "module_constructor"), filename, format, state.wrapper_initialized, state.wrapper_patched));
        if (c.JS_IsUndefined(wrapper)) {
            const compiled = try s.call(try s.get(state.roots, "wrap_safe"), c.pi_js_undefined(), &.{ filename, content, receiver, format });
            wrapper = try s.get(compiled, "function");
            if (s.truthy(try s.get(compiled, "canParseAsESM"))) format = try s.text("module");
        }
    }
    if (try v.eq(&s, format, "module")) {
        _ = try s.call(try s.get(state.roots, "load_esm_from_cjs"), c.pi_js_undefined(), &.{ receiver, filename, format, content });
        return c.pi_js_undefined();
    }
    const dirname = try s.invoke(try s.get(state.roots, "path"), "dirname", &.{filename});
    const require = try s.call(try s.get(state.roots, "make_require_function"), c.pi_js_undefined(), &.{ receiver, c.pi_js_undefined() });
    const exports = try s.get(receiver, "exports");
    if (state.require_depth == 0) {
        const fresh = try engine.checked(c.JS_CallConstructor(engine.context, try s.get(state.roots, "mapConstructor"), 0, null));
        const old = state.stat_cache;
        state.stat_cache = fresh;
        engine.freeValue(old);
    }
    _ = try s.call(try s.get(state.roots, "set_started_user_cjs"), c.pi_js_undefined(), &.{});
    try keySet(&s, state, receiver, "kIsExecuting", c.pi_js_bool(engine.context, 1));
    const result = if (s.truthy(try keyGet(&s, state, receiver, "kIsMainSymbol")) and s.truthy(try s.get(state.roots, "inspect_brk")))
        try s.call(try s.get(state.roots, "call_and_pause_on_start"), c.pi_js_undefined(), &.{ wrapper, exports, exports, require, receiver, filename, dirname })
    else try s.call(wrapper, exports, &.{ exports, require, receiver, filename, dirname });
    // Source has no finally here: a wrapper throw retains executing/statCache.
    try keySet(&s, state, receiver, "kIsExecuting", c.pi_js_bool(engine.context, 0));
    if (state.require_depth == 0) lexical.clearStatCache(state);
    return c.JS_DupValue(engine.context, result);
}
