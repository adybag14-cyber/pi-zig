const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;

test {
    _ = @import("native_sdk_registry_composition_test.zig");
}

test "native private registry integrated fourteen binding boundary and custom-message descriptors match Source" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_sdk_registry_private_assembly.zig").setup(engine, &environment);
    const result = engine.evalModule(
        \\const names=['sendCustomMessage','_appendCustomMessage','_flushPendingCustomMessages','bindExtensions','extendResourcesFromExtensions','buildExtensionResourcePaths','getExtensionSourceLabel','_executeNestedToolCall','_applyBoundaryDrafts','_createBoundaryPreviewManager','_getPendingBoundaryMessages','_buildBoundaryContext','_commitBoundaryDrafts','_reportInvalidBoundaryContinuation'];
        \\const summarize=f=>({name:f.name,length:f.length,async:Object.getPrototypeOf(f)===Object.getPrototypeOf(async()=>{}),ownPrototype:Object.hasOwn(f,'prototype')});
        \\for(const key of names){const d=Object.getOwnPropertyDescriptor(registryNative.AgentSession.prototype,key);if(!d)throw Error('Integrated method absent: '+key);const actual={key,kind:'data',enumerable:d.enumerable,configurable:d.configurable,writable:d.writable,valueType:typeof d.value,function:summarize(d.value)};const expected=registryNativePrototypeSource.descriptors.find(row=>row.key===key);if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({actual,expected}));}
        \\globalThis.nativeRegistryIntegrationReport={installed:names,missing:nativeRegistryMissingMethods,full_factory_qualified:false,full_pi_qualified:false,public_activation:false};export const done=true;
    , "private-session-integrated11.mjs") catch |err| {
        std.debug.print("Private session integration: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(result);
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context));
    defer engine.freeValue(global);
    const report = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "nativeRegistryIntegrationReport"));
    defer engine.freeValue(report);
    const report_json = try engine.stringify(report);
    defer std.testing.allocator.free(report_json);
    std.debug.print("PRIVATE_SESSION_INTEGRATION={s}\n", .{report_json});
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
