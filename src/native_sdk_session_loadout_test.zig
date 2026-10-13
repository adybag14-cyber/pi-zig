const std = @import("std");
const builtin = @import("builtin");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const json = @import("durable/backend/json.zig");
const c = em.c;

fn utility(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const first = if (argc > 0) args[0] else c.pi_js_undefined();
    return (switch (magic) {
        0 => @import("extensions/native_sdk_prompt_normalize.zig").normalize(engine, first),
        1 => @import("extensions/native_sdk_prompt_render.zig").buildSections(engine, first),
        2 => @import("extensions/native_sdk_prompt_render.zig").diffSections(engine, first, if (argc > 1) args[1] else c.pi_js_undefined()),
        else => unreachable,
    }) catch |err| sdk.fail(engine, err);
}
fn setup(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    var environment: std.process.Environ.Map = .init(engine.gpa);
    defer environment.deinit();
    try environment.put("PI_PACKAGE_DIR", if (builtin.os.tag == .windows) "C:/Users/adyba/pi-sdk-loadout-source-e6220e1-20261013/packages/coding-agent" else "/tmp/pi-sdk-loadout-source-fixture/packages/coding-agent");
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-session-loadout"});
    try @import("extensions/native_stream.zig").install(engine);
    const namespace = try sdk.object(engine);
    defer engine.freeValue(namespace);
    try sdk.install(engine, namespace);
    try @import("extensions/native_agent_complete.zig").install(engine, namespace);
    const constructor = try sdk.get(engine, namespace, "AgentSession");
    defer engine.freeValue(constructor);
    const prototype = try sdk.get(engine, constructor, "prototype");
    defer engine.freeValue(prototype);
    try @import("extensions/native_sdk_session_loadout.zig").install(engine, prototype);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "loadoutNative", c.JS_DupValue(engine.context, namespace));
    inline for (.{ "normalizeLoadoutOptions", "buildLoadoutSections", "diffLoadoutSections" }, 0..) |name, index| try sdk.put(engine, global, name, try engine.checked(c.pi_js_function_magic(engine.context, utility, name, if (index == 2) 2 else 1, @intCast(index))));
    const prepared = try engine.eval(
        \\globalThis.createLoadoutCaseReceiver=()=>{const{Agent,AgentSession,SessionManager,ExtensionRunner,convertToLlm}=loadoutNative,session=Object.create(AgentSession.prototype);const model={id:'fixture',name:'fixture',api:'openai-completions',provider:'fixture',baseUrl:'https://fixture.invalid',input:['text'],reasoning:false,cost:{input:0,output:0,cacheRead:0,cacheWrite:0},contextWindow:10000,maxTokens:1000},agent=new Agent({initialState:{model,tools:[],messages:[]},convertToLlm,streamFn(){throw Error('loadout fixture unexpectedly invoked model stream');}}),manager=SessionManager.inMemory('C:/Users/adyba/pi-zig-update-evidence-20261003'),runtime={getThinkingLevel:()=>agent.state.thinkingLevel};Object.defineProperty(session,'agent',{value:agent,writable:true,configurable:true,enumerable:true});session._extensionRunner=new ExtensionRunner([],runtime,'C:/Users/adyba/pi-zig-update-evidence-20261003',manager,{});return session;};
    , "loadout-native-collaborators.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(prepared);
}
fn bounded(value: json.Value, began: i64, ended: i64) !void {
    const actual: i64 = @intCast(try json.asInteger(value));
    if (actual < began or actual > ended) return error.LoadoutClockOutsideObservedOperation;
}
fn compare(actual: *json.Value, expected: *json.Value, began: i64, ended: i64) !void {
    if (actual.* != .object or actual.object.count() != 4) return error.LoadoutResultShapeChanged;
    if (actual.object.get("sectionsRows").?.array.items.len != 12 or actual.object.get("diffRows").?.array.items.len != 9) return error.LoadoutInventoryChanged;
    const source_bounds = expected.object.get("sourceTimeBounds") orelse return error.LoadoutSourceBoundsMissing;
    const source_begin: i64 = @intCast(try json.asInteger(source_bounds.object.get("began").?));
    const source_end: i64 = @intCast(try json.asInteger(source_bounds.object.get("ended").?));
    const cases = [_][]const u8{ "prepare-first", "prepare-remove", "prepare-explicit-messages", "prepare-forced", "prepare-hidden", "prepare-options-accessors", "prepare-current-replay" };
    const rows = actual.object.getPtr("rows") orelse return error.LoadoutRowsMissing;
    const originals = expected.object.getPtr("rows") orelse return error.LoadoutSourceRowsMissing;
    if (rows.array.items.len != 34 or originals.array.items.len != 34) return error.LoadoutInventoryChanged;
    var clocks: usize = 0;
    for (rows.array.items, originals.array.items) |*row, *original| {
        const scenario = row.object.get("scenario").?.string;
        const result = row.object.getPtr("result") orelse continue;
        if (result.* != .object) continue;
        const patch = result.object.getPtr("patch") orelse continue;
        var allowed = false;
        for (cases) |name| if (std.mem.eql(u8, name, scenario)) {
            allowed = true;
            break;
        };
        if (!allowed) return error.UnexpectedLoadoutClockSlot;
        const stamp = patch.object.getPtr("timestamp") orelse return error.LoadoutClockMissing;
        const source = original.object.getPtr("result").?.object.getPtr("patch").?.object.getPtr("timestamp") orelse return error.LoadoutSourceClockMissing;
        try bounded(stamp.*, began, ended);
        try bounded(source.*, source_begin, source_end);
        // Only these seven original Date.now() observations vary. Original raw
        // captures and the native raw log retain their unmodified measurements.
        stamp.* = .null;
        source.* = .null;
        clocks += 1;
    }
    if (clocks != cases.len) return error.LoadoutClockInventoryChanged;
    inline for (.{ "rows", "sectionsRows", "diffRows", "metadata" }) |field| {
        const native = try std.json.Stringify.valueAlloc(std.testing.allocator, actual.object.get(field).?, .{});
        defer std.testing.allocator.free(native);
        const source = try std.json.Stringify.valueAlloc(std.testing.allocator, expected.object.get(field).?, .{});
        defer std.testing.allocator.free(source);
        if (!std.mem.eql(u8, native, source)) {
            std.debug.print("Loadout Source mismatch {s}:\nactual {s}\nexpected {s}\n", .{ field, native, source });
            return error.LoadoutSourceContractMismatch;
        }
    }
}
fn exercise(gpa: std.mem.Allocator, print_raw: bool) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const generation = engine.native_allocation_generation;
    const began = std.Io.Clock.real.now(std.testing.io).toMilliseconds();
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-loadout-e622.input.txt"), "sdk-session-loadout-native.mjs") catch |err| {
        if (print_raw) std.debug.print("Loadout VM: {s}\n", .{engine.last_error orelse "no diagnostic"});
        const original = engine.nativeAllocationError(err, generation);
        if (!print_raw and original != error.OutOfMemory) {
            std.debug.print("SDK_LOADOUT_GPA_EXCEPTION error={s} generation_before={d} generation_after={d} captured_tag={d} native_tag={d} diagnostic={s}\n", .{ @errorName(original), generation, engine.native_allocation_generation, if (engine.captured_exception) |value| c.pi_js_native_allocation_error_generation(value) else 0, if (engine.native_allocation_exception) |value| c.pi_js_native_allocation_error_generation(value) else 0, engine.last_error orelse "none" });
            if (engine.captured_exception) |value| {
                const text = c.JS_ToCString(engine.context, value);
                defer if (text != null) c.JS_FreeCString(engine.context, text);
                if (text != null) std.debug.print("SDK_LOADOUT_GPA_THROWN={s}\n", .{std.mem.span(text)});
            }
        }
        return original;
    };
    engine.freeValue(result);
    // The fixture intentionally catches original hook errors. A marked host
    // allocation failure caught by guest input still makes this GPA trial OOM.
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const value = try sdk.get(engine, global, "sdkSessionLoadoutRows");
    defer engine.freeValue(value);
    const encoded = try engine.stringify(value);
    defer gpa.free(encoded);
    const ended = std.Io.Clock.real.now(std.testing.io).toMilliseconds();
    if (print_raw) std.debug.print("SDK_SESSION_LOADOUT_RAW={s}\n", .{encoded});
    var actual = try json.Owned.parse(gpa, encoded);
    defer actual.deinit();
    var expected = try json.Owned.parse(gpa, if (builtin.os.tag == .windows) @embedFile("extensions/fixtures/sdk-session-loadout-e622.json") else @embedFile("extensions/fixtures/sdk-session-loadout-e622-posix.json"));
    defer expected.deinit();
    try compare(&actual.value, &expected.value, began, ended);
    const cleared = try engine.eval("delete globalThis.loadoutHeldCallback;delete globalThis.loadoutCaseReceivers;delete globalThis.sdkSessionLoadoutRows;delete globalThis.createLoadoutCaseReceiver;delete globalThis.loadoutNative;", "loadout-clear.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(cleared);
    c.JS_RunGC(engine.runtime);
}

test "native SDK session loadout matches 55 genuine latest factory Source cases sections diffs and metadata" {
    try exercise(std.testing.allocator, true);
}

test "native SDK session loadout retains live hook callbacks and receiver across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const result = try engine.evalModule(
        \\(()=>{const receiver=createLoadoutCaseReceiver(),tool={name:'kept',description:'original'};Object.assign(receiver,{_toolRegistry:new Map([['kept',tool]]),_toolDefinitions:new Map([['kept',{definition:{name:'kept',prepareLoadout(loadout){globalThis.keptLoadoutCallbacks={exposure:loadout.getExposure,namespace:loadout.getNamespace,guidelines:loadout.getPromptGuidelines};}},sourceInfo:{path:'<gc-fixture>'}}]]),_toolPromptGuidelines:new Map([['kept',['before']]])});receiver._applyToolLoadout(['kept']);globalThis.keptLoadoutWeak=new WeakRef(receiver);})();
    , "loadout-gc-setup.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    const mutated = try engine.eval("(()=>{const receiver=keptLoadoutWeak.deref();if(!receiver)throw Error('loadout callback lost receiver');receiver._toolDefinitions.get('kept').definition.exposure='deferred';receiver._toolDefinitions.get('kept').definition.namespace='after';receiver._toolPromptGuidelines.set('kept',['after']);})();", "loadout-gc-mutate.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(mutated);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const checked = try engine.eval("if(keptLoadoutCallbacks.exposure('kept')!=='deferred'||keptLoadoutCallbacks.namespace('kept')!=='after'||keptLoadoutCallbacks.guidelines('kept')[0]!=='after')throw Error('loadout callback lost live receiver');delete globalThis.keptLoadoutCallbacks;", "loadout-gc-check.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(checked);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const released = try engine.eval("if(keptLoadoutWeak.deref()!==undefined)throw Error('loadout receiver retained after callback disposal');delete globalThis.keptLoadoutWeak;", "loadout-gc-release.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(released);
}

test "native SDK session loadout releases every failed full Source packet host allocation" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa, false) catch |err| {
                if (err != error.OutOfMemory) {
                    const failed: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                    std.debug.print("SDK_LOADOUT_GPA_FAILURE fail_index={d} alloc_index={d} induced={any} error={s}\n", .{ failed.fail_index, failed.alloc_index, failed.has_induced_failure, @errorName(err) });
                    std.debug.print("SDK_LOADOUT_GPA_ALLOCATION_STACK={f}\n", .{std.debug.FormatStackTrace{ .stack_trace = failed.getStackTrace() }});
                }
                return err;
            };
        }
    };
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-session-loadout", Probe.run, .{});
}
