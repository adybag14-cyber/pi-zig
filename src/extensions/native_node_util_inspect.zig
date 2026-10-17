//! Actual consumed Node24 inspect/format paths. No event-inspector alias.
//! Unsupported exotic/layout capabilities stay explicit and unselected.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
const f = @import("native_node_module_callable.zig");
const primitive = @import("native_node_util_inspect_primitive.zig");
const utf16 = @import("native_utf16.zig");
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
    pub fn deinit(self: Inputs, engine: *v.em.Engine) void { inline for (std.meta.fields(Inputs)) |field| engine.freeValue(@field(self, field.name)); }
};
/// Called at genuine bootstrap before guest code, beside color primordial
/// capture. A late module initializer must receive this retained snapshot.
pub fn capturePrimordials(engine: *v.em.Engine) !Inputs {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const global = try s.own(try h.success(engine, try engine.checked(c.JS_GetGlobalObject(engine.context))));
    const object = try h.get(&s, global, "Object"); const object_prototype = try h.get(&s, object, "prototype");
    const string = try h.get(&s, global, "String");
    const function_to_string = try h.get(&s, try s.own(try engine.checked(c.JS_GetFunctionProto(engine.context))), "toString");
    const symbol = try h.get(&s, global, "Symbol");
    const custom = try h.call(&s, try h.get(&s, symbol, "for"), symbol, &.{try s.text("nodejs.util.inspect.custom")});
    const to_primitive = try h.get(&s, symbol, "toPrimitive"); const to_string_tag = try h.get(&s, symbol, "toStringTag");
    const has_instance = try keyGet(&s, try s.own(try engine.checked(c.JS_GetFunctionProto(engine.context))), try h.get(&s, symbol, "hasInstance"));
    const names = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    const keys = try propKeys(&s, global, false, true); defer c.JS_FreePropertyEnum(engine.context, keys.ptr, @intCast(keys.len));
    for (keys) |entry| {
        const key = try s.own(try engine.checked(c.JS_AtomToValue(engine.context, entry.atom)));
        const units = try utf16.unitsAlloc(engine, key); defer engine.gpa.free(units);
        const matches = units.len >= 2 and units[0] >= 'A' and units[0] <= 'Z' and for (units[1..]) |unit| {
            if (!((unit >= 'A' and unit <= 'Z') or (unit >= 'a' and unit <= 'z') or (unit >= '0' and unit <= '9'))) break false;
        } else true;
        if (matches) {
            if (c.JS_DefinePropertyValue(engine.context, names, entry.atom, c.pi_js_bool(engine.context, 1), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
        }
    }
    const known = try s.own(try engine.checked(c.JS_NewArray(engine.context)));
    inline for (.{ "Array", "ArrayBuffer", "Function", "Map", "Set", "Object", "TypedArray", "RegExp", "Date", "DataView", "Error", "AggregateError", "RangeError", "TypeError", "Boolean", "Number", "String", "Promise", "WeakMap", "WeakSet" }, 0..) |name, i| {
        const constructor = if (comptime std.mem.eql(u8, name, "TypedArray")) try prototype(&s, try h.get(&s, global, "Uint8Array")) else try h.get(&s, global, name);
        const entry = try s.object(); try h.put(engine, entry, "prototype", try h.get(&s, constructor, "prototype")); try h.put(engine, entry, "constructor", constructor); try h.put(engine, entry, "name", try s.text(name));
        if (c.JS_DefinePropertyValueUint32(engine.context, known, @intCast(i), c.JS_DupValue(engine.context, entry), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    }
    return .{ .string = c.JS_DupValue(engine.context, string), .object = c.JS_DupValue(engine.context, object), .object_prototype = c.JS_DupValue(engine.context, object_prototype), .function_to_string = c.JS_DupValue(engine.context, function_to_string),
        .custom_symbol = c.JS_DupValue(engine.context, custom), .to_primitive = c.JS_DupValue(engine.context, to_primitive), .to_string_tag = c.JS_DupValue(engine.context, to_string_tag), .has_instance = c.JS_DupValue(engine.context, has_instance),
        .well_known = c.JS_DupValue(engine.context, known), .built_in_names = c.JS_DupValue(engine.context, names) };
}
pub const Exports = struct {
    inspect: c.JSValue, format: c.JSValue,
    pub fn deinit(self: Exports, engine: *v.em.Engine) void { engine.freeValue(self.inspect); engine.freeValue(self.format); }
};
fn keyGet(s: *v.Scope, value: c.JSValue, key: c.JSValue) !c.JSValue { return s.own(try h.success(s.engine, try v.js.getKey(s.engine, value, key))); }
/// Local descriptor cleanup ownership only. An ordinary first event yields to
/// the FIRST actual native cleanup fatal; later ordinary/fatal events cannot
/// replace a selected fatal. History flags are never current-event authority.
const DescriptorEvent = struct {
    engine: *v.em.Engine,
    selected: ?c.JSValue,
    fatal: bool,
    history: ?c.JSValue,
    fn currentFatal(engine: *v.em.Engine, reason: c.JSValue, generation: u64) bool {
        if (c.JS_IsUncatchableError(reason)) return true;
        const tagged = c.pi_js_native_allocation_error_generation(reason);
        const distance = tagged -% generation;
        if (tagged == 0 or distance == 0 or distance > engine.native_allocation_generation -% generation) return false;
        c.JS_SetUncatchableError(engine.context, reason); return true;
    }
    fn init(engine: *v.em.Engine, reason: c.JSValue, generation: u64) DescriptorEvent {
        const history = engine.captured_exception; engine.captured_exception = null;
        return .{ .engine = engine, .selected = reason, .fatal = currentFatal(engine, reason, generation), .history = history };
    }
    fn select(self: *DescriptorEvent, reason: c.JSValue, generation: u64) c.JSValue {
        const fatal = currentFatal(self.engine, reason, generation);
        if (fatal and !self.fatal) {
            const previous = self.selected.?;
            // Publish the winning fatal outside BOTH exception slots before
            // releasing the displaced reason, whose finalizer can throw too.
            self.selected = reason; self.fatal = true; return previous;
        }
        return reason;
    }
    fn drain(self: *DescriptorEvent, generation: u64) void {
        // Take both out of mutable slots BEFORE releasing/classifying either
        // one. Root's cleanup policy ranks the actual current VM event before
        // a newly captured slot when both were produced by one release.
        const captured = self.engine.captured_exception; self.engine.captured_exception = null;
        const pending: ?c.JSValue = if (c.JS_HasException(self.engine.context)) c.JS_GetException(self.engine.context) else null;
        // Rank both already-existing events before freeing either discarded
        // value. A finalizer raised by that free is chronologically later.
        var retired: [2]?c.JSValue = .{ null, null };
        if (pending) |reason| retired[0] = self.select(reason, generation);
        if (captured) |reason| retired[1] = self.select(reason, generation);
        for (retired) |value| if (value) |reason| self.release(reason);
    }
    fn release(self: *DescriptorEvent, value: c.JSValue) void {
        const generation = self.engine.native_allocation_generation;
        self.engine.freeValue(value);
        self.drain(generation);
    }
    fn releaseHistory(self: *DescriptorEvent) void {
        if (self.history) |history| { self.history = null; self.release(history); }
    }
    fn finish(self: *DescriptorEvent) !void {
        self.releaseHistory();
        const reason = self.selected.?; self.selected = null;
        _ = try self.engine.checked(c.JS_Throw(self.engine.context, reason)); unreachable;
    }
};
fn descriptor(s: *v.Scope, value: c.JSValue, key: c.JSValue) !?c.JSPropertyDescriptor {
    const atom = try v.js.atom(s.engine, key); defer c.JS_FreeAtom(s.engine.context, atom);
    var result: c.JSPropertyDescriptor = undefined;
    const generation = s.engine.native_allocation_generation;
    const present = c.JS_GetOwnProperty(s.engine.context, &result, value, atom);
    if (present < 0) return v.js.capture(s.engine);
    if (present == 0) { try h.pending(s.engine); return null; }
    // Normalize before Scope may allocate. Descriptor fields are three owned
    // results even for an accessor; transfer/free each exactly once.
    if (c.JS_HasException(s.engine.context)) {
        const reason = c.JS_GetException(s.engine.context);
        var event = DescriptorEvent.init(s.engine, reason, generation);
        event.releaseHistory();
        event.release(result.value); event.release(result.getter); event.release(result.setter);
        try event.finish(); unreachable;
    }
    return result;
}
fn freeDescriptor(engine: *v.em.Engine, item: c.JSPropertyDescriptor) void { engine.freeValue(item.value); engine.freeValue(item.getter); engine.freeValue(item.setter); }
fn hasOwn(s: *v.Scope, value: c.JSValue, key: c.JSValue) !bool {
    const item = try descriptor(s, value, key) orelse return false; defer freeDescriptor(s.engine, item); return true;
}
fn propKeys(s: *v.Scope, value: c.JSValue, symbols: bool, hidden: bool) ![]c.JSPropertyEnum {
    var table: [*c]c.JSPropertyEnum = null; var len: u32 = 0;
    const flags: c_int = c.JS_GPN_STRING_MASK | (if (symbols) @as(c_int, c.JS_GPN_SYMBOL_MASK) else 0) | (if (hidden) @as(c_int, 0) else c.JS_GPN_ENUM_ONLY);
    if (c.JS_GetOwnPropertyNames(s.engine.context, &table, &len, value, flags) < 0) return v.js.capture(s.engine);
    if (c.JS_HasException(s.engine.context)) {
        const reason = c.JS_GetException(s.engine.context);
        c.JS_FreePropertyEnum(s.engine.context, table, len);
        _ = try s.engine.checked(c.JS_Throw(s.engine.context, reason)); unreachable;
    }
    return table[0..len];
}
fn discardOrdinary(engine: *v.em.Engine, reason: c.JSValue, generation: u64) !void {
    defer engine.freeValue(reason);
    if (c.JS_IsUncatchableError(reason)) return h.throwValue(engine, reason);
    try @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation);
}
fn instance(s: *v.Scope, value: c.JSValue, constructor: c.JSValue) !bool {
    try h.pending(s.engine); const generation = s.engine.native_allocation_generation;
    const answer = c.JS_IsInstanceOf(s.engine.context, value, constructor);
    if (answer < 0) { try discardOrdinary(s.engine, c.JS_GetException(s.engine.context), generation); return false; }
    try h.pending(s.engine); return answer != 0;
}
fn prototype(s: *v.Scope, value: c.JSValue) !c.JSValue { return s.own(try h.success(s.engine, try s.engine.checked(c.JS_GetPrototype(s.engine.context, value)))); }
fn templateText(s: *v.Scope, value: c.JSValue) !c.JSValue { return s.own(try h.success(s.engine, try s.engine.checked(c.JS_ToString(s.engine.context, value)))); }
fn defaultOptions(s: *v.Scope) !c.JSValue {
    const object = try s.object();
    const values = [_]c.JSValue{ c.pi_js_bool(s.engine.context, 0), c.JS_NewInt32(s.engine.context, 2), c.pi_js_bool(s.engine.context, 0), c.pi_js_bool(s.engine.context, 1), c.pi_js_bool(s.engine.context, 0), c.JS_NewInt32(s.engine.context, 100), c.JS_NewInt32(s.engine.context, 10000), c.JS_NewInt32(s.engine.context, 80), c.JS_NewInt32(s.engine.context, 3), c.pi_js_bool(s.engine.context, 0), c.pi_js_bool(s.engine.context, 0), c.pi_js_bool(s.engine.context, 0) };
    inline for (option_names, values) |name, value| {
        if (c.JS_DefinePropertyValueStr(s.engine.context, object, name, c.JS_DupValue(s.engine.context, value), c.JS_PROP_WRITABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
    }
    if (c.JS_PreventExtensions(s.engine.context, object) < 0) return v.js.capture(s.engine);
    return object;
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Exports {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    if (!c.JS_IsFunction(engine.context, inputs.string) or !c.JS_IsFunction(engine.context, inputs.object) or !c.JS_IsFunction(engine.context, inputs.function_to_string) or !c.JS_IsFunction(engine.context, inputs.has_instance) or !c.JS_IsSymbol(inputs.custom_symbol) or !c.JS_IsSymbol(inputs.to_primitive) or !c.JS_IsSymbol(inputs.to_string_tag) or !c.JS_IsArray(inputs.well_known) or !c.JS_IsObject(inputs.built_in_names)) return error.RequiredActualInspectPrimordials;
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const lexical = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    const defaults = try defaultOptions(&s);
    const no_color = try s.own(try f.create(engine, "stylizeNoColor", 1, true, noColor, &.{}));
    const roots = [_]c.JSValue{ lexical, defaults, inputs.string, inputs.object, inputs.object_prototype, inputs.custom_symbol, inputs.to_primitive, inputs.to_string_tag, inputs.has_instance, inputs.well_known, inputs.built_in_names, inputs.function_to_string, no_color };
    const inspect = try s.own(try f.create(engine, "inspect", 2, true, inspectCall, &roots));
    const format = try s.own(try f.create(engine, "format", 0, true, formatCall, &roots));
    try h.put(engine, lexical, "inspect", inspect);
    try h.put(engine, inspect, "custom", inputs.custom_symbol);
    const atom = c.JS_NewAtom(engine.context, "defaultOptions"); if (atom == c.JS_ATOM_NULL) return v.js.capture(engine); defer c.JS_FreeAtom(engine.context, atom);
    const get = try s.own(try f.create(engine, "get defaultOptions", 0, false, defaultsGet, &.{defaults}));
    const set = try s.own(try f.create(engine, "set defaultOptions", 1, false, defaultsSet, &.{defaults}));
    if (c.JS_DefinePropertyGetSet(engine.context, inspect, atom, c.JS_DupValue(engine.context, get), c.JS_DupValue(engine.context, set), c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    return .{ .inspect = c.JS_DupValue(engine.context, inspect), .format = c.JS_DupValue(engine.context, format) };
}
fn defaultsGet(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { try h.pending(engine); return c.JS_DupValue(engine.context, roots[0]); }
fn defaultsSet(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const source = h.arg(args, 0); if (!c.JS_IsObject(source) or c.JS_IsFunction(engine.context, source) or c.JS_IsArray(source) or c.JS_IsProxy(source)) return error.RequiredActualInspectOptionsValidation;
    // ObjectAssign performs each descriptor/enumerability check immediately
    // before that key's Get/Set. ENUM_ONLY enumeration would prefilter every
    // descriptor before any value getter could mutate the following property.
    const keys = try propKeys(&s, source, true, true); defer c.JS_FreePropertyEnum(engine.context, keys.ptr, @intCast(keys.len));
    for (keys) |entry| {
        const key = try s.own(try engine.checked(c.JS_AtomToValue(engine.context, entry.atom)));
        const item = try descriptor(&s, source, key) orelse continue;
        defer freeDescriptor(engine, item);
        if (item.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        try v.js.setKey(engine, roots[0], key, try keyGet(&s, source, key)); try h.pending(engine);
    }
    return c.JS_DupValue(engine.context, roots[0]);
}
const Context = struct {
    scope: *v.Scope, roots: []const c.JSValue, options: c.JSValue,
    user_options: c.JSValue = c.pi_js_undefined(),
    indentation: usize = 0,
    current_depth: usize = 0,
    seen: std.ArrayList(c.JSValue) = .empty,
    fn init(s: *v.Scope, roots: []const c.JSValue, args: []const c.JSValue) !Context {
        const options = try s.object();
        try h.put(s.engine, options, "stylize", roots[12]);
        inline for (option_names) |name| try h.put(s.engine, options, name, try h.get(s, roots[1], name));
        var self: Context = .{ .scope = s, .roots = roots, .options = options };
        if (args.len > 2 and !c.JS_IsUndefined(args[2])) try h.put(s.engine, options, "depth", args[2]);
        if (args.len > 3 and !c.JS_IsUndefined(args[3])) try h.put(s.engine, options, "colors", args[3]);
        if (args.len > 1) {
            const opts = args[1];
            if (c.JS_IsBool(opts)) try h.put(s.engine, options, "showHidden", opts) else if (s.truthy(opts)) {
                const keys = try propKeys(s, opts, false, false); defer c.JS_FreePropertyEnum(s.engine.context, keys.ptr, @intCast(keys.len));
                for (keys) |entry| {
                    const key = try s.own(try s.engine.checked(c.JS_AtomToValue(s.engine.context, entry.atom)));
                    var recognized = try h.same(s, key, "stylize");
                    inline for (option_names) |name| { if (try h.same(s, key, name)) recognized = true; }
                    if (recognized) {
                        const selected = try keyGet(s, opts, key); try v.js.setKey(s.engine, options, key, selected); try h.pending(s.engine);
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
    fn stylize(self: *Context, value: c.JSValue, kind: []const u8) !c.JSValue { return h.call(self.scope, try self.option("stylize"), c.pi_js_undefined(), &.{ value, try self.scope.text(kind) }); }
    fn userOptions(self: *Context, cross_context: bool) !c.JSValue {
        const s = self.scope;
        const result = try v.spread(s, self.options);
        if (!c.JS_IsUndefined(self.user_options)) { try v.js.spreadInto(s.engine, result, self.user_options); try h.pending(s.engine); }
        if (!cross_context) return result;
        if (c.JS_SetPrototype(s.engine.context, result, c.pi_js_null()) < 0) return v.js.capture(s.engine);
        const keys = try propKeys(s, result, false, false); defer c.JS_FreePropertyEnum(s.engine.context, keys.ptr, @intCast(keys.len));
        for (keys) |entry| {
            const key = try s.own(try s.engine.checked(c.JS_AtomToValue(s.engine.context, entry.atom)));
            const value = try keyGet(s, result, key);
            if (c.JS_IsObject(value)) { if (c.JS_DeleteProperty(s.engine.context, result, entry.atom, c.JS_PROP_THROW) < 0) return v.js.capture(s.engine); }
        }
        const wrapper = try s.own(try f.create(s.engine, "", 2, false, crossStylize, &.{try self.option("stylize")}));
        if (c.JS_SetPrototype(s.engine.context, wrapper, c.pi_js_null()) < 0) return v.js.capture(s.engine);
        try h.put(s.engine, result, "stylize", wrapper); return result;
    }
    fn primitiveValue(self: *Context, value: c.JSValue) !c.JSValue {
        const s = self.scope;
        const separated = s.truthy(try self.option("numericSeparator"));
        if (c.JS_IsNumber(value)) return self.stylize(try primitive.number(s, value, separated), "number");
        if (c.JS_IsBigInt(value)) return self.stylize(try primitive.bigint(s, value, separated), "bigint");
        if (c.JS_IsString(value)) {
            const max = try self.option("maxStringLength"); var maximum: ?usize = null;
            if (!c.JS_IsNull(max)) { var number: f64 = 0; if (c.JS_ToFloat64(s.engine.context, &number, max) < 0) return v.js.capture(s.engine); try h.pending(s.engine); if (number != std.math.inf(f64)) { if (!std.math.isFinite(number) or number < 0 or @trunc(number) != number or number >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) return error.RequiredAdditionalInspectStringLimit; maximum = @intFromFloat(number); } }
            var line: f64 = 0; if (c.JS_ToFloat64(s.engine.context, &line, try self.option("breakLength")) < 0) return v.js.capture(s.engine); try h.pending(s.engine);
            return primitive.string(s, value, .{ .max_string_length = maximum, .break_length = line, .indentation = self.indentation, .compact_true = s.equal(try self.option("compact"), c.pi_js_bool(s.engine.context, 1)) }, try self.option("stylize"));
        }
        if (c.JS_IsNull(value)) return self.stylize(try s.text("null"), "null");
        if (c.JS_IsBool(value)) return self.stylize(try s.text(if (s.truthy(value)) "true" else "false"), "boolean");
        if (c.JS_IsUndefined(value)) return self.stylize(try s.text("undefined"), "undefined");
        if (c.JS_IsSymbol(value)) return self.stylize(try h.call(s, self.roots[2], c.pi_js_undefined(), &.{value}), "symbol");
        unreachable;
    }
    fn formatValue(self: *Context, input: c.JSValue, recurse: usize) anyerror!c.JSValue {
        const s = self.scope;
        if (!c.JS_IsObject(input) or c.JS_IsNull(input)) return self.primitiveValue(input);
        var value = input; var proxied = false;
        while (c.JS_IsProxy(value)) {
            proxied = true;
            const generation = s.engine.native_allocation_generation;
            const target = c.JS_GetProxyTarget(s.engine.context, value);
            if (c.JS_IsException(target)) {
                // QuickJS exposes revoked-proxy status without invoking traps.
                const reason = c.JS_GetException(s.engine.context); try discardOrdinary(s.engine, reason, generation);
                return self.stylize(try s.text("<Revoked Proxy>"), "special");
            }
            value = try s.own(try h.success(s.engine, target));
        }
        if (proxied and s.truthy(try self.option("showProxy"))) return error.RequiredActualInspectProxyLayout;
        if (s.truthy(try self.option("customInspect"))) {
            const method = try keyGet(s, value, self.roots[5]);
            const inspect = try h.get(s, self.roots[0], "inspect");
            if (c.JS_IsFunction(s.engine.context, method) and !s.equal(method, inspect)) {
                var is_prototype = false;
                if (try descriptor(s, value, try s.text("constructor"))) |item| {
                    defer freeDescriptor(s.engine, item);
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
                            return s.own(try h.success(s.engine, try utf16.string(s.engine, output.items)));
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
        var count: u32 = 0; if (c.JS_ToUint32(s.engine.context, &count, try h.get(s, self.roots[9], "length")) < 0) return v.js.capture(s.engine);
        while (!c.JS_IsNull(current)) {
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const entry = try s.own(try h.success(s.engine, try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, self.roots[9], index))));
                if (s.equal(current, try h.get(s, entry, "prototype")) and s.truthy(try h.call(s, self.roots[8], try h.get(s, entry, "constructor"), &.{value}))) return h.get(s, entry, "name");
            }
            if (try descriptor(s, current, try s.text("constructor"))) |item| {
                defer freeDescriptor(s.engine, item);
                if (c.JS_IsFunction(s.engine.context, item.value) and !try h.same(s, try h.get(s, item.value, "name"), "") and try instance(s, value, item.value)) return h.call(s, self.roots[2], c.pi_js_undefined(), &.{try h.get(s, item.value, "name")});
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
            body = try self.stylize(try s.text(if (!c.JS_IsUndefined(item.setter)) "[Getter/Setter]" else "[Getter]"), "special");
        } else if (!c.JS_IsUndefined(item.setter)) body = try self.stylize(try s.text("[Setter]"), "special") else body = try self.stylize(try s.text("undefined"), "undefined");
        return body;
    }
    fn formatProperty(self: *Context, value: c.JSValue, key: c.JSValue, recurse: usize) !c.JSValue {
        const s = self.scope;
        const item = try descriptor(s, value, key) orelse {
            _ = try h.get(s, c.pi_js_undefined(), "value"); unreachable;
        };
        defer freeDescriptor(s.engine, item);
        const body = try self.propertyBody(item, recurse);
        var name: c.JSValue = undefined;
        if (c.JS_IsSymbol(key)) return error.RequiredActualInspectSymbolPropertyEscape;
        const units = try utf16.unitsAlloc(s.engine, key); defer s.engine.gpa.free(units);
        const simple = units.len != 0 and for (units, 0..) |unit, i| {
            if (!((unit >= 'A' and unit <= 'Z') or (unit >= 'a' and unit <= 'z') or unit == '_' or (i != 0 and unit >= '0' and unit <= '9'))) break false;
        } else true;
        if (simple) name = if (try h.same(s, key, "__proto__")) try s.text("['__proto__']") else try self.stylize(key, "name") else name = try self.stylize(try primitive.quote(s, key), "string");
        if (item.flags & c.JS_PROP_ENUMERABLE == 0) name = try h.binary(s, .add, try h.binary(s, .add, try s.text("["), try templateText(s, name)), try s.text("]"));
        const prefix = try h.binary(s, .add, try templateText(s, name), try s.text(": "));
        return h.binary(s, .add, prefix, try templateText(s, body));
    }
    fn formatRaw(self: *Context, value: c.JSValue, recurse: usize) anyerror!c.JSValue {
        const s = self.scope;
        if (s.truthy(try self.option("showHidden"))) return error.RequiredActualInspectPrototypeProperties;
        const constructor = try self.constructorName(value);
        var tag: c.JSValue = undefined;
        const generation = s.engine.native_allocation_generation;
        tag = keyGet(s, value, self.roots[7]) catch |err| caught: {
            if (err != error.JavaScriptException) return err;
            const reason = s.engine.captured_exception orelse return err;
            if (c.JS_IsUncatchableError(reason)) return err;
            try @import("native_async_body.zig").rethrowRecognizedAllocation(s.engine, reason, generation);
            s.engine.captured_exception = null; s.engine.freeValue(reason); break :caught try s.text("");
        };
        if (!c.JS_IsString(tag)) tag = try s.text("") else if (!try h.same(s, tag, "")) {
            if (try descriptor(s, value, self.roots[7])) |item| { defer freeDescriptor(s.engine, item); if (item.flags & c.JS_PROP_ENUMERABLE != 0) tag = try s.text(""); }
        }
        // Run the actual Source iterator-presence check before selecting an
        // ordinary object layout. Prototype proxy has-traps remain observable.
        const iterator = try s.own(try s.engine.checked(c.JS_GetIteratorSymbol(s.engine.context)));
        const iterable = try v.js.hasKey(s.engine, value, iterator); try h.pending(s.engine);
        if (c.JS_IsArray(value)) {
            if (!iterable or !try h.same(s, constructor, "Array") or !try h.same(s, tag, "")) return error.RequiredActualInspectArrayPrefix;
            return self.formatArray(value, recurse);
        }
        if (c.JS_IsFunction(s.engine.context, value)) return self.formatFunction(value, constructor, tag);
        if (c.JS_GetClassID(value) != c.JS_GetClassID(self.roots[4])) return error.RequiredActualInspectExoticLayout;
        if (iterable) return error.RequiredActualInspectIterableTypeDiscrimination;
        const keys = try propKeys(s, value, true, false); defer c.JS_FreePropertyEnum(s.engine.context, keys.ptr, @intCast(keys.len));
        var prefix = if (c.JS_IsNull(constructor)) try s.text("[Object: null prototype] ") else if (try h.same(s, constructor, "Object")) try s.text("") else try h.binary(s, .add, constructor, try s.text(" "));
        if (!try h.same(s, tag, "")) return error.RequiredActualInspectTaggedPrefix;
        if (keys.len == 0) return h.binary(s, .add, prefix, try s.text("{}"));
        const depth = try self.option("depth");
        if (!c.JS_IsNull(depth) and s.truthy(try h.binary(s, .greater, c.JS_NewFloat64(s.engine.context, @floatFromInt(recurse)), depth))) {
            if (c.JS_IsNull(constructor)) return self.stylize(try s.text("[Object: null prototype]"), "special");
            return self.stylize(try h.binary(s, .add, try h.binary(s, .add, try s.text("["), constructor), try s.text("]")), "special");
        }
        try self.seen.append(s.engine.gpa, value); defer _ = self.seen.pop();
        self.current_depth = recurse + 1;
        var entries: std.ArrayList(c.JSValue) = .empty; defer entries.deinit(s.engine.gpa);
        for (keys) |entry| {
            const key = try s.own(try s.engine.checked(c.JS_AtomToValue(s.engine.context, entry.atom)));
            try entries.append(s.engine.gpa, try self.formatProperty(value, key, recurse + 1));
        }
        prefix = try h.binary(s, .add, prefix, try s.text("{"));
        return self.layout(entries.items, prefix, try s.text("}"), recurse + 1, false);
    }
    fn formatFunction(self: *Context, value: c.JSValue, constructor: c.JSValue, tag: c.JSValue) !c.JSValue {
        const s = self.scope;
        const keys = try propKeys(s, value, true, false); defer c.JS_FreePropertyEnum(s.engine.context, keys.ptr, @intCast(keys.len));
        const source = try h.call(s, self.roots[11], value, &.{});
        const units = try utf16.unitsAlloc(s.engine, source); defer s.engine.gpa.free(units);
        const class_prefix = [_]u16{ 'c', 'l', 'a', 's', 's' };
        if (std.mem.startsWith(u16, units, &class_prefix) and units.len > 5 and units[units.len - 1] == '}') return error.RequiredActualInspectClassLayout;
        const class_atom = c.JS_GetClassName(s.engine.runtime, c.JS_GetClassID(value)); defer c.JS_FreeAtom(s.engine.context, class_atom);
        const native_name = try s.own(try s.engine.checked(c.JS_AtomToValue(s.engine.context, class_atom)));
        const kind = if (try h.same(s, native_name, "AsyncGeneratorFunction")) "AsyncGeneratorFunction" else if (try h.same(s, native_name, "GeneratorFunction")) "GeneratorFunction" else if (c.JS_IsAsyncFunction(value)) "AsyncFunction" else "Function";
        var base = try h.binary(s, .add, try s.text("["), try s.text(kind));
        if (c.JS_IsNull(constructor)) base = try h.binary(s, .add, base, try s.text(" (null prototype)"));
        if (try h.same(s, try h.get(s, value, "name"), "")) base = try h.binary(s, .add, base, try s.text(" (anonymous)")) else {
            const name_is_string = c.JS_IsString(try h.get(s, value, "name"));
            const name = try h.get(s, value, "name");
            if (!name_is_string and c.JS_IsObject(name)) return error.RequiredActualInspectFunctionNameImplicitDepth;
            const formatted = if (name_is_string) name else try self.formatValue(name, 0);
            base = try h.binary(s, .add, try h.binary(s, .add, base, try s.text(": ")), try templateText(s, formatted));
        }
        base = try h.binary(s, .add, base, try s.text("]"));
        if (!c.JS_IsNull(constructor) and !try h.same(s, constructor, kind)) base = try h.binary(s, .add, try h.binary(s, .add, base, try s.text(" ")), constructor);
        if (!try h.same(s, tag, "") and !s.equal(constructor, tag)) base = try h.binary(s, .add, try h.binary(s, .add, try h.binary(s, .add, base, try s.text(" [")), tag), try s.text("]"));
        if (keys.len != 0) return error.RequiredActualInspectFunctionProperties;
        return self.stylize(base, "special");
    }
    fn formatArray(self: *Context, value: c.JSValue, recurse: usize) !c.JSValue {
        const s = self.scope;
        const keys = try propKeys(s, value, true, false); defer c.JS_FreePropertyEnum(s.engine.context, keys.ptr, @intCast(keys.len));
        var length: u32 = 0; if (c.JS_ToUint32(s.engine.context, &length, try h.get(s, value, "length")) < 0) return v.js.capture(s.engine);
        for (keys) |entry| {
            const key = try s.own(try s.engine.checked(c.JS_AtomToValue(s.engine.context, entry.atom)));
            if (!c.JS_IsString(key)) return error.RequiredActualInspectArrayExtraProperties;
            const units = try utf16.unitsAlloc(s.engine, key); defer s.engine.gpa.free(units);
            if (units.len == 0 or (units.len > 1 and units[0] == '0')) return error.RequiredActualInspectArrayExtraProperties;
            var index: u64 = 0;
            for (units) |unit| { if (unit < '0' or unit > '9' or index > std.math.maxInt(u32)) return error.RequiredActualInspectArrayExtraProperties; index = index * 10 + unit - '0'; }
            if (index >= std.math.maxInt(u32)) return error.RequiredActualInspectArrayExtraProperties;
        }
        if (length == 0) return s.text("[]");
        const depth = try self.option("depth");
        if (!c.JS_IsNull(depth) and s.truthy(try h.binary(s, .greater, c.JS_NewFloat64(s.engine.context, @floatFromInt(recurse)), depth))) return self.stylize(try s.text("[Array]"), "special");
        var maximum: f64 = 0; const max_value = try self.option("maxArrayLength");
        if (!c.JS_IsNumber(max_value)) return error.RequiredActualInspectCoercibleArrayLength;
        if (c.JS_ToFloat64(s.engine.context, &maximum, max_value) < 0) return v.js.capture(s.engine);
        if (std.math.isNan(maximum) or @trunc(maximum) != maximum) return error.RequiredAdditionalInspectArrayLength;
        const take: u32 = if (maximum <= 0) 0 else if (maximum >= length) length else @intFromFloat(maximum);
        try self.seen.append(s.engine.gpa, value); defer _ = self.seen.pop(); self.current_depth = recurse + 1;
        var entries: std.ArrayList(c.JSValue) = .empty; defer entries.deinit(s.engine.gpa);
        var index: u32 = 0;
        while (index < take) : (index += 1) {
            const key = try s.own(try s.engine.checked(c.JS_ToString(s.engine.context, c.JS_NewUint32(s.engine.context, index))));
            const item = try descriptor(s, value, key) orelse return error.RequiredActualInspectSparseArray;
            defer freeDescriptor(s.engine, item);
            try entries.append(s.engine.gpa, try self.propertyBody(item, recurse + 1));
        }
        if (take < length) {
            const text = try std.fmt.allocPrint(s.engine.gpa, "... {d} more item{s}", .{ length - take, if (length - take > 1) "s" else "" }); defer s.engine.gpa.free(text);
            try entries.append(s.engine.gpa, try s.text(text));
        }
        return self.layout(entries.items, try s.text("["), try s.text("]"), recurse + 1, true);
    }
    fn layout(self: *Context, entries: []const c.JSValue, open: c.JSValue, close: c.JSValue, recurse: usize, array: bool) !c.JSValue {
        const s = self.scope;
        if (s.truthy(try self.option("sorted"))) return error.RequiredActualInspectSortedLayout;
        const compact_value = try self.option("compact");
        if (!c.JS_IsNumber(compact_value)) return error.RequiredAdditionalInspectCompactLayout;
        var compact: f64 = 0; if (c.JS_ToFloat64(s.engine.context, &compact, compact_value) < 0) return v.js.capture(s.engine);
        if (array and entries.len > 6) return error.RequiredActualInspectGroupedArrayLayout;
        var break_length: f64 = 0; const break_value = try self.option("breakLength");
        if (!c.JS_IsNumber(break_value)) return error.RequiredActualInspectCoercibleLayoutOptions;
        if (c.JS_ToFloat64(s.engine.context, &break_length, break_value) < 0) return v.js.capture(s.engine);
        const open_units = try utf16.unitsAlloc(s.engine, open); defer s.engine.gpa.free(open_units);
        var total = 2 * entries.len + self.indentation + open_units.len + 10;
        var below = @as(f64, @floatFromInt(total + entries.len)) <= break_length;
        var joined = try s.text(""); var newline = false;
        for (entries, 0..) |entry, i| {
            if (!c.JS_IsString(entry)) return error.RequiredActualInspectNonStringStylizeLayout;
            const units = try utf16.unitsAlloc(s.engine, entry); defer s.engine.gpa.free(units);
            total += units.len; if (@as(f64, @floatFromInt(total)) > break_length) below = false;
            newline = newline or std.mem.indexOfScalar(u16, units, '\n') != null;
            if (i != 0) joined = try h.binary(s, .add, joined, try s.text(", "));
            joined = try h.binary(s, .add, joined, entry);
        }
        if (compact >= 1 and @as(f64, @floatFromInt(self.current_depth - recurse)) < compact and below and !newline) {
            var result = try h.binary(s, .add, open, try s.text(" ")); result = try h.binary(s, .add, result, joined);
            return h.binary(s, .add, try h.binary(s, .add, result, try s.text(" ")), close);
        }
        var indentation: std.ArrayList(u16) = .empty; defer indentation.deinit(s.engine.gpa);
        try indentation.append(s.engine.gpa, '\n'); try indentation.appendNTimes(s.engine.gpa, ' ', self.indentation);
        const indent = try s.own(try utf16.string(s.engine, indentation.items));
        const inner = try h.binary(s, .add, indent, try s.text("  "));
        var result = try h.binary(s, .add, open, inner);
        for (entries, 0..) |entry, i| {
            if (i != 0) result = try h.binary(s, .add, try h.binary(s, .add, result, try s.text(",")), inner);
            result = try h.binary(s, .add, result, entry);
        }
        return h.binary(s, .add, try h.binary(s, .add, result, indent), close);
    }
};
fn noColor(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { try h.pending(engine); return c.JS_DupValue(engine.context, h.arg(args, 0)); }
fn crossStylize(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const generation = engine.native_allocation_generation;
    const returned = crossStylizeValue(&s, args, roots) catch |err| {
        if (err != error.JavaScriptException) return err;
        const reason = engine.captured_exception orelse return err;
        if (c.JS_IsUncatchableError(reason)) return err;
        try @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation);
        engine.captured_exception = null; engine.freeValue(reason);
        return c.JS_DupValue(engine.context, h.arg(args, 0));
    };
    return c.JS_DupValue(engine.context, returned);
}
fn crossStylizeValue(s: *v.Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const returned = try h.call(s, roots[0], c.pi_js_undefined(), &.{ h.arg(args, 0), h.arg(args, 1) });
    // Template ToString remains inside Source's ordinary catch boundary.
    return s.own(try h.success(s.engine, try s.engine.checked(c.JS_ToString(s.engine.context, returned))));
}
fn inspectCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    var context = try Context.init(&s, roots, args);
    defer context.seen.deinit(engine.gpa);
    return c.JS_DupValue(engine.context, try context.formatValue(h.arg(args, 0), 0));
}
fn formatCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    if (args.len == 0) return c.JS_DupValue(engine.context, try s.text(""));
    const first = args[0];
    if (c.JS_IsString(first) and args.len == 1) return c.JS_DupValue(engine.context, first);
    if (args.len == 1) {
        var context = try Context.init(&s, roots, &.{first}); defer context.seen.deinit(engine.gpa);
        return c.JS_DupValue(engine.context, try context.formatValue(first, 0));
    }
    // The actual static ERR_INVALID_FD registration has exactly one %s and
    // one argument. Other public format profiles are not claimed by this leaf.
    if (args.len != 2 or !try h.same(&s, first, "\"fd\" must be a positive integer: %s")) return error.RequiredAdditionalInspectFormatProfile;
    const value = args[1]; var body: c.JSValue = undefined;
    const separated = s.truthy(try h.get(&s, roots[1], "numericSeparator"));
    if (c.JS_IsNumber(value)) body = try primitive.number(&s, value, separated) else if (c.JS_IsBigInt(value)) body = try primitive.bigint(&s, value, separated) else if (!c.JS_IsObject(value) or c.JS_IsNull(value) or !try hasBuiltInToString(&s, roots, value)) {
        body = try h.call(&s, roots[2], c.pi_js_undefined(), &.{value});
    } else {
        const options = try s.object(); try h.put(engine, options, "compact", c.JS_NewInt32(engine.context, 3)); try h.put(engine, options, "colors", c.pi_js_bool(engine.context, 0)); try h.put(engine, options, "depth", c.JS_NewInt32(engine.context, 0));
        var context = try Context.init(&s, roots, &.{ value, options }); defer context.seen.deinit(engine.gpa);
        body = try context.formatValue(value, 0);
    }
    return c.JS_DupValue(engine.context, try h.binary(&s, .add, try s.text("\"fd\" must be a positive integer: "), body));
}
fn hasBuiltInToString(s: *v.Scope, roots: []const c.JSValue, input: c.JSValue) !bool {
    var value = input;
    while (c.JS_IsProxy(value)) {
        const generation = s.engine.native_allocation_generation;
        const target = c.JS_GetProxyTarget(s.engine.context, value);
        if (c.JS_IsException(target)) { try discardOrdinary(s.engine, c.JS_GetException(s.engine.context), generation); return true; }
        value = try s.own(try h.success(s.engine, target));
    }
    var check_string = true; var check_primitive = true;
    const string_key = try s.text("toString");
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
    if (try descriptor(s, pointer, try s.text("constructor"))) |item| {
        defer freeDescriptor(s.engine, item);
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
