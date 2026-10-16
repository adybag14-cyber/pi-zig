//! Actual ModelsImpl composition. Each instance has ordinary live fields and
//! shares one lexical prototype; no bound registry substitutes for `this`.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
const queries = @import("native_ai_models_queries.zig");
const authentication = @import("native_ai_models_auth_methods.zig");
const refresh = @import("native_ai_models_refresh_methods.zig");
const requests = @import("native_ai_models_request_methods.zig");

pub fn create(engine: *v.em.Engine, core: c.JSValue, operations: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const imports = try s.object();
    const models_error = try s.get(core, "ModelsError");
    try s.put(imports, "ModelsError", models_error);
    inline for (.{ "getModelType", "isModelType", "assertChatModel", "assertImageModel", "assertClassifierModel", "assertClassifierInputSupported", "imageErrorResult", "classifierErrorResult" }) |name| try s.put(imports, name, try s.get(operations, name));
    const abort = try s.own(try @import("native_ai_auth_abort.zig").create(engine));
    inline for (.{ "operationSignal", "raceWithAbortSignal" }) |name| try s.put(imports, name, try s.get(abort, name));
    const resolver = try s.own(try @import("native_ai_auth_resolve.zig").create(engine, imports));
    inline for (.{ "resolveProviderAuth", "refreshStoredOAuthCredential" }) |name| try s.put(imports, name, try s.get(resolver, name));
    const lazy = try s.own(try @import("native_ai_lazy_api.zig").namespace(engine));
    try s.put(imports, "lazyStream", try s.get(lazy, "lazyStream"));
    const transcript = try s.own(try @import("native_ai_transcript_context.zig").exports(engine));
    try s.put(imports, "normalizeContext", try s.get(transcript, "normalizeContext"));
    const methods = try s.object();
    inline for (@typeInfo(queries.Kind).@"enum".fields) |field| try s.put(methods, field.name, try s.own(try queries.create(engine, @enumFromInt(field.value), models_error, operations)));
    inline for (@typeInfo(authentication.Kind).@"enum".fields) |field| try s.put(methods, field.name, try s.own(try authentication.create(engine, @enumFromInt(field.value), imports)));
    inline for (@typeInfo(refresh.Kind).@"enum".fields) |field| try s.put(methods, field.name, try s.own(try refresh.create(engine, @enumFromInt(field.value), imports)));
    inline for (@typeInfo(requests.Kind).@"enum".fields) |field| try s.put(methods, field.name, try s.own(try requests.create(engine, @enumFromInt(field.value), imports)));
    const DefaultContext = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return @import("native_ai_auth_helpers.zig").defaultProviderAuthContext(host);
        }
    };
    const constructor = try s.own(try @import("native_ai_models_class.zig").create(engine, .{
        .methods = methods,
        .credential_store_constructor = try s.get(core, "InMemoryCredentialStore"),
        .models_store_constructor = try s.get(core, "InMemoryModelsStore"),
        .default_auth_context = try s.own(try functions.create(engine, "defaultProviderAuthContext", 0, DefaultContext.call, &.{})),
    }));
    const Factory = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var supplied = [_]c.JSValue{if (args.len > 0) args[0] else c.pi_js_undefined()};
            return host.checked(c.JS_CallConstructor(host.context, roots[0], supplied.len, &supplied));
        }
    };
    return functions.create(engine, "createModels", 1, Factory.call, &.{constructor});
}
