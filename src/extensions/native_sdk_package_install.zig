//! Actual public install/remove/persist and small Git dependency orchestration.
//! Commands and filesystem effects stay on real imported/live class bindings.
const data = @import("native_sdk_package_data.zig");
const v = @import("native_ai_provider_values.zig");
const package_catch = @import("native_sdk_package_catch.zig");
const Scope = v.Scope;
const c = v.c;
const f = @import("native_node_function.zig");
const body = @import("native_async_body.zig");
const af = body.native;
pub const Inputs = struct { exists_sync: c.JSValue, rm_sync: c.JSValue, is_offline: c.JSValue };
pub const methods = .{ "install", "installAndPersist", "remove", "removeAndPersist", "installParsedSource", "repairMissingGitDependencies", "refreshTemporaryGitSource", "removeGit", "runGitRemoteCommand" };
const Method = enum(i32) { install, installAndPersist, remove, removeAndPersist, installParsedSource, repairMissingGitDependencies, refreshTemporaryGitSource, removeGit };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn private(s: *Scope) !c.JSValue { return s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, c.pi_js_null()))); }
pub fn install(engine: *v.em.Engine, prototype: c.JSValue, inputs: Inputs) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const imports = try private(&s);
    inline for (.{ .{ "existsSync", inputs.exists_sync }, .{ "rmSync", inputs.rm_sync }, .{ "isOfflineModeEnabled", inputs.is_offline } }) |entry| { if (!c.JS_IsFunction(engine.context, entry[1])) return error.RequiredActualPackageInstallImport; try data.put(s.engine, imports, entry[0], entry[1]); }
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const length: c_int = if (field.value == @intFromEnum(Method.repairMissingGitDependencies)) 1 else 2;
        const function = try s.own(try af.createResumable(engine, field.name, length, run, &.{ imports, c.JS_NewInt32(engine.context, field.value) }));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
    }
    const remote = try s.own(try f.createMethod(engine, "runGitRemoteCommand", 2, remoteCommand, &.{}));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "runGitRemoteCommand", c.JS_DupValue(engine.context, remote), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
}
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return s.call(try s.get(imports, name), c.pi_js_undefined(), args); }
fn array(s: *Scope, values: []const c.JSValue) !c.JSValue { const result = try s.array(); for (values, 0..) |value, index| try s.index(result, @intCast(index), value); return result; }
fn cwd(s: *Scope, path: c.JSValue) !c.JSValue { const options = try s.object(); try data.put(s.engine, options, "cwd", path); return options; }
fn forced(s: *Scope, recursive: bool) !c.JSValue { const result = try s.object(); if (recursive) try data.put(s.engine, result, "recursive", c.pi_js_bool(s.engine.context, 1)); try data.put(s.engine, result, "force", c.pi_js_bool(s.engine.context, 1)); return result; }

fn remoteCommand(engine: *v.em.Engine, manager: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const run_capture = try s.get(manager, "runCommandCapture"); const options = try cwd(&s, arg(args, 0)); try data.put(s.engine, options, "timeoutMs", c.JS_NewInt32(engine.context, 10000));
    const env = try s.object(); try data.put(s.engine, env, "GIT_TERMINAL_PROMPT", try s.text("0")); try data.put(s.engine, options, "env", env);
    // Source method is ordinary and returns the exact transport Promise.
    return v.js.call(engine, run_capture, manager, &.{ try s.text("git"), arg(args, 1), options });
}
fn operation(engine: *v.em.Engine, manager: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return .{ .thrown = c.JS_DupValue(engine.context, input) };
    if (completion == .fulfilled) return .{ .returned = c.pi_js_undefined() };
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[4]) < 0) return v.js.capture(engine);
    const imports = roots[0]; const parsed = roots[1]; const scope = roots[2]; const source = roots[3]; const kind: Method = @enumFromInt(raw);
    if (kind == .refreshTemporaryGitSource) return .{ .awaited = c.JS_DupValue(engine.context, try s.invoke(manager, "updateGit", &.{ parsed, try s.text("temporary") })) };
    if (try v.eq(&s, try s.get(parsed, "type"), "npm")) return .{ .awaited = c.JS_DupValue(engine.context, if (kind == .install) try s.invoke(manager, "installNpm", &.{ parsed, scope, c.pi_js_bool(engine.context, 0) }) else try s.invoke(manager, "uninstallNpm", &.{ parsed, scope })) };
    if (try v.eq(&s, try s.get(parsed, "type"), "git")) return .{ .awaited = c.JS_DupValue(engine.context, try s.invoke(manager, if (kind == .install) "installGit" else "removeGit", &.{ parsed, scope })) };
    if (try v.eq(&s, try s.get(parsed, "type"), "local")) {
        if (kind == .install) { const resolve = try s.get(manager, "resolvePath"); const path = try s.call(resolve, manager, &.{try s.get(parsed, "path")}); if (!s.truthy(try imported(&s, imports, "existsSync", &.{path}))) return v.errorText(&s, try s.concat(try s.text("Path does not exist: "), try s.stringify(path))); }
        return .{ .returned = c.pi_js_undefined() };
    }
    return v.errorText(&s, try s.concat(try s.text(if (kind == .install) "Unsupported install source: " else "Unsupported remove source: "), try s.stringify(source)));
}
fn progress(s: *Scope, manager: c.JSValue, imports: c.JSValue, kind: Method, parsed: c.JSValue, scope: c.JSValue, source: c.JSValue) !c.JSValue {
    const with_progress = try s.get(manager, "withProgress");
    const prefix = if (kind == .install) "Installing " else if (kind == .remove) "Removing " else "Refreshing ";
    const message = try s.concat(try s.concat(try s.text(prefix), try s.stringify(source)), try s.text("..."));
    const callback = try s.own(try af.createResumableArrow(s.engine, "", 0, operation, &.{ imports, parsed, scope, source, c.JS_NewInt32(s.engine.context, @intFromEnum(kind)) }, manager));
    return s.call(with_progress, manager, &.{ try s.text(if (kind == .install) "install" else if (kind == .remove) "remove" else "pull"), source, message, callback });
}
fn run(engine: *v.em.Engine, manager: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine); const kind: Method = @enumFromInt(raw); const imports = roots[0];
    if (completion == .rejected) {
        if (kind == .refreshTemporaryGitSource) { var boundary: u64 = 0; if (c.JS_ToBigUint64(engine.context, &boundary, try s.get(state.*, "generation")) < 0) return v.js.capture(engine); try package_catch.guard(engine, input, boundary); return .{ .returned = c.pi_js_undefined() }; }
        return .{ .thrown = c.JS_DupValue(engine.context, input) };
    }
    if (completion == .fulfilled) {
        if (kind == .installAndPersist) { _ = try s.invoke(manager, "addSourceToSettings", &.{ arg(args, 0), arg(args, 1) }); return .{ .returned = c.pi_js_undefined() }; }
        if (kind == .removeAndPersist) return .{ .returned = c.JS_DupValue(engine.context, try s.invoke(manager, "removeSourceFromSettings", &.{ arg(args, 0), arg(args, 1) })) };
        return .{ .returned = c.pi_js_undefined() };
    }
    switch (kind) {
        .install, .remove => {
            const parsed = try s.invoke(manager, "parseSource", &.{arg(args, 0)}); const scope = try s.text(if (s.truthy(try v.optional(&s, arg(args, 1), "local"))) "project" else "user"); _ = try s.invoke(manager, "assertProjectTrustedForScope", &.{scope});
            return .{ .awaited = c.JS_DupValue(engine.context, try progress(&s, manager, imports, kind, parsed, scope, arg(args, 0))) };
        },
        .installAndPersist, .removeAndPersist => return .{ .awaited = c.JS_DupValue(engine.context, try s.invoke(manager, if (kind == .installAndPersist) "install" else "remove", &.{ arg(args, 0), arg(args, 1) })) },
        .installParsedSource => {
            if (try v.eq(&s, try s.get(arg(args, 0), "type"), "npm")) return .{ .awaited = c.JS_DupValue(engine.context, try s.invoke(manager, "installNpm", &.{ arg(args, 0), arg(args, 1), c.pi_js_bool(engine.context, @intFromBool(try v.eq(&s, arg(args, 1), "temporary"))) })) };
            if (try v.eq(&s, try s.get(arg(args, 0), "type"), "git")) return .{ .awaited = c.JS_DupValue(engine.context, try s.invoke(manager, "installGit", &.{ arg(args, 0), arg(args, 1) })) };
            return .{ .returned = c.pi_js_undefined() };
        },
        .repairMissingGitDependencies => {
            if (!s.truthy(try s.invoke(manager, "hasMissingGitDependencies", &.{arg(args, 0)}))) return .{ .returned = c.pi_js_undefined() };
            const run_npm = try s.get(manager, "runNpmCommand"); return .{ .awaited = c.JS_DupValue(engine.context, try s.call(run_npm, manager, &.{ try s.invoke(manager, "getGitDependencyInstallArgs", &.{}), try cwd(&s, arg(args, 0)) })) };
        },
        .refreshTemporaryGitSource => {
            if (s.truthy(try imported(&s, imports, "isOfflineModeEnabled", &.{}))) return .{ .returned = c.pi_js_undefined() };
            const job = try body.init(&s, state); const generation = engine.native_allocation_generation; try data.put(s.engine, job, "generation", try s.own(try engine.checked(c.JS_NewBigUint64(engine.context, generation))));
            const pending = progress(&s, manager, imports, kind, arg(args, 0), c.pi_js_undefined(), arg(args, 1)) catch |err| { try package_catch.ignore(engine, err, generation); return .{ .returned = c.pi_js_undefined() }; };
            return .{ .awaited = c.JS_DupValue(engine.context, pending) };
        },
        .removeGit => {
            const path = try s.invoke(manager, "getGitInstallPath", &.{ arg(args, 0), arg(args, 1) }); _ = try imported(&s, imports, "rmSync", &.{ path, try forced(&s, true) }); _ = try imported(&s, imports, "rmSync", &.{ try s.invoke(manager, "getGitUpdateMarkerPath", &.{path}), try forced(&s, false) });
            const prune = try s.get(manager, "pruneEmptyGitParents"); _ = try s.call(prune, manager, &.{ path, try s.invoke(manager, "getGitInstallRoot", &.{arg(args, 1)}) }); return .{ .returned = c.pi_js_undefined() };
        },
    }
}
