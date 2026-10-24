//! Actual VM controls for the complete original debuglog timer consumer.
//! The fixture supplies controlled original private trace-binding inputs and
//! live process.hrtime observations for literal-source comparison. It creates
//! no production trace binding or hrtime provider and launches no Node process.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const debuglog = @import("extensions/native_node_debuglog.zig");
const timers = @import("extensions/native_node_debuglog_timers.zig");
const safe_array = @import("extensions/native_node_safe_array_iterator.zig");
const tty = @import("extensions/native_node_internal_tty.zig");
const colors = @import("extensions/native_node_util_colors.zig");
const internal = @import("extensions/native_node_internal_builtin_require.zig");
const bootstrap = @import("extensions/native_node_argument_bootstrap.zig");
const collections = @import("extensions/native_node_fs_collections.zig");
const publication = @import("extensions/native_node_fs_private_publication.zig");
const functions = @import("extensions/native_node_module_callable.zig");
const c = a.c;
const admissions = [_]internal.Binding{
    .{ .id = "os", .module_name = "node:os" },
    .{ .id = "internal/tty", .module_name = "internal/tty" },
    .{ .id = "internal/util/colors", .module_name = "internal/util/colors" },
};
const Options = struct {
    prepare_arguments: bool = true,
    prepare_require: bool = true,
    create_tty: bool = true,
    install_colors: bool = true,
    create_debug: bool = true,
    create_timers: bool = true,
};
const Fixture = struct {
    engine: *a.v.em.Engine = undefined,
    environment: std.process.Environ.Map = undefined,
    engine_alive: bool = false,
    environment_alive: bool = false,
    prepared: ?bootstrap.Prepared = null,
    native_require: c.JSValue = undefined,
    safe_map: c.JSValue = undefined,
    module_value: c.JSValue = undefined,
    timer_value: c.JSValue = undefined,
    trace_binding: c.JSValue = undefined,
    first_fatal: c.JSValue = undefined,
    probe_class: c.JSClassID = 0,
    retired: usize = 0,
    emit_fatal: bool = false,

    fn init(self: *Fixture, options: Options) !void {
        self.* = .{};
        self.environment = .init(std.testing.allocator); self.environment_alive = true;
        errdefer self.deinit();
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{}); self.engine_alive = true;
        self.native_require = c.pi_js_undefined(); self.safe_map = c.pi_js_undefined();
        self.module_value = c.pi_js_undefined(); self.first_fatal = c.pi_js_undefined();
        self.timer_value = c.pi_js_undefined(); self.trace_binding = c.pi_js_undefined();
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine,
            std.testing.io, &self.environment, &.{"native-debuglog-control"});
        try @import("extensions/native_node_os.zig").install(self.engine);
        self.engine.host_control_context = self;
        try self.engine.bindFunction("debugFatal", rawFatal, 0);
        try self.engine.bindFunction("debugEphemeral", ephemeral, 0);
        try self.engine.bindFunction("debugAcquire", rawAcquire, 0);
        try self.engine.bindFunction("timerAcquire", rawTimerAcquire, 0);
        const process_record = self.engine.native_module_values.get("node:process").?;
        const process = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, process_record, "default"));
        defer self.engine.freeValue(process); try self.publish("P", process);
        try self.publish("IP", self.engine.intrinsic_clone_operations);
        try self.evaluate(
            \\globalThis.lines=[];globalThis.warnings=[];
            \\Object.defineProperty(P,'pid',{value:17,writable:true,configurable:true});
            \\Object.defineProperty(P,'stderr',{value:{isTTY:false,write(s){lines.push(s)}},writable:true,configurable:true});
            \\P.emitWarning=function(s){warnings.push(s)};delete P.env.FORCE_COLOR;
            \\globalThis.reason=function(fn){try{fn()}catch(e){return e}throw Error('expected failure')};
        );
        self.safe_map = try collections.acquireSafeMap(self.engine);
        if (options.prepare_arguments) {
            self.prepared = try bootstrap.prepare(self.engine);
            try self.publish("IM", self.prepared.?.internal_inspect);
        }
        if (options.prepare_require) {
            self.native_require = try internal.acquire(self.engine, .{ .bindings = &admissions });
            try self.publish("Q", self.native_require);
        }
        if (options.create_tty) {
            const complete_tty = try tty.acquire(self.engine, .{ .require = self.native_require });
            defer self.engine.freeValue(complete_tty); try self.publish("TT", complete_tty);
        }
        if (options.install_colors) try self.installColors();
        if (options.create_debug) try self.createDebug();
        try self.evaluate(
            \\globalThis.events=[];globalThis.traceBuffer=new Uint8Array([1]);globalThis.clock=0;
            \\P.hrtime=function(previous){events.push(previous===undefined?'hr:start':'hr:delta');return previous===undefined?[clock++,0]:[0,1500000]};
            \\globalThis.TraceInput={getCategoryEnabledBuffer(category){events.push('buffer:'+category);return globalThis.bufferHook?bufferHook(category):traceBuffer},trace(phase,category,label,id){events.push(['trace',phase,category,label,id]);if(globalThis.traceHook)return traceHook(phase,category,label,id)}};
        );
        if (options.create_timers) try self.createTimers();
    }
    fn installColors(self: *Fixture) !void {
        // Exercise the complete actual module body and publish its real default
        // record. This fixture models an already completed genuine admission;
        // it does not claim the application's cold builtin loader is assembled.
        const process = try self.readGlobal("P"); defer self.engine.freeValue(process);
        const module = try self.engine.checked(c.JS_NewObject(self.engine.context)); defer self.engine.freeValue(module);
        const initial = try self.engine.checked(c.JS_NewObject(self.engine.context));
        if (c.JS_DefinePropertyValueStr(self.engine.context, module, "exports", initial, c.JS_PROP_C_W_E) < 0)
            return error.ActualDebuglogColorsModuleRequired;
        const completion = try colors.execute(self.engine, .{ .process = process, .module = module, .require = self.native_require });
        self.engine.freeValue(completion);
        const exports = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, module, "exports"));
        defer self.engine.freeValue(exports); try self.publish("Colors", exports);
        const record = try self.engine.defaultExports(exports);
        const published = try publication.publish(self.engine, "internal/util/colors", record);
        self.engine.freeValue(published);
    }
    fn createDebug(self: *Fixture) !void {
        const next = try debuglog.acquire(self.engine, .{ .require = self.native_require });
        self.engine.freeValue(self.module_value); self.module_value = next;
        try self.publish("NativeDebug", next);
        const initialize = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, next, "initializeDebugEnv"));
        defer self.engine.freeValue(initialize); try self.publish("I", initialize);
        const factory = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, next, "debuglog"));
        defer self.engine.freeValue(factory); try self.publish("D", factory);
        const iterator = try safe_array.acquire(self.engine);
        defer self.engine.freeValue(iterator); try self.publish("SA", iterator);
        try self.publish("SM", self.safe_map);
        try self.evaluate(@embedFile("fixtures/native-node-debuglog-timers-reference.js"));
    }
    fn createTimers(self: *Fixture) !void {
        const binding = try self.readGlobal("TraceInput"); defer self.engine.freeValue(binding);
        self.engine.freeValue(self.trace_binding); self.trace_binding = a.duplicate(self.engine, binding);
        const next = try timers.acquire(self.engine, .{ .debuglog_exports = self.module_value, .trace_events = binding });
        self.engine.freeValue(self.timer_value); self.timer_value = next;
        try self.publish("T", next);
    }
    fn select(self: *Fixture, reference: bool) !void {
        try self.evaluate(if (reference)
            "globalThis.A=makeOriginalDebugTimers(TraceInput);globalThis.initialize=A.initializeDebugEnv;"
        else "globalThis.A=T;globalThis.initialize=I;");
        try self.evaluate("globalThis.F=A.formatTime;globalThis.DT=A.debugWithTimer;");
    }
    fn evaluate(self: *Fixture, source: []const u8) !void {
        const value = try self.engine.eval(source, "native-debuglog-control.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(value); try std.testing.expect(!c.JS_HasException(self.engine.context));
    }
    fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context)); defer self.engine.freeValue(global);
        if (c.JS_DefinePropertyValueStr(self.engine.context, global, name,
            a.duplicate(self.engine, value), c.JS_PROP_C_W_E) < 0) return error.ActualDebuglogControlPublicationRequired;
    }
    fn readGlobal(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context)); defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, name));
    }
    fn takeReason(self: *Fixture) !c.JSValue {
        if (c.JS_HasException(self.engine.context)) return c.JS_GetException(self.engine.context);
        if (self.engine.captured_exception) |value| { self.engine.captured_exception = null; return value; }
        return error.ActualDebuglogControlReasonRequired;
    }
    fn balanced(self: *Fixture) !void {
        try std.testing.expectEqual(@as(usize, 0), self.engine.native_exception_diagnostics_suppressed);
        try std.testing.expect(self.engine.native_fatal_invocation == null);
    }
    fn deinit(self: *Fixture) void {
        self.emit_fatal = false;
        if (self.engine_alive) {
            if (self.prepared) |prepared| prepared.deinit(self.engine);
            self.engine.freeValue(self.timer_value); self.engine.freeValue(self.trace_binding);
            self.engine.freeValue(self.module_value); self.engine.freeValue(self.safe_map);
            self.engine.freeValue(self.native_require); self.engine.freeValue(self.first_fatal);
            self.engine.deinit(); self.engine_alive = false;
        }
        if (self.environment_alive) { self.environment.deinit(); self.environment_alive = false; }
    }
};
fn current(context: ?*c.JSContext) *Fixture {
    const engine = a.v.em.Engine.fromContext(context.?);
    return @ptrCast(@alignCast(engine.host_control_context.?));
}
fn publishFatal(fixture: *Fixture) void {
    _ = fixture.engine.throwNativeOutOfMemoryFatal();
    if (c.JS_HasException(fixture.engine.context)) {
        const value = c.JS_GetException(fixture.engine.context);
        if (c.JS_IsUndefined(fixture.first_fatal)) fixture.first_fatal = a.duplicate(fixture.engine, value);
        fixture.engine.freeValue(value);
    }
}
fn rawFatal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    publishFatal(current(context)); return c.pi_js_undefined();
}
fn rawAcquire(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = current(context);
    return debuglog.acquire(fixture.engine, .{ .require = fixture.native_require }) catch |err|
        functions.failure(fixture.engine, err, 0);
}
fn rawTimerAcquire(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = current(context);
    return timers.acquire(fixture.engine, .{ .debuglog_exports = fixture.module_value, .trace_events = fixture.trace_binding }) catch |err|
        functions.failure(fixture.engine, err, 0);
}
fn retireProbe(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const fixture: *Fixture = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    fixture.retired += 1;
    if (fixture.emit_fatal) publishFatal(fixture);
}
fn ephemeralBody(s: *a.Scope, fixture: *Fixture) !c.JSValue {
    if (fixture.probe_class == 0) {
        if (c.JS_NewClassID(s.engine.runtime, &fixture.probe_class) == 0) return error.OutOfMemory;
        const definition: c.JSClassDef = .{ .class_name = "Actual debuglog retirement probe", .finalizer = retireProbe };
        if (c.JS_NewClass(s.engine.runtime, fixture.probe_class, &definition) < 0) return error.OutOfMemory;
    }
    const generation = try s.beforeAllocation();
    const value = try s.checkedAllocation(c.JS_NewObjectClass(s.engine.context, fixture.probe_class), generation);
    _ = c.JS_SetOpaque(value, fixture);
    return a.duplicate(s.engine, value);
}
fn ephemeral(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = current(context);
    return a.expression(fixture.engine, ephemeralBody, .{fixture}) catch |err| functions.failure(fixture.engine, err, 0);
}
fn expectFatal(fixture: *Fixture, source: []const u8) !void {
    try std.testing.expectError(error.JavaScriptException, fixture.engine.eval(source, "native-debuglog-fatal.js", c.JS_EVAL_TYPE_GLOBAL));
    fixture.emit_fatal = false;
    const reason = try fixture.takeReason(); defer fixture.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, reason, fixture.first_fatal));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try fixture.balanced();
}


test "native debug timers preserve original callable shapes and defer category or timestamp observation" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\if(A.kNone!==1||A.kSkipLog!==2||A.kSkipTrace!==4)throw Error('constants');
            \\for(const [name,length] of [['formatTime',1],['time',4],['timeEnd',5],['timeLog',5],['debugWithTimer',2]])
            \\ if(A[name].name!==name||A[name].length!==length||!Object.hasOwn(A[name],'prototype'))throw Error(name);
            \\const timers=DT('mod',()=>{});
            \\for(const [name,length] of [['startTimer',2],['endTimer',2],['logTimer',3]]){
            \\ const d=Object.getOwnPropertyDescriptor(timers,name);
            \\ if(timers[name].name!==name||timers[name].length!==length||Object.hasOwn(timers[name],'prototype')||!d.writable||!d.enumerable||!d.configurable)throw Error('arrows/descriptors');
            \\}
            \\if(events.length||lines.length||warnings.length)throw Error('eager native inputs');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers format original thresholds rounding signed zero and nonfinite values" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\const pairs=[[0,'0ms'],[-0,'0ms'],[0.125,'0.125ms'],[-1.25,'-1.25ms'],[999.999,'999.999ms'],[1000,'1.000s'],[59999.9,'60.000s'],[60000,'1:00.000 (m:ss.mmm)'],[3599999.9,'59:60.000 (m:ss.mmm)'],[3600000,'1:00:00.000 (h:mm:ss.mmm)'],[3661001.125,'1:01:01.001 (h:mm:ss.mmm)'],[NaN,'NaNms'],[-Infinity,'-Infinityms'],[Infinity,'Infinity:NaN:NaN.undefined (h:mm:ss.mmm)']];
            \\for(const [input,expected]of pairs)if(F(input)!==expected)throw Error(String(input)+' '+F(input)+' '+expected);
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers preserve repeated original numeric coercion and Number receiver brands" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\const seen=[];const value={valueOf(){seen.push('number');return 3661001}};
            \\if(F(value)!=='1:01:01.001 (h:mm:ss.mmm)'||seen.length!==5)throw Error('numeric order');
            \\seen.length=0;const short={valueOf(){seen.push('number');return 1}};
            \\if(!(reason(()=>F(short)) instanceof TypeError)||seen.length!==1)throw Error('toFixed brand');
            \\if(F(new Number(42))!=='42ms')throw Error('boxed Number');
            \\for(const input of [1n,1001n,Symbol('ms')])if(!(reason(()=>F(input)) instanceof TypeError))throw Error('abrupt numeric input');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers use captured Number Math and string methods after guest replacement" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\const saved={floor:Math.floor,fixed:Number.prototype.toFixed,pad:String.prototype.padStart,split:String.prototype.split,number:Number};
            \\try{
            \\ Math.floor=()=>{throw Error('foreign floor')};Number.prototype.toFixed=()=>{throw Error('foreign fixed')};
            \\ String.prototype.padStart=()=>{throw Error('foreign pad')};String.prototype.split=()=>{throw Error('foreign split')};
            \\ globalThis.Number=()=>{throw Error('foreign constructor')};
            \\ if(F(3661001)!=='1:01:01.001 (h:mm:ss.mmm)'||F(7.5)!=='7.5ms')throw Error('capture');
            \\}finally{globalThis.Number=saved.number;Math.floor=saved.floor;Number.prototype.toFixed=saved.fixed;String.prototype.padStart=saved.pad;String.prototype.split=saved.split}
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers perform split object destructuring index zero before index one" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\const seen=[];const prior=Object.getOwnPropertyDescriptor(String.prototype,Symbol.split);
            \\try{
            \\ Object.defineProperty(String.prototype,Symbol.split,{configurable:true,value:function(text,limit){seen.push('split:'+text+':'+limit);return{get 0(){seen.push('zero');return{toString(){seen.push('seconds');return'9'}}},get 1(){seen.push('one');return'123'}}}});
            \\ if(F(3600000)!=='1:00:09.123 (h:mm:ss.mmm)')throw Error('split result');
            \\ if(JSON.stringify(seen)!=='["split:0.000:2","zero","one","seconds"]')throw Error('destructuring order '+JSON.stringify(seen));
            \\}finally{if(prior)Object.defineProperty(String.prototype,Symbol.split,prior);else delete String.prototype[Symbol.split]}
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers escape trace labels and emit begin before the timestamp" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\const store=new SM();A.time(store,'category','implementation',1,'label','a\\b"c');
            \\if(events.length!==2||events[0][0]!=='trace'||events[0][1]!==98||events[0][2]!=='category'||events[0][3]!==String.fromCharCode(97,92,92,98,92,34,99)||events[0][4]!==0||events[1]!=='hr:start')throw Error(JSON.stringify(events));
            \\if(store.size!==1||store.get('label')[0]!==0)throw Error('actual SafeMap');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers coerce labels before has and capture set before live hrtime" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\events=[];let selected;
            \\const label={[Symbol.toPrimitive](hint){events.push('label:'+hint);return'log'}};
            \\const traceLabel={[Symbol.toPrimitive](hint){events.push('trace:'+hint);return'trace'}};
            \\const store={get has(){events.push('get:has');return function(k){if(this!==store||k!=='log')throw Error('has');events.push('has');return false}},get set(){events.push('get:set');return function(k,v){if(this!==store)throw Error('set receiver');events.push('set');selected=v}}};
            \\Object.defineProperty(P,'hrtime',{configurable:true,get(){events.push('get:hr');return function(){if(this!==P||arguments.length)throw Error('hr');events.push('hr');return 17}}});
            \\A.time(store,'cat','impl',4,label,traceLabel);
            \\if(selected!==17||JSON.stringify(events)!=='["label:string","trace:string","get:has","has","get:set","get:hr","hr","set"]')throw Error(JSON.stringify(events));
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers default log label applies only to undefined and Symbols stop before has" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\const store=new SM();A.time(store,'cat','impl',4);A.time(store,'cat','impl',4,null);A.time(store,'cat','impl',4,0);
            \\if(!store.has('default')||!store.has('null')||!store.has('0'))throw Error('default');
            \\events=[];const guarded={has(){throw Error('should not reach has')}};
            \\if(!(reason(()=>A.time(guarded,'cat','impl',4,Symbol('x')))instanceof TypeError))throw Error('label Symbol');
            \\if(!(reason(()=>A.time(guarded,'cat','impl',4,'x',Symbol('y')))instanceof TypeError))throw Error('trace Symbol');
            \\if(events.length)throw Error('early side effect');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers duplicate warning returns before flag coercion trace and clock" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\const store=new SM([['x',17]]);let coerced=0;const implementation={toString(){coerced++;return'custom'}};
            \\A.time(store,'cat',implementation,Symbol('flags'),'x');
            \\if(coerced!==1||warnings[0]!=="Label 'x' already exists for custom"||events.length||store.get('x')!==17)throw Error('duplicate order');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers direct time always stores while only the trace bit controls begin" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\for(const flags of [1,2,4,6]){
            \\ events=[];const store=new SM();A.time(store,'cat','impl',flags,'x');
            \\ const kinds=events.map(x=>Array.isArray(x)?x[1]:x);
            \\ if(JSON.stringify(kinds)!==(flags===1||flags===2?'[98,"hr:start"]':'["hr:start"]')||!store.has('x'))throw Error('direct flags '+flags);
            \\}
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers missing end label warns then emits end and deletes" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\events=[];P.emitWarning=function(text){events.push(text)};
            \\const store={get(k){events.push('get:'+k);return undefined},delete(k){events.push('delete:'+k)}};
            \\A.timeEnd(store,'cat','impl',1,()=>{throw Error('unexpected log')},'x');
            \\if(JSON.stringify(events)!=='["get:x","No such label \'x\' for impl",["trace",101,"cat","x",0],"delete:x"]')throw Error(JSON.stringify(events));
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers elapsed arithmetic reads and coerces seconds before nanoseconds" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\events=[];const start={};P.hrtime=function(previous){if(this!==P||previous!==start)throw Error('actual argument');events.push('hr');return{get 0(){events.push('zero');return{valueOf(){events.push('seconds');return 1}}},get 1(){events.push('one');return{valueOf(){events.push('nanos');return 500000000}}}}};
            \\const store={get(k){events.push('get:'+k);return start},delete(k){events.push('delete:'+k)}};
            \\A.timeEnd(store,'cat','impl',1,function(label,formatted){events.push('log:'+arguments.length+':'+label+':'+formatted)},'x');
            \\if(JSON.stringify(events)!=='["get:x","hr","zero","seconds","one","nanos","log:2:x:1.500s",["trace",101,"cat","x",0],"delete:x"]')throw Error(JSON.stringify(events));
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers timeLog preserves optional argument arity and keeps the stored timestamp" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\const store=new SM([['x',[0,0]]]);const calls=[];
            \\for(const extra of [undefined,null,0,['tail']])A.timeLog(store,'cat','impl',4,function(label,formatted,args){calls.push([arguments.length,label,formatted,args])},'x',undefined,extra);
            \\if(calls.length!==4||calls[0].length!==4||calls[0][0]!==2||calls.slice(1).some(x=>x[0]!==3)||calls.some(x=>x[1]!=='x'||x[2]!=='1.5ms')||!store.has('x'))throw Error('arity/store');
            \\if(calls[1][3]!==null||calls[2][3]!==0||calls[3][3][0]!=='tail')throw Error('extra forwarding');
            \\events=[];A.timeLog(store,'cat','impl',3,()=>{throw Error('skip log')},'x');
            \\if(events.length!==1||events[0][1]!==110||store.size!==1)throw Error('instant');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers end flag combinations retain the original delete and logging order" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\for(const flags of [2,4,6]){
            \\ events=[];const store={get(){events.push('get');return[0,0]},delete(){events.push('delete')}};
            \\ A.timeEnd(store,'cat','impl',flags,()=>events.push('log'),'x');
            \\ const kinds=events.map(x=>Array.isArray(x)?x[1]:x);
            \\ const expected=flags===2?'[101,"delete"]':flags===4?'["get","hr:delta","log","delete"]':'["delete"]';
            \\ if(JSON.stringify(kinds)!==expected)throw Error('end flags '+flags+' '+JSON.stringify(kinds));
            \\}
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers a logger throw prevents end trace and deletion and preserves identity" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\const marker={},store=new SM([['x',[0,0]]]);events=[];
            \\if(reason(()=>A.timeEnd(store,'cat','impl',1,()=>{throw marker},'x'))!==marker)throw Error('logger identity');
            \\if(!store.has('x')||JSON.stringify(events)!=='["hr:delta"]')throw Error('continued after log failure');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers a trace throw occurs before start timestamp and after end logging" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\const marker={};traceHook=()=>{throw marker};
            \\let store=new SM();events=[];if(reason(()=>A.time(store,'cat','impl',1,'x'))!==marker||store.size||events.some(x=>x==='hr:start'))throw Error('start trace');
            \\store=new SM([['x',[0,0]]]);events=[];let logged=0;
            \\if(reason(()=>A.timeEnd(store,'cat','impl',1,()=>logged++,'x'))!==marker||logged!==1||!store.has('x')||events[0]!=='hr:delta'||events[1][1]!==101)throw Error('end trace');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers retain live two-step replaceAll and forward its result without extra coercion" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\const descriptor=Object.getOwnPropertyDescriptor(String.prototype,'replaceAll'),seen=[],last={};
            \\try{
            \\ Object.defineProperty(String.prototype,'replaceAll',{configurable:true,get(){seen.push('first get');return function(a,b){'use strict';seen.push(['first',this,a,b]);return{get replaceAll(){seen.push('second get');return function(a,b){seen.push(['second',a,b]);return last}}}}}});
            \\ const store=new SM();A.time(store,'cat','impl',1,'x','trace');
            \\ if(seen[0]!=='first get'||seen[1][0]!=='first'||seen[1][1]!=='trace'||seen[2]!=='second get'||seen[3][0]!=='second'||events[0][3]!==last)throw Error('chain');
            \\ if(seen[1][2]!=='\\'||seen[1][3]!=='\\\\'||seen[3][1]!=='"'||seen[3][2]!=='\\"')throw Error('escape operands');
            \\}finally{Object.defineProperty(String.prototype,'replaceAll',descriptor)}
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers retain the selected set method across hrtime reentry" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\events=[];let stored;const store={has(){return false},set(k,v){events.push('old set');stored=v}};
            \\P.hrtime=function(){store.set=()=>{throw Error('replacement set')};events.push('hr');return 43};
            \\A.time(store,'cat','impl',4,'x');
            \\if(stored!==43||JSON.stringify(events)!=='["hr","old set"]')throw Error('set reference');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers start trace reentry happens before either timestamp is stored" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\events=[];const store=new SM();let nested=false;
            \\traceHook=()=>{if(!nested){nested=true;A.time(store,'cat','impl',1,'x')}};
            \\A.time(store,'cat','impl',1,'x');
            \\if(store.get('x')[0]!==1||events.length!==4||events[0][1]!==98||events[1][1]!==98||events[2]!=='hr:start'||events[3]!=='hr:start')throw Error('trace reentry');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers uppercase the category once at construction with captured string methods" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\events=[];let conversions=0;const set={toString(){conversions++;return'mOd'}};
            \\const upper=String.prototype.toUpperCase,lower=String.prototype.toLowerCase;
            \\let timer;
            \\try{String.prototype.toUpperCase=String.prototype.toLowerCase=()=>{throw Error('foreign primordial')};timer=DT(set,()=>{});}
            \\finally{String.prototype.toUpperCase=upper;String.prototype.toLowerCase=lower}
            \\if(conversions!==1||events.length)throw Error('early category observation');
            \\initialize('mod');timer.startTimer('x');
            \\if(conversions!==1||events[0]!=='buffer:node,node.mod'||events[1][2]!=='node,node.mod')throw Error('category');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers leave testEnabled uninitialized until explicit initialization and then retry" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\let callbacks=0;const timer=DT('mod',()=>callbacks++);
            \\if(!(reason(()=>timer.startTimer('x'))instanceof TypeError)||events.length||callbacks)throw Error('uninitialized predicate');
            \\initialize('mod');timer.startTimer('x');
            \\if(callbacks!==1||events[0]!=='buffer:node,node.mod'||events.at(-1)!=='hr:start')throw Error('retry');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers invoke the init callback unconditionally even when both paths are disabled" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize(undefined);traceBuffer[0]=0;
            \\const timer=DT('mod',undefined);
            \\if(!(reason(()=>timer.startTimer('x'))instanceof TypeError)||events.length!==1||events[0]!=='buffer:node,node.mod')throw Error('callback default was invented');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers skip timestamps labels and output only for the original both-disabled condition" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize(undefined);traceBuffer[0]=0;let callbacks=0;const timer=DT('mod',()=>callbacks++);
            \\const poison={toString(){throw Error('disabled label')}};
            \\timer.startTimer(poison);timer.logTimer(poison);timer.endTimer(poison);
            \\if(callbacks!==3||events.length!==3||events.some(x=>typeof x!=='string'||!x.startsWith('buffer:'))||lines.length||warnings.length)throw Error('disabled branch');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers trace an enabled category without reading pid stderr or logging" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize(undefined);traceBuffer[0]=1;let callbacks=0;const timer=DT('mod',()=>callbacks++);
            \\Object.defineProperty(P,'pid',{configurable:true,get(){throw Error('trace-only pid')}});
            \\Object.defineProperty(P,'stderr',{configurable:true,get(){throw Error('trace-only stderr')}});
            \\timer.startTimer('x');timer.endTimer('x');
            \\if(callbacks!==2||lines.length||events.filter(x=>Array.isArray(x)).map(x=>x[1]).join(',')!=='98,101'||events.filter(x=>x==='hr:start').length!==1||events.includes('hr:delta'))throw Error('trace-only');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers log through actual colors inspector and format with tracing disabled" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize('mod');traceBuffer[0]=0;const timer=DT('mod',()=>{});
            \\timer.startTimer('x');timer.endTimer('x');
            \\if(lines.length!==1||lines[0]!=='MOD 17 x: 1.5ms\n'||events.some(x=>Array.isArray(x))||events.filter(x=>x==='hr:delta').length!==1)throw Error('logging '+JSON.stringify(lines));
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers read the real shared enabled byte on every escaped internal call" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize(undefined);traceBuffer[0]=0;let callbacks=0,start,end,log;
            \\DT('mod',(s,e,l)=>{callbacks++;start=s;end=e;log=l}).startTimer('ignored');
            \\events=[];traceBuffer[0]=1;start('x');traceBuffer[0]=0;log('x');traceBuffer[0]=1;end('x');
            \\if(callbacks!==1||events.some(x=>typeof x==='string'&&x.startsWith('buffer:'))||events.filter(Array.isArray).map(x=>x[1]).join(',')!=='98,101'||events.filter(x=>x==='hr:start').length!==1)throw Error('live enabled byte');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers share one SafeMap per uppercase set across independent factories" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize('mod');traceBuffer[0]=0;const first=DT('mod',()=>{}),second=DT('MOD',()=>{});
            \\first.startTimer('x');second.startTimer('x');second.endTimer('x');
            \\if(warnings.length!==1||warnings[0]!=="Label 'x' already exists for debuglog.time"||lines[0]!=='MOD 17 x: 1.5ms\n')throw Error('shared labels');
            \\first.endTimer('x');
            \\if(warnings[1]!=="No such label 'x' for debuglog.timeEnd")throw Error('shared deletion');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers recheck the enabled byte after init callback changes it" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize(undefined);traceBuffer[0]=1;let callbacks=0;
            \\const timer=DT('mod',()=>{callbacks++;traceBuffer[0]=0});
            \\timer.startTimer('x');
            \\if(callbacks!==1||events.length!==1||events[0]!=='buffer:node,node.mod')throw Error('post-callback enabled check');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers retain initialized cells after a callback throw and retry the original callback" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize('mod');traceBuffer[0]=0;let failed=true,calls=0,start;const marker={};
            \\const timer=DT('mod',s=>{calls++;start=s;if(failed){failed=false;throw marker}});
            \\if(reason(()=>timer.startTimer('x'))!==marker||calls!==1)throw Error('callback identity');
            \\start('escaped');timer.endTimer('escaped');
            \\if(calls!==2||lines[0]!=='MOD 17 escaped: 1.5ms\n'||events.filter(x=>typeof x==='string'&&x.startsWith('buffer:')).length!==2)throw Error('callback-state retry');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers run init for every original arrow while escaped internals reuse captures" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize('mod');traceBuffer[0]=0;let callbacks=0,end;
            \\const timer=DT('mod',(_,e)=>{callbacks++;end=e});
            \\timer.startTimer('x');end('x');timer.startTimer('y');timer.endTimer('y');
            \\if(callbacks!==3||lines.length!==2||events.filter(x=>typeof x==='string'&&x.startsWith('buffer:')).length!==3)throw Error('wrapper replacement was invented');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers share original initializeDebugEnv state without retroactively changing escaped flags" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize('mod');traceBuffer[0]=0;let log;const timer=DT('mod',(_,__,l)=>log=l);
            \\timer.startTimer('x');initialize(undefined);log('x');const count=events.length;timer.logTimer('x');
            \\if(lines.length!==1||events.length!==count+1||events.at(-1)!=='buffer:node,node.mod')throw Error('shared testEnabled or flag capture');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers emit the original HTTP warning on each init before category observation" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize(undefined);traceBuffer[0]=0;events=[];
            \\P.emitWarning=function(message){events.push('warning');warnings.push(message)};
            \\const timer=DT('http',()=>events.push('callback'));
            \\timer.startTimer('x');timer.endTimer('x');
            \\if(JSON.stringify(events)!=='["warning","buffer:node,node.http","callback","warning","buffer:node,node.http","callback"]'||warnings.length!==2||!warnings[0].includes("'http'"))throw Error('warning order');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers observe current pid then two live stderr reads with write captured before format" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize('mod');traceBuffer[0]=0;const timer=DT('mod',()=>{});timer.startTimer('x');events=[];
            \\Object.defineProperty(P,'pid',{configurable:true,get(){events.push('pid');return 42}});
            \\let reads=0;Object.defineProperty(P,'stderr',{configurable:true,get(){events.push('stderr'+(++reads));if(reads===1)return{isTTY:false};return{get write(){events.push('write:get');return function(message){events.push('write:call');lines.push(message)}}}}});
            \\timer.endTimer('x');
            \\if(JSON.stringify(events)!=='["buffer:node,node.mod","hr:delta","pid","stderr1","stderr2","write:get","write:call"]'||lines[0]!=='MOD 42 x: 1.5ms\n')throw Error(JSON.stringify(events));
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers forward ordinary colors options to the actual inspector" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize('mod');traceBuffer[0]=0;const timer=DT('mod',()=>{});timer.startTimer('x');events=[];
            \\P.pid={[Symbol.for('nodejs.util.inspect.custom')](depth,options,inspector){events.push('inspect');const d=Object.getOwnPropertyDescriptor(options,'colors');if(!d||d.value!==false||!d.enumerable||!d.writable||!d.configurable||typeof inspector!=='function')throw Error('options');return'PID'}};
            \\Colors.shouldColorize=function(stream){events.push('colors');if(stream!==P.stderr)throw Error('actual stream');return false};
            \\timer.endTimer('x');
            \\if(events.indexOf('colors')>=events.indexOf('inspect')||lines[0]!=='MOD PID x: 1.5ms\n')throw Error('actual inspection');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers spread extra values through SafeArrayIterator without reading a guest iterator" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize('mod');traceBuffer[0]=0;const timer=DT('mod',()=>{});timer.startTimer('x');const seen=[];
            \\const extra={get length(){seen.push('length');return 2},get 0(){seen.push('zero');return'one'},get 1(){seen.push('one');return'two'},get [Symbol.iterator](){throw Error('guest iterator')}};
            \\timer.logTimer('x',undefined,extra);
            \\if(JSON.stringify(seen)!=='["length","zero","length","one","length"]'||lines[0]!=='MOD 17 x: 1.5ms\n one two')throw Error('SafeArrayIterator '+JSON.stringify(seen)+' '+JSON.stringify(lines));
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers keep formatter arguments ordered after selecting the second write method" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\initialize('mod');traceBuffer[0]=0;const timer=DT('mod',()=>{});timer.startTimer('x');const seen=[];
            \\let accesses=0;Object.defineProperty(P,'stderr',{configurable:true,get(){accesses++;if(accesses===1)return{isTTY:false};return{get write(){seen.push('write:get');return function(message){seen.push('write:call');lines.push(message)}}}}});
            \\const extra={[Symbol.for('nodejs.util.inspect.custom')](){seen.push('format:extra');return'TAIL'}};
            \\timer.logTimer('x',undefined,[extra]);
            \\if(JSON.stringify(seen)!=='["write:get","format:extra","write:call"]'||!lines[0].endsWith(' TAIL'))throw Error('write/format order');
            \\}
        );
        try f.balanced();
    }
}

test "native debug timers capture trace binding named imports once in original order" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{ .create_timers = false }); defer f.deinit();
        try f.evaluate(
            \\globalThis.captureEvents=[];
            \\globalThis.TraceInput={get getCategoryEnabledBuffer(){captureEvents.push('get:buffer');return category=>{captureEvents.push(category);return traceBuffer}},get trace(){captureEvents.push('get:trace');return phase=>captureEvents.push(phase)}};
        );
        if (!reference) try f.createTimers();
        try f.select(reference);
        try f.evaluate(
            \\{
            \\if(JSON.stringify(captureEvents)!=='["get:buffer","get:trace"]')throw Error('capture order');
            \\Object.defineProperty(TraceInput,'getCategoryEnabledBuffer',{value:()=>{throw Error('foreign buffer')}});
            \\Object.defineProperty(TraceInput,'trace',{value:()=>{throw Error('foreign trace')}});
            \\initialize(undefined);DT('mod',()=>{}).startTimer('x');
            \\if(JSON.stringify(captureEvents)!=='["get:buffer","get:trace","node,node.mod",98]')throw Error('captured dependencies');
            \\}
        );
        try f.balanced();
    }
}
test "native debug timers require the exact ordinary owner and reject foreign trace identity on reacquisition" {
    var f: Fixture = undefined; try f.init(.{ .create_timers = false }); defer f.deinit();
    try f.evaluate("globalThis.foreignDebug={...NativeDebug};globalThis.otherTrace={...TraceInput};");
    const foreign = try f.readGlobal("foreignDebug"); defer f.engine.freeValue(foreign);
    const binding = try f.readGlobal("TraceInput"); defer f.engine.freeValue(binding);
    try std.testing.expectError(error.ActualInitializedDebuglogOwnerIdentityChanged,
        timers.acquire(f.engine, .{ .debuglog_exports = foreign, .trace_events = binding }));
    try std.testing.expect(!f.engine.native_module_values.contains("pi-native:private/original-debuglog-timers"));
    try f.createTimers(); try f.evaluate("if(timerAcquire()!==T)throw Error('shared actual owner');");
    const other = try f.readGlobal("otherTrace"); defer f.engine.freeValue(other);
    try std.testing.expectError(error.ActualDebuglogTimerInputIdentityChanged,
        timers.acquire(f.engine, .{ .debuglog_exports = f.module_value, .trace_events = other }));
    try std.testing.expect(!f.engine.native_module_names.contains("internal/util/debuglog"));
    try std.testing.expect((try f.engine.requireBuiltin("internal/util/debuglog")) == null);
    try f.balanced();
}
test "native debug timers require actual prior SafeMap bootstrap and never supply a missing trace binding" {
    var f: Fixture = undefined; try f.init(.{ .create_timers = false }); defer f.deinit();
    const binding = try f.readGlobal("TraceInput"); defer f.engine.freeValue(binding);
    const removed = f.engine.native_module_values.fetchRemove("\x00native.fs.SafeMap").?;
    try std.testing.expectError(error.RequiredBootstrappedActualTimerSafeMap,
        timers.acquire(f.engine, .{ .debuglog_exports = f.module_value, .trace_events = binding }));
    f.engine.native_module_values.putAssumeCapacity("\x00native.fs.SafeMap", removed.value);
    try std.testing.expectError(error.JavaScriptException,
        timers.acquire(f.engine, .{ .debuglog_exports = f.module_value, .trace_events = c.pi_js_undefined() }));
    const reason = try f.takeReason(); defer f.engine.freeValue(reason); try f.publish("failure", reason);
    try f.evaluate("if(!(failure instanceof TypeError))throw Error('required trace binding');");
    try std.testing.expect(!f.engine.native_module_values.contains("pi-native:private/original-debuglog-timers"));
    try f.createTimers(); try f.balanced();
}
test "native debug timers preserve reentrant complete owner publication during trace import capture" {
    var f: Fixture = undefined; try f.init(.{ .create_timers = false }); defer f.deinit();
    try f.evaluate(
        \\globalThis.nested=false;globalThis.selectedInner;
        \\globalThis.TraceInput={get getCategoryEnabledBuffer(){if(!nested){nested=true;selectedInner=timerAcquire()}return ()=>traceBuffer},trace(){}};
    );
    try f.createTimers();
    try f.evaluate("if(selectedInner!==T||timerAcquire()!==T)throw Error('reentrant publication');");
    try f.balanced();
}
test "native debug timers propagate native fatal trace before timestamp storage in literal and native bodies" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate("globalThis.store=new SM();globalThis.traceHook=()=>debugFatal();");
        try expectFatal(&f, "A.time(store,'cat','impl',1,'x')");
        try f.evaluate("if(store.size||events.includes('hr:start'))throw Error('continued after fatal trace');");
    }
}
test "native debug timers retire an ignored trace return before timestamp storage" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate("globalThis.store=new SM();globalThis.traceHook=()=>debugEphemeral();");
        f.emit_fatal = true; try expectFatal(&f, "A.time(store,'cat','impl',1,'x')");
        try std.testing.expectEqual(@as(usize, 1), f.retired);
        try f.evaluate("if(store.size||events.includes('hr:start'))throw Error('trace return lifetime');");
    }
}
test "native debug timers retire missing-label warning returns before trace and delete" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate("globalThis.deleted=0;globalThis.store={get(){return undefined},delete(){deleted++}};P.emitWarning=()=>debugEphemeral();");
        f.emit_fatal = true; try expectFatal(&f, "A.timeEnd(store,'cat','impl',1,()=>{},'x')");
        try std.testing.expectEqual(@as(usize, 1), f.retired);
        try f.evaluate("if(deleted||events.length)throw Error('warning return lifetime');");
    }
}
test "native debug timers retire init callback results before entering the original arrow body" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate("initialize('mod');globalThis.timer=DT('mod',()=>debugEphemeral());");
        f.emit_fatal = true; try expectFatal(&f, "timer.startTimer('x')");
        try std.testing.expectEqual(@as(usize, 1), f.retired);
        try f.evaluate("if(events.length!==1||events[0]!=='buffer:node,node.mod')throw Error('callback return retirement');");
    }
}
test "native debug timers retain source pid local through write and retire it on function exit" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\initialize('mod');traceBuffer[0]=0;globalThis.timer=DT('mod',()=>{});timer.startTimer('x');
            \\Object.defineProperty(P,'pid',{configurable:true,get(){const value=debugEphemeral();value[Symbol.for('nodejs.util.inspect.custom')]=()=> 'PID';return value}});
        );
        f.emit_fatal = true; try expectFatal(&f, "timer.endTimer('x')");
        try std.testing.expectEqual(@as(usize, 1), f.retired);
        try f.evaluate("if(lines.length!==1||lines[0]!=='MOD PID x: 1.5ms\\n')throw Error('pid retired before write');");
    }
}

test "native debug timers box a primitive split result once before both object pattern Gets" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\const savedSplit=Object.getOwnPropertyDescriptor(String.prototype,Symbol.split);
            \\const savedZero=Object.getOwnPropertyDescriptor(Number.prototype,'0');
            \\const savedOne=Object.getOwnPropertyDescriptor(Number.prototype,'1');
            \\const seen=[];let boxed;
            \\try{
            \\ Object.defineProperty(String.prototype,Symbol.split,{configurable:true,value:function(text,limit){'use strict';if(this!=='.'||text!=='0.000'||limit!==2)throw Error('split inputs');seen.push('split');return 7}});
            \\ Object.defineProperty(Number.prototype,'0',{configurable:true,get(){'use strict';if(typeof this!=='object'||Number.prototype.valueOf.call(this)!==7)throw Error('one ToObject required');boxed=this;this.marker='same boxed result';seen.push('zero');return'9'}});
            \\ Object.defineProperty(Number.prototype,'1',{configurable:true,get(){'use strict';if(this!==boxed||this.marker!=='same boxed result')throw Error('different object wrappers');seen.push('one');return'123'}});
            \\ if(F(3600000)!=='1:00:09.123 (h:mm:ss.mmm)'||JSON.stringify(seen)!=='["split","zero","one"]')throw Error('boxed destructuring '+JSON.stringify(seen));
            \\}finally{
            \\ if(savedSplit)Object.defineProperty(String.prototype,Symbol.split,savedSplit);else delete String.prototype[Symbol.split];
            \\ if(savedZero)Object.defineProperty(Number.prototype,'0',savedZero);else delete Number.prototype[0];
            \\ if(savedOne)Object.defineProperty(Number.prototype,'1',savedOne);else delete Number.prototype[1];
            \\}
            \\}
        );
        try f.balanced();
    }
}
test "native debug timers reject nullish split results at the original object pattern conversion" {
    for ([_]bool{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit(); try f.select(reference);
        try f.evaluate(
            \\{
            \\const saved=Object.getOwnPropertyDescriptor(String.prototype,Symbol.split);
            \\let calls=0;
            \\try{
            \\ for(const result of [null,undefined]){
            \\  Object.defineProperty(String.prototype,Symbol.split,{configurable:true,value:function(){calls++;return result}});
            \\  if(!(reason(()=>F(3600000)) instanceof TypeError))throw Error('object pattern nullish rejection');
            \\ }
            \\ if(calls!==2)throw Error('split call count');
            \\}finally{if(saved)Object.defineProperty(String.prototype,Symbol.split,saved);else delete String.prototype[Symbol.split]}
            \\}
        );
        try f.balanced();
    }
}
