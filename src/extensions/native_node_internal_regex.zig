// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! internal/util's real cross-realm RegExp cache and @@replace operation.
//! The cache is a genuine SafeWeakMap, not a host replacement loop or a second
//! regex realm. Main Engine.context and runtime pending exception stay unchanged.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const realm = @import("native_node_internal_realm.zig");
const collections = @import("native_node_fs_collections.zig");
const publication = @import("native_node_fs_private_publication.zig");
const key = "pi-native:private/internal-cross-realm-regex";
const Frame = a.frames.Frame(enum { cached, flags, constructor, result });
const flag_names = .{ "hasIndices", "global", "ignoreCase", "multiline", "dotAll", "unicode", "sticky" };
const flag_chars = .{ "d", "g", "i", "m", "s", "u", "y" };

fn captureGetterBody(s: *Scope, prototype: c.JSValue, name: [*:0]const u8) !c.JSValue {
    var descriptor = try s.descriptor(prototype, try s.text(std.mem.span(name))) orelse return error.ActualRegExpGetterRequired;
    defer s.releaseDescriptor(&descriptor);
    if (descriptor.flags & c.JS_PROP_GETSET == 0 or !c.JS_IsFunction(s.engine.context, descriptor.getter))
        return error.ActualRegExpGetterRequired;
    return a.duplicate(s.engine, descriptor.getter);
}
const std = @import("std");
fn createBody(s: *Scope) !c.JSValue {
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    const regexp = try s.get(global, "RegExp");
    const prototype = try s.get(regexp, "prototype");
    const record = try s.objectProto(c.pi_js_null());
    inline for (flag_names) |name| {
        const getter = try s.own(try a.expression(s.engine, captureGetterBody, .{prototype, @as([*:0]const u8, name)}));
        try s.put(record, name, getter);
    }
    try s.put(record, "source", try s.own(try a.expression(s.engine, captureGetterBody, .{prototype, @as([*:0]const u8, "source")})));
    try s.put(record, "replace", try s.get(try s.get(global, "Symbol"), "replace"));
    const constructor = try s.own(try collections.acquireSafeWeakMap(s.engine));
    try s.put(record, "cache", try s.construct(constructor, &.{}));
    return a.duplicate(s.engine, record);
}
/// Called with the genuine bootstrap before guest mutation. Later calls reuse
/// the same original intrinsic getters and actual SafeWeakMap instance.
pub fn acquire(engine: *a.v.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |known| return a.duplicate(engine, known);
    const candidate = try a.expression(engine, createBody, .{});
    if (engine.native_module_values.get(key)) |known| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, known));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, key, candidate);
}
fn cachedBody(s: *Scope, owner: c.JSValue, regex: c.JSValue) !c.JSValue {
    const cache = try s.get(owner, "cache");
    const method = try s.get(cache, "get");
    return a.duplicate(s.engine, try s.call(method, cache, &.{regex}));
}
fn flagBody(s: *Scope, owner: c.JSValue, regex: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return a.boolean(s, s.truthy(try s.call(try s.get(owner, name), regex, &.{})));
}
fn appendFlagBody(s: *Scope, flags: c.JSValue, value: []const u8) !c.JSValue {
    return a.duplicate(s.engine, try a.add(s, flags, try s.text(value)));
}
fn privateConstructorBody(s: *Scope) !c.JSValue {
    const holder = try s.own(try realm.acquire(s.engine));
    return a.duplicate(s.engine, try s.get(realm.global(holder), "RegExp"));
}
fn constructBody(s: *Scope, owner: c.JSValue, regex: c.JSValue, constructor: c.JSValue, flags: c.JSValue) !c.JSValue {
    const source_getter = try s.get(owner, "source");
    // The actual intrinsic getter is called on the original regex. The
    // already-resolved private constructor is kept through that argument call.
    const source = try s.call(source_getter, regex, &.{});
    return a.duplicate(s.engine, try s.construct(constructor, &.{source, flags}));
}
fn rememberBody(s: *Scope, owner: c.JSValue, regex: c.JSValue, value: c.JSValue) !c.JSValue {
    const cache = try s.get(owner, "cache");
    const method = try s.get(cache, "set");
    _ = try s.call(method, cache, &.{regex, value});
    return c.pi_js_undefined();
}
fn getBody(s: *Scope, frame: *Frame, owner: c.JSValue, regex: c.JSValue) !c.JSValue {
    try frame.take(.cached, a.expression(s.engine, cachedBody, .{owner, regex}));
    if (s.truthy(frame.get(.cached))) return a.duplicate(s.engine, frame.get(.cached));
    try frame.take(.flags, a.expression(s.engine, emptyBody, .{}));
    inline for (flag_names, flag_chars) |name, value| {
        if (try a.condition(s.engine, flagBody, .{owner, regex, @as([*:0]const u8, name)}))
            try frame.take(.flags, a.expression(s.engine, appendFlagBody, .{frame.get(.flags), @as([]const u8, value)}));
    }
    try frame.take(.constructor, a.expression(s.engine, privateConstructorBody, .{}));
    try frame.take(.result, a.expression(s.engine, constructBody, .{owner, regex, frame.get(.constructor), frame.get(.flags)}));
    _ = try a.expression(s.engine, rememberBody, .{owner, regex, frame.get(.result)});
    return a.duplicate(s.engine, frame.get(.result));
}
fn emptyBody(s: *Scope) !c.JSValue { return a.duplicate(s.engine, try s.text("")); }
pub fn crossRealm(engine: *a.v.em.Engine, owner: c.JSValue, regex: c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = Frame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, getBody(&s, frame, owner, regex));
}
fn replaceBody(s: *Scope, owner: c.JSValue, regex: c.JSValue, input: c.JSValue, replacement: c.JSValue) !c.JSValue {
    const cross = try s.own(try crossRealm(s.engine, owner, regex));
    const method = try s.getKey(cross, try s.get(owner, "replace"));
    // RegExp @@replace coerces input/replacement and invokes the regex's actual
    // private-realm methods. The complete operation is guest-capable.
    return a.duplicate(s.engine, try s.call(method, cross, &.{input, replacement}));
}
pub fn replace(engine: *a.v.em.Engine, owner: c.JSValue, regex: c.JSValue, input: c.JSValue, replacement: c.JSValue) !c.JSValue {
    return a.expression(engine, replaceBody, .{owner, regex, input, replacement});
}
