//! Original session-manager projections over live guest values. This component
//! is private until its Source comparisons and consumer regressions qualify it.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
const GuestCallback = *const fn (?*c.JSContext, c.JSValue, c_int, [*c]c.JSValue, c_int, [*c]c.JSValue) callconv(.c) c.JSValue;
const Kind = enum { edit, project, flatten };
const Export = enum { buildContextEntries, buildSessionProjection, buildSessionContext, sessionEntryToContextMessages };
pub fn exports(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    inline for (std.meta.fields(Export)) |field| {
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                var input = [_]c.JSValue{c.pi_js_undefined()} ** 3;
                for (args[0..@min(args.len, input.len)], 0..) |value, index| input[index] = value;
                switch (@as(Export, @enumFromInt(field.value))) {
                    .buildContextEntries => return contextEntries(host, input[0], input[1], input[2]),
                    .sessionEntryToContextMessages => return entryMessages(host, input[0]),
                    .buildSessionProjection => return projection(host, input[0], input[1], input[2]),
                    .buildSessionContext => {
                        var local: Scope = .{ .engine = host };
                        defer local.deinit();
                        const projected = try local.own(try projection(host, input[0], input[1], input[2]));
                        const context = try local.object();
                        inline for (.{ "messages", "thinkingLevel", "model" }) |name| try local.put(context, name, try local.get(projected, name));
                        return c.JS_DupValue(host.context, context);
                    },
                }
            }
        };
        try scope.put(result, field.name, try scope.own(try @import("native_node_function.zig").create(engine, field.name, if (field.value == 3) 1 else 3, Adapter.call, &.{})));
    }
    return c.JS_DupValue(engine.context, result);
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn iterate(scope: *Scope, value: c.JSValue) !js.Iterator {
    const symbol = try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context)));
    return js.Iterator.init(scope.engine, value, symbol);
}
fn at(scope: *Scope, value: c.JSValue, key: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, value, key));
}
fn budget(engine: *em.Engine, steps: usize) !void {
    if (engine.cancelled.load(.acquire) or (steps % 256 == 0 and blk: {
        engine.interrupts +|= 1;
        break :blk engine.interrupts > engine.options.interrupt_budget;
    })) {
        _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
        unreachable;
    }
}
fn dataFunction(scope: *Scope, callback: GuestCallback, length: c_int, roots: []const c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, "", length, 0, @intCast(roots.len), @constCast(roots.ptr))));
}
pub fn path(engine: *em.Engine, entries: c.JSValue, leaf_id: c.JSValue, supplied: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const index = if (scope.truthy(supplied)) supplied else try scope.own(try js.builtin(engine, "Map", &.{}));
    if (!scope.truthy(supplied)) {
        var rows = try iterate(&scope, entries);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |entry| {
            defer engine.freeValue(entry);
            var step: Scope = .{ .engine = engine };
            defer step.deinit();
            const set = try step.get(index, "set");
            _ = try step.call(set, index, &.{ try step.get(entry, "id"), entry });
        }
    }
    if (c.JS_IsNull(leaf_id)) return sdk.array(engine);
    var leaf = if (scope.truthy(leaf_id)) try scope.invoke(index, "get", &.{leaf_id}) else c.pi_js_undefined();
    if (c.JS_IsNull(leaf) or c.JS_IsUndefined(leaf)) {
        const last = try scope.own(try arithmetic.binary(engine, .subtract, try scope.get(entries, "length"), c.JS_NewInt32(engine.context, 1)));
        leaf = try at(&scope, entries, last);
    }
    if (!scope.truthy(leaf)) return sdk.array(engine);
    const result = try scope.array();
    var current = c.JS_DupValue(engine.context, leaf);
    defer engine.freeValue(current);
    var steps: usize = 0;
    while (scope.truthy(current)) {
        steps +|= 1;
        try budget(engine, steps);
        var step: Scope = .{ .engine = engine };
        defer step.deinit();
        _ = try step.invoke(result, "push", &.{current});
        var next = c.pi_js_undefined();
        if (step.truthy(try step.get(current, "parentId"))) {
            const get = try step.get(index, "get");
            next = try step.call(get, index, &.{try step.get(current, "parentId")});
        }
        const retained = c.JS_DupValue(engine.context, next);
        engine.freeValue(current);
        current = retained;
    }
    _ = try scope.invoke(result, "reverse", &.{});
    return c.JS_DupValue(engine.context, result);
}
fn sameCompaction(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const entry_id = scope.get(if (argc > 0) argv[0] else c.pi_js_undefined(), "id") catch |err| return sdk.fail(engine, err);
    const compaction_id = scope.get(roots[0], "id") catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(scope.equal(entry_id, compaction_id)));
}
pub fn contextEntries(engine: *em.Engine, entries: c.JSValue, leaf: c.JSValue, by_id: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const selected = try scope.own(try path(engine, entries, leaf, by_id));
    var compaction = c.pi_js_null();
    var rows = try iterate(&scope, selected);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer engine.freeValue(entry);
        var step: Scope = .{ .engine = engine };
        defer step.deinit();
        if (try is(&step, try step.get(entry, "type"), "compaction")) compaction = try scope.own(c.JS_DupValue(engine.context, entry));
    }
    if (!scope.truthy(compaction)) return c.JS_DupValue(engine.context, selected);
    const find = try scope.get(selected, "findIndex");
    const predicate = try dataFunction(&scope, sameCompaction, 1, &.{compaction});
    const compaction_index = try scope.call(find, selected, &.{predicate});
    if (try arithmetic.compare(engine, .less, compaction_index, c.JS_NewInt32(engine.context, 0))) return c.JS_DupValue(engine.context, selected);
    const result = try scope.array();
    try scope.index(result, 0, compaction);
    var found = false;
    var cursor = c.JS_NewInt32(engine.context, 0);
    var steps: usize = 0;
    while (try arithmetic.compare(engine, .less, cursor, compaction_index)) {
        steps +|= 1;
        try budget(engine, steps);
        var step: Scope = .{ .engine = engine };
        defer step.deinit();
        const entry = try at(&step, selected, cursor);
        if (step.equal(try step.get(entry, "id"), try step.get(compaction, "firstKeptEntryId"))) found = true;
        if (found and !(try is(&step, try step.get(entry, "type"), "message") and try is(&step, try step.get(try step.get(entry, "message"), "role"), "system"))) _ = try step.invoke(result, "push", &.{entry});
        cursor = try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, cursor)));
    }
    const push = try scope.get(result, "push");
    const slice = try scope.get(selected, "slice");
    const tail_start = try scope.concat(compaction_index, c.JS_NewInt32(engine.context, 1));
    const tail = try scope.call(slice, selected, &.{tail_start});
    var arguments: std.ArrayList(c.JSValue) = .empty;
    defer {
        for (arguments.items) |value| engine.freeValue(value);
        arguments.deinit(engine.gpa);
    }
    var tail_rows = try iterate(&scope, tail);
    defer tail_rows.deinit();
    errdefer tail_rows.closePreserving();
    while (try tail_rows.next()) |entry| {
        arguments.append(engine.gpa, entry) catch |err| {
            engine.freeValue(entry);
            return err;
        };
    }
    _ = try scope.call(push, result, arguments.items);
    return c.JS_DupValue(engine.context, result);
}
pub fn entryMessages(engine: *em.Engine, entry: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.array();
    if (try is(&scope, try scope.get(entry, "type"), "message")) {
        const message = try scope.get(entry, "message");
        const system_empty = try is(&scope, try scope.get(message, "role"), "system") and @import("native_sdk_prompt_scope.zig").nullish(try scope.get(message, "content"));
        if (system_empty) {
            const copy = try scope.own(try js.spread(engine, message));
            try scope.put(copy, "content", try scope.text(""));
            try scope.index(result, 0, copy);
            return c.JS_DupValue(engine.context, result);
        }
        const empty = (try is(&scope, try scope.get(message, "role"), "user") or try is(&scope, try scope.get(message, "role"), "assistant") or try is(&scope, try scope.get(message, "role"), "toolResult")) and @import("native_sdk_prompt_scope.zig").nullish(try scope.get(message, "content"));
        if (empty) {
            const copy = try scope.own(try js.spread(engine, message));
            try scope.put(copy, "content", try scope.array());
            try scope.index(result, 0, copy);
        } else try scope.index(result, 0, message);
        return c.JS_DupValue(engine.context, result);
    }
    if (try is(&scope, try scope.get(entry, "type"), "custom_message")) {
        const custom_type = try scope.get(entry, "customType");
        var content = try scope.get(entry, "content");
        if (@import("native_sdk_prompt_scope.zig").nullish(content)) content = try scope.array();
        const display = try scope.get(entry, "display");
        const details = try scope.get(entry, "details");
        const stamp = try scope.get(entry, "timestamp");
        const message = try scope.object();
        try scope.put(message, "role", try scope.text("custom"));
        try scope.put(message, "customType", custom_type);
        try scope.put(message, "content", content);
        try scope.put(message, "display", display);
        try scope.put(message, "details", details);
        try scope.put(message, "timestamp", try scope.own(try @import("native_sdk_session_projection.zig").dateTime(engine, stamp)));
        try scope.index(result, 0, message);
        return c.JS_DupValue(engine.context, result);
    }
    if (try is(&scope, try scope.get(entry, "type"), "branch_summary") and scope.truthy(try scope.get(entry, "summary"))) {
        const summary = try scope.get(entry, "summary");
        const from = try scope.get(entry, "fromId");
        const stamp = try scope.get(entry, "timestamp");
        const message = try scope.object();
        try scope.put(message, "role", try scope.text("branchSummary"));
        try scope.put(message, "summary", summary);
        try scope.put(message, "fromId", from);
        try scope.put(message, "timestamp", try scope.own(try @import("native_sdk_session_projection.zig").dateTime(engine, stamp)));
        try scope.index(result, 0, message);
        return c.JS_DupValue(engine.context, result);
    }
    if (try is(&scope, try scope.get(entry, "type"), "compaction")) {
        const summary = try scope.get(entry, "summary");
        const tokens = try scope.get(entry, "tokensBefore");
        const stamp = try scope.get(entry, "timestamp");
        const message = try scope.object();
        try scope.put(message, "role", try scope.text("compactionSummary"));
        try scope.put(message, "summary", summary);
        try scope.put(message, "tokensBefore", tokens);
        try scope.put(message, "timestamp", try scope.own(try @import("native_sdk_session_projection.zig").dateTime(engine, stamp)));
        if (scope.truthy(try scope.get(entry, "systemMessage"))) {
            try scope.index(result, 0, try scope.get(entry, "systemMessage"));
            try scope.index(result, 1, message);
        } else try scope.index(result, 0, message);
    }
    return c.JS_DupValue(engine.context, result);
}
fn callbackResult(engine: *em.Engine, kind: Kind, argc: c_int, argv: [*c]c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = if (argc > 0) argv[0] else c.pi_js_undefined();
    switch (kind) {
        .flatten => return js.get(engine, value, "messages"),
        .project => {
            const result = try scope.object();
            try scope.put(result, "sourceEntry", value);
            var messages: c.JSValue = undefined;
            if (try is(&scope, try scope.get(value, "type"), "compaction") and try scope.positive(if (argc > 1) argv[1] else c.pi_js_undefined())) {
                messages = try scope.array();
            } else {
                const get = try scope.get(roots[0], "get");
                const edit = try scope.call(get, roots[0], &.{try scope.get(value, "id")});
                messages = try scope.own(try projectEntry(engine, value, edit));
            }
            try scope.put(result, "messages", messages);
            return c.JS_DupValue(engine.context, result);
        },
        .edit => {
            if (!try is(&scope, try scope.get(value, "role"), "user") and !try is(&scope, try scope.get(value, "role"), "assistant") and !try is(&scope, try scope.get(value, "role"), "toolResult") and !try is(&scope, try scope.get(value, "role"), "custom")) return c.JS_DupValue(engine.context, value);
            var content: c.JSValue = undefined;
            if ((try is(&scope, try scope.get(value, "role"), "assistant") or try is(&scope, try scope.get(value, "role"), "toolResult")) and c.JS_IsString(try scope.get(roots[0], "content"))) {
                content = try scope.array();
                const text = try scope.object();
                try scope.put(text, "type", try scope.text("text"));
                try scope.put(text, "text", try scope.get(roots[0], "content"));
                try scope.index(content, 0, text);
            } else content = try scope.get(roots[0], "content");
            const result = try scope.own(try js.spread(engine, value));
            try scope.put(result, "content", content);
            return c.JS_DupValue(engine.context, result);
        },
    }
}
fn mapper(comptime kind: Kind) GuestCallback {
    return struct {
        fn call(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
            const engine = em.Engine.fromContext(context.?);
            engine.native_exception_diagnostics_suppressed += 1;
            defer engine.native_exception_diagnostics_suppressed -= 1;
            return callbackResult(engine, kind, argc, argv, roots) catch |err| sdk.fail(engine, err);
        }
    }.call;
}
fn projectEntry(engine: *em.Engine, entry: c.JSValue, edit: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const messages = try scope.own(try entryMessages(engine, entry));
    if (!scope.truthy(edit)) return c.JS_DupValue(engine.context, messages);
    const replacement = try scope.get(edit, "replacement");
    if (c.JS_IsNull(replacement)) return sdk.array(engine);
    const map = try scope.get(messages, "map");
    const callback = try dataFunction(&scope, mapper(.edit), 1, &.{replacement});
    return js.call(engine, map, messages, &.{callback});
}
pub fn projection(engine: *em.Engine, entries: c.JSValue, leaf: c.JSValue, by_id: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const selected = try scope.own(try path(engine, entries, leaf, by_id));
    var thinking = try scope.text("off");
    var model = c.pi_js_null();
    var rows = try iterate(&scope, selected);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer engine.freeValue(entry);
        var step: Scope = .{ .engine = engine };
        defer step.deinit();
        if (try is(&step, try step.get(entry, "type"), "thinking_level_change")) {
            thinking = try scope.get(entry, "thinkingLevel");
        } else if (try is(&step, try step.get(entry, "type"), "model_change")) {
            model = try scope.object();
            try scope.put(model, "provider", try step.get(entry, "provider"));
            try scope.put(model, "modelId", try step.get(entry, "modelId"));
        } else if (try is(&step, try step.get(entry, "type"), "message") and try is(&step, try step.get(try step.get(entry, "message"), "role"), "assistant")) {
            model = try scope.object();
            try scope.put(model, "provider", try step.get(try step.get(entry, "message"), "provider"));
            try scope.put(model, "modelId", try step.get(try step.get(entry, "message"), "model"));
        }
    }
    const context = try scope.own(try contextEntries(engine, entries, leaf, by_id));
    const edits = try scope.own(try js.builtin(engine, "Map", &.{}));
    var context_rows = try iterate(&scope, context);
    defer context_rows.deinit();
    errdefer context_rows.closePreserving();
    while (try context_rows.next()) |entry| {
        defer engine.freeValue(entry);
        var step: Scope = .{ .engine = engine };
        defer step.deinit();
        if (try is(&step, try step.get(entry, "type"), "context_edit")) {
            const set = try step.get(edits, "set");
            _ = try step.call(set, edits, &.{ try step.get(entry, "targetId"), entry });
        }
    }
    const map = try scope.get(context, "map");
    const project = try dataFunction(&scope, mapper(.project), 2, &.{edits});
    const projected = try scope.call(map, context, &.{project});
    const result = try scope.object();
    try scope.put(result, "entries", projected);
    const flat_map = try scope.get(projected, "flatMap");
    const flatten = try dataFunction(&scope, mapper(.flatten), 1, &.{});
    try scope.put(result, "messages", try scope.call(flat_map, projected, &.{flatten}));
    try scope.put(result, "thinkingLevel", thinking);
    try scope.put(result, "model", model);
    return c.JS_DupValue(engine.context, result);
}
