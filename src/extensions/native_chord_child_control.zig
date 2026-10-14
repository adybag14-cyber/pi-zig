//! Actual Source childControl protocol. The kernel-lock implementation is a required typed native dependency.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
pub const ProcessLock = *const fn (*h.Engine, c.JSValue, c.JSValue) anyerror!c.JSValue;
pub fn API(comptime process_lock: ProcessLock) type {
    return struct {
        const Op = enum(c_int) { executor, message, ready, fatal, report, on_shutdown, lock };
        fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, mode: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
            const engine = h.Engine.fromContext(ctx.?);
            const op: Op = @enumFromInt(mode);
            const value = invoke(engine, captures[0], if (argc > 0) argv[0..@intCast(argc)] else &.{}, op) catch |err| return if (op == .lock) @import("native_durable.zig").rejectedPromise(engine, err) else @import("native_durable.zig").reject(engine, err);
            if (op != .lock) return value;
            defer engine.freeValue(value);
            return @import("native_durable.zig").resolvedPromise(engine, value) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
        }
        fn function(s: *Scope, state: c.JSValue, op: Op, name: [*:0]const u8, length: c_int) !c.JSValue {
            var captures = [_]c.JSValue{state};
            const value = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, name, length, @intFromEnum(op), 1, &captures)));
            if (op == .lock) {
                const prototype = try s.keep(try s.engine.checked(c.JS_GetAsyncFunctionPrototype(s.engine.context)));
                if (c.JS_SetPrototype(s.engine.context, value, prototype) < 0) return js.capture(s.engine);
            }
            return value;
        }
        fn message(s: *Scope, tag: []const u8) !c.JSValue {
            const value = try s.record();
            try h.field(s, value, "type", try s.text(tag));
            return value;
        }
        fn send(s: *Scope, state: c.JSValue, value: c.JSValue) !void {
            const channel = try s.get(state, "channel");
            if (!try h.flag(s, channel, "connected")) return;
            const sender = try s.get(channel, "send");
            if (h.nullish(sender)) return;
            const frame = try s.record();
            try h.field(s, frame, "chord2control", value);
            _ = try s.keep(try js.call(s.engine, sender, channel, &.{ frame, c.pi_js_undefined(), c.pi_js_undefined(), try s.get(state, "ignoreSendError") }));
        }
        fn fatal(s: *Scope, state: c.JSValue, error_value: c.JSValue) !void {
            const base = c.JS_IsInstanceOf(s.engine.context, error_value, try s.keep(try js.global(s.engine, "Error")));
            if (base < 0) return js.capture(s.engine);
            const value = try message(s, "fatal");
            try h.field(s, value, "message", if (base != 0) try s.get(error_value, "message") else try s.keep(try js.call(s.engine, try s.keep(try js.global(s.engine, "String")), c.pi_js_undefined(), &.{error_value})));
            const bindings = try s.get(state, "bindings");
            const chord = c.JS_IsInstanceOf(s.engine.context, error_value, try s.get(try s.get(bindings, "errors"), "ChordError"));
            if (chord < 0) return js.capture(s.engine);
            if (chord != 0 and !c.JS_IsUndefined(try s.get(error_value, "reason"))) try h.field(s, value, "reason", try s.get(error_value, "reason"));
            try send(s, state, value);
        }
        fn invoke(engine: *h.Engine, state: c.JSValue, args: []const c.JSValue, op: Op) anyerror!c.JSValue {
            var s: Scope = .{ .engine = engine };
            defer s.deinit();
            const value = h.arg(args, 0);
            switch (op) {
                .executor => try h.field(&s, state, "resolveInit", value),
                .message => {
                    const control = try r.optional(&s, value, "chord2control");
                    const tag = try r.optional(&s, control, "type");
                    if (try s.equal(tag, "init")) _ = try s.keep(try js.call(engine, try s.get(state, "resolveInit"), c.pi_js_undefined(), &.{try s.get(control, "value")}));
                    if (try s.equal(tag, "shutdown")) {
                        var handlers = try r.iterate(&s, try s.get(state, "shutdown"));
                        defer handlers.deinit();
                        errdefer handlers.closePreserving();
                        while (try handlers.next()) |handler| {
                            defer engine.freeValue(handler);
                            _ = try s.keep(try js.call(engine, handler, c.pi_js_undefined(), &.{}));
                        }
                    }
                },
                .ready => try send(&s, state, try message(&s, "ready")),
                .fatal => try fatal(&s, state, value),
                .report => {
                    const status = try message(&s, "status");
                    try js.spreadInto(engine, status, value);
                    try send(&s, state, status);
                },
                .on_shutdown => return js.invoke(engine, try s.get(state, "shutdown"), "add", &.{value}),
                .lock => {
                    const process = try s.keep(try js.global(engine, "process"));
                    const name = try s.get(try s.get(process, "env"), "CHORD2_LOCK");
                    if (c.JS_IsUndefined(name)) return c.pi_js_undefined();
                    const pending = process_lock(engine, try s.get(state, "bindings"), name) catch |err| {
                        if (err != error.JavaScriptException) return err;
                        const failure = try s.keep(c.JS_DupValue(engine.context, engine.captured_exception.?));
                        try fatal(&s, state, failure);
                        return h.throwValue(&s, failure);
                    };
                    defer engine.freeValue(pending);
                    return h.wait(lockDone, engine, state, pending, 0);
                },
            }
            return c.pi_js_undefined();
        }
        fn lockDone(engine: *h.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
            if (!rejected) return c.pi_js_undefined();
            var s: Scope = .{ .engine = engine };
            defer s.deinit();
            try fatal(&s, state, value);
            return h.throwValue(&s, value);
        }
        pub fn create(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
            var s: Scope = .{ .engine = engine };
            defer s.deinit();
            const state = try s.record();
            const channel = if (c.JS_IsUndefined(h.arg(args, 0))) try s.keep(try js.global(engine, "process")) else h.arg(args, 0);
            try h.field(&s, state, "channel", channel);
            try h.field(&s, state, "bindings", captures[0]);
            const ignore = try s.get(captures[0], "managerIgnoreSendError");
            if (c.JS_IsUndefined(ignore)) {
                const noop = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, r.noop, "ignoreSendError", 0, 0, 0, null)));
                try h.field(&s, captures[0], "managerIgnoreSendError", noop);
                try h.field(&s, state, "ignoreSendError", noop);
            } else try h.field(&s, state, "ignoreSendError", ignore);
            const init = try s.keep(try js.builtin(engine, "Promise", &.{try function(&s, state, .executor, "", 1)}));
            try h.field(&s, state, "shutdown", try h.set(&s));
            _ = try h.invoke(&s, channel, "on", &.{ try s.text("message"), try function(&s, state, .message, "", 1) });
            const value = try s.record();
            try h.field(&s, value, "init", init);
            inline for (.{ .{ "lock", Op.lock, 0 }, .{ "ready", Op.ready, 0 }, .{ "fatal", Op.fatal, 1 }, .{ "report", Op.report, 1 }, .{ "onShutdown", Op.on_shutdown, 1 } }) |entry| try h.field(&s, value, entry[0], try function(&s, state, entry[1], entry[0], entry[2]));
            return s.result(value);
        }
    };
}
