const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
fn setup() !*js.Engine {
    const engine = try js.Engine.init(std.testing.allocator, .{ .memory_limit = 64 * 1024 * 1024 });
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"source8a9-ui"});
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("extensions/fixtures/stdin-herdr-original-8a9.json");
    try js.define(engine, root, "latestUiSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-source8a9-ui")));
    return engine;
}
fn replay(engine: *js.Engine, source: []const u8, filename: [:0]const u8) !void {
    const result = engine.evalModule(source, filename) catch |err| {
        std.debug.print("Source8a9 native UI failure: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(result);
}
test "Source8a9 native stdin exact14 actual real timer stages no reply tail or BEL keyboard leakage" {
    const engine = try setup();
    defer engine.deinit();
    try replay(engine,
        \\import{StdinBuffer}from'pi-tui';
        \\if(latestUiSource.stdin.length!==14)throw Error('actual Source14 count');
        \\for(const item of latestUiSource.stdin){const input=new StdinBuffer(item.options),data=[],paste=[],stages=[];input.on('data',value=>data.push(value));input.on('paste',value=>paste.push(value));const observe=phase=>stages.push({phase,data:data.slice(),paste:paste.slice(),buffer:input.getBuffer()});try{input.process(item.first);observe('first');await new Promise(resolve=>setTimeout(resolve,25));observe('after-deadline');if(item.tail)input.process(item.tail);observe('tail');await new Promise(resolve=>setTimeout(resolve,25));observe('after-tail-deadline');if(JSON.stringify(stages)!==JSON.stringify(item.stages))throw Error(JSON.stringify({id:item.id,actual:stages,expected:item.stages}));}finally{input.destroy()}}
    , "actual-source8a9-stdin.mjs");
}
test "Source8a9 native capability exact10 actual Herdr profiles preserve truecolor and mux precedence" {
    const engine = try setup();
    defer engine.deinit();
    try replay(engine,
        \\import{detectCapabilities}from'pi-tui';
        \\if(latestUiSource.caps.length!==10)throw Error('actual Source10 count');const saved=process.env;try{for(const item of latestUiSource.caps){process.env={...item.env};const actual=detectCapabilities(()=>false);if(JSON.stringify(actual)!==JSON.stringify(item.value))throw Error(JSON.stringify({env:item.env,actual,expected:item.value}));}}finally{process.env=saved}
    , "actual-source8a9-herdr.mjs");
}
