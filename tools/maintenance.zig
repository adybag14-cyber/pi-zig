//! Native repository maintenance entry point; no Python/Node tool dependency.
const std = @import("std");
const catalog = @import("catalog.zig");

const forbidden_names = [_][]const u8{
    "generated_root.zig", "tools_extended.zig", "tools_dispatch.zig",
    "catalog_index.zig",  "routes_all.zig",     "methods_all.zig",
};

pub fn forbiddenImplementation(path: []const u8) bool {
    const extension = std.fs.path.extension(path);
    for ([_][]const u8{ ".py", ".pyc", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts", ".rs", ".go", ".java", ".rb", ".lua", ".cpp", ".cc", ".cxx" }) |language| {
        if (std.ascii.eqlIgnoreCase(extension, language)) return true;
    }
    const basename = std.fs.path.basename(path);
    for (forbidden_names) |name| if (std.mem.eql(u8, basename, name)) return true;
    return std.mem.indexOf(u8, basename, "_shard_") != null;
}

fn verifyVendors(gpa: std.mem.Allocator, io: std.Io, writer: *std.Io.Writer) !bool {
    var failures: usize = 0;
    var files: usize = 0;
    for ([_][]const u8{ "vendor/quickjs", "vendor/tree-sitter", "vendor/typescript-parser" }) |root| {
        const manifest_path = try std.fs.path.join(gpa, &.{ root, "UPSTREAM.json" });
        defer gpa.free(manifest_path);
        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, manifest_path, gpa, .limited(1024 * 1024));
        defer gpa.free(bytes);
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, bytes, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidVendorManifest;
        const hashes = parsed.value.object.get("files") orelse return error.InvalidVendorManifest;
        if (hashes != .object or hashes.object.count() == 0) return error.InvalidVendorManifest;
        var entries = hashes.object.iterator();
        while (entries.next()) |entry| {
            const relative = entry.key_ptr.*;
            if (std.fs.path.isAbsolute(relative) or std.mem.indexOf(u8, relative, "..") != null or entry.value_ptr.* != .string) return error.InvalidVendorManifest;
            const path = try std.fs.path.join(gpa, &.{ root, relative });
            defer gpa.free(path);
            const data = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024 * 1024));
            defer gpa.free(data);
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
            const actual = std.fmt.bytesToHex(digest, .lower);
            files += 1;
            if (!std.mem.eql(u8, &actual, entry.value_ptr.string)) {
                failures += 1;
                try writer.print("vendor digest mismatch: {s}\n", .{path});
            }
        }
    }
    try writer.print("verified_vendor_files={d}\nvendor_digest_failures={d}\n", .{ files, failures });
    return failures == 0;
}

fn auditSource(gpa: std.mem.Allocator, io: std.Io, writer: *std.Io.Writer) !bool {
    var files: usize = 0;
    var failures: usize = 0;
    for ([_][]const u8{ "src", "tools", "scripts", "checkpoint-tests" }) |root| {
        const dir = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer dir.close(io);
        var walker = try dir.walk(gpa);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;
            files += 1;
            if (forbiddenImplementation(entry.path)) {
                failures += 1;
                try writer.print("forbidden implementation: {s}/{s}\n", .{ root, entry.path });
            }
            const extension = std.fs.path.extension(entry.path);
            if (std.mem.eql(u8, root, "src") and (std.mem.eql(u8, extension, ".c") or std.mem.eql(u8, extension, ".h")) and
                !std.mem.eql(u8, entry.path, "extensions/engine_abi.c") and !std.mem.eql(u8, entry.path, "extensions/engine_abi.h") and
                !std.mem.eql(u8, entry.path, "extensions\\engine_abi.c") and !std.mem.eql(u8, entry.path, "extensions\\engine_abi.h"))
            {
                failures += 1;
                try writer.print("unreviewed C exception: {s}/{s}\n", .{ root, entry.path });
            }
        }
    }
    try writer.print("audited_files={d}\nimplementation_failures={d}\n", .{ files, failures });
    return failures == 0;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &stdout.interface;
    if (args.len >= 2 and std.mem.eql(u8, args[1], "catalog")) {
        const source = try std.Io.Dir.cwd().readFileAlloc(init.io, "src/ai/catalog_source.json", init.gpa, .limited(16 * 1024 * 1024));
        defer init.gpa.free(source);
        const rendered = try catalog.render(init.gpa, source);
        defer init.gpa.free(rendered);
        if (args.len == 3 and std.mem.eql(u8, args[2], "--check")) {
            const current = try std.Io.Dir.cwd().readFileAlloc(init.io, "src/ai/catalog_generated.zig", init.gpa, .limited(16 * 1024 * 1024));
            defer init.gpa.free(current);
            if (!std.mem.eql(u8, current, rendered)) return error.StaleGeneratedCatalog;
            try writer.writeAll("Native generated catalog check passed.\n");
            try writer.flush();
            return;
        }
        const destination = if (args.len == 4 and std.mem.eql(u8, args[2], "--output")) args[3] else "src/ai/catalog_generated.zig";
        const file = try std.Io.Dir.cwd().createFile(init.io, destination, .{});
        defer file.close(init.io);
        try file.writePositionalAll(init.io, rendered, 0);
        try writer.print("Generated native catalog: {s}\n", .{destination});
        try writer.flush();
        return;
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "audit-source")) {
        const passed = try auditSource(init.gpa, init.io, writer);
        const vendors_passed = try verifyVendors(init.gpa, init.io, writer);
        try writer.flush();
        if (!passed or !vendors_passed) std.process.exit(1);
        return;
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "verify-vendors")) {
        const passed = try verifyVendors(init.gpa, init.io, writer);
        try writer.flush();
        if (!passed) std.process.exit(1);
        return;
    }
    try writer.writeAll("usage: pi-maintenance audit-source | verify-vendors | catalog [--output <path>]\n");
    try writer.flush();
    if (args.len > 1) std.process.exit(2);
}

test "language audit rejects implementation scripts and synthetic surfaces" {
    for ([_][]const u8{ "extensions/bridge.mjs", "generator.py", "plugin.ts", "old.JS", "tools_extended.zig", "api_shard_01.zig" }) |path| {
        try std.testing.expect(forbiddenImplementation(path));
    }
    for ([_][]const u8{ "extensions/engine.zig", "catalog_source.json", "engine_abi.c", "LICENSE", "README.md" }) |path| {
        try std.testing.expect(!forbiddenImplementation(path));
    }
}
