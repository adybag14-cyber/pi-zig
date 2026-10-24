// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Native selected node_modules.cc PackageConfig cache. Entries have stable
//! native addresses across map growth, just as references into unordered_map
//! do. No JS object, property or public filesystem method implements this cache.
//! The binding-only retained parse entry is the next additive parser ABI; this
//! draft is not yet wired into the public loader.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_node_operation_scope.zig").Scope;
const ChargedAllocator = @import("native_env_charged_allocator.zig").ChargedAllocator;
const physical = @import("native_node_package_json_io.zig");
const parser = @import("native_node_package_json_api.zig").c;

pub const Entry = struct {
    path: []u8,
    config: ?*parser.PiNodePackageJsonConfig = null,

    pub fn views(self: *const Entry) parser.PiNodePackageJsonViews {
        var output: parser.PiNodePackageJsonViews = undefined;
        parser.pi_node_package_json_config_views(self.config.?, &output);
        return output;
    }
};
pub const Result = union(enum) {
    missing,
    // Borrowed stable cache entry. The genuine binding owner remains retained
    // across the complete native callback and fresh intrinsic serialization.
    found: *const Entry,
    // Owned uncached entry. Caller constructs/throws the original Error BEFORE
    // calling discardInvalid, including inherited code setter execution.
    invalid: *Entry,
};

pub const Cache = struct {
    memory: ChargedAllocator,
    parser_owner: ?*parser.PiNodePackageJsonParser,
    entries: std.StringHashMapUnmanaged(?*Entry) = .empty,

    // Returned before any allocator pointer into this value can escape.
    pub fn init(engine: *js.Engine) !Cache {
        var memory = ChargedAllocator.init(engine);
        errdefer memory.deinit();
        const native = parser.pi_node_package_json_parser_create(memory.owner) orelse {
            _ = engine.throwNativeOutOfMemoryFatal();
            return error.OutOfMemory;
        };
        return .{ .memory = memory, .parser_owner = native };
    }
    pub fn allocator(self: *Cache) std.mem.Allocator { return self.memory.allocator(); }
    pub fn deinit(self: *Cache) void {
        const alloc = self.allocator();
        // node_modules.h declares package_configs_ before json_parser.
        // Reverse member destruction retires the parser before cached Configs.
        if (self.parser_owner) |native| parser.pi_node_package_json_parser_destroy(native);
        self.parser_owner = null;
        var iterator = self.entries.iterator();
        while (iterator.next()) |item| {
            alloc.free(item.key_ptr.*);
            if (item.value_ptr.*) |entry| self.destroyEntry(entry);
        }
        self.entries.deinit(alloc);
        self.entries = .empty;
        self.memory.deinit();
    }
    fn destroyEntry(self: *Cache, entry: *Entry) void {
        if (entry.config) |config| parser.pi_node_package_json_config_destroy(config);
        const alloc = self.allocator();
        alloc.free(entry.path);
        alloc.destroy(entry);
    }
    pub fn discardInvalid(self: *Cache, entry: *Entry) void { self.destroyEntry(entry); }

    fn checkedNative(engine: *js.Engine, result: anytype) @TypeOf(result) {
        return result catch |err| {
            if (err == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal();
            return err;
        };
    }
    fn newEntry(self: *Cache, engine: *js.Engine, path: []const u8) !*Entry {
        const alloc = self.allocator();
        const result = try checkedNative(engine, alloc.create(Entry));
        errdefer alloc.destroy(result);
        // Original file_path is initialized before the physical open/read.
        result.* = .{ .path = try checkedNative(engine, alloc.dupe(u8, path)) };
        return result;
    }
    fn publishMissing(self: *Cache, engine: *js.Engine, path: []const u8) !void {
        const alloc = self.allocator();
        const key = try checkedNative(engine, alloc.dupe(u8, path));
        var adopted = false;
        defer if (!adopted) alloc.free(key);
        const item = try checkedNative(engine, self.entries.getOrPut(alloc, key));
        if (!item.found_existing) {
            item.value_ptr.* = null;
            adopted = true;
        }
    }
    fn publishEntry(self: *Cache, engine: *js.Engine, candidate: *Entry) !Result {
        const alloc = self.allocator();
        const key = try checkedNative(engine, alloc.dupe(u8, candidate.path));
        var adopted = false;
        defer if (!adopted) alloc.free(key);
        const item = try checkedNative(engine, self.entries.getOrPut(alloc, key));
        if (item.found_existing) {
            // An existing insertion remains the winner. This also keeps native
            // entry references stable if future intrinsic work reenters.
            self.destroyEntry(candidate);
            return if (item.value_ptr.*) |known| .{ .found = known } else .missing;
        }
        item.value_ptr.* = candidate;
        adopted = true;
        return .{ .found = candidate };
    }

    pub fn get(self: *Cache, s: *Scope, path: [:0]const u8) !Result {
        try s.pending();
        // find(path.data()) constructs its lookup from the C string, whereas
        // the actual insertion key and retained file_path use the full span.
        const lookup = path[0 .. std.mem.indexOfScalar(u8, path, 0) orelse path.len];
        if (self.entries.get(lookup)) |entry|
            return if (entry) |known| .{ .found = known } else .missing;

        const candidate = try self.newEntry(s.engine, path);
        var adopted = false;
        defer if (!adopted) self.destroyEntry(candidate);
        var read = try physical.read(s.engine, self.allocator(), path);
        switch (read) {
            .unavailable => {
                try self.publishMissing(s.engine, path);
                return .missing;
            },
            .bytes => {},
        }
        defer read.bytes.deinit(self.allocator());
        if (self.parser_owner == null) {
            self.parser_owner = parser.pi_node_package_json_parser_create(self.memory.owner) orelse {
                _ = s.engine.throwNativeOutOfMemoryFatal();
                return error.OutOfMemory;
            };
        }
        var parsed: ?*parser.PiNodePackageJsonConfig = null;
        const status = parser.pi_node_package_json_parse_retained(self.parser_owner.?,
            read.bytes.slice().ptr, read.bytes.slice().len, &parsed);
        if (status == parser.PI_NODE_PACKAGE_JSON_MEMORY) {
            // The actual native failure is recorded before releasing parser
            // partial storage, the read bytes, path and candidate allocations.
            _ = s.engine.throwNativeOutOfMemoryFatal();
            const failed_parser = self.parser_owner.?;
            self.parser_owner = null;
            parser.pi_node_package_json_parser_destroy(failed_parser);
            return error.OutOfMemory;
        }
        candidate.config = parsed orelse return error.ActualPackageParserResultRequired;
        if (status == parser.PI_NODE_PACKAGE_JSON_INVALID) {
            adopted = true;
            return .{ .invalid = candidate };
        }
        if (status != parser.PI_NODE_PACKAGE_JSON_OK)
            return error.ActualPackageParserStatusRequired;
        const selected = try self.publishEntry(s.engine, candidate);
        adopted = true;
        // The cache now owns the native Config before any fresh JS allocation.
        return selected;
    }
};
