//! Actual VM controls for the complete private internal/tty owner, the shared
//! ERR_OUT_OF_RANGE registration and original validateInteger. No Node child,
//! default environment, replacement native policy or fabricated module is used.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const tty = @import("extensions/native_node_internal_tty.zig");
const internal = @import("extensions/native_node_internal_builtin_require.zig");
const bootstrap = @import("extensions/native_node_argument_bootstrap.zig");
const errors = @import("extensions/native_node_argument_errors.zig");
const functions = @import("extensions/native_node_module_callable.zig");
const collections = @import("extensions/native_node_fs_collections.zig");
const c = a.c;
const Options = struct {
    prepare_arguments: bool = true,
    prepare_map: bool = true,
    prepare_require: bool = true,
    create_tty: bool = true,
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
    reentries: usize = 0,

    fn init(self: *Fixture, options: Options) !void {
        self.* = .{};
        self.environment = .init(std.testing.allocator); self.environment_alive = true;
        errdefer self.deinit();
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{}); self.engine_alive = true;
        self.native_require = c.pi_js_undefined(); self.safe_map = c.pi_js_undefined();
        self.module_value = c.pi_js_undefined(); self.first_fatal = c.pi_js_undefined();
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine,
            std.testing.io, &self.environment, &.{"native-internal-tty-control"});
        try @import("extensions/native_node_os.zig").install(self.engine);
        self.engine.host_control_context = self;
        try self.engine.bindFunction("internalTtyFatal", rawFatal, 0);
        try self.engine.bindFunction("internalTtyEphemeral", ephemeral, 0);
        try self.engine.bindFunction("internalTtyAcquire", rawAcquire, 0);
        try self.engine.bindFunction("internalTtyObserveReentry", observeReentry, 0);
        const process_record = self.engine.native_module_values.get("node:process").?;
        const process = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, process_record, "default"));
        defer self.engine.freeValue(process); try self.publish("P", process);
        try self.publish("ttyIntrinsics", self.engine.intrinsic_clone_operations);
        try self.evaluate(
            \\globalThis.actualPlatform=P.platform;P.platform='linux';
            \\globalThis.ttyReason=function(fn){try{fn()}catch(e){return e}throw Error('expected original failure')};
        );
        if (options.prepare_map) self.safe_map = try collections.acquireSafeMap(self.engine);
        if (options.prepare_arguments) try self.prepareArguments();
        if (options.prepare_require) {
            self.native_require = try internal.acquire(self.engine, .{ .bindings = &tty.bindings });
            try self.publish("Q", self.native_require);
        }
        if (options.create_tty) try self.createTty();
    }
    fn prepareArguments(self: *Fixture) !void {
        self.prepared = try bootstrap.prepare(self.engine);
        const selected = self.prepared.?;
        const range_class = try errors.outOfRange(self.engine); defer self.engine.freeValue(range_class);
        const hidden = try errors.hiddenOutOfRange(self.engine); defer self.engine.freeValue(hidden);
        const validator = try errors.validateInteger(self.engine); defer self.engine.freeValue(validator);
        try self.publish("R", range_class); try self.publish("HR", hidden); try self.publish("V", validator);
        try self.publish("AT", selected.arguments.invalid_arg_type);
        try self.publish("IM", selected.internal_inspect); try self.publish("IA", selected.assert_function);
        const registry = try @import("extensions/native_node_system_errors.zig").registry(self.engine);
        const marker = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, registry, "marker"));
        defer self.engine.freeValue(marker); try self.publish("NodeErrorMarker", marker);
        try self.evaluate(
            \\globalThis.originalRangeMessage=(()=>{
            \\ const NumberIsInteger=Number.isInteger,MathAbs=Math.abs,StringCtor=String;
            \\ const StringPrototypeSlice=Function.prototype.call.bind(String.prototype.slice);
            \\ function addNumericalSeparator(val){let res='';let i=val.length;const start=val[0]==='-'?1:0;for(;i>=start+4;i-=3){res=`_${StringPrototypeSlice(val,i-3,i)}${res}`;}return `${StringPrototypeSlice(val,0,i)}${res}`;}
            \\ return (str,range,input,replaceDefaultBoolean=false)=>{
            \\  IA(range,'Missing "range" argument');let msg=replaceDefaultBoolean?str:`The value of "${str}" is out of range.`;let received;
            \\  if(NumberIsInteger(input)&&MathAbs(input)>2**32)received=addNumericalSeparator(StringCtor(input));
            \\  else if(typeof input==='bigint'){received=StringCtor(input);if(input>2n**32n||input<-(2n**32n))received=addNumericalSeparator(received);received+='n'}
            \\  else received=IM.inspect(input);
            \\  msg+=` It must be ${range}. Received ${received}`;return msg;
            \\ };
            \\})();
            \\globalThis.originalValidateInteger=(()=>{
            \\ const NumberIsInteger=Number.isInteger,NumberMIN_SAFE_INTEGER=Number.MIN_SAFE_INTEGER,NumberMAX_SAFE_INTEGER=Number.MAX_SAFE_INTEGER;
            \\ const ERR_INVALID_ARG_TYPE=AT.HideStackFramesError,ERR_OUT_OF_RANGE=HR;
            \\ return (value,name,min=NumberMIN_SAFE_INTEGER,max=NumberMAX_SAFE_INTEGER)=>{
            \\  if(typeof value!=='number')throw new ERR_INVALID_ARG_TYPE(name,'number',value);
            \\  if(!NumberIsInteger(value))throw new ERR_OUT_OF_RANGE(name,'an integer',value);
            \\  if(value<min||value>max)throw new ERR_OUT_OF_RANGE(name,`>= ${min} && <= ${max}`,value);
            \\ };
            \\})();
        );
    }
    fn createTty(self: *Fixture) !void {
        const next = try tty.acquire(self.engine, .{ .require = self.native_require });
        self.engine.freeValue(self.module_value); self.module_value = next;
        try self.publish("TT", next);
        const colors = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, next, "hasColors"));
        defer self.engine.freeValue(colors); try self.publish("H", colors);
        const depth = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, next, "getColorDepth"));
        defer self.engine.freeValue(depth); try self.publish("D", depth);
        try self.evaluate(
            \\globalThis.originalHasColors=(()=>{
            \\ const getColorDepth=D,validateInteger=V;
            \\ return function hasColors(count,env){
            \\  if(env===undefined&&(count===undefined||(typeof count==='object'&&count!==null))){env=count;count=16}
            \\  else validateInteger(count,'count',2);
            \\  return count<=2**getColorDepth(env);
            \\ };
            \\})();
        );
    }
    fn evaluate(self: *Fixture, source: []const u8) !void {
        const value = try self.engine.eval(source, "native-internal-tty-control.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(value); try std.testing.expect(!c.JS_HasException(self.engine.context));
    }
    fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context)); defer self.engine.freeValue(global);
        if (c.JS_DefinePropertyValueStr(self.engine.context, global, name,
            a.duplicate(self.engine, value), c.JS_PROP_C_W_E) < 0) return error.ActualInternalTtyControlPublicationRequired;
    }
    fn readGlobal(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context)); defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, name));
    }
    fn takeReason(self: *Fixture) !c.JSValue {
        if (c.JS_HasException(self.engine.context)) return c.JS_GetException(self.engine.context);
        if (self.engine.captured_exception) |value| { self.engine.captured_exception = null; return value; }
        return error.ActualInternalTtyControlReasonRequired;
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
    return tty.acquire(fixture.engine, .{ .require = fixture.native_require }) catch |err|
        functions.failure(fixture.engine, err, 0);
}
fn observeReentry(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const fixture = current(context);
    const result = tty.acquire(fixture.engine, .{ .require = fixture.native_require });
    if (result) |unexpected| {
        fixture.engine.freeValue(unexpected);
        return c.JS_ThrowTypeError(context, "incomplete TTY owner escaped");
    } else |err| {
        if (err != error.ActualInternalTtyAssemblyReentry) return functions.failure(fixture.engine, err, 0);
    }
    fixture.reentries += 1;
    return c.pi_js_undefined();
}
fn retireProbe(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const fixture: *Fixture = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    fixture.retired += 1;
    if (fixture.emit_fatal) publishFatal(fixture);
}
fn ephemeralBody(s: *a.Scope, fixture: *Fixture) !c.JSValue {
    if (fixture.probe_class == 0) {
        if (c.JS_NewClassID(s.engine.runtime, &fixture.probe_class) == 0) return error.OutOfMemory;
        const definition: c.JSClassDef = .{ .class_name = "Actual internal TTY retirement probe", .finalizer = retireProbe };
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
    try std.testing.expectError(error.JavaScriptException, fixture.engine.eval(source, "native-internal-tty-fatal.js", c.JS_EVAL_TYPE_GLOBAL));
    fixture.emit_fatal = false;
    const reason = try fixture.takeReason(); defer fixture.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, reason, fixture.first_fatal));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try fixture.balanced();
}

test "native internal tty publishes one complete private module with original descriptors and callable shapes" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\if(Object.getPrototypeOf(TT)!==Object.prototype||Object.keys(TT).join(',')!=='getColorDepth,hasColors')throw Error('module object');
        \\for(const name of ['getColorDepth','hasColors']){const d=Object.getOwnPropertyDescriptor(TT,name);if(!d.writable||!d.enumerable||!d.configurable||d.get)throw Error('original export descriptor')}
        \\if(H.name!=='hasColors'||H.length!==2||!Object.hasOwn(H,'prototype')||D.name!=='getColorDepth'||D.length!==0)throw Error('function shapes');
        \\if(Q('internal/tty')!==TT||internalTtyAcquire()!==TT)throw Error('one completed owner');
        \\if(Object.getPrototypeOf(new H({FORCE_COLOR:'1'}))!==H.prototype)throw Error('ordinary construction');
    );
    try std.testing.expect(!f.engine.native_module_names.contains("internal/tty"));
    try std.testing.expect((try f.engine.requireBuiltin("internal/tty")) == null);
    try std.testing.expect(!@import("extensions/native_node_module_constructor.zig").isCreated(f.engine));
    try f.balanced();
}
test "native internal tty private require fails before actual assembly and retries the completed same backend" {
    var f: Fixture = undefined; try f.init(.{ .create_tty = false }); defer f.deinit();
    try f.evaluate(
        \\const early=ttyReason(()=>Q('internal/tty'));if(!early||Object.hasOwn(early,'getColorDepth'))throw Error('uninstalled backend escaped');
    );
    try std.testing.expect(!f.engine.native_module_values.contains("internal/tty"));
    try f.createTty();
    try internal.validateInstalled(f.engine, .{ .bindings = &tty.bindings });
    try f.evaluate("if(Q('internal/tty')!==TT||Q('internal/tty')!==TT)throw Error('completed private load');");
    const cached = try f.engine.checked(c.JS_GetPropertyStr(f.engine.context, f.engine.commonjs_cache, "internal/tty"));
    defer f.engine.freeValue(cached); try std.testing.expect(c.JS_IsUndefined(cached));
}
test "native internal tty assembly rejects a foreign require before any module publication" {
    var f: Fixture = undefined; try f.init(.{ .create_tty = false }); defer f.deinit();
    try f.evaluate("globalThis.foreignRequire=id=>Q(id);");
    const foreign = try f.readGlobal("foreignRequire"); defer f.engine.freeValue(foreign);
    try std.testing.expectError(error.ActualInternalTtyRequireIdentityChanged, tty.acquire(f.engine, .{ .require = foreign }));
    try std.testing.expect(!f.engine.native_module_values.contains("\x00native.internal.tty.owner"));
    try std.testing.expect(!f.engine.native_module_values.contains("internal/tty"));
    try f.createTty();
}
test "native internal tty requires the complete preselected private admission subset" {
    var f: Fixture = undefined; try f.init(.{ .prepare_require = false, .create_tty = false }); defer f.deinit();
    try std.testing.expectError(error.RequiredBootstrappedActualInternalBuiltinRequire, tty.acquire(f.engine, .{ .require = c.pi_js_undefined() }));
    f.native_require = try internal.acquire(f.engine, .{ .bindings = &.{.{ .id = "os", .module_name = "node:os" }} });
    try std.testing.expectError(error.InternalBuiltinOwnerAdmissionConflict, tty.acquire(f.engine, .{ .require = f.native_require }));
    try std.testing.expect(!f.engine.native_module_values.contains("internal/tty"));
}
test "native internal tty requires actual shared integer bootstrap and permits a later real completion" {
    var f: Fixture = undefined; try f.init(.{ .prepare_arguments = false, .create_tty = false }); defer f.deinit();
    try std.testing.expectError(error.ActualInternalErrorsNotInitialized, tty.acquire(f.engine, .{ .require = f.native_require }));
    try std.testing.expect(!f.engine.native_module_values.contains("\x00native.internal.tty.owner"));
    try f.prepareArguments(); try f.createTty();
    try f.evaluate("if(!H({FORCE_COLOR:'1'}))throw Error('actual later completion');");
}
test "native internal tty incoming ordinary pending survives armed quota before assembly allocation" {
    var f: Fixture = undefined; try f.init(.{ .create_tty = false }); defer f.deinit();
    const reason = try f.engine.checked(c.JS_NewObject(f.engine.context)); defer f.engine.freeValue(reason);
    _ = c.JS_Throw(f.engine.context, a.duplicate(f.engine, reason));
    c.JS_SetMemoryLimit(f.engine.runtime, 1);
    const result = tty.acquire(f.engine, .{ .require = f.native_require });
    c.JS_SetMemoryLimit(f.engine.runtime, f.engine.options.memory_limit);
    try std.testing.expectError(error.JavaScriptException, result);
    const selected = try f.takeReason(); defer f.engine.freeValue(selected);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, reason, selected));
    try std.testing.expect(!c.JS_IsUncatchableError(selected));
    try std.testing.expect(!f.engine.native_module_values.contains("\x00native.internal.tty.owner"));
    try std.testing.expect(!f.engine.native_module_values.contains("internal/tty"));
    try f.balanced();
}

test "native internal tty requires the actual cached SafeMap without late recapture" {
    var f: Fixture = undefined; try f.init(.{ .create_tty = false }); defer f.deinit();
    const saved = f.engine.native_module_values.fetchRemove("\x00native.fs.SafeMap").?.value;
    defer f.engine.freeValue(saved);
    try std.testing.expectError(error.RequiredBootstrappedActualInternalTtySafeMap, tty.acquire(f.engine, .{ .require = f.native_require }));
    try std.testing.expect(!f.engine.native_module_values.contains("internal/tty"));
    try f.engine.native_module_values.put(f.engine.gpa, "\x00native.fs.SafeMap", a.duplicate(f.engine, saved));
    try f.createTty();
}
test "native internal tty authenticates process default data without invoking a foreign accessor" {
    var f: Fixture = undefined; try f.init(.{ .create_tty = false }); defer f.deinit();
    try f.publish("processRecord", f.engine.native_module_values.get("node:process").?);
    try f.evaluate(
        \\globalThis.processDefaultReads=0;Object.defineProperty(processRecord,'default',{configurable:true,get(){processDefaultReads++;return {env:{FORCE_COLOR:'3'}}}});
    );
    try std.testing.expectError(error.RequiredActualInternalTtyProcessData, tty.acquire(f.engine, .{ .require = f.native_require }));
    try f.evaluate(
        \\if(processDefaultReads!==0)throw Error('foreign assembly getter invoked');
        \\Object.defineProperty(processRecord,'default',{value:P,writable:true,enumerable:true,configurable:true});
    );
    try f.createTty();
}
test "native internal tty pending assembly rejects reentry before completed publication" {
    var f: Fixture = undefined; try f.init(.{ .create_tty = false }); defer f.deinit();
    try f.evaluate(
        \\globalThis.originalEntries=ttyIntrinsics['Object.entries'];
        \\ttyIntrinsics['Object.entries']=object=>{internalTtyObserveReentry();return originalEntries(object)};
    );
    try f.createTty();
    try std.testing.expectEqual(@as(usize, 1), f.reentries);
    try f.evaluate("if(Q('internal/tty')!==TT||!H({FORCE_COLOR:'1'}))throw Error('outer assembly lost');");
    try f.balanced();
}
test "native internal tty failed genuine initialization publishes no backend and permits exact retry" {
    var f: Fixture = undefined; try f.init(.{ .create_tty = false }); defer f.deinit();
    try f.evaluate(
        \\globalThis.originalEntries=ttyIntrinsics['Object.entries'];globalThis.initializationReason={};
        \\ttyIntrinsics['Object.entries']=()=>{throw initializationReason};
        \\if(ttyReason(()=>internalTtyAcquire())!==initializationReason)throw Error('initialization reason replaced');
    );
    try std.testing.expect(!f.engine.native_module_values.contains("\x00native.internal.tty.owner"));
    try std.testing.expect(!f.engine.native_module_values.contains("internal/tty"));
    try f.evaluate("ttyIntrinsics['Object.entries']=originalEntries;");
    try f.createTty();
    try f.evaluate("if(Q('internal/tty')!==TT)throw Error('retry publication');");
}
test "native internal tty assembly retirement fatal prevents module publication" {
    var f: Fixture = undefined; try f.init(.{ .create_tty = false }); defer f.deinit();
    try f.evaluate(
        \\const entries=ttyIntrinsics['Object.entries'];
        \\ttyIntrinsics['Object.entries']=object=>{const result=entries(object);result.probe=internalTtyEphemeral();return result};
    );
    f.emit_fatal = true;
    try expectFatal(&f, "internalTtyAcquire();");
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    try std.testing.expect(!f.engine.native_module_values.contains("\x00native.internal.tty.owner"));
    try std.testing.expect(!f.engine.native_module_values.contains("internal/tty"));
}
test "native internal tty hasColors matches original overloads and exact color-capacity boundaries" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\P.env={FORCE_COLOR:'1'};
        \\for(const args of [[],[undefined],[{}],[{FORCE_COLOR:'1'}],[{FORCE_COLOR:'2'}],[[]],[2,{}],[3,{}],[16,{FORCE_COLOR:'1'}],[17,{FORCE_COLOR:'1'}],[256,{FORCE_COLOR:'2'}],[257,{FORCE_COLOR:'2'}],[16777216,{FORCE_COLOR:'3'}],[16777217,{FORCE_COLOR:'3'}],[Number.MAX_SAFE_INTEGER,{FORCE_COLOR:'3'}]]){
        \\ if(H(...args)!==originalHasColors(...args))throw Error('literal-source overload parity');
        \\}
        \\if(H()!==true||H({})!==false||H(2,{})!==true||H(3,{})!==false||H(16777216,{FORCE_COLOR:'3'})!==true)throw Error('actual capacity');
    );
}
test "native internal tty explicit environment keeps undefined null function and primitive count validation" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\let environmentReads=0;const env=new Proxy({},{get(){environmentReads++;throw Error('validation reached environment')}});
        \\for(const count of [undefined,null,false,true,'16',16n,Symbol('count'),function countFunction(){}]){
        \\ const reason=ttyReason(()=>H(count,env));if(reason.code!=='ERR_INVALID_ARG_TYPE'||!(reason instanceof TypeError)||!reason.message.includes('"count"'))throw Error('actual type validation');
        \\}
        \\if(environmentReads!==0)throw Error('environment read before validation');
        \\if(ttyReason(()=>H(null)).code!=='ERR_INVALID_ARG_TYPE'||ttyReason(()=>H(()=>16)).code!=='ERR_INVALID_ARG_TYPE')throw Error('object overload widened');
    );
}
test "native internal tty noninteger and out-of-bound counts fail before depth with original messages" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\let reads=0;const env=new Proxy({},{get(){reads++;throw Error('unexpected depth')}});
        \\for(const count of [NaN,Infinity,-Infinity,1.5]){
        \\ const reason=ttyReason(()=>H(count,env));if(reason.code!=='ERR_OUT_OF_RANGE'||!(reason instanceof RangeError)||!reason.message.includes('It must be an integer.'))throw Error('integer validation');
        \\}
        \\for(const count of [-0,0,1,-1,Number.MAX_SAFE_INTEGER+1]){
        \\ const reason=ttyReason(()=>H(count,env));if(reason.code!=='ERR_OUT_OF_RANGE'||!reason.message.includes('It must be >= 2 && <= 9007199254740991.'))throw Error('count bounds');
        \\}
        \\if(reads!==0)throw Error('invalid count entered depth');
    );
}
test "native internal tty object overload starts environment access without count coercion" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\let coercions=0,reads=0;const env={get FORCE_COLOR(){reads++;return '1'},[Symbol.toPrimitive](){coercions++;throw Error('count conversion')}};
        \\if(H(env)!==true||reads!==2||coercions!==0)throw Error('object overload order');
        \\const revoked=Proxy.revocable({},{});revoked.revoke();const reason=ttyReason(()=>H(revoked.proxy));
        \\if(!(reason instanceof TypeError)||reason.code==='ERR_INVALID_ARG_TYPE')throw Error('revoked object was count validated');
        \\if(!(ttyReason(()=>H(16,null)) instanceof TypeError))throw Error('explicit null environment changed');
    );
}
test "native internal tty retains lexical depth while original exports remain mutable" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\const saved=H;TT.getColorDepth=()=>{throw Error('export is not lexical binding')};
        \\TT.hasColors='ordinary replacement';
        \\if(Q('internal/tty')!==TT||Q('internal/tty').hasColors!=='ordinary replacement')throw Error('module exports not ordinary');
        \\if(saved(256,{FORCE_COLOR:'2'})!==true||saved(257,{FORCE_COLOR:'2'})!==false)throw Error('lexical depth was replaced');
    );
}
test "native internal tty live environment belongs to retained actual process" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\let reads=0;Object.defineProperty(P,'env',{configurable:true,get(){reads++;return {FORCE_COLOR:reads===1?'1':'2'}}});
        \\globalThis.process={env:{FORCE_COLOR:'0'},platform:'invented'};
        \\if(H()!==true||H(256)!==true||reads!==2)throw Error('actual process env not read each default');
        \\if(!H(16,{FORCE_COLOR:'1'})||reads!==2)throw Error('explicit env still read process');
    );
}
test "native internal tty depth and hasColors share the genuine lazy OS release cache" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\P.platform='win32';const os=Q('os'),release=os.release;let calls=0;
        \\os.release=function(){calls++;return release()};
        \\const depth=D({});if(H(2**depth,{})!==true||calls!==1)throw Error('one real release cache');
        \\os.release=()=>{throw Error('cached release read again')};if(H(2**depth,{})!==true||calls!==1)throw Error('shared lexical state');
    );
}
test "native internal tty nested environment getters preserve original outer execution" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\let reads=0;const env={get FORCE_COLOR(){reads++;if(reads===1&&H(2,{})!==true)throw Error('nested body');return '2'}};
        \\if(H(256,env)!==true||reads!==2||Q('internal/tty')!==TT)throw Error('outer body or owner replaced');
    );
}
test "native internal tty current fatal in an environment getter bypasses ordinary catches" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try expectFatal(&f,
        \\globalThis.ordinaryCatch=false;
        \\try{H(16,{get FORCE_COLOR(){internalTtyFatal();return '1'}})}catch(e){ordinaryCatch=true}
    );
    const caught = try f.readGlobal("ordinaryCatch"); defer f.engine.freeValue(caught);
    try std.testing.expect(c.JS_ToBool(f.engine.context, caught) == 0);
}

test "native internal tty out of range uses the shared registered RangeError and hidden class" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\const error=new R('count','>= 2',1);
        \\if(!(error instanceof RangeError)||error.constructor!==RangeError||error.code!=='ERR_OUT_OF_RANGE'||error[NodeErrorMarker]!==true)throw Error('genuine error identity');
        \\if(error.message!=='The value of "count" is out of range. It must be >= 2. Received 1')throw Error('original message');
        \\const code=Object.getOwnPropertyDescriptor(error,'code'),message=Object.getOwnPropertyDescriptor(error,'message');
        \\if(!code.writable||!code.enumerable||!code.configurable||!message.writable||message.enumerable||!message.configurable)throw Error('error descriptors');
        \\if(R.name!=='NodeError'||R.length!==0||R.HideStackFramesError!==HR||new HR('n','integer',0).constructor!==RangeError)throw Error('same hidden registration');
        \\if(!(ttyReason(()=>R('n','integer',0)) instanceof TypeError))throw Error('class called without new');
    );
    const second = try errors.outOfRange(f.engine); defer f.engine.freeValue(second);
    const first = try f.readGlobal("R"); defer f.engine.freeValue(first);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, first, second));
}
test "native internal tty numeric range message matches original separators including exponent strings" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\for(const input of [0,-0,1,1.5,NaN,Infinity,-Infinity,4294967296,4294967297,-4294967296,-4294967297,9007199254740991,1e21,-1e21]){
        \\ const actual=new R('n','chosen range',input).message;
        \\ if(actual!==originalRangeMessage('n','chosen range',input))throw Error('numeric original callback parity');
        \\}
        \\if(!new R('n','x',4294967297).message.endsWith('4_294_967_297')||!new R('n','x',-4294967297).message.endsWith('-4_294_967_297'))throw Error('signed grouping');
        \\if(!new R('n','x',4294967296).message.endsWith('4294967296'))throw Error('strict threshold');
    );
}
test "native internal tty bigint range message preserves strict threshold grouping and suffix" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\for(const input of [0n,1n,-1n,4294967296n,4294967297n,-4294967296n,-4294967297n,123456789012345678901234567890n,-123456789012345678901234567890n]){
        \\ if(new R('n','integer',input).message!==originalRangeMessage('n','integer',input))throw Error('BigInt original callback parity');
        \\}
        \\if(!new R('n','x',4294967296n).message.endsWith('4294967296n')||!new R('n','x',4294967297n).message.endsWith('4_294_967_297n'))throw Error('BigInt bound and suffix');
    );
}
test "native internal tty arbitrary range input uses the actual live private inspector" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\for(const input of [undefined,null,true,false,'value',Symbol('range'),[1,2],{value:3}]){
        \\ if(new R('n','some range',input).message!==originalRangeMessage('n','some range',input))throw Error('actual inspector parity');
        \\}
        \\const previous=IM.inspect;let receiver,calls=0;IM.inspect=function(value){receiver=this;calls++;return 'selected inspection'};
        \\const error=new R('n','some range',{});IM.inspect=previous;
        \\if(receiver!==IM||calls!==1||!error.message.endsWith('selected inspection'))throw Error('live inspect property or receiver');
    );
}
test "native internal tty range replace-default branch retains template and compound-assignment coercion order" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\const log=[];const old=IM.inspect;
        \\IM.inspect=()=>{log.push('inspect');return {toString(){log.push('received:string');return 'received'}}};
        \\const name={[Symbol.toPrimitive](hint){log.push('name:'+hint);return 'custom'}};
        \\const range={toString(){log.push('range:string');return 'range'}};
        \\const custom=new R(name,range,{},true);
        \\if(custom.message!=='custom It must be range. Received received'||log.join(',')!=='inspect,range:string,received:string,name:default')throw Error('compound order');
        \\log.length=0;const standard=new R(name,range,{});
        \\if(standard.message!=='The value of "custom" is out of range. It must be range. Received received'||log.join(',')!=='name:string,inspect,range:string,received:string')throw Error('default title order');
        \\IM.inspect=old;
    );
}
test "native internal tty range assertion and ordinary thrown identity precede later message work" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\let converted=0;const name={toString(){converted++;throw Error('name should not run')}};
        \\for(const range of [undefined,null,false,0,NaN,'']){
        \\ const reason=ttyReason(()=>new R(name,range,1));if(reason.code!=='ERR_INTERNAL_ASSERTION'||!reason.message.includes('Missing "range" argument'))throw Error('actual internal assertion');
        \\}
        \\if(converted!==0)throw Error('assertion reordered');
        \\const insufficient=ttyReason(()=>new R('n','range'));if(insufficient.code!=='ERR_INTERNAL_ASSERTION'||!insufficient.message.includes('provided arguments length'))throw Error('message arity three');
        \\const old=IM.inspect,marker={};IM.inspect=()=>{throw marker};
        \\if(ttyReason(()=>new R('n','range',{}))!==marker)throw Error('ordinary inspect reason');
        \\IM.inspect=old;
    );
}
test "native internal tty validator has original wrapper and raw arrow callable semantics" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\if(V.name!=='wrappedFn'||V.length!==0||!Object.hasOwn(V,'prototype')||V.withoutStackTrace.length!==2||Object.hasOwn(V.withoutStackTrace,'prototype'))throw Error('validator shape');
        \\if(V(0,Symbol('unused'))!==undefined||V.withoutStackTrace(0,Symbol('unused'))!==undefined)throw Error('unused name or success');
        \\if(Object.getPrototypeOf(new V(0,'n'))!==V.prototype)throw Error('ordinary wrapper construction');
        \\if(!(ttyReason(()=>new V.withoutStackTrace(0,'n')) instanceof TypeError))throw Error('raw arrow construction');
        \\if(V===AT||V.withoutStackTrace===HR)throw Error('real bodies not classes');
    );
}
test "native internal tty validator matches full original defaults and separate bounds" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\const rows=[[0,'n'],[-0,'n'],[Number.MIN_SAFE_INTEGER,'n'],[Number.MAX_SAFE_INTEGER,'n'],[Number.MAX_SAFE_INTEGER+1,'n'],[Number.MIN_SAFE_INTEGER-1,'n'],[2,'n',2,2],[1,'n',2,2],[3,'n',2,2],[1.5,'n'],[NaN,'n'],[Infinity,'n'],['2','n'],[2n,'n'],[null,'n'],[2,'n',undefined,2]];
        \\for(const args of rows){
        \\ let first,second;try{V.withoutStackTrace(...args)}catch(e){first=e}try{originalValidateInteger(...args)}catch(e){second=e}
        \\ if((first===undefined)!==(second===undefined)||first&&(first.code!==second.code||first.message!==second.message||first.constructor!==second.constructor))throw Error('literal original integer parity');
        \\}
    );
}
test "native internal tty validator performs relational bounds before ordered template substitutions" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\const order=[];const min={[Symbol.toPrimitive](hint){order.push('min:'+hint);return 10}};
        \\const max={[Symbol.toPrimitive](hint){order.push('max:'+hint);return 20}};
        \\const previous=IM.inspect;IM.inspect=function(value){order.push('inspect');return previous.call(this,value)};
        \\const reason=ttyReason(()=>V(5,'n',min,max));
        \\if(reason.code!=='ERR_OUT_OF_RANGE'||!reason.message.includes('>= 10 && <= 20')||order.join(',')!=='min:number,min:string,max:string,inspect')throw Error('range short circuit and formatting');
        \\order.length=0;const lower={[Symbol.toPrimitive](hint){order.push('lower:'+hint);return 0}};
        \\if(V(5,'n',lower,max)!==undefined||order.join(',')!=='lower:number,max:number')throw Error('successful relational order');
        \\IM.inspect=previous;
    );
}
test "native internal tty validator type and integer failures do not coerce caller bounds" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\let conversions=0;const bound={[Symbol.toPrimitive](){conversions++;throw Error('bound conversion')}};
        \\if(ttyReason(()=>V('1','n',bound,bound)).code!=='ERR_INVALID_ARG_TYPE')throw Error('type before bounds');
        \\if(ttyReason(()=>V(1.5,'n',bound,bound)).code!=='ERR_OUT_OF_RANGE'||conversions!==0)throw Error('integer before bounds');
        \\const marker={};const first={[Symbol.toPrimitive](){throw marker}};
        \\if(ttyReason(()=>V(1,'n',first,bound))!==marker||conversions!==0)throw Error('relational ordinary throw');
        \\if(V(1,'n',NaN,NaN)!==undefined||V(1,'n',null,'2')!==undefined)throw Error('bounds gained invented validation');
    );
}
test "native internal tty validators and range messages retain actual early primordials after global mutation" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\const NativeNumber=Number,NativeString=String,oldInteger=Number.isInteger,oldAbs=Math.abs,oldSlice=String.prototype.slice;
        \\try{
        \\ NativeNumber.isInteger=()=>{throw Error('late integer')};Math.abs=()=>{throw Error('late abs')};NativeString.prototype.slice=()=>{throw Error('late slice')};
        \\ globalThis.Number={isInteger(){throw Error('late Number')},MIN_SAFE_INTEGER:0,MAX_SAFE_INTEGER:0};globalThis.String=()=>{throw Error('late String')};
        \\ if(V(-1,'n')!==undefined||H(16,{FORCE_COLOR:'1'})!==true)throw Error('captured validator');
        \\ if(!new R('n','range',4294967297).message.endsWith('4_294_967_297')||!new R('n','range',4294967297n).message.endsWith('4_294_967_297n'))throw Error('captured range primordials');
        \\}finally{globalThis.Number=NativeNumber;globalThis.String=NativeString;NativeNumber.isInteger=oldInteger;Math.abs=oldAbs;NativeString.prototype.slice=oldSlice}
    );
}
test "native internal tty range template failure retains original Symbol conversion ordering" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\let inspected=0,rangeReads=0;const previous=IM.inspect;IM.inspect=()=>{inspected++;return 'received'};
        \\const range={toString(){rangeReads++;return 'range'}};
        \\if(!(ttyReason(()=>new R(Symbol('name'),range,{})) instanceof TypeError)||inspected!==0||rangeReads!==0)throw Error('default title coercion order');
        \\if(!(ttyReason(()=>new R(Symbol('name'),range,{},true)) instanceof TypeError)||inspected!==1||rangeReads!==1)throw Error('compound final coercion order');
        \\IM.inspect=previous;
    );
}
test "native internal tty current range-inspector fatal survives the real validator wrapper" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate("IM.inspect=()=>{internalTtyFatal();return 'unusable'};");
    try expectFatal(&f, "globalThis.rangeCaught=false;try{H(1.5,{})}catch(e){rangeCaught=true}");
    const caught = try f.readGlobal("rangeCaught"); defer f.engine.freeValue(caught);
    try std.testing.expect(c.JS_ToBool(f.engine.context, caught) == 0);
}
test "native internal tty range received local retires before constructor success" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\IM.inspect=()=>{const value=internalTtyEphemeral();value.toString=()=> 'selected';return value};
    );
    f.emit_fatal = true;
    try expectFatal(&f, "globalThis.rangeCompleted=false;new R('n','range',{});rangeCompleted=true;");
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    const completed = try f.readGlobal("rangeCompleted"); defer f.engine.freeValue(completed);
    try std.testing.expect(c.JS_ToBool(f.engine.context, completed) == 0);
}
test "native internal tty received-local retirement fatal supersedes an ordinary template throw" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    try f.evaluate(
        \\IM.inspect=()=>{const value=internalTtyEphemeral();value.toString=()=> 'selected';return value};
        \\globalThis.templateReason={};globalThis.badRange={toString(){throw templateReason}};
    );
    f.emit_fatal = true;
    try expectFatal(&f, "new R('n',badRange,{});");
    try std.testing.expectEqual(@as(usize, 1), f.retired);
}
test "native internal tty object overload retains reassigned formals until actual terminal retirement" {
    var f: Fixture = undefined; try f.init(.{}); defer f.deinit();
    f.emit_fatal = true;
    try expectFatal(&f,
        \\H((()=>{const environment=internalTtyEphemeral();environment.FORCE_COLOR='1';return environment})());
    );
    try std.testing.expectEqual(@as(usize, 1), f.retired);
}
