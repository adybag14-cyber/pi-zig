//! Real c268 frontend/control comparison with the genuine native YAML import.
//! Source and native run in separate fresh Engines. Existing YAML grammar/
//! schema captures remain a separate dependency qualification.
const std = @import("std");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const fm = @import("extensions/native_sdk_frontmatter_values.zig");
const text = @import("extensions/native_sdk_text_helpers.zig");
const yaml = @import("extensions/native_sdk_yaml_values.zig");
const PromptScope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-frontmatter-public-observer.mjs");

fn publish(s: *h.Scope, name: [*:0]const u8, input: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, input);
}
fn legacyCall(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: PromptScope = .{ .engine = engine };
    return v.owned.finishValue(&scope, legacyBody(&scope, v.arg(args, 0), h.truthy(engine, roots[0])));
}
fn legacyBody(scope: *PromptScope, input: c.JSValue, bytes: bool) !c.JSValue {
    const parsed = if (bytes) value: {
        const raw = try scope.engine.toString(input);
        defer scope.engine.gpa.free(raw);
        break :value try fm.parse(scope, raw);
    } else try fm.parseValue(scope, input);
    return h.expression(scope.engine, legacyRecord, .{parsed});
}
fn legacyRecord(s: *h.Scope, parsed: fm.Result) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "frontmatter", parsed.frontmatter);
    try v.put(s, result, "body", parsed.body);
    return v.duplicate(s, result);
}
fn prepare(engine: *h.Engine) !void { return h.statement(engine, prepareBody, .{}); }
fn prepareBody(s: *h.Scope) !void {
    const engine = s.engine;
    const native = try v.own(s, try fm.exports(engine));
    const repeated = try v.own(s, try fm.exports(engine));
    try std.testing.expect(v.equal(s, native, repeated));
    try std.testing.expect(v.equal(s, try v.get(s, native, "parseFrontmatter"), try v.own(s, try fm.create(engine))));
    const original_text = try v.own(s, try text.create(engine));
    try std.testing.expect(v.equal(s, original_text, try v.own(s, try text.create(engine))));
    const model_text = try v.own(s, try @import("extensions/native_sdk_model_text_production.zig").create(engine));
    try std.testing.expect(v.equal(s, try v.get(s, original_text, "stripBom"), try v.get(s, model_text, "stripBom")));
    const parser = try v.own(s, try yaml.create(engine));
    const factory = try v.own(s, try engine.eval(
        @embedFile("extensions/fixtures/sdk-frontmatter-public-c268-source.mjs"),
        "actual-c268-frontmatter-factory.js", c.JS_EVAL_TYPE_GLOBAL));
    const reference = try v.call(s, factory, c.pi_js_undefined(), &.{parser});
    try publish(s, "frontmatterNative", native);
    try publish(s, "frontmatterNativeText", original_text);
    try publish(s, "frontmatterSource", reference);
    try publish(s, "frontmatterSourceText", try v.get(s, reference, "text"));
    try publish(s, "frontmatterLegacyValue", try v.ordinary(s, "actualLegacyFrontmatter", 1, legacyCall, &.{v.boolean(s, false)}));
    try publish(s, "frontmatterLegacyBytes", try v.ordinary(s, "actualLegacyFrontmatterBytes", 1, legacyCall, &.{v.boolean(s, true)}));
    try publish(s, "frontmatterHooks", try v.own(s, try retirement.createNativeRetirementHooks(engine)));
}
fn run(engine: *h.Engine, source: []const u8) !void {
    engine.freeValue(try engine.evalModule(source, "actual-sdk-frontmatter-control.mjs"));
}
fn clean(engine: *h.Engine) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn both(comptime name: []const u8, comptime extra: []const u8) !void {
    inline for (.{ .{ "frontmatterSource", "frontmatterSourceText" }, .{ "frontmatterNative", "frontmatterNativeText" } }) |subject| {
        const engine = try h.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
        defer engine.deinit(); try prepare(engine);
        try run(engine, observer ++ "\n" ++ name ++ "(" ++ subject[0] ++ "," ++ subject[1] ++ ",frontmatterHooks" ++ extra ++ ");\n");
        try clean(engine);
    }
}
fn recordBody(s: *h.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "frontmatterHooks"), "record"));
}
const FatalKind = enum { current, retirement, cancelled };
fn fatal(comptime name: []const u8, comptime extra: []const u8, comptime kind: FatalKind) !void {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit(); try prepare(engine);
    const original = try h.expression(engine, recordBody, .{});
    defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\n" ++ name ++
        "(frontmatterNative,frontmatterNativeText,frontmatterHooks" ++ extra ++ ");\n"));
    switch (kind) {
        .current => try retirement.verifyRecordedActualNativeFatal(engine, original),
        .retirement => try retirement.verifyActualRetirementFatal(engine, original, 0),
        .cancelled => try retirement.verifyActualCancellationNoGuestClose(engine, original),
    }
    try retirement.verifyNoVisits(original, .{1,2,3});
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK public frontmatter actual arrow text declaration and shared module identities" { try both("observeFrontmatterShapes", ""); }
test "SDK public frontmatter preserves normalized fences BOM and body branches" { try both("observeFrontmatterBasics", ""); }
test "SDK public frontmatter consumes the real native YAML value and alias graph" { try both("observeFrontmatterValues", ""); }
test "SDK public frontmatter evaluates fresh intrinsic regex literals after selected methods" { try both("observeFrontmatterLiterals", ""); }
test "SDK public frontmatter replace receiver callee and normalized owners retire in Source order" { try both("observeFrontmatterNormalizeRetirement", ""); }
test "SDK public frontmatter BOM predicate retires before the slice getter" { try both("observeFrontmatterBomPredicate", ""); }
test "SDK public frontmatter fence predicate retires before the indexOf getter" { try both("observeFrontmatterFencePredicate", ""); }
test "SDK public frontmatter fields preserve live slice selection raw body and end coercion" { try both("observeFrontmatterFieldOrder", ""); }
test "SDK public frontmatter strict end comparison avoids an extra coercion" { try both("observeFrontmatterStrictEnd", ""); }
test "SDK public frontmatter extract locals and trim temporaries retire before the genuine YAML constructor" { try both("observeFrontmatterExtractRetirement", ""); }
test "SDK public frontmatter and BOM literals define ordered own data fields" { try both("observeFrontmatterRecords", ""); }
test "SDK public frontmatter strip executes the actual YAML validation path" { try both("observeFrontmatterStripValidation", ""); }
test "SDK public frontmatter ordinary frontend and dependency private DATA retain exact identity" {
    try both("observeFrontmatterPrivateData", ",\"bom\"");
    try both("observeFrontmatterPrivateData", ",\"replace\"");
    try both("observeFrontmatterPrivateData", ",\"trim\"");
    try both("observeFrontmatterPrivateData", ",\"yaml\"");
}
test "SDK public frontmatter existing prompt and skill scopes use the same real parser" {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit(); try prepare(engine);
    try run(engine,
        \\for (const parse of [frontmatterNative.parseFrontmatter,frontmatterLegacyValue,frontmatterLegacyBytes]) {
        \\  const result = parse("---\nroot: &root {self: *root, value: 42}\ncopy: *root\n---\r\n body ");
        \\  if (result.body !== "body" || result.frontmatter.root.value !== 42 ||
        \\      result.frontmatter.root !== result.frontmatter.copy || result.frontmatter.root.self !== result.frontmatter.root)
        \\    throw new Error("actual original-scope parser graph");
        \\}
    );
    try clean(engine);
}
test "SDK public frontmatter actual indexOf fatal prevents later slice and guest catch" { try fatal("observeFrontmatterCurrentFatal", "", .current); }
test "SDK public frontmatter actual fence predicate retirement fatal precedes indexOf" { try fatal("observeFrontmatterPredicateFatal", ",false", .retirement); }
test "SDK public frontmatter actual trim receiver retirement fatal precedes YAML construction" { try fatal("observeFrontmatterTrimFatal", "", .retirement); }
test "SDK public frontmatter actual first replace callee fatal precedes the second getter" { try fatal("observeFrontmatterCalleeFatal", "", .retirement); }
test "SDK public frontmatter actual predicate cancellation prevents later guest work" { try fatal("observeFrontmatterPredicateFatal", ",true", .cancelled); }
