//! Source-only foreground successor controls over actual native platform/Chalk.
//! The source fixture contains the complete pinned Chalk source bodies. Both
//! sides receive genuine detector inputs; explicit levels isolate style parity.
const std = @import("std");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const em = @import("extensions/engine.zig");
const chalk = @import("extensions/native_sdk_chalk.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const source_fixture = @embedFile("extensions/fixtures/sdk-chalk-project-trust-colors-original.mjs");
const observer = @embedFile("extensions/fixtures/sdk-chalk-project-trust-colors-observer.mjs");
const yellow_regression = @embedFile("extensions/fixtures/sdk-chalk-project-trust-yellow-regression.mjs");
const notify_fixture = @embedFile("extensions/fixtures/sdk-chalk-project-trust-notify-original.mjs");
const gpa = std.testing.allocator;
const Fixture = struct {
    environment: std.process.Environ.Map,
    engine: *em.Engine,
    fn init(self: *Fixture) !void {
        self.environment = .init(gpa);
        errdefer self.environment.deinit();
        self.engine = try em.Engine.init(gpa, .{
            .host_await_timeout_ms = 10000, .interrupt_budget = 8_000_000,
        });
        errdefer self.engine.deinit();
        try @import("extensions/native_sdk_application_bootstrap.zig").installPlatform(
            self.engine, std.testing.io, &self.environment, &.{"actual-chalk-project-trust-color-control"});
    }
    fn deinit(self: *Fixture) void {
        self.engine.deinit();
        self.environment.deinit();
    }
};
fn expose(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn evaluate(s: *v.Scope, source: []const u8) !c.JSValue {
    return v.own(s, try s.engine.eval(source, "chalk-foreground-control.js", c.JS_EVAL_TYPE_GLOBAL));
}
fn originalDefault(s: *v.Scope) !c.JSValue {
    const process_module = s.engine.native_module_values.get("node:process") orelse
        return error.RequiredActualChalkProcess;
    const os_module = s.engine.native_module_values.get("node:os") orelse
        return error.RequiredActualChalkOs;
    const process = try v.get(s, process_module, "default");
    const os = try v.get(s, os_module, "default");
    const colors = try v.own(s, try @import("extensions/native_sdk_chalk_supports_color.zig").create(
        s.engine, process, os));
    const factory = try evaluate(s, source_fixture);
    return v.duplicate(s, try v.call(s, factory, c.pi_js_undefined(), &.{colors}));
}
fn prepare(s: *v.Scope, source: bool) !void {
    const owner = try v.own(s, if (source) try h.expression(s.engine, originalDefault, .{}) else
        try chalk.createDefault(s.engine));
    try expose(s, "__ccRoot", owner);
    try expose(s, "__ccHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
    try expose(s, "__ccNotifyFactory", try evaluate(s, notify_fixture));
    _ = try evaluate(s, yellow_regression);
    _ = try evaluate(s, observer);
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
    try prepare(&s, source);
    const observed = try evaluate(&s, "JSON.stringify(ccCase('" ++ name ++ "',__ccRoot))");
    try std.testing.expect(c.JS_IsString(observed));
    try clean(fixture.engine);
    return fixture.engine.toString(observed);
}
fn both(comptime name: []const u8) !void {
    const expected = try capture(name, true);
    defer gpa.free(expected);
    const actual = try capture(name, false);
    defer gpa.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

test "native project trust Chalk colors preserved 86 observation yellow corpus matches complete original" { try both("yellow-regression"); }

test "native project trust Chalk colors red ANSI and no color bytes cover all levels and line endings" { try both("red-matrix"); }

test "native project trust Chalk colors cyan ANSI and no color bytes cover all levels and line endings" { try both("cyan-matrix"); }

test "native project trust Chalk colors mixed foreground chains preserve reopen order and shared closers" { try both("mixed-chains"); }

test "native project trust Chalk colors lazy foreground getter builder and cache descriptors match source" { try both("descriptors"); }

test "native project trust Chalk colors style caches are distinct immutable and per instance" { try both("cache-isolation"); }

test "native project trust Chalk colors mixed builders share live root level writes" { try both("live-levels"); }

test "native project trust Chalk colors painting reads symbol level while public level getter stays live" { try both("public-level"); }

test "native project trust Chalk colors red and cyan preserve zero single two and rest argument forms" { try both("builder-call-forms"); }

test "native project trust Chalk colors implicit and joined conversion hints match all enabled levels" { try both("coercion-hints"); }

test "native project trust Chalk colors input conversion preserves original thrown identity when disabled" { try both("coercion-throw"); }

test "native project trust Chalk colors enabled and disabled builders reject Symbol conversion" { try both("symbol-input"); }

test "native project trust Chalk colors input conversion can reenter another genuine foreground builder" { try both("coercion-reentry"); }

test "native project trust Chalk colors borrowed lazy getter preserves parent and generator read order" { try both("getter-order"); }

test "native project trust Chalk colors failed parent getter publishes no style cache" { try both("getter-throw"); }

test "native project trust Chalk colors same style getter reentry preserves inner cache and outer error" { try both("getter-same-reentry"); }

test "native project trust Chalk colors cross style getter reentry keeps independent cached builders" { try both("getter-cross-reentry"); }

test "native project trust Chalk colors proxy cache definition preserves original thrown identity" { try both("cache-throw"); }

test "native project trust Chalk colors borrowed getter keeps real generator and nonconstructor shape" { try both("borrowed-getter"); }

test "native project trust Chalk colors null and primitive style receivers reject without cache" { try both("primitive-receiver"); }

test "native project trust Chalk colors new builders capture the live generator exactly once" { try both("generator-capture"); }

test "native project trust Chalk colors symbol level getter and numeric conversion stay live" { try both("symbol-level"); }

test "native project trust Chalk colors symbol level error follows input conversion and remains original" { try both("symbol-level-throw"); }

test "native project trust Chalk colors embedded ANSI and CRLF use original live String method order" { try both("string-method-order"); }

test "native project trust Chalk colors live String method throws remain original for both styles" { try both("string-method-throw"); }

test "native project trust Chalk colors live String method can reenter another actual color" { try both("string-method-reentry"); }

test "native project trust Chalk colors real private native DATA thrown during color conversion remains ordinary" { try both("native-data"); }

test "native project trust Chalk colors exact original project trust notify selects red yellow and cyan" { try both("notify-colors"); }

test "native project trust Chalk colors exact original notify preserves mode style and console reference order" { try both("notify-order"); }

test "native project trust Chalk colors default owner remains the same genuine cached callable" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine };
    defer s.deinit();
    const first = try v.own(&s, try chalk.createDefault(fixture.engine));
    try expose(&s, "__ccFirst", first);
    _ = try evaluate(&s,
        \\__ccFirst.level=1;
        \\globalThis.__ccRed=__ccFirst.red;globalThis.__ccYellow=__ccFirst.yellow;
        \\globalThis.__ccCyan=__ccFirst.cyan;__ccCyan.level=0;
    );
    const second = try v.own(&s, try chalk.createDefault(fixture.engine));
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, first, second));
    try expose(&s, "__ccSecond", second);
    const observed = try evaluate(&s,
        \\__ccSecond.red===__ccRed&&__ccSecond.yellow===__ccYellow&&
        \\__ccSecond.cyan===__ccCyan&&__ccSecond.red("x")==="x"&&
        \\__ccSecond.cyan("x")==="x"&&__ccSecond.level===0
    );
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, observed,
        c.JS_NewBool(fixture.engine.context, true)));
    try clean(fixture.engine);
}
fn fatal(comptime style: []const u8, comptime phase: []const u8) !void {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine };
    defer s.deinit();
    try prepare(&s, false);
    const record = try v.get(&s, try v.global(&s, "__ccHooks"), "record");
    try std.testing.expectError(error.JavaScriptException,
        evaluate(&s, "ccFreshFatal('" ++ style ++ "','" ++ phase ++ "');"));
    try retirement.verifyRecordedActualNativeFatal(fixture.engine, record);
    try retirement.verifyNoVisits(record, .{ 1, 2 });
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}
test "native project trust Chalk colors red getter fresh fatal bypasses guest catch" { try fatal("red", "getter"); }
test "native project trust Chalk colors cyan getter fresh fatal bypasses guest catch" { try fatal("cyan", "getter"); }
test "native project trust Chalk colors red conversion fresh fatal bypasses guest catch" { try fatal("red", "conversion"); }
test "native project trust Chalk colors cyan conversion fresh fatal bypasses guest catch" { try fatal("cyan", "conversion"); }
