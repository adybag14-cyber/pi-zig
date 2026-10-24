//! Focused actual VM controls for original initializeDebugEnv/debuglog.
//! Literal comparison uses only the pinned ordinary source body. No Node child,
//! invented output implementation, timer trace stub or environment default.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const debuglog = @import("extensions/native_node_debuglog.zig");
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
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine,
            std.testing.io, &self.environment, &.{"native-debuglog-control"});
        try @import("extensions/native_node_os.zig").install(self.engine);
        self.engine.host_control_context = self;
        try self.engine.bindFunction("debugFatal", rawFatal, 0);
        try self.engine.bindFunction("debugEphemeral", ephemeral, 0);
        try self.engine.bindFunction("debugAcquire", rawAcquire, 0);
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
        try self.evaluate(@embedFile("fixtures/native-node-debuglog-reference.js"));
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

test "native debuglog authentic private assembly preserves original callable shapes and lazy initial state" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\if(debugAcquire()!==NativeDebug||I.name!=='initializeDebugEnv'||I.length!==1||D.name!=='debuglog'||D.length!==2)throw Error('actual one owner');
        \\if(!Object.hasOwn(I,'prototype')||!Object.hasOwn(D,'prototype'))throw Error('ordinary function construction');
        \\const logger=D('x');const descriptor=Object.getOwnPropertyDescriptor(logger,'enabled');
        \\if(logger.name!=='logger'||logger.length!==0||Object.hasOwn(logger,'prototype')||descriptor.set!==undefined||!descriptor.configurable||!descriptor.enumerable)throw Error('logger shape');
        \\if(lines.length||warnings.length)throw Error('eager process observation');
        \\if(!(reason(()=>logger.enabled) instanceof TypeError)||!(reason(()=>logger()) instanceof TypeError))throw Error('uninitialized predicate was defaulted');
        \\I('x');if(logger.enabled!==true)throw Error('retry after original initialization');
        \\}
    );
    try f.balanced();
}

test "native debuglog rejects foreign require and missing actual bootstrap without publication" {
    var f: Fixture = undefined; try f.init(.{ .create_debug = false }); defer f.deinit();
    try f.evaluate("globalThis.foreignRequire=id=>Q(id);");
    const foreign = try f.readGlobal("foreignRequire"); defer f.engine.freeValue(foreign);
    try std.testing.expectError(error.ActualDebuglogRequireIdentityChanged,
        debuglog.acquire(f.engine, .{ .require = foreign }));
    try std.testing.expect(!f.engine.native_module_values.contains("pi-native:private/initialized-ordinary-debuglog"));
    try std.testing.expect(!f.engine.native_module_names.contains("internal/util/debuglog"));
    try std.testing.expect((try f.engine.requireBuiltin("internal/util/debuglog")) == null);
    try f.createDebug();
}
test "native debuglog requires actual inspector and complete selected require admissions" {
    var f: Fixture = undefined;
    try f.init(.{ .prepare_arguments = false, .create_tty = false, .install_colors = false, .create_debug = false });
    defer f.deinit();
    try std.testing.expectError(error.RequiredBootstrappedActualDebuglogInspector,
        debuglog.acquire(f.engine, .{ .require = f.native_require }));
    try std.testing.expect(!f.engine.native_module_values.contains("pi-native:private/initialized-ordinary-debuglog"));
    var absent: Fixture = undefined;
    try absent.init(.{ .prepare_require = false, .create_tty = false, .install_colors = false, .create_debug = false });
    defer absent.deinit();
    try std.testing.expectError(error.RequiredBootstrappedActualDebuglogRequire,
        debuglog.acquire(absent.engine, .{ .require = c.pi_js_undefined() }));
    absent.native_require = try internal.acquire(absent.engine, .{ .bindings = &.{.{ .id = "os", .module_name = "node:os" }} });
    try std.testing.expectError(error.InternalBuiltinOwnerAdmissionConflict,
        debuglog.acquire(absent.engine, .{ .require = absent.native_require }));
}
test "native debuglog requires actual installed process before capture" {
    var f: Fixture = undefined; try f.init(.{ .create_debug = false }); defer f.deinit();
    const removed = f.engine.native_module_values.fetchRemove("node:process").?;
    defer f.engine.native_module_values.putAssumeCapacity("node:process", removed.value);
    try std.testing.expectError(error.RequiredActualDebuglogProcess,
        debuglog.acquire(f.engine, .{ .require = f.native_require }));
    try std.testing.expect(!f.engine.native_module_values.contains("pi-native:private/initialized-ordinary-debuglog"));
}

test "native debuglog initializer falsy inputs preserve legitimate disabled noop and callback-once behavior" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\for(const value of [undefined,null,false,0,0n,'',NaN]){
        \\ I(value);let calls=0,actual;const log=D('module',f=>{calls++;actual=f});
        \\ if(log('one')!==undefined||calls!==1||actual.name!=='noop'||actual.enabled!==false)throw Error('disabled first call');
        \\ log('two','three',4);if(calls!==1||log.enabled!==false||lines.length!==0)throw Error('disabled fast path');
        \\}
        \\}
    );
    try f.balanced();
}

test "native debuglog regex construction preserves exact wildcard comma escaping and case insensitive matching" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('http*,one.two,a+b,a|b,[set],b\\c,é');
        \\for(const name of ['HTTP','http2','one.two','A+B','a|b','[set]','b\\c','É'])if(!D(name).enabled)throw Error('missing exact match '+name);
        \\for(const name of ['xhttp','oneXtwo','ab','a','b','set','bc'])if(D(name).enabled)throw Error('unescaped match '+name);
        \\if(warnings.length||lines.length)throw Error('enabled getter must not initialize implementation');
        \\}
    );
    try f.balanced();
}

test "native debuglog original initialization method chain receives exact patterns receivers and coercion order" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\const events=[];const first={replaceAll(a,b){events.push('first:'+a+':'+b);return second}};
        \\const second={replaceAll(a,b){events.push('second:'+a+':'+b);return final}};
        \\const final={[Symbol.toPrimitive](hint){events.push('coerce:'+hint);return 'x'}};
        \\const input={replace(pattern,replacement){
        \\ if(this!==input||pattern.source!==/[|\\{}()[\]^$+?.]/g.source||pattern.flags!=='g'||replacement!=='\\$&')throw Error('exact first call');
        \\ events.push('replace');return first;
        \\}};I(input);
        \\if(events.join('|')!=='replace|first:*:.*|second:,:$|^|coerce:string')throw Error(JSON.stringify(events));
        \\if(!D('x').enabled||D('xx').enabled)throw Error('final replacement assignment');
        \\}
    );
    try f.balanced();
}

test "native debuglog failed reinitialization clears implementation table before retaining the previous predicate" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('x');let old;D('x',f=>old=f)('a');const failure={};if(reason(()=>I({replace(){throw failure}}))!==failure)throw Error('original error');
        \\let fresh;const next=D('x',f=>fresh=f);if(next.enabled!==true)throw Error('old predicate replaced on failure');next('b');
        \\if(old===fresh||lines.join('')!=='X 17: a\nX 17: b\n')throw Error('cache not reset before failed replace');
        \\}
    );
    try f.balanced();
}

test "native debuglog logger creation defers set coercion and enabled memoization preserves the captured uppercase set" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\let count=0;const object={toString(){count++;return 'module'}};
        \\I('module');const log=D(object);if(count!==0)throw Error('eager uppercase');
        \\if(log.enabled!==true||log.enabled!==true||count!==1)throw Error('memoized enabled');
        \\log('a');if(count!==1||lines[0]!=='MODULE 17: a\n')throw Error('uppercase formal capture');
        \\if(!(reason(()=>D(Symbol('bad')).enabled) instanceof TypeError))throw Error('symbol coercion');
        \\}
    );
    try f.balanced();
}

test "native debuglog callback receives original descriptor and assigned implementation before reentry" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('x');let log,called=0,implementation;log=D('x',fn=>{
        \\ called++;implementation=fn;const d=Object.getOwnPropertyDescriptor(fn,'enabled');
        \\ if(d.set!==undefined||!d.configurable||!d.enumerable||fn.name!=='debug'||fn.length!==0||!Object.hasOwn(fn,'prototype')||fn.enabled!==true)throw Error('callback shape');
        \\ log('inner');
        \\});log('outer');
        \\if(called!==1||lines.join('')!=='X 17: inner\nX 17: outer\n'||implementation.enabled!==true)throw Error('assigned-before-callback');
        \\}
    );
    try f.balanced();
}

test "native debuglog callback failure retains the assigned implementation and never repeats callback" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('x');let called=0;const failure={};const log=D('x',()=>{called++;throw failure});
        \\if(reason(()=>log('blocked'))!==failure||lines.length!==0)throw Error('callback failure precedence');
        \\log('after');if(called!==1||lines[0]!=='X 17: after\n')throw Error('implementation assignment lost');
        \\}
    );
    try f.balanced();
}

test "native debuglog enabled-first disabled path skips callback while ordinary first call invokes it" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('x');let calls=0;const skipped=D('y',()=>calls++);if(skipped.enabled!==false)throw Error('disabled');
        \\skipped();skipped(1,2,3);if(calls!==0)throw Error('disabled logger entered wrapper');
        \\const entered=D('z',()=>calls++);entered();if(calls!==1||lines.length)throw Error('first-call disabled callback');
        \\}
    );
    try f.balanced();
}

test "native debuglog same set shares implementation while logger-local enabled values remain original" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('x');let one,two;D('x',fn=>one=fn)('a');D('X',fn=>two=fn)('b');
        \\if(one!==two)throw Error('set cache');I('');const old=one;let disabled;
        \\D('x',fn=>disabled=fn)('ignored');if(disabled===old||disabled.enabled!==false||old.enabled!==true)throw Error('cache reset changed existing closure');
        \\old('still');if(lines[2]!=='X 17: still\n')throw Error('old implementation lost');
        \\}
    );
    try f.balanced();
}

test "native debuglog original shared noop enabled descriptor remains configurable across distinct sets" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('');let a,b;D('a',f=>a=f)();D('b',f=>b=f)();
        \\if(a!==b||a.enabled!==false||Object.keys(a).join(',')!=='enabled')throw Error('shared noop');
        \\Object.defineProperty(a,'enabled',{value:'changed',configurable:true});let selected;D('c',f=>selected=f)();
        \\if(selected!==a||selected.enabled!==false||typeof Object.getOwnPropertyDescriptor(selected,'enabled').get!=='function')throw Error('ordinary descriptor replacement');
        \\}
    );
    try f.balanced();
}

test "native debuglog cached logger state follows original reinitialization behavior" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\const original=makeOriginalDebuglog();
        \\function exercise(api){api.initializeDebugEnv('x');const old=api.debuglog('x');const enabled=old.enabled;api.initializeDebugEnv('');old('retained');const after=old.enabled;const fresh=api.debuglog('x').enabled;return [enabled,after,fresh]}
        \\lines.length=0;const nativeResult=exercise(NativeDebug),nativeLines=lines.slice();lines.length=0;
        \\const literalResult=exercise(original);if(JSON.stringify(nativeResult)!==JSON.stringify(literalResult)||JSON.stringify(nativeLines)!==JSON.stringify(lines))throw Error('reset/capture mismatch');
        \\}
    );
    try f.balanced();
}

test "native debuglog actual formatter handles all dispatcher argument cardinalities and captures pid lazily" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('net');const log=D('net');P.pid=18;log();P.pid=19;log('one');log('%s:%d','x',4);log('a','b','c','d');
        \\if(lines.join('')!=='NET 18: \nNET 18: one\nNET 18: x:4\nNET 18: a b c d\n')throw Error(JSON.stringify(lines));
        \\D('NET')('shared');if(lines[4]!=='NET 18: shared\n')throw Error('pid recaptured from same set');
        \\}
    );
    try f.balanced();
}

test "native debuglog complete color owner and actual internal tty produce real ANSI formatting" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\P.env.FORCE_COLOR='1';I('x');D('x')('%d',4);
        \\if(lines.length!==1||!lines[0].includes('\x1b[')||!lines[0].includes('X '))throw Error('actual forced color path missing');
        \\if(Q('internal/tty')!==TT||Q('internal/util/colors')!==Colors)throw Error('actual providers not retained');
        \\}
    );
    try f.balanced();
}

test "native debuglog preserves shouldColorize Get and two live stderr reads around actual numeric formatting" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('x');const events=[],actualShould=Colors.shouldColorize;
        \\Object.defineProperty(Colors,'shouldColorize',{configurable:true,get(){events.push('get-should');return actualShould}});
        \\let reads=0;Object.defineProperty(P,'stderr',{configurable:true,get(){
        \\ events.push('stderr-'+(++reads));return reads===1?{get isTTY(){events.push('isTTY');return false}}:
        \\ {get write(){events.push('get-write');return function(s){events.push('write');lines.push(s)}}};
        \\}});
        \\D('x')('%d',{valueOf(){events.push('number');return 9}});
        \\if(events.join(',')!=='get-should,stderr-1,isTTY,number,stderr-2,get-write,write'||lines[0]!=='X 17: 9\n')throw Error(events);
        \\}
    );
    try f.balanced();
}

test "native debuglog warning laziness exact strings and per-set implementation cache match original" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('http*');const log=D('http');if(!log.enabled||warnings.length)throw Error('early warning');
        \\log('one');D('HTTP')('two');D('http2')('three');D('http3')('four');
        \\const suffix="' can expose sensitive data (such as passwords, tokens and authentication headers) in the resulting log.";
        \\if(warnings.length!==2||warnings[0]!=="Setting the NODE_DEBUG environment variable to 'http"+suffix||warnings[1]!=="Setting the NODE_DEBUG environment variable to 'http2"+suffix)throw Error(warnings);
        \\}
    );
    try f.balanced();
}

test "native debuglog warning reinitialization observes current assignment table after guest reentry" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\function exercise(api){lines.length=0;warnings.length=0;api.initializeDebugEnv('http');
        \\ let calls=0;P.emitWarning=function(s){warnings.push(s);if(calls++===0){api.initializeDebugEnv('http');api.debuglog('http')('inner')}};
        \\ let selected;api.debuglog('http',fn=>selected=fn)('outer');api.debuglog('http')('after');
        \\ return [calls,selected.enabled,lines.slice(),warnings.slice()];
        \\}
        \\const n=exercise(NativeDebug),r=exercise(makeOriginalDebuglog());
        \\if(JSON.stringify(n)!==JSON.stringify(r)||n[0]!==2)throw Error('warning cache reference mismatch');
        \\}
    );
    try f.balanced();
}

test "native debuglog pid getter failure retries before warning and leaves implementation cache absent" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('http');let attempts=0;const fail={};Object.defineProperty(P,'pid',{configurable:true,get(){if(attempts++===0)throw fail;return 23}});
        \\const log=D('http');if(reason(()=>log('blocked'))!==fail||warnings.length||lines.length)throw Error('pid failure order');
        \\log('after');if(attempts!==2||warnings.length!==1||lines[0]!=='HTTP 23: after\n')throw Error('pid retry');
        \\}
    );
    try f.balanced();
}

test "native debuglog actual colors admission failure is retryable without redoing implementation callback" {
    var f: Fixture = undefined; try f.init(.{ .install_colors = false }); defer f.deinit();
    try f.evaluate(
        \\I('x');globalThis.callbackCount=0;globalThis.retryLogger=D('x',()=>callbackCount++);
        \\if(!reason(()=>retryLogger('before'))||callbackCount!==1||lines.length)throw Error('missing real colors admitted');
    );
    try std.testing.expect(!f.engine.native_module_values.contains("internal/util/colors"));
    try f.installColors();
    try f.evaluate("retryLogger('after');if(callbackCount!==1||lines[0]!=='X 17: after\\n')throw Error('real module retry');");
    try f.balanced();
}

test "native debuglog ordinary spread to actual formatWithOptions remains guest observable" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\function exercise(api){lines.length=0;api.initializeDebugEnv('x');const log=api.debuglog('x');let ordinary=0;
        \\ const saved=Array.prototype[Symbol.iterator];Array.prototype[Symbol.iterator]=function*(){ordinary++;yield 'replacement'};
        \\ try{log('one','two','three')}finally{Array.prototype[Symbol.iterator]=saved}
        \\ return [ordinary,lines.slice()];
        \\}
        \\const n=exercise(NativeDebug),r=exercise(makeOriginalDebuglog());
        \\if(JSON.stringify(n)!==JSON.stringify(r)||n[0]!==1||n[1][0]!=='X 17: replacement\n')throw Error('safe/ordinary spread boundary');
        \\}
    );
    try f.balanced();
}

test "native debuglog safe dispatcher protects iteration even when disabled callback is reached with zero or many args" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('');let calls=0;const saved=Array.prototype[Symbol.iterator];
        \\Array.prototype[Symbol.iterator]=function(){throw Error('ordinary array iteration must not be consulted')};
        \\try{D('x',()=>calls++)();D('y',()=>calls++)(1,2,3,4)}finally{Array.prototype[Symbol.iterator]=saved}
        \\if(calls!==2||lines.length)throw Error('safe disabled dispatch');
        \\}
    );
    try f.balanced();
}

test "native debuglog pristine methods survive later prototype and constructor replacement" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('x');const originalUpper=String.prototype.toUpperCase,originalExec=RegExp.prototype.exec,originalDefine=Object.defineProperty;
        \\String.prototype.toUpperCase=function(){throw Error('poison upper')};RegExp.prototype.exec=function(){throw Error('poison exec')};Object.defineProperty=function(){throw Error('poison define')};
        \\try{const log=D('x');if(!log.enabled)throw Error('lost capture');log('captured')}finally{String.prototype.toUpperCase=originalUpper;RegExp.prototype.exec=originalExec;Object.defineProperty=originalDefine}
        \\if(lines[0]!=='X 17: captured\n')throw Error('actual primordial closure');
        \\}
    );
    try f.balanced();
}

test "native debuglog genuine SafeArrayIterator has frozen null prototype and original own iterator semantics" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\if(!Object.isFrozen(SA)||!Object.isFrozen(SA.prototype)||Object.getPrototypeOf(SA.prototype)!==null)throw Error('safe class');
        \\const list=[1,,3],it=new SA(list);if(Object.keys(it).join(',')!=='_iterator'||it[Symbol.iterator]()!==it)throw Error('own iterator');
        \\const first=it.next(),hole=it.next();list.push(4);const third=it.next(),fourth=it.next(),done=it.next();
        \\if(first.value!==1||hole.value!==undefined||third.value!==3||fourth.value!==4||!done.done)throw Error('actual live array iterator');
        \\if(!(reason(()=>SA([])) instanceof TypeError))throw Error('class callable');
        \\}
    );
    try f.balanced();
}

test "native debuglog SafeArrayIterator binds pristine call and bind before late class acquisition" {
    var f: Fixture = undefined; try f.init(.{ .create_debug = false }); defer f.deinit();
    try f.evaluate(
        \\globalThis.savedCall=Function.prototype.call;globalThis.savedBind=Function.prototype.bind;
        \\Function.prototype.call=function(){throw Error('late call capture')};Function.prototype.bind=function(){throw Error('late bind capture')};
    );
    try f.createDebug();
    try f.evaluate(
        \\I('');let calls=0;D('x',()=>calls++)(1,2,3);
        \\Function.prototype.call=savedCall;Function.prototype.bind=savedBind;
        \\if(calls!==1)throw Error('early uncurry');
    );
    try f.balanced();
}

test "native debuglog original named inspector functions stay captured after later record mutation" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\IM.inspect=()=>{throw Error('late inspect import')};IM.format=()=>{throw Error('late format import')};IM.formatWithOptions=()=>{throw Error('late formatter import')};
        \\I('x');D('x')('%d',8);if(lines[0]!=='X 17: 8\n')throw Error('named imports were read late');
        \\}
    );
    try f.balanced();
}

test "native debuglog complete nested owner wins inspect import reentry without publishing a partial owner" {
    var f: Fixture = undefined; try f.init(.{ .create_debug = false }); defer f.deinit();
    try f.evaluate(
        \\globalThis.captureCount=0;globalThis.actualInspect=IM.inspect;
        \\Object.defineProperty(IM,'inspect',{configurable:true,get(){captureCount++;
        \\ Object.defineProperty(IM,'inspect',{value:actualInspect,writable:true,configurable:true,enumerable:true});
        \\ globalThis.innerDebug=debugAcquire();return actualInspect;
        \\}});
    );
    try f.createDebug();
    try f.evaluate("if(captureCount!==1||NativeDebug!==innerDebug||debugAcquire()!==innerDebug)throw Error('nested completed owner');I('x');D('x')('ready');");
    try f.balanced();
}

test "native debuglog shouldColorize and stderr exceptions preserve actual error identity and retry" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('x');const log=D('x'),failure={},actualShould=Colors.shouldColorize;let reads=0;
        \\Object.defineProperty(Colors,'shouldColorize',{configurable:true,get(){if(reads++===0)throw failure;return actualShould}});
        \\if(reason(()=>log('blocked'))!==failure||lines.length)throw Error('colors error');
        \\log('after');if(lines[0]!=='X 17: after\n')throw Error('colors retry');
        \\Object.defineProperty(P,'stderr',{configurable:true,get(){throw failure}});
        \\if(reason(()=>log('later'))!==failure||lines.length!==1)throw Error('actual stderr error');
        \\}
    );
    try f.balanced();
}

test "native debuglog setter replacement of enabled property does not change its hidden lazy state" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\I('x');const log=D('x');Object.defineProperty(log,'enabled',{value:'public',writable:true});
        \\log('still');if(log.enabled!=='public'||lines[0]!=='X 17: still\n')throw Error('public descriptor changed internal state');
        \\}
    );
    try f.balanced();
}

test "native debuglog original undefined set and nonfunction callback behavior match literal source" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\{
        \\function exercise(api){api.initializeDebugEnv('undefined');lines.length=0;const log=api.debuglog(undefined,{});const enabled=log.enabled;log('message');return [enabled,lines.slice(),Object.keys(log)]}
        \\const n=exercise(NativeDebug),r=exercise(makeOriginalDebuglog());if(JSON.stringify(n)!==JSON.stringify(r))throw Error('formal/default mismatch');
        \\}
    );
    try f.balanced();
}

test "native debuglog uppercase assignment retires captured set before predicate with literal parity and first fatal identity" {
    inline for (.{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
        try f.evaluate(if (reference) "globalThis.API=makeOriginalDebuglog();" else "globalThis.API=NativeDebug;");
        try f.evaluate(
            \\API.initializeDebugEnv('x');globalThis.coercions=0;
            \\globalThis.probeLogger=(()=>{const set=debugEphemeral();set.toString=function(){coercions++;return 'x'};return API.debuglog(set)})();
        );
        f.emit_fatal = true;
        try expectFatal(&f, "probeLogger('blocked');");
        try std.testing.expectEqual(@as(usize, 1), f.retired);
        try f.evaluate("if(coercions!==1||lines.length)throw Error('formal retirement order');probeLogger('retry');if(coercions!==1||lines[0]!=='X 17: retry\\n')throw Error('published uppercase formal');");
    }
}
test "native debuglog callback ignored result retires after implementation assignment with literal parity" {
    inline for (.{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
        try f.evaluate(if (reference) "globalThis.API=makeOriginalDebuglog();" else "globalThis.API=NativeDebug;");
        try f.evaluate("API.initializeDebugEnv('x');globalThis.calls=0;globalThis.probeLogger=API.debuglog('x',()=>{calls++;return debugEphemeral()});");
        f.emit_fatal = true; try expectFatal(&f, "probeLogger('blocked');");
        try std.testing.expectEqual(@as(usize, 1), f.retired);
        try f.evaluate("if(calls!==1||lines.length)throw Error('callback result retirement');probeLogger('retry');if(calls!==1||lines[0]!=='X 17: retry\\n')throw Error('assigned implementation');");
    }
}
test "native debuglog actual write result retirement preserves side effect and first fatal with literal parity" {
    inline for (.{ false, true }) |reference| {
        var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
        try f.evaluate(if (reference) "globalThis.API=makeOriginalDebuglog();" else "globalThis.API=NativeDebug;");
        try f.evaluate(
            \\API.initializeDebugEnv('x');globalThis.probeLogger=API.debuglog('x');
            \\P.stderr.write=function(s){lines.push(s);return debugEphemeral()};
        );
        f.emit_fatal = true; try expectFatal(&f, "probeLogger('first');");
        try std.testing.expectEqual(@as(usize, 1), f.retired);
        try f.evaluate("if(lines[0]!=='X 17: first\\n')throw Error('write side effect lost');probeLogger('second');if(lines[1]!=='X 17: second\\n')throw Error('real subsequent log');");
        try std.testing.expectEqual(@as(usize, 2), f.retired);
    }
}
test "native debuglog current native fatal prevents later callback and dispatch effects" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\I('x');globalThis.callbackCalls=0;globalThis.probeLogger=D('x',()=>{callbackCalls++;debugFatal();throw {later:true}});
    );
    try expectFatal(&f, "probeLogger('blocked');");
    try f.evaluate("if(callbackCalls!==1||lines.length)throw Error('fatal callback precedence');probeLogger('after');if(callbackCalls!==1||lines[0]!=='X 17: after\\n')throw Error('assigned implementation on fatal');");
}
