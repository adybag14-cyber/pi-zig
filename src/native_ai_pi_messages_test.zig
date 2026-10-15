const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn install(engine: *em.Engine) !void {
    try @import("extensions/native_url.zig").install(engine);
    try @import("extensions/text_encoding.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "piMessagesAPI", try scope.own(try @import("extensions/native_ai_pi_messages_factory.zig").create(engine)));
}
fn evaluate(engine: *em.Engine, input: []const u8, name: []const u8) !void {
    const result = engine.evalModule(input, name) catch |err| {
        std.debug.print("Pi messages: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(result);
}
test "native AI pi messages literal requests awaited callbacks event identity sparse tools and failures" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000, .interrupt_budget = 10000000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/ai-pi-messages-5ab.json");
    try sdk.put(engine, global, "piMessagesSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "ai-pi-messages-5ab.json")));
    try evaluate(engine, @embedFile("extensions/fixtures/ai-pi-messages-5ab.input.txt") ++
        \\if(piMessagesSource.sourceHead!=='5ab7fe74c400097b386662205cd93900695b8a71'||piMessagesSource.cases!==22||piMessagesSource.actualNode.version!=='v24.14.0')throw Error('actual original22 required');for(let i=0;i<18;i++)if(JSON.stringify(piMessagesRows[i])!==JSON.stringify(piMessagesSource.rows[i]))throw Error(JSON.stringify({case:i,actual:piMessagesRows[i],expected:piMessagesSource.rows[i]}));
        \\const rows=globalThis.piMessagesRows;if(rows.length!==18)throw Error('18 controls');const by=name=>rows.find(row=>row.name===name);const basic=by('basic-bytewise');if(basic.result.content[0].text!=='hello 😀'||basic.result.responseId!=='response-1'||basic.releases!==1)throw Error('stream result');if(basic.requests[0].url!=='https://example.invalid/v1/messages?debug=1'||!basic.requests[0].urlObject||basic.requests[0].body.options.cacheRetention!=='long'||basic.requests[0].body.options.maxTokens!==0||basic.requests[0].headers['x-test']!=='new'||'x-null'in basic.requests[0].headers||'ignored-model-header'in basic.requests[0].headers)throw Error('literal payload');if(basic.order.indexOf('payload-awaited')>basic.order.indexOf('fetch')||basic.order.indexOf('response-awaited')>basic.order.indexOf('reader'))throw Error('awaited hooks');const tool=by('tool-and-thinking').result;if(tool.content.length!==5||tool.content[0]!==null||tool.content[2].thinkingSignature!=='think'||!tool.content[2].redacted||tool.content[4].arguments.file!=='final'||tool.content[4].extra!==7||tool.stopReason!=='toolUse')throw Error('sparse content');if(by('first-data-only').events.length!==1||by('eof-terminal').result.stopReason!=='stop')throw Error('frame parsing');if(by('missing-terminal').result.errorMessage!=='test-pi stream ended without a terminal event'||by('missing-api-key').result.errorMessage!=='No API key provided for provider "test-pi"')throw Error('error text');if(by('http-structured').result.errorMessage!=='429 Slow Down: busy (quota)'||by('http-empty-message').result.errorMessage!=='400 Bad Request: '||by('http-array-error').result.diagnostics[0].details.body!=='{"error":[1,2]}')throw Error('HTTP body');if(by('http-aborted').result.stopReason!=='aborted'||by('http-aborted').result.diagnostics!==undefined)throw Error('abort diagnostic');if(by('response-hook-failure').result.errorMessage!=='hook rejected'||by('provider-hook-failure').result.errorMessage!=='event hook rejected'||by('provider-hook-failure').releases!==1)throw Error('hook failure');if(!by('payload-replacement').requests[0].body.custom||by('simple-options').result.stopReason!=='stop')throw Error('simple/replacement');
    , "native-ai-pi-messages-controls.mjs");
    c.JS_RunGC(engine.runtime);
}
test "native AI pi messages retained ordinary native functions keep dependencies across GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    try evaluate(engine,
        \\globalThis.keptPiStream=piMessagesAPI.stream;delete globalThis.piMessagesAPI;if(keptPiStream.length!==3||keptPiStream.name!=='stream'||Object.getPrototypeOf(keptPiStream)!==Function.prototype)throw Error('native function contract');
    , "native-ai-pi-messages-gc-before.mjs");
    c.JS_RunGC(engine.runtime);
    try evaluate(engine,
        \\const model={id:'m',api:'pi-messages',provider:'p',baseUrl:'https://example.invalid'},stream=keptPiStream(model,{messages:[]});const error=await stream.result();if(error.errorMessage!=='No API key provided for provider "p"'||error.api!=='pi-messages'||error.usage.totalTokens!==0)throw Error('retained dependencies');delete globalThis.keptPiStream;
    , "native-ai-pi-messages-gc-after.mjs");
    c.JS_RunGC(engine.runtime);
}
test "native AI pi messages owned HTTP bytes worker matches four original default fetch wire controls" {
    const gpa = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/ai-pi-messages-5ab.json"), .{});
    defer parsed.deinit();
    const rows = parsed.value.object.get("rows").?.array.items[18..22];
    const terminal = "{\"type\":\"done\",\"reason\":\"stop\",\"usage\":{\"input\":2,\"output\":3,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":5,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}},\"responseId\":\"wire-response\"}";
    const fixture = @import("ai/http_fixture.zig");
    const bodies = [_][]const u8{
        "data: {\"type\":\"start\"}\r\n\r\ndata: {\"type\":\"text_start\",\"contentIndex\":0}\n\ndata: {\"type\":\"text_delta\",\"contentIndex\":0,\"delta\":\"wire\"}\n\ndata: " ++ terminal ++ "\n\n",
        "{\"error\":{\"message\":\"denied\",\"code\":\"fixture\"}}",
        "data: " ++ terminal,
        "",
    };
    const statuses = [_]std.http.Status{ .ok, .forbidden, .ok, .no_content };
    for (rows, bodies, statuses, 0..) |row, body, status, index| {
        const payload = try std.json.Stringify.valueAlloc(gpa, row.object.get("requests").?.array.items[0].object.get("body").?, .{});
        defer gpa.free(payload);
        const server = try fixture.PlanServer.init(gpa, std.testing.io, &.{.{ .path = "/v1/messages", .body = body, .status = status, .reason = if (index == 1) "Fixture Denied" else null, .payload_contains = payload, .headers = &.{.{ .name = "x-fixture", .value = "source-only" }}, .expected_request_headers = &.{ .{ .name = "authorization", .value = "Bearer fixture-key" }, .{ .name = "accept", .value = "text/event-stream" }, .{ .name = "content-type", .value = "application/json" }, .{ .name = "x-test", .value = "yes" } } }});
        defer server.deinit();
        const url = try server.url(gpa, "/v1///");
        defer gpa.free(url);
        const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        engine.native_io = std.testing.io;
        try install(engine);
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try sdk.put(engine, global, "wireBaseUrl", try sdk.text(engine, url));
        const expected = try std.json.Stringify.valueAlloc(gpa, row, .{});
        defer gpa.free(expected);
        const expected_z = try gpa.dupeZ(u8, expected);
        defer gpa.free(expected_z);
        try sdk.put(engine, global, "wireSource", try engine.checked(c.JS_ParseJSON(engine.context, expected_z.ptr, expected_z.len, "pi-wire-source.json")));
        try evaluate(engine,
            \\Date.now=()=>123456789;const snapshot=value=>JSON.parse(JSON.stringify(value,(key,item)=>key==='stack'&&typeof item==='string'?'<stack>':key==='durationMs'&&typeof item==='number'?'<duration>':item));const order=[],events=[],model={id:'wire-model',api:'pi-messages',provider:'test-pi',baseUrl:wireBaseUrl},context={messages:[{role:'user',content:'wire request',timestamp:9}]};const stream=piMessagesAPI.stream(model,context,{apiKey:'fixture-key',headers:{'x-test':'yes'},maxTokens:0,cacheRetention:'none',onPayload(payload,seen){if(payload.context!==context||seen!==model)throw Error('literal identity');order.push('payload')},onResponse(response){order.push('response:'+response.status+':'+response.headers['x-fixture'])},onProviderStreamEvent(event){order.push('provider:'+event.type)}});let partial;for await(const event of stream){if(event.partial){if(partial&&partial!==event.partial)throw Error('partial alias');partial=event.partial}events.push(snapshot(event))}const result=await stream.result();if(partial&&result!==partial)throw Error('terminal alias');if(wireSource.result.diagnostics){const url=new URL(wireBaseUrl.replace(/\/+$/u,'')+'/messages').toString();wireSource.result.diagnostics[0].details.url=url;wireSource.events[0].error.diagnostics[0].details.url=url;}const actual=snapshot({events,result,order}),expected={events:wireSource.events,result:wireSource.result,order:wireSource.order};if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({actual,expected}));
        , "native-ai-pi-messages-owned-wire.mjs");
        try server.finish();
        try std.testing.expectEqual(@as(usize, 1), server.captured.items.len);
        try std.testing.expectEqualStrings(payload, server.captured.items[0].payload);
    }
}
test "native AI pi messages every allocation releases request codec converter roots and pending callbacks" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const usage={input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}},wire=new TextEncoder().encode('data: {"type":"start"}\n\ndata: '+JSON.stringify({type:'done',reason:'stop',usage})+'\n\n');let read=false,release=0;const stream=piMessagesAPI.stream({id:'m',api:'pi-messages',provider:'p',baseUrl:'https://example.invalid'},{messages:[]},{apiKey:'fixture',async onPayload(payload){await Promise.resolve();return payload},fetch:async()=>({status:200,statusText:'OK',ok:true,headers:{entries:()=>[][Symbol.iterator]()},body:{getReader:()=>({read:async()=>read?{done:true}:(read=true,{done:false,value:wire}),releaseLock(){release++}})}})});const result=await stream.result();if(result.stopReason!=='stop'||release!==1)throw Error(result.errorMessage||'stream did not finish');
            , "native-ai-pi-messages-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
