//! Real installed builtin backends; no synthetic completed Node graph or util.
const std=@import("std");
const v=@import("extensions/native_ai_provider_values.zig");
const c=v.c;
const internal=@import("extensions/native_node_internal_builtin_require.zig");
fn call(s:*v.Scope,function:c.JSValue,id:[]const u8)!c.JSValue { return s.call(function,c.pi_js_undefined(),&.{try s.text(id)}); }
fn expectCaptureError(engine:*v.em.Engine,expected:anyerror,result:anyerror!c.JSValue)!void {
    if(result)|unexpected|{engine.freeValue(unexpected);return error.ExpectedInternalBuiltinCaptureFailure;}else |err|try std.testing.expectEqual(expected,err);
}
test "native internal require returns actual installed path exports and same owner without public CJS lookup" {
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    try @import("extensions/node_path.zig").install(engine,std.testing.io);
    var s:v.Scope=.{.engine=engine};defer s.deinit();
    const inputs:internal.Inputs=.{.bindings=&.{.{.id="path",.module_name="node:path"}}};
    const require=try s.own(try internal.acquire(engine,inputs));
    const second=try s.own(try internal.acquire(engine,inputs));try std.testing.expect(s.equal(require,second));
    const record=engine.native_module_values.get("node:path").?;const actual=try s.get(record,"default");
    // Real public bootstrap can be absent. Poisoning a guest global require
    // cannot redirect the private completed-native owner.
    const global=try s.own(try engine.checked(c.JS_GetGlobalObject(engine.context)));try s.put(global,"require",c.JS_NewInt32(engine.context,29));
    try std.testing.expect(!@import("extensions/native_node_module_constructor.zig").isCreated(engine));
    const result=try call(&s,require,"path");try std.testing.expect(s.equal(result,actual));
    try std.testing.expect(s.equal(try s.invoke(result,"dirname",&.{try s.text("/actual/internal/file.js")}),try s.text("/actual/internal")));
    try std.testing.expect(c.JS_IsUndefined(try s.get(engine.commonjs_cache,"path")));try std.testing.expect(c.JS_IsUndefined(try s.get(engine.commonjs_cache,"node:path")));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));c.JS_RunGC(engine.runtime);
    try std.testing.expect(s.equal(try call(&s,require,"path"),actual));
    try std.testing.expect(engine.native_fatal_invocation==null);try std.testing.expectEqual(@as(usize,0),engine.native_exception_diagnostics_suppressed);
}
test "native internal require acquisition precedes real backend install and failed first load publishes no fake exports" {
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    try std.testing.expectError(error.ActualInternalBuiltinNotInstalled,internal.validateInstalled(engine,.{.bindings=&.{.{.id="util",.module_name="node:util"}}}));
    var s:v.Scope=.{.engine=engine};defer s.deinit();
    const require=try s.own(try internal.acquire(engine,.{.bindings=&.{.{.id="path",.module_name="node:path"}}}));
    var args=[_]c.JSValue{try s.text("path")};
    const early=c.JS_Call(engine.context,require,c.pi_js_undefined(),args.len,&args);defer engine.freeValue(early);
    const had_reason=c.JS_HasException(engine.context);const reason=c.JS_GetException(engine.context);defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsException(early));try std.testing.expect(had_reason);try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expect(!engine.native_module_values.contains("node:path"));try std.testing.expect(!engine.native_module_values.contains("node:util"));
    // Actual native backend setup is separate; the private loader has not
    // substituted a partial namespace for it during acquisition or failure.
    try @import("extensions/node_path.zig").install(engine,std.testing.io);
    try internal.validateInstalled(engine,.{.bindings=&.{.{.id="path",.module_name="node:path"}}});
    try std.testing.expect(s.equal(try call(&s,require,"path"),try s.get(engine.native_module_values.get("node:path").?,"default")));
    try expectCaptureError(engine,error.InternalBuiltinOwnerAdmissionConflict,internal.acquire(engine,.{.bindings=&.{.{.id="util",.module_name="node:util"}}}));
    try std.testing.expectEqual(@as(usize,0),engine.native_exception_diagnostics_suppressed);
}
test "native internal require admits genuine fs and path defaults without fabricating module cache records" {
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    try @import("extensions/node_path.zig").install(engine,std.testing.io);try @import("extensions/node_fs.zig").install(engine,std.testing.io);
    var s:v.Scope=.{.engine=engine};defer s.deinit();
    const require=try s.own(try internal.acquire(engine,.{.bindings=&.{.{.id="fs",.module_name="node:fs"},.{.id="path",.module_name="node:path"}}}));
    const result=try call(&s,require,"fs");try std.testing.expect(s.equal(result,try s.get(engine.native_module_values.get("node:fs").?,"default")));
    try std.testing.expect(c.JS_IsFunction(engine.context,try s.get(result,"readFileSync")));
    try std.testing.expect(c.JS_IsUndefined(try s.get(engine.commonjs_cache,"node:fs")));try std.testing.expect(c.JS_IsUndefined(try s.get(engine.commonjs_cache,"fs")));
    const bad=try s.text("node:fs");var args=[_]c.JSValue{bad};const raw=c.JS_Call(engine.context,require,c.pi_js_undefined(),args.len,&args);defer engine.freeValue(raw);
    try std.testing.expect(c.JS_IsException(raw));try std.testing.expect(c.JS_HasException(engine.context));const reason=c.JS_GetException(engine.context);defer engine.freeValue(reason);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    // An actual test value-module record is not a completed builtin merely
    // because a guest placed default on Object.prototype.
    const invalid=try s.object();try engine.registerValueModule("owned-no-default",invalid);
    try s.put(try s.get(try s.global("Object"),"prototype"),"default",result);
    try std.testing.expect(s.equal(try s.get(invalid,"default"),result));
    try std.testing.expectError(error.ActualInternalBuiltinDefaultRequired,internal.validateInstalled(engine,.{.bindings=&.{.{.id="owned-no-default",.module_name="owned-no-default"}}}));
}

test "native internal require actual pending entry survives armed VM quota before owner allocation" {
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    var s:v.Scope=.{.engine=engine};defer s.deinit();const reason=try s.object();
    _=c.JS_Throw(engine.context,c.JS_DupValue(engine.context,reason));
    c.JS_SetMemoryLimit(engine.runtime,1);
    const result=internal.acquire(engine,.{.bindings=&.{.{.id="util",.module_name="node:util"}}});
    c.JS_SetMemoryLimit(engine.runtime,engine.options.memory_limit);
    try expectCaptureError(engine,error.JavaScriptException,result);try std.testing.expect(s.equal(reason,engine.captured_exception.?));
    try std.testing.expect(!c.JS_IsUncatchableError(engine.captured_exception.?));try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!engine.native_module_values.contains("pi-native:private/internal-builtin-require"));
    try std.testing.expect(engine.native_fatal_invocation==null);try std.testing.expectEqual(@as(usize,0),engine.native_exception_diagnostics_suppressed);
}
