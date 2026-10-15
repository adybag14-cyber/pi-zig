const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const sdk = @import("extensions/native_sdk.zig");
const native = @import("extensions/native_node_function.zig");
const c = em.c;
fn read(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return js.get(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), "field");
}
test "native node function preserves caught getter exception without diagnostic coercion" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "nativeRead", try native.createArrow(engine, "nativeRead", 1, read, &.{}));
    const result = try engine.evalModule(
        \\let coerced=0;const reason={toString(){coerced++;throw Error('diagnostic must not run before guest catch')}};const input={get field(){throw reason}};let caught;try{nativeRead(input)}catch(error){caught=error}if(caught!==reason||coerced!==0)throw Error('guest exception was coerced');export const done=true;
    , "native-function-raw-getter.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
