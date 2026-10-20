// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Node v24.13 src/node_process_events.cc ProcessEmitWarningGeneric and
//! ProcessEmitDeprecationWarning. The native Environment retains the actual
//! process object; emitWarning is looked up on that object for every call.
//! This module does not install a process object or an emitWarning substitute.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const Environment = @import("native_node_callback_scope.zig").Environment;

pub const Input = struct {
    warning: []const u8,
    warning_type: []const u8 = "",
    code: []const u8 = "",
};

fn genericBody(s: *Scope, env: *Environment, input: Input) !c.JSValue {
    // Source Local<Object> retains the selected process before the live Get.
    // A getter may retire the Environment root while this call still owns it.
    const process = try s.own(a.duplicate(s.engine, env.process_object orelse
        return error.ActualNodeProcessObjectRequired));
    const method = try s.get(process, "emitWarning");
    if (!c.JS_IsFunction(s.engine.context, method)) return a.boolean(s, false);

    // Source constructs warning first; code is considered only inside the
    // nonempty type branch. These inputs are explicit-length UTF-8 strings.
    var args: [3]c.JSValue = undefined;
    var argc: usize = 1;
    args[0] = try s.text(input.warning);
    if (input.warning_type.len != 0) {
        args[1] = try s.text(input.warning_type);
        argc = 2;
        if (input.code.len != 0) {
            args[2] = try s.text(input.code);
            argc = 3;
        }
    }
    // The native Source calls Function::Call directly. Its discarded result
    // remains an ordinary value even if it happens to be an Error instance.
    // No InternalCallbackScope, MakeCallback, or checkpoint is introduced.
    _ = try s.call(method, process, args[0..argc]);
    return a.boolean(s, true);
}

pub fn emitGeneric(env: *Environment, input: Input) !bool {
    // Node's early return precedes HandleScope and process property lookup.
    // In particular, a disabled Environment does not enter the guest at all.
    if (!env.canCallIntoJs()) return false;
    const engine = try env.requireEngine();
    return a.condition(engine, genericBody, .{ env, input });
}

/// The ProcessEmitWarning template's boundary AFTER actual SPrintF. Its
/// warning.c_str() conversion intentionally truncates at the first NUL.
/// The caller owns formatting and the resulting native string allocation.
pub fn emitFormattedWarning(env: *Environment, formatted_warning: []const u8) !bool {
    const end = std.mem.indexOfScalar(u8, formatted_warning, 0) orelse formatted_warning.len;
    return emitGeneric(env, .{ .warning = formatted_warning[0..end] });
}

pub fn emitDeprecationWarning(env: *Environment, warning: []const u8,
    deprecation_code: []const u8) !bool
{
    // std::string -> std::string_view preserves the complete warning length.
    return emitGeneric(env, .{
        .warning = warning,
        .warning_type = "DeprecationWarning",
        .code = deprecation_code,
    });
}

/// Exact selected SPrintF("%d", native int) site in FileHandle::Close.
/// ToStringHelper::Convert(int) is signed decimal std::to_string, not guest
/// coercion. The caller's actual charged allocator owns the returned bytes.
pub fn formatFileHandleGcWarning(allocator: std.mem.Allocator, fd: i32) ![]u8 {
    return std.fmt.allocPrint(allocator,
        "Closing file descriptor {d} on garbage collection", .{fd});
}
