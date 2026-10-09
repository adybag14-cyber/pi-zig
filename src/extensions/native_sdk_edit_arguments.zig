//! Edit factory argument preparation preserves the input object's identity and
//! mutations; the legacy pair returns a fresh object with those keys removed.
const std = @import("std");
const engine_mod = @import("engine.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
const vm = @import("native_values.zig");

pub fn create(engine: *Engine) !c.JSValue {
    return engine.checked(c.JS_NewCFunction(engine.context, callback, "prepareEditArguments", 1));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return prepare(engine, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn single(engine: *Engine, value: c.JSValue) !bool {
    if (!c.JS_IsObject(value) or c.JS_IsArray(value) or c.JS_IsFunction(engine.context, value)) return false;
    const old = try vm.get(engine, value, "oldText");
    defer engine.freeValue(old);
    if (!c.JS_IsString(old)) return false;
    const new = try vm.get(engine, value, "newText");
    defer engine.freeValue(new);
    return c.JS_IsString(new);
}
fn one(engine: *Engine, value: c.JSValue) !c.JSValue {
    const result = try vm.array(engine);
    errdefer engine.freeValue(result);
    if (c.JS_SetPropertyUint32(engine.context, result, 0, c.JS_DupValue(engine.context, value)) < 0) return error.JavaScriptException;
    return result;
}
pub fn prepare(engine: *Engine, input: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(input) or c.JS_IsFunction(engine.context, input)) return c.JS_DupValue(engine.context, input);
    const original = try vm.get(engine, input, "edits");
    defer engine.freeValue(original);
    if (c.JS_IsString(original)) {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const json = try vm.get(engine, global, "JSON");
        defer engine.freeValue(json);
        const parse = try vm.get(engine, json, "parse");
        defer engine.freeValue(parse);
        const again = try vm.get(engine, input, "edits");
        defer engine.freeValue(again);
        var args = [_]c.JSValue{again};
        const parsed = c.JS_Call(engine.context, parse, json, 1, &args);
        if (c.JS_IsException(parsed)) {
            engine.freeValue(c.JS_GetException(engine.context));
        } else {
            defer engine.freeValue(parsed);
            if (c.JS_IsArray(parsed)) try vm.put(engine, input, "edits", c.JS_DupValue(engine.context, parsed)) else if (try single(engine, parsed)) try vm.put(engine, input, "edits", try one(engine, parsed));
        }
    } else if (try single(engine, original)) {
        const again = try vm.get(engine, input, "edits");
        defer engine.freeValue(again);
        try vm.put(engine, input, "edits", try one(engine, again));
    }
    const old_check = try vm.get(engine, input, "oldText");
    defer engine.freeValue(old_check);
    if (!c.JS_IsString(old_check)) return c.JS_DupValue(engine.context, input);
    const new_check = try vm.get(engine, input, "newText");
    defer engine.freeValue(new_check);
    if (!c.JS_IsString(new_check)) return c.JS_DupValue(engine.context, input);
    const existing = try vm.get(engine, input, "edits");
    defer engine.freeValue(existing);
    const edits = try vm.array(engine);
    defer engine.freeValue(edits);
    if (c.JS_IsArray(existing)) {
        const values = try vm.get(engine, input, "edits");
        defer engine.freeValue(values);
        for (0..try vm.length(engine, values)) |index| if (c.JS_SetPropertyUint32(engine.context, edits, @intCast(index), try engine.checked(c.JS_GetPropertyUint32(engine.context, values, @intCast(index)))) < 0) return error.JavaScriptException;
    }
    const entry = try vm.object(engine);
    defer engine.freeValue(entry);
    try vm.put(engine, entry, "oldText", try vm.get(engine, input, "oldText"));
    try vm.put(engine, entry, "newText", try vm.get(engine, input, "newText"));
    if (c.JS_SetPropertyUint32(engine.context, edits, @intCast(try vm.length(engine, edits)), c.JS_DupValue(engine.context, entry)) < 0) return error.JavaScriptException;
    const old_discard = try vm.get(engine, input, "oldText");
    defer engine.freeValue(old_discard);
    const new_discard = try vm.get(engine, input, "newText");
    defer engine.freeValue(new_discard);
    const rest = try vm.object(engine);
    errdefer engine.freeValue(rest);
    const old_atom = c.JS_NewAtom(engine.context, "oldText");
    defer c.JS_FreeAtom(engine.context, old_atom);
    const new_atom = c.JS_NewAtom(engine.context, "newText");
    defer c.JS_FreeAtom(engine.context, new_atom);
    var properties: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &properties, &count, input, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, properties, count);
    for (properties[0..count]) |property| {
        if (property.atom == old_atom or property.atom == new_atom) continue;
        const value = try engine.checked(c.JS_GetProperty(engine.context, input, property.atom));
        if (c.JS_DefinePropertyValue(engine.context, rest, property.atom, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    try vm.put(engine, rest, "edits", c.JS_DupValue(engine.context, edits));
    return rest;
}

test "ToolInfo edit factory preparation preserves real mutations legacy rest and raw failures" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "prepare", try create(engine));
    const result = try engine.eval(
        "for(const input of [undefined,null,false,0,'x'])if(prepare(input)!==input)throw Error('primitive');" ++
            "const single={path:'a',edits:{oldText:'a',newText:'b'}};if(prepare(single)!==single||!Array.isArray(single.edits))throw Error('single');" ++
            "for(const edits of ['[{\"oldText\":\"a\",\"newText\":\"b\"}]','{\"oldText\":\"a\",\"newText\":\"b\"}']){const input={edits};if(prepare(input)!==input||!Array.isArray(input.edits)||input.edits.length!==1)throw Error('string');}" ++
            "const invalid={edits:'{broken'};if(prepare(invalid)!==invalid||invalid.edits!=='{broken')throw Error('invalid');" ++
            "const token=Symbol('kept'),legacy={path:'a',oldText:'old',newText:'new',edits:[],[token]:42};const output=prepare(legacy);if(output===legacy||'oldText'in output||'newText'in output||output[token]!==42||output.edits===legacy.edits||output.edits[0].oldText!=='old'||legacy.oldText!=='old')throw Error('legacy');" ++
            "const raw={owned:true};try{prepare({get edits(){throw raw}});throw Error('accepted')}catch(e){if(e!==raw)throw e}true",
        "edit-factory-preparation.js",
        c.JS_EVAL_TYPE_GLOBAL,
    );
    defer engine.freeValue(result);
}
