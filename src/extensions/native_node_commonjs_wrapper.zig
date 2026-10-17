// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Real Source Module.wrap/wrapper and mutation tracking over the same owner.
//! No compiler, ESM fallback or default Module namespace is selected here.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const lexical = @import("native_node_commonjs_state.zig");
const functions = @import("native_node_module_callable.zig");
const constructor = @import("native_node_module_constructor.zig");
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn accessor(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, getter: c.JSValue, setter: c.JSValue) !void {
    const atom = c.JS_NewAtom(engine.context, name);
    if (atom == c.JS_ATOM_NULL) return v.js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, target, atom, c.JS_DupValue(engine.context, getter), c.JS_DupValue(engine.context, setter), c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
/// Invoke during actual Module bootstrap, before guest code. The exact known
/// constructor authenticates the private owner before any opaque storage read.
/// This is not invoked by the legacy default node:module installation.
pub fn install(engine: *v.em.Engine, module: c.JSValue) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const owner = try s.own(try constructor.commonJSState(engine, module));
    if (c.JS_IsUndefined(owner)) return error.ActualCommonJSLexicalOwnerRequired;
    const state = try lexical.known(engine, owner);
    if (state.wrapper_initialized) return error.CommonJSWrapperAlreadyInitialized;
    const strings = try s.array();
    try s.index(strings, 0, try s.text("(function (exports, require, module, __filename, __dirname) { "));
    try s.index(strings, 1, try s.text("\n});"));
    const reflect = try s.global("Reflect");
    try s.put(state.roots, "wrapperReflectSet", try s.get(reflect, "set"));
    try s.put(state.roots, "wrapperDefineProperty", try s.get(try s.global("Object"), "defineProperty"));
    const handlers = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try s.put(handlers, "set", try s.own(try functions.create(engine, "set", 4, false, setTrap, &.{owner})));
    try s.put(handlers, "defineProperty", try s.own(try functions.create(engine, "defineProperty", 3, false, defineTrap, &.{owner})));
    var arguments = [_]c.JSValue{ strings, handlers };
    const proxy = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, try s.global("Proxy"), arguments.len, &arguments)));
    try s.put(state.roots, "wrapperProxy", proxy);
    try s.put(state.roots, "wrapperWrap", try s.own(try functions.create(engine, "wrap", 1, true, wrapBody, &.{owner})));
    const get_wrap = try s.own(try functions.create(engine, "get", 0, false, getWrap, &.{owner}));
    const set_wrap = try s.own(try functions.create(engine, "set", 1, false, setWrap, &.{owner}));
    const get_wrapper = try s.own(try functions.create(engine, "get", 0, false, getWrapper, &.{owner}));
    const set_wrapper = try s.own(try functions.create(engine, "set", 1, false, setWrapper, &.{owner}));
    try accessor(engine, module, "wrap", get_wrap, set_wrap);
    try accessor(engine, module, "wrapper", get_wrapper, set_wrapper);
    state.wrapper_initialized = true;
}
fn wrapBody(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const state = try lexical.known(engine, roots[0]);
    const module = try s.get(state.roots, "module_constructor");
    const first = try v.at(&s, try s.get(module, "wrapper"), 0);
    const prefix = try s.concat(first, arg(args, 0));
    const last = try v.at(&s, try s.get(module, "wrapper"), 1);
    return engine.checked(c.JS_PiBinaryOperator(engine.context, 0, prefix, last));
}
fn getWrap(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return v.js.get(engine, (try lexical.known(engine, roots[0])).roots, "wrapperWrap");
}
fn getWrapper(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return v.js.get(engine, (try lexical.known(engine, roots[0])).roots, "wrapperProxy");
}
fn setWrap(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const state = try lexical.known(engine, roots[0]);
    state.wrapper_patched = true;
    try s.put(state.roots, "wrapperWrap", arg(args, 0));
    return c.pi_js_undefined();
}
fn setWrapper(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const state = try lexical.known(engine, roots[0]);
    state.wrapper_patched = true;
    try s.put(state.roots, "wrapperProxy", arg(args, 0));
    return c.pi_js_undefined();
}
fn setTrap(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const state = try lexical.known(engine, roots[0]);
    state.wrapper_patched = true;
    return v.js.call(engine, try s.get(state.roots, "wrapperReflectSet"), c.pi_js_undefined(), &.{ arg(args, 0), arg(args, 1), arg(args, 2), arg(args, 3) });
}
fn defineTrap(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const state = try lexical.known(engine, roots[0]);
    state.wrapper_patched = true;
    return v.js.call(engine, try s.get(state.roots, "wrapperDefineProperty"), c.pi_js_undefined(), &.{ arg(args, 0), arg(args, 1), arg(args, 2) });
}
