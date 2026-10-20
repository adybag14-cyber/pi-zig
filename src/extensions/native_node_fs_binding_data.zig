//! Selected original Node24.13 fs::BindingData and Realm weak-pointer owner.
//! This is the native binding target's BaseObject, not an AsyncWrap: all real
//! request/handle objects share its Registry FIFO, but no init/destroy hook is
//! emitted for BindingData. The module assembler supplies the original target,
//! AsyncWrap template owner and cached promise string before guest admission.
//!
//! Native Global cells are a declared VM dependency. Their strong creation,
//! later weak transition, ordinary Local retrieval and reset must be the real
//! native weak-handle operations; public WeakRef is not used here. Snapshot
//! deserialization and the other internal/fs binding methods are separate.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const callbacks = @import("native_node_callback_scope.zig");
const native = @import("native_node_async_wrap_state.zig");
const templates = @import("native_node_async_wrap.zig");
const globals = @import("native_node_weak_global.zig");
const callable = @import("native_node_module_callable.zig");
const c = a.c;
pub const Engine = native.Engine;
const Scope = a.Scope;

/// The original internal binding ObjectTemplate has two native internal fields.
/// Its caller creates this actual target before BindingData construction. The
/// prototype input is the original object prototype selected by that bootstrap.
pub const TargetTemplate = struct {
    class_id: c.JSClassID,
    pub fn create(s: *Scope) !TargetTemplate {
        var class_id: c.JSClassID = 0;
        const generation = try s.beforeAllocation();
        if (c.JS_NewClassID(s.engine.runtime, &class_id) == 0)
            return error.OutOfMemory;
        const definition: c.JSClassDef = .{
            .class_name = "fs::BindingData", .finalizer = finalize,
        };
        const status = c.JS_NewClass(s.engine.runtime, class_id, &definition);
        try s.boundary.checkPendingSince(generation);
        if (status < 0) return error.OutOfMemory;
        return .{ .class_id = class_id };
    }
    pub fn newInstance(self: TargetTemplate, s: *Scope,
        actual_object_prototype: c.JSValue) !c.JSValue
    {
        const generation = try s.beforeAllocation();
        return s.checkedAllocation(c.JS_NewObjectProtoClass(s.engine.context,
            actual_object_prototype, self.class_id), generation);
    }
};

/// Each AliasedBuffer constructor has its own actual native HandleScope. It
/// drops the temporary ArrayBuffer/view before the next member constructor;
/// only the original Global remains. BindingData's four later GetJSArray
/// Locals instead live in the enclosing constructor scope through MakeWeak.
fn WeakAlias(comptime T: type, comptime kind: c.JSTypedArrayEnum) type {
    return struct {
        data: []T = &.{},
        global: ?globals.Global = null,
        const Self = @This();

        fn create(engine: *Engine, count: usize) !Self {
            var s = Scope.init(engine);
            var result: Self = .{};
            const ignored = s.finish(createBody(&s, count, &result)) catch |err| {
                var completion = a.owned.Completion.initVoid(engine, err);
                completion.release(c.pi_js_undefined());
                var cleanup = Scope.init(engine);
                result.release(&cleanup);
                finishEmpty(&cleanup) catch {};
                try completion.finishVoid();
                unreachable;
            };
            engine.freeValue(ignored);
            return result;
        }
        fn createBody(s: *Scope, count: usize, output: *Self) !c.JSValue {
            const bytes = std.math.mul(usize, count, @sizeOf(T)) catch return error.OutOfMemory;
            const allocation = try s.beforeAllocation();
            const buffer = try s.checkedAllocation(
                c.JS_NewArrayBufferCopy(s.engine.context, null, bytes), allocation);
            var actual_bytes: usize = 0;
            try s.pending();
            const raw = c.JS_GetArrayBuffer(s.engine.context, &actual_bytes, buffer);
            try s.pending();
            if (raw == null or actual_bytes != bytes)
                return error.ActualNodeAliasedBufferRequired;
            var args = [_]c.JSValue{buffer};
            const view_allocation = try s.beforeAllocation();
            const view = try s.checkedAllocation(c.JS_NewTypedArray(
                s.engine.context, 1, &args, kind), view_allocation);
            output.data = @as([*]T, @ptrCast(@alignCast(raw)))[0..count];
            output.global = try globals.Global.create(s, view);
            return c.pi_js_undefined();
        }
        fn local(self: *Self, s: *Scope) !c.JSValue {
            if (self.global) |*global| return global.get(s);
            return c.pi_js_undefined();
        }
        fn makeWeak(self: *Self, s: *Scope) !void {
            if (self.global) |*global| try global.makeWeak(s);
        }
        fn release(self: *Self, s: *Scope) void {
            self.data = &.{};
            if (self.global) |value| {
                self.global = null;
                var previous = value;
                previous.release(s);
            }
        }
    };
}
const Numbers = WeakAlias(f64, c.JS_TYPED_ARRAY_FLOAT64);
const BigInts = WeakAlias(i64, c.JS_TYPED_ARRAY_BIG_INT64);

/// Original BaseObject::PointerData is allocated lazily at the first native
/// weak/strong pointer. The Realm weak slot may outlive the actual BaseObject.
const PointerData = struct {
    environment: *callbacks.Environment,
    self: ?*BindingData,
    strong_count: c_uint = 0,
    weak_count: c_uint = 0,
    wants_weak: bool,
    detached: bool = false,

    fn releaseWeak(self: *PointerData) void {
        std.debug.assert(self.weak_count != 0);
        self.weak_count -= 1;
        if (self.weak_count != 0 or self.self != null) return;
        self.destroy();
    }
    fn destroy(self: *PointerData) void {
        const environment = self.environment;
        environment.allocator().destroy(self);
        environment.release();
    }
    fn getSlot(raw: *anyopaque) ?*anyopaque {
        const self: *PointerData = @ptrCast(@alignCast(raw));
        return if (self.self) |object| object else null;
    }
    fn releaseSlot(raw: *anyopaque) void {
        const self: *PointerData = @ptrCast(@alignCast(raw));
        self.releaseWeak();
    }
};

pub const BindingData = struct {
    registry: *native.Registry,
    environment: *callbacks.Environment,
    base_entry: native.BaseEntry,
    wrapper: ?c.JSValue,
    strong_wrapper: ?c.JSValue,
    weak_wrapper: bool = false,
    pointer_data: ?*PointerData = null,
    retiring: bool = false,
    // These are the actual Realm/template imports needed by its request
    // factory, held as independent native roots until BaseObject retirement.
    template_owner: c.JSValue,
    promise_string: c.JSValue,
    stats_field_array: Numbers = .{},
    stats_field_bigint_array: BigInts = .{},
    statfs_field_array: Numbers = .{},
    statfs_field_bigint_array: BigInts = .{},
    file_handle_read_wrap_freelist: std.ArrayList(*native.State) = .empty,

    /// The target and imports are borrowed caller-local handles. The target
    /// must stay alive throughout AddBindingData, just as the original Local.
    pub fn create(s: *Scope, shape: TargetTemplate, target: c.JSValue,
        template_owner: c.JSValue, promise_string: c.JSValue) !*BindingData
    {
        // AddBindingData has no inner HandleScope. Its native Local values
        // belong to the caller's actual binding-initialization scope.
        const registry = try templates.registry(s.engine, template_owner);
        var result: ?*BindingData = null;
        _ = try createBody(s, registry, shape, target,
            template_owner, promise_string, &result);
        return result.?;
    }
    fn createBody(s: *Scope, registry: *native.Registry, shape: TargetTemplate,
        target: c.JSValue, template_owner: c.JSValue, promise_string: c.JSValue,
        output: *?*BindingData) !c.JSValue
    {
        try s.pending();
        if (c.JS_GetClassID(target) != shape.class_id or
            c.JS_GetOpaque(target, shape.class_id) != null)
            return registry.check(.invalid_wrap_brand);
        if (!c.JS_IsString(promise_string))
            return error.ActualFSBindingPromiseStringRequired;
        const environment = registry.environment;
        const self = try environment.allocator().create(BindingData);
        self.* = .{
            .registry = registry.retain(), .environment = environment,
            .base_entry = .{ .raw = self, .delete_me = deleteBaseEntry },
            .wrapper = target, .strong_wrapper = a.duplicate(s.engine, target),
            .template_owner = a.duplicate(s.engine, template_owner),
            .promise_string = a.duplicate(s.engine, promise_string),
        };
        _ = c.JS_SetOpaque(target, self);
        // BaseObject's persistent/internal fields and FIFO publication precede
        // every derived alias constructor.
        registry.append(&self.base_entry);
        self.initializeMembers(s) catch |err| {
            var completion = a.owned.Completion.initVoid(s.engine, err);
            completion.release(c.pi_js_undefined());
            self.retire(false) catch {};
            try completion.finishVoid();
            unreachable;
        };
        // MakeWeakBaseObject: finish T's constructor, then weaken its wrapper,
        // then construct the temporary BaseObjectWeakPtr.
        self.makeWeak() catch |err| {
            var completion = a.owned.Completion.initVoid(s.engine, err);
            completion.release(c.pi_js_undefined());
            self.retire(false) catch {};
            try completion.finishVoid();
            unreachable;
        };
        const metadata = self.pointerData() catch |err| {
            var completion = a.owned.Completion.initVoid(s.engine, err);
            completion.release(c.pi_js_undefined());
            self.retire(false) catch {};
            try completion.finishVoid();
            unreachable;
        };
        metadata.weak_count += 1;
        defer metadata.releaseWeak(); // local item in Realm::AddBindingData
        if (registry.fs_binding_data) |previous| {
            if (previous.get(previous.raw) != null)
                return registry.check(.binding_data_slot_occupied);
            registry.fs_binding_data = null;
            previous.release(previous.raw);
        }
        // Actual weak-pointer copy assignment adds the stored entitlement.
        metadata.weak_count += 1;
        registry.fs_binding_data = .{
            .raw = metadata, .get = PointerData.getSlot,
            .release = PointerData.releaseSlot,
        };
        output.* = self;
        return c.pi_js_undefined();
    }
    fn initializeMembers(self: *BindingData, s: *Scope) !void {
        self.stats_field_array = try Numbers.create(s.engine, 36);
        self.stats_field_bigint_array = try BigInts.create(s.engine, 36);
        self.statfs_field_array = try Numbers.create(s.engine, 7);
        self.statfs_field_bigint_array = try BigInts.create(s.engine, 7);
        try self.setAlias(s, "statValues", &self.stats_field_array);
        try self.setAlias(s, "bigintStatValues", &self.stats_field_bigint_array);
        try self.setAlias(s, "statFsValues", &self.statfs_field_array);
        try self.setAlias(s, "bigintStatFsValues", &self.statfs_field_bigint_array);
        try self.stats_field_array.makeWeak(s);
        try self.stats_field_bigint_array.makeWeak(s);
        try self.statfs_field_array.makeWeak(s);
        try self.statfs_field_bigint_array.makeWeak(s);
    }
    fn setAlias(self: *BindingData, s: *Scope, name: []const u8, alias: anytype) !void {
        const key = try s.text(name);
        const value = try alias.local(s);
        const target = self.wrapper orelse return self.registry.check(.invalid_wrap_brand);
        try s.pending();
        const status = c.JS_SetPropertyValue(s.engine.context, target,
            a.duplicate(s.engine, key), a.duplicate(s.engine, value), 0);
        // V8 Maybe::Check fails on Nothing, not on a normal false Set.
        if (status < 0) return self.registry.check(.binding_data_property_set);
        try s.pending();
    }
    fn pointerData(self: *BindingData) !*PointerData {
        if (self.pointer_data) |data| return data;
        const data = try self.environment.allocator().create(PointerData);
        data.* = .{
            .environment = self.environment.retain(), .self = self,
            .wants_weak = self.weak_wrapper,
        };
        self.pointer_data = data;
        return data;
    }
    pub fn retainNative(self: *BindingData) !void {
        const data = try self.pointerData();
        const previous = data.strong_count;
        data.strong_count += 1;
        if (previous == 0 and self.wrapper != null) {
            const engine = try self.environment.requireEngine();
            if (self.strong_wrapper == null)
                self.strong_wrapper = a.duplicate(engine, self.wrapper.?);
            self.weak_wrapper = false;
        }
    }
    pub fn releaseNative(self: *BindingData) !void {
        const data = self.pointer_data orelse return self.registry.check(.invalid_wrap_brand);
        if (data.strong_count == 0) return self.registry.check(.invalid_wrap_brand);
        data.strong_count -= 1;
        if (data.strong_count != 0) return;
        if (data.detached) return self.retire(false);
        if (data.wants_weak and self.wrapper != null) return self.makeWeak();
    }
    pub fn makeWeak(self: *BindingData) !void {
        if (self.pointer_data) |data| {
            data.wants_weak = true;
            if (data.strong_count != 0) return;
        }
        const engine = try self.environment.requireEngine();
        var s = Scope.init(engine);
        self.weak_wrapper = true;
        var persistent = self.strong_wrapper orelse return finishEmpty(&s);
        self.strong_wrapper = null;
        // The actual weak callback may destroy self. No self access follows.
        s.boundary.release(&persistent);
        try finishEmpty(&s);
    }
    pub fn deleteMe(self: *BindingData) !void {
        if (self.pointer_data) |data| {
            if (data.strong_count != 0) {
                data.detached = true;
                return;
            }
        }
        return self.retire(false);
    }
    fn deleteBaseEntry(raw: *anyopaque) !void {
        const self: *BindingData = @ptrCast(@alignCast(raw));
        return self.deleteMe();
    }
    fn retire(self: *BindingData, from_gc: bool) !void {
        if (self.retiring) return;
        if (self.pointer_data) |data|
            if (data.strong_count != 0) return self.registry.check(.invalid_wrap_brand);
        self.retiring = true;
        const registry = self.registry;
        const environment = self.environment;
        const engine = try environment.requireEngine();
        if (from_gc) {
            std.debug.assert(self.strong_wrapper == null);
            if (self.wrapper) |wrapper| _ = c.JS_SetOpaque(wrapper, null);
            self.wrapper = null;
        }
        var s = Scope.init(engine);
        var failure: ?anyerror = null;
        // The selected request paths leave this original vector empty. Actual
        // FileHandleReadWrap entries, when present, own native BaseObjectPtrs.
        var free_list = self.file_handle_read_wrap_freelist;
        self.file_handle_read_wrap_freelist = .empty;
        for (free_list.items) |entry| {
            entry.releaseNative() catch |err| {
                s.boundary.escaping();
                if (failure == null) failure = err;
            };
        }
        free_list.deinit(environment.allocator());
        // Reverse derived-member destruction, before the BaseObject base.
        self.statfs_field_bigint_array.release(&s);
        self.statfs_field_array.release(&s);
        self.stats_field_bigint_array.release(&s);
        self.stats_field_array.release(&s);
        registry.unlink(&self.base_entry);
        if (self.pointer_data) |metadata| {
            self.pointer_data = null;
            metadata.self = null;
            if (metadata.weak_count == 0) metadata.destroy();
        }
        if (self.wrapper) |wrapper| _ = c.JS_SetOpaque(wrapper, null);
        self.wrapper = null;
        if (self.strong_wrapper) |value| {
            self.strong_wrapper = null;
            var persistent = value;
            s.boundary.release(&persistent);
        }
        s.boundary.release(&self.promise_string);
        s.boundary.release(&self.template_owner);
        environment.allocator().destroy(self);
        defer registry.release();
        const ignored = try s.finish(if (failure) |err|
            @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
        engine.freeValue(ignored);
    }
};

/// Exact selected Realm::GetBindingData weak-pointer copy. The returned native
/// pointer is borrowed; an asynchronous owner must immediately retainNative.
pub fn get(registry: *native.Registry) ?*BindingData {
    const slot = registry.fs_binding_data orelse return null;
    const metadata: *PointerData = @ptrCast(@alignCast(slot.raw));
    metadata.weak_count += 1;
    defer metadata.releaseWeak();
    return metadata.self;
}
fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *BindingData = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const engine = self.environment.requireEngine() catch return;
    self.retire(true) catch |err| { _ = callable.failure(engine, err, 0); };
}
fn finishEmpty(s: *Scope) !void {
    const engine = s.engine;
    const ignored = try s.finish(c.pi_js_undefined());
    engine.freeValue(ignored);
}
