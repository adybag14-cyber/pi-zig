//! Real actual-owner integration bodies retained for compile/link only.
//! There is deliberately no fabricated Completed graph or runnable substitute.
const em = @import("extensions/engine.zig");
const c = em.c;
const integration = @import("native_auth_resource_genuine_af_controls.zig");
const cleanup = @import("native_auth_resource_cleanup_controls.zig");
/// Supplied only by the genuine SDK owner. Auth additionally authenticates its
/// private installed module; ResourceLoader must be that owner's exact class.
pub const Bindings = struct { auth_exports: c.JSValue, resource_constructor: c.JSValue };
const Control = enum {
    auth_resource_actual_observer_body,
    auth_resource_actual_rejected_data_body,
    auth_resource_actual_current_event_body,
    auth_read_owned_ordinary_cleanup_body,
    auth_read_owned_new_fatal_cleanup_body,
    auth_read_owned_rejected_diagnostic_body,
    auth_sync_reload_owned_caught_reason_raw_pending_body,
    resource_reload_owned_ordinary_cleanup_body,
    resource_reload_owned_new_fatal_cleanup_body,
    resource_reload_owned_rejected_diagnostic_body,
};
fn run(engine: *em.Engine, bindings: Bindings, comptime control: Control) !void {
    switch (control) {
        .auth_resource_actual_observer_body => engine.freeValue(try integration.observeActualBootstrapBindings(engine, bindings.auth_exports, bindings.resource_constructor)),
        .auth_resource_actual_rejected_data_body => engine.freeValue(try integration.verifyActualRejectedData(engine, bindings.auth_exports, bindings.resource_constructor)),
        .auth_resource_actual_current_event_body => try integration.verifyActualCurrentEvent(engine, bindings.auth_exports, bindings.resource_constructor),
        .auth_read_owned_ordinary_cleanup_body => try cleanup.verifyActualReadRetirement(engine, bindings.auth_exports, false),
        .auth_read_owned_new_fatal_cleanup_body => try cleanup.verifyActualReadRetirement(engine, bindings.auth_exports, true),
        .auth_read_owned_rejected_diagnostic_body => try cleanup.verifyActualReadCleanupDiagnostic(engine, bindings.auth_exports),
        .auth_sync_reload_owned_caught_reason_raw_pending_body => try cleanup.verifyActualSyncReloadCaughtReason(engine, bindings.auth_exports),
        .resource_reload_owned_ordinary_cleanup_body => try cleanup.verifyActualReloadRetirement(engine, bindings.resource_constructor, false),
        .resource_reload_owned_new_fatal_cleanup_body => try cleanup.verifyActualReloadRetirement(engine, bindings.resource_constructor, true),
        .resource_reload_owned_rejected_diagnostic_body => try cleanup.verifyActualReloadCleanupDiagnostic(engine, bindings.resource_constructor),
    }
}
comptime {
    for (@typeInfo(Control).@"enum".fields) |field| {
        const Adapter = struct {
            fn call(raw_engine: *anyopaque, raw_bindings: *const anyopaque) callconv(.c) c_int {
                const engine: *em.Engine = @ptrCast(@alignCast(raw_engine));
                const bindings: *const Bindings = @ptrCast(@alignCast(raw_bindings));
                @call(.never_inline, run, .{ engine, bindings.*, @as(Control, @enumFromInt(field.value)) }) catch return 1;
                return 0;
            }
        };
        @export(&Adapter.call, .{ .name = field.name });
    }
}
test "Auth resource actual-owner compile-only sentinel must never execute" {
    return error.ActualOwnerIntegrationIsCompileOnly;
}
