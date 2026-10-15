const std = @import("std");
const em = @import("extensions/engine.zig");
const collect = @import("extensions/native_body_collect.zig");
const v = @import("extensions/native_ai_provider_values.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    try @import("extensions/abort_signal.zig").install(engine);
    const Adapter = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            host.native_exception_diagnostics_suppressed += 1;
            defer host.native_exception_diagnostics_suppressed -= 1;
            var scope: v.Scope = .{ .engine = host };
            defer scope.deinit();
            var options: collect.Options = .{};
            if (args.len > 1 and try v.eq(&scope, args[1], "text")) options.mode = .text;
            if (args.len > 1 and try v.eq(&scope, args[1], "arrayBuffer")) options.mode = .array_buffer;
            if (args.len > 2 and !v.nullish(args[2])) {
                var limit: i64 = 0;
                if (c.JS_ToInt64(host.context, &limit, args[2]) < 0) return v.js.capture(host);
                if (limit < 0) return error.InvalidBodyLimit;
                options.max_bytes = @intCast(limit);
            }
            if (args.len > 3) options.signal = args[3];
            if (args.len > 4) options.cancel = args[4];
            if (args.len > 5 and scope.truthy(args[5])) options.input = .byte_events;
            return collect.collect(host, if (args.len > 0) args[0] else c.pi_js_undefined(), options);
        }
    };
    const function = try @import("extensions/native_node_function.zig").createArrow(engine, "collect", 6, Adapter.call, &.{});
    defer engine.freeValue(function);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(try scope.own(c.JS_GetGlobalObject(engine.context)), "collectBody", function);
}
fn evaluate(engine: *em.Engine, source: []const u8, name: [:0]const u8) !void {
    const result = engine.evalModule(source, name) catch |err| {
        std.debug.print("Body collector: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(result);
}
test "native body collector large bytes UTF8 EOF mutation framing and binary ownership" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000, .interrupt_budget = 10000000 });
    defer engine.deinit();
    try install(engine);
    try evaluate(engine,
        \\const reader=chunks=>({async read(){return chunks.length?{value:chunks.shift(),done:false}:{done:true}}});const large=new Uint8Array(700000).fill(65),text=await collectBody(reader([large]),'text');if(text.length!==700000||text[699999]!=='A')throw Error('large success beyond previous aggregation bound');const replacement=await collectBody(reader([new Uint8Array([239]),new Uint8Array([187,191,97,226,40,161,240,159])]),'text');if(replacement!=='a�(��')throw Error('BOM replacement and incomplete EOF');const chunk=new Uint8Array([65,66]);let position=0;const mutated=await collectBody({async read(){if(position++===0)return {value:chunk,done:false};chunk[1]=90;return {done:true}}},'text');if(mutated!=='AZ')throw Error('retain chunks through EOF');const source=new Uint8Array([3,4]),bytes=await collectBody(reader([source]),'bytes');source[0]=9;if(!(bytes instanceof Uint8Array)||bytes.join(',')!=='3,4')throw Error('owned bytes');const buffer=await collectBody(reader([new Uint8Array([5,6])]),'arrayBuffer');if(!(buffer instanceof ArrayBuffer)||new Uint8Array(buffer).join(',')!=='5,6')throw Error('owned ArrayBuffer');const frames=[{type:'bytes',data:new Uint8Array([65])},{type:'bytes',data:new Uint8Array([66])}];const framed=await collectBody({async next(){return frames.length?{value:frames.shift(),done:false}:{done:true}}},'text',undefined,undefined,undefined,true);if(framed!=='AB')throw Error('shared HTTP byte framing');if(await collectBody(reader([new Uint8Array()]),'text')!=='')throw Error('empty bytes');
    , "native-body-collect-values.mjs");
}
test "native body collector budget abort wrong chunk and source rejection retain original reasons" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    try evaluate(engine,
        \\let cancelReason,reads=0;const limited=await collectBody({async read(){reads++;return {value:new Uint8Array(600000),done:false}}},'bytes',550000,undefined,reason=>{cancelReason=reason;return Promise.reject('ignored cancel failure')}).then(()=>null,error=>error);if(limited?.code!=='NativeBodyLimit'||limited.limit!==550000||cancelReason!==limited||reads!==1)throw Error('explicit no-truncation budget');const reason={marker:'original',toString(){throw Error('must not coerce')}},rejected=await collectBody({read(){return Promise.reject(reason)}}).then(()=>null,error=>error);if(rejected!==reason)throw Error('reader error identity');for(const value of ['text',new Uint16Array([1]),new Uint8ClampedArray([1]),new ArrayBuffer(2),new DataView(new ArrayBuffer(2))]){const wrong=await collectBody({read(){return {done:false,value}}}).then(()=>null,error=>error);if(!(wrong instanceof TypeError)||wrong.message!=='Received non-Uint8Array chunk')throw Error('wrong chunk brand');}const controller=new AbortController();let readResolve;const pending=collectBody({read(){return new Promise(resolve=>readResolve=resolve)}},'bytes',undefined,controller.signal,reason=>{cancelReason=reason});controller.abort(reason);if(await pending.then(()=>null,error=>error)!==reason||cancelReason!==reason)throw Error('pending abort identity');readResolve({done:true});await Promise.resolve();const before=new AbortController();before.abort(reason);if(await collectBody({read(){throw Error('preabort read')}},'bytes',undefined,before.signal).then(()=>null,error=>error)!==reason)throw Error('preabort');
    , "native-body-collect-failures.mjs");
}
test "native body collector pending chunk graph survives GC without reader lock release" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    try evaluate(engine,
        \\let reads=0;globalThis.collectPending=collectBody({read(){if(reads++===0)return {value:new Uint8Array(700000).fill(66),done:false};return new Promise(resolve=>globalThis.collectResume=resolve)},releaseLock(){throw Error('must retain reader lock')}},'text');await Promise.resolve();await Promise.resolve();
    , "native-body-collect-gc-before.mjs");
    c.JS_RunGC(engine.runtime);
    try evaluate(engine,
        \\collectResume({done:true});const result=await collectPending;if(result.length!==700000||result[699999]!=='B')throw Error('rooted bytes across GC');delete globalThis.collectPending;delete globalThis.collectResume;
    , "native-body-collect-gc-after.mjs");
    c.JS_RunGC(engine.runtime);
}
test "native body collector every host allocation releases decoder chunks and async callback roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const chunks=[new Uint8Array([239,187]),new Uint8Array([191,65,226,40,161])],reader={async read(){await Promise.resolve();return chunks.length?{value:chunks.shift(),done:false}:{done:true}}},text=await collectBody(reader,'text');if(text!=='A�(�')throw Error('collector allocation probe');
            , "native-body-collect-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
