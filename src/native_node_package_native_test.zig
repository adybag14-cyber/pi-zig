//! Native package field/path controls tied to retained Node24 and MSVC source.
//! Authored declarations only until Root grants an installed-artifact run.
const std = @import("std");
const paths = @import("extensions/native_node_package_path.zig");
const fields = @import("extensions/native_node_package_json_fields.zig");
const gpa = std.testing.allocator;
fn namespace(input: []const u8, directory: []const u8, drive: ?[]const u8, expected: []const u8) !void {
    const actual = try paths.namespacedWithDirectory(gpa, input, directory, drive, .win32);
    defer gpa.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}
test "native package path preserves native absolute and drive-relative resolution" {
    try namespace("C:/pkg/./nested/../file.js", "D:\\cwd", null, "\\\\?\\C:\\pkg\\file.js");
    try namespace("pkg/file.js", "C:\\cwd", null, "\\\\?\\C:\\cwd\\pkg\\file.js");
    try namespace("D:pkg/file.js", "C:\\cwd", "D:\\saved", "\\\\?\\D:\\saved\\pkg\\file.js");
    // Node C++ path.cc checks '/' at byte 2 in its final drive fallback.
    try namespace("D:pkg", "C:/cwd", null, "\\\\?\\D:\\pkg");
    try namespace("D:pkg", "C:\\cwd", null, "D:pkg");
}
test "native package path canonicalizes forward and mixed namespace prefixes" {
    const cases = [_][]const u8{ "//?/C:/pkg/file.js", "/\\?/C:/pkg/file.js", "\\/?\\C:/pkg/file.js", "\\\\?\\C:\\pkg\\file.js" };
    for (cases) |input| try namespace(input, "D:\\cwd", null, "\\\\?\\C:\\pkg\\file.js");
    try namespace("//./pipe/pi", "D:\\cwd", null, "\\\\.\\pipe\\pi");
    try namespace("/\\./pipe/pi", "D:\\cwd", null, "\\\\.\\pipe\\pi");
}
test "native package path normalizes UNC without public reserved-device rewriting" {
    try namespace("//server//share/pkg/../file.js", "C:\\cwd", null, "\\\\?\\UNC\\server\\share\\file.js");
    try namespace("CON:/pkg", "C:\\cwd", null, "\\\\?\\C:\\cwd\\CON:\\pkg");
    try namespace("", "C:\\cwd", null, "");
}
test "native package path preserves POSIX input spelling before filesystem traversal" {
    const actual = try paths.namespacedWithDirectory(gpa, "/pkg//nested/../file.js", "/cwd", null, .posix);
    defer gpa.free(actual);
    try std.testing.expectEqualStrings("/pkg//nested/../file.js", actual);
    try std.testing.expectEqualStrings("/pkg", paths.parent("/pkg/file.js", .posix));
    try std.testing.expectEqualStrings("/pkg", paths.parent("/pkg/", .posix));
    try std.testing.expectEqualStrings("/", paths.parent("/", .posix));
    try std.testing.expectEqualStrings("", paths.filename("/pkg/", .posix));
}
test "native package path retains native namespace and UNC parent components" {
    try std.testing.expectEqualStrings("\\\\?\\C:\\pkg", paths.parent("\\\\?\\C:\\pkg\\file.js", .win32));
    try std.testing.expectEqualStrings("\\\\?\\C:", paths.parent("\\\\?\\C:\\pkg", .win32));
    try std.testing.expectEqualStrings("\\\\?\\", paths.parent("\\\\?\\C:", .win32));
    try std.testing.expectEqualStrings("\\\\?\\", paths.parent("\\\\?\\", .win32));
    try std.testing.expectEqualStrings("\\\\.\\pipe", paths.parent("\\\\.\\pipe\\pi", .win32));
    try std.testing.expectEqualStrings("\\??\\C:\\pkg", paths.parent("\\??\\C:\\pkg\\file.js", .win32));
    try std.testing.expectEqualStrings("\\\\server\\share", paths.parent("\\\\server\\share\\file.js", .win32));
    try std.testing.expectEqualStrings("node_modules", paths.filename("\\\\?\\C:\\pkg\\node_modules", .win32));
}
test "native package path generic permission spelling and append keep component boundaries" {
    const windows = try paths.generic(gpa, "\\\\?\\C:\\pkg\\\\nested", .win32);
    defer gpa.free(windows);
    try std.testing.expectEqualStrings("//?/C:/pkg//nested", windows);
    const posix = try paths.generic(gpa, "/pkg//nested///", .posix);
    defer gpa.free(posix);
    try std.testing.expectEqualStrings("/pkg/nested/", posix);
    const appended = try paths.appendPackage(gpa, "\\\\?\\C:\\pkg", .win32);
    defer gpa.free(appended);
    try std.testing.expectEqualStrings("\\\\?\\C:\\pkg\\package.json", appended);
}
test "native package fields retain ordered duplicate checks and recognized type" {
    var parsed = try fields.parse(gpa, "{\"name\":\"first\",\"name\":\"last\",\"main\":\"a.js\",\"main\":false,\"type\":\"module\",\"type\":\"future\"}");
    defer parsed.deinit(gpa);
    try std.testing.expectEqualStrings("last", parsed.name.?);
    try std.testing.expectEqualStrings("a.js", parsed.main.?);
    try std.testing.expectEqual(.module, parsed.kind);
    try std.testing.expectError(error.InvalidNativePackageJson, fields.parse(gpa, "{\"name\":false,\"name\":\"valid later\"}"));
    try std.testing.expectError(error.InvalidNativePackageJson, fields.parse(gpa, "{\"type\":false,\"type\":\"module\"}"));
}
test "native package fields preserve raw nested imports and exports independently" {
    var parsed = try fields.parse(gpa, "{\"imports\": { \"#x\" : [\"./x.js\", null] }, \"exports\": [ \"./first.js\", {\"default\":\"./next.js\"} ]}");
    defer parsed.deinit(gpa);
    try std.testing.expectEqualStrings("{ \"#x\" : [\"./x.js\", null] }", parsed.imports.?);
    try std.testing.expectEqualStrings("[ \"./first.js\", {\"default\":\"./next.js\"} ]", parsed.exports.?);
    var replaced = try fields.parse(gpa, "{\"exports\":\"./one.js\",\"exports\":null,\"imports\":\"./two.js\",\"imports\":42}");
    defer replaced.deinit(gpa);
    try std.testing.expectEqualStrings("./one.js", replaced.exports.?);
    try std.testing.expectEqualStrings("./two.js", replaced.imports.?);
}
test "native package fields skip BOM and compare raw keys without unescaping" {
    var parsed = try fields.parse(gpa, "\xef\xbb\xbf{\"na\\u006de\":\"ignored\",\"name\":\"café\",\"main\":\"a\\u002ejs\"}");
    defer parsed.deinit(gpa);
    try std.testing.expectEqualStrings("café", parsed.name.?);
    try std.testing.expectEqualStrings("a.js", parsed.main.?);
    var escaped = try fields.parse(gpa, "{\"\\u0074ype\":\"module\"}");
    defer escaped.deinit(gpa);
    try std.testing.expectEqual(.none, escaped.kind);
}
test "native package fields reject malformed JSON and invalid UTF8" {
    const invalid = [_][]const u8{ "[]", "{\"name\":\"x\",}", "{\"x\":01}", "{\"x\":1e}", "{\"x\":\"\\q\"}", "{\"x\":[0,]}", "{} trailing", "{\"name\":\"\xff\"}" };
    for (invalid) |input| try std.testing.expectError(error.InvalidNativePackageJson, fields.parse(gpa, input));
}
fn allocatingFields(allocator: std.mem.Allocator) !void {
    var parsed = try fields.parse(allocator, "{\"name\":\"old\",\"name\":\"new\",\"main\":\"a.js\",\"type\":\"module\",\"exports\":{\".\":\"./a.js\"},\"imports\":[\"./b.js\"]}");
    defer parsed.deinit(allocator);
}
fn allocatingPath(allocator: std.mem.Allocator) !void {
    const value = try paths.namespacedWithDirectory(allocator, "//?/C:/pkg/nested/../file.js", "D:\\cwd", null, .win32);
    defer allocator.free(value);
}
test "native package allocation failures preserve typed OOM and release all parsed ownership" {
    try std.testing.checkAllAllocationFailures(gpa, allocatingFields, .{});
    try std.testing.checkAllAllocationFailures(gpa, allocatingPath, .{});
}
