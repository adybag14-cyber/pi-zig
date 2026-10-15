//! Private whole-index candidate tests. No application/default binding.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_highlight_scope.zig").Scope;
const eager_module = @import("extensions/native_syntax_highlight.zig");
const index = @import("extensions/native_highlight_index191.zig");
const complete_module = @import("extensions/native_syntax_highlight_complete191.zig");
const c = em.c;

fn bindCore(engine: *em.Engine, core: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    try s.put(global, "highlightCoreAPI", core);
}
pub fn exerciseDirect(gpa: std.mem.Allocator, failure: enum { none, lookup, factory }) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    const eager = try eager_module.createEager(engine);
    defer eager.deinit(engine);
    try index.install(engine, eager.core, eager.factories);
    try bindCore(engine, eager.core);
    if (index.ready(engine, eager.core)) return error.NativeReadinessPromotedBeforeRegistration;
    if (failure != .none) {
        const prepared = try engine.eval(if (failure == .lookup)
            "globalThis.originalReason={tag:'original failure',message:'out of memory'};let n=0;const reg=highlightCoreAPI.registerLanguage;Object.defineProperty(highlightCoreAPI,'registerLanguage',{configurable:true,get(){if(++n===8)throw originalReason;return reg}});"
        else
            "globalThis.originalReason={tag:'original failure',message:'out of memory'};globalThis.console={error(){},log(){},warn(){}};const reg=highlightCoreAPI.registerLanguage;highlightCoreAPI.registerLanguage=function(name,definition){return reg(name,name==='xml'?function failedActualFactory(){throw originalReason}:definition)};", "highlight191-owned-failure-input.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(prepared);
    }
    const actual = index.registerAll(engine, eager.core) catch |err| {
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        if (failure != .lookup or err != error.JavaScriptException) return err;
        if (index.ready(engine, eager.core)) return error.NativeReadinessPromotedAfterImportFailure;
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const original = try s.global("originalReason");
        if (!c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, original)) return error.NativeImportFailureIdentityChanged;
        return;
    };
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    try std.testing.expectEqual(failure == .none, actual);
    try std.testing.expectEqual(failure == .none, index.ready(engine, eager.core));
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const registry = try s.invoke(eager.core, "listLanguages", &.{});
    var count: i32 = 0;
    if (c.JS_ToInt32(engine.context, &count, try s.get(registry, "length")) < 0) return error.JavaScriptException;
    try std.testing.expectEqual(@as(i32, 191), count);
    inline for (@import("extensions/native_highlight_core.zig").eager_order) |name| {
        const original = try s.get(eager.factories, name);
        inline for (index.order, 0..) |canonical, ordinal| if (comptime std.mem.eql(u8, canonical, name)) {
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, index.cachedFactory(engine, ordinal)));
        };
    }
    if (failure == .factory) {
        const xml = try s.invoke(eager.core, "getLanguage", &.{try s.text("xml")});
        const name = try s.get(xml, "name");
        const bytes = try engine.toString(name);
        defer gpa.free(bytes);
        try std.testing.expectEqualStrings("Plain text", bytes);
    }
}

fn factoryProbe(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return getFactory(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("extensions/native_sdk.zig").fail(engine, err);
}
fn getFactory(engine: *em.Engine, supplied: c.JSValue) !c.JSValue {
    const text = try engine.toString(supplied);
    defer engine.gpa.free(text);
    inline for (index.order, 0..) |name, ordinal| if (std.mem.eql(u8, text, name)) return index.factoryAt(engine, ordinal);
    return error.NativeActualFactoryAbsent;
}
pub fn exerciseSource(gpa: std.mem.Allocator, install_immediates: *const fn (*em.Engine) anyerror!void, mode: []const u8, expected_bytes: []const u8) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/console.zig").install(engine, std.testing.io);
    try install_immediates(engine);
    const bundle = try complete_module.create(engine);
    defer bundle.deinit(engine);
    try bindCore(engine, bundle.eager.core);
    {
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const global = try s.own(c.JS_GetGlobalObject(engine.context));
        try s.put(global, "highlightSyntaxAPI", bundle.syntax);
        try s.put(global, "highlightWholeCase", try s.text(mode));
        try s.put(global, "highlightFactoryFor", try s.own(try engine.checked(c.JS_NewCFunction(engine.context, factoryProbe, "highlightFactoryFor", 1))));
        try s.put(global, "highlightIndexNamespace", bundle.import_function);
    }
    if (bundle.ready(engine)) return error.NativeReadinessPromotedBeforeBarrier;
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-highlight-complete191-10_7_3.input.txt"), "highlight-complete191-shared-input.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    try std.testing.expectEqual(std.mem.eql(u8, mode, "success"), bundle.ready(engine));
    try std.testing.expectEqual(if (std.mem.eql(u8, mode, "success")) c.JS_PROMISE_FULFILLED else c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, bundle.readiness));
    {
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const actual_rows = try s.global("sdkHighlightComplete191Rows");
        const actual_bytes = try engine.stringify(actual_rows);
        defer gpa.free(actual_bytes);
        const actual = try std.json.parseFromSlice(std.json.Value, gpa, actual_bytes, .{});
        defer actual.deinit();
        const original = try std.json.parseFromSlice(std.json.Value, gpa, expected_bytes, .{});
        defer original.deinit();
        const expected_rows = original.value.object.get("rows").?.array.items;
        try std.testing.expectEqual(expected_rows.len, actual.value.array.items.len);
        for (actual.value.array.items, expected_rows) |row, expected| {
            const a = try std.json.Stringify.valueAlloc(gpa, row, .{});
            defer gpa.free(a);
            const e = try std.json.Stringify.valueAlloc(gpa, expected, .{});
            defer gpa.free(e);
            if (!std.mem.eql(u8, a, e)) {
                std.debug.print("Actual full191 Source mismatch {s}\nNative: {s}\nSource: {s}\n", .{ expected.object.get("name").?.string, a, e });
                return error.NativeHighlightComplete191SourceMismatch;
            }
        }
    }
    const released = try engine.eval("delete globalThis.highlightCoreAPI;delete globalThis.highlightSyntaxAPI;delete globalThis.highlightFactoryFor;delete globalThis.highlightIndexNamespace;delete globalThis.highlightWholeCase;delete globalThis.sdkHighlightComplete191Rows;", "highlight191-owned-release.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native actual complete191 direct registration requires all real factories and preserves eager identities" {
    try exerciseDirect(std.testing.allocator, .none);
}
test "native actual complete191 import failure does not promote readiness and preserves guest reason" {
    try exerciseDirect(std.testing.allocator, .lookup);
}
test "native actual complete191 ordinary factory fallback and lookalike OOM never promote readiness" {
    try exerciseDirect(std.testing.allocator, .factory);
}
