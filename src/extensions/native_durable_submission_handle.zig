//! Public submission handles over the native Session mutation line.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const durable = @import("native_durable.zig");
const awaiting = @import("native_durable_await.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const HandleState = struct { engine: *Engine, state: c.JSValue };
fn finalizeHandle(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const owner: *HandleState = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_durable_submission_class) orelse return));
    c.JS_FreeValueRT(runtime, owner.state);
    engine.gpa.destroy(owner);
}
fn markHandle(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const owner: *HandleState = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_durable_submission_class) orelse return));
    c.JS_MarkValue(runtime, owner.state, marker);
}
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
fn captured(scope: *Scope, state: c.JSValue) !awaiting.Intrinsics {
    return .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
}
fn wait(engine: *Engine, state: c.JSValue, pending: c.JSValue, stage: c_int) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var intrinsics = try captured(&scope, state);
    return awaiting.continueWith(advance, engine, &intrinsics, state, pending, stage);
}
fn stateObject(engine: *Engine, session: c.JSValue, options: c.JSValue, context: c.JSValue) !c.JSValue {
    const state = try vm.object(engine);
    errdefer engine.freeValue(state);
    var intrinsics = try awaiting.Intrinsics.init(engine);
    defer intrinsics.deinit(engine);
    inline for (.{ .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function }, .{ "session", session }, .{ "options", options }, .{ "context", context } }) |field| try put(engine, state, field[0], field[1]);
    return state;
}
pub fn submit(engine: *Engine, session: c.JSValue, options: c.JSValue, conversation: c.JSValue, draft: c.JSValue, context: c.JSValue) !c.JSValue {
    const manager = try @import("native_durable_tasks.zig").getManager(engine, session);
    try manager.@"resume"();
    const state = try stateObject(engine, session, options, context);
    defer engine.freeValue(state);
    try put(engine, state, "conversation", conversation);
    try put(engine, state, "draft", draft);
    var data = [_]c.JSValue{state};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, admitCommit, "", 1, 0, data.len, &data));
    defer engine.freeValue(callback);
    const native = try durable.state(engine, session);
    const pending = try durable.sessionDispatch(native, session, .commit, &.{ callback, context });
    defer engine.freeValue(pending);
    return wait(engine, state, pending, 1);
}
fn admitCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return admitDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| durable.reject(engine, err);
}
fn admitDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    const options = try scope.get(state, "options");
    const settings = try scope.own(try @import("native_durable_agent.zig").runtimeSettings(engine, options));
    const clock = try scope.get(options, "now");
    const now = if (c.JS_IsFunction(engine.context, clock)) try scope.own(try engine.checked(c.JS_Call(engine.context, clock, c.pi_js_undefined(), 0, null))) else now: {
        const date = try scope.own(try js.global(engine, "Date"));
        break :now try scope.invoke(date, "now", &.{});
    };
    var intrinsics = try captured(&scope, state);
    return @import("native_durable_submissions.zig").admit(engine, &intrinsics, .{ .live = try scope.get(exports, "LiveDoc"), .inbox = try scope.get(exports, "InboxDoc"), .user = try scope.get(exports, "UserEntry"), .generation = try scope.get(exports, "GenerationTask") }, tx, try scope.get(state, "conversation"), try scope.get(state, "draft"), now, settings);
}
fn ensureHandleClass(engine: *Engine) !void {
    if (engine.native_durable_submission_class == 0) _ = c.JS_NewClassID(engine.runtime, &engine.native_durable_submission_class);
    if (engine.native_durable_submission_prototype_ready) return;
    const definition: c.JSClassDef = .{ .class_name = "SubmissionHandle", .finalizer = finalizeHandle, .gc_mark = markHandle, .call = null, .exotic = null };
    if (!c.JS_IsRegisteredClass(engine.runtime, engine.native_durable_submission_class) and c.JS_NewClass(engine.runtime, engine.native_durable_submission_class, &definition) < 0) return error.OutOfMemory;
    const prototype = try vm.object(engine);
    errdefer engine.freeValue(prototype);
    const ctor = try engine.checked(c.JS_NewCFunction2(engine.context, handleConstructor, "SubmissionHandle", 2, c.JS_CFUNC_constructor, 0));
    defer engine.freeValue(ctor);
    if (c.JS_SetConstructor(engine.context, ctor, prototype) < 0) return js.capture(engine);
    inline for (.{ "status", "wait", "abort" }, 0..) |name, index| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, handleMethod, name, 1, @intCast(index)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    c.JS_SetClassProto(engine.context, engine.native_durable_submission_class, prototype);
    engine.native_durable_submission_prototype_ready = true;
}
fn makeHandle(engine: *Engine, id: c.JSValue, host: c.JSValue, new_target: c.JSValue) !c.JSValue {
    try ensureHandleClass(engine);
    const prototype = if (c.JS_IsUndefined(new_target)) c.pi_js_undefined() else try vm.get(engine, new_target, "prototype");
    defer engine.freeValue(prototype);
    const object = try engine.checked(if (c.JS_IsUndefined(prototype)) c.JS_NewObjectClass(engine.context, engine.native_durable_submission_class) else c.JS_NewObjectProtoClass(engine.context, prototype, engine.native_durable_submission_class));
    errdefer engine.freeValue(object);
    try put(engine, object, "id", id);
    const private = try vm.object(engine);
    defer engine.freeValue(private);
    try put(engine, private, "host", host);
    const owner = try engine.gpa.create(HandleState);
    owner.* = .{ .engine = engine, .state = c.JS_DupValue(engine.context, private) };
    _ = c.JS_SetOpaque(object, owner);
    return object;
}
fn handleConstructor(context: ?*c.JSContext, new_target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return makeHandle(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), new_target) catch |err| durable.reject(engine, err);
}
pub fn handle(engine: *Engine, session: c.JSValue, options: c.JSValue, id: c.JSValue) !c.JSValue {
    const base = try stateObject(engine, session, options, c.pi_js_undefined());
    defer engine.freeValue(base);
    const host = try vm.object(engine);
    defer engine.freeValue(host);
    inline for (.{ "status", "wait", "abort" }, 0..) |name, index| {
        var data = [_]c.JSValue{base};
        try @import("native_tool_info.zig").putData(engine, host, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, backendMethod, name, 2, @intCast(index), data.len, &data)));
    }
    return makeHandle(engine, id, host, c.pi_js_undefined());
}
fn backendMethod(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, method: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return handleCall(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), method, if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| durable.rejectedPromise(engine, err);
}
pub fn get(engine: *Engine, session: c.JSValue, options: c.JSValue, id: c.JSValue, context: c.JSValue) !c.JSValue {
    const state = try stateObject(engine, session, options, context);
    defer engine.freeValue(state);
    try put(engine, state, "id", id);
    try put(engine, state, "method", c.JS_NewInt32(engine.context, 3));
    var data = [_]c.JSValue{state};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, readLine, "", 0, 0, data.len, &data));
    defer engine.freeValue(callback);
    const pending = try durable.enqueue(engine, session, callback);
    defer engine.freeValue(pending);
    return wait(engine, state, pending, 3);
}
fn handleMethod(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, method: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const owner: *HandleState = @ptrCast(@alignCast(c.JS_GetOpaque(receiver, engine.native_durable_submission_class) orelse {
        const exception = c.JS_ThrowTypeError(engine.context, "Cannot read private member #submissions from an object whose class did not declare it");
        if (method == 2) {
            _ = engine.checked(exception) catch {};
            return durable.rejectedPromise(engine, error.JavaScriptException);
        }
        return exception;
    }));
    return delegateHandle(engine, owner.state, receiver, method, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| if (method == 2) durable.rejectedPromise(engine, err) else durable.reject(engine, err);
}
fn delegateHandle(engine: *Engine, private: c.JSValue, receiver: c.JSValue, method: c_int, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const host = try scope.get(private, "host");
    const id = try scope.get(receiver, "id");
    const value = try scope.invoke(host, switch (method) {
        0 => "status",
        1 => "wait",
        else => "abort",
    }, &.{ id, context });
    if (method != 2) return c.JS_DupValue(engine.context, value);
    const state = try scope.own(try stateObject(engine, c.pi_js_undefined(), c.pi_js_undefined(), context));
    try put(engine, state, "receiver", receiver);
    return wait(engine, state, value, 8);
}
fn handleCall(engine: *Engine, base: c.JSValue, id: c.JSValue, method: c_int, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try stateObject(engine, try scope.get(base, "session"), try scope.get(base, "options"), context));
    try put(engine, state, "id", id);
    try put(engine, state, "method", c.JS_NewInt32(engine.context, method));
    const session = try scope.get(state, "session");
    if (method == 1) try (try @import("native_durable_tasks.zig").getManager(engine, session)).@"resume"();
    if (method == 2) {
        var data = [_]c.JSValue{state};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, abortCommit, "", 1, 0, data.len, &data)));
        const native = try durable.state(engine, session);
        return durable.sessionDispatch(native, session, .commit, &.{ callback, context });
    }
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, readLine, "", 0, 0, data.len, &data)));
    const pending = try scope.own(try durable.enqueue(engine, session, callback));
    return wait(engine, state, pending, 3);
}
fn readLine(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return readRecord(engine, data[0]) catch |err| durable.reject(engine, err);
}
fn readRecord(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try durable.checkCancellation(engine, try scope.get(state, "context"));
    const native = try durable.state(engine, try scope.get(state, "session"));
    const pending = try scope.invoke(native.parent, "submission", &.{ try scope.get(state, "id"), try scope.get(state, "context") });
    return wait(engine, state, pending, 2);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    if (stage == 4) {
        try cleanup(engine, state);
        if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
        return c.JS_DupValue(engine.context, value);
    }
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 1) return handle(engine, try scope.get(state, "session"), try scope.get(state, "options"), value);
    if (stage == 2) {
        if (c.JS_IsUndefined(value)) {
            var method: i32 = 0;
            if (c.JS_ToInt32(engine.context, &method, try scope.get(state, "method")) < 0) return js.capture(engine);
            if (method == 3) return c.pi_js_undefined();
            const id = try engine.toString(try scope.get(state, "id"));
            defer engine.gpa.free(id);
            const message = try std.fmt.allocPrint(engine.gpa, "Submission {s} does not exist", .{id});
            defer engine.gpa.free(message);
            return @import("native_sdk.zig").sourceError(engine, message);
        }
        var method: i32 = 0;
        if (c.JS_ToInt32(engine.context, &method, try scope.get(state, "method")) < 0) return js.capture(engine);
        return if (method == 1) boxedWait(engine, state, value) else c.JS_DupValue(engine.context, value);
    }
    if (stage == 3) {
        var method: i32 = 0;
        if (c.JS_ToInt32(engine.context, &method, try scope.get(state, "method")) < 0) return js.capture(engine);
        if (method == 0) return c.JS_DupValue(engine.context, value);
        if (method == 3) return if (c.JS_IsUndefined(value)) c.pi_js_undefined() else handle(engine, try scope.get(state, "session"), try scope.get(state, "options"), try scope.get(state, "id"));
        const pending = try scope.get(value, "promise");
        return wait(engine, state, pending, 4);
    }
    if (stage == 5) {
        if (c.JS_IsUndefined(value)) return engine.checked(c.JS_NewString(engine.context, "not_found"));
        const status = try scope.get(value, "status");
        if (!c.JS_IsStrictEqual(engine.context, status, try scope.text("queued"))) return engine.checked(c.JS_NewString(engine.context, if (c.JS_IsStrictEqual(engine.context, status, try scope.text("placed"))) "already_placed" else "settled"));
        const tx = try scope.get(state, "tx");
        const settlement = try scope.own(try vm.object(engine));
        try put(engine, settlement, "status", try scope.text("unanswered"));
        try put(engine, settlement, "reason", try scope.text("aborted"));
        _ = try scope.invoke(tx, "settleSubmission", &.{ try scope.get(state, "id"), settlement });
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        const pending = try scope.invoke(tx, "doc", &.{ try scope.get(exports, "InboxDoc"), try scope.get(value, "conversationId") });
        return wait(engine, state, pending, 6);
    }
    if (stage == 6) {
        const items = try scope.get(value, "items");
        const id = try scope.get(state, "id");
        for (0..try vm.length(engine, items)) |index| {
            const item = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, items, @intCast(index))));
            if (c.JS_IsStrictEqual(engine.context, try scope.get(item, "id"), id)) {
                _ = try scope.invoke(items, "splice", &.{ c.JS_NewFloat64(engine.context, @floatFromInt(index)), c.JS_NewInt32(engine.context, 1) });
                break;
            }
        }
        return engine.checked(c.JS_NewString(engine.context, "aborted"));
    }
    if (stage == 7) return c.pi_js_undefined();
    if (stage == 8) {
        const missing = try scope.text("not_found");
        if (c.JS_IsStrictEqual(engine.context, value, missing)) {
            const id = try engine.toString(try scope.get(try scope.get(state, "receiver"), "id"));
            defer engine.gpa.free(id);
            const message = try std.fmt.allocPrint(engine.gpa, "Submission {s} does not exist", .{id});
            defer engine.gpa.free(message);
            return @import("native_sdk.zig").sourceError(engine, message);
        }
        return c.JS_DupValue(engine.context, value);
    }
    return error.InvalidPublicSubmissionContinuation;
}
fn settled(engine: *Engine, record: c.JSValue) !bool {
    const status = try vm.get(engine, record, "status");
    defer engine.freeValue(status);
    const done = try engine.checked(c.JS_NewString(engine.context, "done"));
    defer engine.freeValue(done);
    const unanswered = try engine.checked(c.JS_NewString(engine.context, "unanswered"));
    defer engine.freeValue(unanswered);
    return c.JS_IsStrictEqual(engine.context, status, done) or c.JS_IsStrictEqual(engine.context, status, unanswered);
}
fn boxedWait(engine: *Engine, state: c.JSValue, record: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const box = try vm.object(engine);
    errdefer engine.freeValue(box);
    if (try settled(engine, record)) {
        try put(engine, box, "promise", record);
        return box;
    }
    const session = try scope.get(state, "session");
    const native = try durable.state(engine, session);
    if (native.closing) return closed(engine, native);
    var functions: [2]c.JSValue = undefined;
    const pending = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions)));
    defer for (functions) |function| engine.freeValue(function);
    try put(engine, state, "resolve", functions[0]);
    try put(engine, state, "reject", functions[1]);
    const signal = try scope.get(try scope.get(state, "context"), "abortSignal");
    if (!c.JS_IsUndefined(signal)) {
        try put(engine, state, "abortSignal", signal);
        if (c.JS_ToBool(engine.context, try scope.get(signal, "aborted")) != 0) {
            _ = try scope.own(try settle(engine, state, try scope.get(signal, "reason"), true));
            try put(engine, box, "promise", pending);
            return box;
        }
        var abort_data = [_]c.JSValue{state};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, onAbort, "", 0, 0, abort_data.len, &abort_data)));
        try put(engine, state, "onAbort", callback);
        const options = try scope.own(try vm.object(engine));
        try put(engine, options, "once", c.pi_js_bool(engine.context, 1));
        _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), callback, options });
    }
    var data = [_]c.JSValue{state};
    const publication = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, onPublication, "", 1, 0, data.len, &data)));
    const closing = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, onClosing, "", 0, 0, data.len, &data)));
    try put(engine, state, "unsubscribeCommits", try scope.invoke(session, "subscribeCommits", &.{publication}));
    try put(engine, state, "unsubscribeClose", try scope.invoke(session, "subscribeClose", &.{closing}));
    try put(engine, box, "promise", pending);
    return box;
}
fn closed(engine: *Engine, native: *durable.State) !c.JSValue {
    if (native.failure_reason) |reason| return engine.checked(c.JS_Throw(engine.context, try @import("native_durable_errors.zig").sessionFailed(engine, reason)));
    return @import("native_sdk.zig").sourceError(engine, "Harness is closed");
}
fn onPublication(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return published(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| durable.reject(engine, err);
}
fn published(engine: *Engine, state: c.JSValue, event: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const changes = try scope.get(event, "changes");
    const id = try scope.get(state, "id");
    const submission = try scope.text("submission");
    for (0..try vm.length(engine, changes)) |index| {
        const change = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, changes, @intCast(index))));
        if (!c.JS_IsStrictEqual(engine.context, try scope.get(change, "type"), submission)) continue;
        const record = try scope.get(change, "value");
        if (c.JS_IsStrictEqual(engine.context, try scope.get(record, "id"), id) and try settled(engine, record)) return settle(engine, state, record, false);
    }
    return c.pi_js_undefined();
}
fn onClosing(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return closingWait(engine, data[0]) catch |err| durable.reject(engine, err);
}
fn closingWait(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const native = try durable.state(engine, try scope.get(state, "session"));
    const rejected = closed(engine, native) catch |err| {
        if (err != error.JavaScriptException) return err;
        return settle(engine, state, engine.captured_exception orelse return err, true);
    };
    engine.freeValue(rejected);
    return error.ExpectedClosedException;
}
fn settle(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (c.JS_ToBool(engine.context, try scope.get(state, "settled")) != 0) return c.pi_js_undefined();
    try put(engine, state, "settled", c.pi_js_bool(engine.context, 1));
    const callback = try scope.get(state, if (rejected) "reject" else "resolve");
    var args = [_]c.JSValue{value};
    const result = try engine.checked(c.JS_Call(engine.context, callback, c.pi_js_undefined(), 1, &args));
    defer engine.freeValue(result);
    try cleanup(engine, state);
    return c.pi_js_undefined();
}
fn cleanup(engine: *Engine, state: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const signal = try scope.get(state, "abortSignal");
    const abort_callback = try scope.get(state, "onAbort");
    if (!c.JS_IsUndefined(signal) and c.JS_IsFunction(engine.context, abort_callback)) {
        _ = try scope.invoke(signal, "removeEventListener", &.{ try scope.text("abort"), abort_callback });
        try put(engine, state, "onAbort", c.pi_js_undefined());
    }
    inline for (.{ "unsubscribeCommits", "unsubscribeClose" }) |key| {
        const callback = try scope.get(state, key);
        if (c.JS_IsFunction(engine.context, callback)) {
            const result = try scope.own(try engine.checked(c.JS_Call(engine.context, callback, c.pi_js_undefined(), 0, null)));
            _ = result;
            try put(engine, state, key, c.pi_js_undefined());
        }
    }
}
fn abortCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return abortDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| durable.reject(engine, err);
}
fn abortDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "tx", tx);
    const pending = try scope.invoke(tx, "submission", &.{try scope.get(state, "id")});
    return wait(engine, state, pending, 5);
}
pub fn compact(engine: *Engine, session: c.JSValue, options: c.JSValue, conversation: c.JSValue, instructions: c.JSValue, context: c.JSValue) !c.JSValue {
    try (try @import("native_durable_tasks.zig").getManager(engine, session)).@"resume"();
    const state = try stateObject(engine, session, options, context);
    defer engine.freeValue(state);
    try put(engine, state, "conversation", conversation);
    try put(engine, state, "instructions", instructions);
    var data = [_]c.JSValue{state};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, compactCommit, "", 1, 0, data.len, &data));
    defer engine.freeValue(callback);
    return durable.sessionDispatch(try durable.state(engine, session), session, .commit, &.{ callback, context });
}
fn compactCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return compactDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| durable.reject(engine, err);
}
fn compactDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input = try scope.own(try vm.object(engine));
    try put(engine, input, "reason", try scope.text("manual"));
    const instructions = try scope.get(state, "instructions");
    if (!c.JS_IsUndefined(instructions)) try put(engine, input, "instructions", instructions);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    var intrinsics = try captured(&scope, state);
    return @import("native_durable_compaction_task.zig").createCompaction(engine, &intrinsics, tx, try scope.get(state, "conversation"), input, c.pi_js_undefined(), try scope.get(exports, "CompactionTask"), try scope.get(exports, "LiveDoc"));
}
pub fn reset(engine: *Engine, session: c.JSValue, options: c.JSValue, conversation: c.JSValue, handoff: c.JSValue, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const entry = try scope.own(try vm.object(engine));
    try put(engine, entry, "kind", try scope.text("pi.reset"));
    try put(engine, entry, "head", try scope.text("self"));
    if (!c.JS_IsUndefined(handoff)) {
        const model = try scope.own(try vm.array(engine));
        const message = try scope.own(try vm.object(engine));
        try put(engine, message, "role", try scope.text("user"));
        try put(engine, message, "content", handoff);
        const clock = try scope.get(options, "now");
        const now = if (c.JS_IsFunction(engine.context, clock)) try scope.own(try engine.checked(c.JS_Call(engine.context, clock, c.pi_js_undefined(), 0, null))) else now: {
            const date = try scope.own(try js.global(engine, "Date"));
            break :now try scope.invoke(date, "now", &.{});
        };
        try put(engine, message, "timestamp", now);
        try js.push(engine, model, message);
        try put(engine, entry, "model", model);
    }
    const draft = try scope.own(try vm.object(engine));
    try put(engine, draft, "type", try scope.text("write"));
    try put(engine, draft, "entry", entry);
    const pending = try scope.own(try submit(engine, session, options, conversation, draft, context));
    const state = try scope.own(try stateObject(engine, session, options, context));
    return wait(engine, state, pending, 7);
}
fn onAbort(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return abortedWait(engine, data[0]) catch |err| durable.reject(engine, err);
}
fn abortedWait(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return settle(engine, state, try scope.get(try scope.get(state, "abortSignal"), "reason"), true);
}
