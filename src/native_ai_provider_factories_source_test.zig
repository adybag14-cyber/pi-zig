//! Replay the retained genuine Source92 against actual native module values.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const functions = @import("extensions/native_node_function.zig");
const wrappers = @import("extensions/native_ai_provider_wrappers.zig");

test "native actual provider factories compare all genuine4954 Source92 observations" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"provider-factories-source92"});
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    var s: v.Scope = .{ .engine = engine };
    defer s.deinit();
    const api = try s.object();
    const models = try s.own(try @import("extensions/native_ai_models_namespace.zig").create(engine));
    try engine.registerValueModule("native:factory-models92", models);
    const apis = try s.own(try @import("extensions/native_ai_builtin_apis.zig").create(engine));
    try s.put(api, "apis", apis);
    const constructors = try s.own(try @import("extensions/native_ai_provider_factories.zig").create(engine, apis));
    const all = try s.own(try @import("extensions/native_ai_provider_factories.zig").all(engine, constructors));
    try engine.registerValueModule("native:factory-all92", all);
    const factories = try s.object();
    inline for (@import("extensions/native_ai_provider_specs.zig").providers) |spec| try s.put(factories, spec.function.ptr, try s.get(constructors, spec.function.ptr));
    try s.put(api, "factories", factories);
    const wrapper_exports = try s.object();
    const Adapter = struct {
        fn opencode(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return wrappers.streams(host, .opencode, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
        fn cloudflare(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return wrappers.streams(host, .cloudflare, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
        fn classifier(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return wrappers.classifier(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
        fn model(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var local: v.Scope = .{ .engine = host };
            defer local.deinit();
            return c.JS_DupValue(host.context, try wrappers.cloudflareModel(&local, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined()));
        }
    };
    try s.put(wrapper_exports, "withOpenCodeSessionHeader", try s.own(try functions.create(engine, "withOpenCodeSessionHeader", 1, Adapter.opencode, &.{})));
    try s.put(wrapper_exports, "cloudflareStreams", try s.own(try functions.create(engine, "cloudflareStreams", 1, Adapter.cloudflare, &.{})));
    try s.put(wrapper_exports, "cloudflareClassifier", try s.own(try functions.create(engine, "cloudflareClassifier", 1, Adapter.classifier, &.{})));
    try s.put(wrapper_exports, "resolveCloudflareModel", try s.own(try functions.create(engine, "resolveCloudflareModel", 2, Adapter.model, &.{})));
    try s.put(api, "wrappers", wrapper_exports);
    const helpers = try s.object();
    try s.put(helpers, "personalizeOpenRouterCatalog", try s.own(try @import("extensions/native_ai_provider_openrouter.zig").create(engine)));
    try s.put(helpers, "openRouterCost", try s.own(try @import("extensions/native_ai_provider_openrouter.zig").costFunction(engine)));
    try s.put(api, "helpers", helpers);
    const global = try s.own(try engine.checked(c.JS_GetGlobalObject(engine.context)));
    try s.put(global, "ownedFactoryAPI", api);
    const captured = @embedFile("extensions/fixtures/provider-factories-models-4954-source.json");
    const captured_z = try std.testing.allocator.dupeZ(u8, captured);
    defer std.testing.allocator.free(captured_z);
    try s.put(global, "ownedFactorySource", try s.own(try engine.checked(c.JS_ParseJSON(engine.context, captured_z.ptr, captured.len, "actual-factory-Source92.json"))));
    const result = engine.evalModule(@embedFile("extensions/native_ai_provider_factories_fixture.mjs") ++
        \\import * as models from 'native:factory-models92';import * as all from 'native:factory-all92';
        \\const observed=await run({...ownedFactoryAPI,models,all});
        \\if(ownedFactorySource.sourceHead!=='4954d760504c11df9b2cbdc040346107b6a8153d'||ownedFactorySource.cases!==92||observed.rows.length!==92)throw Error('Genuine Source92 inventory required');
        \\for(let index=0;index<observed.rows.length;index++)if(JSON.stringify(observed.rows[index])!==JSON.stringify(ownedFactorySource.rows[index]))throw Error(JSON.stringify({case:observed.rows[index].case,actual:observed.rows[index],source:ownedFactorySource.rows[index]}));
        \\delete globalThis.ownedFactoryAPI;delete globalThis.ownedFactorySource;
    , "native-actual-provider-factories-source92.mjs") catch |err| {
        std.debug.print("Actual provider factories Source92: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
