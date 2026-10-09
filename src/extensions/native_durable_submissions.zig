//! Durable submission admission shares the native inbox boundary implementation.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const awaiting = @import("native_durable_await.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Tokens = struct { live: c.JSValue, inbox: c.JSValue, user: c.JSValue, generation: c.JSValue };
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
fn equals(engine: *Engine, value: c.JSValue, text: [:0]const u8) !bool {
    const expected = try engine.checked(c.JS_NewString(engine.context, text));
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, value, expected);
}
fn intrinsics(scope: *Scope, state: c.JSValue) !awaiting.Intrinsics {
    return .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
}
fn wait(engine: *Engine, state: c.JSValue, pending: c.JSValue, stage: c_int) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var captured = try intrinsics(&scope, state);
    return awaiting.continueWith(advance, engine, &captured, state, pending, stage);
}
pub fn admit(engine: *Engine, captured: *awaiting.Intrinsics, tokens: Tokens, tx: c.JSValue, conversation: c.JSValue, draft: c.JSValue, now: c.JSValue, modes: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "promiseConstructor", captured.constructor }, .{ "promiseResolve", captured.resolve }, .{ "promiseThen", captured.then_function }, .{ "liveToken", tokens.live }, .{ "inboxToken", tokens.inbox }, .{ "userToken", tokens.user }, .{ "generationToken", tokens.generation }, .{ "tx", tx }, .{ "conversation", conversation }, .{ "draft", draft }, .{ "now", now }, .{ "modes", modes } }) |field| try put(engine, state, field[0], field[1]);
    const request = try scope.get(draft, "requestId");
    if (!c.JS_IsUndefined(request)) {
        const pending = try scope.invoke(tx, "submissionByRequest", &.{ conversation, request });
        return wait(engine, state, pending, 1);
    }
    return readLive(engine, state);
}
fn readLive(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try scope.invoke(try scope.get(state, "tx"), "doc", &.{ try scope.get(state, "liveToken"), try scope.get(state, "conversation") });
    return wait(engine, state, pending, 2);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 1) {
        if (!c.JS_IsUndefined(value)) {
            const existing_type = try scope.get(value, "type");
            const draft = try scope.get(state, "draft");
            if (!c.JS_IsStrictEqual(engine.context, existing_type, try scope.get(draft, "type"))) {
                const message = try scope.own(try @import("native_utf16.zig").concat(engine, &.{ try scope.text("Request "), try scope.get(draft, "requestId"), try scope.text(" already identifies a submission of type "), existing_type }));
                const bytes = try engine.toString(message);
                defer engine.gpa.free(bytes);
                return @import("native_sdk.zig").sourceError(engine, bytes);
            }
            return vm.get(engine, value, "id");
        }
        return readLive(engine, state);
    }
    if (stage == 2) {
        try put(engine, state, "live", value);
        const draft = try scope.get(state, "draft");
        const busy = !c.JS_IsUndefined(try scope.get(value, "run"));
        if (busy and try equals(engine, try scope.get(draft, "type"), "input") and try equals(engine, try scope.get(draft, "whenBusy"), "reject")) {
            const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
            const constructor = try scope.get(exports, "ConversationBusy");
            var args = [_]c.JSValue{try scope.get(state, "conversation")};
            const exception = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args));
            return engine.checked(c.JS_Throw(engine.context, exception));
        }
        if (busy) return createQueued(engine, state);
        var captured = try intrinsics(&scope, state);
        const pending = try scope.own(try @import("native_durable_inbox.zig").prepare(engine, &captured, try scope.get(state, "tx"), try scope.get(state, "conversation"), try scope.get(state, "modes"), try scope.get(state, "inboxToken")));
        return wait(engine, state, pending, 3);
    }
    if (stage == 3) {
        try put(engine, state, "boundary", value);
        const items = try scope.get(try scope.get(value, "inbox"), "items");
        if (try vm.length(engine, items) > 0) return createQueued(engine, state);
        return placeIdle(engine, state);
    }
    if (stage == 4) {
        try put(engine, state, "id", try scope.get(value, "id"));
        const boundary = try scope.get(state, "boundary");
        if (!c.JS_IsUndefined(boundary)) return appendQueued(engine, state, try scope.get(boundary, "inbox"));
        const pending = try scope.invoke(try scope.get(state, "tx"), "doc", &.{ try scope.get(state, "inboxToken"), try scope.get(state, "conversation") });
        return wait(engine, state, pending, 5);
    }
    if (stage == 5) return appendQueued(engine, state, value);
    if (stage == 6) {
        const users = try scope.get(value, "users");
        if (try vm.length(engine, users) > 0) {
            var captured_intrinsics = try intrinsics(&scope, state);
            const pending = try scope.own(try @import("native_durable_generation_live.zig").startRun(engine, &captured_intrinsics, try scope.get(state, "tx"), try scope.get(state, "conversation"), try scope.get(state, "live"), users, try scope.get(state, "generationToken")));
            return wait(engine, state, pending, 11);
        }
        return vm.get(engine, state, "id");
    }
    if (stage == 7) {
        const record = try scope.own(try createRecord(engine, &scope, state, "done"));
        try put(engine, record, "entry", try scope.get(value, "id"));
        const pending = try scope.invoke(try scope.get(state, "tx"), "createSubmission", &.{record});
        return wait(engine, state, pending, 8);
    }
    if (stage == 8) return vm.get(engine, value, "id");
    if (stage == 9) {
        const record = try scope.own(try createRecord(engine, &scope, state, "placed"));
        try put(engine, record, "entry", try scope.get(value, "id"));
        const pending = try scope.invoke(try scope.get(state, "tx"), "createSubmission", &.{record});
        return wait(engine, state, pending, 10);
    }
    if (stage == 10) {
        const id = try scope.get(value, "id");
        try put(engine, state, "id", id);
        const inputs = try scope.own(try vm.array(engine));
        try js.push(engine, inputs, id);
        var captured_intrinsics = try intrinsics(&scope, state);
        const pending = try scope.own(try @import("native_durable_generation_live.zig").startRun(engine, &captured_intrinsics, try scope.get(state, "tx"), try scope.get(state, "conversation"), try scope.get(state, "live"), inputs, try scope.get(state, "generationToken")));
        return wait(engine, state, pending, 11);
    }
    if (stage == 11) return vm.get(engine, state, "id");
    return error.InvalidSubmissionContinuation;
}
fn createRecord(engine: *Engine, scope: *Scope, state: c.JSValue, status: [:0]const u8) !c.JSValue {
    const record = try vm.object(engine);
    errdefer engine.freeValue(record);
    try put(engine, record, "conversationId", try scope.get(state, "conversation"));
    const draft = try scope.get(state, "draft");
    const request = try scope.get(draft, "requestId");
    if (!c.JS_IsUndefined(request)) try put(engine, record, "requestId", request);
    try put(engine, record, "type", try scope.get(draft, "type"));
    try put(engine, record, "status", try scope.text(status));
    return record;
}
fn createQueued(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const record = try scope.own(try createRecord(engine, &scope, state, "queued"));
    const pending = try scope.invoke(try scope.get(state, "tx"), "createSubmission", &.{record});
    return wait(engine, state, pending, 4);
}
fn placeIdle(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const draft = try scope.get(state, "draft");
    const tx = try scope.get(state, "tx");
    const conversation = try scope.get(state, "conversation");
    if (try equals(engine, try scope.get(draft, "type"), "write")) {
        const entry = try scope.get(draft, "entry");
        const boundary = try scope.get(state, "boundary");
        if (try @import("native_durable_inbox.zig").isStale(engine, try scope.get(boundary, "head"), entry)) {
            const record = try scope.own(try createRecord(engine, &scope, state, "unanswered"));
            try put(engine, record, "reason", try scope.text("stale"));
            const pending = try scope.invoke(tx, "createSubmission", &.{record});
            return wait(engine, state, pending, 8);
        }
        const pending = try scope.invoke(tx, "appendEntry", &.{ conversation, entry });
        return wait(engine, state, pending, 7);
    }
    const message = try scope.own(try vm.object(engine));
    try put(engine, message, "role", try scope.text("user"));
    try put(engine, message, "content", try scope.get(draft, "content"));
    try put(engine, message, "timestamp", try scope.get(state, "now"));
    const model = try scope.own(try vm.array(engine));
    try js.push(engine, model, message);
    const entry = try scope.own(try vm.object(engine));
    try put(engine, entry, "model", model);
    const pending = try scope.invoke(tx, "appendEntry", &.{ try scope.get(state, "userToken"), conversation, entry });
    return wait(engine, state, pending, 9);
}
fn appendQueued(engine: *Engine, state: c.JSValue, inbox: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const draft = try scope.get(state, "draft");
    const write = try equals(engine, try scope.get(draft, "type"), "write");
    const options = try scope.own(try vm.object(engine));
    try put(engine, options, "omitUndefinedProperties", c.pi_js_bool(engine.context, 1));
    const value = try scope.own(try @import("native_chord_json.zig").copyJson(engine, try scope.get(draft, if (write) "entry" else "content"), options));
    const item = try scope.own(try vm.object(engine));
    try put(engine, item, "id", try scope.get(state, "id"));
    try put(engine, item, "mode", try scope.text(if (write) "write" else if (try equals(engine, try scope.get(draft, "whenBusy"), "steer")) "steer" else "followUp"));
    try put(engine, item, if (write) "entry" else "content", value);
    try js.push(engine, try scope.get(inbox, "items"), item);
    const boundary = try scope.get(state, "boundary");
    if (c.JS_IsUndefined(boundary)) return vm.get(engine, state, "id");
    var captured = try intrinsics(&scope, state);
    const pending = try scope.own(try @import("native_durable_inbox.zig").apply(engine, &captured, try scope.get(state, "tx"), boundary, true, try scope.get(state, "now"), try scope.get(state, "userToken")));
    return wait(engine, state, pending, 6);
}
