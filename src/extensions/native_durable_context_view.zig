//! Committed context bounds and derivation over native storage snapshots.
const std = @import("std");
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const backend = @import("../durable/backend/root.zig");
const query = @import("../durable/backend/query.zig");
const scan = @import("../durable/backend/source_scan.zig");
const json = backend.json;
const Value = json.Value;
const Engine = engine_mod.Engine;
const c = engine_mod.c;
pub const Cache = struct { view: c.JSValue, head: ?u64, tail: u64, idle_since: ?i64 = null };
fn array(a: std.mem.Allocator) Value {
    return .{ .array = .init(a) };
}
fn text(value: Value, name: []const u8, expected: []const u8) bool {
    const item = json.get(value, name) orelse return false;
    return item == .string and std.mem.eql(u8, item.string, expected);
}
pub fn queued(engine: *Engine, session: c.JSValue, conversation: c.JSValue, context: c.JSValue, at: c.JSValue) !c.JSValue {
    var data = [_]c.JSValue{ session, conversation, context, at };
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, onLine, 0, 0, data.len, &data));
    defer engine.freeValue(callback);
    return durable.enqueue(engine, session, callback);
}
fn onLine(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return read(engine, data[0], data[1], data[2], data[3], null) catch |err| durable.reject(engine, err);
}
pub fn read(engine: *Engine, session: c.JSValue, conversation: c.JSValue, context: c.JSValue, at: c.JSValue, cache: ?*?Cache) !c.JSValue {
    const deep = cache != null;
    try durable.checkCancellation(engine, context);
    const native = try durable.state(engine, session);
    if (native.closing) return error.SessionClosed;
    var store: backend.memory.Memory = .{ .gpa = engine.gpa, .state = try native.session_lease.?.value.storage.snapshot(engine.gpa) };
    defer store.deinit();
    const id = try durable.number(engine, conversation);
    const bounded = if (c.JS_IsUndefined(at)) null else try durable.number(engine, at);
    if (bounded) |entry_id| {
        var visible = try query.entry(engine.gpa, &store, entry_id, id);
        defer if (visible) |*entry| entry.deinit();
        if (visible == null) {
            const message = try std.fmt.allocPrint(engine.gpa, "Entry {d} is not visible from conversation {d}", .{ entry_id, id });
            defer engine.gpa.free(message);
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            const constructor = try sdk.get(engine, global, "Error");
            defer engine.freeValue(constructor);
            const string = try sdk.text(engine, message);
            defer engine.freeValue(string);
            var args = [_]c.JSValue{string};
            const failure = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args));
            return engine.checked(c.JS_Throw(engine.context, failure));
        }
    }
    const ids = try query.visibleIds(engine.gpa, store.state, id, null, bounded);
    defer engine.gpa.free(ids);
    var owned = try json.Owned.empty(engine.gpa);
    defer owned.deinit();
    const a = owned.arena.allocator();
    var entries = array(a);
    var head: ?Value = null;
    if (ids.len != 0) {
        var marker = try scan.latestHead(engine.gpa, &store, id, ids[0]);
        defer if (marker) |*value| value.deinit();
        const minimum = if (marker) |value| try json.asInteger(try json.required(value.value, "head")) else 0;
        if (marker) |value| head = try json.clone(a, value.value);
        var index = ids.len;
        while (index > 0) {
            index -= 1;
            if (ids[index] >= minimum) try entries.array.append(try json.clone(a, store.state.rows.get(ids[index]).?.record));
        }
    }
    owned.value = try derive(a, head, entries);
    var memo: std.AutoHashMapUnmanaged(usize, c.JSValue) = .empty;
    defer memo.deinit(engine.gpa);
    const head_id = if (head) |marker| try json.asInteger(try json.required(marker, "id")) else null;
    const tail = if (ids.len == 0) 0 else ids[0];
    if (cache) |slot| if (slot.*) |previous| {
        if (previous.head == head_id) try seedPrevious(engine, owned.value, previous, tail, &memo);
    };
    const result = try sharedValue(engine, owned.value, &memo);
    errdefer engine.freeValue(result);
    if (head == null) try sdk.put(engine, result, "head", c.pi_js_undefined());
    // Source records, messages and contribution arrays are immutable; each view
    // owns new outer arrays that callers may freely change.
    const js_entries = try sdk.get(engine, result, "entries");
    defer engine.freeValue(js_entries);
    for (0..try sdk.length(engine, js_entries)) |index| {
        const entry = try engine.checked(c.JS_GetPropertyUint32(engine.context, js_entries, @intCast(index)));
        defer engine.freeValue(entry);
        if (deep) try freeze(engine, entry);
    }
    const contributions = try sdk.get(engine, result, "contributions");
    defer engine.freeValue(contributions);
    for (0..try sdk.length(engine, contributions)) |index| {
        const contribution = try engine.checked(c.JS_GetPropertyUint32(engine.context, contributions, @intCast(index)));
        defer engine.freeValue(contribution);
        if (deep) try freeze(engine, contribution) else try freezeShallow(engine, contribution);
    }
    const messages = try sdk.get(engine, result, "messages");
    defer engine.freeValue(messages);
    for (0..try sdk.length(engine, messages)) |index| {
        const message = try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, @intCast(index)));
        defer engine.freeValue(message);
        const details = try sdk.get(engine, message, "details");
        defer engine.freeValue(details);
        const reason = if (c.JS_IsUndefined(details)) c.pi_js_undefined() else try sdk.get(engine, details, "reason");
        defer engine.freeValue(reason);
        var missing = false;
        if (c.JS_IsString(reason)) {
            const name = try engine.toString(reason);
            defer engine.gpa.free(name);
            missing = std.mem.eql(u8, name, "missing_result");
        }
        if (deep or missing) try freeze(engine, message);
    }
    if (cache) |slot| {
        if (slot.*) |previous| {
            if (tail >= previous.tail) {
                engine.freeValue(previous.view);
                slot.* = .{ .view = c.JS_DupValue(engine.context, result), .head = head_id, .tail = tail };
            }
        } else if (tail != 0) slot.* = .{ .view = c.JS_DupValue(engine.context, result), .head = head_id, .tail = tail };
    }
    return result;
}
fn nativeKey(value: Value) ?usize {
    return switch (value) {
        .object => if (value.object.count() == 0) null else @intFromPtr(value.object.keys().ptr),
        .array => if (value.array.items.len == 0) null else @intFromPtr(value.array.items.ptr),
        else => null,
    };
}
fn seedPrevious(engine: *Engine, value: Value, previous: Cache, tail: u64, memo: *std.AutoHashMapUnmanaged(usize, c.JSValue)) !void {
    const entries = try json.required(value, "entries");
    const contributions = try json.required(value, "contributions");
    const old_entries = try sdk.get(engine, previous.view, "entries");
    defer engine.freeValue(old_entries);
    const old_contributions = try sdk.get(engine, previous.view, "contributions");
    defer engine.freeValue(old_contributions);
    var keep_contributions = tail >= previous.tail;
    for (entries.array.items) |entry| if (try json.asInteger(try json.required(entry, "id")) > previous.tail and json.get(entry, "edits") != null) {
        keep_contributions = false;
    };
    for (entries.array.items, 0..) |entry, index| {
        const id = try json.asInteger(try json.required(entry, "id"));
        for (0..try sdk.length(engine, old_entries)) |old_index| {
            const old = try engine.checked(c.JS_GetPropertyUint32(engine.context, old_entries, @intCast(old_index)));
            defer engine.freeValue(old);
            const old_id = try sdk.get(engine, old, "id");
            defer engine.freeValue(old_id);
            if (id != try durable.number(engine, old_id)) continue;
            try seedObjects(engine, entry, old, memo);
            if (keep_contributions) if (nativeKey(contributions.array.items[index])) |key| {
                const old_contribution = try engine.checked(c.JS_GetPropertyUint32(engine.context, old_contributions, @intCast(old_index)));
                defer engine.freeValue(old_contribution);
                try memo.put(engine.gpa, key, old_contribution);
            };
            break;
        }
    }
}
fn seedObjects(engine: *Engine, native: Value, previous: c.JSValue, memo: *std.AutoHashMapUnmanaged(usize, c.JSValue)) anyerror!void {
    if (nativeKey(native)) |key| try memo.put(engine.gpa, key, previous) else return;
    if (native == .object) {
        for (native.object.keys(), native.object.values()) |name, child| {
            const property = try engine.gpa.dupeZ(u8, name);
            defer engine.gpa.free(property);
            const existing = try sdk.get(engine, previous, property);
            defer engine.freeValue(existing);
            try seedObjects(engine, child, existing, memo);
        }
    } else for (native.array.items, 0..) |child, index| {
        const existing = try engine.checked(c.JS_GetPropertyUint32(engine.context, previous, @intCast(index)));
        defer engine.freeValue(existing);
        try seedObjects(engine, child, existing, memo);
    }
}
/// JSON ownership already has shared map/array buffers for each contribution.
/// Preserve those aliases across the C boundary, as the source context does.
fn sharedValue(engine: *Engine, value: Value, memo: *std.AutoHashMapUnmanaged(usize, c.JSValue)) anyerror!c.JSValue {
    const key = nativeKey(value);
    if (key) |id| if (memo.get(id)) |existing| return c.JS_DupValue(engine.context, existing);
    if (value != .object and value != .array) return durable.jsValue(engine, value);
    const result = if (value == .array) try sdk.array(engine) else try sdk.object(engine);
    errdefer engine.freeValue(result);
    if (key) |id| try memo.put(engine.gpa, id, result);
    if (value == .array) {
        for (value.array.items) |item| try sdk.append(engine, result, try sharedValue(engine, item, memo));
    } else {
        for (value.object.keys(), value.object.values()) |name, child| {
            const property = try engine.gpa.dupeZ(u8, name);
            defer engine.gpa.free(property);
            try sdk.put(engine, result, property, try sharedValue(engine, child, memo));
        }
    }
    return result;
}
fn derive(a: std.mem.Allocator, head: ?Value, range: Value) !Value {
    var edits: std.AutoHashMapUnmanaged(u64, Value) = .empty;
    for (range.array.items) |entry| if (json.get(entry, "edits")) |changes| {
        for (changes.array.items) |edit| try edits.put(a, try json.asInteger(try json.required(edit, "target")), edit);
    };
    var active = array(a);
    if (head) |marker| try active.array.append(marker);
    for (range.array.items) |entry| if (head == null or json.get(entry, "head") == null) try active.array.append(entry);
    var contributions = array(a);
    var messages = array(a);
    for (active.array.items) |entry| {
        var contribution = array(a);
        const edit = edits.get(try json.asInteger(try json.required(entry, "id")));
        const omitted = if (edit) |value| text(value, "action", "omit") else false;
        if (!omitted) {
            const model = if (edit != null and text(edit.?, "action", "replace")) json.get(edit.?, "messages") else json.get(entry, "model");
            if (model) |items| for (items.array.items) |message| {
                if (text(message, "role", "assistant") and (text(message, "stopReason", "error") or text(message, "stopReason", "aborted") or text(message, "stopReason", "deferred"))) continue;
                try contribution.array.append(message);
                try messages.array.append(message);
            };
        }
        try contributions.array.append(contribution);
    }
    var ordered = try orderTools(a, messages);
    var first_non_user: usize = 0;
    while (first_non_user < ordered.array.items.len and text(ordered.array.items[first_non_user], "role", "user")) : (first_non_user += 1) {}
    if (first_non_user > 0 and first_non_user < ordered.array.items.len and text(ordered.array.items[first_non_user], "role", "system")) {
        const system = ordered.array.orderedRemove(first_non_user);
        try ordered.array.insert(0, system);
    }
    var result: Value = .{ .object = .empty };
    try result.object.put(a, "head", head orelse .null);
    try result.object.put(a, "entries", active);
    try result.object.put(a, "contributions", contributions);
    try result.object.put(a, "messages", ordered);
    return result;
}
fn orderTools(a: std.mem.Allocator, messages: Value) !Value {
    var ordered = array(a);
    for (messages.array.items, 0..) |message, index| {
        if (text(message, "role", "toolResult")) continue;
        try ordered.array.append(message);
        if (!text(message, "role", "assistant")) continue;
        const content = json.get(message, "content") orelse continue;
        for (content.array.items) |call| {
            if (!text(call, "type", "toolCall")) continue;
            var found: ?Value = null;
            for (messages.array.items[index + 1 ..]) |candidate| {
                if (text(candidate, "role", "assistant")) break;
                if (text(candidate, "role", "toolResult") and json.equal(try json.required(candidate, "toolCallId"), try json.required(call, "id"))) {
                    found = candidate;
                    break;
                }
            }
            if (found) |value| try ordered.array.append(value) else {
                var missing: Value = .{ .object = .empty };
                try missing.object.put(a, "role", .{ .string = "toolResult" });
                try missing.object.put(a, "toolCallId", try json.required(call, "id"));
                try missing.object.put(a, "toolName", try json.required(call, "name"));
                try missing.object.put(a, "content", try json.parseLeaky(a, "[{\"type\":\"text\",\"text\":\"Tool result unavailable: history ends before this call completed.\"}]"));
                try missing.object.put(a, "isError", .{ .bool = true });
                try missing.object.put(a, "details", try json.parseLeaky(a, "{\"reason\":\"missing_result\"}"));
                try missing.object.put(a, "timestamp", try json.required(message, "timestamp"));
                try ordered.array.append(missing);
            }
        }
    }
    return ordered;
}
fn freeze(engine: *Engine, value: c.JSValue) anyerror!void {
    if (!c.JS_IsObject(value)) return;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const object = try sdk.get(engine, global, "Object");
    defer engine.freeValue(object);
    const values = try sdk.invoke(engine, object, "values", &.{value});
    defer engine.freeValue(values);
    for (0..try sdk.length(engine, values)) |index| {
        const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, values, @intCast(index)));
        defer engine.freeValue(item);
        try freeze(engine, item);
    }
    const frozen = try sdk.invoke(engine, object, "freeze", &.{value});
    engine.freeValue(frozen);
}
fn freezeShallow(engine: *Engine, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const object = try sdk.get(engine, global, "Object");
    defer engine.freeValue(object);
    const frozen = try sdk.invoke(engine, object, "freeze", &.{value});
    engine.freeValue(frozen);
}
fn allocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    var data = try json.Owned.parse(gpa,
        \\[{"id":2,"kind":"user","model":[{"role":"user","content":"before","timestamp":1}]},{"id":3,"kind":"assistant","model":[{"role":"assistant","content":[{"type":"toolCall","id":"call","name":"echo","arguments":{}}],"stopReason":"toolUse","timestamp":2}]},{"id":4,"kind":"edit","edits":[{"target":2,"action":"replace","messages":[{"role":"user","content":"after","timestamp":3}]}]}]
    );
    defer data.deinit();
    const view = try derive(data.arena.allocator(), null, data.value);
    var memo: std.AutoHashMapUnmanaged(usize, c.JSValue) = .empty;
    defer memo.deinit(gpa);
    const result = try sharedValue(engine, view, &memo);
    defer engine.freeValue(result);
    try freeze(engine, result);
}
test "native durable VM context derivation shared aliases and freeze unwind every GPA allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}
