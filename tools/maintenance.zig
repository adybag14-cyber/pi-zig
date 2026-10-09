//! Native repository maintenance entry point; no Python/Node tool dependency.
const std = @import("std");
const catalog = @import("catalog.zig");
const projections = @import("projections.zig");
const config_schemas = @import("config_schemas.zig");
const artifacts = @import("artifacts.zig");
const release = @import("release.zig");
const upstream_contract = @import("upstream_contract.zig");
const release_config = @import("release_config");

const forbidden_names = [_][]const u8{
    "gen_surface.py",
    "generated_root.zig",
    "tools_extended.zig",
    "tools_dispatch.zig",
    "catalog_index.zig",
    "routes_all.zig",
    "methods_all.zig",
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
    for ([_][]const u8{ "vendor/quickjs", "vendor/tree-sitter", "vendor/typescript-parser", "vendor/sqlite" }) |root| {
        const manifest_path = try std.fs.path.join(gpa, &.{ root, "UPSTREAM.json" });
        defer gpa.free(manifest_path);
        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, manifest_path, gpa, .limited(1024 * 1024));
        defer gpa.free(bytes);
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, bytes, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidVendorManifest;
        const hashes = parsed.value.object.get("files") orelse return error.InvalidVendorManifest;
        if (hashes != .object or hashes.object.count() == 0) return error.InvalidVendorManifest;
        const commit = parsed.value.object.get("commit") orelse return error.InvalidVendorManifest;
        if (commit != .string) return error.InvalidVendorManifest;
        if (std.mem.eql(u8, root, "vendor/sqlite")) {
            const kind = parsed.value.object.get("revision_kind") orelse return error.InvalidVendorManifest;
            if (kind != .string or !std.mem.eql(u8, kind.string, "Fossil SHA3-256") or commit.string.len != 64) return error.InvalidVendorManifest;
        } else if (commit.string.len != 40) return error.InvalidVendorManifest;
        for (commit.string) |byte| if (!std.ascii.isHex(byte)) return error.InvalidVendorManifest;
        const dir = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
        defer dir.close(io);
        var walker = try dir.walk(gpa);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind == .directory) continue;
            const canonical = try gpa.dupe(u8, entry.path);
            defer gpa.free(canonical);
            for (canonical) |*byte| if (byte.* == '\\') {
                byte.* = '/';
            };
            if (entry.kind != .file or (!std.mem.eql(u8, canonical, "UPSTREAM.json") and !hashes.object.contains(canonical))) {
                failures += 1;
                try writer.print("unmanifested vendor entry: {s}/{s}\n", .{ root, canonical });
            }
        }
        var entries = hashes.object.iterator();
        while (entries.next()) |entry| {
            const relative = entry.key_ptr.*;
            if (std.fs.path.isAbsolute(relative) or std.mem.indexOf(u8, relative, "..") != null or entry.value_ptr.* != .string or entry.value_ptr.string.len != 64) return error.InvalidVendorManifest;
            for (entry.value_ptr.string) |byte| if (!std.ascii.isHex(byte)) return error.InvalidVendorManifest;
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

fn auditSource(gpa: std.mem.Allocator, io: std.Io, writer: *std.Io.Writer, enforce_languages: bool) !bool {
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
            const synthetic = blk: {
                const basename = std.fs.path.basename(entry.path);
                for (forbidden_names) |name| if (std.mem.eql(u8, name, basename)) break :blk true;
                break :blk std.mem.indexOf(u8, basename, "_shard_") != null;
            };
            if (synthetic or (enforce_languages and forbiddenImplementation(entry.path))) {
                failures += 1;
                try writer.print("forbidden implementation: {s}/{s}\n", .{ root, entry.path });
            }
            const extension = std.fs.path.extension(entry.path);
            if (std.mem.eql(u8, root, "src") and (std.mem.eql(u8, extension, ".c") or std.mem.eql(u8, extension, ".h")) and
                !std.mem.eql(u8, entry.path, "extensions/engine_abi.c") and !std.mem.eql(u8, entry.path, "extensions/engine_abi.h") and
                !std.mem.eql(u8, entry.path, "extensions\\engine_abi.c") and !std.mem.eql(u8, entry.path, "extensions\\engine_abi.h") and
                !std.mem.eql(u8, entry.path, "extensions/typescript_scanner_abi.h") and !std.mem.eql(u8, entry.path, "extensions\\typescript_scanner_abi.h") and
                !std.mem.eql(u8, entry.path, "durable/process_probe.c") and !std.mem.eql(u8, entry.path, "durable\\process_probe.c"))
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
    if (args.len >= 3 and std.mem.eql(u8, args[1], "hash-files")) {
        try artifacts.writeFileDigests(init.io, args[2..], writer);
        try writer.flush();
        return;
    }
    if ((args.len == 2 or args.len == 3) and std.mem.eql(u8, args[1], "verify-release")) {
        const manifest = try std.Io.Dir.cwd().readFileAlloc(init.io, "ARTIFACT-MANIFEST.json", init.gpa, .limited(1024 * 1024));
        defer init.gpa.free(manifest);
        const source = try std.Io.Dir.cwd().readFileAlloc(init.io, "src/ai/catalog_source.json", init.gpa, .limited(16 * 1024 * 1024));
        defer init.gpa.free(source);
        try release.validate(init.gpa, manifest, source, .{
            .version = release_config.version,
            .upstream_version = release_config.upstream_version,
            .upstream_commit = release_config.upstream_commit,
        }, if (args.len == 3) args[2] else null);
        try artifacts.verify(init.gpa, init.io, writer);
        const languages_passed = try auditSource(init.gpa, init.io, writer, true);
        const vendors_passed = try verifyVendors(init.gpa, init.io, writer);
        try writer.flush();
        if (!languages_passed or !vendors_passed) return error.InvalidNativeReleaseSources;
        return;
    }
    if (args.len == 5 and std.mem.eql(u8, args[1], "capture-upstream-contract")) {
        const bytes = try upstream_contract.capture(init.gpa, init.io, args[2], args[3]);
        defer init.gpa.free(bytes);
        const file = try std.Io.Dir.cwd().createFile(init.io, args[4], .{});
        defer file.close(init.io);
        try file.writePositionalAll(init.io, bytes, 0);
        try writer.writeAll("Captured immutable whole-tree upstream contract.\n");
        try writer.flush();
        return;
    }
    if (args.len == 4 and std.mem.eql(u8, args[1], "verify-upstream-contract")) {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[3], init.gpa, .limited(32 * 1024 * 1024));
        defer init.gpa.free(bytes);
        upstream_contract.verify(init.gpa, init.io, args[2], bytes, writer) catch |err| {
            try writer.flush();
            return err;
        };
        try writer.flush();
        return;
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "verify-artifacts")) {
        try artifacts.verify(init.gpa, init.io, writer);
        try writer.flush();
        return;
    }
    if (args.len == 3 and std.mem.eql(u8, args[1], "artifact-manifest")) {
        const checkpoint = std.fmt.parseInt(u32, args[2], 10) catch return error.InvalidCheckpoint;
        try artifacts.generate(init.gpa, init.io, checkpoint, writer);
        try writer.flush();
        return;
    }
    if (args.len == 4 and std.mem.eql(u8, args[1], "import-changelog")) {
        const bytes = try projections.changelog(init.gpa, init.io, args[2], args[3]);
        defer init.gpa.free(bytes);
        const file = try std.Io.Dir.cwd().createFile(init.io, "src/coding_agent/assets/UPSTREAM-CHANGELOG.md", .{});
        defer file.close(init.io);
        try file.writePositionalAll(init.io, bytes, 0);
        try writer.print("Imported {d} changelog bytes from {s}\n", .{ bytes.len, args[3] });
        try writer.flush();
        return;
    }
    if (args.len == 8 and std.mem.eql(u8, args[1], "import-catalog")) {
        // Explicit immutable inputs: catalog, version, commit, source archive,
        // revision and destination. No upstream program is executed.
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], init.gpa, .limited(32 * 1024 * 1024));
        defer init.gpa.free(bytes);
        const archive = try std.Io.Dir.cwd().readFileAlloc(init.io, args[5], init.gpa, .limited(256 * 1024 * 1024));
        defer init.gpa.free(archive);
        if (!std.ascii.eqlIgnoreCase(try projections.archiveCommit(archive), args[4])) return error.SourceArchiveCommitMismatch;
        const archive_version = try projections.validateNamedPackage(init.gpa, try projections.archiveFile(archive, "packages/ai/package.json"), "@earendil-works/pi-ai");
        defer init.gpa.free(archive_version);
        if (!std.mem.eql(u8, archive_version, args[3])) return error.SourceArchiveVersionMismatch;
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(archive, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        const source = try catalog.importTyped(init.gpa, bytes, args[3], args[4], &hex, args[6]);
        defer init.gpa.free(source);
        const validation = try catalog.render(init.gpa, source);
        defer init.gpa.free(validation);
        const file = try std.Io.Dir.cwd().createFile(init.io, args[7], .{});
        defer file.close(init.io);
        try file.writePositionalAll(init.io, source, 0);
        try writer.print("Imported reviewed typed catalog: {s}\n", .{args[7]});
        try writer.flush();
        return;
    }
    if ((args.len == 5 or args.len == 6) and std.mem.eql(u8, args[1], "project-config-schemas")) {
        const check = args.len == 6;
        if (check and !std.mem.eql(u8, args[5], "--check")) return error.InvalidSchemaProjectionArgument;
        const archive = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], init.gpa, .limited(256 * 1024 * 1024));
        defer init.gpa.free(archive);
        try config_schemas.project(init.gpa, init.io, archive, args[3], args[4], check);
        try writer.writeAll(if (check) "Published configuration schema projection check passed.\n" else "Projected archive-bound published configuration schemas.\n");
        try writer.flush();
        return;
    }
    if (args.len >= 2 and std.mem.eql(u8, args[1], "catalog")) {
        if (!(args.len == 2 or (args.len == 3 and std.mem.eql(u8, args[2], "--check")) or (args.len == 4 and std.mem.eql(u8, args[2], "--output")))) return error.InvalidMaintenanceArguments;
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
    if (args.len == 2 and (std.mem.eql(u8, args[1], "audit-source") or std.mem.eql(u8, args[1], "audit-structure"))) {
        const enforce_languages = std.mem.eql(u8, args[1], "audit-source");
        const passed = try auditSource(init.gpa, init.io, writer, enforce_languages);
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
    try writer.writeAll("usage: pi-maintenance audit-source | audit-structure | verify-vendors | catalog [--check | --output <path>]\n" ++
        "       pi-maintenance import-changelog <upstream-checkout> <expected-commit>\n" ++
        "       pi-maintenance artifact-manifest <checkpoint> | verify-artifacts | verify-release [tag]\n" ++
        "       pi-maintenance import-catalog <catalog-json> <version> <commit> <source-archive> <revision> <destination>\n" ++
        "       pi-maintenance project-config-schemas <source-archive> <commit> <destination> [--check]\n");
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

test {
    _ = projections;
    _ = artifacts;
    _ = release;
}
