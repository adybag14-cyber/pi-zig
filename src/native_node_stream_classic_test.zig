//! Prepared native consumer controls. No source observation is accepted here
//! until the genuine Node Source20 packet state explicitly says accepted.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue { c.JS_RunGC(em.Engine.fromContext(context.?).runtime); return c.pi_js_undefined(); }
fn original(engine: *em.Engine, scope: *Scope, global: c.JSValue, key: [*:0]const u8, source: []const u8, filename: [:0]const u8) !void {
    const transformed = try @import("extensions/typescript.zig").transform(engine.gpa, source); defer engine.gpa.free(transformed);
    const namespace = try scope.own(try engine.evalModule(transformed, filename)); try scope.put(global, key, namespace);
}
fn replay(case_name: []const u8, assertion: []const u8, compare_source: bool) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-node-stream-classic-control"});
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try @import("extensions/native_node_stream.zig").install(engine, try scope.get(global, "process"));
    try @import("extensions/native_node_stream_web.zig").install(engine);
    try original(engine, &scope, global, "originalJsonl", @embedFile("extensions/fixtures/node-stream-classic-source/jsonl.ts"), "classic-original-jsonl.mjs");
    try original(engine, &scope, global, "originalChildWait", @embedFile("extensions/fixtures/node-stream-classic-source/wait-for-child-process.excerpt.ts"), "classic-original-child-wait.mjs");
    try scope.put(global, "caseName", try scope.text(case_name)); try scope.put(global, "nativeCollect", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, collect, "nativeCollect", 0))));
    if (compare_source) {
        const state = @embedFile("extensions/fixtures/node-stream-classic-node24.capture-pending.json");
        try scope.put(global, "source20State", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, state.ptr, state.len, "classic-source20-capture-state.json"))));
        const accepted = try scope.get(try scope.get(global, "source20State"), "captureAccepted");
        if (!scope.truthy(accepted)) return error.GenuineNodeClassicSource20NotCapturedOrAccepted;
    }
    const trailer = if (compare_source) "\nif(JSON.stringify(packet)!==JSON.stringify(source20State.expectedPackets[caseName]))throw Error(JSON.stringify({case:caseName,actual:packet,expected:source20State.expectedPackets[caseName]}));" else assertion;
    const input = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/node-stream-classic-node24.input.txt"), trailer, "\nexport const proof=true;" }); defer engine.gpa.free(input);
    const value = engine.evalModule(input, "native-node-classic-stream-control.mjs") catch |err| { std.debug.print("Classic stream {s}: {s}\n", .{ case_name, engine.last_error orelse "no diagnostic" }); return err; }; engine.freeValue(value);
    engine.finishJob(); c.JS_RunGC(engine.runtime);
}
test "native classic stream draft original JSONL consumer" {
    try replay("from-sync-jsonl-original", "\nconst lines=packet.rows[0];if(lines.length!==3||JSON.parse(lines[0]).text!=='a\\u2028b\\u2029c'||lines[1]!=='{\"a\":1}'||lines[2]!=='{\"b\":2}')throw Error('original strict LF consumer lost input');", false);
}
test "native classic stream draft preserves child tail after exit without manufacturing EOF" {
    try replay("original-child-exit-tail", "\nif(packet.rows[0]!==false||packet.rows[1]!==false||packet.rows[2]!==0||packet.rows[3]!=='HEAD\\nTICK1\\nTICK2\\nTICK3\\nTAIL\\n'||packet.rows[4]!==true||packet.rows[5]!==true||packet.rows[6]!==0||packet.rows[7]!==0)throw Error('original child stream lifetime or cleanup changed');", false);
}
test "native classic stream draft asynchronous write retains actual completion and drain" {
    try replay("write-async-backpressure", "\nif(packet.rows[0]!==false||packet.rows[1]!==false||packet.rows[2].writableLength!==3||packet.rows[3].writableLength!==1||packet.rows[5].writableLength!==0)throw Error('actual write completion did not own queue/backpressure');", false);
}
test "native classic stream draft genuine Web reader cancellation" {
    try replay("from-web-cancel", "\nif(JSON.stringify(packet.rows[0])!==JSON.stringify([['cancel',true],['destroyed',true],['error',true]]))throw Error('actual reader cancel/error identity or ordering lost');", false);
}
test "native classic stream Source20 complete original packets required" {
    const cases = [_][]const u8{ "constructor-metadata", "write-sync-order", "write-async-backpressure", "cork-writev", "final-finish-close", "destroy-once", "duplex-half-open", "readable-read-unshift", "pipe-pause-drain-unpipe", "decoder-utf8-carry-bom", "decoder-utf16-base64", "from-sync-jsonl-original", "from-async-values-order", "from-async-iterator-close", "from-web-real-reader", "from-web-cancel", "passthrough-readable-backpressure", "pipeline-node-and-end-false", "finished-premature-close", "original-child-exit-tail" };
    for (cases) |case_name| try replay(case_name, "", true);
}
