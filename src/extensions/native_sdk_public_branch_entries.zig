//! Actual c268 branch collection and budget preparation. The public functions
//! and existing branch-summary caller share these real bodies and message owners.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const Engine = h.Engine;
const Scope = h.Scope;
const files = @import("native_sdk_compaction_file_ops.zig");
const estimate = @import("native_sdk_compaction_estimate.zig");
const records = @import("native_sdk_session_projection_live.zig");
const cache_key = "\x00sdk-public-branch-entries";
const CollectFrame = h.Frame(enum { old_path, target_path, ancestor, i, entries, current, entry });
const PrepareFrame = h.Frame(enum {
    messages, file_ops, total, first_entry, details, read_path, modified_path, i, entry, message, tokens,
});
extern "c" fn JS_PiDecrement(context: ?*c.JSContext, value: c.JSValue) c.JSValue;

pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, createBody, .{});
    if (engine.native_module_values.get(cache_key)) |cached| {
        var selected = v.owned.Completion.initValue(engine, h.duplicate(engine, cached));
        selected.release(candidate);
        return selected.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate);
        return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, candidate);
    return h.duplicate(engine, candidate);
}
fn createBody(s: *Scope) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "collectEntriesForBranchSummary", try v.ordinary(s, "collectEntriesForBranchSummary", 3, collectCall, &.{}));
    try v.put(s, result, "prepareBranchEntries", try v.ordinary(s, "prepareBranchEntries", 1, prepareCall, &.{}));
    return v.duplicate(s, result);
}
fn collectCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return collect(engine, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2));
}
fn prepareCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return prepare(engine, v.arg(args, 0), v.arg(args, 1));
}
fn lastIndex(s: *Scope, entries: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .subtract, try v.get(s, entries, "length"), v.number(s, 1)));
}
fn decrementBody(s: *Scope, value: c.JSValue) !c.JSValue {
    var operation: v.guest.Boundary = .{ .engine = s.engine };
    try operation.begin();
    return v.duplicate(s, try operation.finishValue(s, JS_PiDecrement(s.engine.context, value)));
}
fn decrement(engine: *Engine, value: c.JSValue) !c.JSValue {
    return h.expression(engine, decrementBody, .{value});
}
fn entryId(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return h.get(engine, v.arg(args, 0), "id");
}
fn branchOf(s: *Scope, session: c.JSValue, id: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.invoke(s, session, "getBranch", &.{id}));
}
fn mappedBranch(s: *Scope, session: c.JSValue, old_leaf: c.JSValue) !c.JSValue {
    const branch = try v.own(s, try h.expression(s.engine, branchOf, .{ session, old_leaf }));
    const map = try v.get(s, branch, "map");
    const callback = try v.arrow(s, "", 1, entryId, &.{});
    return v.duplicate(s, try v.call(s, map, branch, &.{callback}));
}
fn oldPath(s: *Scope, session: c.JSValue, old_leaf: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Set");
    const mapped = try v.own(s, try h.expression(s.engine, mappedBranch, .{ session, old_leaf }));
    return v.duplicate(s, try v.construct(s, constructor, &.{mapped}));
}
fn indexedId(s: *Scope, path: c.JSValue, index: c.JSValue) !c.JSValue {
    const entry = try v.key(s, path, index);
    return v.duplicate(s, try v.get(s, entry, "id"));
}
fn commonHas(s: *Scope, old_path: c.JSValue, target_path: c.JSValue, index: c.JSValue) !c.JSValue {
    const method = try v.get(s, old_path, "has");
    const id = try v.own(s, try h.expression(s.engine, indexedId, .{ target_path, index }));
    return v.boolean(s, v.truthy(s, try v.call(s, method, old_path, &.{id})));
}
fn collectEmpty(s: *Scope) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "entries", try v.array(s));
    try v.put(s, result, "commonAncestorId", c.pi_js_null());
    return v.duplicate(s, result);
}
fn currentDiffers(s: *Scope, current: c.JSValue, ancestor: c.JSValue) !c.JSValue {
    return v.boolean(s, !v.equal(s, current, ancestor));
}
fn getEntry(s: *Scope, session: c.JSValue, current: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.invoke(s, session, "getEntry", &.{current}));
}
fn collectResult(s: *Scope, entries: c.JSValue, ancestor: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "entries", entries);
    try v.put(s, result, "commonAncestorId", ancestor);
    return v.duplicate(s, result);
}
fn collectSource(f: *CollectFrame, session: c.JSValue, old_leaf: c.JSValue, target: c.JSValue) !c.JSValue {
    const engine = f.engine;
    if (!h.truthy(engine, old_leaf)) return h.expression(engine, collectEmpty, .{});
    try f.set(.old_path, h.expression(engine, oldPath, .{ session, old_leaf }));
    try f.set(.target_path, h.expression(engine, branchOf, .{ session, target }));
    try f.set(.ancestor, c.pi_js_null());
    try f.set(.i, h.expression(engine, lastIndex, .{f.get(.target_path)}));
    var steps: usize = 0;
    while (try h.compare(engine, .greater_equal, f.get(.i), h.number(engine, 0))) {
        try v.poll(engine, &steps);
        if (h.truthy(engine, try h.expression(engine, commonHas, .{ f.get(.old_path), f.get(.target_path), f.get(.i) }))) {
            try f.set(.ancestor, h.expression(engine, indexedId, .{ f.get(.target_path), f.get(.i) }));
            break;
        }
        try f.set(.i, decrement(engine, f.get(.i)));
    }
    try f.set(.entries, h.array(engine));
    try f.set(.current, h.duplicate(engine, old_leaf));
    while (h.truthy(engine, f.get(.current)) and h.truthy(engine, try h.expression(engine, currentDiffers, .{ f.get(.current), f.get(.ancestor) }))) {
        try v.poll(engine, &steps);
        // The while condition precedes the body scope's entry-slot reset.
        try f.clear(.entry);
        try f.set(.entry, h.expression(engine, getEntry, .{ session, f.get(.current) }));
        if (!h.truthy(engine, f.get(.entry))) break;
        try h.discard(engine, f.get(.entries), "push", &.{f.get(.entry)});
        try f.set(.current, h.get(engine, f.get(.entry), "parentId"));
    }
    try h.discard(engine, f.get(.entries), "reverse", &.{});
    return h.expression(engine, collectResult, .{ f.get(.entries), f.get(.ancestor) });
}
pub fn collect(engine: *Engine, session: c.JSValue, old_leaf: c.JSValue, target: c.JSValue) !c.JSValue {
    var f = CollectFrame.init(engine);
    return f.finish(collectSource(&f, session, old_leaf, target));
}

fn messageKind(s: *Scope, entry: c.JSValue) !c.JSValue {
    const kind = try v.get(s, entry, "type");
    inline for (.{ "message", "custom_message", "branch_summary", "compaction" }, 1..) |name, index|
        if (try v.eq(s, kind, name)) return c.JS_NewInt32(s.engine.context, @intCast(index));
    return c.JS_NewInt32(s.engine.context, 0);
}
fn customRecord(s: *Scope, entry: c.JSValue) !c.JSValue {
    const custom_type = try v.get(s, entry, "customType");
    const content = try v.get(s, entry, "content");
    const display = try v.get(s, entry, "display");
    const details = try v.get(s, entry, "details");
    const timestamp = try v.get(s, entry, "timestamp");
    return h.expression(s.engine, records.customMessage, .{ custom_type, content, display, details, timestamp });
}
fn branchRecord(s: *Scope, entry: c.JSValue) !c.JSValue {
    const summary = try v.get(s, entry, "summary");
    const from_id = try v.get(s, entry, "fromId");
    const timestamp = try v.get(s, entry, "timestamp");
    return h.expression(s.engine, records.branchMessage, .{ summary, from_id, timestamp });
}
fn compactionRecord(s: *Scope, entry: c.JSValue) !c.JSValue {
    const summary = try v.get(s, entry, "summary");
    const tokens = try v.get(s, entry, "tokensBefore");
    const timestamp = try v.get(s, entry, "timestamp");
    return h.expression(s.engine, records.compactionRecord, .{ summary, tokens, timestamp });
}
fn messageFromEntry(engine: *Engine, entry: c.JSValue) !c.JSValue {
    const kind = try h.expression(engine, messageKind, .{entry});
    // messageKind returns an immediate Number after the switch operand retires.
    var code: i32 = 0;
    _ = c.JS_ToInt32(engine.context, &code, kind);
    return switch (code) {
        1 => if (try h.nestedEqual(engine, entry, "message", "role", "toolResult")) c.pi_js_undefined() else h.get(engine, entry, "message"),
        2 => h.expression(engine, customRecord, .{entry}),
        3 => h.expression(engine, branchRecord, .{entry}),
        4 => h.expression(engine, compactionRecord, .{entry}),
        else => c.pi_js_undefined(),
    };
}
fn arrayField(s: *Scope, details: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const array = try v.global(s, "Array");
    const method = try v.get(s, array, "isArray");
    const value = try v.get(s, details, name);
    return v.boolean(s, v.truthy(s, try v.call(s, method, array, &.{value})));
}
fn addPath(s: *Scope, operations: c.JSValue, name: [*:0]const u8, path: c.JSValue) !void {
    const receiver = try v.get(s, operations, name);
    const method = try v.get(s, receiver, "add");
    _ = try v.call(s, method, receiver, &.{path});
}
fn pathRows(f: *PrepareFrame, iterator: *v.Iterator, comptime modified: bool) !void {
    while (try iterator.next()) |path| {
        try f.set(if (modified) .modified_path else .read_path, path);
        try h.statement(f.engine, addPath, .{
            f.get(.file_ops), @as([*:0]const u8, if (modified) "edited" else "read"),
            f.get(if (modified) .modified_path else .read_path),
        });
    }
}
fn fileRows(f: *PrepareFrame, iterator: *v.Iterator) !void {
    const engine = f.engine;
    while (try iterator.next()) |entry| {
        try f.set(.first_entry, entry);
        if (try h.fieldEqual(engine, f.get(.first_entry), "type", "branch_summary") and
            !try h.fieldTest(engine, f.get(.first_entry), "fromHook", .truthy) and
            try h.fieldTest(engine, f.get(.first_entry), "details", .truthy))
        {
            try f.clear(.details);
            try f.set(.details, h.get(engine, f.get(.first_entry), "details"));
            if (h.truthy(engine, try h.expression(engine, arrayField, .{ f.get(.details), @as([*:0]const u8, "readFiles") }))) {
                // The for-head scope enters before its iterable expression.
                try f.clear(.read_path);
                var paths = try v.Iterator.initOwned(engine, try h.get(engine, f.get(.details), "readFiles"));
                try paths.finish(pathRows(f, &paths, false));
            }
            if (h.truthy(engine, try h.expression(engine, arrayField, .{ f.get(.details), @as([*:0]const u8, "modifiedFiles") }))) {
                try f.clear(.modified_path);
                var paths = try v.Iterator.initOwned(engine, try h.get(engine, f.get(.details), "modifiedFiles"));
                try paths.finish(pathRows(f, &paths, true));
            }
        }
    }
}
fn addTokens(s: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .add, left, right));
}
fn sumExceeds(s: *Scope, total: c.JSValue, tokens: c.JSValue, token_budget: c.JSValue) !c.JSValue {
    const sum = try v.own(s, try h.expression(s.engine, addTokens, .{ total, tokens }));
    return v.duplicate(s, try h.binary(s, .greater, sum, token_budget));
}
fn summaryThreshold(s: *Scope, total: c.JSValue, token_budget: c.JSValue) !c.JSValue {
    const threshold = try h.binary(s, .multiply, token_budget, v.number(s, 0.9));
    return v.duplicate(s, try h.binary(s, .less, total, threshold));
}
fn prepareResult(s: *Scope, f: *PrepareFrame) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "messages", f.get(.messages));
    try v.put(s, result, "fileOps", f.get(.file_ops));
    try v.put(s, result, "totalTokens", f.get(.total));
    return v.duplicate(s, result);
}
fn prepareSource(f: *PrepareFrame, entries: c.JSValue, supplied_budget: c.JSValue) !c.JSValue {
    const engine = f.engine;
    const token_budget = if (c.JS_IsUndefined(supplied_budget)) h.number(engine, 0) else supplied_budget;
    try f.set(.messages, h.array(engine));
    try f.set(.file_ops, files.create(engine));
    try f.set(.total, h.number(engine, 0));
    var iterator = try v.Iterator.init(engine, entries);
    try iterator.finish(fileRows(f, &iterator));
    try f.set(.i, h.expression(engine, lastIndex, .{entries}));
    var steps: usize = 0;
    while (try h.compare(engine, .greater_equal, f.get(.i), h.number(engine, 0))) {
        try v.poll(engine, &steps);
        // All three belong to the same for-body scope; reset in reverse order.
        try f.clear(.tokens);
        try f.clear(.message);
        try f.clear(.entry);
        try f.set(.entry, h.key(engine, entries, f.get(.i)));
        try f.set(.message, messageFromEntry(engine, f.get(.entry)));
        if (h.truthy(engine, f.get(.message))) {
            try files.extract(engine, f.get(.message), f.get(.file_ops));
            try f.set(.tokens, estimate.estimateTokens(engine, f.get(.message)));
            if (try h.compare(engine, .greater, token_budget, h.number(engine, 0)) and
                h.truthy(engine, try h.expression(engine, sumExceeds, .{ f.get(.total), f.get(.tokens), token_budget })))
            {
                if (try h.fieldEqual(engine, f.get(.entry), "type", "compaction") or
                    try h.fieldEqual(engine, f.get(.entry), "type", "branch_summary"))
                {
                    if (h.truthy(engine, try h.expression(engine, summaryThreshold, .{ f.get(.total), token_budget }))) {
                        try h.discard(engine, f.get(.messages), "unshift", &.{f.get(.message)});
                        try f.set(.total, h.expression(engine, addTokens, .{ f.get(.total), f.get(.tokens) }));
                    }
                }
                break;
            }
            try h.discard(engine, f.get(.messages), "unshift", &.{f.get(.message)});
            try f.set(.total, h.expression(engine, addTokens, .{ f.get(.total), f.get(.tokens) }));
        }
        try f.set(.i, decrement(engine, f.get(.i)));
    }
    return h.expression(engine, prepareResult, .{f});
}
pub fn prepare(engine: *Engine, entries: c.JSValue, token_budget: c.JSValue) !c.JSValue {
    var f = PrepareFrame.init(engine);
    return f.finish(prepareSource(&f, entries, token_budget));
}
