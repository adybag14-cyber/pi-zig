//! Main-owned registry admission. JSON arguments never select an owner/lease.
const std = @import("std");
const registry_mod = @import("../extensions/provider_registry.zig");
const providers = @import("../ai/providers.zig");
const models = @import("../mcp/codemode_models.zig");
const json = @import("../mcp/protocol.zig").json;
const Value = json.Value;
pub const Snapshot = struct {
    arena: std.heap.ArenaAllocator,
    info: providers.ModelInfo,
    value: Value,
    configuration: Value,
    native_mode: bool = false,
    owner: ?*Owner = null,
    generation: u64 = 0,
    callback: ?registry_mod.Registry.MethodLease = null,
    auth_resolve: ?registry_mod.Registry.MethodLease = null,
    auth_check: ?registry_mod.Registry.MethodLease = null,
    pub fn deinit(self: *Snapshot) void {
        if (self.callback) |*callback| callback.deinit();
        if (self.auth_resolve) |*callback| callback.deinit();
        if (self.auth_check) |*callback| callback.deinit();
        self.arena.deinit();
    }
};
pub const Backend = struct {
    context: ?*anyopaque,
    operate: *const fn (?*anyopaque, std.mem.Allocator, *const Snapshot, models.Operation, Value, ?*bool) anyerror!json.Owned,
    available: *const fn (?*anyopaque, std.mem.Allocator, []const Snapshot, ?*bool) anyerror!json.Owned,
    retain: ?*const fn (?*anyopaque) void = null,
    release: ?*const fn (?*anyopaque) void = null,
};
pub const Owner = struct {
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    registry: ?*registry_mod.Registry = null,
    backend: Backend,
    generation: u64 = 1,
    live: bool = false,
    const Lease = struct { owner: *Owner, generation: u64 };
    /// Call after the Owner has its final stable address. Replacement invalidates
    /// every prior program before publication of the new actual registry.
    pub fn bind(self: *Owner, registry: *registry_mod.Registry) !void {
        try self.bindBackend(registry, self.backend);
    }
    pub fn bindBackend(self: *Owner, registry: *registry_mod.Registry, backend: Backend) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.generation == std.math.maxInt(u64)) return error.TypedRegistryGenerationExhausted;
        self.generation += 1;
        self.registry = registry;
        self.backend = backend;
        self.live = true;
        registry.access_mutex = &self.mutex;
    }
    pub fn retire(self: *Owner) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.live = false;
        self.registry = null;
    }
    pub fn runtime(self: *Owner) models.Runtime {
        return .{ .context = self, .invoke = unadmitted, .acquire = acquire };
    }
    fn unadmitted(_: ?*anyopaque, _: std.mem.Allocator, _: models.Operation, _: Value, _: ?*bool) !json.Owned {
        return error.TypedRegistryProgramNotAdmitted;
    }
    fn acquire(raw: ?*anyopaque, gpa: std.mem.Allocator) !models.Runtime {
        const self: *Owner = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (!self.live or self.registry == null) return error.TypedRegistryOwnerRetired;
        const lease = try gpa.create(Lease);
        lease.* = .{ .owner = self, .generation = self.generation };
        return .{ .context = lease, .invoke = invoke, .release = release };
    }
    fn release(raw: ?*anyopaque, gpa: std.mem.Allocator) void {
        const lease: *Lease = @ptrCast(@alignCast(raw.?));
        gpa.destroy(lease);
    }
    fn current(self: *Owner, generation: u64) !*registry_mod.Registry {
        if (!self.live or self.generation != generation) return error.TypedRegistryOwnerRetired;
        return self.registry orelse error.TypedRegistryOwnerRetired;
    }
    fn snapshot(self: *Owner, gpa: std.mem.Allocator, registry: *registry_mod.Registry, model: providers.ModelInfo, operation: models.Operation, generation: u64) !Snapshot {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        errdefer arena.deinit();
        const a = arena.allocator();
        const copied = try cloneModelField(providers.ModelInfo, a, model);
        const bytes = try registry.configurationOwned(a, model.providerName());
        const config = try std.json.parseFromSlice(Value, a, bytes, .{ .allocate = .alloc_always });
        const value = try modelValue(a, copied);
        const callback = if (operation == .classify or operation == .generateImages) try registry.captureTypedMethod(gpa, model.providerName(), model.apiName(), operation == .generateImages) else null;
        errdefer if (callback) |owned| {
            var release_callback = owned;
            release_callback.deinit();
        };
        const auth_resolve = try registry.captureMethod(gpa, model.providerName(), "auth.apiKey.resolve");
        errdefer if (auth_resolve) |owned| {
            var release_callback = owned;
            release_callback.deinit();
        };
        const auth_check = try registry.captureMethod(gpa, model.providerName(), "auth.apiKey.check");
        return .{ .arena = arena, .info = copied, .value = value, .configuration = config.value, .callback = callback, .auth_resolve = auth_resolve, .auth_check = auth_check, .native_mode = registry.nativeMode(model.providerName()), .owner = self, .generation = generation };
    }
    fn invoke(raw: ?*anyopaque, gpa: std.mem.Allocator, operation: models.Operation, args: Value, abort: ?*bool) !json.Owned {
        const lease: *Lease = @ptrCast(@alignCast(raw.?));
        const self = lease.owner;
        if (args != .array) return error.InvalidTypedRegistryArguments;
        self.mutex.lockUncancelable(self.io);
        var locked = true;
        defer if (locked) self.mutex.unlock(self.io);
        const registry = try self.current(lease.generation);
        const backend = self.backend;
        if (backend.retain) |retain| retain(backend.context);
        defer if (backend.release) |release_backend| release_backend(backend.context);
        var result = try json.Owned.empty(gpa);
        var result_live = true;
        errdefer if (result_live) result.deinit();
        const a = result.arena.allocator();
        if (operation == .classify or operation == .generateImages) {
            if (args.array.items.len < 2 or args.array.items[0] != .object) return error.InvalidTypedRegistryArguments;
            const selected = args.array.items[0];
            const provider = try json.asString(try json.required(selected, "provider"));
            const id = try json.asString(try json.required(selected, "id"));
            const kind: providers.ModelType = if (operation == .classify) .classifier else .image;
            for (registry.allCatalog()) |model| if (model.kind == kind and std.mem.eql(u8, model.providerName(), provider) and std.mem.eql(u8, model.id, id)) {
                var captured = try self.snapshot(gpa, registry, model, operation, lease.generation);
                defer captured.deinit();
                self.mutex.unlock(self.io);
                locked = false;
                result.deinit();
                result_live = false;
                var answer = try backend.operate(backend.context, gpa, &captured, operation, args.array.items[1], abort);
                errdefer answer.deinit();
                self.mutex.lockUncancelable(self.io);
                defer self.mutex.unlock(self.io);
                _ = try self.current(lease.generation);
                return answer;
            };
            return error.UnknownTypedRegistryModel;
        }
        if (args.array.items.len == 0) return error.InvalidTypedRegistryArguments;
        const kind = std.meta.stringToEnum(providers.ModelType, try json.asString(args.array.items[0])) orelse return error.InvalidTypedRegistryArguments;
        const provider: ?[]const u8 = if (args.array.items.len > 1 and args.array.items[1] != .null) try json.asString(args.array.items[1]) else null;
        const wanted_id: ?[]const u8 = if (operation == .getModelOfType and args.array.items.len > 2) try json.asString(args.array.items[2]) else null;
        if (operation == .getModelOfType and wanted_id == null) return error.InvalidTypedRegistryArguments;
        result.value = if (operation == .getModelOfType) .null else .{ .array = .init(a) };
        var available: std.ArrayList(Snapshot) = .empty;
        defer {
            for (available.items) |*item| item.deinit();
            available.deinit(gpa);
        }
        for (registry.allCatalog()) |model| {
            if (model.kind != kind or (provider != null and !std.mem.eql(u8, provider.?, model.providerName())) or (wanted_id != null and !std.mem.eql(u8, wanted_id.?, model.id))) continue;
            if (operation == .getAvailableOfType) {
                var captured = try self.snapshot(gpa, registry, model, operation, lease.generation);
                errdefer captured.deinit();
                try available.append(gpa, captured);
                continue;
            }
            const value = try modelValue(a, model);
            if (operation == .getModelOfType) {
                result.value = value;
                break;
            }
            try result.value.array.append(value);
        }
        if (operation == .getAvailableOfType) {
            self.mutex.unlock(self.io);
            locked = false;
            result.deinit();
            result_live = false;
            var answer = try backend.available(backend.context, gpa, available.items, abort);
            errdefer answer.deinit();
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            _ = try self.current(lease.generation);
            return answer;
        }
        return result;
    }
};
fn cloneModelField(comptime T: type, a: std.mem.Allocator, value: T) anyerror!T {
    if (comptime T == Value) {
        return json.clone(a, value);
    } else if (comptime T == std.json.Array) {
        var output: std.json.Array = .init(a);
        for (value.items) |item| try output.append(try json.clone(a, item));
        return output;
    } else if (comptime T == std.json.ObjectMap) {
        var output: std.json.ObjectMap = .empty;
        var entries = value.iterator();
        while (entries.next()) |entry| try output.put(a, try a.dupe(u8, entry.key_ptr.*), try json.clone(a, entry.value_ptr.*));
        return output;
    } else return switch (@typeInfo(T)) {
        .optional => |info| if (value) |item| try cloneModelField(info.child, a, item) else null,
        .pointer => |info| switch (info.size) {
            .slice => blk: {
                const output = try a.alloc(info.child, value.len);
                for (value, output) |item, *target| target.* = try cloneModelField(info.child, a, item);
                break :blk output;
            },
            else => @compileError("Model snapshot contains an unsupported pointer: " ++ @typeName(T)),
        },
        .array => |info| blk: {
            var output: T = undefined;
            for (0..info.len) |index| output[index] = try cloneModelField(info.child, a, value[index]);
            break :blk output;
        },
        .@"struct" => |info| blk: {
            var output: T = undefined;
            inline for (info.fields) |field| @field(output, field.name) = try cloneModelField(field.type, a, @field(value, field.name));
            break :blk output;
        },
        .@"union" => |info| blk: {
            const tag = std.meta.activeTag(value);
            inline for (info.fields) |field| if (std.mem.eql(u8, @tagName(tag), field.name)) break :blk @unionInit(T, field.name, try cloneModelField(field.type, a, @field(value, field.name)));
            unreachable;
        },
        else => value,
    };
}
pub fn modelValue(a: std.mem.Allocator, model: providers.ModelInfo) !Value {
    var row: Value = .{ .object = .empty };
    if (model.source_metadata_json) |bytes| {
        const parsed = try std.json.parseFromSlice(Value, a, bytes, .{ .allocate = .alloc_always });
        row = parsed.value;
    }
    try row.object.put(a, "id", .{ .string = try a.dupe(u8, model.id) });
    try row.object.put(a, "provider", .{ .string = try a.dupe(u8, model.providerName()) });
    try row.object.put(a, "api", .{ .string = try a.dupe(u8, model.apiName()) });
    if (model.base_url) |base| try row.object.put(a, "baseUrl", .{ .string = try a.dupe(u8, base) });
    if (model.kind != .chat) {
        try row.object.put(a, "type", .{ .string = @tagName(model.kind) });
        return row;
    }
    try row.object.put(a, "name", .{ .string = try a.dupe(u8, model.display) });
    try row.object.put(a, "reasoning", .{ .bool = model.reasoning });
    try row.object.put(a, "contextWindow", .{ .integer = @intCast(model.context_window) });
    try row.object.put(a, "maxTokens", .{ .integer = @intCast(model.max_tokens) });
    var input: Value = .{ .array = .init(a) };
    if (model.input_text) try input.array.append(.{ .string = "text" });
    if (model.input_image) try input.array.append(.{ .string = "image" });
    try row.object.put(a, "input", input);
    var cost: Value = .{ .object = .empty };
    inline for (.{ .{ "input", "input" }, .{ "output", "output" }, .{ "cacheRead", "cache_read" }, .{ "cacheWrite", "cache_write" } }) |field| try cost.object.put(a, field[0], .{ .float = @field(model.cost, field[1]) });
    try row.object.put(a, "cost", cost);
    return row;
}
