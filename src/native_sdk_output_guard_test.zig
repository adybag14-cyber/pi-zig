//! Actual output-guard bodies over real native process streams and exact c268
//! Source. Bridge callbacks collect bytes; they do not implement any queue.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const output_guard = @import("extensions/native_sdk_output_guard.zig");
const streams = @import("extensions/native_process_streams.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const fields = .{
    .{ "takeOverStdout", "take_over_stdout" }, .{ "restoreStdout", "restore_stdout" },
    .{ "isStdoutTakenOver", "is_stdout_taken_over" }, .{ "writeRawStdout", "write_raw_stdout" },
    .{ "waitForRawStdoutBackpressure", "wait_for_raw_stdout_backpressure" }, .{ "flushRawStdout", "flush_raw_stdout" },
};
const Sink = struct {
    engine: ?*v.em.Engine = null,
    output: std.ArrayList(u8) = .empty,
    errors: std.ArrayList(u8) = .empty,
    closed: bool = false,
    fn deinit(self: *Sink) void {
        self.output.deinit(std.testing.allocator);
        self.errors.deinit(std.testing.allocator);
    }
    fn checked(context: ?*anyopaque) !*Sink {
        const self: *Sink = @ptrCast(@alignCast(context.?));
        if (self.closed) return error.ActualOutputControlFrontendClosed;
        try self.engine.?.checkNativeEntry();
        return self;
    }
    fn live(context: ?*anyopaque) !void { _ = try checked(context); }
    fn control(context: ?*anyopaque, _: streams.Control) !void { _ = try checked(context); }
    fn write(context: ?*anyopaque, destination: streams.Output, bytes: []const u8) !void {
        const self = try checked(context);
        if (destination == .stdout) try self.output.appendSlice(std.testing.allocator, bytes)
        else try self.errors.appendSlice(std.testing.allocator, bytes);
    }
    fn bridge(self: *Sink) streams.Bridge {
        return .{ .context = self, .guard_fn = live, .control_fn = control, .write_fn = write };
    }
};
fn publish(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    const global = try v.own(s, c.JS_GetGlobalObject(s.engine.context));
    try v.put(s, global, name, value);
}
fn startup(engine: *v.em.Engine, sink: *Sink) !streams.Lease {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{ "actual-output-control" });
    sink.engine = engine;
    const lease = try streams.bind(engine, sink.bridge());
    var s: v.Scope = .{ .engine = engine };
    try v.owned.finishVoid(&s, startupBody(&s));
    return lease;
}
fn startupBody(s: *v.Scope) !void {
    const source = try v.own(s, try s.engine.eval(@embedFile("extensions/fixtures/sdk-output-guard-c268-source.mjs"), "actual-output-source-factory.js", c.JS_EVAL_TYPE_GLOBAL));
    try publish(s, "makeSourceOutputGuard", source);
    try publish(s, "outputHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
}
fn activate(engine: *v.em.Engine, lease: streams.Lease) !void {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, activateBody(&s, lease));
}
fn activateBody(s: *v.Scope, lease: streams.Lease) !void {
    const exports = try output_guard.create(s.engine, try v.global(s, "process"), lease);
    var publication: v.Scope = .{ .engine = s.engine };
    var completion = v.owned.Completion.initVoid(s.engine, publishActual(&publication, exports));
    completion.releaseScope(&publication);
    inline for (std.meta.fields(output_guard.Exports)) |field| completion.release(@field(exports, field.name));
    try completion.finishVoid();
    const source = try v.call(s, try v.global(s, "makeSourceOutputGuard"), c.pi_js_undefined(), &.{});
    try publish(s, "sourceOutput", source);
}
fn publishActual(s: *v.Scope, exports: output_guard.Exports) !void {
    const namespace = try v.object(s);
    inline for (fields) |field| try v.put(s, namespace, field[0], @field(exports, field[1]));
    try publish(s, "nativeOutput", namespace);
}
fn run(engine: *v.em.Engine, source: []const u8) !void {
    const namespace = try engine.evalModule(source, "actual-output-control.mjs");
    engine.freeValue(namespace);
}
fn select(engine: *v.em.Engine, native: bool) !void {
    try run(engine, if (native) "globalThis.selectedOutput=nativeOutput;" else "globalThis.selectedOutput=sourceOutput;");
}
fn read(engine: *v.em.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
fn record(engine: *v.em.Engine) !c.JSValue {
    const hooks = try read(engine, "outputHooks");
    defer engine.freeValue(hooks);
    return engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record"));
}
test "Native stdout guard actual six ordinary and genuine async export identities" {
    var sink: Sink = .{}; defer sink.deinit();
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const lease = try startup(engine, &sink); try activate(engine, lease);
    try run(engine,
        \\for(const api of[sourceOutput,nativeOutput]){
        \\ if(Object.keys(api).sort().join()!==["takeOverStdout","restoreStdout","isStdoutTakenOver","writeRawStdout","waitForRawStdoutBackpressure","flushRawStdout"].sort().join())throw Error("Actual output exports");
        \\ for(const[name,length]of[["takeOverStdout",0],["restoreStdout",0],["isStdoutTakenOver",0],["writeRawStdout",1]]){
        \\  const f=api[name];if(f.name!==name||f.length!==length||Object.getPrototypeOf(f)!==Function.prototype||!Object.hasOwn(f,"prototype"))throw Error("Ordinary output shape "+name);
        \\ }
        \\ for(const name of["waitForRawStdoutBackpressure","flushRawStdout"]){
        \\  const f=api[name];if(f.name!==name||f.length!==0||Object.prototype.toString.call(f)!=="[object AsyncFunction]"||Object.hasOwn(f,"prototype"))throw Error("Actual async output shape");
        \\ }
        \\ if(api.isStdoutTakenOver()!==false||api.writeRawStdout("")!==undefined)throw Error("Initial module state");
        \\}
    );
    const process = try read(engine, "process"); defer engine.freeValue(process);
    const first = try output_guard.create(engine, process, lease); defer first.deinit(engine);
    const second = try output_guard.create(engine, process, lease); defer second.deinit(engine);
    inline for (std.meta.fields(output_guard.Exports)) |field| try std.testing.expect(c.JS_IsStrictEqual(engine.context, @field(first, field.name), @field(second, field.name)));
}
test "Native stdout guard actual shared frontend byte sinks takeover and restoration" {
    inline for (.{ false, true }) |native| {
        var sink: Sink = .{}; defer sink.deinit();
        const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        const lease = try startup(engine, &sink); try activate(engine, lease); try select(engine, native);
        try run(engine,
            \\const original=process.stdout.write;let callbacks=0;
            \\selectedOutput.takeOverStdout();selectedOutput.takeOverStdout();
            \\if(!selectedOutput.isStdoutTakenOver())throw Error("Actual takeover state");
            \\process.stdout.write("diagnostic",()=>{callbacks++});
            \\selectedOutput.writeRawStdout("raw");
            \\await selectedOutput.flushRawStdout();
            \\selectedOutput.restoreStdout();selectedOutput.restoreStdout();
            \\if(selectedOutput.isStdoutTakenOver()||process.stdout.write!==original)throw Error("Original stdout restored");
            \\process.stdout.write("normal",()=>{callbacks++});
            \\await new Promise(resolve=>process.nextTick(resolve));
            \\if(callbacks!==2)throw Error("Actual stream callbacks");
        );
        try std.testing.expectEqualStrings("rawnormal", sink.output.items);
        try std.testing.expectEqualStrings("diagnostic", sink.errors.items);
    }
}
test "Native stdout guard actual Source queue retry error normalization and Await traces" {
    inline for (.{ "success", "queue", "ENOBUFS", "EAGAIN", "EWOULDBLOCK", "sync-retry", "EPIPE", "throw-string" }) |mode| {
        var sink: Sink = .{}; defer sink.deinit();
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 }); defer engine.deinit();
        const lease = try startup(engine, &sink); try activate(engine, lease);
        const source = try std.mem.concat(engine.gpa, u8, &.{
            @embedFile("extensions/fixtures/sdk-output-guard-observer.mjs"),
            "\nexport const row=await compareRawOutput(nativeOutput,sourceOutput,\"", mode, "\");\n",
        });
        defer engine.gpa.free(source);
        try run(engine, source);
    }
}
test "Native stdout guard actual live tail then catch reentry and replacement retirement" {
    inline for (.{ false, true }) |native| {
        var sink: Sink = .{}; defer sink.deinit();
        const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        const lease = try startup(engine, &sink);
        try run(engine,
            \\globalThis.outputLog=[];globalThis.outputResolve=Promise.resolve;
            \\Promise.resolve=function(){
            \\ if(this!==Promise)throw Error("Live Promise receiver");
            \\ let first=true,calls=0;
            \\ return {get then(){
            \\  const number=++calls;outputLog.push("get:"+number);
            \\  if(first){first=false;selectedOutput.writeRawStdout("inner");outputLog.push("inner:return")}
            \\  return function(callback){
            \\   if(this===undefined||callback.name!==""||callback.length!==0||"prototype"in callback)throw Error("Actual then arrow");
            \\   outputLog.push("call:"+number);
            \\   return {holder:outputHooks.make(number===2?0:1),get catch(){
            \\    if(number===1&&outputHooks.count(0)!==1)throw Error("Replaced tail retained before catch");
            \\    outputLog.push("catch:"+number);return function(callback){if(callback.name!==""||callback.length!==0||"prototype"in callback)throw Error("Actual catch arrow");outputLog.push("observe:"+number)}
            \\   }};
            \\  };
            \\ }};
            \\};
        );
        try activate(engine, lease); try select(engine, native);
        try run(engine,
            \\Promise.resolve=outputResolve;delete globalThis.outputResolve;
            \\selectedOutput.writeRawStdout("outer");
            \\if(outputLog.join()!=="get:1,get:2,call:2,catch:2,observe:2,inner:return,call:1,catch:1,observe:1")throw Error(outputLog.join());
        );
    }
}
test "Native stdout guard actual live process and String temporaries retire before later callees" {
    inline for (.{ false, true }) |native| {
        var sink: Sink = .{}; defer sink.deinit();
        const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        const lease = try startup(engine, &sink); try activate(engine, lease); try select(engine, native);
        try run(engine,
            \\const processDescriptor=Object.getOwnPropertyDescriptor(globalThis,"process"),stringDescriptor=Object.getOwnPropertyDescriptor(globalThis,"String"),ActualString=String;
            \\let made=0,redirected=false,writes=0,currentWrite=function(){return true};
            \\const out={get write(){if(outputHooks.count(0)!==made)throw Error("Process retained into write getter");return currentWrite},set write(value){currentWrite=value}};
            \\const err={write(text,callback){if(redirected&&outputHooks.count(1)!==1)throw Error("String callee retained into stderr");if(text!=="Symbol(actual)")throw Error("Live String result");writes++;callback();return false}};
            \\try{
            \\ Object.defineProperty(globalThis,"process",{configurable:true,get(){made++;return {stdout:out,stderr:err,holder:outputHooks.make(0)}}});
            \\ selectedOutput.takeOverStdout();
            \\ Object.defineProperty(globalThis,"String",{configurable:true,get(){const f=value=>ActualString(value);f.holder=outputHooks.make(1);return f}});
            \\ redirected=true;let callbacks=0;
            \\ if(process.stdout.write(Symbol("actual"),()=>{callbacks++})!==false||callbacks!==1||writes!==1)throw Error("Actual redirection");
            \\ selectedOutput.restoreStdout();
            \\ if(outputHooks.count(0)!==made)throw Error("Live process roots retained");
            \\}finally{Object.defineProperty(globalThis,"process",processDescriptor);Object.defineProperty(globalThis,"String",stringDescriptor)}
        );
    }
}
test "Native stdout guard actual throwing stdout assignment and restore reentry preserve Source state" {
    inline for (.{ false, true }) |native| {
        var sink: Sink = .{}; defer sink.deinit();
        const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        const lease = try startup(engine, &sink); try activate(engine, lease); try select(engine, native);
        try run(engine,
            \\const processDescriptor=Object.getOwnPropertyDescriptor(globalThis,"process"),first={kind:"setter"};
            \\let current=function(){},fail=true,reenter=false;const err={write(){return true}};
            \\const out={get write(){return current},set write(value){if(fail)throw first;current=value}};
            \\const p={get stdout(){if(reenter){reenter=false;selectedOutput.restoreStdout()}return out},stderr:err};
            \\try{
            \\ Object.defineProperty(globalThis,"process",{configurable:true,value:p});
            \\ let caught;try{selectedOutput.takeOverStdout()}catch(error){caught=error}
            \\ if(caught!==first||selectedOutput.isStdoutTakenOver())throw Error("Throwing setter published takeover");
            \\ fail=false;selectedOutput.takeOverStdout();reenter=true;caught=undefined;
            \\ try{selectedOutput.restoreStdout()}catch(error){caught=error}
            \\ if(!(caught instanceof TypeError)||selectedOutput.isStdoutTakenOver())throw Error("Restore failed to reread current state");
            \\}finally{Object.defineProperty(globalThis,"process",processDescriptor)}
        );
    }
}
test "Native stdout guard actual same-operation private DATA remains ordinary through write rejection" {
    var sink: Sink = .{}; defer sink.deinit();
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const lease = try startup(engine, &sink); try activate(engine, lease);
    try run(engine,
        \\globalThis.outputData=undefined;globalThis.outputCaught=undefined;let exits=0;
        \\process.exit=code=>{if(code!==1)throw Error("Exit code");exits++};
        \\Object.defineProperty(process.stdout,"write",{configurable:true,get(){outputData=outputHooks.freshPrivateData();throw outputData}});
        \\nativeOutput.writeRawStdout("actual");
        \\try{await nativeOutput.flushRawStdout()}catch(error){outputCaught=error}
        \\if(outputCaught!==outputData||!outputHooks.isUnmarkedPrivateData(outputCaught)||exits!==1)throw Error("Ordinary DATA queue rejection");
    );
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "Native stdout guard actual current B preempts DATA and the queued guest catch" {
    var sink: Sink = .{}; defer sink.deinit();
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const lease = try startup(engine, &sink); try activate(engine, lease);
    const observed = try record(engine); defer engine.freeValue(observed);
    try run(engine,
        \\globalThis.outputData=undefined;
        \\Object.defineProperty(process.stdout,"write",{configurable:true,get(){outputData=outputHooks.freshPrivateData();outputHooks.raiseNativeFatal();throw outputData}});
        \\process.exit=()=>{outputHooks.record.guestReached=true;outputHooks.visit(3)};
    );
    try std.testing.expectError(error.JavaScriptException, run(engine,
        \\nativeOutput.writeRawStdout("actual");
        \\try{await nativeOutput.flushRawStdout()}catch(error){outputHooks.record.guestReached=true;outputHooks.visit(3)}
    ));
    try retirement.verifyRecordedActualNativeFatal(engine, observed);
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "Native stdout guard actual catch locals survive the next try and reset on next catch entry" {
    inline for (.{ false, true }) |native| {
        var sink: Sink = .{}; defer sink.deinit();
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 }); defer engine.deinit();
        const lease = try startup(engine, &sink); try activate(engine, lease); try select(engine, native);
        try run(engine,
            \\const ActualError=Error,ActualPromise=Promise;let calls=0,timers=[],settled=false,failure,checked=false;
            \\process.exit=()=>{};
            \\globalThis.setTimeout=(callback,delay)=>{if(delay!==10)throw new ActualError("Retry delay");timers.push(callback)};
            \\function ObservedError(message){const error=new ActualError(message);error.holder=outputHooks.make(1);error.code="EAGAIN";return error}
            \\ObservedError.prototype=ActualError.prototype;
            \\Object.defineProperty(globalThis,"Error",{configurable:true,get(){
            \\ if(calls===2){if(outputHooks.count(0)!==1||outputHooks.count(1)!==1)throw new ActualError("Prior catch slots retained at catch entry");checked=true}
            \\ return ObservedError;
            \\}});
            \\process.stdout.write=function(text,callback){
            \\ if(text===""){callback();return true}
            \\ calls++;
            \\ if(calls===1){callback({holder:outputHooks.make(0),toString(){return "retry"}});return false}
            \\ if(outputHooks.count(0)!==0||outputHooks.count(1)!==0)throw new ActualError("Prior catch locals retired before next try");
            \\ const next=new ActualError("stop");next.code="EPIPE";callback(next);return false;
            \\};
            \\selectedOutput.writeRawStdout("actual");
            \\selectedOutput.flushRawStdout().then(()=>{settled=true},error=>{failure=error;settled=true});
            \\for(let i=0;!settled&&i<200;i++){await ActualPromise.resolve();if(timers.length)timers.shift()()}
            \\if(!settled||!checked||failure.message!=="stop"||calls!==2)throw new ActualError("Actual catch-slot control");
        );
    }
}
test "Native stdout guard actual retained callbacks and cached owner reject a stale lease" {
    var sink: Sink = .{}; defer sink.deinit();
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const lease = try startup(engine, &sink); try activate(engine, lease);
    const process = try read(engine, "process"); defer engine.freeValue(process);
    const next = try streams.bind(engine, sink.bridge());
    try std.testing.expect(!streams.ownsLease(engine, lease));
    try std.testing.expect(streams.ownsLease(engine, next));
    try std.testing.expect(!streams.unbind(engine, lease));
    try std.testing.expectError(error.JavaScriptException, run(engine, "nativeOutput.isStdoutTakenOver();"));
    try std.testing.expectError(error.JavaScriptException, output_guard.create(engine, process, next));
    try std.testing.expect(streams.ownsLease(engine, next));
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "Native stdout guard actual failed module initialization leaves no published owner" {
    var sink: Sink = .{}; defer sink.deinit();
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const lease = try startup(engine, &sink);
    const process = try read(engine, "process"); defer engine.freeValue(process);
    try run(engine,
        \\globalThis.outputOriginalResolve=Object.getOwnPropertyDescriptor(Promise,"resolve");globalThis.outputInitError={};
        \\Object.defineProperty(Promise,"resolve",{configurable:true,get(){throw outputInitError}});
    );
    try std.testing.expectError(error.JavaScriptException, output_guard.create(engine, process, lease));
    try std.testing.expect(!engine.native_module_values.contains("\x00native.sdk.stdout-takeover-owner"));
    try run(engine,
        \\Object.defineProperty(Promise,"resolve",outputOriginalResolve);delete globalThis.outputOriginalResolve;
    );
    const exports = try output_guard.create(engine, process, lease); defer exports.deinit(engine);
    try std.testing.expect(engine.native_module_values.contains("\x00native.sdk.stdout-takeover-owner"));
}

test "Native stdout guard actual backpressure follows writes enqueued during its Await" {
    inline for (.{ false, true }) |native| {
        var sink: Sink = .{}; defer sink.deinit();
        const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        const lease = try startup(engine, &sink); try activate(engine, lease); try select(engine, native);
        try run(engine,
            \\globalThis.outputCallbacks=[];globalThis.outputWritten=[];globalThis.outputWaited=false;
            \\process.stdout.write=function(text,callback){outputWritten.push(text);outputCallbacks.push(callback);return true};
            \\selectedOutput.writeRawStdout("first");
            \\globalThis.outputWaiting=selectedOutput.waitForRawStdoutBackpressure();
            \\outputWaiting.then(()=>{outputWaited=true});
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        try run(engine,
            \\if(outputWritten.join()!=="first"||outputWaited)throw Error("First actual Await");
            \\selectedOutput.writeRawStdout("second");
            \\outputCallbacks[0]();delete outputCallbacks[0];
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        try run(engine,
            \\if(outputWritten.join()!=="first,second"||outputWaited)throw Error("Backpressure lost the new tail");
            \\outputCallbacks[1]();delete outputCallbacks[1];await outputWaiting;
            \\if(!outputWaited)throw Error("New tail did not complete");
        );
    }
}
