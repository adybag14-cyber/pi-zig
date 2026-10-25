//! Differential controls use the original retained Node source in the same
//! linked VM. Input functions are observable test seams, never public builtin
//! substitutes; the Module constructor itself is the genuine native owner.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const core = @import("extensions/native_node_commonjs_module_core.zig");
const functions = @import("extensions/native_node_module_callable.zig");
const wrapping = @import("extensions/native_node_commonjs_wrap_load.zig");
const Fixture = struct {
    engine: *a.v.em.Engine,
    environment: std.process.Environ.Map,
    module: ?c.JSValue = null,
    fn init(self: *Fixture) !void {
        self.* = .{ .engine = undefined, .environment = .init(std.testing.allocator) };
        errdefer self.environment.deinit();
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{});
        errdefer self.engine.deinit();
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine, std.testing.io,
            &self.environment, &.{"actual-wrap-load-controls"});
        try @import("extensions/node_path.zig").install(self.engine, std.testing.io);
        try @import("extensions/node_url.zig").install(self.engine);
        const process = (try self.engine.requireBuiltin("node:process")) orelse return error.ActualWrapProcessRequired;
        defer self.engine.freeValue(process);
        try @import("extensions/node_fs.zig").installWithStreams(self.engine, std.testing.io, process);
        self.module = try core.create(self.engine);
        errdefer { self.engine.freeValue(self.module.?); self.module = null; }
        _ = try a.expression(self.engine, expose, .{self.module.?});
        try self.run(@embedFile("extensions/fixtures/node-commonjs-wrap-load-original.js"));
        try self.run(@embedFile("extensions/fixtures/node-commonjs-wrap-load-controls.js"));
    }
    fn expose(s: *a.Scope, module: c.JSValue) !c.JSValue {
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const factory = try s.own(try functions.create(s.engine, "makeNativeModuleLoad", 2, false, nativeFactory, &.{module}));
        try s.define(global, "makeNativeModuleLoad", factory, c.JS_PROP_C_W_E);
        try s.define(global, "actualWrapModule", module, c.JS_PROP_C_W_E);
        return c.pi_js_undefined();
    }
    fn nativeFactory(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue,
        roots: []const c.JSValue) !c.JSValue
    {
        return wrapping.create(engine, .{ .module_constructor = roots[0],
            .debug_with_timer = a.arg(args, 0), .tracing_channel = a.arg(args, 1) });
    }
    fn run(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "native-wrap-load-controls.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(result);
    }
    fn deinit(self: *Fixture) void {
        if (self.module) |value| self.engine.freeValue(value);
        self.engine.deinit();
        self.environment.deinit();
    }
};
fn compare(comptime index: usize) !void {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.run(std.fmt.comptimePrint("if(runWrapLoadCase({d})!==true)throw Error('missing comparison');", .{index}));
}

test "native actual CommonJS wrap load preserves ordinary declaration metadata" { try compare(0); }
test "native actual CommonJS wrap load dispatches unsubscribed calls with exact receiver arguments and return identity" { try compare(1); }
test "native actual CommonJS wrap load dispatches subscribed calls with context descriptors and early callee lookup" { try compare(2); }
test "native actual CommonJS wrap load preserves independent string-hint label conversions in order" { try compare(3); }
test "native actual CommonJS wrap load accepts null optional parent" { try compare(4); }
test "native actual CommonJS wrap load keeps startTimer outside try finally" { try compare(5); }
test "native actual CommonJS wrap load runs finally after subscribers getter throws" { try compare(6); }
test "native actual CommonJS wrap load runs finally after Module load getter throws" { try compare(7); }
test "native actual CommonJS wrap load preserves loader throw identity through successful finally" { try compare(8); }
test "native actual CommonJS wrap load finally throw replaces successful return" { try compare(9); }
test "native actual CommonJS wrap load finally throw replaces earlier ordinary throw" { try compare(10); }
test "native actual CommonJS wrap load runs finally after traceSync getter throws" { try compare(11); }
test "native actual CommonJS wrap load runs finally after traceSync call throws" { try compare(12); }
test "native actual CommonJS wrap load uses timer callbacks updated during start and on subsequent calls" { try compare(13); }
test "native actual CommonJS wrap load uses timer callback updated during loader execution" { try compare(14); }
test "native actual CommonJS wrap load retries failed lazy channel initialization" { try compare(15); }
test "native actual CommonJS wrap load preserves successful outer lazy assignment after reentry" { try compare(16); }
test "native actual CommonJS wrap load caches undefined lazy channel value" { try compare(17); }
test "native actual CommonJS wrap load defines traced context own writable enumerable configurable fields" { try compare(18); }
test "native actual CommonJS wrap load preserves ordinary construction for primitive loader result" { try compare(19); }
test "native actual CommonJS wrap load observes timer initialization temporal dead zone" { try compare(20); }
test "native actual CommonJS wrap load observes partial timer destructuring temporal dead zone" { try compare(21); }
test "native actual CommonJS wrap load reads live subscriber state for each invocation" { try compare(22); }
test "native actual CommonJS wrap load throws for noncallable start without running finally" { try compare(23); }
test "native actual CommonJS wrap load runs finally after parent filename getter throws" { try compare(24); }
test "native actual CommonJS wrap load unsubscribed path skips trace and filename getters" { try compare(25); }
test "native actual CommonJS wrap load uses authenticated Module lexical identity despite mutable Module property" { try compare(26); }
test "native actual CommonJS wrap load rejects Symbol template interpolation before channel and timer calls" { try compare(27); }
test "native actual CommonJS wrap load keeps independent frames through recursive loader execution" { try compare(28); }
test "native actual CommonJS wrap load accepts truthy nonboolean subscriber state" { try compare(29); }
test "native actual CommonJS wrap load accepts undefined optional parent" { try compare(30); }
test "native actual CommonJS wrap load preserves coercion failure before lazy channel acquisition" { try compare(31); }
