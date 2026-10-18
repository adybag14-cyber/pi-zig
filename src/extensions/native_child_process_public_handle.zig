//! Canonical platform public Process entitlement. Ref types are the ACTUAL
//! selected platform types; no numeric fd/HANDLE placeholder crosses platforms.
const platform = if (@import("builtin").os.tag == .linux)
    @import("native_child_process_public_handle_linux.zig")
else
    @import("native_child_process_public_handle_windows.zig");
pub const Ticket = platform.Ticket;
pub const reserve = platform.reserve;
pub const bind = platform.bind;
pub const close = platform.close;
