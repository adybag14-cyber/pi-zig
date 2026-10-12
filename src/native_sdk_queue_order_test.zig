const std = @import("std");
const em = @import("extensions/engine.zig");
const group_mod = @import("extensions/native_group.zig");
const json = @import("mcp/protocol.zig").json;
const host = @import("builtin");

// Original Source567 was captured on C:. Source598 repeated the unchanged
// corpus on actual C: and D: working directories: only these six absolute
// cwd strings change; all four cwd identity comparisons remain false.
// Bind that observed Source drive parameter before comparing whole rows.
fn sourceFixture(comptime windows: []const u8, comptime posix: []const u8, comptime stem: []const u8, comptime count: usize) ![]u8 {
    const original = @embedFile(windows);
    if (host.os.tag != .windows) return std.testing.allocator.dupe(u8, @embedFile(posix));
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const directory = try std.Io.Dir.cwd().openDir(std.testing.io, ".", .{});
    defer directory.close(std.testing.io);
    const length = try directory.realPath(std.testing.io, &buffer);
    const drive = std.fs.path.diskDesignatorWindows(buffer[0..length]);
    try std.testing.expectEqual(@as(usize, 2), drive.len);
    const needle = "C:\\\\" ++ stem;
    try std.testing.expectEqual(count, std.mem.count(u8, original, needle));
    const bound = try std.fmt.allocPrint(std.testing.allocator, "{s}\\\\{s}", .{ drive, stem });
    defer std.testing.allocator.free(bound);
    return std.mem.replaceOwned(u8, std.testing.allocator, original, needle, bound);
}
test "native SDK queue order FACTORY all eleven actual current Source588 auth traces retain preflight lookup order and raw identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{ "pi-sdk-auth", "sdk-auth-current-588.mjs" });
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-auth-current-588-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-auth-preflight-589.input.txt"), "sdk-auth-current-588.mjs") catch |err| {
        std.debug.print("SDK actual Source588 auth: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkAuthPreflightRows", "sdk-auth-current-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, if (host.os.tag == .windows) @embedFile("extensions/fixtures/sdk-auth-preflight-source-571.json") else @embedFile("extensions/fixtures/sdk-auth-preflight-source-599-posix.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 11), rows.len);
    try std.testing.expectEqual(rows.len, actual.value.array.items.len);
    for (rows, actual.value.array.items) |source, observed| {
        if (!json.equal(source, observed)) std.debug.print("SDK Source588 auth complete actual={s}\n", .{raw});
        try std.testing.expect(json.equal(source, observed));
    }
    const cleared = try engine.eval("delete globalThis.sdkAuthPreflightRows", "sdk-auth-current-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}
test "native SDK queue order FACTORY actual Source567 eleven shared runner runtime binding and disposal cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-factory-runner-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-factory-runner-568.input.txt"), "sdk-factory-runner.mjs") catch |err| {
        std.debug.print("SDK Source567 factory: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkFactoryRunnerRows", "sdk-factory-runner-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    const fixture = try sourceFixture("extensions/fixtures/sdk-factory-runner-source-567.json", "extensions/fixtures/sdk-factory-runner-source-596-posix.json", "sdk-owned-factory-566", 6);
    defer std.testing.allocator.free(fixture);
    var expected = try json.Owned.parse(std.testing.allocator, fixture);
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 11), rows.len);
    try std.testing.expectEqual(rows.len, actual.value.array.items.len);
    for (rows, actual.value.array.items) |source, observed| {
        if (!json.equal(source, observed)) std.debug.print("SDK Source567 factory complete actual={s}\n", .{raw});
        try std.testing.expect(json.equal(source, observed));
    }
    const cleared = try engine.eval("delete globalThis.sdkFactoryRunnerRows", "sdk-factory-runner-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}
fn sdkRuntimeSourceHelper(context: ?*em.c.JSContext, _: em.c.JSValue, argc: c_int, argv: [*c]em.c.JSValue, magic: c_int) callconv(.c) em.c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const sdk = @import("extensions/native_sdk.zig");
    if (magic == 0) return @import("extensions/native_sdk_extension_runtime.zig").create(engine, em.c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
    var args = [_]em.c.JSValue{ em.c.pi_js_undefined(), em.c.pi_js_undefined(), em.c.pi_js_undefined(), em.c.pi_js_undefined() };
    for (0..@min(args.len, @as(usize, @intCast(argc)))) |index| args[index] = argv[index];
    return @import("extensions/native_sdk_agent_state.zig").create(engine, args[0], args[1], args[2], args[3]) catch |err| sdk.fail(engine, err);
}
test "native SDK queue order PRIVATE loader runtime and MCP genuine production bodies match all nine actual Source569 rows" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-runtime-mcp-root");
    try root.installSchemas();
    const sdk = @import("extensions/native_sdk.zig");
    const js = @import("extensions/native_js_values.zig");
    const namespace = try sdk.object(engine);
    defer engine.freeValue(namespace);
    try sdk.put(engine, namespace, "createExtensionRuntime", try engine.checked(em.c.pi_js_function_magic(engine.context, sdkRuntimeSourceHelper, "createExtensionRuntime", 0, 0)));
    const registry = try @import("extensions/native_sdk_mcp_registry.zig").create(engine);
    defer engine.freeValue(registry);
    try sdk.put(engine, namespace, "McpServerRegistry", try js.get(engine, registry, "constructor"));
    const global = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "sdkRuntimeNative", em.c.JS_DupValue(engine.context, namespace));
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runtime-mcp-569.input.txt"), "sdk-runtime-mcp.mjs") catch |err| {
        std.debug.print("SDK Source569 runtime/MCP: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRuntimeMcpRows", "sdk-runtime-mcp-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runtime-mcp-agent-source-569.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 11), rows.len);
    try std.testing.expectEqual(@as(usize, 9), actual.value.array.items.len);
    for (rows[0..9], actual.value.array.items) |source, observed| {
        if (!json.equal(source, observed)) std.debug.print("SDK Source569 runtime/MCP complete actual={s}\n", .{raw});
        try std.testing.expect(json.equal(source, observed));
    }
    const cleared = try engine.eval("delete globalThis.sdkRuntimeMcpRows;delete globalThis.sdkRuntimeNative", "sdk-runtime-mcp-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}
test "native SDK queue order PRIVATE Agent state constructor fields and real shared default model match Source569 state observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-agent-state-root");
    try root.installSchemas();
    const sdk = @import("extensions/native_sdk.zig");
    const global = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "sdkCreateAgentState", try engine.checked(em.c.pi_js_function_magic(engine.context, sdkRuntimeSourceHelper, "createAgentState", 4, 1)));
    const result = engine.evalModule(
        \\const first=sdkCreateAgentState(undefined,undefined,[],[]),second=sdkCreateAgentState(undefined,undefined,[],[]),model={provider:'caller',id:'caller'},third=sdkCreateAgentState(model,'high',[],[]);
        \\const describe=value=>value===undefined?{type:'undefined'}:typeof value==='object'?{type:value instanceof Set?'Set':'object'}:{type:typeof value,value};
        \\const own=obj=>Reflect.ownKeys(obj).map(key=>{const d=Object.getOwnPropertyDescriptor(obj,key);return{name:String(key),value:describe(d.value),writable:d.writable,enumerable:d.enumerable,configurable:d.configurable}});
        \\globalThis.sdkAgentStateObserved={model:first.model,shared:first.model===second.model,explicit:third.model===model,defaultThinking:first.thinkingLevel,explicitThinking:third.thinkingLevel,ownState:own(first),messageKeys:first.messages.map(message=>Reflect.ownKeys(message).map(String))};
        \\first.model.id='changed singleton';globalThis.sdkAgentStateLive={secondId:second.model.id,explicitId:third.model.id};first.model.id='unknown';
    , "sdk-agent-state-constructor.mjs") catch |err| {
        std.debug.print("SDK Source569 Agent state: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(result);
    const observed = try engine.eval("[sdkAgentStateObserved,sdkAgentStateLive]", "sdk-agent-state-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(observed);
    const raw = try engine.stringify(observed);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runtime-mcp-agent-source-569.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    inline for (.{ "model", "shared", "explicit", "defaultThinking", "explicitThinking", "ownState", "messageKeys" }) |field| try std.testing.expect(json.equal(rows[9].object.get(field).?, actual.value.array.items[0].object.get(field).?));
    inline for (.{ "secondId", "explicitId" }) |field| try std.testing.expect(json.equal(rows[10].object.get(field).?, actual.value.array.items[1].object.get(field).?));
    // This exercises the real state helper used by the factory. The broader
    // public Agent class, its signal and prototype are not exported by this test.
    const cleared = try engine.eval("delete globalThis.sdkCreateAgentState;delete globalThis.sdkAgentStateObserved;delete globalThis.sdkAgentStateLive", "sdk-agent-state-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}
test "native SDK queue order PUBLIC constructor full thirteen actual Source564 newTarget fields and default callback cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-constructor-deep-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-constructor-deep-565.input.txt"), "sdk-constructor-deep.mjs") catch |err| {
        std.debug.print("SDK Source564 PUBLIC constructor: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkConstructorDeepRows", "sdk-constructor-deep-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-constructor-deep-source-564.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 13), rows.len);
    try std.testing.expectEqual(rows.len, actual.value.array.items.len);
    for (rows, actual.value.array.items) |source, observed| {
        const id = source.object.get("id").?.string;
        if (std.mem.eql(u8, id, "constructor-call") or std.mem.eql(u8, id, "default-arrow-new") or std.mem.eql(u8, id, "default-async-new")) {
            // Preserve the original V8 diagnostic text in the capture. The
            // engine-generated wording differs; error class and full row
            // structure remain strict, and both messages must be nonempty.
            try std.testing.expectEqual(@as(usize, 2), source.object.count());
            try std.testing.expectEqual(source.object.count(), observed.object.count());
            try std.testing.expect(json.equal(source.object.get("id").?, observed.object.get("id").?));
            const wanted = source.object.get("outcome").?;
            const found = observed.object.get("outcome").?;
            try std.testing.expectEqual(@as(usize, 2), wanted.object.count());
            try std.testing.expectEqual(wanted.object.count(), found.object.count());
            try std.testing.expect(json.equal(wanted.object.get("name").?, found.object.get("name").?));
            try std.testing.expect(wanted.object.get("message").? == .string and wanted.object.get("message").?.string.len > 0);
            try std.testing.expect(found.object.get("message").? == .string and found.object.get("message").?.string.len > 0);
        } else {
            if (!json.equal(source, observed)) std.debug.print("SDK Source564 constructor complete actual={s}\n", .{raw});
            try std.testing.expect(json.equal(source, observed));
        }
    }
    const cleared = try engine.eval("delete globalThis.sdkConstructorDeepRows", "sdk-constructor-deep-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}
test "native SDK queue order PUBLIC implemented method metadata matches complete original Source class declaration" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-method-metadata-root");
    try root.installSchemas();
    const global = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/sdk-runner-method-metadata-89e5-source.json");
    try @import("extensions/native_js_values.zig").define(engine, global, "sdkMethodSource", try engine.checked(em.c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-sdk-method-metadata-89e5")));
    const result = engine.evalModule(
        \\import{ExtensionRunner}from'@earendil-works/pi-coding-agent';
        \\const missing=[],asyncPrototype=Object.getPrototypeOf(async()=>{});let implemented=0,absent=0;
        \\if(sdkMethodSource.methods.length!==50)throw Error('Source method inventory');
        \\for(const expected of sdkMethodSource.methods){const descriptor=Object.getOwnPropertyDescriptor(ExtensionRunner.prototype,expected.name);
        \\ if(missing.includes(expected.name)){if(descriptor!==undefined)throw Error('unqualified method inventory changed');absent++;continue}
        \\ if(typeof descriptor?.value!=='function')throw Error('missing implemented method '+expected.name);const fn=descriptor.value;
        \\ const actual={name:fn.name,arity:fn.length,async:Object.getPrototypeOf(fn)===asyncPrototype,ownKeys:Reflect.ownKeys(fn).map(String),descriptor:{writable:descriptor.writable,enumerable:descriptor.enumerable,configurable:descriptor.configurable}};
        \\ if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({actual,expected}));implemented++;
        \\}
        \\if(implemented!==50||absent!==0)throw Error('partial native method inventory');
    , "sdk-method-metadata-native") catch |err| {
        std.debug.print("SDK method metadata: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}

fn exercise(gpa: std.mem.Allocator, comptime capture: []const u8) !void {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-queue-order-root");
    try root.installSchemas();
    const loaded = try engine.evalModule(@embedFile("extensions/fixtures/sdk-template-order-" ++ capture ++ ".input.txt"), "sdk-queue-order.mjs");
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkTemplateOrderResult", "sdk-queue-order-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer gpa.free(raw);
    var actual = try json.Owned.parse(gpa, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(gpa, @embedFile("extensions/fixtures/sdk-template-order-" ++ capture ++ ".json"));
    defer expected.deinit();
    const actual_rows = actual.value.object.get("rows") orelse return error.MissingSDKQueueOrderRows;
    const expected_rows = expected.value.object.get("rows") orelse return error.MissingSourceQueueOrderRows;
    if (!json.equal(expected_rows, actual_rows)) std.debug.print("SDK queue order Source{s} actual={s}\n", .{ capture, raw });
    try std.testing.expect(json.equal(expected_rows, actual_rows));
    em.c.JS_RunGC(engine.runtime);
}
test "native SDK queue order evaluates prompt getter spread find and argument pushes exactly as Source476" {
    try exercise(std.testing.allocator, "476");
}
test "native SDK queue order uses the immutable iterator even after replacement of the guest global Symbol" {
    try exercise(std.testing.allocator, "477");
}

test "native SDK queue order reads ordinary writable AgentSession fields from the actual receiver" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-session-public-fields-root");
    try root.installSchemas();
    const loaded = try engine.evalModule(
        \\import {ModelRuntime,DefaultResourceLoader,SessionManager,SettingsManager,createAgentSession} from '@earendil-works/pi-coding-agent';
        \\const runtime=await ModelRuntime.create({modelsPath:null,refreshOnCreate:false,credentials:{read:async()=>undefined,list:async()=>[]}});
        \\const cwd='/sdk-public-fields';const manager=SessionManager.inMemory(cwd),settings=SettingsManager.inMemory();
        \\const loader=new DefaultResourceLoader({cwd,agentDir:cwd+'/agent',noExtensions:true,noSkills:true,noThemes:true,noPromptTemplates:true,noContextFiles:true});await loader.reload();
        \\const {session}=await createAgentSession({cwd,modelRuntime:runtime,resourceLoader:loader,sessionManager:manager,settingsManager:settings,tools:[]});
        \\const prototype=Object.getPrototypeOf(session),getter=Object.getOwnPropertyDescriptor(prototype,'promptTemplates');if(Object.hasOwn(session,'promptTemplates')||!getter||getter.enumerable||!getter.configurable||getter.get.name!=='get promptTemplates')throw Error('prototype getter descriptor');
        \\if(Object.hasOwn(session,'steer')||Object.getOwnPropertyDescriptor(prototype,'steer').enumerable)throw Error('prototype method descriptor');
        \\const prompts=session.promptTemplates,marker=[];Object.defineProperty(session,'promptTemplates',{configurable:true,get(){return marker}});if(session.promptTemplates!==marker)throw Error('getter override');delete session.promptTemplates;if(session.promptTemplates!==prompts)throw Error('getter restoration');
        \\for(const name of ['agent','sessionManager','settingsManager']){const descriptor=Object.getOwnPropertyDescriptor(session,name);if(!descriptor||!('value'in descriptor)||!descriptor.writable||!descriptor.enumerable||!descriptor.configurable)throw Error('ordinary field '+name)}
        \\const previous=session.agent,trace=[];const replacement={state:{messages:[],model:{id:'replacement'},thinkingLevel:'low'},steeringMode:'all',steer(message){trace.push(['agent.steer',this===replacement,message.content[0].text])}};
        \\session.agent=replacement;if(session.state!==replacement.state||session.model!==replacement.state.model||session.messages!==replacement.state.messages||session.thinkingLevel!=='low')throw Error('agent field not read');
        \\const replacementSettings={setSteeringMode(mode){trace.push(['settings.setSteeringMode',this===replacementSettings,mode])}};session.settingsManager=replacementSettings;session.setSteeringMode('oneAtATime');
        \\const replacementManager={getSessionId(){trace.push(['manager.getSessionId',this===replacementManager]);return'replacement-id'}};session.sessionManager=replacementManager;if(session.sessionId!=='replacement-id')throw Error('manager field not read');
        \\await session.steer('ordinary');if(JSON.stringify(trace)!==JSON.stringify([['settings.setSteeringMode',true,'oneAtATime'],['manager.getSessionId',true],['agent.steer',true,'ordinary']]))throw Error('public field order '+JSON.stringify(trace));
        \\const descriptors=Object.fromEntries(['agent','sessionManager','settingsManager'].map(name=>{const d=Object.getOwnPropertyDescriptor(session,name);return[name,{valueField:'value'in d,writable:d.writable,enumerable:d.enumerable,configurable:d.configurable}]}));globalThis.sdkPublicFieldsResult={descriptors,trace};
        \\session.agent=previous;session.sessionManager=manager;session.settingsManager=settings;session.dispose();
    , "sdk-public-fields.mjs");
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkPublicFieldsResult", "sdk-public-fields-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-public-fields-source-486.json"));
    defer expected.deinit();
    inline for (.{ "descriptors", "trace" }) |field| try std.testing.expect(json.equal(expected.value.object.get(field).?, actual.value.object.get(field).?));
}

test "native SDK queue order rejects Source499 ordered duplicate command aliases and literal collisions" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-command-collision-root");
    try root.installSchemas();
    const loaded = try engine.evalModule(@embedFile("extensions/fixtures/sdk-command-collision-499.input.txt"), "sdk-command-collision.mjs");
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkCommandCollisionRows", "sdk-command-collision-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-command-collision-source-499.json"));
    defer expected.deinit();
    const expected_rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(expected_rows.len, actual.value.array.items.len);
    const sessions = try engine.eval("sdkCommandCollisionSessions", "sdk-command-collision-sessions.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(sessions);
    for (expected_rows, actual.value.array.items, 0..) |expected_row, actual_row, index| {
        inline for (.{ "id", "probes", "steering" }) |field| {
            if (!json.equal(expected_row.object.get(field).?, actual_row.object.get(field).?)) std.debug.print("SDK Source499 row{d} field{s} actual={s}\n", .{ index, field, raw });
            try std.testing.expect(json.equal(expected_row.object.get(field).?, actual_row.object.get(field).?));
        }
        const session = try engine.checked(em.c.JS_GetPropertyUint32(engine.context, sessions, @intCast(index)));
        defer engine.freeValue(session);
        const owner = try @import("extensions/native_sdk.zig").state(engine, session);
        const commands = try @import("extensions/native_sdk_commands.zig").resolve(owner);
        defer engine.freeValue(commands);
        const expected_commands = expected_row.object.get("commands").?.array.items;
        try std.testing.expectEqual(expected_commands.len, try @import("extensions/native_sdk.zig").length(engine, commands));
        for (expected_commands, 0..) |command, command_index| {
            const row = try engine.checked(em.c.JS_GetPropertyUint32(engine.context, commands, @intCast(command_index)));
            defer engine.freeValue(row);
            const name = try @import("extensions/native_sdk.zig").get(engine, row, "invocationName");
            defer engine.freeValue(name);
            const text = try engine.toString(name);
            defer std.testing.allocator.free(text);
            try std.testing.expectEqualStrings(command.object.get("invocationName").?.string, text);
        }
    }
    const disposed = try engine.eval("for(const session of sdkCommandCollisionSessions)session.dispose();delete globalThis.sdkCommandCollisionSessions;delete globalThis.sdkCommandCollisionRows", "sdk-command-collision-dispose.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(disposed);
    em.c.JS_RunGC(engine.runtime);
}

fn commandSourceBridge(context: ?*em.c.JSContext, _: em.c.JSValue, argc: c_int, args: [*c]em.c.JSValue, magic: c_int, _: [*c]em.c.JSValue) callconv(.c) em.c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return commandSourceBridgeValue(engine, if (argc > 0) args[0] else em.c.pi_js_undefined(), if (argc > 1) args[1] else em.c.pi_js_undefined(), magic) catch |err| @import("extensions/native_sdk.zig").fail(engine, err);
}
fn commandSourceBridgeValue(engine: *em.Engine, session: em.c.JSValue, extensions: em.c.JSValue, operation: c_int) !em.c.JSValue {
    const owner = try @import("extensions/native_sdk.zig").state(engine, session);
    if (operation == 0) return @import("extensions/native_sdk_commands.zig").resolve(owner);
    const rows = try @import("extensions/native_sdk_resource_owners.zig").sessionExtensionRows(engine, owner.data);
    defer engine.freeValue(rows);
    return em.c.pi_js_bool(engine.context, @intFromBool(em.c.JS_IsStrictEqual(engine.context, rows, extensions)));
}
test "native SDK queue order actual command Maps snapshots complete rows and mutable builtin traces match Source501" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-command-rows-root");
    try root.installSchemas();
    const global = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    inline for (.{ "nativeSDKResolveCommands", "nativeSDKSameCommandRows" }, 0..) |name, operation| {
        const callback = try engine.checked(em.c.JS_NewCFunctionData2(engine.context, commandSourceBridge, name, if (operation == 0) 1 else 2, @intCast(operation), 0, null));
        if (em.c.JS_DefinePropertyValueStr(engine.context, global, name, callback, em.c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    // The fixture's test-only callbacks call the actual production resolver
    // and scope accessors; AgentSession._extensionRunner's public object
    // surface is a separate prerequisite, not emulated by a guest facade.
    const loaded = try engine.evalModule(@embedFile("extensions/fixtures/sdk-command-rows-501.input.txt"), "sdk-command-rows.mjs");
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkCommandRowsResult", "sdk-command-rows-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-command-rows-source-501.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?;
    if (!json.equal(rows, actual.value)) std.debug.print("SDK complete command Source501 actual={s}\n", .{raw});
    try std.testing.expect(json.equal(rows, actual.value));
    const cleared = try engine.eval("delete globalThis.sdkCommandRowsResult;delete globalThis.nativeSDKResolveCommands;delete globalThis.nativeSDKSameCommandRows", "sdk-command-rows-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order command execution catalogue contexts and reload incarnation match Source504" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-command-execution-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-command-execution-504.input.txt"), "sdk-command-execution.mjs") catch |err| {
        std.debug.print("SDK Source504 setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkCommandExecutionRows", "sdk-command-execution-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-command-execution-source-504.json"));
    defer expected.deinit();
    const expected_rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(expected_rows.len, actual.value.array.items.len);
    for (expected_rows, actual.value.array.items, 0..) |expected_row, actual_row, index| {
        var fields = expected_row.object.iterator();
        while (fields.next()) |entry| {
            // This original Source run automatically chose an unauthenticated
            // default model. Native's existing factory selects no model. The
            // bypass must reject without a command call or message; exact
            // factory/auth/docs-path error parity remains explicitly open.
            if (index == 0 and std.mem.eql(u8, entry.key_ptr.*, "extra")) {
                const extra = actual_row.object.get("extra").?;
                try std.testing.expect(extra.object.get("error") != null);
                continue;
            }
            const observed = actual_row.object.get(entry.key_ptr.*) orelse return error.MissingSource504Field;
            if (!json.equal(entry.value_ptr.*, observed)) std.debug.print("SDK Source504 row{d} field{s} actual={s}\n", .{ index, entry.key_ptr.*, raw });
            try std.testing.expect(json.equal(entry.value_ptr.*, observed));
        }
    }
    const cleared = try engine.eval("delete globalThis.sdkCommandExecutionRows", "sdk-command-execution-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order actual command actions defaults bound receiver rebind and stale contexts match Source505" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-command-actions-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-command-actions-505.input.txt"), "sdk-command-actions.mjs") catch |err| {
        std.debug.print("SDK Source505 setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkCommandActionsRows", "sdk-command-actions-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    // Source603 repeats the full original corpus on D: and POSIX. Only this
    // one absolute cwd changes; all identities and callback traces are exact.
    const fixture = try sourceFixture("extensions/fixtures/sdk-command-actions-source-505.json", "extensions/fixtures/sdk-command-actions-source-505-posix-603.json", "sdk-command-actions", 1);
    defer std.testing.allocator.free(fixture);
    var expected = try json.Owned.parse(std.testing.allocator, fixture);
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?;
    if (!json.equal(rows, actual.value)) std.debug.print("SDK complete command actions Source505 actual={s}\n", .{raw});
    try std.testing.expect(json.equal(rows, actual.value));
    const cleared = try engine.eval("delete globalThis.sdkCommandActionsRows", "sdk-command-actions-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

fn normalizedOptions(comptime capture: []const u8) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-normalized-options-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-normalized-options-" ++ capture ++ ".input.txt"), "sdk-normalized-options.mjs") catch |err| {
        std.debug.print("SDK Source{s} normalized options setup: {s}\n", .{ capture, engine.last_error orelse "no diagnostic" });
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkNormalizedOptionsRows", "sdk-normalized-options-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    // All three complete Source603 corpora independently retain their six
    // platform cwd values and every shallow identity and descriptor field.
    const fixture = try sourceFixture("extensions/fixtures/sdk-normalized-options-source-" ++ capture ++ ".json", "extensions/fixtures/sdk-normalized-options-source-" ++ capture ++ "-posix-603.json", "sdk-normalized-options", 6);
    defer std.testing.allocator.free(fixture);
    var expected = try json.Owned.parse(std.testing.allocator, fixture);
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?;
    if (!json.equal(rows, actual.value)) std.debug.print("SDK complete normalized options Source{s} actual={s}\n", .{ capture, raw });
    try std.testing.expect(json.equal(rows, actual.value));
    const cleared = try engine.eval("delete globalThis.sdkNormalizedOptionsRows", "sdk-normalized-options-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}
test "native SDK queue order normalized options actual metadata graphs whitelist and shallow identities match Source507 508 509" {
    inline for (.{ "507", "508", "509" }) |capture| try normalizedOptions(capture);
}

test "native SDK queue order normalized metadata getter cache raw ToolInfo and registration refresh match Source511" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-normalized-getter-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-normalized-options-getter-511.input.txt"), "sdk-normalized-getter.mjs") catch |err| {
        std.debug.print("SDK Source511 normalized getter setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkNormalizedGetterRows", "sdk-normalized-getter-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-normalized-options-getter-source-511.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?;
    if (!json.equal(rows, actual.value)) std.debug.print("SDK complete normalized getter Source511 actual={s}\n", .{raw});
    try std.testing.expect(json.equal(rows, actual.value));
    const cleared = try engine.eval("delete globalThis.sdkNormalizedGetterRows", "sdk-normalized-getter-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order actual runner borrowed receiver descriptors diagnostic lookup and disposed rows match Source514" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-runner-contract-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-contract-514.input.txt"), "sdk-runner-contract.mjs") catch |err| {
        std.debug.print("SDK Source514 actual runner setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerContractRows", "sdk-runner-contract-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-contract-source-514.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?;
    if (!json.equal(rows, actual.value)) std.debug.print("SDK complete actual runner Source514 actual={s}\n", .{raw});
    try std.testing.expect(json.equal(rows, actual.value));
    const cleared = try engine.eval("delete globalThis.sdkRunnerContractRows", "sdk-runner-contract-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order actual resolver operator BigInt Symbol coercion and suffix traces match Source513" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-command-operator-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-command-operators-513.input.txt"), "sdk-command-operators.mjs") catch |err| {
        std.debug.print("SDK Source513 actual operators setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkCommandOperatorRows", "sdk-command-operators-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-command-operators-source-513.json"));
    defer expected.deinit();
    const expected_rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(expected_rows.len, actual.value.array.items.len);
    for (expected_rows, actual.value.array.items) |source, observed| {
        inline for (.{ "id", "trace", "constructed" }) |field| try std.testing.expect(json.equal(source.object.get(field).?, observed.object.get(field).?));
        const outcome = source.object.get("outcome").?;
        const native = observed.object.get("outcome").?;
        if (outcome.object.get("error")) |failure| {
            // ECMAScript exception class and original coercion/order are the
            // operator contract. Preserve the captured Node wording unchanged;
            // exact Node/QuickJS builtin error-message parity remains open.
            const actual_failure = native.object.get("error") orelse return error.MissingSource513Exception;
            try std.testing.expect(json.equal(failure.object.get("name").?, actual_failure.object.get("name").?));
        } else {
            if (!json.equal(outcome, native)) std.debug.print("SDK Source513 outcome actual={s}\n", .{raw});
            try std.testing.expect(json.equal(outcome, native));
        }
    }
    const cleared = try engine.eval("delete globalThis.sdkCommandOperatorRows", "sdk-command-operators-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC runner constructor refs fields and implemented foundation match Source516" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-runner-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-constructor-516.input.txt"), "sdk-public-runner.mjs") catch |err| {
        std.debug.print("SDK Source516 PUBLIC constructor setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkPublicRunnerRows", "sdk-public-runner-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-constructor-source-516.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(rows.len, actual.value.array.items.len);
    for (rows, actual.value.array.items, 0..) |source, observed, index| {
        if (index == 0) {
            const expected_own = source.object.get("own").?.object.keys();
            const actual_own = observed.object.get("own").?.object.keys();
            try std.testing.expectEqual(expected_own.len, actual_own.len);
            for (expected_own, actual_own) |wanted, found| try std.testing.expectEqualStrings(wanted, found);
        }
        var fields = source.object.iterator();
        while (fields.next()) |entry| {
            const field = observed.object.get(entry.key_ptr.*) orelse return error.MissingSource516FoundationField;
            if (!json.equal(entry.value_ptr.*, field)) std.debug.print("SDK Source516 row{d} field{s} actual={s}\n", .{ index, entry.key_ptr.*, raw });
            try std.testing.expect(json.equal(entry.value_ptr.*, field));
        }
    }
    const cleared = try engine.eval("delete globalThis.sdkPublicRunnerRows", "sdk-public-runner-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC bindCore getter phases provider queues and live receivers match Source519" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-bindcore-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-bindcore-519.input.txt"), "sdk-public-bindcore.mjs") catch |err| {
        std.debug.print("SDK Source519 PUBLIC bindCore setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerBindCoreRows", "sdk-public-bindcore-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-bindcore-source-519.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?;
    if (!json.equal(rows, actual.value)) std.debug.print("SDK complete PUBLIC bindCore Source519 actual={s}\n", .{raw});
    try std.testing.expect(json.equal(rows, actual.value));
    const cleared = try engine.eval("delete globalThis.sdkRunnerBindCoreRows", "sdk-public-bindcore-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC tool context descriptors nested Promise options and borrowed refs match Source521" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-tool-context-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-toolcontext-521.input.txt"), "sdk-public-tool-context.mjs") catch |err| {
        std.debug.print("SDK Source521 PUBLIC tool context setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerToolContextRows", "sdk-public-tool-context-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-toolcontext-source-521.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(rows.len, actual.value.array.items.len);
    for (rows, actual.value.array.items) |source, observed| {
        const name = source.object.get("id").?.string;
        if (std.mem.eql(u8, name, "null-options")) {
            inline for (.{ "id", "events", "calls" }) |field| try std.testing.expect(json.equal(source.object.get(field).?, observed.object.get(field).?));
            const wanted = source.object.get("outcome").?;
            const found = observed.object.get("outcome").?;
            try std.testing.expect(json.equal(wanted.object.get("identity").?, found.object.get("identity").?));
            try std.testing.expect(json.equal(wanted.object.get("error").?.object.get("name").?, found.object.get("error").?.object.get("name").?));
            // Original Node builtin wording remains in the immutable capture;
            // semantic error class/order is compared across the two engines.
        } else {
            if (!json.equal(source, observed)) std.debug.print("SDK Source521 actual={s}\n", .{raw});
            try std.testing.expect(json.equal(source, observed));
        }
    }
    const cleared = try engine.eval("delete globalThis.sdkRunnerToolContextRows", "sdk-public-tool-context-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC renderer chains deferred roots raw errors and flatMap getters match Source525" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group_mod.Group.add(group, "sdk-public-renderer-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-renderers-525.input.txt"), "sdk-public-renderers.mjs") catch |err| {
        std.debug.print("SDK Source525 PUBLIC renderer setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerRendererRows", "sdk-public-renderers-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-renderers-source-525.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?;
    if (!json.equal(rows, actual.value)) std.debug.print("SDK complete PUBLIC renderer Source525 actual={s}\n", .{raw});
    try std.testing.expect(json.equal(rows, actual.value));
    const cleared = try engine.eval("delete globalThis.sdkRunnerRendererRows", "sdk-public-renderers-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC UI prompt old numeric depth finally raw identity and queued receivers match Source530" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-ui-prompts-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-ui-prompts-530.input.txt"), "sdk-public-ui-prompts.mjs") catch |err| {
        std.debug.print("SDK Source530 PUBLIC UI prompts setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerUIPromptRows", "sdk-public-ui-prompts-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-ui-prompts-source-530.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 20), rows.len);
    try std.testing.expectEqual(rows.len, actual.value.array.items.len);
    for (rows, actual.value.array.items) |source, observed| {
        if (std.mem.eql(u8, source.object.get("id").?.string, "symbol-depth")) {
            // Keep the immutable Node wording. Compare the original builtin
            // error class and every other field/trace across the two engines.
            inline for (.{ "id", "events", "depth", "active" }) |field| try std.testing.expect(json.equal(source.object.get(field).?, observed.object.get(field).?));
            const wanted = source.object.get("outcome").?;
            const found = observed.object.get("outcome").?;
            inline for (.{ "identity", "finishIdentity", "name" }) |field| try std.testing.expect(json.equal(wanted.object.get(field).?, found.object.get(field).?));
        } else {
            if (!json.equal(source, observed)) std.debug.print("SDK Source530 complete actual={s}\n", .{raw});
            try std.testing.expect(json.equal(source, observed));
        }
    }
    const cleared = try engine.eval("delete globalThis.sdkRunnerUIPromptRows", "sdk-public-ui-prompts-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC async emit snapshots intrinsic await errors and lazy context match Source527" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-emit-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-emit-527.input.txt"), "sdk-public-emit.mjs") catch |err| {
        std.debug.print("SDK Source527 PUBLIC emit setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerEmitRows", "sdk-public-emit-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-emit-source-527.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 9), rows.len);
    try std.testing.expectEqual(rows.len, actual.value.array.items.len);
    for (rows, actual.value.array.items) |source, observed| {
        if (std.mem.eql(u8, source.object.get("id").?.string, "post-invalidate-context")) {
            inline for (.{ "id", "outcome", "events" }) |field| try std.testing.expect(json.equal(source.object.get(field).?, observed.object.get(field).?));
            const wanted = source.object.get("errors").?.array.items;
            const found = observed.object.get("errors").?.array.items;
            try std.testing.expectEqual(@as(usize, 1), wanted.len);
            try std.testing.expectEqual(wanted.len, found.len);
            inline for (.{ "extensionPath", "event", "error", "ownKeys" }) |field| try std.testing.expect(json.equal(wanted[0].object.get(field).?, found[0].object.get(field).?));
            // Runtime-rendered stack text is preserved in the original Source
            // capture but not claimed equal between Node and QuickJS.
            try std.testing.expect(wanted[0].object.get("stack").?.string.len > 0);
            try std.testing.expect(found[0].object.get("stack").?.string.len > 0);
        } else {
            if (!json.equal(source, observed)) std.debug.print("SDK Source527 complete actual={s}\n", .{raw});
            try std.testing.expect(json.equal(source, observed));
        }
    }
    const cleared = try engine.eval("delete globalThis.sdkRunnerEmitRows", "sdk-public-emit-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC emit custom iterator close precedence latest result and before short circuits match Source532" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-emit-iterators-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-emit-iterators-532.input.txt"), "sdk-public-emit-iterators.mjs") catch |err| {
        std.debug.print("SDK Source532 PUBLIC emit iterators setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerEmitIteratorRows", "sdk-public-emit-iterators-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-emit-iterators-source-532.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?;
    try std.testing.expectEqual(@as(usize, 17), rows.array.items.len);
    if (!json.equal(rows, actual.value)) std.debug.print("SDK Source532 complete actual={s}\n", .{raw});
    try std.testing.expect(json.equal(rows, actual.value));
    const cleared = try engine.eval("delete globalThis.sdkRunnerEmitIteratorRows", "sdk-public-emit-iterators-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC shortcuts reserved precedence diagnostics getters and raw warnings match Source534" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/console.zig").install(engine, std.testing.io);
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-shortcuts-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-shortcuts-534.input.txt"), "sdk-public-shortcuts.mjs") catch |err| {
        std.debug.print("SDK Source534 PUBLIC shortcuts setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerShortcutRows", "sdk-public-shortcuts-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-shortcuts-source-534.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 8), rows.len);
    try std.testing.expectEqual(rows.len, actual.value.array.items.len);
    for (rows, actual.value.array.items) |source, observed| {
        if (std.mem.eql(u8, source.object.get("id").?.string, "invalid-key")) {
            inline for (.{ "id", "events", "diagnostics" }) |field| try std.testing.expect(json.equal(source.object.get(field).?, observed.object.get(field).?));
            const wanted = source.object.get("outcome").?;
            const found = observed.object.get("outcome").?;
            inline for (.{ "identity", "name" }) |field| try std.testing.expect(json.equal(wanted.object.get(field).?, found.object.get(field).?));
            // Original Node builtin wording remains immutable; only its
            // class and the complete surrounding behavior are compared.
        } else {
            if (!json.equal(source, observed)) std.debug.print("SDK Source534 complete actual={s}\n", .{raw});
            try std.testing.expect(json.equal(source, observed));
        }
    }
    const cleared = try engine.eval("delete globalThis.sdkRunnerShortcutRows", "sdk-public-shortcuts-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC eight real async reducers preserve all fourteen selected Source535 cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-reducers-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-reducers-540.input.txt"), "sdk-public-reducers.mjs") catch |err| {
        std.debug.print("SDK Source535 PUBLIC reducers setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerReducerRows", "sdk-public-reducers-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-reducers-source-535.json"));
    defer expected.deinit();
    const methods = .{ "emitCacheWarmingDecision", "emitMessageEnd", "emitToolResult", "emitToolCall", "emitBeforeProviderRequest", "emitBeforeProviderHeaders", "emitResourcesDiscover", "emitInput" };
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 23), rows.len);
    try std.testing.expectEqual(@as(usize, 14), actual.value.array.items.len);
    var index: usize = 0;
    for (rows) |source| {
        var selected = false;
        inline for (methods) |name| if (std.mem.eql(u8, name, source.object.get("method").?.string)) {
            selected = true;
        };
        if (!selected) continue;
        try std.testing.expect(index < actual.value.array.items.len);
        const observed = actual.value.array.items[index];
        if (!json.equal(source, observed)) std.debug.print("SDK Source535 selected complete actual={s}\n", .{raw});
        try std.testing.expect(json.equal(source, observed));
        index += 1;
    }
    try std.testing.expectEqual(@as(usize, 14), index);
    // The nine original Source cases for boundary/userBash/context/agentStart
    // remain immutable in the capture. Their four bodies are still absent.
    const cleared = try engine.eval("delete globalThis.sdkRunnerReducerRows", "sdk-public-reducers-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC user bash exact validation getters report and rethrow match eighteen Source539 cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-user-bash-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-user-bash-549.input.txt"), "sdk-public-user-bash.mjs") catch |err| {
        std.debug.print("SDK Source539 PUBLIC user bash setup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerUserBashRows", "sdk-public-user-bash-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-user-bash-source-539.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 18), rows.len);
    try std.testing.expectEqual(rows.len, actual.value.array.items.len);
    for (rows, actual.value.array.items) |source, observed| {
        try std.testing.expectEqual(@as(usize, 4), source.object.count());
        try std.testing.expectEqual(source.object.count(), observed.object.count());
        inline for (.{ "id", "outcome", "events" }) |field| {
            if (!json.equal(source.object.get(field).?, observed.object.get(field).?)) std.debug.print("SDK Source539 complete actual={s}\n", .{raw});
            try std.testing.expect(json.equal(source.object.get(field).?, observed.object.get(field).?));
        }
        const wanted_errors = source.object.get("errors").?.array.items;
        const found_errors = observed.object.get("errors").?.array.items;
        try std.testing.expectEqual(wanted_errors.len, found_errors.len);
        for (wanted_errors, found_errors) |wanted, found| {
            if (wanted.object.get("stack")) |stack| {
                try std.testing.expectEqual(@as(usize, 5), wanted.object.count());
                try std.testing.expectEqual(wanted.object.count(), found.object.count());
                inline for (.{ "extensionPath", "event", "error", "ownKeys" }) |field| try std.testing.expect(json.equal(wanted.object.get(field).?, found.object.get(field).?));
                // Preserve the original Node-generated Error stack verbatim in
                // the fixture. Runtime frame text is not portable; both actual
                // engines must still produce a nonempty string at the same key.
                try std.testing.expect(stack == .string and stack.string.len > 0);
                const observed_stack = found.object.get("stack").?;
                try std.testing.expect(observed_stack == .string and observed_stack.string.len > 0);
            } else {
                try std.testing.expect(json.equal(wanted, found));
            }
        }
    }
    const cleared = try engine.eval("delete globalThis.sdkRunnerUserBashRows", "sdk-public-user-bash-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC user bash preserves three original Source535 foundation cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-user-bash-foundation-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-user-bash-foundation-550.input.txt"), "sdk-public-user-bash-foundation.mjs") catch |err| {
        std.debug.print("SDK Source535 PUBLIC user bash foundation: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerUserBashFoundationRows", "sdk-public-user-bash-foundation-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-reducers-source-535.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 23), rows.len);
    try std.testing.expectEqual(@as(usize, 3), actual.value.array.items.len);
    var index: usize = 0;
    for (rows) |source| {
        if (!std.mem.eql(u8, source.object.get("method").?.string, "emitUserBash")) continue;
        try std.testing.expect(index < actual.value.array.items.len);
        const observed = actual.value.array.items[index];
        try std.testing.expectEqual(@as(usize, 5), source.object.count());
        try std.testing.expectEqual(source.object.count(), observed.object.count());
        inline for (.{ "id", "method", "outcome", "events" }) |field| {
            if (!json.equal(source.object.get(field).?, observed.object.get(field).?)) std.debug.print("SDK Source535 user bash complete actual={s}\n", .{raw});
            try std.testing.expect(json.equal(source.object.get(field).?, observed.object.get(field).?));
        }
        const wanted_errors = source.object.get("errors").?.array.items;
        const found_errors = observed.object.get("errors").?.array.items;
        try std.testing.expectEqual(wanted_errors.len, found_errors.len);
        for (wanted_errors, found_errors) |wanted, found| {
            try std.testing.expectEqual(@as(usize, 5), wanted.object.count());
            try std.testing.expectEqual(wanted.object.count(), found.object.count());
            inline for (.{ "extensionPath", "event", "error", "ownKeys" }) |field| try std.testing.expect(json.equal(wanted.object.get(field).?, found.object.get(field).?));
            // Generated engine stack frames differ, with every other field and
            // the stack key, type and nonempty presence still checked.
            const wanted_stack = wanted.object.get("stack").?;
            const found_stack = found.object.get("stack").?;
            try std.testing.expect(wanted_stack == .string and wanted_stack.string.len > 0);
            try std.testing.expect(found_stack == .string and found_stack.string.len > 0);
        }
        index += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), index);
    const cleared = try engine.eval("delete globalThis.sdkRunnerUserBashFoundationRows", "sdk-public-user-bash-foundation-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC boundary preserves initial await rebuild invalidation and recovery Source535 cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-boundary-foundation-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-boundary-foundation-554.input.txt"), "sdk-public-boundary-foundation.mjs") catch |err| {
        std.debug.print("SDK Source535 PUBLIC boundary foundation: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerBoundaryFoundationRows", "sdk-public-boundary-foundation-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-reducers-source-535.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 23), rows.len);
    try std.testing.expectEqual(@as(usize, 3), actual.value.array.items.len);
    var index: usize = 0;
    for (rows) |source| {
        if (!std.mem.eql(u8, source.object.get("method").?.string, "emitBoundary")) continue;
        try std.testing.expect(index < actual.value.array.items.len);
        const observed = actual.value.array.items[index];
        if (!json.equal(source, observed)) std.debug.print("SDK Source535 boundary complete actual={s}\n", .{raw});
        try std.testing.expect(json.equal(source, observed));
        index += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), index);
    const cleared = try engine.eval("delete globalThis.sdkRunnerBoundaryFoundationRows", "sdk-public-boundary-foundation-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC boundary twenty actual Source555 phase getter failure and receiver cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-boundary-phases-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-boundary-phases-555.input.txt"), "sdk-public-boundary-phases.mjs") catch |err| {
        std.debug.print("SDK Source555 PUBLIC boundary phases: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerBoundaryPhaseRows", "sdk-public-boundary-phases-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-boundary-phases-source-555.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 20), rows.len);
    try std.testing.expectEqual(rows.len, actual.value.array.items.len);
    for (rows, actual.value.array.items) |source, observed| {
        if (!json.equal(source, observed)) std.debug.print("SDK Source555 boundary complete actual={s}\n", .{raw});
        try std.testing.expect(json.equal(source, observed));
    }
    const cleared = try engine.eval("delete globalThis.sdkRunnerBoundaryPhaseRows", "sdk-public-boundary-phases-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC context two phases actual replay clone and ten original Source557 cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-context-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-context-558.input.txt"), "sdk-public-context.mjs") catch |err| {
        std.debug.print("SDK Source557 PUBLIC context: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerContextClosureRows", "sdk-public-context-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-context-source-557.json"));
    defer expected.deinit();
    try std.testing.expectEqual(@as(usize, 2), actual.value.object.count());
    inline for (.{ .{ "source536", 8 }, .{ "source535", 2 } }) |capture| {
        const rows = expected.value.object.get(capture[0]).?.array.items;
        const found = actual.value.object.get(capture[0]).?.array.items;
        try std.testing.expectEqual(@as(usize, capture[1]), rows.len);
        try std.testing.expectEqual(rows.len, found.len);
        for (rows, found) |source, observed| {
            if (!json.equal(source, observed)) std.debug.print("SDK Source557 context complete actual={s}\n", .{raw});
            try std.testing.expect(json.equal(source, observed));
        }
    }
    const cleared = try engine.eval("delete globalThis.sdkRunnerContextClosureRows", "sdk-public-context-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}

test "native SDK queue order PUBLIC before agent start full normalization lazy renderer and nineteen actual Source cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment = try std.process.Environ.createMap(std.testing.environ, std.testing.allocator);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-sdk"});
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-agent-start-root");
    try root.installSchemas();
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-runner-agent-start-561.input.txt"), "sdk-public-agent-start.mjs") catch |err| {
        std.debug.print("SDK Source560 PUBLIC before agent start: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkRunnerAgentStartRows", "sdk-public-agent-start-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer std.testing.allocator.free(raw);
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    // Actual current045 Source605 repeats every row with the caller's absolute
    // POSIX package directory. Keep original Windows rows and all descriptor,
    // identity, getter, error and retained-callback checks unchanged.
    var expected = try json.Owned.parse(std.testing.allocator, if (host.os.tag == .windows) @embedFile("extensions/fixtures/sdk-runner-agent-start-source-560.json") else @embedFile("extensions/fixtures/sdk-runner-agent-start-source-605-posix.json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 18), rows.len);
    try std.testing.expectEqual(rows.len, actual.value.array.items.len);
    for (rows, actual.value.array.items) |source, observed| {
        if (!std.mem.eql(u8, source.object.get("id").?.string, "invalid-section")) {
            if (!json.equal(source, observed)) std.debug.print("SDK Source560 agent start complete actual={s}\n", .{raw});
            try std.testing.expect(json.equal(source, observed));
            continue;
        }
        try std.testing.expectEqual(@as(usize, 4), source.object.count());
        try std.testing.expectEqual(source.object.count(), observed.object.count());
        inline for (.{ "id", "outcome", "events" }) |field| try std.testing.expect(json.equal(source.object.get(field).?, observed.object.get(field).?));
        const wanted_errors = source.object.get("errors").?.array.items;
        const found_errors = observed.object.get("errors").?.array.items;
        try std.testing.expectEqual(@as(usize, 2), wanted_errors.len);
        try std.testing.expectEqual(wanted_errors.len, found_errors.len);
        for (wanted_errors, found_errors) |wanted, found| {
            try std.testing.expectEqual(@as(usize, 5), wanted.object.count());
            try std.testing.expectEqual(wanted.object.count(), found.object.count());
            inline for (.{ "extensionPath", "event", "error", "ownKeys" }) |field| try std.testing.expect(json.equal(wanted.object.get(field).?, found.object.get(field).?));
            // The original generated frame strings remain byte-unchanged in
            // Source. Both engines must retain nonempty stack strings here.
            const wanted_stack = wanted.object.get("stack").?;
            const found_stack = found.object.get("stack").?;
            try std.testing.expect(wanted_stack == .string and wanted_stack.string.len > 0);
            try std.testing.expect(found_stack == .string and found_stack.string.len > 0);
        }
    }
    const foundation_result = try engine.eval("sdkRunnerAgentFoundationRows", "sdk-public-agent-foundation-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(foundation_result);
    const foundation_raw = try engine.stringify(foundation_result);
    defer std.testing.allocator.free(foundation_raw);
    var foundation = try json.Owned.parse(std.testing.allocator, foundation_raw);
    defer foundation.deinit();
    var original = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/sdk-runner-reducers-source-535.json"));
    defer original.deinit();
    try std.testing.expectEqual(@as(usize, 1), foundation.value.array.items.len);
    var matched: usize = 0;
    for (original.value.object.get("rows").?.array.items) |source| {
        if (!std.mem.eql(u8, source.object.get("method").?.string, "emitBeforeAgentStart")) continue;
        if (!json.equal(source, foundation.value.array.items[0])) std.debug.print("SDK Source535 agent foundation actual={s}\n", .{foundation_raw});
        try std.testing.expect(json.equal(source, foundation.value.array.items[0]));
        matched += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), matched);
    const cleared = try engine.eval("delete globalThis.sdkRunnerAgentStartRows;delete globalThis.sdkRunnerAgentFoundationRows", "sdk-public-agent-start-clear.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    em.c.JS_RunGC(engine.runtime);
}
