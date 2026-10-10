//! Native ordered prompt section replay for Durable generation preparation.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Scope = struct {
    engine: *Engine,
    values: std.ArrayList(c.JSValue) = .empty,
    fn deinit(self: *Scope) void {
        for (self.values.items) |value| self.engine.freeValue(value);
        self.values.deinit(self.engine.gpa);
    }
    fn own(self: *Scope, value: c.JSValue) !c.JSValue {
        self.values.append(self.engine.gpa, value) catch |err| {
            self.engine.freeValue(value);
            return err;
        };
        return value;
    }
    fn get(self: *Scope, object: c.JSValue, key: [:0]const u8) !c.JSValue {
        return self.own(try vm.get(self.engine, object, key));
    }
    fn invoke(self: *Scope, object: c.JSValue, key: [:0]const u8, args: []const c.JSValue) !c.JSValue {
        return self.own(try vm.invoke(self.engine, object, key, args));
    }
    fn text(self: *Scope, bytes: []const u8) !c.JSValue {
        return self.own(try self.engine.checked(c.JS_NewStringLen(self.engine.context, bytes.ptr, bytes.len)));
    }
};
fn item(scope: *Scope, array: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, array, @intCast(index))));
}
fn equals(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return c.JS_IsStrictEqual(scope.engine.context, value, try scope.text(text));
}
pub fn replaySections(engine: *Engine, messages: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const constructor = try scope.own(try js.global(engine, "Map"));
    const shown = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
    errdefer engine.freeValue(shown);
    const object = try scope.own(try js.global(engine, "Object"));
    for (0..try vm.length(engine, messages)) |index| {
        const message = try item(&scope, messages, index);
        if (!try equals(&scope, try scope.get(message, "role"), "system")) continue;
        const sections = try scope.get(message, "sections");
        if (c.JS_IsUndefined(sections)) continue;
        const entries = try scope.invoke(object, "entries", &.{sections});
        for (0..try vm.length(engine, entries)) |position| {
            const pair = try item(&scope, entries, position);
            const key = try item(&scope, pair, 0);
            const value = try item(&scope, pair, 1);
            _ = try scope.invoke(shown, if (c.JS_IsNull(value)) "delete" else "set", if (c.JS_IsNull(value)) &.{key} else &.{ key, value });
        }
    }
    return shown;
}
fn arrayFrom(scope: *Scope, iterable: c.JSValue) !c.JSValue {
    const array = try scope.own(try js.global(scope.engine, "Array"));
    return scope.invoke(array, "from", &.{iterable});
}
fn mapEntries(scope: *Scope, map: c.JSValue) !c.JSValue {
    return arrayFrom(scope, try scope.invoke(map, "entries", &.{}));
}
fn has(scope: *Scope, map: c.JSValue, key: c.JSValue) !bool {
    return c.JS_ToBool(scope.engine.context, try scope.invoke(map, "has", &.{key})) != 0;
}
fn assign(engine: *Engine, object: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    const atom = c.JS_ValueToAtom(engine.context, key);
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_SetProperty(engine.context, object, atom, c.JS_DupValue(engine.context, value)) < 0) return js.capture(engine);
}
pub fn planSections(engine: *Engine, shown: c.JSValue, desired: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const offered = try mapEntries(&scope, shown);
    const wanted = try mapEntries(&scope, desired);
    const order = try scope.own(try vm.array(engine));
    for (0..try vm.length(engine, offered)) |index| {
        const pair = try item(&scope, offered, index);
        const key = try item(&scope, pair, 0);
        if (try has(&scope, desired, key)) try js.push(engine, order, key);
    }
    for (0..try vm.length(engine, wanted)) |index| {
        const pair = try item(&scope, wanted, index);
        const key = try item(&scope, pair, 0);
        if (!try has(&scope, shown, key)) try js.push(engine, order, key);
    }
    var reordered = false;
    for (0..try vm.length(engine, order)) |index| {
        const wanted_pair = try item(&scope, wanted, index);
        if (!c.JS_IsStrictEqual(engine.context, try item(&scope, order, index), try item(&scope, wanted_pair, 0))) {
            reordered = true;
            break;
        }
    }
    const patches = try vm.array(engine);
    errdefer engine.freeValue(patches);
    if (reordered) {
        const removed = try scope.own(try vm.object(engine));
        for (0..try vm.length(engine, offered)) |index| try assign(engine, removed, try item(&scope, try item(&scope, offered, index), 0), c.pi_js_null());
        try js.push(engine, patches, removed);
        const object = try scope.own(try js.global(engine, "Object"));
        const next = try scope.invoke(object, "fromEntries", &.{desired});
        try js.push(engine, patches, next);
        return patches;
    }
    const patch = try scope.own(try vm.object(engine));
    for (0..try vm.length(engine, offered)) |index| {
        const pair = try item(&scope, offered, index);
        const key = try item(&scope, pair, 0);
        const previous = try item(&scope, pair, 1);
        const next = try scope.invoke(desired, "get", &.{key});
        if (!c.JS_IsStrictEqual(engine.context, previous, next)) try assign(engine, patch, key, if (c.JS_IsUndefined(next) or c.JS_IsNull(next)) c.pi_js_null() else next);
    }
    for (0..try vm.length(engine, wanted)) |index| {
        const pair = try item(&scope, wanted, index);
        const key = try item(&scope, pair, 0);
        if (!try has(&scope, shown, key)) try assign(engine, patch, key, try item(&scope, pair, 1));
    }
    const object = try scope.own(try js.global(engine, "Object"));
    const keys = try scope.invoke(object, "keys", &.{patch});
    if (try vm.length(engine, keys) != 0) try js.push(engine, patches, patch);
    return patches;
}
fn put(engine: *Engine, object: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, object, key, c.JS_DupValue(engine.context, value));
}
pub fn toToolDeclaration(engine: *Engine, tool: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try put(engine, result, "name", try scope.get(tool, "name"));
    try put(engine, result, "description", try scope.get(tool, "description"));
    const object = try scope.own(try js.global(engine, "JSON"));
    const encoded = try scope.invoke(object, "stringify", &.{try scope.get(tool, "parameters")});
    const decoded = try scope.invoke(object, "parse", &.{encoded});
    try put(engine, result, "parameters", decoded);
    const sampling = try scope.get(tool, "constrainedSampling");
    if (!c.JS_IsUndefined(sampling)) try put(engine, result, "constrainedSampling", sampling);
    return result;
}
pub fn declarationsEqual(engine: *Engine, left: c.JSValue, right: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const object = try scope.own(try js.global(engine, "JSON"));
    const a = try scope.own(try toToolDeclaration(engine, left));
    const b = try scope.own(try toToolDeclaration(engine, right));
    return c.JS_IsStrictEqual(engine.context, try scope.invoke(object, "stringify", &.{a}), try scope.invoke(object, "stringify", &.{b}));
}
pub fn getCurrentTools(engine: *Engine, messages: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const constructor = try scope.own(try js.global(engine, "Map"));
    const tools = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
    for (0..try vm.length(engine, messages)) |index| {
        const message = try item(&scope, messages, index);
        if (!try equals(&scope, try scope.get(message, "role"), "system")) continue;
        inline for (.{ "toolsRemoved", "toolsAdded" }) |key| {
            const list = try scope.get(message, key);
            if (!c.JS_IsUndefined(list) and !c.JS_IsNull(list)) {
                for (0..try vm.length(engine, list)) |position| {
                    const tool = try item(&scope, list, position);
                    const name = try scope.get(tool, "name");
                    _ = try scope.invoke(tools, if (comptime std.mem.eql(u8, key, "toolsRemoved")) "delete" else "set", if (comptime std.mem.eql(u8, key, "toolsRemoved")) &.{name} else &.{ name, tool });
                }
            }
        }
    }
    return c.JS_DupValue(engine.context, try arrayFrom(&scope, try scope.invoke(tools, "values", &.{})));
}
pub fn planTools(engine: *Engine, offered: c.JSValue, desired: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const constructor = try scope.own(try js.global(engine, "Map"));
    const wanted = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
    for (0..try vm.length(engine, desired)) |index| {
        const tool = try item(&scope, desired, index);
        _ = try scope.invoke(wanted, "set", &.{ try scope.get(tool, "name"), tool });
    }
    const kept = try scope.own(try vm.array(engine));
    const kept_names = try scope.own(try vm.array(engine));
    for (0..try vm.length(engine, offered)) |index| {
        const tool = try item(&scope, offered, index);
        const name = try scope.get(tool, "name");
        const next = try scope.invoke(wanted, "get", &.{name});
        if (!c.JS_IsUndefined(next) and try declarationsEqual(engine, tool, next)) {
            try js.push(engine, kept, tool);
            try js.push(engine, kept_names, name);
        }
    }
    const added = try scope.own(try vm.array(engine));
    for (0..try vm.length(engine, desired)) |index| {
        const tool = try item(&scope, desired, index);
        const included = try scope.invoke(kept_names, "includes", &.{try scope.get(tool, "name")});
        if (c.JS_ToBool(engine.context, included) == 0) try js.push(engine, added, tool);
    }
    const replayed = try scope.invoke(kept, "concat", &.{added});
    var reordered = false;
    for (0..try vm.length(engine, replayed)) |index| {
        const left = try item(&scope, replayed, index);
        const right = try item(&scope, desired, index);
        if (!c.JS_IsStrictEqual(engine.context, try scope.get(left, "name"), try scope.get(right, "name"))) {
            reordered = true;
            break;
        }
    }
    const removed = try scope.own(try vm.array(engine));
    for (0..try vm.length(engine, offered)) |index| {
        const tool = try item(&scope, offered, index);
        const name = try scope.get(tool, "name");
        const included = try scope.invoke(kept_names, "includes", &.{name});
        if (reordered or c.JS_ToBool(engine.context, included) == 0) {
            const reference = try scope.own(try vm.object(engine));
            try put(engine, reference, "name", name);
            try js.push(engine, removed, reference);
        }
    }
    const additions = try scope.own(try vm.array(engine));
    const selected = if (reordered) desired else added;
    for (0..try vm.length(engine, selected)) |index| {
        const declaration = try scope.own(try toToolDeclaration(engine, try item(&scope, selected, index)));
        try js.push(engine, additions, declaration);
    }
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try put(engine, result, "toolsRemoved", removed);
    try put(engine, result, "toolsAdded", additions);
    return result;
}
fn systemEntry(scope: *Scope, sections: c.JSValue, tools: c.JSValue, timestamp: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const message = try scope.own(try vm.object(engine));
    try put(engine, message, "role", try scope.text("system"));
    try put(engine, message, "content", try scope.text(""));
    if (!c.JS_IsUndefined(sections)) try put(engine, message, "sections", sections);
    if (!c.JS_IsUndefined(tools)) {
        inline for (.{ "toolsRemoved", "toolsAdded" }) |key| {
            const values = try scope.get(tools, key);
            if (try vm.length(engine, values) > 0) try put(engine, message, key, values);
        }
    }
    try put(engine, message, "timestamp", timestamp);
    const model = try scope.own(try vm.array(engine));
    try js.push(engine, model, message);
    const entry = try vm.object(engine);
    errdefer engine.freeValue(entry);
    try put(engine, entry, "model", model);
    return entry;
}
pub fn planSystemEntries(engine: *Engine, view: c.JSValue, desired: c.JSValue, tools: c.JSValue, timestamp: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const entries = try scope.get(view, "entries");
    const head = try scope.get(view, "head");
    var baseline = !c.JS_IsUndefined(head);
    if (baseline) {
        var head_id: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &head_id, try scope.get(head, "id")) < 0) return js.capture(engine);
        for (0..try vm.length(engine, entries)) |index| {
            const entry = try item(&scope, entries, index);
            if (!try equals(&scope, try scope.get(entry, "kind"), "pi.system")) continue;
            var id: f64 = 0;
            if (c.JS_ToFloat64(engine.context, &id, try scope.get(entry, "id")) < 0) return js.capture(engine);
            if (id > head_id) {
                baseline = false;
                break;
            }
        }
    }
    const planned = try vm.array(engine);
    errdefer engine.freeValue(planned);
    if (baseline) {
        const edits = try scope.own(try vm.array(engine));
        for (0..try vm.length(engine, entries)) |index| {
            const entry = try item(&scope, entries, index);
            if (!try equals(&scope, try scope.get(entry, "kind"), "pi.system")) continue;
            const edit = try scope.own(try vm.object(engine));
            try put(engine, edit, "target", try scope.get(entry, "id"));
            try put(engine, edit, "action", try scope.text("omit"));
            try js.push(engine, edits, edit);
        }
        const object = try scope.own(try js.global(engine, "Object"));
        const sections = try scope.invoke(object, "fromEntries", &.{desired});
        const changes = try scope.own(try vm.object(engine));
        try @import("native_tool_info.zig").putData(engine, changes, "toolsRemoved", try vm.array(engine));
        const additions = try scope.own(try vm.array(engine));
        for (0..try vm.length(engine, tools)) |index| {
            const declaration = try scope.own(try toToolDeclaration(engine, try item(&scope, tools, index)));
            try js.push(engine, additions, declaration);
        }
        try put(engine, changes, "toolsAdded", additions);
        const entry = try scope.own(try systemEntry(&scope, sections, changes, timestamp));
        if (try vm.length(engine, edits) > 0) try put(engine, entry, "edits", edits);
        try js.push(engine, planned, entry);
        return planned;
    }
    const messages = try scope.get(view, "messages");
    const shown = try scope.own(try replaySections(engine, messages));
    const sections = try scope.own(try planSections(engine, shown, desired));
    const offered = try scope.own(try getCurrentTools(engine, messages));
    const changes = try scope.own(try planTools(engine, offered, tools));
    const removed = try scope.get(changes, "toolsRemoved");
    const added = try scope.get(changes, "toolsAdded");
    const has_changes = try vm.length(engine, removed) > 0 or try vm.length(engine, added) > 0;
    const count = try vm.length(engine, sections);
    if (count == 0 and has_changes) {
        const entry = try scope.own(try systemEntry(&scope, c.pi_js_undefined(), changes, timestamp));
        try js.push(engine, planned, entry);
        return planned;
    }
    for (0..count) |index| {
        const patch = try item(&scope, sections, index);
        const entry = try scope.own(try systemEntry(&scope, patch, if (has_changes and index + 1 == count) changes else c.pi_js_undefined(), timestamp));
        try js.push(engine, planned, entry);
    }
    return planned;
}
const awaiting = @import("native_durable_await.zig");
pub fn renderSections(engine: *Engine, captured: *awaiting.Intrinsics, sections: c.JSValue, input: c.JSValue, shown: c.JSValue, report: c.JSValue, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "promiseConstructor", captured.constructor }, .{ "promiseResolve", captured.resolve }, .{ "promiseThen", captured.then_function }, .{ "sections", sections }, .{ "input", input }, .{ "shown", shown }, .{ "report", report }, .{ "context", context } }) |field| try put(engine, state, field[0], field[1]);
    const constructor = try scope.own(try js.global(engine, "Map"));
    try @import("native_tool_info.zig").putData(engine, state, "desired", try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
    try put(engine, state, "index", c.JS_NewInt32(engine.context, 0));
    return renderNext(engine, state);
}
fn renderWait(engine: *Engine, state: c.JSValue, pending: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var captured: awaiting.Intrinsics = .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
    return awaiting.continueWith(renderReady, engine, &captured, state, pending, 0);
}
fn renderNext(engine: *Engine, state: c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const index_value = try scope.get(state, "index");
    var index: u32 = 0;
    if (c.JS_ToUint32(engine.context, &index, index_value) < 0) return js.capture(engine);
    const sections = try scope.get(state, "sections");
    if (index >= try vm.length(engine, sections)) return vm.get(engine, state, "desired");
    const section = try item(&scope, sections, index);
    try put(engine, state, "section", section);
    try put(engine, state, "index", c.JS_NewUint32(engine.context, index + 1));
    const pending = scope.invoke(section, "render", &.{ try scope.get(state, "input"), try scope.get(state, "context") }) catch |err| {
        if (err != error.JavaScriptException) return err;
        const exception = engine.captured_exception orelse return err;
        return renderReady(engine, state, exception, true, 0);
    };
    return renderWait(engine, state, pending);
}
fn renderReady(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const section = try scope.get(state, "section");
    const key = try scope.get(section, "key");
    const desired = try scope.get(state, "desired");
    if (rejected) {
        const context = try scope.get(state, "context");
        const signal = try scope.get(context, "abortSignal");
        if (!c.JS_IsUndefined(signal) and !c.JS_IsNull(signal) and c.JS_ToBool(engine.context, try scope.get(signal, "aborted")) != 0) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
        const report = try scope.get(state, "report");
        var args = [_]c.JSValue{value};
        const ignored = try scope.own(try engine.checked(c.JS_Call(engine.context, report, c.pi_js_undefined(), 1, &args)));
        _ = ignored;
        const kept = try scope.invoke(try scope.get(state, "shown"), "get", &.{key});
        if (!c.JS_IsUndefined(kept)) _ = try scope.invoke(desired, "set", &.{ key, kept });
        return renderNext(engine, state);
    }
    if (!c.JS_IsUndefined(value)) {
        const tag = try scope.get(section, "tag");
        const text = if (c.JS_IsStrictEqual(engine.context, tag, c.pi_js_bool(engine.context, 0))) value else try scope.own(try @import("native_utf16.zig").concat(engine, &.{ try scope.text("<"), key, try scope.text(">\n"), value, try scope.text("\n</"), key, try scope.text(">") }));
        _ = try scope.invoke(desired, "set", &.{ key, text });
    }
    return renderNext(engine, state);
}
