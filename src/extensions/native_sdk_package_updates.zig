//! Actual configured update batching/checking and Source-created async tasks.
//! Real runWithConcurrency, npm/Git methods and Promise.all retain Source's
//! ordering and failfast behavior; no command result or update is fabricated.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const body = @import("native_async_body.zig");
const af = body.native;
const f = @import("native_node_function.zig");
pub const Inputs = struct { is_offline: c.JSValue, exists_sync: c.JSValue };
pub const methods = .{ "update", "updateConfiguredSources", "updateNpmBatch", "checkForAvailableUpdates" };
const Method = enum(i32) { update, updateConfiguredSources, updateNpmBatch, checkForAvailableUpdates };
const Task = enum(i32) { npm_check, git_update, git_operation, npm_batch, available };
const Callback = enum(i32) { npm_task, git_task, available_task, non_temporary, defined, spec, noop };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn private(s: *Scope) !c.JSValue { return s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, c.pi_js_null()))); }
pub fn install(engine: *v.em.Engine, prototype: c.JSValue, inputs: Inputs) !void {
    if (!c.JS_IsFunction(engine.context, inputs.is_offline) or !c.JS_IsFunction(engine.context, inputs.exists_sync)) return error.RequiredActualPackageUpdateImport;
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const imports = try private(&s); try s.put(imports, "isOfflineModeEnabled", inputs.is_offline); try s.put(imports, "existsSync", inputs.exists_sync);
    inline for (@typeInfo(Method).@"enum".fields) |field| { const value = try s.own(try af.createResumable(engine, field.name, if (field.value == @intFromEnum(Method.checkForAvailableUpdates)) 0 else if (field.value == @intFromEnum(Method.updateNpmBatch)) 2 else 1, run, &.{ imports, c.JS_NewInt32(engine.context, field.value) })); if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, value), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine); }
}
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return s.call(try s.get(imports, name), c.pi_js_undefined(), args); }
fn packages(s: *Scope, settings: c.JSValue) !c.JSValue { const values = try s.get(settings, "packages"); return if (v.nullish(values)) s.array() else values; }
fn appendSpread(s: *Scope, target: c.JSValue, values: c.JSValue) !void { var iterator = try v.iterator(s, values); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |value| { defer s.engine.freeValue(value); try s.index(target, try v.length(s, target), value); } }
fn wait(s: *Scope, job: c.JSValue, stage: i32, pending: c.JSValue) !af.Action { try s.put(job, "stage", c.JS_NewInt32(s.engine.context, stage)); return .{ .awaited = c.JS_DupValue(s.engine.context, pending) }; }
fn integer(s: *Scope, object: c.JSValue, key: [*:0]const u8) !i32 { var value: i32 = 0; if (c.JS_ToInt32(s.engine.context, &value, try s.get(object, key)) < 0) return v.js.capture(s.engine); return value; }
fn callback(s: *Scope, kind: Callback, manager: c.JSValue, imports: c.JSValue) !c.JSValue { return s.own(try f.createArrow(s.engine, "", if (kind == .noop) 0 else 1, mapped, &.{ manager, imports, c.JS_NewInt32(s.engine.context, @intFromEnum(kind)) })); }
fn makeTask(s: *Scope, manager: c.JSValue, imports: c.JSValue, kind: Task, entry: c.JSValue) !c.JSValue { return s.own(try af.createResumableArrow(s.engine, "", 0, task, &.{ imports, entry, c.JS_NewInt32(s.engine.context, @intFromEnum(kind)) }, manager)); }
fn mapped(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[2]) < 0) return v.js.capture(engine); const entry = arg(args, 0);
    const result = switch (@as(Callback, @enumFromInt(raw))) {
        .npm_task => try makeTask(&s, roots[0], roots[1], .npm_check, entry), .git_task => try makeTask(&s, roots[0], roots[1], .git_update, entry), .available_task => try makeTask(&s, roots[0], roots[1], .available, entry),
        .non_temporary => c.pi_js_bool(engine.context, @intFromBool(!try v.eq(&s, try s.get(entry, "scope"), "temporary"))), .defined => c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(entry))), .noop => c.pi_js_undefined(),
        .spec => if (s.truthy(try s.get(try s.get(entry, "parsed"), "version"))) try s.get(try s.get(entry, "parsed"), "spec") else try s.concat(try s.stringify(try s.get(try s.get(entry, "parsed"), "name")), try s.text("@latest")),
    }; return c.JS_DupValue(engine.context, result);
}
fn updateRecord(s: *Scope, source: c.JSValue, parsed: c.JSValue, scope: c.JSValue, npm: bool) !c.JSValue { const result = try s.object(); try s.put(result, "source", source); const display = if (npm) try s.get(parsed, "name") else blk: { const host = try s.stringify(try s.get(parsed, "host")); break :blk try s.concat(try s.concat(host, try s.text("/")), try s.stringify(try s.get(parsed, "path"))); }; try s.put(result, "displayName", display); try s.put(result, "type", try s.text(if (npm) "npm" else "git")); try s.put(result, "scope", scope); return result; }
fn task(engine: *v.em.Engine, manager: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return .{ .thrown = c.JS_DupValue(engine.context, input) }; var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[2]) < 0) return v.js.capture(engine); const kind: Task = @enumFromInt(raw); const entry = roots[1]; const imports = roots[0];
    if (completion == .fulfilled) {
        if (kind == .npm_check) { const value = try s.object(); try s.put(value, "entry", entry); try s.put(value, "shouldUpdate", input); return .{ .returned = c.JS_DupValue(engine.context, value) }; }
        if (kind == .available) { if (!s.truthy(input)) return .{ .returned = c.pi_js_undefined() }; return .{ .returned = c.JS_DupValue(engine.context, try updateRecord(&s, try s.get(state.*, "source"), try s.get(state.*, "parsed"), try s.get(entry, "scope"), s.truthy(try s.get(state.*, "npm")))) }; }
        return .{ .returned = c.pi_js_undefined() };
    }
    switch (kind) {
        .npm_check => { const check = try s.get(manager, "shouldUpdateNpmSource"); return .{ .awaited = c.JS_DupValue(engine.context, try s.call(check, manager, &.{ try s.get(entry, "parsed"), try s.get(entry, "scope") })) }; },
        .git_operation => { const update = try s.get(manager, "updateGit"); return .{ .awaited = c.JS_DupValue(engine.context, try s.call(update, manager, &.{ try s.get(entry, "parsed"), try s.get(entry, "scope") })) }; },
        .npm_batch => { const install_batch = try s.get(manager, "installNpmBatch"); return .{ .awaited = c.JS_DupValue(engine.context, try s.call(install_batch, manager, &.{ try s.get(entry, "specs"), try s.get(entry, "scope") })) }; },
        .git_update => { const with_progress = try s.get(manager, "withProgress"); const source = try s.get(entry, "source"); const message = try s.concat(try s.concat(try s.text("Updating "), try s.stringify(try s.get(entry, "source"))), try s.text("...")); const operation = try makeTask(&s, manager, imports, .git_operation, entry); return .{ .awaited = c.JS_DupValue(engine.context, try s.call(with_progress, manager, &.{ try s.text("update"), source, message, operation })) }; },
        .available => {
            const source = if (c.JS_IsString(try s.get(entry, "pkg"))) try s.get(entry, "pkg") else try s.get(try s.get(entry, "pkg"), "source"); const parsed = try s.invoke(manager, "parseSource", &.{source});
            if (try v.eq(&s, try s.get(parsed, "type"), "local") or s.truthy(try s.get(parsed, "pinned"))) return .{ .returned = c.pi_js_undefined() };
            const job = try body.init(&s, state); try s.put(job, "source", source); try s.put(job, "parsed", parsed); const npm = try v.eq(&s, try s.get(parsed, "type"), "npm"); try s.put(job, "npm", c.pi_js_bool(engine.context, @intFromBool(npm)));
            const get_path = try s.get(manager, if (npm) "getNpmInstallPath" else "getGitInstallPath"); const path = try s.call(get_path, manager, &.{ parsed, try s.get(entry, "scope") }); if (!s.truthy(try imported(&s, imports, "existsSync", &.{path}))) return .{ .returned = c.pi_js_undefined() };
            return .{ .awaited = c.JS_DupValue(engine.context, if (npm) try s.invoke(manager, "npmHasAvailableUpdate", &.{ parsed, path }) else try s.invoke(manager, "gitHasAvailableUpdate", &.{path})) };
        },
    }
}
fn collect(s: *Scope, manager: c.JSValue, values: c.JSValue, settings: c.JSValue, scope: []const u8, identity: ?c.JSValue, matched: ?*bool) !void {
    var iterator = try v.iterator(s, try packages(s, settings)); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |pkg| {
        defer s.engine.freeValue(pkg); const source = if (c.JS_IsString(pkg)) pkg else try s.get(pkg, "source");
        if (identity) |key| if (s.truthy(key) and !s.equal(try s.invoke(manager, "getPackageIdentity", &.{ source, try s.text(scope) }), key)) continue;
        if (matched) |flag| flag.* = true; const row = try s.object(); if (identity != null) try s.put(row, "source", source) else try s.put(row, "pkg", pkg); try s.put(row, "scope", try s.text(scope)); try v.js.push(s.engine, values, row);
    }
}
fn evaluate(s: *Scope, manager: c.JSValue, imports: c.JSValue, args: []const c.JSValue, job: c.JSValue, kind: Method, completion: af.Completion, input: c.JSValue) !af.Action {
    const engine = s.engine;
    if (completion == .start) switch (kind) {
        .update => {
            const global = try s.invoke(try s.get(manager, "settingsManager"), "getGlobalSettings", &.{}); const project = try s.invoke(try s.get(manager, "settingsManager"), "getProjectSettings", &.{}); const source = arg(args, 0); const identity = if (s.truthy(source)) try s.invoke(manager, "getPackageIdentity", &.{source}) else c.pi_js_undefined();
            var matched = false; const values = try s.array(); try collect(s, manager, values, global, "user", identity, &matched); try collect(s, manager, values, project, "project", identity, &matched);
            if (s.truthy(source) and !matched) { const error_constructor = try s.global("Error"); const message_function = try s.get(manager, "buildNoMatchingPackageMessage"); const configured = try s.array(); try appendSpread(s, configured, try packages(s, global)); try appendSpread(s, configured, try packages(s, project)); const message = try s.call(message_function, manager, &.{ source, configured }); var constructor_args = [_]c.JSValue{message}; const reason = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, error_constructor, 1, &constructor_args))); return .{ .thrown = c.JS_DupValue(engine.context, reason) }; }
            return wait(s, job, 1, try s.invoke(manager, "updateConfiguredSources", &.{values}));
        },
        .updateConfiguredSources => {
            if (s.truthy(try imported(s, imports, "isOfflineModeEnabled", &.{})) or s.equal(try s.get(arg(args, 0), "length"), c.JS_NewInt32(engine.context, 0))) return .{ .returned = c.pi_js_undefined() };
            const npm = try s.array(); const git = try s.array(); var iterator = try v.iterator(s, arg(args, 0)); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |entry| {
                defer engine.freeValue(entry); const parse = try s.get(manager, "parseSource"); const parsed = try s.call(parse, manager, &.{try s.get(entry, "source")}); if (try v.eq(s, try s.get(parsed, "type"), "npm")) { if (!s.truthy(try s.get(parsed, "pinned"))) { const row = try v.spread(s, entry); try s.put(row, "parsed", parsed); try v.js.push(engine, npm, row); } } else if (try v.eq(s, try s.get(parsed, "type"), "git")) { const row = try v.spread(s, entry); try s.put(row, "parsed", parsed); try v.js.push(engine, git, row); }
            }
            try s.put(job, "git", git); const checks = try s.invoke(npm, "map", &.{try callback(s, .npm_task, manager, imports)}); return wait(s, job, 2, try s.invoke(manager, "runWithConcurrency", &.{ checks, c.JS_NewInt32(engine.context, 4) }));
        },
        .updateNpmBatch => {
            const values = arg(args, 0); const scope = arg(args, 1); if (s.equal(try s.get(values, "length"), c.JS_NewInt32(engine.context, 0))) return .{ .returned = c.pi_js_undefined() };
            const label = if (s.equal(try s.get(values, "length"), c.JS_NewInt32(engine.context, 1))) try s.get(try v.at(s, values, 0), "source") else try s.concat(try s.stringify(scope), try s.text(" npm packages"));
            const message = if (s.equal(try s.get(values, "length"), c.JS_NewInt32(engine.context, 1))) try s.concat(try s.concat(try s.text("Updating "), try s.stringify(try s.get(try v.at(s, values, 0), "source"))), try s.text("...")) else try s.concat(try s.concat(try s.text("Updating "), try s.stringify(scope)), try s.text(" npm packages..."));
            const specs = try s.invoke(values, "map", &.{try callback(s, .spec, manager, imports)}); const entry = try private(s); try s.put(entry, "specs", specs); try s.put(entry, "scope", scope); const operation = try makeTask(s, manager, imports, .npm_batch, entry); return wait(s, job, 1, try s.invoke(manager, "withProgress", &.{ try s.text("update"), label, message, operation }));
        },
        .checkForAvailableUpdates => {
            if (s.truthy(try imported(s, imports, "isOfflineModeEnabled", &.{}))) return .{ .returned = c.JS_DupValue(engine.context, try s.array()) };
            const global = try s.invoke(try s.get(manager, "settingsManager"), "getGlobalSettings", &.{}); const project = try s.invoke(try s.get(manager, "settingsManager"), "getProjectSettings", &.{}); const values = try s.array(); try collect(s, manager, values, project, "project", null, null); try collect(s, manager, values, global, "user", null, null);
            const packages_value = try s.invoke(manager, "dedupePackages", &.{values}); const installed = try s.invoke(packages_value, "filter", &.{try callback(s, .non_temporary, manager, imports)}); const checks = try s.invoke(installed, "map", &.{try callback(s, .available_task, manager, imports)}); return wait(s, job, 3, try s.invoke(manager, "runWithConcurrency", &.{ checks, c.JS_NewInt32(engine.context, 4) }));
        },
    };
    switch (try integer(s, job, "stage")) {
        1 => return .{ .returned = c.pi_js_undefined() },
        3 => return .{ .returned = c.JS_DupValue(engine.context, try s.invoke(input, "filter", &.{try callback(s, .defined, manager, imports)})) },
        2 => {
            const user = try s.array(); const project = try s.array(); var iterator = try v.iterator(s, input); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |result| { defer engine.freeValue(result); if (!s.truthy(try s.get(result, "shouldUpdate"))) continue; if (try v.eq(s, try s.get(try s.get(result, "entry"), "scope"), "user")) try v.js.push(engine, user, try s.get(result, "entry")) else try v.js.push(engine, project, try s.get(result, "entry")); }
            const tasks = try s.array(); if (try v.length(s, user) > 0) { const push = try s.get(tasks, "push"); _ = try s.call(push, tasks, &.{try s.invoke(manager, "updateNpmBatch", &.{ user, try s.text("user") })}); } if (try v.length(s, project) > 0) { const push = try s.get(tasks, "push"); _ = try s.call(push, tasks, &.{try s.invoke(manager, "updateNpmBatch", &.{ project, try s.text("project") })}); }
            const git = try s.get(job, "git"); if (try v.length(s, git) > 0) { const work = try s.invoke(git, "map", &.{try callback(s, .git_task, manager, imports)}); const push = try s.get(tasks, "push"); const pending = try s.invoke(manager, "runWithConcurrency", &.{ work, c.JS_NewInt32(engine.context, 4) }); const handled = try s.invoke(pending, "then", &.{try callback(s, .noop, manager, imports)}); _ = try s.call(push, tasks, &.{handled}); }
            const all = try s.invoke(try s.global("Promise"), "all", &.{tasks}); return wait(s, job, 1, all);
        },
        else => return error.InvalidPackageUpdateStage,
    }
}
fn run(engine: *v.em.Engine, manager: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return .{ .thrown = c.JS_DupValue(engine.context, input) }; var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine); const job = if (completion == .start) try body.init(&s, state) else state.*; return evaluate(&s, manager, roots[0], args, job, @enumFromInt(raw), completion, input);
}
