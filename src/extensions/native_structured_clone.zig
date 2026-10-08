//! Owner-native argument cloning. Values and callbacks never leave this VM.
const std = @import("std");
const engine_mod = @import("engine.zig");
const values = @import("native_values.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
const Pair = struct { source: c.JSValue, target: c.JSValue };
pub fn clone(engine: *Engine, value: c.JSValue) !c.JSValue {
    var seen: std.ArrayList(Pair) = .empty;
    defer seen.deinit(engine.gpa);
    return copy(engine, value, &seen);
}
fn dataCloneError(engine: *Engine, value: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const string = try values.get(engine, global, "String");
    defer engine.freeValue(string);
    var description_args = [_]c.JSValue{value};
    const description = try engine.checked(c.JS_Call(engine.context, string, c.pi_js_undefined(), 1, &description_args));
    defer engine.freeValue(description);
    const name = try engine.toString(description);
    defer engine.gpa.free(name);
    const message = try std.fmt.allocPrint(engine.gpa, "{s} could not be cloned.", .{name});
    defer engine.gpa.free(message);
    const constructor = try values.get(engine, global, "Error");
    defer engine.freeValue(constructor);
    const text = try engine.checked(c.JS_NewStringLen(engine.context, message.ptr, message.len));
    defer engine.freeValue(text);
    var args = [_]c.JSValue{text};
    const failure = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args));
    var consumed = false;
    errdefer if (!consumed) engine.freeValue(failure);
    if (c.JS_DefinePropertyValueStr(engine.context, failure, "name", c.JS_NewString(engine.context, "DataCloneError"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    consumed = true;
    return engine.checked(c.JS_Throw(engine.context, failure));
}
fn serialized(engine: *Engine, value: c.JSValue) !c.JSValue {
    var size: usize = 0;
    // This buffer is produced and consumed locally, without bytecode flags.
    // It cannot load code and is never accepted from an untrusted producer.
    const bytes = c.JS_WriteObject(engine.context, &size, value, c.JS_WRITE_OBJ_REFERENCE);
    if (bytes == null) {
        return engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
    }
    defer c.js_free(engine.context, bytes);
    return engine.checked(c.JS_ReadObject(engine.context, bytes, size, c.JS_READ_OBJ_REFERENCE));
}
fn copy(engine: *Engine, value: c.JSValue, seen: *std.ArrayList(Pair)) anyerror!c.JSValue {
    if (c.JS_IsFunction(engine.context, value) or c.JS_IsSymbol(value)) return dataCloneError(engine, value);
    if (!c.JS_IsObject(value)) return c.JS_DupValue(engine.context, value);
    for (seen.items) |pair| if (c.JS_IsStrictEqual(engine.context, pair.source, value)) return c.JS_DupValue(engine.context, pair.target);
    const atom = c.JS_GetClassName(engine.runtime, c.JS_GetClassID(value));
    defer c.JS_FreeAtom(engine.context, atom);
    const class = try engine.checked(c.JS_AtomToString(engine.context, atom));
    defer engine.freeValue(class);
    const name = try engine.toString(class);
    defer engine.gpa.free(name);
    const typed = c.JS_GetTypedArrayType(value);
    if (typed >= 0) {
        var offset: usize = 0;
        var length: usize = 0;
        var element_size: usize = 0;
        const buffer = try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, value, &offset, &length, &element_size));
        defer engine.freeValue(buffer);
        const cloned_buffer = try copy(engine, buffer, seen);
        defer engine.freeValue(cloned_buffer);
        var args = [_]c.JSValue{ cloned_buffer, c.JS_NewInt64(engine.context, @intCast(offset)), c.JS_NewInt64(engine.context, @intCast(length / element_size)) };
        const result = try engine.checked(c.JS_NewTypedArray(engine.context, args.len, &args, @intCast(typed)));
        errdefer engine.freeValue(result);
        try seen.append(engine.gpa, .{ .source = value, .target = result });
        return result;
    }
    if (c.JS_IsDate(value) or c.JS_IsArrayBuffer(value) or std.mem.eql(u8, name, "RegExp")) {
        const result = try serialized(engine, value);
        errdefer engine.freeValue(result);
        try seen.append(engine.gpa, .{ .source = value, .target = result });
        return result;
    }
    const is_map = std.mem.eql(u8, name, "Map");
    const is_set = std.mem.eql(u8, name, "Set");
    if (is_map or is_set) {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const constructor_name = try engine.gpa.dupeZ(u8, name);
        defer engine.gpa.free(constructor_name);
        const constructor = try values.get(engine, global, constructor_name);
        defer engine.freeValue(constructor);
        const result = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
        errdefer engine.freeValue(result);
        try seen.append(engine.gpa, .{ .source = value, .target = result });
        const prototype = try values.get(engine, constructor, "prototype");
        defer engine.freeValue(prototype);
        const entries = try values.get(engine, prototype, if (is_map) "entries" else "values");
        defer engine.freeValue(entries);
        const iterator = try engine.checked(c.JS_Call(engine.context, entries, value, 0, null));
        defer engine.freeValue(iterator);
        while (true) {
            const next = try values.invoke(engine, iterator, "next", &.{});
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
                const ignored = try values.invoke(engine, result, "set", &.{ cloned_key, cloned_child });
                engine.freeValue(ignored);
            } else {
                const child = try copy(engine, item, seen);
                defer engine.freeValue(child);
                const ignored = try values.invoke(engine, result, "add", &.{child});
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
