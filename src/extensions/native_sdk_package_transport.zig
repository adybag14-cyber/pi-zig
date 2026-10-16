//! Actual DefaultPackageManager command/stdio bodies from pinned package-manager.ts.
//! Requires concrete child-process utility functions; no command is simulated.
const v = @import("native_ai_provider_values.zig");
const js = v.js;
const c = v.c;
const Scope = v.Scope;
const functions = @import("native_node_function.zig");
pub const Inputs = struct { process: c.JSValue, read_file_sync: c.JSValue, spawn_process: c.JSValue, spawn_process_sync: c.JSValue, is_stdout_taken_over: c.JSValue };
const Method = enum(c_int) { spawnCommand, spawnCaptureCommand, runCommandCapture, runCommand, runCommandSync };
const Event = enum(c_int) { executor_capture, executor_command, stdout, stderr, timeout, capture_error, capture_close, command_exit };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn private(scope: *Scope) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
}
pub fn install(engine: *v.em.Engine, prototype: c.JSValue, inputs: Inputs) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const imports = try private(&scope);
    inline for (@typeInfo(Inputs).@"struct".fields) |field| try scope.put(imports, field.name, @field(inputs, field.name));
    inline for (.{ inputs.read_file_sync, inputs.spawn_process, inputs.spawn_process_sync, inputs.is_stdout_taken_over }) |value| if (!c.JS_IsFunction(engine.context, value)) return error.RequiredRealPackageTransportImport;
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const value = try scope.own(try functions.createMethod(engine, field.name, if (field.value == @intFromEnum(Method.runCommandSync)) 2 else 3, method, &.{ imports, c.JS_NewInt32(engine.context, field.value) }));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, value), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
}
fn imported(scope: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(imports, name), c.pi_js_undefined(), args);
}
fn environmentInner(scope: *Scope, imports: c.JSValue) !c.JSValue {
    const bytes = try imported(scope, imports, "read_file_sync", &.{ try scope.text("/proc/self/environ"), try scope.text("utf-8") });
    const env = try scope.object();
    const entries = try scope.invoke(bytes, "split", &.{try scope.text("\x00")});
    var iterator = try v.iterator(scope, entries);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer scope.engine.freeValue(entry);
        const index = try scope.invoke(entry, "indexOf", &.{try scope.text("=")});
        if (try scope.positive(index)) {
            const key = try scope.invoke(entry, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), index });
            const next = try scope.own(try scope.engine.checked(c.JS_PiIncrement(scope.engine.context, index)));
            const value = try scope.invoke(entry, "slice", &.{next});
            const atom = try js.atom(scope.engine, key);
            defer c.JS_FreeAtom(scope.engine.context, atom);
            if (c.JS_SetProperty(scope.engine.context, env, atom, c.JS_DupValue(scope.engine.context, value)) < 0) return js.capture(scope.engine);
        }
    }
    return env;
}
fn environment(scope: *Scope, imports: c.JSValue) !c.JSValue {
    const process = try scope.get(imports, "process");
    if (!scope.equal(try scope.get(process, "platform"), try scope.text("linux"))) return scope.get(process, "env");
    const object = try scope.global("Object");
    const keys = try scope.call(try scope.get(object, "keys"), object, &.{try scope.get(process, "env")});
    if (try scope.positive(try scope.get(keys, "length"))) return scope.get(process, "env");
    const generation = scope.engine.native_allocation_generation;
    return environmentInner(scope, imports) catch |err| {
        const classified = scope.engine.nativeAllocationError(err, generation);
        if (classified != error.JavaScriptException) return classified;
        if (scope.engine.captured_exception) |value| scope.engine.freeValue(value);
        scope.engine.captured_exception = null;
        return scope.get(process, "env");
    };
}
fn stdio(scope: *Scope) !c.JSValue {
    const array = try scope.array();
    inline for (.{ "ignore", "pipe", "pipe" }, 0..) |value, index| try scope.index(array, index, try scope.text(value));
    return array;
}
fn method(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return js.capture(engine);
    const operation: Method = @enumFromInt(raw);
    const command = arg(args, 0);
    const argv = arg(args, 1);
    const options = arg(args, 2);
    switch (operation) {
        .spawnCommand, .spawnCaptureCommand => {
            const base_env = try environment(&scope, roots[0]);
            var env = base_env;
            if (operation == .spawnCaptureCommand and !v.nullish(options)) {
                const extra = try scope.get(options, "env");
                if (scope.truthy(extra)) {
                    env = try v.spread(&scope, base_env);
                    try js.spreadInto(engine, env, try scope.get(options, "env"));
                }
            }
            const supplied = try scope.object();
            try scope.put(supplied, "cwd", if (v.nullish(options)) c.pi_js_undefined() else try scope.get(options, "cwd"));
            var streams: c.JSValue = undefined;
            if (operation == .spawnCaptureCommand) streams = try stdio(&scope) else if (scope.truthy(try imported(&scope, roots[0], "is_stdout_taken_over", &.{}))) {
                streams = try scope.array();
                try scope.index(streams, 0, try scope.text("ignore"));
                try scope.index(streams, 1, c.JS_NewInt32(engine.context, 2));
                try scope.index(streams, 2, c.JS_NewInt32(engine.context, 2));
            } else streams = try scope.text("inherit");
            try scope.put(supplied, "stdio", streams);
            try scope.put(supplied, "env", env);
            return c.JS_DupValue(engine.context, try imported(&scope, roots[0], "spawn_process", &.{ command, argv, supplied }));
        },
        .runCommandSync => {
            const env = try environment(&scope, roots[0]);
            const supplied = try scope.object();
            try scope.put(supplied, "stdio", try stdio(&scope));
            try scope.put(supplied, "encoding", try scope.text("utf-8"));
            try scope.put(supplied, "env", env);
            const result = try imported(&scope, roots[0], "spawn_process_sync", &.{ command, argv, supplied });
            if (scope.truthy(try scope.get(result, "error")) or !scope.equal(try scope.get(result, "status"), c.JS_NewInt32(engine.context, 0))) {
                const error_value = try scope.get(result, "error");
                const message = if (v.nullish(error_value)) c.pi_js_undefined() else try scope.get(error_value, "message");
                const stderr = if (scope.truthy(message)) message else try scope.get(result, "stderr");
                const detail = if (scope.truthy(stderr)) stderr else try scope.get(result, "stdout");
                const prefix = try scope.concat(try scope.text("Failed to run "), try commandLine(&scope, command, argv));
                return throwError(&scope, try scope.concat(try scope.concat(prefix, try scope.text(": ")), try scope.stringify(detail)));
            }
            const stdout = try scope.get(result, "stdout");
            const stderr = if (scope.truthy(stdout)) stdout else try scope.get(result, "stderr");
            return c.JS_DupValue(engine.context, try scope.invoke(if (scope.truthy(stderr)) stderr else try scope.text(""), "trim", &.{}));
        },
        .runCommandCapture, .runCommand => {
            const executor = try scope.own(try functions.createArrow(engine, "", 2, event, &.{ c.JS_NewInt32(engine.context, @intFromEnum(if (operation == .runCommandCapture) Event.executor_capture else Event.executor_command)), receiver, command, argv, options }));
            return engine.checked(c.JS_CallConstructor(engine.context, try scope.global("Promise"), 1, @constCast((&[_]c.JSValue{executor}).ptr)));
        },
    }
}
fn commandLine(scope: *Scope, command: c.JSValue, args: c.JSValue) !c.JSValue {
    return scope.concat(try scope.concat(try scope.stringify(command), try scope.text(" ")), try scope.stringify(try scope.invoke(args, "join", &.{try scope.text(" ")})));
}
fn throwError(scope: *Scope, message: c.JSValue) !c.JSValue {
    return scope.engine.checked(c.JS_Throw(scope.engine.context, try js.builtin(scope.engine, "Error", &.{message})));
}
fn listener(scope: *Scope, kind: Event, owner: c.JSValue, length: c_int) !c.JSValue {
    return scope.own(try functions.createArrow(scope.engine, "", length, event, &.{ c.JS_NewInt32(scope.engine.context, @intFromEnum(kind)), owner }));
}
fn clearTimer(scope: *Scope, owner: c.JSValue) !void {
    const timer = try scope.get(owner, "timeout");
    if (scope.truthy(timer)) _ = try scope.call(try scope.global("clearTimeout"), c.pi_js_undefined(), &.{timer});
}
fn event(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, roots[0]) < 0) return js.capture(engine);
    const kind: Event = @enumFromInt(raw);
    if (kind == .executor_capture or kind == .executor_command) {
        const child = try scope.invoke(roots[1], if (kind == .executor_capture) "spawnCaptureCommand" else "spawnCommand", &.{ roots[2], roots[3], roots[4] });
        const owner = try private(&scope);
        inline for (.{ "child", "command", "args", "options", "resolve", "reject" }, 0..) |name, index| try scope.put(owner, name, switch (index) { 0 => child, 1 => roots[2], 2 => roots[3], 3 => roots[4], 4 => arg(args, 0), else => arg(args, 1) });
        if (kind == .executor_command) {
            _ = try scope.invoke(child, "on", &.{ try scope.text("error"), arg(args, 1) });
            _ = try scope.invoke(child, "on", &.{ try scope.text("exit"), try listener(&scope, .command_exit, owner, 1) });
        } else {
            try scope.put(owner, "stdout", try scope.text(""));
            try scope.put(owner, "stderr", try scope.text(""));
            try scope.put(owner, "timedOut", c.pi_js_bool(engine.context, 0));
            const timeout_ms = if (v.nullish(roots[4])) c.pi_js_undefined() else try scope.get(roots[4], "timeoutMs");
            const timer = if (c.JS_IsNumber(timeout_ms)) try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ try listener(&scope, .timeout, owner, 0), try scope.get(roots[4], "timeoutMs") }) else c.pi_js_undefined();
            try scope.put(owner, "timeout", timer);
            inline for (.{ .{ "stdout", Event.stdout }, .{ "stderr", Event.stderr } }) |pair| {
                const stream = try scope.get(child, pair[0]);
                if (!v.nullish(stream)) _ = try scope.invoke(stream, "on", &.{ try scope.text("data"), try listener(&scope, pair[1], owner, 1) });
            }
            _ = try scope.invoke(child, "once", &.{ try scope.text("error"), try listener(&scope, .capture_error, owner, 1) });
            _ = try scope.invoke(child, "once", &.{ try scope.text("close"), try listener(&scope, .capture_close, owner, 2) });
        }
        return c.pi_js_undefined();
    }
    const owner = roots[1];
    switch (kind) {
        .stdout, .stderr => {
            const key = if (kind == .stdout) "stdout" else "stderr";
            try scope.set(owner, key, try scope.concat(try scope.get(owner, key), try scope.invoke(arg(args, 0), "toString", &.{})));
        },
        .timeout => {
            try scope.set(owner, "timedOut", c.pi_js_bool(engine.context, 1));
            _ = try scope.invoke(try scope.get(owner, "child"), "kill", &.{});
        },
        .capture_error => {
            try clearTimer(&scope, owner);
            _ = try scope.call(try scope.get(owner, "reject"), c.pi_js_undefined(), &.{arg(args, 0)});
        },
        .capture_close, .command_exit => {
            if (kind == .capture_close) try clearTimer(&scope, owner);
            const command = try scope.get(owner, "command");
            const argv = try scope.get(owner, "args");
            var message: c.JSValue = undefined;
            if (kind == .capture_close and scope.truthy(try scope.get(owner, "timedOut"))) {
                const options = try scope.get(owner, "options");
                const timeout_ms = if (v.nullish(options)) c.pi_js_undefined() else try scope.get(options, "timeoutMs");
                message = try scope.concat(try scope.concat(try commandLine(&scope, command, argv), try scope.text(" timed out after ")), try scope.concat(try scope.stringify(timeout_ms), try scope.text("ms")));
            } else if (scope.equal(arg(args, 0), c.JS_NewInt32(engine.context, 0))) {
                _ = try scope.call(try scope.get(owner, "resolve"), c.pi_js_undefined(), if (kind == .command_exit) &.{} else &.{try scope.invoke(try scope.get(owner, "stdout"), "trim", &.{})});
                return c.pi_js_undefined();
            } else if (kind == .command_exit) {
                message = try scope.concat(try scope.concat(try commandLine(&scope, command, argv), try scope.text(" failed with code ")), try scope.stringify(arg(args, 0)));
            } else {
                const signal = arg(args, 1);
                const status = if (c.JS_IsNull(arg(args, 0))) try scope.concat(try scope.text("signal "), try scope.stringify(if (v.nullish(signal)) try scope.text("unknown") else signal)) else try scope.concat(try scope.text("code "), try scope.stringify(arg(args, 0)));
                const stderr = try scope.get(owner, "stderr");
                const detail = if (scope.truthy(stderr)) stderr else try scope.get(owner, "stdout");
                message = try scope.concat(try scope.concat(try scope.concat(try scope.concat(try commandLine(&scope, command, argv), try scope.text(" failed with ")), status), try scope.text(": ")), detail);
            }
            const reason = try scope.own(try js.builtin(engine, "Error", &.{message}));
            _ = try scope.call(try scope.get(owner, "reject"), c.pi_js_undefined(), &.{reason});
        },
        .executor_capture, .executor_command => unreachable,
    }
    return c.pi_js_undefined();
}
