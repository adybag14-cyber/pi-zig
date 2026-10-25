//! Source-only actual linked-VM controls. Each comparison uses fresh real
//! platform, model resolver, CLI and Chalk owners; no Node host is executed.
//! Controlled namespace-member mutations isolate wrapper seams and are not
//! evidence of physical ModelRuntime or whole-application startup behavior.
const std = @import("std");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const em = @import("extensions/engine.zig");
const wrapper = @import("extensions/native_sdk_model_scope_warning.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const original = @embedFile("extensions/fixtures/sdk-model-scope-warning-4954-source.mjs");
const observer = @embedFile("extensions/fixtures/sdk-model-scope-warning-observer.mjs");
const key = "pi-private:actual-sdk-model-scope-warning";
const gpa = std.testing.allocator;

const Fixture = struct {
    environment: std.process.Environ.Map,
    engine: *em.Engine,
    fn init(self: *Fixture) !void {
        self.environment = .init(gpa);
        errdefer self.environment.deinit();
        self.engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000, .interrupt_budget = 4_000_000 });
        errdefer self.engine.deinit();
        try @import("extensions/native_sdk_application_bootstrap.zig").installPlatform(
            self.engine, std.testing.io, &self.environment, &.{"actual-model-scope-warning-control"});
    }
    fn deinit(self: *Fixture) void {
        self.engine.deinit();
        self.environment.deinit();
    }
};
fn expose(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn runGlobal(s: *v.Scope, source: []const u8) !void {
    _ = try v.own(s, try s.engine.eval(source, "model-scope-warning-control.js", c.JS_EVAL_TYPE_GLOBAL));
}
fn runModule(engine: *em.Engine, source: []const u8) !void {
    const result = try engine.evalModule(source, "model-scope-warning-observer.mjs");
    engine.freeValue(result);
}
fn pendingReason(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const global = c.JS_GetGlobalObject(context);
    const state = c.JS_GetPropertyStr(context, global, "__mswState");
    const reason = c.JS_GetPropertyStr(context, state, "reason");
    c.JS_FreeValue(context, state);
    c.JS_FreeValue(context, global);
    _ = c.JS_Throw(context, reason);
    return c.JS_NewInt32(context, 17);
}
fn providers(s: *v.Scope) !void {
    const engine = s.engine;
    const chalk = try v.own(s, try @import("extensions/native_sdk_chalk.zig").createDefault(engine));
    const cli = try v.own(s, try @import("extensions/native_sdk_main_runtime_helpers.zig").cliBindings(engine));
    const resolver = try v.own(s, try @import("extensions/native_sdk_public_model_resolver.zig").create(
        engine, .{ .thinking = try v.get(s, cli, "isValidThinkingLevel") }));
    try expose(s, "__mswChalk", chalk);
    try expose(s, "__mswResolver", resolver);
    try expose(s, "__mswHooks", try v.own(s, try retirement.createNativeRetirementHooks(engine)));
    try expose(s, "__mswPending", try v.own(s, try engine.checked(
        c.JS_NewCFunction(engine.context, pendingReason, "__mswPending", 0))));
    try expose(s, "__mswSourceFactory", try v.own(s, try engine.eval(
        original, "original-model-scope-warning-factory.js", c.JS_EVAL_TYPE_GLOBAL)));
    try runGlobal(s, observer);
}
fn sourceFunction(s: *v.Scope) !c.JSValue {
    const resolver = try v.global(s, "__mswResolver");
    const original_resolver = try v.get(s, resolver, "resolveModelScopeWithDiagnostics");
    const chalk = try v.global(s, "__mswChalk");
    return v.duplicate(s, try v.call(s, try v.global(s, "__mswSourceFactory"),
        c.pi_js_undefined(), &.{original_resolver, chalk}));
}
fn subject(s: *v.Scope, source: bool) !void {
    const selected = try v.own(s, if (source) try h.expression(s.engine, sourceFunction, .{}) else
        try wrapper.create(s.engine));
    try expose(s, "__mswSubject", selected);
}
fn clean(engine: *em.Engine) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn capture(comptime name: []const u8, source: bool) ![]u8 {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine };
    defer s.deinit();
    try providers(&s);
    try runGlobal(&s, "mswPrepare('" ++ name ++ "');");
    try subject(&s, source);
    if (comptime std.mem.eql(u8, name, "lexical-console"))
        try runGlobal(&s, "let console = __mswState.lexicalConsole;");
    if (comptime std.mem.eql(u8, name, "console-tdz"))
        try std.testing.expectError(error.JavaScriptException, runGlobal(&s,
            "throw __mswState.reason; let console;"));
    try runModule(fixture.engine,
        "globalThis.__mswObserved=JSON.stringify(await mswObserve('" ++ name ++ "',__mswSubject));");
    const result = try v.global(&s, "__mswObserved");
    try std.testing.expect(c.JS_IsString(result));
    try clean(fixture.engine);
    return fixture.engine.toString(result);
}
fn both(comptime name: []const u8) !void {
    const expected = try capture(name, true);
    defer gpa.free(expected);
    const actual = try capture(name, false);
    defer gpa.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}
fn fatal(comptime name: []const u8) !void {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine };
    defer s.deinit();
    try providers(&s);
    try runGlobal(&s, "mswPrepare('" ++ name ++ "');");
    try subject(&s, false);
    const record = try v.get(&s, try v.global(&s, "__mswHooks"), "record");
    try std.testing.expectError(error.JavaScriptException,
        runModule(fixture.engine, "await mswFatal(__mswSubject);"));
    if (comptime std.mem.eql(u8, name, "current-fatal"))
        try retirement.verifyRecordedActualNativeFatal(fixture.engine, record)
    else if (comptime std.mem.eql(u8, name, "retirement-fatal"))
        try retirement.verifyActualRetirementFatal(fixture.engine, record, 0)
    else
        try retirement.verifyActualCancellationNoGuestClose(fixture.engine, record);
    try retirement.verifyNoVisits(record, .{1,2,3});
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}

test "native model scope warning genuine async callable shape and source promise" { try both("shape"); }
test "native model scope warning empty actual model scope emits no warning" { try both("empty"); }
test "native model scope warning actual resolver preserves exact selected model identity" { try both("match"); }
test "native model scope warning actual resolver emits exact missing pattern warning" { try both("missing"); }
test "native model scope warning actual Chalk yellow preserves ANSI warning bytes" { try both("colored"); }
test "native model scope warning actual resolver preserves sorted ambiguity warning" { try both("ambiguous"); }
test "native model scope warning actual resolver receives original options and receiver" { try both("options"); }
test "native model scope warning real resolver Await delays warnings until catalog settlement" { try both("deferred"); }
test "native model scope warning rejected catalog reason remains original identity" { try both("rejected"); }
test "native model scope warning native private DATA rejection stays catchable ordinary data" { try both("actual-data"); }
test "native model scope warning captured real resolver resists later member replacement" { try both("capture-import"); }
test "native model scope warning result destructuring reads scoped models before diagnostics" { try both("result-order"); }
test "native model scope warning primitive result destructuring boxes exactly once" { try both("boxed-once"); }
test "native model scope warning null result rejects before iteration" { try both("null-result"); }
test "native model scope warning missing diagnostics rejects as noniterable" { try both("missing-diagnostics"); }
test "native model scope warning first result getter failure suppresses second Get" { try both("getter-throw"); }
test "native model scope warning second result getter retains original throw" { try both("diagnostics-throw"); }
test "native model scope warning real Await assimilates returned thenable" { try both("result-thenable"); }
test "native model scope warning return adopts original scopedModels thenable" { try both("return-thenable"); }
test "native model scope warning for of caches next through later replacement" { try both("cached-next"); }
test "native model scope warning next throw skips iterator return" { try both("next-throw"); }
test "native model scope warning done getter throw skips iterator return" { try both("done-throw"); }
test "native model scope warning value getter throw skips iterator return" { try both("value-throw"); }
test "native model scope warning warning body throw closes iterator exactly once" { try both("warn-throw"); }
test "native model scope warning original warning error dominates close throw" { try both("close-throw"); }
test "native model scope warning template Symbol rejection closes iterator" { try both("message-symbol"); }
test "native model scope warning template coercion uses string hint" { try both("message-coercion"); }
test "native model scope warning nested warning calls preserve original reference order" { try both("console-order"); }
test "native model scope warning console receives uncoerced exact color result" { try both("yellow-value"); }
test "native model scope warning message object retires before color invocation" { try both("message-lifetime"); }
test "native model scope warning color callable retires before console invocation" { try both("yellow-lifetime"); }
test "native model scope warning for of head remains live through final step" { try both("head-lifetime"); }
test "native model scope warning normal native return preserves actual pending reason" { try both("pending-reason"); }
test "native model scope warning deleted console identifier is a ReferenceError" { try both("deleted-console"); }
test "native model scope warning global lexical console shadows global object property" { try both("lexical-console"); }
test "native model scope warning uninitialized global lexical console preserves TDZ" { try both("console-tdz"); }
test "native model scope warning warning callback can reenter with separate async state" { try both("warning-reentry"); }

test "native model scope warning actual fresh fatal bypasses guest await catch" { try fatal("current-fatal"); }
test "native model scope warning message retirement fatal prevents color invocation" { try fatal("retirement-fatal"); }
test "native model scope warning message retirement cancellation prevents color invocation" { try fatal("retirement-cancel"); }

fn reenter(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return wrapper.create(engine);
}
test "native model scope warning warm cache preserves genuine imported owners" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine };
    defer s.deinit();
    try providers(&s);
    const first = try v.own(&s, try wrapper.create(fixture.engine));
    try runGlobal(&s,
        \\Object.defineProperty(__mswResolver,"resolveModelScopeWithDiagnostics",{configurable:true,
        \\get(){throw Error("warm import reread");}});
    );
    const second = try v.own(&s, try wrapper.create(fixture.engine));
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, first, second));
    try clean(fixture.engine);
}
test "native model scope warning cold reentry rejects incomplete cache publication" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine };
    defer s.deinit();
    try providers(&s);
    try expose(&s, "__mswReenter", try v.ordinary(&s, "actualWarningReenter", 0, reenter, &.{}));
    try runGlobal(&s,
        \\globalThis.__mswReentered=false;globalThis.__mswReads=0;
        \\const savedWarningResolver=__mswResolver.resolveModelScopeWithDiagnostics;
        \\Object.defineProperty(__mswResolver,"resolveModelScopeWithDiagnostics",{configurable:true,get(){
        \\  __mswReads++;try{__mswReenter();}catch(error){
        \\    __mswReentered=String(error).includes("ActualModelScopeWarningCreationReentry");
        \\  }return savedWarningResolver;
        \\}});
    );
    _ = try v.own(&s, try wrapper.create(fixture.engine));
    const observed = try v.own(&s, try fixture.engine.eval(
        "__mswReentered&&__mswReads===1", "warning-reentry-oracle.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, observed, c.JS_NewBool(fixture.engine.context, true)));
    try std.testing.expect(fixture.engine.native_module_values.contains(key));
    try clean(fixture.engine);
}
test "native model scope warning failed import getter publishes no cache and retries" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine };
    defer s.deinit();
    try providers(&s);
    try runGlobal(&s,
        \\globalThis.__mswColdReason={sentinel:true};
        \\const savedColdWarningResolver=__mswResolver.resolveModelScopeWithDiagnostics;
        \\Object.defineProperty(__mswResolver,"resolveModelScopeWithDiagnostics",{configurable:true,
        \\get(){throw __mswColdReason;}});
    );
    const reason = try v.global(&s, "__mswColdReason");
    try std.testing.expectError(error.JavaScriptException, wrapper.create(fixture.engine));
    try std.testing.expect(!fixture.engine.native_module_values.contains(key));
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, reason,
        fixture.engine.captured_exception orelse return error.MissingColdWarningReason));
    try runGlobal(&s,
        \\Object.defineProperty(__mswResolver,"resolveModelScopeWithDiagnostics",{
        \\configurable:true,value:savedColdWarningResolver});
    );
    const restored = try v.own(&s, try wrapper.create(fixture.engine));
    try std.testing.expect(c.JS_IsFunction(fixture.engine.context, restored));
    try std.testing.expect(c.JS_IsAsyncFunction(restored));
    try clean(fixture.engine);
}
test "native model scope warning missing actual platform fails without fabricated owners" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    try std.testing.expectError(error.JavaScriptException, wrapper.create(engine));
    try std.testing.expect(!engine.native_module_values.contains(key));
    const reason = engine.captured_exception orelse return error.MissingActualPlatformReason;
    var s: v.Scope = .{ .engine = engine };
    defer s.deinit();
    const message = try v.get(&s, reason, "message");
    const matched = try v.invoke(&s, message, "includes", &.{try v.text(&s, "NativeChalkRequiresActualProcess")});
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, matched, c.JS_NewBool(engine.context, true)));
    try clean(engine);
}
