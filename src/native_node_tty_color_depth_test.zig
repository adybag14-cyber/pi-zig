//! Actual VM controls for original internal/tty.getColorDepth. Process, native OS,
//! private builtin require and SafeMap are genuine owners. Mutated providers and
//! explicit environments below are test probes, never production defaults.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const tty = @import("extensions/native_node_tty_color_depth.zig");
const functions = @import("extensions/native_node_module_callable.zig");
const sync = @import("extensions/native_sync_arguments.zig");
const collections = @import("extensions/native_node_fs_collections.zig");
const c = a.c;
const Fixture = struct {
    engine: *a.v.em.Engine = undefined,
    environment: std.process.Environ.Map = undefined,
    engine_alive: bool = false,
    environment_alive: bool = false,
    safe_map: c.JSValue = undefined,
    native_require: c.JSValue = undefined,
    depth: c.JSValue = undefined,
    first_fatal: c.JSValue = undefined,
    probe_class: c.JSClassID = 0,
    retired: usize = 0,
    emit_fatal: bool = false,

    fn init(self: *Fixture, create_depth: bool) !void {
        self.* = .{};
        self.environment = .init(std.testing.allocator); self.environment_alive = true;
        errdefer self.deinit();
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{});
        self.engine_alive = true;
        self.safe_map = c.pi_js_undefined(); self.native_require = c.pi_js_undefined();
        self.depth = c.pi_js_undefined(); self.first_fatal = c.pi_js_undefined();
        try @import("extensions/native_process.zig").install(self.engine,
            std.testing.io, &self.environment, &.{"native-tty-color-depth-control"});
        try @import("extensions/native_node_os.zig").install(self.engine);
        self.safe_map = try collections.acquireSafeMap(self.engine);
        self.native_require = try @import("extensions/native_node_internal_builtin_require.zig").acquire(self.engine,
            .{ .bindings = &.{.{ .id = "os", .module_name = "node:os" }} });
        try self.publish("actualNativeRequire", self.native_require);
        self.engine.host_control_context = self;
        try self.run(
            \\globalThis.actualProcess=process;globalThis.actualOS=actualNativeRequire('os');
            \\globalThis.nativePlatform=actualProcess.platform;actualProcess.platform='linux';
            \\globalThis.requireCalls=0;globalThis.requireIds=[];globalThis.releaseCalls=0;
            \\globalThis.requireAction=id=>actualNativeRequire(id);
            \\globalThis.depthRequire=function(id){'use strict';if(this!==undefined)throw Error('require receiver');requireCalls++;requireIds.push(id);return requireAction(id)};
        );
        const fatal = try self.engine.checked(c.JS_NewCFunction(self.engine.context, rawFatal, "depthNativeFatal", 0));
        defer self.engine.freeValue(fatal); try self.publish("depthNativeFatal", fatal);
        const ephemeral = try self.engine.checked(c.JS_NewCFunction(self.engine.context, makeEphemeral, "depthEphemeral", 1));
        defer self.engine.freeValue(ephemeral); try self.publish("depthEphemeral", ephemeral);
        if (create_depth) try self.create();
    }
    fn create(self: *Fixture) !void {
        const process = try self.get("actualProcess"); defer self.engine.freeValue(process);
        const require = try self.get("depthRequire"); defer self.engine.freeValue(require);
        const value = try tty.create(self.engine, .{ .process = process, .require = require, .safe_map = self.safe_map });
        const previous = self.depth; self.depth = value; self.engine.freeValue(previous);
        try self.publish("getColorDepth", value);
    }
    fn run(self: *Fixture, source: []const u8) !void {
        const value = try self.engine.eval(source, "native-tty-color-depth-control.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(value);
        try std.testing.expect(!c.JS_HasException(self.engine.context));
    }
    fn get(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context)); defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, name));
    }
    fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context)); defer self.engine.freeValue(global);
        if (c.JS_DefinePropertyValueStr(self.engine.context, global, name, a.duplicate(self.engine, value), c.JS_PROP_C_W_E) < 0)
            return error.ActualTtyDepthControlPublicationRequired;
    }
    fn privateField(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const roots = try functions.capturedRoots(self.engine, self.depth);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, roots[0], name));
    }
    fn reason(self: *Fixture) !c.JSValue {
        if (c.JS_HasException(self.engine.context)) return c.JS_GetException(self.engine.context);
        if (self.engine.captured_exception) |value| { self.engine.captured_exception = null; return value; }
        return error.ActualTtyDepthControlReasonRequired;
    }
    fn balanced(self: *Fixture) !void {
        try std.testing.expectEqual(@as(usize, 0), self.engine.native_exception_diagnostics_suppressed);
        try std.testing.expect(self.engine.native_fatal_invocation == null);
    }
    fn deinit(self: *Fixture) void {
        self.emit_fatal = false;
        if (self.engine_alive) {
            self.engine.freeValue(self.first_fatal);
            self.engine.freeValue(self.depth);
            self.engine.freeValue(self.native_require);
            self.engine.freeValue(self.safe_map);
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
fn retireProbe(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const fixture: *Fixture = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    fixture.retired += 1;
    if (fixture.emit_fatal) publishFatal(fixture);
}
fn releaseText(engine: *a.v.em.Engine, _: c.JSValue, _: *sync.Arguments, _: []const c.JSValue) !c.JSValue {
    return a.expression(engine, releaseLiteral, .{});
}
fn releaseLiteral(s: *a.Scope) !c.JSValue {
    return a.duplicate(s.engine, try s.text("10.0.14931"));
}
fn ephemeralBody(s: *a.Scope, fixture: *Fixture, callable: bool) !c.JSValue {
    if (fixture.probe_class == 0) {
        if (c.JS_NewClassID(s.engine.runtime, &fixture.probe_class) == 0) return error.OutOfMemory;
        const definition: c.JSClassDef = .{ .class_name = "Actual TTY expression retirement probe", .finalizer = retireProbe };
        if (c.JS_NewClass(s.engine.runtime, fixture.probe_class, &definition) < 0) return error.OutOfMemory;
    }
    const generation = try s.beforeAllocation();
    const probe = try s.checkedAllocation(c.JS_NewObjectClass(s.engine.context, fixture.probe_class), generation);
    _ = c.JS_SetOpaque(probe, fixture);
    if (!callable) return a.duplicate(s.engine, probe);
    return functions.createWithArguments(s.engine, "release", 0, true,
        .{ .formal_count = 0, .callback = releaseText }, &.{probe});
}
fn makeEphemeral(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = current(context);
    return a.expression(fixture.engine, ephemeralBody, .{fixture, argc > 0 and c.JS_ToBool(context, argv[0]) == 1}) catch |err|
        functions.failure(fixture.engine, err, 0);
}
fn expectFatal(fixture: *Fixture, source: []const u8) !void {
    try std.testing.expectError(error.JavaScriptException, fixture.engine.eval(source, "native-tty-fatal-control.js", c.JS_EVAL_TYPE_GLOBAL));
    fixture.emit_fatal = false;
    const caught = try fixture.reason(); defer fixture.engine.freeValue(caught);
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, caught, fixture.first_fatal));
    try std.testing.expect(c.JS_IsUncatchableError(caught));
    try fixture.balanced();
}

test "native tty color depth has original callable shape and no unrelated OS load" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\if(getColorDepth.name!=='getColorDepth'||getColorDepth.length!==0||!Object.hasOwn(getColorDepth,'prototype'))throw Error('callable shape');
        \\if(getColorDepth({})!==1||getColorDepth.call(null,{TMUX:true})!==24||requireCalls!==0)throw Error('detached original body');
        \\const result=new getColorDepth({});if(Object.getPrototypeOf(result)!==getColorDepth.prototype)throw Error('ordinary construction');
    );
    try f.balanced();
}
test "native tty color depth uses genuine installed OS release and caches only successful lazy resolution" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\actualProcess.platform='win32';const release=actualOS.release();const parts=release.split('.',3);
        \\const expected=+parts[0]>=10?(+parts[2]>=14931?24:+parts[2]>=10586?8:4):4;
        \\if(getColorDepth({})!==expected||requireCalls!==1||requireIds.join(',')!=='os')throw Error('actual native OS branch');
        \\requireAction=()=>{throw Error('OS cache ignored')};if(getColorDepth({})!==expected||requireCalls!==1)throw Error('actual cache');
    );
}
test "native tty color depth force color uses strict cases and two original Gets" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\for(const [force,depth] of [['',4],['1',4],['true',4],['2',8],['3',24],['0',1],['TRUE',1],[true,1],[false,1],[1,1],[null,1],[{},1],[Symbol(),1]]){if(getColorDepth({FORCE_COLOR:force})!==depth)throw Error('strict FORCE_COLOR')}
        \\let reads=0;const env={get FORCE_COLOR(){return ++reads===1?'first':'3'}};
        \\if(getColorDepth(env)!==24||reads!==2||requireCalls!==0)throw Error('force read twice');
        \\if(getColorDepth({FORCE_COLOR:false,get NODE_DISABLE_COLORS(){throw Error('invalid forced value touched disable')}})!==1)throw Error('force precedence');
    );
}
test "native tty color depth disable flags use definedness nonempty comparison and short circuit" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const order=[];const env={get FORCE_COLOR(){order.push('force')},get NODE_DISABLE_COLORS(){order.push('node');return false},get NO_COLOR(){throw Error('disable short circuit')}};
        \\if(getColorDepth(env)!==1||order.join(',')!=='force,node,node')throw Error('disable order');
        \\for(const flag of [null,false,0,{},Symbol()])if(getColorDepth({NO_COLOR:flag,TMUX:true})!==1)throw Error('disable is not truthiness');
        \\if(getColorDepth({NODE_DISABLE_COLORS:'',NO_COLOR:'',TMUX:true})!==24||getColorDepth({TERM:'dumb',TMUX:true})!==1)throw Error('empty and dumb');
    );
}
test "native tty color depth emits exact combined warning once on actual process receiver" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\let calls=0;actualProcess.emitWarning=function(message,kind){if(this!==actualProcess||kind!=='Warning'||message!=="The 'NODE_DISABLE_COLORS' and 'NO_COLOR' env is ignored due to the 'FORCE_COLOR' env being set.")throw Error('warning arguments');calls++};
        \\if(getColorDepth({FORCE_COLOR:'2',NODE_DISABLE_COLORS:'yes',NO_COLOR:'yes'})!==8||calls!==1)throw Error('first warning');
        \\if(getColorDepth({FORCE_COLOR:'3',get NO_COLOR(){throw Error('warned flag not honored')}})!==24||calls!==1)throw Error('warning cache');
    );
}
test "native tty color depth warning retries throws and preserves reentrant assignment timing" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const marker={};let calls=0;actualProcess.emitWarning=function(){calls++;if(calls===1)throw marker;if(calls===2)getColorDepth({FORCE_COLOR:'1',NO_COLOR:'yes'})};
        \\let reason;try{getColorDepth({FORCE_COLOR:'1',NO_COLOR:'yes'})}catch(e){reason=e}if(reason!==marker||calls!==1)throw Error('warning throw');
        \\if(getColorDepth({FORCE_COLOR:'1',NO_COLOR:'yes'})!==4||calls!==3)throw Error('warning reentry');
        \\getColorDepth({FORCE_COLOR:'1',NO_COLOR:'yes'});if(calls!==3)throw Error('warning assigned too early or not cached');
    );
}
test "native tty color depth Windows thresholds preserve original split limit and major condition" {
    inline for (.{ .{ "6.3.14931", 4 }, .{ "10.0.10585", 4 }, .{ "10.0.10586", 8 },
        .{ "10.0.14930", 8 }, .{ "10.0.14931.more", 24 }, .{ "11.0.0", 4 }, .{ "NaN.0.14931", 4 } }) |row|
    {
        var f: Fixture = undefined; try f.init(true); defer f.deinit();
        const release = try f.engine.checked(c.JS_NewString(f.engine.context, row[0])); defer f.engine.freeValue(release);
        try f.publish("releaseInput", release);
        try f.publish("expectedDepth", c.JS_NewInt32(f.engine.context, row[1]));
        try f.run(
            \\actualProcess.platform='win32';requireAction=()=>({release(){'use strict';if(this!==undefined)throw Error('release receiver');releaseCalls++;return releaseInput}});
            \\if(getColorDepth({})!==expectedDepth||getColorDepth({})!==expectedDepth||releaseCalls!==1)throw Error('Windows thresholds');
        );
    }
}
test "native tty color depth lazy require member and release failures do not publish cache" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\actualProcess.platform='win32';const markers=[{},{},{}];let stage=0;
        \\requireAction=()=>{stage++;if(stage===1)throw markers[0];if(stage===2)return{get release(){throw markers[1]}};if(stage===3)return{release(){throw markers[2]}};return{release(){return'10.0.14931'}}};
        \\for(let i=0;i<3;i++){let reason;try{getColorDepth({})}catch(e){reason=e}if(reason!==markers[i])throw Error('lazy original reason')}
        \\if(getColorDepth({})!==24||getColorDepth({})!==24||requireCalls!==4)throw Error('failed lazy cache retained');
    );
}
test "native tty color depth outer OS release assignment wins after synchronous reentry" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\actualProcess.platform='win32';let nested;
        \\requireAction=()=>{if(requireCalls===1){nested=getColorDepth({});return{release(){return'10.0.14931'}}}return{release(){return'10.0.10586'}}};
        \\if(getColorDepth({})!==24||nested!==8||requireCalls!==2||getColorDepth({})!==24)throw Error('outer assignment lost');
    );
}
test "native tty color depth captured split retains original Symbol split dispatch and undefined retry" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\actualProcess.platform='win32';const raw={toString(){throw Error('split override should receive raw receiver')}};let calls=0;
        \\requireAction=()=>({release(){return raw}});String.prototype[Symbol.split]=function(value,limit){if(value!==raw||String(this)!=='.'||limit!==3)throw Error('split arguments');return ++calls===1?undefined:[10,0,14931]};
        \\let reason;try{getColorDepth({})}catch(e){reason=e}if(!(reason instanceof TypeError))throw Error('undefined cache first failure');
        \\if(getColorDepth({})!==24||getColorDepth({})!==24||requireCalls!==2||calls!==2)throw Error('undefined retry');
    );
}
test "native tty color depth Windows cached property coercions use unary plus and reject BigInt" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\actualProcess.platform='win32';const log=[];let bigint=false;
        \\String.prototype[Symbol.split]=()=>({get 0(){log.push('major');return{[Symbol.toPrimitive](hint){log.push(hint);return 10}}},get 2(){log.push('build');return bigint?14931n:{[Symbol.toPrimitive](hint){log.push(hint);return 14931}}}});
        \\requireAction=()=>({release(){return'ignored'}});
        \\if(getColorDepth({})!==24||log.join(',')!=='major,number,build,number')throw Error('unary plus order');
        \\bigint=true;let reason;try{getColorDepth({})}catch(e){reason=e}if(!(reason instanceof TypeError)||requireCalls!==1)throw Error('BigInt accepted or cache recaptured');
    );
}
test "native tty color depth retains builtin process while reading live env and platform properties" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\let reads=0;Object.defineProperty(actualProcess,'env',{configurable:true,get(){reads++;return{FORCE_COLOR:'3'}}});
        \\globalThis.process={env:{FORCE_COLOR:'0'},platform:'win32'};
        \\if(getColorDepth()!==24||getColorDepth(undefined)!==24||reads!==2)throw Error('builtin process binding');
        \\if(getColorDepth({TMUX:true})!==24||reads!==2)throw Error('explicit parameter defaulted');
        \\actualProcess.platform='win32';requireAction=()=>({release(){return'6.0.0'}});if(getColorDepth({TMUX:true})!==4)throw Error('current platform precedence');
    );
}

test "native tty color depth tmux and Azure gates retain own property semantics" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\if(getColorDepth({TMUX:'',TF_BUILD:undefined,AGENT_NAME:undefined})!==4||getColorDepth({TMUX:1,CI:true})!==24)throw Error('tmux Azure order');
        \\if(getColorDepth(Object.create({TF_BUILD:true,AGENT_NAME:true}))!==1)throw Error('inherited Azure');
        \\const log=[];const env=new Proxy({TF_BUILD:0,AGENT_NAME:0},{getOwnPropertyDescriptor(t,k){log.push(k);return Reflect.getOwnPropertyDescriptor(t,k)}});
        \\if(getColorDepth(env)!==4||log.join(',')!=='TF_BUILD,AGENT_NAME')throw Error('real hasOwn sequence');
    );
}
test "native tty color depth CI uses exact real Map order and hasOwn checks" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    const map = try f.privateField("ci_map"); defer f.engine.freeValue(map);
    try f.publish("actualCIMapForControl", map);
    try f.run(
        \\if(Object.getOwnPropertyDescriptor(Map.prototype,'size').get.call(actualCIMapForControl)!==8||!Object.isFrozen(Object.getPrototypeOf(actualCIMapForControl)))throw Error('genuine SafeMap');
        \\for(const [key,depth] of [['APPVEYOR',8],['BUILDKITE',8],['CIRCLECI',24],['DRONE',8],['GITEA_ACTIONS',24],['GITHUB_ACTIONS',24],['GITLAB_CI',8],['TRAVIS',8]])if(getColorDepth({CI:false,[key]:undefined})!==depth)throw Error('CI table '+key);
        \\const order=[];const env=new Proxy({CI:undefined,APPVEYOR:undefined,CIRCLECI:true},{getOwnPropertyDescriptor(t,k){order.push(k);return Reflect.getOwnPropertyDescriptor(t,k)}});
        \\if(getColorDepth(env)!==8||order.join(',')!=='TF_BUILD,CI,APPVEYOR')throw Error('CI ordered own checks');
        \\if(getColorDepth({CI:true,CI_NAME:'codeship'})!==8||getColorDepth({CI:true,TEAMCITY_VERSION:'10.1'})!==1)throw Error('CI early result');
        \\const inherited=Object.assign(Object.create({APPVEYOR:1}),{CI:1});if(getColorDepth(inherited)!==1)throw Error('inherited CI provider');
    );
}
test "native tty color depth actual SafeMap iteration observes its real entries and closes early returns" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    const map = try f.privateField("ci_map"); defer f.engine.freeValue(map); try f.publish("actualCIMapForControl", map);
    try f.run(
        \\actualCIMapForControl.clear();const key={toString(){return'CUSTOM_CI'}};const color={marker:'actual map value'};actualCIMapForControl.set(key,color);
        \\if(getColorDepth({CI:1,CUSTOM_CI:1})!==color)throw Error('CI map replaced by static lookup');
        \\actualCIMapForControl.delete(key);actualCIMapForControl.set('GITHUB_ACTIONS',24);
        \\if(getColorDepth({CI:1,GITHUB_ACTIONS:1})!==24)throw Error('actual map mutation not used');
    );
}
test "native tty color depth TeamCity uses inherited in trap and exact version regexp" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\for(const [version,depth] of [['8.9.1',1],['9.0.1',1],['9.01.0',4],['9.1.0',4],['10.0',4],['999.1',4],['v10.1',1]])if(getColorDepth(Object.create({TEAMCITY_VERSION:version}))!==depth)throw Error('TeamCity '+version);
        \\const log=[];const env=new Proxy({},{has(t,k){log.push('has:'+k);return k==='TEAMCITY_VERSION'},get(t,k){if(k==='TEAMCITY_VERSION'){log.push('version');return{toString(){log.push('string');return'10.1'}}}}});
        \\if(getColorDepth(env)!==4||log.join(',')!=='has:TEAMCITY_VERSION,version,string')throw Error('in and regex coercion');
        \\for(const value of [false,1,'',Symbol()]){let reason;try{getColorDepth(value)}catch(e){reason=e}if(!(reason instanceof TypeError))throw Error('primitive in RHS boxed')}
    );
}
test "native tty color depth terminal program cases preserve repeated version Get and short circuit" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\for(const [program,depth] of [['HyperTerm',24],['MacTerm',24],['Apple_Terminal',8]])if(getColorDepth({TERM_PROGRAM:program,get COLORTERM(){throw Error('program short circuit')}})!==depth)throw Error('program table');
        \\let reads=0;const newer={TERM_PROGRAM:'iTerm.app',get TERM_PROGRAM_VERSION(){reads++;return reads===1?'first':'3.0'}};
        \\if(getColorDepth(newer)!==24||reads!==2)throw Error('iTerm double Get');
        \\if(getColorDepth({TERM_PROGRAM:'iTerm.app',TERM_PROGRAM_VERSION:''})!==8||getColorDepth({TERM_PROGRAM:'iTerm.app',TERM_PROGRAM_VERSION:'2.9'})!==8)throw Error('iTerm old or absent');
    );
}
test "native tty color depth COLORTERM comparisons read twice and ordinary fallback remains last" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\let reads=0;const env={get COLORTERM(){return ++reads===1?'first':'24bit'},get TERM(){return reads===0?undefined:(()=>{throw Error('truecolor fell through')})()}};
        \\if(getColorDepth(env)!==24||reads!==2)throw Error('COLORTERM second comparison');
        \\if(getColorDepth({COLORTERM:'TRUECOLOR'})!==4||getColorDepth({COLORTERM:false})!==1||getColorDepth({COLORTERM:'color',TERM:'xterm-256color'})!==8)throw Error('fallback order');
    );
}
test "native tty color depth original ordinary TERM table and every regexp are retained" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\for(const name of ['eterm','cons25','console','cygwin','dtterm','gnome','hurd','jfbterm','konsole','kterm','mlterm','putty','st'])if(getColorDepth({TERM:name.toUpperCase()})!==4)throw Error('TERM '+name);
        \\for(const name of ['mosh','rxvt-unicode-24bit','terminator','xterm-kitty'])if(getColorDepth({TERM:name.toUpperCase()})!==24)throw Error('true TERM '+name);
        \\for(const name of ['ansi-any','withcolor','linux-alt','direct-all','con80x25','rxvt-new','screen-new','xterm-new','vt100-x','vt220-x'])if(getColorDepth({TERM:name})!==4)throw Error('regexp '+name);
        \\if(getColorDepth({TERM:'xterm-256color'})!==8||getColorDepth({TERM:'a-truecolor-b'})!==24||getColorDepth({TERM:'TRUECOLOR'})!==4)throw Error('case-sensitive early regex');
    );
}
test "native tty color depth TERM coercions and five property reads follow original order" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\let reads=0;const log=[];const values=['not-dumb',{}, {toString(){log.push('regex1');return'unknown'}},{toString(){log.push('regex2');return'unknown'}},{toString(){log.push('lower');return'MOSH'}}];
        \\const env={get TERM(){log.push('get'+(++reads));return values[reads-1]}};
        \\if(getColorDepth(env)!==24||log.join(',')!=='get1,get2,get3,regex1,get4,regex2,get5,lower')throw Error('TERM original evaluation '+log);
    );
}
test "native tty color depth inherited TERM lookup is ordinary and repeats successful Get" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\let reads=0;const result={owned:true};Object.defineProperty(Object.prototype,'depthspecial',{configurable:true,get(){reads++;return reads===1?true:result}});
        \\try{if(getColorDepth({TERM:'DEPTHSPECIAL'})!==result||reads!==2)throw Error('two ordinary inherited Gets')}finally{delete Object.prototype.depthspecial}
        \\if(getColorDepth({TERM:'constructor'})!==Object)throw Error('TERM map incorrectly null-prototyped');
    );
}
test "native tty color depth captures original primordials and genuine SafeMap before guest mutation" {
    var f: Fixture = undefined; try f.init(false); defer f.deinit();
    try f.run(
        \\Object.entries=()=>{throw Error('late entries')};Object.prototype.hasOwnProperty=()=>{throw Error('late hasOwn')};
        \\Array.prototype.some=()=>{throw Error('late some')};String.prototype.toLowerCase=()=>{throw Error('late lower')};
        \\String.prototype.split=()=>{throw Error('late split')};RegExp.prototype.exec=()=>{throw Error('late exec')};
        \\globalThis.Map=function(){throw Error('late Map')};globalThis.RegExp=function(){throw Error('late RegExp')};
    );
    try f.create();
    try f.run(
        \\if(getColorDepth({CI:1,GITHUB_ACTIONS:1})!==24||getColorDepth({TERM:'ANSI'})!==4||getColorDepth({TERM:'MoSh'})!==24)throw Error('genuine captured operators');
        \\actualProcess.platform='win32';requireAction=()=>({release(){return'10.0.14931'}});if(getColorDepth({})!==24)throw Error('captured split');
    );
}
test "native tty color depth genuine Array some skips holes and consults inherited indexed entries" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    const regexes = try f.privateField("regexes"); defer f.engine.freeValue(regexes); try f.publish("actualTermRegexesForControl", regexes);
    try f.run(
        \\actualTermRegexesForControl.length=2;delete actualTermRegexesForControl[0];actualTermRegexesForControl[1]=/absent/;
        \\if(getColorDepth({TERM:'holemark'})!==1)throw Error('some visited absent hole');
        \\let hits=0;Object.defineProperty(Array.prototype,'0',{configurable:true,get(){hits++;return /holemark/}});
        \\try{if(getColorDepth({TERM:'holemark'})!==4||hits!==1)throw Error('inherited some element')}finally{delete Array.prototype[0]}
    );
}
test "native tty color depth ordinary environment errors preserve exact thrown identity" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const marker={};for(const env of [{get FORCE_COLOR(){throw marker}},{TEAMCITY_VERSION:{toString(){throw marker}}},{TERM:{toString(){throw marker}}}]){let reason;try{getColorDepth(env)}catch(e){reason=e}if(reason!==marker)throw Error('original thrown identity')}
        \\for(const env of [null]){let reason;try{getColorDepth(env)}catch(e){reason=e}if(!(reason instanceof TypeError))throw Error('null argument')}
    );
}
test "native tty color depth discarded disable operand fatal retires before second property Get" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\globalThis.disableReads=0;globalThis.disableEnvironment={get NODE_DISABLE_COLORS(){disableReads++;return depthEphemeral(false)}};
    );
    f.emit_fatal = true;
    try expectFatal(&f, "getColorDepth(disableEnvironment)");
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    try f.run("if(disableReads!==1)throw Error('read after discarded operand fatal')");
}
test "native tty color depth warning result fatal precedes warned assignment and preserves retry" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run("globalThis.warningCalls=0;actualProcess.emitWarning=function(){warningCalls++;return depthEphemeral(false)};");
    f.emit_fatal = true;
    try expectFatal(&f, "getColorDepth({FORCE_COLOR:'1',NO_COLOR:'yes'})");
    const warned = try f.privateField("warned"); defer f.engine.freeValue(warned);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, warned, c.JS_NewBool(f.engine.context, false)));
    try f.run("if(getColorDepth({FORCE_COLOR:'1',NO_COLOR:'yes'})!==4||warningCalls!==2)throw Error('warning retry after return retirement')");
}
test "native tty color depth release local survives through cache assignment and retires at original terminal" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run("actualProcess.platform='win32';requireAction=()=>({get release(){return depthEphemeral(true)}});");
    f.emit_fatal = true;
    try expectFatal(&f, "getColorDepth({})");
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    const release = try f.privateField("OSRelease"); defer f.engine.freeValue(release);
    try std.testing.expect(!c.JS_IsUndefined(release));
    try f.run("if(getColorDepth({})!==24||requireCalls!==1)throw Error('release retired before assignment or cache lost')");
}
test "native tty color depth current native fatal in environment Get prevents later branches" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run("globalThis.laterReads=0;globalThis.fatalEnvironment={get FORCE_COLOR(){depthNativeFatal();return undefined},get NODE_DISABLE_COLORS(){laterReads++;return 'yes'}};");
    try expectFatal(&f, "getColorDepth(fatalEnvironment)");
    try f.run("if(laterReads!==0||requireCalls!==0)throw Error('continued after current fatal')");
}
test "native tty color depth rejects a foreign SafeMap and never lazily recaptures globals" {
    var f: Fixture = undefined; try f.init(false); defer f.deinit();
    const process = try f.get("actualProcess"); defer f.engine.freeValue(process);
    const require = try f.get("depthRequire"); defer f.engine.freeValue(require);
    const foreign = try f.get("Map"); defer f.engine.freeValue(foreign);
    try std.testing.expectError(error.ActualTtySafeMapIdentityChanged,
        tty.create(f.engine, .{ .process = process, .require = require, .safe_map = foreign }));
    try std.testing.expect(c.JS_IsUndefined(f.depth));
    try f.create();
    try f.run("if(getColorDepth({CI:1,CIRCLECI:1})!==24)throw Error('valid retry after foreign private assembly')");
}
