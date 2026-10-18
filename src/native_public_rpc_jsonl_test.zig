//! Actual c268 RPC JSONL exports with the real native StringDecoder.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const jsonl = @import("extensions/native_public_rpc_jsonl.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const c = v.c;
fn publish(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    const global = try v.own(s, c.JS_GetGlobalObject(s.engine.context));
    try v.put(s, global, name, value);
}
fn prepare(engine: *v.em.Engine, native: bool) !void {
    engine.native_io = std.testing.io;
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, prepareBody(&s, native));
}
fn prepareBody(s: *v.Scope, native: bool) !void {
    const actual = try v.own(s, try jsonl.create(s.engine));
    const decoder_namespace = s.engine.native_module_values.get("node:string_decoder") orelse return error.MissingActualStringDecoder;
    const imports = try v.object(s);
    try v.put(s, imports, "StringDecoder", try v.get(s, decoder_namespace, "StringDecoder"));
    try publish(s, "__rpcJsonlImports", imports);
    const source = try v.own(s, try s.engine.evalModule(@embedFile("extensions/fixtures/public-rpc-jsonl-c268-source.mjs"), "actual-rpc-jsonl-source.mjs"));
    try publish(s, "nativeRpcJsonl", actual);
    try publish(s, "sourceRpcJsonl", source);
    try publish(s, "selectedRpcJsonl", if (native) actual else source);
    try publish(s, "jsonlHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
}
fn run(engine: *v.em.Engine, tail: []const u8) !void {
    const source = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/public-rpc-jsonl-observer.mjs"), "\n", tail });
    defer engine.gpa.free(source);
    const namespace = try engine.evalModule(source, "actual-rpc-jsonl-observer.mjs");
    engine.freeValue(namespace);
}
fn both(tail: []const u8) !void {
    inline for (.{ false, true }) |native| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer engine.deinit();
        try prepare(engine, native);
        try run(engine, tail);
    }
}
test "Public RPC JSONL actual ordinary export shapes and retained owner" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine, true);
    try run(engine,
        \\for(const api of[sourceRpcJsonl,nativeRpcJsonl]){
        \\ for(const [name,length]of[["serializeJsonLine",1],["attachJsonlLineReader",2]]){
        \\  const fn=api[name];if(fn.name!==name||fn.length!==length||!Object.hasOwn(fn,"prototype")||Object.prototype.toString.call(fn)!=="[object Function]")throw Error("Actual JSONL ordinary function shape");
        \\ }
        \\}
    );
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const repeated = try v.own(&s, try jsonl.create(engine));
    try std.testing.expect(v.equal(&s, repeated, try v.global(&s, "nativeRpcJsonl")));
}
test "Public RPC JSONL actual LF framing Unicode split UTF8 and decoder end" {
    try both("observeJsonlFraming(selectedRpcJsonl);");
}
test "Public RPC JSONL actual template serialization undefined and circular error" {
    try both("observeJsonlSerialize(selectedRpcJsonl);");
}
test "Public RPC JSONL actual reentrant callbacks mutate the shared buffer cell" {
    try both("observeJsonlReentry(selectedRpcJsonl);");
}
test "Public RPC JSONL actual callback DATA stops before remaining-buffer assignment" {
    try both("observeJsonlCallbackFailure(selectedRpcJsonl);");
}
test "Public RPC JSONL actual partial registration preserves escaped closed cells" {
    try both("observeJsonlRegistrationFailure(selectedRpcJsonl);");
}
test "Public RPC JSONL actual newline local retires on next true body entry" {
    try both("observeJsonlNewlineSlot(selectedRpcJsonl);");
}
test "Public RPC JSONL actual JSON receiver and callee retire before template coercion" {
    try both("observeJsonlSerializeRetirement(selectedRpcJsonl);");
}
test "Public RPC JSONL actual same-getter private DATA remains ordinary" {
    try both("observeJsonlPrivateData(selectedRpcJsonl);");
}
test "Public RPC JSONL actual native B preempts callback DATA and guest catch" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine, true);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const record = try v.get(&s, try v.global(&s, "jsonlHooks"), "record");
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\let data;
        \\nativeRpcJsonl.attachJsonlLineReader({on(name,fn){if(name==="data")data=fn;return this}},()=>{
        \\ const prior=jsonlHooks.freshPrivateData();try{jsonlHooks.raiseNativeFatal()}catch(error){}throw prior;
        \\});
        \\try{data("actual\n")}catch(error){jsonlHooks.visit(3)}
    , "actual-rpc-jsonl-native-fatal.mjs"));
    try retirement.verifyRecordedActualNativeFatal(engine, record);
}
