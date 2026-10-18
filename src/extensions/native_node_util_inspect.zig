//! Actual consumed Node24 inspect/format paths. No event-inspector alias.
//! Unsupported exotic/layout capabilities stay explicit and unselected.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
const f = @import("native_node_module_callable.zig");
const primitive = @import("native_node_util_inspect_primitive.zig");
const utf16 = @import("native_utf16.zig");
const ops = @import("native_node_inspect_operations.zig");
const Scope = ops.Scope;
const owned = @import("native_sdk_owned_completion.zig");
const option_names = .{ "showHidden", "depth", "colors", "customInspect", "showProxy", "maxArrayLength", "maxStringLength", "breakLength", "compact", "sorted", "getters", "numericSeparator" };
pub const Inputs = struct {
    string: c.JSValue, object: c.JSValue, object_prototype: c.JSValue,
    function_to_string: c.JSValue,
    custom_symbol: c.JSValue, to_primitive: c.JSValue, to_string_tag: c.JSValue,
    has_instance: c.JSValue,
    /// Bootstrap array of actual {prototype,constructor,name} records for the
    /// retained Source wellKnownPrototypes; not late guest constructor reads.
    well_known: c.JSValue,
    /// Bootstrap ordinary own global names matching /^[A-Z][a-zA-Z0-9]+$/.
    /// An own-key set captured before guest code, not an assumed fixed list.
    built_in_names: c.JSValue,
    /// Captured original ObjectAssign used by the actual default-options setter.
    object_assign: c.JSValue,
    pub fn deinit(self: Inputs, engine: *v.em.Engine) void {
        var completion = owned.Completion.initVoid(engine, {});
        inline for (std.meta.fields(Inputs)) |field| completion.release(@field(self, field.name));
        completion.finishVoid() catch {};
    }
};
/// Called at genuine bootstrap before guest code, beside color primordial
/// capture. A late module initializer must receive this retained snapshot.
pub fn capturePrimordials(engine: *v.em.Engine) !Inputs {
    var stage = Scope.init(engine);
    var outputs: [std.meta.fields(Inputs).len]c.JSValue = @splat(c.pi_js_undefined());
    var host_error: ?anyerror = null;
    if (captureBody(&stage.values)) |result| {
        inline for (std.meta.fields(Inputs), 0..) |field, i| outputs[i] = @field(result, field.name);
    } else |err| host_error = err;
    try stage.boundary.finishMany(host_error, &stage.values, &outputs);
    var result: Inputs = undefined;
    inline for (std.meta.fields(Inputs), 0..) |field, i| @field(result, field.name) = outputs[i];
    return result;
}
fn captureBody(s: *v.Scope) !Inputs {
    const engine = s.engine;
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    const global = try ops.own(s, try h.success(engine, try engine.checked(c.JS_GetGlobalObject(engine.context))));
    const object = try h.get(s, global, "Object"); const object_prototype = try h.get(s, object, "prototype");
    const object_assign = try h.get(s, object, "assign");
    const string = try h.get(s, global, "String");
    const function_to_string = try h.get(s, try ops.own(s, try engine.checked(c.JS_GetFunctionProto(engine.context))), "toString");
    const symbol = try h.get(s, global, "Symbol");
    const custom = try h.call(s, try h.get(s, symbol, "for"), symbol, &.{try ops.bytes(s, "nodejs.util.inspect.custom")});
    const to_primitive = try h.get(s, symbol, "toPrimitive"); const to_string_tag = try h.get(s, symbol, "toStringTag");
    const has_instance = try keyGet(s, try ops.own(s, try engine.checked(c.JS_GetFunctionProto(engine.context))), try h.get(s, symbol, "hasInstance"));
    const names = try ops.nullObject(s);
    const keys = try propKeys(s, global, false, true); defer c.JS_FreePropertyEnum(engine.context, keys.ptr, @intCast(keys.len));
    for (keys) |entry| {
        const key = try ops.atomValue(s, entry.atom);
        const units = try utf16.unitsAlloc(engine, key); defer engine.gpa.free(units);
        const matches = units.len >= 2 and units[0] >= 'A' and units[0] <= 'Z' and for (units[1..]) |unit| {
            if (!((unit >= 'A' and unit <= 'Z') or (unit >= 'a' and unit <= 'z') or (unit >= '0' and unit <= '9'))) break false;
        } else true;
        if (matches) {
            try ops.defineAtom(s, names, entry.atom, c.pi_js_bool(engine.context, 1), c.JS_PROP_C_W_E);
        }
    }
    const known = try ops.array(s);
    inline for (.{ "Array", "ArrayBuffer", "Function", "Map", "Set", "Object", "TypedArray", "RegExp", "Date", "DataView", "Error", "AggregateError", "RangeError", "TypeError", "Boolean", "Number", "String", "Promise", "WeakMap", "WeakSet" }, 0..) |name, i| {
        const constructor = if (comptime std.mem.eql(u8, name, "TypedArray")) try prototype(s, try h.get(s, global, "Uint8Array")) else try h.get(s, global, name);
        const entry = try ops.object(s); try h.put(engine, entry, "prototype", try h.get(s, constructor, "prototype")); try h.put(engine, entry, "constructor", constructor); try h.put(engine, entry, "name", try ops.bytes(s, name));
        try ops.index(s, known, @intCast(i), entry);
    }
    return .{ .string = c.JS_DupValue(engine.context, string), .object = c.JS_DupValue(engine.context, object), .object_prototype = c.JS_DupValue(engine.context, object_prototype), .function_to_string = c.JS_DupValue(engine.context, function_to_string),
        .custom_symbol = c.JS_DupValue(engine.context, custom), .to_primitive = c.JS_DupValue(engine.context, to_primitive), .to_string_tag = c.JS_DupValue(engine.context, to_string_tag), .has_instance = c.JS_DupValue(engine.context, has_instance),
        .well_known = c.JS_DupValue(engine.context, known), .built_in_names = c.JS_DupValue(engine.context, names), .object_assign = c.JS_DupValue(engine.context, object_assign) };
}
pub const Exports = struct {
    inspect: c.JSValue, format: c.JSValue,
    pub fn deinit(self: Exports, engine: *v.em.Engine) void {
        var completion = owned.Completion.initVoid(engine, {});
        completion.release(self.inspect); completion.release(self.format);
        completion.finishVoid() catch {};
    }
};
/// Host-only formatter seam: `known_inspect` is the actual inspect returned by
/// this factory, retained by its assembler, never a guest-supplied function.
/// Exposes the SAME Source classifier and captured builtin-name authority.
pub fn createStringClassifier(engine:*v.em.Engine,known_inspect:c.JSValue)!c.JSValue {
    var stage=Scope.init(engine);
    return stage.finish(classifierBody(&stage,known_inspect));
}
fn classifierBody(s:*Scope,known_inspect:c.JSValue)!c.JSValue {
    try s.pending();const engine=s.engine;const roots=try f.capturedRoots(engine,known_inspect);
    if(roots.len!=13)return error.ActualInspectOwnerRequired;
    const previous=try s.get(roots[0],"cjsStringClassifier");
    if(!c.JS_IsUndefined(previous))return c.JS_DupValue(engine.context,previous);
    const classifier=try s.own(try f.create(engine,"hasBuiltInToString",1,true,classifierCall,roots));
    try s.put(roots[0],"cjsStringClassifier",classifier);
    return c.JS_DupValue(engine.context,classifier);
}
fn classifierCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(classifierValue(&stage.values, args, roots));
}
fn classifierValue(s: *v.Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(s.engine.context, @intFromBool(try hasBuiltInToString(s, roots, h.arg(args, 0))));
}
fn keyGet(s: *v.Scope, value: c.JSValue, key: c.JSValue) !c.JSValue { return ops.key(s, value, key); }
fn descriptor(s: *v.Scope, value: c.JSValue, key: c.JSValue) !?c.JSPropertyDescriptor { return ops.descriptor(s, value, key); }
fn freeDescriptor(engine: *v.em.Engine, item: c.JSPropertyDescriptor) void { ops.freeDescriptor(engine, item); }
fn hasOwn(s: *v.Scope, value: c.JSValue, key: c.JSValue) !bool {
    const item = try descriptor(s, value, key) orelse return false;
    defer freeDescriptor(s.engine, item); errdefer |err| ops.recordFailure(s.engine, err);
    return true;
}
fn propKeys(s: *v.Scope, value: c.JSValue, symbols: bool, hidden: bool) ![]c.JSPropertyEnum { return ops.keys(s, value, symbols, hidden); }
fn instance(s: *v.Scope, value: c.JSValue, constructor: c.JSValue) !bool { return ops.instance(s, value, constructor); }
fn prototype(s: *v.Scope, value: c.JSValue) !c.JSValue { return ops.prototype(s, value); }
fn templateText(s: *v.Scope, value: c.JSValue) !c.JSValue { return ops.text(s, value); }
fn defaultOptions(s: *v.Scope) !c.JSValue {
    const object = try ops.object(s);
    const values = [_]c.JSValue{ c.pi_js_bool(s.engine.context, 0), c.JS_NewInt32(s.engine.context, 2), c.pi_js_bool(s.engine.context, 0), c.pi_js_bool(s.engine.context, 1), c.pi_js_bool(s.engine.context, 0), c.JS_NewInt32(s.engine.context, 100), c.JS_NewInt32(s.engine.context, 10000), c.JS_NewInt32(s.engine.context, 80), c.JS_NewInt32(s.engine.context, 3), c.pi_js_bool(s.engine.context, 0), c.pi_js_bool(s.engine.context, 0), c.pi_js_bool(s.engine.context, 0) };
    inline for (option_names, values) |name, value| {
        try ops.define(s, object, name, value, c.JS_PROP_WRITABLE | c.JS_PROP_ENUMERABLE);
    }
    try ops.preventExtensions(s, object);
    return object;
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Exports {
    var stage = Scope.init(engine);
    var outputs = [_]c.JSValue{c.pi_js_undefined(), c.pi_js_undefined()};
    var host_error: ?anyerror = null;
    if (createBody(&stage.values, inputs)) |result| outputs = .{result.inspect, result.format} else |err| host_error = err;
    try stage.boundary.finishMany(host_error, &stage.values, &outputs);
    return .{ .inspect = outputs[0], .format = outputs[1] };
}
fn createBody(s: *v.Scope, inputs: Inputs) !Exports {
    const engine = s.engine;
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    if (!c.JS_IsFunction(engine.context, inputs.object_assign) or !c.JS_IsFunction(engine.context, inputs.string) or !c.JS_IsFunction(engine.context, inputs.object) or !c.JS_IsFunction(engine.context, inputs.function_to_string) or !c.JS_IsFunction(engine.context, inputs.has_instance) or !c.JS_IsSymbol(inputs.custom_symbol) or !c.JS_IsSymbol(inputs.to_primitive) or !c.JS_IsSymbol(inputs.to_string_tag) or !c.JS_IsArray(inputs.well_known) or !c.JS_IsObject(inputs.built_in_names)) return error.RequiredActualInspectPrimordials;
    const lexical = try ops.nullObject(s);
    const defaults = try defaultOptions(s);
    const no_color = try ops.own(s, try f.create(engine, "stylizeNoColor", 1, true, noColor, &.{}));
    const roots = [_]c.JSValue{ lexical, defaults, inputs.string, inputs.object, inputs.object_prototype, inputs.custom_symbol, inputs.to_primitive, inputs.to_string_tag, inputs.has_instance, inputs.well_known, inputs.built_in_names, inputs.function_to_string, no_color };
    const inspect = try ops.own(s, try f.create(engine, "inspect", 2, true, inspectCall, &roots));
    const format = try ops.own(s, try f.create(engine, "format", 0, true, formatCall, &roots));
    try h.put(engine, lexical, "inspect", inspect);
    try h.put(engine, inspect, "custom", inputs.custom_symbol);
    const get = try ops.own(s, try f.create(engine, "get", 0, false, defaultsGet, &.{defaults}));
    const set = try ops.own(s, try f.create(engine, "set", 1, false, defaultsSet, &.{defaults, inputs.object_assign}));
    try ops.accessor(s, inspect, "defaultOptions", get, set, 0);
    return .{ .inspect = c.JS_DupValue(engine.context, inspect), .format = c.JS_DupValue(engine.context, format) };
}
fn defaultsGet(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { try h.pending(engine); return c.JS_DupValue(engine.context, roots[0]); }
fn defaultsSet(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(defaultsSetBody(&stage.values, args, roots));
}
fn defaultsSetBody(s: *v.Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const engine = s.engine;
    try h.pending(engine);
    const source = h.arg(args, 0); if (!c.JS_IsObject(source) or c.JS_IsFunction(engine.context, source) or c.JS_IsArray(source)) return error.RequiredActualInspectOptionsValidation;
    // Invoke the actual captured primordial. Its per-key descriptor/Get/Set
    // and temporary retirement are the VM's real ObjectAssign operation.
    return c.JS_DupValue(engine.context, try h.call(s, roots[1], c.pi_js_undefined(), &.{roots[0], source}));
}
const Context = struct {
    scope: *v.Scope, roots: []const c.JSValue, options: c.JSValue,
    user_options: c.JSValue,
    indentation: usize = 0,
    current_depth: usize = 0,
    seen: std.ArrayList(c.JSValue) = .empty,
    fn init(s: *v.Scope, roots: []const c.JSValue, args: []const c.JSValue) !Context {
        const options = try ops.object(s);
        try h.put(s.engine, options, "stylize", roots[12]);
        inline for (option_names) |name| try h.put(s.engine, options, name, try h.get(s, roots[1], name));
        var self: Context = .{ .scope = s, .roots = roots, .options = options, .user_options = c.pi_js_undefined() };
        if (args.len > 2 and !c.JS_IsUndefined(args[2])) try h.put(s.engine, options, "depth", args[2]);
        if (args.len > 3 and !c.JS_IsUndefined(args[3])) try h.put(s.engine, options, "colors", args[3]);
        if (args.len > 1) {
            const opts = args[1];
            if (c.JS_IsBool(opts)) try h.put(s.engine, options, "showHidden", opts) else if (s.truthy(opts)) {
                const keys = try propKeys(s, opts, false, false); defer c.JS_FreePropertyEnum(s.engine.context, keys.ptr, @intCast(keys.len));
                for (keys) |entry| {
                    const key = try ops.atomValue(s, entry.atom);
                    var recognized = try ops.same(s, key, "stylize");
                    inline for (option_names) |name| { if (try ops.same(s, key, name)) recognized = true; }
                    if (recognized) {
                        const selected = try keyGet(s, opts, key); try ops.setKey(s, options, key, selected);
                    } else if (c.JS_IsUndefined(self.user_options)) self.user_options = opts;
                }
            }
        }
        if (s.truthy(try h.get(s, options, "colors"))) return error.RequiredActualInspectColorStyles;
        // The Source default stylizer identity is pinned once per module.
        // A user-supplied stylizer also receives the actual internal ctx as
        // `this` in several branches; that mutable context is not yet ported.
        if (!s.equal(try h.get(s, options, "stylize"), roots[12])) return error.RequiredActualInspectCustomStylizeContext;
        inline for (.{ "maxArrayLength", "maxStringLength" }) |name| if (c.JS_IsNull(try h.get(s, options, name))) try h.put(s.engine, options, name, c.JS_NewFloat64(s.engine.context, std.math.inf(f64)));
        return self;
    }
    fn option(self: *Context, name: [*:0]const u8) !c.JSValue { return h.get(self.scope, self.options, name); }
    fn stylize(self: *Context, value: c.JSValue, kind: []const u8) !c.JSValue { return h.call(self.scope, try self.option("stylize"), c.pi_js_undefined(), &.{ value, try ops.bytes(self.scope, kind) }); }
    fn userOptions(self: *Context, cross_context: bool) !c.JSValue {
        const s = self.scope;
        const result = try ops.spread(s, self.options);
        if (!c.JS_IsUndefined(self.user_options)) try ops.copyInto(s, result, self.user_options);
        if (!cross_context) return result;
        try ops.setPrototype(s, result, c.pi_js_null());
        const keys = try propKeys(s, result, false, false); defer c.JS_FreePropertyEnum(s.engine.context, keys.ptr, @intCast(keys.len));
        for (keys) |entry| {
            const key = try ops.atomValue(s, entry.atom);
            const value = try keyGet(s, result, key);
            if (c.JS_IsObject(value)) try ops.remove(s, result, entry.atom);
        }
        const wrapper = try ops.own(s, try f.create(s.engine, "", 2, false, crossStylize, &.{try self.option("stylize")}));
        try ops.setPrototype(s, wrapper, c.pi_js_null());
        try h.put(s.engine, result, "stylize", wrapper); return result;
    }
    fn primitiveValue(self: *Context, value: c.JSValue) !c.JSValue {
        const s = self.scope;
        const separated = s.truthy(try self.option("numericSeparator"));
        if (c.JS_IsNumber(value)) return self.stylize(try primitive.number(s, value, separated), "number");
        if (c.JS_IsBigInt(value)) return self.stylize(try primitive.bigint(s, value, separated), "bigint");
        if (c.JS_IsString(value)) {
            const max = try self.option("maxStringLength"); var maximum: ?usize = null;
            if (!c.JS_IsNull(max)) { const number = try ops.float64(s, max); if (number != std.math.inf(f64)) { if (!std.math.isFinite(number) or number < 0 or @trunc(number) != number or number >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) return error.RequiredAdditionalInspectStringLimit; maximum = @intFromFloat(number); } }
            const line = try ops.float64(s, try self.option("breakLength"));
            return primitive.string(s, value, .{ .max_string_length = maximum, .break_length = line, .indentation = self.indentation, .compact_true = s.equal(try self.option("compact"), c.pi_js_bool(s.engine.context, 1)) }, try self.option("stylize"));
        }
        if (c.JS_IsNull(value)) return self.stylize(try ops.bytes(s, "null"), "null");
        if (c.JS_IsBool(value)) return self.stylize(try ops.bytes(s, if (s.truthy(value)) "true" else "false"), "boolean");
        if (c.JS_IsUndefined(value)) return self.stylize(try ops.bytes(s, "undefined"), "undefined");
        if (c.JS_IsSymbol(value)) return self.stylize(try h.call(s, self.roots[2], c.pi_js_undefined(), &.{value}), "symbol");
        unreachable;
    }
    fn formatValue(self: *Context, input: c.JSValue, recurse: usize) anyerror!c.JSValue {
        const s = self.scope;
        if (!c.JS_IsObject(input) or c.JS_IsNull(input)) return self.primitiveValue(input);
        var value = input; var proxied = false;
        while (c.JS_IsProxy(value)) {
            proxied = true;
            value = ops.proxyTarget(s, value) catch |err| {
                try ops.discardCaught(s.engine, err);
                return self.stylize(try ops.bytes(s, "<Revoked Proxy>"), "special");
            };
        }
        if (proxied and s.truthy(try self.option("showProxy"))) return error.RequiredActualInspectProxyLayout;
        if (s.truthy(try self.option("customInspect"))) {
            const method = try keyGet(s, value, self.roots[5]);
            const inspect = try h.get(s, self.roots[0], "inspect");
            if (c.JS_IsFunction(s.engine.context, method) and !s.equal(method, inspect)) {
                var is_prototype = false;
                if (try descriptor(s, value, try ops.bytes(s, "constructor"))) |item| {
                    defer freeDescriptor(s.engine, item); errdefer |err| ops.recordFailure(s.engine, err);
                    if (!v.nullish(item.value)) is_prototype = s.equal(try h.get(s, item.value, "prototype"), value);
                }
                if (!is_prototype) {
                    const depth = try self.option("depth");
                    const remaining = if (c.JS_IsNull(depth)) depth else try h.binary(s, .subtract, depth, c.JS_NewFloat64(s.engine.context, @floatFromInt(recurse)));
                    const cross = proxied or !s.truthy(try h.call(s, self.roots[8], self.roots[3], &.{input}));
                    const returned = try h.call(s, method, input, &.{ remaining, try self.userOptions(cross), inspect });
                    if (!s.equal(returned, input)) {
                        if (c.JS_IsString(returned)) {
                            if (self.indentation == 0) return returned;
                            const units = try utf16.unitsAlloc(s.engine, returned); defer s.engine.gpa.free(units);
                            var output: std.ArrayList(u16) = .empty; defer output.deinit(s.engine.gpa);
                            for (units) |unit| { try output.append(s.engine.gpa, unit); if (unit == '\n') try output.appendNTimes(s.engine.gpa, ' ', self.indentation); }
                            return ops.utf16(s, output.items);
                        }
                        return self.formatValue(returned, recurse);
                    }
                }
            }
        }
        for (self.seen.items) |prior| if (s.equal(value, prior)) return error.RequiredActualInspectCircularLayout;
        return self.formatRaw(value, recurse);
    }
    fn constructorName(self: *Context, value: c.JSValue) !c.JSValue {
        const s = self.scope;
        var current = value; var first = true;
        const count = try ops.uint32(s, try h.get(s, self.roots[9], "length"));
        while (!c.JS_IsNull(current)) {
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const entry = try ops.at(s, self.roots[9], index);
                if (s.equal(current, try h.get(s, entry, "prototype")) and s.truthy(try h.call(s, self.roots[8], try h.get(s, entry, "constructor"), &.{value}))) return h.get(s, entry, "name");
            }
            if (try descriptor(s, current, try ops.bytes(s, "constructor"))) |item| {
                defer freeDescriptor(s.engine, item); errdefer |err| ops.recordFailure(s.engine, err);
                if (c.JS_IsFunction(s.engine.context, item.value) and !try ops.same(s, try h.get(s, item.value, "name"), "") and try instance(s, value, item.value)) return h.call(s, self.roots[2], c.pi_js_undefined(), &.{try h.get(s, item.value, "name")});
            }
            current = try prototype(s, current);
            if (first and c.JS_IsNull(current)) return c.pi_js_null();
            first = false;
        }
        return error.RequiredActualInspectComplexPrototypeName;
    }
    fn propertyBody(self: *Context, item: c.JSPropertyDescriptor, recurse: usize) !c.JSValue {
        const s = self.scope;
        var body: c.JSValue = undefined;
        if (!c.JS_IsUndefined(item.value)) {
            self.indentation += 2; defer self.indentation -= 2;
            body = try self.formatValue(item.value, recurse);
        } else if (!c.JS_IsUndefined(item.getter)) {
            if (s.truthy(try self.option("getters"))) return error.RequiredActualInspectEvaluatedGetterLayout;
            body = try self.stylize(try ops.bytes(s, if (!c.JS_IsUndefined(item.setter)) "[Getter/Setter]" else "[Getter]"), "special");
        } else if (!c.JS_IsUndefined(item.setter)) body = try self.stylize(try ops.bytes(s, "[Setter]"), "special") else body = try self.stylize(try ops.bytes(s, "undefined"), "undefined");
        return body;
    }
    fn formatProperty(self: *Context, value: c.JSValue, key: c.JSValue, recurse: usize) !c.JSValue {
        const s = self.scope;
        const item = try descriptor(s, value, key) orelse {
            _ = try h.get(s, c.pi_js_undefined(), "value"); unreachable;
        };
        defer freeDescriptor(s.engine, item); errdefer |err| ops.recordFailure(s.engine, err);
        const body = try self.propertyBody(item, recurse);
        var name: c.JSValue = undefined;
        if (c.JS_IsSymbol(key)) return error.RequiredActualInspectSymbolPropertyEscape;
        const units = try utf16.unitsAlloc(s.engine, key); defer s.engine.gpa.free(units);
        const simple = units.len != 0 and for (units, 0..) |unit, i| {
            if (!((unit >= 'A' and unit <= 'Z') or (unit >= 'a' and unit <= 'z') or unit == '_' or (i != 0 and unit >= '0' and unit <= '9'))) break false;
        } else true;
        if (simple) name = if (try ops.same(s, key, "__proto__")) try ops.bytes(s, "['__proto__']") else try self.stylize(key, "name") else name = try self.stylize(try primitive.quote(s, key), "string");
        if (item.flags & c.JS_PROP_ENUMERABLE == 0) name = try h.binary(s, .add, try h.binary(s, .add, try ops.bytes(s, "["), try templateText(s, name)), try ops.bytes(s, "]"));
        const prefix = try h.binary(s, .add, try templateText(s, name), try ops.bytes(s, ": "));
        return h.binary(s, .add, prefix, try templateText(s, body));
    }
    fn formatRaw(self: *Context, value: c.JSValue, recurse: usize) anyerror!c.JSValue {
        const s = self.scope;
        if (s.truthy(try self.option("showHidden"))) return error.RequiredActualInspectPrototypeProperties;
        const constructor = try self.constructorName(value);
        var tag: c.JSValue = undefined;
        tag = keyGet(s, value, self.roots[7]) catch |err| caught: {
            try ops.discardCaught(s.engine, err);
            break :caught try ops.bytes(s, "");
        };
        if (!c.JS_IsString(tag)) tag = try ops.bytes(s, "") else if (!try ops.same(s, tag, "")) {
            if (try descriptor(s, value, self.roots[7])) |item| { defer freeDescriptor(s.engine, item); errdefer |err| ops.recordFailure(s.engine, err); if (item.flags & c.JS_PROP_ENUMERABLE != 0) tag = try ops.bytes(s, ""); }
        }
        // Run the actual Source iterator-presence check before selecting an
        // ordinary object layout. Prototype proxy has-traps remain observable.
        const iterator = try ops.own(s, try s.engine.checked(c.JS_GetIteratorSymbol(s.engine.context)));
        const iterable = try ops.has(s, value, iterator);
        if (c.JS_IsArray(value)) {
            if (!iterable or !try ops.same(s, constructor, "Array") or !try ops.same(s, tag, "")) return error.RequiredActualInspectArrayPrefix;
            return self.formatArray(value, recurse);
        }
        if (c.JS_IsFunction(s.engine.context, value)) return self.formatFunction(value, constructor, tag);
        if (c.JS_GetClassID(value) != c.JS_GetClassID(self.roots[4])) return error.RequiredActualInspectExoticLayout;
        if (iterable) return error.RequiredActualInspectIterableTypeDiscrimination;
        const keys = try propKeys(s, value, true, false); defer c.JS_FreePropertyEnum(s.engine.context, keys.ptr, @intCast(keys.len));
        var prefix = if (c.JS_IsNull(constructor)) try ops.bytes(s, "[Object: null prototype] ") else if (try ops.same(s, constructor, "Object")) try ops.bytes(s, "") else try h.binary(s, .add, constructor, try ops.bytes(s, " "));
        if (!try ops.same(s, tag, "")) return error.RequiredActualInspectTaggedPrefix;
        if (keys.len == 0) return h.binary(s, .add, prefix, try ops.bytes(s, "{}"));
        const depth = try self.option("depth");
        if (!c.JS_IsNull(depth) and s.truthy(try h.binary(s, .greater, c.JS_NewFloat64(s.engine.context, @floatFromInt(recurse)), depth))) {
            if (c.JS_IsNull(constructor)) return self.stylize(try ops.bytes(s, "[Object: null prototype]"), "special");
            return self.stylize(try h.binary(s, .add, try h.binary(s, .add, try ops.bytes(s, "["), constructor), try ops.bytes(s, "]")), "special");
        }
        try self.seen.append(s.engine.gpa, value); defer _ = self.seen.pop();
        self.current_depth = recurse + 1;
        var entries: std.ArrayList(c.JSValue) = .empty; defer entries.deinit(s.engine.gpa);
        for (keys) |entry| {
            const key = try ops.atomValue(s, entry.atom);
            try entries.append(s.engine.gpa, try self.formatProperty(value, key, recurse + 1));
        }
        prefix = try h.binary(s, .add, prefix, try ops.bytes(s, "{"));
        return self.layout(entries.items, prefix, try ops.bytes(s, "}"), recurse + 1, false);
    }
    fn formatFunction(self: *Context, value: c.JSValue, constructor: c.JSValue, tag: c.JSValue) !c.JSValue {
        const s = self.scope;
        const keys = try propKeys(s, value, true, false); defer c.JS_FreePropertyEnum(s.engine.context, keys.ptr, @intCast(keys.len));
        const source = try h.call(s, self.roots[11], value, &.{});
        const units = try utf16.unitsAlloc(s.engine, source); defer s.engine.gpa.free(units);
        const class_prefix = [_]u16{ 'c', 'l', 'a', 's', 's' };
        if (std.mem.startsWith(u16, units, &class_prefix) and units.len > 5 and units[units.len - 1] == '}') return error.RequiredActualInspectClassLayout;
        const class_atom = c.JS_GetClassName(s.engine.runtime, c.JS_GetClassID(value)); defer c.JS_FreeAtom(s.engine.context, class_atom);
        const native_name = try ops.atomValue(s, class_atom);
        const kind = if (try ops.same(s, native_name, "AsyncGeneratorFunction")) "AsyncGeneratorFunction" else if (try ops.same(s, native_name, "GeneratorFunction")) "GeneratorFunction" else if (c.JS_IsAsyncFunction(value)) "AsyncFunction" else "Function";
        var base = try h.binary(s, .add, try ops.bytes(s, "["), try ops.bytes(s, kind));
        if (c.JS_IsNull(constructor)) base = try h.binary(s, .add, base, try ops.bytes(s, " (null prototype)"));
        if (try ops.same(s, try h.get(s, value, "name"), "")) base = try h.binary(s, .add, base, try ops.bytes(s, " (anonymous)")) else {
            const name_is_string = c.JS_IsString(try h.get(s, value, "name"));
            const name = try h.get(s, value, "name");
            if (!name_is_string and c.JS_IsObject(name)) return error.RequiredActualInspectFunctionNameImplicitDepth;
            const formatted = if (name_is_string) name else try self.formatValue(name, 0);
            base = try h.binary(s, .add, try h.binary(s, .add, base, try ops.bytes(s, ": ")), try templateText(s, formatted));
        }
        base = try h.binary(s, .add, base, try ops.bytes(s, "]"));
        if (!c.JS_IsNull(constructor) and !try ops.same(s, constructor, kind)) base = try h.binary(s, .add, try h.binary(s, .add, base, try ops.bytes(s, " ")), constructor);
        if (!try ops.same(s, tag, "") and !s.equal(constructor, tag)) base = try h.binary(s, .add, try h.binary(s, .add, try h.binary(s, .add, base, try ops.bytes(s, " [")), tag), try ops.bytes(s, "]"));
        if (keys.len != 0) return error.RequiredActualInspectFunctionProperties;
        return self.stylize(base, "special");
    }
    fn formatArray(self: *Context, value: c.JSValue, recurse: usize) !c.JSValue {
        const s = self.scope;
        const keys = try propKeys(s, value, true, false); defer c.JS_FreePropertyEnum(s.engine.context, keys.ptr, @intCast(keys.len));
        const length = try ops.uint32(s, try h.get(s, value, "length"));
        for (keys) |entry| {
            const key = try ops.atomValue(s, entry.atom);
            if (!c.JS_IsString(key)) return error.RequiredActualInspectArrayExtraProperties;
            const units = try utf16.unitsAlloc(s.engine, key); defer s.engine.gpa.free(units);
            if (units.len == 0 or (units.len > 1 and units[0] == '0')) return error.RequiredActualInspectArrayExtraProperties;
            var index: u64 = 0;
            for (units) |unit| { if (unit < '0' or unit > '9' or index > std.math.maxInt(u32)) return error.RequiredActualInspectArrayExtraProperties; index = index * 10 + unit - '0'; }
            if (index >= std.math.maxInt(u32)) return error.RequiredActualInspectArrayExtraProperties;
        }
        if (length == 0) return ops.bytes(s, "[]");
        const depth = try self.option("depth");
        if (!c.JS_IsNull(depth) and s.truthy(try h.binary(s, .greater, c.JS_NewFloat64(s.engine.context, @floatFromInt(recurse)), depth))) return self.stylize(try ops.bytes(s, "[Array]"), "special");
        const max_value = try self.option("maxArrayLength");
        if (!c.JS_IsNumber(max_value)) return error.RequiredActualInspectCoercibleArrayLength;
        const maximum = try ops.float64(s, max_value);
        if (std.math.isNan(maximum) or @trunc(maximum) != maximum) return error.RequiredAdditionalInspectArrayLength;
        const take: u32 = if (maximum <= 0) 0 else if (maximum >= length) length else @intFromFloat(maximum);
        try self.seen.append(s.engine.gpa, value); defer _ = self.seen.pop(); self.current_depth = recurse + 1;
        var entries: std.ArrayList(c.JSValue) = .empty; defer entries.deinit(s.engine.gpa);
        var index: u32 = 0;
        while (index < take) : (index += 1) {
            const key = try ops.text(s, c.JS_NewUint32(s.engine.context, index));
            const item = try descriptor(s, value, key) orelse return error.RequiredActualInspectSparseArray;
            defer freeDescriptor(s.engine, item); errdefer |err| ops.recordFailure(s.engine, err);
            try entries.append(s.engine.gpa, try self.propertyBody(item, recurse + 1));
        }
        if (take < length) {
            const text = try std.fmt.allocPrint(s.engine.gpa, "... {d} more item{s}", .{ length - take, if (length - take > 1) "s" else "" }); defer s.engine.gpa.free(text);
            try entries.append(s.engine.gpa, try ops.bytes(s, text));
        }
        return self.layout(entries.items, try ops.bytes(s, "["), try ops.bytes(s, "]"), recurse + 1, true);
    }
    fn layout(self: *Context, entries: []const c.JSValue, open: c.JSValue, close: c.JSValue, recurse: usize, array: bool) !c.JSValue {
        const s = self.scope;
        if (s.truthy(try self.option("sorted"))) return error.RequiredActualInspectSortedLayout;
        const compact_value = try self.option("compact");
        if (!c.JS_IsNumber(compact_value)) return error.RequiredAdditionalInspectCompactLayout;
        const compact = try ops.float64(s, compact_value);
        if (array and entries.len > 6) return error.RequiredActualInspectGroupedArrayLayout;
        const break_value = try self.option("breakLength");
        if (!c.JS_IsNumber(break_value)) return error.RequiredActualInspectCoercibleLayoutOptions;
        const break_length = try ops.float64(s, break_value);
        const open_units = try utf16.unitsAlloc(s.engine, open); defer s.engine.gpa.free(open_units);
        var total = 2 * entries.len + self.indentation + open_units.len + 10;
        var below = @as(f64, @floatFromInt(total + entries.len)) <= break_length;
        var joined = try ops.bytes(s, ""); var newline = false;
        for (entries, 0..) |entry, i| {
            if (!c.JS_IsString(entry)) return error.RequiredActualInspectNonStringStylizeLayout;
            const units = try utf16.unitsAlloc(s.engine, entry); defer s.engine.gpa.free(units);
            total += units.len; if (@as(f64, @floatFromInt(total)) > break_length) below = false;
            newline = newline or std.mem.indexOfScalar(u16, units, '\n') != null;
            if (i != 0) joined = try h.binary(s, .add, joined, try ops.bytes(s, ", "));
            joined = try h.binary(s, .add, joined, entry);
        }
        if (compact >= 1 and @as(f64, @floatFromInt(self.current_depth - recurse)) < compact and below and !newline) {
            var result = try h.binary(s, .add, open, try ops.bytes(s, " ")); result = try h.binary(s, .add, result, joined);
            return h.binary(s, .add, try h.binary(s, .add, result, try ops.bytes(s, " ")), close);
        }
        var indentation: std.ArrayList(u16) = .empty; defer indentation.deinit(s.engine.gpa);
        try indentation.append(s.engine.gpa, '\n'); try indentation.appendNTimes(s.engine.gpa, ' ', self.indentation);
        const indent = try ops.utf16(s, indentation.items);
        const inner = try h.binary(s, .add, indent, try ops.bytes(s, "  "));
        var result = try h.binary(s, .add, open, inner);
        for (entries, 0..) |entry, i| {
            if (i != 0) result = try h.binary(s, .add, try h.binary(s, .add, result, try ops.bytes(s, ",")), inner);
            result = try h.binary(s, .add, result, entry);
        }
        return h.binary(s, .add, try h.binary(s, .add, result, indent), close);
    }
};
fn noColor(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { try h.pending(engine); return c.JS_DupValue(engine.context, h.arg(args, 0)); }
fn crossStylize(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(crossStylizeValue(&stage.values, args, roots)) catch |err| {
        try ops.discardCaught(engine, err);
        return c.JS_DupValue(engine.context, h.arg(args, 0));
    };
}
fn crossStylizeValue(s: *v.Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const returned = try h.call(s, roots[0], c.pi_js_undefined(), &.{h.arg(args, 0), h.arg(args, 1)});
    return c.JS_DupValue(s.engine.context, try templateText(s, returned));
}
fn inspectCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(inspectCallBody(&stage.values, args, roots));
}
fn inspectCallBody(s: *v.Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const engine = s.engine;
    try h.pending(engine);
    var context = try Context.init(s, roots, args);
    defer context.seen.deinit(engine.gpa);
    return c.JS_DupValue(engine.context, try context.formatValue(h.arg(args, 0), 0));
}
fn formatCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(formatCallBody(&stage.values, args, roots));
}
fn formatCallBody(s: *v.Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const engine = s.engine;
    try h.pending(engine);
    if (args.len == 0) return c.JS_DupValue(engine.context, try ops.bytes(s, ""));
    const first = args[0];
    if (c.JS_IsString(first) and args.len == 1) return c.JS_DupValue(engine.context, first);
    if (args.len == 1) {
        var context = try Context.init(s, roots, &.{first}); defer context.seen.deinit(engine.gpa);
        return c.JS_DupValue(engine.context, try context.formatValue(first, 0));
    }
    // The actual static ERR_INVALID_FD registration has exactly one %s and
    // one argument. Other public format profiles are not claimed by this leaf.
    if (args.len != 2 or !try ops.same(s, first, "\"fd\" must be a positive integer: %s")) return error.RequiredAdditionalInspectFormatProfile;
    const value = args[1]; var body: c.JSValue = undefined;
    const separated = s.truthy(try h.get(s, roots[1], "numericSeparator"));
    if (c.JS_IsNumber(value)) body = try primitive.number(s, value, separated) else if (c.JS_IsBigInt(value)) body = try primitive.bigint(s, value, separated) else if (!c.JS_IsObject(value) or c.JS_IsFunction(engine.context,value) or c.JS_IsNull(value) or !try hasBuiltInToString(s, roots, value)) {
        body = try h.call(s, roots[2], c.pi_js_undefined(), &.{value});
    } else {
        const options = try ops.object(s); try h.put(engine, options, "compact", c.JS_NewInt32(engine.context, 3)); try h.put(engine, options, "colors", c.pi_js_bool(engine.context, 0)); try h.put(engine, options, "depth", c.JS_NewInt32(engine.context, 0));
        var context = try Context.init(s, roots, &.{ value, options }); defer context.seen.deinit(engine.gpa);
        body = try context.formatValue(value, 0);
    }
    return c.JS_DupValue(engine.context, try h.binary(s, .add, try ops.bytes(s, "\"fd\" must be a positive integer: "), body));
}
fn hasBuiltInToString(s: *v.Scope, roots: []const c.JSValue, input: c.JSValue) !bool {
    var value = input;
    while (c.JS_IsProxy(value)) {
        value = ops.proxyTarget(s, value) catch |err| {
            try ops.discardCaught(s.engine, err);
            return true;
        };
    }
    var check_string = true; var check_primitive = true;
    const string_key = try ops.bytes(s, "toString");
    if (!c.JS_IsFunction(s.engine.context, try h.get(s, value, "toString"))) {
        if (!c.JS_IsFunction(s.engine.context, try keyGet(s, value, roots[6]))) return true;
        if (try hasOwn(s, value, roots[6])) return false;
        check_string = false;
    } else if (try hasOwn(s, value, string_key)) return false else if (!c.JS_IsFunction(s.engine.context, try keyGet(s, value, roots[6]))) check_primitive = false else if (try hasOwn(s, value, roots[6])) return false;
    var pointer = value;
    while (true) {
        pointer = try prototype(s, pointer);
        if ((check_string and try hasOwn(s, pointer, string_key)) or (check_primitive and try hasOwn(s, pointer, roots[6]))) break;
    }
    if (try descriptor(s, pointer, try ops.bytes(s, "constructor"))) |item| {
        defer freeDescriptor(s.engine, item); errdefer |err| ops.recordFailure(s.engine, err);
        if (c.JS_IsFunction(s.engine.context, item.value)) {
            const name = try h.get(s, item.value, "name");
            // SafeSet.has uses key identity and never ToPropertyKey. The
            // captured set contains strings only; a getter-produced object or
            // symbol name must not be coerced by this private lookup.
            return c.JS_IsString(name) and try hasOwn(s, roots[10], name);
        }
    }
    return false;
}
