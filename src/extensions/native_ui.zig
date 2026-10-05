//! Standard extension dialogs and retained actions over the native worker wire.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;

pub const Bridge = struct {
    context: ?*anyopaque = null,
    request: *const fn (?*anyopaque, u32, []const u8, []const u8) anyerror!void,
    action: *const fn (?*anyopaque, []const u8, []const u8) anyerror!void,
    cancel: *const fn (?*anyopaque, u32) anyerror!void,
};

const Method = enum(c_int) { select, confirm, input, editor, notify, setStatus, setTitle, setEditorText, pasteToEditor, getEditorText, setWidget, setWorkingMessage, setWorkingVisible, setHiddenThinkingLabel, custom };
const Pending = struct {
    id: u32,
    generation: u32,
    confirm: bool,
    resolve: c.JSValue,
    reject: c.JSValue,
    listener: c.JSValue,
    signals: [2]c.JSValue = undefined,
    signal_count: usize = 0,
    deadline: ?i64 = null,
};

pub const Manager = struct {
    engine: *engine_mod.Engine,
    token: c.JSValue,
    add_listener: c.JSValue,
    remove_listener: c.JSValue,
    abort_text: c.JSValue,
    editor_text: c.JSValue,
    bridge: ?Bridge = null,
    generation: u32 = 0,
    active: bool = false,
    has_ui: bool = false,
    signal: ?c.JSValue = null,
    next_id: u32 = 1,
    pending: std.ArrayList(Pending) = .empty,

    pub fn init(engine: *engine_mod.Engine) !*Manager {
        if (engine.native_ui_manager != null) return error.NativeUiAlreadyAttached;
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const constructor = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "AbortSignal"));
        defer engine.freeValue(constructor);
        const prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, constructor, "prototype"));
        defer engine.freeValue(prototype);
        const token = try engine.checked(c.JS_NewObject(engine.context));
        errdefer engine.freeValue(token);
        const add = try engine.checked(c.JS_GetPropertyStr(engine.context, prototype, "addEventListener"));
        errdefer engine.freeValue(add);
        const remove = try engine.checked(c.JS_GetPropertyStr(engine.context, prototype, "removeEventListener"));
        errdefer engine.freeValue(remove);
        const abort_text = try engine.checked(c.JS_NewString(engine.context, "abort"));
        errdefer engine.freeValue(abort_text);
        const editor_text = try engine.checked(c.JS_NewString(engine.context, ""));
        errdefer engine.freeValue(editor_text);
        const self = try engine.gpa.create(Manager);
        self.* = .{ .engine = engine, .token = token, .add_listener = add, .remove_listener = remove, .abort_text = abort_text, .editor_text = editor_text };
        engine.native_ui_manager = self;
        return self;
    }

    pub fn deinit(self: *Manager) void {
        self.bridge = null;
        self.finish();
        self.engine.native_ui_manager = null;
        self.pending.deinit(self.engine.gpa);
        for ([_]c.JSValue{ self.token, self.add_listener, self.remove_listener, self.abort_text, self.editor_text }) |value| self.engine.freeValue(value);
        self.engine.gpa.destroy(self);
    }

    pub fn begin(self: *Manager, generation: u32, snapshot: ?c.JSValue, signal: ?c.JSValue) !void {
        self.finish();
        self.generation = generation;
        self.has_ui = false;
        if (snapshot) |context| {
            const available = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, context, "hasUI"));
            defer self.engine.freeValue(available);
            self.has_ui = c.JS_ToBool(self.engine.context, available) != 0;
            const text = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, context, "editorText"));
            defer self.engine.freeValue(text);
            if (c.JS_IsString(text)) {
                self.engine.freeValue(self.editor_text);
                self.editor_text = c.JS_DupValue(self.engine.context, text);
            }
        }
        if (signal) |value| self.signal = c.JS_DupValue(self.engine.context, value);
        self.active = true;
    }

    pub fn finish(self: *Manager) void {
        while (self.pending.items.len > 0) self.cancel(self.pending.items[self.pending.items.len - 1].id) catch {};
        if (self.signal) |signal| self.engine.freeValue(signal);
        self.signal = null;
        self.active = false;
    }

    pub fn createObject(self: *Manager) !c.JSValue {
        const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
        errdefer self.engine.freeValue(object);
        var data = [_]c.JSValue{ self.token, c.JS_NewInt64(self.engine.context, self.generation) };
        defer self.engine.freeValue(data[1]);
        inline for (std.meta.fields(Method)) |field| {
            const name: [:0]const u8 = field.name;
            const length: c_int = switch (@as(Method, @enumFromInt(field.value))) {
                .select, .confirm, .setStatus, .setWidget => 2,
                .getEditorText => 0,
                else => 1,
            };
            const function = try self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, invoke, name.ptr, length, @intCast(field.value), data.len, &data));
            if (c.JS_DefinePropertyValueStr(self.engine.context, object, name.ptr, function, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        }
        return object;
    }

    fn current(engine: *engine_mod.Engine, data: [*c]c.JSValue) !*Manager {
        const self: *Manager = @ptrCast(@alignCast(engine.native_ui_manager orelse return error.StaleNativeUi));
        var generation: i64 = 0;
        if (c.JS_ToInt64(engine.context, &generation, data[1]) < 0) return error.JavaScriptException;
        if (!self.active or generation != self.generation or !c.JS_IsStrictEqual(engine.context, self.token, data[0])) return error.StaleNativeUi;
        return self;
    }

    fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        const self = current(engine, data) catch |err| return fail(engine, err);
        const method: Method = @enumFromInt(magic);
        const args: []c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
        if (@intFromEnum(method) <= @intFromEnum(Method.editor) or method == .custom) return self.dialog(method, args) catch |err| fail(engine, err);
        return self.action(method, args) catch |err| fail(engine, err);
    }

    fn fail(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
        return c.JS_ThrowTypeError(engine.context, "Native UI: %s", @as([*:0]const u8, @errorName(err)));
    }

    fn call(self: *Manager, function: c.JSValue, value: c.JSValue) !void {
        var args = [_]c.JSValue{value};
        const result = try self.engine.checked(c.JS_Call(self.engine.context, function, c.pi_js_undefined(), 1, &args));
        self.engine.freeValue(result);
    }

    fn rejectError(self: *Manager, reject: c.JSValue, err: anyerror) !void {
        _ = fail(self.engine, err);
        const reason = c.JS_GetException(self.engine.context);
        defer self.engine.freeValue(reason);
        try self.call(reject, reason);
    }

    fn defineField(self: *Manager, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        if (c.JS_DefinePropertyValueStr(self.engine.context, object, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }

    fn stringArgument(self: *Manager, args: []c.JSValue, index: usize, default: ?[]const u8) !c.JSValue {
        if (default) |fallback| if (index >= args.len or c.JS_IsUndefined(args[index]) or c.JS_IsNull(args[index])) return self.engine.checked(c.JS_NewStringLen(self.engine.context, fallback.ptr, fallback.len));
        const bytes = try self.engine.toString(if (index < args.len) args[index] else c.pi_js_undefined());
        defer self.engine.gpa.free(bytes);
        return self.engine.checked(c.JS_NewStringLen(self.engine.context, bytes.ptr, bytes.len));
    }

    fn isAborted(self: *Manager, signal: c.JSValue) !bool {
        if (c.JS_GetOpaque(signal, self.engine.abort_signal_class) == null) return error.InvalidNativeDialogSignal;
        // Native signal branding precedes observable property access.
        const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, signal, "aborted"));
        defer self.engine.freeValue(value);
        return c.JS_ToBool(self.engine.context, value) != 0;
    }

    fn dialog(self: *Manager, method: Method, args: []c.JSValue) !c.JSValue {
        var capabilities: [2]c.JSValue = undefined;
        const promise = try self.engine.checked(c.JS_NewPromiseCapability(self.engine.context, &capabilities));
        errdefer self.engine.freeValue(promise);
        var transferred = false;
        defer if (!transferred) for (capabilities) |function| self.engine.freeValue(function);
        if (method == .custom) {
            try self.rejectError(capabilities[1], error.NativeCustomUiNotImplemented);
            return promise;
        }
        if (!self.has_ui or self.bridge == null) {
            try self.call(capabilities[0], if (method == .confirm) c.pi_js_bool(self.engine.context, 0) else c.pi_js_undefined());
            return promise;
        }
        self.requestDialog(method, args, capabilities, &transferred) catch |err| {
            try self.rejectError(capabilities[1], err);
            return promise;
        };
        return promise;
    }

    fn requestDialog(self: *Manager, method: Method, args: []c.JSValue, capabilities: [2]c.JSValue, transferred: *bool) !void {
        if (self.pending.items.len >= 128 or self.next_id == std.math.maxInt(u32)) return error.NativeDialogLimit;
        const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(object);
        try self.defineField(object, "title", try self.stringArgument(args, 0, null));
        if (method == .select) {
            if (args.len < 2 or !c.JS_IsArray(args[1])) return error.InvalidNativeDialogOptions;
            const array = try self.engine.checked(c.JS_NewArray(self.engine.context));
            var consumed = false;
            defer if (!consumed) self.engine.freeValue(array);
            const raw_length = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, args[1], "length"));
            defer self.engine.freeValue(raw_length);
            var length: u32 = 0;
            if (c.JS_ToUint32(self.engine.context, &length, raw_length) < 0) return error.JavaScriptException;
            if (length > 4096) return error.NativeDialogOptionsLimit;
            for (0..length) |index| {
                const value = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, args[1], @intCast(index)));
                defer self.engine.freeValue(value);
                var item = [_]c.JSValue{value};
                if (c.JS_SetPropertyUint32(self.engine.context, array, @intCast(index), try self.stringArgument(&item, 0, null)) < 0) return error.JavaScriptException;
            }
            consumed = true;
            try self.defineField(object, "options", array);
        } else try self.defineField(object, if (method == .confirm) "message" else if (method == .editor) "prefill" else "placeholder", try self.stringArgument(args, 1, if (method == .confirm) null else ""));
        var requested_signal: ?c.JSValue = null;
        defer if (requested_signal) |signal| self.engine.freeValue(signal);
        var deadline: ?i64 = null;
        if (method != .editor and args.len > 2 and c.JS_IsObject(args[2])) {
            const signal = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, args[2], "signal"));
            if (c.JS_IsUndefined(signal) or c.JS_IsNull(signal)) self.engine.freeValue(signal) else requested_signal = signal;
            const timeout = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, args[2], "timeout"));
            defer self.engine.freeValue(timeout);
            if (!c.JS_IsUndefined(timeout)) {
                var number: f64 = 0;
                if (c.JS_ToFloat64(self.engine.context, &number, timeout) < 0) return error.JavaScriptException;
                if (std.math.isFinite(number) and number > 0) {
                    try self.defineField(object, "timeout", c.JS_NewFloat64(self.engine.context, number));
                    const io = self.engine.native_io orelse return error.NativeDialogClockUnavailable;
                    deadline = std.Io.Clock.awake.now(io).toMilliseconds() +| @as(i64, @intFromFloat(@min(@ceil(number), @as(f64, @floatFromInt(std.math.maxInt(i64) - 1024)))));
                }
            }
        }
        if (requested_signal) |signal| if (try self.isAborted(signal)) {
            try self.call(capabilities[0], if (method == .confirm) c.pi_js_bool(self.engine.context, 0) else c.pi_js_undefined());
            return;
        };
        if (self.signal) |signal| if (try self.isAborted(signal)) {
            try self.call(capabilities[0], if (method == .confirm) c.pi_js_bool(self.engine.context, 0) else c.pi_js_undefined());
            return;
        };
        const encoded = try self.engine.stringify(object);
        defer self.engine.gpa.free(encoded);
        var data = [_]c.JSValue{ self.token, c.JS_NewInt64(self.engine.context, self.generation), c.JS_NewInt64(self.engine.context, self.next_id) };
        defer self.engine.freeValue(data[1]);
        defer self.engine.freeValue(data[2]);
        const listener = try self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, onAbort, "native dialog abort", 0, 0, data.len, &data));
        var pending: Pending = .{ .id = self.next_id, .generation = self.generation, .confirm = method == .confirm, .resolve = capabilities[0], .reject = capabilities[1], .listener = listener, .deadline = deadline };
        var attached = false;
        errdefer if (!attached) {
            self.detach(&pending);
            self.engine.freeValue(listener);
        };
        if (self.signal) |signal| try self.listen(&pending, signal);
        if (requested_signal) |signal| if (self.signal == null or !c.JS_IsStrictEqual(self.engine.context, signal, self.signal.?)) try self.listen(&pending, signal);
        try self.pending.append(self.engine.gpa, pending);
        self.engine.host_ui_pending += 1;
        attached = true;
        transferred.* = true;
        self.next_id += 1;
        self.bridge.?.request(self.bridge.?.context, pending.id, @tagName(method), encoded) catch |err| {
            const removed = self.takePending(pending.id) orelse return;
            // Capabilities return to dialog() so rejection preserves the cause.
            transferred.* = false;
            var release = removed;
            self.detach(&release);
            self.engine.freeValue(release.listener);
            return err;
        };
    }

    fn listen(self: *Manager, pending: *Pending, signal: c.JSValue) !void {
        _ = try self.isAborted(signal);
        const options = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(options);
        try self.defineField(options, "once", c.pi_js_bool(self.engine.context, 1));
        var args = [_]c.JSValue{ self.abort_text, pending.listener, options };
        const result = try self.engine.checked(c.JS_Call(self.engine.context, self.add_listener, signal, args.len, &args));
        self.engine.freeValue(result);
        pending.signals[pending.signal_count] = c.JS_DupValue(self.engine.context, signal);
        pending.signal_count += 1;
    }

    fn detach(self: *Manager, pending: *Pending) void {
        for (pending.signals[0..pending.signal_count]) |signal| {
            var args = [_]c.JSValue{ self.abort_text, pending.listener };
            const result = c.JS_Call(self.engine.context, self.remove_listener, signal, args.len, &args);
            if (c.JS_IsException(result)) self.engine.freeValue(c.JS_GetException(self.engine.context)) else self.engine.freeValue(result);
            self.engine.freeValue(signal);
        }
        pending.signal_count = 0;
    }

    fn takePending(self: *Manager, id: u32) ?Pending {
        for (self.pending.items, 0..) |pending, index| if (pending.id == id) {
            self.engine.host_ui_pending -= 1;
            return self.pending.orderedRemove(index);
        };
        return null;
    }

    fn freePending(self: *Manager, pending: *Pending) void {
        self.detach(pending);
        for ([_]c.JSValue{ pending.resolve, pending.reject, pending.listener }) |value| self.engine.freeValue(value);
    }

    pub fn respond(self: *Manager, id: u32, ok: bool, value: c.JSValue) !void {
        var pending = self.takePending(id) orelse return;
        defer self.freePending(&pending);
        if (!self.active or pending.generation != self.generation) return;
        const result = if (!ok) value else if (pending.confirm) c.pi_js_bool(self.engine.context, c.JS_ToBool(self.engine.context, value)) else if (c.JS_IsNull(value)) c.pi_js_undefined() else value;
        try self.call(if (ok) pending.resolve else pending.reject, result);
    }

    pub fn cancel(self: *Manager, id: u32) !void {
        var pending = self.takePending(id) orelse return;
        defer self.freePending(&pending);
        if (self.bridge) |bridge| bridge.cancel(bridge.context, id) catch |err| {
            try self.rejectError(pending.reject, err);
            return err;
        };
        try self.call(pending.resolve, if (pending.confirm) c.pi_js_bool(self.engine.context, 0) else c.pi_js_undefined());
    }

    pub fn poll(self: *Manager) !bool {
        const io = self.engine.native_io orelse return false;
        const now = std.Io.Clock.awake.now(io).toMilliseconds();
        var changed = false;
        var index: usize = 0;
        while (index < self.pending.items.len) {
            const pending = self.pending.items[index];
            if (pending.deadline) |deadline| if (now >= deadline) {
                try self.cancel(pending.id);
                changed = true;
                continue;
            };
            index += 1;
        }
        return changed;
    }

    fn onAbort(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        const self = current(engine, data) catch return c.pi_js_undefined();
        var id: u32 = 0;
        if (c.JS_ToUint32(context, &id, data[2]) < 0) return engine.throwCaptured();
        self.cancel(id) catch |err| return fail(engine, err);
        return c.pi_js_undefined();
    }

    fn action(self: *Manager, method: Method, args: []c.JSValue) !c.JSValue {
        if (method == .getEditorText) return c.JS_DupValue(self.engine.context, self.editor_text);
        const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(object);
        switch (method) {
            .notify => {
                try self.defineField(object, "message", try self.stringArgument(args, 0, null));
                try self.defineField(object, "type", try self.stringArgument(args, 1, "info"));
            },
            .setStatus => {
                try self.defineField(object, "key", try self.stringArgument(args, 0, null));
                try self.defineField(object, "text", if (args.len < 2 or c.JS_IsUndefined(args[1]) or c.JS_IsNull(args[1])) c.pi_js_null() else try self.stringArgument(args, 1, null));
            },
            .setTitle => try self.defineField(object, "title", try self.stringArgument(args, 0, null)),
            .setEditorText, .pasteToEditor => {
                const text = try self.stringArgument(args, 0, null);
                defer self.engine.freeValue(text);
                if (method == .setEditorText) {
                    self.engine.freeValue(self.editor_text);
                    self.editor_text = c.JS_DupValue(self.engine.context, text);
                } else {
                    const old = try self.engine.toString(self.editor_text);
                    defer self.engine.gpa.free(old);
                    const added = try self.engine.toString(text);
                    defer self.engine.gpa.free(added);
                    const joined = try std.mem.concat(self.engine.gpa, u8, &.{ old, added });
                    defer self.engine.gpa.free(joined);
                    const value = try self.engine.checked(c.JS_NewStringLen(self.engine.context, joined.ptr, joined.len));
                    self.engine.freeValue(self.editor_text);
                    self.editor_text = value;
                }
                try self.defineField(object, "text", c.JS_DupValue(self.engine.context, text));
            },
            .setWorkingVisible => try self.defineField(object, "visible", c.pi_js_bool(self.engine.context, if (args.len > 0) c.JS_ToBool(self.engine.context, args[0]) else 0)),
            .setWorkingMessage, .setHiddenThinkingLabel => try self.defineField(object, if (method == .setWorkingMessage) "message" else "label", if (args.len == 0 or c.JS_IsUndefined(args[0]) or c.JS_IsNull(args[0])) c.pi_js_null() else try self.stringArgument(args, 0, null)),
            .setWidget => {
                try self.defineField(object, "key", try self.stringArgument(args, 0, null));
                if (args.len > 1 and !c.JS_IsUndefined(args[1]) and !c.JS_IsNull(args[1]) and !c.JS_IsArray(args[1])) return error.NativeWidgetFactoriesNotImplemented;
                try self.defineField(object, "lines", if (args.len < 2 or c.JS_IsUndefined(args[1])) c.pi_js_null() else c.JS_DupValue(self.engine.context, args[1]));
                var placement = try self.engine.checked(c.JS_NewString(self.engine.context, "aboveEditor"));
                if (args.len > 2 and c.JS_IsObject(args[2])) {
                    const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, args[2], "placement"));
                    defer self.engine.freeValue(value);
                    if (!c.JS_IsUndefined(value)) {
                        self.engine.freeValue(placement);
                        var values = [_]c.JSValue{value};
                        placement = try self.stringArgument(&values, 0, null);
                    }
                }
                try self.defineField(object, "placement", placement);
            },
            else => return error.NativeUiOperationUnsupported,
        }
        const encoded = try self.engine.stringify(object);
        defer self.engine.gpa.free(encoded);
        if (self.bridge) |bridge| try bridge.action(bridge.context, @tagName(method), encoded);
        return c.pi_js_undefined();
    }
};

test "native dialog awaiting human response suspends ordinary engine deadline and resumes after settlement" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 1 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("abort_signal.zig").install(engine);
    const manager = try Manager.init(engine);
    defer manager.deinit();
    const Context = struct {
        manager: *Manager,
        id: u32 = 0,
        polls: usize = 0,
        fn request(context: ?*anyopaque, id: u32, _: []const u8, _: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.id = id;
        }
        fn action(_: ?*anyopaque, _: []const u8, _: []const u8) !void {}
        fn cancel(_: ?*anyopaque, _: u32) !void {}
        fn pump(owner: *engine_mod.Engine) !bool {
            const self: *@This() = @ptrCast(@alignCast(owner.host_control_context.?));
            self.polls += 1;
            if (self.polls < 3 or self.id == 0) return false;
            const value = try owner.checked(c.JS_NewString(owner.context, "human-answer"));
            defer owner.freeValue(value);
            try self.manager.respond(self.id, true, value);
            self.id = 0;
            return true;
        }
    };
    var context: Context = .{ .manager = manager };
    manager.bridge = .{ .context = &context, .request = Context.request, .action = Context.action, .cancel = Context.cancel };
    const snapshot = try engine.checked(c.JS_ParseJSON(engine.context, "{\"hasUI\":true}", 14, "ui-deadline-context"));
    defer engine.freeValue(snapshot);
    try manager.begin(1, snapshot, null);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(engine.context, global, "nativeUi", try manager.createObject(), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    engine.host_control_context = &context;
    engine.host_control_pump = Context.pump;
    const promise = try engine.eval("nativeUi.select('Title',[])", "native-ui-human-deadline.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(promise);
    const result = try engine.awaitValue(promise);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("human-answer", text);
    try std.testing.expectEqual(@as(usize, 3), context.polls);
    try std.testing.expectEqual(@as(usize, 0), engine.host_ui_pending);
}
