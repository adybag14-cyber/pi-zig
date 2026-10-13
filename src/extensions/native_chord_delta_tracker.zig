//! Real Source TrackerImpl/ChangeImpl/PreparedImpl ownership and lifecycle.
//! Proxy storage, mutators and operation emission are native modules below.
const std = @import("std");
pub const values = @import("native_chord_values.zig");
pub const js = values.js;
pub const c = js.c;
pub const Scope = values.Scope;
pub const tree = @import("native_chord_delta_tracker_pieces.zig");
const overlay = @import("native_chord_delta_tracker_overlay.zig");
const emitter = @import("native_chord_delta_tracker_emit.zig");
pub const Status = enum { open, prepared, consumed, aborted, stale };
pub const Kind = enum(usize) { tracker, change, prepared, context, node_ref };
pub const ParentKind = enum { object, base, insert };
pub const OverrideMap = std.AutoArrayHashMapUnmanaged(usize, c.JSValue);
pub const Source = struct { values: []c.JSValue, overrides: OverrideMap = .empty };
pub const Array = struct {
    pieces: tree.Tree,
    sources: std.ArrayList(Source) = .empty,
    overrides: OverrideMap = .empty,
};
pub const Node = struct {
    context: *Context,
    index: usize,
    base: c.JSValue,
    parent: ?usize,
    parent_kind: ParentKind,
    parent_key: c.JSValue,
    parent_source: ?usize,
    placement: bool,
    target: c.JSValue,
    proxy: c.JSValue,
    reference: c.JSValue,
    write_key: c.JSValue,
    write_value: c.JSValue,
    writes: c.JSValue,
    delete_key: c.JSValue,
    deletes: c.JSValue,
    readded: c.JSValue,
    array: ?Array = null,
    dirty: bool = false,
    subtree_dirty: bool = false,
    path: c.JSValue,
    retired_next: ?*Node = null,
};
pub const Context = struct {
    instance: *Instance,
    self: c.JSValue,
    tracker: c.JSValue,
    owner: c.JSValue,
    base_revision: f64,
    status: Status = .open,
    root: ?*Node = null,
    nodes: std.ArrayList(*Node) = .empty,
    dirty: std.ArrayList(*Node) = .empty,
    raw_nodes: c.JSValue,
    ops: c.JSValue,
    replacement: bool,
    replacement_noop: bool = false,
    base_value: c.JSValue,
    released: bool = false,
    simple_materialization: bool = false,
    registry_ref: c.JSValue,
    steps: usize = 0,
    active_depth: usize = 0,
    retired_nodes: ?*Node = null,
    pub fn engine(self: *Context) *js.Engine {
        return self.instance.engine;
    }
    pub fn binding(self: *Context) *Binding {
        return self.instance.binding;
    }
};
/// Source JS locals keep contexts/nodes alive across reentrant guest callbacks.
/// The native lease provides that same lifetime without allocating a host root.
pub const Lease = struct {
    context: *Context,
    owner: c.JSValue,
    pub fn init(context: *Context) Lease {
        context.active_depth += 1;
        return .{ .context = context, .owner = c.JS_DupValue(context.engine().context, context.self) };
    }
    pub fn deinit(self: *Lease) void {
        const engine = self.context.engine();
        self.context.active_depth -= 1;
        if (self.context.active_depth == 0) overlay.freeRetired(engine.gpa, self.context);
        engine.freeValue(self.owner);
    }
};
pub const Tracker = struct { owner: c.JSValue, contexts: c.JSValue, self_ref: c.JSValue, value: c.JSValue, revision: f64 = 0, prune_budget: usize = 256 };
pub const Change = struct { context: c.JSValue, prepared_context: c.JSValue, settled: bool = false };
pub const Prepared = struct { context: c.JSValue };
pub const NodeRef = struct { context: c.JSValue, index: usize };
pub const Instance = struct {
    engine: *js.Engine,
    binding: *Binding,
    binding_value: c.JSValue,
    data: union(Kind) { tracker: Tracker, change: Change, prepared: Prepared, context: Context, node_ref: NodeRef },
};
pub const Binding = struct {
    engine: *js.Engine,
    self: c.JSValue,
    ids: [5]c.JSClassID,
    prototypes: [3]c.JSValue,
    constructors: [3]c.JSValue,
    node_symbol: c.JSValue,
    handler: c.JSValue,
    mutators: c.JSValue,
    sort_class: c.JSClassID = 0,
};
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn replace(engine: *js.Engine, destination: *c.JSValue, value: c.JSValue) void {
    const next = c.JS_DupValue(engine.context, value);
    engine.freeValue(destination.*);
    destination.* = next;
}
pub fn errorMessage(engine: *js.Engine, message: [*:0]const u8) anyerror {
    const text = engine.checked(c.JS_NewString(engine.context, message)) catch |err| return err;
    defer engine.freeValue(text);
    const failure = js.builtin(engine, "Error", &.{text}) catch |err| return err;
    _ = engine.checked(c.JS_Throw(engine.context, failure)) catch |err| return err;
    unreachable;
}
pub fn settled(context: *Context) bool {
    return context.released or context.status == .consumed or context.status == .aborted or context.status == .stale;
}
pub fn readable(context: *Context) !void {
    if (settled(context)) return js.typeError(context.engine(), "Cannot use a settled overlay");
}
pub fn writable(context: *Context) !void {
    try readable(context);
    if (context.status != .open) return js.typeError(context.engine(), "Prepared overlays are read-only");
}
pub fn tick(context: *Context) !void {
    context.steps +|= 1;
    const engine = context.engine();
    if (engine.cancelled.load(.acquire) or (context.steps % 256 == 0 and blk: {
        engine.interrupts +|= 1;
        break :blk engine.interrupts > engine.options.interrupt_budget;
    })) _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
}
pub fn contextOf(engine: *js.Engine, value: c.JSValue, binding: *Binding) !*Context {
    const instance: *Instance = @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, value, binding.ids[@intFromEnum(Kind.context)]) orelse return js.capture(engine)));
    return &instance.data.context;
}
pub fn nodeOf(engine: *js.Engine, reference: c.JSValue, binding: *Binding) !*Node {
    if (c.JS_IsUndefined(reference)) return js.typeError(engine, "Cannot use a settled overlay");
    const instance: *Instance = @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, reference, binding.ids[@intFromEnum(Kind.node_ref)]) orelse return js.capture(engine)));
    const context = try contextOf(engine, instance.data.node_ref.context, binding);
    try readable(context);
    return context.nodes.items[instance.data.node_ref.index];
}
pub fn getInstance(engine: *js.Engine, object: c.JSValue, binding: *Binding, kind: Kind) !*Instance {
    return @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, object, binding.ids[@intFromEnum(kind)]) orelse return js.capture(engine)));
}
pub fn createInstance(engine: *js.Engine, binding: *Binding, kind: Kind, prototype: c.JSValue, data: @FieldType(Instance, "data")) !c.JSValue {
    var owned = data;
    var transferred = false;
    errdefer if (!transferred) dispose(engine.runtime, engine.gpa, &owned);
    const result = try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, binding.ids[@intFromEnum(kind)]));
    errdefer engine.freeValue(result);
    const state = try engine.gpa.create(Instance);
    state.* = .{ .engine = engine, .binding = binding, .binding_value = c.JS_DupValue(engine.context, binding.self), .data = owned };
    if (kind == .context) {
        state.data.context.instance = state;
        state.data.context.self = result;
    }
    _ = c.JS_SetOpaque(result, state);
    transferred = true;
    return result;
}
fn releaseContext(context: *Context) !void {
    if (c.JS_IsUndefined(context.registry_ref)) return;
    const engine = context.engine();
    const tracker_value = try js.invoke(engine, context.tracker, "deref", &.{});
    defer engine.freeValue(tracker_value);
    if (!c.JS_IsUndefined(tracker_value)) {
        const state = try getInstance(engine, tracker_value, context.binding(), .tracker);
        const ignored = try js.invoke(engine, state.data.tracker.contexts, "delete", &.{context.registry_ref});
        engine.freeValue(ignored);
    }
    replace(engine, &context.registry_ref, c.pi_js_undefined());
}
pub fn clearContext(context: *Context, clear_targets: bool) !void {
    try releaseContext(context);
    context.released = true;
    try overlay.clear(context, clear_targets);
    replace(context.engine(), &context.raw_nodes, c.pi_js_undefined());
    replace(context.engine(), &context.ops, c.pi_js_undefined());
    replace(context.engine(), &context.base_value, c.pi_js_undefined());
    context.root = null;
}
fn abortContext(context: *Context) !void {
    if (context.status == .aborted or context.status == .consumed or context.status == .stale) return;
    context.status = .aborted;
    var lease = Lease.init(context);
    defer lease.deinit();
    try clearContext(context, true);
}
fn createContext(engine: *js.Engine, tracker_instance: *Instance, root: c.JSValue, replacement: bool) !c.JSValue {
    const tracker_state = &tracker_instance.data.tracker;
    const binding = tracker_instance.binding;
    const raw = try js.builtin(engine, "WeakMap", &.{});
    const object = try createInstance(engine, binding, .context, c.pi_js_null(), .{ .context = .{ .instance = undefined, .self = undefined, .tracker = c.JS_DupValue(engine.context, tracker_state.self_ref), .owner = c.JS_DupValue(engine.context, tracker_state.owner), .base_revision = tracker_state.revision, .raw_nodes = raw, .ops = c.pi_js_undefined(), .registry_ref = c.pi_js_undefined(), .replacement = replacement, .base_value = c.JS_DupValue(engine.context, tracker_state.value) } });
    errdefer engine.freeValue(object);
    const state = try getInstance(engine, object, binding, .context);
    const context = &state.data.context;
    context.instance = state;
    context.self = object;
    context.root = try overlay.createNode(context, root, null, .object, c.pi_js_undefined(), null, false);
    return object;
}
fn registerContext(engine: *js.Engine, tracker_state: *Tracker, context_value: c.JSValue, binding: *Binding) !void {
    const reference = try js.builtin(engine, "WeakRef", &.{context_value});
    defer engine.freeValue(reference);
    const context = try contextOf(engine, context_value, binding);
    replace(engine, &context.registry_ref, reference);
    const ignored = try js.invoke(engine, tracker_state.contexts, "add", &.{reference});
    engine.freeValue(ignored);
    tracker_state.prune_budget -= 1;
    if (tracker_state.prune_budget != 0) return;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const iterator_symbol = try scope.get(try scope.keep(try js.global(engine, "Symbol")), "iterator");
    var iterator = try js.Iterator.init(engine, tracker_state.contexts, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        const live = try js.invoke(engine, entry, "deref", &.{});
        defer engine.freeValue(live);
        if (c.JS_IsUndefined(live)) {
            const removed = try js.invoke(engine, tracker_state.contexts, "delete", &.{entry});
            engine.freeValue(removed);
        }
    }
    const size = try scope.get(tracker_state.contexts, "size");
    var count: u32 = 0;
    if (c.JS_ToUint32(engine.context, &count, size) < 0) return js.capture(engine);
    tracker_state.prune_budget = @max(256, count);
}
fn materialize(context: *Context) !c.JSValue {
    var lease = Lease.init(context);
    defer lease.deinit();
    const engine = context.engine();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const operations = try scope.keep(try emitter.ensureOperations(context));
    try readable(context);
    const base = try scope.keep(c.JS_DupValue(engine.context, context.base_value));
    const value = if (try @import("native_values.zig").length(engine, operations) == 0) base else if (context.simple_materialization) try scope.keep(try overlay.cloneNode(context.root.?, false)) else try scope.keep(try @import("native_durable_view_delta.zig").apply(engine, base, operations));
    const prepared = try scope.keep(try createInstance(engine, context.binding(), .prepared, context.binding().prototypes[2], .{ .prepared = .{ .context = c.JS_DupValue(engine.context, context.self) } }));
    try js.define(engine, prepared, "value", c.JS_DupValue(engine.context, value));
    try js.define(engine, prepared, "base", c.JS_DupValue(engine.context, base));
    try js.define(engine, prepared, "ops", c.JS_DupValue(engine.context, operations));
    try clearContext(context, context.nodes.items.len <= 4096);
    return scope.result(prepared);
}
const Op = enum(c_int) { tracker_value, tracker_revision, begin, prepare_replace, adopt, release_context, replacement_base, change_state, prepare, change_abort, base_revision, prepared_abort };
fn method(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    const binding: *Binding = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], c.JS_GetClassID(data[0])).?));
    return invoke(engine, binding, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn invoke(engine: *js.Engine, binding: *Binding, receiver: c.JSValue, args: []const c.JSValue, operation: Op) !c.JSValue {
    if (operation == .base_revision or operation == .prepared_abort) {
        const state = try getInstance(engine, receiver, binding, .prepared);
        const context = try contextOf(engine, state.data.prepared.context, binding);
        if (operation == .base_revision) return c.JS_NewFloat64(engine.context, context.base_revision);
        try abortContext(context);
        return c.pi_js_undefined();
    }
    if (@intFromEnum(operation) >= @intFromEnum(Op.change_state)) {
        const state = try getInstance(engine, receiver, binding, .change);
        const change = &state.data.change;
        if (operation == .change_abort) {
            if (change.settled) {
                if (!c.JS_IsUndefined(change.prepared_context)) {
                    const context = try contextOf(engine, change.prepared_context, binding);
                    if (context.status == .prepared) context.status = .aborted;
                    replace(engine, &change.prepared_context, c.pi_js_undefined());
                }
                return c.pi_js_undefined();
            }
            change.settled = true;
            const context = try contextOf(engine, change.context, binding);
            try abortContext(context);
            replace(engine, &change.context, c.pi_js_undefined());
            return c.pi_js_undefined();
        }
        if (operation == .change_state) {
            if (c.JS_IsUndefined(change.context)) return js.typeError(engine, "Cannot use a settled overlay");
            const context = try contextOf(engine, change.context, binding);
            return if (context.root) |root| c.JS_DupValue(engine.context, root.proxy) else js.typeError(engine, "Cannot use a settled overlay");
        }
        if (change.settled) return errorMessage(engine, "Change has already been settled");
        const context_owner = c.JS_DupValue(engine.context, change.context);
        defer engine.freeValue(context_owner);
        const context = try contextOf(engine, change.context, binding);
        try writable(context);
        context.status = .prepared;
        defer replace(engine, &change.context, c.pi_js_undefined());
        const prepared = materialize(context) catch |err| {
            context.status = .aborted;
            clearContext(context, true) catch {};
            change.settled = true;
            return err;
        };
        replace(engine, &change.prepared_context, change.context);
        change.settled = true;
        return prepared;
    }
    const state = try getInstance(engine, receiver, binding, .tracker);
    const tracker_state = &state.data.tracker;
    switch (operation) {
        .tracker_value => return c.JS_DupValue(engine.context, tracker_state.value),
        .tracker_revision => return c.JS_NewFloat64(engine.context, tracker_state.revision),
        .begin, .prepare_replace => {
            const context_value = try createContext(engine, state, if (operation == .begin) tracker_state.value else arg(args, 0), operation == .prepare_replace);
            defer engine.freeValue(context_value);
            const context = try contextOf(engine, context_value, binding);
            if (operation == .prepare_replace) context.status = .prepared;
            try registerContext(engine, tracker_state, context_value, binding);
            if (operation == .begin) return createInstance(engine, binding, .change, binding.prototypes[1], .{ .change = .{ .context = c.JS_DupValue(engine.context, context_value), .prepared_context = c.pi_js_undefined() } });
            return materialize(context) catch |err| {
                context.status = .aborted;
                clearContext(context, true) catch {};
                return err;
            };
        },
        .adopt => {
            const prepared = arg(args, 0);
            const private_state = c.JS_GetOpaque(prepared, binding.ids[@intFromEnum(Kind.prepared)]) orelse return errorMessage(engine, "Prepared change belongs to a different tracker");
            const prepared_state: *Instance = @ptrCast(@alignCast(private_state));
            const context = try contextOf(engine, prepared_state.data.prepared.context, binding);
            if (!c.JS_IsStrictEqual(engine.context, context.owner, tracker_state.owner)) return errorMessage(engine, "Prepared change belongs to a different tracker");
            switch (context.status) {
                .consumed => return errorMessage(engine, "Prepared change has already been used"),
                .aborted => return errorMessage(engine, "Prepared change has been aborted"),
                .stale => return errorMessage(engine, "Prepared change is stale"),
                .open => return errorMessage(engine, "Prepared change is not ready"),
                .prepared => {},
            }
            if (context.base_revision != tracker_state.revision) {
                context.status = .stale;
                try clearContext(context, true);
                return errorMessage(engine, "Prepared change is stale");
            }
            const base = try js.get(engine, prepared, "base");
            defer engine.freeValue(base);
            if (!c.JS_IsStrictEqual(engine.context, tracker_state.value, base)) {
                context.status = .stale;
                return errorMessage(engine, "Prepared change is stale");
            }
            const next = try js.get(engine, prepared, "value");
            defer engine.freeValue(next);
            // Reserve the native root vector before the Source authority swap.
            // Standard invalidation afterward performs no host allocation.
            var scope: Scope = .{ .engine = engine };
            defer scope.deinit();
            try scope.owned.ensureTotalCapacity(engine.gpa, 4);
            replace(engine, &tracker_state.value, next);
            context.status = .consumed;
            tracker_state.revision += 1;
            const symbol = try scope.get(try scope.keep(try js.global(engine, "Symbol")), "iterator");
            var iterator = try js.Iterator.init(engine, tracker_state.contexts, symbol);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |reference| {
                defer engine.freeValue(reference);
                const other_value = try js.invoke(engine, reference, "deref", &.{});
                defer engine.freeValue(other_value);
                if (c.JS_IsUndefined(other_value) or c.JS_IsStrictEqual(engine.context, other_value, context.self)) continue;
                const other = try contextOf(engine, other_value, binding);
                if (other.status == .open or other.status == .prepared) other.status = .stale;
                try clearContext(other, false);
            }
            const ignored = try js.invoke(engine, tracker_state.contexts, "clear", &.{});
            engine.freeValue(ignored);
            tracker_state.prune_budget = 256;
            return c.pi_js_undefined();
        },
        .replacement_base => {
            const revision = try js.get(engine, arg(args, 0), "baseRevision");
            defer engine.freeValue(revision);
            return if (c.JS_IsStrictEqual(engine.context, revision, c.JS_NewFloat64(engine.context, tracker_state.revision))) c.JS_DupValue(engine.context, tracker_state.value) else c.pi_js_undefined();
        },
        .release_context => {
            const value = arg(args, 0);
            const reference = try js.get(engine, value, "registryRef");
            defer engine.freeValue(reference);
            if (!c.JS_IsUndefined(reference)) {
                const ignored = try js.invoke(engine, tracker_state.contexts, "delete", &.{reference});
                engine.freeValue(ignored);
            }
            const key = try engine.checked(c.JS_NewString(engine.context, "registryRef"));
            defer engine.freeValue(key);
            try js.setKey(engine, value, key, c.pi_js_undefined());
            return c.pi_js_undefined();
        },
        else => unreachable,
    }
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    const binding: *Binding = @ptrCast(@alignCast(c.JS_GetOpaque(captures[0], c.JS_GetClassID(captures[0])).?));
    var index: u32 = 0;
    if (c.JS_ToUint32(engine.context, &index, captures[1]) < 0) return js.capture(engine);
    var prototype = try js.get(engine, target, "prototype");
    defer engine.freeValue(prototype);
    if (!c.JS_IsObject(prototype)) {
        const ordinary = try js.object(engine);
        defer engine.freeValue(ordinary);
        const fallback = try engine.checked(c.JS_GetPrototype(engine.context, ordinary));
        engine.freeValue(prototype);
        prototype = fallback;
    }
    if (index == 0) {
        var transferred = false;
        const owner = try js.object(engine);
        errdefer if (!transferred) engine.freeValue(owner);
        const contexts = try js.builtin(engine, "Set", &.{});
        errdefer if (!transferred) engine.freeValue(contexts);
        transferred = true;
        const object = try createInstance(engine, binding, .tracker, prototype, .{ .tracker = .{ .owner = owner, .contexts = contexts, .self_ref = c.pi_js_undefined(), .value = c.JS_DupValue(engine.context, arg(args, 0)) } });
        errdefer engine.freeValue(object);
        const state = try getInstance(engine, object, binding, .tracker);
        state.data.tracker.self_ref = try js.builtin(engine, "WeakRef", &.{object});
        return object;
    }
    _ = try contextOf(engine, arg(args, 0), binding);
    if (index == 1) return createInstance(engine, binding, .change, prototype, .{ .change = .{ .context = c.JS_DupValue(engine.context, arg(args, 0)), .prepared_context = c.pi_js_undefined() } });
    const object = try createInstance(engine, binding, .prepared, prototype, .{ .prepared = .{ .context = c.JS_DupValue(engine.context, arg(args, 0)) } });
    errdefer engine.freeValue(object);
    const context = try contextOf(engine, arg(args, 0), binding);
    try js.define(engine, object, "value", c.JS_DupValue(engine.context, arg(args, 1)));
    try js.define(engine, object, "base", c.JS_DupValue(engine.context, context.base_value));
    try js.define(engine, object, "ops", c.JS_DupValue(engine.context, arg(args, 2)));
    return object;
}
fn bindMethod(engine: *js.Engine, binding: *Binding, prototype: c.JSValue, name: [*:0]const u8, length: c_int, operation: Op, getter: bool) !void {
    var captures = [_]c.JSValue{binding.self};
    const getter_name = if (getter) try std.fmt.allocPrintSentinel(engine.gpa, "get {s}", .{std.mem.span(name)}, 0) else null;
    defer if (getter_name) |owned_name| engine.gpa.free(owned_name);
    const function_value = try engine.checked(c.JS_NewCFunctionData2(engine.context, method, if (getter_name) |owned_name| owned_name.ptr else name, length, @intFromEnum(operation), 1, &captures));
    if (!getter) {
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, function_value, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
        return;
    }
    const atom = c.JS_NewAtom(engine.context, name);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, function_value, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
pub fn bindings(engine: *js.Engine) !*Binding {
    if (engine.native_chord_delta_tracker_bindings) |value| return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    var holder_id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &holder_id);
    const holder_def: c.JSClassDef = .{ .class_name = "Native Chord Delta Bindings", .finalizer = bindingFinalizer, .gc_mark = bindingMark };
    if (c.JS_NewClass(engine.runtime, holder_id, &holder_def) < 0) return error.OutOfMemory;
    const holder = try engine.checked(c.JS_NewObjectClass(engine.context, holder_id));
    errdefer engine.freeValue(holder);
    const binding = try engine.gpa.create(Binding);
    binding.* = .{ .engine = engine, .self = holder, .ids = .{0} ** 5, .prototypes = .{c.pi_js_undefined()} ** 3, .constructors = .{c.pi_js_undefined()} ** 3, .node_symbol = c.pi_js_undefined(), .handler = c.pi_js_undefined(), .mutators = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(holder, binding);
    inline for (.{ "TrackerImpl", "ChangeImpl", "PreparedImpl", "Native Chord Overlay Context", "Native Chord Overlay Node" }, 0..) |name, index| {
        _ = c.JS_NewClassID(engine.runtime, &binding.ids[index]);
        const definition: c.JSClassDef = .{ .class_name = name, .finalizer = finalizer, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, binding.ids[index], &definition) < 0) return error.OutOfMemory;
    }
    const symbol_constructor = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol_constructor);
    const description = try engine.checked(c.JS_NewString(engine.context, "chord.delta.overlay.node"));
    defer engine.freeValue(description);
    binding.node_symbol = try js.call(engine, symbol_constructor, c.pi_js_undefined(), &.{description});
    inline for (.{ "TrackerImpl", "ChangeImpl", "PreparedImpl" }, 0..) |name, index| {
        binding.prototypes[index] = try js.object(engine);
        binding.constructors[index] = try @import("native_class.zig").constructor(engine, name, if (index == 2) 3 else 1, binding.prototypes[index], construct, &.{ holder, c.JS_NewUint32(engine.context, index) });
    }
    try bindMethod(engine, binding, binding.prototypes[0], "value", 0, .tracker_value, true);
    try bindMethod(engine, binding, binding.prototypes[0], "revision", 0, .tracker_revision, true);
    try bindMethod(engine, binding, binding.prototypes[0], "beginChange", 0, .begin, false);
    try bindMethod(engine, binding, binding.prototypes[0], "prepareReplace", 1, .prepare_replace, false);
    try bindMethod(engine, binding, binding.prototypes[0], "adopt", 1, .adopt, false);
    try bindMethod(engine, binding, binding.prototypes[0], "releaseContext", 1, .release_context, false);
    try bindMethod(engine, binding, binding.prototypes[0], "replacementBase", 1, .replacement_base, false);
    try bindMethod(engine, binding, binding.prototypes[1], "state", 0, .change_state, true);
    try bindMethod(engine, binding, binding.prototypes[1], "prepare", 0, .prepare, false);
    try bindMethod(engine, binding, binding.prototypes[1], "abort", 0, .change_abort, false);
    try bindMethod(engine, binding, binding.prototypes[2], "baseRevision", 0, .base_revision, true);
    try bindMethod(engine, binding, binding.prototypes[2], "abort", 0, .prepared_abort, false);
    binding.handler = try overlay.handler(engine, binding);
    binding.mutators = try @import("native_chord_delta_tracker_array.zig").functions(engine, binding);
    engine.native_chord_delta_tracker_bindings = holder;
    return binding;
}
pub fn track(engine: *js.Engine, initial: c.JSValue) !c.JSValue {
    const binding = try bindings(engine);
    return engine.checked(c.JS_CallConstructor(engine.context, binding.constructors[0], 1, @constCast(@as([]const c.JSValue, &.{initial}).ptr)));
}
fn trackCallback(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return track(engine, arg(args, 0));
}
pub fn function(engine: *js.Engine) !c.JSValue {
    _ = try bindings(engine);
    return @import("native_node_function.zig").create(engine, "track", 1, trackCallback, &.{});
}
fn bindingFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const binding: *Binding = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (binding.prototypes) |item| c.JS_FreeValueRT(runtime, item);
    for (binding.constructors) |item| c.JS_FreeValueRT(runtime, item);
    inline for (.{ "node_symbol", "handler", "mutators" }) |name| c.JS_FreeValueRT(runtime, @field(binding, name));
    binding.engine.gpa.destroy(binding);
}
fn bindingMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const binding: *Binding = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (binding.prototypes) |item| c.JS_MarkValue(runtime, item, visit);
    for (binding.constructors) |item| c.JS_MarkValue(runtime, item, visit);
    inline for (.{ "node_symbol", "handler", "mutators" }) |name| c.JS_MarkValue(runtime, @field(binding, name), visit);
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Instance = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    dispose(runtime, state.engine.gpa, &state.data);
    c.JS_FreeValueRT(runtime, state.binding_value);
    state.engine.gpa.destroy(state);
}
fn dispose(runtime: ?*c.JSRuntime, allocator: std.mem.Allocator, payload: *@FieldType(Instance, "data")) void {
    switch (payload.*) {
        .tracker => |data| {
            inline for (.{ "owner", "contexts", "self_ref", "value" }) |field| c.JS_FreeValueRT(runtime, @field(data, field));
        },
        .change => |data| {
            c.JS_FreeValueRT(runtime, data.context);
            c.JS_FreeValueRT(runtime, data.prepared_context);
        },
        .prepared => |data| c.JS_FreeValueRT(runtime, data.context),
        .node_ref => |data| c.JS_FreeValueRT(runtime, data.context),
        .context => |*data| {
            overlay.deinit(runtime, allocator, data);
            inline for (.{ "tracker", "owner", "raw_nodes", "ops", "base_value", "registry_ref" }) |field| c.JS_FreeValueRT(runtime, @field(data, field));
        },
    }
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Instance = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.binding_value, visit);
    switch (state.data) {
        .tracker => |data| {
            inline for (.{ "owner", "contexts", "self_ref", "value" }) |field| c.JS_MarkValue(runtime, @field(data, field), visit);
        },
        .change => |data| {
            c.JS_MarkValue(runtime, data.context, visit);
            c.JS_MarkValue(runtime, data.prepared_context, visit);
        },
        .prepared => |data| c.JS_MarkValue(runtime, data.context, visit),
        .node_ref => |data| c.JS_MarkValue(runtime, data.context, visit),
        .context => |*data| {
            inline for (.{ "tracker", "owner", "raw_nodes", "ops", "base_value", "registry_ref" }) |field| c.JS_MarkValue(runtime, @field(data, field), visit);
            overlay.mark(runtime, data, visit);
        },
    }
}
