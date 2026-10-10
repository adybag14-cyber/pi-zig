//! EventEmitterAsyncResource's native subclass and private constructor scope.
//! Async IDs belong to this engine's resource state; original owner tokens
//! remain private native references, never ordinary guest properties.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const events = @import("node_events.zig");
const scope = @import("native_async_scope.zig");
const Method = enum(c_int) { getConstructor, emit, emitDestroy, asyncId, triggerAsyncId, asyncResource, resourceAsyncId, resourceTriggerId, resourceRun, resourceDestroy, resourceEmitter, resourceBind, staticBind, bound, boundGet, boundSet, executionId };
const Kind = enum { emitter, referencing, base };
const Constructor = struct { engine: *js.Engine, state: c.JSValue, kind: Kind };
const Instance = struct { engine: *js.Engine, resource: c.JSValue };
const Resource = struct { engine: *js.Engine, emitter: c.JSValue, owner: c.JSValue, state: c.JSValue, id: c.JSValue, trigger: c.JSValue };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native EventEmitter resource: %s", @as([*:0]const u8, @errorName(err)));
}
fn constructorFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owned: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, owned.state);
    owned.engine.gpa.destroy(owned);
}
fn constructorMark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const owned: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, owned.state, marker);
}
fn instanceFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owned: *Instance = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, owned.resource);
    owned.engine.gpa.destroy(owned);
}
fn instanceMark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const owned: *Instance = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, owned.resource, marker);
}
fn resourceFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owned: *Resource = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ "emitter", "owner", "state", "id", "trigger" }) |name| c.JS_FreeValueRT(runtime, @field(owned, name));
    owned.engine.gpa.destroy(owned);
}
fn resourceMark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const owned: *Resource = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ "emitter", "owner", "state", "id", "trigger" }) |name| c.JS_MarkValue(runtime, @field(owned, name), marker);
}
fn constructorCall(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const owned: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) return c.JS_ThrowTypeError(context, "Class constructor %s cannot be invoked without 'new'", @as([*:0]const u8, switch (owned.kind) {
        .referencing => "EventEmitterReferencingAsyncResource",
        .emitter => "EventEmitterAsyncResource",
        .base => "AsyncResource",
    }));
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return (switch (owned.kind) {
        .emitter => createEmitter(engine, owned.state, function, target, args),
        .referencing => createResource(engine, owned.state, target, args),
        .base => createResource(engine, owned.state, target, &.{ c.pi_js_undefined(), v.arg(args, 0), v.arg(args, 1) }),
    }) catch |err| fail(engine, err);
}
fn constructor(engine: *js.Engine, state: c.JSValue, name: [*:0]const u8, prototype: c.JSValue, parent: c.JSValue, kind: Kind) !c.JSValue {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = name, .call = constructorCall, .finalizer = constructorFinalizer, .gc_mark = constructorMark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const function = try engine.checked(c.JS_NewObjectProtoClass(engine.context, parent, class));
    errdefer engine.freeValue(function);
    const owned = try engine.gpa.create(Constructor);
    owned.* = .{ .engine = engine, .state = c.JS_DupValue(engine.context, state), .kind = kind };
    _ = c.JS_SetOpaque(function, owned);
    _ = c.JS_SetConstructorBit(engine.context, function, true);
    if (c.JS_DefinePropertyValueStr(engine.context, function, "length", c.JS_NewInt32(engine.context, switch (kind) {
        .referencing => 3,
        .emitter => 0,
        .base => 1,
    }), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, function, "name", try engine.checked(c.JS_NewString(engine.context, name)), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, function, "prototype", c.JS_DupValue(engine.context, prototype), 0) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    return function;
}
fn makeFunction(engine: *js.Engine, state: c.JSValue, method: Method, name: [*:0]const u8, length: c_int) !c.JSValue {
    if (method == .getConstructor) return @import("native_node_function.zig").create(engine, name, length, constructorGetter, &.{state});
    var data = [_]c.JSValue{state};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, call, name, length, @intFromEnum(method), 1, &data));
}
fn constructorGetter(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    return js.get(engine, values[0], "constructor");
}
fn ordinaryBound(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    return operation(engine, values[0], receiver, .bound, args);
}
fn call(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return operation(engine, data[0], receiver, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| fail(engine, err);
}
fn classId(engine: *js.Engine, state: c.JSValue, name: [*:0]const u8) !c.JSClassID {
    return @intFromFloat(try v.numberField(engine, state, name));
}
fn emitterResource(engine: *js.Engine, state: c.JSValue, emitter: c.JSValue) !c.JSValue {
    const owned: *Instance = @ptrCast(@alignCast(c.JS_GetOpaque(emitter, try classId(engine, state, "emitterClass")) orelse {
        _ = try engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot read private member #asyncResource from an object whose class did not declare it"));
        unreachable;
    }));
    return c.JS_DupValue(engine.context, owned.resource);
}
fn resourceState(engine: *js.Engine, state: c.JSValue, value: c.JSValue) !*Resource {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, try classId(engine, state, "resourceClass")) orelse {
        _ = try engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot read private member #eventEmitter from an object whose class did not declare it"));
        unreachable;
    }));
}
fn privatePrototype(engine: *js.Engine, target: c.JSValue, class: c.JSClassID) !c.JSValue {
    const prototype = try js.get(engine, target, "prototype");
    defer engine.freeValue(prototype);
    return engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, class));
}
fn invalidString(engine: *js.Engine, value: c.JSValue, name: []const u8) anyerror {
    const received = try events.description(engine, value);
    defer engine.gpa.free(received);
    const message = try std.fmt.allocPrint(engine.gpa, "The \"{s}\" property must be of type string. Received {s}", .{ name, received });
    defer engine.gpa.free(message);
    return events.codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", message);
}
fn createEmitter(engine: *js.Engine, state: c.JSValue, function_value: c.JSValue, target: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var options = c.JS_DupValue(engine.context, v.arg(args, 0));
    defer engine.freeValue(options);
    var name = c.pi_js_undefined();
    defer engine.freeValue(name);
    if (c.JS_IsString(options)) {
        name = c.JS_DupValue(engine.context, options);
        engine.freeValue(options);
        options = c.pi_js_undefined();
    } else {
        if (c.JS_IsStrictEqual(engine.context, target, function_value)) {
            const checked_name = if (c.JS_IsNull(options) or c.JS_IsUndefined(options)) c.pi_js_undefined() else try js.get(engine, options, "name");
            defer engine.freeValue(checked_name);
            if (!c.JS_IsString(checked_name)) return invalidString(engine, checked_name, "options.name");
        }
        name = if (c.JS_IsNull(options) or c.JS_IsUndefined(options)) c.pi_js_undefined() else try js.get(engine, options, "name");
        if (!v.truthy(engine, name)) {
            engine.freeValue(name);
            name = try js.get(engine, target, "name");
        }
    }
    const emitter = try privatePrototype(engine, target, try classId(engine, state, "emitterClass"));
    errdefer engine.freeValue(emitter);
    const base = try js.get(engine, state, "base");
    defer engine.freeValue(base);
    const initialized = try js.call(engine, base, emitter, &.{options});
    engine.freeValue(initialized);
    const resource_constructor = try js.get(engine, state, "resourceConstructor");
    defer engine.freeValue(resource_constructor);
    const resource = try createResource(engine, state, resource_constructor, &.{ emitter, name, options });
    errdefer engine.freeValue(resource);
    const owned = try engine.gpa.create(Instance);
    owned.* = .{ .engine = engine, .resource = resource };
    _ = c.JS_SetOpaque(emitter, owned);
    return emitter;
}
fn createResource(engine: *js.Engine, state: c.JSValue, target: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const name = v.arg(args, 1);
    if (!c.JS_IsString(name)) return invalidString(engine, name, "type");
    const options = v.arg(args, 2);
    var trigger = if (c.JS_IsNumber(options)) c.JS_DupValue(engine.context, options) else if (c.JS_IsUndefined(options)) try js.get(engine, state, "currentId") else try js.get(engine, options, "triggerAsyncId");
    defer engine.freeValue(trigger);
    if (c.JS_IsUndefined(trigger)) {
        engine.freeValue(trigger);
        trigger = try js.get(engine, state, "currentId");
    }
    const trigger_number = if (c.JS_IsNumber(trigger)) try v.number(engine, trigger) else std.math.nan(f64);
    if (!std.math.isFinite(trigger_number) or @trunc(trigger_number) != trigger_number or @abs(trigger_number) > 9007199254740991 or trigger_number < -1) {
        const text = try engine.toString(trigger);
        defer engine.gpa.free(text);
        const message = try std.fmt.allocPrint(engine.gpa, "Invalid triggerAsyncId value: {s}", .{text});
        defer engine.gpa.free(message);
        return events.codedError(engine, "RangeError", "ERR_INVALID_ASYNC_ID", message);
    }
    if (!c.JS_IsUndefined(options) and !c.JS_IsNumber(options)) {
        const manual = try js.get(engine, options, "requireManualDestroy");
        engine.freeValue(manual);
    }
    const resource = try privatePrototype(engine, target, try classId(engine, state, "resourceClass"));
    errdefer engine.freeValue(resource);
    const id = try js.get(engine, state, "nextId");
    defer engine.freeValue(id);
    try v.set(engine, state, "nextId", v.numeric(engine, try v.number(engine, id) + 1));
    const owned = try engine.gpa.create(Resource);
    owned.* = .{ .engine = engine, .emitter = c.JS_DupValue(engine.context, v.arg(args, 0)), .owner = scope.capture(engine), .state = c.JS_DupValue(engine.context, state), .id = c.JS_DupValue(engine.context, id), .trigger = c.JS_DupValue(engine.context, trigger) };
    _ = c.JS_SetOpaque(resource, owned);
    inline for (.{ .{ "frameSymbol", "context_frame" }, .{ "idSymbol", "async_id_symbol" }, .{ "triggerSymbol", "trigger_async_id_symbol" } }) |entry| {
        const key = try js.get(engine, state, entry[0]);
        defer engine.freeValue(key);
        try js.setKey(engine, resource, key, if (comptime std.mem.eql(u8, entry[0], "idSymbol")) id else if (comptime std.mem.eql(u8, entry[0], "triggerSymbol")) trigger else c.pi_js_undefined());
    }
    return resource;
}
fn resourceField(engine: *js.Engine, state: c.JSValue, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const key = try js.get(engine, state, name);
    defer engine.freeValue(key);
    return js.getKey(engine, receiver, key);
}
fn deprecateBoundResource(engine: *js.Engine, holder: c.JSValue) !void {
    const state = try js.get(engine, holder, "warningState");
    defer engine.freeValue(state);
    const warned = try js.get(engine, state, "dep0172Warned");
    defer engine.freeValue(warned);
    if (v.truthy(engine, warned)) return;
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    if (c.JS_IsUndefined(process) or c.JS_IsNull(process)) return;
    const suppressed = try js.get(engine, process, "noDeprecation");
    defer engine.freeValue(suppressed);
    if (v.truthy(engine, suppressed)) return;
    const emit_warning = try js.get(engine, process, "emitWarning");
    defer engine.freeValue(emit_warning);
    if (!c.JS_IsFunction(engine.context, emit_warning)) return;
    const message = try v.text(engine, "The asyncResource property on bound functions is deprecated");
    defer engine.freeValue(message);
    const kind = try v.text(engine, "DeprecationWarning");
    defer engine.freeValue(kind);
    const code = try v.text(engine, "DEP0172");
    defer engine.freeValue(code);
    const returned = try js.call(engine, emit_warning, process, &.{ message, kind, code });
    engine.freeValue(returned);
    try v.set(engine, state, "dep0172Warned", c.pi_js_bool(engine.context, 1));
}
fn operation(engine: *js.Engine, state: c.JSValue, receiver: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    if (method == .getConstructor) return js.get(engine, state, "constructor");
    if (method == .executionId) return js.get(engine, state, "currentId");
    if (method == .boundGet) {
        try deprecateBoundResource(engine, state);
        return js.get(engine, state, "publicResource");
    }
    if (method == .boundSet) {
        try deprecateBoundResource(engine, state);
        try v.set(engine, state, "publicResource", c.JS_DupValue(engine.context, v.arg(args, 0)));
        return c.pi_js_undefined();
    }
    if (method == .bound) {
        const resource = try js.get(engine, state, "resource");
        defer engine.freeValue(resource);
        const callback = try js.get(engine, state, "callback");
        defer engine.freeValue(callback);
        const this_arg = try js.get(engine, state, "thisArg");
        defer engine.freeValue(this_arg);
        const values = try engine.gpa.alloc(c.JSValue, args.len + 2);
        defer engine.gpa.free(values);
        values[0] = callback;
        values[1] = if (c.JS_IsUndefined(this_arg)) receiver else this_arg;
        @memcpy(values[2..], args);
        const captured = try js.get(engine, state, "capturedRun");
        defer engine.freeValue(captured);
        return if (c.JS_IsUndefined(this_arg)) js.invoke(engine, resource, "runInAsyncScope", values) else js.call(engine, captured, resource, values);
    }
    if (method == .staticBind) {
        const callback = v.arg(args, 0);
        var type_value = c.JS_DupValue(engine.context, v.arg(args, 1));
        defer engine.freeValue(type_value);
        if (!v.truthy(engine, type_value)) {
            engine.freeValue(type_value);
            type_value = try js.get(engine, callback, "name");
        }
        if (!v.truthy(engine, type_value)) {
            engine.freeValue(type_value);
            type_value = try v.text(engine, "bound-anonymous-fn");
        }
        const base_constructor = try js.get(engine, state, "baseResourceConstructor");
        defer engine.freeValue(base_constructor);
        const resource = try createResource(engine, state, base_constructor, &.{ c.pi_js_undefined(), type_value, c.pi_js_undefined() });
        defer engine.freeValue(resource);
        return js.invoke(engine, resource, "bind", &.{ callback, v.arg(args, 2) });
    }
    if (method == .emit or method == .emitDestroy or method == .asyncId or method == .triggerAsyncId or method == .asyncResource) {
        const resource = try emitterResource(engine, state, receiver);
        defer engine.freeValue(resource);
        if (method == .asyncResource) return c.JS_DupValue(engine.context, resource);
        if (method == .asyncId or method == .triggerAsyncId) return js.invoke(engine, resource, if (method == .asyncId) "asyncId" else "triggerAsyncId", &.{});
        if (method == .emitDestroy) {
            const returned = try js.invoke(engine, resource, "emitDestroy", &.{});
            engine.freeValue(returned);
            return c.pi_js_undefined();
        }
        const base_prototype = try js.get(engine, state, "basePrototype");
        defer engine.freeValue(base_prototype);
        const emit = try js.get(engine, base_prototype, "emit");
        defer engine.freeValue(emit);
        const values = try engine.gpa.alloc(c.JSValue, args.len + 2);
        defer engine.gpa.free(values);
        values[0] = emit;
        values[1] = receiver;
        @memcpy(values[2..], args);
        return js.invoke(engine, resource, "runInAsyncScope", values);
    }
    const owned = try resourceState(engine, state, receiver);
    switch (method) {
        .resourceAsyncId => return resourceField(engine, state, receiver, "idSymbol"),
        .resourceTriggerId => return resourceField(engine, state, receiver, "triggerSymbol"),
        .resourceEmitter => return c.JS_DupValue(engine.context, owned.emitter),
        .resourceDestroy => return c.JS_DupValue(engine.context, receiver),
        .resourceRun => {
            const prior = try js.get(engine, state, "currentId");
            defer engine.freeValue(prior);
            try v.set(engine, state, "currentId", try resourceField(engine, state, receiver, "idSymbol"));
            defer v.set(engine, state, "currentId", c.JS_DupValue(engine.context, prior)) catch {};
            const guard = scope.enter(engine, owned.owner);
            defer guard.restore();
            // Source Node resources restore the constructor's context; they
            // do not revoke pure JS or process-global operations when a Pi
            // session retires. Pi/ctx bindings enforce their own original
            // snapshot fences when the callback actually invokes them.
            return js.call(engine, v.arg(args, 0), v.arg(args, 1), if (args.len > 2) args[2..] else &.{});
        },
        .resourceBind => {
            const callback = v.arg(args, 0);
            if (!c.JS_IsFunction(engine.context, callback)) {
                const received = try events.description(engine, callback);
                defer engine.gpa.free(received);
                const message = try std.fmt.allocPrint(engine.gpa, "The \"fn\" argument must be of type function. Received {s}", .{received});
                defer engine.gpa.free(message);
                return events.codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", message);
            }
            const holder = try js.object(engine);
            defer engine.freeValue(holder);
            try js.define(engine, holder, "resource", c.JS_DupValue(engine.context, receiver));
            try js.define(engine, holder, "warningState", c.JS_DupValue(engine.context, state));
            try js.define(engine, holder, "publicResource", c.JS_DupValue(engine.context, receiver));
            try js.define(engine, holder, "callback", c.JS_DupValue(engine.context, callback));
            try js.define(engine, holder, "thisArg", c.JS_DupValue(engine.context, v.arg(args, 1)));
            const run_function = if (c.JS_IsUndefined(v.arg(args, 1))) c.pi_js_undefined() else try js.get(engine, receiver, "runInAsyncScope");
            defer engine.freeValue(run_function);
            try js.define(engine, holder, "capturedRun", c.JS_DupValue(engine.context, run_function));
            const bound = if (c.JS_IsUndefined(v.arg(args, 1))) try @import("native_node_function.zig").create(engine, "bound", 0, ordinaryBound, &.{holder}) else blk: {
                const bind = try js.get(engine, state, "functionBind");
                defer engine.freeValue(bind);
                break :blk try js.call(engine, bind, run_function, &.{ receiver, callback, v.arg(args, 1) });
            };
            errdefer engine.freeValue(bound);
            if (c.JS_DefinePropertyValueStr(engine.context, bound, "length", try js.get(engine, callback, "length"), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
            const atom = c.JS_NewAtom(engine.context, "asyncResource");
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, bound, atom, try makeFunction(engine, holder, .boundGet, "deprecated", 0), try makeFunction(engine, holder, .boundSet, "deprecated", 0), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
            return bound;
        },
        else => unreachable,
    }
}
pub fn install(engine: *js.Engine, emitter: c.JSValue, base_prototype: c.JSValue) !c.JSValue {
    const state = try js.object(engine);
    defer engine.freeValue(state);
    try js.define(engine, state, "base", c.JS_DupValue(engine.context, emitter));
    try js.define(engine, state, "basePrototype", c.JS_DupValue(engine.context, base_prototype));
    try js.define(engine, state, "currentId", c.JS_NewInt32(engine.context, 0));
    try js.define(engine, state, "nextId", c.JS_NewInt32(engine.context, 1));
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    inline for (.{ .{ "frameSymbol", "context_frame" }, .{ "idSymbol", "async_id_symbol" }, .{ "triggerSymbol", "trigger_async_id_symbol" } }) |entry| {
        const name = try v.text(engine, entry[1]);
        defer engine.freeValue(name);
        try js.define(engine, state, entry[0], try js.call(engine, symbol, c.pi_js_undefined(), &.{name}));
    }
    var emitter_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &emitter_class);
    const emitter_definition: c.JSClassDef = .{ .class_name = "EventEmitterAsyncResource", .finalizer = instanceFinalizer, .gc_mark = instanceMark };
    if (c.JS_NewClass(engine.runtime, emitter_class, &emitter_definition) < 0) return error.OutOfMemory;
    try js.define(engine, state, "emitterClass", c.JS_NewUint32(engine.context, emitter_class));
    var resource_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &resource_class);
    const resource_definition: c.JSClassDef = .{ .class_name = "EventEmitterReferencingAsyncResource", .finalizer = resourceFinalizer, .gc_mark = resourceMark };
    if (c.JS_NewClass(engine.runtime, resource_class, &resource_definition) < 0) return error.OutOfMemory;
    try js.define(engine, state, "resourceClass", c.JS_NewUint32(engine.context, resource_class));
    const function_value = try js.global(engine, "Function");
    defer engine.freeValue(function_value);
    const function_prototype = try js.get(engine, function_value, "prototype");
    defer engine.freeValue(function_prototype);
    try js.define(engine, state, "functionBind", try js.get(engine, function_prototype, "bind"));
    const base_resource_prototype = try js.object(engine);
    defer engine.freeValue(base_resource_prototype);
    const base_resource_constructor = try constructor(engine, state, "AsyncResource", base_resource_prototype, function_prototype, .base);
    defer engine.freeValue(base_resource_constructor);
    try js.define(engine, state, "baseResourceConstructor", c.JS_DupValue(engine.context, base_resource_constructor));
    if (c.JS_DefinePropertyValueStr(engine.context, base_resource_constructor, "bind", try makeFunction(engine, state, .staticBind, "bind", 3), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (.{ .{ "runInAsyncScope", Method.resourceRun, 2 }, .{ "emitDestroy", Method.resourceDestroy, 0 }, .{ "asyncId", Method.resourceAsyncId, 0 }, .{ "triggerAsyncId", Method.resourceTriggerId, 0 }, .{ "bind", Method.resourceBind, 1 } }) |entry| {
        if (c.JS_DefinePropertyValueStr(engine.context, base_resource_prototype, entry[0], try makeFunction(engine, state, entry[1], entry[0], entry[2]), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const resource_prototype = try engine.checked(c.JS_NewObjectProto(engine.context, base_resource_prototype));
    defer engine.freeValue(resource_prototype);
    const resource_constructor = try constructor(engine, state, "EventEmitterReferencingAsyncResource", resource_prototype, base_resource_constructor, .referencing);
    defer engine.freeValue(resource_constructor);
    try js.define(engine, state, "resourceConstructor", c.JS_DupValue(engine.context, resource_constructor));
    const resource_emitter_atom = c.JS_NewAtom(engine.context, "eventEmitter");
    defer c.JS_FreeAtom(engine.context, resource_emitter_atom);
    if (c.JS_DefinePropertyGetSet(engine.context, resource_prototype, resource_emitter_atom, try makeFunction(engine, state, .resourceEmitter, "get eventEmitter", 0), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, base_prototype));
    defer engine.freeValue(prototype);
    const result = try constructor(engine, state, "EventEmitterAsyncResource", prototype, emitter, .emitter);
    errdefer engine.freeValue(result);
    try js.define(engine, state, "constructor", c.JS_DupValue(engine.context, result));
    inline for (.{ .{ "emit", Method.emit, 1 }, .{ "emitDestroy", Method.emitDestroy, 0 } }) |entry| if (c.JS_DefinePropertyValueStr(engine.context, prototype, entry[0], try makeFunction(engine, state, entry[1], entry[0], entry[2]), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (.{ .{ "asyncId", Method.asyncId }, .{ "triggerAsyncId", Method.triggerAsyncId }, .{ "asyncResource", Method.asyncResource } }) |entry| {
        const atom = c.JS_NewAtom(engine.context, entry[0]);
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, try makeFunction(engine, state, entry[1], "get " ++ entry[0], 0), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
    const atom = c.JS_NewAtom(engine.context, "EventEmitterAsyncResource");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, emitter, atom, try makeFunction(engine, state, .getConstructor, "lazyEventEmitterAsyncResource", 0), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    return result;
}
/// Test/native-host observation without pretending to implement node:async_hooks.
pub fn executionIdFunction(engine: *js.Engine) !c.JSValue {
    const exports = engine.native_module_values.get("node:events").?;
    const constructor_value = try js.get(engine, exports, "EventEmitterAsyncResource");
    defer engine.freeValue(constructor_value);
    const owned: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(constructor_value, c.JS_GetClassID(constructor_value)).?));
    return makeFunction(engine, owned.state, .executionId, "executionAsyncId", 0);
}
