//! Prepared, unrun component controls; collaborators are explicit test inputs.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const helpers = @import("extensions/native_sdk_session_hook_helpers.zig");
const c = em.c;

fn nativeReason(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(context);
    const global = c.JS_GetGlobalObject(context);
    defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(context, global, "ownedHookFatalReason", c.JS_DupValue(context, reason), c.JS_PROP_C_W_E) < 0) {
        engine.freeValue(reason);
        return c.JS_Throw(context, c.JS_GetException(context));
    }
    return reason;
}
fn throwReason(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const reason = nativeReason(context, receiver, argc, args);
    return if (c.JS_IsException(reason)) reason else c.JS_Throw(context, reason);
}
fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const imports = try sdk.object(engine);
    defer engine.freeValue(imports);
    // A controlled normalizer is an explicit test dependency. This does not
    // qualify the production normalizer or replace it in the public graph.
    const normalizer = try engine.eval("(content,options)=>globalThis.ownedNormalize(content,options)", "owned-hook-normalizer-input.js", c.JS_EVAL_TYPE_GLOBAL);
    try sdk.put(engine, imports, "normalizeToolResultImages", normalizer);
    const methods = try sdk.object(engine);
    defer engine.freeValue(methods);
    inline for (std.meta.fields(helpers.Kind)) |field| try sdk.put(engine, methods, field.name, try helpers.create(engine, @enumFromInt(field.value), imports));
    try sdk.put(engine, global, "ownedHookMethods", c.JS_DupValue(engine.context, methods));
    inline for (.{ .{ "ownedMakeHookNativeReason", nativeReason }, .{ "ownedThrowHookNativeReason", throwReason } }) |entry| {
        try sdk.put(engine, global, entry[0], try engine.checked(c.JS_NewCFunction(engine.context, entry[1], entry[0], 0)));
    }
}
fn run(program: []const u8) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const module = try engine.evalModule(program, "owned-hook-helper-controls.mjs");
    engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
}
fn fatal(program: []const u8) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    if (engine.evalModule(program, "owned-hook-helper-fatal-identity.mjs")) |module| {
        engine.freeValue(module);
        return error.RequiredExactFatalHookReason;
    } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const retained = try sdk.get(engine, global, "ownedHookFatalReason");
    defer engine.freeValue(retained);
    const captured = engine.captured_exception orelse return error.RequiredCapturedHookReason;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, retained, captured));
    try std.testing.expect(c.JS_IsUncatchableError(captured));
}

test "native hook helper after no handler starts normalization before its first real await" {
    try run(
        \\const calls=[],content=[];globalThis.ownedNormalize=(value,options)=>{calls.push('normalize');if(value!==content||options.autoResizeImages!==true)throw Error('normalizer input');return Promise.resolve(value)};
        \\const receiver={_extensionRunner:{hasHandlers(){calls.push('handlers');return false}},_limitsModel(){calls.push('limits');return undefined},settingsManager:{getImageAutoResize(){calls.push('settings');return true}}};
        \\const pending=ownedHookMethods._afterToolCall.call(receiver,{toolCall:{},args:{},result:{content},isError:false});calls.push('returned');
        \\if(calls.join(',')!=='handlers,limits,settings,normalize,returned')throw Error('extra hook await on no-handler path: '+calls);if(await pending!==undefined)throw Error('identity normalization result');
    );
}

test "native hook helper preserves callee getter and repeated structured content order" {
    try run(
        \\const calls=[],raw={raw:true},toolCall={get name(){calls.push('name');return'tool'},get id(){calls.push('id');return'call'}},runner={hasHandlers(){calls.push('handlers');return true},get emitToolCall(){calls.push('get-emit');return function(event){calls.push(this===runner?'emit':'wrong-this');throw raw}}};
        \\let blocked;try{await ownedHookMethods._beforeToolCall.call({_extensionRunner:runner},{toolCall,args:{}})}catch(error){blocked=error}if(blocked?.message!=='Extension failed, blocking execution: [object Object]')throw Error('before raw failure was not wrapped');
        \\if(calls.join(',')!=='handlers,get-emit,name,id,emit')throw Error('before callee order: '+calls);
        \\let parameterFailure;try{await ownedHookMethods._beforeToolCall.call({_extensionRunner:runner},{get toolCall(){throw raw}})}catch(error){parameterFailure=error}if(parameterFailure!==raw)throw Error('parameter failure entered Source catch');
        \\calls.length=0;let reads=0;const content=[],result={content,details:{},get structuredContent(){reads++;return{read:reads}}};globalThis.ownedNormalize=value=>Promise.resolve(value);
        \\const after={_extensionRunner:{hasHandlers(){return true},get emitToolResult(){calls.push('get-emit');return event=>{calls.push(event.structuredContent.read);return undefined}}},_limitsModel(){return undefined},settingsManager:{getImageAutoResize(){return false}}};
        \\await ownedHookMethods._afterToolCall.call(after,{toolCall:{},args:{},result,isError:false});if(reads!==2||calls.join(',')!=='get-emit,2')throw Error('structured content getter order');
    );
}

test "native hook helper compact awaits only the selected compaction and reprojects afterward" {
    try run(
        \\const calls=[],before=[{role:'user'}],after=[{role:'assistant'}];let compacted=false;
        \\const receiver={model:{api:'fixture'},sessionManager:{buildSessionProjection(){calls.push('projection');return{messages:compacted?after:before}}},_exceedsCompactionThreshold(){calls.push('threshold');return true},async _runAutoCompaction(reason,retry){calls.push(['compact',reason,retry]);await Promise.resolve();compacted=true}};
        \\const context={tools:[]},pending=ownedHookMethods._compactBeforeNextAssistantResponse.call(receiver,context);calls.push('returned');const value=await pending;
        \\if(value.messages!==after||value.tools!==context.tools||value===context||calls[0]!=='projection'||calls[1]!=='threshold'||calls[3]!=='returned'||calls[4]!=='projection')throw Error('compaction await/reprojection');
        \\receiver.model=undefined;compacted=false;calls.length=0;const early=await ownedHookMethods._compactBeforeNextAssistantResponse.call(receiver,context);if(early.messages!==before||calls.join(',')!=='projection')throw Error('early compaction path');
    );
}

test "native hook helper boundary preserves flatMap override and live continuation getters" {
    try run(
        \\const calls=[],message={get stopReason(){calls.push('stop');return'stop'}},result={result:true},entries=[],toolResults={get flatMap(){calls.push('get-flatMap');return function(mapper){calls.push(this===toolResults?'flatMap':'wrong-this');return mapper(result)}}};let continueReads=0;
        \\const boundary={get entries(){calls.push('entries');return entries},get continue(){calls.push('continue');return ++continueReads===1?false:'second-value'}};
        \\const receiver={_turnIndex:7,_findPersistedMessageEntryId(value){calls.push(value===message?'message-id':'result-id');return value===message?'message-entry':'result-entry'},_extensionRunner:{hasHandlers(){calls.push('handlers');return true},get emitBoundary(){calls.push('get-emit');return async function(event,build){calls.push(event.toolResultEntryIds[0]);if(event.outcome!=='completed'||event.toolResults!==toolResults)throw Error('event');build([]);return boundary}}},_buildBoundaryContext(){calls.push('build');return{canContinue:true}},get _commitBoundaryDrafts(){calls.push('get-commit');return value=>{calls.push('commit');if(value!==entries)throw Error('entries')}}};
        \\const value=await ownedHookMethods._dispatchTurnEndBoundary.call(receiver,message,toolResults);
        \\if(value!=='second-value'||calls.slice(0,9).join(',')!=='stop,stop,message-id,handlers,get-flatMap,flatMap,result-id,get-emit,result-entry'||calls.indexOf('get-commit')>calls.indexOf('entries')||continueReads!==2)throw Error('boundary order: '+calls);
    );
}

test "native hook helper Source catch and resumed rejection retain exact fatal native reason" {
    try fatal(
        \\await ownedHookMethods._beforeToolCall.call({_extensionRunner:{hasHandlers(){return true},emitToolCall:ownedThrowHookNativeReason}},{toolCall:{name:'tool',id:'call'},args:{}});
    );
    try fatal(
        \\await ownedHookMethods._beforeToolCall.call({_extensionRunner:{hasHandlers(){return true},emitToolCall(){return Promise.reject(ownedMakeHookNativeReason())}}},{toolCall:{name:'tool',id:'call'},args:{}});
    );
    try fatal(
        \\globalThis.String=ownedThrowHookNativeReason;await ownedHookMethods._beforeToolCall.call({_extensionRunner:{hasHandlers(){return true},emitToolCall(){throw {ordinaryPrimary:true}}}},{toolCall:{name:'tool',id:'call'},args:{}});
    );
}
