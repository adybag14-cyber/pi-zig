//! The actual SDK runtime incarnation owns the exposed command Maps.
const sdk = @import("native_sdk.zig");
const em = @import("engine.zig");
pub fn resolve(owner: *sdk.State) !em.c.JSValue {
    const rows = try @import("native_sdk_resource_owners.zig").sessionExtensionRows(owner.engine, owner.data);
    defer owner.engine.freeValue(rows);
    return @import("native_sdk_command_resolution.zig").resolve(owner.engine, rows);
}