const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const facade = @import("extensions/native_ai_google_mistral_factory.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
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
test "native AI Google Mistral actual Source60 request event callback error semantics" {
    const gpa = std.testing.allocator;
    const original = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/ai-google-mistral60-5ab.json"), .{});
    defer original.deinit();
    try std.testing.expectEqualStrings("5ab7fe74c400097b386662205cd93900695b8a71", original.value.object.get("sourceHead").?.string);
    const rows = original.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 60), rows.len);
    for (rows) |observation| {
        const input = observation.object.get("input").?;
        const requests = observation.object.get("requests").?.array.items;
        var wire: std.ArrayList(u8) = .empty;
        defer wire.deinit(gpa);
        const kind = input.object.get("kind").?.string;
        if (input.object.get("body")) |value| try wire.appendSlice(gpa, value.string) else {
            const encoded = if (input.object.get("chunks")) |chunks| try std.json.Stringify.valueAlloc(gpa, chunks, .{}) else try gpa.dupe(u8, if (std.mem.eql(u8, kind, "mistral")) "[{\"id\":\"response-1\",\"choices\":[{\"delta\":{\"content\":\"answer\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":4,\"total_tokens\":16}}]" else "[{\"responseId\":\"response-1\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"answer\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":12,\"candidatesTokenCount\":4,\"totalTokenCount\":16}}]");
            defer gpa.free(encoded);
            const parsed = try std.json.parseFromSlice(std.json.Value, gpa, encoded, .{});
            defer parsed.deinit();
            for (parsed.value.array.items) |chunk| {
                const bytes = try std.json.Stringify.valueAlloc(gpa, chunk, .{});
                defer gpa.free(bytes);
                try wire.appendSlice(gpa, "data: ");
                try wire.appendSlice(gpa, bytes);
                try wire.appendSlice(gpa, "\n\n");
            }
        }
        const fixture = @import("ai/http_fixture.zig");
        const path = if (requests.len > 0) requests[0].object.get("path").?.string else "/no-request";
        var expected_headers: std.ArrayList(std.http.Header) = .empty;
        defer expected_headers.deinit(gpa);
        if (requests.len > 0) {
            var fields = requests[0].object.get("headers").?.object.iterator();
            while (fields.next()) |field| try expected_headers.append(gpa, .{ .name = field.key_ptr.*, .value = field.value_ptr.string });
        }
        const plan = fixture.Reply{ .path = path, .status = if (input.object.get("status")) |status| @enumFromInt(status.integer) else .ok, .body = wire.items, .expected_request_headers = expected_headers.items, .headers = &.{.{ .name = "x-fixture", .value = "source-only" }} };
        const server = try fixture.PlanServer.init(gpa, std.testing.io, if (requests.len > 0) &.{plan} else &.{});
        defer server.deinit();
        const url = try server.url(gpa, "/v1");
        defer gpa.free(url);
        const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        engine.native_io = std.testing.io;
        try install(engine);
        try source(engine, "expected", observation);
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try sdk.put(engine, global, "fixtureBase", try sdk.text(engine, url));
        const checked = engine.evalModule(
            \\function snapshot(value){if(Array.isArray(value))return value.map(snapshot);if(value&&typeof value==='object'){const out={};for(const[key,item]of Object.entries(value)){if(value.role==='assistant'&&key==='timestamp')out[key]='$TIMESTAMP';else if(value.role==='assistant'&&key==='durationMs')out[key]='$DURATION';else out[key]=snapshot(item)}return out}return value}
            \\function canonical(value){if(Array.isArray(value))return value.map(canonical);if(value&&typeof value==='object'){const result={};for(const key of Object.keys(value).sort())if(value[key]!==undefined)result[key]=canonical(value[key]);return result}return value}
            \\const item=expected.input,apiName=item.kind==='google'?'google-generative-ai':item.kind==='vertex'?'google-vertex':'mistral-conversations',model={id:item.kind==='mistral'?'mistral-fixture':'gemini-3.1-pro-preview',name:'fixture',provider:item.kind==='vertex'?'google-vertex':item.kind,api:apiName,baseUrl:fixtureBase,reasoning:false,input:['text','image'],cost:{input:1,output:2,cacheRead:.5,cacheWrite:1.5},contextWindow:32000,maxTokens:8192,...item.model},context=item.context??{messages:[{role:'system',content:'system',timestamp:0},{role:'user',content:'hello',timestamp:1}]},callbacks=[],events=[],payloads=[],options={apiKey:'fixture-placeholder-key',env:{GOOGLE_CLOUD_PROJECT:'',GCLOUD_PROJECT:'',GOOGLE_CLOUD_LOCATION:'',GOOGLE_APPLICATION_CREDENTIALS:''},maxTokens:1000,maxRetries:0,sessionId:'fixture-session',...item.options,onPayload(payload){callbacks.push('payload');payloads.push(snapshot(payload));if(item.callback==='replace')return {...payload,...(item.kind==='mistral'?{temperature:.25}:{config:{...payload.config,temperature:.25}})};if(item.callback==='async')return Promise.resolve()},onResponse(response){callbacks.push('response:'+response.status+':'+response.headers['x-fixture']);if(item.callback==='throw')throw Error('caller response failed');if(item.callback==='async')return Promise.resolve()},onProviderStreamEvent(chunk){callbacks.push('chunk');if(item.callback==='metadata')callbacks.push({constructor:chunk.constructor.name,keys:Object.keys(chunk),text:chunk.text,data:chunk.data,functionCalls:chunk.functionCalls,executableCode:chunk.executableCode,codeExecutionResult:chunk.codeExecutionResult,httpKeys:Object.keys(chunk.sdkHttpResponse?.headers??{}).filter(key=>key==='content-type'||key==='x-fixture')});if(item.callback==='async')return Promise.resolve()}};let result,syncError;try{const stream=globalThis[item.kind].streamSimple(model,context,options);for await(const event of stream)events.push(snapshot(event));result=snapshot(await stream.result())}catch(error){syncError={name:error.name,message:error.message}}for(const key of ['payloads','callbacks','events','result','syncError']){const actual={payloads,callbacks,events,result,syncError}[key];if(JSON.stringify(canonical(actual))!==JSON.stringify(canonical(expected[key])))throw Error(JSON.stringify({case:item.name,key,actual,expected:expected[key]}))}export const done=true;
        , "native-google-mistral-actual-source60.mjs") catch |err| {
            std.debug.print("Google/Mistral {s}: {s}\n", .{ input.object.get("name").?.string, engine.last_error orelse "no diagnostic" });
            return err;
        };
        engine.freeValue(checked);
        try server.finish();
        try std.testing.expectEqual(requests.len, server.captured.items.len);
        if (requests.len > 0) {
            const actual = try std.json.parseFromSlice(std.json.Value, gpa, server.captured.items[0].payload, .{});
            defer actual.deinit();
            try source(engine, "actualWire", actual.value);
            const validated = engine.evalModule(
                \\function canonical(v){if(Array.isArray(v))return v.map(canonical);if(v&&typeof v==='object'){const out={};for(const key of Object.keys(v).sort())out[key]=canonical(v[key]);return out}return v}if(JSON.stringify(canonical(actualWire))!==JSON.stringify(canonical(expected.requests[0].body)))throw Error(JSON.stringify({name:expected.name,actual:actualWire,expected:expected.requests[0].body}));export const wire=true;
            , "native-google-mistral-source-wire.mjs") catch |err| {
                std.debug.print("Google/Mistral wire {s}: {s}\n", .{ input.object.get("name").?.string, engine.last_error orelse "no diagnostic" });
                return err;
            };
            engine.freeValue(validated);
        }
        c.JS_RunGC(engine.runtime);
    }
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
            const checked = engine.evalModule("for(const f of [google.streamSimple,mistral.streamSimple]){try{f({provider:'fixture'},{messages:[]},{});throw Error('missing key accepted')}catch(error){if(error.message!=='No API key for provider: fixture')throw error}}export const checked=true;", "native-google-mistral-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(checked);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
