//! Controls for the genuine formatWithOptions and complete validateObject owners.
//! The real process/Stream/internal-errors bootstrap and native inspector are used.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const bootstrap = @import("extensions/native_node_argument_bootstrap.zig");
const binding = @import("extensions/native_node_internal_inspect_binding.zig");
const errors = @import("extensions/native_node_argument_errors.zig");
const c = a.c;

const Fixture = struct {
    engine: *a.v.em.Engine = undefined,
    environment: std.process.Environ.Map = undefined,
    engine_alive: bool = false,
    environment_alive: bool = false,
    prepared: ?bootstrap.Prepared = null,
    probe_class: c.JSClassID = 0,
    retired: usize = 0,
    emit_fatal: bool = false,
    first_fatal: c.JSValue = undefined,
    fn init(self: *Fixture, prepare_errors: bool) !void {
        self.* = .{};
        self.environment = .init(std.testing.allocator);
        self.environment_alive = true;
        errdefer self.deinit();
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{});
        self.engine_alive = true;
        self.first_fatal = c.pi_js_undefined();
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine,
            std.testing.io, &self.environment, &.{"native-format-options-control"});
        try @import("extensions/native_node_os.zig").install(self.engine);
        self.engine.host_control_context = self;
        const record = try binding.acquire(self.engine); defer self.engine.freeValue(record);
        const actual_inspect = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, record, "inspect"));
        defer self.engine.freeValue(actual_inspect); try self.publish("I", actual_inspect);
        const format = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, record, "format"));
        defer self.engine.freeValue(format); try self.publish("G", format);
        const selected = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, record, "formatWithOptions"));
        defer self.engine.freeValue(selected); try self.publish("F", selected);
        if (prepare_errors) try self.prepare();
        try self.engine.bindFunction("formatNativeFatal", rawFatal, 0);
        try self.engine.bindFunction("formatEphemeral", ephemeral, 0);
    }
    fn prepare(self: *Fixture) !void {
        self.prepared = try bootstrap.prepare(self.engine);
        const validator = try errors.validateObject(self.engine); defer self.engine.freeValue(validator);
        try self.publish("V", validator);
        try self.publish("ArgumentType", self.prepared.?.arguments.invalid_arg_type);
    }
    fn deinit(self: *Fixture) void {
        self.emit_fatal = false;
        if (self.engine_alive) {
            if (self.prepared) |prepared| prepared.deinit(self.engine);
            self.engine.freeValue(self.first_fatal);
            self.engine.deinit(); self.engine_alive = false;
        }
        if (self.environment_alive) { self.environment.deinit(); self.environment_alive = false; }
    }
    fn run(self: *Fixture, source: []const u8) !void {
        const value = try self.engine.eval(source, "native-format-options-control.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(value); try std.testing.expect(!c.JS_HasException(self.engine.context));
    }
    fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global);
        if (c.JS_DefinePropertyValueStr(self.engine.context, global, name,
            c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E) < 0)
            return error.ActualFormatOptionsPublicationRequired;
    }
    fn get(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, name));
    }
    fn reason(self: *Fixture) !c.JSValue {
        if (c.JS_HasException(self.engine.context)) return c.JS_GetException(self.engine.context);
        if (self.engine.captured_exception) |value| { self.engine.captured_exception = null; return value; }
        return error.ActualFormatOptionsReasonRequired;
    }
    fn balanced(self: *Fixture) !void {
        try std.testing.expectEqual(@as(usize, 0), self.engine.native_exception_diagnostics_suppressed);
        try std.testing.expect(self.engine.native_fatal_invocation == null);
    }
};
fn current(context: ?*c.JSContext) *Fixture {
    const engine = a.v.em.Engine.fromContext(context.?);
    return @ptrCast(@alignCast(engine.host_control_context.?));
}
fn publishFatal(fixture: *Fixture) void {
    _ = fixture.engine.throwNativeOutOfMemoryFatal();
    if (c.JS_HasException(fixture.engine.context)) {
        const reason_value = c.JS_GetException(fixture.engine.context);
        if (c.JS_IsUndefined(fixture.first_fatal)) fixture.first_fatal = a.duplicate(fixture.engine, reason_value);
        fixture.engine.freeValue(reason_value);
    }
}
fn rawFatal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    publishFatal(current(context)); return c.pi_js_undefined();
}
fn retireProbe(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const fixture: *Fixture = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    fixture.retired += 1;
    if (fixture.emit_fatal) publishFatal(fixture);
}
fn ephemeralBody(s: *a.Scope, fixture: *Fixture) !c.JSValue {
    if (fixture.probe_class == 0) {
        if (c.JS_NewClassID(s.engine.runtime, &fixture.probe_class) == 0) return error.OutOfMemory;
        const definition: c.JSClassDef = .{ .class_name = "Actual format options retirement probe", .finalizer = retireProbe };
        if (c.JS_NewClass(s.engine.runtime, fixture.probe_class, &definition) < 0) return error.OutOfMemory;
    }
    const generation = try s.beforeAllocation();
    const value = try s.checkedAllocation(c.JS_NewObjectClass(s.engine.context, fixture.probe_class), generation);
    _ = c.JS_SetOpaque(value, fixture);
    return a.duplicate(s.engine, value);
}
fn ephemeral(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = current(context);
    return a.expression(fixture.engine, ephemeralBody, .{fixture}) catch |err|
        @import("extensions/native_node_module_callable.zig").failure(fixture.engine, err, 0);
}

test "native format options exposes genuine callable shape and shares the completed private owners" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\if(F.name!=='formatWithOptions'||F.length!==1||Object.getPrototypeOf(F)!==Function.prototype||!Object.hasOwn(F,'prototype'))throw Error('original function shape');
        \\if(V.name!=='wrappedFn'||V.length!==0||typeof V.withoutStackTrace!=='function'||V.withoutStackTrace.length!==2||Object.hasOwn(V.withoutStackTrace,'prototype'))throw Error('original validator wrapper');
        \\if(F({},'literal')!=='literal'||F({})!==''||G('%d',1000)!=='1000')throw Error('basic exact entries');
    );
    const second = try bootstrap.prepare(f.engine); defer second.deinit(f.engine);
    const selected = try f.engine.checked(c.JS_GetPropertyStr(f.engine.context, second.internal_inspect, "formatWithOptions"));
    defer f.engine.freeValue(selected);
    const first = try f.get("F"); defer f.engine.freeValue(first);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, selected, first));
    const validator = try errors.validateObject(f.engine); defer f.engine.freeValue(validator);
    const expected = try f.get("V"); defer f.engine.freeValue(expected);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, validator, expected));
    try f.balanced();
}
test "native format options allows arrays objects and revoked object proxies without option enumeration on literal return" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const poison=new Proxy({},{get(){throw Error('option Get')},ownKeys(){throw Error('option ownKeys')}});
        \\const revoked=Proxy.revocable({},{});revoked.revoke();
        \\for(const options of [{},[],Object.create(null),new Number(1),poison,revoked.proxy])if(F(options,'literal')!=='literal')throw Error('valid Object options');
        \\if(F(poison)!=='')throw Error('empty rest enumerated options');
    );
}
test "native format options rejects primitives and functions with the actual hidden argument error before formatting" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\let converted=0;const tail={toString(){converted++;return 'bad'}};
        \\for(const options of [undefined,null,true,0,1n,'',Symbol('x'),function named(){}]){
        \\  let reason;try{F(options,'%s',tail)}catch(e){reason=e}
        \\  if(!(reason instanceof TypeError)||reason.code!=='ERR_INVALID_ARG_TYPE'||reason.constructor!==TypeError||!reason.message.includes('"inspectOptions"'))throw Error('genuine validation error');
        \\}
        \\if(converted!==0)throw Error('invalid options entered formatter');
    );
    try f.balanced();
}
test "native format options numeric separator uses explicit values and only nullish shared defaults" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\if(F({numericSeparator:true,colors:true},'%d %i %f %s',1000,1234n,1234.5,1000n)!=='1_000 1_234n 1_234.5 1_000n')throw Error('number bigint option');
        \\I.defaultOptions.numericSeparator=true;
        \\for(const selected of [undefined,null])if(F({numericSeparator:selected},'%d',1000)!=='1_000')throw Error('nullish defaults');
        \\for(const selected of [false,0,''])if(F({numericSeparator:selected},'%d',1000)!=='1000')throw Error('falsy override');
        \\const truthy={valueOf(){throw Error('separator coerced')}};if(F({numericSeparator:truthy},'%d',1000)!=='1_000')throw Error('separator truthiness');
        \\I.defaultOptions.numericSeparator=false;if(G('%d',1000)!=='1000')throw Error('plain format changed');
    );
}
test "native format options reads numeric separator after each original value conversion" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const order=[];const options={get numericSeparator(){order.push('option');return true}};
        \\const decimal={valueOf(){order.push('decimal');return 1000}},integer={toString(){order.push('integer');return '1234x'}},float={toString(){order.push('float');return '1234.5x'}};
        \\if(F(options,'%d %i %f',decimal,integer,float)!=='1_000 1_234 1_234.5'||order.join(',')!=='decimal,option,integer,option,float,option')throw Error('numeric conversion order '+order);
    );
}
test "native format options nonnumeric placeholders do not consult numeric separator" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const options={get numericSeparator(){throw Error('unused numeric option')}};
        \\const result=F(options,'%d %i %f %s %j %c %%',Symbol(),Symbol(),Symbol(),Symbol('s'),{x:1},'discard');
        \\if(result!=='NaN NaN NaN Symbol(s) {"x":1}  %')throw Error('nonnumeric placeholder route '+result);
        \\if(F(options,'%s',{toString(){return 'custom'}})!=='custom')throw Error('custom String path');
    );
}
test "native format options string placeholder copies options then overrides compact colors and depth" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const order=[],token=Symbol('token'),options={};
        \\for(const [key,value] of [['compact',9],['colors',true],['depth',99],['customOption','kept']])Object.defineProperty(options,key,{enumerable:true,get(){order.push(key);return value}});
        \\Object.defineProperty(options,token,{enumerable:true,get(){order.push('symbol');return 7}});
        \\const input={[I.custom](depth,selected,inspector){if(this!==input||inspector!==I||depth!==0||selected.depth!==0||selected.compact!==3||selected.colors!==false||selected.customOption!=='kept'||selected[token]!==7)throw Error('string overrides');return 'observed'}};
        \\if(F(options,'%s',input)!=='observed'||order.join(',')!=='compact,colors,depth,customOption,symbol')throw Error('string spread order '+order);
    );
}
test "native format options hidden placeholder preserves own key descriptor Get order before overrides" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const seen=[],token=Symbol('token'),target={depth:1,showHidden:false,showProxy:false,customOption:'kept'};
        \\Object.defineProperty(target,'hidden',{enumerable:false,get(){throw Error('nonenumerable copied')}});
        \\Object.defineProperty(target,token,{enumerable:true,value:7});
        \\const options=new Proxy(target,{ownKeys(t){seen.push('keys');return Reflect.ownKeys(t)},getOwnPropertyDescriptor(t,k){seen.push('desc:'+String(k));return Reflect.getOwnPropertyDescriptor(t,k)},get(t,k,r){seen.push('get:'+String(k));return Reflect.get(t,k,r)}});
        \\const input={[I.custom](depth,selected){if(depth!==4||selected.depth!==4||!selected.showHidden||!selected.showProxy||selected[token]!==7||selected.customOption!=='kept'||Object.hasOwn(selected,'hidden'))throw Error('hidden overrides');return 'observed'}};
        \\if(F(options,'%o',input)!=='observed')throw Error('hidden result');
        \\if(seen.join('|')!=='keys|desc:depth|get:depth|desc:showHidden|get:showHidden|desc:showProxy|get:showProxy|desc:customOption|get:customOption|desc:hidden|desc:Symbol(token)|get:Symbol(token)')throw Error('CopyDataProperties order '+seen);
    );
}
test "native format options ordinary placeholder forwards the actual options without eager spreading" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\let reads=0,keys=0;const token=Symbol('unused'),target={get depth(){if(this!==options)throw Error('actual options receiver');reads++;return 1}};
        \\Object.defineProperty(target,token,{enumerable:true,get(){throw Error('ordinary options eagerly spread symbol')}});
        \\const options=new Proxy(target,{ownKeys(t){keys++;return Reflect.ownKeys(t)}});
        \\const value={a:{b:{c:1}}};const result=F(options,'%O',value);
        \\if(!result.includes('[Object]')||reads!==1||keys!==1)throw Error('actual ordinary options flow');
    );
}
test "native format options trailing objects use the same options and trailing strings stay uninspected" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\let calls=0;const input={[I.custom](depth,selected,inspector){calls++;if(inspector!==I||selected.depth!==1||depth!==1)throw Error('trailing options');return 'object'}};
        \\if(F({depth:1},'lead',input,'tail')!=='lead object tail'||calls!==1)throw Error('trailing selected inspector');
    );
}

test "native format options performs nullish default lookup after the live separator getter" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const order=[],options={get numericSeparator(){order.push('get');I.defaultOptions.numericSeparator=true;return undefined}};
        \\if(F(options,'%d',1000)!=='1_000'||order.join(',')!=='get')throw Error('fallback preceded getter');
        \\I.defaultOptions.numericSeparator=false;
        \\const arrayOptions=[];arrayOptions.numericSeparator=true;if(F(arrayOptions,'%d',1000)!=='1_000')throw Error('actual array options');
    );
}
test "native format options preserves ordinary getter failures and suppresses later argument work" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const marker={tag:'numeric Get'};let later=0,reason;
        \\try{F({get numericSeparator(){throw marker}},'%d %s',1000,{toString(){later++;return 'late'}})}catch(e){reason=e}
        \\if(reason!==marker||later!==0)throw Error('numeric Get failure changed');
        \\const spreadMarker={tag:'spread Get'},order=[];reason=undefined;
        \\const options={get depth(){order.push('depth');throw spreadMarker},get colors(){order.push('colors');return true}};
        \\const input={[I.custom](){later++;return 'late'}};
        \\try{F(options,'%s',input)}catch(e){reason=e}
        \\if(reason!==spreadMarker||order.join(',')!=='depth'||later!==0)throw Error('spread failure ordering');
    );
    try f.balanced();
}
test "native format options retains independent option frames across recursive getter calls" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const order=[];let inner;
        \\const outer={get numericSeparator(){order.push('outer');inner=F({get numericSeparator(){order.push('inner');return false}},'%d',2000);return true}};
        \\if(F(outer,'%d',1000)!=='1_000'||inner!=='2000'||order.join(',')!=='outer,inner')throw Error('reentrant frame alias');
        \\let inspected=0;const input={[I.custom](depth,options){inspected++;if(depth!==3||options.depth!==3)throw Error('reentrant options changed');return F({numericSeparator:true},'%d',3000)}};
        \\if(F({depth:3},'%O',input)!=='3_000'||inspected!==1)throw Error('nested inspector format');
    );
    try f.balanced();
}
test "native validateObject preserves all three original flags and actual hidden error identity" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const values=[null,[],function named(){},{},Object.create(null),new Number(1),undefined,1,'value',true,1n,Symbol('v')];
        \\for(let flags=0;flags<8;flags++)for(let index=0;index<values.length;index++){
        \\  const expected=index===0?!!(flags&1):index===1?!!(flags&2):index===2?!!(flags&4):index<6;
        \\  let reason;try{if(V(values[index],'input',flags)!==undefined)throw Error('validator return')}catch(e){reason=e}
        \\  if(expected?reason!==undefined:!(reason instanceof TypeError&&reason.code==='ERR_INVALID_ARG_TYPE'&&reason.constructor===TypeError))throw Error('flag acceptance '+flags+':'+index);
        \\}
        \\if(V({},'input')!==undefined||V({},'input',undefined)!==undefined||V({},'input',-0)!==undefined)throw Error('default zero flags');
        \\let direct;try{V.withoutStackTrace([],'input')}catch(e){direct=e}
        \\if(!(direct instanceof TypeError)||direct.code!=='ERR_INVALID_ARG_TYPE'||direct.constructor!==TypeError)throw Error('raw shares hidden class');
    );
}
test "native validateObject performs three independent bit coercions with original short circuit points" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\let seen=[];const flags={valueOf(){seen.push(seen.length);return [1,2,4][seen.length-1]}};
        \\V(function accepted(){},'input',flags);if(seen.join(',')!=='0,1,2')throw Error('three flag conversions');
        \\seen=[];let reason;const deny={valueOf(){seen.push('bit');return 0}};
        \\try{V(null,'input',deny)}catch(e){reason=e}
        \\if(reason?.code!=='ERR_INVALID_ARG_TYPE'||seen.length!==1)throw Error('null short circuit');
        \\seen=[];reason=undefined;try{V([],'input',deny)}catch(e){reason=e}
        \\if(reason?.code!=='ERR_INVALID_ARG_TYPE'||seen.length!==2)throw Error('array short circuit');
        \\seen=[];V({},'input',deny);if(seen.length!==3)throw Error('ordinary object bit order');
        \\seen=[];V(null,'input',{valueOf(){seen.push('bit');return 1}});if(seen.length!==3)throw Error('nullable still evaluates other flags');
    );
}
test "native validateObject preserves primitive flag conversion failures and original thrown values" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\for(const flags of [1n,Symbol('flags')]){let reason;try{V({},'input',flags)}catch(e){reason=e}if(!(reason instanceof TypeError)||Object.hasOwn(reason,'code'))throw Error('actual bitwise type failure')}
        \\const marker={tag:'flags'};let seen=0,reason;
        \\try{V({},'input',{valueOf(){seen++;throw marker}})}catch(e){reason=e}
        \\if(reason!==marker||seen!==1)throw Error('coercion throw changed');
        \\V({},'input',null);V({},'input',false);V({},'input','7');
    );
    try f.balanced();
}
test "native validateObject uses the captured real ArrayIsArray including revoked proxy behavior" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const original=Array.isArray;Array.isArray=()=>false;
        \\try{
        \\  let reason;try{V(new Proxy([],{}),'input')}catch(e){reason=e}
        \\  if(reason?.code!=='ERR_INVALID_ARG_TYPE')throw Error('array proxy brand bypassed');
        \\  const revoked=Proxy.revocable({},{});revoked.revoke();reason=undefined;
        \\  try{V(revoked.proxy,'input')}catch(e){reason=e}
        \\  if(!(reason instanceof TypeError)||Object.hasOwn(reason,'code'))throw Error('actual revoked ArrayIsArray failure');
        \\  if(V(revoked.proxy,'input',2)!==undefined||F(revoked.proxy,'literal')!=='literal')throw Error('allowed array bypass not preserved');
        \\}finally{Array.isArray=original}
    );
}
test "native format options uses original numeric String and Apply primordials after guest mutation" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const saved=[Number,String,parseInt,parseFloat,Reflect.apply],poison=()=>{throw Error('late primordial read')};
        \\Number=String=parseInt=parseFloat=Reflect.apply=poison;
        \\try{
        \\  if(F({numericSeparator:true},'%d %i %f %s','1000','2345x','3456.5x',Symbol('s'))!=='1_000 2_345 3_456.5 Symbol(s)')throw Error('original primordial lost');
        \\  if(V({},'input')!==undefined)throw Error('original ReflectApply lost');
        \\}finally{[Number,String,parseInt,parseFloat,Reflect.apply]=saved}
    );
}
test "native format options spread defines actual own symbol data without inherited setter calls" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const token=Symbol('option'),options={customOption:true};let assigned=0;
        \\Object.defineProperty(options,token,{enumerable:true,value:17});
        \\Object.defineProperty(Object.prototype,token,{configurable:true,set(){assigned++;throw Error('inherited symbol setter')}});
        \\try{
        \\  const input={[I.custom](depth,selected){const d=Object.getOwnPropertyDescriptor(selected,token);if(!d||d.value!==17||!d.writable||!d.enumerable||!d.configurable)throw Error('own symbol descriptor');return 'observed'}};
        \\  if(F(options,'%s',input)!=='observed'||assigned!==0)throw Error('CopyDataProperties used ordinary Set');
        \\}finally{delete Object.prototype[token]}
    );
}
test "native format options current native getter fatal stops later placeholders with first reason" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try std.testing.expectError(error.JavaScriptException, f.run(
        \\var later=0;
        \\F({get numericSeparator(){formatNativeFatal();return true}},'%d %s',1000,{toString(){later++;return 'late'}});
    ));
    const caught_reason = try f.reason(); defer f.engine.freeValue(caught_reason);
    try std.testing.expect(c.JS_IsUncatchableError(caught_reason));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, caught_reason, f.first_fatal));
    try f.run("if(later!==0)throw Error('later placeholder entered')");
    try f.balanced();
}
test "native format options retires the separator temporary before the next placeholder" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit(); f.emit_fatal = true;
    try std.testing.expectError(error.JavaScriptException, f.run(
        \\var later=0;
        \\F({get numericSeparator(){return formatEphemeral()}},'%d %s',1000,{toString(){later++;return 'late'}});
    ));
    const caught_reason = try f.reason(); defer f.engine.freeValue(caught_reason);
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    try std.testing.expect(c.JS_IsUncatchableError(caught_reason));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, caught_reason, f.first_fatal));
    try f.run("if(later!==0)throw Error('separator retired after later placeholder')");
    try f.balanced();
}
test "native format options retires overwritten spread values before entering inspect" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit(); f.emit_fatal = true;
    try std.testing.expectError(error.JavaScriptException, f.run(
        \\var entered=0;
        \\F({get colors(){return formatEphemeral()}},'%s',{[I.custom](){entered++;return 'late'}});
    ));
    const caught_reason = try f.reason(); defer f.engine.freeValue(caught_reason);
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    try std.testing.expect(c.JS_IsUncatchableError(caught_reason));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, caught_reason, f.first_fatal));
    try f.run("if(entered!==0)throw Error('overwritten value retired after inspector')");
    try f.balanced();
}
test "native format options accepts flagged error values as data without an actual pending event" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run("var marked=new Error('diagnostic-only'),later=0");
    const marked = try f.get("marked"); defer f.engine.freeValue(marked);
    c.JS_SetUncatchableError(f.engine.context, marked);
    try f.run(
        \\if(F(marked,'literal')!=='literal'||F({numericSeparator:marked},'%d %s',1000,{toString(){later++;return 'tail'}})!=='1_000 tail'||later!==1)throw Error('flag-only data became a pending failure');
    );
    try std.testing.expect(c.JS_IsUncatchableError(marked));
    try std.testing.expect(c.JS_IsUndefined(f.first_fatal));
    try f.balanced();
}
test "native format options requires the actual errors bootstrap and reuses its original inspector function" {
    var f: Fixture = undefined; try f.init(false); defer f.deinit();
    try std.testing.expectError(error.ActualInternalErrorsNotInitialized, errors.validateObject(f.engine));
    try std.testing.expect(!f.engine.native_module_values.contains("pi-native:private/argument-error-owner"));
    const before = try f.get("F"); defer f.engine.freeValue(before);
    try std.testing.expectError(error.JavaScriptException, f.run("F({},'literal')"));
    const caught_reason = try f.reason(); defer f.engine.freeValue(caught_reason);
    try std.testing.expect(!f.engine.native_module_values.contains("pi-native:private/argument-error-owner"));
    try f.prepare();
    const after = try f.get("F"); defer f.engine.freeValue(after);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, before, after));
    try f.run("if(F({},'literal')!=='literal'||V({},'input')!==undefined)throw Error('actual graph not shared')");
    try f.balanced();
}
