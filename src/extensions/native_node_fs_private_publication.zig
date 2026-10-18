//! Publication of a completed private filesystem owner. No cache entry is
//! visible until all construction temporaries have retired through Node Scope.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = @import("native_node_operation_scope.zig").Scope;
pub fn publish(engine: *v.em.Engine, comptime key: []const u8, value: c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    var incoming = [_]c.JSValue{value};
    var failure: ?anyerror = null;
    reserve(&s) catch |err| { failure = err; };
    // Trusted map-allocation failure is recorded before incoming can retire.
    try s.boundary.finishMany(failure, &s.values, &incoming);
    // No guest call, allocation or owner retirement after the final completion.
    engine.native_module_values.putAssumeCapacity(key, c.JS_DupValue(engine.context, incoming[0]));
    return incoming[0];
}
fn reserve(s: *Scope) !void {
    try s.pending();
    try s.engine.native_module_values.ensureUnusedCapacity(s.engine.gpa, 1);
    try s.pending();
}
