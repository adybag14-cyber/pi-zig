const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const facade = @import("extensions/native_ai_google_mistral_factory.zig");
const c = em.c;
comptime {
    _ = @import("ai/mistral.zig");
}
fn install(engine: *em.Engine) !void {
    try @import("extensions/native_stream.zig").install(engine);
    if (engine.text_decoder_class == 0) try @import("extensions/text_decoder.zig").install(engine);
    if (engine.text_encoder_class == 0) try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/node_url.zig").install(engine);
    try @import("extensions/console.zig").install(engine, std.testing.io);
    const base64_module = try sdk.object(engine);
    defer engine.freeValue(base64_module);
    try @import("extensions/node_base64.zig").install(engine, base64_module);
    const imported = try engine.evalModule("import 'pi-ai';export const loaded=true;", "native-google-mistral-stream-install.mjs");
    engine.freeValue(imported);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    inline for (.{ .{ "google", facade.Kind.google }, .{ "vertex", facade.Kind.vertex }, .{ "mistral", facade.Kind.mistral } }) |entry| try sdk.put(engine, global, entry[0], try facade.create(engine, entry[1]));
}
fn source(engine: *em.Engine, name: [*:0]const u8, value: std.json.Value) !void {
    const bytes = try std.json.Stringify.valueAlloc(engine.gpa, value, .{});
    defer engine.gpa.free(bytes);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, name, try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-source5ab-google-mistral60.json")));
}
test "native AI Google Mistral Source60 request component retains actual payload hook and wire observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const v = @import("extensions/native_ai_provider_values.zig");
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const dependencies = try scope.own(try @import("extensions/native_ai_openai_dependencies.zig").create(engine));
    try scope.put(dependencies, "text", try scope.own(try @import("extensions/native_ai_text.zig").create(engine)));
    const Adapter = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: v.Scope = .{ .engine = host };
            defer row.deinit();
            if (args.len != 4) return error.NativeGoogleMistralRequestTestArguments;
            const is_mistral = try v.eq(&row, args[0], "mistral");
            const is_vertex = try v.eq(&row, args[0], "vertex");
            const mid_system = is_mistral and row.truthy(try v.optional(&row, try row.get(args[1], "compat"), "supportsMidConvoSystemMessages"));
            const context = try row.own(try @import("extensions/native_ai_provider_transcript.zig").resolve(host, args[2], mid_system));
            const options = if (is_mistral) try @import("extensions/native_ai_mistral_request.zig").simple(&row, roots[0], args[1], args[2], args[3]) else try @import("extensions/native_ai_google_request.zig").simple(&row, roots[0], args[1], args[2], args[3], is_vertex);
            const payload = try row.own(if (is_mistral) try @import("extensions/native_ai_mistral_request.zig").build(host, roots[0], args[1], context, options) else try @import("extensions/native_ai_google_request.zig").build(host, roots[0], args[1], context, options));
            const result = try row.object();
            try row.put(result, "payload", payload);
            if (row.truthy(try v.optional(&row, args[3], "replace"))) {
                if (is_mistral) try row.put(payload, "temperature", c.JS_NewFloat64(host.context, 0.25)) else try row.put(try row.get(payload, "config"), "temperature", c.JS_NewFloat64(host.context, 0.25));
            }
            try row.put(result, "wire", if (is_mistral) try @import("extensions/native_ai_mistral_request.zig").wire(&row, payload) else try @import("extensions/native_ai_google_request.zig").wire(&row, payload));
            return c.JS_DupValue(host.context, result);
        }
    };
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "buildProviderRequest", try @import("extensions/native_node_function.zig").create(engine, "buildProviderRequest", 4, Adapter.call, &.{dependencies}));
    const original_bytes = @embedFile("extensions/fixtures/ai-google-mistral60-5ab.json");
    try sdk.put(engine, global, "source60", try engine.checked(c.JS_ParseJSON(engine.context, original_bytes.ptr, original_bytes.len, "actual-source5ab-google-mistral60.json")));
    const checked = engine.evalModule(
        \\function canonical(v){if(Array.isArray(v))return v.map(canonical);if(v&&typeof v==='object'){const out={};for(const k of Object.keys(v).sort())if(v[k]!==undefined)out[k]=canonical(v[k]);return out}return v}let count=0;for(const expected of source60.rows){if(!expected.payloads.length)continue;const item=expected.input,model={id:item.kind==='mistral'?'mistral-fixture':'gemini-3.1-pro-preview',name:'fixture',provider:item.kind==='vertex'?'google-vertex':item.kind,api:item.kind==='google'?'google-generative-ai':item.kind==='vertex'?'google-vertex':'mistral-conversations',baseUrl:'http://127.0.0.1/v1',reasoning:false,input:['text','image'],cost:{input:1,output:2,cacheRead:.5,cacheWrite:1.5},contextWindow:32000,maxTokens:8192,...item.model},context=item.context??{messages:[{role:'system',content:'system',timestamp:0},{role:'user',content:'hello',timestamp:1}]},options={apiKey:'fixture-placeholder-key',maxTokens:1000,maxRetries:0,sessionId:'fixture-session',...item.options};const actual=buildProviderRequest(item.kind,model,context,options);if(JSON.stringify(canonical(actual.payload))!==JSON.stringify(canonical(expected.payloads[0])))throw Error(JSON.stringify({name:item.name,payload:actual.payload,expected:expected.payloads[0]}));if(item.callback==='replace'){if(item.kind==='mistral')actual.wire.temperature=.25;else actual.wire.generationConfig.temperature=.25}if(JSON.stringify(canonical(actual.wire))!==JSON.stringify(canonical(expected.requests[0].body)))throw Error(JSON.stringify({name:item.name,wire:actual.wire,expected:expected.requests[0].body}));count++}if(count!==57)throw Error('all57 actual request controls required');export const done=true;
    , "native-google-mistral-request-source60.mjs") catch |err| {
        std.debug.print("Google/Mistral requests: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}
fn source60Http(full_snapshots: bool) !void {
    const gpa = std.testing.allocator;
    const v = @import("extensions/native_ai_provider_values.zig");
    for (0..60) |case_index| {
        const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        engine.native_io = std.testing.io;
        try install(engine);
        var scope: v.Scope = .{ .engine = engine };
        defer scope.deinit();
        const original_bytes = @embedFile("extensions/fixtures/ai-google-mistral60-5ab.json");
        const original = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, original_bytes.ptr, original_bytes.len, "actual-source5ab-google-mistral.json")));
        try std.testing.expect(try v.eq(&scope, try scope.get(original, "sourceHead"), "5ab7fe74c400097b386662205cd93900695b8a71"));
        const rows = try scope.get(original, "rows");
        try std.testing.expectEqual(@as(u32, 60), try v.length(&scope, rows));
        const observation = try v.at(&scope, rows, @intCast(case_index));
        const input = try scope.get(observation, "input");
        const requests = try scope.get(observation, "requests");
        const request_count = try v.length(&scope, requests);
        const name = try engine.toString(try scope.get(input, "name"));
        defer gpa.free(name);
        var wire: std.ArrayList(u8) = .empty;
        defer wire.deinit(gpa);
        var chunk_ends: std.ArrayList(usize) = .empty;
        defer chunk_ends.deinit(gpa);
        var raw_body = try scope.get(input, "body");
        if (c.JS_IsUndefined(raw_body)) raw_body = try scope.get(input, "rawSSE");
        if (!c.JS_IsUndefined(raw_body)) {
            const bytes = try engine.toString(raw_body);
            defer gpa.free(bytes);
            try wire.appendSlice(gpa, bytes);
        } else {
            var chunks = try scope.get(input, "chunks");
            if (c.JS_IsUndefined(chunks)) {
                const encoded = if (try v.eq(&scope, try scope.get(input, "kind"), "mistral")) "[{\"id\":\"response-1\",\"choices\":[{\"delta\":{\"content\":\"answer\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":4,\"total_tokens\":16}}]" else "[{\"responseId\":\"response-1\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"answer\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":12,\"candidatesTokenCount\":4,\"totalTokenCount\":16}}]";
                chunks = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, encoded.ptr, encoded.len, "source-response-input.json")));
            }
            var chunk_rows = try v.iterator(&scope, chunks);
            defer chunk_rows.deinit();
            errdefer chunk_rows.closePreserving();
            while (try chunk_rows.next()) |chunk| {
                defer engine.freeValue(chunk);
                const bytes = try engine.toString(try scope.invoke(try scope.global("JSON"), "stringify", &.{chunk}));
                defer gpa.free(bytes);
                try wire.appendSlice(gpa, "data: ");
                try wire.appendSlice(gpa, bytes);
                try wire.appendSlice(gpa, "\n\n");
                try chunk_ends.append(gpa, wire.items.len);
            }
        }
        var response_chunks: std.ArrayList([]const u8) = .empty;
        defer response_chunks.deinit(gpa);
        var offset: usize = 0;
        for (chunk_ends.items) |end| {
            try response_chunks.append(gpa, wire.items[offset..end]);
            offset = end;
        }
        const fixture = @import("ai/http_fixture.zig");
        const request = if (request_count > 0) try v.at(&scope, requests, 0) else c.pi_js_undefined();
        const path = if (request_count > 0) try engine.toString(try scope.get(request, "path")) else try gpa.dupe(u8, "/no-request");
        defer gpa.free(path);
        var expected_headers: std.ArrayList(std.http.Header) = .empty;
        defer expected_headers.deinit(gpa);
        defer for (expected_headers.items) |header| {
            gpa.free(header.name);
            gpa.free(header.value);
        };
        if (request_count > 0) {
            var fields = try v.iterator(&scope, try scope.invoke(try scope.global("Object"), "entries", &.{try scope.get(request, "headers")}));
            defer fields.deinit();
            errdefer fields.closePreserving();
            while (try fields.next()) |field| {
                defer engine.freeValue(field);
                const key = try engine.toString(try v.at(&scope, field, 0));
                errdefer gpa.free(key);
                const value = try engine.toString(try v.at(&scope, field, 1));
                errdefer gpa.free(value);
                try expected_headers.append(gpa, .{ .name = key, .value = value });
            }
        }
        var status: i32 = 200;
        const status_value = try scope.get(input, "status");
        if (!c.JS_IsUndefined(status_value) and c.JS_ToInt32(engine.context, &status, status_value) < 0) return v.js.capture(engine);
        const plan = fixture.Reply{ .path = path, .status = @enumFromInt(status), .body = wire.items, .body_chunks = if (c.JS_IsUndefined(raw_body)) response_chunks.items else null, .expected_request_headers = expected_headers.items, .headers = &.{ .{ .name = "content-type", .value = if (c.JS_IsUndefined(status_value)) "text/event-stream" else "application/json" }, .{ .name = "x-fixture", .value = "source-only" } } };
        const server = try fixture.PlanServer.init(gpa, std.testing.io, if (request_count > 0) &.{plan} else &.{});
        defer server.deinit();
        const url = try server.url(gpa, "/v1");
        defer gpa.free(url);
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try sdk.put(engine, global, "expected", c.JS_DupValue(engine.context, observation));
        try sdk.put(engine, global, "fullSnapshots", c.pi_js_bool(engine.context, @intFromBool(full_snapshots)));
        try sdk.put(engine, global, "fixtureBase", try sdk.text(engine, url));
        const checked = engine.evalModule(
            \\function snapshot(value){if(Array.isArray(value))return value.map(snapshot);if(value&&typeof value==='object'){const out={};for(const[key,item]of Object.entries(value)){if(value.role==='assistant'&&key==='timestamp')out[key]='$TIMESTAMP';else if(value.role==='assistant'&&key==='durationMs')out[key]='$DURATION';else out[key]=snapshot(item)}return out}return value}
            \\function canonical(value){if(Array.isArray(value))return value.map(canonical);if(value&&typeof value==='object'){const result={};for(const key of Object.keys(value).sort())if(value[key]!==undefined)result[key]=canonical(value[key]);return result}return value}
            \\const item=expected.input,apiName=item.kind==='google'?'google-generative-ai':item.kind==='vertex'?'google-vertex':'mistral-conversations',model={id:item.kind==='mistral'?'mistral-fixture':'gemini-3.1-pro-preview',name:'fixture',provider:item.kind==='vertex'?'google-vertex':item.kind,api:apiName,baseUrl:fixtureBase,reasoning:false,input:['text','image'],cost:{input:1,output:2,cacheRead:.5,cacheWrite:1.5},contextWindow:32000,maxTokens:8192,...item.model},context=item.context??{messages:[{role:'system',content:'system',timestamp:0},{role:'user',content:'hello',timestamp:1}]},callbacks=[],events=[],payloads=[],options={apiKey:'fixture-placeholder-key',env:{GOOGLE_CLOUD_PROJECT:'',GCLOUD_PROJECT:'',GOOGLE_CLOUD_LOCATION:'',GOOGLE_APPLICATION_CREDENTIALS:''},maxTokens:1000,maxRetries:0,sessionId:'fixture-session',...item.options,onPayload(payload){callbacks.push('payload');payloads.push(snapshot(payload));if(item.callback==='replace')return {...payload,...(item.kind==='mistral'?{temperature:.25}:{config:{...payload.config,temperature:.25}})};if(item.callback==='async')return Promise.resolve()},onResponse(response){callbacks.push('response:'+response.status+':'+response.headers['x-fixture']);if(item.callback==='throw')throw Error('caller response failed');if(item.callback==='async')return Promise.resolve()},onProviderStreamEvent(chunk){callbacks.push('chunk');if(item.callback==='metadata')callbacks.push({constructor:chunk.constructor.name,keys:Object.keys(chunk),text:chunk.text,data:chunk.data,functionCalls:chunk.functionCalls,executableCode:chunk.executableCode,codeExecutionResult:chunk.codeExecutionResult,httpKeys:Object.keys(chunk.sdkHttpResponse?.headers??{}).filter(key=>key==='content-type'||key==='x-fixture')});if(item.callback==='async')return Promise.resolve()}};let result,syncError;try{const stream=globalThis[item.kind].streamSimple(model,context,options);for await(const event of stream)events.push(snapshot(event));result=snapshot(await stream.result())}catch(error){syncError={name:error.name,message:error.message}}for(const key of ['payloads','callbacks','result','syncError',...(fullSnapshots?['events']:[])]){const actual={payloads,callbacks,events,result,syncError}[key];if(JSON.stringify(canonical(actual))!==JSON.stringify(canonical(expected[key])))throw Error(JSON.stringify({case:item.name,key,actual,expected:expected[key]}))}if(!fullSnapshots){const shape=event=>{const out={...event};delete out.partial;delete out.message;delete out.error;return out};if(JSON.stringify(canonical(events.map(shape)))!==JSON.stringify(canonical(expected.events.map(shape))))throw Error(JSON.stringify({case:item.name,eventShapes:events.map(shape),expected:expected.events.map(shape)}))}export const done=true;
        , "native-google-mistral-actual-source60.mjs") catch |err| {
            std.debug.print("Google/Mistral {s}: {s}\n", .{ name, engine.last_error orelse "no diagnostic" });
            return err;
        };
        engine.freeValue(checked);
        try server.finish();
        try std.testing.expectEqual(@as(usize, request_count), server.captured.items.len);
        if (request_count > 0) {
            const actual = server.captured.items[0].payload;
            try sdk.put(engine, global, "actualWire", try engine.checked(c.JS_ParseJSON(engine.context, actual.ptr, actual.len, "native-wire.json")));
            const validated = engine.evalModule(
                \\function canonical(v){if(Array.isArray(v))return v.map(canonical);if(v&&typeof v==='object'){const out={};for(const key of Object.keys(v).sort())out[key]=canonical(v[key]);return out}return v}if(JSON.stringify(canonical(actualWire))!==JSON.stringify(canonical(expected.requests[0].body)))throw Error(JSON.stringify({name:expected.name,actual:actualWire,expected:expected.requests[0].body}));export const wire=true;
            , "native-google-mistral-source-wire.mjs") catch |err| {
                std.debug.print("Google/Mistral wire {s}: {s}\n", .{ name, engine.last_error orelse "no diagnostic" });
                return err;
            };
            engine.freeValue(validated);
        }
        c.JS_RunGC(engine.runtime);
    }
}
test "native AI Google Mistral actual Source60 full intermediate snapshots remain strict" {
    try source60Http(true);
}

test "native AI Google Mistral Source60 terminal callback SDK metadata auth wire event shape components" {
    try source60Http(false);
}

test "native AI Google Mistral retained facade roots survive collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule("globalThis.kept=[google.streamSimple,vertex.streamSimple,mistral.streamSimple];delete globalThis.google;delete globalThis.vertex;delete globalThis.mistral;export const prepared=true;", "native-google-mistral-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const checked = try engine.evalModule(
        \\for(const f of [kept[0],kept[2]]){try{f({provider:'fixture'},{messages:[]},{});throw Error('missing key accepted')}catch(error){if(error.message!=='No API key for provider: fixture')throw error}}delete globalThis.kept;export const checked=true;
    , "native-google-mistral-gc-complete.mjs");
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}
test "native AI Google Mistral complete native facade allocation graph" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const checked = engine.evalModule(
                \\const tool={name:'read',description:'read file',parameters:{type:'object',properties:{path:{type:'string'}},required:['path']}},context={messages:[{role:'system',content:'system',toolsAdded:[tool],timestamp:0},{role:'user',content:[{type:'text',text:'hello'},{type:'image',mimeType:'image/png',data:'AA=='}],timestamp:1}]};for(const [kind,api]of [['google','google-generative-ai'],['vertex','google-vertex'],['mistral','mistral-conversations']]){const model={id:kind==='mistral'?'mistral-fixture':'gemini-3.1-pro-preview',provider:kind,api,baseUrl:'http://127.0.0.1/v1',reasoning:false,input:['text','image'],cost:{input:1,output:2,cacheRead:.5,cacheWrite:1.5},contextWindow:32000,maxTokens:8192};const stream=globalThis[kind].stream(model,context,{apiKey:'fixture-placeholder',onPayload(){throw Error('stop before HTTP')}}),result=await stream.result();if(result.stopReason!=='error'||result.errorMessage!=='stop before HTTP')throw Error('owner failure retirement');for await(const event of stream){if(event.type!=='error')throw Error('unexpected owned terminal event')}}export const checked=true;
            , "native-google-mistral-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(checked);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
test "native AI Google Mistral pending payload continuations retain complete provider graphs through GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule(
        \\globalThis.gates=[];globalThis.pendingStreams=[];for(const [kind,api]of [['google','google-generative-ai'],['vertex','google-vertex'],['mistral','mistral-conversations']]){const model={id:kind==='mistral'?'mistral-fixture':'gemini-3.1-pro-preview',provider:kind,api,baseUrl:'http://127.0.0.1/v1',reasoning:false,input:['text'],cost:{input:1,output:2,cacheRead:.5,cacheWrite:1.5},contextWindow:32000,maxTokens:8192};pendingStreams.push(globalThis[kind].stream(model,{messages:[{role:'user',content:'hello',timestamp:0}]},{apiKey:'fixture-placeholder',onPayload(){return new Promise((_,reject)=>gates.push(reject))}}));delete globalThis[kind]}if(gates.length!==3)throw Error('actual pending payload continuations required');export const prepared=true;
    , "native-google-mistral-pending-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const checked = try engine.evalModule(
        \\for(const reject of gates)reject(Error('stop before HTTP'));for(const stream of pendingStreams){const result=await stream.result();if(result.stopReason!=='error'||result.errorMessage!=='stop before HTTP')throw Error('pending callback graph lost');const events=[];for await(const event of stream)events.push(event.type);if(JSON.stringify(events)!=='["error"]')throw Error('owned terminal event lost')}delete globalThis.gates;delete globalThis.pendingStreams;export const checked=true;
    , "native-google-mistral-pending-gc-complete.mjs");
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}
