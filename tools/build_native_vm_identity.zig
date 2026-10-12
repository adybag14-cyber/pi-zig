//! Conservative replay identity: all native source, C VM and ICU inputs plus
//! the exact Zig compiler and its installed library tree. Over-invalidation is
//! preferable to replaying a journal against a silently changed implementation.
const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

fn field(hash: *Sha256, value: []const u8) void {
    var size: [8]u8 = undefined;
    std.mem.writeInt(u64, &size, value.len, .little);
    hash.update(&size);
    hash.update(value);
}
fn fileDigest(io: std.Io, dir: std.Io.Dir, path: []const u8) ![32]u8 {
    const file = try dir.openFile(io, path, .{});
    defer file.close(io);
    var buffer: [16384]u8 = undefined;
    var reader = file.reader(io, &buffer);
    var block: [16384]u8 = undefined;
    var hash = Sha256.init(.{});
    while (true) {
        const count = try reader.interface.readSliceShort(&block);
        hash.update(block[0..count]);
        if (count < block.len) break;
    }
    return hash.finalResult();
}
fn less(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}
fn tree(b: *std.Build, hash: *Sha256, base: std.Io.Dir, path: []const u8, domain: []const u8) !void {
    const io = b.graph.io;
    const dir = try base.openDir(io, path, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(b.allocator);
    defer walker.deinit();
    var paths: std.ArrayList([]const u8) = .empty;
    defer {
        for (paths.items) |entry| b.allocator.free(entry);
        paths.deinit(b.allocator);
    }
    while (try walker.next(io)) |entry| switch (entry.kind) {
        .directory => {},
        .file => try paths.append(b.allocator, try b.allocator.dupe(u8, entry.path)),
        else => return error.UnboundVMIdentityInput,
    };
    std.mem.sort([]const u8, paths.items, {}, less);
    field(hash, domain);
    for (paths.items) |entry| {
        // Directory separators are transport details rather than source data.
        const normalized = try b.allocator.dupe(u8, entry);
        defer b.allocator.free(normalized);
        std.mem.replaceScalar(u8, normalized, '\\', '/');
        field(hash, normalized);
        const digest = try fileDigest(io, dir, entry);
        field(hash, &digest);
    }
}
pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, use_llvm: ?bool) !*std.Build.Module {
    var hash = Sha256.init(.{});
    field(&hash, "pi-zig-native-codemode-identity-v1");
    for ([_][]const u8{ "src", "tools", "vendor/quickjs", "vendor/icu78" }) |path| try tree(b, &hash, b.build_root.handle, path, path);
    for ([_][]const u8{ "build.zig", "build.zig.zon" }) |path| {
        field(&hash, path);
        const digest = try fileDigest(b.graph.io, b.build_root.handle, path);
        field(&hash, &digest);
    }
    field(&hash, "zig-compiler");
    const compiler = try fileDigest(b.graph.io, .cwd(), b.graph.zig_exe);
    field(&hash, &compiler);
    try tree(b, &hash, b.graph.zig_lib_directory.handle, ".", "zig-installed-library");
    field(&hash, try target.result.zigTriple(b.allocator));
    field(&hash, target.result.cpu.model.name);
    field(&hash, b.fmt("{any}", .{target.result.cpu.features.ints}));
    field(&hash, b.fmt("{any}", .{target.result.os.version_range}));
    field(&hash, @tagName(target.result.ofmt));
    field(&hash, @tagName(optimize));
    field(&hash, if (use_llvm) |enabled| if (enabled) "llvm" else "self-hosted" else "compiler-default-backend");
    const options = b.addOptions();
    options.addOption([64]u8, "sha256", std.fmt.bytesToHex(hash.finalResult(), .lower));
    options.addOption([]const u8, "schema", "pi-zig-native-codemode-identity-v1");
    return options.createModule();
}

test "native VM identity frames source fields without concatenation collisions" {
    var first = Sha256.init(.{});
    field(&first, "ab");
    field(&first, "c");
    var second = Sha256.init(.{});
    field(&second, "a");
    field(&second, "bc");
    try std.testing.expect(!std.mem.eql(u8, &first.finalResult(), &second.finalResult()));
}
