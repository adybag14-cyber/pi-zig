//! Prepared genuine application-composition checks. No test backend/bootstrap
//! or substitute namespaces are created here; the owner supplies the real one.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const application = @import("extensions/native_sdk_application_assembly.zig");
const c = em.c;

pub fn verifyActualAiIdentity(engine: *em.Engine) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const first = try s.own(try @import("extensions/native_sdk_ai_imports.zig").create(engine));
    c.JS_RunGC(engine.runtime);
    const second = try s.own(try @import("extensions/native_sdk_ai_imports.zig").create(engine));
    try std.testing.expect(s.equal(first, second));
    const ai = try s.get(first, "ai");
    const models = try s.own(try @import("extensions/native_ai_models_namespace.zig").create(engine));
    const operations = try s.own(try @import("extensions/native_ai_models_namespace.zig").operations(engine));
    inline for (.{ "createModels", "createProvider", "ModelsError", "clampThinkingLevel" }) |name|
        try std.testing.expect(s.equal(try s.get(ai, name), try s.get(models, name)));
    inline for (.{ "assertChatModel", "assertImageModel", "assertClassifierModel", "assertClassifierInputSupported", "imageErrorResult", "classifierErrorResult" }) |name|
        try std.testing.expect(s.equal(try s.get(ai, name), try s.get(operations, name)));
    const transcript = try s.own(try @import("extensions/native_ai_transcript_context.zig").exports(engine));
    try std.testing.expect(s.equal(try s.get(ai, "normalizeContext"), try s.get(transcript, "normalizeContext")));
    const factories = try s.get(first, "providerFactories");
    const compat = try s.own(try @import("extensions/native_ai_compat.zig").namespace(engine, try s.get(factories, "builtinModels")));
    try std.testing.expect(s.equal(compat, try s.get(first, "compat")));
    const held = try s.get(first, "compat");
    try std.testing.expect(s.equal(try s.get(held, "resetApiProviders"), try s.get(compat, "resetApiProviders")));
}

/// Full unchanged Source27 cases, including failures; never narrow the rows or
/// author native expected data. Actual class/loader/Agent gates stay separate.
pub fn compareFullFactorySource(engine: *em.Engine, inputs: application.Inputs, original_reference: []const u8) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const graph = try s.own(try application.create(engine, inputs));
    return @import("native_sdk_factory_production_test.zig").compareActualSourceCases(engine, try s.get(graph, "exports"), original_reference);
}
