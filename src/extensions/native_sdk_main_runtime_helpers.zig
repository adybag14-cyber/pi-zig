//! Complete original 4954 Main buildSessionOptions and resolveCliPaths.
//! This private callable projection retains genuine imported owners. It is not
//! a Main namespace or runtimeFactory; production assembly is owned by Auth.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const Engine = h.Engine;
const Scope = h.Scope;
const sync = @import("native_sync_arguments.zig");
const Arguments = sync.Arguments;
const Frame = @import("native_public_lexical_frame.zig").Frame(enum {
    options, diagnostics, cli_thinking_from_model, resolved,
    saved_provider, saved_model_id, saved_model, saved_in_scope,
});
const cache_key = "pi-private:actual-sdk-main-runtime-helpers";
const cli_key = "pi-private:actual-sdk-main-cli-bindings";
const Creating = struct { engine: *Engine, previous: ?*Creating };
threadlocal var creating: ?*Creating = null;

pub fn create(engine: *Engine, path_utilities: c.JSValue) anyerror!c.JSValue {
    try engine.checkNativeEntry();
    const actual = engine.native_module_values.get("pi-private:actual-sdk-path-utilities") orelse
        return error.RequiredActualMainPathUtilities;
    if (!c.JS_IsStrictEqual(engine.context, actual, path_utilities))
        return error.ActualMainPathUtilitiesChanged;
    if (engine.native_module_values.get(cache_key)) |cached|
        return h.expression(engine, cachedBody, .{cached, path_utilities});
    var cursor = creating;
    while (cursor) |current| : (cursor = current.previous)
        if (current.engine == engine) return error.ActualMainHelpersCreationReentry;
    var entry: Creating = .{ .engine = engine, .previous = creating };
    creating = &entry;
    defer creating = entry.previous;
    const candidate = try h.expression(engine, createBody, .{path_utilities});
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate); return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, candidate);
    return h.expression(engine, cachedBody, .{candidate, path_utilities});
}
fn cachedBody(s: *Scope, owner: c.JSValue, paths: c.JSValue) !c.JSValue {
    if (!v.equal(s, try v.get(s, owner, "paths"), paths))
        return error.ActualMainPathUtilitiesChanged;
    return v.duplicate(s, try v.get(s, owner, "exports"));
}
/// Canonical genuine callable imports reused by this Main evaluation. This
/// native supplier does not claim the separate original printHelp publication.
pub fn cliBindings(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cli_key)) |cached| return h.duplicate(engine, cached);
    // Retain the actual existing CLI callable owner once for this evaluation.
    // Its missing printHelp publication is not invented by this private entry.
    const candidate = try @import("native_public_cli_args.zig").create(engine);
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate); return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cli_key, candidate);
    return h.duplicate(engine, candidate);
}
fn createBody(s: *Scope, path_utilities: c.JSValue) !c.JSValue {
    const paths = try v.own(s, v.duplicate(s, path_utilities));
    const models = try v.own(s, try @import("native_ai_model_values.zig").bindings(s.engine));
    const models_equal = try v.get(s, models, "modelsAreEqual");
    const cli = try v.own(s, try cliBindings(s.engine));
    const thinking = try v.get(s, cli, "isValidThinkingLevel");
    // The complete original map successor is a required source prerequisite.
    // The existing resolver receives only this genuine retained CLI import.
    const resolver = try v.own(s, try @import("native_sdk_public_model_resolver.zig").create(
        s.engine, .{ .thinking = thinking }));
    const resolve_cli_model = try v.get(s, resolver, "resolveCliModel");
    const is_local_path = try v.get(s, paths, "isLocalPath");
    const resolve_path = try v.get(s, paths, "resolvePath");
    const exports = try v.object(s);
    try v.put(s, exports, "buildSessionOptions", try function(s, "buildSessionOptions", 5,
        .{ .formal_count = 5, .callback = buildCall, .hooks = sync.frameHooks(Frame) },
        &.{models_equal, resolve_cli_model}));
    try v.put(s, exports, "resolveCliPaths", try function(s, "resolveCliPaths", 2,
        .{ .formal_count = 2, .callback = pathsCall }, &.{is_local_path, resolve_path}));
    const owner = try v.object(s);
    try v.put(s, owner, "paths", paths);
    try v.put(s, owner, "models", models);
    try v.put(s, owner, "cli", cli);
    try v.put(s, owner, "resolver", resolver);
    try v.put(s, owner, "exports", exports);
    return v.duplicate(s, owner);
}
fn function(s: *Scope, name: [*:0]const u8, length: c_int, definition: sync.Definition, roots: []const c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, v.function.createWithArguments(s.engine, name, length, definition, roots));
}
fn arrow(s: *Scope, definition: sync.Definition, roots: []const c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, v.function.createArrowWithArguments(s.engine, "", 1, definition, roots));
}
fn newObject(s: *Scope) !c.JSValue { return v.duplicate(s, try v.object(s)); }
fn fieldTruthy(engine: *Engine, target: c.JSValue, field: [*:0]const u8) !bool {
    return h.fieldTest(engine, target, field, .truthy);
}
fn positiveLength(s: *Scope, value: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try h.binary(s, .greater, try v.get(s, value, "length"), v.number(s, 0))));
}
fn lengthPositive(engine: *Engine, value: c.JSValue) !bool {
    return h.truthy(engine, try h.expression(engine, positiveLength, .{value}));
}
fn assignField(s: *Scope, target: c.JSValue, field: [*:0]const u8, source: c.JSValue, source_field: [*:0]const u8) !void {
    try v.set(s, target, field, try v.get(s, source, source_field));
}
fn assignFirst(s: *Scope, target: c.JSValue, field: [*:0]const u8, values: c.JSValue) !void {
    try v.set(s, target, field, try v.get(s, try v.at(s, values, 0), field));
}
fn firstThinking(s: *Scope, values: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.get(s, try v.at(s, values, 0), "thinkingLevel")));
}
fn providerString(s: *Scope, parsed: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, try v.get(s, parsed, "provider")));
}
fn providerMessage(s: *Scope, parsed: c.JSValue) !c.JSValue {
    const prefix = try v.text(s, "--provider requires --model (for example: --provider ");
    const provider = try v.own(s, try h.expression(s.engine, providerString, .{parsed}));
    const start = try h.binary(s, .add, prefix, provider);
    return v.duplicate(s, try h.binary(s, .add, start, try v.text(s, " --model <pattern>)")));
}
fn missingModelDiagnostic(s: *Scope, diagnostics: c.JSValue, parsed: c.JSValue) !void {
    const push = try v.get(s, diagnostics, "push");
    const row = try v.object(s);
    try v.put(s, row, "type", try v.text(s, "error"));
    try v.put(s, row, "message", try v.own(s, try h.expression(s.engine, providerMessage, .{parsed})));
    _ = try v.call(s, push, diagnostics, &.{row});
}
fn resolvedDiagnostic(s: *Scope, diagnostics: c.JSValue, resolved: c.JSValue, kind: [*:0]const u8) !void {
    const push = try v.get(s, diagnostics, "push");
    const row = try v.object(s);
    try v.put(s, row, "type", try v.text(s, std.mem.span(kind)));
    try v.put(s, row, "message", try v.get(s, resolved, kind));
    _ = try v.call(s, push, diagnostics, &.{row});
}
const std = @import("std");
fn inlineKey(s: *Scope, parsed: c.JSValue) !c.JSValue {
    const boolean = try v.global(s, "Boolean");
    return v.duplicate(s, try v.call(s, boolean, c.pi_js_undefined(), &.{try v.get(s, parsed, "apiKey")}));
}
fn resolveCli(s: *Scope, callable: c.JSValue, parsed: c.JSValue, runtime: c.JSValue) !c.JSValue {
    const options = try v.object(s);
    try v.put(s, options, "cliProvider", try v.get(s, parsed, "provider"));
    try v.put(s, options, "cliModel", try v.get(s, parsed, "model"));
    try v.put(s, options, "cliThinking", try v.get(s, parsed, "thinking"));
    try v.put(s, options, "inlineApiKey", try v.own(s, try h.expression(s.engine, inlineKey, .{parsed})));
    try v.put(s, options, "modelRuntime", runtime);
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{options}));
}
fn savedModel(s: *Scope, runtime: c.JSValue, provider: c.JSValue, model_id: c.JSValue) !c.JSValue {
    if (!v.truthy(s, provider) or !v.truthy(s, model_id)) return c.pi_js_undefined();
    const callable = try v.get(s, runtime, "getModel");
    return v.duplicate(s, try v.call(s, callable, runtime, &.{provider, model_id}));
}
fn equalModel(s: *Scope, incoming: c.JSValue, saved_cell: c.JSValue, callable: c.JSValue) !c.JSValue {
    const model = try v.get(s, incoming, "model");
    const saved = try Frame.read(s, saved_cell);
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{model, saved}));
}
fn equalCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, equalModel, .{args.get(0), roots[0], roots[1]});
}
fn findSaved(s: *Scope, frame: *Frame, scoped: c.JSValue, equal: c.JSValue) !c.JSValue {
    if (!v.truthy(s, frame.get(.saved_model))) return c.pi_js_undefined();
    const callable = try v.get(s, scoped, "find");
    const cell = try frame.capture(s, .saved_model, "savedModel");
    const callback = try arrow(s, .{ .formal_count = 1, .callback = equalCall }, &.{cell, equal});
    return v.duplicate(s, try v.call(s, callable, scoped, &.{callback}));
}
fn selectScoped(frame: *Frame, args: *Arguments, equal: c.JSValue) !void {
    const engine = frame.engine;
    try frame.take(.saved_provider, v.invokeOwned(engine, args.get(4), "getDefaultProvider", &.{}));
    try frame.take(.saved_model_id, v.invokeOwned(engine, args.get(4), "getDefaultModel", &.{}));
    try frame.take(.saved_model, h.expression(engine, savedModel, .{args.get(3), frame.get(.saved_provider), frame.get(.saved_model_id)}));
    try frame.take(.saved_in_scope, h.expression(engine, findSaved, .{frame, args.get(1), equal}));
    if (h.truthy(engine, frame.get(.saved_in_scope))) {
        try h.statement(engine, assignField, .{frame.get(.options), @as([*:0]const u8, "model"), frame.get(.saved_in_scope), @as([*:0]const u8, "model")});
        if (!try fieldTruthy(engine, args.get(0), "thinking") and try fieldTruthy(engine, frame.get(.saved_in_scope), "thinkingLevel"))
            try h.statement(engine, assignField, .{frame.get(.options), @as([*:0]const u8, "thinkingLevel"), frame.get(.saved_in_scope), @as([*:0]const u8, "thinkingLevel")});
    } else {
        try h.statement(engine, assignFirst, .{frame.get(.options), @as([*:0]const u8, "model"), args.get(1)});
        if (!try fieldTruthy(engine, args.get(0), "thinking") and h.truthy(engine, try h.expression(engine, firstThinking, .{args.get(1)})))
            try h.statement(engine, assignFirst, .{frame.get(.options), @as([*:0]const u8, "thinkingLevel"), args.get(1)});
    }
}
fn mappedModel(s: *Scope, incoming: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "model", try v.get(s, incoming, "model"));
    try v.put(s, result, "thinkingLevel", try v.get(s, incoming, "thinkingLevel"));
    return v.duplicate(s, result);
}
fn mapCall(engine: *Engine, _: c.JSValue, args: *Arguments, _: []const c.JSValue) !c.JSValue {
    return h.expression(engine, mappedModel, .{args.get(0)});
}
fn assignScope(s: *Scope, target: c.JSValue, scoped: c.JSValue) !void {
    const callable = try v.get(s, scoped, "map");
    const callback = try arrow(s, .{ .formal_count = 1, .callback = mapCall }, &.{});
    try v.set(s, target, "scopedModels", try v.call(s, callable, scoped, &.{callback}));
}
fn assignText(s: *Scope, target: c.JSValue, field: [*:0]const u8, text: []const u8) !void {
    try v.set(s, target, field, try v.text(s, text));
}
fn spreadField(s: *Scope, parsed: c.JSValue, field: [*:0]const u8) !c.JSValue {
    const output = try v.array(s);
    const iterable = try v.get(s, parsed, field);
    var position: u32 = 0;
    // Reuse the VM's real OP_append implementation, including its two iterator
    // property Gets, fast-array branch and close-on-step-failure semantics.
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    try boundary.finishStatus(c.JS_PiArrayAppend(s.engine.context, output, &position, iterable));
    return v.duplicate(s, output);
}
fn assignSpread(s: *Scope, target: c.JSValue, parsed: c.JSValue, field: [*:0]const u8) !void {
    const output = try v.own(s, try h.expression(s.engine, spreadField, .{parsed, field}));
    try v.set(s, target, field, output);
}
fn buildResult(s: *Scope, frame: *Frame) !c.JSValue {
    const output = try v.object(s);
    try v.put(s, output, "options", frame.get(.options));
    try v.put(s, output, "cliThinkingFromModel", frame.get(.cli_thinking_from_model));
    try v.put(s, output, "diagnostics", frame.get(.diagnostics));
    return v.duplicate(s, output);
}
fn buildBody(s: *Scope, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    const engine = s.engine;
    const frame = try args.createFrame(s, Frame);
    try frame.take(.options, h.expression(engine, newObject, .{}));
    try frame.take(.diagnostics, h.array(engine));
    try frame.take(.cli_thinking_from_model, c.JS_NewBool(engine.context, false));
    if (try fieldTruthy(engine, args.get(0), "provider") and !try fieldTruthy(engine, args.get(0), "model"))
        try h.statement(engine, missingModelDiagnostic, .{frame.get(.diagnostics), args.get(0)});
    if (try fieldTruthy(engine, args.get(0), "model")) {
        try frame.take(.resolved, h.expression(engine, resolveCli, .{roots[1], args.get(0), args.get(3)}));
        if (try fieldTruthy(engine, frame.get(.resolved), "warning"))
            try h.statement(engine, resolvedDiagnostic, .{frame.get(.diagnostics), frame.get(.resolved), @as([*:0]const u8, "warning")});
        if (try fieldTruthy(engine, frame.get(.resolved), "error"))
            try h.statement(engine, resolvedDiagnostic, .{frame.get(.diagnostics), frame.get(.resolved), @as([*:0]const u8, "error")});
        if (try fieldTruthy(engine, frame.get(.resolved), "model")) {
            try h.statement(engine, assignField, .{frame.get(.options), @as([*:0]const u8, "model"), frame.get(.resolved), @as([*:0]const u8, "model")});
            if (!try fieldTruthy(engine, args.get(0), "thinking") and try fieldTruthy(engine, frame.get(.resolved), "thinkingLevel")) {
                try h.statement(engine, assignField, .{frame.get(.options), @as([*:0]const u8, "thinkingLevel"), frame.get(.resolved), @as([*:0]const u8, "thinkingLevel")});
                try frame.take(.cli_thinking_from_model, c.JS_NewBool(engine.context, true));
            }
        }
    }
    if (!try fieldTruthy(engine, frame.get(.options), "model") and
        try lengthPositive(engine, args.get(1)) and !h.truthy(engine, args.get(2))) {
        var completion = v.owned.Completion.initVoid(engine, selectScoped(frame, args, roots[0]));
        // This captured block-local closes at the original if-block exit.
        // Its uncaptured slot remains until ordinary function-local retirement.
        frame.detach(.saved_model, &completion);
        try completion.finishVoid();
    }
    if (try fieldTruthy(engine, args.get(0), "thinking"))
        try h.statement(engine, assignField, .{frame.get(.options), @as([*:0]const u8, "thinkingLevel"), args.get(0), @as([*:0]const u8, "thinking")});
    if (try lengthPositive(engine, args.get(1)))
        try h.statement(engine, assignScope, .{frame.get(.options), args.get(1)});
    if (try fieldTruthy(engine, args.get(0), "noTools")) {
        try h.statement(engine, assignText, .{frame.get(.options), @as([*:0]const u8, "noTools"), @as([]const u8, "all")});
    } else if (try fieldTruthy(engine, args.get(0), "noBuiltinTools")) {
        try h.statement(engine, assignText, .{frame.get(.options), @as([*:0]const u8, "noTools"), @as([]const u8, "builtin")});
    }
    if (try fieldTruthy(engine, args.get(0), "tools"))
        try h.statement(engine, assignSpread, .{frame.get(.options), args.get(0), @as([*:0]const u8, "tools")});
    if (try fieldTruthy(engine, args.get(0), "excludeTools"))
        try h.statement(engine, assignSpread, .{frame.get(.options), args.get(0), @as([*:0]const u8, "excludeTools")});
    return h.expression(engine, buildResult, .{frame});
}
fn buildCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, buildBody, .{args, roots});
}
fn localPath(s: *Scope, value: c.JSValue, predicate: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.call(s, predicate, c.pi_js_undefined(), &.{value})));
}
fn resolvePathValue(s: *Scope, value: c.JSValue, cwd_cell: c.JSValue, callable: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{value, try sync.read(s, cwd_cell)}));
}
fn pathCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    if (h.truthy(engine, try h.expression(engine, localPath, .{args.get(0), roots[1]})))
        return h.expression(engine, resolvePathValue, .{args.get(0), roots[0], roots[2]});
    return h.duplicate(engine, args.get(0));
}
fn pathsBody(s: *Scope, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    const paths = args.get(1);
    if (v.nullish(paths)) return c.pi_js_undefined();
    const callable = try v.get(s, paths, "map");
    const cwd_cell = try args.capture(s, 0);
    const callback = try arrow(s, .{ .formal_count = 1, .callback = pathCall }, &.{cwd_cell, roots[0], roots[1]});
    return v.duplicate(s, try v.call(s, callable, paths, &.{callback}));
}
fn pathsCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, pathsBody, .{args, roots});
}
