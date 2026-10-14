//! Source-only highlight.js10.7.3 compiler extension bodies.
//! Unimported/uncompiled; actual compiled-grammar reference cases are required.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const ordinary = @import("native_node_function.zig");
const regex = @import("native_highlight_regex.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub const Kind = enum { match, begin_keywords, illegal, relevance };

pub fn create(engine: *em.Engine, kind: Kind) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
            var numeric: i32 = 0;
            if (c.JS_ToInt32(host.context, &numeric, roots[0]) < 0) return js.capture(host);
            try apply(host, @enumFromInt(numeric), if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined());
            return c.pi_js_undefined();
        }
    };
    const name: [*:0]const u8 = switch (kind) {
        .match => "compileMatch",
        .begin_keywords => "beginKeywords",
        .illegal => "compileIllegal",
        .relevance => "compileRelevance",
    };
    return ordinary.create(engine, name, 2, Adapter.invoke, &.{c.JS_NewInt32(engine.context, @intFromEnum(kind))});
}

fn remove(engine: *em.Engine, value: c.JSValue, name: [*:0]const u8) !void {
    const atom = c.JS_NewAtom(engine.context, name);
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, value, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
}
fn sourceError(scope: *Scope, message: []const u8) !void {
    const constructor = try scope.global("Error");
    var args = [_]c.JSValue{try scope.text(message)};
    const reason = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
    _ = c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason));
    return js.capture(scope.engine);
}
fn skipDot(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const match = if (args.len > 0) args[0] else c.pi_js_undefined();
    const response = if (args.len > 1) args[1] else c.pi_js_undefined();
    const input = try scope.get(match, "input");
    const previous = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, try scope.get(match, "index"), c.JS_NewInt32(engine.context, 1))));
    const before = try scope.own(try js.getKey(engine, input, previous));
    if (scope.equal(before, try scope.text("."))) _ = try scope.invoke(response, "ignoreMatch", &.{});
    return c.pi_js_undefined();
}
fn skipFunction(scope: *Scope) !c.JSValue {
    const name = "pi-native:highlight-skip-preceding-dot";
    if (!scope.engine.native_module_values.contains(name)) {
        const exports = try scope.object();
        try scope.put(exports, "callback", try scope.own(try ordinary.create(scope.engine, "skipIfhasPrecedingDot", 2, skipDot, &.{})));
        try scope.engine.registerValueModule(name, exports);
    }
    return scope.get(scope.engine.native_module_values.get(name).?, "callback");
}
pub fn apply(engine: *em.Engine, kind: Kind, mode: c.JSValue, parent: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (kind) {
        .match => {
            if (!scope.truthy(try scope.get(mode, "match"))) return;
            if (scope.truthy(try scope.get(mode, "begin")) or scope.truthy(try scope.get(mode, "end"))) return sourceError(&scope, "begin & end are not supported with match");
            try scope.set(mode, "begin", try scope.get(mode, "match"));
            try remove(engine, mode, "match");
        },
        .begin_keywords => {
            if (!scope.truthy(parent) or !scope.truthy(try scope.get(mode, "beginKeywords"))) return;
            const list = try scope.invoke(try scope.get(mode, "beginKeywords"), "split", &.{try scope.text(" ")});
            const joined = try scope.invoke(list, "join", &.{try scope.text("|")});
            const start = try scope.concat(try scope.text("\\b("), joined);
            try scope.set(mode, "begin", try scope.concat(start, try scope.text(")(?!\\.)(?=\\b|\\s)")));
            try scope.set(mode, "__beforeBegin", try skipFunction(&scope));
            const keywords = try scope.get(mode, "keywords");
            try scope.set(mode, "keywords", if (scope.truthy(keywords)) keywords else try scope.get(mode, "beginKeywords"));
            try remove(engine, mode, "beginKeywords");
            if (c.JS_IsUndefined(try scope.get(mode, "relevance"))) try scope.set(mode, "relevance", c.JS_NewInt32(engine.context, 0));
        },
        .illegal => {
            const array = try scope.global("Array");
            const is_array = try scope.get(array, "isArray");
            if (!scope.truthy(try scope.call(is_array, array, &.{try scope.get(mode, "illegal")}))) return;
            const values = try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(engine, try scope.get(mode, "illegal"), null));
            try scope.set(mode, "illegal", try scope.own(try regex.either(engine, values)));
        },
        .relevance => if (c.JS_IsUndefined(try scope.get(mode, "relevance"))) {
            try scope.set(mode, "relevance", c.JS_NewInt32(engine.context, 1));
        },
    }
}
