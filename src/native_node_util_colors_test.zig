//! Controls for the complete original internal/util/colors module body.
//! Process and stderr are actual native owners. The internal/tty require
//! observer is an explicit fixture collaborator, never production policy.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const colors = @import("extensions/native_node_util_colors.zig");
const functions = @import("extensions/native_node_module_callable.zig");
const sync = @import("extensions/native_sync_arguments.zig");
const c = a.c;

const Fixture = struct {
    engine: *a.v.em.Engine = undefined,
    environment: std.process.Environ.Map = undefined,
    engine_alive: bool = false,
    environment_alive: bool = false,
    probe_class: c.JSClassID = 0,
    retired: usize = 0,
    emit_fatal: bool = false,
    first_fatal: c.JSValue = undefined,

    fn init(self: *Fixture, execute_module: bool) !void {
        self.* = .{};
        self.environment = .init(std.testing.allocator);
        self.environment_alive = true;
        errdefer self.deinit();
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{});
        self.engine_alive = true;
        self.first_fatal = c.pi_js_undefined();
        try @import("extensions/native_process.zig").install(self.engine,
            std.testing.io, &self.environment, &.{"native-util-colors-control"});
        self.engine.host_control_context = self;
        try self.run(
            \\globalThis.actualProcess=process;process.stderr.isTTY=false;
            \\globalThis.colorModule={exports:{}};
            \\globalThis.requireCalls=0;globalThis.requireIds=[];globalThis.depthCalls=0;
            \\globalThis.ttyModule={getColorDepth(){if(this!==ttyModule)throw Error('tty receiver');depthCalls++;return 4}};
            \\globalThis.requireAction=()=>ttyModule;
            \\globalThis.colorRequireFixture=function(id){requireCalls++;requireIds.push(id);return requireAction(id)};
        );
        const fatal = try self.engine.checked(c.JS_NewCFunction(
            self.engine.context, rawFatal, "colorNativeFatal", 0));
        defer self.engine.freeValue(fatal); try self.publish("colorNativeFatal", fatal);
        const ephemeral = try self.engine.checked(c.JS_NewCFunction(
            self.engine.context, makeEphemeral, "colorEphemeral", 1));
        defer self.engine.freeValue(ephemeral); try self.publish("colorEphemeral", ephemeral);
        if (execute_module) try self.execute();
    }
    fn execute(self: *Fixture) !void {
        const process = try self.get("actualProcess"); defer self.engine.freeValue(process);
        const module = try self.get("colorModule"); defer self.engine.freeValue(module);
        const require = try self.get("colorRequireFixture"); defer self.engine.freeValue(require);
        const value = try colors.execute(self.engine, .{ .process = process, .module = module, .require = require });
        defer self.engine.freeValue(value); try std.testing.expect(c.JS_IsUndefined(value));
        try self.run("globalThis.colors=colorModule.exports;");
    }
    fn run(self: *Fixture, source: []const u8) !void {
        const value = try self.engine.eval(source, "native-util-colors-control.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(value);
        try std.testing.expect(!c.JS_HasException(self.engine.context));
    }
    fn get(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, name));
    }
    fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global);
        if (c.JS_DefinePropertyValueStr(self.engine.context, global, name,
            c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E) < 0)
            return error.ActualColorControlPublicationRequired;
    }
    fn reason(self: *Fixture) !c.JSValue {
        if (c.JS_HasException(self.engine.context)) return c.JS_GetException(self.engine.context);
        if (self.engine.captured_exception) |value| { self.engine.captured_exception = null; return value; }
        return error.ActualColorControlReasonRequired;
    }
    fn balanced(self: *Fixture) !void {
        try std.testing.expectEqual(@as(usize, 0), self.engine.native_exception_diagnostics_suppressed);
        try std.testing.expect(self.engine.native_fatal_invocation == null);
    }
    fn deinit(self: *Fixture) void {
        self.emit_fatal = false;
        if (self.engine_alive) {
            self.engine.freeValue(self.first_fatal);
            self.first_fatal = c.pi_js_undefined();
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
        const reason_value = c.JS_GetException(fixture.engine.context);
        if (c.JS_IsUndefined(fixture.first_fatal))
            fixture.first_fatal = a.duplicate(fixture.engine, reason_value);
        fixture.engine.freeValue(reason_value);
    }
}
fn rawFatal(context: ?*c.JSContext, _: c.JSValue,
    _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    publishFatal(current(context)); return c.pi_js_undefined();
}
fn retireProbe(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const fixture: *Fixture = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    fixture.retired += 1;
    if (fixture.emit_fatal) publishFatal(fixture);
}
fn unusedDepth(engine: *a.v.em.Engine, _: c.JSValue,
    _: *sync.Arguments, _: []const c.JSValue) !c.JSValue
{
    return c.JS_NewInt32(engine.context, 4);
}
fn ephemeralBody(s: *a.Scope, fixture: *Fixture, callable: bool) !c.JSValue {
    if (fixture.probe_class == 0) {
        if (c.JS_NewClassID(s.engine.runtime, &fixture.probe_class) == 0) return error.OutOfMemory;
        const definition: c.JSClassDef = .{ .class_name = "Actual color expression retirement probe", .finalizer = retireProbe };
        if (c.JS_NewClass(s.engine.runtime, fixture.probe_class, &definition) < 0) return error.OutOfMemory;
    }
    const generation = try s.beforeAllocation();
    const probe = try s.checkedAllocation(c.JS_NewObjectClass(s.engine.context, fixture.probe_class), generation);
    _ = c.JS_SetOpaque(probe, fixture);
    if (!callable) return a.duplicate(s.engine, probe);
    return functions.createWithArguments(s.engine, "ephemeralDepth", 0, false,
        .{ .formal_count = 0, .callback = unusedDepth }, &.{probe});
}
fn makeEphemeral(context: ?*c.JSContext, _: c.JSValue,
    argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const fixture = current(context);
    const callable = argc > 0 and c.JS_ToBool(context, argv[0]) == 1;
    return a.expression(fixture.engine, ephemeralBody, .{fixture, callable}) catch |err|
        functions.failure(fixture.engine, err, 0);
}

test "native util colors executes original exports initialization and refresh with actual process" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\if(actualProcess!==process||colors!==colorModule.exports||colors.hasColors!==false||requireCalls!==0)throw Error('actual initialization');
        \\if(Object.getPrototypeOf(colors)!==Object.prototype)throw Error('ordinary export record');
        \\if(Object.keys(colors).join(',')!=='blue,green,white,red,gray,clear,reset,hasColors,shouldColorize,refresh,yellow')throw Error('original key order');
        \\for(const key of ['blue','green','white','yellow','red','gray','clear','reset'])if(colors[key]!=='')throw Error('initial refresh');
        \\for(const [name,length] of [['shouldColorize',1],['refresh',0]]){const d=Object.getOwnPropertyDescriptor(colors,name);if(!d.enumerable||!d.writable||!d.configurable||d.value.name!==name||d.value.length!==length||Object.hasOwn(d.value,'prototype'))throw Error('method shape')}
    );
    try f.balanced();
}
test "native util colors optional stream and logical and preserve original raw falsy results" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\if(colors.shouldColorize(null)!==undefined||colors.shouldColorize()!==undefined)throw Error('optional stream');
        \\for(const value of [undefined,null,false,0,-0,NaN,'',0n]){const stream={isTTY:value,get getColorDepth(){throw Error('short circuit')}};if(!Object.is(colors.shouldColorize(stream),value))throw Error('raw falsy result')}
        \\if(requireCalls!==0)throw Error('unforced tty required');
    );
}
test "native util colors noncallable depth chooses true without coercing the property" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const order=[];const stream={get isTTY(){order.push('tty');return true},get getColorDepth(){order.push('depth');return {valueOf(){throw Error('depth coerced')}}}};
        \\if(colors.shouldColorize(stream)!==true||order.join(',')!=='tty,depth')throw Error('nonfunction depth');
    );
}
test "native util colors reads a callable depth twice and preserves receiver and relational coercion" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const order=[];let reads=0;const first=()=>{throw Error('first method called')};
        \\const stream={isTTY:true,get getColorDepth(){order.push('get'+(++reads));return reads===1?first:function(){if(this!==stream)throw Error('stream receiver');order.push('call');return {[Symbol.toPrimitive](hint){order.push(hint);return 3}}}}};
        \\if(colors.shouldColorize(stream)!==true||order.join(',')!=='get1,get2,call,number')throw Error('depth read order '+order);
    );
}
test "native util colors second depth lookup may become noncallable and throw" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\let reads=0;const stream={isTTY:true,get getColorDepth(){return ++reads===1?()=>4:null}};let reason;
        \\try{colors.shouldColorize(stream)}catch(e){reason=e}
        \\if(!(reason instanceof TypeError)||reads!==2)throw Error('second getter callable assumption');
    );
}
test "native util colors any defined FORCE_COLOR enters actual lazy tty capability branch" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const forbidden=new Proxy({},{get(){throw Error('forced branch touched stream')}});
        \\for(const force of [false,0,null,'','0','3']){actualProcess.env.FORCE_COLOR=force;if(colors.shouldColorize(forbidden)!==true)throw Error('forced presence gate')}
        \\if(requireCalls!==1||depthCalls!==6||requireIds.join(',')!=='internal/tty')throw Error('genuine lazy require route');
        \\ttyModule.getColorDepth=function(){if(this!==ttyModule)throw Error('tty receiver');return 2};
        \\if(colors.shouldColorize(forbidden)!==false)throw Error('two-bit boundary');
    );
}
test "native util colors reads current process env FORCE_COLOR and stderr without defaults" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\globalThis.order=[];const environment={get FORCE_COLOR(){order.push('force');return undefined}};
        \\Object.defineProperty(actualProcess,'env',{configurable:true,get(){order.push('env');return environment}});
        \\const stream={get isTTY(){order.push('tty');return 0}};
        \\if(colors.shouldColorize(stream)!==0||order.join(',')!=='env,force,tty')throw Error('current env order');
        \\globalThis.process={env:{FORCE_COLOR:'wrong'}};
        \\order.length=0;if(colors.shouldColorize(stream)!==0||requireCalls!==0)throw Error('captured actual process replaced');
    );
}
test "native util colors lazy require retries ordinary failure and nullish results" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\actualProcess.env.FORCE_COLOR='1';const marker={};let step=0;
        \\requireAction=()=>{step++;if(step===1)throw marker;if(step===2)return undefined;return ttyModule};
        \\let one,two;try{colors.shouldColorize({})}catch(e){one=e}try{colors.shouldColorize({})}catch(e){two=e}
        \\if(one!==marker||!(two instanceof TypeError)||colors.shouldColorize({})!==true||requireCalls!==3)throw Error('lazy retry');
        \\if(colors.shouldColorize({})!==true||requireCalls!==3)throw Error('successful cache not retained');
    );
}
test "native util colors lazy require retains nonnull falsy values and retries null values" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\actualProcess.env.FORCE_COLOR='1';requireAction=()=>0;
        \\for(let i=0;i<2;i++){let reason;try{colors.shouldColorize({})}catch(e){reason=e}if(!(reason instanceof TypeError))throw Error('zero module call')}
        \\if(requireCalls!==1)throw Error('falsy cache treated as nullish');
    );
    var second: Fixture = undefined; try second.init(true); defer second.deinit();
    try second.run(
        \\actualProcess.env.FORCE_COLOR='1';requireAction=()=>requireCalls===1?null:ttyModule;
        \\let reason;try{colors.shouldColorize({})}catch(e){reason=e}
        \\if(!(reason instanceof TypeError)||colors.shouldColorize({})!==true||requireCalls!==2)throw Error('null module not retried');
    );
}
test "native util colors nested lazy require preserves outer assignment after reentry" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\actualProcess.env.FORCE_COLOR='1';const seen=[];const inner={getColorDepth(){seen.push('inner');return 3}},outer={getColorDepth(){seen.push('outer');return 4}};
        \\requireAction=()=>{if(requireCalls===1){if(colors.shouldColorize({})!==true)throw Error('nested');return outer}return inner};
        \\if(colors.shouldColorize({})!==true||colors.shouldColorize({})!==true||seen.join(',')!=='inner,outer,outer'||requireCalls!==2)throw Error('lazy outer assignment');
    );
}

test "native util colors refresh resolves the current method before stderr and uses its exports receiver" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const order=[],actualStream=actualProcess.stderr;let receiver;
        \\Object.defineProperty(colors,'shouldColorize',{configurable:true,get(){order.push('method');return function(stream){order.push('call');receiver=this;if(stream!==actualStream)throw Error('actual stderr');return {valueOf(){throw Error('truthy result coerced')}}}}});
        \\Object.defineProperty(actualProcess,'stderr',{configurable:true,get(){order.push('stderr');return actualStream}});
        \\if(colors.refresh()!==undefined||receiver!==colors||order.join(',')!=='method,stderr,call')throw Error('refresh condition order');
        \\const expected={blue:'\u001b[34m',green:'\u001b[32m',white:'\u001b[39m',yellow:'\u001b[33m',red:'\u001b[31m',gray:'\u001b[90m',clear:'\u001bc',reset:'\u001b[0m',hasColors:true};
        \\for(const key of Object.keys(expected))if(colors[key]!==expected[key])throw Error('actual enabled palette '+key);
    );
}
test "native util colors refresh resolves module exports separately for every assignment" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const refresh=colors.refresh,records=[{shouldColorize(){if(this!==records[0])throw Error('condition receiver');return true}}];
        \\for(let i=0;i<9;i++)records.push({});let reads=0;
        \\Object.defineProperty(colorModule,'exports',{configurable:true,get(){return records[reads++]}});
        \\refresh();
        \\const names=['blue','green','white','yellow','red','gray','clear','reset','hasColors'];
        \\if(reads!==10)throw Error('module exports reads');
        \\for(let i=0;i<names.length;i++)if(Object.keys(records[i+1]).join(',')!==names[i])throw Error('assignment destination '+i);
        \\if(records[1].blue!=='\u001b[34m'||records[9].hasColors!==true)throw Error('assignment payload');
    );
}
test "native util colors refresh preserves earlier assignments when a middle setter throws" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const marker={},writes=[];colors.shouldColorize=()=>true;
        \\for(const key of ['blue','green','white','yellow','red','gray','clear','reset','hasColors'])Object.defineProperty(colors,key,{configurable:true,set(value){writes.push([key,value]);if(key==='yellow')throw marker}});
        \\let reason;try{colors.refresh()}catch(e){reason=e}
        \\if(reason!==marker||writes.map(x=>x[0]).join(',')!=='blue,green,white,yellow')throw Error('partial refresh ordering');
        \\if(writes[0][1]!=='\u001b[34m'||writes[3][1]!=='\u001b[33m')throw Error('partial refresh values');
    );
}
test "native util colors disabled refresh clears the palette and a noncallable condition prevents writes" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\colors.shouldColorize=()=>true;colors.refresh();colors.shouldColorize=()=>0;colors.refresh();
        \\for(const key of ['blue','green','white','yellow','red','gray','clear','reset'])if(colors[key]!=='')throw Error('disabled clear');
        \\if(colors.hasColors!==false)throw Error('disabled hasColors');
        \\let writes=0;Object.defineProperty(colors,'blue',{configurable:true,set(){writes++}});
        \\colors.shouldColorize=null;let reason;try{colors.refresh()}catch(e){reason=e}
        \\if(!(reason instanceof TypeError)||writes!==0)throw Error('noncallable condition wrote colors');
    );
}
test "native util colors final statement rereads a replacement chosen by the module exports setter" {
    var f: Fixture = undefined; try f.init(false); defer f.deinit();
    try f.run(
        \\globalThis.selectedRecord={refresh(){if(this!==selectedRecord)throw Error('replacement receiver');globalThis.replacementCalls++}};
        \\globalThis.replacementCalls=0;globalThis.initialRecord=undefined;
        \\Object.defineProperty(colorModule,'exports',{configurable:true,get(){return selectedRecord},set(value){initialRecord=value}});
    );
    try f.execute();
    try f.run(
        \\if(colors!==selectedRecord||replacementCalls!==1||requireCalls!==0)throw Error('final live exports selection');
        \\if(Object.hasOwn(initialRecord,'yellow')||initialRecord.hasColors!==false||typeof initialRecord.refresh!=='function')throw Error('initial literal initialization');
    );
}
test "native util colors ordinary module assignment failure keeps its exact reason and skips refresh" {
    var f: Fixture = undefined; try f.init(false); defer f.deinit();
    try f.run(
        \\globalThis.assignmentMarker={};globalThis.reads=0;
        \\Object.defineProperty(colorModule,'exports',{configurable:true,get(){reads++;throw Error('refresh read after assignment failure')},set(){throw assignmentMarker}});
    );
    try std.testing.expectError(error.JavaScriptException, f.execute());
    const actual = try f.reason(); defer f.engine.freeValue(actual);
    const expected = try f.get("assignmentMarker"); defer f.engine.freeValue(expected);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, actual, expected));
    try f.run("if(reads!==0)throw Error('failed assignment continued');");
    try f.balanced();
}
test "native util colors escaped methods retain actual wrapper owners after replacement and collection" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\globalThis.savedShould=colors.shouldColorize;globalThis.savedRefresh=colors.refresh;
        \\globalThis.retainedModule=colorModule;globalThis.retainedProcess=actualProcess;
        \\globalThis.process={env:{FORCE_COLOR:'foreign'},stderr:{}};
        \\globalThis.colorModule={exports:{shouldColorize(){throw Error('foreign module')}}};
        \\delete globalThis.actualProcess;delete globalThis.colors;
        \\retainedProcess.stderr.isTTY=true;retainedProcess.stderr.getColorDepth=()=>4;
    );
    f.engine.finishJob(); c.JS_RunGC(f.engine.runtime);
    try f.run(
        \\if(savedShould({isTTY:0})!==0||requireCalls!==0)throw Error('escaped process owner');
        \\savedRefresh();if(retainedModule.exports.hasColors!==true||retainedModule.exports.blue!=='\u001b[34m')throw Error('escaped module owner');
    );
}
test "native util colors current native fatal from FORCE_COLOR getter prevents tty and stream work" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\globalThis.streamReads=0;globalThis.stream={get isTTY(){streamReads++;return true}};
        \\Object.defineProperty(actualProcess.env,'FORCE_COLOR',{configurable:true,get(){colorNativeFatal();return '1'}});
    );
    try std.testing.expectError(error.JavaScriptException, f.run("colors.shouldColorize(stream);"));
    const actual = try f.reason(); defer f.engine.freeValue(actual);
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, actual, f.first_fatal));
    try f.run("if(streamReads!==0||requireCalls!==0||depthCalls!==0)throw Error('fatal force read continued');");
    try f.balanced();
}
test "native util colors truthy isTTY temporary retires before the depth property read" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\globalThis.depthReads=0;globalThis.stream={get isTTY(){return colorEphemeral(false)},get getColorDepth(){depthReads++;return ()=>4}};
    );
    f.emit_fatal = true;
    try std.testing.expectError(error.JavaScriptException, f.run("colors.shouldColorize(stream);"));
    const actual = try f.reason(); defer f.engine.freeValue(actual);
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, actual, f.first_fatal));
    try f.run("if(depthReads!==0)throw Error('truthy temporary continued');");
    try f.balanced();
}
test "native util colors first typeof depth function retires before the second property read" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\globalThis.depthReads=0;globalThis.stream={isTTY:true,get getColorDepth(){depthReads++;return colorEphemeral(true)}};
    );
    f.emit_fatal = true;
    try std.testing.expectError(error.JavaScriptException, f.run("colors.shouldColorize(stream);"));
    const actual = try f.reason(); defer f.engine.freeValue(actual);
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, actual, f.first_fatal));
    try f.run("if(depthReads!==1)throw Error('typeof temporary continued');");
    try f.balanced();
}
test "native util colors refresh condition result retires before its first assignment" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\globalThis.blueWrites=0;colors.shouldColorize=function(){return colorEphemeral(false)};
        \\Object.defineProperty(colors,'blue',{configurable:true,set(){blueWrites++}});
    );
    f.emit_fatal = true;
    try std.testing.expectError(error.JavaScriptException, f.run("colors.refresh();"));
    const actual = try f.reason(); defer f.engine.freeValue(actual);
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, actual, f.first_fatal));
    try f.run("if(blueWrites!==0||colors.hasColors!==false)throw Error('condition temporary continued');");
    try f.balanced();
}
test "native util colors discarded assignment literal retires before final refresh selection" {
    var f: Fixture = undefined; try f.init(false); defer f.deinit();
    try f.run(
        \\globalThis.exportReads=0;globalThis.finalRefreshCalls=0;
        \\Object.defineProperty(colorModule,'exports',{configurable:true,get(){exportReads++;return {refresh(){finalRefreshCalls++}}},set(value){value.retirement=colorEphemeral(false)}});
    );
    f.emit_fatal = true;
    try std.testing.expectError(error.JavaScriptException, f.execute());
    const actual = try f.reason(); defer f.engine.freeValue(actual);
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, actual, f.first_fatal));
    try f.run("if(exportReads!==0||finalRefreshCalls!==0)throw Error('assignment temporary continued');");
    try f.balanced();
}
test "native util colors captured flagged Error remains data unless an actual producer publishes it" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    const flagged = try f.engine.checked(c.JS_NewError(f.engine.context)); defer f.engine.freeValue(flagged);
    c.JS_SetUncatchableError(f.engine.context, flagged); try f.publish("flaggedData", flagged);
    try f.run(
        \\if(colors.shouldColorize({isTTY:flaggedData})!==true)throw Error('flagged truthy data');
        \\flaggedData[Symbol.toPrimitive]=function(hint){if(hint!=='number')throw Error('wrong hint');return 3};
        \\if(colors.shouldColorize({isTTY:true,getColorDepth(){return flaggedData}})!==true)throw Error('flagged numeric data');
        \\colors.shouldColorize=()=>flaggedData;colors.refresh();
        \\if(colors.hasColors!==true||colors.red!=='\u001b[31m')throw Error('flagged condition data');
    );
    try f.balanced();
}
