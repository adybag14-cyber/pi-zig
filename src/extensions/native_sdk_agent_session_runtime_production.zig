//! Actual latest4954 AgentSessionRuntime ordinary class and imported helpers.
//! No legacy SDK.Kind.session_runtime or substitute session factory participates.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const flow = @import("native_sdk_async_actions.zig");
const class = @import("native_class.zig");
const c = em.c;
const builtin = @import("builtin");
pub const required_functions = .{ "SessionManager", "resolvePath", "existsSync", "mkdirSync", "copyFileSync", "basename", "join", "parse", "resolve" };

/// Actual native filesystem dependency for this class's import operation only.
/// It supplies exclusive copy, not the complete public node:fs copy API.
pub fn importFileCopyBindings(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    try scope.put(result, "copyFileSync", try scope.own(try @import("native_node_function.zig").create(engine, "copyFileSync", 3, copyImportFile, &.{})));
    const constants = try scope.object();
    try scope.put(constants, "COPYFILE_EXCL", c.JS_NewInt32(engine.context, 1));
    try scope.put(result, "constants", constants);
    return c.JS_DupValue(engine.context, result);
}
fn copyImportFile(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.equal(arg(args, 2), c.JS_NewInt32(engine.context, 1))) return error.ImportCopyRequiresActualExclusiveFlag;
    if (!c.JS_IsString(arg(args, 0)) or !c.JS_IsString(arg(args, 1))) return error.ImportCopyRequiresResolvedStringPaths;
    const source = try engine.toString(arg(args, 0));
    defer engine.gpa.free(source);
    const destination = try engine.toString(arg(args, 1));
    defer engine.gpa.free(destination);
    const io = engine.native_io orelse return error.NativeIoUnavailable;
    std.Io.Dir.cwd().copyFile(source, .cwd(), destination, io, .{ .replace = false }) catch |err| {
        const failure: anyerror = err;
        if (failure == error.OutOfMemory) return failure;
        const code: []const u8 = switch (failure) {
            error.PathAlreadyExists => "EEXIST",
            error.FileNotFound => "ENOENT",
            error.AccessDenied, error.PermissionDenied => "EACCES",
            error.IsDir => "EISDIR",
            else => "EIO",
        };
        const description: []const u8 = if (std.mem.eql(u8, code, "EEXIST")) "file already exists" else if (std.mem.eql(u8, code, "ENOENT")) "no such file or directory" else if (std.mem.eql(u8, code, "EACCES")) "permission denied" else if (std.mem.eql(u8, code, "EISDIR")) "illegal operation on a directory" else "i/o error";
        const message = try std.fmt.allocPrint(engine.gpa, "{s}: {s}, copyfile '{s}' -> '{s}'", .{ code, description, source, destination });
        defer engine.gpa.free(message);
        const reason = try scope.own(try js.builtin(engine, "Error", &.{try scope.text(message)}));
        const errno: i32 = if (std.mem.eql(u8, code, "EEXIST")) (if (builtin.os.tag == .windows) -4075 else -17) else if (std.mem.eql(u8, code, "ENOENT")) (if (builtin.os.tag == .windows) -4058 else -2) else if (std.mem.eql(u8, code, "EACCES")) (if (builtin.os.tag == .windows) -4092 else -13) else if (std.mem.eql(u8, code, "EISDIR")) (if (builtin.os.tag == .windows) -4068 else -21) else (if (builtin.os.tag == .windows) -4070 else -5);
        try scope.put(reason, "errno", c.JS_NewInt32(engine.context, errno));
        try scope.put(reason, "code", try scope.text(code));
        try scope.put(reason, "syscall", try scope.text("copyfile"));
        try scope.put(reason, "path", arg(args, 0));
        try scope.put(reason, "dest", arg(args, 1));
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        unreachable;
    };
    return c.pi_js_undefined();
}
const Getter = enum(c_int) { services, session, cwd, diagnostics, modelFallbackMessage };
const Method = enum(c_int) { setRebindSession, setBeforeSessionInvalidate, emitBeforeSwitch, emitBeforeFork, teardownCurrent, apply, finishSessionReplacement, switchSession, newSession, fork, importFromJsonl, dispose };
const Stage = enum(c_int) { before_switch, before_fork, aborted, shutdown, rebound, context_done, switch_ready, replacement_created, replacement_finished, new_ready, new_setup, fork_ready, fork_torn, import_ready, disposed, replacement_done };
const Helper = enum(c_int) { getMissingSessionCwdIssue, formatMissingSessionCwdError, formatMissingSessionCwdPrompt, assertSessionCwdExists, emitSessionShutdownEvent };

/// All filesystem/path/manager dependencies must be the application's actual
/// shared imports. Validation does not qualify a caller-supplied substitute.
pub fn create(engine: *em.Engine, imports: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.object();
    inline for (required_functions) |name| {
        const value = try scope.get(imports, name);
        if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualAgentSessionRuntimeImport;
        try scope.put(bindings, name, value);
    }
    try scope.put(bindings, "constants", try scope.get(imports, "constants"));
    const output = try scope.object();
    inline for (.{ "SessionImportFileNotFoundError", "MissingSessionCwdError" }, 0..) |name, index| {
        const error_type = try errorClass(&scope, name, index);
        try scope.put(output, name, error_type);
        try scope.put(bindings, name, error_type);
    }
    inline for (std.meta.fields(Helper)) |field| {
        var roots = [_]c.JSValue{bindings};
        const function = try scope.own(if (field.value == 4) try flow.native.createResumable(engine, field.name, 2, shutdownBody, &roots) else try engine.checked(c.JS_NewCFunctionData2(engine.context, helper, field.name, if (field.value == 1 or field.value == 2) 1 else 2, field.value, roots.len, &roots)));
        try scope.put(output, field.name, function);
        // Helpers are lexical imports, not ordinary runtime instance fields.
        if (field.value == 3 or field.value == 4) try scope.put(bindings, field.name, function);
    }
    const prototype = try scope.object();
    const constructor = try scope.own(try class.constructor(engine, "AgentSessionRuntime", 3, prototype, construct, &.{bindings}));
    inline for (std.meta.fields(Getter)) |field| {
        const function = try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, getter, "get " ++ field.name, 0, field.value)));
        const atom = c.JS_NewAtom(engine.context, field.name);
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
    inline for (std.meta.fields(Method)) |field| {
        var roots = [_]c.JSValue{ bindings, c.JS_NewInt32(engine.context, field.value) };
        const method: Method = @enumFromInt(field.value);
        const arity: c_int = switch (method) {
            .dispose => 0,
            .setRebindSession, .setBeforeSessionInvalidate, .apply, .finishSessionReplacement, .newSession => 1,
            else => 2,
        };
        const function = try scope.own(if (method != .setRebindSession and method != .setBeforeSessionInvalidate and method != .apply) try flow.native.createResumable(engine, field.name, arity, methodBody, &roots) else try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, arity, field.value, roots.len, &roots)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
    try scope.put(output, "AgentSessionRuntime", constructor);
    return c.JS_DupValue(engine.context, output);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn optional(scope: *Scope, receiver: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (temp.nullish(receiver)) c.pi_js_undefined() else scope.get(receiver, key);
}
fn imported(scope: *Scope, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(bindings, name), c.pi_js_undefined(), args);
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try class.object(engine, target));
    inline for (.{ "rebindSession", "beforeSessionInvalidate", "_session", "_services", "createRuntime", "_diagnostics", "_modelFallbackMessage" }) |name| try scope.put(result, name, c.pi_js_undefined());
    try scope.set(result, "_session", arg(args, 0));
    try scope.set(result, "_services", arg(args, 1));
    try scope.set(result, "createRuntime", arg(args, 2));
    try scope.set(result, "_diagnostics", if (c.JS_IsUndefined(arg(args, 3))) try scope.array() else arg(args, 3));
    try scope.set(result, "_modelFallbackMessage", arg(args, 4));
    return c.JS_DupValue(engine.context, result);
}
fn getter(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return getValue(&scope, receiver, @enumFromInt(magic)) catch |err| sdk.fail(engine, err);
}
fn getValue(scope: *Scope, receiver: c.JSValue, field: Getter) !c.JSValue {
    if (field == .cwd) return js.get(scope.engine, try scope.get(receiver, "_services"), "cwd");
    return js.get(scope.engine, receiver, switch (field) {
        .services => "_services",
        .session => "_session",
        .diagnostics => "_diagnostics",
        .modelFallbackMessage => "_modelFallbackMessage",
        .cwd => unreachable,
    });
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return invoke(engine, receiver, @enumFromInt(magic), args, roots[0]) catch |err| sdk.fail(engine, err);
}
fn invoke(engine: *em.Engine, receiver: c.JSValue, method: Method, args: []const c.JSValue, bindings: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (method == .setRebindSession or method == .setBeforeSessionInvalidate) {
        try scope.set(receiver, if (method == .setRebindSession) "rebindSession" else "beforeSessionInvalidate", arg(args, 0));
        return c.pi_js_undefined();
    }
    if (method == .apply) {
        inline for (.{ "session", "services", "diagnostics", "modelFallbackMessage" }, .{ "_session", "_services", "_diagnostics", "_modelFallbackMessage" }) |source, destination| try scope.set(receiver, destination, try scope.get(arg(args, 0), source));
        return c.pi_js_undefined();
    }
    _ = bindings;
    return error.InvalidSynchronousAgentSessionRuntimeMethod;
}
fn methodBody(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: flow.native.Completion, input: c.JSValue) !flow.native.Action {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    if (completion == .rejected and try flow.nativeAllocationReason(engine, state.*, input)) return error.OutOfMemory;
    if (completion == .start) {
        const owner = try flow.init(&scope, state);
        try scope.put(owner, "agent", receiver);
        try scope.put(owner, "bindings", roots[0]);
        try scope.put(owner, "first", arg(args, 0));
        try scope.put(owner, "second", arg(args, 1));
        var method_id: i32 = undefined; if (c.JS_ToInt32(engine.context, &method_id, roots[1]) < 0) return js.capture(engine);
        start(engine, owner, @enumFromInt(method_id)) catch |err| try flow.rejectError(engine, owner, err);
    } else advance(engine, state.*, input, completion == .rejected, try flow.body.stage(&scope, state.*)) catch |err| try flow.rejectError(engine, state.*, err);
    return flow.body.action(&scope, state.*);
}
fn wait(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try flow.wait(advance, engine, owner, value, @intFromEnum(stage));
}
fn cancelled(scope: *Scope, value: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "cancelled", value);
    return result;
}
fn falseResult(scope: *Scope) !c.JSValue {
    return cancelled(scope, c.pi_js_bool(scope.engine.context, 0));
}
fn event(scope: *Scope, event_type: []const u8, reason: c.JSValue, target: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "type", try scope.text(event_type));
    try scope.put(result, "reason", reason);
    try scope.put(result, "targetSessionFile", target);
    return result;
}
fn start(engine: *em.Engine, owner: c.JSValue, method: Method) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(owner, "agent");
    const first = try scope.get(owner, "first");
    const second = try scope.get(owner, "second");
    switch (method) {
        .emitBeforeSwitch, .emitBeforeFork => {
            const runner = try scope.get(try scope.get(runtime, "session"), "extensionRunner");
            const name = if (method == .emitBeforeSwitch) "session_before_switch" else "session_before_fork";
            if (!scope.truthy(try scope.invoke(runner, "hasHandlers", &.{try scope.text(name)}))) return flow.settle(engine, owner, false, try falseResult(&scope));
            const emit = try scope.get(runner, "emit");
            const before = try scope.object();
            try scope.put(before, "type", try scope.text(name));
            if (method == .emitBeforeSwitch) {
                try scope.put(before, "reason", first);
                try scope.put(before, "targetSessionFile", second);
            } else {
                try scope.put(before, "entryId", first);
                try js.spreadInto(engine, before, second);
            }
            return wait(engine, owner, try scope.call(emit, runner, &.{before}), if (method == .emitBeforeSwitch) .before_switch else .before_fork);
        },
        .teardownCurrent => return wait(engine, owner, try scope.invoke(try scope.get(runtime, "session"), "abort", &.{}), .aborted),
        .finishSessionReplacement => {
            if (scope.truthy(try scope.get(runtime, "rebindSession"))) {
                const callback = try scope.get(runtime, "rebindSession");
                return wait(engine, owner, try scope.call(callback, runtime, &.{try scope.get(runtime, "session")}), .rebound);
            }
            return finishWithSession(engine, owner);
        },
        .switchSession => return wait(engine, owner, try scope.invoke(runtime, "emitBeforeSwitch", &.{ try scope.text("resume"), first }), .switch_ready),
        .newSession => return wait(engine, owner, try scope.invoke(runtime, "emitBeforeSwitch", &.{try scope.text("new")}), .new_ready),
        .fork => {
            const position = try optional(&scope, second, "position");
            try scope.put(owner, "position", if (temp.nullish(position)) try scope.text("before") else position);
            const options = try scope.object();
            try scope.put(options, "position", try scope.get(owner, "position"));
            return wait(engine, owner, try scope.invoke(runtime, "emitBeforeFork", &.{ first, options }), .fork_ready);
        },
        .importFromJsonl => return startImport(engine, owner),
        .dispose => {
            const shutdown = try scope.object();
            try scope.put(shutdown, "type", try scope.text("session_shutdown"));
            try scope.put(shutdown, "reason", try scope.text("quit"));
            return wait(engine, owner, try imported(&scope, try scope.get(owner, "bindings"), "emitSessionShutdownEvent", &.{ try scope.get(try scope.get(runtime, "session"), "extensionRunner"), shutdown }), .disposed);
        },
        else => unreachable,
    }
}
fn advance(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    try resumeBody(engine, owner, value, @enumFromInt(stage));
}
fn resumeBody(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(owner, "agent");
    const first = try scope.get(owner, "first");
    const second = try scope.get(owner, "second");
    const bindings = try scope.get(owner, "bindings");
    switch (stage) {
        .before_switch, .before_fork => {
            const cancel = try optional(&scope, value, "cancel");
            return flow.settle(engine, owner, false, try cancelled(&scope, c.pi_js_bool(engine.context, @intFromBool(scope.equal(cancel, c.pi_js_bool(engine.context, 1))))));
        },
        .aborted => {
            const shutdown = try event(&scope, "session_shutdown", first, second);
            return wait(engine, owner, try imported(&scope, bindings, "emitSessionShutdownEvent", &.{ try scope.get(try scope.get(runtime, "session"), "extensionRunner"), shutdown }), .shutdown);
        },
        .shutdown, .disposed => {
            const before = try scope.get(runtime, "beforeSessionInvalidate");
            if (!temp.nullish(before)) _ = try scope.call(before, runtime, &.{});
            _ = try scope.invoke(try scope.get(runtime, "session"), "dispose", &.{});
            return flow.settle(engine, owner, false, c.pi_js_undefined());
        },
        .rebound => return finishWithSession(engine, owner),
        .context_done => return flow.settle(engine, owner, false, c.pi_js_undefined()),
        .switch_ready => {
            if (scope.truthy(try scope.get(value, "cancelled"))) return flow.settle(engine, owner, false, value);
            try scope.put(owner, "previous", try scope.get(try scope.get(runtime, "session"), "sessionFile"));
            const managers = try scope.get(bindings, "SessionManager");
            const open = try scope.get(managers, "open");
            const manager = try scope.call(open, managers, &.{ first, c.pi_js_undefined(), try optional(&scope, second, "cwdOverride") });
            _ = try imported(&scope, bindings, "assertSessionCwdExists", &.{ manager, try scope.get(runtime, "cwd") });
            try scope.put(owner, "manager", manager);
            try scope.put(owner, "replacementKind", try scope.text("switch"));
            return wait(engine, owner, try teardownCall(&scope, runtime, "resume", manager), .replacement_created);
        },
        .new_ready => {
            if (scope.truthy(try scope.get(value, "cancelled"))) return flow.settle(engine, owner, false, value);
            try scope.put(owner, "previous", try scope.get(try scope.get(runtime, "session"), "sessionFile"));
            const directory = try scope.invoke(try scope.get(try scope.get(runtime, "session"), "sessionManager"), "getSessionDir", &.{});
            const persisted = try scope.invoke(try scope.get(try scope.get(runtime, "session"), "sessionManager"), "isPersisted", &.{});
            const managers = try scope.get(bindings, "SessionManager");
            const create_manager = try scope.get(managers, if (scope.truthy(persisted)) "create" else "inMemory");
            const manager = if (scope.truthy(persisted)) try scope.call(create_manager, managers, &.{ try scope.get(runtime, "cwd"), directory }) else try scope.call(create_manager, managers, &.{try scope.get(runtime, "cwd")});
            if (scope.truthy(try optional(&scope, first, "parentSession"))) {
                const new_session = try scope.get(manager, "newSession");
                const options = try scope.object();
                try scope.put(options, "parentSession", try scope.get(first, "parentSession"));
                _ = try scope.call(new_session, manager, &.{options});
            }
            try scope.put(owner, "manager", manager);
            try scope.put(owner, "replacementKind", try scope.text("new"));
            return wait(engine, owner, try teardownCall(&scope, runtime, "new", manager), .replacement_created);
        },
        .fork_ready => {
            if (scope.truthy(try scope.get(value, "cancelled"))) return flow.settle(engine, owner, false, try cancelled(&scope, c.pi_js_bool(engine.context, 1)));
            return prepareFork(engine, owner);
        },
        .fork_torn => {
            const manager = try scope.get(owner, "manager");
            const target = try scope.get(owner, "targetLeaf");
            if (!scope.truthy(target)) {
                const options = try scope.object();
                try scope.put(options, "parentSession", try scope.get(owner, "previous"));
                _ = try scope.invoke(manager, "newSession", &.{options});
            } else _ = try scope.invoke(manager, "createBranchedSession", &.{target});
            return createReplacement(engine, owner);
        },
        .replacement_created => return createReplacement(engine, owner),
        .replacement_finished => {
            _ = try scope.call(try scope.get(owner, "applyFunction"), runtime, &.{value});
            const kind = try scope.get(owner, "replacementKind");
            if (scope.equal(kind, try scope.text("new")) and scope.truthy(try optional(&scope, first, "setup"))) {
                const setup = try scope.get(first, "setup");
                return wait(engine, owner, try scope.call(setup, first, &.{try scope.get(try scope.get(runtime, "session"), "sessionManager")}), .new_setup);
            }
            return finishReplacement(engine, owner);
        },
        .new_setup => {
            _ = try scope.invoke(try scope.get(runtime, "session"), "refreshContext", &.{});
            return finishReplacement(engine, owner);
        },
        .import_ready => return importAfterBefore(engine, owner, value),
        .replacement_done => return replacementDone(engine, owner, value, false, 0),
    }
}
fn finishWithSession(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const callback = try scope.get(owner, "first");
    if (scope.truthy(callback)) {
        const context = try scope.invoke(try scope.get(try scope.get(owner, "agent"), "session"), "createReplacedSessionContext", &.{});
        return wait(engine, owner, try scope.call(callback, c.pi_js_undefined(), &.{context}), .context_done);
    }
    try flow.settle(engine, owner, false, c.pi_js_undefined());
}
fn replacementReason(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const kind = try scope.get(owner, "replacementKind");
    return if (scope.equal(kind, try scope.text("switch")) or scope.equal(kind, try scope.text("import"))) scope.text("resume") else if (scope.equal(kind, try scope.text("new"))) scope.text("new") else scope.text("fork");
}
fn createReplacement(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(owner, "agent");
    // Source captures this.apply before evaluating and awaiting createRuntime.
    try scope.put(owner, "applyFunction", try scope.get(runtime, "apply"));
    const create_runtime = try scope.get(runtime, "createRuntime");
    const manager = try scope.get(owner, "manager");
    const kind = try scope.get(owner, "replacementKind");
    const use_manager_cwd = scope.equal(kind, try scope.text("switch")) or scope.equal(kind, try scope.text("import")) or scope.equal(kind, try scope.text("fork-file"));
    const options = try scope.object();
    try scope.put(options, "cwd", if (use_manager_cwd) try scope.invoke(manager, "getCwd", &.{}) else try scope.get(runtime, "cwd"));
    try scope.put(options, "agentDir", try scope.get(try scope.get(runtime, "services"), "agentDir"));
    try scope.put(options, "sessionManager", manager);
    const started = try scope.object();
    try scope.put(started, "type", try scope.text("session_start"));
    try scope.put(started, "reason", try replacementReason(&scope, owner));
    try scope.put(started, "previousSessionFile", try scope.get(owner, "previous"));
    try scope.put(options, "sessionStartEvent", started);
    if (scope.equal(kind, try scope.text("switch"))) {
        const supplied = try scope.get(owner, "second");
        const factory = try optional(&scope, supplied, "projectTrustContextFactory");
        try scope.put(options, "projectTrustContext", if (temp.nullish(factory)) c.pi_js_undefined() else try scope.call(factory, supplied, &.{try scope.invoke(manager, "getCwd", &.{})}));
    }
    try wait(engine, owner, try scope.call(create_runtime, runtime, &.{options}), .replacement_finished);
}
fn finishReplacement(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const kind = try scope.get(owner, "replacementKind");
    const runtime = try scope.get(owner, "agent");
    const finish = try scope.get(runtime, "finishSessionReplacement");
    const options = if (scope.equal(kind, try scope.text("new"))) try scope.get(owner, "first") else try scope.get(owner, "second");
    const with_session = if (scope.equal(kind, try scope.text("import"))) c.pi_js_undefined() else try optional(&scope, options, "withSession");
    const result = try scope.call(finish, runtime, if (scope.equal(kind, try scope.text("import"))) &.{} else &.{with_session});
    try wait(engine, owner, result, .replacement_done);
}
fn teardownCall(scope: *Scope, runtime: c.JSValue, reason: []const u8, manager: c.JSValue) !c.JSValue {
    const function = try scope.get(runtime, "teardownCurrent");
    return scope.call(function, runtime, &.{ try scope.text(reason), try scope.invoke(manager, "getSessionFile", &.{}) });
}
fn replacementDone(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try falseResult(&scope);
    const kind = try scope.get(owner, "replacementKind");
    if (scope.equal(kind, try scope.text("fork-file")) or scope.equal(kind, try scope.text("fork-new")) or scope.equal(kind, try scope.text("fork-memory"))) try scope.put(result, "selectedText", try scope.get(owner, "selectedText"));
    try flow.settle(engine, owner, false, result);
}
fn raise(scope: *Scope, message: []const u8) anyerror {
    const reason = scope.own(js.builtin(scope.engine, "Error", &.{scope.text(message) catch |err| return err}) catch |err| return err) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason))) catch |err| return err;
    unreachable;
}
fn textPart(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const part = if (argc > 0) argv[0] else c.pi_js_undefined();
    const kind = scope.get(part, "type") catch |err| return sdk.fail(engine, err);
    const text = scope.text("text") catch |err| return sdk.fail(engine, err);
    if (!scope.equal(kind, text)) return c.pi_js_bool(engine.context, 0);
    const value = scope.get(part, "text") catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsString(value)));
}
fn partText(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "text") catch |err| sdk.fail(engine, err);
}
fn extract(scope: *Scope, content: c.JSValue) !c.JSValue {
    if (c.JS_IsString(content)) return content;
    const filter = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, textPart, "", 1)));
    const map = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, partText, "", 1)));
    return scope.invoke(try scope.invoke(try scope.invoke(content, "filter", &.{filter}), "map", &.{map}), "join", &.{try scope.text("")});
}
fn prepareFork(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(owner, "agent");
    const entry = try scope.invoke(try scope.get(try scope.get(runtime, "session"), "sessionManager"), "getEntry", &.{try scope.get(owner, "first")});
    if (!scope.truthy(entry)) return raise(&scope, "Invalid entry ID for forking");
    const position = try scope.get(owner, "position");
    var target: c.JSValue = undefined;
    if (scope.equal(position, try scope.text("at"))) target = try scope.get(entry, "id") else {
        if (!scope.equal(try scope.get(entry, "type"), try scope.text("message")) or !scope.equal(try scope.get(try scope.get(entry, "message"), "role"), try scope.text("user"))) return raise(&scope, "Invalid entry ID for forking");
        target = try scope.get(entry, "parentId");
        try scope.put(owner, "selectedText", try extract(&scope, try scope.get(try scope.get(entry, "message"), "content")));
    }
    try scope.put(owner, "targetLeaf", target);
    try scope.put(owner, "previous", try scope.get(try scope.get(runtime, "session"), "sessionFile"));
    if (scope.truthy(try scope.invoke(try scope.get(try scope.get(runtime, "session"), "sessionManager"), "isPersisted", &.{}))) {
        const current = try scope.get(try scope.get(runtime, "session"), "sessionFile");
        if (!scope.truthy(current)) return raise(&scope, "Persisted session is missing a session file");
        const directory = try scope.invoke(try scope.get(try scope.get(runtime, "session"), "sessionManager"), "getSessionDir", &.{});
        const managers = try scope.get(try scope.get(owner, "bindings"), "SessionManager");
        var manager: c.JSValue = undefined;
        if (!scope.truthy(target)) {
            const create_manager = try scope.get(managers, "create");
            manager = try scope.call(create_manager, managers, &.{ try scope.get(runtime, "cwd"), directory });
            const new_session = try scope.get(manager, "newSession");
            const options = try scope.object();
            try scope.put(options, "parentSession", current);
            _ = try scope.call(new_session, manager, &.{options});
            try scope.put(owner, "replacementKind", try scope.text("fork-new"));
        } else {
            const bindings = try scope.get(owner, "bindings");
            if (!scope.truthy(try imported(&scope, bindings, "existsSync", &.{current}))) return raise(&scope, "This session has not been saved yet. Send a message before cloning or forking it.");
            manager = try scope.invoke(managers, "open", &.{ current, directory });
            if (!scope.truthy(try scope.invoke(manager, "createBranchedSession", &.{target}))) return raise(&scope, "Failed to create forked session");
            try scope.put(owner, "replacementKind", try scope.text("fork-file"));
        }
        try scope.put(owner, "manager", manager);
        return wait(engine, owner, try teardownCall(&scope, runtime, "fork", manager), .replacement_created);
    }
    const manager = try scope.get(try scope.get(runtime, "session"), "sessionManager");
    try scope.put(owner, "manager", manager);
    try scope.put(owner, "replacementKind", try scope.text("fork-memory"));
    try wait(engine, owner, try teardownCall(&scope, runtime, "fork", manager), .fork_torn);
}
fn startImport(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.get(owner, "bindings");
    const runtime = try scope.get(owner, "agent");
    const path = try imported(&scope, bindings, "resolvePath", &.{try scope.get(owner, "first")});
    try scope.put(owner, "resolvedPath", path);
    if (!scope.truthy(try imported(&scope, bindings, "existsSync", &.{path}))) {
        var args = [_]c.JSValue{path};
        const reason = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.get(bindings, "SessionImportFileNotFoundError"), args.len, &args)));
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        unreachable;
    }
    const directory = try scope.invoke(try scope.get(try scope.get(runtime, "session"), "sessionManager"), "getSessionDir", &.{});
    try scope.put(owner, "sessionDir", directory);
    if (!scope.truthy(try imported(&scope, bindings, "existsSync", &.{directory}))) {
        const options = try scope.object();
        try scope.put(options, "recursive", c.pi_js_bool(engine.context, 1));
        _ = try imported(&scope, bindings, "mkdirSync", &.{ directory, options });
    }
    var destination = try imported(&scope, bindings, "join", &.{ directory, try imported(&scope, bindings, "basename", &.{path}) });
    const already = scope.equal(try imported(&scope, bindings, "resolve", &.{destination}), path);
    try scope.put(owner, "alreadyStored", c.pi_js_bool(engine.context, @intFromBool(already)));
    if (!already) {
        const parsed = try imported(&scope, bindings, "parse", &.{destination});
        const name = try scope.get(parsed, "name");
        const extension = try scope.get(parsed, "ext");
        var suffix: f64 = 1;
        var native_steps: u64 = 0;
        while (scope.truthy(try imported(&scope, bindings, "existsSync", &.{destination}))) {
            native_steps +|= 1;
            if (engine.cancelled.load(.acquire) or (native_steps % 256 == 0 and blk: {
                engine.interrupts +|= 1;
                break :blk engine.interrupts > engine.options.interrupt_budget;
            })) {
                _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
                unreachable;
            }
            const filename = try scope.concat(try scope.concat(try scope.concat(try scope.stringify(name), try scope.text("-")), try scope.stringify(c.JS_NewFloat64(engine.context, suffix))), try scope.stringify(extension));
            suffix += 1;
            destination = try imported(&scope, bindings, "join", &.{ directory, filename });
        }
    }
    try scope.put(owner, "destination", destination);
    try wait(engine, owner, try scope.invoke(runtime, "emitBeforeSwitch", &.{ try scope.text("resume"), destination }), .import_ready);
}
fn importAfterBefore(engine: *em.Engine, owner: c.JSValue, before: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(try scope.get(before, "cancelled"))) return flow.settle(engine, owner, false, before);
    const runtime = try scope.get(owner, "agent");
    const bindings = try scope.get(owner, "bindings");
    try scope.put(owner, "previous", try scope.get(try scope.get(runtime, "session"), "sessionFile"));
    const destination = try scope.get(owner, "destination");
    if (!scope.truthy(try scope.get(owner, "alreadyStored"))) _ = try imported(&scope, bindings, "copyFileSync", &.{ try scope.get(owner, "resolvedPath"), destination, try scope.get(try scope.get(bindings, "constants"), "COPYFILE_EXCL") });
    const managers = try scope.get(bindings, "SessionManager");
    const open = try scope.get(managers, "open");
    const manager = try scope.call(open, managers, &.{ destination, try scope.get(owner, "sessionDir"), try scope.get(owner, "second") });
    _ = try imported(&scope, bindings, "assertSessionCwdExists", &.{ manager, try scope.get(runtime, "cwd") });
    try scope.put(owner, "manager", manager);
    try scope.put(owner, "replacementKind", try scope.text("import"));
    try wait(engine, owner, try teardownCall(&scope, runtime, "resume", manager), .replacement_created);
}
fn errorClass(scope: *Scope, name: [:0]const u8, kind: usize) !c.JSValue {
    const base = try scope.global("Error");
    const prototype = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, try scope.get(base, "prototype"))));
    const constructor = try scope.own(try class.constructor(scope.engine, name, 1, prototype, errorConstruct, &.{ base, c.JS_NewUint32(scope.engine.context, @intCast(kind)) }));
    if (c.JS_SetPrototype(scope.engine.context, constructor, base) < 0) return js.capture(scope.engine);
    return constructor;
}
fn errorConstruct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const missing_cwd = scope.truthy(roots[1]);
    const input = arg(args, 0);
    const message = if (missing_cwd) try formatCwd(&scope, input, false) else try scope.concat(try scope.text("File not found: "), try scope.stringify(input));
    var super_args = [_]c.JSValue{message};
    const object = try scope.own(try engine.checked(c.JS_CallConstructor2(engine.context, roots[0], target, super_args.len, &super_args)));
    try scope.put(object, if (missing_cwd) "issue" else "filePath", c.pi_js_undefined());
    try scope.set(object, "name", try scope.text(if (missing_cwd) "MissingSessionCwdError" else "SessionImportFileNotFoundError"));
    try scope.set(object, if (missing_cwd) "issue" else "filePath", input);
    return c.JS_DupValue(engine.context, object);
}
fn helper(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return helperValue(engine, roots[0], @enumFromInt(magic), args) catch |err| sdk.fail(engine, err);
}
fn helperValue(engine: *em.Engine, bindings: c.JSValue, method: Helper, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (method) {
        .getMissingSessionCwdIssue => return missingCwd(engine, bindings, arg(args, 0), arg(args, 1)),
        .formatMissingSessionCwdError, .formatMissingSessionCwdPrompt => return c.JS_DupValue(engine.context, try formatCwd(&scope, arg(args, 0), method == .formatMissingSessionCwdPrompt)),
        .assertSessionCwdExists => {
            const issue = try scope.own(try missingCwd(engine, bindings, arg(args, 0), arg(args, 1)));
            if (scope.truthy(issue)) {
                var values = [_]c.JSValue{issue};
                const reason = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.get(bindings, "MissingSessionCwdError"), values.len, &values)));
                _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
                unreachable;
            }
            return c.pi_js_undefined();
        },
        .emitSessionShutdownEvent => return error.GenuineShutdownAsyncBodyRequired,
    }
}
fn missingCwd(engine: *em.Engine, bindings: c.JSValue, manager: c.JSValue, fallback: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const file = try scope.invoke(manager, "getSessionFile", &.{});
    if (!scope.truthy(file)) return c.pi_js_undefined();
    const cwd = try scope.invoke(manager, "getCwd", &.{});
    if (!scope.truthy(cwd) or scope.truthy(try imported(&scope, bindings, "existsSync", &.{cwd}))) return c.pi_js_undefined();
    const issue = try scope.object();
    try scope.put(issue, "sessionFile", file);
    try scope.put(issue, "sessionCwd", cwd);
    try scope.put(issue, "fallbackCwd", fallback);
    return c.JS_DupValue(engine.context, issue);
}
fn formatCwd(scope: *Scope, issue: c.JSValue, prompt: bool) !c.JSValue {
    if (prompt) return scope.concat(try scope.concat(try scope.concat(try scope.text("cwd from session file does not exist\n"), try scope.stringify(try scope.get(issue, "sessionCwd"))), try scope.text("\n\ncontinue in current cwd\n")), try scope.stringify(try scope.get(issue, "fallbackCwd")));
    const file = if (scope.truthy(try scope.get(issue, "sessionFile"))) try scope.concat(try scope.text("\nSession file: "), try scope.stringify(try scope.get(issue, "sessionFile"))) else try scope.text("");
    return scope.concat(try scope.concat(try scope.concat(try scope.concat(try scope.text("Stored session working directory does not exist: "), try scope.stringify(try scope.get(issue, "sessionCwd"))), file), try scope.text("\nCurrent working directory: ")), try scope.stringify(try scope.get(issue, "fallbackCwd")));
}
fn shutdownStart(engine: *em.Engine, owner: c.JSValue, shutdown_event: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runner = try scope.get(owner, "agent");
    if (scope.truthy(try scope.invoke(runner, "hasHandlers", &.{try scope.text("session_shutdown")}))) try flow.wait(shutdownFinished, engine, owner, try scope.invoke(runner, "emit", &.{shutdown_event}), 0) else try flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 0));
}
fn shutdownFinished(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    try flow.settle(engine, owner, rejected, if (rejected) value else c.pi_js_bool(engine.context, 1));
}
fn shutdownBody(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: flow.native.Completion, input: c.JSValue) !flow.native.Action {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    if (completion == .rejected and try flow.nativeAllocationReason(engine, state.*, input)) return error.OutOfMemory;
    if (completion == .start) {
        const owner = try flow.init(&scope, state); try scope.put(owner, "agent", arg(args, 0));
        shutdownStart(engine, owner, arg(args, 1)) catch |err| try flow.rejectError(engine, owner, err);
    } else shutdownFinished(engine, state.*, input, completion == .rejected, 0) catch |err| try flow.rejectError(engine, state.*, err);
    return flow.body.action(&scope, state.*);
}
