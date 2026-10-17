//! Genuine shared TTY/readline error registrations. Existing frozen TTY and
//! utility leaves are unchanged. Compose this ONCE, then give tty to both lanes.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
const f = @import("native_node_module_callable.zig");
const classes = @import("native_node_error_class.zig");
const tty_errors = @import("native_node_tty_errors.zig");
pub const Inputs = struct {
    messages: @import("native_node_tty_error_messages.zig").Exports,
    internal_inspect: c.JSValue,
    require: c.JSValue,
};
pub const Exports = struct {
    /// Real registered base classes, distinct from validator-only subclasses.
    codes: tty_errors.Exports,
    tty: tty_errors.Exports,
    /// util validates its number type with Hide, but its explicit negative/
    /// safe-integer ERR_OUT_OF_RANGE branch uses the registered BASE class.
    util: tty_errors.Exports,
    invalid_arg_value: c.JSValue,
    invalid_cursor_pos: c.JSValue,
    validate_function: c.JSValue,
    pub fn deinit(self: Exports, engine: *v.em.Engine) void { self.codes.deinit(engine); self.tty.deinit(engine); self.util.deinit(engine); engine.freeValue(self.invalid_arg_value); engine.freeValue(self.invalid_cursor_pos); engine.freeValue(self.validate_function); }
};
fn view(engine: *v.em.Engine, codes: tty_errors.Exports, invalid_arg: c.JSValue, out_of_range: c.JSValue) tty_errors.Exports {
    return .{ .invalid_fd=c.JS_DupValue(engine.context,codes.invalid_fd),.invalid_arg_type=c.JS_DupValue(engine.context,invalid_arg),.out_of_range=c.JS_DupValue(engine.context,out_of_range),.tty_init_failed=c.JS_DupValue(engine.context,codes.tty_init_failed),.errno_exception=c.JS_DupValue(engine.context,codes.errno_exception) };
}
fn define(s: *v.Scope, object: c.JSValue, name: [*:0]const u8, value: c.JSValue, flags: c_int) !void {
    if (c.JS_DefinePropertyValueStr(s.engine.context, object, name, c.JS_DupValue(s.engine.context, value), flags | c.JS_PROP_THROW) < 0) return v.js.capture(s.engine); try h.pending(s.engine);
}
fn text(s: *v.Scope, value: c.JSValue) !c.JSValue { return s.own(try h.success(s.engine, try s.engine.checked(c.JS_ToString(s.engine.context, value)))); }
fn getter(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { try h.pending(engine); return c.JS_DupValue(engine.context, roots[0]); }
fn accessor(s: *v.Scope, object: c.JSValue, key: c.JSValue, name: [*:0]const u8, returned: c.JSValue) !void {
    const atom = try v.js.atom(s.engine, key); defer c.JS_FreeAtom(s.engine.context, atom);
    const function = try s.own(try f.create(s.engine, name, 0, false, getter, &.{returned}));
    if (c.JS_DefinePropertyGetSet(s.engine.context, object, atom, c.JS_DupValue(s.engine.context, function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
}
fn errorString(engine: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine); var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    var result = try h.binary(&s, .add, try text(&s, try h.get(&s, receiver, "name")), try s.text(" ["));
    result = try h.binary(&s, .add, result, roots[0]); result = try h.binary(&s, .add, result, try s.text("]: "));
    result = try h.binary(&s, .add, result, try text(&s, try h.get(&s, receiver, "message"))); return c.JS_DupValue(engine.context, result);
}
fn construct(engine: *v.em.Engine, callee: c.JSValue, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine); var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const value = if (s.truthy(roots[2])) try classes.superConstruct(&s, callee, target, &.{roots[1]}) else try classes.superConstruct(&s, callee, target, &.{});
    try define(&s, value, "code", roots[0], c.JS_PROP_C_W_E);
    if (!s.truthy(roots[2])) try define(&s, value, "message", try h.call(&s, roots[1], value, args), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    return c.JS_DupValue(engine.context, value);
}
fn register(s: *v.Scope, base: c.JSValue, key: []const u8, message: c.JSValue, static_message: bool, marker: c.JSValue) !c.JSValue {
    const prototype = try s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, try h.get(s, base, "prototype"))));
    const function = try s.own(try classes.create(s.engine, "NodeError", 0, prototype, base, construct, &.{try s.text(key),message,c.pi_js_bool(s.engine.context,@intFromBool(static_message))}));
    try accessor(s, prototype, try s.text("constructor"), "get constructor", base);
    try accessor(s, prototype, marker, "get [kIsNodeError]", c.pi_js_bool(s.engine.context,1));
    try define(s, prototype, "toString", try s.own(try f.create(s.engine,"toString",0,false,errorString,&.{try s.text(key)})), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    return function;
}
fn stackLimitWritable(s: *v.Scope, error_class: c.JSValue) !bool {
    // The actual native QuickJS host has no V8 startup-snapshot serializer.
    // Preserve the Source live property/descriptor algorithm; V8 stack string
    // formatting and ErrorCaptureStackTrace remain separately unqualified.
    const atom=c.JS_NewAtom(s.engine.context,"stackTraceLimit"); if(atom==c.JS_ATOM_NULL)return v.js.capture(s.engine); defer c.JS_FreeAtom(s.engine.context,atom);
    var item:c.JSPropertyDescriptor=undefined;
    const present=c.JS_GetOwnProperty(s.engine.context,&item,error_class,atom);
    if(present<0)return v.js.capture(s.engine);
    if(present==0){const extensible=c.JS_IsExtensible(s.engine.context,error_class);if(extensible<0)return v.js.capture(s.engine);try h.pending(s.engine);return extensible!=0;}
    defer {s.engine.freeValue(item.value);s.engine.freeValue(item.getter);s.engine.freeValue(item.setter);}
    try h.pending(s.engine);
    return if(item.flags&c.JS_PROP_GETSET==0) item.flags&c.JS_PROP_WRITABLE!=0 else !c.JS_IsUndefined(item.setter);
}
fn hideConstruct(engine:*v.em.Engine,callee:c.JSValue,target:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    try h.pending(engine);var s:v.Scope=.{.engine=engine};defer s.deinit();
    if(!try stackLimitWritable(&s,roots[0]))return c.JS_DupValue(engine.context,try classes.superConstruct(&s,callee,target,args));
    const limit=try h.get(&s,roots[0],"stackTraceLimit");
    try h.set(&s,roots[0],"stackTraceLimit",c.JS_NewInt32(engine.context,0));
    const value=try classes.superConstruct(&s,callee,target,args);
    // Source has no finally: a throwing super leaves the installed zero.
    try h.set(&s,roots[0],"stackTraceLimit",limit);
    return c.JS_DupValue(engine.context,value);
}
fn hide(s:*v.Scope,base:c.JSValue,original_base:c.JSValue,error_class:c.JSValue)!c.JSValue{
    const prototype=try s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context,try h.get(s,base,"prototype"))));
    const hidden=try s.own(try classes.create(s.engine,"HideStackFramesError",0,prototype,base,hideConstruct,&.{error_class}));
    try accessor(s,prototype,try s.text("constructor"),"get constructor",original_base);
    try h.set(s,base,"HideStackFramesError",hidden);
    return hidden;
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Exports {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1; try h.pending(engine);
    if (!c.JS_IsObject(inputs.internal_inspect)) return error.RequiredActualReadlinePrivateInspect;
    inline for (.{ inputs.messages.invalid_fd, inputs.messages.invalid_arg_type, inputs.messages.out_of_range, inputs.messages.determine_specific_type, inputs.require }) |function| if (!c.JS_IsFunction(engine.context,function)) return error.RequiredActualReadlineMessageDependencies;
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    // ONE base registration plus ONE actual validator subclass serve all
    // TTY/util/readline validators. Neither class is flattened into the other.
    const argument_message = try s.own(try f.create(engine,"",3,false,argTypeMessage,&.{inputs.messages.invalid_arg_type,inputs.messages.determine_specific_type}));
    const codes = try tty_errors.create(engine,.{ .invalid_fd_message=inputs.messages.invalid_fd,.invalid_arg_type_message=argument_message,.out_of_range_message=inputs.messages.out_of_range,.require=inputs.require }); errdefer codes.deinit(engine);
    const type_error = try h.get(&s, try @import("native_node_stream.zig").owner(engine), "TypeError");
    const range_error = try h.get(&s, try @import("native_node_stream.zig").owner(engine), "RangeError");
    const error_class = try h.get(&s, try @import("native_node_stream.zig").owner(engine), "Error");
    const hidden_argument = try hide(&s,codes.invalid_arg_type,type_error,error_class);
    const hidden_range = try hide(&s,codes.out_of_range,range_error,error_class);
    const marker = try h.get(&s, try @import("native_node_system_errors.zig").registry(engine), "marker");
    const value_message = try s.own(try f.create(engine,"",2,false,argValueMessage,&.{inputs.internal_inspect}));
    const arg_value = try register(&s,type_error,"ERR_INVALID_ARG_VALUE",value_message,false,marker);
    const cursor = try register(&s,type_error,"ERR_INVALID_CURSOR_POS",try s.text("Cannot set cursor row without setting its column"),true,marker);
    const validator = try makeValidateFunction(&s,hidden_argument,error_class);
    return .{ .codes=codes,.tty=view(engine,codes,hidden_argument,hidden_range),.util=view(engine,codes,hidden_argument,codes.out_of_range),.invalid_arg_value=c.JS_DupValue(engine.context,arg_value),.invalid_cursor_pos=c.JS_DupValue(engine.context,cursor),.validate_function=c.JS_DupValue(engine.context,validator) };
}
fn argTypeMessage(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine); var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    if (try h.same(&s,h.arg(args,1),"number")) return c.JS_DupValue(engine.context,try h.call(&s,roots[0],receiver,args));
    if (!try h.same(&s,h.arg(args,1),"Function") or !try h.same(&s,h.arg(args,0),"callback")) return error.RequiredAdditionalReadlineArgumentTypeProfile;
    const actual = try h.call(&s,roots[1],c.pi_js_undefined(),&.{h.arg(args,2)});
    return c.JS_DupValue(engine.context,try h.binary(&s,.add,try s.text("The \"callback\" argument must be of type function. Received "),actual));
}
fn validateFunctionRaw(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine); var s: v.Scope = .{ .engine=engine }; defer s.deinit();
    if (!c.JS_IsFunction(engine.context,h.arg(args,0))) return h.throwValue(engine,try h.construct(&s,roots[0],&.{h.arg(args,1),try s.text("Function"),h.arg(args,0)}));
    return c.pi_js_undefined();
}
fn makeValidateFunction(s:*v.Scope,invalid_arg:c.JSValue,error_class:c.JSValue)!c.JSValue{
    const raw=try s.own(try f.create(s.engine,"",2,false,validateFunctionRaw,&.{invalid_arg}));
    const capture=try h.get(s,error_class,"captureStackTrace");
    if(!c.JS_IsFunction(s.engine.context,capture))return error.RequiredActualNativeErrorCaptureStackTrace;
    const lexical=try s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context,c.pi_js_null())));
    const wrapper=try s.own(try f.create(s.engine,"wrappedFn",0,true,validateFunctionWrapped,&.{raw,error_class,capture,lexical}));
    try h.set(s,wrapper,"withoutStackTrace",raw);try h.put(s.engine,lexical,"wrapper",wrapper);return wrapper;
}
fn validateFunctionWrapped(engine:*v.em.Engine,receiver:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    try h.pending(engine);var s:v.Scope=.{.engine=engine};defer s.deinit();
    const generation=engine.native_allocation_generation;
    const result=runValidateFunctionWrapped(&s,receiver,args,roots,generation) catch |err| return retireValidationFailure(&s,err,generation);
    return c.JS_DupValue(engine.context,result);
}
fn runValidateFunctionWrapped(s:*v.Scope,receiver:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue,generation:u64)!c.JSValue{
    const engine=s.engine;
    const result=h.call(s,roots[0],receiver,args) catch |err| {
        if(err!=error.JavaScriptException)return err;
        const captured=engine.captured_exception orelse return err;
        if(c.JS_IsUncatchableError(captured))return err;
        try @import("native_async_body.zig").rethrowRecognizedAllocation(engine,captured,generation);
        engine.captured_exception=null;
        const reason=try s.own(captured); // first inline slot, before any getter.
        if(s.truthy(try h.get(s,roots[1],"stackTraceLimit"))) _=try h.call(s,roots[2],c.pi_js_undefined(),&.{reason,try h.get(s,roots[3],"wrapper")});
        return h.throwValue(engine,reason);
    };
    return result;
}
/// Only this new catch boundary retires its private temporary roots here.
/// Shared Scope/Engine are unchanged. A caught native holder can finalize
/// while another Source getter/capture error is unwinding; protect first
/// ordinary/first actual fatal across EACH release rather than replaying it.
const ValidationCleanup=struct{
    engine:*v.em.Engine,selected:?c.JSValue=null,fatal:bool=false,
    fn currentFatal(self:*ValidationCleanup,reason:c.JSValue,generation:u64)bool{
        if(c.JS_IsUncatchableError(reason))return true;
        const tag=c.pi_js_native_allocation_error_generation(reason);const distance=tag-%generation;
        if(tag==0 or distance==0 or distance>self.engine.native_allocation_generation-%generation)return false;
        c.JS_SetUncatchableError(self.engine.context,reason);return true;
    }
    fn select(self:*ValidationCleanup,reason:c.JSValue,generation:u64)?c.JSValue{
        const fatal=self.currentFatal(reason,generation);
        if(self.selected==null){self.selected=reason;self.fatal=fatal;return null;}
        if(!self.fatal and fatal){const old=self.selected;self.selected=reason;self.fatal=true;return old;}
        return reason;
    }
    fn collect(self:*ValidationCleanup,generation:u64)void{
        const pending:?c.JSValue=if(c.JS_HasException(self.engine.context))c.JS_GetException(self.engine.context)else null;
        const captured=self.engine.captured_exception;self.engine.captured_exception=null;
        var retired:[2]?c.JSValue=.{null,null};
        if(pending)|reason|retired[0]=self.select(reason,generation);
        if(captured)|reason|retired[1]=self.select(reason,generation);
        for(retired)|value|if(value)|reason|self.release(reason);
    }
    fn release(self:*ValidationCleanup,reason:c.JSValue)void{
        const generation=self.engine.native_allocation_generation;self.engine.freeValue(reason);self.collect(generation);
    }
};
fn retireValidationFailure(s:*v.Scope,err:anyerror,generation:u64)anyerror{
    const engine=s.engine;var cleanup:ValidationCleanup=.{.engine=engine};
    const pending:?c.JSValue=if(c.JS_HasException(engine.context))c.JS_GetException(engine.context)else null;
    const captured=engine.captured_exception;engine.captured_exception=null;
    var history:?c.JSValue=null;
    if(pending)|reason|{_=cleanup.select(reason,generation);history=captured;}else if(err==error.JavaScriptException){if(captured)|reason|_=cleanup.select(reason,generation);}else history=captured;
    if(err==error.OutOfMemory){const before=engine.native_allocation_generation;_=engine.throwNativeOutOfMemory();cleanup.collect(before);}
    if(history)|reason|cleanup.release(reason);
    const count=s.inline_count;s.inline_count=0;
    for(s.inline_values[0..count])|value|cleanup.release(value);
    const values=s.values.items;s.values.items.len=0;
    for(values)|value|cleanup.release(value);
    if(cleanup.selected)|reason|{
        cleanup.selected=null;
        _=engine.checked(c.JS_Throw(engine.context,reason)) catch |actual|return actual;
        unreachable;
    }
    return err;
}
fn argValueMessage(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine); var s: v.Scope = .{ .engine=engine }; defer s.deinit();
    const name = h.arg(args,0); if (!c.JS_IsString(name)) return error.RequiredActualStringReadlineArgumentName;
    var inspected = try h.invoke(&s,roots[0],"inspect",&.{h.arg(args,1)});
    if (!c.JS_IsString(inspected)) return error.RequiredActualStringReadlineValueInspection;
    const units = try @import("native_utf16.zig").unitsAlloc(engine,inspected); defer engine.gpa.free(units);
    if (units.len > 128) inspected = try h.binary(&s,.add,try s.own(try @import("native_utf16.zig").string(engine,units[0..128])),try s.text("..."));
    const name_units = try @import("native_utf16.zig").unitsAlloc(engine,name); defer engine.gpa.free(name_units);
    const kind = if (std.mem.indexOfScalar(u16,name_units,'.') != null) "property" else "argument";
    const reason = if (c.JS_IsUndefined(h.arg(args,2))) try s.text("is invalid") else h.arg(args,2);
    var result = try h.binary(&s,.add,try s.text("The "),try s.text(kind));
    result = try h.binary(&s,.add,result,try s.text(" '")); result = try h.binary(&s,.add,result,name); result = try h.binary(&s,.add,result,try s.text("' "));
    result = try h.binary(&s,.add,result,try text(&s,reason)); result = try h.binary(&s,.add,result,try s.text(". Received ")); result = try h.binary(&s,.add,result,inspected);
    return c.JS_DupValue(engine.context,result);
}
