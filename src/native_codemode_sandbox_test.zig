const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
test "native CodeMode sandbox respects the actual original host stringify override in execute and controlled delivery" {
    const engine = try prepare();
    defer engine.deinit();
    const data = @embedFile("mcp/fixtures/codemode-json-override-148622-source.json");
    const fixture = try engine.checked(c.JS_ParseJSON(engine.context, data, data.len, "original-json-override.json"));
    defer engine.freeValue(fixture);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "originalOverride", c.JS_DupValue(engine.context, fixture)) < 0) return error.JavaScriptException;
    const value = engine.evalModule(
        \\import{CodemodeSandbox}from'@earendil-works/pi-codemode';
        \\const mismatches=[];let tested=0;
        \\for(const row of originalOverride.rows){
        \\ const effects=[],original=JSON.stringify,box=new CodemodeSandbox({tools:[{name:'echo',execute(){return{n:7}}}]});let run,result;
        \\ const begin=Date.now();try{
        \\  JSON.stringify=function(value,...args){effects.push([this===JSON,typeof value,value?.n]);return original.call(this,value?.n===7?{intercepted:7}:value,...args)};
        \\  result=row.mode==='execute'?await box.execute('return await tools.echo(1)'):await(run=box.start('return await tools.echo(1)',{startedAt:0,seed:1,tools:[{name:'echo'}],onCall(call){run.deliver(1,1,call.id,{ok:true,value:{n:7}})}})).result;
        \\ }finally{JSON.stringify=original;await box.close()}
        \\ const elapsed=Date.now()-begin;
        \\ function canonical(value,max){const copy=JSON.parse(JSON.stringify(value));for(const call of copy.calls){if(!Number.isFinite(call.durationMs)||call.durationMs<0||call.durationMs>max+1)throw Error('call duration');call.durationMs=0}return copy}
        \\ const actual={result:canonical(result,elapsed),effects},expected={result:canonical(row.result,row.elapsedMs),effects:row.effects};
        \\ if(JSON.stringify(actual)!==JSON.stringify(expected))mismatches.push({mode:row.mode,actual,expected});tested++;
        \\}if(tested!==2)throw Error('original override record count');if(mismatches.length)throw Error('host stringify differs '+JSON.stringify(mismatches));
    , "native-original-json-override.mjs") catch |err| {
        std.debug.print("host stringify original: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(value);
}
test "native CodeMode sandbox VM environment matches six original worker engine observations" {
    const engine = try prepare();
    defer engine.deinit();
    const data = @embedFile("mcp/fixtures/codemode-vm-environment-148622-source.json");
    const fixture = try engine.checked(c.JS_ParseJSON(engine.context, data, data.len, "original-vm-environment.json"));
    defer engine.freeValue(fixture);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "originalEnvironment", c.JS_DupValue(engine.context, fixture)) < 0) return error.JavaScriptException;
    const result = engine.evalModule(
        \\import{CodemodeSandbox}from'@earendil-works/pi-codemode';
        \\const mismatches=[];let tested=0;
        \\for(const row of originalEnvironment.rows){
        \\ if(row.name==='ordinary-local-clock')continue;
        \\ const box=new CodemodeSandbox({memoryLimitBytes:67108864});
        \\ let observed;try{observed=await box.execute(row.code)}finally{await box.close()}
        \\ if(JSON.stringify(observed)!==JSON.stringify(row.result))mismatches.push({name:row.name,observed,expected:row.result});tested++;
        \\}
        \\if(tested!==6)throw Error('original VM record count');
        \\if(mismatches.length)throw Error('VM environment differs '+JSON.stringify(mismatches));
    , "native-sandbox-original-environment.mjs") catch |err| {
        std.debug.print("original VM environment: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(result);
}
test "native CodeMode sandbox constructor matches twenty actual upstream registration and validation observations" {
    const engine = try prepare();
    defer engine.deinit();
    const a = std.testing.allocator;
    const source = @embedFile("mcp/fixtures/codemode-construct-148622-source.txt");
    const imports = try std.mem.replaceOwned(u8, a, source, "file:///C:/Users/adyba/pi-upstream-runtime-148622bc-20261012/packages/codemode/dist/runtime/host.js", "@earendil-works/pi-codemode");
    defer a.free(imports);
    const bound = try std.mem.replaceOwned(u8, a, imports, "console.log(JSON.stringify({upstream:'148622bc6f8d0ffd64e33cbc0e1e66754f45d32c',rows},null,2));", "export const observations=rows;");
    defer a.free(bound);
    const module = engine.evalModule(bound, "native-codemode-original-constructor.mjs") catch |err| {
        std.debug.print("constructor cases: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(module);
    const observations = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "observations"));
    defer engine.freeValue(observations);
    const actual = try engine.checked(c.JS_JSONStringify(engine.context, observations, c.pi_js_undefined(), c.pi_js_undefined()));
    defer engine.freeValue(actual);
    const actual_text = try engine.toString(actual);
    defer a.free(actual_text);
    const json = @import("mcp/protocol.zig").json;
    var fixture = try json.Owned.parse(a, @embedFile("mcp/fixtures/codemode-construct-148622-source.json"));
    defer fixture.deinit();
    try std.testing.expectEqual(@as(usize, 20), fixture.value.object.get("rows").?.array.items.len);
    const expected = try json.stringify(a, fixture.value.object.get("rows").?);
    defer a.free(expected);
    var observed = try json.Owned.parse(a, actual_text);
    defer observed.deinit();
    const comparable = try json.stringify(a, observed.value);
    defer a.free(comparable);
    try std.testing.expectEqualStrings(expected, comparable);
}
fn nodeStringify(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_PiJSONStringifyNode(context, if (argc > 0) argv[0] else c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined());
}

test "native CodeMode sandbox host JSON diagnostics match twelve actual Node cycle observations without repeated getters" {
    try compareNodeSerialization(@embedFile("mcp/fixtures/node-json-cycle-source-20261012.txt"), @embedFile("mcp/fixtures/node-json-cycle-source-20261012.json"), 12);
}
test "native CodeMode sandbox host JSON matches five actual Unicode NUL and BigInt observations" {
    try compareNodeSerialization(@embedFile("mcp/fixtures/node-json-extra-source-20261012.txt"), @embedFile("mcp/fixtures/node-json-extra-source-20261012.json"), 5);
}
fn compareNodeSerialization(source: []const u8, expected: []const u8, count: usize) !void {
    const engine = try prepare();
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const stringify = try engine.checked(c.JS_NewCFunction(engine.context, nodeStringify, "nodeJSONStringify", 1));
    if (c.JS_SetPropertyStr(engine.context, root, "nodeJSONStringify", stringify) < 0) return error.JavaScriptException;
    const a = std.testing.allocator;
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, source, "JSON.stringify(value)"));
    const call_bound = try std.mem.replaceOwned(u8, a, source, "JSON.stringify(value)", "nodeJSONStringify(value)");
    defer a.free(call_bound);
    const bound = try std.mem.replaceOwned(u8, a, call_bound, "console.log(JSON.stringify({node:process.versions.node,rows},null,2));", "export const observations=rows;");
    defer a.free(bound);
    const module = engine.evalModule(bound, "native-node-json-original-cases.mjs") catch |err| {
        std.debug.print("host JSON cases: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(module);
    const observations = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "observations"));
    defer engine.freeValue(observations);
    const actual = try engine.checked(c.JS_JSONStringify(engine.context, observations, c.pi_js_undefined(), c.pi_js_undefined()));
    defer engine.freeValue(actual);
    const actual_text = try engine.toString(actual);
    defer a.free(actual_text);
    const json = @import("mcp/protocol.zig").json;
    var fixture = try json.Owned.parse(a, expected);
    defer fixture.deinit();
    try std.testing.expectEqual(count, fixture.value.object.get("rows").?.array.items.len);
    const expected_text = try json.stringify(a, fixture.value.object.get("rows").?);
    defer a.free(expected_text);
    var actual_value = try json.Owned.parse(a, actual_text);
    defer actual_value.deinit();
    const canonical_actual = try json.stringify(a, actual_value.value);
    defer a.free(canonical_actual);
    try std.testing.expectEqualStrings(expected_text, canonical_actual);
}
fn prepare() !*em.Engine {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    errdefer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(exports);
    try @import("extensions/native_codemode_sandbox.zig").install(engine, exports);
    try engine.registerValueModule("@earendil-works/pi-codemode", exports);
    engine.host_await_deadline_ms = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() + 10000;
    return engine;
}

test "native CodeMode sandbox ordinary execution matches five original default-worker observations" {
    const engine = try prepare();
    defer engine.deinit();
    const fixture = try engine.checked(c.JS_ParseJSON(engine.context, @embedFile("mcp/fixtures/codemode-sandbox-148622-ordinary-worker-source.json"), @embedFile("mcp/fixtures/codemode-sandbox-148622-ordinary-worker-source.json").len, "original-worker.json"));
    defer engine.freeValue(fixture);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "originalSandbox", c.JS_DupValue(engine.context, fixture)) < 0) return error.JavaScriptException;
    const value = engine.evalModule(
        \\import{CodemodeSandbox}from'@earendil-works/pi-codemode';
        \\const mismatches=[];let tested=0;
        \\for(const row of originalSandbox.rows){
        \\ // The retained sixth observation has host-timezone-dependent values;
        \\ // this test qualifies the five environment-independent records only.
        \\ if(row.mode==='clock')continue;
        \\ const events=[],signals=[];
        \\ const echo={name:'echo',description:'echo original',execute(args,ctx){events.push([this===echo,ctx.signal instanceof AbortSignal,ctx.signal.aborted,Object.keys(ctx),args]);signals.push(ctx.signal);if(row.mode==='throw')throw Error('actual tool failure');if(row.mode==='cycle'){const value={};value.self=value;return value}return args}};
        \\ const box=new CodemodeSandbox({interruptBudget:50000,memoryLimitBytes:67108864,tools:[echo],globals:[{name:'math.add',spread:true,execute(args,ctx){events.push(['global',args,ctx.signal.aborted]);signals.push(ctx.signal);return args[0]+args[1]}}]});
        \\ const begin=Date.now();const options=row.mode==='store'?{store:{x:7,toJSON(){return{wrong:99}}}}:{};
        \\ let result;try{result=await box.execute(row.code,options)}finally{await box.close()}
        \\ const elapsed=Date.now()-begin;
        \\ function canonical(observed,max){const copy=JSON.parse(JSON.stringify(observed));for(const call of copy.calls){if(!Number.isFinite(call.durationMs)||call.durationMs<0||call.durationMs>max+1)throw Error('invalid call duration '+JSON.stringify(call));call.durationMs=0}return copy}
        \\ const actual={result:canonical(result,elapsed),events,signalsAfter:signals.map(s=>s.aborted)};
        \\ const expected={result:canonical(row.result,row.elapsedMs),events:row.events,signalsAfter:row.signalsAfter};
        \\ if(JSON.stringify(actual)!==JSON.stringify(expected))mismatches.push({name:row.name,actual,expected});tested++;
        \\}
        \\if(tested!==5)throw Error('original record count');
        \\if(mismatches.length)throw Error('original default-worker mismatches '+JSON.stringify(mismatches));
        \\export const success=true;
    , "native-sandbox-original-worker.mjs") catch |err| {
        std.debug.print("original sandbox comparison: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(value);
    const success = try engine.checked(c.JS_GetPropertyStr(engine.context, value, "success"));
    defer engine.freeValue(success);
    try std.testing.expect(c.JS_ToBool(engine.context, success) != 0);
}
test "native CodeMode sandbox runs ordinary registered tools globals and output on owned worker VMs" {
    const engine = try prepare();
    defer engine.deinit();
    const value = try engine.evalModule(
        \\import{CodemodeSandbox}from'@earendil-works/pi-codemode';
        \\const seen=[];let toolSignal;
        \\const echo={name:'echo',execute(args,ctx){toolSignal=ctx.signal;seen.push([this===echo,ctx.signal instanceof AbortSignal,ctx.signal.aborted]);return args}};
        \\const box=new CodemodeSandbox({memoryLimitBytes:67108864,tools:[echo],globals:[{name:'math.add',spread:true,async execute(args,ctx){seen.push([Array.isArray(args),ctx.signal.aborted]);return args[0]+args[1]}}]});
        \\if(box.tools[0]!==echo||box.tools===box.tools||box.globals[0].name!=='math.add')throw Error('registration identity');
        \\const result=await box.execute('text("hello");return [await tools.echo({n:7}),await math.add(2,3),typeof WeakRef]');
        \\if(!result.ok||result.value[0].n!==7||result.value[1]!==5||result.value[2]!=='function'||result.during!==undefined||result.output[0].text!=='hello')throw Error('ordinary result '+JSON.stringify(result));
        \\if(JSON.stringify(seen)!=='[[true,true,false],[true,false]]'||toolSignal.aborted)throw Error('tool context');
        \\if(!box.unregisterTool('echo')||box.unregisterTool('echo')||box.tools.length!==0)throw Error('unregister');
        \\box.registerTool(echo);let duplicate;try{box.registerTool(echo)}catch(e){duplicate=e.message}if(duplicate!=='Tool "echo" is already registered')throw Error('duplicate');
        \\await box.close();export const success=true;
    , "native-sandbox-ordinary.mjs");
    defer engine.freeValue(value);
    const success = try engine.checked(c.JS_GetPropertyStr(engine.context, value, "success"));
    defer engine.freeValue(success);
    try std.testing.expect(c.JS_ToBool(engine.context, success) != 0);
}
test "native CodeMode sandbox close cancels pending tool signals synchronously and waits for VM release" {
    const engine = try prepare();
    defer engine.deinit();
    const value = try engine.evalModule(
        \\import{CodemodeSandbox}from'@earendil-works/pi-codemode';
        \\let entered,signal;const ready=new Promise(resolve=>entered=resolve);
        \\const box=new CodemodeSandbox({tools:[{name:'hang',execute(args,ctx){signal=ctx.signal;entered();return new Promise(resolve=>ctx.signal.addEventListener('abort',()=>resolve('late')))}}]});
        \\const execution=box.execute('await tools.hang(1);return "wrong"');await ready;
        \\const closing=box.close();if(!signal.aborted)throw Error('close must cancel pending call before returning');
        \\const result=await execution;await closing;if(result.ok||result.error.kind!=='aborted'||result.error.message!=='Sandbox closed'||result.calls[0].status!=='cancelled')throw Error('close outcome '+JSON.stringify(result));
        \\let rejected;try{await box.execute('return 1')}catch(e){rejected=e.message}if(rejected!=='Sandbox is closed')throw Error('closed execute');
        \\let thrown;try{box.start('return 1',{startedAt:0,seed:1,onCall(){}})}catch(e){thrown=e.message}if(thrown!=='Sandbox is closed')throw Error('closed start');
        \\export const success=true;
    , "native-sandbox-close.mjs");
    defer engine.freeValue(value);
    const success = try engine.checked(c.JS_GetPropertyStr(engine.context, value, "success"));
    defer engine.freeValue(success);
    try std.testing.expect(c.JS_ToBool(engine.context, success) != 0);
}
test "native CodeMode sandbox deadlines stop computing ordinary scripts through the host owner" {
    const engine = try prepare();
    defer engine.deinit();
    const value = try engine.evalModule(
        \\import{CodemodeSandbox}from'@earendil-works/pi-codemode';
        \\const box=new CodemodeSandbox();const result=await box.execute('while(true){}',{timeoutMs:25});
        \\if(result.ok||result.error.kind!=='timeout'||result.error.message!=='Execution timed out after 25 ms')throw Error('deadline '+JSON.stringify(result));
        \\await box.close();export const success=true;
    , "native-sandbox-deadline.mjs");
    defer engine.freeValue(value);
    const success = try engine.checked(c.JS_GetPropertyStr(engine.context, value, "success"));
    defer engine.freeValue(success);
    try std.testing.expect(c.JS_ToBool(engine.context, success) != 0);
}
