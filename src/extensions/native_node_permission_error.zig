// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Selected native permission::CreateAccessDeniedError/ThrowAccessDenied for
//! FileSystemRead/Write. Uses the actual intrinsic Error and native Environment keys.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;

/// The real native embedding creates these two original Environment strings
/// before exposing callbacks, and keeps them rooted for its Environment life.
/// create() returns Scope-owned values; the assembler retains them in its own
/// actual owner. They are primitive VM strings, not public properties/getters.
pub const Keys = struct {
    engine: *a.v.em.Engine,
    permission: c.JSValue,
    resource: c.JSValue,

    pub fn create(s: *a.Scope) !Keys {
        return .{ .engine = s.engine, .permission = try s.text("permission"),
            .resource = try s.text("resource") };
    }
    pub fn retain(self: Keys, s: *a.Scope) !Keys {
        try s.pending();
        if (self.engine != s.engine or !c.JS_IsString(self.permission) or
            !c.JS_IsString(self.resource))
            return error.ActualNativePermissionKeysRequired;
        _ = try s.own(a.duplicate(s.engine, self.permission));
        _ = try s.own(a.duplicate(s.engine, self.resource));
        return self;
    }
};

/// A false present Maybe is accepted by the original IsNothing() tests.
/// A thrown permission/resource setter supersedes the access-denied Error.
fn setMaybe(s: *a.Scope, target: c.JSValue, key: c.JSValue,
    value: c.JSValue) !void
{
    try s.pending();
    const status = c.JS_SetPropertyValue(s.engine.context, target,
        a.duplicate(s.engine, key), a.duplicate(s.engine, value), 0);
    try s.pending();
    if (status < 0) return error.ActualPermissionSetExceptionRequired;
}

pub fn throwFileSystemRead(s: *a.Scope, allocator: std.mem.Allocator,
    keys: Keys, resource: []const u8) !c.JSValue
{
    return throwFileSystem(s, allocator, keys, resource, .read);
}
pub fn throwFileSystemWrite(s: *a.Scope, allocator: std.mem.Allocator,
    keys: Keys, resource: []const u8) !c.JSValue
{
    return throwFileSystem(s, allocator, keys, resource, .write);
}
const FileSystemScope = enum { read, write };
fn throwFileSystem(s: *a.Scope, allocator: std.mem.Allocator,
    keys: Keys, resource: []const u8, comptime scope: FileSystemScope) !c.JSValue
{
    try s.pending();
    // Native GetErrorFlagSuggestion for this scope then SPrintF precede every
    // VM allocation. The full resource is a separate native string_view below.
    const message = std.fmt.allocPrint(allocator,
        "Access to this API has been restricted. {s}",
        .{if (scope == .read) "Use --allow-fs-read to manage permissions."
          else "Use --allow-fs-write to manage permissions."}) catch |err| {
        if (err == error.OutOfMemory) check.heapOutOfMemory(s.engine, null);
        return err;
    };
    defer allocator.free(message);
    // Original ERR_ACCESS_DENIED macro: code, message, intrinsic Error, code
    // key, ordinary code Set.Check(). Public Error is never selected.
    const code = try s.text("ERR_ACCESS_DENIED");
    const message_value = try s.text(message);
    const generation = try s.beforeAllocation();
    const reason = try s.checkedAllocation(c.JS_NewError(s.engine.context), generation);
    const definition_generation = try s.beforeAllocation();
    const defined = c.JS_DefinePropertyValueStr(s.engine.context, reason, "message",
        a.duplicate(s.engine, message_value), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    _ = try s.checkedAllocation(c.pi_js_undefined(), definition_generation);
    if (defined < 0) return error.ActualPermissionErrorMessageDefinitionRequired;
    const code_key = try s.text("code");
    try s.pending();
    const code_status = c.JS_SetPropertyValue(s.engine.context, reason,
        a.duplicate(s.engine, code_key), a.duplicate(s.engine, code), 0);
    if (code_status < 0) check.maybeCheck(s.engine, null);
    try s.pending();

    // Both native ToV8Value conversions complete before either ordinary Set.
    // Full-length resource bytes retain embedded NUL; no c_str truncation.
    const permission_value = try s.text(if (scope == .read) "FileSystemRead" else "FileSystemWrite");
    const resource_value = try s.text(resource);
    try setMaybe(s, reason, keys.permission, permission_value);
    try setMaybe(s, reason, keys.resource, resource_value);
    // ThrowAccessDenied throws only after CreateAccessDeniedError succeeded.
    _ = c.JS_Throw(s.engine.context, a.duplicate(s.engine, reason));
    try s.pending();
    return error.ActualAccessDeniedThrowDidNotEscape;
}
