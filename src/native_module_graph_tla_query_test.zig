//! Prepared actual-VM controls, uncompiled/unrun. No Node/link-only caller claim.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
fn compile(engine: *em.Engine, source: []const u8, filename: [:0]const u8) !c.JSValue {
    return engine.eval(source, filename, c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
}
fn query(engine: *em.Engine, module: c.JSValue, expected: c_int) !void {
    var result: c_int = 99;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiModuleGraphHasTLA(engine.context, module, &result));
    try std.testing.expectEqual(expected, result);
    try std.testing.expect(!c.JS_HasException(engine.context));
}
fn check(engine: *em.Engine, source: []const u8) !void {
    const value = try engine.eval(source, "module-query-observer.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_ToBool(engine.context, value) == 1);
}
const Definition = struct { name: []const u8, source: []const u8 };
const Sources = struct {
    definitions: []const Definition,
    loads: usize = 0,
    fn normalize(_: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, name: []const u8) ![]u8 { return allocator.dupe(u8, name); }
    fn load(data: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8) ![]u8 {
        const self: *Sources = @ptrCast(@alignCast(data.?));
        self.loads += 1;
        for (self.definitions) |definition| if (std.mem.eql(u8, definition.name, name)) return allocator.dupe(u8, definition.source);
        return error.OwnedQueryFixtureMissing;
    }
    fn install(self: *Sources, engine: *em.Engine) void { engine.setSourceLoader(.{ .context = self, .normalize = normalize, .load = load }); }
};
test "module graph TLA query is readonly before genuine synchronous body evaluation and namespace" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const module = try compile(engine, "globalThis.queryBody=41;export let value=43;export function bump(){value++}", "C:/query/sync.mjs");
    defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
    var before: c.JSMemoryUsage = undefined;
    c.JS_ComputeMemoryUsage(engine.runtime, &before);
    try query(engine, module, 0);
    c.JS_RunGC(engine.runtime);
    try query(engine, module, 0);
    try check(engine, "globalThis.queryBody===undefined");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    var after: c.JSMemoryUsage = undefined;
    c.JS_ComputeMemoryUsage(engine.runtime, &after);
    // Scratch is freed; no module object/value or retained query record exists.
    try std.testing.expectEqual(before.malloc_count, after.malloc_count);
    const evaluated = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, module));
    defer engine.freeValue(evaluated);
    try std.testing.expect(!c.JS_IsException(evaluated));
    try check(engine, "globalThis.queryBody===41");
    const ns = try engine.checked(c.JS_GetModuleNamespace(engine.context, c.pi_js_module(module)));
    defer engine.freeValue(ns);
    const value = try engine.checked(c.JS_GetPropertyStr(engine.context, ns, "value"));
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, value, c.JS_NewInt32(engine.context, 43)));
    try query(engine, module, 0); // Evaluation status does not change syntax metadata.
}
test "module graph TLA query distinguishes syntactic unreachable await from nested async await" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const tla = try compile(engine, "globalThis.unreachableBody=true;if(false)await 0;export const x=1", "C:/query/unreachable.mjs");
    defer engine.freeValue(tla);
    const nested = try compile(engine, "globalThis.nestedBody=true;export async function f(){await 0}", "C:/query/nested.mjs");
    defer engine.freeValue(nested);
    try query(engine, tla, 1);
    try query(engine, nested, 0);
    try check(engine, "!globalThis.unreachableBody&&!globalThis.nestedBody");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
test "module graph TLA query follows actual diamond static dependencies once without loader or body calls" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var sources: Sources = .{ .definitions = &.{
        .{ .name = "C:/query/left.mjs", .source = "import 'C:/query/leaf.mjs';globalThis.leftBody=true;" },
        .{ .name = "C:/query/right.mjs", .source = "import 'C:/query/leaf.mjs';globalThis.rightBody=true;" },
        .{ .name = "C:/query/leaf.mjs", .source = "globalThis.leafBody=true;if(false)await 0;" },
    } };
    sources.install(engine);
    const module = try compile(engine, "import 'C:/query/left.mjs';import 'C:/query/right.mjs';globalThis.rootBody=true;", "C:/query/diamond.mjs");
    defer engine.freeValue(module);
    const loads = sources.loads;
    try query(engine, module, 1);
    c.JS_RunGC(engine.runtime);
    try query(engine, module, 1);
    try std.testing.expectEqual(loads, sources.loads);
    try check(engine, "!globalThis.rootBody&&!globalThis.leftBody&&!globalThis.rightBody&&!globalThis.leafBody");
}
fn cycle(tla: bool) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var sources: Sources = .{ .definitions = &.{.{ .name = "C:/query/cycle-b.mjs", .source = if (tla) "import 'C:/query/cycle-a.mjs';if(false)await 0;globalThis.cycleBody=true;" else "import 'C:/query/cycle-a.mjs';globalThis.cycleBody=true;" }} };
    sources.install(engine);
    const module = try compile(engine, "import 'C:/query/cycle-b.mjs';globalThis.cycleBody=true;", "C:/query/cycle-a.mjs");
    defer engine.freeValue(module);
    const loads = sources.loads;
    try query(engine, module, if (tla) 1 else 0);
    try std.testing.expectEqual(loads, sources.loads);
    try check(engine, "!globalThis.cycleBody");
}
test "module graph TLA query terminates on a genuine synchronous cycle" { try cycle(false); }
test "module graph TLA query finds unreachable TLA in a genuine cycle" { try cycle(true); }
test "module graph TLA query excludes dynamic imports and unrelated context modules" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const unrelated = try compile(engine, "await 0;", "C:/query/unrelated.mjs");
    defer engine.freeValue(unrelated);
    var sources: Sources = .{ .definitions = &.{} };
    sources.install(engine);
    const module = try compile(engine, "export function later(){return import('C:/query/not-loaded.mjs')}", "C:/query/dynamic.mjs");
    defer engine.freeValue(module);
    try query(engine, module, 0);
    try std.testing.expectEqual(@as(usize, 0), sources.loads);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
const SerializedResolution = struct {
    fail_second: bool = false,
    normalizations: usize = 0,
    loads: usize = 0,
    fn normalize(data: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, name: []const u8) ![]u8 {
        const self: *SerializedResolution = @ptrCast(@alignCast(data.?));
        self.normalizations += 1;
        if (self.fail_second and std.mem.eql(u8, name, "C:/query/missing.mjs")) return error.OwnedQuerySecondNormalizationFailure;
        return allocator.dupe(u8, name);
    }
    fn load(data: ?*anyopaque, _: std.mem.Allocator, _: []const u8) ![]u8 {
        const self: *SerializedResolution = @ptrCast(@alignCast(data.?));
        self.loads += 1;
        return error.UnexpectedSerializedQueryLoad;
    }
    fn install(self: *SerializedResolution, engine: *em.Engine) void { engine.setSourceLoader(.{ .context = self, .normalize = normalize, .load = load }); }
};
test "module graph TLA query rejects actual serialized unresolved and partial graphs even after root TLA" {
    const original = try em.Engine.init(std.testing.allocator, .{});
    defer original.deinit();
    var all: Sources = .{ .definitions = &.{
        .{ .name = "C:/query/first.mjs", .source = "export const a=1" },
        .{ .name = "C:/query/missing.mjs", .source = "export const b=2" },
    } };
    all.install(original);
    const compiled = try compile(original, "import 'C:/query/first.mjs';import 'C:/query/missing.mjs';if(false)await 0;", "C:/query/serialized.mjs");
    defer original.freeValue(compiled);
    var size: usize = 0;
    const bytes = c.JS_WriteObject(original.context, &size, compiled, c.JS_WRITE_OBJ_BYTECODE);
    if (bytes == null) return error.BytecodeSerializationFailure;
    defer c.js_free(original.context, bytes);
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    // Reading bytecode resolves request names, but a cache hit does not resolve
    // the returned module's graph. Real native definitions let reading finish
    // without loading or initializing either child; all remain unresolved.
    if (c.JS_NewCModule(engine.context, "C:/query/first.mjs", nativeInit) == null) return error.NativeModuleSetupFailure;
    if (c.JS_NewCModule(engine.context, "C:/query/missing.mjs", nativeInit) == null) return error.NativeModuleSetupFailure;
    var resolution: SerializedResolution = .{};
    resolution.install(engine);
    const module = try engine.checked(c.JS_ReadObject(engine.context, bytes, size, c.JS_READ_OBJ_BYTECODE));
    defer engine.freeValue(module);
    try std.testing.expectEqual(@as(usize, 2), resolution.normalizations);
    try std.testing.expectEqual(@as(usize, 0), resolution.loads);
    var output: c_int = 99;
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiModuleGraphHasTLA(engine.context, module, &output));
    const unresolved = c.JS_GetException(engine.context);
    defer engine.freeValue(unresolved);
    try std.testing.expectEqual(@as(c_int, 99), output);
    try std.testing.expectEqual(@as(usize, 2), resolution.normalizations);
    // Resolve marks the parent, resolves the first child, then fails before
    // looking up the second. Its normal unresolved-module sweep removes that
    // child, leaving a genuine partial edge in the still-owned parent. No
    // independent child token is retained across that sweep.
    resolution.fail_second = true;
    try std.testing.expectEqual(@as(c_int, -1), c.JS_ResolveModule(engine.context, module));
    const load_error = c.JS_GetException(engine.context);
    defer engine.freeValue(load_error);
    try std.testing.expectEqual(@as(usize, 4), resolution.normalizations);
    try std.testing.expectEqual(@as(usize, 0), resolution.loads);
    c.JS_RunGC(engine.runtime);
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiModuleGraphHasTLA(engine.context, module, &output));
    const incomplete = c.JS_GetException(engine.context);
    defer engine.freeValue(incomplete);
    try std.testing.expectEqual(@as(c_int, 99), output);
    try std.testing.expectEqual(@as(usize, 4), resolution.normalizations);
    try std.testing.expectEqual(@as(usize, 0), resolution.loads);
    try check(engine, "globalThis.queryNativeInit===undefined");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
test "module graph TLA query rejects foreign context ownership wrong tag and null output" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const local = try compile(engine, "export const x=1", "C:/query/local.mjs");
    defer engine.freeValue(local);
    const foreign = c.JS_NewContext(engine.runtime) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(foreign);
    const source = "export const foreignValue=1";
    const module = c.JS_Eval(foreign, source.ptr, source.len, "C:/query/foreign.mjs", c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
    defer c.JS_FreeValue(foreign, module);
    try std.testing.expect(!c.JS_IsException(module));
    var output: c_int = 99;
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiModuleGraphHasTLA(engine.context, module, &output));
    engine.freeValue(c.JS_GetException(engine.context));
    try std.testing.expectEqual(@as(c_int, 99), output);
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiModuleGraphHasTLA(engine.context, c.pi_js_undefined(), &output));
    engine.freeValue(c.JS_GetException(engine.context));
    try std.testing.expectEqual(@as(c_int, 99), output);
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiModuleGraphHasTLA(engine.context, local, null));
    engine.freeValue(c.JS_GetException(engine.context));
    try query(engine, local, 0);
}
fn preservesPending(fatal: bool) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const module = try compile(engine, "export const x=1", "C:/query/pending.mjs");
    defer engine.freeValue(module);
    const reason = if (fatal) pending: {
        _ = engine.throwNativeOutOfMemory();
        const value = c.JS_GetException(engine.context);
        c.JS_SetUncatchableError(engine.context, value);
        break :pending value;
    } else try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(reason);
    defer if (fatal) c.JS_ClearUncatchableError(engine.context, reason);
    const generation = engine.native_allocation_generation;
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    var output: c_int = 99;
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiModuleGraphHasTLA(engine.context, module, &output));
    const actual = c.JS_GetException(engine.context);
    defer engine.freeValue(actual);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, reason));
    try std.testing.expectEqual(generation, engine.native_allocation_generation);
    try std.testing.expectEqual(@as(c_int, 99), output);
}
test "module graph TLA query preserves an actual pending ordinary reason unchanged" { try preservesPending(false); }
test "module graph TLA query preserves an actual pending fresh private fatal without retagging" { try preservesPending(true); }
test "module graph TLA query ignores historical captured flags when no VM reason is pending" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const module = try compile(engine, "export const x=1", "C:/query/historical.mjs");
    defer engine.freeValue(module);
    const old = try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(old);
    c.JS_SetUncatchableError(engine.context, old);
    defer c.JS_ClearUncatchableError(engine.context, old);
    engine.captured_exception = c.JS_DupValue(engine.context, old);
    try query(engine, module, 0);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, old));
}
test "module graph TLA query scratch allocation failure leaves output unchanged and permits reuse" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const module = try compile(engine, "export const x=1", "C:/query/allocation.mjs");
    defer engine.freeValue(module);
    c.JS_SetMemoryLimit(engine.runtime, 1);
    defer c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    var output: c_int = 99;
    const status = c.JS_PiModuleGraphHasTLA(engine.context, module, &output);
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    try std.testing.expectEqual(@as(c_int, -1), status);
    try std.testing.expectEqual(@as(c_int, 99), output);
    // Existing VM OOM may fall back to null. Do not infer a native fatal tag.
    try query(engine, module, 0);
}
fn nativeInit(context: ?*c.JSContext, _: ?*c.JSModuleDef) callconv(.c) c_int {
    const global = c.JS_GetGlobalObject(context);
    defer c.JS_FreeValue(context, global);
    return if (c.JS_SetPropertyStr(context, global, "queryNativeInit", c.JS_NewInt32(context, 1)) < 0) -1 else 0;
}
test "module graph TLA query traverses an actual native dependency without initializing it" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    if (c.JS_NewCModule(engine.context, "C:/query/native.mjs", nativeInit) == null) return error.NativeModuleSetupFailure;
    const module = try compile(engine, "import 'C:/query/native.mjs';globalThis.nativeParentBody=true;", "C:/query/native-parent.mjs");
    defer engine.freeValue(module);
    try query(engine, module, 0);
    try check(engine, "globalThis.queryNativeInit===undefined&&!globalThis.nativeParentBody");
    const evaluated = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, module));
    defer engine.freeValue(evaluated);
    try std.testing.expect(!c.JS_IsException(evaluated));
    try check(engine, "globalThis.queryNativeInit===1&&globalThis.nativeParentBody===true");
}
test "module graph TLA query actual Engine budget interruption frees partially initialized scratch" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const module = try compile(engine, "export const x=1", "C:/query/budget.mjs");
    defer engine.freeValue(module);
    // The current context owns 12001 modules. Counting completes before the
    // third <=10000-step trusted Engine poll; table initialization is then active.
    for (0..12000) |index| {
        var name_buffer: [80]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&name_buffer, "C:/query/context-only-{d}.mjs", .{index});
        if (c.JS_NewCModule(engine.context, name.ptr, nativeInit) == null) return error.NativeModuleSetupFailure;
    }
    const previous = engine.interrupts;
    defer engine.interrupts = previous;
    engine.interrupts = engine.options.interrupt_budget - 2;
    var output: c_int = 99;
    const status = c.JS_PiModuleGraphHasTLA(engine.context, module, &output);
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    defer c.JS_ClearUncatchableError(engine.context, reason);
    engine.interrupts = previous;
    try std.testing.expectEqual(@as(c_int, -1), status);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(@as(c_int, 99), output);
    c.JS_ClearUncatchableError(engine.context, reason);
    c.JS_RunGC(engine.runtime);
    try query(engine, module, 0);
}
