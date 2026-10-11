const std = @import("std");
const em = @import("extensions/engine.zig");
const group_mod = @import("extensions/native_group.zig");
const json = @import("mcp/protocol.zig").json;

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
