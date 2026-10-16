//! Actual clone/ref/dependency repair lifecycle. These Source bodies use real
//! Git/npm transports and managed paths; no repository or command success is
//! synthesized. This file is source-only until the owner admits real fixtures.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const body = @import("native_async_body.zig");
const af = body.native;
const f = @import("native_node_function.zig");
pub const Inputs = struct { paths: c.JSValue, filesystem: c.JSValue };
pub const methods = .{ "installGit", "updateGit", "cleanAndInstallGitDependencies", "ensureGitRef" };
const Method = enum(i32) { installGit, updateGit, cleanAndInstallGitDependencies, ensureGitRef };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn install(engine: *v.em.Engine, prototype: c.JSValue, inputs: Inputs) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const imports = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    inline for (.{ "join", "dirname" }) |name| { const value = try s.get(inputs.paths, name); if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualPackageGitImport; try s.put(imports, name, value); }
    inline for (.{ "existsSync", "mkdirSync", "rmSync", "writeFileSync" }) |name| { const value = try s.get(inputs.filesystem, name); if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualPackageGitImport; try s.put(imports, name, value); }
    inline for (@typeInfo(Method).@"enum".fields) |field| { const value = try s.own(try af.createResumable(engine, field.name, if (field.value == @intFromEnum(Method.ensureGitRef)) 3 else 2, run, &.{ imports, c.JS_NewInt32(engine.context, field.value) })); if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, value), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine); }
}
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return s.call(try s.get(imports, name), c.pi_js_undefined(), args); }
fn array(s: *Scope, values: []const c.JSValue) !c.JSValue { const result = try s.array(); for (values, 0..) |value, index| try s.index(result, @intCast(index), value); return result; }
fn opts(s: *Scope, recursive: bool, force: bool) !c.JSValue { const result = try s.object(); if (recursive) try s.put(result, "recursive", c.pi_js_bool(s.engine.context, 1)); if (force) try s.put(result, "force", c.pi_js_bool(s.engine.context, 1)); return result; }
fn cwd(s: *Scope, path: c.JSValue, timeout: bool) !c.JSValue { const result = try s.object(); try s.put(result, "cwd", path); if (timeout) try s.put(result, "timeoutMs", c.JS_NewInt32(s.engine.context, 10000)); return result; }
fn exists(s: *Scope, imports: c.JSValue, path: c.JSValue) !bool { return s.truthy(try imported(s, imports, "existsSync", &.{path})); }
fn stage(s: *Scope, job: c.JSValue) !i32 { var result: i32 = 0; if (c.JS_ToInt32(s.engine.context, &result, try s.get(job, "stage")) < 0) return v.js.capture(s.engine); return result; }
fn wait(s: *Scope, job: c.JSValue, next: i32, pending: c.JSValue) !af.Action { try s.put(job, "stage", c.JS_NewInt32(s.engine.context, next)); return .{ .awaited = c.JS_DupValue(s.engine.context, pending) }; }
fn command(s: *Scope, manager: c.JSValue, values: c.JSValue, path: ?c.JSValue, capture: bool) !c.JSValue { const run_command = try s.get(manager, if (capture) "runCommandCapture" else "runCommand"); return if (path) |dir| s.call(run_command, manager, &.{ try s.text("git"), values, try cwd(s, dir, capture) }) else s.call(run_command, manager, &.{ try s.text("git"), values }); }
fn dependencyInstall(s: *Scope, manager: c.JSValue, path: c.JSValue) !c.JSValue { const run_npm = try s.get(manager, "runNpmCommand"); return s.call(run_npm, manager, &.{ try s.invoke(manager, "getGitDependencyInstallArgs", &.{}), try cwd(s, path, false) }); }
fn boundary(s: *Scope, job: c.JSValue) !void { try s.put(job, "boundary", try s.own(try s.engine.checked(c.JS_NewBigUint64(s.engine.context, s.engine.native_allocation_generation)))); }
fn trusted(s: *Scope, job: c.JSValue, reason: c.JSValue) !void { var generation: u64 = 0; if (c.JS_ToBigUint64(s.engine.context, &generation, try s.get(job, "boundary")) < 0) return v.js.capture(s.engine); try body.rethrowRecognizedAllocation(s.engine, reason, generation); }
fn ignoreRepair(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { var generation: u64 = 0; if (c.JS_ToBigUint64(engine.context, &generation, roots[0]) < 0) return v.js.capture(engine); try body.rethrowRecognizedAllocation(engine, arg(args, 0), generation); return c.pi_js_undefined(); }
fn failClean(s: *Scope, manager: c.JSValue, job: c.JSValue, path: c.JSValue, reason: c.JSValue) !af.Action {
    try trusted(s, job, reason); try s.put(job, "originalReason", reason); try s.put(job, "stage", c.JS_NewInt32(s.engine.context, 11));
    const generation = s.engine.native_allocation_generation; const pending = try s.invoke(manager, "repairMissingGitDependencies", &.{path}); const marker = try s.own(try s.engine.checked(c.JS_NewBigUint64(s.engine.context, generation)));
    const handled = try s.invoke(pending, "catch", &.{try s.own(try f.createArrow(s.engine, "", 0, ignoreRepair, &.{marker}))}); return .{ .awaited = c.JS_DupValue(s.engine.context, handled) };
}
fn failClone(s: *Scope, manager: c.JSValue, imports: c.JSValue, job: c.JSValue, reason: c.JSValue) !af.Action {
    try trusted(s, job, reason); const path = try s.get(job, "path"); _ = try imported(s, imports, "rmSync", &.{ path, try opts(s, true, true) }); _ = try s.invoke(manager, "pruneEmptyGitParents", &.{ path, try s.get(job, "gitRoot") }); return .{ .thrown = c.JS_DupValue(s.engine.context, reason) };
}
fn npmIfManifest(s: *Scope, manager: c.JSValue, imports: c.JSValue, job: c.JSValue, path: c.JSValue, next: i32) !af.Action {
    const manifest = try imported(s, imports, "join", &.{ path, try s.text("package.json") }); if (try exists(s, imports, manifest)) return wait(s, job, next, try dependencyInstall(s, manager, path));
    if (next == 13) _ = try imported(s, imports, "rmSync", &.{ try s.get(job, "marker"), try opts(s, false, true) }); return .{ .returned = c.pi_js_undefined() };
}
fn ensure(s: *Scope, manager: c.JSValue, path: c.JSValue, source: c.JSValue) !c.JSValue { const function = try s.get(manager, "ensureGitRef"); return s.call(function, manager, &.{ path, try array(s, &.{ try s.text("fetch"), try s.text("origin"), try s.get(source, "ref") }), try s.text("FETCH_HEAD") }); }
fn evaluate(s: *Scope, manager: c.JSValue, imports: c.JSValue, args: []const c.JSValue, job: c.JSValue, kind: Method, completion: af.Completion, input: c.JSValue) !af.Action {
    const engine = s.engine;
    if (completion == .start) switch (kind) {
        .ensureGitRef => return wait(s, job, 1, try command(s, manager, arg(args, 1), arg(args, 0), false)),
        .cleanAndInstallGitDependencies => { try s.put(job, "marker", arg(args, 1)); try s.put(job, "stage", c.JS_NewInt32(engine.context, 10)); try boundary(s, job); return wait(s, job, 10, try command(s, manager, try array(s, &.{ try s.text("clean"), try s.text("-fdx") }), arg(args, 0), false)); },
        .installGit, .updateGit => {
            const path = try s.invoke(manager, "getGitInstallPath", &.{ arg(args, 0), arg(args, 1) }); try s.put(job, "path", path);
            const present = try exists(s, imports, path);
            if (kind == .updateGit and !present) return wait(s, job, 30, try s.invoke(manager, "installGit", &.{ arg(args, 0), arg(args, 1) }));
            if (present) { if (s.truthy(try s.get(arg(args, 0), "ref"))) return wait(s, job, 30, try ensure(s, manager, path, arg(args, 0))); return wait(s, job, 20, try s.invoke(manager, "getLocalGitUpdateTarget", &.{path})); }
            const git_root = try s.invoke(manager, "getGitInstallRoot", &.{arg(args, 1)}); try s.put(job, "gitRoot", git_root); if (s.truthy(git_root)) _ = try s.invoke(manager, "ensureGitIgnore", &.{git_root});
            _ = try imported(s, imports, "mkdirSync", &.{ try imported(s, imports, "dirname", &.{path}), try opts(s, true, false) }); _ = try imported(s, imports, "rmSync", &.{ try s.invoke(manager, "getGitUpdateMarkerPath", &.{path}), try opts(s, false, true) });
            try s.put(job, "cloneTry", c.pi_js_bool(engine.context, 1)); try boundary(s, job); const run_command = try s.get(manager, "runCommand"); return wait(s, job, 21, try s.call(run_command, manager, &.{ try s.text("git"), try array(s, &.{ try s.text("clone"), try s.get(arg(args, 0), "repo"), path }) }));
        },
    };
    switch (try stage(s, job)) {
        1 => return wait(s, job, 2, try command(s, manager, try array(s, &.{ try s.text("rev-parse"), try s.text("HEAD") }), arg(args, 0), true)),
        2 => { try s.put(job, "localHead", input); const ref = try s.concat(try s.stringify(arg(args, 2)), try s.text("^{commit}")); try s.put(job, "commitRef", ref); return wait(s, job, 3, try command(s, manager, try array(s, &.{ try s.text("rev-parse"), ref }), arg(args, 0), true)); },
        3 => { const marker = try s.invoke(manager, "getGitUpdateMarkerPath", &.{arg(args, 0)}); try s.put(job, "marker", marker); const local = try s.invoke(try s.get(job, "localHead"), "trim", &.{}); const target = try s.invoke(input, "trim", &.{});
            if (s.equal(local, target)) return wait(s, job, 4, if (try exists(s, imports, marker)) try s.invoke(manager, "cleanAndInstallGitDependencies", &.{ arg(args, 0), marker }) else try s.invoke(manager, "repairMissingGitDependencies", &.{arg(args, 0)}));
            _ = try imported(s, imports, "writeFileSync", &.{ marker, try s.text(""), try s.text("utf-8") }); return wait(s, job, 5, try command(s, manager, try array(s, &.{ try s.text("reset"), try s.text("--hard"), try s.get(job, "commitRef") }), arg(args, 0), false));
        },
        4, 30 => return .{ .returned = c.pi_js_undefined() },
        5 => return wait(s, job, 4, try s.invoke(manager, "cleanAndInstallGitDependencies", &.{ arg(args, 0), try s.get(job, "marker") })),
        10 => { try s.put(job, "stage", c.JS_NewInt32(engine.context, 12)); return npmIfManifest(s, manager, imports, job, arg(args, 0), 13); },
        11 => return .{ .thrown = c.JS_DupValue(engine.context, try s.get(job, "originalReason")) },
        13 => { _ = try imported(s, imports, "rmSync", &.{ try s.get(job, "marker"), try opts(s, false, true) }); return .{ .returned = c.pi_js_undefined() }; },
        20 => { const ensure_ref = try s.get(manager, "ensureGitRef"); return wait(s, job, 30, try s.call(ensure_ref, manager, &.{ try s.get(job, "path"), try s.get(input, "fetchArgs"), try s.get(input, "ref") })); },
        21 => { if (s.truthy(try s.get(arg(args, 0), "ref"))) { const run_command = try s.get(manager, "runCommand"); return wait(s, job, 22, try s.call(run_command, manager, &.{ try s.text("git"), try array(s, &.{ try s.text("checkout"), try s.get(arg(args, 0), "ref") }), try cwd(s, try s.get(job, "path"), false) })); } return npmIfManifest(s, manager, imports, job, try s.get(job, "path"), 23); },
        22 => return npmIfManifest(s, manager, imports, job, try s.get(job, "path"), 23), 23 => return .{ .returned = c.pi_js_undefined() },
        else => return error.InvalidPackageGitStage,
    }
}
fn run(engine: *v.em.Engine, manager: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine); const kind: Method = @enumFromInt(raw); const imports = roots[0]; const job = if (completion == .start) try body.init(&s, state) else state.*;
    if (completion == .rejected) { if (kind == .cleanAndInstallGitDependencies and try stage(&s, job) == 10) return failClean(&s, manager, job, arg(args, 0), input); if (kind == .installGit and s.truthy(try s.get(job, "cloneTry"))) return failClone(&s, manager, imports, job, input); return .{ .thrown = c.JS_DupValue(engine.context, input) }; }
    return evaluate(&s, manager, imports, args, job, kind, completion, input) catch |err| {
        const clean = kind == .cleanAndInstallGitDependencies and try stage(&s, job) == 10; const clone = kind == .installGit and s.truthy(try s.get(job, "cloneTry")); if (!clean and !clone) return err;
        if (err == error.JavaScriptException) if (engine.captured_exception) |reason| try trusted(&s, job, reason);
        var generation: u64 = 0; if (c.JS_ToBigUint64(engine.context, &generation, try s.get(job, "boundary")) < 0) return v.js.capture(engine); const classified = engine.nativeAllocationError(err, generation); if (classified == error.OutOfMemory) return classified;
        const reason = try s.own(@import("native_agent_async.zig").reason(engine, classified)); return if (clean) failClean(&s, manager, job, arg(args, 0), reason) else failClone(&s, manager, imports, job, reason);
    };
}
