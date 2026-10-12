const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const Fixture = @import("native_error_stack_fixture.zig").Fixture;

test "Native Error stack Source controlled42 exact descriptors delete raw assignment lazy prepare and limits" {
    const fixture = try Fixture.init(std.testing.allocator, .{ .memory_limit = 64 * 1024 * 1024 });
    defer fixture.deinit();
    const engine = fixture.engine;
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("extensions/fixtures/node-error-stack-controlled42.json");
    try js.define(engine, root, "stackSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-node-stack-controlled42")));
    const module = try engine.evalModule(@embedFile("extensions/fixtures/error-stack-original-controlled.input.mjs"), "error-stack-original-controlled.input.mjs");
    defer engine.freeValue(module);
    const function = try js.get(engine, module, "runStackCases");
    defer engine.freeValue(function);
    const rows = js.call(engine, function, c.pi_js_undefined(), &.{}) catch |err| {
        std.debug.print("Native Error stack Source42 execution: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    try js.define(engine, root, "stackActual", rows);
    const result = engine.eval(
        \\if(stackSource.cases.length!==42||stackActual.length!==42)throw Error('Source42 count');
        \\for(let i=0;i<42;i++){if(JSON.stringify(stackActual[i])!==JSON.stringify(stackSource.cases[i]))throw Error(JSON.stringify({index:i,id:stackSource.cases[i].id,actual:stackActual[i],expected:stackSource.cases[i]}));}
    , "stack-source42-compare.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
        std.debug.print("Native Error stack Source42 mismatch: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(result);
}

test "Native Error stack Source exact named caller limit1 original function filename line and column" {
    const fixture = try Fixture.init(std.testing.allocator, .{ .memory_limit = 64 * 1024 * 1024 });
    defer fixture.deinit();
    const engine = fixture.engine;
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("extensions/fixtures/node-error-stack-frame1.json");
    try js.define(engine, root, "stackFrameSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-node-stack-frame1")));
    const result = try engine.eval(@embedFile("extensions/fixtures/owned-error-stack-frame.input.js"), "owned-error-stack-frame.input.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    const comparison = engine.eval("if(JSON.stringify(ownedErrorFrameResult)!==JSON.stringify(stackFrameSource.value))throw Error(JSON.stringify({actual:ownedErrorFrameResult,expected:stackFrameSource.value}));", "stack-frame1-compare.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
        std.debug.print("Native Error stack named Source frame mismatch: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(comparison);
}

test "Native Error stack Source constructor13 exact lexical locations named property computed spread and new target" {
    const fixture = try Fixture.init(std.testing.allocator, .{ .memory_limit = 64 * 1024 * 1024 });
    defer fixture.deinit();
    const engine = fixture.engine;
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("extensions/fixtures/node-error-stack-constructor13.json");
    try js.define(engine, root, "constructorSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-node-constructor13")));
    const result = try engine.eval(@embedFile("extensions/fixtures/error-stack-constructor-location.input.js"), "error-stack-constructor-location.input.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    const comparison = engine.eval(
        \\if(constructorLocationResult.length!==13||constructorSource.value.length!==13)throw Error('constructor13 count');
        \\for(let i=0;i<13;i++){if(JSON.stringify(constructorLocationResult[i])!==JSON.stringify(constructorSource.value[i]))throw Error(JSON.stringify({index:i,actual:constructorLocationResult[i],expected:constructorSource.value[i]}));}
    , "stack-constructor13-compare.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
        std.debug.print("Native Error stack constructor Source mismatch: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(comparison);
}

const policy_mod = @import("extensions/native_promise_rejection_policy.zig");
const rejection_mod = @import("extensions/native_promise_rejections.zig");
fn allocationEval(engine: *js.Engine, source: []const u8) !void {
    const generation = engine.native_allocation_generation;
    const result = engine.eval(source, "stack-policy-allocation.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
}
fn stackAllocationProbe(gpa: std.mem.Allocator) !void {
    const fixture = try Fixture.init(gpa, .{});
    defer fixture.deinit();
    const engine = fixture.engine;
    try allocationEval(engine,
        \\Error.stackTraceLimit=2;
        \\function allocationFrame(){return new Error('allocation stack',{cause:{raw:true}})}
        \\const first=allocationFrame();const firstStack=first.stack;first.stack={raw:'replacement'};
        \\const target={};Error.captureStackTrace(target,allocationFrame);const targetStack=target.stack;
        \\Error.prepareStackTrace=(error,frames)=>{const nested=new TypeError('nested allocation');return nested.stack+frames.map(frame=>frame.toString()).join('\n')};
        \\const lazy=allocationFrame();const lazyStack=lazy.stack;
        \\Error.prepareStackTrace=undefined;const defaultStack=new RangeError('default allocation').stack;
        \\delete first.stack;Error.captureStackTrace(first);const recaptured=first.stack;
    );
    c.JS_RunGC(engine.runtime);
}
test "Native Error stack Source complete host allocation failure sweep install capture lazy format GC and teardown" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, stackAllocationProbe, .{});
}
fn policyAllocationProbe(gpa: std.mem.Allocator) !void {
    const fixture = try Fixture.init(gpa, .{});
    defer fixture.deinit();
    const engine = fixture.engine;
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"stack-policy-allocation"});
    var policy = try policy_mod.Policy.init(engine);
    defer policy.deinit();
    try allocationEval(engine,
        \\globalThis.reason={raw:'policy allocation'};globalThis.promise=Promise.reject(reason);
        \\process.on('uncaughtExceptionMonitor',(reason,origin)=>{const stack=reason.stack});
        \\process.on('exit',code=>{});
    );
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const process = try js.get(engine, root, "process");
    defer engine.freeValue(process);
    const promise = try js.get(engine, root, "promise");
    defer engine.freeValue(promise);
    const reason = try js.get(engine, root, "reason");
    defer engine.freeValue(reason);
    const pending: rejection_mod.Rejection = .{ .promise = promise, .reason = reason, .scope = c.pi_js_undefined(), .uid = 1 };
    const fatal = (try policy.reportUnhandled(process, pending)) orelse return error.MissingFatal;
    defer fatal.deinit(engine);
    const terminal = (try policy.reportUncaught(process, fatal)) orelse return error.MissingTerminal;
    defer terminal.deinit(engine);
    c.JS_RunGC(engine.runtime);
}
test "Native Error stack Source complete policy host allocation failure sweep original reason monitor exit and teardown" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, policyAllocationProbe, .{});
}

test "Native Error stack Source genuine ephemeron stack records do not retain captured-function or formatted-self cycles" {
    const fixture = try Fixture.init(std.testing.allocator, .{});
    defer fixture.deinit();
    const engine = fixture.engine;
    engine.freeValue(try engine.eval(
        \\Error.stackTraceLimit=2;
        \\globalThis.capturedCycleWeak=(function(){let error;function capturedCycleFrame(){error=new Error('captured cycle')}capturedCycleFrame();return new WeakRef(error)})();
        \\globalThis.formattedCycleWeak=(function(){const error=new Error('formatted cycle');Error.prepareStackTrace=()=>({error});void error.stack;Error.prepareStackTrace=undefined;return new WeakRef(error)})();
        \\globalThis.selfCycleWeak=(function(){const error=new Error('self cycle');error.stack=error;return new WeakRef(error)})();
    , "stack-genuine-ephemeron-cycles.js", c.JS_EVAL_TYPE_GLOBAL));
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    engine.freeValue(try engine.eval(
        \\if(capturedCycleWeak.deref()!==undefined||formattedCycleWeak.deref()!==undefined||selfCycleWeak.deref()!==undefined)throw Error('native stack map retained an unreachable genuine cycle');
    , "stack-genuine-ephemeron-cycles-compare.js", c.JS_EVAL_TYPE_GLOBAL));
}
