// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual Node24 Module._load body over the canonical Module lexical owner.
//! Real resolver/hooks/builtin/circular helpers remain required dependencies.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const lexical = @import("native_node_commonjs_state.zig");
const constructor = @import("native_node_module_constructor.zig");
pub const Inputs = struct {
    process: c.JSValue,
    resolve_for_cjs_with_hooks: c.JSValue,
    load_builtin_with_hooks: c.JSValue,
    normalize_requirable_id: c.JSValue,
    can_require_without_scheme: c.JSValue,
    circular_exports: c.JSValue,
    circular_warning_proxy: c.JSValue,
    should_report_required_modules: c.JSValue,
};
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn create(engine: *v.em.Engine, module: c.JSValue, inputs: Inputs) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const owner = try s.own(try constructor.commonJSState(engine, module));
    if (c.JS_IsUndefined(owner)) return error.ActualCommonJSLexicalOwnerRequired;
    const state = try lexical.known(engine, owner);
    if (!c.JS_IsObject(inputs.process) or !c.JS_IsProxy(inputs.circular_warning_proxy)) return error.ActualCommonJSLoadDependencyRequired;
    if (!c.JS_IsUndefined(try s.get(state.roots, "relativeResolveCache"))) return error.CommonJSLoadAlreadyCreated;
    inline for (std.meta.fields(Inputs)) |field| {
        const value = @field(inputs, field.name);
        if (comptime !std.mem.eql(u8, field.name, "process") and !std.mem.eql(u8, field.name, "circular_warning_proxy")) {
            if (!c.JS_IsFunction(engine.context, value)) return error.ActualCommonJSLoadDependencyRequired;
        }
        try s.put(state.roots, field.name, value);
    }
    try s.put(state.roots, "relativeResolveCache", try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()))));
    const empty = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    if (c.JS_FreezeObject(engine.context, empty) < 0) return v.js.capture(engine);
    try s.put(state.roots, "loadEmptyOptions", empty);
    const array = try s.global("Array");
    try s.put(state.roots, "loadArrayIsArray", try s.get(array, "isArray"));
    const arrays = try s.get(array, "prototype");
    inline for (.{ .{ "loadArrayIncludes", "includes" }, .{ "loadArrayPush", "push" }, .{ "loadArrayIndexOf", "indexOf" }, .{ "loadArraySplice", "splice" } }) |pair| try s.put(state.roots, pair[0], try s.get(arrays, pair[1]));
    const object = try s.global("Object");
    try s.put(state.roots, "loadObjectPrototype", try s.get(object, "prototype"));
    try s.put(state.roots, "loadGetPrototypeOf", try s.get(object, "getPrototypeOf"));
    try s.put(state.roots, "loadSetPrototypeOf", try s.get(object, "setPrototypeOf"));
    try s.put(state.roots, "loadStringStartsWith", try s.get(try s.get(try s.global("String"), "prototype"), "startsWith"));
    const weak = try s.global("WeakMap");
    try s.put(state.roots, "moduleSource", try s.own(try engine.checked(c.JS_CallConstructor(engine.context, weak, 0, null))));
    try s.put(state.roots, "moduleCircularVisited", try s.own(try engine.checked(c.JS_CallConstructor(engine.context, weak, 0, null))));
    try s.put(state.roots, "loadWeakGet", try s.get(try s.get(weak, "prototype"), "get"));
    return @import("native_node_module_callable.zig").create(engine, "", 3, true, loadBody, &.{owner});
}
fn property(s: *Scope, value: c.JSValue, key: c.JSValue) !c.JSValue { return s.own(try v.js.getKey(s.engine, value, key)); }
fn symbol(s: *Scope, state: *lexical.State, value: c.JSValue, key: [*:0]const u8) !c.JSValue { return property(s, value, try s.get(state.roots, key)); }
fn setSymbol(s: *Scope, state: *lexical.State, value: c.JSValue, key: [*:0]const u8, item: c.JSValue) !void { return v.js.setKey(s.engine, value, try s.get(state.roots, key), item); }
fn privateSet(s: *Scope, state: *lexical.State, map: [*:0]const u8, module: c.JSValue, value: c.JSValue) !void { _ = try s.call(try s.get(state.roots, "weakSet"), try s.get(state.roots, map), &.{ module, value }); }
fn privateGet(s: *Scope, state: *lexical.State, map: [*:0]const u8, module: c.JSValue) !c.JSValue { return s.call(try s.get(state.roots, "loadWeakGet"), try s.get(state.roots, map), &.{module}); }
fn remove(s: *Scope, target: c.JSValue, key: c.JSValue) !void {
    const atom = try v.js.atom(s.engine, key);
    defer c.JS_FreeAtom(s.engine.context, atom);
    if (c.JS_DeleteProperty(s.engine.context, target, atom, c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
}
fn updateChildren(s: *Scope, state: *lexical.State, parent: c.JSValue, child: c.JSValue) !void {
    const children = try v.optional(s, parent, "children");
    if (s.truthy(children) and !s.truthy(try s.call(try s.get(state.roots, "loadArrayIncludes"), children, &.{child}))) {
        _ = try s.call(try s.get(state.roots, "loadArrayPush"), children, &.{child});
    }
}
fn report(s: *Scope, state: *lexical.State, filename: c.JSValue) !void {
    if (!s.truthy(try s.call(try s.get(state.roots, "should_report_required_modules"), c.pi_js_undefined(), &.{}))) return;
    const process = try s.get(state.roots, "process");
    if (!s.truthy(try s.get(process, "send"))) return;
    const send = try s.get(process, "send");
    const record = try s.object();
    const list = try s.array();
    try s.index(list, 0, filename);
    try s.put(record, "watch:require", list);
    _ = try s.call(send, process, &.{record});
}
fn circular(s: *Scope, state: *lexical.State, module: c.JSValue) !c.JSValue { return s.call(try s.get(state.roots, "circular_exports"), c.pi_js_undefined(), &.{module}); }
fn failedCleanup(s: *Scope, state: *lexical.State, module: c.JSValue, parent: c.JSValue, filename: c.JSValue, relative: c.JSValue) !void {
    try remove(s, try s.get(try s.get(state.roots, "module_constructor"), "_cache"), filename);
    if (!c.JS_IsUndefined(parent)) {
        try remove(s, try s.get(state.roots, "relativeResolveCache"), relative);
        const children = try v.optional(s, parent, "children");
        if (s.truthy(try s.call(try s.get(state.roots, "loadArrayIsArray"), c.pi_js_undefined(), &.{children}))) {
            const index = try s.call(try s.get(state.roots, "loadArrayIndexOf"), children, &.{module});
            if (!s.equal(index, c.JS_NewInt32(s.engine.context, -1))) _ = try s.call(try s.get(state.roots, "loadArraySplice"), children, &.{ index, c.JS_NewInt32(s.engine.context, 1) });
        }
    }
}
fn loadBody(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const state = try lexical.known(engine, roots[0]);
    const module_constructor = try s.get(state.roots, "module_constructor");
    const request = arg(args, 0);
    const parent = arg(args, 1);
    const is_main = arg(args, 2);
    const options = if (c.JS_IsUndefined(arg(args, 3))) try s.get(state.roots, "loadEmptyOptions") else arg(args, 3);
    var relative = c.pi_js_undefined();
    const relative_cache = try s.get(state.roots, "relativeResolveCache");
    if (s.truthy(parent)) {
        _ = try s.call(try s.get(state.roots, "debug"), c.pi_js_undefined(), &.{ try s.text("Module._load REQUEST %s parent: %s"), request, try s.get(parent, "id") });
        const prefix = try s.concat(try s.stringify(try s.get(parent, "path")), try s.text("\x00"));
        relative = try s.concat(prefix, try s.stringify(request));
        const filename = try property(&s, relative_cache, relative);
        try report(&s, state, filename);
        if (!c.JS_IsUndefined(filename)) {
            const cached = try property(&s, try s.get(module_constructor, "_cache"), filename);
            if (!c.JS_IsUndefined(cached)) {
                try updateChildren(&s, state, parent, cached);
                if (!s.truthy(try s.get(cached, "loaded"))) return c.JS_DupValue(engine.context, try circular(&s, state, cached));
                return v.js.get(engine, cached, "exports");
            }
            try remove(&s, relative_cache, relative);
        }
    }
    const resolved = try s.call(try s.get(state.roots, "resolve_for_cjs_with_hooks"), c.pi_js_undefined(), &.{ request, parent, is_main, try s.get(options, "shouldSkipModuleHooks") });
    var format = try s.get(resolved, "format");
    const url = try s.get(resolved, "url");
    const filename = try s.get(resolved, "filename");
    var from_hook = c.pi_js_undefined();
    if (s.equal(request, url) and s.truthy(try s.call(try s.get(state.roots, "loadStringStartsWith"), request, &.{try s.text("node:")}))) {
        const normalized = try s.call(try s.get(state.roots, "normalize_requirable_id"), c.pi_js_undefined(), &.{request});
        if (s.truthy(normalized)) {
            const builtin = try s.call(try s.get(state.roots, "load_builtin_with_hooks"), c.pi_js_undefined(), &.{ normalized, url, format });
            const result = try s.get(builtin, "resultFromHook");
            const exports = try s.get(builtin, "builtinExports");
            if (s.truthy(exports)) return c.JS_DupValue(engine.context, exports);
            from_hook = result;
            format = try s.get(from_hook, "format");
        }
    }
    var cached = c.pi_js_undefined();
    if (c.JS_IsUndefined(from_hook)) {
        cached = try property(&s, try s.get(module_constructor, "_cache"), filename);
        _ = try s.call(try s.get(state.roots, "debug"), c.pi_js_undefined(), &.{ try s.text("Module._load checking cache for"), filename, c.pi_js_bool(engine.context, @intFromBool(s.truthy(cached))) });
        if (!c.JS_IsUndefined(cached)) {
            try updateChildren(&s, state, parent, cached);
            if (s.truthy(try s.get(cached, "loaded"))) return v.js.get(engine, cached, "exports");
            if (!s.truthy(try symbol(&s, state, cached, "kIsCachedByESMLoader"))) return c.JS_DupValue(engine.context, try circular(&s, state, cached));
            if (s.truthy(try privateGet(&s, state, "moduleCircularVisited", cached))) return c.JS_DupValue(engine.context, try circular(&s, state, cached));
            try privateSet(&s, state, "moduleCircularVisited", cached, c.pi_js_bool(engine.context, 1));
        }
    }
    if (c.JS_IsUndefined(from_hook) and s.truthy(try s.call(try s.get(state.roots, "can_require_without_scheme"), c.pi_js_undefined(), &.{filename}))) {
        const builtin = try s.call(try s.get(state.roots, "load_builtin_with_hooks"), c.pi_js_undefined(), &.{ filename, url, format });
        const result = try s.get(builtin, "resultFromHook");
        const exports = try s.get(builtin, "builtinExports");
        if (s.truthy(exports)) return c.JS_DupValue(engine.context, exports);
        from_hook = result;
        format = try s.get(from_hook, "format");
    }
    var parameters = [_]c.JSValue{ filename, parent };
    const module = if (s.truthy(cached)) cached else try s.own(try engine.checked(c.JS_CallConstructor(engine.context, module_constructor, parameters.len, &parameters)));
    if (!s.truthy(cached)) {
        if (s.truthy(is_main)) {
            const process = try s.get(state.roots, "process");
            try s.put(process, "mainModule", module);
            const require = try s.get(module, "require");
            try s.put(require, "main", try s.get(process, "mainModule"));
            try s.set(module, "id", try s.text("."));
            try setSymbol(&s, state, module, "kIsMainSymbol", c.pi_js_bool(engine.context, 1));
        } else try setSymbol(&s, state, module, "kIsMainSymbol", c.pi_js_bool(engine.context, 0));
        if (!c.JS_IsUndefined(from_hook)) try privateSet(&s, state, "moduleSource", module, try s.get(from_hook, "source"));
        try report(&s, state, filename);
        try v.js.setKey(engine, try s.get(module_constructor, "_cache"), filename, module);
        try setSymbol(&s, state, module, "kIsCachedByESMLoader", c.pi_js_bool(engine.context, 0));
        try setSymbol(&s, state, module, "kURL", url);
        try setSymbol(&s, state, module, "kFormat", format);
    } else try constructor.setLastParent(engine, module_constructor, module, parent);
    if (!c.JS_IsUndefined(parent)) try v.js.setKey(engine, relative_cache, relative, filename);
    try loadWithCleanup(engine, state, module, parent, filename, relative);
    if (s.truthy(try s.get(module, "exports")) and !c.JS_IsProxy(try s.get(module, "exports")) and
        s.equal(try s.call(try s.get(state.roots, "loadGetPrototypeOf"), c.pi_js_undefined(), &.{try s.get(module, "exports")}), try s.get(state.roots, "circular_warning_proxy"))) {
        _ = try s.call(try s.get(state.roots, "loadSetPrototypeOf"), c.pi_js_undefined(), &.{ try s.get(module, "exports"), try s.get(state.roots, "loadObjectPrototype") });
    }
    return v.js.get(engine, module, "exports");
}
/// Actual _load call/finally boundary, also used by focused native controls.
/// state is the already authenticated private lexical record, not a guest token.
/// Tests of this function do not assert a composed Module namespace/bootstrap.
pub fn loadWithCleanup(engine: *v.em.Engine, state: *lexical.State, module: c.JSValue, parent: c.JSValue, filename: c.JSValue, relative: c.JSValue) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const generation = engine.native_allocation_generation;
    _ = s.invoke(module, "load", &.{filename}) catch |err| {
        // A trusted VM/native abort bypasses guest finally execution, as in
        // the linked runtime; do not let arbitrary cleanup replace that reason.
        if (err == error.OutOfMemory) return err;
        if (err != error.JavaScriptException) return err;
        const original = engine.captured_exception orelse return error.MissingCommonJSLoadException;
        if (c.JS_IsUncatchableError(original)) return err;
        try @import("native_async_body.zig").rethrowRecognizedAllocation(engine, original, generation);
        engine.captured_exception = null;
        failedCleanup(&s, state, module, parent, filename, relative) catch |cleanup_error| {
            engine.freeValue(original);
            return cleanup_error;
        };
        if (engine.captured_exception) |prior| engine.freeValue(prior);
        engine.captured_exception = original;
        return err;
    };
}
