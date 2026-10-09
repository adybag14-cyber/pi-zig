//! Owner-native argument cloning. Values and callbacks never leave this VM.
const std = @import("std");
const engine_mod = @import("engine.zig");
const values = @import("native_values.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
const Pair = struct { source: c.JSValue, target: c.JSValue };
pub fn clone(engine: *Engine, value: c.JSValue) !c.JSValue {
    if (engine.dom_exception_class == 0) try @import("dom_exception.zig").install(engine);
    var seen: std.ArrayList(Pair) = .empty;
    defer seen.deinit(engine.gpa);
    return copy(engine, value, &seen);
}
fn dataCloneError(engine: *Engine, value: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Throw(engine.context, try cloneFailureValue(engine, value)));
}
fn cloneFailureValue(engine: *Engine, value: c.JSValue) !c.JSValue {
    const name = if (c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value)) blk: {
        const atom = c.JS_GetClassName(engine.runtime, c.JS_GetClassID(value));
        defer c.JS_FreeAtom(engine.context, atom);
        const class = try engine.checked(c.JS_AtomToString(engine.context, atom));
        defer engine.freeValue(class);
        const class_name = try engine.toString(class);
        defer engine.gpa.free(class_name);
        if (c.JS_IsProxy(value)) break :blk try engine.gpa.dupe(u8, "#<Object>");
        if (std.mem.eql(u8, class_name, "Symbol")) break :blk try engine.gpa.dupe(u8, "[object Symbol]");
        break :blk try std.fmt.allocPrint(engine.gpa, "#<{s}>", .{class_name});
    } else blk: {
        if (c.JS_IsFunction(engine.context, value)) {
            const rendered = try intrinsicCall(engine, "Function.toString", value, &.{});
            defer engine.freeValue(rendered);
            break :blk try engine.toString(rendered);
        }
        const string = try values.get(engine, engine.intrinsic_clone_operations, "String");
        defer engine.freeValue(string);
        var description_args = [_]c.JSValue{value};
        const description = try engine.checked(c.JS_Call(engine.context, string, c.pi_js_undefined(), 1, &description_args));
        defer engine.freeValue(description);
        break :blk try engine.toString(description);
    };
    defer engine.gpa.free(name);
    const message = try std.fmt.allocPrint(engine.gpa, "{s} could not be cloned.", .{name});
    defer engine.gpa.free(message);
    return @import("dom_exception.zig").create(engine, message, "DataCloneError");
}
fn serialized(engine: *Engine, value: c.JSValue) !c.JSValue {
    var size: usize = 0;
    // This buffer is produced and consumed locally, without bytecode flags.
    // It cannot load code and is never accepted from an untrusted producer.
    const bytes = c.JS_WriteObject(engine.context, &size, value, c.JS_WRITE_OBJ_REFERENCE | c.JS_WRITE_OBJ_SAB);
    if (bytes == null) {
        return checkedBufferOperation(engine, c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
    }
    defer c.js_free(engine.context, bytes);
    return engine.checked(c.JS_ReadObject(engine.context, bytes, size, c.JS_READ_OBJ_REFERENCE | c.JS_READ_OBJ_SAB));
}
fn checkedBufferOperation(engine: *Engine, result: c.JSValue) !c.JSValue {
    if (!c.JS_IsException(result)) return result;
    const failure = c.JS_GetException(engine.context);
    defer engine.freeValue(failure);
    const message_value = try values.get(engine, failure, "message");
    defer engine.freeValue(message_value);
    if (c.JS_IsString(message_value)) {
        const message = try engine.toString(message_value);
        defer engine.gpa.free(message);
        // Only the intrinsic buffer operations call this adapter. No user
        // callback or getter-thrown error is classified by its name/message.
        if (std.mem.eql(u8, message, "ArrayBuffer is detached")) return engine.checked(c.JS_Throw(engine.context, try @import("dom_exception.zig").create(engine, "An ArrayBuffer is detached and could not be cloned.", "DataCloneError")));
    }
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, failure)));
}
fn intrinsicCall(engine: *Engine, key: [:0]const u8, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const callback = try values.get(engine, engine.intrinsic_clone_operations, key);
    defer engine.freeValue(callback);
    return engine.checked(c.JS_Call(engine.context, callback, receiver, @intCast(args.len), @constCast(args.ptr)));
}
fn ownData(engine: *Engine, value: c.JSValue, key: [:0]const u8) !?c.JSValue {
    const atom = c.JS_NewAtom(engine.context, key);
    defer c.JS_FreeAtom(engine.context, atom);
    var descriptor: c.JSPropertyDescriptor = undefined;
    const present = c.JS_GetOwnProperty(engine.context, &descriptor, value, atom);
    if (present < 0) return error.JavaScriptException;
    if (present == 0) return null;
    defer engine.freeValue(descriptor.value);
    defer engine.freeValue(descriptor.getter);
    defer engine.freeValue(descriptor.setter);
    return if ((descriptor.flags & c.JS_PROP_TMASK) == c.JS_PROP_GETSET) null else c.JS_DupValue(engine.context, descriptor.value);
}
fn copyError(engine: *Engine, value: c.JSValue, seen: *std.ArrayList(Pair)) !c.JSValue {
    const name_value = try values.get(engine, value, "name");
    defer engine.freeValue(name_value);
    var constructor_name: [:0]const u8 = "Error";
    if (c.JS_IsString(name_value)) {
        const label = try engine.toString(name_value);
        defer engine.gpa.free(label);
        inline for (.{ "EvalError", "RangeError", "ReferenceError", "SyntaxError", "TypeError", "URIError" }) |name| if (std.mem.eql(u8, label, name)) {
            constructor_name = name;
        };
    }
    const constructor = try values.get(engine, engine.intrinsic_clone_operations, constructor_name);
    defer engine.freeValue(constructor);
    const message = try ownData(engine, value, "message");
    defer if (message) |data| engine.freeValue(data);
    const result = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
    errdefer engine.freeValue(result);
    if (c.JS_DefinePropertyValueStr(engine.context, result, "stack", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    // Error(undefined) omits message; the serializer retains the own data
    // property and spells its value with the intrinsic ToString operation.
    if (message) |data| {
        const text = try engine.checked(c.JS_ToString(engine.context, data));
        if (c.JS_DefinePropertyValueStr(engine.context, result, "message", text, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    }
    try seen.append(engine.gpa, .{ .source = value, .target = result });
    const stack = try values.get(engine, value, "stack");
    defer engine.freeValue(stack);
    if (c.JS_DefinePropertyValueStr(engine.context, result, "stack", if (c.JS_IsString(stack)) c.JS_DupValue(engine.context, stack) else c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    const cause = try ownData(engine, value, "cause");
    defer if (cause) |data| engine.freeValue(data);
    if (cause) |data| if (c.JS_DefinePropertyValueStr(engine.context, result, "cause", try copy(engine, data, seen), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    return result;
}
fn copy(engine: *Engine, value: c.JSValue, seen: *std.ArrayList(Pair)) anyerror!c.JSValue {
    if (c.JS_IsFunction(engine.context, value) or c.JS_IsSymbol(value)) return dataCloneError(engine, value);
    if (!c.JS_IsObject(value)) return c.JS_DupValue(engine.context, value);
    if (c.JS_IsProxy(value)) return dataCloneError(engine, value);
    for (seen.items) |pair| if (c.JS_IsStrictEqual(engine.context, pair.source, value)) return c.JS_DupValue(engine.context, pair.target);
    const atom = c.JS_GetClassName(engine.runtime, c.JS_GetClassID(value));
    defer c.JS_FreeAtom(engine.context, atom);
    const class = try engine.checked(c.JS_AtomToString(engine.context, atom));
    defer engine.freeValue(class);
    const name = try engine.toString(class);
    defer engine.gpa.free(name);
    if (c.JS_IsError(value)) return copyError(engine, value, seen);
    if (c.JS_IsDataView(value)) {
        const buffer = try intrinsicCall(engine, "DataView.buffer", value, &.{});
        defer engine.freeValue(buffer);
        const copied_buffer = try copy(engine, buffer, seen);
        defer engine.freeValue(copied_buffer);
        const offset = try intrinsicCall(engine, "DataView.byteOffset", value, &.{});
        defer engine.freeValue(offset);
        const length = try intrinsicCall(engine, "DataView.byteLength", value, &.{});
        defer engine.freeValue(length);
        const constructor = try values.get(engine, engine.intrinsic_clone_operations, "DataView");
        defer engine.freeValue(constructor);
        var args = [_]c.JSValue{ copied_buffer, offset, length };
        const result = try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
        errdefer engine.freeValue(result);
        try seen.append(engine.gpa, .{ .source = value, .target = result });
        return result;
    }
    const typed = c.JS_GetTypedArrayType(value);
    if (typed >= 0) {
        var offset: usize = 0;
        var length: usize = 0;
        var element_size: usize = 0;
        const buffer = try checkedBufferOperation(engine, c.JS_GetTypedArrayBuffer(engine.context, value, &offset, &length, &element_size));
        defer engine.freeValue(buffer);
        const cloned_buffer = try copy(engine, buffer, seen);
        defer engine.freeValue(cloned_buffer);
        var args = [_]c.JSValue{ cloned_buffer, c.JS_NewInt64(engine.context, @intCast(offset)), c.JS_NewInt64(engine.context, @intCast(length / element_size)) };
        const result = try engine.checked(c.JS_NewTypedArray(engine.context, args.len, &args, @intCast(typed)));
        errdefer engine.freeValue(result);
        try seen.append(engine.gpa, .{ .source = value, .target = result });
        return result;
    }
    if (c.JS_IsDate(value) or c.JS_IsArrayBuffer(value) or std.mem.eql(u8, name, "SharedArrayBuffer") or std.mem.eql(u8, name, "RegExp") or std.mem.eql(u8, name, "Boolean") or std.mem.eql(u8, name, "Number") or std.mem.eql(u8, name, "String") or std.mem.eql(u8, name, "BigInt")) {
        const result = try serialized(engine, value);
        errdefer engine.freeValue(result);
        try seen.append(engine.gpa, .{ .source = value, .target = result });
        return result;
    }
    const is_map = std.mem.eql(u8, name, "Map");
    const is_set = std.mem.eql(u8, name, "Set");
    if (is_map or is_set) {
        const constructor = try values.get(engine, engine.intrinsic_clone_operations, if (is_map) "Map" else "Set");
        defer engine.freeValue(constructor);
        const result = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
        errdefer engine.freeValue(result);
        try seen.append(engine.gpa, .{ .source = value, .target = result });
        const iterator = try intrinsicCall(engine, if (is_map) "Map.iterate" else "Set.iterate", value, &.{});
        defer engine.freeValue(iterator);
        while (true) {
            const next = try intrinsicCall(engine, if (is_map) "Map.next" else "Set.next", iterator, &.{});
            defer engine.freeValue(next);
            const done = try values.get(engine, next, "done");
            defer engine.freeValue(done);
            if (c.JS_ToBool(engine.context, done) != 0) break;
            const item = try values.get(engine, next, "value");
            defer engine.freeValue(item);
            if (is_map) {
                const key = try engine.checked(c.JS_GetPropertyUint32(engine.context, item, 0));
                defer engine.freeValue(key);
                const child = try engine.checked(c.JS_GetPropertyUint32(engine.context, item, 1));
                defer engine.freeValue(child);
                const cloned_key = try copy(engine, key, seen);
                defer engine.freeValue(cloned_key);
                const cloned_child = try copy(engine, child, seen);
                defer engine.freeValue(cloned_child);
                const ignored = try intrinsicCall(engine, "Map.insert", result, &.{ cloned_key, cloned_child });
                engine.freeValue(ignored);
            } else {
                const child = try copy(engine, item, seen);
                defer engine.freeValue(child);
                const ignored = try intrinsicCall(engine, "Set.insert", result, &.{child});
                engine.freeValue(ignored);
            }
        }
        return result;
    }
    if (!std.mem.eql(u8, name, "Object") and !std.mem.eql(u8, name, "Array")) return dataCloneError(engine, value);
    const result = if (c.JS_IsArray(value)) try values.array(engine) else try values.object(engine);
    errdefer engine.freeValue(result);
    try seen.append(engine.gpa, .{ .source = value, .target = result });
    if (c.JS_IsArray(value)) {
        const length = try values.get(engine, value, "length");
        if (c.JS_SetPropertyStr(engine.context, result, "length", length) < 0) return error.JavaScriptException;
    }
    var properties: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &properties, &count, value, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, properties, count);
    for (0..count) |index| {
        const child = try engine.checked(c.JS_GetProperty(engine.context, value, properties[index].atom));
        defer engine.freeValue(child);
        if (c.JS_DefinePropertyValue(engine.context, result, properties[index].atom, try copy(engine, child, seen), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    return result;
}

fn cloned(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return clone(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return engine.throwCaptured();
    };
}
test "native durable VM argument cloning preserves cyclic values special numbers typed buffer aliases and original getter errors" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try values.put(engine, global, "nativeClone", try engine.checked(c.JS_NewCFunction(engine.context, cloned, "nativeClone", 1)));
    errdefer std.debug.print("Argument clone VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\const copy=nativeClone,shared={n:1},symbol=Symbol('ignored'),buffer=new ArrayBuffer(8),bytes=new Uint8Array(buffer,2,3),array=[,undefined,NaN,Infinity,17n],original={shared,again:shared,array,buffer,bytes,date:new Date(123),regexp:/a+/gi,map:new Map(),set:new Set(),get computed(){globalThis.getters=(globalThis.getters??0)+1;return shared}};original.self=original;original.map.set(shared,original);original.set.add(original);original.regexp.lastIndex=3;original[symbol]='ignore';Object.defineProperty(original,'hidden',{value:17});bytes[0]=9;
        \\const cloned=copy(original),reverse=copy({bytes,buffer}),prototype=copy(Object.assign(Object.create(null),{n:1})),failures=[];for(const value of [Symbol('x'),function bad(){}])try{copy(value)}catch(error){failures.push({name:error.name,message:error.message})}const reason={identity:true};let getter;try{copy({get value(){throw reason}})}catch(error){getter=error===reason}
        \\globalThis.result=JSON.stringify({identity:cloned!==original&&cloned.shared!==shared&&cloned.shared===cloned.again&&cloned.self===cloned&&cloned.computed===cloned.shared,map:cloned.map.get(cloned.shared)===cloned,set:cloned.set.has(cloned),array:{length:cloned.array.length,hole:!(0 in cloned.array),undefined:cloned.array[1]===undefined,nan:Number.isNaN(cloned.array[2]),infinity:cloned.array[3]===Infinity,bigint:cloned.array[4]===17n},buffer:{alias:cloned.bytes.buffer===cloned.buffer,reverse:reverse.bytes.buffer===reverse.buffer,offset:cloned.bytes.byteOffset,length:cloned.bytes.length,value:cloned.bytes[0],detached:buffer.byteLength===8},date:cloned.date.getTime(),regexp:{source:cloned.regexp.source,flags:cloned.regexp.flags,lastIndex:cloned.regexp.lastIndex},symbols:Object.getOwnPropertySymbols(cloned).length,hidden:Object.hasOwn(cloned,'hidden'),prototype:Object.getPrototypeOf(prototype)===Object.prototype,getters:globalThis.getters,failures,getter});
        \\
        \\
    , "native-tool-argument-clone-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-tool-argument-clone-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"identity\":true,\"map\":true,\"set\":true,\"array\":{\"length\":5,\"hole\":true,\"undefined\":true,\"nan\":true,\"infinity\":true,\"bigint\":true},\"buffer\":{\"alias\":true,\"reverse\":true,\"offset\":2,\"length\":3,\"value\":9,\"detached\":true},\"date\":123,\"regexp\":{\"source\":\"a+\",\"flags\":\"gi\",\"lastIndex\":0},\"symbols\":0,\"hidden\":false,\"prototype\":true,\"getters\":1,\"failures\":[{\"name\":\"DataCloneError\",\"message\":\"Symbol(x) could not be cloned.\"},{\"name\":\"DataCloneError\",\"message\":\"function bad(){} could not be cloned.\"}],\"getter\":true}", text);
}
fn allocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const input = try engine.eval("(()=>{const common={n:1},buffer=new ArrayBuffer(8),value={common,again:common,buffer,bytes:new Uint8Array(buffer,2,3),map:new Map([[common,{n:2}]])};value.self=value;return value})()", "clone-allocation-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(input);
    const output = try clone(engine, input);
    defer engine.freeValue(output);
}
test "native durable VM argument cloning unwinds every GPA allocation failure with cyclic values and buffers" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}
test "native durable VM structured clone failures use DOMException identity without wrapping getter thrown DataCloneError names" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    if (engine.dom_exception_class == 0) try @import("dom_exception.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try values.put(engine, global, "nativeClone", try engine.checked(c.JS_NewCFunction(engine.context, cloned, "nativeClone", 1)));
    const output = try engine.evalModule(
        \\const output=[];for(const value of [Symbol('x'),function bad(){},new WeakMap()])try{nativeClone(value)}catch(error){output.push({name:error.name,message:error.message,dom:error instanceof DOMException,ordinary:error instanceof Error,prototype:Object.getPrototypeOf(error)===DOMException.prototype,tag:Object.prototype.toString.call(error),code:error.code})}const raw=new Error('raw');raw.name='DataCloneError';let getter;try{nativeClone({get value(){throw raw}})}catch(error){getter={identity:error===raw,dom:error instanceof DOMException,ordinary:error instanceof Error,name:error.name}}globalThis.result=JSON.stringify({output,getter});
    , "native-clone-domexception-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-clone-domexception-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("{\"output\":[{\"name\":\"DataCloneError\",\"message\":\"Symbol(x) could not be cloned.\",\"dom\":true,\"ordinary\":true,\"prototype\":true,\"tag\":\"[object DOMException]\",\"code\":25},{\"name\":\"DataCloneError\",\"message\":\"function bad(){} could not be cloned.\",\"dom\":true,\"ordinary\":true,\"prototype\":true,\"tag\":\"[object DOMException]\",\"code\":25},{\"name\":\"DataCloneError\",\"message\":\"#<WeakMap> could not be cloned.\",\"dom\":true,\"ordinary\":true,\"prototype\":true,\"tag\":\"[object DOMException]\",\"code\":25}],\"getter\":{\"identity\":true,\"dom\":false,\"ordinary\":true,\"name\":\"DataCloneError\"}}", text);
}
fn cloneFailureAllocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const value = try engine.eval("Symbol('fixture')", "clone-error-allocation-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    if (engine.dom_exception_class == 0) try @import("dom_exception.zig").install(engine);
    const result = try cloneFailureValue(engine, value);
    defer engine.freeValue(result);
}
test "native durable VM generated structured clone DOMException failure unwinds every GPA allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneFailureAllocationExercise, .{});
}

test "native durable VM structured clone Error boxed primitives DataView graph proxy and detached failures match original" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try values.put(engine, global, "nativeClone", try engine.checked(c.JS_NewCFunction(engine.context, cloned, "nativeClone", 1)));
    try values.put(engine, global, "nativeDetach", try engine.checked(c.JS_NewCFunction(engine.context, testDetach, "nativeDetach", 1)));
    errdefer std.debug.print("Exotic clone VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\const output=[],events=[];
        \\function show(name,value){try{const result=nativeClone(value);output.push({name,tag:Object.prototype.toString.call(result),ctor:result.constructor?.name,keys:Reflect.ownKeys(result).map(String),value:result instanceof Error?{name:result.name,message:result.message,stack:result.stack===value.stack,cause:result.cause}:result instanceof DataView?{offset:result.byteOffset,length:result.byteLength,value:result.getUint8(0)}:typeof result==='object'&&['Boolean','Number','String','BigInt'].includes(result.constructor?.name)?String(result.valueOf()):{},prototype:Object.getPrototypeOf(result)===Object.getPrototypeOf(value)})}catch(error){output.push({name,error:{name:error.name,message:error.message}})}}
        \\for(const value of [new Error('oops',{cause:{why:1}}),new TypeError('bad'),new RangeError('range'),new AggregateError([1,2],'agg'),new Boolean(false),new Number(NaN),new String('hi'),Object(17n),Object(Symbol('x'))]){value.extra=1;show(value.constructor.name,value)}
        \\const buffer=new ArrayBuffer(8),view=new DataView(buffer,2,3);view.setUint8(0,7);show('DataView',view);const cloned=nativeClone({buffer,view});output.push({name:'DataView-alias',alias:cloned.view.buffer===cloned.buffer,detached:cloned.buffer!==buffer});
        \\const sab=new SharedArrayBuffer(8);new Uint8Array(sab)[0]=9;const shared=nativeClone({sab,view:new Uint8Array(sab),again:sab});new Uint8Array(shared.sab)[0]=11;output.push({name:'SAB',alias:shared.sab===shared.again,view:shared.view.buffer===shared.sab,detached:shared.sab!==sab,shared:new Uint8Array(sab)[0]});
        \\const error=new Error('initial');for(const key of ['name','message','stack','cause'])Object.defineProperty(error,key,{get(){events.push(key);return key==='cause'?{a:1}:key==='name'?'TypeError':'get-'+key},enumerable:true,configurable:true});show('error-getters',error);output.push({name:'error-events',events});
        \\show('proxy',new Proxy({a:1},{}));show('weakset',new WeakSet());show('promise',Promise.resolve(1));const detached=new ArrayBuffer(8);nativeDetach(detached);show('detached-buffer',detached);
        \\globalThis.result=JSON.stringify(output);
    , "native-clone-exotics-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-clone-exotics-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/structured-clone-exotics-1ced.json"), "\r\n "), text);
}
fn testDetach(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    if (argc > 0) c.JS_DetachArrayBuffer(context, argv[0]);
    return c.pi_js_undefined();
}

test "native durable VM fixed shared backing survives source runtime retirement and releases the final cross runtime owner" {
    const owners = c.pi_js_native_memory_owners();
    const buffers = c.pi_js_shared_buffer_allocations();
    const source = try Engine.init(std.testing.allocator, .{});
    var source_open = true;
    defer if (source_open) source.deinit();
    const target = try Engine.init(std.testing.allocator, .{});
    var target_open = true;
    defer if (target_open) target.deinit();
    const output = blk: {
        const input = try source.eval("(()=>{const sab=new SharedArrayBuffer(8);new Uint8Array(sab)[0]=7;return sab})()", "shared-backing-source", c.JS_EVAL_TYPE_GLOBAL);
        defer source.freeValue(input);
        var size: usize = 0;
        const bytes = c.JS_WriteObject(source.context, &size, input, c.JS_WRITE_OBJ_REFERENCE | c.JS_WRITE_OBJ_SAB) orelse return error.JavaScriptException;
        defer c.js_free(source.context, bytes);
        break :blk try target.checked(c.JS_ReadObject(target.context, bytes, size, c.JS_READ_OBJ_REFERENCE | c.JS_READ_OBJ_SAB));
    };
    var output_open = true;
    defer if (output_open) target.freeValue(output);
    source.deinit();
    source_open = false;
    try std.testing.expectEqual(buffers + 1, c.pi_js_shared_buffer_allocations());
    try std.testing.expectEqual(owners + 2, c.pi_js_native_memory_owners());
    const global = c.JS_GetGlobalObject(target.context);
    try values.put(target, global, "fixtureShared", c.JS_DupValue(target.context, output));
    target.freeValue(global);
    const check = try target.eval("new Uint8Array(fixtureShared)[0]", "shared-backing-after-source", c.JS_EVAL_TYPE_GLOBAL);
    var byte: i32 = 0;
    const converted = c.JS_ToInt32(target.context, &byte, check);
    target.freeValue(check);
    if (converted < 0) return error.JavaScriptException;
    try std.testing.expectEqual(@as(i32, 7), byte);
    target.freeValue(output);
    output_open = false;
    target.deinit();
    target_open = false;
    try std.testing.expectEqual(buffers, c.pi_js_shared_buffer_allocations());
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
}

test "native durable VM shared and ordinary allocations obey one memory quota and release ignored property graph cycles" {
    const owners = c.pi_js_native_memory_owners();
    const buffers = c.pi_js_shared_buffer_allocations();
    const quota = 8 * 1024 * 1024;
    const engine = try Engine.init(std.testing.allocator, .{ .memory_limit = quota });
    var engine_open = true;
    defer if (engine_open) engine.deinit();
    const input = try engine.eval("globalThis.fixtureShared=new SharedArrayBuffer(5*1024*1024)", "shared-quota-source", c.JS_EVAL_TYPE_GLOBAL);
    const output = try clone(engine, input);
    const atom = c.JS_NewAtom(engine.context, "ignoredClone");
    if (c.JS_DefinePropertyValue(engine.context, input, atom, c.JS_DupValue(engine.context, output), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    c.JS_FreeAtom(engine.context, atom);
    engine.freeValue(input);
    engine.freeValue(output);
    try std.testing.expect(c.pi_js_native_memory_used(engine.native_memory_owner) <= quota);
    try std.testing.expectError(error.JavaScriptException, engine.eval("new ArrayBuffer(5*1024*1024)", "shared-quota-combined-failure", c.JS_EVAL_TYPE_GLOBAL));
    engine.beginInvocation();
    const cleared = try engine.eval("fixtureShared=null", "shared-quota-release-root", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(cleared);
    c.JS_RunGC(engine.runtime);
    try std.testing.expectEqual(buffers, c.pi_js_shared_buffer_allocations());
    const ordinary = try engine.eval("new ArrayBuffer(5*1024*1024)", "shared-quota-after-release", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(ordinary);
    engine.deinit();
    engine_open = false;
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
    try std.testing.expectEqual(buffers, c.pi_js_shared_buffer_allocations());
}

test "native durable VM structured clone captures intrinsic constructors methods and function rendering while preserving cyclic Error causes" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try values.put(engine, global, "nativeClone", try engine.checked(c.JS_NewCFunction(engine.context, cloned, "nativeClone", 1)));
    errdefer std.debug.print("Clone intrinsics VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\const output=[],events=[],raw={owned:true},OriginalMap=Map,OriginalSet=Set,OriginalDataView=DataView,OriginalString=String,OriginalError=Error,OriginalTypeError=TypeError,toString=Function.prototype.toString;
        \\const map=new Map([[{n:1},{n:2}]]),set=new Set([{n:3}]),view=new DataView(new ArrayBuffer(8),2,3),error=new TypeError('original',{cause:{n:4}});view.setUint8(0,7);const mapEntries=Map.prototype.entries,mapSet=Map.prototype.set,setValues=Set.prototype.values,setAdd=Set.prototype.add,nextProto=Object.getPrototypeOf(map.entries()),next=nextProto.next;
        \\for(const name of ['Map','Set','DataView','String','Error','TypeError'])globalThis[name]=function(){events.push(name);throw raw};OriginalMap.prototype.entries=OriginalMap.prototype.set=OriginalSet.prototype.values=OriginalSet.prototype.add=nextProto.next=function(){events.push('method');throw raw};Function.prototype.toString=function(){events.push('toString');return 'spoof'};
        \\let cloned,failure;try{cloned=nativeClone({map,set,view,error});try{nativeClone(function original(){})}catch(error){failure={name:error.name,message:error.message}}}finally{for(const [name,value]of [['Map',OriginalMap],['Set',OriginalSet],['DataView',OriginalDataView],['String',OriginalString],['Error',OriginalError],['TypeError',OriginalTypeError]])globalThis[name]=value;Map.prototype.entries=mapEntries;Map.prototype.set=mapSet;Set.prototype.values=setValues;Set.prototype.add=setAdd;nextProto.next=next;Function.prototype.toString=toString}
        \\output.push({map:[...cloned.map],set:[...cloned.set],view:cloned.view.getUint8(0),error:{name:cloned.error.name,message:cloned.error.message,cause:cloned.error.cause,stack:cloned.error.stack===error.stack},failure,events});const cyclic=new Error('cycle');cyclic.cause={owner:cyclic};const cycle=nativeClone(cyclic);output.push({cycle:cycle.cause.owner===cycle,detached:cycle!==cyclic});globalThis.result=JSON.stringify(output);
    , "native-clone-intrinsics-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-clone-intrinsics-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/structured-clone-intrinsics-cycles-1ced.json"), "\r\n "), text);
}

fn exoticAllocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const input = try engine.eval("(()=>{const error=new TypeError('fixture');error.cause={error};const buffer=new ArrayBuffer(8),view=new DataView(buffer,2,3),sab=new SharedArrayBuffer(8);return {error,boxed:[new String('x'),new Number(3),Object(4n)],buffer,view,sab,sabView:new Uint8Array(sab)}})()", "clone-exotic-gpa-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(input);
    const output = try clone(engine, input);
    defer engine.freeValue(output);
}
test "native durable VM Error boxed DataView and fixed shared graph cloning unwind every allocation and native backing owner" {
    const owners = c.pi_js_native_memory_owners();
    const buffers = c.pi_js_shared_buffer_allocations();
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exoticAllocationExercise, .{});
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
    try std.testing.expectEqual(buffers, c.pi_js_shared_buffer_allocations());
}
