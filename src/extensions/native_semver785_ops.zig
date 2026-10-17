//! Local definitions use the same raw current-event boundary as guest calls.
const Scope = @import("native_semver785_scope.zig").Scope;
const c = @import("engine.zig").c;
pub fn put(scope: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    return scope.put(target, name, value);
}