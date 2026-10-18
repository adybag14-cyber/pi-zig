//! One canonical platform wake namespace. Ref/Sink are the selected platform's
//! actual types; generic close/flush pools and child readiness share those types
//! and the same sixteen native lifetime slots.
const builtin = @import("builtin");
const platform = switch (builtin.os.tag) {
    .windows => @import("native_owner_wake_windows.zig"),
    .linux => @import("native_owner_wake_linux.zig"),
    else => @compileError("native owner wake requires Windows or Linux"),
};
pub const Ref = platform.Ref;
pub const Sink = platform.Sink;
pub const create = platform.create;
pub const retain = platform.retain;
pub const notify = platform.notify;
pub const bindHost = platform.bindHost;
pub const detachHost = platform.detachHost;
pub const detach = platform.detach;
pub const release = platform.release;
