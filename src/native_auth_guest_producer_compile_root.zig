//! Compile/link actual owner-required bodies only. No runtime pass is claimed.
const em = @import("extensions/engine.zig");
const c = em.c;
const controls = @import("native_auth_guest_producer_controls.zig");
const Control = enum { auth_getter_data, auth_getter_fatal, auth_call_data, auth_call_fatal, readonly_getter_data, readonly_getter_fatal, reload_getter_data, reload_getter_fatal };
fn run(engine: *em.Engine, inputs: controls.Inputs, comptime control: Control) !void {
    const route: controls.Route = switch (control) {
        .auth_getter_data, .auth_getter_fatal => .auth_getter,
        .auth_call_data, .auth_call_fatal => .auth_call,
        .readonly_getter_data, .readonly_getter_fatal => .readonly_getter,
        .reload_getter_data, .reload_getter_fatal => .reload_getter,
    };
    const fatal = switch (control) { .auth_getter_fatal, .auth_call_fatal, .readonly_getter_fatal, .reload_getter_fatal => true, else => false };
    try controls.verify(engine, inputs, route, fatal);
}
comptime {
    for (@typeInfo(Control).@"enum".fields) |field| {
        const Adapter = struct {
            fn call(raw_engine: *anyopaque, raw_inputs: *const anyopaque) callconv(.c) c_int {
                const engine: *em.Engine = @ptrCast(@alignCast(raw_engine));
                const inputs: *const controls.Inputs = @ptrCast(@alignCast(raw_inputs));
                @call(.never_inline, run, .{ engine, inputs.*, @as(Control, @enumFromInt(field.value)) }) catch return 1;
                return 0;
            }
        };
        @export(&Adapter.call, .{ .name = field.name });
    }
}
test "Auth guest-producer actual-owner compile-only sentinel must never execute" { return error.ActualAuthAndResourceOwnersRequired; }
