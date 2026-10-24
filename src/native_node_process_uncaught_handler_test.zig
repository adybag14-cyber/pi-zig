//! Controls for the complete private execution.js uncaught-handler declarations.
//! Required async-hook/require callbacks are explicit observable VM probes;
//! these controls do not qualify native Message/report/exit or scheduling.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const bootstrap = @import("extensions/native_node_argument_bootstrap.zig");
const registration = @import("extensions/native_node_string_error_registration.zig");
const errors = @import("extensions/native_node_argument_errors.zig");
const owner = @import("extensions/native_node_process_uncaught_handler.zig");
const functions = @import("extensions/native_node_module_callable.zig");
const c = a.c;
const owner_key = "pi-native:private/process-uncaught-handler";

const Fixture = struct {
    engine: *a.v.em.Engine = undefined,
    environment: std.process.Environ.Map = undefined,
    engine_alive: bool = false,
    environment_alive: bool = false,
    prepared: ?bootstrap.Prepared = null,
    capture_error: c.JSValue = undefined,
    exported: c.JSValue = undefined,
    first_fatal: c.JSValue = undefined,
    fn init(self: *Fixture, install_owner: bool) !void {
        return self.initUsing(std.testing.allocator, install_owner);
    }
    fn initUsing(self: *Fixture, allocator: std.mem.Allocator, install_owner: bool) !void {
        self.* = .{};
        self.environment = .init(std.testing.allocator);
        self.environment_alive = true;
        errdefer self.deinit();
        self.engine = try a.v.em.Engine.init(allocator, .{});
        self.engine_alive = true;
        self.capture_error = c.pi_js_undefined();
        self.exported = c.pi_js_undefined();
        self.first_fatal = c.pi_js_undefined();
        self.engine.host_control_context = self;
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine,
            std.testing.io, &self.environment, &.{"native-uncaught-handler-control"});
        try @import("extensions/native_node_os.zig").install(self.engine);
        self.prepared = try bootstrap.prepare(self.engine);
        self.capture_error = try a.expression(self.engine, captureErrorBody, .{self});
        try self.publish("CaptureAlreadySet", self.capture_error);
        try self.publish("InvalidArgumentType", self.prepared.?.arguments.invalid_arg_type);
        try self.engine.bindFunction("uncaughtNativeFatal", rawFatal, 0);
        try self.engine.bindFunction("uncaughtDropOwner", dropOwner, 0);
        try self.run(
            \\ "use strict";
            \\globalThis.trace=[];globalThis.ids=[];globalThis.afterEnabled=false;globalThis.handled=false;
            \\globalThis.toggle=new Uint32Array([1]);process.report={reportOnUncaughtException:true};
            \\process._exiting=false;process.exitCode=undefined;
            \\process.emit=function(name,...args){trace.push([name,...args]);return name==='uncaughtException'?handled:false};
            \\globalThis.timerModule={setImmediate:function(fn){trace.push(['immediate',this,fn]);return {unused:true}}};
            \\globalThis.requireDependency=function(name){trace.push(['require',name,this]);return timerModule};
            \\globalThis.hooks={
            \\clearDefaultTriggerAsyncId:function(){trace.push(['clearTrigger',this])},
            \\executionAsyncId:function(){const value=ids.shift();trace.push(['executionId',value,this]);return value},
            \\clearAsyncIdStack:function(){trace.push(['clearStack',this])},
            \\hasAsyncIdStack:function(){trace.push(['hasStack',this]);return ids.length>0},
            \\afterHooksExist:function(){trace.push(['afterExists',this]);return afterEnabled},
            \\emitAfter:function(id){trace.push(['after',id,this])},
            \\popAsyncContext:function(id){trace.push(['pop',id,this])}};
        );
        if (install_owner) try self.install();
    }
    fn install(self: *Fixture) !void {
        self.exported = try a.expression(self.engine, ownerBody, .{self});
        try self.publish("U", self.exported);
        try self.run("globalThis.H=U.createOnGlobalUncaughtException();");
    }
    fn deinit(self: *Fixture) void {
        if (self.engine_alive) {
            self.engine.freeValue(self.exported);
            self.engine.freeValue(self.capture_error);
            self.engine.freeValue(self.first_fatal);
            if (self.prepared) |prepared| prepared.deinit(self.engine);
            self.engine.deinit();
            self.engine_alive = false;
        }
        if (self.environment_alive) { self.environment.deinit(); self.environment_alive = false; }
    }
    fn run(self: *Fixture, source: []const u8) !void {
        const value = try self.engine.eval(source, "native-uncaught-handler-control.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(value);
        try std.testing.expect(!c.JS_HasException(self.engine.context));
    }
    fn check(self: *Fixture, source: []const u8) !void {
        const value = try self.engine.eval(source, "native-uncaught-handler-control.js", c.JS_EVAL_TYPE_GLOBAL);
        defer self.engine.freeValue(value);
        try std.testing.expect(c.JS_IsStrictEqual(self.engine.context, value, c.JS_NewBool(self.engine.context, true)));
    }
    fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global);
        if (c.JS_DefinePropertyValueStr(self.engine.context, global, name,
            c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E) < 0)
            return error.ActualUncaughtControlPublicationRequired;
    }
    fn get(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, name));
    }
    fn reason(self: *Fixture) !c.JSValue {
        if (c.JS_HasException(self.engine.context)) return c.JS_GetException(self.engine.context);
        if (self.engine.captured_exception) |value| { self.engine.captured_exception = null; return value; }
        return error.ActualUncaughtControlReasonRequired;
    }
    fn balanced(self: *Fixture) !void {
        try std.testing.expectEqual(@as(usize, 0), self.engine.native_exception_diagnostics_suppressed);
        try std.testing.expect(self.engine.native_fatal_invocation == null);
    }
};
fn captureErrorBody(s: *a.Scope, fixture: *Fixture) !c.JSValue {
    const core = try s.own(a.duplicate(s.engine, try @import("extensions/native_node_stream.zig").owner(s.engine)));
    const registry = try s.own(a.duplicate(s.engine, try @import("extensions/native_node_system_errors.zig").registry(s.engine)));
    const prepared = fixture.prepared.?;
    const apply = try s.own(try errors.reflectApply(s.engine));
    const unshift = try s.own(try errors.arrayUnshift(s.engine));
    return a.duplicate(s.engine, try registration.register(s, try s.get(core, "Error"),
        "ERR_UNCAUGHT_EXCEPTION_CAPTURE_ALREADY_SET",
        "\x60process.setupUncaughtExceptionCapture()\x60 was called while a capture callback was already active",
        try s.get(registry, "marker"), prepared.assert_function, apply, prepared.internal_inspect, unshift));
}
fn ownerBody(s: *a.Scope, fixture: *Fixture) !c.JSValue {
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    const hooks = try s.get(global, "hooks");
    return owner.create(s.engine, .{
        .process = try s.get(global, "process"), .require = try s.get(global, "requireDependency"),
        .should_abort_on_uncaught_toggle = try s.get(global, "toggle"),
        .invalid_arg_type = fixture.prepared.?.arguments.invalid_arg_type,
        .capture_already_set = fixture.capture_error,
        .execution_async_id = try s.get(hooks, "executionAsyncId"),
        .clear_default_trigger_async_id = try s.get(hooks, "clearDefaultTriggerAsyncId"),
        .clear_async_id_stack = try s.get(hooks, "clearAsyncIdStack"),
        .has_async_id_stack = try s.get(hooks, "hasAsyncIdStack"),
        .after_hooks_exist = try s.get(hooks, "afterHooksExist"),
        .emit_after = try s.get(hooks, "emitAfter"),
        .pop_async_context = try s.get(hooks, "popAsyncContext"),
    });
}
fn current(context: ?*c.JSContext) *Fixture {
    const engine = a.v.em.Engine.fromContext(context.?);
    return @ptrCast(@alignCast(engine.host_control_context.?));
}
fn rawFatal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = current(context);
    _ = fixture.engine.throwNativeOutOfMemoryFatal();
    if (c.JS_HasException(fixture.engine.context)) {
        const value = c.JS_GetException(fixture.engine.context);
        if (c.JS_IsUndefined(fixture.first_fatal)) fixture.first_fatal = a.duplicate(fixture.engine, value);
        fixture.engine.freeValue(value);
    }
    return c.pi_js_undefined();
}
fn dropOwner(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = current(context);
    var completion = a.owned.Completion.initVoid(fixture.engine, {});
    if (fixture.engine.native_module_values.fetchRemove(owner_key)) |removed| completion.release(removed.value);
    completion.finishVoid() catch |err| return functions.failure(fixture.engine, err, 0);
    return c.pi_js_undefined();
}

test "native uncaught handler original declarations preserve callable metadata and fresh anonymous arrows" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\const names=['setUncaughtExceptionCaptureCallback','hasUncaughtExceptionCaptureCallback','createOnGlobalUncaughtException'];
        \\if(JSON.stringify(Object.keys(U))!==JSON.stringify(names))throw Error('exported declarations');
        \\for(const [i,n] of names.entries()){const f=U[n];if(f.name!==n||f.length!==(i===0?1:0)||Object.getPrototypeOf(f)!==Function.prototype||!Object.hasOwn(f,'prototype'))throw Error('ordinary declaration metadata')}
        \\const second=U.createOnGlobalUncaughtException();if(second===H||H.name!==''||H.length!==2||Object.hasOwn(H,'prototype'))throw Error('fresh anonymous arrow');
        \\let rejected=false;try{Reflect.construct(H,[])}catch(e){rejected=e instanceof TypeError}return rejected;
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler initial null capture reset writes the stored false report flag" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\if(U.hasUncaughtExceptionCaptureCallback()!==false||toggle[0]!==1||process.report.reportOnUncaughtException!==true)throw Error('initial');
        \\if(U.setUncaughtExceptionCaptureCallback(null)!==undefined)throw Error('null result');
        \\return U.hasUncaughtExceptionCaptureCallback()===false&&toggle[0]===1&&process.report.reportOnUncaughtException===false;
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler capture receives the original ordinary state and saved report flag is strict true" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\for(const flag of [true,1,{},false,undefined]){
        \\ process.report={reportOnUncaughtException:flag};let state;
        \\ U.setUncaughtExceptionCaptureCallback(function(reason){state=this;if(reason!==flag)throw Error('reason')});
        \\ if(toggle[0]!==0||process.report.reportOnUncaughtException!==false||H(flag,false)!==true)throw Error('capture');
        \\ if(Object.getPrototypeOf(state)!==Object.prototype||JSON.stringify(Object.keys(state))!=='["captureFn","reportFlag"]')throw Error('ordinary literal');
        \\ for(const key of ['captureFn','reportFlag']){const d=Object.getOwnPropertyDescriptor(state,key);if(!d.writable||!d.enumerable||!d.configurable)throw Error('literal descriptor')}
        \\ U.setUncaughtExceptionCaptureCallback(null);if(process.report.reportOnUncaughtException!==(flag===true))throw Error('strict saved flag');
        \\}return toggle[0]===1&&!U.hasUncaughtExceptionCaptureCallback();
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler invalid callback uses the actual argument error graph before any state read" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\for(const value of [undefined,1,{},[],Symbol('bad'),true]){
        \\ let reason;try{U.setUncaughtExceptionCaptureCallback(value)}catch(e){reason=e}
        \\ if(!(reason instanceof InvalidArgumentType)||!(reason instanceof TypeError)||reason.code!=='ERR_INVALID_ARG_TYPE'||!reason.message.includes('"fn"'))throw Error('actual argument class');
        \\ if(U.hasUncaughtExceptionCaptureCallback()||toggle[0]!==1)throw Error('validation changed state');
        \\}return true;
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler duplicate registration uses the required canonical capture error constructor" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\const first=()=>{};U.setUncaughtExceptionCaptureCallback(first);let reason;
        \\try{U.setUncaughtExceptionCaptureCallback(()=>{})}catch(e){reason=e}
        \\return reason instanceof CaptureAlreadySet&&reason instanceof Error&&reason.code==='ERR_UNCAUGHT_EXCEPTION_CAPTURE_ALREADY_SET'&&reason.constructor===Error&&reason.message==='`process.setupUncaughtExceptionCapture()` was called while a capture callback was already active'&&U.hasUncaughtExceptionCaptureCallback();
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler class callback passes typeof function then fails at its actual call" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\U.setUncaughtExceptionCaptureCallback(class Capture{});let reason;try{H({},false)}catch(e){reason=e}
        \\return reason instanceof TypeError&&toggle[0]===0&&U.hasUncaughtExceptionCaptureCallback()&&trace.map(x=>x[0]).join('|')==='clearTrigger|uncaughtExceptionMonitor';
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler registration resolves the report receiver twice in original order" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\const seen=[],r1={get reportOnUncaughtException(){seen.push('read');return true}},r2={set reportOnUncaughtException(v){seen.push(['write',v])}};
        \\let reads=0;Object.defineProperty(process,'report',{configurable:true,get(){seen.push('report');return reads++===0?r1:r2}});
        \\U.setUncaughtExceptionCaptureCallback(()=>{});
        \\if(JSON.stringify(seen)!=='["report","read","report",["write",false]]')throw Error('two report reads');
        \\U.setUncaughtExceptionCaptureCallback(null);return JSON.stringify(seen.slice(4))==='["report",["write",true]]';
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler null reset resolves its left report receiver before the mutable reportFlag getter" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\let state;U.setUncaughtExceptionCaptureCallback(function(){state=this});H({},false);
        \\const seen=[],report={set reportOnUncaughtException(value){seen.push(['write',value])}};
        \\Object.defineProperty(process,'report',{configurable:true,get(){seen.push('report');return report}});
        \\Object.defineProperty(state,'reportFlag',{configurable:true,get(){seen.push('flag');return 'saved'}});
        \\U.setUncaughtExceptionCaptureCallback(null);
        \\return state.captureFn===null&&toggle[0]===1&&JSON.stringify(seen)==='["report","flag",["write","saved"]]';
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler report lookup failure retains the already assigned capture and toggle" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\const reason={};Object.defineProperty(process,'report',{configurable:true,get(){throw reason}});
        \\let caught;try{U.setUncaughtExceptionCaptureCallback(()=>{})}catch(e){caught=e}
        \\return caught===reason&&toggle[0]===0&&U.hasUncaughtExceptionCaptureCallback();
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler invalid type precedes duplicate and hostile capture getters" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\let state;U.setUncaughtExceptionCaptureCallback(function(){state=this});H({},false);
        \\let reads=0;Object.defineProperty(state,'captureFn',{configurable:true,get(){reads++;throw Error('must not read')}});
        \\let reason;try{U.setUncaughtExceptionCaptureCallback(1)}catch(e){reason=e}
        \\return reason?.code==='ERR_INVALID_ARG_TYPE'&&reads===0;
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler monitor uses the live process receiver and fromPromise truthiness without coercion" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\handled=true;const reason={},from={get [Symbol.toPrimitive](){throw Error('coercion')}},calls=[];
        \\process.emit=function(...args){calls.push([this,...args]);return true};
        \\if(H(reason,from)!==true)throw Error('handled');
        \\return calls.length===2&&calls[0][0]===process&&calls[0][1]==='uncaughtExceptionMonitor'&&calls[0][2]===reason&&calls[0][3]==='unhandledRejection'&&calls[1][0]===process&&calls[1][1]==='uncaughtException'&&calls[1][2]===reason;
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler monitor can register the capture used by the subsequent live branch" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\const reason={},seen=[];process.emit=function(name,er,type){seen.push(name);if(name==='uncaughtExceptionMonitor')U.setUncaughtExceptionCaptureCallback(function(value){seen.push(value===reason?'capture':'wrong')});return false};
        \\return H(reason,false)===true&&seen.join('|')==='uncaughtExceptionMonitor|capture';
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler capture branch performs two live gets and calls the second with state receiver" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\let state;U.setUncaughtExceptionCaptureCallback(function(){state=this});H({},false);
        \\let gets=0,first=0,second=0;const reason={};Object.defineProperty(state,'captureFn',{configurable:true,get(){gets++;return gets===1?function(){first++}:function(er){if(this!==state||er!==reason)throw Error('capture receiver');second++}}});
        \\return H(reason,false)===true&&gets===2&&first===0&&second===1;
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler null capture getter selects the uncaught emitter without a second get" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\let state;U.setUncaughtExceptionCaptureCallback(function(){state=this});H({},false);
        \\let gets=0;Object.defineProperty(state,'captureFn',{configurable:true,get(){gets++;return null}});handled=true;trace=[];
        \\return H({},false)===true&&gets===1&&trace.filter(x=>x[0]==='uncaughtException').length===1;
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler capture return values remain ignored without thenable assimilation" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\let reads=0;const thenable={get then(){reads++;throw Error('must not await')}};
        \\U.setUncaughtExceptionCaptureCallback(()=>thenable);return H({},true)===true&&reads===0&&trace.filter(x=>x[0]==='uncaughtException').length===0;
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler monitor throw propagates before capture or unhandled processing" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\const reason={};process.emit=function(){throw reason};let caught;try{H({},false)}catch(e){caught=e}
        \\return caught===reason&&trace.map(x=>x[0]).join('|')==='clearTrigger'&&!process._exiting;
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler capture throw propagates before timers and after hooks" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\const reason={};U.setUncaughtExceptionCaptureCallback(()=>{throw reason});trace=[];
        \\let caught;try{H({},false)}catch(e){caught=e}return caught===reason&&trace.map(x=>x[0]).join('|')==='clearTrigger|uncaughtExceptionMonitor'&&U.hasUncaughtExceptionCaptureCallback();
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler unhandled false marks exiting sets code one and emits exit once" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\const reason={};if(H(reason,false)!==false)throw Error('unhandled result');
        \\const tags=trace.map(x=>x[0]);const exit=trace.find(x=>x[0]==='exit');
        \\return tags.join('|')==='clearTrigger|uncaughtExceptionMonitor|uncaughtException|exit'&&process._exiting===true&&process.exitCode===1&&exit.length===2&&exit[1]===1;
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler truthy exiting skips all further exit writes without coercion" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\process._exiting={get [Symbol.toPrimitive](){throw Error('coercion')}};process.exitCode=99;
        \\if(H({},false)!==false)throw Error('unhandled');return process.exitCode===99&&trace.map(x=>x[0]).join('|')==='clearTrigger|uncaughtExceptionMonitor|uncaughtException';
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler only the original exit try block swallows its ordinary abrupt completions" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\for(let stage=0;stage<5;stage++){
        \\ const reason={},seen=[];let exiting=false;
        \\ Object.defineProperty(process,'_exiting',{configurable:true,get(){seen.push('get');if(stage===0)throw reason;return exiting},set(value){seen.push('set');if(stage===1)throw reason;exiting=value}});
        \\ Object.defineProperty(process,'exitCode',{configurable:true,set(value){seen.push('code:'+value);if(stage===2)throw reason}});
        \\ let reads=0;Object.defineProperty(process,'emit',{configurable:true,get(){reads++;if(stage===4&&reads===3)throw reason;return function(name){seen.push(name);if(stage===3&&name==='exit')throw reason;return false}}});
        \\ trace=[];if(H({},false)!==false)throw Error('exit catch result');
        \\ if(trace.map(x=>x[0]).join('|')!=='clearTrigger')throw Error('continued into timers');
        \\ if(stage<2&&seen.some(x=>x.startsWith('code:')))throw Error('continued past earlier failure');
        \\ if(stage===2&&seen.includes('exit'))throw Error('continued past code setter');
        \\}return true;
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler timers require and live setImmediate retain their original receiver and noop identity" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\handled=true;const seen=[];Object.defineProperty(timerModule,'setImmediate',{configurable:true,get(){seen.push('get');return function(fn){if(this!==timerModule)throw Error('receiver');seen.push(fn);if(fn.name!=='noop'||fn.length!==0||!Object.hasOwn(fn,'prototype')||fn()!==undefined)throw Error('original noop');return {get then(){throw Error('not awaited')}}}}});
        \\H({},false);H({},true);return seen.length===4&&seen[0]==='get'&&seen[2]==='get'&&seen[1]===seen[3]&&trace.filter(x=>x[0]==='require').every(x=>x[1]==='timers'&&x[2]===undefined);
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler after hooks use do while order strict zero and exact supplied async identities" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\handled=true;afterEnabled=true;ids=[0,5,'0',0n,-0,NaN];H({},false);
        \\const operations=trace.filter(x=>x[0]==='pop'||x[0]==='after');if(operations.map(x=>x[0]).join('|')!=='pop|after|after|after|pop|after')throw Error('strict zero');
        \\return operations[1][1]===5&&operations[2][1]==='0'&&operations[3][1]===0n&&Number.isNaN(operations[5][1])&&operations.every(x=>x[2]===undefined)&&trace.filter(x=>x[0]==='hasStack').length===6&&trace.at(-1)[0]==='clearStack';
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler false after hook predicate skips the loop but always clears the stack" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\handled=true;afterEnabled=false;ids=[4];if(H({},false)!==true)throw Error('handled');
        \\return ids.length===1&&trace.map(x=>x[0]).join('|')==='clearTrigger|uncaughtExceptionMonitor|uncaughtException|require|immediate|afterExists|clearStack';
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler null reset preserves earlier writes when the report setter is read only" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(function(){
        \\U.setUncaughtExceptionCaptureCallback(()=>{});Object.defineProperty(process.report,'reportOnUncaughtException',{value:false,writable:false,configurable:true});
        \\let reason;try{U.setUncaughtExceptionCaptureCallback(null)}catch(e){reason=e}
        \\return reason instanceof TypeError&&toggle[0]===1&&!U.hasUncaughtExceptionCaptureCallback();
        \\})()
    );
    try f.balanced();
}

test "native uncaught handler clear trigger abrupt completion precedes every process event" {
    var f: Fixture = undefined; try f.init(false); defer f.deinit();
    try f.run("globalThis.probeReason={};hooks.clearDefaultTriggerAsyncId=function(){throw probeReason};");
    try f.install();
    try f.check(
        \\(()=>{let reason;try{H({},false)}catch(e){reason=e}return reason===probeReason&&trace.length===0&&!process._exiting})()
    );
    try f.balanced();
}
test "native uncaught handler required timers failure propagates before after hooks" {
    var f: Fixture = undefined; try f.init(false); defer f.deinit();
    try f.run("handled=true;globalThis.probeReason={};requireDependency=function(name){if(name!=='timers')throw Error('module');throw probeReason};");
    try f.install();
    try f.check(
        \\(()=>{let reason;try{H({},false)}catch(e){reason=e}return reason===probeReason&&trace.map(x=>x[0]).join('|')==='clearTrigger|uncaughtExceptionMonitor|uncaughtException'})()
    );
    try f.balanced();
}
test "native uncaught handler after hook abrupt stages preserve the original short circuit" {
    var f: Fixture = undefined; try f.init(false); defer f.deinit();
    try f.run(
        \\globalThis.phase=0;globalThis.probeReason={};handled=true;
        \\hooks.afterHooksExist=function(){if(phase===0)throw probeReason;return true};
        \\hooks.executionAsyncId=function(){return phase===2?0:3};
        \\hooks.emitAfter=function(){if(phase===1)throw probeReason};
        \\hooks.popAsyncContext=function(){if(phase===2)throw probeReason};
        \\hooks.hasAsyncIdStack=function(){if(phase===3)throw probeReason;return false};
        \\hooks.clearAsyncIdStack=function(){trace.push(['clearStackAttempt']);if(phase===4)throw probeReason};
    );
    try f.install();
    try f.check(
        \\(()=>{for(phase=0;phase<5;phase++){trace=[];let reason;try{H({},false)}catch(e){reason=e}
        \\if(reason!==probeReason)throw Error('hook reason');if(trace.some(x=>x[0]==='clearStackAttempt')!==(phase===4))throw Error('cleanup after abrupt')}
        \\return true})()
    );
    try f.balanced();
}
test "native uncaught handler exact cached acquisition retains declarations and capture state" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run("U.setUncaughtExceptionCaptureCallback(()=>{});");
    const second = try a.expression(f.engine, ownerBody, .{&f}); defer f.engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, second, f.exported));
    try f.publish("secondOwner", second);
    try f.check("secondOwner===U&&secondOwner.hasUncaughtExceptionCaptureCallback()&&secondOwner.createOnGlobalUncaughtException===U.createOnGlobalUncaughtException");
    try f.balanced();
}
test "native uncaught handler conflicting actual inputs cannot reset or replace a cached owner" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run("U.setUncaughtExceptionCaptureCallback(()=>{});hooks.clearAsyncIdStack=function(){throw Error('replacement')};");
    try std.testing.expectError(error.ActualUncaughtOwnerInputsConflict, a.expression(f.engine, ownerBody, .{&f}));
    try f.check("U.hasUncaughtExceptionCaptureCallback()===true&&toggle[0]===0");
    try f.balanced();
}
test "native uncaught handler ordinary state is independent in distinct actual Engines" {
    var first: Fixture = undefined; try first.init(true); defer first.deinit();
    var second: Fixture = undefined; try second.init(true); defer second.deinit();
    try first.run("U.setUncaughtExceptionCaptureCallback(()=>{});");
    try first.check("U.hasUncaughtExceptionCaptureCallback()===true&&toggle[0]===0");
    try second.check("U.hasUncaughtExceptionCaptureCallback()===false&&toggle[0]===1");
    try second.run("U.setUncaughtExceptionCaptureCallback(null);");
    try first.check("process.report.reportOnUncaughtException===false&&U.hasUncaughtExceptionCaptureCallback()===true");
    try first.balanced(); try second.balanced();
}
test "native uncaught handler retained arrow owns dependencies through cache retirement and GC" {
    var f: Fixture = undefined; try f.init(false); defer f.deinit();
    const baseline = c.pi_js_native_memory_used(f.engine.native_memory_owner);
    try f.install();
    try f.run("globalThis.retainedHandler=H;delete globalThis.U;delete globalThis.H;uncaughtDropOwner();handled=true;");
    f.engine.freeValue(f.exported); f.exported = c.pi_js_undefined();
    c.JS_RunGC(f.engine.runtime);
    try std.testing.expect(!f.engine.native_module_values.contains(owner_key));
    try std.testing.expect(c.pi_js_native_memory_used(f.engine.native_memory_owner) > baseline);
    try f.check("retainedHandler({},true)===true&&trace.at(-1)[0]==='clearStack'");
    try f.run("delete globalThis.retainedHandler;trace=[];");
    c.JS_RunGC(f.engine.runtime);
    try std.testing.expectEqual(baseline, c.pi_js_native_memory_used(f.engine.native_memory_owner));
    try f.balanced();
}
test "native uncaught handler pending cold entry wins before allocator failure or publication" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var f: Fixture = undefined; try f.initUsing(failing.allocator(), false); defer f.deinit();
    const original = try f.engine.checked(c.JS_NewError(f.engine.context)); defer f.engine.freeValue(original);
    _ = c.JS_Throw(f.engine.context, c.JS_DupValue(f.engine.context, original));
    const index = failing.alloc_index; failing.fail_index = index;
    const result = a.expression(f.engine, ownerBody, .{&f});
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectError(error.JavaScriptException, result);
    try std.testing.expectEqual(index, failing.alloc_index);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, original, f.engine.captured_exception.?));
    try std.testing.expect(!f.engine.native_module_values.contains(owner_key));
    try f.balanced();
}
test "native uncaught handler actual cold allocation failure remains fatal and unpublished" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var f: Fixture = undefined; try f.initUsing(failing.allocator(), false); defer f.deinit();
    failing.fail_index = failing.alloc_index;
    const result = a.expression(f.engine, ownerBody, .{&f});
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectError(error.JavaScriptException, result);
    const observed = try f.reason(); defer f.engine.freeValue(observed);
    try std.testing.expect(c.JS_IsUncatchableError(observed));
    try std.testing.expect(!f.engine.native_module_values.contains(owner_key));
    try f.balanced();
}
test "native uncaught handler original exit catch cannot swallow an actual native fatal producer" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\globalThis.caughtFatal=false;globalThis.returnedFatal=false;
        \\process.emit=function(name){if(name==='exit')uncaughtNativeFatal();return false};
    );
    try std.testing.expectError(error.JavaScriptException, f.engine.eval(
        "try{H({},false);returnedFatal=true}catch(e){caughtFatal=true}", "uncaught-fatal-exit.js", c.JS_EVAL_TYPE_GLOBAL));
    const observed = try f.reason(); defer f.engine.freeValue(observed);
    try std.testing.expect(c.JS_IsUncatchableError(observed));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, observed, f.first_fatal));
    try f.check("caughtFatal===false&&returnedFatal===false&&process._exiting===true&&process.exitCode===1");
    try f.balanced();
}
test "native uncaught handler flagged returned DATA does not become a pending fatal event" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    const data = try f.engine.checked(c.JS_NewError(f.engine.context)); defer f.engine.freeValue(data);
    c.JS_SetUncatchableError(f.engine.context, data);
    try f.publish("flaggedData", data);
    try f.run("process.emit=function(){return flaggedData};");
    try f.check("H({},false)===true&&process._exiting===false&&trace.at(-1)[0]==='clearStack'");
    try std.testing.expect(f.engine.captured_exception == null);
    try f.balanced();
}
test "native uncaught handler fatal clear trigger prevents monitor and all later work" {
    var f: Fixture = undefined; try f.init(false); defer f.deinit();
    try f.run("hooks.clearDefaultTriggerAsyncId=function(){uncaughtNativeFatal()};globalThis.caughtFatal=false;");
    try f.install();
    try std.testing.expectError(error.JavaScriptException, f.engine.eval(
        "try{H({},false)}catch(e){caughtFatal=true}", "uncaught-fatal-clear.js", c.JS_EVAL_TYPE_GLOBAL));
    const observed = try f.reason(); defer f.engine.freeValue(observed);
    try std.testing.expect(c.JS_IsUncatchableError(observed));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, observed, f.first_fatal));
    try f.check("caughtFatal===false&&trace.length===0&&process._exiting===false");
    try f.balanced();
}
