//! Actual Node v24.13 IncomingMessage bodies over the same genuine Stream
//! imports. The explicit finished import seam exercises synchronous/late
//! callback behavior; this group does not qualify physical HTTP/TCP parsing.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const incoming = @import("extensions/native_node_http_incoming.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/native-node-http-incoming-observer.mjs");
const import_host =
    \\const actual = globalThis.__incomingActualStream;
    \\const apply = Reflect.apply;
    \\export const state = {finished:null};
    \\function finished(...args) { return apply(state.finished ?? actual.finished,this,args); }
    \\export const streams = {Readable:actual.Readable, finished};
;
const Fixture = struct {
    environment: std.process.Environ.Map,
    engine: *v.em.Engine,
    fn init(self: *Fixture) !void {
        self.environment = .init(std.testing.allocator);
        errdefer self.environment.deinit();
        self.engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
        errdefer self.engine.deinit();
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine, std.testing.io, &self.environment, &.{"native-http-incoming-control"});
        try @import("extensions/native_node_os.zig").install(self.engine);
        var s: v.Scope = .{ .engine = self.engine };
        try v.owned.finishVoid(&s, prepareBody(&s));
    }
    fn deinit(self: *Fixture) void {
        self.engine.deinit();
        self.environment.deinit();
    }
};
fn publish(s: *v.Scope, name: [*:0]const u8, input: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, input);
}
fn prepareBody(s: *v.Scope) !void {
    const engine = s.engine;
    const actual_stream = engine.native_module_values.get("node:stream") orelse return error.ActualNodeStreamRequired;
    try publish(s, "__incomingActualStream", actual_stream);
    const host = try v.own(s, try engine.evalModule(import_host, "actual-http-incoming-import-host.mjs"));
    const streams = try v.get(s, host, "streams");
    const native = try v.own(s, try incoming.create(engine, .{ .streams = streams }));
    const again = try v.own(s, try incoming.create(engine, .{ .streams = streams }));
    try std.testing.expect(v.equal(s, native, again));
    const primordials = try v.object(s);
    const object = try v.global(s, "Object");
    try v.put(s, primordials, "ObjectDefineProperty", try v.get(s, object, "defineProperty"));
    try v.put(s, primordials, "ObjectSetPrototypeOf", try v.get(s, object, "setPrototypeOf"));
    try v.put(s, primordials, "Symbol", try v.global(s, "Symbol"));
    const dependencies = try v.object(s);
    try v.put(s, dependencies, "primordials", primordials);
    try v.put(s, dependencies, "streams", streams);
    try publish(s, "__httpIncomingSourceDependencies", dependencies);
    const source = try v.own(s, try engine.evalModule(
        @embedFile("extensions/fixtures/native-node-http-incoming-v24-source.mjs"), "actual-node-v24-http-incoming.mjs"));
    try publish(s, "incomingNative", native);
    try publish(s, "incomingSource", source);
    try publish(s, "incomingStreams", streams);
    try publish(s, "incomingControl", try v.get(s, host, "state"));
    try publish(s, "incomingHooks", try v.own(s, try retirement.createNativeRetirementHooks(engine)));
}
fn run(engine: *v.em.Engine, source: []const u8) !void {
    engine.freeValue(try engine.evalModule(source, "actual-http-incoming-control.mjs"));
}
fn both(comptime tail: []const u8) !void {
    inline for (.{ "incomingSource", "incomingNative" }) |name| {
        var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
        try run(fixture.engine, observer ++ "\nconst incomingSelected = " ++ name ++ ";\n" ++ tail);
        try std.testing.expect(!c.JS_HasException(fixture.engine.context));
        try std.testing.expect(!c.JS_IsJobPending(fixture.engine.runtime));
        try std.testing.expect(fixture.engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), fixture.engine.native_exception_diagnostics_suppressed);
    }
}
fn record(engine: *v.em.Engine) !c.JSValue {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, recordBody(&s));
}
fn recordBody(s: *v.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "incomingHooks"), "record"));
}
fn noGuestCatch(engine: *v.em.Engine, original: c.JSValue) !void {
    const reached = c.JS_GetPropertyStr(engine.context, original, "guestReached");
    defer engine.freeValue(reached);
    try std.testing.expect(c.JS_IsBool(reached) and c.JS_ToBool(engine.context, reached) == 0);
}
test "Node HTTP incoming actual constructor methods descriptors and Stream identity" { try both("observeIncomingShape(incomingSelected,incomingStreams);"); }
test "Node HTTP incoming constructor preserves options then live Readable call order" { try both("observeIncomingConstructor(incomingSelected,incomingStreams);"); }
test "Node HTTP incoming actual known duplicate and assigned headers" { try both("observeIncomingHeaders(incomingSelected);"); }
test "Node HTTP incoming distinct headers and completed trailers retain real arrays" { try both("observeIncomingDistinct(incomingSelected);"); }
test "Node HTTP incoming known-field fast paths precede one live lowercase recursion" { try both("observeIncomingKnownFields(incomingSelected);"); }
test "Node HTTP incoming repeated dynamic keys perform separate Source references" { try both("observeIncomingDynamicKeys(incomingSelected);"); }
test "Node HTTP incoming compound assignment retains one converted LHS across generic plus" { try both("observeIncomingCompound(incomingSelected);"); }
test "Node HTTP incoming lazy getter rereads count and selects callee before indices" { try both("observeIncomingHeaderLoop(incomingSelected);"); }
test "Node HTTP incoming addHeaderLines orders raw count and destination assignments" { try both("observeIncomingLineOrder(incomingSelected);"); }
test "Node HTTP incoming timeout call retires before socket read and connection is live" { try both("observeIncomingTimeoutConnection(incomingSelected,incomingHooks);"); }
test "Node HTTP incoming read predicates retire before following live socket operations" { try both("observeIncomingReadPredicates(incomingSelected,incomingHooks);"); }
test "Node HTTP incoming dump and close perform actual distinct state operations" { try both("observeIncomingDump(incomingSelected);"); }
test "Node HTTP incoming direct destroy tick invokes real listener-count error policy" { try both("observeIncomingDestroyElse(incomingSelected);"); }
test "Node HTTP incoming deferred finished callback closes actual cleanup cell" { try both("observeIncomingDestroyFinished(incomingSelected,incomingControl);"); }
test "Node HTTP incoming synchronous finished callback and escape retain cleanup TDZ" { try both("observeIncomingCleanupTDZ(incomingSelected,incomingControl);"); }
test "Node HTTP incoming destroy short circuits keep repeated socket reads" { try both("observeIncomingDestroyOrder(incomingSelected,incomingControl);"); }
test "Node HTTP incoming same getter private DATA remains ordinary" { try both("observeIncomingPrivateData(incomingSelected,incomingHooks);"); }
test "Node HTTP incoming actual current B precedes later getter and guest catch" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const original = try record(fixture.engine); defer fixture.engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(fixture.engine, observer ++
        "\nobserveIncomingCurrentFatal(incomingNative,incomingHooks);"));
    try retirement.verifyRecordedActualNativeFatal(fixture.engine, original);
    try retirement.verifyNoVisits(original, .{ 1, 2 });
    try noGuestCatch(fixture.engine, original);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}
test "Node HTTP incoming actual predicate retirement B stops resume and guest catch" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const original = try record(fixture.engine); defer fixture.engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(fixture.engine, observer ++
        "\nobserveIncomingPredicateFatal(incomingNative,incomingHooks);"));
    try retirement.verifyActualRetirementFatal(fixture.engine, original, 0);
    try retirement.verifyNoVisits(original, .{ 1, 2 });
    try noGuestCatch(fixture.engine, original);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}
test "Node HTTP incoming drives the genuine Readable body through completed data flow" { try both("await observeIncomingRealReadable(incomingSelected,incomingStreams);"); }
test "Node HTTP incoming binary operands retire before actual compound setter" { try both("observeIncomingCompoundRetirement(incomingSelected,incomingHooks);"); }
