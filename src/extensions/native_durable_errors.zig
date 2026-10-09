//! Source durable error classes. Failure causes remain original VM values;
//! reporting a hostile thrown object must never coerce the failure itself.
const std = @import("std");
const engine_mod = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
pub const failed_message = "Session failed after a storage error; close and reopen it";
const Kind = enum(c_int) { ReadAfterWrite, StorageRequestError, SessionFailed, ConversationBusy };
fn construct(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, kind: Kind) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (c.JS_IsUndefined(target)) return c.JS_ThrowTypeError(context, "Class constructor %s cannot be invoked without 'new'", @as([*:0]const u8, @tagName(kind)));
    return create(engine, target, kind, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn readAfterWrite(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return construct(context, target, argc, argv, .ReadAfterWrite);
}
fn requestError(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return construct(context, target, argc, argv, .StorageRequestError);
}
fn failed(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return construct(context, target, argc, argv, .SessionFailed);
}
fn busy(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return construct(context, target, argc, argv, .ConversationBusy);
}
fn create(engine: *Engine, target: c.JSValue, kind: Kind, input: c.JSValue) !c.JSValue {
    const prototype = try sdk.get(engine, target, "prototype");
    defer engine.freeValue(prototype);
    const result = try engine.checked(c.JS_NewError(engine.context));
    errdefer engine.freeValue(result);
    if (c.JS_IsObject(prototype) and c.JS_SetPrototype(engine.context, result, prototype) < 0) return error.JavaScriptException;
    const message = if (kind == .SessionFailed) try sdk.text(engine, failed_message) else if (kind == .StorageRequestError) c.JS_DupValue(engine.context, input) else blk: {
        const text = try engine.toString(input);
        defer engine.gpa.free(text);
        const formatted = if (kind == .ReadAfterWrite)
            try std.fmt.allocPrint(engine.gpa, "Tx.{s}() cannot read tables after the first table write", .{text})
        else
            try std.fmt.allocPrint(engine.gpa, "Conversation {s} is busy", .{text});
        defer engine.gpa.free(formatted);
        break :blk try sdk.text(engine, formatted);
    };
    defer engine.freeValue(message);
    if (!c.JS_IsUndefined(message)) {
        // Error(message) coerces a message, but SessionFailed never coerces cause.
        const text = try engine.toString(message);
        defer engine.gpa.free(text);
        if (c.JS_DefinePropertyValueStr(engine.context, result, "message", try sdk.text(engine, text), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    }
    try sdk.put(engine, result, "name", try sdk.text(engine, @tagName(kind)));
    if (kind == .SessionFailed and c.JS_DefinePropertyValueStr(engine.context, result, "cause", c.JS_DupValue(engine.context, input), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    if (kind == .ConversationBusy) try sdk.put(engine, result, "conversationId", c.JS_DupValue(engine.context, input));
    return result;
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const base = try sdk.get(engine, global, "Error");
    defer engine.freeValue(base);
    const base_prototype = try sdk.get(engine, base, "prototype");
    defer engine.freeValue(base_prototype);
    inline for (std.meta.tags(Kind)) |kind| {
        const name = @tagName(kind);
        const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, base_prototype));
        defer engine.freeValue(prototype);
        const callback: *const fn (?*c.JSContext, c.JSValue, c_int, [*c]c.JSValue) callconv(.c) c.JSValue = switch (kind) {
            .ReadAfterWrite => readAfterWrite,
            .StorageRequestError => requestError,
            .SessionFailed => failed,
            .ConversationBusy => busy,
        };
        const constructor = try engine.checked(c.JS_NewCFunction2(engine.context, callback, name, 1, c.JS_CFUNC_constructor_or_func, 0));
        defer engine.freeValue(constructor);
        _ = c.JS_SetConstructorBit(engine.context, constructor, true);
        if (c.JS_SetPrototype(engine.context, constructor, base) < 0 or c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
        try sdk.put(engine, exports, name, c.JS_DupValue(engine.context, constructor));
    }
}
pub fn sessionFailed(engine: *Engine, cause: c.JSValue) !c.JSValue {
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableExportsUnavailable;
    const constructor = try sdk.get(engine, exports, "SessionFailed");
    defer engine.freeValue(constructor);
    var args = [_]c.JSValue{cause};
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args));
}
pub fn isRequestError(engine: *Engine, value: c.JSValue) !bool {
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableExportsUnavailable;
    const constructor = try sdk.get(engine, exports, "StorageRequestError");
    defer engine.freeValue(constructor);
    const found = c.JS_IsInstanceOf(engine.context, value, constructor);
    if (found < 0) return error.JavaScriptException;
    return found != 0;
}
pub fn errorMessage(engine: *Engine, value: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const base = try sdk.get(engine, global, "Error");
    defer engine.freeValue(base);
    const is_error = c.JS_IsInstanceOf(engine.context, value, base);
    if (is_error < 0) return error.JavaScriptException;
    if (is_error != 0) return sdk.get(engine, value, "message");
    const string = try sdk.get(engine, global, "String");
    defer engine.freeValue(string);
    var args = [_]c.JSValue{value};
    const converted = c.JS_Call(engine.context, string, c.pi_js_undefined(), 1, &args);
    if (!c.JS_IsException(converted)) return converted;
    engine.freeValue(c.JS_GetException(engine.context));
    const object = try sdk.get(engine, global, "Object");
    defer engine.freeValue(object);
    const prototype = try sdk.get(engine, object, "prototype");
    defer engine.freeValue(prototype);
    const to_string = try sdk.get(engine, prototype, "toString");
    defer engine.freeValue(to_string);
    return engine.checked(c.JS_Call(engine.context, to_string, value, 0, null));
}

test "native durable VM eba error classes preserve original hostile cause identity and Source safe messages" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("native_durable.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const Callback = struct {
        fn run(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
            const owner = Engine.fromContext(context.?);
            return errorMessage(owner, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(owner, err);
        }
    };
    try sdk.put(engine, global, "nativeDurableErrorMessage", try engine.checked(c.JS_NewCFunction(engine.context, Callback.run, "errorMessage", 1)));
    const result = engine.evalModule(
        \\import{ReadAfterWrite,StorageRequestError,SessionFailed,ConversationBusy}from'@earendil-works/pi-durable';
        \\const cause=Object.create(null);cause.toString=()=>{throw Error('must not coerce cause')};
        \\const failure=new SessionFailed(cause);
        \\if(!(failure instanceof SessionFailed)||!(failure instanceof Error)||failure.cause!==cause||failure.name!=='SessionFailed'||failure.message!=='Session failed after a storage error; close and reopen it')throw Error('failure identity');
        \\if(Object.getOwnPropertyDescriptor(failure,'cause').enumerable)throw Error('cause enumerable');
        \\class Derived extends StorageRequestError{}const request=new Derived('exact');if(!(request instanceof StorageRequestError)||!(request instanceof Error)||request.message!=='exact')throw Error('request subclass');
        \\if(new ReadAfterWrite('task').message!=='Tx.task() cannot read tables after the first table write')throw Error('read after write');
        \\const busy=new ConversationBusy(17);if(busy.conversationId!==17||busy.message!=='Conversation 17 is busy')throw Error('busy');
        \\for(const value of [Object.create(null),{toString(){throw 1}}])if(nativeDurableErrorMessage(value)!=='[object Object]')throw Error('safe message');
        \\if(nativeDurableErrorMessage(7)!=='7'||nativeDurableErrorMessage(new Error('exact'))!=='exact')throw Error('message');
    , "actual-eba-errors") catch |err| {
        std.debug.print("Actual Source durable errors: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
