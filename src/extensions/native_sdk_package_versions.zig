//! Actual npm/Git version and update-target probes. All command responses and
//! semver decisions come from the real transport and required semver imports.
const v = @import("native_ai_provider_values.zig");
const package_catch = @import("native_sdk_package_catch.zig");
const Scope = v.Scope;
const c = v.c;
const body = @import("native_async_body.zig");
const af = body.native;
const f = @import("native_node_function.zig");
pub const Inputs = struct { exists_sync: c.JSValue, is_offline: c.JSValue, satisfies: c.JSValue, gt: c.JSValue, max_satisfying: c.JSValue, rcompare: c.JSValue };
pub const methods = .{ "installedNpmMatchesConfiguredVersion", "npmHasAvailableUpdate", "shouldUpdateNpmSource", "getLatestNpmVersion", "gitHasAvailableUpdate", "getRemoteGitHead", "getGitUpstreamRef", "getLocalGitUpdateTarget" };
const Method = enum(i32) { installedNpmMatchesConfiguredVersion, npmHasAvailableUpdate, shouldUpdateNpmSource, getLatestNpmVersion, gitHasAvailableUpdate, getRemoteGitHead, getGitUpstreamRef, getLocalGitUpdateTarget };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn install(engine: *v.em.Engine, prototype: c.JSValue, inputs: Inputs) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const imports = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    inline for (.{ .{ "existsSync", inputs.exists_sync }, .{ "isOfflineModeEnabled", inputs.is_offline }, .{ "satisfies", inputs.satisfies }, .{ "gt", inputs.gt }, .{ "maxSatisfying", inputs.max_satisfying }, .{ "rcompare", inputs.rcompare } }) |entry| { if (!c.JS_IsFunction(engine.context, entry[1])) return error.RequiredActualPackageVersionImport; try s.put(imports, entry[0], entry[1]); }
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const length: c_int = if (field.value <= @intFromEnum(Method.getLatestNpmVersion)) 2 else 1;
        const function = try s.own(try af.createResumable(engine, field.name, length, run, &.{ imports, c.JS_NewInt32(engine.context, field.value) }));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
    }
}
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return s.call(try s.get(imports, name), c.pi_js_undefined(), args); }
fn array(s: *Scope, values: []const c.JSValue) !c.JSValue { const result = try s.array(); for (values, 0..) |value, index| try s.index(result, @intCast(index), value); return result; }
fn append(s: *Scope, target: c.JSValue, values: c.JSValue) !void { var iterator = try v.iterator(s, values); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |value| { defer s.engine.freeValue(value); try s.index(target, try v.length(s, target), value); } }
fn options(s: *Scope, path: c.JSValue) !c.JSValue { const result = try s.object(); try s.put(result, "cwd", path); try s.put(result, "timeoutMs", c.JS_NewInt32(s.engine.context, 10000)); return result; }
fn stage(s: *Scope, job: c.JSValue, value: i32) !void { try s.put(job, "stage", c.JS_NewInt32(s.engine.context, value)); }
fn integer(s: *Scope, object: c.JSValue, key: [*:0]const u8) !i32 { var result: i32 = 0; if (c.JS_ToInt32(s.engine.context, &result, try s.get(object, key)) < 0) return v.js.capture(s.engine); return result; }
fn catching(s: *Scope, job: c.JSValue, mode: i32) !void { try s.put(job, "catchMode", c.JS_NewInt32(s.engine.context, mode)); try s.put(job, "boundary", try s.own(try s.engine.checked(c.JS_NewBigUint64(s.engine.context, s.engine.native_allocation_generation)))); }
fn wait(s: *Scope, job: c.JSValue, next: i32, pending: c.JSValue) !af.Action { try stage(s, job, next); return .{ .awaited = c.JS_DupValue(s.engine.context, pending) }; }
fn trusted(s: *Scope, job: c.JSValue, reason: c.JSValue) !void { var generation: u64 = 0; if (c.JS_ToBigUint64(s.engine.context, &generation, try s.get(job, "boundary")) < 0) return v.js.capture(s.engine); try package_catch.guard(s.engine, reason, generation); }
fn catchBoundary(engine: *v.em.Engine, args: []const c.JSValue, roots: []const c.JSValue) !void { var generation: u64 = 0; if (c.JS_ToBigUint64(engine.context, &generation, roots[0]) < 0) return v.js.capture(engine); try package_catch.guard(engine, arg(args, 0), generation); }
fn empty(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { try catchBoundary(engine, args, roots); return engine.checked(c.JS_NewString(engine.context, "")); }
fn noop(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { try catchBoundary(engine, args, roots); return c.pi_js_undefined(); }
fn validVersion(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { if (!c.JS_IsString(arg(args, 0))) return c.pi_js_bool(engine.context, 0); var s: Scope = .{ .engine = engine }; defer s.deinit(); return c.pi_js_bool(engine.context, @intFromBool(try @import("native_image_arithmetic.zig").compare(engine, .greater, try s.get(arg(args, 0), "length"), c.JS_NewInt32(engine.context, 0)))); }
fn match(s: *Scope, text: c.JSValue, pattern: []const u8) !c.JSValue { const method = try s.get(text, "match"); var args = [_]c.JSValue{ try s.text(pattern), try s.text("m") }; const regex = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, 2, &args))); return s.call(method, text, &.{regex}); }
fn firstMatch(s: *Scope, value: c.JSValue) !c.JSValue { return if (v.nullish(value)) c.pi_js_undefined() else v.at(s, value, 1); }
fn capture(s: *Scope, manager: c.JSValue, path: c.JSValue, args: c.JSValue) !c.JSValue { const run_capture = try s.get(manager, "runCommandCapture"); return s.call(run_capture, manager, &.{ try s.text("git"), args, try options(s, path) }); }
fn fallbackTarget(s: *Scope, manager: c.JSValue, job: c.JSValue, path: c.JSValue) !af.Action {
    try catching(s, job, 0); const generation = s.engine.native_allocation_generation; const command = try s.get(manager, "runCommand"); const pending = try s.call(command, manager, &.{ try s.text("git"), try array(s, &.{ try s.text("remote"), try s.text("set-head"), try s.text("origin"), try s.text("-a") }), blk: { const value = try s.object(); try s.put(value, "cwd", path); break :blk value; } });
    const marker = try s.own(try s.engine.checked(c.JS_NewBigUint64(s.engine.context, generation))); const handled = try s.invoke(pending, "catch", &.{try s.own(try f.createArrow(s.engine, "", 0, noop, &.{marker}))}); return wait(s, job, 20, handled);
}
fn failure(s: *Scope, manager: c.JSValue, job: c.JSValue, reason: c.JSValue) !af.Action {
    const mode = try integer(s, job, "catchMode"); if (mode == 0) return .{ .thrown = c.JS_DupValue(s.engine.context, reason) }; try trusted(s, job, reason);
    return recover(s, manager, job, mode);
}
fn recover(s: *Scope, manager: c.JSValue, job: c.JSValue, mode: i32) !af.Action {
    return switch (mode) { 1 => .{ .returned = c.pi_js_bool(s.engine.context, 1) }, 2 => .{ .returned = c.pi_js_bool(s.engine.context, 0) }, 3 => .{ .returned = c.pi_js_undefined() }, 4 => fallbackTarget(s, manager, job, try s.get(job, "path")), else => error.InvalidPackageVersionCatchMode };
}
fn target(s: *Scope, ref: c.JSValue, head: c.JSValue, branch: c.JSValue, fallback: bool) !c.JSValue {
    const result = try s.object(); try s.put(result, "ref", ref); try s.put(result, "head", head);
    const fetch = try array(s, &.{ try s.text("fetch"), try s.text("--prune"), try s.text("--no-tags"), try s.text("origin") });
    const spec = if (fallback and !s.truthy(branch)) try s.text("+HEAD:refs/remotes/origin/HEAD") else try s.concat(try s.concat(try s.concat(try s.text("+refs/heads/"), try s.stringify(branch)), try s.text(":refs/remotes/origin/")), try s.stringify(branch));
    try s.index(fetch, 4, spec); try s.put(result, "fetchArgs", fetch); return result;
}
fn evaluate(s: *Scope, manager: c.JSValue, args: []const c.JSValue, imports: c.JSValue, job: c.JSValue, kind: Method, completion: af.Completion, input: c.JSValue) !af.Action {
    const engine = s.engine;
    if (completion == .start) {
        switch (kind) {
            .installedNpmMatchesConfiguredVersion => { const installed = try s.invoke(manager, "getInstalledNpmVersion", &.{arg(args, 1)}); if (!s.truthy(installed)) return .{ .returned = c.pi_js_bool(engine.context, 0) }; const source = arg(args, 0); return .{ .returned = c.JS_DupValue(engine.context, if (s.truthy(try s.get(source, "range"))) try imported(s, imports, "satisfies", &.{ installed, try s.get(source, "range") }) else c.pi_js_bool(engine.context, 1)) }; },
            .npmHasAvailableUpdate, .shouldUpdateNpmSource => {
                if (kind == .npmHasAvailableUpdate and s.truthy(try imported(s, imports, "isOfflineModeEnabled", &.{}))) return .{ .returned = c.pi_js_bool(engine.context, 0) };
                var installed: c.JSValue = undefined;
                if (kind == .shouldUpdateNpmSource) { const path = try s.invoke(manager, "getManagedNpmInstallPath", &.{ arg(args, 0), arg(args, 1) }); installed = if (s.truthy(try imported(s, imports, "existsSync", &.{path}))) try s.invoke(manager, "getInstalledNpmVersion", &.{path}) else c.pi_js_undefined(); } else installed = try s.invoke(manager, "getInstalledNpmVersion", &.{arg(args, 1)});
                if (!s.truthy(installed)) return .{ .returned = c.pi_js_bool(engine.context, @intFromBool(kind == .shouldUpdateNpmSource)) }; try s.put(job, "installed", installed);
                try catching(s, job, if (kind == .shouldUpdateNpmSource) 1 else 2); const latest = try s.get(manager, "getLatestNpmVersion"); const source = arg(args, 0); const spec = if (s.truthy(try s.get(source, "version"))) try s.get(source, "spec") else try s.get(source, "name"); return wait(s, job, 1, try s.call(latest, manager, &.{ spec, try s.get(source, "range") }));
            },
            .getLatestNpmVersion => {
                const command = try s.invoke(manager, "getNpmCommand", &.{}); const run_capture = try s.get(manager, "runCommandCapture"); const name = try s.get(command, "command"); const values = try s.array(); try append(s, values, try s.get(command, "args")); try s.index(values, try v.length(s, values), try s.text("view")); try s.index(values, try v.length(s, values), arg(args, 0)); try s.index(values, try v.length(s, values), try s.text("version")); try s.index(values, try v.length(s, values), try s.text("--json"));
                return wait(s, job, 2, try s.call(run_capture, manager, &.{ name, values, try options(s, try s.get(manager, "cwd")) }));
            },
            .gitHasAvailableUpdate => { if (s.truthy(try imported(s, imports, "isOfflineModeEnabled", &.{}))) return .{ .returned = c.pi_js_bool(engine.context, 0) }; try catching(s, job, 2); return wait(s, job, 3, try capture(s, manager, arg(args, 0), try array(s, &.{ try s.text("rev-parse"), try s.text("HEAD") }))); },
            .getRemoteGitHead => return wait(s, job, 5, try s.invoke(manager, "getGitUpstreamRef", &.{arg(args, 0)})),
            .getGitUpstreamRef => { try catching(s, job, 3); return wait(s, job, 8, try capture(s, manager, arg(args, 0), try array(s, &.{ try s.text("rev-parse"), try s.text("--abbrev-ref"), try s.text("@{upstream}") }))); },
            .getLocalGitUpdateTarget => { try s.put(job, "path", arg(args, 0)); try catching(s, job, 4); return wait(s, job, 10, try capture(s, manager, arg(args, 0), try array(s, &.{ try s.text("rev-parse"), try s.text("--abbrev-ref"), try s.text("@{upstream}") }))); },
        }
    }
    switch (try integer(s, job, "stage")) {
        1 => return .{ .returned = c.JS_DupValue(engine.context, try imported(s, imports, "gt", &.{ input, try s.get(job, "installed") })) },
        2 => {
            const raw = try s.invoke(input, "trim", &.{}); if (!s.truthy(raw)) return v.errorText(s, try s.text("Empty response from npm view")); const parsed = try s.invoke(try s.global("JSON"), "parse", &.{raw}); if (c.JS_IsString(parsed)) return .{ .returned = c.JS_DupValue(engine.context, parsed) };
            if (try v.array(s, parsed)) { const versions = try s.invoke(parsed, "filter", &.{try s.own(try f.createArrow(engine, "", 1, validVersion, &.{}))}); var latest: c.JSValue = undefined;
                if (s.truthy(arg(args, 1))) latest = try imported(s, imports, "maxSatisfying", &.{ versions, arg(args, 1) }) else { const copy = try s.array(); try append(s, copy, versions); const sorted = try s.invoke(copy, "sort", &.{try s.get(imports, "rcompare")}); latest = try v.at(s, sorted, 0); }
                if (s.truthy(latest)) return .{ .returned = c.JS_DupValue(engine.context, latest) };
            }
            return v.errorText(s, try s.text("Unexpected response from npm view"));
        },
        3 => { try s.put(job, "localHead", input); return wait(s, job, 4, try s.invoke(manager, "getRemoteGitHead", &.{arg(args, 0)})); },
        4 => { const local = try s.invoke(try s.get(job, "localHead"), "trim", &.{}); const remote = try s.invoke(input, "trim", &.{}); return .{ .returned = c.pi_js_bool(engine.context, @intFromBool(!s.equal(local, remote))) }; },
        5 => { if (s.truthy(input)) return wait(s, job, 6, try s.invoke(manager, "runGitRemoteCommand", &.{ arg(args, 0), try array(s, &.{ try s.text("ls-remote"), try s.text("origin"), input }) })); return wait(s, job, 7, try s.invoke(manager, "runGitRemoteCommand", &.{ arg(args, 0), try array(s, &.{ try s.text("ls-remote"), try s.text("origin"), try s.text("HEAD") }) })); },
        6 => { const matched = try match(s, input, "^([0-9a-f]{40})\\s+"); if (s.truthy(try firstMatch(s, matched))) return .{ .returned = c.JS_DupValue(engine.context, try v.at(s, matched, 1)) }; return wait(s, job, 7, try s.invoke(manager, "runGitRemoteCommand", &.{ arg(args, 0), try array(s, &.{ try s.text("ls-remote"), try s.text("origin"), try s.text("HEAD") }) })); },
        7 => { const matched = try match(s, input, "^([0-9a-f]{40})\\s+HEAD$"); if (!s.truthy(try firstMatch(s, matched))) return v.errorText(s, try s.text("Failed to determine remote HEAD")); return .{ .returned = c.JS_DupValue(engine.context, try v.at(s, matched, 1)) }; },
        8 => { const trimmed = try s.invoke(input, "trim", &.{}); if (!s.truthy(try s.invoke(trimmed, "startsWith", &.{try s.text("origin/")}))) return .{ .returned = c.pi_js_undefined() }; const branch = try s.invoke(trimmed, "slice", &.{c.JS_NewInt32(engine.context, 7)}); return .{ .returned = c.JS_DupValue(engine.context, if (s.truthy(branch)) try s.concat(try s.text("refs/heads/"), try s.stringify(branch)) else c.pi_js_undefined()) }; },
        10 => { const trimmed = try s.invoke(input, "trim", &.{}); if (!s.truthy(try s.invoke(trimmed, "startsWith", &.{try s.text("origin/")}))) return v.errorText(s, try s.concat(try s.text("Unsupported upstream remote: "), try s.stringify(trimmed))); const branch = try s.invoke(trimmed, "slice", &.{c.JS_NewInt32(engine.context, 7)}); if (!s.truthy(branch)) return v.errorText(s, try s.text("Missing upstream branch name")); try s.put(job, "branch", branch); return wait(s, job, 11, try capture(s, manager, arg(args, 0), try array(s, &.{ try s.text("rev-parse"), try s.text("@{upstream}") }))); },
        11 => return .{ .returned = c.JS_DupValue(engine.context, try target(s, try s.text("@{upstream}"), input, try s.get(job, "branch"), false)) },
        20 => return wait(s, job, 21, try capture(s, manager, arg(args, 0), try array(s, &.{ try s.text("rev-parse"), try s.text("origin/HEAD") }))),
        21 => { try s.put(job, "head", input); const generation = engine.native_allocation_generation; const pending = try capture(s, manager, arg(args, 0), try array(s, &.{ try s.text("symbolic-ref"), try s.text("refs/remotes/origin/HEAD") })); const marker = try s.own(try engine.checked(c.JS_NewBigUint64(engine.context, generation))); const handled = try s.invoke(pending, "catch", &.{try s.own(try f.createArrow(engine, "", 0, empty, &.{marker}))}); return wait(s, job, 22, handled); },
        22 => { const trimmed = try s.invoke(input, "trim", &.{}); const replace = try s.get(trimmed, "replace"); var regex_args = [_]c.JSValue{ try s.text("^refs/remotes/origin/"), try s.text("") }; const regex = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, 2, &regex_args))); const branch = try s.call(replace, trimmed, &.{ regex, try s.text("") }); return .{ .returned = c.JS_DupValue(engine.context, try target(s, try s.text("origin/HEAD"), try s.get(job, "head"), branch, true)) }; },
        else => return error.InvalidPackageVersionStage,
    }
}
fn run(engine: *v.em.Engine, manager: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const job = if (completion == .start) try body.init(&s, state) else state.*; if (completion == .start) try catching(&s, job, 0);
    if (completion == .rejected) return failure(&s, manager, job, input);
    var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine);
    return evaluate(&s, manager, args, roots[0], job, @enumFromInt(raw), completion, input) catch |err| {
        if (err == error.OutOfMemory) return err;
        const mode = try integer(&s, job, "catchMode"); if (mode == 0) return err;
        var boundary: u64 = 0; if (c.JS_ToBigUint64(engine.context, &boundary, try s.get(job, "boundary")) < 0) return v.js.capture(engine);
        // These Source catches have no binding. Retire the unused reason
        // before mode 4 can invoke the real fallback callback.
        try package_catch.ignore(engine, err, boundary);
        return recover(&s, manager, job, mode);
    };
}
