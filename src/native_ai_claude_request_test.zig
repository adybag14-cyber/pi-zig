const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
fn install(engine: *v.em.Engine) !void {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "anthropicStreams", try scope.own(try @import("extensions/native_ai_anthropic_factory.zig").create(engine)));
    const Decoder = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            const json = try @import("extensions/native_ai_json_parse.zig").create(host);
            defer host.freeValue(json);
            return @import("extensions/native_ai_anthropic_decode.zig").create(host, args[0], args[1], json, false, args[2]);
        }
    };
    try scope.put(global, "anthropicDecoder", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "anthropicDecoder", 3, Decoder.call, &.{})));
    inline for (.{ "anthropic", "bedrock" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                var row: v.Scope = .{ .engine = host };
                defer row.deinit();
                const model = if (args.len > 0) args[0] else c.pi_js_undefined();
                const context = if (args.len > 1) args[1] else c.pi_js_undefined();
                const options = if (args.len > 2) args[2] else c.pi_js_undefined();
                return if (index == 0) @import("extensions/native_ai_anthropic_request.zig").build(host, model, context, false, options, false) else @import("extensions/native_ai_bedrock_request.zig").build(host, model, context, options);
            }
        };
        try scope.put(global, name, try scope.own(try @import("extensions/native_node_function.zig").create(engine, name, 3, Adapter.call, &.{})));
    }
}
test "native Claude5ab Anthropic request bodies match25 actual public Source observations" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const source = @embedFile("extensions/fixtures/ai-anthropic5ab.json");
    const terminated = try engine.gpa.dupeZ(u8, source);
    defer engine.gpa.free(terminated);
    try scope.put(global, "anthropicSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, source.len, "ai-anthropic5ab.json"))));
    const result = engine.evalModule(
        \\if(anthropicSource.sourceHead!=='5ab7fe74c400097b386662205cd93900695b8a71'||anthropicSource.cases!==25)throw Error('genuine Source25 required');for(const row of anthropicSource.rows){const item=row.input,model=row.model,context=row.context;let actual;const options={apiKey:'fixture-placeholder-key',env:{},maxTokens:1000,maxRetries:0,sessionId:'fixture-session',...item.options,onPayload(p){actual=JSON.parse(JSON.stringify(p));throw Error('request-only boundary')}};let stream;try{stream=anthropicStreams[item.simple?'streamSimple':'stream'](model,context,options)}catch(e){if(row.name!=='no-key')throw e;continue}const result=await stream.result();if(row.payloads.length){if(JSON.stringify(actual)!==JSON.stringify(row.payloads[0]))throw Error(JSON.stringify({name:row.name,actual,expected:row.payloads[0]}));if(result.stopReason!=='error'||result.errorMessage!=='request-only boundary')throw Error('request boundary failure')}else if(actual!==undefined||result.errorMessage!==row.result.errorMessage)throw Error(JSON.stringify({name:row.name,actual,result}));}export const requestSource=true;
    , "native-claude5ab-source-request.mjs") catch |err| {
        std.debug.print("Anthropic Source25 request: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native Claude5ab Anthropic real wire stream events callbacks and results match actual Source" {
    const gpa = std.testing.allocator;
    const fixture = @import("ai/http_fixture.zig");
    const source = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/ai-anthropic5ab.json"), .{});
    defer source.deinit();
    const default_chunks =
        \\[{"type":"message_start","message":{"id":"m1","model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":0}}},{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"answer"}},{"type":"content_block_stop","index":0},{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}},{"type":"message_stop"}]
    ;
    const defaults = try std.json.parseFromSlice(std.json.Value, gpa, default_chunks, .{});
    defer defaults.deinit();
    var exercised: usize = 0;
    for (source.value.object.get("rows").?.array.items) |row| {
        const input = row.object.get("input").?.object;
        if (input.get("noRequest") != null or input.get("status") != null) continue;
        const chunks = if (input.get("chunks")) |value| value.array.items else defaults.value.array.items;
        var wire: std.ArrayList(u8) = .empty;
        defer wire.deinit(gpa);
        for (chunks) |chunk| {
            const kind = chunk.object.get("type").?.string;
            if (input.get("omitStop") != null and std.mem.eql(u8, kind, "message_stop")) continue;
            const encoded = try std.json.Stringify.valueAlloc(gpa, chunk, .{});
            defer gpa.free(encoded);
            try wire.appendSlice(gpa, "event: ");
            try wire.appendSlice(gpa, kind);
            try wire.appendSlice(gpa, "\ndata: ");
            try wire.appendSlice(gpa, encoded);
            try wire.appendSlice(gpa, "\n\n");
        }
        const server = try fixture.PlanServer.init(gpa, std.testing.io, &.{.{ .path = "/v1/messages", .body = wire.items, .headers = &.{ .{ .name = "content-type", .value = "text/event-stream" }, .{ .name = "x-fixture", .value = "source-only" } } }});
        defer server.deinit();
        const address = try server.url(gpa, "");
        defer gpa.free(address);
        const engine = try v.em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        engine.native_io = std.testing.io;
        try install(engine);
        var scope: v.Scope = .{ .engine = engine };
        defer scope.deinit();
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        const encoded = try std.json.Stringify.valueAlloc(gpa, row, .{});
        defer gpa.free(encoded);
        const terminated = try gpa.dupeZ(u8, encoded);
        defer gpa.free(terminated);
        try scope.put(global, "sourceWire", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, encoded.len, "anthropic-source-wire-row.json"))));
        try scope.put(global, "sourceWireURL", try scope.text(address));
        const result = engine.evalModule(
            \\function snapshot(value){if(Array.isArray(value))return value.map(snapshot);if(value&&typeof value==='object'){const out={};for(const[key,item]of Object.entries(value)){if(value.role==='assistant'&&key==='timestamp')out[key]='$TIMESTAMP';else if(value.role==='assistant'&&key==='durationMs')out[key]='$DURATION';else out[key]=snapshot(item)}return out}return value}const row=sourceWire,item=row.input,model={...row.model,baseUrl:sourceWireURL};const callbacks=[],events=[],payloads=[];const options={apiKey:'fixture-placeholder-key',env:{},maxTokens:1000,maxRetries:0,sessionId:'fixture-session',...item.options,onPayload(payload){callbacks.push('payload');payloads.push(snapshot(payload));if(item.callback==='replace')return {...payload,temperature:.25};if(item.callback==='async')return Promise.resolve()},onResponse(response){callbacks.push('response:'+response.status+':'+response.headers['x-fixture']);if(item.callback==='throw')throw Error('caller response failed');if(item.callback==='async')return Promise.resolve()},onProviderStreamEvent(chunk){callbacks.push('chunk');if(item.callback==='async')return Promise.resolve()}};const stream=anthropicStreams[item.simple?'streamSimple':'stream'](model,row.context,options);for await(const event of stream)events.push(snapshot(event));const result=snapshot(await stream.result());for(const[key,actual]of Object.entries({payloads,callbacks,events,result})){if(JSON.stringify(actual)!==JSON.stringify(row[key]))throw Error(JSON.stringify({name:row.name,key,actual,expected:row[key]}));}export const wire=true;
        , "native-claude5ab-source-wire.mjs") catch |err| {
            std.debug.print("Anthropic wire {s}: {s}\n", .{ row.object.get("name").?.string, engine.last_error orelse "no diagnostic" });
            return err;
        };
        engine.freeValue(result);
        c.JS_RunGC(engine.runtime);
        var retirement_polls: usize = 0;
        while (@import("extensions/native_ai_http.zig").pending(engine) and retirement_polls < 200) : (retirement_polls += 1) {
            _ = try engine.pumpControls();
            if (@import("extensions/native_ai_http.zig").pending(engine)) try std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake);
        }
        try std.testing.expect(!@import("extensions/native_ai_http.zig").pending(engine));
        try server.finish();
        exercised += 1;
    }
    try std.testing.expectEqual(@as(usize, 22), exercised);
}
const observations =
    \\const a={api:'anthropic-messages',provider:'anthropic',id:'claude-haiku-5-5',name:'Claude Haiku 5.5',baseUrl:'https://api.anthropic.com',input:['text','image'],reasoning:true,maxTokens:8192,cost:{input:1,output:1,cacheRead:1,cacheWrite:1},compat:{forceAdaptiveThinking:true,supportsMidConvoSystemMessages:true,supportsMidConvoToolChanges:true,supportsMidConvoEffort:true},thinkingLevelMap:{off:null,max:'max'}};
    \\const tools=[{name:'Read',description:'read file',parameters:{type:'object',properties:{path:{type:'string'}},required:['path']}}];
    \\const msg=[{role:'system',content:'system',toolsAdded:tools},{role:'user',content:'hello'},{role:'assistant',api:a.api,provider:a.provider,model:a.id,stopReason:'toolUse',providerThinkingLevel:'low',content:[{type:'toolCall',id:'c1',name:'Read',arguments:{path:'a'}}]},{role:'toolResult',toolCallId:'c1',toolName:'Read',isError:true,content:[{type:'image',data:'AQI=',mimeType:'image/png'},{type:'text',text:'failed'},{type:'image',data:'Aw==',mimeType:'image/jpeg'}]}];
    \\const output=anthropic(a,{messages:msg},{thinkingEnabled:false,cacheRetention:'short'}),p=output.params,last=p.messages.at(-2);if(p.thinking.type!=='adaptive'||p.thinking.block_binding.prefix_mismatch_behavior!=='drop_block'||p.output_config.effort!=='high'||output.providerThinkingLevel!=='high')throw Error('unsupported off should keep managed effort');if(last.content[0].content!=='(image attached after the tool results)\nfailed\n(image attached after the tool results)'||last.content[1].text!=='Images from the error result of tool call c1 (Read):'||last.content[2].type!=='image'||last.content[3].type!=='image'||last.content[3].cache_control.type!=='ephemeral')throw Error('Anthropic exact error image ordering');
    \\const disabled=anthropic({...a,thinkingLevelMap:{}},{messages:msg},{thinkingEnabled:false}).params;if(disabled.thinking.type!=='disabled'||disabled.output_config!==undefined||disabled.messages.some(m=>m.output_config))throw Error('supported off must disable thinking and omit effort markers');
    \\const b={...a,api:'bedrock-converse-stream',provider:'amazon-bedrock',id:'application-profile',name:'Anthropic Claude Haiku 5.5'};const wire=bedrock(b,{messages:msg},{reasoning:'max',cacheRetention:'short'}),end=wire.messages.at(-1).content;if(wire.additionalModelRequestFields.output_config.effort!=='max'||wire.additionalModelRequestFields.thinking.block_binding.prefix_mismatch_behavior!=='drop_block')throw Error('Bedrock named profile/max map');if(end[0].toolResult.content[0].text!=='(image attached after the tool results)'||end[1].text!=='Images from the error result of tool call c1 (Read):'||!(end[2].image.source.bytes instanceof Uint8Array)||end[2].image.source.bytes[1]!==2||end.at(-1).cachePoint.type!=='default')throw Error('Bedrock byte blobs/error siblings');
    \\const success=bedrock({...b,id:'amazon.nova-pro',name:'Nova'},{messages:[{role:'toolResult',toolCallId:'x',toolName:'shot',isError:true,content:[{type:'image',data:'AQ==',mimeType:'image/png'}]}]},{cacheRetention:'none'});if(!success.messages[0].content[0].toolResult.content[0].image)throw Error('non-Claude error image must stay in tool result');
    \\const marker={};const getter={...a,get compat(){throw marker}};try{anthropic(getter,{messages:[]},{});throw Error('missing getter rejection')}catch(e){if(e!==marker)throw e}globalThis.retainedAnthropic=anthropic;globalThis.retainedModel=a;globalThis.retainedMessages=msg;export const proof=true;
;
test "native Claude5ab request owner graphs preserve error images unsupported off effort and actual Bedrock bytes" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const result = engine.evalModule(observations, "native-claude5ab-request-owner.mjs") catch |err| {
        std.debug.print("Claude request owner: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    const retained = try engine.evalModule(
        \\const p=retainedAnthropic(retainedModel,{messages:retainedMessages},{thinkingEnabled:true,effort:'max'});if(p.params.messages.at(-1).output_config.effort!=='max')throw Error('retained roots after GC');delete globalThis.retainedAnthropic;delete globalThis.retainedModel;delete globalThis.retainedMessages;export const retained=true;
    , "native-claude5ab-request-retained.mjs");
    engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}
test "native Claude5ab every host allocation releases request schemas transcript images and getter exceptions" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try v.em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(observations, "native-claude5ab-request-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
