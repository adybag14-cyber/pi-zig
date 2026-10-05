//! DOMException state, constructor, and accessors owned by native Zig/C.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const State = struct { engine: *engine_mod.Engine, name: c.JSValue, message: c.JSValue, code: u8 };
const Legacy = struct { constant: [*:0]const u8, name: []const u8, code: u8 };
const legacy = [_]Legacy{
    .{ .constant = "INDEX_SIZE_ERR", .name = "IndexSizeError", .code = 1 },
    .{ .constant = "DOMSTRING_SIZE_ERR", .name = "", .code = 2 },
    .{ .constant = "HIERARCHY_REQUEST_ERR", .name = "HierarchyRequestError", .code = 3 },
    .{ .constant = "WRONG_DOCUMENT_ERR", .name = "WrongDocumentError", .code = 4 },
    .{ .constant = "INVALID_CHARACTER_ERR", .name = "InvalidCharacterError", .code = 5 },
    .{ .constant = "NO_DATA_ALLOWED_ERR", .name = "", .code = 6 },
    .{ .constant = "NO_MODIFICATION_ALLOWED_ERR", .name = "NoModificationAllowedError", .code = 7 },
    .{ .constant = "NOT_FOUND_ERR", .name = "NotFoundError", .code = 8 },
    .{ .constant = "NOT_SUPPORTED_ERR", .name = "NotSupportedError", .code = 9 },
    .{ .constant = "INUSE_ATTRIBUTE_ERR", .name = "InUseAttributeError", .code = 10 },
    .{ .constant = "INVALID_STATE_ERR", .name = "InvalidStateError", .code = 11 },
    .{ .constant = "SYNTAX_ERR", .name = "SyntaxError", .code = 12 },
    .{ .constant = "INVALID_MODIFICATION_ERR", .name = "InvalidModificationError", .code = 13 },
    .{ .constant = "NAMESPACE_ERR", .name = "NamespaceError", .code = 14 },
    .{ .constant = "INVALID_ACCESS_ERR", .name = "InvalidAccessError", .code = 15 },
    .{ .constant = "VALIDATION_ERR", .name = "", .code = 16 },
    .{ .constant = "TYPE_MISMATCH_ERR", .name = "TypeMismatchError", .code = 17 },
    .{ .constant = "SECURITY_ERR", .name = "SecurityError", .code = 18 },
    .{ .constant = "NETWORK_ERR", .name = "NetworkError", .code = 19 },
    .{ .constant = "ABORT_ERR", .name = "AbortError", .code = 20 },
    .{ .constant = "URL_MISMATCH_ERR", .name = "URLMismatchError", .code = 21 },
    .{ .constant = "QUOTA_EXCEEDED_ERR", .name = "QuotaExceededError", .code = 22 },
    .{ .constant = "TIMEOUT_ERR", .name = "TimeoutError", .code = 23 },
    .{ .constant = "INVALID_NODE_TYPE_ERR", .name = "InvalidNodeTypeError", .code = 24 },
    .{ .constant = "DATA_CLONE_ERR", .name = "DataCloneError", .code = 25 },
};

fn stateFor(engine: *engine_mod.Engine, value: c.JSValue) !*State {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.dom_exception_class) orelse return error.IllegalDOMExceptionReceiver));
    if (state.engine != engine) return error.IllegalDOMExceptionReceiver;
    return state;
}

fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.name);
    c.JS_FreeValueRT(runtime, state.message);
    state.engine.gpa.destroy(state);
}

fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, mark_value: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.name, mark_value);
    c.JS_MarkValue(runtime, state.message, mark_value);
}

fn fail(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native DOMException: %s", @as([*:0]const u8, @errorName(err)));
}

fn createValues(engine: *engine_mod.Engine, prototype: c.JSValue, message: c.JSValue, name: c.JSValue) !c.JSValue {
    if (engine.dom_exception_class == 0) return error.NativeDOMExceptionUnavailable;
    const name_bytes = try engine.toString(name);
    defer engine.gpa.free(name_bytes);
    var code: u8 = 0;
    for (legacy) |entry| if (entry.name.len != 0 and std.mem.eql(u8, entry.name, name_bytes)) {
        code = entry.code;
        break;
    };
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .name = c.JS_DupValue(engine.context, name), .message = c.JS_DupValue(engine.context, message), .code = code };
    errdefer {
        engine.freeValue(state.name);
        engine.freeValue(state.message);
        engine.gpa.destroy(state);
    }
    const object = try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, engine.dom_exception_class));
    _ = c.JS_SetOpaque(object, state);
    return object;
}

/// Host-created abort reasons use the native class and captured class prototype,
/// independently of mutations to the global constructor.
pub fn create(engine: *engine_mod.Engine, message: []const u8, name: []const u8) !c.JSValue {
    if (engine.dom_exception_class == 0) return error.NativeDOMExceptionUnavailable;
    const message_value = try engine.checked(c.JS_NewStringLen(engine.context, message.ptr, message.len));
    defer engine.freeValue(message_value);
    const name_value = try engine.checked(c.JS_NewStringLen(engine.context, name.ptr, name.len));
    defer engine.freeValue(name_value);
    const prototype = try engine.checked(c.JS_GetClassProto(engine.context, engine.dom_exception_class));
    defer engine.freeValue(prototype);
    return createValues(engine, prototype, message_value, name_value);
}

fn construct(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return constructValue(engine, target, argc, argv) catch |err| fail(engine, err);
}

fn constructValue(engine: *engine_mod.Engine, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) !c.JSValue {
    var prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, target, "prototype"));
    if (!c.JS_IsObject(prototype) and !c.JS_IsNull(prototype)) {
        engine.freeValue(prototype);
        prototype = try engine.checked(c.JS_GetClassProto(engine.context, engine.dom_exception_class));
    }
    defer engine.freeValue(prototype);
    const options = if (argc < 2 or c.JS_IsUndefined(argv[1])) try engine.checked(c.JS_NewString(engine.context, "Error")) else c.JS_DupValue(engine.context, argv[1]);
    defer engine.freeValue(options);
    // Match the installed Node constructor's options form, including observable
    // name access before message conversion and cause access afterward.
    const dictionary = c.JS_IsObject(options) and !c.JS_IsFunction(engine.context, options);
    const input_name = if (dictionary) try engine.checked(c.JS_GetPropertyStr(engine.context, options, "name")) else c.JS_DupValue(engine.context, options);
    defer engine.freeValue(input_name);
    const message = if (argc == 0 or c.JS_IsUndefined(argv[0])) try engine.checked(c.JS_NewString(engine.context, "")) else try engine.checked(c.JS_ToString(engine.context, argv[0]));
    defer engine.freeValue(message);
    const name = try engine.checked(c.JS_ToString(engine.context, input_name));
    defer engine.freeValue(name);
    const object = try createValues(engine, prototype, message, name);
    errdefer engine.freeValue(object);
    if (dictionary) {
        const atom = c.JS_NewAtom(engine.context, "cause");
        if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        defer c.JS_FreeAtom(engine.context, atom);
        const has_cause = c.JS_HasProperty(engine.context, options, atom);
        if (has_cause < 0) return error.JavaScriptException;
        if (has_cause != 0) {
            const cause = try engine.checked(c.JS_GetProperty(engine.context, options, atom));
            if (c.JS_DefinePropertyValue(engine.context, object, atom, cause, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
        }
    }
    return object;
}

fn attribute(context: ?*c.JSContext, this: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const state = stateFor(engine, this) catch |err| return fail(engine, err);
    return switch (magic) {
        0 => c.JS_DupValue(context, state.name),
        1 => c.JS_DupValue(context, state.message),
        2 => c.JS_NewInt32(context, state.code),
        else => unreachable,
    };
}

pub fn install(engine: *engine_mod.Engine) !void {
    if (engine.dom_exception_class != 0) return error.DOMExceptionAlreadyInstalled;
    var class_id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class_id);
    const definition: c.JSClassDef = .{ .class_name = "DOMException", .finalizer = finalizer, .gc_mark = mark, .call = null, .exotic = null };
    if (c.JS_NewClass(engine.runtime, class_id, &definition) < 0) return error.DOMExceptionClassFailed;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const error_constructor = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Error"));
    defer engine.freeValue(error_constructor);
    const error_prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, error_constructor, "prototype"));
    defer engine.freeValue(error_prototype);
    const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, error_prototype));
    defer engine.freeValue(prototype);
    const constructor = try engine.checked(c.JS_NewCFunction2(engine.context, construct, "DOMException", 0, c.JS_CFUNC_constructor, 0));
    defer engine.freeValue(constructor);
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
    c.JS_SetClassProto(engine.context, class_id, c.JS_DupValue(engine.context, prototype));
    for ([_][*:0]const u8{ "name", "message", "code" }, 0..) |name, index| {
        const atom = c.JS_NewAtom(engine.context, name);
        if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        defer c.JS_FreeAtom(engine.context, atom);
        const getter = try engine.checked(c.pi_js_function_magic(engine.context, attribute, name, 0, @intCast(index)));
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
    }
    for (legacy) |entry| {
        for ([_]c.JSValue{ constructor, prototype }) |object| {
            if (c.JS_DefinePropertyValueStr(engine.context, object, entry.constant, c.JS_NewInt32(engine.context, entry.code), c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
        }
    }
    const symbol = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Symbol"));
    defer engine.freeValue(symbol);
    const tag = try engine.checked(c.JS_GetPropertyStr(engine.context, symbol, "toStringTag"));
    defer engine.freeValue(tag);
    const tag_atom = c.JS_ValueToAtom(engine.context, tag);
    if (tag_atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, tag_atom);
    if (c.JS_DefinePropertyValue(engine.context, prototype, tag_atom, c.JS_NewString(engine.context, "DOMException"), c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    if (c.JS_DefinePropertyValueStr(engine.context, global, "DOMException", c.JS_DupValue(engine.context, constructor), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    engine.dom_exception_class = class_id;
}

fn fixture(source: []const u8, expected: []const u8) !void {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const result = try engine.eval(source, "dom-exception-fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(expected, text);
}

test "native DOMException defaults Error inheritance branded getters constants and legacy codes" {
    try fixture(
        \\const e=new DOMException('message','AbortError'),d=new DOMException();let brands=[];for(const receiver of [{},DOMException.prototype,new Proxy(e,{})]){try{Object.getOwnPropertyDescriptor(DOMException.prototype,'name').get.call(receiver);brands.push(false)}catch(error){brands.push(error instanceof TypeError)}}
        \\const codes=['IndexSizeError','DOMStringSizeError','NoDataAllowedError','ValidationError','AbortError','TimeoutError','DataCloneError','aborterror','Other'].map(name=>new DOMException('',name).code);class Special extends DOMException{}const child=new Special('child','TimeoutError');
        \\JSON.stringify({defaults:[d.message,d.name,d.code],value:[e.message,e.name,e.code,String(e),Object.prototype.toString.call(e)],inheritance:[e instanceof Error,e instanceof DOMException,Object.getPrototypeOf(DOMException.prototype)===Error.prototype,child instanceof Special,child.code],brands,codes,constants:[DOMException.ABORT_ERR,e.ABORT_ERR,DOMException.TIMEOUT_ERR,e.TIMEOUT_ERR,Object.getOwnPropertyDescriptor(DOMException,'ABORT_ERR').writable]});
    , "{\"defaults\":[\"\",\"Error\",0],\"value\":[\"message\",\"AbortError\",20,\"AbortError: message\",\"[object DOMException]\"],\"inheritance\":[true,true,true,true,23],\"brands\":[true,true,true],\"codes\":[1,0,0,0,20,23,25,0,0],\"constants\":[20,20,23,23,false]}");
}

test "native DOMException original conversion exceptions options ordering cause and Unicode" {
    try fixture(
        \\const original={},order=[],cause={owned:1};const e=new DOMException({toString(){order.push('message');return '🌍\ud800'}},{get name(){order.push('name');return {toString(){order.push('name-string');return 'TimeoutError'}}},get cause(){order.push('cause');return cause}});let identities=[];
        \\for(const fn of [()=>new DOMException({toString(){throw original}}),()=>new DOMException('x',{get name(){throw original}}),()=>new DOMException('x',{name:{toString(){throw original}}}),()=>new DOMException('x',{name:'AbortError',get cause(){throw original}})]){try{fn();identities.push(false)}catch(error){identities.push(error===original)}}
        \\JSON.stringify({order,identities,strings:[e.message,e.name,e.code],cause:e.cause===cause,enumerable:Object.keys(e),optionsMissingName:new DOMException('x',{}).name,primitives:[new DOMException(null,null).message,new DOMException(null,null).name]});
    , "{\"order\":[\"name\",\"message\",\"name-string\",\"cause\"],\"identities\":[true,true,true,true],\"strings\":[\"🌍\\ud800\",\"TimeoutError\",23],\"cause\":true,\"enumerable\":[],\"optionsMissingName\":\"undefined\",\"primitives\":[\"null\",\"null\"]}");
}

fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try install(engine);
    const value = try create(engine, "This operation was aborted", "AbortError");
    defer engine.freeValue(value);
    const state = try stateFor(engine, value);
    try std.testing.expectEqual(@as(u8, 20), state.code);
    c.JS_RunGC(engine.runtime);
    const text = try engine.toString(state.message);
    defer gpa.free(text);
    try std.testing.expectEqualStrings("This operation was aborted", text);
}

test "native DOMException state ownership and GC survive every native allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}

test "native DOMException cause cycles are collected and native creation ignores global replacement" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const result = try engine.eval("for(let i=0;i<20;i++){const cause={};const value=new DOMException('cycle',{name:'AbortError',cause});cause.value=value;}globalThis.DOMException=function(){throw Error('replaced')};", "dom-cycle.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    const value = try create(engine, "native", "TimeoutError");
    defer engine.freeValue(value);
    const state = try stateFor(engine, value);
    try std.testing.expectEqual(@as(u8, 23), state.code);
}

test "native DOMException failed installation does not publish a usable class and can be retried" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const setup = try engine.eval("globalThis.savedError=Error;globalThis.installReason={};Object.defineProperty(globalThis,'Error',{configurable:true,get(){throw installReason}});", "dom-install-failure.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(setup);
    try std.testing.expectError(error.JavaScriptException, install(engine));
    try std.testing.expectEqual(@as(c.JSClassID, 0), engine.dom_exception_class);
    try std.testing.expectError(error.NativeDOMExceptionUnavailable, create(engine, "unavailable", "AbortError"));
    const restore = try engine.eval("Object.defineProperty(globalThis,'Error',{configurable:true,writable:true,value:savedError});", "dom-install-restore.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(restore);
    try install(engine);
    const value = try create(engine, "ready", "AbortError");
    defer engine.freeValue(value);
    try std.testing.expectEqual(@as(u8, 20), (try stateFor(engine, value)).code);
}
