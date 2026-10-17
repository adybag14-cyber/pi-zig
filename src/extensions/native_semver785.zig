//! Private SDK six-binding strict/default semver7.8.5 supplier.
//! No SemVer/Range public class, loose/includePrerelease API, or JS host port.
const std = @import("std");
const em = @import("engine.zig");
const Scope = @import("native_semver785_scope.zig").Scope;
const ops = @import("native_semver785_ops.zig");
const functions = @import("native_node_function.zig");
const v = @import("native_semver785_version.zig");
const ranges = @import("native_semver785_range.zig");
const c = em.c;
const Method = enum { valid, validRange, gt, rcompare, satisfies, maxSatisfying };
pub fn create(engine: *em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    var boundary: Scope = .{ .engine = engine };
    const result = createInner(engine) catch |err| {
        const failure = if (c.JS_HasException(engine.context)) c.JS_Throw(engine.context, c.JS_GetException(engine.context))
            else if (err == error.OutOfMemory) engine.throwNativeOutOfMemoryFatal()
            else engine.throwCaptured();
        _ = engine.checked(engine.leaveNativeInvocation(&invocation, failure)) catch return err;
        return err;
    };
    const final = boundary.complete(result, engine.native_allocation_generation) catch |err| {
        _ = engine.checked(engine.leaveNativeInvocation(&invocation, engine.throwCaptured())) catch return err;
        return err;
    };
    return engine.checked(engine.leaveNativeInvocation(&invocation, final));
}
fn createInner(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    errdefer |err| scope.failed(err);
    const context = try scope.plain();
    try ops.put(&scope, context, "regex", try scope.own(try @import("native_semver785_regex.zig").create(engine)));
    try ops.put(&scope, context, "cache", try scope.builtin("Map", &.{}));
    const result = try scope.object();
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var boundary: Scope = .{ .engine = host };
                const returned = try invoke(host, method, args, roots[0]);
                return boundary.complete(returned, host.native_allocation_generation);
            }
        };
        try ops.put(&scope, result, field.name, try scope.own(try functions.createArrow(engine, field.name, if (method == .valid or method == .validRange) 2 else 3, Adapter.call, &.{context})));
    }
    return c.JS_DupValue(engine.context, result);
}
fn arg(args: []const c.JSValue, position: usize) c.JSValue {
    return if (args.len > position) args[position] else c.pi_js_undefined();
}
fn caught(engine: *em.Engine, err: anyerror) !void {
    if (err == error.OutOfMemory) return err;
    if (err != error.JavaScriptException) return err;
    // Actual pending/current invocation events have priority. A captured
    // diagnostic or an older private tag alone is not a new allocation event.
    try engine.checkNativeEntry();
    if (engine.captured_exception) |reason| {
        engine.captured_exception = null;
        var cleanup: Scope = .{ .engine = engine };
        try cleanup.retire(reason);
    } else {
        return err;
    }
}
fn invoke(engine: *em.Engine, method: Method, args: []const c.JSValue, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    errdefer |err| scope.failed(err);
    const options = arg(args, if (method == .valid or method == .validRange) 1 else 2);
    if (scope.truthy(options)) return v.typeError(&scope, &.{try scope.text("Native semver 7.8.5 PackageManager binding supports default options only")});
    const regex = try scope.get(context, "regex");
    switch (method) {
        .valid => {
            const version = v.create(&scope, regex, arg(args, 0)) catch |err| {
                try caught(engine, err);
                return c.pi_js_null();
            };
            return c.JS_DupValue(engine.context, try scope.get(version, "version"));
        },
        .validRange => {
            const formatted = validRange(&scope, context, arg(args, 0)) catch |err| {
                try caught(engine, err);
                return c.pi_js_null();
            };
            return c.JS_DupValue(engine.context, formatted);
        },
        .gt, .rcompare => {
            // rcompare delegates to compare(b,a): constructor failures and
            // live string methods must retain that reversed evaluation order.
            const first = try v.create(&scope, regex, arg(args, if (method == .rcompare) 1 else 0));
            const second = try v.create(&scope, regex, arg(args, if (method == .rcompare) 0 else 1));
            const compared = try v.compare(&scope, regex, first, second);
            return if (method == .gt) c.pi_js_bool(engine.context, @intFromBool(compared > 0)) else c.JS_NewInt32(engine.context, compared);
        },
        .satisfies, .maxSatisfying => {
            const range = ranges.create(&scope, context, arg(args, 1)) catch |err| {
                try caught(engine, err);
                return if (method == .satisfies) c.pi_js_bool(engine.context, 0) else c.pi_js_null();
            };
            if (method == .satisfies) return c.pi_js_bool(engine.context, @intFromBool(try testInput(&scope, context, range, arg(args, 0))));
            const owner = try scope.plain();
            try ops.put(&scope, owner, "context", context);
            try ops.put(&scope, owner, "range", range);
            try ops.put(&scope, owner, "max", c.pi_js_null());
            try ops.put(&scope, owner, "maxSV", c.pi_js_null());
            const versions = arg(args, 0);
            const for_each = try scope.get(versions, "forEach");
            const callback = try scope.own(try functions.createArrow(engine, "", 1, maximum, &.{owner}));
            _ = try scope.call(for_each, versions, &.{callback});
            return c.JS_DupValue(engine.context, try scope.get(owner, "max"));
        },
    }
}
fn validRange(scope: *Scope, context: c.JSValue, input: c.JSValue) !c.JSValue {
    const range = try ranges.create(scope, context, input);
    const formatted = try ranges.formatted(scope, range);
    return if (scope.truthy(formatted)) formatted else try scope.text("*");
}
fn testInput(scope: *Scope, context: c.JSValue, range: c.JSValue, input: c.JSValue) !bool {
    if (!scope.truthy(input)) return false;
    var version = input;
    if (c.JS_IsString(input)) {
        version = v.create(scope, try scope.get(context, "regex"), input) catch |err| {
            try caught(scope.engine, err);
            return false;
        };
    }
    return ranges.test(scope, context, range, version, c.JS_IsString(input));
}
fn maximum(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var boundary: Scope = .{ .engine = engine };
    const returned = try maximumInner(engine, args, roots);
    return boundary.complete(returned, engine.native_allocation_generation);
}
fn maximumInner(engine: *em.Engine, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    errdefer |err| scope.failed(err);
    const owner = roots[0];
    const context = try scope.get(owner, "context");
    const candidate = arg(args, 0);
    if (!try testInput(&scope, context, try scope.get(owner, "range"), candidate)) return c.pi_js_undefined();
    const current = try scope.get(owner, "max");
    var replace = !scope.truthy(current);
    const regex = try scope.get(context, "regex");
    if (!replace) {
        const previous = try scope.get(owner, "maxSV");
        // SemVer.compare(string) returns immediately for the exact formatted
        // string before constructing another version. Equal builds retain the
        // first original candidate rather than returning a normalized copy.
        if (!c.JS_IsString(candidate) or !scope.equal(candidate, try scope.get(previous, "version"))) replace = try v.compare(&scope, regex, previous, try v.create(&scope, regex, candidate)) == -1;
    }
    if (replace) {
        try ops.put(&scope, owner, "max", candidate);
        try ops.put(&scope, owner, "maxSV", try v.create(&scope, regex, candidate));
    }
    return c.pi_js_undefined();
}
