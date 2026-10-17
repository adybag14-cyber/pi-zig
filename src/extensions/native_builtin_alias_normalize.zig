//! Preserve linked QuickJS default filename normalization when aliases require
//! a host normalizer and no user SourceLoader normalizer is installed.
//! Authority: vendor/quickjs/quickjs.c js_default_module_normalize_name.
//! Only leading ./ and ../ are reduced; this is NOT std.fs.path.resolve.
const std = @import("std");
const c = @import("engine.zig").c;
pub fn duplicate(context: ?*c.JSContext, bytes: []const u8) [*c]u8 {
    const capacity = std.math.add(usize, bytes.len, 1) catch { _ = c.JS_ThrowOutOfMemory(context); return null; };
    const allocation = c.js_malloc(context, capacity) orelse return null;
    const output: [*]u8 = @ptrCast(allocation);
    @memcpy(output[0..bytes.len], bytes); output[bytes.len] = 0; return output;
}
pub fn defaultFilename(context: ?*c.JSContext, base: []const u8, name: []const u8) [*c]u8 {
    if (name.len == 0 or name[0] != '.') return duplicate(context, name);
    var prefix_len = std.mem.lastIndexOfScalar(u8, base, '/') orelse 0;
    const first_capacity = std.math.add(usize, prefix_len, name.len) catch { _ = c.JS_ThrowOutOfMemory(context); return null; };
    const capacity = std.math.add(usize, first_capacity, 2) catch { _ = c.JS_ThrowOutOfMemory(context); return null; };
    const allocation = c.js_malloc(context, capacity) orelse return null;
    const output: [*]u8 = @ptrCast(allocation);
    @memcpy(output[0..prefix_len], base[0..prefix_len]);
    var remaining = name;
    while (true) {
        if (std.mem.startsWith(u8, remaining, "./")) {
            remaining = remaining[2..];
        } else if (std.mem.startsWith(u8, remaining, "../")) {
            if (prefix_len == 0) break;
            const segment_start = if (std.mem.lastIndexOfScalar(u8, output[0..prefix_len], '/')) |slash| slash + 1 else 0;
            const segment = output[segment_start..prefix_len];
            if (std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) break;
            prefix_len = if (segment_start == 0) 0 else segment_start - 1;
            remaining = remaining[3..];
        } else break;
    }
    if (prefix_len != 0) { output[prefix_len] = '/'; prefix_len += 1; }
    @memcpy(output[prefix_len .. prefix_len + remaining.len], remaining);
    output[prefix_len + remaining.len] = 0; return output;
}
