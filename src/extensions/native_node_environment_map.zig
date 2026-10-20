// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! The embedding host's explicit MapKVStore. The actual C++ owner supplies
//! native string temporaries, table growth and iteration; no Zig hash table
//! approximates those operations. No process-global environment is used.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;

pub const ValueVisitor = *const fn (?*anyopaque, [*]const u8, usize) callconv(.c) void;
pub const KeysVisitor = *const fn (?*anyopaque, *Keys) callconv(.c) void;

pub const Store = opaque {
    pub fn create(engine: *js.Engine) *Store {
        return pi_node_environment_map_create(engine.native_memory_owner, engine.context);
    }
    pub fn fromEnvironment(engine: *js.Engine,
        input: *const std.process.Environ.Map) *Store
    {
        const self = create(engine);
        var fields = input.iterator();
        while (fields.next()) |field|
            self.set(field.key_ptr.*, field.value_ptr.*);
        return self;
    }
    pub fn clone(self: *Store, engine: *js.Engine) *Store {
        return pi_node_environment_map_clone(self, engine.native_memory_owner, engine.context);
    }
    pub fn retain(self: *Store) *Store {
        pi_node_environment_map_retain(self);
        return self;
    }
    pub fn release(self: *Store) void {
        pi_node_environment_map_release(self);
    }

    /// The callback borrows the original optional native string after unlock.
    /// It must finish every use before returning; no extra copy is introduced.
    pub fn withValue(self: *Store, key: [*:0]const u8,
        visitor: ValueVisitor, user: ?*anyopaque) bool
    {
        return pi_node_environment_map_get(self, key, visitor, user) != 0;
    }
    /// The actual JS Get body also copies the optional into its local string.
    /// The intrinsic JS string producer runs while both native copies live.
    pub fn withJsValue(self: *Store, key: [*:0]const u8,
        visitor: ValueVisitor, user: ?*anyopaque) bool
    {
        return pi_node_environment_map_get_js(self, key, visitor, user) != 0;
    }
    pub fn query(self: *Store, key: [*:0]const u8) i32 {
        return pi_node_environment_map_query(self, key);
    }
    pub fn set(self: *Store, key: []const u8, value: []const u8) void {
        var selected = self.mutation();
        defer selected.deinit();
        selected.set(key, value);
    }
    pub fn delete(self: *Store, key: []const u8) void {
        var selected = self.mutation();
        defer selected.deinit();
        selected.delete(key);
    }
    /// Obtain after the genuine guest ToString operations, before both native
    /// Utf8Value conversions. Neither conversion may run guest code here.
    pub fn mutation(self: *Store) Mutation {
        pi_node_environment_map_lock(self);
        return .{ .store = self };
    }
    /// The synchronous visitor consumes the real native iterator under its
    /// retained mutex. All intrinsic vector/string/array work and retirement
    /// must finish before return. Neither Keys nor borrowed spans may escape.
    pub fn withKeys(self: *Store, visitor: KeysVisitor, user: ?*anyopaque) void {
        pi_node_environment_map_with_keys(self, visitor, user);
    }
};

pub const Mutation = struct {
    store: ?*Store,
    pub fn set(self: *Mutation, key: []const u8, value: []const u8) void {
        pi_node_environment_map_set_locked(self.store.?, key.ptr, key.len,
            value.ptr, value.len);
    }
    pub fn delete(self: *Mutation, key: []const u8) void {
        pi_node_environment_map_delete_locked(self.store.?, key.ptr, key.len);
    }
    pub fn deinit(self: *Mutation) void {
        const store = self.store orelse return;
        self.store = null;
        pi_node_environment_map_unlock(store);
    }
};

pub const Keys = opaque {
    pub fn count(self: *Keys) usize {
        return pi_node_environment_keys_count(self);
    }
    pub fn next(self: *Keys) ?[]const u8 {
        var bytes: [*]const u8 = undefined;
        var length: usize = undefined;
        if (pi_node_environment_keys_next(self, &bytes, &length) == 0) return null;
        return bytes[0..length];
    }
};

extern fn pi_node_environment_map_create(?*anyopaque, ?*c.JSContext) *Store;
extern fn pi_node_environment_map_clone(*Store, ?*anyopaque, ?*c.JSContext) *Store;
extern fn pi_node_environment_map_retain(*Store) void;
extern fn pi_node_environment_map_release(*Store) void;
extern fn pi_node_environment_map_get(*Store, [*:0]const u8, ValueVisitor, ?*anyopaque) c_int;
extern fn pi_node_environment_map_get_js(*Store, [*:0]const u8, ValueVisitor, ?*anyopaque) c_int;
extern fn pi_node_environment_map_query(*Store, [*:0]const u8) i32;
extern fn pi_node_environment_map_lock(*Store) void;
extern fn pi_node_environment_map_unlock(*Store) void;
extern fn pi_node_environment_map_set_locked(*Store, [*]const u8, usize, [*]const u8, usize) void;
extern fn pi_node_environment_map_delete_locked(*Store, [*]const u8, usize) void;
extern fn pi_node_environment_map_with_keys(*Store, KeysVisitor, ?*anyopaque) void;
extern fn pi_node_environment_keys_count(*Keys) usize;
extern fn pi_node_environment_keys_next(*Keys, *[*]const u8, *usize) c_int;
