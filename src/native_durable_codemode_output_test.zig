//! Execute the latest Source formatter's forty-six frozen DTO/callback cases.
const std = @import("std");
const em = @import("extensions/engine.zig");
const vm = @import("extensions/native_values.zig");
const durable = @import("extensions/native_durable.zig");
const c = em.c;
fn format(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("extensions/native_durable_codemode_output.zig").format(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| durable.rejectedPromise(engine, err);
}
test "native durable CodeMode output forty six actual Source layout limits images and linear adjacent parts" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/node_buffer.zig").install(engine);
    const raw = @embedFile("durable/fixtures/durable-ee-codemode-output-source.json");
    const fixture = try engine.checked(c.JS_ParseJSON(engine.context, raw, raw.len, "actual-ee-codemode-output-source"));
    defer engine.freeValue(fixture);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "originalCodemodeOutput", c.JS_DupValue(engine.context, fixture));
    try engine.bindFunction("nativeFormatDurableCodeMode", format, 2);
    const result = engine.evalModule(
        \\const rows=[];
        \\for(const original of originalCodemodeOutput.rows){
        \\ const input=original.input,writes=[];
        \\ const options={generatedImages:0,wallMs:1234,maxOutputTokens:10000,calls:[],limits:{maxBytes:4*1024*1024,maxLines:100000},...input.options,write:async(name,data)=>{writes.push({name,...(typeof data==='string'?{text:data}:{bytes:[...data]})});if(input.writer==='error')return{error:'fixture write denied'};if(input.writer==='reject')throw Error('fixture write rejected');return{path:`/owned-output/${name}`}}};
        \\ let outcome;try{outcome={ok:true,value:await nativeFormatDurableCodeMode(input.result,options)}}catch(error){outcome={ok:false,name:error.name,message:error.message}}
        \\ const actual={input,outcome,writes};if(JSON.stringify(actual)!==JSON.stringify(original))throw Error(JSON.stringify({case:input.name,actual,original}));rows.push(actual);
        \\}
        \\globalThis.nativeCodemodeOutputTrace={source:originalCodemodeOutput.source,rows};export const proof=true;
    , "native-durable-ee-codemode-output") catch |err| {
        std.debug.print("Actual CodeMode output {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no VM diagnostic" });
        return err;
    };
    engine.freeValue(result);
}
