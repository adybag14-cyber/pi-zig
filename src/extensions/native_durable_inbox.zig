//! Inbox boundary selection and stale-write rules are native Zig.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Selection = struct {
    writes: []usize,
    users: []usize,
    reset: bool,
    pub fn deinit(self: *Selection, gpa: std.mem.Allocator) void {
        gpa.free(self.writes);
        gpa.free(self.users);
    }
};
fn equals(engine: *Engine, value: c.JSValue, text: [:0]const u8) !bool {
    const expected = try engine.checked(c.JS_NewString(engine.context, text));
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, value, expected);
}
pub fn isStale(engine: *Engine, head: c.JSValue, entry: c.JSValue) !bool {
    const target = try vm.get(engine, entry, "head");
    defer engine.freeValue(target);
    if (!c.JS_IsNumber(target) or c.JS_IsUndefined(head)) return false;
    var from: f64 = 0;
    var to: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &from, target) < 0 or c.JS_ToFloat64(engine.context, &to, head) < 0) return js.capture(engine);
    return from < to;
}
pub fn select(engine: *Engine, items: c.JSValue, final: bool, steering_mode: c.JSValue, follow_up_mode: c.JSValue) !Selection {
    var writes: std.ArrayList(usize) = .empty;
    defer writes.deinit(engine.gpa);
    var steers: std.ArrayList(usize) = .empty;
    defer steers.deinit(engine.gpa);
    var followups: std.ArrayList(usize) = .empty;
    defer followups.deinit(engine.gpa);
    var reset = false;
    const all_steers = try equals(engine, steering_mode, "all");
    const all_followups = try equals(engine, follow_up_mode, "all");
    for (0..try vm.length(engine, items)) |index| {
        const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, items, @intCast(index)));
        defer engine.freeValue(item);
        const mode = try vm.get(engine, item, "mode");
        defer engine.freeValue(mode);
        if (try equals(engine, mode, "write")) {
            try writes.append(engine.gpa, index);
            const entry = try vm.get(engine, item, "entry");
            defer engine.freeValue(entry);
            const head = try vm.get(engine, entry, "head");
            defer engine.freeValue(head);
            if (try equals(engine, head, "self")) reset = true;
        } else if (try equals(engine, mode, "steer")) {
            if (all_steers or steers.items.len == 0) try steers.append(engine.gpa, index);
        } else if (try equals(engine, mode, "followUp")) {
            if (all_followups or followups.items.len == 0) try followups.append(engine.gpa, index);
        }
    }
    if (final or reset) try steers.appendSlice(engine.gpa, followups.items);
    std.mem.sort(usize, steers.items, {}, std.sort.asc(usize));
    const owned_writes = try writes.toOwnedSlice(engine.gpa);
    errdefer engine.gpa.free(owned_writes);
    return .{ .writes = owned_writes, .users = try steers.toOwnedSlice(engine.gpa), .reset = reset };
}
pub fn removeSelected(engine: *Engine, items: c.JSValue, selection: Selection) !void {
    var removed: std.ArrayList(usize) = .empty;
    defer removed.deinit(engine.gpa);
    try removed.appendSlice(engine.gpa, selection.writes);
    try removed.appendSlice(engine.gpa, selection.users);
    std.mem.sort(usize, removed.items, {}, std.sort.desc(usize));
    for (removed.items) |index| {
        const result = try vm.invoke(engine, items, "splice", &.{ c.JS_NewFloat64(engine.context, @floatFromInt(index)), c.JS_NewInt32(engine.context, 1) });
        engine.freeValue(result);
    }
}
const awaiting = @import("native_durable_await.zig");
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
fn put(engine: *Engine, object: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, object, key, c.JS_DupValue(engine.context, value));
}
fn wait(engine: *Engine, state: c.JSValue, pending: c.JSValue, stage: c_int) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var intrinsics: awaiting.Intrinsics = .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
    return awaiting.continueWith(advance, engine, &intrinsics, state, pending, stage);
}
pub fn apply(engine: *Engine, intrinsics: *awaiting.Intrinsics, tx: c.JSValue, boundary: c.JSValue, final: bool, now: c.JSValue, user_token: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function }, .{ "tx", tx }, .{ "boundary", boundary }, .{ "now", now }, .{ "userToken", user_token } }) |field| try put(engine, state, field[0], field[1]);
    const items = try scope.get(try scope.get(boundary, "inbox"), "items");
    var selected = try select(engine, items, final, try scope.get(boundary, "steeringMode"), try scope.get(boundary, "followUpMode"));
    defer selected.deinit(engine.gpa);
    inline for (.{ .{ "writes", selected.writes }, .{ "users", selected.users } }) |field| {
        const indexes = try scope.own(try vm.array(engine));
        for (field[1]) |index| try js.push(engine, indexes, c.JS_NewFloat64(engine.context, @floatFromInt(index)));
        try put(engine, state, field[0], indexes);
    }
    try put(engine, state, "reset", c.pi_js_bool(engine.context, @intFromBool(selected.reset)));
    try put(engine, state, "writeIndex", c.JS_NewInt32(engine.context, 0));
    try put(engine, state, "userIndex", c.JS_NewInt32(engine.context, 0));
    try @import("native_tool_info.zig").putData(engine, state, "placed", try vm.array(engine));
    return processNext(engine, state);
}
fn indexNumber(engine: *Engine, value: c.JSValue) !u32 {
    var index: u32 = 0;
    if (c.JS_ToUint32(engine.context, &index, value) < 0) return js.capture(engine);
    return index;
}
fn processNext(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const boundary = try scope.get(state, "boundary");
    const items = try scope.get(try scope.get(boundary, "inbox"), "items");
    const tx = try scope.get(state, "tx");
    const conversation = try scope.get(boundary, "conversationId");
    const writes = try scope.get(state, "writes");
    var write_index = try indexNumber(engine, try scope.get(state, "writeIndex"));
    while (write_index < try vm.length(engine, writes)) {
        const position = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, writes, write_index)));
        const item = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, items, try indexNumber(engine, position))));
        const entry = try scope.get(item, "entry");
        write_index += 1;
        try put(engine, state, "writeIndex", c.JS_NewUint32(engine.context, write_index));
        if (try isStale(engine, try scope.get(boundary, "head"), entry)) {
            const settlement = try scope.own(try vm.object(engine));
            try put(engine, settlement, "status", try scope.text("unanswered"));
            try put(engine, settlement, "reason", try scope.text("stale"));
            _ = try scope.invoke(tx, "settleSubmission", &.{ try scope.get(item, "id"), settlement });
            continue;
        }
        try put(engine, state, "currentItem", item);
        const pending = try scope.invoke(tx, "appendEntry", &.{ conversation, entry });
        return wait(engine, state, pending, 1);
    }
    const users = try scope.get(state, "users");
    const user_index = try indexNumber(engine, try scope.get(state, "userIndex"));
    if (user_index < try vm.length(engine, users)) {
        const position = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, users, user_index)));
        const item = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, items, try indexNumber(engine, position))));
        try put(engine, state, "currentItem", item);
        try put(engine, state, "userIndex", c.JS_NewUint32(engine.context, user_index + 1));
        const message = try scope.own(try vm.object(engine));
        try put(engine, message, "role", try scope.text("user"));
        try put(engine, message, "content", try scope.get(item, "content"));
        try put(engine, message, "timestamp", try scope.get(state, "now"));
        const model = try scope.own(try vm.array(engine));
        try js.push(engine, model, message);
        const entry = try scope.own(try vm.object(engine));
        try put(engine, entry, "model", model);
        const pending = try scope.invoke(tx, "appendEntry", &.{ try scope.get(state, "userToken"), conversation, entry });
        return wait(engine, state, pending, 2);
    }
    var removed: std.ArrayList(usize) = .empty;
    defer removed.deinit(engine.gpa);
    inline for (.{ writes, users }) |indexes| for (0..try vm.length(engine, indexes)) |index| {
        const position = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, indexes, @intCast(index))));
        try removed.append(engine.gpa, try indexNumber(engine, position));
    };
    std.mem.sort(usize, removed.items, {}, std.sort.desc(usize));
    for (removed.items) |index| _ = try scope.invoke(items, "splice", &.{ c.JS_NewFloat64(engine.context, @floatFromInt(index)), c.JS_NewInt32(engine.context, 1) });
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try put(engine, result, "users", try scope.get(state, "placed"));
    try put(engine, result, "reset", try scope.get(state, "reset"));
    return result;
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 3) {
        try put(engine, state, "head", if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) c.pi_js_undefined() else try scope.get(value, "head"));
        const pending = try scope.invoke(try scope.get(state, "tx"), "doc", &.{ try scope.get(state, "inboxToken"), try scope.get(state, "conversation") });
        return wait(engine, state, pending, 4);
    }
    if (stage == 4) {
        const boundary = try vm.object(engine);
        errdefer engine.freeValue(boundary);
        const modes = try scope.get(state, "modes");
        try put(engine, boundary, "conversationId", try scope.get(state, "conversation"));
        try put(engine, boundary, "inbox", value);
        try put(engine, boundary, "steeringMode", try scope.get(modes, "steeringMode"));
        try put(engine, boundary, "followUpMode", try scope.get(modes, "followUpMode"));
        try put(engine, boundary, "head", try scope.get(state, "head"));
        return boundary;
    }
    const item = try scope.get(state, "currentItem");
    const id = try scope.get(value, "id");
    const item_id = try scope.get(item, "id");
    if (stage == 1) {
        const head = try scope.get(try scope.get(item, "entry"), "head");
        if (!c.JS_IsUndefined(head)) try put(engine, try scope.get(state, "boundary"), "head", if (try equals(engine, head, "self")) id else head);
    } else if (stage == 2) try js.push(engine, try scope.get(state, "placed"), item_id) else return error.InvalidInboxContinuation;
    _ = try scope.invoke(try scope.get(state, "tx"), "placeSubmission", &.{ item_id, id });
    return processNext(engine, state);
}
pub fn prepare(engine: *Engine, intrinsics: *awaiting.Intrinsics, tx: c.JSValue, conversation: c.JSValue, modes: c.JSValue, inbox_token: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function }, .{ "tx", tx }, .{ "conversation", conversation }, .{ "modes", modes }, .{ "inboxToken", inbox_token } }) |field| try put(engine, state, field[0], field[1]);
    const pending = try scope.invoke(tx, "latestHeadMarker", &.{conversation});
    return wait(engine, state, pending, 3);
}
