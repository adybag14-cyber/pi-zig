//! Actual canonical modules for the generic TTY assembler. This selects no
//! public builtin and creates no process/console/descriptor on its own.
pub const Socket = @import("native_node_net_socket.zig");
pub const Hub = @import("native_env_io.zig");
pub const Scheduler = @import("native_owner_completion.zig");
pub const Wake = @import("native_owner_wake.zig");
pub const ClosePool = @import("native_node_fs_windows_close_worker.zig").Pool(Wake);
pub const canonical = @import("native_node_net_socket_provider.zig");
