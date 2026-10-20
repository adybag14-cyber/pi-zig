// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual Node24.14 internal/util emitExperimentalWarning and its one private
//! experimentalWarnings SafeSet. The genuine builtin process wrapper parameter
//! is retained; its emitWarning property remains a live Source lookup.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const sync = @import("native_sync_arguments.zig");
const functions = @import("native_node_module_callable.zig");
const collections = @import("native_node_fs_collections.zig");
const publication = @import("native_node_fs_private_publication.zig");
const Frame = a.frames.Frame(enum { message });
const cache_key = "pi-native:private/node-util-experimental-warning";

fn hasWarning(s: *Scope, warnings: c.JSValue, feature: c.JSValue) !c.JSValue {
    const method = try s.get(warnings, "has");
    const value = try s.call(method, warnings, &.{feature});
    return a.boolean(s, s.truthy(value));
}
fn addWarning(s: *Scope, warnings: c.JSValue, feature: c.JSValue) !c.JSValue {
    const method = try s.get(warnings, "add");
    _ = try s.call(method, warnings, &.{feature});
    return c.pi_js_undefined();
}
fn messageValue(s: *Scope, feature: c.JSValue) !c.JSValue {
    // Original untagged template eagerly ToStrings the feature. Its result
    // and the literal tail are primitive strings; concat invokes no method.
    const feature_text = try s.toString(feature);
    const tail = try s.text(" is an experimental feature and might change at any time");
    return a.duplicate(s.engine, try s.binary(0, feature_text, tail));
}
fn prefixedMessage(s: *Scope, prefix: c.JSValue, message: c.JSValue) !c.JSValue {
    // This Source expression is ordinary + with its original default hint.
    return a.duplicate(s.engine, try s.binary(0, prefix, message));
}
fn emitWarning(s: *Scope, process: c.JSValue, message: c.JSValue,
    code: c.JSValue, ctor: c.JSValue) !c.JSValue
{
    const method = try s.get(process, "emitWarning");
    const warning_type = try s.text("ExperimentalWarning");
    _ = try s.call(method, process, &.{ message, warning_type, code, ctor });
    return c.pi_js_undefined();
}
fn body(s: *Scope, args: *sync.Arguments, frame: *Frame,
    roots: []const c.JSValue) !c.JSValue
{
    if (try a.condition(s.engine, hasWarning, .{ roots[0], args.get(0) }))
        return c.pi_js_undefined();
    // Membership publishes before feature conversion and is not rolled back
    // when a later conversion or the actual warning callback throws.
    _ = try a.expression(s.engine, addWarning, .{ roots[0], args.get(0) });
    try frame.take(.message, a.expression(s.engine, messageValue, .{args.get(0)}));
    if (s.truthy(args.get(1)))
        try frame.take(.message, a.expression(s.engine, prefixedMessage,
            .{ args.get(1), frame.get(.message) }));
    _ = try a.expression(s.engine, emitWarning,
        .{ roots[1], frame.get(.message), args.get(2), args.get(3) });
    return c.pi_js_undefined();
}
fn callback(engine: *a.v.em.Engine, _: c.JSValue,
    args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue
{
    var s = Scope.init(engine);
    const frame = args.createFrame(&s.values, Frame) catch |err|
        return s.finish(@as(anyerror!c.JSValue, err));
    // Actual C hooks detach captures and retire the original local after
    // formals. The borrowed callback view does not close the Frame early.
    return s.finish(body(&s, args, frame, roots));
}
fn createBody(s: *Scope) !c.JSValue {
    const process = try s.own((try s.engine.requireBuiltin("node:process")) orelse
        return error.ActualNodeExperimentalWarningProcessRequired);
    // Genuine primordial bootstrap supplies the shared retained SafeSet owner.
    const constructor = try s.own(try collections.acquireSafeSet(s.engine));
    const warnings = try s.construct(constructor, &.{});
    return functions.createWithArguments(s.engine, "emitExperimentalWarning", 4, true,
        .{ .formal_count = 4, .callback = callback, .hooks = sync.frameHooks(Frame) },
        &.{ warnings, process });
}
pub fn acquire(engine: *a.v.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached|
        return a.duplicate(engine, cached);
    const candidate = try a.expression(engine, createBody, .{});
    if (engine.native_module_values.get(cache_key)) |cached| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, cached));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, cache_key, candidate);
}
