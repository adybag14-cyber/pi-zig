//! Actual Node24.13 AsyncWrap and request FunctionTemplate owners.
//! This private graph supplies real template instances and the three native
//! AsyncWrap API methods. FileHandle's callback/StreamBase template is separate.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const native = @import("native_node_async_wrap_state.zig");
const callable = @import("native_node_module_callable.zig");
const publication = @import("native_node_fs_private_publication.zig");
const fs_io = @import("native_node_fs_request_io.zig");
const fs_callback = @import("native_node_fs_request_callback.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
pub const Engine = native.Engine;
pub const Environment = native.Environment;
pub const Registry = native.Registry;
pub const State = native.State;
pub const Kind = native.Kind;
pub const Provider = native.Provider;
const Scope = a.Scope;
const cache_key = "\x00native.node.AsyncWrap.actual-templates.v24.13";

const Bundle = struct {
    engine: *Engine,
    registry: *Registry,
    constructors: [6]?c.JSValue = .{ null, null, null, null, null, null },
    cached_instances: [6]?c.JSValue = .{ null, null, null, null, null, null },
    fs_callback_controller: ?*fs_io.Controller = null,
    constructor_class: c.JSClassID = 0,
};
const Constructor = struct {
    registry: *Registry,
    owner: c.JSValue,
    kind: Kind,
};
fn bundleOf(engine: *Engine, known_owner: c.JSValue) !*Bundle {
    const raw = c.JS_GetOpaque(known_owner, c.JS_GetClassID(known_owner)) orelse
        return error.ActualAsyncWrapTemplateOwnerRequired;
    const self: *Bundle = @ptrCast(@alignCast(raw));
    if (self.engine != engine) return error.ActualAsyncWrapEnvironmentMismatch;
    return self;
}
fn bundleFinalizer(runtime: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const self: *Bundle = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    _ = c.JS_SetOpaque(owner, null);
    const registry_owner = self.registry;
    for (&self.cached_instances) |*slot| if (slot.*) |value| {
        slot.* = null;
        c.JS_FreeValueRT(runtime, value);
    };
    for (&self.constructors) |*slot| if (slot.*) |value| {
        slot.* = null;
        c.JS_FreeValueRT(runtime, value);
    };
    if (self.fs_callback_controller) |controller| {
        self.fs_callback_controller = null;
        controller.release();
    }
    registry_owner.environment.allocator().destroy(self);
    registry_owner.release();
}
fn bundleMark(runtime: ?*c.JSRuntime, owner: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *Bundle = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    for (self.cached_instances) |slot| if (slot) |value| c.JS_MarkValue(runtime, value, marker);
    for (self.constructors) |slot| if (slot) |value| c.JS_MarkValue(runtime, value, marker);
}
fn constructorFinalizer(runtime: ?*c.JSRuntime, function: c.JSValue) callconv(.c) void {
    const self: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)) orelse return));
    _ = c.JS_SetOpaque(function, null);
    const registry_owner = self.registry;
    c.JS_FreeValueRT(runtime, self.owner);
    registry_owner.environment.allocator().destroy(self);
    registry_owner.release();
}
fn constructorMark(runtime: ?*c.JSRuntime, function: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)) orelse return));
    c.JS_MarkValue(runtime, self.owner, marker);
}
fn callConstructor(_: ?*c.JSContext, function: c.JSValue, receiver_or_target: c.JSValue,
    argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue
{
    const self: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    const engine = self.registry.environment.requireEngine() catch return c.pi_js_exception();
    var scope = Scope.init(engine);
    return scope.finish(constructorBody(&scope, self, function, receiver_or_target,
        if (argc > 0) argv[0] else c.pi_js_undefined(),
        flags & c.JS_CALL_FLAG_CONSTRUCTOR != 0)) catch |err| callable.failure(engine, err, 0);
}
fn constructorBody(s: *Scope, self: *Constructor, function: c.JSValue,
    receiver_or_target: c.JSValue, first_argument: c.JSValue,
    constructing: bool) !c.JSValue
{
    try s.pending();
    try s.engine.checkNativeEntry();
    if (constructing) {
        const owner = try bundleOf(s.engine, self.owner);
        const simple = c.JS_IsStrictEqual(s.engine.context, function, receiver_or_target);
        const receiver = try instantiate(s, owner, self.owner, self.kind,
            if (simple) null else receiver_or_target);
        if (self.kind == .fsreqcallback) {
            // NewFSReqCallback is a genuine present native callback. The
            // instance-template operation above did not invoke it.
            const controller = owner.fs_callback_controller orelse
                return error.ActualFSReqCallbackControllerRequired;
            const use_bigint = c.JS_IsBool(first_argument) and
                c.JS_ToBool(s.engine.context, first_argument) == 1;
            try fs_callback.Request.construct(s, owner.registry, controller,
                receiver, use_bigint);
        } else if (self.kind == .shutdownwrap) {
            // IsConstructCallCallback has no return assignment; constructor
            // invocation returns its actual receiver after ResetObject.
            try owner.registry.resetRequestObject(receiver);
        }
        return a.duplicate(s.engine, receiver);
    }
    // InvokeApiFunction converts its receiver before the present callback's
    // CHECK, including the primitive-boxing/global-receiver branches.
    const receiver = try convertedReceiver(s, receiver_or_target);
    if (self.kind == .fsreqcallback)
        check.assertion(s.engine, .{
            .file_line = "src/node_file.cc:727",
            .message = "args.IsConstructCall()",
            .function = "node::fs::NewFSReqCallback",
        });
    if (self.kind == .shutdownwrap)
        check.assertion(s.engine, .{
            .file_line = "src/stream_wrap.cc:62",
            .message = "args.IsConstructCall()",
            .function = "node::IsConstructCallCallback",
        });
    // V8's no-handler FunctionTemplate returns its actual converted receiver.
    // It is not the separate present-callback/empty-return-handle case.
    return a.duplicate(s.engine, receiver);
}
fn convertedReceiver(s: *Scope, receiver: c.JSValue) !c.JSValue {
    // InvokeApiFunction converts before signature admission. Keep any actual
    // boxed receiver in this call scope through the native callback.
    if (c.JS_IsObject(receiver)) return receiver;
    if (c.JS_IsNull(receiver) or c.JS_IsUndefined(receiver))
        return s.checked(c.JS_GetGlobalObject(s.engine.context));
    const generation = try s.beforeAllocation();
    return s.checkedAllocation(c.JS_ToObject(s.engine.context, receiver), generation);
}
fn name(kind: Kind) [:0]const u8 {
    return switch (kind) {
        .async_wrap => "AsyncWrap",
        .fsreqpromise => "FSReqPromise",
        .filehandleclosereq => "FileHandleCloseReq",
        .filehandle => "FileHandle",
        .fsreqcallback => "FSReqCallback",
        .shutdownwrap => "ShutdownWrap",
    };
}
fn requireTemplate(owner: *Bundle, kind: Kind) !void {
    if (kind == .filehandle) return error.ActualFileHandleCallbackTemplateRequired;
    if (kind == .fsreqcallback and owner.fs_callback_controller == null)
        return error.ActualFSReqCallbackControllerRequired;
}
fn markApi(s: *Scope, function: c.JSValue) !void {
    try s.pending();
    const status = c.JS_PiMarkNativeApiFunction(s.engine.context, function);
    try s.pending();
    if (status < 0) return error.ActualNodeApiFunctionProvenanceRequired;
}
fn signature(s: *Scope, owner: *Bundle, receiver: c.JSValue) !?*State {
    // A plain object with the same prototype and a Proxy of a real instance
    // are not FunctionTemplate signature instances. A cleared real instance is.
    if (!owner.registry.hasTemplateBrand(receiver)) {
        return s.boundary.rejectOwned(c.JS_ThrowTypeError(s.engine.context, "Illegal invocation"));
    }
    return owner.registry.unwrap(receiver);
}
fn getAsyncId(engine: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, getAsyncIdBody, .{ receiver, roots[0] });
}
fn getAsyncIdBody(s: *Scope, receiver: c.JSValue, owner_value: c.JSValue) !c.JSValue {
    const converted_receiver = try convertedReceiver(s, receiver);
    const owner = try bundleOf(s.engine, owner_value);
    const state = try signature(s, owner, converted_receiver);
    return c.JS_NewFloat64(s.engine.context, if (state) |value| value.async_id else -1);
}
fn getProviderType(engine: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, getProviderTypeBody, .{ receiver, roots[0] });
}
fn getProviderTypeBody(s: *Scope, receiver: c.JSValue, owner_value: c.JSValue) !c.JSValue {
    const converted_receiver = try convertedReceiver(s, receiver);
    const owner = try bundleOf(s.engine, owner_value);
    const state = try signature(s, owner, converted_receiver);
    return c.JS_NewUint32(s.engine.context, if (state) |value| value.provider else Provider.none);
}
fn asyncReset(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, asyncResetBody, .{ receiver, args, roots[0] });
}
fn asyncResetBody(s: *Scope, receiver: c.JSValue, args: []const c.JSValue, owner_value: c.JSValue) !c.JSValue {
    const converted_receiver = try convertedReceiver(s, receiver);
    const owner = try bundleOf(s.engine, owner_value);
    // The API signature check happens before the native callback's CHECK.
    const state = try signature(s, owner, converted_receiver);
    const resource = a.arg(args, 0);
    if (!c.JS_IsObject(resource)) return owner.registry.check(.invalid_wrap_brand);
    const actual = state orelse return c.pi_js_undefined();
    const supplied_id = a.arg(args, 1);
    var async_id: f64 = -1;
    if (c.JS_IsNumber(supplied_id)) {
        try s.pending();
        const status = c.JS_ToFloat64(s.engine.context, &async_id, supplied_id);
        try s.pending();
        if (status < 0) return error.ActualAsyncIdNumberRequired;
    }
    try actual.reset(resource, async_id);
    return c.pi_js_undefined();
}
fn addMethod(s: *Scope, prototype: c.JSValue, owner_value: c.JSValue,
    method_name: [*:0]const u8, callback: callable.Callback) !void
{
    const method = try s.own(try callable.create(s.engine, method_name, 0, false, callback, &.{owner_value}));
    try markApi(s, method);
    try s.define(prototype, method_name, method, c.JS_PROP_C_W_E);
}
fn createConstructor(s: *Scope, owner: *Bundle, owner_value: c.JSValue, kind: Kind) !c.JSValue {
    try requireTemplate(owner, kind);
    // InstantiateFunction configures the prototype template before allocating
    // the API function. The parent template is instantiated at its real use.
    const prototype = try s.object();
    if (kind == .async_wrap) {
        try addMethod(s, prototype, owner_value, "getAsyncId", getAsyncId);
        try addMethod(s, prototype, owner_value, "asyncReset", asyncReset);
        try addMethod(s, prototype, owner_value, "getProviderType", getProviderType);
    } else {
        const parent = try ensureConstructor(s, owner, owner_value, .async_wrap);
        const parent_prototype = try s.get(parent, "prototype");
        if (!c.JS_IsObject(parent_prototype) and !c.JS_IsNull(parent_prototype))
            return owner.registry.check(.invalid_wrap_brand);
        try s.pending();
        const status = c.JS_SetPrototype(s.engine.context, prototype, parent_prototype);
        try s.pending();
        if (status < 0) return error.ActualAsyncWrapPrototypeInheritanceRequired;
    }
    const function_prototype = try s.checked(c.JS_GetFunctionProto(s.engine.context));
    const generation = try s.beforeAllocation();
    const function = try s.checkedAllocation(c.JS_NewObjectProtoClass(s.engine.context,
        function_prototype, owner.constructor_class), generation);
    const state = try owner.registry.environment.allocator().create(Constructor);
    state.* = .{ .registry = owner.registry.retain(), .owner = a.duplicate(s.engine, owner_value), .kind = kind };
    _ = c.JS_SetOpaque(function, state);
    _ = c.JS_SetConstructorBit(s.engine.context, function, true);
    try markApi(s, function);
    try s.define(function, "length", c.JS_NewInt32(s.engine.context, 0), c.JS_PROP_CONFIGURABLE);
    try s.define(function, "name", try s.text(name(kind)), c.JS_PROP_CONFIGURABLE);
    try s.define(prototype, "constructor", function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    try s.define(function, "prototype", prototype, c.JS_PROP_WRITABLE);
    return a.duplicate(s.engine, function);
}
fn ensureConstructor(s: *Scope, owner: *Bundle, owner_value: c.JSValue, kind: Kind) !c.JSValue {
    try requireTemplate(owner, kind);
    if (owner.constructors[@intFromEnum(kind)]) |existing| return existing;
    // Cache only the completed real function. A prior prototype lookup may
    // reenter; retain the completed winner before retiring this candidate.
    const candidate = try a.expression(s.engine, createConstructor, .{ owner, owner_value, kind });
    if (owner.constructors[@intFromEnum(kind)]) |existing| {
        var completion = a.owned.Completion.initValue(s.engine, a.duplicate(s.engine, existing));
        completion.release(candidate);
        const selected = try s.own(try completion.finishValue());
        return selected;
    }
    owner.constructors[@intFromEnum(kind)] = candidate;
    return candidate;
}
fn instantiate(s: *Scope, owner: *Bundle, owner_value: c.JSValue,
    kind: Kind, new_target: ?c.JSValue) !c.JSValue
{
    try requireTemplate(owner, kind);
    if (new_target) |target| {
        // Subclass construction does not use the simple-template object cache.
        const prototype = try s.checked(c.JS_PiGetObjectPrototypeFromConstructor(s.engine.context, target));
        return owner.registry.newInstance(s, kind, prototype);
    }
    if (owner.cached_instances[@intFromEnum(kind)]) |cached| {
        const prototype = try s.prototype(cached);
        return owner.registry.newInstance(s, kind, prototype);
    }
    const constructor_value = try ensureConstructor(s, owner, owner_value, kind);
    const prototype = try s.checked(c.JS_PiGetObjectPrototypeFromConstructor(s.engine.context, constructor_value));
    // CacheTemplateInstantiation retains the first actual object, then
    // CopyJSObject returns another with the same prototype and blank native
    // slots. ShutdownWrap also copies its three original null data fields;
    // Registry.newInstance installs those same attributes on every path.
    const first = try owner.registry.newInstance(s, kind, prototype);
    owner.cached_instances[@intFromEnum(kind)] = a.duplicate(s.engine, first);
    return owner.registry.newInstance(s, kind, prototype);
}
fn createBody(s: *Scope, environment: *Environment) !c.JSValue {
    const registry_owner = try Registry.create(s.engine, environment);
    var transferred = false;
    errdefer if (!transferred) registry_owner.release();
    const self = try environment.allocator().create(Bundle);
    errdefer if (!transferred) environment.allocator().destroy(self);
    self.* = .{ .engine = s.engine, .registry = registry_owner };
    var class_id: c.JSClassID = 0;
    const class_generation = try s.beforeAllocation();
    if (c.JS_NewClassID(s.engine.runtime, &class_id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Node AsyncWrap templates",
        .finalizer = bundleFinalizer, .gc_mark = bundleMark };
    if (c.JS_NewClass(s.engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
    if (c.JS_NewClassID(s.engine.runtime, &self.constructor_class) == 0) return error.OutOfMemory;
    const constructor_definition: c.JSClassDef = .{ .class_name = "Function",
        .finalizer = constructorFinalizer, .gc_mark = constructorMark, .call = callConstructor };
    if (c.JS_NewClass(s.engine.runtime, self.constructor_class, &constructor_definition) < 0)
        return error.OutOfMemory;
    try s.boundary.checkPendingSince(class_generation);
    const generation = try s.beforeAllocation();
    const owner = try s.checkedAllocation(c.JS_NewObjectProtoClass(s.engine.context, c.pi_js_null(), class_id), generation);
    _ = c.JS_SetOpaque(owner, self);
    transferred = true;
    // ObjectTemplate/FunctionTemplate construction itself has not instantiated
    // any realm function or instance yet. Those actual caches are lazy.
    return a.duplicate(s.engine, owner);
}
pub fn acquire(engine: *Engine, environment: *Environment) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |known| {
        const owner = try bundleOf(engine, known);
        if (owner.registry.environment != environment) return error.ActualAsyncWrapEnvironmentMismatch;
        return a.duplicate(engine, known);
    }
    const candidate = try a.expression(engine, createBody, .{environment});
    if (engine.native_module_values.get(cache_key)) |known| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, known));
        completion.release(candidate);
        const result = try completion.finishValue();
        const owner = bundleOf(engine, result) catch |err| { engine.freeValue(result); return err; };
        if (owner.registry.environment != environment) {
            engine.freeValue(result);
            return error.ActualAsyncWrapEnvironmentMismatch;
        }
        return result;
    }
    return publication.publish(engine, cache_key, candidate);
}
pub fn registry(engine: *Engine, known_owner: c.JSValue) !*Registry {
    return (try bundleOf(engine, known_owner)).registry;
}
pub fn constructor(engine: *Engine, known_owner: c.JSValue, kind: Kind) !c.JSValue {
    return a.expression(engine, constructorValue, .{ known_owner, kind });
}
fn constructorValue(s: *Scope, known_owner: c.JSValue, kind: Kind) !c.JSValue {
    const owner = try bundleOf(s.engine, known_owner);
    return a.duplicate(s.engine, try ensureConstructor(s, owner, known_owner, kind));
}
pub fn newInstance(engine: *Engine, known_owner: c.JSValue, kind: Kind) !c.JSValue {
    return a.expression(engine, newInstanceBody, .{ known_owner, kind });
}
fn newInstanceBody(s: *Scope, known_owner: c.JSValue, kind: Kind) !c.JSValue {
    return a.duplicate(s.engine, try instantiate(s, try bundleOf(s.engine, known_owner), known_owner, kind, null));
}

/// The genuine internal/fs assembler binds its already-acquired shared
/// Controller before exposing FSReqCallback or its stored InstanceTemplate.
/// This retains the actual native owner; it starts no new service/worker.
pub fn configureFSReqCallback(engine: *Engine, known_owner: c.JSValue,
    controller: *fs_io.Controller) !void
{
    const owner = try bundleOf(engine, known_owner);
    if (owner.registry.environment != controller.environment)
        return error.ActualFSReqCallbackEnvironmentMismatch;
    try controller.beginCall(engine);
    defer controller.endCall();
    if (owner.fs_callback_controller) |existing| {
        if (existing != controller) return error.ActualFSReqCallbackControllerMismatch;
        return;
    }
    owner.fs_callback_controller = controller.retain();
}

/// The exact template stored by node_file.cc is fst->InstanceTemplate(),
/// where fst is the genuine FSReqCallback callback template. Instantiating it
/// bypasses NewFSReqCallback while retaining that real prototype and brand.
/// Its JS locals belong to the caller's existing FileHandle HandleScope.
pub fn newFSReqCallbackInstance(s: *Scope, known_owner: c.JSValue) !c.JSValue {
    return instantiate(s, try bundleOf(s.engine, known_owner),
        known_owner, .fsreqcallback, null);
}

/// env->shutdown_wrap_template() stores the real ShutdownWrap InstanceTemplate.
/// StreamBase::Shutdown invokes ResetObject itself after this bypass operation.
pub fn newShutdownWrapInstance(s: *Scope, known_owner: c.JSValue) !c.JSValue {
    return instantiate(s, try bundleOf(s.engine, known_owner),
        known_owner, .shutdownwrap, null);
}
