//! Real per-Engine internal/modules/helpers execution-state controls.
//! They do not claim a completed canonical loader or execute a fake prototype.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const execution = @import("extensions/native_node_module_execution_state.zig");
const js = @import("extensions/native_js_values.zig");
const key = "pi-native:private/module-execution-state";

fn expose(engine: *em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(engine.context, global, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
}
fn check(engine: *em.Engine, source: []const u8) !void {
    const result = try engine.eval(source, "module-execution-state-controls.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, c.JS_NewBool(engine.context, true)));
}
fn method(engine: *em.Engine, namespace: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, namespace, name));
}
fn call(engine: *em.Engine, function: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null));
}

test "native module execution state original methods preserve metadata and independent monotone facts" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const namespace = try execution.acquire(engine); defer engine.freeValue(namespace);
    try expose(engine, "executionState", namespace);
    try check(engine,
        \\(()=>{const names=["hasStartedUserCJSExecution","setHasStartedUserCJSExecution","hasStartedUserESMExecution","setHasStartedUserESMExecution"];
        \\if(JSON.stringify(Object.keys(executionState))!==JSON.stringify(names))throw Error("names");
        \\for(const name of names){const f=executionState[name];if(f.name!==name||f.length!==0||Object.hasOwn(f,"prototype"))throw Error("method metadata")}
        \\if(executionState.hasStartedUserCJSExecution()!==false||executionState.hasStartedUserESMExecution()!==false)throw Error("initial facts");
        \\if(executionState.setHasStartedUserCJSExecution()!==undefined||executionState.hasStartedUserCJSExecution()!==true||executionState.hasStartedUserESMExecution()!==false)throw Error("CJS fact");
        \\if(executionState.setHasStartedUserCJSExecution()!==undefined||executionState.setHasStartedUserESMExecution()!==undefined)throw Error("setter results");
        \\return executionState.hasStartedUserCJSExecution()===true&&executionState.hasStartedUserESMExecution()===true})()
    );
    try std.testing.expect(!engine.native_module_names.contains(key));
}
test "native module execution state ignores receiver and arguments and rejects construction without setting" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const namespace = try execution.acquire(engine); defer engine.freeValue(namespace);
    try expose(engine, "executionState", namespace);
    try check(engine,
        \\(()=>{let touches=0;const hostile=new Proxy({},{get(){touches++;throw Error("unused receiver")}});
        \\const argument={get then(){touches++;throw Error("unused argument")},[Symbol.toPrimitive](){touches++;throw Error("unused coercion")}};
        \\for(const name of Object.keys(executionState)){let rejected=false;try{Reflect.construct(executionState[name],[])}catch(error){rejected=error instanceof TypeError}if(!rejected)throw Error("constructible method")}
        \\if(executionState.hasStartedUserCJSExecution()||executionState.hasStartedUserESMExecution())throw Error("constructor changed state");
        \\if(Reflect.apply(executionState.hasStartedUserCJSExecution,hostile,[argument])!==false)throw Error("detached getter");
        \\if(Reflect.apply(executionState.setHasStartedUserCJSExecution,hostile,[argument])!==undefined)throw Error("detached setter");
        \\return touches===0&&executionState.hasStartedUserCJSExecution()===true&&executionState.hasStartedUserESMExecution()===false})()
    );
}
test "native module execution state cached acquisition retains exact methods and never resets a started fact" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const first = try execution.acquire(engine); defer engine.freeValue(first);
    const setter = try method(engine, first, "setHasStartedUserESMExecution"); defer engine.freeValue(setter);
    const result = try call(engine, setter); defer engine.freeValue(result);
    const second = try execution.acquire(engine); defer engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
    const next = try method(engine, second, "setHasStartedUserESMExecution"); defer engine.freeValue(next);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, setter, next));
    try expose(engine, "executionState", second);
    try check(engine, "executionState.hasStartedUserESMExecution()===true&&executionState.hasStartedUserCJSExecution()===false");
}
test "native module execution state belongs to each actual Engine rather than process globals" {
    const first = try em.Engine.init(std.testing.allocator, .{}); defer first.deinit();
    const first_namespace = try execution.acquire(first); defer first.freeValue(first_namespace);
    try expose(first, "executionState", first_namespace);
    try check(first, "executionState.setHasStartedUserCJSExecution()===undefined&&executionState.hasStartedUserCJSExecution()===true");
    const second = try em.Engine.init(std.testing.allocator, .{}); defer second.deinit();
    const second_namespace = try execution.acquire(second); defer second.freeValue(second_namespace);
    try expose(second, "executionState", second_namespace);
    try check(second, "executionState.hasStartedUserCJSExecution()===false&&executionState.hasStartedUserESMExecution()===false");
    try check(second, "executionState.setHasStartedUserESMExecution()===undefined&&executionState.hasStartedUserESMExecution()===true");
    try check(first, "executionState.hasStartedUserCJSExecution()===true&&executionState.hasStartedUserESMExecution()===false");
}
test "native module execution state pending cold entry wins before any native allocation or publication" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    const index = failing.alloc_index;
    failing.fail_index = index;
    const result = execution.acquire(engine);
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectError(error.JavaScriptException, result);
    try std.testing.expectEqual(index, failing.alloc_index);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?));
    try std.testing.expect(!engine.native_module_values.contains(key));
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "native module execution state pending event prevents setter mutation without hiding the original reason" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const namespace = try execution.acquire(engine); defer engine.freeValue(namespace);
    const setter = try method(engine, namespace, "setHasStartedUserCJSExecution"); defer engine.freeValue(setter);
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    try std.testing.expectError(error.JavaScriptException, call(engine, setter));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?));
    try expose(engine, "executionState", namespace);
    try check(engine, "executionState.hasStartedUserCJSExecution()===false&&executionState.hasStartedUserESMExecution()===false");
    const result = try call(engine, setter); defer engine.freeValue(result);
    try check(engine, "executionState.hasStartedUserCJSExecution()===true");
}
test "native module execution state retained methods own their native cell through cache retirement and collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const baseline = c.pi_js_native_memory_used(engine.native_memory_owner);
    const namespace = try execution.acquire(engine);
    var own_namespace = true; defer if (own_namespace) engine.freeValue(namespace);
    const getter = try method(engine, namespace, "hasStartedUserCJSExecution");
    var own_getter = true; defer if (own_getter) engine.freeValue(getter);
    const setter = try method(engine, namespace, "setHasStartedUserCJSExecution");
    var own_setter = true; defer if (own_setter) engine.freeValue(setter);
    engine.freeValue(namespace); own_namespace = false;
    // Deliberate native cache retirement: only the two retained real methods
    // keep the same native cell alive. This is a lifetime control, not a public
    // cache-eviction API or a fabricated helper owner.
    const removed = engine.native_module_values.fetchRemove(key).?;
    engine.freeValue(removed.value);
    c.JS_RunGC(engine.runtime);
    try std.testing.expect(c.pi_js_native_memory_used(engine.native_memory_owner) > baseline);
    const set_result = try call(engine, setter); engine.freeValue(set_result);
    const get_result = try call(engine, getter); defer engine.freeValue(get_result);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, get_result, c.JS_NewBool(engine.context, true)));
    engine.freeValue(setter); own_setter = false;
    engine.freeValue(getter); own_getter = false;
    c.JS_RunGC(engine.runtime);
    try std.testing.expectEqual(baseline, c.pi_js_native_memory_used(engine.native_memory_owner));
}
