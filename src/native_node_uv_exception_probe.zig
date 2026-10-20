//! Isolated process controls for actual UVException Object::Set(...).Check().
//! Throwing inherited setters are real guest throws. The genuine native Maybe
//! failure owner then terminates this process before guest catch or retirement.
//! Nonthrowing setter and readonly controls complete through actual ThrowUV.
const std = @import("std");
extern fn getchar() c_int;
const a = @import("extensions/native_node_argument_values.zig");
const em = a.v.em;
const c = em.c;
const callbacks = @import("extensions/native_node_callback_scope.zig");
const providers = @import("extensions/native_node_async_providers.zig");
const functions = @import("extensions/native_node_module_callable.zig");
const throwing = @import("extensions/native_node_throw_uv_exception.zig");
const uv = @cImport({ @cInclude("uv.h"); });

const fields = [_][]const u8{ "errno", "code", "syscall", "path", "dest" };
const Selected = struct {
    throw_index: ?usize = null,
    readonly_code: bool = false,
};
fn select(name: []const u8) !Selected {
    if (std.mem.eql(u8, name, "control-setters")) return .{};
    if (std.mem.eql(u8, name, "control-readonly")) return .{ .readonly_code = true };
    inline for (fields, 0..) |field, index| {
        if (std.mem.eql(u8, name, "throw-" ++ field)) return .{ .throw_index = index };
    }
    return error.UnknownActualUvCheckProbe;
}
fn unselected(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedActualUvCheckProbeOperation;
}
fn unselectedCheck(_: *callbacks.Environment, _: callbacks.Check) anyerror {
    return error.UnselectedActualUvCheckProbeCheck;
}
fn unselectedCorruption(_: *callbacks.Environment, _: f64) anyerror {
    return error.UnselectedActualUvCheckProbeCorruption;
}
const operations: callbacks.Operations = .{
    .on_hook_exception = unselected,
    .native_check_failure = unselectedCheck,
    .fail_corrupted_async_stack = unselectedCorruption,
    .perform_checkpoint = unselected,
    .schedule_destroy_immediate = unselected,
    .request_destroy_interrupt = unselected,
};
var active_environment: ?*callbacks.Environment = null;
var selected: Selected = .{};
var next_index: usize = 0;
fn actualThrow(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const env = active_environment orelse return error.ActualUvCheckEnvironmentRequired;
    try throwing.throwException(env, .{
        .code = uv.UV_EINVAL, .syscall = "close", .message = "selected failure",
        .path = "actual-path", .dest = "actual-dest",
    });
    return error.UnexpectedActualUvCheckReturn;
}
fn beforeSetter(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    if (args.len != 1 or !c.JS_IsNumber(args[0])) return error.UnexpectedActualUvCheckArgument;
    var index: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &index, args[0]) < 0) return error.UnexpectedActualUvCheckConversion;
    if (selected.readonly_code and next_index == 1) next_index += 1;
    if (index < 0 or @as(usize, @intCast(index)) != next_index or next_index >= fields.len)
        return error.UnexpectedActualUvCheckPropertyOrder;
    next_index += 1;
    const must_throw = if (selected.throw_index) |wanted| wanted == @as(usize, @intCast(index)) else false;
    if (must_throw) std.debug.print("UV_CHECK_SITE:{s}\n", .{fields[@intCast(index)]});
    return c.pi_js_bool(engine.context, @intFromBool(must_throw));
}
fn initialize(s: *a.Scope, output: *?*callbacks.Environment) !c.JSValue {
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    const process = try s.get(global, "process");
    const allocation = try s.beforeAllocation();
    const symbol = try s.checkedAllocation(c.JS_NewSymbol(
        s.engine.context, "node:resource_symbol", false), allocation);
    output.* = try callbacks.Environment.create(s.engine, .{
        .provider_names = providers.names(false), .resource_symbol = symbol,
        .process_object = process, .async_context_frame = false, .operations = operations,
    });
    inline for (.{
        .{ "actualThrowUV", actualThrow },
        .{ "actualBeforeSetter", beforeSetter },
    }) |entry| {
        const function = try s.own(try functions.create(s.engine, entry[0], 0, false, entry[1], &.{}));
        try s.define(global, entry[0], function, c.JS_PROP_C_W_E);
    }
    try s.define(global, "actualReadonlyCode", a.boolean(s, selected.readonly_code), 0);
    try s.define(global, "actualFatalCase", a.boolean(s, selected.throw_index != null), 0);
    try s.define(global, "actualUVEINVAL", c.JS_NewInt32(s.engine.context, uv.UV_EINVAL), 0);
    return c.pi_js_undefined();
}
pub fn main(init: std.process.Init) !void {
    // Original CI607 records its retained handle/live identity before closing
    // redirected stdin. Even a fast control waits for that actual owner.
    if (getchar() != -1) return error.UnexpectedNativeProbeInput;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedOneActualUvCheckProbe;
    selected = try select(args[1]);
    next_index = 0;
    var process_environment: std.process.Environ.Map = .init(init.gpa);
    defer process_environment.deinit();
    const engine = try em.Engine.init(init.gpa, .{});
    defer engine.deinit();
    try @import("extensions/native_process.zig").install(
        engine, init.io, &process_environment, &.{"native-node-uv-exception-probe"});
    var environment: ?*callbacks.Environment = null;
    defer if (environment) |owner| {
        active_environment = null;
        owner.cleanupRealmAfterIoJoin() catch @panic("actual UV check probe realm cleanup failed");
        owner.disarm() catch @panic("actual UV check probe environment disarm failed");
        owner.release();
    };
    const initialized = try a.expression(engine, initialize, .{&environment});
    engine.freeValue(initialized);
    active_environment = environment;
    const result = try engine.eval(
        \\const names=["errno","code","syscall","path","dest"];
        \\const expected=[actualUVEINVAL,"EINVAL","close","actual-path","actual-dest"];
        \\const reason={marker:"actual inherited setter throw"};
        \\for(let index=0;index<names.length;index++){
        \\ const name=names[index];
        \\ if(actualReadonlyCode&&index===1){
        \\  Object.defineProperty(Error.prototype,name,{configurable:true,writable:false,value:"inherited"});
        \\ }else{
        \\  Object.defineProperty(Error.prototype,name,{configurable:true,set:function actualUvSetter(value){
        \\   if(value!==expected[index])throw new Error("UNEXPECTED property value");
        \\   const mustThrow=actualBeforeSetter(index);
        \\   if(mustThrow)throw reason;
        \\   Object.defineProperty(this,name,{configurable:true,enumerable:true,writable:true,value});
        \\  }});
        \\ }
        \\}
        \\let caught=false;try{actualThrowUV();throw new Error("UNEXPECTED normal return");}
        \\catch(error){
        \\ if(actualFatalCase)throw new Error("UNEXPECTED guest catch");
        \\ if(!(error instanceof Error)||error.message!=="EINVAL: selected failure, close 'actual-path' -> 'actual-dest'")throw new Error("UNEXPECTED UV Error");
        \\ for(let i=0;i<names.length;i++){
        \\  if(actualReadonlyCode&&i===1){
        \\   if(error.code!=="inherited"||Object.hasOwn(error,"code"))throw new Error("UNEXPECTED readonly Set");
        \\  }else if(!Object.hasOwn(error,names[i])||error[names[i]]!==expected[i])throw new Error("UNEXPECTED actual field");
        \\ }
        \\ caught=true;
        \\}
        \\for(const name of names)delete Error.prototype[name];
        \\if(!caught)throw new Error("UNEXPECTED missing actual UV throw");
        , "native-node-uv-exception-probe.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    if (selected.throw_index != null or next_index != fields.len)
        return error.UnexpectedActualUvCheckContinuation;
}
