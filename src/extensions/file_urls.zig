//! File URL conversion shared by native imports and URL host bindings.
const std = @import("std");

pub fn decodePath(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    return decodePathMode(gpa, input, true);
}

fn decodePathMode(gpa: std.mem.Allocator, input: []const u8, reject_backslash: bool) ![]u8 {
    const output = try gpa.alloc(u8, input.len);
    errdefer gpa.free(output);
    var read: usize = 0;
    var written: usize = 0;
    while (read < input.len) : (read += 1) {
        const byte = input[read];
        if (byte == '%') {
            if (input.len - read < 3) return error.InvalidFileUrlEncoding;
            const high = std.fmt.charToDigit(input[read + 1], 16) catch return error.InvalidFileUrlEncoding;
            const low = std.fmt.charToDigit(input[read + 2], 16) catch return error.InvalidFileUrlEncoding;
            const decoded = (high << 4) | low;
            if (decoded == '/' or (reject_backslash and decoded == '\\') or decoded == 0) return error.InvalidFileUrlSeparator;
            output[written] = decoded;
            read += 2;
        } else {
            if (byte == 0) return error.InvalidFileUrlEncoding;
            output[written] = byte;
        }
        written += 1;
    }
    if (!std.unicode.utf8ValidateSlice(output[0..written])) return error.InvalidFileUrlEncoding;
    return gpa.realloc(output, written);
}

pub fn toPath(gpa: std.mem.Allocator, input: []const u8, windows: bool) ![]u8 {
    const uri = std.Uri.parse(input) catch return error.InvalidFileUrl;
    if (!std.ascii.eqlIgnoreCase(uri.scheme, "file") or uri.user != null or uri.password != null or uri.port != null) return error.InvalidFileUrl;
    const host = if (uri.host) |value| switch (value) {
        .raw, .percent_encoded => |bytes| bytes,
    } else "";
    const encoded = switch (uri.path) {
        .raw, .percent_encoded => |bytes| bytes,
    };
    if (encoded.len == 0 or encoded[0] != '/') return error.InvalidFileUrl;
    const path = try decodePathMode(gpa, encoded, windows);
    defer gpa.free(path);
    if (!windows) {
        if (host.len > 0 and !std.ascii.eqlIgnoreCase(host, "localhost")) return error.InvalidFileUrlHost;
        return gpa.dupe(u8, path);
    }
    const remote = host.len > 0 and !std.ascii.eqlIgnoreCase(host, "localhost");
    if (remote and std.mem.indexOfAny(u8, host, "%/:\\?#\x00") != null) return error.InvalidFileUrlHost;
    const output = if (remote)
        try std.fmt.allocPrint(gpa, "\\\\{s}{s}", .{ host, path })
    else valid_drive: {
        if (path.len < 3 or !std.ascii.isAlphabetic(path[1]) or path[2] != ':' or (path.len > 3 and path[3] != '/')) return error.InvalidFileUrlDrive;
        break :valid_drive try gpa.dupe(u8, path[1..]);
    };
    for (output) |*byte| if (byte.* == '/') {
        byte.* = '\\';
    };
    return output;
}

pub fn fromPath(gpa: std.mem.Allocator, input: []const u8, windows: bool) ![]u8 {
    if (std.mem.indexOfScalar(u8, input, 0) != null or !std.unicode.utf8ValidateSlice(input)) return error.InvalidFileUrlPath;
    var writer: std.Io.Writer.Allocating = .init(gpa);
    defer writer.deinit();
    try writer.writer.writeAll("file://");
    var path = input;
    if (windows) {
        if (input.len >= 2 and std.fs.path.PathType.windows.isSep(u8, input[0]) and std.fs.path.PathType.windows.isSep(u8, input[1])) {
            const end = std.mem.indexOfAnyPos(u8, input, 2, "/\\") orelse return error.InvalidFileUrlHost;
            const host = input[2..end];
            if (host.len == 0 or std.mem.indexOfAny(u8, host, "%/:?#\x00") != null) return error.InvalidFileUrlHost;
            try writer.writer.writeAll(host);
            path = input[end..];
        } else {
            if (input.len < 3 or !std.ascii.isAlphabetic(input[0]) or input[1] != ':' or !std.fs.path.PathType.windows.isSep(u8, input[2])) return error.InvalidFileUrlDrive;
            try writer.writer.writeByte('/');
        }
    } else if (!std.fs.path.isAbsolutePosix(input)) return error.InvalidFileUrlPath;
    const hex = "0123456789ABCDEF";
    for (path) |byte| {
        if (byte == '/' or (windows and byte == '\\')) {
            try writer.writer.writeByte('/');
        } else if (std.ascii.isAlphanumeric(byte) or std.mem.indexOfScalar(u8, "-._~:", byte) != null) {
            try writer.writer.writeByte(byte);
        } else {
            try writer.writer.writeAll(&.{ '%', hex[byte >> 4], hex[byte & 15] });
        }
    }
    return writer.toOwnedSlice();
}

test "native file URLs preserve Unicode reserved characters drive and UNC paths" {
    const gpa = std.testing.allocator;
    inline for (.{
        .{ false, "/tmp/a #%.\u{1f680}.js", "file:///tmp/a%20%23%25.%F0%9F%9A%80.js" },
        .{ false, "/tmp/back\\slash", "file:///tmp/back%5Cslash" },
        .{ true, "C:\\a b\\extension.ts", "file:///C:/a%20b/extension.ts" },
        .{ true, "\\\\server\\share\\a b.js", "file://server/share/a%20b.js" },
    }) |sample| {
        const url = try fromPath(gpa, sample[1], sample[0]);
        defer gpa.free(url);
        try std.testing.expectEqualStrings(sample[2], url);
        const path = try toPath(gpa, url, sample[0]);
        defer gpa.free(path);
        try std.testing.expectEqualStrings(sample[1], path);
    }
    try std.testing.expectError(error.InvalidFileUrlSeparator, toPath(gpa, "file:///tmp/%2Fsecret", false));
    try std.testing.expectError(error.InvalidFileUrlSeparator, toPath(gpa, "file:///C:/a%5Csecret", true));
    try std.testing.expectError(error.InvalidFileUrlEncoding, toPath(gpa, "file:///tmp/%GG", false));
    try std.testing.expectError(error.InvalidFileUrlEncoding, toPath(gpa, "file:///tmp/%FF", false));
    try std.testing.expectError(error.InvalidFileUrlHost, toPath(gpa, "file://remote/tmp/a", false));
    try std.testing.expectError(error.InvalidFileUrlDrive, toPath(gpa, "file:///tmp/a", true));
    const query_path = try toPath(gpa, "file:///tmp/a?copy=2#part", false);
    defer gpa.free(query_path);
    try std.testing.expectEqualStrings("/tmp/a", query_path);
}
