//! Node v24.13 src/api/exceptions.cc UVException. Ordinary libuv status
//! remains an ordinary Error value; this factory never throws that value.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const c = em.c;
const Scope = @import("native_node_operation_scope.zig").Scope;

// The one admitted libuv graph supplies these actual mappings on each host.
extern fn uv_err_name(code: c_int) [*:0]const u8;
extern fn uv_strerror(code: c_int) [*:0]const u8;

pub const Input = struct {
    code: i32,
    syscall: []const u8,
    message: ?[]const u8 = null,
    path: ?[]const u8 = null,
    dest: ?[]const u8 = null,
};

pub fn create(engine: *em.Engine, input: Input) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(createBody(&s, input));
}

fn cString(bytes: []const u8) []const u8 {
    return bytes[0 .. std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len];
}
fn oneByteString(s: *Scope, incoming: []const u8) !c.JSValue {
    try s.pending();
    const bytes = cString(incoming);
    const units = try s.engine.gpa.alloc(u16, bytes.len);
    defer s.engine.gpa.free(units);
    for (bytes, 0..) |byte, index| units[index] = byte;
    const generation = try s.beforeAllocation();
    return s.checkedAllocation(c.JS_NewStringUTF16(s.engine.context, units.ptr, units.len), generation);
}
fn stringFromPath(s: *Scope, incoming: []const u8) !c.JSValue {
    const path = cString(incoming);
    if (builtin.os.tag == .windows) {
        if (std.mem.startsWith(u8, path, "\\\\?\\UNC\\")) {
            const prefix = try s.text("\\\\");
            const rest = try s.text(path[8..]);
            return s.binary(0, prefix, rest);
        }
        if (std.mem.startsWith(u8, path, "\\\\?\\")) return s.text(path[4..]);
    }
    return s.text(path);
}

fn appendLiteral(s: *Scope, left: c.JSValue, text: []const u8) !c.JSValue {
    return s.binary(0, left, try s.text(text));
}

fn createBody(s: *Scope, input: Input) !c.JSValue {
    try s.pending();
    const description = if (input.message) |given|
        if (cString(given).len != 0) cString(given) else std.mem.span(uv_strerror(input.code))
    else std.mem.span(uv_strerror(input.code));
    const code_value = try oneByteString(s, std.mem.span(uv_err_name(input.code)));
    const syscall_value = try oneByteString(s, input.syscall);
    var path_value = c.pi_js_undefined();
    var dest_value = c.pi_js_undefined();
    var message_value = try appendLiteral(s, code_value, ": ");
    message_value = try s.binary(0, message_value, try oneByteString(s, description));
    message_value = try appendLiteral(s, message_value, ", ");
    message_value = try s.binary(0, message_value, syscall_value);

    if (input.path) |path| {
        path_value = try stringFromPath(s, path);
        message_value = try appendLiteral(s, message_value, " '");
        message_value = try s.binary(0, message_value, path_value);
        message_value = try appendLiteral(s, message_value, "'");
    }
    if (input.dest) |dest| {
        dest_value = try stringFromPath(s, dest);
        message_value = try appendLiteral(s, message_value, " -> '");
        message_value = try s.binary(0, message_value, dest_value);
        message_value = try appendLiteral(s, message_value, "'");
    }

    // Exception::Error constructs the intrinsic Error with an own, writable
    // and configurable non-enumerable message. It does not select global Error.
    const generation = try s.beforeAllocation();
    const reason = try s.checkedAllocation(c.JS_NewError(s.engine.context), generation);
    const definition_generation = try s.beforeAllocation();
    const status = c.JS_DefinePropertyValueStr(s.engine.context, reason, "message",
        c.JS_DupValue(s.engine.context, message_value),
        c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    _ = try s.checkedAllocation(c.pi_js_undefined(), definition_generation);
    if (status < 0) return error.MissingActualUvErrorMessageDefinition;

    // Actual Object::Set, including inherited setters, in the original order.
    try s.put(reason, "errno", c.JS_NewInt32(s.engine.context, input.code));
    try s.put(reason, "code", code_value);
    try s.put(reason, "syscall", syscall_value);
    if (input.path != null) try s.put(reason, "path", path_value);
    if (input.dest != null) try s.put(reason, "dest", dest_value);
    return c.JS_DupValue(s.engine.context, reason);
}
