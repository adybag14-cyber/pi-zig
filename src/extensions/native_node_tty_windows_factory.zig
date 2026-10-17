//! Concrete actual Windows node:tty assembly. One canonical Socket registry,
//! actual native console/owner/TTY binding and real public class bodies.
//! Source-only/unselected; Root supplies the reviewed canonical module types.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
const tty = @import("native_node_tty.zig");
const colors = @import("native_node_tty_colors.zig");
const errors = @import("native_node_tty_errors.zig");
pub fn Factory(comptime Socket: type, comptime Hub: type, comptime Scheduler: type, comptime Wake: type, comptime ClosePool: type) type {
    return struct {
        const Native = @import("native_node_tty_windows_owner.zig").Owner(Socket, Hub, Scheduler, Wake, ClosePool);
        const Binding = @import("native_node_tty_binding.zig").Binding(Socket, Native);
        pub const Inputs = struct {
            canonical_socket: *const Socket.Provider,
            actual_net: c.JSValue,
            actual_process: c.JSValue,
            actual_require: c.JSValue,
            errors: errors.Exports,
            primordials: colors.Primordials,
            frontend_mode: ?@import("native_node_tty_frontend_mode.zig").Snapshot = null,
        };
        /// Return the genuine Source carrier {isatty,ReadStream,WriteStream}.
        /// Root's actual valueNamespace/defaultExports must wrap THIS carrier
        /// once, preserving the same constructor objects across import forms.
        /// Nothing registers or selects a partial public namespace here.
        pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
            engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
            try h.pending(engine);
            if (@import("builtin").os.tag != .windows) return error.RequiredActualPlatformTtyOwner;
            var s: v.Scope = .{ .engine = engine }; defer s.deinit();
            const native = try Native.Provider.create(engine, inputs.canonical_socket, .{ .errno_exception = inputs.errors.errno_exception, .process = inputs.actual_process, .frontend_mode = inputs.frontend_mode });
            defer native.release();
            var published = false; defer if (!published) native.rollbackUnpublished();
            var binding = try Binding.prepare(engine, &native.socket, native); defer binding.deinit();
            const validator = try s.own(try colors.createValidator(engine, inputs.primordials.number_is_integer, inputs.errors.invalid_arg_type, inputs.errors.out_of_range));
            const actual_colors = try colors.create(engine, .{ .require = inputs.actual_require, .validate_integer = validator,
                .string_split = inputs.primordials.string_split, .string_lower = inputs.primordials.string_lower,
                .regexp_exec = inputs.primordials.regexp_exec, .regexp_constructor = inputs.primordials.regexp_constructor,
                .has_own = inputs.primordials.has_own });
            defer actual_colors.deinit(engine);
            const carrier = try s.own(try tty.create(engine, .{ .net = inputs.actual_net,
                .tty_constructor = binding.exports.tty, .is_tty = binding.exports.is_tty,
                .invalid_fd = inputs.errors.invalid_fd, .tty_init_failed = inputs.errors.tty_init_failed,
                .errno_exception = inputs.errors.errno_exception, .require = inputs.actual_require,
                .number_is_integer = inputs.primordials.number_is_integer, .colors = actual_colors }));
            // Native adopter publication is LAST and has no later allocation,
            // guest callback, optional missing-binding fallback or fresh tick.
            try binding.commit(); published = true;
            return c.JS_DupValue(engine.context, carrier);
        }
    };
}
