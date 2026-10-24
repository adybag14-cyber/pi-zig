// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Complete FileHandle callback template and StreamBase::AddMethods.
//! Inputs are the real shared native owners. This does not create an fs binding,
//! worker, trace policy, allocation policy or replacement application bootstrap.
const a = @import("native_node_argument_values.zig");
const native = @import("native_node_async_wrap_state.zig");
const templates = @import("native_node_async_wrap.zig");
const binding = @import("native_node_fs_binding_data.zig");
const handle = @import("native_node_file_handle_owner.zig");
const read = @import("native_node_file_handle_read.zig");
const close_request = @import("native_node_file_handle_close_request.zig");
const io = @import("native_node_fs_request_io.zig");
const immediates = @import("native_node_native_immediates.zig");
const streams = @import("native_node_stream_base.zig");
const dispatch = @import("native_node_stream_js_dispatch.zig");
const callbacks = @import("native_node_async_wrap_make_callback.zig");
const callable = @import("native_node_module_callable.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
const Scope = a.Scope;
const Engine = native.Engine;

/// Controller and Queue are retained here. The native trace/allocation/report
/// owners are the embedding's original Environment-lifetime imports, as on
/// Handle.Inputs; no guest callable or invented retention contract replaces them.
pub const Inputs = struct {
    controller: *io.Controller,
    immediate_queue: *immediates.Queue,
    read_trace: read.Trace,
    close_trace: close_request.Trace,
    allocation: streams.Allocation,
    trace: callbacks.Trace,
    heap_diagnostics: ?*const check.Diagnostics,
};

/// Owned exclusively by the genuine AsyncWrap Bundle. template_owner is a
/// borrowed back-pointer, not another strong root or GC edge. Every concrete
/// Handle retains BindingData, whose actual native Global retains that Bundle
/// through all request completions. Callables and constructors also trace it.
pub const Owner = struct {
    registry: *native.Registry,
    template_owner: c.JSValue,
    inputs: Inputs,
    handle_string: c.JSValue,
    error_string: c.JSValue,
    oncomplete_string: c.JSValue,

    pub fn create(s: *Scope, registry: *native.Registry,
        template_owner: c.JSValue, inputs: Inputs) !*Owner
    {
        if ((try registry.environment.requireEngine()) != s.engine or
            inputs.controller.environment != registry.environment or
            inputs.immediate_queue.engine != s.engine)
            return error.ActualFileHandleTemplateEnvironmentMismatch;
        const data = binding.get(registry) orelse
            return error.ActualFileHandleRealmBindingDataRequired;
        if (!c.JS_IsStrictEqual(s.engine.context, data.template_owner, template_owner))
            return error.ActualFileHandleBindingTemplateMismatch;
        try inputs.controller.beginCall(s.engine);
        defer inputs.controller.endCall();

        // Actual primitive keys exist before any constructor/callback exposure.
        // Only this Bundle supplies the ShutdownWrap/WriteWrap template identity.
        const handle_string = try s.text("handle");
        const error_string = try s.text("error");
        const oncomplete_string = try s.text("oncomplete");
        try s.pending();
        const self = try registry.environment.allocator().create(Owner);
        self.* = .{
            .registry = registry, .template_owner = template_owner, .inputs = inputs,
            .handle_string = a.duplicate(s.engine, handle_string),
            .error_string = a.duplicate(s.engine, error_string),
            .oncomplete_string = a.duplicate(s.engine, oncomplete_string),
        };
        _ = inputs.controller.retain();
        _ = inputs.immediate_queue.retain();
        return self;
    }
    pub fn matches(self: *const Owner, other: Inputs) bool {
        const actual = self.inputs;
        return actual.controller == other.controller and
            actual.immediate_queue == other.immediate_queue and
            actual.read_trace.raw == other.read_trace.raw and
            actual.read_trace.begin_read == other.read_trace.begin_read and
            actual.read_trace.end_read == other.read_trace.end_read and
            actual.close_trace.raw == other.close_trace.raw and
            actual.close_trace.begin_sync == other.close_trace.begin_sync and
            actual.close_trace.end_sync == other.close_trace.end_sync and
            actual.close_trace.begin_async == other.close_trace.begin_async and
            actual.close_trace.end_async == other.close_trace.end_async and
            actual.allocation.raw == other.allocation.raw and
            actual.allocation.new_backing_store == other.allocation.new_backing_store and
            actual.trace.raw == other.trace.raw and
            actual.trace.before == other.trace.before and
            actual.trace.after == other.trace.after and
            actual.heap_diagnostics == other.heap_diagnostics;
    }
    pub fn mark(self: *const Owner, runtime: ?*c.JSRuntime,
        marker: ?*const c.JS_MarkFunc) void
    {
        c.JS_MarkValue(runtime, self.handle_string, marker);
        c.JS_MarkValue(runtime, self.error_string, marker);
        c.JS_MarkValue(runtime, self.oncomplete_string, marker);
    }
    pub fn destroy(self: *Owner, runtime: ?*c.JSRuntime) void {
        const registry = self.registry; // Bundle retains it until after this call.
        c.JS_FreeValueRT(runtime, self.oncomplete_string);
        c.JS_FreeValueRT(runtime, self.error_string);
        c.JS_FreeValueRT(runtime, self.handle_string);
        self.inputs.immediate_queue.release();
        self.inputs.controller.release();
        registry.environment.allocator().destroy(self);
    }
    pub fn nativeInputs(self: *const Owner) handle.Inputs {
        const request: streams.RequestBindings = .{
            .template_owner = self.template_owner,
            .error_string = self.error_string,
            .oncomplete_string = self.oncomplete_string,
        };
        return .{
            .controller = self.inputs.controller,
            .immediate_queue = self.inputs.immediate_queue,
            .handle_string = self.handle_string,
            .read_trace = self.inputs.read_trace,
            .close_trace = self.inputs.close_trace,
            .stream = .{
                .allocation = self.inputs.allocation, .trace = self.inputs.trace,
                .heap_diagnostics = self.inputs.heap_diagnostics,
                .shutdown = request,
                .write = .{ .request = request, .handle_string = self.handle_string },
                // FileHandle::IsIPCPipe is the original false virtual.
                .unwrap_send_handle = null,
            },
        };
    }
    pub fn construct(self: *Owner, s: *Scope, receiver: c.JSValue,
        args: []const c.JSValue) !void
    {
        try handle.Handle.construct(s, self.registry, receiver, args, true, self.nativeInputs());
    }
};

const Receiver = struct { registry: *native.Registry, value: c.JSValue };
fn signature(s: *Scope, receiver: c.JSValue, known_owner: c.JSValue) !Receiver {
    // InvokeApiFunction performs receiver conversion before Signature admission.
    // The concrete FileHandle template admits real derived instances, but neither
    // a Proxy nor another AsyncWrap kind nor a prototype-only imitation.
    const converted = if (c.JS_IsObject(receiver)) receiver else if
        (c.JS_IsNull(receiver) or c.JS_IsUndefined(receiver))
        try s.checked(c.JS_GetGlobalObject(s.engine.context)) else blk: {
            const generation = try s.beforeAllocation();
            break :blk try s.checkedAllocation(c.JS_ToObject(s.engine.context, receiver), generation);
        };
    const registry = try templates.registry(s.engine, known_owner);
    if (c.JS_GetClassID(converted) != registry.classId(.filehandle))
        return s.boundary.rejectOwned(c.JS_ThrowTypeError(s.engine.context, "Illegal invocation"));
    return .{ .registry = registry, .value = converted };
}
fn close(engine: *Engine, receiver: c.JSValue, _: []const c.JSValue,
    roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, closeBody, .{ receiver, roots[0] });
}
fn closeBody(s: *Scope, receiver: c.JSValue, known_owner: c.JSValue) !c.JSValue {
    const actual = try signature(s, receiver, known_owner);
    if (actual.registry.unwrap(actual.value) == null) return c.pi_js_undefined();
    return (try handle.Handle.fromObject(actual.registry, actual.value)).closePromise();
}
fn releaseFD(engine: *Engine, receiver: c.JSValue, _: []const c.JSValue,
    roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, releaseBody, .{ receiver, roots[0] });
}
fn releaseBody(s: *Scope, receiver: c.JSValue, known_owner: c.JSValue) !c.JSValue {
    const actual = try signature(s, receiver, known_owner);
    if (actual.registry.unwrap(actual.value) == null) return c.pi_js_undefined();
    // Release() returns a native descriptor; ReleaseFD deliberately has no
    // ReturnValue assignment. It performs AfterClose without a close syscall.
    _ = try (try handle.Handle.fromObject(actual.registry, actual.value)).releaseDescriptor(s);
    return c.pi_js_undefined();
}
fn method(comptime operation: dispatch.Method) callable.Callback {
    return struct {
        fn call(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue,
            roots: []const c.JSValue) !c.JSValue
        {
            return a.expression(engine, body, .{ receiver, args, roots[0] });
        }
        fn body(s: *Scope, receiver: c.JSValue, args: []const c.JSValue,
            known_owner: c.JSValue) !c.JSValue
        {
            const actual = try signature(s, receiver, known_owner);
            return dispatch.jsMethod(s, actual.registry, actual.value, operation, args);
        }
    }.call;
}
const Accessor = enum { fd, external_stream, bytes_read, bytes_written, onread };
fn getter(comptime accessor: Accessor) callable.Callback {
    return struct {
        fn call(engine: *Engine, receiver: c.JSValue, _: []const c.JSValue,
            roots: []const c.JSValue) !c.JSValue
        {
            return a.expression(engine, body, .{ receiver, roots[0] });
        }
        fn body(s: *Scope, receiver: c.JSValue, known_owner: c.JSValue) !c.JSValue {
            const actual = try signature(s, receiver, known_owner);
            return switch (accessor) {
                .fd => dispatch.getFD(s, actual.registry, actual.value),
                .external_stream => dispatch.getExternal(s, actual.registry, actual.value),
                .bytes_read => dispatch.getBytesRead(s, actual.registry, actual.value),
                .bytes_written => dispatch.getBytesWritten(s, actual.registry, actual.value),
                .onread => a.duplicate(s.engine,
                    try actual.registry.streamOnRead(s, actual.value)),
            };
        }
    }.call;
}
fn setOnRead(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, setOnReadBody, .{ receiver, args, roots[0] });
}
fn setOnReadBody(s: *Scope, receiver: c.JSValue, args: []const c.JSValue,
    known_owner: c.JSValue) !c.JSValue
{
    const actual = try signature(s, receiver, known_owner);
    const value = a.arg(args, 0);
    if (!c.JS_IsFunction(s.engine.context, value)) check.assertion(s.engine, .{
        .file_line = "src/base_object-inl.h:140",
        .message = "((*value)->*typecheck)()",
        .function = "node::BaseObject::InternalFieldSet",
    });
    // These are wrapper slots, even after its concrete native Handle is gone.
    try actual.registry.setStreamOnRead(s, actual.value, value);
    return c.pi_js_undefined();
}
fn api(s: *Scope, known_owner: c.JSValue, name: [*:0]const u8,
    callback: callable.Callback) !c.JSValue
{
    const function = try s.own(try callable.create(s.engine, name, 0, false,
        callback, &.{known_owner}));
    try s.pending();
    const status = c.JS_PiMarkNativeApiFunction(s.engine.context, function);
    try s.pending();
    if (status < 0) return error.ActualNodeApiFunctionProvenanceRequired;
    return function;
}
fn addMethod(s: *Scope, prototype: c.JSValue, known_owner: c.JSValue,
    name: [*:0]const u8, callback: callable.Callback) !void
{
    try s.define(prototype, name, try api(s, known_owner, name, callback), c.JS_PROP_C_W_E);
}
fn addAccessor(s: *Scope, prototype: c.JSValue, known_owner: c.JSValue,
    name: [*:0]const u8, callback: callable.Callback, setter: ?callable.Callback) !void
{
    // AddMethod/AddAccessor do not SetClassName on their function templates.
    // Getter/setter functions have the default empty name and length zero.
    const get = try api(s, known_owner, "", callback);
    const set = if (setter) |function| try api(s, known_owner, "", function) else c.pi_js_undefined();
    const generation = try s.beforeAllocation();
    const atom = c.JS_NewAtom(s.engine.context, name);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try s.boundary.checkPendingSince(generation);
    if (atom == c.JS_ATOM_NULL) return error.ActualFileHandleAccessorAtomRequired;
    try s.pending();
    const status = c.JS_DefinePropertyGetSet(s.engine.context, prototype, atom,
        a.duplicate(s.engine, get), a.duplicate(s.engine, set), c.JS_PROP_THROW);
    try s.pending();
    if (status < 0) return error.ActualFileHandleAccessorDefinitionRequired;
}

/// node_file.cc installs close/releaseFD before StreamBase::AddMethods. Own
/// prototype properties are instantiated before the parent prototype lookup.
pub fn installPrototype(s: *Scope, prototype: c.JSValue, known_owner: c.JSValue) !void {
    try addMethod(s, prototype, known_owner, "close", close);
    try addMethod(s, prototype, known_owner, "releaseFD", releaseFD);
    try addAccessor(s, prototype, known_owner, "fd", getter(.fd), null);
    try addAccessor(s, prototype, known_owner, "external_stream", getter(.external_stream), null);
    try addAccessor(s, prototype, known_owner, "bytesRead", getter(.bytes_read), null);
    try addAccessor(s, prototype, known_owner, "bytesWritten", getter(.bytes_written), null);
    try addMethod(s, prototype, known_owner, "readStart", method(.read_start));
    try addMethod(s, prototype, known_owner, "readStop", method(.read_stop));
    try addMethod(s, prototype, known_owner, "shutdown", method(.shutdown));
    try addMethod(s, prototype, known_owner, "useUserBuffer", method(.use_user_buffer));
    try addMethod(s, prototype, known_owner, "writev", method(.writev));
    try addMethod(s, prototype, known_owner, "writeBuffer", method(.write_buffer));
    try addMethod(s, prototype, known_owner, "writeAsciiString", method(.write_ascii_string));
    try addMethod(s, prototype, known_owner, "writeUtf8String", method(.write_utf8_string));
    try addMethod(s, prototype, known_owner, "writeUcs2String", method(.write_ucs2_string));
    try addMethod(s, prototype, known_owner, "writeLatin1String", method(.write_latin1_string));
    try s.define(prototype, "isStreamBase", c.pi_js_bool(s.engine.context, 1), c.JS_PROP_C_W_E);
    try addAccessor(s, prototype, known_owner, "onread", getter(.onread), setOnRead);
}
