//! Actual shared graph and Source replay entry point. No stand-in compiler.
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = js.c;
fn gc(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = em.Engine.fromContext(context.?);
    c.JS_RunGC(e.runtime);
    return c.pi_js_undefined();
}
pub fn graph(e: *em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const shared = try s.own(try @import("extensions/native_typebox_memory.zig").create(e));
    const types = try s.object();
    try s.put(shared, "Type", types);
    try @import("extensions/native_typebox_partial.zig").install(e, types, shared);
    try @import("extensions/native_typebox_operators_production.zig").install(e, types, shared);
    const compiler = try s.own(try @import("extensions/native_typebox_compile_production.zig").create(e, shared));
    try s.put(shared, "Compiler", compiler);
    return c.JS_DupValue(e.context, shared);
}
pub fn replay(e: *em.Engine, actual: c.JSValue, source: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const global = try s.own(c.JS_GetGlobalObject(e.context));
    try s.put(global, "gc", try s.own(try e.checked(c.JS_NewCFunction(e.context, gc, "gc", 0))));
    try s.put(global, "actualSchemaType", try s.get(actual, "Type"));
    try s.put(global, "actualSchemaSystem", actual);
    try s.put(global, "actualSchemaCompiler", try s.get(actual, "Compiler"));
    try s.put(global, "typeboxCompileProductionSource", source);
    const pending = try s.own(try e.evalModule(@embedFile("extensions/fixtures/typebox-compile-production.input.mjs") ++
        \\const expected=typeboxCompileProductionSource.rows,actual=typeboxCompileProductionObservation.rows;if(expected.length!==actual.length)throw Error(JSON.stringify({scope:'actual TypeBox Compile',expected:expected.length,actual:actual.length}));for(let index=0;index<expected.length;index++){if(JSON.stringify(expected[index])!==JSON.stringify(actual[index]))throw Error(JSON.stringify({index,expected:expected[index],actual:actual[index]}))}export const pass=true;
    , "actual-typebox-compile-production.mjs"));
    _ = try s.own(try e.awaitValue(pending));
}
