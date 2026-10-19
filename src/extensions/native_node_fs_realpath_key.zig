//! One actual internal/fs/utils realpathCacheKey Symbol per Engine.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = @import("native_node_operation_scope.zig").Scope;
const key = "\x00native.fs.realpathCacheKey";
fn acquireBody(s: *Scope) !c.JSValue {
    try s.pending();
    if (s.engine.native_module_values.get(key)) |known| return c.JS_DupValue(s.engine.context, known);
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    const symbol = try s.call(try s.get(global, "Symbol"), c.pi_js_undefined(), &.{try s.text("realpathCacheKey")});
    if (!c.JS_IsSymbol(symbol)) return error.RequiredActualFsPrivateSymbol;
    return c.JS_DupValue(s.engine.context, symbol);
}
pub fn acquire(engine: *v.em.Engine) !c.JSValue {
    var s = Scope.init(engine);
    const result = try s.finish(acquireBody(&s));
    if (engine.native_module_values.get(key)) |known| {
        // Select the completed winner before the losing candidate can retire.
        // Its cleanup may itself reenter; the selected owner already survives.
        var completion = @import("native_sdk_owned_completion.zig").Completion.initValue(engine, c.JS_DupValue(engine.context, known));
        completion.release(result);
        return completion.finishValue();
    }
    return @import("native_node_fs_private_publication.zig").publish(engine, key, result);
}
