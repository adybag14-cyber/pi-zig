//! Node24.14 loader.js _nodeModulePaths. Source UTF16 operations use captured
//! primordials; no UTF8/CESU8 filesystem round trip or split-path approximation.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const nm = [_]i32{ 115, 101, 108, 117, 100, 111, 109, 95, 101, 100, 111, 110 };
const nm_len: i32 = nm.len;
fn binary(engine: *v.em.Engine, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue { return engine.checked(c.JS_PiBinaryOperator(engine.context, operation, left, right)); }
fn code(s: *Scope, owner: c.JSValue, from: c.JSValue, index: c.JSValue) !c.JSValue { return s.call(try s.get(owner, "charCodeAt"), from, &.{index}); }
fn equalNumber(engine: *v.em.Engine, value: c.JSValue, number: i32) bool { return c.JS_IsStrictEqual(engine.context, value, c.JS_NewInt32(engine.context, number)); }
fn push(s: *Scope, owner: c.JSValue, paths: c.JSValue, value: c.JSValue) !void { _ = try s.call(try s.get(owner, "arrayPush"), paths, &.{value}); }
fn singleton(s: *Scope, value: c.JSValue) !c.JSValue {
    const result = try s.array();
    if (c.JS_DefinePropertyValueUint32(s.engine.context, result, 0, c.JS_DupValue(s.engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
    return c.JS_DupValue(s.engine.context, result);
}
pub fn invoke(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const owner = roots[0];
    const paths_object = try s.get(owner, "paths");
    const from = try s.invoke(paths_object, "resolve", &.{if (args.len > 0) args[0] else c.pi_js_undefined()});
    const windows = s.truthy(try s.get(owner, "windows"));
    if (windows) {
        const first = try s.own(try binary(engine, 1, try s.get(from, "length"), c.JS_NewInt32(engine.context, 1)));
        if (equalNumber(engine, try code(&s, owner, from, first), 92)) {
            const second = try s.own(try binary(engine, 1, try s.get(from, "length"), c.JS_NewInt32(engine.context, 2)));
            if (equalNumber(engine, try code(&s, owner, from, second), 58)) {
                return singleton(&s, try s.own(try binary(engine, 0, from, try s.get(owner, "bareNodeModules"))));
            }
        }
    } else if (s.equal(from, try s.get(owner, "rootSlash"))) {
        return singleton(&s, try s.get(owner, "rootNodeModules"));
    }
    const paths = try s.array();
    var index = try binary(engine, 1, try s.get(from, "length"), c.JS_NewInt32(engine.context, 1));
    defer engine.freeValue(index);
    var last = try v.js.get(engine, from, "length");
    defer engine.freeValue(last);
    var matched: i32 = 0;
    var steps: usize = 0;
    while (true) {
        var frame: Scope = .{ .engine = engine }; defer frame.deinit();
        const condition = try frame.own(try binary(engine, 7, index, c.JS_NewInt32(engine.context, 0)));
        if (!frame.truthy(condition)) break;
        steps +|= 1;
        if (engine.cancelled.load(.acquire) or (steps % 256 == 0 and budget: {
            engine.interrupts +|= 1;
            break :budget engine.interrupts > engine.options.interrupt_budget;
        })) {
            _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
            unreachable;
        }
        const current = try code(&frame, owner, from, index);
        const separator = equalNumber(engine, current, 47) or (windows and (equalNumber(engine, current, 92) or equalNumber(engine, current, 58)));
        if (separator) {
            if (matched != nm_len) {
                const prefix = try frame.call(try frame.get(owner, "stringSlice"), from, &.{ c.JS_NewInt32(engine.context, 0), last });
                const value = try frame.own(try binary(engine, 0, prefix, try frame.get(owner, if (windows) "windowsNodeModules" else "posixNodeModules")));
                try push(&frame, owner, paths, value);
            }
            const retained = c.JS_DupValue(engine.context, index);
            engine.freeValue(last);
            last = retained;
            matched = 0;
        } else if (matched != -1) {
            if (matched >= 0 and matched < nm_len and equalNumber(engine, current, nm[@intCast(matched)])) matched += 1 else matched = -1;
        }
        const next = try engine.checked(c.JS_PiDecrement(engine.context, index));
        engine.freeValue(index);
        index = next;
    }
    if (!windows) try push(&s, owner, paths, try s.get(owner, "rootNodeModules"));
    return c.JS_DupValue(engine.context, paths);
}
