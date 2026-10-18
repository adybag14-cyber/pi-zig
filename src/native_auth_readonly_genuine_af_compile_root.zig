//! Actual owner-required bodies, compile/link only until a genuine SDK graph
//! supplies its authenticated namespace and owned physical fixture directory.
const em = @import("extensions/engine.zig");
const c = em.c;
const controls = @import("native_auth_readonly_genuine_af_controls.zig");
pub const Bindings = struct { auth_exports: c.JSValue, fixture_root: c.JSValue };
const Control = enum { readonly_actual_original_observer_body, readonly_actual_returned_rejected_data_body, readonly_actual_current_native_event_body, readonly_actual_signal_temporary_retirement_body, readonly_actual_direct_factory_pending_body, readonly_actual_auth_carrier_pending_body };
fn run(engine: *em.Engine, bindings: Bindings, comptime control: Control) !void {
    switch (control) {
        .readonly_actual_original_observer_body => engine.freeValue(try controls.observeActual(engine, bindings.auth_exports, bindings.fixture_root)),
        .readonly_actual_returned_rejected_data_body => engine.freeValue(try controls.verifyData(engine, bindings.auth_exports, bindings.fixture_root)),
        .readonly_actual_current_native_event_body => try controls.verifyCurrent(engine, bindings.auth_exports, bindings.fixture_root),
        .readonly_actual_signal_temporary_retirement_body => engine.freeValue(try controls.verifySignalRetirement(engine, bindings.auth_exports, bindings.fixture_root)),
        .readonly_actual_direct_factory_pending_body => try controls.verifyReadonlyFactoryPending(engine, bindings.auth_exports, bindings.fixture_root),
        .readonly_actual_auth_carrier_pending_body => try controls.verifyAuthCarrierPending(engine, bindings.auth_exports, bindings.fixture_root),
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
test "Auth readonly actual-owner compile-only sentinel must never execute" { return error.ActualReadonlyOwnerRequired; }
