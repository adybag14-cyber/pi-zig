//! Canonical compaction preparation over live projected entries and guest
//! operators. Private until genuine Source and ownership checks qualify it.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const projection = @import("native_sdk_session_projection_live.zig");
const files = @import("native_sdk_compaction_files.zig");
const c = em.c;
const Callback = enum(c_int) { cutRole, turnRole, tokenSum, candidate, visible, omitted, sourceId, source, external, omittedAssistant, invisible, previous, messages, nonSystem };
pub fn create(engine: *em.Engine) !c.JSValue {
    return @import("native_node_function.zig").create(engine, "prepareCompaction", 2, invoke, &.{});
}
fn invoke(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return prepare(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined());
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn at(scope: *Scope, value: c.JSValue, key: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, value, key));
}
fn binary(scope: *Scope, operation: arithmetic.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try arithmetic.binary(scope.engine, operation, left, right));
}
fn iterate(scope: *Scope, value: c.JSValue) !js.Iterator {
    const symbol = try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context)));
    return js.Iterator.init(scope.engine, value, symbol);
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
fn callback(scope: *Scope, kind: Callback, roots: []const c.JSValue) !c.JSValue {
    inline for (.{ Callback.cutRole, Callback.turnRole, Callback.messages }) |declared| {
        if (kind == declared) {
            const Adapter = struct {
                fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, saved: []const c.JSValue) !c.JSValue {
                    engine.native_exception_diagnostics_suppressed += 1;
                    defer engine.native_exception_diagnostics_suppressed -= 1;
                    return evaluate(engine, declared, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined(), @constCast(saved.ptr));
                }
            };
            const function_name = switch (declared) {
                .cutRole => "isCutPointMessage",
                .turnRole => "isTurnStartMessage",
                .messages => "getMessagesFromProjectedEntryForCompaction",
                else => unreachable,
            };
            const engine = scope.engine;
            if (engine.native_sdk_compaction_prepare_callbacks == null) engine.native_sdk_compaction_prepare_callbacks = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
            const cache = engine.native_sdk_compaction_prepare_callbacks.?;
            const existing = try scope.get(cache, function_name);
            if (!c.JS_IsUndefined(existing)) return existing;
            const function = try scope.own(try @import("native_node_function.zig").create(engine, function_name, 1, Adapter.call, roots));
            try scope.put(cache, function_name, function);
            return function;
        }
    }
    const name = switch (kind) {
        .visible => "isIntrinsicallyVisible",
        .omitted => "isOmitted",
        else => "",
    };
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, if (kind == .tokenSum) 2 else 1, @intFromEnum(kind), @intCast(roots.len), @constCast(roots.ptr))));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return evaluate(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), roots) catch |err| sdk.fail(engine, err);
}
fn role(engine: *em.Engine, value: c.JSValue, turn: bool) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const actual = try scope.get(value, "role");
    inline for (.{ "user", "bashExecution", "custom", "branchSummary", "compactionSummary" }) |name| if (try is(&scope, actual, name)) return true;
    return !turn and try is(&scope, actual, "assistant");
}
fn visible(engine: *em.Engine, entry: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try is(&scope, try scope.get(try scope.get(entry, "sourceEntry"), "type"), "context_edit")) return false;
    const messages = try scope.own(try projection.entryMessages(engine, try scope.get(entry, "sourceEntry")));
    return scope.positive(try scope.get(messages, "length"));
}
fn omitted(engine: *em.Engine, entry: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return try visible(engine, entry) and scope.equal(try scope.get(try scope.get(entry, "messages"), "length"), c.JS_NewInt32(engine.context, 0));
}
fn evaluate(engine: *em.Engine, kind: Callback, first: c.JSValue, second: c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const truth = switch (kind) {
        .cutRole => try role(engine, first, false),
        .turnRole => try role(engine, first, true),
        .tokenSum => return arithmetic.binary(engine, .add, first, try scope.own(try @import("native_sdk_compaction_estimate.zig").estimateTokens(engine, second))),
        .candidate => try arithmetic.compare(engine, .greater_equal, first, roots[0]),
        .visible => try visible(engine, first),
        .omitted => try omitted(engine, first),
        .sourceId => return js.get(engine, try scope.get(first, "sourceEntry"), "id"),
        .source => return js.get(engine, first, "sourceEntry"),
        .external => blk: {
            if (!try is(&scope, try scope.get(try scope.get(first, "sourceEntry"), "type"), "context_edit")) break :blk false;
            if (c.JS_IsNull(try scope.get(try scope.get(first, "sourceEntry"), "replacement"))) break :blk false;
            const has = try scope.get(roots[0], "has");
            break :blk !scope.truthy(try scope.call(has, roots[0], &.{try scope.get(try scope.get(first, "sourceEntry"), "targetId")}));
        },
        .omittedAssistant => try is(&scope, try scope.get(try scope.get(first, "sourceEntry"), "type"), "message") and try is(&scope, try scope.get(try scope.get(try scope.get(first, "sourceEntry"), "message"), "role"), "assistant") and try omitted(engine, first),
        .invisible => !try is(&scope, try scope.get(try scope.get(first, "sourceEntry"), "type"), "compaction") and (!try visible(engine, first) or try omitted(engine, first)),
        .previous => try is(&scope, try scope.get(try scope.get(first, "sourceEntry"), "type"), "compaction") and try scope.positive(try scope.get(try scope.get(first, "messages"), "length")),
        .nonSystem => !try is(&scope, try scope.get(first, "role"), "system"),
        .messages => {
            if (try is(&scope, try scope.get(try scope.get(first, "sourceEntry"), "type"), "compaction")) return sdk.array(engine);
            const messages = try scope.get(first, "messages");
            const filter = try scope.get(messages, "filter");
            return js.call(engine, filter, messages, &.{try callback(&scope, .nonSystem, &.{})});
        },
    };
    return c.pi_js_bool(engine.context, @intFromBool(truth));
}
fn someRole(scope: *Scope, entry: c.JSValue, turn: bool) !bool {
    if (try is(scope, try scope.get(try scope.get(entry, "sourceEntry"), "type"), "compaction")) return false;
    const messages = try scope.get(entry, "messages");
    const some = try scope.get(messages, "some");
    return scope.truthy(try scope.call(some, messages, &.{try callback(scope, if (turn) .turnRole else .cutRole, &.{})}));
}
const Cut = struct { first: c.JSValue, turn_start: c.JSValue, split: bool };
fn cutPoint(scope: *Scope, entries: c.JSValue, start: c.JSValue, end: c.JSValue, keep: c.JSValue) !Cut {
    const engine = scope.engine;
    const points = try scope.array();
    var cursor = start;
    var steps: usize = 0;
    while (try arithmetic.compare(engine, .less, cursor, end)) {
        steps +|= 1;
        try budget(engine, steps);
        var step: Scope = .{ .engine = engine };
        defer step.deinit();
        if (try someRole(&step, try at(&step, entries, cursor), false)) _ = try step.invoke(points, "push", &.{cursor});
        cursor = try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, cursor)));
    }
    if (scope.equal(try scope.get(points, "length"), c.JS_NewInt32(engine.context, 0))) return .{ .first = start, .turn_start = c.JS_NewInt32(engine.context, -1), .split = false };
    var accumulated = c.JS_NewInt32(engine.context, 0);
    var exceeded = false;
    var cut = try at(scope, points, c.JS_NewInt32(engine.context, 0));
    cursor = try binary(scope, .subtract, end, c.JS_NewInt32(engine.context, 1));
    while (try arithmetic.compare(engine, .greater_equal, cursor, start)) {
        steps +|= 1;
        try budget(engine, steps);
        var step: Scope = .{ .engine = engine };
        defer step.deinit();
        const messages = try step.get(try at(&step, entries, cursor), "messages");
        const reduce = try step.get(messages, "reduce");
        const tokens = try step.call(reduce, messages, &.{ try callback(&step, .tokenSum, &.{}), c.JS_NewInt32(engine.context, 0) });
        if (!step.equal(tokens, c.JS_NewInt32(engine.context, 0))) {
            accumulated = try scope.concat(accumulated, tokens);
            if (try arithmetic.compare(engine, .greater_equal, accumulated, keep)) {
                exceeded = true;
                const find = try step.get(points, "find");
                cut = try scope.own(try js.call(engine, find, points, &.{try callback(&step, .candidate, &.{cursor})}));
                if (c.JS_IsNull(cut) or c.JS_IsUndefined(cut)) cut = try at(scope, points, try binary(scope, .subtract, try scope.get(points, "length"), c.JS_NewInt32(engine.context, 1)));
                break;
            }
        }
        cursor = try scope.own(try engine.checked(c.JS_PiDecrement(engine.context, cursor)));
    }
    const slice = try scope.get(entries, "slice");
    const suffix = try scope.call(slice, entries, &.{ try scope.concat(cut, c.JS_NewInt32(engine.context, 1)), end });
    const set_constructor = try scope.global("Set");
    const filter = try scope.get(suffix, "filter");
    const omitted_entries = try scope.call(filter, suffix, &.{try callback(scope, .omitted, &.{})});
    const map = try scope.get(omitted_entries, "map");
    const omitted_ids = try scope.call(map, omitted_entries, &.{try callback(scope, .sourceId, &.{})});
    const ids = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, set_constructor, 1, @constCast(&[_]c.JSValue{omitted_ids}))));
    const external_some = try scope.get(suffix, "some");
    const external = try scope.call(external_some, suffix, &.{try callback(scope, .external, &.{ids})});
    if (exceeded and !scope.truthy(external)) {
        const assistant_some = try scope.get(suffix, "some");
        if (scope.truthy(try scope.call(assistant_some, suffix, &.{try callback(scope, .omittedAssistant, &.{})}))) {
            const every = try scope.get(suffix, "every");
            if (scope.truthy(try scope.call(every, suffix, &.{try callback(scope, .invisible, &.{})}))) cut = try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, cut)));
        }
    }
    while (try arithmetic.compare(engine, .greater, cut, start)) {
        steps +|= 1;
        try budget(engine, steps);
        var step: Scope = .{ .engine = engine };
        defer step.deinit();
        const previous = try at(&step, entries, try binary(&step, .subtract, cut, c.JS_NewInt32(engine.context, 1)));
        if (try is(&step, try step.get(try step.get(previous, "sourceEntry"), "type"), "compaction") or try step.positive(try step.get(try step.get(previous, "messages"), "length"))) break;
        cut = try scope.own(try engine.checked(c.JS_PiDecrement(engine.context, cut)));
    }
    const starts = try someRole(scope, try at(scope, entries, cut), true);
    var turn_start = c.JS_NewInt32(engine.context, -1);
    if (!starts) {
        cursor = cut;
        while (try arithmetic.compare(engine, .greater_equal, cursor, start)) {
            steps +|= 1;
            try budget(engine, steps);
            var step: Scope = .{ .engine = engine };
            defer step.deinit();
            if (try someRole(&step, try at(&step, entries, cursor), true)) {
                turn_start = cursor;
                break;
            }
            cursor = try scope.own(try engine.checked(c.JS_PiDecrement(engine.context, cursor)));
        }
    }
    return .{ .first = cut, .turn_start = turn_start, .split = !starts and !scope.equal(turn_start, c.JS_NewInt32(engine.context, -1)) };
}
fn messageSlice(scope: *Scope, entries: c.JSValue, start: c.JSValue, end: c.JSValue) !c.JSValue {
    const sliced = try scope.invoke(entries, "slice", &.{ start, end });
    const flat_map = try scope.get(sliced, "flatMap");
    return scope.call(flat_map, sliced, &.{try callback(scope, .messages, &.{})});
}
fn extractOperations(engine: *em.Engine, messages: c.JSValue, entries: c.JSValue, previous_index: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const operations = try scope.own(try files.create(engine));
    if (try arithmetic.compare(engine, .greater_equal, previous_index, c.JS_NewInt32(engine.context, 0))) {
        const previous = try at(&scope, entries, previous_index);
        if (!scope.truthy(try scope.get(previous, "fromHook")) and scope.truthy(try scope.get(previous, "details"))) {
            const details = try scope.get(previous, "details");
            inline for (.{ .{ "readFiles", "read" }, .{ "modifiedFiles", "edited" } }) |field| {
                const array = try scope.global("Array");
                const is_array = try scope.get(array, "isArray");
                if (scope.truthy(try scope.call(is_array, array, &.{try scope.get(details, field[0])}))) {
                    var names = try iterate(&scope, try scope.get(details, field[0]));
                    defer names.deinit();
                    errdefer names.closePreserving();
                    while (try names.next()) |name| {
                        defer engine.freeValue(name);
                        var step: Scope = .{ .engine = engine };
                        defer step.deinit();
                        _ = try step.invoke(try step.get(operations, field[1]), "add", &.{name});
                    }
                }
            }
        }
    }
    var rows = try iterate(&scope, messages);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |message| {
        defer engine.freeValue(message);
        try files.extract(engine, message, operations);
    }
    return c.JS_DupValue(engine.context, operations);
}
pub fn prepare(engine: *em.Engine, path_entries: c.JSValue, settings: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try scope.positive(try scope.get(path_entries, "length"))) {
        const last = try at(&scope, path_entries, try binary(&scope, .subtract, try scope.get(path_entries, "length"), c.JS_NewInt32(engine.context, 1)));
        if (try is(&scope, try scope.get(last, "type"), "compaction")) return c.pi_js_undefined();
    }
    const projected = try scope.own(try projection.projection(engine, path_entries, c.pi_js_undefined(), c.pi_js_undefined()));
    const entries = try scope.get(projected, "entries");
    const map = try scope.get(entries, "map");
    const source_entries = try scope.call(map, entries, &.{try callback(&scope, .source, &.{})});
    const find = try scope.get(entries, "findIndex");
    const previous = try scope.call(find, entries, &.{try callback(&scope, .previous, &.{})});
    var previous_summary = c.pi_js_undefined();
    var start = c.JS_NewInt32(engine.context, 0);
    if (try arithmetic.compare(engine, .greater_equal, previous, c.JS_NewInt32(engine.context, 0))) {
        previous_summary = try scope.get(try scope.get(try at(&scope, entries, previous), "sourceEntry"), "summary");
        start = try scope.concat(previous, c.JS_NewInt32(engine.context, 1));
    }
    const end = try scope.get(entries, "length");
    const estimate = try scope.own(try @import("native_sdk_session_estimate.zig").estimate(engine, projected, path_entries));
    const tokens_before = try scope.get(estimate, "tokens");
    const cut = try cutPoint(&scope, entries, start, end, try scope.get(settings, "keepRecentTokens"));
    const kept_projected = try at(&scope, entries, cut.first);
    const kept = if (@import("native_sdk_prompt_scope.zig").nullish(kept_projected)) c.pi_js_undefined() else try scope.get(kept_projected, "sourceEntry");
    if (@import("native_sdk_prompt_scope.zig").nullish(kept) or !scope.truthy(try scope.get(kept, "id"))) return c.pi_js_undefined();
    const kept_id = try scope.get(kept, "id");
    const history_end = if (cut.split) cut.turn_start else cut.first;
    const messages = try messageSlice(&scope, entries, start, history_end);
    const prefix = if (cut.split) try messageSlice(&scope, entries, cut.turn_start, cut.first) else try scope.array();
    if (scope.equal(try scope.get(messages, "length"), c.JS_NewInt32(engine.context, 0)) and scope.equal(try scope.get(prefix, "length"), c.JS_NewInt32(engine.context, 0))) return c.pi_js_undefined();
    const operations = try scope.own(try extractOperations(engine, messages, source_entries, previous));
    if (cut.split) {
        var rows = try iterate(&scope, prefix);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |message| {
            defer engine.freeValue(message);
            try files.extract(engine, message, operations);
        }
    }
    const result = try scope.object();
    try scope.put(result, "firstKeptEntryId", kept_id);
    try scope.put(result, "messagesToSummarize", messages);
    try scope.put(result, "turnPrefixMessages", prefix);
    try scope.put(result, "isSplitTurn", c.pi_js_bool(engine.context, @intFromBool(cut.split)));
    try scope.put(result, "tokensBefore", tokens_before);
    try scope.put(result, "previousSummary", previous_summary);
    try scope.put(result, "fileOps", operations);
    try scope.put(result, "settings", settings);
    return c.JS_DupValue(engine.context, result);
}
