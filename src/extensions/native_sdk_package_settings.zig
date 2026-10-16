//! Actual source/settings matching, listing and progress methods. Parsing,
//! paths, SettingsManager and installed-file checks remain live real imports.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const f = @import("native_node_function.zig");
const body = @import("native_async_body.zig");
const af = body.native;
pub const Inputs = struct { exists_sync: c.JSValue, relative: c.JSValue };
pub const methods = .{ "addSourceToSettings", "removeSourceFromSettings", "getInstalledPath", "listConfiguredPackages", "getSourceMatchKeyForInput", "getSourceMatchKeyForSettings", "packageSourcesMatch", "normalizePackageSourceForSettings", "buildNoMatchingPackageMessage", "findSuggestedConfiguredSource", "emitProgress", "withProgress" };
const Method = enum(i32) { addSourceToSettings, removeSourceFromSettings, getInstalledPath, listConfiguredPackages, getSourceMatchKeyForInput, getSourceMatchKeyForSettings, packageSourcesMatch, normalizePackageSourceForSettings, buildNoMatchingPackageMessage, findSuggestedConfiguredSource, emitProgress };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn install(engine: *v.em.Engine, prototype: c.JSValue, inputs: Inputs) !void {
    if (!c.JS_IsFunction(engine.context, inputs.exists_sync) or !c.JS_IsFunction(engine.context, inputs.relative)) return error.RequiredActualPackageSettingsImports;
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const imports = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try s.put(imports, "existsSync", inputs.exists_sync); try s.put(imports, "relative", inputs.relative);
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) { .listConfiguredPackages => 0, .getSourceMatchKeyForInput, .emitProgress => 1, .packageSourcesMatch => 3, else => 2 };
        const value = try s.own(try f.createMethod(engine, field.name, length, method, &.{ imports, c.JS_NewInt32(engine.context, field.value) }));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, value), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
    }
    const progress = try s.own(try af.createResumable(engine, "withProgress", 4, withProgress, &.{}));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "withProgress", c.JS_DupValue(engine.context, progress), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
}
fn append(s: *Scope, array: c.JSValue, values: c.JSValue) !void {
    var iterator = try v.iterator(s, values); defer iterator.deinit(); errdefer iterator.closePreserving();
    while (try iterator.next()) |value| { defer s.engine.freeValue(value); try s.index(array, try v.length(s, array), value); }
}
fn packages(s: *Scope, settings: c.JSValue) !c.JSValue {
    const value = try s.get(settings, "packages"); return if (v.nullish(value)) s.array() else value;
}
fn selectedScope(s: *Scope, options: c.JSValue) !c.JSValue { return s.text(if (s.truthy(try v.optional(s, options, "local"))) "project" else "user"); }
fn settingsFor(s: *Scope, manager: c.JSValue, scope: c.JSValue) !c.JSValue { return s.invoke(try s.get(manager, "settingsManager"), if (try v.eq(s, scope, "project")) "getProjectSettings" else "getGlobalSettings", &.{}); }
fn save(s: *Scope, manager: c.JSValue, scope: c.JSValue, values: c.JSValue) !void { _ = try s.invoke(try s.get(manager, "settingsManager"), if (try v.eq(s, scope, "project")) "setProjectPackages" else "setPackages", &.{values}); }
fn matches(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return v.js.invoke(engine, roots[0], "packageSourcesMatch", &.{ arg(args, 0), roots[1], roots[2] });
}
fn doesNotMatch(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const value = try matches(engine, c.pi_js_undefined(), args, roots); defer engine.freeValue(value);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_ToBool(engine.context, value) == 0));
}
fn mutate(s: *Scope, manager: c.JSValue, source: c.JSValue, options: c.JSValue, adding: bool) !c.JSValue {
    const scope = try selectedScope(s, options); const current = try packages(s, try settingsFor(s, manager, scope));
    if (!adding) {
        const callback = try s.own(try f.createArrow(s.engine, "", 1, doesNotMatch, &.{ manager, source, scope }));
        const next = try s.invoke(current, "filter", &.{callback});
        if (s.equal(try s.get(next, "length"), try s.get(current, "length"))) return c.pi_js_bool(s.engine.context, 0);
        try save(s, manager, scope, next); return c.pi_js_bool(s.engine.context, 1);
    }
    const normalized = try s.invoke(manager, "normalizePackageSourceForSettings", &.{ source, scope });
    const callback = try s.own(try f.createArrow(s.engine, "", 1, matches, &.{ manager, source, scope }));
    const index = try s.invoke(current, "findIndex", &.{callback});
    var next: c.JSValue = undefined;
    if (!s.equal(index, c.JS_NewInt32(s.engine.context, -1))) {
        const existing = try s.own(try v.js.getKey(s.engine, current, index));
        if (s.equal(try s.invoke(manager, "getPackageSourceString", &.{existing}), normalized)) return c.pi_js_bool(s.engine.context, 0);
        next = try s.array();
        try append(s, next, current);
        var replacement = normalized;
        if (!c.JS_IsString(existing)) { replacement = try v.spread(s, existing); try s.put(replacement, "source", normalized); }
        try v.js.setKey(s.engine, next, index, replacement);
    } else { next = try s.array(); try append(s, next, current); try s.index(next, try v.length(s, next), normalized); }
    try save(s, manager, scope, next); return c.pi_js_bool(s.engine.context, 1);
}
fn key(s: *Scope, manager: c.JSValue, source: c.JSValue, scope: c.JSValue, settings: bool) !c.JSValue {
    const parsed = try s.invoke(manager, "parseSource", &.{source});
    if (try v.eq(s, try s.get(parsed, "type"), "npm")) return s.concat(try s.text("npm:"), try s.stringify(try s.get(parsed, "name")));
    if (try v.eq(s, try s.get(parsed, "type"), "git")) {
        const start = try s.concat(try s.text("git:"), try s.stringify(try s.get(parsed, "host")));
        return s.concat(try s.concat(start, try s.text("/")), try s.stringify(try s.get(parsed, "path")));
    }
    const resolved = if (settings) blk: {
        const base = try s.invoke(manager, "getBaseDirForScope", &.{scope});
        const resolve = try s.get(manager, "resolvePathFromBase");
        break :blk try s.call(resolve, manager, &.{ try s.get(parsed, "path"), base });
    } else blk: {
        const resolve = try s.get(manager, "resolvePath");
        break :blk try s.call(resolve, manager, &.{try s.get(parsed, "path")});
    };
    return s.concat(try s.text("local:"), try s.stringify(resolved));
}
fn installed(s: *Scope, manager: c.JSValue, source: c.JSValue, scope: c.JSValue, imports: c.JSValue) !c.JSValue {
    const parsed = try s.invoke(manager, "parseSource", &.{source}); var path = c.pi_js_undefined();
    if (try v.eq(s, try s.get(parsed, "type"), "npm")) path = try s.invoke(manager, "getNpmInstallPath", &.{ parsed, scope }) else if (try v.eq(s, try s.get(parsed, "type"), "git")) path = try s.invoke(manager, "getGitInstallPath", &.{ parsed, scope }) else if (try v.eq(s, try s.get(parsed, "type"), "local")) {
        const base = try s.invoke(manager, "getBaseDirForScope", &.{scope}); const resolve = try s.get(manager, "resolvePathFromBase"); path = try s.call(resolve, manager, &.{ try s.get(parsed, "path"), base });
    } else return c.pi_js_undefined();
    return if (s.truthy(try s.call(try s.get(imports, "existsSync"), c.pi_js_undefined(), &.{path}))) path else c.pi_js_undefined();
}
fn list(s: *Scope, manager: c.JSValue) !c.JSValue {
    const global = try s.invoke(try s.get(manager, "settingsManager"), "getGlobalSettings", &.{});
    const project = try s.invoke(try s.get(manager, "settingsManager"), "getProjectSettings", &.{});
    const result = try s.array();
    inline for (.{ .{ global, "user" }, .{ project, "project" } }) |entry| {
        var iterator = try v.iterator(s, try packages(s, entry[0])); defer iterator.deinit(); errdefer iterator.closePreserving();
        while (try iterator.next()) |pkg| {
            defer s.engine.freeValue(pkg); const source = if (c.JS_IsString(pkg)) pkg else try s.get(pkg, "source"); const row = try s.object();
            try s.put(row, "source", source); try s.put(row, "scope", try s.text(entry[1]));
            try s.put(row, "filtered", c.pi_js_bool(s.engine.context, @intFromBool(c.JS_IsNull(pkg) or (c.JS_IsObject(pkg) and !c.JS_IsFunction(s.engine.context, pkg)))));
            try s.put(row, "installedPath", try s.invoke(manager, "getInstalledPath", &.{ source, try s.text(entry[1]) }));
            // Source uses configuredPackages.push, so preserve its live lookup.
            try v.js.push(s.engine, result, row);
        }
    }
    return result;
}
fn suggestion(s: *Scope, manager: c.JSValue, source: c.JSValue, configured: c.JSValue) !c.JSValue {
    const trimmed = try s.invoke(source, "trim", &.{}); const suggestions = try s.own(try v.js.builtin(s.engine, "Set", &.{}));
    var iterator = try v.iterator(s, configured); defer iterator.deinit(); errdefer iterator.closePreserving();
    while (try iterator.next()) |pkg| {
        defer s.engine.freeValue(pkg); const text = try s.invoke(manager, "getPackageSourceString", &.{pkg}); const parsed = try s.invoke(manager, "parseSource", &.{text});
        if (try v.eq(s, try s.get(parsed, "type"), "npm")) { if (s.equal(trimmed, try s.get(parsed, "name")) or s.equal(trimmed, try s.get(parsed, "spec"))) _ = try s.invoke(suggestions, "add", &.{text}); continue; }
        if (try v.eq(s, try s.get(parsed, "type"), "git")) {
            const host = try s.stringify(try s.get(parsed, "host")); const shorthand = try s.concat(try s.concat(host, try s.text("/")), try s.stringify(try s.get(parsed, "path")));
            const ref = if (s.truthy(try s.get(parsed, "ref"))) try s.concat(try s.concat(shorthand, try s.text("@")), try s.stringify(try s.get(parsed, "ref"))) else c.pi_js_undefined();
            if (s.equal(trimmed, shorthand) or (s.truthy(ref) and s.equal(trimmed, ref))) _ = try s.invoke(suggestions, "add", &.{text});
        }
    }
    return s.get(try s.invoke(try s.invoke(suggestions, "values", &.{}), "next", &.{}), "value");
}
fn emit(s: *Scope, manager: c.JSValue, event: c.JSValue) !void { const callback = try s.get(manager, "progressCallback"); if (!v.nullish(callback)) _ = try s.call(callback, manager, &.{event}); }
fn method(engine: *v.em.Engine, manager: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine);
    const first = arg(args, 0); const second = arg(args, 1);
    const result = switch (@as(Method, @enumFromInt(raw))) {
        .addSourceToSettings => try mutate(&s, manager, first, second, true), .removeSourceFromSettings => try mutate(&s, manager, first, second, false),
        .getInstalledPath => try installed(&s, manager, first, second, roots[0]), .listConfiguredPackages => try list(&s, manager),
        .getSourceMatchKeyForInput => try key(&s, manager, first, c.pi_js_undefined(), false), .getSourceMatchKeyForSettings => try key(&s, manager, first, second, true),
        .packageSourcesMatch => blk: { const get_left = try s.get(manager, "getSourceMatchKeyForSettings"); const source = try s.invoke(manager, "getPackageSourceString", &.{first}); const left = try s.call(get_left, manager, &.{ source, arg(args, 2) }); const right = try s.invoke(manager, "getSourceMatchKeyForInput", &.{second}); break :blk c.pi_js_bool(engine.context, @intFromBool(s.equal(left, right))); },
        .normalizePackageSourceForSettings => blk: { const parsed = try s.invoke(manager, "parseSource", &.{first}); if (!try v.eq(&s, try s.get(parsed, "type"), "local")) break :blk first; const base = try s.invoke(manager, "getBaseDirForScope", &.{second}); const resolve = try s.get(manager, "resolvePath"); const resolved = try s.call(resolve, manager, &.{try s.get(parsed, "path")}); const rel = try s.call(try s.get(roots[0], "relative"), c.pi_js_undefined(), &.{ base, resolved }); break :blk if (s.truthy(rel)) rel else try s.text("."); },
        .findSuggestedConfiguredSource => try suggestion(&s, manager, first, second),
        .buildNoMatchingPackageMessage => blk: { const suggested = try s.invoke(manager, "findSuggestedConfiguredSource", &.{ first, second }); const prefix = try s.concat(try s.text("No matching package found for "), try s.stringify(first)); break :blk if (!s.truthy(suggested)) prefix else try s.concat(try s.concat(prefix, try s.text(". Did you mean ")), try s.concat(try s.stringify(suggested), try s.text("?"))); },
        .emitProgress => blk: { try emit(&s, manager, first); break :blk c.pi_js_undefined(); },
    }; return c.JS_DupValue(engine.context, result);
}
fn event(s: *Scope, kind: []const u8, action: c.JSValue, source: c.JSValue, message: ?c.JSValue) !c.JSValue {
    const value = try s.object(); try s.put(value, "type", try s.text(kind)); try s.put(value, "action", action); try s.put(value, "source", source); if (message) |text| try s.put(value, "message", text); return value;
}
fn progressError(s: *Scope, manager: c.JSValue, args: []const c.JSValue, reason: c.JSValue) !af.Action {
    const instance = c.JS_IsInstanceOf(s.engine.context, reason, try s.global("Error")); if (instance < 0) return v.js.capture(s.engine);
    const message = if (instance != 0) try s.get(reason, "message") else try s.call(try s.global("String"), c.pi_js_undefined(), &.{reason});
    try emitEvent(s, manager, "error", arg(args, 0), arg(args, 1), message);
    return .{ .thrown = c.JS_DupValue(s.engine.context, reason) };
}
fn emitEvent(s: *Scope, manager: c.JSValue, kind: []const u8, action: c.JSValue, source: c.JSValue, message: ?c.JSValue) !void {
    const emit_progress = try s.get(manager, "emitProgress");
    _ = try s.call(emit_progress, manager, &.{try event(s, kind, action, source, message)});
}
fn trustedBoundary(engine: *v.em.Engine, err: anyerror, generation: u64) !void {
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| try body.rethrowRecognizedAllocation(engine, reason, generation);
}
fn withProgress(engine: *v.em.Engine, manager: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .start) {
        try emitEvent(&s, manager, "start", arg(args, 0), arg(args, 1), arg(args, 2));
        const job = try body.init(&s, state); const generation = engine.native_allocation_generation;
        try s.put(job, "generation", try s.own(try engine.checked(c.JS_NewBigUint64(engine.context, generation))));
        const pending = s.call(arg(args, 3), c.pi_js_undefined(), &.{}) catch |err| { try trustedBoundary(engine, err, generation); const failure = engine.nativeAllocationError(err, generation); if (failure == error.OutOfMemory) return failure; const reason = try s.own(@import("native_agent_async.zig").reason(engine, failure)); return progressError(&s, manager, args, reason); };
        return .{ .awaited = c.JS_DupValue(engine.context, pending) };
    }
    var boundary: u64 = 0; if (c.JS_ToBigUint64(engine.context, &boundary, try s.get(state.*, "generation")) < 0) return v.js.capture(engine);
    if (completion == .rejected) { try body.rethrowRecognizedAllocation(engine, input, boundary); return progressError(&s, manager, args, input); }
    const complete_generation = engine.native_allocation_generation;
    emitEvent(&s, manager, "complete", arg(args, 0), arg(args, 1), null) catch |err| { try trustedBoundary(engine, err, complete_generation); const failure = engine.nativeAllocationError(err, complete_generation); if (failure == error.OutOfMemory) return failure; const reason = try s.own(@import("native_agent_async.zig").reason(engine, failure)); return progressError(&s, manager, args, reason); };
    return .{ .returned = c.pi_js_undefined() };
}
