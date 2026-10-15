const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "aiJSONAPI", try @import("extensions/native_ai_json_parse.zig").create(engine));
}
fn source(engine: *em.Engine, name: [*:0]const u8, bytes: [:0]const u8) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, name, try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "original-b06-observation.json")));
}
fn identity(input: []const u8, expected: []const u8) !void {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &digest, .{});
    try std.testing.expectEqualStrings(expected, &std.fmt.bytesToHex(digest, .lower));
}
test "native AI JSON OpenAI decoder matches genuine b06 HTTP20 terminal results and event shapes" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    try @import("extensions/native_stream.zig").install(engine);
    try source(engine, "openAIInput", @embedFile("extensions/fixtures/ai-openai-http-b06.input.json"));
    try source(engine, "openAISource", @embedFile("extensions/fixtures/ai-openai-http-b06.json"));
    const Adapter = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            if (args.len != 4) return error.OpenAIDecoderTestArguments;
            const compat = try @import("extensions/native_ai_openai_compat_options.zig").resolve(host, args[0]);
            defer host.freeValue(compat);
            return @import("extensions/native_ai_openai_decode.zig").create(host, args[0], compat, args[1], args[2], args[3]);
        }
    };
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "createOpenAIDecoder", try @import("extensions/native_node_function.zig").create(engine, "createOpenAIDecoder", 4, Adapter.call, &.{}));
    const checked = engine.evalModule(
        \\import {AssistantMessageEventStream} from 'pi-ai';
        \\if(openAISource.sourceHead!=='b06c1f2cf1dea6af8748ddeee18c23587d2cb7c6'||openAISource.rows.length!==20)throw Error('genuine HTTP20 required');
        \\function snapshot(value){if(Array.isArray(value))return value.map(snapshot);if(value&&typeof value==='object'){const out={};for(const [key,item]of Object.entries(value)){if(value.role==='assistant'&&key==='timestamp')out[key]='$TIMESTAMP';else if(value.role==='assistant'&&key==='durationMs')out[key]='$DURATION';else out[key]=snapshot(item)}return out}return value}
        \\for(let i=0;i<openAIInput.length;i++){const item=openAIInput[i],expected=openAISource.rows[i],model={id:item.kimiModel??'fixture-model',api:'openai-completions',provider:item.provider??'openai',baseUrl:'http://127.0.0.1/v1',reasoning:item.reasoning??false,cost:{input:1,output:2,cacheRead:.5,cacheWrite:1.5},compat:item.compat};const stream=new AssistantMessageEventStream(),decoder=createOpenAIDecoder(model,stream,aiJSONAPI,new Map());decoder.start();for(const chunk of item.chunks)decoder.push(chunk);decoder.finish();const events=[];for await(const event of stream)events.push(event);const actual=snapshot(await stream.result());if(JSON.stringify(actual)!==JSON.stringify(expected.result))throw Error(JSON.stringify({case:item.name,actual,expected:expected.result}));const shape=e=>{const out={...e};delete out.partial;delete out.message;delete out.error;return snapshot(out)};if(JSON.stringify(events.map(shape))!==JSON.stringify(expected.events.map(shape)))throw Error(JSON.stringify({case:item.name,events:events.map(shape),expected:expected.events.map(shape)}));}export const done=true;
    , "native-ai-openai-decoder-source20.mjs") catch |err| {
        std.debug.print("OpenAI decoder: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}
test "native AI JSON helpers and native partial fallback match33 genuine b06 observations" {
    const input = @embedFile("extensions/fixtures/ai-json-parse-b06.input.txt");
    try identity(input, "ce059a7d2ccb1673828797f6c05876970e7ac180a6ac87495f9d06a5059f1936");
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    try source(engine, "jsonSource", @embedFile("extensions/fixtures/ai-json-parse-b06.json"));
    const checked = engine.evalModule(
        \\if(jsonSource.sourceHead!=='b06c1f2cf1dea6af8748ddeee18c23587d2cb7c6'||jsonSource.rows.length!==33)throw Error('all original33 required');
        \\for(const row of jsonSource.rows.slice(0,28))for(const method of ['repairJson','parseJsonWithRepair','parseToolCallArguments','parseStreamingJson']){let actual;try{actual={value:aiJSONAPI[method](row.input)}}catch(error){actual={error:{name:error.name,message:error.message}}}if(JSON.stringify(actual)!==JSON.stringify(row[method]))throw Error(JSON.stringify({case:row.name,method,actual,expected:row[method]}));}export const checked=true;
    , "native-ai-json-b06-original28.mjs") catch |err| {
        std.debug.print("JSON b06: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(checked);
    const start = std.mem.indexOf(u8, input, "// Caller replacements expose").?;
    const end = std.mem.indexOf(u8, input, "export default rows;").?;
    const script = try std.fmt.allocPrint(std.testing.allocator, "const api=aiJSONAPI,rows=[];\n{s}\nif(rows.length!==5||JSON.stringify(rows)!==JSON.stringify(jsonSource.rows.slice(28)))throw Error(JSON.stringify({{actual:rows,expected:jsonSource.rows.slice(28)}}));export const done=true;", .{input[start..end]});
    defer std.testing.allocator.free(script);
    const dynamic = engine.evalModule(script, "native-ai-json-b06-original5.mjs") catch |err| {
        std.debug.print("JSON b06 dynamic: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(dynamic);
    try std.testing.expectEqual(@as(usize, 0), engine.native_json_diagnostic_depth);
    c.JS_RunGC(engine.runtime);
}
test "native AI JSON genuine b06 delegates observe intrinsic diagnostics and preserve caller and reviver error identity" {
    const input = @embedFile("extensions/fixtures/ai-json-delegate-b06.input.txt");
    try identity(input, "ce2e79b7714eca7206ede9fb193310369eb660affa4a0c7a5a655bd4b6334fce");
    const start = std.mem.indexOfScalar(u8, input, '\n').? + 1;
    const end = std.mem.indexOf(u8, input, "export default rows;").?;
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    try source(engine, "jsonDelegateSource", @embedFile("extensions/fixtures/ai-json-delegate-b06.json"));
    const script = try std.fmt.allocPrint(std.testing.allocator, "const api=aiJSONAPI;\n{s}\nif(jsonDelegateSource.sourceHead!=='b06c1f2cf1dea6af8748ddeee18c23587d2cb7c6'||rows.length!==6||JSON.stringify(rows)!==JSON.stringify(jsonDelegateSource.rows))throw Error(JSON.stringify({{actual:rows,expected:jsonDelegateSource.rows}}));export const done=true;", .{input[start..end]});
    defer std.testing.allocator.free(script);
    const result = engine.evalModule(script, "native-ai-json-b06-original-delegate6.mjs") catch |err| {
        std.debug.print("JSON b06 delegates: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    try std.testing.expectEqual(@as(usize, 0), engine.native_json_diagnostic_depth);
    c.JS_RunGC(engine.runtime);
}
test "native AI JSON private hooks restore prior owner callback across nested scopes and retain roots after GC" {
    const Sentinel = struct {
        var calls: usize = 0;
        fn callback(ctx: ?*c.JSContext, _: c.JSValue, error_value: c.JSValue) callconv(.c) c.JSValue {
            calls += 1;
            return c.JS_DupValue(ctx, error_value);
        }
    };
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    Sentinel.calls = 0;
    const previous = c.JS_PiSetJSONParseErrorHook(engine.context, Sentinel.callback);
    defer _ = c.JS_PiSetJSONParseErrorHook(engine.context, previous);
    try install(engine);
    const prepared = try engine.evalModule("globalThis.keptJSON=aiJSONAPI;delete globalThis.aiJSONAPI;export const done=true;", "native-ai-json-retain.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const result = try engine.evalModule(
        \\const intrinsic=JSON.parse;function raw(){try{intrinsic('{')}catch(error){return error.message}}const before=raw();
        \\for(const name of ['repairJson','parseJsonWithRepair','parseToolCallArguments']){const fn=keptJSON[name];if(fn.name!==name||fn.length!==1||!Object.hasOwn(fn,'prototype'))throw Error('function shape');}
        \\function wrapped(text){JSON.parse=intrinsic;try{if(!keptJSON.parseToolCallArguments('[]').argumentsError)throw Error('nested shape')}finally{JSON.parse=wrapped}return Reflect.apply(intrinsic,this,[text]);}
        \\JSON.parse=wrapped;try{const result=keptJSON.parseToolCallArguments('{"bad":.5}');if(!result.argumentsError.startsWith("Unexpected token '.'"))throw Error('nested intrinsic diagnostic')}finally{JSON.parse=intrinsic}
        \\if(before!==raw()||JSON.parse!==intrinsic)throw Error('global parser identity/behavior changed');let coercions=0;const input={length:0,trim(){return 'nonempty'},toString(){coercions++;return '{"bad":.5}'}};if(!keptJSON.parseToolCallArguments(input).argumentsError||coercions!==2)throw Error('one intrinsic coercion plus original template coercion');delete globalThis.keptJSON;export const done=true;
    , "native-ai-json-nested-scope.mjs");
    engine.freeValue(result);
    try std.testing.expectEqual(@as(usize, 2), Sentinel.calls);
    try std.testing.expectEqual(@as(usize, 0), engine.native_json_diagnostic_depth);
    c.JS_RunGC(engine.runtime);
}
test "native AI JSON ordinary no-hook parse retains single coercion reviver behavior and native error identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try std.testing.expect(c.JS_PiSetJSONParseErrorHook(engine.context, null) == null);
    const result = try engine.evalModule(
        \\const events=[],input={toString(){events.push('coerce');return '{"number":3,"array":[true,null,"wide 😀"]}'}};const result=JSON.parse(input,function(key,value){events.push(key);return key==='number'?value+1:value});if(result.number!==4||result.array[2]!=='wide 😀'||JSON.stringify(events)!==JSON.stringify(['coerce','number','0','1','2','array','']))throw Error('ordinary parse/reviver or coercion');
        \\const sentinel={owned:true};let seen;try{JSON.parse('{}',()=>{throw sentinel})}catch(error){seen=error}if(seen!==sentinel)throw Error('ordinary reviver identity');let coercions=0;try{JSON.parse({toString(){coercions++;throw sentinel}})}catch(error){seen=error}if(seen!==sentinel||coercions!==1)throw Error('ordinary coercion identity');let syntax;try{JSON.parse('{')}catch(error){syntax=error}if(!(syntax instanceof SyntaxError))throw Error('ordinary syntax subtype');export const done=true;
    , "native-ai-json-ordinary-no-hook.mjs");
    engine.freeValue(result);
    try std.testing.expectEqual(@as(usize, 0), engine.native_json_diagnostic_depth);
    try std.testing.expect(c.JS_PiSetJSONParseErrorHook(engine.context, null) == null);
}
test "native AI JSON every host allocation preserves intrinsic parser hook ownership and trusted OOM origin" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const api=aiJSONAPI,slash=String.fromCharCode(92),bad='{"value":"a'+slash+'q"}',fixed='{"value":"a'+slash+slash+'q"}';if(api.repairJson(bad)!==fixed)throw Error('repair');if(api.parseJsonWithRepair(bad).value!=='a'+slash+'q')throw Error('repaired parse');if(api.parseToolCallArguments('{"ok":1,"cutoff":').argumentsError!=='Unexpected end of JSON input\n\nReceived arguments:\n{"ok":1,"cutoff":')throw Error('final malformed');const intrinsic=JSON.parse;JSON.parse=new Proxy(intrinsic,{apply(target,receiver,args){return Reflect.apply(target,receiver,args)}});try{if(!api.parseToolCallArguments('{"bad":.5}').argumentsError.startsWith("Unexpected token '.'"))throw Error('delegated syntax')}finally{JSON.parse=intrinsic}export const done=true;
            , "native-ai-json-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            if (engine.native_json_diagnostic_depth != 0) return error.JSONDiagnosticScopeLeak;
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
