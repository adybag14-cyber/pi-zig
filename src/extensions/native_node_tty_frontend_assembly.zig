//! Concrete frontend-to-TTY composition entry. Called explicitly by the real
//! embedded frontend before guest code; not an Engine/default-worker selector.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
const assembly = @import("native_node_tty_builtin_assembly.zig");
const frontend = @import("native_stdio_frontend.zig");
const mode = @import("native_node_tty_frontend_mode.zig");

/// Owned by the actual frontend's bootstrap frame. Retain until assembly has
/// cached its own JS roots; retaining it longer permits identity-checked retry.
/// A remote worker hydration record cannot construct this capability.
pub const Bootstrap = struct {
    engine: *v.em.Engine,
    actual_frontend: *frontend.Frontend,
    primordials: assembly.Primordials,
    native_mode: ?mode.Snapshot,
    physical_filename: c.JSValue,
    pub fn capture(engine: *v.em.Engine, actual_frontend: *frontend.Frontend, filename: []const u8) !Bootstrap {
        engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
        try h.pending(engine);
        if (!std.fs.path.isAbsolute(filename)) return error.RequiredPhysicalTtyCallerFilename;
        // capture validates active frontend, VM/owner thread, original native
        // mode and current native descriptor mapping where input is a console.
        const snapshot = try mode.capture(engine, actual_frontend);
        const primordials = try assembly.capturePrimordials(engine); errdefer primordials.deinit();
        const physical = try h.success(engine, try engine.checked(c.JS_NewStringLen(engine.context, filename.ptr, filename.len)));
        return .{ .engine = engine, .actual_frontend = actual_frontend, .primordials = primordials, .native_mode = snapshot, .physical_filename = physical };
    }
    pub fn deinit(self: Bootstrap) void { self.primordials.deinit(); self.engine.freeValue(self.physical_filename); }
};

pub fn FrontendAssembly(comptime Socket: type, comptime Hub: type, comptime Scheduler: type, comptime Wake: type, comptime ClosePool: type) type {
    return struct {
        pub const Builtins = assembly.Assembly(Socket, Hub, Scheduler, Wake, ClosePool);
        /// Requires actual classic streams, process/nextTick, canonical Socket,
        /// commonjs node:module and native node:os already installed by their
        /// owners. It neither overwrites these modules nor creates substitutes.
        pub fn install(bootstrap: *const Bootstrap, canonical_socket: *const Socket.Provider, actual_net: c.JSValue, qualification_admission: bool) !Builtins.Exports {
            const engine = bootstrap.engine;
            engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
            try h.pending(engine);
            const actual_frontend = bootstrap.actual_frontend;
            if (actual_frontend.engine != engine or std.Thread.getCurrentId() != actual_frontend.owner or !actual_frontend.active.load(.acquire)) return error.RequiredLiveActualTtyFrontend;
            if (bootstrap.native_mode) |snapshot| try snapshot.validate(engine);
            const process = try h.success(engine, try v.js.global(engine, "process")); defer engine.freeValue(process);
            return Builtins.install(engine, .{ .canonical_socket = canonical_socket, .actual_net = actual_net, .actual_process = process,
                .physical_filename = bootstrap.physical_filename, .primordials = &bootstrap.primordials, .frontend_mode = bootstrap.native_mode,
                .qualification_admission = qualification_admission });
        }
    };
}
