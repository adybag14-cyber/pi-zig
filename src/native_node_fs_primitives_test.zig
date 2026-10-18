//! Genuine FS binding primitives: real contexts, typed-array owners and SafeSet.
//! These declarations do not execute during the install-only build target.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("extensions/engine.zig");
const c = em.c;
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_node_operation_scope.zig").Scope;
const realm = @import("extensions/native_node_internal_realm.zig");
const stats = @import("extensions/native_node_fs_stat_values.zig");
const stat = @import("extensions/native_file_stat.zig");
const collections = @import("extensions/native_node_fs_collections.zig");
const gpa = std.testing.allocator;
fn publish(engine: *em.Engine, name: [:0]const u8, value: c.JSValue) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context));
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, name, c.JS_DupValue(engine.context, value)) < 0)
        return error.ActualFsPrimitiveControlPublicationFailed;
}
fn evaluate(engine: *em.Engine, source: []const u8) !void {
    const value = try engine.eval(source, "native-fs-primitive-observer.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
}
fn check(engine: *em.Engine, source: []const u8) !void {
    const value = try engine.eval(source, "native-fs-primitive-observer.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_ToBool(engine.context, value) == 1);
}
fn clearCaptured(engine: *em.Engine) void {
    if (engine.captured_exception) |value| {
        engine.captured_exception = null;
        engine.freeValue(value);
    }
}
fn execBody(s: *Scope, holder: c.JSValue, expression: c.JSValue, input: c.JSValue) !c.JSValue {
    const value = try realm.regexpExec(s, holder, expression, input);
    return c.JS_DupValue(s.engine.context, value);
}
fn actualExec(engine: *em.Engine, holder: c.JSValue, expression: c.JSValue, input: c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(execBody(&s, holder, expression, input));
}
fn sample() stat.Stat {
    return .{
        .dev = 11, .ino = 18, .size = 19, .mode = 12, .nlink = 13,
        .uid = 14, .gid = 15, .rdev = 16, .blksize = 17, .blocks = 20,
        .atime_ns = 2_000_000_003, .mtime_ns = 4_000_000_005,
        .ctime_ns = 6_000_000_007, .birthtime_ns = 8_000_000_009,
    };
}
test "native fs primitives internal realm keeps actual context and cached owner identities" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    const main_context = engine.context;
    const main_opaque = c.JS_GetContextOpaque(main_context);
    const owner = try realm.acquire(engine);
    defer engine.freeValue(owner);
    const again = try realm.acquire(engine);
    defer engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, owner, again));
    try std.testing.expect(engine.context == main_context);
    try std.testing.expect(c.JS_GetContextOpaque(engine.context) == main_opaque);
    try publish(engine, "internalGlobal", realm.global(owner));
    try check(engine, "internalGlobal!==globalThis && internalGlobal.RegExp!==RegExp && internalGlobal.RegExp.prototype.exec!==RegExp.prototype.exec");
}
test "native fs primitives internal regexp ignores main exec mutation and performs input coercion" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    const owner = try realm.acquire(engine);
    defer engine.freeValue(owner);
    const expression = try engine.eval("/^([a-z]+):/", "native-fs-regexp.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(expression);
    try evaluate(engine,
        \\globalThis.coercions = [];
        \\RegExp.prototype.exec = function() { throw new Error('main exec must not run'); };
    );
    const input = try engine.eval("({[Symbol.toPrimitive](hint){coercions.push(hint);return 'drive:/pkg';}})", "native-fs-input.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(input);
    const result = try actualExec(engine, owner, expression, input);
    defer engine.freeValue(result);
    try publish(engine, "actualMatch", result);
    try check(engine, "actualMatch[0]==='drive:' && actualMatch[1]==='drive' && JSON.stringify(coercions)==='[\"string\"]'");
}
test "native fs primitives internal regexp preserves shared ordinary throw identity" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    const owner = try realm.acquire(engine);
    defer engine.freeValue(owner);
    const expression = try engine.eval("/x/", "native-fs-regexp.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(expression);
    const input = try engine.eval("globalThis.reason={ordinary:1};({toString(){throw reason;}})", "native-fs-input.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(input);
    const attempted = actualExec(engine, owner, expression, input);
    if (attempted) |unexpected| {
        engine.freeValue(unexpected);
        return error.ExpectedActualInternalRealmThrow;
    } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
    const reason = engine.captured_exception orelse return error.ExpectedActualInternalRealmReason;
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try publish(engine, "actualReason", reason);
    clearCaptured(engine);
    try check(engine, "actualReason===reason");
}
test "native fs primitives numeric stats expose ten fields and eight time parts in shared owner" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    const owner = try stats.acquire(engine);
    defer engine.freeValue(owner);
    const again = try stats.acquire(engine);
    defer engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, owner, again));
    const record = try stats.record(engine, owner, false, sample(), false);
    defer engine.freeValue(record);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, record, stats.numeric(owner)));
    try publish(engine, "actualStats", record);
    try check(engine,
        \\actualStats instanceof Float64Array && actualStats.length===36 &&
        \\JSON.stringify(Array.from(actualStats.slice(0,18)))==='[11,12,13,14,15,16,17,18,19,20,2,3,4,5,6,7,8,9]' &&
        \\actualStats.slice(18).every(value=>value===0)
    );
}
test "native fs primitives BigInt stats keep precision and leave numeric stats unchanged" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    const owner = try stats.acquire(engine);
    defer engine.freeValue(owner);
    const number_record = try stats.record(engine, owner, false, sample(), false);
    defer engine.freeValue(number_record);
    var large = sample();
    large.ino = std.math.maxInt(u64);
    large.size = 9_007_199_254_740_993;
    large.mtime_ns = -1;
    const big_record = try stats.record(engine, owner, true, large, false);
    defer engine.freeValue(big_record);
    try publish(engine, "numberStats", number_record);
    try publish(engine, "bigStats", big_record);
    const expected_seconds = if (builtin.os.tag == .windows) "4294967295n" else "-1n";
    const source = try std.fmt.allocPrint(gpa,
        "bigStats instanceof BigInt64Array && bigStats.length===36 && bigStats[7]===-1n && bigStats[8]===9007199254740993n && bigStats[12]==={s} && bigStats[13]===999999999n && numberStats[7]===18 && numberStats[8]===19 && numberStats[12]===4",
        .{expected_seconds});
    defer gpa.free(source);
    try check(engine, source);
}
test "native fs primitives second stat record starts at eighteen and survives first updates" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    const owner = try stats.acquire(engine);
    defer engine.freeValue(owner);
    var second = sample();
    second.size = 37;
    const first_result = try stats.record(engine, owner, false, second, true);
    defer engine.freeValue(first_result);
    const second_result = try stats.record(engine, owner, false, sample(), false);
    defer engine.freeValue(second_result);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first_result, second_result));
    try publish(engine, "actualStats", first_result);
    try check(engine, "actualStats[8]===19 && actualStats[26]===37 && actualStats[28]===2 && actualStats[35]===9");
}
test "native fs primitives binding arrays use actual intrinsics after global constructor replacement" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    try evaluate(engine,
        \\globalThis.realFloat64 = Float64Array;
        \\globalThis.realBigInt64 = BigInt64Array;
        \\Object.defineProperty(globalThis,'Float64Array',{get(){throw new Error('guest numeric constructor');}});
        \\Object.defineProperty(globalThis,'BigInt64Array',{get(){throw new Error('guest bigint constructor');}});
    );
    const owner = try stats.acquire(engine);
    defer engine.freeValue(owner);
    try publish(engine, "numberStats", stats.numeric(owner));
    try publish(engine, "bigStats", stats.bigint(owner));
    try check(engine, "numberStats instanceof realFloat64 && bigStats instanceof realBigInt64");
}
test "native fs primitives SafeSet keeps genuine membership and frozen iterator owners" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    const safe = try collections.acquireSafeSet(engine);
    defer engine.freeValue(safe);
    try publish(engine, "ActualSafeSet", safe);
    try check(engine,
        \\(() => {
        \\ const set = new ActualSafeSet(['a','b']);
        \\ const iterator = set.values();
        \\ return set.has('a') && !set.has('c') && set.size===2 &&
        \\  Object.isFrozen(ActualSafeSet) && Object.isFrozen(ActualSafeSet.prototype) &&
        \\  Object.getPrototypeOf(ActualSafeSet.prototype)===null &&
        \\  iterator[Symbol.iterator]()===iterator &&
        \\  Object.isFrozen(Object.getPrototypeOf(iterator)) &&
        \\  Object.getPrototypeOf(Object.getPrototypeOf(iterator))===null &&
        \\  iterator.next().value==='a' && iterator.next().value==='b' && iterator.next().done;
        \\})()
    );
}
fn reenterSafeSet(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return collections.acquireSafeSet(engine);
}
test "native fs primitives SafeSet reentry returns the actual completed cache owner" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    const reenter = try @import("extensions/native_node_module_callable.zig").create(engine, "reenterSafeSet", 0, true, reenterSafeSet, &.{});
    defer engine.freeValue(reenter);
    try publish(engine, "reenterSafeSet", reenter);
    try evaluate(engine,
        \\globalThis.reenterOnce = true;
        \\globalThis.realValues = Set.prototype.values;
        \\Set.prototype.values = function values() {
        \\ if (reenterOnce) { reenterOnce=false;globalThis.innerSafeSet=reenterSafeSet(); }
        \\ return Reflect.apply(realValues,this,[]);
        \\};
    );
    const outer = try collections.acquireSafeSet(engine);
    defer engine.freeValue(outer);
    try publish(engine, "outerSafeSet", outer);
    try check(engine, "outerSafeSet===innerSafeSet");
    const cached = try collections.acquireSafeSet(engine);
    defer engine.freeValue(cached);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, outer, cached));
}
test "native fs primitives failed SafeSet iterator probe leaves no owner and permits retry" {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    try evaluate(engine,
        \\globalThis.savedValues = Set.prototype.values;
        \\Set.prototype.values = function values() {return 7;};
    );
    const attempted = collections.acquireSafeSet(engine);
    if (attempted) |unexpected| {
        engine.freeValue(unexpected);
        return error.ExpectedActualSafeSetProbeFailure;
    } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
    try std.testing.expect(!engine.native_module_values.contains("\x00native.fs.SafeSet"));
    const reason = engine.captured_exception orelse return error.ExpectedActualSafeSetProbeReason;
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    clearCaptured(engine);
    try evaluate(engine, "Set.prototype.values=savedValues");
    const retried = try collections.acquireSafeSet(engine);
    defer engine.freeValue(retried);
    try std.testing.expect(engine.native_module_values.contains("\x00native.fs.SafeSet"));
}
