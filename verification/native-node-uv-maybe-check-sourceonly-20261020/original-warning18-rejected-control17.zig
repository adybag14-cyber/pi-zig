//! Genuine native process-warning and Environment::ThrowUVException controls.
//! Uses the actual native_process owner and Environment, with actual JavaScript
//! property getters/callbacks. Unselected scheduling and fatal-policy operations
//! fail explicitly; this root does not claim full bootstrap or immediate drain.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const em = a.v.em;
const callbacks = @import("extensions/native_node_callback_scope.zig");
const providers = @import("extensions/native_node_async_providers.zig");
const functions = @import("extensions/native_node_module_callable.zig");
const warning = @import("extensions/native_node_process_warning.zig");
const throwing = @import("extensions/native_node_throw_uv_exception.zig");
const uv = @cImport({ @cInclude("uv.h"); });

fn noHook(_: *callbacks.Environment) anyerror!void { return error.UnselectedActualFatalHookPolicy; }
fn noCheck(_: *callbacks.Environment, _: callbacks.Check) anyerror { return error.UnselectedActualNativeCheck; }
fn noCorruption(_: *callbacks.Environment, _: f64) anyerror { return error.UnselectedActualCorruptedStack; }
fn noCheckpoint(_: *callbacks.Environment) anyerror!void { return error.UnselectedActualTaskQueueCheckpoint; }
fn noSchedule(_: *callbacks.Environment) anyerror!void { return error.UnselectedActualDestroyImmediate; }
fn noInterrupt(_: *callbacks.Environment) anyerror!void { return error.UnselectedActualDestroyInterrupt; }
const operations: callbacks.Operations = .{
    .on_hook_exception = noHook, .native_check_failure = noCheck,
    .fail_corrupted_async_stack = noCorruption, .perform_checkpoint = noCheckpoint,
    .schedule_destroy_immediate = noSchedule, .request_destroy_interrupt = noInterrupt,
};
var active_fixture: ?*Fixture = null;
fn nativeEnv() *callbacks.Environment { return active_fixture.?.environment.?; }
fn ordinary(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(try warning.emitGeneric(nativeEnv(), .{ .warning = "native warning" })));
}
fn typed(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(try warning.emitGeneric(nativeEnv(), .{ .warning = "native warning", .warning_type = "SelectedType" })));
}
fn codeOnly(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(try warning.emitGeneric(nativeEnv(), .{ .warning = "native warning", .code = "IGNORED" })));
}
fn full(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(try warning.emitGeneric(nativeEnv(), .{ .warning = "native warning", .warning_type = "SelectedType", .code = "CODE" })));
}
fn encoding(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(try warning.emitGeneric(nativeEnv(), .{
        .warning = "\xc3\xa9\x00tail", .warning_type = "T\x00type", .code = "C\x00code",
    })));
}
fn formatted(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(try warning.emitFormattedWarning(nativeEnv(), "\xc3\xa9\x00tail")));
}
fn deprecation(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(try warning.emitDeprecationWarning(nativeEnv(), "deprecated\x00tail", "DEP0137")));
}
fn throwUv(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    try throwing.throwException(nativeEnv(), .{ .code = uv.UV_EINVAL, .syscall = "close", .message = "selected failure" });
    return error.ActualThrowUvReturned;
}
fn flagError(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    std.debug.assert(args.len == 1 and c.JS_IsError(args[0]));
    c.JS_SetUncatchableError(engine.context, args[0]);
    return c.pi_js_undefined();
}
fn isFlagged(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    std.debug.assert(args.len == 1);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsUncatchableError(args[0])));
}
fn disable(env_engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    _ = env_engine;
    nativeEnv().can_call_into_js = false;
    return c.pi_js_undefined();
}
const Fixture = struct {
    native_environment: std.process.Environ.Map,
    engine: *em.Engine,
    environment: ?*callbacks.Environment = null,
    fn init(self: *Fixture) !void {
        self.* = .{ .native_environment = .init(std.testing.allocator), .engine = undefined };
        errdefer self.native_environment.deinit();
        self.engine = try em.Engine.init(std.testing.allocator, .{});
        errdefer self.engine.deinit();
        try @import("extensions/native_process.zig").install(
            self.engine, std.testing.io, &self.native_environment, &.{"actual-native-warning"});
        active_fixture = self;
        errdefer active_fixture = null;
        errdefer self.closeEnvironment() catch {};
        const result = try a.expression(self.engine, installBody, .{self});
        self.engine.freeValue(result);
    }
    fn installBody(s: *a.Scope, self: *Fixture) !c.JSValue {
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const process = try s.get(global, "process");
        const generation = try s.beforeAllocation();
        const symbol = try s.checkedAllocation(c.JS_NewSymbol(s.engine.context, "node:resource_symbol", false), generation);
        self.environment = try callbacks.Environment.create(s.engine, .{
            .provider_names = providers.names(false), .resource_symbol = symbol,
            .process_object = process, .async_context_frame = false, .operations = operations,
        });
        try s.define(global, "actualProcess", process, c.JS_PROP_C_W_E);
        try s.define(global, "actualUVEINVAL", c.JS_NewInt32(s.engine.context, uv.UV_EINVAL), 0);
        inline for (.{
            .{ "actualWarning", ordinary }, .{ "actualTypedWarning", typed },
            .{ "actualCodeOnlyWarning", codeOnly }, .{ "actualFullWarning", full },
            .{ "actualEncodingWarning", encoding }, .{ "actualFormattedWarning", formatted },
            .{ "actualDeprecationWarning", deprecation }, .{ "actualThrowUV", throwUv },
            .{ "actualFlagError", flagError }, .{ "actualIsFlagged", isFlagged },
            .{ "actualDisableEnvironment", disable },
        }) |entry| {
            const function = try s.own(try functions.create(s.engine, entry[0], 0, false, entry[1], &.{}));
            try s.define(global, entry[0], function, c.JS_PROP_C_W_E);
        }
        return c.pi_js_undefined();
    }
    fn evaluate(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "actual-native-warning.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(result);
    }
    fn closeEnvironment(self: *Fixture) !void {
        const env = self.environment orelse return;
        try env.cleanupRealmAfterIoJoin();
        try env.disarm();
        self.environment = null;
        env.release();
    }
    fn deinit(self: *Fixture) void {
        self.closeEnvironment() catch @panic("actual warning Environment failed to close");
        self.engine.deinit();
        active_fixture = null;
        self.native_environment.deinit();
    }
};

test "native process warning disabled Environment skips live emitWarning getter" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\let reads=0; Object.defineProperty(actualProcess,"emitWarning",{configurable:true,get(){++reads;throw "unexpected";}});
        \\actualDisableEnvironment();
        \\if(actualWarning()!==false || reads!==0)throw new Error("disabled native warning entered JS");
    );
}
test "native process warning stopping Environment skips live emitWarning getter" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.environment.?.stopping = true;
    try f.evaluate(
        \\Object.defineProperty(actualProcess,"emitWarning",{configurable:true,get(){throw "unexpected";}});
        \\if(actualWarning()!==false)throw new Error("stopping native warning");
    );
}
test "native process warning nonfunctions return false without coercion" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\for(const value of [undefined,null,false,17,"method",{[Symbol.toPrimitive](){throw "coerced";}}]){
        \\ actualProcess.emitWarning=value;if(actualWarning()!==false)throw new Error("nonfunction warning");
        \\}
    );
}
test "native process warning direct call preserves native process receiver and one argument" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\let calls=0;actualProcess.emitWarning=function(message){"use strict";++calls;
        \\ if(this!==actualProcess||arguments.length!==1||message!=="native warning")throw new Error("direct call contract");};
        \\if(actualWarning()!==true||calls!==1)throw new Error("ordinary warning result");
    );
}
test "native process warning nonempty type adds exactly the second argument" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\actualProcess.emitWarning=function(message,type){if(arguments.length!==2||message!=="native warning"||type!=="SelectedType")throw "type";};
        \\if(actualTypedWarning()!==true)throw "result";
    );
}
test "native process warning code is ignored when type is empty" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\actualProcess.emitWarning=function(message){if(arguments.length!==1||message!=="native warning")throw "code-only";};
        \\if(actualCodeOnlyWarning()!==true)throw "result";
    );
}
test "native process warning nonempty type and code add exactly three arguments" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\actualProcess.emitWarning=function(message,type,code){if(arguments.length!==3||message!=="native warning"||type!=="SelectedType"||code!=="CODE")throw "full";};
        \\if(actualFullWarning()!==true)throw "result";
    );
}
test "native process warning explicit UTF8 string views preserve embedded NULs" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\actualProcess.emitWarning=function(message,type,code){if(message!=="\u00e9\0tail"||type!=="T\0type"||code!=="C\0code")throw "explicit views";};
        \\if(actualEncodingWarning()!==true)throw "result";
    );
}
test "native process warning formatted c string truncates only after actual formatting" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\actualProcess.emitWarning=function(message){if(arguments.length!==1||message!=="\u00e9")throw "c string";};
        \\if(actualFormattedWarning()!==true)throw "result";
    );
    const allocator = f.environment.?.allocator();
    const first = try warning.formatFileHandleGcWarning(allocator, std.math.minInt(i32)); defer allocator.free(first);
    const last = try warning.formatFileHandleGcWarning(allocator, std.math.maxInt(i32)); defer allocator.free(last);
    try std.testing.expectEqualStrings("Closing file descriptor -2147483648 on garbage collection", first);
    try std.testing.expectEqualStrings("Closing file descriptor 2147483647 on garbage collection", last);
}
test "native process warning deprecation preserves full message and exact type code" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\actualProcess.emitWarning=function(message,type,code){if(arguments.length!==3||message!=="deprecated\0tail"||type!=="DeprecationWarning"||code!=="DEP0137")throw "deprecation";};
        \\if(actualDeprecationWarning()!==true)throw "result";
    );
}
test "native process warning live method uses retained process after global replacement" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\let first=0,second=0;actualProcess.emitWarning=function(){if(this!==actualProcess)throw "receiver";++first;};
        \\globalThis.process={emitWarning(){throw "replacement process";}};
        \\if(!actualWarning())throw "first";actualProcess.emitWarning=function(){if(this!==actualProcess)throw "receiver";++second;};
        \\if(!actualWarning()||first!==1||second!==1)throw "live method";
    );
}
test "native process warning actual getter throw keeps exact ordinary reason" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\const reason={marker:"getter"};Object.defineProperty(actualProcess,"emitWarning",{configurable:true,get(){throw reason;}});
        \\let caught=false;try{actualWarning();}catch(error){if(error!==reason)throw "wrong reason";caught=true;}
        \\if(!caught)throw "missing getter throw";
    );
}
test "native process warning actual callback throw keeps exact ordinary reason" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\const reason={marker:"call"};actualProcess.emitWarning=function(){throw reason;};
        \\let caught=false;try{actualWarning();}catch(error){if(error!==reason)throw "wrong reason";caught=true;}
        \\if(!caught)throw "missing call throw";
    );
}
test "native process warning discarded flagged Error result remains returned DATA" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\const result=new Error("returned only");actualFlagError(result);actualProcess.emitWarning=function(){return result;};
        \\if(!actualWarning()||!actualIsFlagged(result))throw "returned Error became throw";
    );
}
test "native process warning getter can replace method while selected function stays rooted" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\let calls=0;Object.defineProperty(actualProcess,"emitWarning",{configurable:true,get(){
        \\ Object.defineProperty(actualProcess,"emitWarning",{configurable:true,value:undefined});
        \\ return function(){if(this!==actualProcess)throw "receiver";++calls;};}});
        \\if(!actualWarning()||actualWarning()!==false||calls!==1)throw "selected method lifetime";
    );
}
test "native process warning ThrowUVException throws intrinsic actual Error fields" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\const OriginalError=Error;Object.defineProperty(globalThis,"Error",{configurable:true,get(){throw "public Error";}});
        \\let caught=false;try{actualThrowUV();}catch(error){
        \\ if(!(error instanceof OriginalError)||error.message!=="EINVAL: selected failure, close"||error.errno!==actualUVEINVAL||error.code!=="EINVAL"||error.syscall!=="close")throw "actual UV error";
        \\ caught=true;}if(!caught)throw "missing UV throw";
    );
}
test "native process warning ThrowUVException preserves actual inherited setter throw" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\const reason={marker:"setter"};Object.defineProperty(Error.prototype,"code",{configurable:true,set(){throw reason;}});
        \\let caught=false;try{actualThrowUV();}catch(error){if(error!==reason)throw "wrong setter reason";caught=true;}
        \\delete Error.prototype.code;if(!caught)throw "missing setter throw";
    );
}
test "native process warning ThrowUVException has no canCallIntoJs guard" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\actualDisableEnvironment();let called=false;
        \\Object.defineProperty(Error.prototype,"code",{configurable:true,set(value){called=value==="EINVAL";}});
        \\let caught=false;try{actualThrowUV();}catch(error){if(!(error instanceof Error)||error.syscall!=="close")throw "wrong throw";caught=true;}
        \\delete Error.prototype.code;if(!caught||!called)throw "native guard incorrectly inserted";
    );
}
