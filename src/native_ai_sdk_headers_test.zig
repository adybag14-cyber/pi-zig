const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;

test "native SDK nullable headers preserve real brands removals multiple values and guest iterator ownership" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_headers.zig").install(engine);
    try @import("extensions/native_ai_sdk_headers.zig").install(engine);
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var scope: v.Scope = .{ .engine = host };
            defer scope.deinit();
            return c.JS_DupValue(host.context, try @import("extensions/native_ai_sdk_headers.zig").build(&scope, args));
        }
    };
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "sdkHeaders", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "sdkHeaders", 1, Adapter.call, &.{})));
    const result = engine.evalModule(
        \\const brand=Symbol.for('brand.privateNullableHeaders');
        \\const combined=sdkHeaders({'x-a':'old','x-b':'keep','x-stainless-helper':'one, two'},{'X-A':undefined,'x-b':null,'x-stainless-helper':['two,three','four']});
        \\if(!(combined.values instanceof Headers)||!(combined.nulls instanceof Set)||combined[brand]!==true||combined.values.get('x-a')!=='old'||combined.values.has('x-b')||!combined.nulls.has('x-b')||combined.values.get('x-stainless-helper')!=='one, two, three, four')throw Error('nullable and accumulating header semantics');
        \\const tuples=sdkHeaders([['X-a','one'],['x-a',['two','three']]]);if(tuples.values.get('x-a')!=='one, two, three')throw Error('tuple values should append');
        \\const record=sdkHeaders({'X-a':['one','two'],'x-a':['three']});if(record.values.get('x-a')!=='three')throw Error('record keys should clear before their first defined value');
        \\const nested=sdkHeaders({'x-b':'older'},combined);if(nested.values.has('x-b')||!nested.nulls.has('x-b'))throw Error('private nullable composition lost removal');
        \\try{sdkHeaders([[42,'value']]);throw Error('missing header name failure')}catch(error){if(!(error instanceof TypeError)||error.message!=='expected header name to be a string')throw error}
        \\let reads=0;const pair={0:'x-read',get 1(){reads++;return 'value'}};if(sdkHeaders([pair]).values.get('x-read')!=='value'||reads!==2)throw Error('header value getter must be read twice');
        \\const marker={},trace=[];const failingPair={0:'x-fail',get 1(){throw marker}};const sequence=[];sequence[Symbol.iterator]=()=>({next(){trace.push('next');return {value:failingPair,done:false}},return(){trace.push('return');return {done:true}}});try{sdkHeaders(sequence);throw Error('missing iterator failure')}catch(error){if(error!==marker)throw error}if(trace.join(',')!=='next,return')throw Error('guest iterator must close on failure');
        \\let intercepted=0;Object.defineProperty(Object.prototype,brand,{set(){intercepted++},configurable:true});try{if(sdkHeaders({'x-own':'ok'})[brand]!==true||intercepted!==0)throw Error('SDK brand must be own data property')}finally{delete Object.prototype[brand]}
        \\globalThis.retainedNullableHeaders=combined;export const headers=true;
    , "native-sdk-nullable-headers.mjs") catch |err| {
        std.debug.print("SDK nullable headers: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    const retained = try engine.evalModule(
        \\if(retainedNullableHeaders.values.get('x-a')!=='old'||!retainedNullableHeaders.nulls.has('x-b'))throw Error('nullable owners did not survive collection');delete globalThis.retainedNullableHeaders;export const collected=true;
    , "native-sdk-nullable-headers-retained.mjs");
    engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}
