const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const durable = @import("extensions/native_durable.zig");
const json = @import("durable/backend/json.zig");
const c = em.c;
test "native Models actual Source9 credential resolution typed services and abort identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try @import("extensions/native_models.zig").populateExports(engine, exports);
    try engine.registerValueModule("native-typed-models", exports);
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-19cb534-model-services-source.json"));
    defer fixture.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "modelsServiceSource", try durable.jsValue(engine, fixture.value));
    const module = engine.evalModule(@embedFile("durable/fixtures/durable-19cb534-model-services-native.input.txt"), "native-model-services-source9") catch |err| {
        std.debug.print("Native Models services {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        return err;
    };
    defer engine.freeValue(module);
    const observed = try sdk.get(engine, global, "modelsServicesActual");
    defer engine.freeValue(observed);
    const raw = try engine.stringify(observed);
    defer engine.gpa.free(raw);
    std.debug.print("Native Models services raw {s}\n", .{raw});
    c.JS_RunGC(engine.runtime);
}

fn sourceProof(comptime fixture_path: []const u8, comptime input_path: []const u8, comptime label: [:0]const u8) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const exports = if (comptime std.mem.eql(u8, label, "native-model-streams-source10")) stream_exports: {
        try @import("extensions/native_stream.zig").install(engine);
        break :stream_exports c.JS_DupValue(engine.context, engine.native_module_values.get("@earendil-works/pi-ai").?);
    } else plain_exports: {
        const value = try sdk.object(engine);
        errdefer engine.freeValue(value);
        try @import("extensions/native_models.zig").populateExports(engine, value);
        break :plain_exports value;
    };
    defer engine.freeValue(exports);
    try engine.registerValueModule("native-typed-models", exports);
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile(fixture_path));
    defer fixture.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "modelsServiceSource", try durable.jsValue(engine, fixture.value));
    const module = engine.evalModule(@embedFile(input_path), label) catch |err| {
        std.debug.print("Native Models {s} {s}: {s}\n", .{ label, @errorName(err), engine.last_error orelse "none" });
        return err;
    };
    defer engine.freeValue(module);
    const observed = try sdk.get(engine, global, "modelsServicesActual");
    defer engine.freeValue(observed);
    const raw = try engine.stringify(observed);
    defer engine.gpa.free(raw);
    std.debug.print("Native Models {s} raw {s}\n", .{ label, raw });
    c.JS_RunGC(engine.runtime);
}
test "native Models actual Source10 auth causes transforms and raw typed failures" {
    try sourceProof("durable/fixtures/durable-19cb534-model-auth-edges-source.json", "durable/fixtures/durable-19cb534-model-auth-edges-native.input.txt", "native-auth-edges-source10");
}
test "native Models actual Source6 credential identities serialized queues and cancellation" {
    try sourceProof("durable/fixtures/durable-19cb534-credential-store-source.json", "durable/fixtures/durable-19cb534-credential-store-native.input.txt", "native-credentials-source6");
}
test "native Models actual typed services credential queues release every failed host allocation" {
    const Probe = struct {
        fn exercise(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const exports = try sdk.object(engine);
            defer engine.freeValue(exports);
            try @import("extensions/native_models.zig").populateExports(engine, exports);
            try engine.registerValueModule("native-typed-models", exports);
            const module = try engine.evalModule(
                \\import{createModels,InMemoryCredentialStore}from'native-typed-models';const credentials=new InMemoryCredentialStore(),credential={type:'api_key',key:'fixture'},post=await credentials.modify('fixture',async()=>credential);if(post!==credential||await credentials.read('fixture')!==credential)throw Error('credential identity');
                \\const models=createModels({credentials});const model={id:'judge',provider:'fixture',api:'fixture-api',type:'classifier',input:['text']};models.setProvider({id:'fixture',auth:{apiKey:{async resolve({credential}){return{auth:{apiKey:credential.key},source:'fixture'}}}},getModels:()=>[],getAllModels:()=>[model],async classify(selected,context,options){if(selected!==model||options.apiKey!=='fixture')throw Error('typed request');return{answers:{good:{value:true}},stopReason:'stop'}}});const value=await models.classify(model,{state:{},questions:{}});if(value.stopReason!=='stop'||!value.answers.good.value)throw Error('typed classifier');await credentials.delete('fixture');if(await credentials.read('fixture')!==undefined)throw Error('credential delete');export const proof=true;
            , "native-typed-models-allocation");
            defer engine.freeValue(module);
            c.JS_RunGC(engine.runtime);
        }
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.JavaScriptException or err == error.OutOfMemory)) return error.OutOfMemory;
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

test "native Models actual Source streams10 synchronous outer auth transcript and deferred services" {
    try sourceProof("durable/fixtures/durable-19cb534-model-streams-source.json", "durable/fixtures/durable-19cb534-model-streams-native.input.txt", "native-model-streams-source10");
}

test "native Models actual streaming auth continuations release every failed host allocation" {
    const Probe = struct {
        fn exercise(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            engine.native_io = std.testing.io;
            try @import("extensions/native_stream.zig").install(engine);
            const module = try engine.evalModule(
                \\import{createModels,AssistantMessageEventStream}from'@earendil-works/pi-ai';const models=createModels(),model={id:'chat',provider:'fixture',api:'fixture-api',input:['text']},message={role:'assistant',api:'fixture-api',provider:'fixture',model:'chat',content:[],stopReason:'stop',timestamp:0};models.setProvider({id:'fixture',auth:{apiKey:{async resolve(){return{auth:{apiKey:'fixture'},source:'fixture'}}}},streamSimple(selected,context,options){if(options.apiKey!=='fixture'||context.messages.length!==1)throw Error('request');const stream=new AssistantMessageEventStream();stream.push({type:'done',reason:'stop',message});return stream}});const stream=models.streamSimple(model,{systemPrompt:'System',messages:[]});if(await stream.result()!==message)throw Error('result identity');let count=0;for await(const event of stream){if(event.message!==message)throw Error('event identity');count++}if(count!==1)throw Error('event count');export const proof=true;
            , "native-model-streams-allocation");
            defer engine.freeValue(module);
            c.JS_RunGC(engine.runtime);
        }
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.JavaScriptException or err == error.OutOfMemory)) return error.OutOfMemory;
                std.debug.print("stream GPA unexpected {s} fail_index={d} alloc_index={d} induced={} stack={f}\n", .{ @errorName(err), failing.fail_index, failing.alloc_index, failing.has_induced_failure, std.debug.FormatStackTrace{ .stack_trace = failing.getStackTrace() } });
                return err;
            };
            const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
            if (failing.has_induced_failure) std.debug.print("stream GPA swallowed fail_index={d} alloc_index={d} stack={f}\n", .{ failing.fail_index, failing.alloc_index, std.debug.FormatStackTrace{ .stack_trace = failing.getStackTrace() } });
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

test "native Models actual Source login8 credential persistence causes and preabort identity" {
    try sourceProof("durable/fixtures/durable-19cb534-model-login-source.json", "durable/fixtures/durable-19cb534-model-login-native.input.txt", "native-model-login-source8");
}

test "native Models actual login credential mutation release every failed host allocation" {
    const Probe = struct {
        fn exercise(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            engine.native_io = std.testing.io;
            const exports = try sdk.object(engine);
            defer engine.freeValue(exports);
            try @import("extensions/native_models.zig").populateExports(engine, exports);
            try engine.registerValueModule("native-typed-models", exports);
            const module = try engine.evalModule(
                \\import{createModels,InMemoryCredentialStore}from'native-typed-models';const credentials=new InMemoryCredentialStore(),models=createModels({credentials}),credential={type:'api_key',key:'fixture-key'},signal=new AbortController().signal;models.setProvider({id:'fixture',name:'Fixture',auth:{apiKey:{async login(interaction){if(interaction.signal!==signal)throw Error('signal identity');return credential}}}});if(await models.login('fixture','api_key',{signal})!==credential||await credentials.read('fixture')!==credential)throw Error('login identity');await models.logout('fixture',{signal});if(await credentials.read('fixture')!==undefined)throw Error('logout');export const proof=true;
            , "native-model-login-allocation");
            defer engine.freeValue(module);
            c.JS_RunGC(engine.runtime);
        }
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.JavaScriptException or err == error.OutOfMemory)) return error.OutOfMemory;
                std.debug.print("login GPA unexpected {s} fail_index={d} induced={} stack={f}\n", .{ @errorName(err), failing.fail_index, failing.has_induced_failure, std.debug.FormatStackTrace{ .stack_trace = failing.getStackTrace() } });
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

test "native Models actual Source auth mutation3 no eager termination after mutation start" {
    try sourceProof("durable/fixtures/durable-19cb534-model-auth-mutation-boundaries-source.json", "durable/fixtures/durable-19cb534-model-auth-mutation-boundaries-native.input.txt", "native-model-auth-mutation-source3");
}
