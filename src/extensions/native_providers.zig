//! Provider configuration and callback ownership for the directly linked engine.
const std = @import("std");
const engine_mod = @import("engine.zig");
const descriptor = @import("provider_method_ref.zig");
const c = engine_mod.c;
const maximum_safe_integer = 9_007_199_254_740_991;

const Callback = struct {
    provider: []u8,
    path: []u8,
    generation: u64,
    function: c.JSValue,
    receiver: c.JSValue,
};
const Pending = struct { id: []u8, callback: Callback };
const Registration = struct { source: c.JSValue, encoded: c.JSValue, generation: u64 };

pub const Providers = struct {
    engine: *engine_mod.Engine,
    registrations: std.StringHashMapUnmanaged(Registration) = .empty,
    callbacks: std.StringHashMapUnmanaged(Callback) = .empty,
    next_ordinal: u64 = 1,
    next_generation: u64 = 1,

    pub fn init(engine: *engine_mod.Engine) Providers {
        return .{ .engine = engine };
    }

    pub fn deinit(self: *Providers) void {
        var registrations = self.registrations.iterator();
        while (registrations.next()) |entry| {
            self.engine.gpa.free(entry.key_ptr.*);
            self.engine.freeValue(entry.value_ptr.source);
            self.engine.freeValue(entry.value_ptr.encoded);
        }
        self.registrations.deinit(self.engine.gpa);
        var callbacks = self.callbacks.iterator();
        while (callbacks.next()) |entry| {
            self.engine.gpa.free(entry.key_ptr.*);
            self.freeCallback(entry.value_ptr.*);
        }
        self.callbacks.deinit(self.engine.gpa);
    }

    fn freeCallback(self: *Providers, callback: Callback) void {
        self.engine.gpa.free(callback.provider);
        self.engine.gpa.free(callback.path);
        self.engine.freeValue(callback.function);
        self.engine.freeValue(callback.receiver);
    }

    fn define(self: *Providers, object: c.JSValue, key: [*:0]const u8, value: c.JSValue) !void {
        if (c.JS_DefinePropertyValueStr(self.engine.context, object, key, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }

    fn copyDefined(self: *Providers, destination: c.JSValue, source: c.JSValue) !void {
        var names: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(self.engine.context, &names, &count, source, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
        defer c.JS_FreePropertyEnum(self.engine.context, names, count);
        if (count > 16_384) return error.NativeProviderConfigurationLimit;
        for (names[0..count]) |name| {
            const value = try self.engine.checked(c.JS_GetProperty(self.engine.context, source, name.atom));
            if (c.JS_IsUndefined(value)) {
                self.engine.freeValue(value);
                continue;
            }
            if (c.JS_DefinePropertyValue(self.engine.context, destination, name.atom, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        }
    }

    fn callbackId(self: *Providers, provider: []const u8) ![]u8 {
        if (self.next_ordinal > maximum_safe_integer) return error.NativeProviderGenerationExhausted;
        var name: std.ArrayList(u8) = .empty;
        defer name.deinit(self.engine.gpa);
        for (provider) |byte| {
            if (std.ascii.isAlphanumeric(byte) or std.mem.indexOfScalar(u8, "-_.!~*'()", byte) != null) {
                try name.append(self.engine.gpa, byte);
            } else {
                const hex = "0123456789ABCDEF";
                try name.appendSlice(self.engine.gpa, &.{ '%', hex[byte >> 4], hex[byte & 15] });
            }
        }
        const id = try std.fmt.allocPrint(self.engine.gpa, "provider:{s}:{d}", .{ name.items, self.next_ordinal });
        self.next_ordinal += 1;
        return id;
    }

    fn walk(
        self: *Providers,
        value: c.JSValue,
        receiver: c.JSValue,
        provider: []const u8,
        path: []const u8,
        generation: u64,
        active: *std.ArrayList(c.JSValue),
        pending: *std.ArrayList(Pending),
    ) anyerror!c.JSValue {
        const engine = self.engine;
        if (c.JS_IsFunction(engine.context, value)) {
            if (self.callbacks.count() + pending.items.len >= 16_384) return error.NativeProviderCallbackLimit;
            const id = try self.callbackId(provider);
            errdefer engine.gpa.free(id);
            const owned_provider = try engine.gpa.dupe(u8, provider);
            errdefer engine.gpa.free(owned_provider);
            const owned_path = try engine.gpa.dupe(u8, path);
            errdefer engine.gpa.free(owned_path);
            const object = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
            errdefer engine.freeValue(object);
            try self.define(object, descriptor.callback_id_field, try engine.fromJsonValue(.{ .string = id }));
            try self.define(object, descriptor.callback_kind_field, try engine.fromJsonValue(.{ .string = descriptor.provider_method_kind }));
            try self.define(object, descriptor.callback_path_field, try engine.fromJsonValue(.{ .string = path }));
            try self.define(object, descriptor.callback_generation_field, c.JS_NewInt64(engine.context, @intCast(generation)));
            const function = c.JS_DupValue(engine.context, value);
            errdefer engine.freeValue(function);
            const owner = c.JS_DupValue(engine.context, receiver);
            errdefer engine.freeValue(owner);
            try pending.append(engine.gpa, .{ .id = id, .callback = .{
                .provider = owned_provider,
                .path = owned_path,
                .generation = generation,
                .function = function,
                .receiver = owner,
            } });
            return object;
        }
        if (!c.JS_IsObject(value)) return c.JS_DupValue(engine.context, value);
        if (active.items.len >= 256) return error.NativeProviderConfigurationLimit;
        for (active.items) |ancestor| if (c.JS_IsStrictEqual(engine.context, value, ancestor)) return error.NativeProviderConfigurationCycle;
        try active.append(engine.gpa, value);
        defer _ = active.pop();
        const array = c.JS_IsArray(value);
        const clone = try engine.checked(if (array) c.JS_NewArray(engine.context) else c.JS_NewObjectProto(engine.context, c.pi_js_null()));
        errdefer engine.freeValue(clone);
        if (array) {
            const length = try engine.checked(c.JS_GetPropertyStr(engine.context, value, "length"));
            defer engine.freeValue(length);
            var size: u32 = 0;
            if (c.JS_ToUint32(engine.context, &size, length) < 0) return error.JavaScriptException;
            if (size > 16_384) return error.NativeProviderConfigurationLimit;
            for (0..size) |index| {
                const key = try std.fmt.allocPrint(engine.gpa, "{d}", .{index});
                defer engine.gpa.free(key);
                const atom = c.JS_NewAtomLen(engine.context, key.ptr, key.len);
                if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
                defer c.JS_FreeAtom(engine.context, atom);
                const present = c.JS_HasProperty(engine.context, value, atom);
                if (present < 0) return error.JavaScriptException;
                if (present == 0) continue;
                const child_path = if (path.len == 0) try engine.gpa.dupe(u8, key) else try std.fmt.allocPrint(engine.gpa, "{s}.{s}", .{ path, key });
                defer engine.gpa.free(child_path);
                const child = try engine.checked(c.JS_GetProperty(engine.context, value, atom));
                defer engine.freeValue(child);
                const encoded = try self.walk(child, value, provider, child_path, generation, active, pending);
                if (c.JS_SetPropertyUint32(engine.context, clone, @intCast(index), encoded) < 0) return error.JavaScriptException;
            }
            if (c.JS_SetPropertyStr(engine.context, clone, "length", c.JS_DupValue(engine.context, length)) < 0) return error.JavaScriptException;
            return clone;
        }
        var names: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, value, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
        defer c.JS_FreePropertyEnum(engine.context, names, count);
        if (count > 16_384) return error.NativeProviderConfigurationLimit;
        for (names[0..count]) |name| {
            const key_value = try engine.checked(c.JS_AtomToString(engine.context, name.atom));
            defer engine.freeValue(key_value);
            const key = try engine.toString(key_value);
            defer engine.gpa.free(key);
            const child_path = if (path.len == 0) try engine.gpa.dupe(u8, key) else try std.fmt.allocPrint(engine.gpa, "{s}.{s}", .{ path, key });
            defer engine.gpa.free(child_path);
            const child = try engine.checked(c.JS_GetProperty(engine.context, value, name.atom));
            defer engine.freeValue(child);
            const encoded = try self.walk(child, value, provider, child_path, generation, active, pending);
            if (c.JS_DefinePropertyValue(engine.context, clone, name.atom, encoded, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        }
        return clone;
    }

    /// Complete encoding before mutating live maps; old IDs remain callable until unregister.
    pub fn register(self: *Providers, name: []const u8, config: c.JSValue, replace: bool) !c.JSValue {
        const engine = self.engine;
        if (name.len == 0 or name.len > 4096 or !std.unicode.utf8ValidateSlice(name)) return error.InvalidNativeProviderName;
        if (!c.JS_IsObject(config) or c.JS_IsArray(config) or c.JS_IsFunction(engine.context, config)) return error.InvalidNativeProviderConfiguration;
        if (self.next_generation > maximum_safe_integer) return error.NativeProviderGenerationExhausted;
        const generation = self.next_generation;
        self.next_generation += 1;
        const source = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
        errdefer engine.freeValue(source);
        if (!replace) if (self.registrations.get(name)) |previous| try self.copyDefined(source, previous.source);
        try self.copyDefined(source, config);
        var active: std.ArrayList(c.JSValue) = .empty;
        defer active.deinit(engine.gpa);
        var pending: std.ArrayList(Pending) = .empty;
        defer pending.deinit(engine.gpa);
        var committed = false;
        defer if (!committed) for (pending.items) |entry| {
            engine.gpa.free(entry.id);
            self.freeCallback(entry.callback);
        };
        const encoded = try self.walk(source, c.pi_js_undefined(), name, "", generation, &active, &pending);
        errdefer engine.freeValue(encoded);
        const json = try engine.stringify(encoded);
        defer engine.gpa.free(json);
        const key = if (self.registrations.contains(name)) null else try engine.gpa.dupe(u8, name);
        errdefer if (key) |owned| engine.gpa.free(owned);
        try self.callbacks.ensureUnusedCapacity(engine.gpa, @intCast(pending.items.len));
        try self.registrations.ensureUnusedCapacity(engine.gpa, 1);
        for (pending.items) |entry| self.callbacks.putAssumeCapacityNoClobber(entry.id, entry.callback);
        if (self.registrations.getPtr(name)) |previous| {
            engine.freeValue(previous.source);
            engine.freeValue(previous.encoded);
            previous.* = .{ .source = source, .encoded = encoded, .generation = generation };
        } else self.registrations.putAssumeCapacityNoClobber(key.?, .{ .source = source, .encoded = encoded, .generation = generation });
        committed = true;
        return c.JS_DupValue(engine.context, encoded);
    }

    pub fn unregister(self: *Providers, name: []const u8) void {
        if (self.registrations.fetchRemove(name)) |removed| {
            self.engine.gpa.free(removed.key);
            self.engine.freeValue(removed.value.source);
            self.engine.freeValue(removed.value.encoded);
        }
        // Remove in repeated passes so table movement never invalidates an iterator.
        while (true) {
            var callbacks = self.callbacks.iterator();
            const id = blk: {
                while (callbacks.next()) |entry| if (std.mem.eql(u8, entry.value_ptr.provider, name)) break :blk entry.key_ptr.*;
                break :blk null;
            } orelse break;
            const removed = self.callbacks.fetchRemove(id).?;
            self.engine.gpa.free(removed.key);
            self.freeCallback(removed.value);
        }
    }

    pub fn invoke(self: *Providers, id: []const u8, arguments: c.JSValue) !c.JSValue {
        const entry = self.callbacks.get(id) orelse return error.UnknownNativeProviderCallback;
        const function = c.JS_DupValue(self.engine.context, entry.function);
        defer self.engine.freeValue(function);
        const receiver = c.JS_DupValue(self.engine.context, entry.receiver);
        defer self.engine.freeValue(receiver);
        if (!c.JS_IsArray(arguments)) return error.InvalidNativeProviderArguments;
        const length = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, arguments, "length"));
        defer self.engine.freeValue(length);
        var count: u32 = 0;
        if (c.JS_ToUint32(self.engine.context, &count, length) < 0) return error.JavaScriptException;
        if (count > 1024) return error.NativeProviderArgumentLimit;
        const args = try self.engine.gpa.alloc(c.JSValue, count);
        defer self.engine.gpa.free(args);
        var initialized: usize = 0;
        defer for (args[0..initialized]) |value| self.engine.freeValue(value);
        for (args, 0..) |*value, index| {
            value.* = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, arguments, @intCast(index)));
            initialized += 1;
        }
        const pending = try self.engine.checked(c.JS_Call(self.engine.context, function, receiver, @intCast(count), args.ptr));
        defer self.engine.freeValue(pending);
        return self.engine.awaitValue(pending);
    }

    pub fn manifest(self: *Providers) !c.JSValue {
        const result = try self.engine.checked(c.JS_NewArray(self.engine.context));
        errdefer self.engine.freeValue(result);
        var registrations = self.registrations.iterator();
        var index: u32 = 0;
        while (registrations.next()) |entry| : (index += 1) {
            const record = try self.engine.checked(c.JS_NewObjectProto(self.engine.context, c.pi_js_null()));
            var transferred = false;
            defer if (!transferred) self.engine.freeValue(record);
            try self.define(record, "name", try self.engine.fromJsonValue(.{ .string = entry.key_ptr.* }));
            try self.define(record, "config", c.JS_DupValue(self.engine.context, entry.value_ptr.encoded));
            transferred = true;
            if (c.JS_SetPropertyUint32(self.engine.context, result, index, record) < 0) return error.JavaScriptException;
        }
        return result;
    }
};

fn providerAllocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    var providers = Providers.init(engine);
    defer providers.deinit();
    const namespace = try engine.evalModule("export const config={name:'Provider',oauth:{owner:'stable',async key(value){return this.owner+':'+value}},nested:{methods:[function(value){return this.length+':'+value}]}};export const overlay={name:'Renamed'};", "provider-allocation.mjs");
    defer engine.freeValue(namespace);
    const config = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "config"));
    defer engine.freeValue(config);
    const initial = try providers.register("demo", config, false);
    defer engine.freeValue(initial);
    const overlay = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "overlay"));
    defer engine.freeValue(overlay);
    const replacement = try providers.register("demo", overlay, false);
    defer engine.freeValue(replacement);
    const manifest = try providers.manifest();
    defer engine.freeValue(manifest);
    const encoded = try engine.stringify(manifest);
    defer gpa.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "Renamed") != null);
    try std.testing.expectEqual(@as(usize, 4), providers.callbacks.count());
}

test "native provider registration and replacement release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, providerAllocationProbe, .{});
}

test "provider snapshot rejects cycles and BigInt before replacing live callbacks" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var providers = Providers.init(engine);
    defer providers.deinit();
    const namespace = try engine.evalModule("const shared={value:7};export const config={name:'Stable',left:shared,right:shared,key(){return this.name}};export const cycle={};cycle.self=cycle;export const unsupported={bad:1n};", "provider-atomic.mjs");
    defer engine.freeValue(namespace);
    const config = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "config"));
    defer engine.freeValue(config);
    const initial = try providers.register("demo", config, false);
    defer engine.freeValue(initial);
    const initial_json = try engine.stringify(initial);
    defer engine.gpa.free(initial_json);
    const cycle = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "cycle"));
    defer engine.freeValue(cycle);
    try std.testing.expectError(error.NativeProviderConfigurationCycle, providers.register("demo", cycle, false));
    const unsupported = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "unsupported"));
    defer engine.freeValue(unsupported);
    try std.testing.expectError(error.JavaScriptException, providers.register("demo", unsupported, false));
    engine.beginInvocation();
    try std.testing.expectEqual(@as(usize, 1), providers.callbacks.count());
    const retained_json = try engine.stringify(providers.registrations.get("demo").?.encoded);
    defer engine.gpa.free(retained_json);
    try std.testing.expectEqualStrings(initial_json, retained_json);
    var parsed = try std.json.parseFromSlice(std.json.Value, engine.gpa, retained_json, .{});
    defer parsed.deinit();
    const reference = try descriptor.ProviderMethodRef.fromJson(parsed.value.object.get("key").?);
    const args = try engine.checked(c.JS_NewArray(engine.context));
    defer engine.freeValue(args);
    const result = try providers.invoke(reference.callback_id, args);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("Stable", text);
}

test "native provider array traversal preserves holes inherited indices and callback receivers" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var providers = Providers.init(engine);
    defer providers.deinit();
    const namespace = try engine.evalModule("const values=new Array(3);const parent=Object.create(Array.prototype);parent[1]=function(){return this.length};Object.setPrototypeOf(values,parent);values.extra=function(){throw Error('non-index callback')};export const config={values};", "native-provider-array.mjs");
    defer engine.freeValue(namespace);
    const config = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "config"));
    defer engine.freeValue(config);
    const encoded = try providers.register("array", config, false);
    defer engine.freeValue(encoded);
    const json = try engine.stringify(encoded);
    defer engine.gpa.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, engine.gpa, json, .{});
    defer parsed.deinit();
    const values = parsed.value.object.get("values").?.array.items;
    try std.testing.expectEqual(@as(usize, 3), values.len);
    try std.testing.expect(values[0] == .null and values[2] == .null);
    try std.testing.expectEqual(@as(usize, 1), providers.callbacks.count());
    const reference = try descriptor.ProviderMethodRef.fromJson(values[1]);
    const args = try engine.checked(c.JS_NewArray(engine.context));
    defer engine.freeValue(args);
    const result = try providers.invoke(reference.callback_id, args);
    defer engine.freeValue(result);
    var length: i32 = 0;
    try std.testing.expect(c.JS_ToInt32(engine.context, &length, result) == 0);
    try std.testing.expectEqual(@as(i32, 3), length);
}
