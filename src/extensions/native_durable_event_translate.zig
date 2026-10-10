//! Ordered agent event batches derived from one durable publication.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const progress = @import("native_durable_event_progress.zig");
const Scope = @import("native_durable_view_mount.zig").Scope;
const c = engine_mod.c;
const Engine = engine_mod.Engine;
fn put(scope: *Scope, object: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(scope.engine, object, key, c.JS_DupValue(scope.engine.context, value));
}
fn same(scope: *Scope, left: c.JSValue, right: c.JSValue) bool {
    return c.JS_IsStrictEqual(scope.engine.context, left, right);
}
fn is(scope: *Scope, value: c.JSValue, bytes: []const u8) !bool {
    return same(scope, value, try scope.text(bytes));
}
fn get(scope: *Scope, object: c.JSValue, key: [:0]const u8) !c.JSValue {
    return if (c.JS_IsUndefined(object) or c.JS_IsNull(object)) c.pi_js_undefined() else scope.get(object, key);
}
fn array(scope: *Scope, value: c.JSValue) !c.JSValue {
    return if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) scope.array(&.{}) else value;
}
fn objectOrDefault(scope: *Scope, value: c.JSValue) !c.JSValue {
    return if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) scope.own(try vm.object(scope.engine)) else value;
}
fn add(scope: *Scope, events: c.JSValue, kind: []const u8) !c.JSValue {
    const result = try scope.own(try vm.object(scope.engine));
    try put(scope, result, "type", try scope.text(kind));
    try js.push(scope.engine, events, result);
    return result;
}
fn find(scope: *Scope, values: c.JSValue, key: [:0]const u8, wanted: c.JSValue) !c.JSValue {
    for (0..try vm.length(scope.engine, values)) |index| {
        const value = try scope.item(values, index);
        if (same(scope, try get(scope, value, key), wanted)) return value;
    }
    return c.pi_js_undefined();
}
fn by(scope: *Scope, values: c.JSValue, key: [:0]const u8) !c.JSValue {
    const result = try scope.own(try js.builtin(scope.engine, "Map", &.{}));
    for (0..try vm.length(scope.engine, values)) |index| {
        const value = try scope.item(values, index);
        _ = try scope.invoke(result, "set", &.{ try get(scope, value, key), value });
    }
    return result;
}
fn mapValues(scope: *Scope, map: c.JSValue) !c.JSValue {
    const iterator = try scope.invoke(map, "values", &.{});
    const symbol = try scope.get(try scope.own(try js.global(scope.engine, "Symbol")), "iterator");
    return scope.own(try js.collect(scope.engine, iterator, symbol));
}
fn queued(scope: *Scope, inbox: c.JSValue) !c.JSValue {
    const items = try array(scope, try get(scope, inbox, "items"));
    const result = try scope.array(&.{});
    for (0..try vm.length(scope.engine, items)) |index| {
        const item = try scope.item(items, index);
        const next = try scope.own(try vm.object(scope.engine));
        try put(scope, next, "id", try get(scope, item, "id"));
        try put(scope, next, "mode", try get(scope, item, "mode"));
        try js.push(scope.engine, result, next);
    }
    return result;
}
fn initialUsage(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsUndefined(value) and !c.JS_IsNull(value)) return value;
    const result = try scope.own(try vm.object(scope.engine));
    try put(scope, result, "models", try objectOrDefault(scope, c.pi_js_undefined()));
    try put(scope, result, "tools", try objectOrDefault(scope, c.pi_js_undefined()));
    return result;
}
pub fn snapshotOf(engine: *Engine, view: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try vm.object(engine));
    try put(&scope, result, "type", try scope.text("snapshot"));
    try put(&scope, result, "entries", try get(&scope, view, "entries"));
    const docs = try get(&scope, view, "docs");
    const live = try objectOrDefault(&scope, try get(&scope, docs, "pi.live"));
    const run = try get(&scope, live, "run");
    if (!c.JS_IsUndefined(run)) {
        const current = try objectOrDefault(&scope, c.pi_js_undefined());
        try put(&scope, current, "inputs", try get(&scope, run, "inputs"));
        try put(&scope, result, "run", current);
    }
    const generation = try get(&scope, live, "generation");
    if (!c.JS_IsUndefined(generation)) try put(&scope, result, "generation", generation);
    inline for (.{ "tools", "nestedTools", "compactions" }) |key| try put(&scope, result, key, try array(&scope, try get(&scope, live, key)));
    try put(&scope, result, "inbox", try queued(&scope, try get(&scope, docs, "pi.inbox")));
    try put(&scope, result, "agent", try objectOrDefault(&scope, try get(&scope, docs, "pi.agent")));
    try put(&scope, result, "usage", try initialUsage(&scope, try get(&scope, docs, "pi.usage")));
    return c.JS_DupValue(engine.context, result);
}
fn callEvent(scope: *Scope, events: c.JSValue, kind: []const u8, slot: c.JSValue) !c.JSValue {
    const result = try add(scope, events, kind);
    const fields = try scope.own(try progress.callOf(scope.engine, slot));
    const keys = try scope.invoke(try scope.own(try js.global(scope.engine, "Object")), "keys", &.{fields});
    for (0..try vm.length(scope.engine, keys)) |index| {
        const key = try scope.item(keys, index);
        try js.setKey(scope.engine, result, key, try scope.own(try js.getKey(scope.engine, fields, key)));
    }
    return result;
}
fn copyFields(scope: *Scope, target: c.JSValue, source: c.JSValue) !void {
    const keys = try scope.invoke(try scope.own(try js.global(scope.engine, "Object")), "keys", &.{source});
    for (0..try vm.length(scope.engine, keys)) |index| {
        const key = try scope.item(keys, index);
        try js.setKey(scope.engine, target, key, try scope.own(try js.getKey(scope.engine, source, key)));
    }
}
fn nested(scope: *Scope, slot: c.JSValue) !bool {
    const key = try scope.text("parentCallId");
    const atom = c.JS_ValueToAtom(scope.engine.context, key);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    const has = c.JS_HasProperty(scope.engine.context, slot, atom);
    if (has < 0) return js.capture(scope.engine);
    return has != 0;
}
fn endTool(scope: *Scope, ends: c.JSValue, entries: c.JSValue, slot: c.JSValue, id: c.JSValue) !void {
    const next = try callEvent(scope, ends, "tool_execution_end", slot);
    const entry = try find(scope, entries, "id", id);
    if (!c.JS_IsUndefined(entry)) try put(scope, next, "entry", entry);
}
fn endNested(scope: *Scope, events: c.JSValue, results: c.JSValue, slot: c.JSValue) !void {
    const next = try callEvent(scope, events, "tool_execution_end", slot);
    const string = try scope.own(try js.global(scope.engine, "String"));
    const key = try scope.own(try js.call(scope.engine, string, c.pi_js_undefined(), &.{try get(scope, slot, "taskId")}));
    const result = try scope.invoke(results, "get", &.{key});
    if (!c.JS_IsUndefined(result)) try put(scope, next, "result", result);
}
fn resultOf(scope: *Scope, entries: c.JSValue, id: c.JSValue) !c.JSValue {
    for (0..try vm.length(scope.engine, entries)) |index| {
        const entry = try scope.item(entries, index);
        const model = try get(scope, entry, "model");
        if (c.JS_IsUndefined(model) or c.JS_IsNull(model)) continue;
        const message = try scope.item(model, 0);
        if (try is(scope, try get(scope, message, "role"), "toolResult") and same(scope, try get(scope, message, "toolCallId"), id)) return entry;
    }
    return c.pi_js_undefined();
}
fn compare(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (argc < 2) return c.JS_ThrowInternalError(context, "Missing event submission records");
    const left = vm.get(engine, argv[0], "id") catch return engine.throwCaptured();
    defer engine.freeValue(left);
    const right = vm.get(engine, argv[1], "id") catch return engine.throwCaptured();
    defer engine.freeValue(right);
    var a: f64 = 0;
    var b: f64 = 0;
    if (c.JS_ToFloat64(context, &a, left) < 0 or c.JS_ToFloat64(context, &b, right) < 0) return c.JS_ThrowInternalError(context, "Invalid event submission ID");
    return c.JS_NewFloat64(context, a - b);
}
pub fn translate(engine: *Engine, conversation: c.JSValue, before: c.JSValue, after: c.JSValue, operations: c.JSValue, publication: c.JSValue, held: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const entries = try scope.array(&.{});
    const tasks = try scope.own(try js.builtin(engine, "Map", &.{}));
    const submissions = try scope.array(&.{});
    const results = try scope.own(try js.builtin(engine, "Map", &.{}));
    const changes = try get(&scope, publication, "changes");
    for (0..try vm.length(engine, changes)) |index| {
        const change = try scope.item(changes, index);
        const kind = try get(&scope, change, "type");
        const value = try get(&scope, change, "value");
        if (try is(&scope, kind, "document")) {
            const record = try get(&scope, change, "record");
            const key = try get(&scope, record, "key");
            if (try is(&scope, try get(&scope, record, "kind"), "pi.tool.nested-result") and !c.JS_IsUndefined(key) and !c.JS_IsNull(value) and same(&scope, try get(&scope, change, "conversationId"), conversation)) _ = try scope.invoke(results, "set", &.{ key, try get(&scope, value, "result") });
        }
        if (!same(&scope, try get(&scope, value, "conversationId"), conversation)) continue;
        if (try is(&scope, kind, "entry")) try js.push(engine, entries, value);
        if (try is(&scope, kind, "task")) _ = try scope.invoke(tasks, "set", &.{ try get(&scope, value, "id"), value });
        if (try is(&scope, kind, "submission")) try js.push(engine, submissions, value);
    }
    const events = try scope.array(&.{});
    if (try vm.length(engine, operations) == 0 and try vm.length(engine, entries) == 0 and try @import("native_durable.zig").number(engine, try get(&scope, tasks, "size")) == 0 and try vm.length(engine, submissions) == 0) return c.JS_DupValue(engine.context, events);
    const comparator = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, compare, "", 2)));
    _ = try scope.invoke(submissions, "sort", &.{comparator});
    const was_docs = try get(&scope, before, "docs");
    const now_docs = try get(&scope, after, "docs");
    const was = try objectOrDefault(&scope, try get(&scope, was_docs, "pi.live"));
    const now = try objectOrDefault(&scope, try get(&scope, now_docs, "pi.live"));
    const old_slots = try by(&scope, try array(&scope, try get(&scope, was, "tools")), "callId");
    const old_nested = try by(&scope, try array(&scope, try get(&scope, was, "nestedTools")), "taskId");
    const slots = try array(&scope, try get(&scope, now, "tools"));
    const nested_slots = try array(&scope, try get(&scope, now, "nestedTools"));
    const all_slots = try scope.invoke(slots, "concat", &.{nested_slots});
    for (0..try vm.length(engine, all_slots)) |index| {
        const slot = try scope.item(all_slots, index);
        const is_nested = try nested(&scope, slot);
        const previous = try scope.invoke(if (is_nested) old_nested else old_slots, "get", &.{try get(&scope, slot, if (is_nested) "taskId" else "callId")});
        if (!try is(&scope, try get(&scope, slot, "status"), "running") or try is(&scope, try get(&scope, previous, "status"), "running")) continue;
        const task = try scope.invoke(tasks, "get", &.{try get(&scope, slot, "taskId")});
        const arguments = if (is_nested) try get(&scope, slot, "arguments") else try objectOrDefault(&scope, try get(&scope, try get(&scope, try get(&scope, task, "state"), "checkpoint"), "arguments"));
        try put(&scope, try callEvent(&scope, events, "tool_execution_start", slot), "args", arguments);
    }
    const generation_before = try get(&scope, was, "generation");
    const generation = try get(&scope, now, "generation");
    const partial_before = try get(&scope, generation_before, "message");
    const partial = try get(&scope, generation, "message");
    if (!c.JS_IsUndefined(partial) and c.JS_IsUndefined(partial_before)) {
        try put(&scope, try add(&scope, events, "message_start"), "message", partial);
    } else if (!c.JS_IsUndefined(partial) and !same(&scope, partial, partial_before)) {
        const next = try add(&scope, events, "message_update");
        try put(&scope, next, "usage", try get(&scope, partial, "usage"));
        try put(&scope, next, "changes", try scope.own(try progress.messageChanges(engine, operations, partial)));
    }
    for ([_]struct { items: c.JSValue, old: c.JSValue, key: [:0]const u8, name: []const u8 }{ .{ .items = slots, .old = old_slots, .key = "callId", .name = "tools" }, .{ .items = nested_slots, .old = old_nested, .key = "taskId", .name = "nestedTools" } }) |group| {
        for (0..try vm.length(engine, group.items)) |index| {
            const slot = try scope.item(group.items, index);
            const previous = try scope.invoke(group.old, "get", &.{try get(&scope, slot, group.key)});
            if (!try is(&scope, try get(&scope, slot, "status"), "running") or !try is(&scope, try get(&scope, previous, "status"), "running")) continue;
            const at = try scope.array(&.{ try scope.text(group.name), c.JS_NewFloat64(engine.context, @floatFromInt(index)) });
            const update = try scope.own(try progress.toolUpdate(engine, operations, at, slot, previous));
            if (!c.JS_IsUndefined(update)) try copyFields(&scope, try callEvent(&scope, events, "tool_execution_update", slot), update);
        }
    }
    const retry = try get(&scope, generation, "retry");
    const old_retry = try get(&scope, generation_before, "retry");
    if (!c.JS_IsUndefined(retry) and c.JS_IsUndefined(old_retry)) {
        const next = try add(&scope, events, "auto_retry_start");
        try put(&scope, next, "attempt", try get(&scope, generation, "attempt"));
        try put(&scope, next, "at", try get(&scope, retry, "at"));
        try put(&scope, next, "errorMessage", try get(&scope, retry, "error"));
    }
    if (!c.JS_IsUndefined(old_retry) and c.JS_IsUndefined(retry)) try put(&scope, try add(&scope, events, "auto_retry_end"), "attempt", try get(&scope, generation_before, "attempt"));
    const deferred = try get(&scope, generation, "deferred");
    const old_deferred = try get(&scope, generation_before, "deferred");
    if (!c.JS_IsUndefined(deferred) and !same(&scope, try get(&scope, deferred, "pollAt"), try get(&scope, old_deferred, "pollAt"))) try put(&scope, try add(&scope, events, "deferred_poll"), "pollAt", try get(&scope, deferred, "pollAt"));
    const ends = try scope.array(&.{});
    const previous_slots = try mapValues(&scope, old_slots);
    for (0..try vm.length(engine, previous_slots)) |index| {
        const previous = try scope.item(previous_slots, index);
        if (try is(&scope, try get(&scope, previous, "status"), "done")) continue;
        const id = try get(&scope, previous, "callId");
        const slot = try find(&scope, slots, "callId", id);
        if (try is(&scope, try get(&scope, slot, "status"), "done")) {
            try endTool(&scope, ends, entries, slot, try get(&scope, slot, "entry"));
        } else if (c.JS_IsUndefined(slot)) try endTool(&scope, ends, entries, previous, try get(&scope, try resultOf(&scope, entries, id), "id"));
    }
    for (0..try vm.length(engine, slots)) |index| {
        const slot = try scope.item(slots, index);
        if (try is(&scope, try get(&scope, slot, "status"), "done") and c.JS_ToBool(engine.context, try scope.invoke(old_slots, "has", &.{try get(&scope, slot, "callId")})) == 0) try endTool(&scope, ends, entries, slot, try get(&scope, slot, "entry"));
    }
    const nested_now = try by(&scope, nested_slots, "taskId");
    const previous_nested = try mapValues(&scope, old_nested);
    var remaining = try vm.length(engine, previous_nested);
    while (remaining > 0) {
        remaining -= 1;
        const previous = try scope.item(previous_nested, remaining);
        if (try is(&scope, try get(&scope, previous, "status"), "done")) continue;
        const slot = try scope.invoke(nested_now, "get", &.{try get(&scope, previous, "taskId")});
        if (c.JS_IsUndefined(slot) or try is(&scope, try get(&scope, slot, "status"), "done")) try endNested(&scope, events, results, if (c.JS_IsUndefined(slot)) previous else slot);
    }
    remaining = try vm.length(engine, nested_slots);
    while (remaining > 0) {
        remaining -= 1;
        const slot = try scope.item(nested_slots, remaining);
        if (try is(&scope, try get(&scope, slot, "status"), "done") and c.JS_ToBool(engine.context, try scope.invoke(old_nested, "has", &.{try get(&scope, slot, "taskId")})) == 0) try endNested(&scope, events, results, slot);
    }
    var assistant_appended = false;
    for (0..try vm.length(engine, entries)) |index| {
        const entry = try scope.item(entries, index);
        for (0..try vm.length(engine, ends)) |end_index| {
            const end = try scope.item(ends, end_index);
            if (same(&scope, try get(&scope, end, "entry"), entry)) try js.push(engine, events, end);
        }
        const model = try get(&scope, entry, "model");
        const message = if (c.JS_IsUndefined(model) or c.JS_IsNull(model)) c.pi_js_undefined() else try scope.item(model, 0);
        if (c.JS_IsUndefined(message)) {
            try put(&scope, try add(&scope, events, "entry_appended"), "entry", entry);
            continue;
        }
        const assistant = try is(&scope, try get(&scope, message, "role"), "assistant");
        const streamed = assistant and !c.JS_IsUndefined(partial_before) and !assistant_appended;
        if (assistant) assistant_appended = true;
        if (!streamed) try put(&scope, try add(&scope, events, "message_start"), "message", message);
        try put(&scope, try add(&scope, events, "message_end"), "entry", entry);
    }
    for (0..try vm.length(engine, ends)) |index| {
        const end = try scope.item(ends, index);
        if (c.JS_IsUndefined(try get(&scope, end, "entry"))) try js.push(engine, events, end);
    }
    const old_compactions = try array(&scope, try get(&scope, was, "compactions"));
    const compactions = try array(&scope, try get(&scope, now, "compactions"));
    for (0..try vm.length(engine, old_compactions)) |index| {
        const previous = try scope.item(old_compactions, index);
        const id = try get(&scope, previous, "taskId");
        if (!c.JS_IsUndefined(try find(&scope, compactions, "taskId", id))) continue;
        const next = try add(&scope, events, "compaction_end");
        try put(&scope, next, "taskId", id);
        try put(&scope, next, "reason", try get(&scope, previous, "reason"));
    }
    var turn_ended = false;
    const task_values = try mapValues(&scope, tasks);
    for (0..try vm.length(engine, task_values)) |index| {
        const task = try scope.item(task_values, index);
        const state = try get(&scope, task, "state");
        const status = try get(&scope, state, "status");
        const kind = try get(&scope, task, "kind");
        const id = try get(&scope, task, "id");
        const generation_task = try is(&scope, kind, "pi.generation");
        if (generation_task and try is(&scope, status, "completing") and c.JS_ToBool(engine.context, try scope.invoke(held, "has", &.{id})) == 0) {
            _ = try scope.invoke(held, "add", &.{id});
            turn_ended = true;
        }
        if (!try is(&scope, status, "terminal")) continue;
        if (generation_task and c.JS_ToBool(engine.context, try scope.invoke(held, "delete", &.{id})) == 0) turn_ended = true;
        const outcome = try get(&scope, state, "outcome");
        const faulted = try is(&scope, try get(&scope, outcome, "status"), "faulted");
        if (faulted or try is(&scope, try get(&scope, outcome, "status"), "orphaned")) {
            const next = try add(&scope, events, "task_failed");
            try put(&scope, next, "taskId", id);
            try put(&scope, next, "kind", kind);
            try put(&scope, next, "message", if (faulted) try get(&scope, try get(&scope, outcome, "error"), "message") else try get(&scope, outcome, "reason"));
        }
    }
    if (turn_ended) _ = try add(&scope, events, "turn_end");
    const run = try get(&scope, now, "run");
    const old_run = try get(&scope, was, "run");
    const inputs = try get(&scope, run, "inputs");
    const old_inputs = try get(&scope, old_run, "inputs");
    const first = if (c.JS_IsUndefined(inputs)) c.pi_js_undefined() else try scope.item(inputs, 0);
    const old_first = if (c.JS_IsUndefined(old_inputs)) c.pi_js_undefined() else try scope.item(old_inputs, 0);
    const run_changed = !same(&scope, first, old_first);
    if (!c.JS_IsUndefined(old_run) and run_changed) try put(&scope, try add(&scope, events, "run_end"), "inputs", old_inputs);
    for (0..try vm.length(engine, submissions)) |index| try put(&scope, try add(&scope, events, "submission"), "record", try scope.item(submissions, index));
    const inbox = try get(&scope, now_docs, "pi.inbox");
    if (!same(&scope, inbox, try get(&scope, was_docs, "pi.inbox"))) try put(&scope, try add(&scope, events, "inbox_update"), "items", try queued(&scope, inbox));
    const agent = try get(&scope, now_docs, "pi.agent");
    if (!same(&scope, agent, try get(&scope, was_docs, "pi.agent"))) try put(&scope, try add(&scope, events, "agent_changed"), "agent", try objectOrDefault(&scope, agent));
    const usage = try get(&scope, now_docs, "pi.usage");
    if (!same(&scope, usage, try get(&scope, was_docs, "pi.usage"))) try put(&scope, try add(&scope, events, "usage_changed"), "usage", try initialUsage(&scope, usage));
    for (0..try vm.length(engine, compactions)) |index| {
        const status = try scope.item(compactions, index);
        const id = try get(&scope, status, "taskId");
        if (!c.JS_IsUndefined(try find(&scope, old_compactions, "taskId", id))) continue;
        const next = try add(&scope, events, "compaction_start");
        inline for (.{ "taskId", "reason", "blocking" }) |key| try put(&scope, next, key, try get(&scope, status, key));
    }
    if (!c.JS_IsUndefined(run) and run_changed) try put(&scope, try add(&scope, events, "run_start"), "inputs", inputs);
    const run_task = try get(&scope, run, "taskId");
    if (!c.JS_IsUndefined(run) and !same(&scope, run_task, try get(&scope, old_run, "taskId")) and try is(&scope, try get(&scope, try scope.invoke(tasks, "get", &.{run_task}), "kind"), "pi.generation")) _ = try add(&scope, events, "turn_start");
    return c.JS_DupValue(engine.context, events);
}
