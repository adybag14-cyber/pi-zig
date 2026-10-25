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
    inline for (.{ "Error", "EvalError", "RangeError", "ReferenceError", "SyntaxError", "TypeError", "URIError", "Map", "Set", "DataView", "String", "Function", "FinalizationRegistry", "Array", "Object", "Symbol", "RegExp", "Number" }) |name| {
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
            if (is_map) {
                try put(context, result, "Map.get", try checked(c.JS_GetPropertyStr(context, prototype, "get")));
                try put(context, result, "Map.delete", try checked(c.JS_GetPropertyStr(context, prototype, "delete")));
                const atom = c.JS_NewAtom(context, "size");
                defer c.JS_FreeAtom(context, atom);
                var descriptor: c.JSPropertyDescriptor = undefined;
                if (c.JS_GetOwnProperty(context, &descriptor, prototype, atom) <= 0) return error.OutOfMemory;
                defer c.JS_FreeValue(context, descriptor.value);
                defer c.JS_FreeValue(context, descriptor.getter);
                defer c.JS_FreeValue(context, descriptor.setter);
                try put(context, result, "Map.size", c.JS_DupValue(context, descriptor.getter));
            }
        }
        if (comptime @import("std").mem.eql(u8, name, "Array") or @import("std").mem.eql(u8, name, "FinalizationRegistry")) {
            const prototype = try checked(c.JS_GetPropertyStr(context, constructor, "prototype"));
            defer c.JS_FreeValue(context, prototype);
            const method = if (comptime @import("std").mem.eql(u8, name, "Array")) "forEach" else "register";
            try put(context, result, name ++ "." ++ method, try checked(c.JS_GetPropertyStr(context, prototype, method)));
            if (comptime @import("std").mem.eql(u8, name, "Array")) {
                try put(context, result, "Array.some", try checked(c.JS_GetPropertyStr(context, prototype, "some")));
                try put(context, result, "Array.slice", try checked(c.JS_GetPropertyStr(context, prototype, "slice")));
                try put(context, result, "Array.indexOf", try checked(c.JS_GetPropertyStr(context, prototype, "indexOf")));
                try put(context, result, "Array.push", try checked(c.JS_GetPropertyStr(context, prototype, "push")));
                // Exact primordial uncurryThis: Function.prototype.call.bind(fn).
                // Bind while the realm is pristine, before guest code can change
                // Function metadata, Array iteration or the iterator prototype.
                const symbol = try checked(c.JS_GetIteratorSymbol(context));
                defer c.JS_FreeValue(context, symbol);
                const atom = c.JS_ValueToAtom(context, symbol);
                if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
                defer c.JS_FreeAtom(context, atom);
                const iterate = try checked(c.JS_GetProperty(context, prototype, atom));
                defer c.JS_FreeValue(context, iterate);
                const array = try checked(c.JS_NewArray(context));
                defer c.JS_FreeValue(context, array);
                const iterator = try checked(c.JS_Call(context, iterate, array, 0, null));
                defer c.JS_FreeValue(context, iterator);
                const next = try checked(c.JS_GetPropertyStr(context, iterator, "next"));
                defer c.JS_FreeValue(context, next);
                const function_constructor = try checked(c.JS_GetPropertyStr(context, global, "Function"));
                defer c.JS_FreeValue(context, function_constructor);
                const function_prototype = try checked(c.JS_GetPropertyStr(context, function_constructor, "prototype"));
                defer c.JS_FreeValue(context, function_prototype);
                const call_method = try checked(c.JS_GetPropertyStr(context, function_prototype, "call"));
                defer c.JS_FreeValue(context, call_method);
                const bind_method = try checked(c.JS_GetPropertyStr(context, function_prototype, "bind"));
                defer c.JS_FreeValue(context, bind_method);
                var factory_args = [_]c.JSValue{iterate};
                var next_args = [_]c.JSValue{next};
                try put(context, result, "Array.iterate.uncurried",
                    try checked(c.JS_Call(context, bind_method, call_method, 1, &factory_args)));
                try put(context, result, "Array.next.uncurried",
                    try checked(c.JS_Call(context, bind_method, call_method, 1, &next_args)));
            }
        }
        if (comptime @import("std").mem.eql(u8, name, "Number")) {
            const prototype = try checked(c.JS_GetPropertyStr(context, constructor, "prototype"));
            defer c.JS_FreeValue(context, prototype);
            try put(context, result, "Number.toFixed", try checked(c.JS_GetPropertyStr(context, prototype, "toFixed")));
        }
        if (comptime @import("std").mem.eql(u8, name, "Object")) {
            try put(context, result, "Object.defineProperty", try checked(c.JS_GetPropertyStr(context, constructor, "defineProperty")));
            try put(context, result, "Object.freeze", try checked(c.JS_GetPropertyStr(context, constructor, "freeze")));
            try put(context, result, "Object.entries", try checked(c.JS_GetPropertyStr(context, constructor, "entries")));
            try put(context, result, "Object.getPrototypeOf", try checked(c.JS_GetPropertyStr(context, constructor, "getPrototypeOf")));
            try put(context, result, "Object.setPrototypeOf", try checked(c.JS_GetPropertyStr(context, constructor, "setPrototypeOf")));
            const prototype = try checked(c.JS_GetPropertyStr(context, constructor, "prototype"));
            defer c.JS_FreeValue(context, prototype);
            try put(context, result, "Object.hasOwnProperty", try checked(c.JS_GetPropertyStr(context, prototype, "hasOwnProperty")));
        }
        if (comptime @import("std").mem.eql(u8, name, "String") or @import("std").mem.eql(u8, name, "RegExp")) {
            const prototype = try checked(c.JS_GetPropertyStr(context, constructor, "prototype"));
            defer c.JS_FreeValue(context, prototype);
            if (comptime @import("std").mem.eql(u8, name, "String")) {
                try put(context, result, "String.split", try checked(c.JS_GetPropertyStr(context, prototype, "split")));
                try put(context, result, "String.toLowerCase", try checked(c.JS_GetPropertyStr(context, prototype, "toLowerCase")));
                try put(context, result, "String.toUpperCase", try checked(c.JS_GetPropertyStr(context, prototype, "toUpperCase")));
                try put(context, result, "String.padStart", try checked(c.JS_GetPropertyStr(context, prototype, "padStart")));
            } else {
                try put(context, result, "RegExp.exec", try checked(c.JS_GetPropertyStr(context, prototype, "exec")));
            }
        }
        if (comptime @import("std").mem.eql(u8, name, "Symbol")) {
            try put(context, result, "Symbol.iterator", try checked(c.JS_GetPropertyStr(context, constructor, "iterator")));
            try put(context, result, "Symbol.hasInstance", try checked(c.JS_GetPropertyStr(context, constructor, "hasInstance")));
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
    const math = try checked(c.JS_GetPropertyStr(context, global, "Math"));
    defer c.JS_FreeValue(context, math);
    try put(context, result, "Math.floor", try checked(c.JS_GetPropertyStr(context, math, "floor")));
    // Node util's actual private symbol is shared by every cache instance in
    // this Engine, including independently created SourceMapCacheMap classes.
    try put(context, result, "Node.source_map_data_private_symbol",
        try checked(c.JS_NewPrivateSymbol(context, "node:source_map_data")));
    return result;
}
