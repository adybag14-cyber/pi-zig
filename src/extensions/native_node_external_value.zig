// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Genuine native External values over the VM's private External class.
//! Only the JS value is owned. The original native address is borrowed; there is
//! no BaseObjectPtr, persistent wrapper, native reference, or disposal callback.
const a = @import("native_node_argument_values.zig");
const c = a.c;

/// Returns a local handle owned by s. Duplicate it only when escaping the scope.
pub fn create(s: *a.Scope, pointer: *anyopaque) !c.JSValue {
    const generation = try s.beforeAllocation();
    return s.checkedAllocation(c.JS_PiNewExternal(s.engine.context, pointer), generation);
}
pub fn isExternal(candidate: c.JSValue) bool {
    return c.JS_PiIsExternal(candidate);
}
/// This authenticates the VM class without dereferencing the borrowed address.
/// The consumer must independently know the target's native lifetime.
pub fn value(candidate: c.JSValue) ?*anyopaque {
    return c.JS_PiExternalValue(candidate);
}
