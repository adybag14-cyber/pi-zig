// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Selected original options.cc serializers over the Engine's actual owned
//! startup configuration. These callables are private inputs to the genuine
//! JavaScript declarations; they do not publish a partial internalBinding.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const config = @import("native_node_options_config.zig");
const ChargedAllocator = @import("native_env_charged_allocator.zig").ChargedAllocator;
const functions = @import("native_node_module_callable.zig");
const check_failure = @import("native_node_check_failure.zig");
pub const Exports = struct { values: c.JSValue, embedder: c.JSValue };
fn known(engine: *a.v.em.Engine) !*config.Config {
    return engine.node_options orelse return error.ActualNodeOptionsConfigurationRequired;
}
// An actual OOM occurrence belongs only to the immediately enclosed raw
// intrinsic. A failed result with no new occurrence keeps its ordinary reason
// (including string length RangeError). No Error DATA or historical tag is read.
const IntrinsicAllocation = struct {
    generation: u64,
    occurrence: u64,
    fn begin(s: *Scope) !IntrinsicAllocation {
        const generation = try s.beforeAllocation();
        return .{ .generation = generation,
            .occurrence = c.JS_PiOutOfMemoryOccurrence(s.engine.runtime) };
    }
    fn check(self: IntrinsicAllocation, s: *Scope, failed: bool) void {
        if (failed and c.JS_PiOutOfMemoryOccurrence(s.engine.runtime) != self.occurrence)
            check_failure.heapOutOfMemory(s.engine, null);
    }
    fn value(self: IntrinsicAllocation, s: *Scope, result: c.JSValue) !c.JSValue {
        self.check(s, c.JS_IsException(result));
        return s.checkedAllocation(result, self.generation);
    }
};
fn nativeText(s: *Scope, bytes: []const u8) !c.JSValue {
    const allocation = try IntrinsicAllocation.begin(s);
    return allocation.value(s, c.JS_NewStringLen(s.engine.context, bytes.ptr, bytes.len));
}
// These builders only receive freshly created intrinsic records/arrays and
// primitive names produced here. No guest property lookup, setter or coercion
// can enter this native serializer tail.
fn nativeDefine(s: *Scope, target: c.JSValue, name: c.JSValue, value: c.JSValue) !void {
    const atom_allocation = try IntrinsicAllocation.begin(s);
    const property = c.JS_ValueToAtom(s.engine.context, name);
    atom_allocation.check(s, property == c.JS_ATOM_NULL);
    s.boundary.checkPendingSince(atom_allocation.generation) catch |err| {
        c.JS_FreeAtom(s.engine.context, property);
        return err;
    };
    defer c.JS_FreeAtom(s.engine.context, property);
    if (property == c.JS_ATOM_NULL) return error.MissingActualNodeOptionsNameReason;
    const allocation = try IntrinsicAllocation.begin(s);
    const status = c.JS_DefinePropertyValue(s.engine.context, target, property,
        a.duplicate(s.engine, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW);
    allocation.check(s, status < 0);
    try s.boundary.checkPendingSince(allocation.generation);
    if (status < 0) return error.MissingActualNodeOptionsDefinitionReason;
}
fn nativeObject(s: *Scope, names: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    std.debug.assert(names.len == values.len);
    const allocation = try IntrinsicAllocation.begin(s);
    const result = try allocation.value(s, c.JS_NewObjectProto(s.engine.context, c.pi_js_null()));
    for (names, values) |name, value| try nativeDefine(s, result, name, value);
    return result;
}
fn allocateHandles(s: *Scope, memory: *ChargedAllocator, count: usize) ![]c.JSValue {
    try s.pending();
    return memory.allocator().alloc(c.JSValue, count) catch |err| {
        // This is the actual native vector allocation failure, selected before
        // any prior vector/root retirement. It is not a DATA classification.
        if (err == error.OutOfMemory)
            @as(anyerror!void, s.boundary.rejectOwned(s.engine.throwNativeOutOfMemoryFatal())) catch {};
        return err;
    };
}
const NativeFields = struct {
    memory: ChargedAllocator,
    names: []c.JSValue = &.{},
    values: []c.JSValue = &.{},
    length: usize = 0,
    fn init(self: *NativeFields, s: *Scope, capacity: usize) !void {
        self.* = .{ .memory = ChargedAllocator.init(s.engine) };
        errdefer self.deinit();
        // Original LocalVectors reserve names first, then values. The entries
        // are borrowed from the caller-stable Scope until the final Object.
        self.names = try allocateHandles(s, &self.memory, capacity);
        self.values = try allocateHandles(s, &self.memory, capacity);
    }
    fn deinit(self: *NativeFields) void {
        self.memory.allocator().free(self.values);
        self.memory.allocator().free(self.names);
        self.memory.deinit();
    }
    fn append(self: *NativeFields, s: *Scope, name: []const u8, value: c.JSValue) !void {
        std.debug.assert(self.length < self.names.len);
        self.names[self.length] = try nativeText(s, name);
        self.values[self.length] = value;
        self.length += 1;
    }
    fn object(self: *NativeFields, s: *Scope) !c.JSValue {
        return nativeObject(s, self.names[0..self.length], self.values[0..self.length]);
    }
};
fn strings(s: *Scope, input: []const []const u8) !c.JSValue {
    var memory = ChargedAllocator.init(s.engine);
    defer memory.deinit();
    const elements = try allocateHandles(s, &memory, input.len);
    defer memory.allocator().free(elements);
    // ToV8Value(StringVector) creates each string before the intrinsic Array.
    for (input, elements) |value, *element| element.* = try nativeText(s, value);
    const allocation = try IntrinsicAllocation.begin(s);
    // JS_NewArrayFrom consumes every supplied value on success and failure;
    // duplicate the rooted native elements only immediately before that call.
    for (elements) |*element| element.* = a.duplicate(s.engine, element.*);
    return allocation.value(s, c.JS_NewArrayFrom(s.engine.context,
        @intCast(elements.len), elements.ptr));
}
fn fieldValue(s: *Scope, values: *const config.Values, comptime entry: config.Entry) !c.JSValue {
    const input = @field(values, @tagName(entry.field));
    return switch (comptime entry.kind) {
        .boolean => a.boolean(s, input),
        .optional_boolean => a.boolean(s, input orelse return error.ActualNodeStripTypesBuildDefaultRequired),
        .string => nativeText(s, input),
        .string_list => strings(s, input),
    };
}
fn boolean(s: *Scope, fields: *NativeFields, comptime name: [:0]const u8, value: bool) !void {
    // Original GetCLIOptionsValues stages the negated entry before the Boolean.
    try fields.append(s, "--no" ++ name[1..], a.boolean(s, !value));
    try fields.append(s, name, a.boolean(s, value));
}
fn bootstrapReason(s: *Scope) !c.JSValue {
    // Exact ERR_OPTIONS_BEFORE_BOOTSTRAPPING(Error) macro: intrinsic Error,
    // own message, then the actual live code Set before the explicit throw.
    const code = try s.text("ERR_OPTIONS_BEFORE_BOOTSTRAPPING");
    const message = try s.text("Should not query options before bootstrapping is done");
    const allocation = try s.beforeAllocation();
    const reason = try s.checkedAllocation(c.JS_NewError(s.engine.context), allocation);
    try s.define(reason, "message", message, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    // V8 Object::Set uses kDontThrow: a normal false assignment still returns
    // normally. An empty Maybe reaches the actual native .Check() termination
    // before pending capture or any caller-owned operand retirement.
    const key = try s.text("code");
    try s.pending();
    const status = c.JS_SetPropertyValue(s.engine.context, reason,
        c.JS_DupValue(s.engine.context, key), c.JS_DupValue(s.engine.context, code), 0);
    if (status < 0) check_failure.maybeCheck(s.engine, null);
    try s.pending();
    return reason;
}
fn valuesBody(s: *Scope, cached_names: []const c.JSValue) !c.JSValue {
    const owner = try known(s.engine);
    if (!owner.bootstrapped) {
        // THROW_ERR is a void native helper. The actual throw is escrowed by
        // this same boundary while only the intrinsic native tail continues.
        @as(anyerror!void, a.raise(s, try bootstrapReason(s))) catch {};
    }
    owner.serialized = true;
    var fields: NativeFields = undefined;
    try fields.init(s, (config.entries.len + 7) * 2);
    defer fields.deinit();
    // Original kV8Option special case: one native Boolean, without a
    // synthesized --no-* dictionary entry. This reads the Environment latch.
    try fields.append(s, "--abort-on-uncaught-exception", a.boolean(s, owner.values.abort_on_uncaught_exception));
    inline for (config.entries) |entry| {
        if (comptime entry.kind == .boolean or entry.kind == .optional_boolean) {
            const value = @field(owner.values, @tagName(entry.field));
            try boolean(s, &fields, entry.name,
                if (comptime entry.kind == .boolean) value
                else value orelse return error.ActualNodeStripTypesBuildDefaultRequired);
        } else {
            const value = try fieldValue(s, &owner.values, entry);
            try fields.append(s, entry.name, value);
        }
    }
    // The compile-disabled QUIC option is kNoOp, whose value is undefined;
    // only the actual enabled Boolean option gets a --no-* companion.
    if (owner.original.features.quic) {
        try boolean(s, &fields, "--experimental-quic", owner.values.experimental_quic);
    } else try fields.append(s, "--experimental-quic", c.pi_js_undefined());
    try boolean(s, &fields, "--inspect", owner.values.inspector_enabled);
    try boolean(s, &fields, "--inspect-brk", owner.values.inspect_brk);
    try boolean(s, &fields, "--inspect-brk-node", owner.values.inspect_brk_node);
    try boolean(s, &fields, "--inspect-wait", owner.values.inspect_wait);
    const host = try nativeText(s, owner.values.inspect_host);
    const host_names = [_]c.JSValue{ cached_names[0], cached_names[1] };
    const host_values = [_]c.JSValue{ host, c.JS_NewInt32(s.engine.context, owner.values.inspect_port) };
    const host_port = try nativeObject(s, &host_names, &host_values);
    try fields.append(s, "--inspect-port", host_port);
    const output = try fields.object(s);
    return a.duplicate(s.engine, output);
}
fn valuesCallback(engine: *a.v.em.Engine, _: c.JSValue, _: *@import("native_sync_arguments.zig").Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, valuesBody, .{roots});
}
fn embedderBody(s: *Scope) !c.JSValue {
    const owner = try known(s.engine);
    if (!owner.bootstrapped) @as(anyerror!void, a.raise(s, try bootstrapReason(s))) catch {};
    // Original fixed names and primitive values are all produced before the
    // final intrinsic null-prototype Object. This binding has no serialized flag.
    const names = [_]c.JSValue{
        try nativeText(s, "shouldNotRegisterESMLoader"),
        try nativeText(s, "noGlobalSearchPaths"),
        try nativeText(s, "noBrowserGlobals"),
        try nativeText(s, "hasEmbedderPreload"),
    };
    const source = owner.original.embedder;
    const values = [_]c.JSValue{
        a.boolean(s, source.should_not_register_esm_loader),
        a.boolean(s, source.no_global_search_paths or !owner.values.global_search_paths),
        a.boolean(s, source.no_browser_globals),
        a.boolean(s, source.has_embedder_preload),
    };
    return a.duplicate(s.engine, try nativeObject(s, &names, &values));
}
fn embedderCallback(engine: *a.v.em.Engine, _: c.JSValue, _: *@import("native_sync_arguments.zig").Arguments, _: []const c.JSValue) !c.JSValue {
    return a.expression(engine, embedderBody, .{});
}
pub fn create(engine: *a.v.em.Engine) !Exports {
    var s = Scope.init(engine);
    var outputs = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined() };
    var failure: ?anyerror = null;
    createBody(&s, &outputs) catch |err| { failure = err; };
    try s.boundary.finishMany(failure, &s.values, &outputs);
    return .{ .values = outputs[0], .embedder = outputs[1] };
}
fn createBody(s: *Scope, outputs: *[2]c.JSValue) !void {
    _ = try known(s.engine);
    // These are the original cached Environment names. Their private callable
    // owns them from binding bootstrap, before any serializer invocation.
    const cached_names = [_]c.JSValue{ try s.text("host"), try s.text("port") };
    const values = try s.own(try functions.createWithArguments(s.engine, "getCLIOptionsValues", 0, false,
        .{ .formal_count = 0, .callback = valuesCallback }, &cached_names));
    const embedder = try s.own(try functions.createWithArguments(s.engine, "getEmbedderOptions", 0, false,
        .{ .formal_count = 0, .callback = embedderCallback }, &.{}));
    outputs.* = .{ a.duplicate(s.engine, values), a.duplicate(s.engine, embedder) };
}
