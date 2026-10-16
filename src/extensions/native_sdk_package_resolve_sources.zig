//! Actual sequential package-source resolver with retained for-of iterator,
//! genuine per-entry async missing callbacks and exact npm/Git await paths.
const data = @import("native_sdk_package_data.zig");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const body = @import("native_async_body.zig");
const af = body.native;
const retained = @import("native_sdk_resource_async_iterator.zig");
const IteratorScope = @import("native_sdk_prompt_scope.zig").Scope;
pub const Inputs = struct { exists_sync: c.JSValue, is_offline: c.JSValue };
pub fn install(engine: *v.em.Engine, prototype: c.JSValue, inputs: Inputs) !void {
    if (!c.JS_IsFunction(engine.context, inputs.exists_sync) or !c.JS_IsFunction(engine.context, inputs.is_offline)) return error.RequiredActualPackageSourcesImport;
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const imports = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()))); try data.put(s.engine, imports, "existsSync", inputs.exists_sync); try data.put(s.engine, imports, "isOfflineModeEnabled", inputs.is_offline);
    const function = try s.own(try af.createResumable(engine, "resolvePackageSources", 3, run, &.{imports})); if (c.JS_DefinePropertyValueStr(engine.context, prototype, "resolvePackageSources", c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return s.call(try s.get(imports, name), c.pi_js_undefined(), args); }
fn exists(s: *Scope, imports: c.JSValue, path: c.JSValue) !bool { return s.truthy(try imported(s, imports, "existsSync", &.{path})); }
fn wait(s: *Scope, job: c.JSValue, stage: i32, pending: c.JSValue) !af.Action { try data.put(s.engine, job, "stage", c.JS_NewInt32(s.engine.context, stage)); return .{ .awaited = c.JS_DupValue(s.engine.context, pending) }; }
fn integer(s: *Scope, job: c.JSValue) !i32 { var result: i32 = 0; if (c.JS_ToInt32(s.engine.context, &result, try s.get(job, "stage")) < 0) return v.js.capture(s.engine); return result; }
fn retainIterator(s: *Scope, job: c.JSValue, values: c.JSValue) !void { var scope: IteratorScope = .{ .engine = s.engine }; defer scope.deinit(); try retained.retain(&scope, job, values); }
fn next(s: *Scope, job: c.JSValue) !?c.JSValue { var scope: IteratorScope = .{ .engine = s.engine }; defer scope.deinit(); return retained.next(&scope, job); }
fn clearEntry(s: *Scope, job: c.JSValue) !void { inline for (.{ "pkg", "scope", "source", "resolvedSource", "resolvedScope", "parsed", "filter", "metadata", "missing", "path", "npm" }) |field| try v.remove(s, job, field); }
fn installParsed(s: *Scope, manager: c.JSValue, roots: []const c.JSValue) !c.JSValue { return s.invoke(manager, "installParsedSource", &.{ roots[1], roots[2] }); }
fn missing(engine: *v.em.Engine, manager: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return .{ .thrown = c.JS_DupValue(engine.context, input) }; var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .start) {
        if (s.truthy(try imported(&s, roots[0], "isOfflineModeEnabled", &.{}))) return .{ .returned = c.pi_js_bool(engine.context, 0) };
        const job = try body.init(&s, state); if (!s.truthy(roots[4])) return wait(&s, job, 20, try installParsed(&s, manager, roots)); return wait(&s, job, 21, try s.call(roots[4], c.pi_js_undefined(), &.{roots[3]}));
    }
    if (try integer(&s, state.*) == 20) return .{ .returned = c.pi_js_bool(engine.context, 1) };
    if (try v.eq(&s, input, "skip")) return .{ .returned = c.pi_js_bool(engine.context, 0) };
    if (try v.eq(&s, input, "error")) { const error_constructor = try s.global("Error"); const message = try s.concat(try s.text("Missing source: "), try s.stringify(roots[3])); var args = [_]c.JSValue{message}; return .{ .thrown = try engine.checked(c.JS_CallConstructor(engine.context, error_constructor, 1, &args)) }; }
    return wait(&s, state.*, 20, try installParsed(&s, manager, roots));
}
fn startMissing(s: *Scope, job: c.JSValue) !af.Action { return wait(s, job, 3, try s.call(try s.get(job, "missing"), c.pi_js_undefined(), &.{})); }
fn collect(s: *Scope, manager: c.JSValue, args: []const c.JSValue, job: c.JSValue) !void {
    const metadata = try s.get(job, "metadata"); const path = try s.get(job, "path"); try s.set(metadata, "baseDir", path); try s.set(metadata, "packageRoot", path);
    _ = try s.invoke(manager, "collectPackageResources", &.{ path, arg(args, 1), try s.get(job, "filter"), metadata });
}
fn loop(s: *Scope, manager: c.JSValue, args: []const c.JSValue, imports: c.JSValue, job: c.JSValue) !af.Action {
    while (true) {
        try clearEntry(s, job); const current = (try next(s, job)) orelse return .{ .returned = c.pi_js_undefined() }; const entry = try s.own(current); const pkg = try s.get(entry, "pkg"); const scope = try s.get(entry, "scope");
        const source = if (c.JS_IsString(pkg)) pkg else try s.get(pkg, "source"); const is_object = c.JS_IsNull(pkg) or (c.JS_IsObject(pkg) and !c.JS_IsFunction(s.engine.context, pkg)); const filter = if (is_object) pkg else c.pi_js_undefined();
        const delta = try s.invoke(manager, "findAutoloadDeltaBase", &.{ pkg, scope, arg(args, 0) }); const delta_source = try v.optional(s, delta, "source"); const resolved_source = if (v.nullish(delta_source)) source else delta_source; const delta_scope = try v.optional(s, delta, "scope"); const resolved_scope = if (v.nullish(delta_scope)) scope else delta_scope;
        const parsed = try s.invoke(manager, "parseSource", &.{resolved_source}); const metadata = try s.object(); try data.put(s.engine, metadata, "source", source); try data.put(s.engine, metadata, "scope", scope); try data.put(s.engine, metadata, "origin", try s.text("package"));
        if (try v.eq(s, try s.get(parsed, "type"), "local")) { const base = try s.invoke(manager, "getBaseDirForScope", &.{resolved_scope}); _ = try s.invoke(manager, "resolveLocalExtensionSource", &.{ parsed, arg(args, 1), filter, metadata, base }); continue; }
        inline for (.{ .{ "parsed", parsed }, .{ "resolvedSource", resolved_source }, .{ "resolvedScope", resolved_scope }, .{ "filter", filter }, .{ "metadata", metadata } }) |field| try data.put(s.engine, job, field[0], field[1]);
        const install_missing = try s.own(try af.createResumableArrow(s.engine, "installMissing", 0, missing, &.{ imports, parsed, resolved_scope, resolved_source, arg(args, 2) }, manager)); try data.put(s.engine, job, "missing", install_missing);
        if (try v.eq(s, try s.get(parsed, "type"), "npm")) {
            try data.put(s.engine, job, "npm", c.pi_js_bool(s.engine.context, 1)); const path = try s.invoke(manager, "getNpmInstallPath", &.{ parsed, resolved_scope }); try data.put(s.engine, job, "path", path);
            if (!try exists(s, imports, path)) return startMissing(s, job);
            return wait(s, job, 2, try s.invoke(manager, "installedNpmMatchesConfiguredVersion", &.{ parsed, path }));
        }
        if (try v.eq(s, try s.get(parsed, "type"), "git")) {
            try data.put(s.engine, job, "npm", c.pi_js_bool(s.engine.context, 0)); const path = try s.invoke(manager, "getGitInstallPath", &.{ parsed, resolved_scope }); try data.put(s.engine, job, "path", path);
            if (!try exists(s, imports, path)) return startMissing(s, job);
            if (try v.eq(s, resolved_scope, "temporary") and !s.truthy(try s.get(parsed, "pinned")) and !s.truthy(try imported(s, imports, "isOfflineModeEnabled", &.{}))) return wait(s, job, 4, try s.invoke(manager, "refreshTemporaryGitSource", &.{ parsed, resolved_source }));
            try collect(s, manager, args, job);
        }
    }
}
fn evaluate(s: *Scope, manager: c.JSValue, args: []const c.JSValue, imports: c.JSValue, job: c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) { try retainIterator(s, job, arg(args, 0)); return loop(s, manager, args, imports, job); }
    switch (try integer(s, job)) {
        2 => { if (!s.truthy(input)) return startMissing(s, job); try collect(s, manager, args, job); },
        3 => { if (s.truthy(input)) { if (s.truthy(try s.get(job, "npm"))) { const path = try s.invoke(manager, "getNpmInstallPath", &.{ try s.get(job, "parsed"), try s.get(job, "resolvedScope") }); try data.put(s.engine, job, "path", path); } try collect(s, manager, args, job); } },
        4 => try collect(s, manager, args, job),
        else => return error.InvalidPackageSourcesStage,
    }
    return loop(s, manager, args, imports, job);
}
fn run(engine: *v.em.Engine, manager: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const job = if (completion == .start) try body.init(&s, state) else state.*;
    if (completion == .rejected) { retained.closePreserving(engine, job); return .{ .thrown = c.JS_DupValue(engine.context, input) }; }
    return evaluate(&s, manager, args, roots[0], job, completion, input) catch |err| { retained.closePreserving(engine, job); return err; };
}
