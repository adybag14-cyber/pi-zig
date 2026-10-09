//! Source ToolInfo rows retain definition values. Schema identity, hidden
//! metadata, callback errors and shared nested annotations never pass JSON.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Exposure = struct {
    context: ?*anyopaque,
    read: *const fn (?*anyopaque, c.JSValue) anyerror!c.JSValue,
};
pub fn putData(engine: *Engine, target: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, target, key, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}
fn shallow(engine: *Engine, value: c.JSValue) !c.JSValue {
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) return result;
    // CopyDataProperties boxes primitives and includes enumerable symbols.
    const boxed = try engine.checked(c.JS_ToObject(engine.context, value));
    defer engine.freeValue(boxed);
    var keys: [*c]c.JSPropertyEnum = null;
    var length: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &keys, &length, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, keys, length);
    for (0..length) |index| {
        const child = try engine.checked(c.JS_GetProperty(engine.context, boxed, keys[index].atom));
        if (c.JS_DefinePropertyValue(engine.context, result, keys[index].atom, child, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    return result;
}
pub fn project(engine: *Engine, definition: c.JSValue, source_info: c.JSValue, exposure: ?Exposure) !c.JSValue {
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    inline for (.{ "name", "description", "parameters", "promptGuidelines" }) |key| try putData(engine, result, key, try vm.get(engine, definition, key));
    const name = try vm.get(engine, definition, "name");
    defer engine.freeValue(name);
    var selected = if (exposure) |resolver| try resolver.read(resolver.context, name) else try vm.get(engine, definition, "exposure");
    if (c.JS_IsUndefined(selected) or c.JS_IsNull(selected)) {
        engine.freeValue(selected);
        selected = try engine.checked(c.JS_NewString(engine.context, "direct"));
    }
    try putData(engine, result, "exposure", selected);
    inline for (.{ "namespace", "annotations" }) |key| {
        const test_value = try vm.get(engine, definition, key);
        defer engine.freeValue(test_value);
        if (c.JS_ToBool(engine.context, test_value) != 0) {
            const value = try vm.get(engine, definition, key);
            defer engine.freeValue(value);
            try putData(engine, result, key, if (comptime std.mem.eql(u8, key, "annotations")) try shallow(engine, value) else c.JS_DupValue(engine.context, value));
        }
    }
    try putData(engine, result, "sourceInfo", c.JS_DupValue(engine.context, source_info));
    return result;
}

fn testProject(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return project(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), null) catch |err| {
        if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
        return engine.throwCaptured();
    };
}
test "native durable VM ToolInfo rows preserve actual SDK getter ordering symbols original exceptions and data-property semantics" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bindFunction("nativeToolInfo", testProject, 2);
    const output = try engine.evalModule(
        \\const output=[],events=[],symbol=Symbol('shared-annotation'),raw={name:'DataCloneError',owned:true},original={name:'fixture_identity',description:'original description',parameters:{type:'object'},promptGuidelines:['fixture guideline'],exposure:undefined,namespace:{name:'fixture_namespace'},annotations:{get hint(){events.push('annotation-hint');return true},[symbol]:{shared:true}}},definition={};
        \\for(const key of ['name','description','parameters','promptGuidelines','exposure','namespace','annotations'])Object.defineProperty(definition,key,{get(){events.push(key);return original[key]},configurable:true});
        \\Object.defineProperty(Object.prototype,'parameters',{set(){events.push('prototype-setter')},configurable:true});
        \\try{const info=nativeToolInfo(definition,{});output.push({keys:Object.keys(info),schema:info.parameters===original.parameters,guidelines:info.promptGuidelines===original.promptGuidelines,namespace:info.namespace===original.namespace,annotationsCopy:info.annotations!==original.annotations,symbol:info.annotations[symbol]===original.annotations[symbol],events:[...events]})}finally{delete Object.prototype.parameters}
        \\events.length=0;Object.defineProperty(definition,'parameters',{get(){events.push('parameters');throw raw},configurable:true});try{nativeToolInfo(definition,{})}catch(error){output.push({raw:error===raw,events:[...events]})}globalThis.result=JSON.stringify(output);
    , "native-toolinfo-source-getters");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-toolinfo-source-getters-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/sdk-toolinfo-getters-symbols-1ced.json"), "\r\n "), text);
}
