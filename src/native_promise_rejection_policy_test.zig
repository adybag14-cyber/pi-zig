const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const policy_mod = @import("extensions/native_promise_rejection_policy.zig");
const rejection_mod = @import("extensions/native_promise_rejections.zig");
fn script(engine: *js.Engine, source: []const u8) !void {
    engine.freeValue(try engine.eval(source, "native-node-policy-boundary.js", c.JS_EVAL_TYPE_GLOBAL));
}
fn field(engine: *js.Engine, key: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return js.get(engine, global, key);
}
fn setup() !@import("native_error_stack_fixture.zig").Fixture {
    const fixture = try @import("native_error_stack_fixture.zig").Fixture.init(std.testing.allocator, .{});
    errdefer fixture.deinit();
    const engine = fixture.engine;
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-node-policy"});
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    return fixture;
}
fn rejection(engine: *js.Engine) !rejection_mod.Rejection {
    return .{ .promise = try field(engine, "promise"), .reason = try field(engine, "reason"), .scope = c.pi_js_undefined(), .uid = 1 };
}
fn expose(engine: *js.Engine, fatal: policy_mod.Fatal) !void {
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "fatalReason", c.JS_DupValue(engine.context, fatal.reason));
}

test "Promise rejection policy Source default original Error monitor before uncaught and exit event" {
    const fixture = try setup();
    defer fixture.deinit();
    const engine = fixture.engine;
    var policy = try policy_mod.Policy.init(engine);
    defer policy.deinit();
    try script(engine, "globalThis.log=[];globalThis.reason=Error('original-policy-rejection');globalThis.promise=Promise.reject(reason);process.on('uncaughtExceptionMonitor',(error,origin)=>{if(error!==reason||origin!=='unhandledRejection')throw Error('original monitor identity');log.push('monitor')});process.on('exit',code=>{if(code!==1)throw Error('exit code');log.push('exit')});");
    const process = try field(engine, "process");
    defer engine.freeValue(process);
    const pending = try rejection(engine);
    defer pending.deinit(engine.context);
    const fatal = (try policy.reportUnhandled(process, pending)).?;
    defer fatal.deinit(engine);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, fatal.reason, pending.reason));
    try std.testing.expectEqual(policy_mod.Origin.unhandledRejection, fatal.origin);
    const terminal = (try policy.reportUncaught(process, fatal)).?;
    defer terminal.deinit(engine);
    try std.testing.expectEqual(@as(u8, 1), terminal.exit_code);
    try script(engine, "if(JSON.stringify(log)!=='[\"monitor\",\"exit\"]'||process._exiting!==true||process.exitCode!==1)throw Error('Node fatal event ordering');");
}

test "Promise rejection policy Source own stack object passes through without reading accessor" {
    const fixture = try setup();
    defer fixture.deinit();
    const engine = fixture.engine;
    var policy = try policy_mod.Policy.init(engine);
    defer policy.deinit();
    try script(engine, "globalThis.stackReads=0;globalThis.reason=Object.defineProperty({},'stack',{get(){stackReads++;throw Error('must not read')}});globalThis.promise=Promise.reject(reason);");
    const process = try field(engine, "process");
    defer engine.freeValue(process);
    const pending = try rejection(engine);
    defer pending.deinit(engine.context);
    const fatal = (try policy.reportUnhandled(process, pending)).?;
    defer fatal.deinit(engine);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, fatal.reason, pending.reason));
    try script(engine, "if(stackReads!==0)throw Error('Node own stack is descriptor only');");
}

test "Promise rejection policy Source non-error object wraps with proper V8 text and no guest primitive conversion" {
    const fixture = try setup();
    defer fixture.deinit();
    const engine = fixture.engine;
    var policy = try policy_mod.Policy.init(engine);
    defer policy.deinit();
    try script(engine, "globalThis.primitiveCalls=0;globalThis.reason={[Symbol.toPrimitive](){primitiveCalls++;throw Error('forbidden coercion')}};globalThis.promise=Promise.reject(reason);");
    const process = try field(engine, "process");
    defer engine.freeValue(process);
    const pending = try rejection(engine);
    defer pending.deinit(engine.context);
    const fatal = (try policy.reportUnhandled(process, pending)).?;
    defer fatal.deinit(engine);
    try expose(engine, fatal);
    try script(engine, "if(primitiveCalls!==0||fatalReason===reason||!(fatalReason instanceof Error)||fatalReason.name!=='UnhandledPromiseRejection'||fatalReason.code!=='ERR_UNHANDLED_REJECTION'||fatalReason.constructor.name!=='UnhandledPromiseRejection'||fatalReason.message!=='This error originated either by throwing inside of an async function without a catch block, or by rejecting a promise which was not handled with .catch(). The promise rejected with the reason \"#<Object>\".')throw Error('actual Node non-error wrapper');");
}

test "Promise rejection policy Source function own stack wraps while proxy own stack uses one descriptor trap" {
    const fixture = try setup();
    defer fixture.deinit();
    const engine = fixture.engine;
    var policy = try policy_mod.Policy.init(engine);
    defer policy.deinit();
    const process = try field(engine, "process");
    defer engine.freeValue(process);
    try script(engine, "globalThis.reason=Object.assign(function namedReason(){},{stack:'function-stack'});globalThis.promise=Promise.reject(reason);");
    {
        const pending = try rejection(engine);
        defer pending.deinit(engine.context);
        const fatal = (try policy.reportUnhandled(process, pending)).?;
        defer fatal.deinit(engine);
        try expose(engine, fatal);
        try script(engine, "if(fatalReason===reason||fatalReason.code!=='ERR_UNHANDLED_REJECTION'||!fatalReason.message.endsWith('\"function namedReason(){}\".'))throw Error('Source function typeof distinction');");
    }
    try script(engine, "globalThis.ownChecks=0;globalThis.reason=new Proxy({stack:'proxy-stack'},{getOwnPropertyDescriptor(target,key){if(key==='stack')ownChecks++;return Reflect.getOwnPropertyDescriptor(target,key)}});globalThis.promise=Promise.reject(reason);");
    {
        const pending = try rejection(engine);
        defer pending.deinit(engine.context);
        const fatal = (try policy.reportUnhandled(process, pending)).?;
        defer fatal.deinit(engine);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, fatal.reason, pending.reason));
        try script(engine, "if(ownChecks!==1)throw Error('Source proxy descriptor count');");
    }
}

test "Promise rejection policy Source dynamic process emit receiver and listener throw preserve raw uncaught origin" {
    const fixture = try setup();
    defer fixture.deinit();
    const engine = fixture.engine;
    var policy = try policy_mod.Policy.init(engine);
    defer policy.deinit();
    try script(engine, "globalThis.reason=Error('original-policy-rejection');globalThis.promise=Promise.reject(reason);globalThis.other={toString(){throw Error('capture must not coerce')}};const emit=process.emit;process.emit=function(name,...args){if(name==='unhandledRejection'&&(this!==process||args[0]!==reason||args[1]!==promise))throw Error('Source dynamic emit');return Reflect.apply(emit,this,[name,...args])};process.on('unhandledRejection',()=>{throw other});");
    const process = try field(engine, "process");
    defer engine.freeValue(process);
    const pending = try rejection(engine);
    defer pending.deinit(engine.context);
    const fatal = (try policy.reportUnhandled(process, pending)).?;
    defer fatal.deinit(engine);
    const other = try field(engine, "other");
    defer engine.freeValue(other);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, fatal.reason, other));
    try std.testing.expectEqual(policy_mod.Origin.uncaughtException, fatal.origin);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}

test "Promise rejection policy Source handled unhandled listener and uncaught listener allow ordinary continuation" {
    const fixture = try setup();
    defer fixture.deinit();
    const engine = fixture.engine;
    var policy = try policy_mod.Policy.init(engine);
    defer policy.deinit();
    try script(engine, "globalThis.reason=Error('handled');globalThis.promise=Promise.reject(reason);const handler=(value,p)=>{if(value!==reason||p!==promise)throw Error('handled identity')};process.on('unhandledRejection',handler);globalThis.remove=()=>process.off('unhandledRejection',handler);");
    const process = try field(engine, "process");
    defer engine.freeValue(process);
    const pending = try rejection(engine);
    defer pending.deinit(engine.context);
    const unhandled_outcome = try policy.reportUnhandled(process, pending);
    defer if (unhandled_outcome) |unexpected| unexpected.deinit(engine);
    try std.testing.expect(unhandled_outcome == null);
    try script(engine, "remove();process.on('uncaughtException',(value,origin)=>{if(value!==reason||origin!=='unhandledRejection')throw Error('uncaught handling')});");
    const fatal = (try policy.reportUnhandled(process, pending)).?;
    defer fatal.deinit(engine);
    const uncaught_outcome = try policy.reportUncaught(process, fatal);
    defer if (uncaught_outcome) |unexpected| unexpected.deinit(engine);
    try std.testing.expect(uncaught_outcome == null);
    try script(engine, "if(process._exiting||process.exitCode)throw Error('handled must remain live');");
}

const scopes = @import("extensions/native_async_scope.zig");
fn noScopeChange(_: ?*anyopaque) void {}
const Probe = struct {
    producer: c.JSValue,
    catcher: c.JSValue,
    fn init(engine: *js.Engine) !Probe {
        const producer = try scopes.create(engine, null, noScopeChange, noScopeChange);
        errdefer engine.freeValue(producer);
        const catcher = try scopes.create(engine, null, noScopeChange, noScopeChange);
        errdefer engine.freeValue(catcher);
        var values = [_]c.JSValue{ producer, catcher };
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, scopeProbe, "privateScopeProbe", 0, 0, values.len, &values));
        const root = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(root);
        try js.define(engine, root, "privateScopeProbe", function);
        return .{ .producer = producer, .catcher = catcher };
    }
    fn deinit(self: Probe, engine: *js.Engine) void {
        scopes.retire(engine, self.producer);
        scopes.retire(engine, self.catcher);
        engine.freeValue(self.producer);
        engine.freeValue(self.catcher);
    }
};
fn scopeProbe(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, values: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const current = scopes.capture(engine);
    defer engine.freeValue(current);
    return c.JS_NewString(engine.context, if (c.JS_IsStrictEqual(engine.context, current, values[0])) "producer" else if (c.JS_IsStrictEqual(engine.context, current, values[1])) "catcher" else "neutral");
}
fn neutralScope(engine: *js.Engine) !void {
    const current = scopes.capture(engine);
    defer engine.freeValue(current);
    try std.testing.expect(c.JS_IsUndefined(current));
}
fn runIn(engine: *js.Engine, token: c.JSValue, source: []const u8) !void {
    const guard = scopes.enter(engine, token);
    defer guard.restore();
    try script(engine, source);
}
fn scopedRejection(engine: *js.Engine, producer: c.JSValue) !rejection_mod.Rejection {
    return .{ .promise = try field(engine, "promise"), .reason = try field(engine, "reason"), .scope = c.JS_DupValue(engine.context, producer), .uid = 1 };
}

test "Promise rejection policy actual Source async8 default Error and own stack retain producer through monitor" {
    inline for (.{ "Error('original')", "Object.defineProperty({},'stack',{get(){throw Error('no isErrorLike read')}})" }) |expression| {
        const fixture = try setup();
        defer fixture.deinit();
        const engine = fixture.engine;
        var policy = try policy_mod.Policy.init(engine);
        defer policy.deinit();
        const probe = try Probe.init(engine);
        defer probe.deinit(engine);
        try script(engine, "globalThis.log=[];process.on('uncaughtExceptionMonitor',(value,origin)=>log.push({scope:privateScopeProbe(),origin,original:value===reason}));");
        try runIn(engine, probe.producer, "globalThis.reason=" ++ expression ++ ";globalThis.promise=Promise.reject(reason);");
        const process = try field(engine, "process");
        defer engine.freeValue(process);
        const pending = try scopedRejection(engine, probe.producer);
        defer pending.deinit(engine.context);
        const fatal = (try policy.reportUnhandled(process, pending)).?;
        defer fatal.deinit(engine);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, fatal.scope, probe.producer));
        try neutralScope(engine);
        const terminal = (try policy.reportUncaught(process, fatal)).?;
        defer terminal.deinit(engine);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, terminal.scope, probe.producer));
        try neutralScope(engine);
        try script(engine, "if(JSON.stringify(log)!=='[{\"scope\":\"producer\",\"origin\":\"unhandledRejection\",\"original\":true}]')throw Error('Source default producer context');");
    }
}

test "Promise rejection policy actual Source async8 listener and descriptor trap throws unwind to prior context" {
    for ([_]bool{ false, true }) |proxy| {
        const fixture = try setup();
        defer fixture.deinit();
        const engine = fixture.engine;
        var policy = try policy_mod.Policy.init(engine);
        defer policy.deinit();
        const probe = try Probe.init(engine);
        defer probe.deinit(engine);
        try script(engine, "globalThis.log=[];globalThis.other={toString(){throw Error('no original reason coercion')}};process.on('uncaughtExceptionMonitor',(value,origin)=>log.push({scope:privateScopeProbe(),origin,original:value===other}));");
        if (proxy) {
            try runIn(engine, probe.producer, "globalThis.reason=new Proxy({},{getOwnPropertyDescriptor(target,key){if(key==='stack'){log.push({scope:privateScopeProbe(),phase:'throw'});throw other}return Reflect.getOwnPropertyDescriptor(target,key)}});globalThis.promise=Promise.reject(reason);");
        } else {
            try script(engine, "process.on('unhandledRejection',()=>{log.push({scope:privateScopeProbe(),phase:'throw'});throw other});");
            try runIn(engine, probe.producer, "globalThis.reason=Error('original');globalThis.promise=Promise.reject(reason);");
        }
        const process = try field(engine, "process");
        defer engine.freeValue(process);
        const pending = try scopedRejection(engine, probe.producer);
        defer pending.deinit(engine.context);
        const fatal = (try policy.reportUnhandled(process, pending)).?;
        defer fatal.deinit(engine);
        try std.testing.expect(c.JS_IsUndefined(fatal.scope));
        try std.testing.expectEqual(policy_mod.Origin.uncaughtException, fatal.origin);
        const terminal = (try policy.reportUncaught(process, fatal)).?;
        defer terminal.deinit(engine);
        try std.testing.expect(c.JS_IsUndefined(terminal.scope));
        try neutralScope(engine);
        try script(engine, "if(JSON.stringify(log)!=='[{\"scope\":\"producer\",\"phase\":\"throw\"},{\"scope\":\"neutral\",\"origin\":\"uncaughtException\",\"original\":true}]')throw Error('Source throw unwind context');");
    }
}

fn contextTracker(_: ?*c.JSContext, promise: c.JSValue, reason: c.JSValue, handled: bool, raw: ?*anyopaque) callconv(.c) void {
    const queue: *rejection_mod.Queue = @ptrCast(@alignCast(raw.?));
    queue.observe(promise, reason, handled);
}
test "Promise rejection policy actual Source async8 catch reaction inherits catcher and late handled stays neutral" {
    for ([_]bool{ false, true }) |microtask| {
        const fixture = try setup();
        defer fixture.deinit();
        const engine = fixture.engine;
        var queue = try rejection_mod.Queue.init(engine, std.testing.allocator);
        defer queue.deinit();
        c.JS_SetHostPromiseRejectionTracker(engine.runtime, contextTracker, &queue);
        defer c.JS_SetHostPromiseRejectionTracker(engine.runtime, null, null);
        const probe = try Probe.init(engine);
        defer probe.deinit(engine);
        try script(engine, "globalThis.log=[];process.on('rejectionHandled',()=>log.push({phase:'handled',scope:privateScopeProbe()}));");
        try runIn(engine, probe.producer, "globalThis.reason=Error('original');globalThis.promise=Promise.reject(reason);");
        queue.checkpoint();
        const pending = (try queue.take()).?;
        defer pending.deinit(engine.context);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, pending.scope, probe.producer));
        try queue.noteReported(pending);
        // Native context adapter remains private; genuine JS reactions and the
        // actual C rejection callback establish handling, not a manual signal.
        try runIn(engine, probe.catcher, if (microtask) "queueMicrotask(()=>promise.catch(()=>log.push({phase:'catch',scope:privateScopeProbe()})));" else "promise.catch(()=>log.push({phase:'catch',scope:privateScopeProbe()}));");
        _ = try engine.drainReadyJobs();
        const handled = (try queue.takeHandled()).?;
        defer handled.deinit(engine.context);
        const process = try field(engine, "process");
        defer engine.freeValue(process);
        const event = try engine.checked(c.JS_NewString(engine.context, "rejectionHandled"));
        defer engine.freeValue(event);
        engine.freeValue(try js.invoke(engine, process, "emit", &.{ event, handled.promise }));
        try neutralScope(engine);
        try script(engine, "if(JSON.stringify(log)!=='[{\"phase\":\"catch\",\"scope\":\"catcher\"},{\"phase\":\"handled\",\"scope\":\"neutral\"}]')throw Error('Source late handled context');");
    }
}
test "Promise rejection policy actual Source async8 handled listeners run in producer without leaking context" {
    for ([_]bool{ false, true }) |uncaught| {
        const fixture = try setup();
        defer fixture.deinit();
        const engine = fixture.engine;
        var policy = try policy_mod.Policy.init(engine);
        defer policy.deinit();
        const probe = try Probe.init(engine);
        defer probe.deinit(engine);
        try script(engine, "globalThis.log=[];");
        if (uncaught) try script(engine, "process.on('uncaughtExceptionMonitor',()=>log.push('monitor:'+privateScopeProbe()));process.on('uncaughtException',()=>log.push('handled:'+privateScopeProbe()));") else try script(engine, "process.on('unhandledRejection',()=>log.push('handled:'+privateScopeProbe()));");
        try runIn(engine, probe.producer, "globalThis.reason=Error('original');globalThis.promise=Promise.reject(reason);");
        const process = try field(engine, "process");
        defer engine.freeValue(process);
        const pending = try scopedRejection(engine, probe.producer);
        defer pending.deinit(engine.context);
        const fatal = try policy.reportUnhandled(process, pending);
        defer if (fatal) |value| value.deinit(engine);
        if (uncaught) {
            try std.testing.expect(fatal != null);
            const outcome = try policy.reportUncaught(process, fatal.?);
            defer if (outcome) |value| value.deinit(engine);
            try std.testing.expect(outcome == null);
            try script(engine, "if(JSON.stringify(log)!=='[\"monitor:producer\",\"handled:producer\"]')throw Error('Source handled uncaught scope');");
        } else {
            try std.testing.expect(fatal == null);
            try script(engine, "if(JSON.stringify(log)!=='[\"handled:producer\"]')throw Error('Source handled scope');");
        }
        try neutralScope(engine);
    }
}
