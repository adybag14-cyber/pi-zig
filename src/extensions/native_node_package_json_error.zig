// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Native ERR_INVALID_PACKAGE_CONFIG construction from node_errors.h. The
//! caller retains the failed PackageConfig until this actual throw completes.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const c = a.c;
const check = @import("native_node_check_failure.zig");

pub const ImportContext = struct {
    specifier: []const u8,
    // This is the owned native output of the original Ada parse/FileURLToPath
    // checks, not a JS URL object or a public fileURLToPath call.
    base_file_path: ?[]const u8,
};
fn cString(value: []const u8) []const u8 {
    return value[0 .. std.mem.indexOfScalar(u8, value, 0) orelse value.len];
}
fn nativeMessage(s: *a.Scope, allocator: std.mem.Allocator, path: []const u8,
    context: ?ImportContext) ![]u8
{
    const result = if (context) |actual|
        if (actual.base_file_path) |base|
            std.fmt.allocPrint(allocator, "Invalid package config {s} while importing \"{s}\" from {s}.",
                .{cString(path), cString(actual.specifier), cString(base)})
        else std.fmt.allocPrint(allocator, "Invalid package config {s}.", .{cString(path)})
    else std.fmt.allocPrint(allocator, "Invalid package config {s}.", .{cString(path)});
    return result catch |err| {
        if (err == error.OutOfMemory) _ = s.engine.throwNativeOutOfMemoryFatal();
        return err;
    };
}
pub fn raise(s: *a.Scope, allocator: std.mem.Allocator, path: []const u8,
    context: ?ImportContext) !c.JSValue
{
    try s.pending();
    const message = try nativeMessage(s, allocator, path, context);
    defer allocator.free(message);
    // The native macro finishes SPrintF, then creates code, message, Error and
    // the literal code key in that order. No global Error property is selected.
    const code = try s.text("ERR_INVALID_PACKAGE_CONFIG");
    const message_value = try s.text(message);
    const generation = try s.beforeAllocation();
    const reason = try s.checkedAllocation(c.JS_NewError(s.engine.context), generation);
    const definition_generation = try s.beforeAllocation();
    const defined = c.JS_DefinePropertyValueStr(s.engine.context, reason, "message",
        a.duplicate(s.engine, message_value), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    _ = try s.checkedAllocation(c.pi_js_undefined(), definition_generation);
    if (defined < 0) return error.ActualPackageErrorMessageDefinitionRequired;
    const key = try s.text("code");
    try s.pending();
    const status = c.JS_SetPropertyValue(s.engine.context, reason,
        a.duplicate(s.engine, key), a.duplicate(s.engine, code), 0);
    if (status < 0) check.maybeCheck(s.engine, null);
    try s.pending();
    // A present false Maybe is not a failure. Throw the same intrinsic Error
    // after the original nonthrowing code Set, including inherited setters.
    _ = c.JS_Throw(s.engine.context, a.duplicate(s.engine, reason));
    try s.pending();
    return error.ActualPackageConfigThrowDidNotEscape;
}
