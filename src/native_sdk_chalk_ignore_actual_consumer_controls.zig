//! Parameterized genuine package-consumer profile. Root supplies qualified
//! real filesystem/path/process/manifest/homedir imports and an owned directory.
//! There is no fake filesystem, matcher or package namespace fallback here.
const em = @import("extensions/engine.zig");
const discovery = @import("extensions/native_sdk_package_discovery.zig");
const supplier = @import("extensions/native_sdk_ignore708.zig");
const Scope = @import("extensions/native_sdk_chalk_scope.zig").Scope;
const owned = @import("extensions/native_sdk_owned_completion.zig");
const c = em.c;
pub fn collectActualFiles(engine: *em.Engine, inputs: discovery.Inputs, directory: c.JSValue, pattern: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    var scope: Scope = .{ .engine = engine };
    const result = owned.finishValue(&scope, collect(&scope, inputs, directory, pattern));
    // The successful result is owned; ordinary diagnostic failure is retained
    // as DATA instead of republishing it into this consuming leave operation.
    const returned = engine.leaveNativeInvocation(&invocation, if (result) |value| value else |_| c.pi_js_undefined());
    if (result) |_| {
        var completion = owned.Completion.initValue(engine, returned);
        return completion.finishValue();
    } else |err| {
        if (c.JS_IsException(returned) or c.JS_HasException(engine.context)) {
            var completion = owned.Completion.initValue(engine, returned);
            return completion.finishValue();
        }
        engine.freeValue(returned);
        return err;
    }
}
fn collect(scope: *Scope, inputs: discovery.Inputs, directory: c.JSValue, pattern: c.JSValue) !c.JSValue {
    const actual = try scope.own(try supplier.createDefault(scope.engine));
    if (!scope.equal(inputs.ignore, actual)) return error.RequiredActualPrivateIgnoreSupplier;
    const namespace = try scope.own(try discovery.create(scope.engine, inputs));
    const method = try scope.get(namespace, "collectFiles");
    return c.JS_DupValue(scope.engine.context, try scope.call(method, c.pi_js_undefined(), &.{ directory, pattern }));
}
