//! Genuine AsyncGenerator consumer controls; no Node observations are invented.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn replay(case_name: []const u8, assertion: []const u8, compare_source: bool) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-classic-readable-iterator"});
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try @import("extensions/native_node_stream.zig").install(engine, try scope.get(global, "process")); try scope.put(global, "caseName", try scope.text(case_name));
    if (compare_source) {
        const bytes = @embedFile("extensions/fixtures/node-stream-classic-iterator-node24.capture-pending.json");
        const accepted = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "classic-iterator-source14-capture-state.json"))); try scope.put(global, "source14State", accepted);
        if (!scope.truthy(try scope.get(accepted, "captureAccepted"))) return error.GenuineNodeClassicIteratorSource14NotCapturedOrAccepted;
    }
    const trailer = if (compare_source) "\nif(JSON.stringify(packet)!==JSON.stringify(source14State.expectedPackets[caseName]))throw Error(JSON.stringify({case:caseName,actual:packet,expected:source14State.expectedPackets[caseName]}));" else assertion;
    const input = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/node-stream-classic-iterator-node24.input.txt"), trailer, "\nexport const proof=true;" }); defer engine.gpa.free(input);
    const value = engine.evalModule(input, "native-classic-readable-iterator.mjs") catch |err| { std.debug.print("Classic iterator {s}: {s}\n", .{ case_name, engine.last_error orelse "no diagnostic" }); return err; }; engine.freeValue(value);
    engine.finishJob(); c.JS_RunGC(engine.runtime);
}
test "native classic iterator draft genuine VM brand shared prototype and lazy start" {
    try replay("iterator-genuine-brand", "\nconst brand=packet.rows[0];if(brand.tag!=='[object AsyncGenerator]'||!brand.samePrototype||!brand.intrinsic||!brand.stream||!brand.self||!brand.next||!brand.return||!brand.throw||packet.rows[1][0]!=='rejected'||packet.rows[2]!==0||packet.rows[3].destroyed!==false)throw Error('Readable iterator must be a genuine lazy AsyncGenerator');", false);
}
test "native classic iterator draft destroyOnReturn false cleans listeners and resumes actual queue" {
    try replay("iterator-return-false-resume", "\nif(packet.rows[0].value!=='a'||packet.rows[0].done||packet.rows[1].value!==7||!packet.rows[1].done||packet.rows[2].destroyed||packet.rows[3]!==0||packet.rows[4]!==0||JSON.stringify(packet.rows[5])!==JSON.stringify(['b','c']))throw Error('iterator return discarded queued data or retained EOS listeners');", false);
}
test "native classic iterator draft queued return waits behind actual pending read" {
    try replay("iterator-return-queued-behind-read", "\nif(packet.rows[0]!==false||packet.rows[2].value!=='actual-byte-batch'||packet.rows[2].done||packet.rows[3].value!==4||!packet.rows[3].done||packet.rows[4].destroyed)throw Error('queued AsyncGenerator return preempted a pending read');", false);
}
test "native classic iterator draft pending producer failure preserves raw identity" {
    try replay("iterator-pending-stream-error", "\nif(packet.rows[0][0]!=='rejected'||packet.rows[0][1]!==true||packet.rows[1].destroyed!==true)throw Error('producer failure lost identity or readable retirement');", false);
}
test "native classic iterator draft child exit waits for actual EOF" {
    try replay("iterator-child-exit-is-not-eof", "\nif(packet.rows[0]!==false||packet.rows[1].destroyed||packet.rows[2].value!=='descendant-tail'||packet.rows[2].done||!packet.rows[3].done)throw Error('child exit manufactured readable EOF');", false);
}
test "native classic iterator draft Node pipeline awaits real write completion and backpressure" {
    try replay("pipeline-node-real-completion-backpressure", "\nif(packet.rows[0]!==false||packet.rows[1]!==1||packet.rows[2]!==true||packet.rows[3].filter(x=>Array.isArray(x)&&x[0]==='write').length!==3||packet.rows[3].filter(x=>x==='final').length!==1||packet.rows[5].writableFinished!==true)throw Error('pipeline bypassed real write acknowledgement or finalization');", false);
}
test "native classic iterator Source14 complete original packets required" {
    const cases = [_][]const u8{ "iterator-genuine-brand", "iterator-lazy-pending-eof", "iterator-for-await-natural", "iterator-break-default", "iterator-return-false-resume", "iterator-options-live-finally", "iterator-yield-thenable", "iterator-yield-rejection", "iterator-throw-identity", "iterator-pending-stream-error", "iterator-return-queued-behind-read", "iterator-child-exit-is-not-eof", "pipeline-node-real-completion-backpressure", "pipeline-node-error-closes-source-iterator" };
    for (cases) |case_name| try replay(case_name, "", true);
}
