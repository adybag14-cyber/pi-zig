const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const v = @import("extensions/native_ai_provider_values.zig");
const facade = @import("extensions/native_ai_google_mistral_factory.zig");
const peer = @import("native_ai_google_mistral_wire_fixture.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/native_stream.zig").install(engine);
    if (engine.text_decoder_class == 0) try @import("extensions/text_decoder.zig").install(engine);
    if (engine.text_encoder_class == 0) try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/node_url.zig").install(engine);
    try @import("extensions/console.zig").install(engine, std.testing.io);
    const base64 = try sdk.object(engine);
    defer engine.freeValue(base64);
    try @import("extensions/node_base64.zig").install(engine, base64);
    const imported = try engine.evalModule("import 'pi-ai';export const installed=true;", "provider-source20-prerequisites.mjs");
    engine.freeValue(imported);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    inline for (.{ .{ "google", facade.Kind.google }, .{ "vertex", facade.Kind.vertex }, .{ "mistral", facade.Kind.mistral } }) |entry| try sdk.put(engine, global, entry[0], try facade.create(engine, entry[1]));
    try sdk.put(engine, global, "nativeUserAgent", try sdk.text(engine, @import("ai/pi_user_agent.zig").value));
}
fn controls(comptime bytes: []const u8, count: u32, full: bool) !void {
    const gpa = std.testing.allocator;
    for (0..count) |index| {
        const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        try install(engine);
        var scope: v.Scope = .{ .engine = engine };
        defer scope.deinit();
        const original = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-source20-controls.json")));
        const rows = try scope.get(original, "rows");
        try std.testing.expectEqual(count, try v.length(&scope, rows));
        const expected = try v.at(&scope, rows, @intCast(index));
        const input = try scope.get(expected, "input");
        const request = try v.at(&scope, try scope.get(expected, "requests"), 0);
        var wire: std.ArrayList(u8) = .empty;
        defer wire.deinit(gpa);
        const raw = try scope.get(input, "rawSSE");
        if (!c.JS_IsUndefined(raw)) {
            const text = try engine.toString(raw);
            defer gpa.free(text);
            try wire.appendSlice(gpa, text);
        } else {
            var chunks = try scope.get(input, "chunks");
            if (c.JS_IsUndefined(chunks)) {
                const encoded = "[{\"responseId\":\"response-1\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"answer\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":12,\"candidatesTokenCount\":4,\"totalTokenCount\":16}}]";
                chunks = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, encoded.ptr, encoded.len, "actual-google-wire-input.json")));
            }
            var items = try v.iterator(&scope, chunks);
            defer items.deinit();
            errdefer items.closePreserving();
            while (try items.next()) |chunk| {
                defer engine.freeValue(chunk);
                const text = try engine.toString(try scope.invoke(try scope.global("JSON"), "stringify", &.{chunk}));
                defer gpa.free(text);
                try wire.appendSlice(gpa, "data: ");
                try wire.appendSlice(gpa, text);
                try wire.appendSlice(gpa, "\n\n");
            }
        }
        const server = try peer.Server.init(gpa, std.testing.io, wire.items);
        defer server.deinit();
        const url = try server.url(gpa, "/v1");
        defer gpa.free(url);
        const origin = try server.url(gpa, "");
        defer gpa.free(origin);
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        try scope.put(global, "expected", expected);
        try scope.put(global, "fixtureBase", try scope.text(url));
        try scope.put(global, "fullSnapshots", c.pi_js_bool(engine.context, @intFromBool(full)));
        const checked = engine.evalModule(
            \\function snapshot(v){if(Array.isArray(v))return v.map(snapshot);if(v&&typeof v==='object'){const out={};for(const[k,x]of Object.entries(v)){if(v.role==='assistant'&&k==='timestamp')out[k]='$TIMESTAMP';else if(v.role==='assistant'&&k==='durationMs')out[k]='$DURATION';else out[k]=snapshot(x)}return out}return v}function canonical(v){if(Array.isArray(v))return v.map(canonical);if(v&&typeof v==='object'){const out={};for(const k of Object.keys(v).sort())if(v[k]!==undefined)out[k]=canonical(v[k]);return out}return v}function same(a,b,key){if(JSON.stringify(canonical(a))!==JSON.stringify(canonical(b)))throw Error(JSON.stringify({name:expected.name,key,actual:a,expected:b}))}
            \\const item=expected.input,kind=item.kind,model={id:kind==='mistral'?'mistral-fixture':'gemini-3.1-pro-preview',name:'fixture',provider:kind==='vertex'?'google-vertex':kind,api:kind==='google'?'google-generative-ai':kind==='vertex'?'google-vertex':'mistral-conversations',baseUrl:fixtureBase,reasoning:false,input:['text','image'],cost:{input:1,output:2,cacheRead:.5,cacheWrite:1.5},contextWindow:32000,maxTokens:8192},context={messages:[{role:'system',content:'system',timestamp:0},{role:'user',content:'hello',timestamp:1}]},payloads=[],callbacks=[],events=[];if(item.symbolSchema){const symbol=Symbol.for('TypeBox.Kind');context.messages[0].toolsAdded=[{name:'read',description:'read file',parameters:{type:'object',properties:{path:{type:'string',[symbol]:'String'}},required:['path'],[symbol]:'Object'}}]}
            \\const options={apiKey:'fixture-placeholder-key',env:{GOOGLE_CLOUD_PROJECT:'',GCLOUD_PROJECT:'',GOOGLE_CLOUD_LOCATION:'',GOOGLE_APPLICATION_CREDENTIALS:''},maxTokens:1000,maxRetries:0,sessionId:'fixture-session',onPayload(payload){callbacks.push('payload');payloads.push(snapshot(payload));if(item.symbolSchema){const schema=payload.tools[0].function.parameters;callbacks.push({rootSymbols:Object.getOwnPropertySymbols(schema).length,nestedSymbols:Object.getOwnPropertySymbols(schema.properties.path).length})}},onResponse(response){callbacks.push('response:'+response.status+':'+response.headers['x-fixture'])},onProviderStreamEvent(chunk){callbacks.push('chunk');const part=chunk.candidates?.[0]?.content?.parts?.[0];if(item.callback==='live-text'){let reads=0,signatures=0;Object.defineProperty(part,'text',{enumerable:true,configurable:true,get(){callbacks.push('text:'+ ++reads);return 'text-'+reads}});Object.defineProperty(part,'thoughtSignature',{enumerable:true,configurable:true,get(){callbacks.push('signature:'+ ++signatures);return 'YWJjZA=='}})}if(item.callback==='live-function'){let reads=0;Object.defineProperty(part,'functionCall',{enumerable:true,configurable:true,get(){callbacks.push('function:'+ ++reads);return{id:'call-'+reads,name:'read-'+reads,args:{n:reads}}}})}}};const stream=globalThis[kind].streamSimple(model,context,options);for await(const event of stream)events.push(snapshot(event));const result=snapshot(await stream.result());same(payloads,expected.payloads,'payloads');same(callbacks,expected.callbacks,'callbacks');same(result,expected.result,'result');if(fullSnapshots)same(events,expected.events,'events');else{const shape=e=>{const out={...e};delete out.partial;delete out.message;delete out.error;return out};same(events.map(shape),expected.events.map(shape),'event shapes')}export const checked=true;
        , "native-actual-source12-wire.mjs") catch |err| {
            const name = try engine.toString(try scope.get(input, "name"));
            defer gpa.free(name);
            std.debug.print("Source20 wire {s}: {s}\n", .{ name, engine.last_error orelse "no diagnostic" });
            return err;
        };
        engine.freeValue(checked);
        const actual = try server.finish();
        const method = try engine.toString(try scope.get(request, "method"));
        defer gpa.free(method);
        try std.testing.expectEqualStrings(method, @tagName(actual.method));
        const target = try engine.toString(try scope.get(request, "path"));
        defer gpa.free(target);
        try std.testing.expectEqualStrings(target, actual.target);
        const body = try engine.toString(try scope.get(request, "rawBody"));
        defer gpa.free(body);
        try std.testing.expectEqualStrings(body, actual.body);
        const source_url = try engine.toString(try scope.get(request, "url"));
        defer gpa.free(source_url);
        try std.testing.expect(std.mem.endsWith(u8, source_url, target));
        const rebound = try server.url(gpa, target);
        defer gpa.free(rebound);
        try std.testing.expect(std.mem.startsWith(u8, rebound, origin));
        var fields = try v.iterator(&scope, try scope.invoke(try scope.global("Object"), "entries", &.{try scope.get(request, "headers")}));
        defer fields.deinit();
        errdefer fields.closePreserving();
        while (try fields.next()) |entry| {
            defer engine.freeValue(entry);
            const name = try engine.toString(try v.at(&scope, entry, 0));
            defer gpa.free(name);
            // These describe the received authority or HTTP client runtime.
            if (std.mem.eql(u8, name, "host") or std.mem.eql(u8, name, "connection") or std.mem.eql(u8, name, "user-agent") or std.mem.eql(u8, name, "x-goog-api-client") or std.mem.eql(u8, name, "accept-language") or std.mem.eql(u8, name, "accept-encoding") or std.mem.eql(u8, name, "sec-fetch-mode")) continue;
            const value = try engine.toString(try v.at(&scope, entry, 1));
            defer gpa.free(value);
            var matched = false;
            for (actual.headers) |field| if (std.ascii.eqlIgnoreCase(field.name, name)) {
                try std.testing.expectEqualStrings(value, field.value);
                matched = true;
            };
            try std.testing.expect(matched);
        }
        var ua = false;
        for (actual.headers) |field| if (std.ascii.eqlIgnoreCase(field.name, "user-agent")) {
            try std.testing.expectEqualStrings(@import("ai/pi_user_agent.zig").value, field.value);
            ua = true;
        };
        for (actual.headers) |field| if (std.ascii.eqlIgnoreCase(field.name, "x-goog-api-client")) {
            try std.testing.expect(std.mem.indexOf(u8, field.value, "gl-node/") == null);
        };
        try std.testing.expect(ua);
        c.JS_RunGC(engine.runtime);
    }
}
test "native AI Google Mistral Source12 actual wire framing getter functional components" {
    try controls(@embedFile("extensions/fixtures/ai-mistral-framing8-5ab.json"), 8, false);
    try controls(@embedFile("extensions/fixtures/ai-google-live4-5ab.json"), 4, false);
}
test "native AI Google Mistral Source12 full intermediate snapshots remain strict" {
    try controls(@embedFile("extensions/fixtures/ai-mistral-framing8-5ab.json"), 8, true);
    try controls(@embedFile("extensions/fixtures/ai-google-live4-5ab.json"), 4, true);
}
