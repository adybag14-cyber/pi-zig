// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! The actual internal/util kEmptyObject: one frozen null-prototype object.
//! Acquire during genuine bootstrap before guest code can replace primordials.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const key = "pi-native:private/internal-util-empty-object";
fn body(s: *a.Scope) !c.JSValue {
    try s.pending();
    if (s.engine.native_module_values.get(key)) |known| return a.duplicate(s.engine, known);
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    const object = try s.get(global, "Object");
    const freeze = try s.get(object, "freeze");
    const value = try s.objectProto(c.pi_js_null());
    const result = try s.call(freeze, c.pi_js_undefined(), &.{value});
    return a.duplicate(s.engine, result);
}
pub fn acquire(engine: *a.v.em.Engine) !c.JSValue {
    var s = a.Scope.init(engine);
    const candidate = try s.finish(body(&s));
    if (engine.native_module_values.get(key)) |known| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, known));
        completion.release(candidate);
        return completion.finishValue();
    }
    return @import("native_node_fs_private_publication.zig").publish(engine, key, candidate);
}
