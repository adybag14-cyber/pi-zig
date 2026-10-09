//! Capture the VM's standard clone operations before extension code can replace
//! global constructors or prototype methods. The registry is never exported.
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
fn checked(value: c.JSValue) !c.JSValue {
    if (c.JS_IsException(value)) return error.OutOfMemory;
    return value;
}
fn put(context: *c.JSContext, object: c.JSValue, key: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_SetPropertyStr(context, object, key, value) < 0) return error.OutOfMemory;
}
pub fn create(context: *c.JSContext) !c.JSValue {
    const global = c.JS_GetGlobalObject(context);
    defer c.JS_FreeValue(context, global);
    const result = try checked(c.JS_NewObjectProto(context, c.pi_js_null()));
    errdefer c.JS_FreeValue(context, result);
    inline for (.{ "Error", "EvalError", "RangeError", "ReferenceError", "SyntaxError", "TypeError", "URIError", "Map", "Set", "DataView", "String", "Function" }) |name| {
        const constructor = try checked(c.JS_GetPropertyStr(context, global, name));
        defer c.JS_FreeValue(context, constructor);
        try put(context, result, name, c.JS_DupValue(context, constructor));
        if (comptime @import("std").mem.eql(u8, name, "Function")) {
            const prototype = try checked(c.JS_GetPropertyStr(context, constructor, "prototype"));
            defer c.JS_FreeValue(context, prototype);
            try put(context, result, "Function.toString", try checked(c.JS_GetPropertyStr(context, prototype, "toString")));
        }
        if (comptime @import("std").mem.eql(u8, name, "Map") or @import("std").mem.eql(u8, name, "Set")) {
            const prototype = try checked(c.JS_GetPropertyStr(context, constructor, "prototype"));
            defer c.JS_FreeValue(context, prototype);
            const is_map = comptime @import("std").mem.eql(u8, name, "Map");
            const iter_name = if (is_map) "entries" else "values";
            const entries = try checked(c.JS_GetPropertyStr(context, prototype, iter_name));
            defer c.JS_FreeValue(context, entries);
            try put(context, result, name ++ ".iterate", c.JS_DupValue(context, entries));
            try put(context, result, name ++ ".insert", try checked(c.JS_GetPropertyStr(context, prototype, if (is_map) "set" else "add")));
            const object = try checked(c.JS_CallConstructor(context, constructor, 0, null));
            defer c.JS_FreeValue(context, object);
            const iterator = try checked(c.JS_Call(context, entries, object, 0, null));
            defer c.JS_FreeValue(context, iterator);
            try put(context, result, name ++ ".next", try checked(c.JS_GetPropertyStr(context, iterator, "next")));
        }
        if (comptime @import("std").mem.eql(u8, name, "DataView")) {
            const prototype = try checked(c.JS_GetPropertyStr(context, constructor, "prototype"));
            defer c.JS_FreeValue(context, prototype);
            inline for (.{ "buffer", "byteOffset", "byteLength" }) |key| {
                const atom = c.JS_NewAtom(context, key);
                defer c.JS_FreeAtom(context, atom);
                var descriptor: c.JSPropertyDescriptor = undefined;
                if (c.JS_GetOwnProperty(context, &descriptor, prototype, atom) <= 0) return error.OutOfMemory;
                defer c.JS_FreeValue(context, descriptor.value);
                defer c.JS_FreeValue(context, descriptor.getter);
                defer c.JS_FreeValue(context, descriptor.setter);
                try put(context, result, "DataView." ++ key, c.JS_DupValue(context, descriptor.getter));
            }
        }
    }
    return result;
}
