//! Actual utils/shell.ts shell selection/environment/output and tracked-child
//! bodies. Real child_process spawn/spawnSync/execSync and process are imports;
//! this namespace supplies no dummy command runner or successful process result.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = @import("native_node_socket_scope.zig").Scope;
const functions = @import("native_child_process_function.zig");
const owned = @import("native_sdk_owned_completion.zig");
const guest = @import("native_sdk_guest_operation.zig");
const process_body = @import("native_sdk_shell_process.zig");
const c = em.c;
pub const Inputs = struct { process: c.JSValue, paths: c.JSValue, filesystem: c.JSValue, child_process: c.JSValue, configuration: c.JSValue };
const Method = enum(c_int) { getShellConfig, getPowerShellConfig, getShellEnv, sanitizeBinaryOutput, trackDetachedChildPid, untrackDetachedChildPid, killTrackedDetachedChildren, killProcessTree };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn imported(scope: *Scope, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(bindings, name), c.pi_js_undefined(), args);
}
fn capture(scope: *Scope, bindings: c.JSValue, namespace: c.JSValue, comptime names: anytype) !void {
    inline for (names) |name| {
        const value = try scope.get(namespace, name);
        if (!c.JS_IsFunction(scope.engine.context, value)) return error.RequiredActualSdkShellImport;
        try scope.put(bindings, name, value);
    }
}
const module_name = "pi-native:sdk-shell";
pub fn create(engine: *em.Engine, inputs: Inputs) !c.JSValue {
    try engine.checkNativeEntry();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    const result = createInner(engine, inputs) catch |err| @import("native_sdk.zig").fail(engine, err);
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn createInner(engine: *em.Engine, inputs: Inputs) !c.JSValue {
    if (engine.native_module_values.get(module_name)) |cached| return c.JS_DupValue(engine.context, cached);
    var scope: Scope = .{ .engine = engine };
    const namespace = try owned.finishValue(&scope, createBody(&scope, inputs));
    var publication: guest.Boundary = .{ .engine = engine };
    publication.begin() catch |err| {
        var completion = owned.Completion.initVoid(engine, err);
        completion.release(namespace);
        try completion.finishVoid();
        unreachable;
    };
    publication.finishVoid(engine.registerValueModule(module_name, namespace)) catch |err| {
        var completion = owned.Completion.initVoid(engine, err);
        completion.release(namespace);
        try completion.finishVoid();
        unreachable;
    };
    return namespace;
}
fn createBody(scope: *Scope, inputs: Inputs) !c.JSValue {
    const engine = scope.engine;
    const bindings = try scope.object();
    try capture(scope, bindings, inputs.paths, .{"join"});
    try scope.put(bindings, "delimiter", try scope.get(inputs.paths, "delimiter"));
    try capture(scope, bindings, inputs.filesystem, .{"existsSync"});
    try capture(scope, bindings, inputs.child_process, .{ "spawn", "spawnSync", "execSync" });
    try capture(scope, bindings, inputs.configuration, .{"getBinDir"});
    try scope.put(bindings, "process", inputs.process);
    const powershell_args = try scope.array();
    inline for (.{ "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command" }, 0..) |name, index| try scope.index(powershell_args, index, try scope.text(name));
    try scope.put(bindings, "POWERSHELL_ARGS", powershell_args);
    try scope.put(bindings, "trackedDetachedChildPids", try guest.construct(scope, try guest.global(scope, "Set"), &.{}));
    const namespace = try scope.object();
    try scope.put(namespace, "POWERSHELL_ARGS", powershell_args);
    // These are the same genuine imported functions required by config-value.
    try scope.put(namespace, "spawnSync", try scope.get(bindings, "spawnSync"));
    try scope.put(namespace, "execSync", try scope.get(bindings, "execSync"));
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const operation: Method = @enumFromInt(field.value);
        const length: c_int = switch (operation) {
            .getPowerShellConfig, .getShellEnv, .killTrackedDetachedChildren => 0,
            else => 1,
        };
        try scope.put(namespace, field.name, try scope.own(try functions.create(engine, field.name, length, callback, &.{ bindings, c.JS_NewInt32(engine.context, field.value) })));
    }
    return c.JS_DupValue(engine.context, namespace);
}
fn regexp(scope: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    const args = [_]c.JSValue{ try scope.text(pattern), try scope.text(flags) };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, @constCast(&args))));
}
fn windows(scope: *Scope, bindings: c.JSValue) !bool {
    return scope.equal(try scope.get(try scope.get(bindings, "process"), "platform"), try scope.text("win32"));
}
fn ignore(scope: *Scope, err: anyerror, generation: u64) !void {
    if (scope.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
    if (scope.engine.captured_exception) |reason| scope.engine.freeValue(reason);
    scope.engine.captured_exception = null;
}
fn findExecutable(scope: *Scope, bindings: c.JSValue, name: c.JSValue) !c.JSValue {
    const is_windows = try windows(scope, bindings);
    const generation = scope.engine.native_allocation_generation;
    return findBody(scope, bindings, name, is_windows) catch |err| {
        try ignore(scope, err, generation);
        return c.pi_js_null();
    };
}
fn findBody(scope: *Scope, bindings: c.JSValue, name: c.JSValue, is_windows: bool) !c.JSValue {
    const args = try scope.array();
    try scope.index(args, 0, name);
    const options = try scope.object();
    try scope.put(options, "encoding", try scope.text("utf-8"));
    try scope.put(options, "timeout", c.JS_NewInt32(scope.engine.context, 5000));
    if (is_windows) try scope.put(options, "windowsHide", c.pi_js_bool(scope.engine.context, 1));
    const result = try imported(scope, bindings, "spawnSync", &.{ try scope.text(if (is_windows) "where" else "which"), args, options });
    if (scope.equal(try scope.get(result, "status"), c.JS_NewInt32(scope.engine.context, 0)) and scope.truthy(try scope.get(result, "stdout"))) {
        const split = try scope.invoke(try scope.invoke(try scope.get(result, "stdout"), "trim", &.{}), "split", &.{try regexp(scope, "\\r?\\n", "")});
        const first = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, split, 0)));
        if (scope.truthy(first) and (!is_windows or scope.truthy(try imported(scope, bindings, "existsSync", &.{first})))) return first;
    }
    return c.pi_js_null();
}
fn bash(scope: *Scope, shell: c.JSValue) !c.JSValue {
    const normalized = try scope.invoke(try scope.invoke(shell, "replace", &.{ try regexp(scope, "/", "g"), try scope.text("\\") }), "toLowerCase", &.{});
    const legacy = scope.truthy(try scope.invoke(try regexp(scope, "^[a-z]:\\\\windows\\\\(?:system32|sysnative)\\\\bash\\.exe$", ""), "test", &.{normalized}));
    const result = try scope.object();
    try scope.put(result, "shell", shell);
    const args = try scope.array();
    try scope.index(args, 0, try scope.text(if (legacy) "-s" else "-c"));
    try scope.put(result, "args", args);
    if (legacy) try scope.put(result, "commandTransport", try scope.text("stdin"));
    return result;
}
fn throwError(scope: *Scope, message: c.JSValue) !c.JSValue {
    const reason = try scope.own(try js.builtin(scope.engine, "Error", &.{message}));
    return scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason)));
}
fn shellConfig(scope: *Scope, bindings: c.JSValue, custom: c.JSValue) !c.JSValue {
    if (scope.truthy(custom)) {
        if (scope.truthy(try imported(scope, bindings, "existsSync", &.{custom}))) return bash(scope, custom);
        return throwError(scope, try scope.concat(try scope.text("Custom shell path not found: "), try scope.stringify(custom)));
    }
    if (try windows(scope, bindings)) {
        const paths = try scope.array();
        const process = try scope.get(bindings, "process");
        const first = try scope.get(try scope.get(process, "env"), "ProgramFiles");
        if (scope.truthy(first)) _ = try scope.invoke(paths, "push", &.{try scope.concat(try scope.stringify(first), try scope.text("\\Git\\bin\\bash.exe"))});
        const second = try scope.get(try scope.get(process, "env"), "ProgramFiles(x86)");
        if (scope.truthy(second)) _ = try scope.invoke(paths, "push", &.{try scope.concat(try scope.stringify(second), try scope.text("\\Git\\bin\\bash.exe"))});
        var iterator = try js.Iterator.init(scope.engine, paths, try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context))));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |path| {
            defer scope.engine.freeValue(path);
            if (scope.truthy(try imported(scope, bindings, "existsSync", &.{path}))) {
                const result = try bash(scope, path);
                try iterator.close();
                return result;
            }
        }
        const found = try findExecutable(scope, bindings, try scope.text("bash.exe"));
        if (scope.truthy(found)) return bash(scope, found);
        const mapper = try scope.own(try functions.createArrow(scope.engine, "", 1, indent, &.{}));
        const searched = try scope.invoke(try scope.invoke(paths, "map", &.{mapper}), "join", &.{try scope.text("\n")});
        return throwError(scope, try scope.concat(try scope.text("No bash shell found. Options:\n  1. Install Git for Windows: https://git-scm.com/download/win\n  2. Add your bash to PATH (Cygwin, MSYS2, etc.)\n  3. Set shellPath in settings.json\n\nSearched Git Bash in:\n"), try scope.stringify(searched)));
    }
    if (scope.truthy(try imported(scope, bindings, "existsSync", &.{try scope.text("/bin/bash")}))) return bash(scope, try scope.text("/bin/bash"));
    const found = try findExecutable(scope, bindings, try scope.text("bash"));
    if (scope.truthy(found)) return bash(scope, found);
    const result = try scope.object();
    try scope.put(result, "shell", try scope.text("sh"));
    const args = try scope.array();
    try scope.index(args, 0, try scope.text("-c"));
    try scope.put(result, "args", args);
    return result;
}
fn indent(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try scope.concat(try scope.text("  "), try scope.stringify(arg(args, 0))));
}
fn pathKey(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.invoke(arg(args, 0), "toLowerCase", &.{}), try scope.text("path"))));
}
fn shellEnv(scope: *Scope, bindings: c.JSValue) !c.JSValue {
    const bin = try imported(scope, bindings, "getBinDir", &.{});
    const process = try scope.get(bindings, "process");
    const object = try scope.global("Object");
    const keys_function = try scope.get(object, "keys");
    const keys = try scope.call(keys_function, object, &.{try scope.get(process, "env")});
    const predicate = try scope.own(try functions.createArrow(scope.engine, "", 1, pathKey, &.{}));
    const found = try scope.invoke(keys, "find", &.{predicate});
    const key = if (temp.nullish(found)) try scope.text("PATH") else found;
    const supplied = try scope.own(try js.getKey(scope.engine, try scope.get(process, "env"), key));
    const current = if (temp.nullish(supplied)) try scope.text("") else supplied;
    const entries = try scope.invoke(try scope.invoke(current, "split", &.{try scope.get(bindings, "delimiter")}), "filter", &.{try scope.global("Boolean")});
    const included = scope.truthy(try scope.invoke(entries, "includes", &.{bin}));
    var updated = current;
    if (!included) {
        const values = try scope.array();
        try scope.index(values, 0, bin);
        try scope.index(values, 1, current);
        updated = try scope.invoke(try scope.invoke(values, "filter", &.{try scope.global("Boolean")}), "join", &.{try scope.get(bindings, "delimiter")});
    }
    const result = try scope.own(try js.spread(scope.engine, try scope.get(process, "env")));
    const atom = try js.atom(scope.engine, key);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyValue(scope.engine.context, result, atom, c.JS_DupValue(scope.engine.context, updated), c.JS_PROP_C_W_E) < 0) return js.capture(scope.engine);
    return result;
}
fn callback(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return owned.finishValue(&scope, callbackBody(&scope, args, roots));
}
fn callbackBody(scope: *Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var operation: i32 = undefined;
    if (c.JS_ToInt32(scope.engine.context, &operation, roots[1]) < 0) return js.capture(scope.engine);
    return c.JS_DupValue(scope.engine.context, try execute(scope, roots[0], @enumFromInt(operation), args));
}
fn execute(scope: *Scope, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .getShellConfig => return shellConfig(scope, bindings, arg(args, 0)),
        .getPowerShellConfig => {
            if (!try windows(scope, bindings)) return throwError(scope, try scope.text("The powershell tool is only available on Windows."));
            const modern = try findExecutable(scope, bindings, try scope.text("pwsh.exe"));
            const shell = if (temp.nullish(modern)) try findExecutable(scope, bindings, try scope.text("powershell.exe")) else modern;
            if (!scope.truthy(shell)) return throwError(scope, try scope.text("No PowerShell executable found. Install PowerShell or add powershell.exe/pwsh.exe to PATH."));
            const result = try scope.object();
            try scope.put(result, "shell", shell);
            try scope.put(result, "args", try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(scope.engine, try scope.get(bindings, "POWERSHELL_ARGS"), null)));
            return result;
        },
        .getShellEnv => return shellEnv(scope, bindings),
        .sanitizeBinaryOutput => return scope.invoke(arg(args, 0), "replace", &.{ try regexp(scope, "[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\uFFF9-\\uFFFB]", "g"), try scope.text("") }),
        .trackDetachedChildPid => try process_body.track(scope.engine, try scope.get(bindings, "trackedDetachedChildPids"), arg(args, 0)),
        .untrackDetachedChildPid => try process_body.untrack(scope.engine, try scope.get(bindings, "trackedDetachedChildPids"), arg(args, 0)),
        .killTrackedDetachedChildren => try process_body.killTracked(scope.engine, bindings, try scope.get(bindings, "trackedDetachedChildPids")),
        .killProcessTree => try process_body.kill(scope.engine, bindings, arg(args, 0)),
    }
    return c.pi_js_undefined();
}
