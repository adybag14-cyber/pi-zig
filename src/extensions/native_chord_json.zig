//! Strict Chord JSON copies for actual durable workflow values. The returned
//! functions own their shared descriptor and preserve VM values without JSON.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const putData = @import("native_tool_info.zig").putData;
const c = engine_mod.c;
const Engine = engine_mod.Engine;

fn builtin(engine: *Engine, name: [:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return vm.get(engine, global, name);
}
fn invokeBuiltin(engine: *Engine, owner: [:0]const u8, name: [:0]const u8, args: []const c.JSValue) !c.JSValue {
    const object = try builtin(engine, owner);
    defer engine.freeValue(object);
    return vm.invoke(engine, object, name, args);
}
fn prototype(engine: *Engine, name: [:0]const u8) !c.JSValue {
    const constructor = try builtin(engine, name);
    defer engine.freeValue(constructor);
    return vm.get(engine, constructor, "prototype");
}
fn throwType(engine: *Engine, message: [:0]const u8) !c.JSValue {
    const constructor = try builtin(engine, "TypeError");
    defer engine.freeValue(constructor);
    const text = try engine.checked(c.JS_NewString(engine.context, message.ptr));
    defer engine.freeValue(text);
    var arguments = [_]c.JSValue{text};
    const value = try engine.checked(c.JS_CallConstructor(engine.context, constructor, arguments.len, &arguments));
    return engine.checked(c.JS_Throw(engine.context, value));
}
fn newSet(engine: *Engine) !c.JSValue {
    const constructor = try builtin(engine, "Set");
    defer engine.freeValue(constructor);
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
}
fn isArray(engine: *Engine, value: c.JSValue) !bool {
    const result = try invokeBuiltin(engine, "Array", "isArray", &.{value});
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
fn ownKeys(engine: *Engine, value: c.JSValue) !c.JSValue {
    return invokeBuiltin(engine, "Reflect", "ownKeys", &.{value});
}
fn descriptor(engine: *Engine, value: c.JSValue, key: c.JSValue) !c.JSValue {
    return invokeBuiltin(engine, "Object", "getOwnPropertyDescriptor", &.{ value, key });
}
fn validDescriptor(engine: *Engine, desc: c.JSValue) !bool {
    if (c.JS_IsUndefined(desc)) return false;
    const enumerable = try vm.get(engine, desc, "enumerable");
    defer engine.freeValue(enumerable);
    if (c.JS_ToBool(engine.context, enumerable) == 0) return false;
    const atom = c.JS_NewAtom(engine.context, "value");
    defer c.JS_FreeAtom(engine.context, atom);
    const exists = c.JS_HasProperty(engine.context, desc, atom);
    if (exists < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        unreachable;
    }
    return exists != 0;
}
fn contains(engine: *Engine, active: c.JSValue, value: c.JSValue) !bool {
    const found = try vm.invoke(engine, active, "has", &.{value});
    defer engine.freeValue(found);
    return c.JS_ToBool(engine.context, found) != 0;
}
fn mark(engine: *Engine, active: c.JSValue, value: c.JSValue) !void {
    const result = try vm.invoke(engine, active, "add", &.{value});
    engine.freeValue(result);
}
fn unmark(engine: *Engine, active: c.JSValue, value: c.JSValue) !void {
    const result = try vm.invoke(engine, active, "delete", &.{value});
    engine.freeValue(result);
}
fn finite(engine: *Engine, value: c.JSValue) !bool {
    const result = try invokeBuiltin(engine, "Number", "isFinite", &.{value});
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
fn primitive(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsString(value) or c.JS_IsBool(value);
}
fn isObject(engine: *Engine, value: c.JSValue) bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value);
}
fn restoreFailure(engine: *Engine, original: ?c.JSValue) void {
    if (original) |value| {
        if (engine.captured_exception) |previous| engine.freeValue(previous);
        engine.captured_exception = c.JS_DupValue(engine.context, value);
    }
}
fn defineData(engine: *Engine, shared_descriptor: c.JSValue, target: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    try vm.put(engine, shared_descriptor, "value", value);
    const result = try invokeBuiltin(engine, "Object", "defineProperty", &.{ target, key, shared_descriptor });
    engine.freeValue(result);
    try vm.put(engine, shared_descriptor, "value", c.pi_js_undefined());
}
pub fn copy(engine: *Engine, shared_descriptor: c.JSValue, value: c.JSValue, options: c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    const omit_value = if (c.JS_IsUndefined(options) or c.JS_IsNull(options)) c.pi_js_undefined() else try vm.get(engine, options, "omitUndefinedProperties");
    defer engine.freeValue(omit_value);
    return copyValue(engine, shared_descriptor, value, null, c.JS_IsBool(omit_value) and c.JS_ToBool(engine.context, omit_value) != 0) catch |err| return engine.nativeAllocationError(err, generation);
}
fn copyValue(engine: *Engine, shared_descriptor: c.JSValue, value: c.JSValue, ancestors: ?c.JSValue, omit: bool) anyerror!c.JSValue {
    if (primitive(value)) return c.JS_DupValue(engine.context, value);
    if (c.JS_IsNumber(value)) return if (try finite(engine, value)) c.JS_DupValue(engine.context, value) else throwType(engine, "Value contains a non-finite number and is not strict JSON");
    if (!isObject(engine, value)) return throwType(engine, if (c.JS_IsUndefined(value)) "Value contains a non-JSON undefined; expected strict JSON" else if (c.JS_IsBigInt(value)) "Value contains a non-JSON bigint; expected strict JSON" else if (c.JS_IsSymbol(value)) "Value contains a non-JSON symbol; expected strict JSON" else "Value contains a non-JSON function; expected strict JSON");
    const active = if (ancestors) |set| c.JS_DupValue(engine.context, set) else try newSet(engine);
    defer engine.freeValue(active);
    if (try contains(engine, active, value)) return throwType(engine, "Value contains cycles and is not strict JSON");
    try mark(engine, active, value);
    const result = copyBody(engine, shared_descriptor, value, active, omit) catch |err| {
        const original = if (engine.captured_exception) |exception| c.JS_DupValue(engine.context, exception) else null;
        defer if (original) |exception| engine.freeValue(exception);
        try unmark(engine, active, value);
        restoreFailure(engine, original);
        return err;
    };
    errdefer engine.freeValue(result);
    try unmark(engine, active, value);
    return result;
}
fn copyBody(engine: *Engine, shared_descriptor: c.JSValue, value: c.JSValue, active: c.JSValue, omit: bool) !c.JSValue {
    const array = try isArray(engine, value);
    const actual_prototype = try invokeBuiltin(engine, "Object", "getPrototypeOf", &.{value});
    defer engine.freeValue(actual_prototype);
    const expected_prototype = try prototype(engine, if (array) "Array" else "Object");
    defer engine.freeValue(expected_prototype);
    if (!c.JS_IsStrictEqual(engine.context, actual_prototype, expected_prototype) and (array or !c.JS_IsNull(actual_prototype))) return throwType(engine, if (array) "Value must contain strict JSON dense plain arrays" else "Value must contain strict JSON plain objects or arrays");
    const keys = try ownKeys(engine, value);
    defer engine.freeValue(keys);
    if (array) {
        const length_value = try vm.get(engine, value, "length");
        defer engine.freeValue(length_value);
        const length = try vm.length(engine, value);
        if (!c.JS_IsNumber(length_value) or try vm.length(engine, keys) != length + 1) return throwType(engine, "Value must contain strict JSON dense plain arrays");
        const constructor = try builtin(engine, "Array");
        defer engine.freeValue(constructor);
        var arguments = [_]c.JSValue{length_value};
        const result = try engine.checked(c.JS_CallConstructor(engine.context, constructor, arguments.len, &arguments));
        errdefer engine.freeValue(result);
        var index: u32 = 0;
        while (index < try vm.length(engine, value)) : (index += 1) {
            const key = c.pi_js_int32(engine.context, @bitCast(index));
            const desc = try descriptor(engine, value, key);
            defer engine.freeValue(desc);
            if (!try validDescriptor(engine, desc)) return throwType(engine, "Value must contain strict JSON enumerable indexed data properties");
            const child = try vm.get(engine, desc, "value");
            defer engine.freeValue(child);
            const string = try builtin(engine, "String");
            defer engine.freeValue(string);
            var key_arguments = [_]c.JSValue{key};
            const name = try engine.checked(c.JS_Call(engine.context, string, c.pi_js_undefined(), key_arguments.len, &key_arguments));
            defer engine.freeValue(name);
            try defineData(engine, shared_descriptor, result, name, try copyValue(engine, shared_descriptor, child, active, omit));
        }
        return result;
    }
    const result = try invokeBuiltin(engine, "Object", "create", &.{actual_prototype});
    errdefer engine.freeValue(result);
    for (0..try vm.length(engine, keys)) |index| {
        const key = try engine.checked(c.JS_GetPropertyUint32(engine.context, keys, @intCast(index)));
        defer engine.freeValue(key);
        if (c.JS_IsSymbol(key)) return throwType(engine, "Value contains a symbol key and is not strict JSON");
        const desc = try descriptor(engine, value, key);
        defer engine.freeValue(desc);
        if (!try validDescriptor(engine, desc)) return throwType(engine, "Value must contain strict JSON enumerable data properties");
        const child = try vm.get(engine, desc, "value");
        defer engine.freeValue(child);
        if (omit and c.JS_IsUndefined(child)) continue;
        try defineData(engine, shared_descriptor, result, key, try copyValue(engine, shared_descriptor, child, active, omit));
    }
    return result;
}
pub fn check(engine: *Engine, value: c.JSValue) !bool {
    const active = try newSet(engine);
    defer engine.freeValue(active);
    return checkValue(engine, value, active);
}
fn checkValue(engine: *Engine, value: c.JSValue, active: c.JSValue) anyerror!bool {
    if (primitive(value)) return true;
    if (c.JS_IsNumber(value)) return finite(engine, value);
    if (!isObject(engine, value)) return false;
    const array = try isArray(engine, value);
    const actual_prototype = try invokeBuiltin(engine, "Object", "getPrototypeOf", &.{value});
    defer engine.freeValue(actual_prototype);
    const expected_prototype = try prototype(engine, if (array) "Array" else "Object");
    defer engine.freeValue(expected_prototype);
    if (!c.JS_IsStrictEqual(engine.context, actual_prototype, expected_prototype) and (array or !c.JS_IsNull(actual_prototype))) return false;
    const keys = try ownKeys(engine, value);
    defer engine.freeValue(keys);
    if (array and try vm.length(engine, keys) != try vm.length(engine, value) + 1) return false;
    for (0..try vm.length(engine, keys)) |index| {
        const key = try engine.checked(c.JS_GetPropertyUint32(engine.context, keys, @intCast(index)));
        defer engine.freeValue(key);
        if (c.JS_IsSymbol(key)) return false;
    }
    if (try contains(engine, active, value)) return false;
    try mark(engine, active, value);
    const result = checkBody(engine, value, active, array) catch |err| {
        const original = if (engine.captured_exception) |exception| c.JS_DupValue(engine.context, exception) else null;
        defer if (original) |exception| engine.freeValue(exception);
        try unmark(engine, active, value);
        restoreFailure(engine, original);
        return err;
    };
    try unmark(engine, active, value);
    return result;
}
fn checkBody(engine: *Engine, value: c.JSValue, active: c.JSValue, array: bool) !bool {
    if (array) {
        var index: u32 = 0;
        while (index < try vm.length(engine, value)) : (index += 1) {
            const desc = try descriptor(engine, value, c.pi_js_int32(engine.context, @bitCast(index)));
            defer engine.freeValue(desc);
            if (!try validDescriptor(engine, desc)) return false;
            const child = try vm.get(engine, desc, "value");
            defer engine.freeValue(child);
            if (!try checkValue(engine, child, active)) return false;
        }
        return true;
    }
    const descriptors = try invokeBuiltin(engine, "Object", "getOwnPropertyDescriptors", &.{value});
    defer engine.freeValue(descriptors);
    const values = try invokeBuiltin(engine, "Object", "values", &.{descriptors});
    defer engine.freeValue(values);
    for (0..try vm.length(engine, values)) |index| {
        const desc = try engine.checked(c.JS_GetPropertyUint32(engine.context, values, @intCast(index)));
        defer engine.freeValue(desc);
        if (!try validDescriptor(engine, desc)) return false;
        const child = try vm.get(engine, desc, "value");
        defer engine.freeValue(child);
        if (!try checkValue(engine, child, active)) return false;
    }
    return true;
}
fn call(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const value = if (argc > 0) argv[0] else c.pi_js_undefined();
    return (if (operation == 0) copy(engine, data[0], value, if (argc > 1) argv[1] else c.pi_js_undefined()) else checkJs(engine, value)) catch |err| {
        if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
        return engine.throwCaptured();
    };
}
fn checkJs(engine: *Engine, value: c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(try check(engine, value)));
}
/// Private function bundle; a complete Chord module may export the same values.
pub fn functions(engine: *Engine) !c.JSValue {
    if (engine.native_chord_json_functions) |value| return c.JS_DupValue(engine.context, value);
    const shared_descriptor = try vm.object(engine);
    defer engine.freeValue(shared_descriptor);
    try putData(engine, shared_descriptor, "value", c.pi_js_undefined());
    inline for (.{ "writable", "enumerable", "configurable" }) |key| try putData(engine, shared_descriptor, key, c.pi_js_bool(engine.context, 1));
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    var data = [_]c.JSValue{shared_descriptor};
    inline for (.{ "copyJson", "isJsonValue" }, 0..) |name, operation| try putData(engine, result, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, call, name, if (operation == 0) 2 else 1, @intCast(operation), data.len, &data)));
    engine.native_chord_json_functions = c.JS_DupValue(engine.context, result);
    return result;
}

/// The real strict JSON helpers for native durable workflows; owned result.
pub fn copyJson(engine: *Engine, value: c.JSValue, options: c.JSValue) !c.JSValue {
    const exports = try functions(engine);
    defer engine.freeValue(exports);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return vm.invoke(engine, exports, "copyJson", &.{ value, options });
}
pub fn isJsonValue(engine: *Engine, value: c.JSValue) !bool {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return check(engine, value);
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    const json = try functions(engine);
    defer engine.freeValue(json);
    inline for (.{ "copyJson", "isJsonValue" }) |name| try putData(engine, exports, name, try vm.get(engine, json, name));
}

test "native durable VM public Chord root strict JSON and context exports share original function module state" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_durable.zig").install(engine);
    const result = try engine.evalModule(
        "import{copyJson,isJsonValue,BACKGROUND_CONTEXT}from'@earendil-works/chord';import{BACKGROUND_CONTEXT as context}from'@earendil-works/chord/context';" ++
        "const source={a:{value:1},b:undefined},copy=copyJson(source,{omitUndefinedProperties:true});if(copy===source||copy.a===source.a||copy.a.value!==1||'b'in copy||!isJsonValue(copy)||isJsonValue(source)||copyJson.length!==2||isJsonValue.length!==1||BACKGROUND_CONTEXT!==context)throw Error('public strict JSON');export{copyJson,isJsonValue};",
        "public-chord-json.mjs",
    );
    defer engine.freeValue(result);
    const first = try functions(engine);
    defer engine.freeValue(first);
    const second = try functions(engine);
    defer engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
    const exported = try vm.get(engine, result, "copyJson");
    defer engine.freeValue(exported);
    const cached = try vm.get(engine, first, "copyJson");
    defer engine.freeValue(cached);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, exported, cached));
}

test "native durable VM Chord strict JSON raw getter reflection failures are not coerced before guest catch" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const json = try functions(engine);
    defer engine.freeValue(json);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "strictJson", c.JS_DupValue(engine.context, json));
    const result = try engine.eval(
        "let coercions=0;const original={toString(){coercions++;return'raw'}};const value=new Proxy({a:1},{ownKeys(){throw original}});for(const call of[()=>strictJson.copyJson(value),()=>strictJson.isJsonValue(value)]){let caught;try{call()}catch(e){caught=e}if(caught!==original)throw Error('identity')}if(coercions!==0)throw Error('premature coercion');true",
        "chord-json-raw-coercion.js", c.JS_EVAL_TYPE_GLOBAL,
    );
    defer engine.freeValue(result);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}

test "native durable VM private Chord strict JSON matches original65 finite dense descriptor omission alias and prototype cases" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const json = try functions(engine);
    defer engine.freeValue(json);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    inline for (.{ "copyJson", "isJsonValue" }) |name| try vm.put(engine, global, name, try vm.get(engine, json, name));
    const output = try engine.evalModule(
        \\const shared={value:1},cycle={};cycle.self=cycle;
        \\const nullObject=Object.assign(Object.create(null),{a:1}),ownProto=Object.defineProperty({a:1},'__proto__',{value:{retained:true},enumerable:true,writable:true,configurable:true}),accessor={};let reads=0;Object.defineProperty(accessor,'a',{get(){reads++;return 1},enumerable:true});
        \\const hidden=Object.defineProperty({},'a',{value:1}),hiddenIndex=[1];Object.defineProperty(hiddenIndex,'0',{value:1,enumerable:false});const extraArray=[1];extraArray.extra=2;const symbolArray=[1];symbolArray[Symbol('extra')]=2;
        \\const cases=[['null',null],['text','ok'],['boolean',true],['number',1],['negative-zero',-0],['nan',NaN],['positive-infinity',Infinity],['negative-infinity',-Infinity],['undefined',undefined],['bigint',1n],['symbol',Symbol('value')],['function',()=>{}],['null-prototype',nullObject],['prototype-key',ownProto],['shared-alias',{a:shared,b:shared}],['cycle',cycle],['array-cycle',null],['sparse',new Array(2)],['array-extra',extraArray],['array-symbol',symbolArray],['array-hidden-index',hiddenIndex],['accessor',accessor],['hidden',hidden],['symbol-key',{[Symbol('key')]:1}],['date',new Date(0)],['map',new Map()],['set',new Set()],['boxed',new Number(1)],['custom-prototype',Object.create({})],['undefined-property',{a:1,missing:undefined}],['undefined-array',[undefined]],['toJSON',{toJSON(){throw Error('must not run')}}]];const recursive=[];recursive.push(recursive);cases.find(c=>c[0]==='array-cycle')[1]=recursive;
        \\const output=[];for(const [name,value]of cases)for(const omit of [false,true]){const row={name,omit};try{row.valid=isJsonValue(value)}catch(error){row.checkError={name:error.name,message:error.message}}try{const copied=copyJson(value,{omitUndefinedProperties:omit});row.value=copied;row.nullPrototype=typeof copied==='object'&&copied!==null&&Object.getPrototypeOf(copied)===null;row.aliasFree=name==='shared-alias'?copied.a!==copied.b:true;row.negativeZero=Object.is(copied,-0)}catch(error){row.error={name:error.name,message:error.message}}output.push(row)}output.push({accessorReads:reads});globalThis.result=JSON.stringify(output);
    , "native-chord-json-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-chord-json-source-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/chord-strict-json-1ced.json"), "\r\n "), text);
}

fn allocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const json = try functions(engine);
    defer engine.freeValue(json);
    const value = try engine.eval("({a:{shared:true},b:[1,2,3],nullObject:Object.assign(Object.create(null),{value:'fixture'}),omitted:undefined})", "native-chord-json-gpa", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    const options = try vm.object(engine);
    defer engine.freeValue(options);
    try putData(engine, options, "omitUndefinedProperties", c.pi_js_bool(engine.context, 1));
    const cloned = try vm.invoke(engine, json, "copyJson", &.{ value, options });
    defer engine.freeValue(cloned);
    try std.testing.expect(try check(engine, cloned));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, value, cloned));
}
test "native durable VM private Chord strict JSON function roots descriptor recursion and failure cleanup unwind every allocation failure" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            allocationExercise(gpa) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and err == error.JavaScriptException) return error.OutOfMemory;
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

test "native durable VM Chord JSON preserves Source reflection callbacks original errors option getter constructor and shared descriptor reentry" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const json = try functions(engine);
    defer engine.freeValue(json);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    inline for (.{ "copyJson", "isJsonValue" }) |name| try vm.put(engine, global, name, try vm.get(engine, json, name));
    const output = try engine.evalModule(
        \\const output=[],raw={owned:true};
        \\for(const operation of ['copy','check']){const events=[],proxy=new Proxy({a:1},{getPrototypeOf(target){events.push('prototype');return Reflect.getPrototypeOf(target)},ownKeys(target){events.push('keys');return Reflect.ownKeys(target)},getOwnPropertyDescriptor(target,key){events.push('descriptor:'+String(key));return Reflect.getOwnPropertyDescriptor(target,key)}});output.push({name:operation+'-proxy',value:operation==='copy'?copyJson(proxy):isJsonValue(proxy),events})}
        \\for(const operation of ['copy','check']){const proxy=new Proxy({},{getPrototypeOf(){throw raw}});try{operation==='copy'?copyJson(proxy):isJsonValue(proxy)}catch(error){output.push({name:operation+'-raw',raw:error===raw})}}
        \\let reads=0;output.push({name:'omit-option',value:copyJson({missing:undefined},{get omitUndefinedProperties(){reads++;return true}}),reads});
        \\const originalTypeError=TypeError;globalThis.TypeError=function(message){output.push({name:'constructor',message});return raw};try{try{copyJson(undefined)}catch(error){output.push({name:'constructor-raw',raw:error===raw})}}finally{globalThis.TypeError=originalTypeError}
        \\const originalDefine=Object.defineProperty,seen=[];Object.defineProperty=function(target,key,descriptor){seen.push(descriptor);return originalDefine(target,key,descriptor)};try{const value=copyJson({a:{x:1},b:[2,3]});output.push({name:'shared-descriptor',value,same:seen.every(d=>d===seen[0]),cleared:seen.every(d=>d.value===undefined),flags:seen.map(d=>[d.writable,d.enumerable,d.configurable])})}finally{Object.defineProperty=originalDefine}
        \\let nested=false;Object.defineProperty=function(target,key,descriptor){if(!nested){nested=true;copyJson({inner:1})}return originalDefine(target,key,descriptor)};try{const value=copyJson({outer:1});output.push({name:'descriptor-reentry',has:Object.hasOwn(value,'outer'),undefined:value.outer===undefined})}finally{Object.defineProperty=originalDefine}
        \\globalThis.result=JSON.stringify(output);
    , "native-chord-json-callbacks-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-chord-json-callbacks-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/chord-strict-json-callbacks-1ced.json"), "\r\n "), text);
}
