//! Source-bound controls for actual public extension guards and tool wrappers.
//! These are authored tests; native qualification requires its separate grant.
const std = @import("std");
const x = @import("extensions/native_sdk_catalog_values.zig");
const c = x.c;
const helpers = @import("extensions/native_sdk_public_extension_helpers.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
fn publish(o: *x.Ops, name: [*:0]const u8, value: c.JSValue) !void {
    const root = try o.own(c.JS_GetGlobalObject(o.s.engine.context));
    try o.put(root, name, value);
}
fn prepare(engine: *x.em.Engine) !void {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, prepareBody(&o));
}
fn prepareBody(o: *x.Ops) !void {
    const actual = try o.own(try helpers.create(o.s.engine));
    const source = try o.own(try o.s.engine.eval(@embedFile("extensions/fixtures/sdk-public-extension-helpers-c268-source.mjs"), "public-extension-helpers-source.js", c.JS_EVAL_TYPE_GLOBAL));
    const hooks = try o.own(try retirement.createNativeRetirementHooks(o.s.engine));
    try publish(o, "actualExtensionHelpers", actual);
    try publish(o, "sourceExtensionHelpers", source);
    try publish(o, "extensionRetirement", hooks);
}
fn run(engine: *x.em.Engine, source: []const u8) !void {
    const namespace = try engine.evalModule(source, "actual-public-extension-helpers-control.mjs");
    engine.freeValue(namespace);
}
fn read(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const root = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(root);
    return engine.checked(c.JS_GetPropertyStr(engine.context, root, name));
}
test "SDK public extension helpers actual namespace and ordinary function identities" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const first = try helpers.create(engine); defer engine.freeValue(first);
    const second = try helpers.create(engine); defer engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
    try run(engine,
        \\const expected={defineTool:1,isBashToolResult:1,isPowerShellToolResult:1,isReadToolResult:1,isEditToolResult:1,isWriteToolResult:1,isGrepToolResult:1,isFindToolResult:1,isLsToolResult:1,isToolCallEventType:2,wrapRegisteredTool:2,wrapRegisteredTools:2};
        \\for(const api of[sourceExtensionHelpers,actualExtensionHelpers]){
        \\if(Object.keys(api).sort().join()!==Object.keys(expected).sort().join())throw Error('actual helper export set');
        \\for(const[name,length]of Object.entries(expected)){const f=api[name];if(f.name!==name||f.length!==length||typeof f.prototype!=='object'||Object.getPrototypeOf(f)!==Function.prototype)throw Error('ordinary shape '+name)}
        \\const token={};if(api.defineTool(token)!==token||api.defineTool(17)!==17||api.defineTool()!==undefined)throw Error('defineTool identity');
        \\}
    );
}
test "SDK public extension helpers actual strict guards preserve live getters and identity" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    try run(engine,
        \\for(const api of[sourceExtensionHelpers,actualExtensionHelpers]){
        \\for(const[name,tool]of[['isBashToolResult','bash'],['isPowerShellToolResult','powershell'],['isReadToolResult','read'],['isEditToolResult','edit'],['isWriteToolResult','write'],['isGrepToolResult','grep'],['isFindToolResult','find'],['isLsToolResult','ls']]){
        \\let calls=0;const event={get toolName(){calls++;return tool}};if(api[name](event)!==true||calls!==1)throw Error('single live getter '+name);
        \\if(api[name]({toolName:{[Symbol.toPrimitive](){throw Error('guard coerced')}}})!==false)throw Error('strict guard');
        \\let caught;try{api[name](null)}catch(e){caught=e}if(!(caught instanceof TypeError))throw Error('ordinary property error');
        \\}
        \\for(const token of[{},Symbol('tool'),null,undefined,17,NaN]){const expected=token===token;if(api.isToolCallEventType(token,{toolName:token})!==expected)throw Error('strict event identity')}
        \\}
    );
}
test "SDK public extension helpers actual definition snapshots and live execution order" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    try run(engine,
        \\for(const api of[sourceExtensionHelpers,actualExtensionHelpers]){
        \\const log=[],fields=['name','label','description','parameters','outputSchema','constrainedSampling','prepareArguments','executionMode'],values=Object.fromEntries(fields.map(k=>[k,{field:k}]));
        \\const definition={};for(const field of fields)Object.defineProperty(definition,field,{configurable:true,get(){log.push(field);return values[field]}});
        \\const context={},params={},signal={},update={},result={then(){throw Error('ordinary execute adopted')}};
        \\let executeCall;Object.defineProperty(definition,'execute',{configurable:true,get(){log.push('execute');return function(...args){log.push('call');executeCall=[this,args];return result}}});
        \\const runner={get createToolContext(){log.push('context');return function(id,s){if(this!==runner||id!=='id'||s!==signal)throw Error('real context receiver');return context}}};
        \\const registered={get definition(){log.push('definition');return definition}},wrapped=api.wrapRegisteredTool(registered,runner);
        \\if(log.join()!==['definition',...fields].join())throw Error('definition snapshot order '+log);log.length=0;
        \\for(const field of fields)if(wrapped[field]!==values[field])throw Error('snapshot identity');
        \\if(wrapped.execute.name!=='execute'||wrapped.execute.length!==5||'prototype'in wrapped.execute)throw Error('ordinary arrow shape');
        \\if(wrapped.execute('id',params,signal,update)!==result||log.join()!=='execute,context,call')throw Error('execute order '+log);
        \\if(executeCall[0]!==definition||executeCall[1].length!==5||executeCall[1][4]!==context)throw Error('definition receiver and context');
        \\log.length=0;const supplied={};if(wrapped.execute('id',params,signal,update,supplied,17)!==result||log.join()!=='execute,call'||executeCall[1][4]!==supplied)throw Error('supplied context');
        \\let next=0;Object.defineProperty(definition,'execute',{value(){next++;return 9}});if(wrapped.execute('id',params,signal,update)!==9||next!==1)throw Error('live execute binding');
        \\}
    );
}
test "SDK public extension helpers actual map receiver sparse arrays and callback contract" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    try run(engine,
        \\for(const api of[sourceExtensionHelpers,actualExtensionHelpers]){
        \\const definition={name:'actual',execute(){return 17}},registered={definition},runner={createToolContext(){return{}}};
        \\const sparse=[];sparse[2]=registered;const out=api.wrapRegisteredTools(sparse,runner);if(out.length!==3||0 in out||1 in out||out[2].name!=='actual')throw Error('real map holes');
        \\const result={},log=[];let saved;const object={get map(){log.push('get');return function(callback){log.push('call');if(this!==object||arguments.length!==1||callback.name!==''||callback.length!==1||'prototype'in callback)throw Error('map callback');saved=callback;return result}}};
        \\if(api.wrapRegisteredTools(object,runner)!==result||log.join()!=='get,call'||saved(registered).name!=='actual')throw Error('live map receiver');
        \\}
    );
}
test "SDK public extension helpers actual guard result retirement precedes caller continuation" {
    inline for (.{false, true}) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
        const source = try std.mem.concat(engine.gpa, u8, &.{
            "const api=", if (native) "actualExtensionHelpers" else "sourceExtensionHelpers",
            ";const event={get toolName(){return extensionRetirement.make(0)}};if(api.isBashToolResult(event)!==false||extensionRetirement.count(0)!==1)throw Error('guard result retained');",
        }); defer engine.gpa.free(source); try run(engine, source);
    }
}
test "SDK public extension helpers actual context callee retires before definition execution" {
    inline for (.{false, true}) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
        const source = try std.mem.concat(engine.gpa, u8, &.{
            "const api=", if (native) "actualExtensionHelpers" else "sourceExtensionHelpers",
            ";const h=extensionRetirement,context={},runner={get createToolContext(){const f=()=>context;f.carrier=h.make(0);return f}};",
            "const definition={execute(id,params,signal,update,ctx){if(h.count(0)!==1||ctx!==context)throw Error('context callee retained');return 23}};",
            "if(api.wrapRegisteredTool({definition},runner).execute()!==23)throw Error('actual wrapper call');",
        }); defer engine.gpa.free(source); try run(engine, source);
    }
}
test "SDK public extension helpers SAME getter DATA stays ordinary and actual B1 wins" {
    inline for (.{false, true}) |fatal| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
        const hooks = try read(engine, "extensionRetirement"); defer engine.freeValue(hooks);
        const record = try engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record")); defer engine.freeValue(record);
        const source = try std.mem.concat(engine.gpa, u8, &.{
            "globalThis.extensionData=undefined;globalThis.extensionCaught=undefined;const h=extensionRetirement;const event={get toolName(){extensionData=h.freshPrivateData();",
            if (fatal) "h.raiseNativeFatal();" else "",
            "throw extensionData}};try{actualExtensionHelpers.isBashToolResult(event)}catch(error){extensionCaught=error;h.record.guestReached=true}",
        }); defer engine.gpa.free(source);
        if (fatal) {
            try std.testing.expectError(error.JavaScriptException, run(engine, source));
            try retirement.verifyRecordedActualNativeFatal(engine, record);
        } else {
            try run(engine, source);
            const data = try read(engine, "extensionData"); defer engine.freeValue(data);
            const caught = try read(engine, "extensionCaught"); defer engine.freeValue(caught);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, data, caught));
            try std.testing.expect(!c.JS_IsUncatchableError(data));
            try std.testing.expect(c.pi_js_native_allocation_error_generation(data) != 0);
        }
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    }
}
test "SDK public extension helpers actual context callee retirement fatal preempts execute" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const hooks = try read(engine, "extensionRetirement"); defer engine.freeValue(hooks);
    const record = try engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record")); defer engine.freeValue(record);
    try std.testing.expectError(error.JavaScriptException, run(engine,
        \\const h=extensionRetirement,runner={get createToolContext(){const f=()=>({});f.carrier=h.make(0);return f}};
        \\const definition={execute(){h.visit(2);throw Error('downstream execute reached')}};
        \\const wrapped=actualExtensionHelpers.wrapRegisteredTool({definition},runner);h.armFatal(0);wrapped.execute();
    ));
    try retirement.verifyActualRetirementFatal(engine, record, 0);
}
