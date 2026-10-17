//! Exact contained workspace junctions; no retained-source mutation or deletion.
const std = @import("std");
const w = @import("win32.zig");
const files = @import("files.zig");
pub const Plan = struct { root: []const u8, path: []const u8, target: []const u8 };
const mount_point_tag = 0xa0000003;

pub const WriteRoot = struct {
    path: []const u8,
    pub fn reviewed(path: []const u8, protected_stage: []const u8) !WriteRoot {
        const runtime = files.container ++ "\\upstream\\runtime";
        try files.contained(path, runtime);
        if (std.ascii.eqlIgnoreCase(path, protected_stage)) return error.ProtectedStageMutationForbidden;
        const name = path[runtime.len + 1..];
        if (!std.mem.startsWith(u8, name, "19cb534-reproduction-") and
            !std.mem.startsWith(u8, name, "19cb534-metadata-install-")) return error.UnapprovedMutationRoot;
        for (name) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '-') return error.UnapprovedMutationRoot;
        return .{ .path = path };
    }
};
pub fn validatePlan(rows: []const Plan, root: []const u8) !void {
    if (rows.len != 16) return error.Exact16JunctionPlanRequired;
    for (rows, 0..) |row, index| {
        if (!std.mem.eql(u8, row.root, root)) return error.JunctionPlanRootMismatch;
        try files.contained(row.path, root);
        try files.contained(row.target, root);
        if (!std.mem.startsWith(u8, row.path[root.len + 1..], "node_modules\\")) return error.NonWorkspaceJunctionPath;
        if (!std.mem.startsWith(u8, row.target[root.len + 1..], "packages\\")) return error.NonWorkspaceTarget;
        for (rows[0..index]) |prior| if (std.ascii.eqlIgnoreCase(prior.path, row.path)) return error.DuplicateJunctionPlan;
    }
}

pub fn create(allocator: std.mem.Allocator, root: WriteRoot, row: Plan) !void {
    if (!std.mem.eql(u8, root.path, row.root)) return error.JunctionWriteScopeMismatch;
    try files.contained(row.path, root.path);
    try files.contained(row.target, root.path);
    try files.requirePhysicalAncestors(allocator, row.target);
    const target_handle = try files.openLeaf(allocator, row.target, w.generic_read, w.open_existing, w.file_flag_backup_semantics);
    defer _ = w.CloseHandle(target_handle);
    const target_tag = try files.requirePhysical(target_handle);
    if (target_tag.attributes & w.file_attribute_directory == 0) return error.WorkspaceTargetNotDirectory;
    try ensureParents(allocator, root, row.path);
    try files.requirePhysicalAncestors(allocator, row.path);
    const path_utf8 = try std.fmt.allocPrint(allocator, "\\\\?\\{s}", .{row.path});
    defer allocator.free(path_utf8);
    const path = try std.unicode.utf8ToUtf16LeAllocZ(allocator, path_utf8);
    defer allocator.free(path);
    // Existing paths are never removed/replaced. Partial ordinary directory on
    // a later failure remains evidence; do not delete it or retry this attempt.
    if (w.CreateDirectoryW(path.ptr, null) == 0) return error.FreshJunctionLeafRequired;
    const handle = try files.openLeaf(allocator, row.path, w.generic_write, w.open_existing, w.file_flag_backup_semantics);
    var writer_owned = true;
    defer if (writer_owned) { _ = w.CloseHandle(handle); };
    _ = try files.requirePhysical(handle);
    const target = try std.unicode.utf8ToUtf16LeAlloc(allocator, row.target);
    defer allocator.free(target);
    const native_utf8 = try std.fmt.allocPrint(allocator, "\\??\\{s}", .{row.target});
    defer allocator.free(native_utf8);
    const native = try std.unicode.utf8ToUtf16LeAlloc(allocator, native_utf8);
    defer allocator.free(native);
    const native_bytes = native.len * 2;
    const print_bytes = target.len * 2;
    const payload = 8 + native_bytes + 2 + print_bytes + 2;
    if (payload + 8 > 16384 or payload > std.math.maxInt(u16)) return error.JunctionTargetLimit;
    var buffer: [16384]u8 align(8) = @splat(0);
    std.mem.writeInt(u32, buffer[0..4], mount_point_tag, .little);
    std.mem.writeInt(u16, buffer[4..6], @intCast(payload), .little);
    std.mem.writeInt(u16, buffer[8..10], 0, .little);
    std.mem.writeInt(u16, buffer[10..12], @intCast(native_bytes), .little);
    std.mem.writeInt(u16, buffer[12..14], @intCast(native_bytes + 2), .little);
    std.mem.writeInt(u16, buffer[14..16], @intCast(print_bytes), .little);
    @memcpy(buffer[16..][0..native_bytes], std.mem.sliceAsBytes(native));
    @memcpy(buffer[16 + native_bytes + 2..][0..print_bytes], std.mem.sliceAsBytes(target));
    var returned: u32 = 0;
    if (w.DeviceIoControl(handle, 0x000900a4, &buffer, @intCast(payload + 8), null, 0, &returned, null) == 0)
        return error.JunctionWriteFailed;
    // check opens this same reparse leaf with GENERIC_READ/FILE_SHARE_READ.
    // That share mask cannot admit our still-open GENERIC_WRITE handle. Retire
    // the writer first; a failed close remains negative and is never retried.
    writer_owned = false;
    if (w.CloseHandle(handle) == 0) return error.JunctionWriterCloseFailed;
    try check(allocator, row);
}
fn ensureParents(allocator: std.mem.Allocator, root: WriteRoot, leaf: []const u8) !void {
    try files.contained(leaf, root.path);
    var start = root.path.len + 1;
    while (std.mem.indexOfScalarPos(u8, leaf, start, '\\')) |end| {
        const parent = leaf[0..end];
        const utf8 = try std.fmt.allocPrint(allocator, "\\\\?\\{s}", .{parent});
        defer allocator.free(utf8);
        const wide = try std.unicode.utf8ToUtf16LeAllocZ(allocator, utf8);
        defer allocator.free(wide);
        if (w.CreateDirectoryW(wide.ptr, null) == 0 and w.GetLastError() != 183)
            return error.WorkspaceParentCreateFailed;
        const handle = try files.openLeaf(allocator, parent, w.generic_read, w.open_existing, w.file_flag_backup_semantics);
        defer _ = w.CloseHandle(handle);
        if ((try files.requirePhysical(handle)).attributes & w.file_attribute_directory == 0)
            return error.WorkspaceParentNotPhysicalDirectory;
        start = end + 1;
    }
}

pub fn check(allocator: std.mem.Allocator, row: Plan) !void {
    try files.contained(row.path, row.root);
    try files.contained(row.target, row.root);
    try files.requirePhysicalAncestors(allocator, row.path);
    const handle = try files.openLeaf(allocator, row.path, w.generic_read, w.open_existing, w.file_flag_backup_semantics);
    defer _ = w.CloseHandle(handle);
    var tag: w.AttributeTag = undefined;
    if (w.GetFileInformationByHandleEx(handle, 9, &tag, @sizeOf(w.AttributeTag)) == 0 or
        tag.attributes & w.file_attribute_reparse_point == 0 or tag.reparse_tag != mount_point_tag)
        return error.ExpectedWorkspaceJunction;
    var buffer: [16384]u8 align(8) = undefined;
    var returned: u32 = 0;
    if (w.DeviceIoControl(handle, 0x000900a8, null, 0, &buffer, buffer.len, &returned, null) == 0 or
        returned < 16 or returned > buffer.len) return error.JunctionReadFailed;
    if (std.mem.readInt(u32, buffer[0..4], .little) != mount_point_tag) return error.JunctionTagMismatch;
    const payload = std.mem.readInt(u16, buffer[4..6], .little);
    if (@as(usize, payload) + 8 != returned or payload < 8) return error.JunctionPayloadInvalid;
    const sub_offset = std.mem.readInt(u16, buffer[8..10], .little);
    const sub_length = std.mem.readInt(u16, buffer[10..12], .little);
    const print_offset = std.mem.readInt(u16, buffer[12..14], .little);
    const print_length = std.mem.readInt(u16, buffer[14..16], .little);
    const data = buffer[16..returned];
    const sub = try targetSlice(data, sub_offset, sub_length);
    const print = try targetSlice(data, print_offset, print_length);
    const expected_print = try std.unicode.utf8ToUtf16LeAlloc(allocator, row.target);
    defer allocator.free(expected_print);
    const expected_native_utf8 = try std.fmt.allocPrint(allocator, "\\??\\{s}", .{row.target});
    defer allocator.free(expected_native_utf8);
    const expected_sub = try std.unicode.utf8ToUtf16LeAlloc(allocator, expected_native_utf8);
    defer allocator.free(expected_sub);
    if (!samePath(sub, expected_sub) or !samePath(print, expected_print)) return error.JunctionTargetMismatch;
    try files.requirePhysicalAncestors(allocator, row.target);
    const target_handle = try files.openLeaf(allocator, row.target, w.generic_read, w.open_existing, w.file_flag_backup_semantics);
    defer _ = w.CloseHandle(target_handle);
    if ((try files.requirePhysical(target_handle)).attributes & w.file_attribute_directory == 0)
        return error.WorkspaceTargetNotDirectory;
}
fn targetSlice(data: []align(8) const u8, offset: u16, length: u16) ![]const u16 {
    const start: usize = offset;
    const len: usize = length;
    if (start % 2 != 0 or len == 0 or len % 2 != 0 or start > data.len or len > data.len - start)
        return error.JunctionStringBounds;
    const bytes = data[start..][0..len];
    return std.mem.bytesAsSlice(u16, @as([]align(2) const u8, @alignCast(bytes)));
}
fn samePath(a: []const u16, b: []const u16) bool {
    return w.CompareStringOrdinal(a.ptr, @intCast(a.len), b.ptr, @intCast(b.len), 1) == 2;
}

/// Caller checks all exact plan links before resolving. This operation follows
/// only those explicit aliases lexically, never an arbitrary filesystem link.
pub fn resolveCheckedPlan(allocator: std.mem.Allocator, rows: []const Plan,
    root: []const u8, path: []const u8) ![]u8
{
    try validatePlan(rows, root);
    try files.contained(path, root);
    var result = try allocator.dupe(u8, path);
    errdefer allocator.free(result);
    for (0..17) |_| {
        var longest: ?Plan = null;
        for (rows) |row| {
            if (result.len < row.path.len or !std.ascii.eqlIgnoreCase(result[0..row.path.len], row.path) or
                (result.len != row.path.len and result[row.path.len] != '\\')) continue;
            if (longest == null or row.path.len > longest.?.path.len) longest = row;
        }
        const alias = longest orelse return result;
        const next = try std.fmt.allocPrint(allocator, "{s}{s}", .{ alias.target, result[alias.path.len..] });
        allocator.free(result);
        result = next;
        try files.contained(result, root);
    }
    return error.JunctionPlanResolutionCycle;
}
