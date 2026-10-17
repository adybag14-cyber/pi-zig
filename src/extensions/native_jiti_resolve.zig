//! Actual jiti 2.7 resolve.ts control flow. No SourceLoader alias or Node bridge.
//! Derived from jiti, Copyright Pooya Parsa, MIT; retained primary/LICENSE.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const body = @import("native_async_body.zig");
pub const Inputs = struct {
    pathe_resolve_alias: c.JSValue,
    mlly_file_url_to_path: c.JSValue,
    mlly_resolve_path_sync: c.JSValue,
    pathe_join: c.JSValue,
    pathe_dirname: c.JSValue,
    is_dir: c.JSValue,
    /// The two module-scoped actual RegExp literals, shared by every call.
    js_ext_re: c.JSValue,
    ts_ext_re: c.JSValue,
};
pub const Constants = struct { js_ext_re: c.JSValue, ts_ext_re: c.JSValue };
pub fn createConstants(engine: *v.em.Engine) !Constants {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const js = try regex(&s, "\\.(c|m)?j(sx?)$");
    const ts = try regex(&s, "\\.(c|m)?t(sx?)$");
    return .{ .js_ext_re = c.JS_DupValue(engine.context, js), .ts_ext_re = c.JS_DupValue(engine.context, ts) };
}
/// The genuine ordinary exported declaration, length 3, with traced captures.
/// No loader/global registration or collaborator substitution is performed.
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    return @import("native_node_module_callable.zig").create(engine, "jitiResolve", 3, true, exported, &.{ inputs.pathe_resolve_alias, inputs.mlly_file_url_to_path, inputs.mlly_resolve_path_sync, inputs.pathe_join, inputs.pathe_dirname, inputs.is_dir, inputs.js_ext_re, inputs.ts_ext_re });
}
fn exported(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const inputs: Inputs = .{ .pathe_resolve_alias = roots[0], .mlly_file_url_to_path = roots[1], .mlly_resolve_path_sync = roots[2], .pathe_join = roots[3], .pathe_dirname = roots[4], .is_dir = roots[5], .js_ext_re = roots[6], .ts_ext_re = roots[7] };
    return resolve(engine, inputs, arg(args, 0), arg(args, 1), arg(args, 2));
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
/// Borrowed actual ctx/id/options and real dependency bindings; owned result.
/// The dependency owner supplies genuine mlly/pathe policy, never an identity
/// function or Engine.normalizeRequire relabelled as conditional resolution.
pub fn resolve(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, id: c.JSValue, options: c.JSValue) anyerror!c.JSValue {
    const generation = engine.native_allocation_generation;
    return resolveInner(engine, inputs, context, id, options) catch |err| return exactFailure(engine, err, generation);
}
fn resolveInner(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, original_id: c.JSValue, options: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    var id = original_id;
    var resolved = c.pi_js_undefined();
    var last_error = c.pi_js_undefined(); defer engine.freeValue(last_error);
    if (s.truthy(try s.invoke(try s.get(context, "isNativeRe"), "test", &.{id}))) return c.JS_DupValue(engine.context, id);
    if (s.truthy(try s.get(context, "resolveTsConfigPaths")) and !s.truthy(try s.get(options, "skipTsConfigPaths"))) {
        const candidates = try s.invoke(context, "resolveTsConfigPaths", &.{id});
        var iterator = try v.iterator(&s, candidates); defer iterator.deinit();
        while (try iterator.next()) |candidate| {
            defer engine.freeValue(candidate);
            const generation = engine.native_allocation_generation;
            const found = resolveCandidate(engine, inputs, context, candidate, options) catch |err| return closeAbrupt(engine, &iterator, err, generation);
            if (s.truthy(found)) {
                errdefer engine.freeValue(found);
                try iterator.close();
                return found;
            }
            engine.freeValue(found);
        }
    }
    if (s.truthy(try s.get(context, "alias"))) id = try s.call(inputs.pathe_resolve_alias, c.pi_js_undefined(), &.{ id, try s.get(context, "alias") });
    const option_parent = try v.optional(&s, options, "parentURL");
    var parent = if (s.truthy(option_parent)) option_parent else try s.get(context, "url");
    if (s.truthy(try s.call(inputs.is_dir, c.pi_js_undefined(), &.{parent}))) parent = try s.call(inputs.pathe_join, c.pi_js_undefined(), &.{ parent, try s.text("_index.js") });
    // Keep the actual literal/filter(Boolean)/for-of operations observable.
    const sets = try s.array();
    const asynchronous = s.truthy(try v.optional(&s, options, "async"));
    try s.index(sets, 0, try v.optional(&s, options, "conditions"));
    try s.index(sets, 1, try conditionPair(&s, if (asynchronous) "import" else "require"));
    try s.index(sets, 2, try conditionPair(&s, if (asynchronous) "require" else "import"));
    const filter = try s.get(sets, "filter");
    const filtered = try s.call(filter, sets, &.{try s.global("Boolean")});
    var conditions = try v.iterator(&s, filtered); defer conditions.deinit();
    while (try conditions.next()) |set| {
        defer engine.freeValue(set);
        const generation = engine.native_allocation_generation;
        const result = resolveCondition(engine, inputs, context, id, parent, set) catch |err| {
            const reason = takeCaught(engine, err, generation) catch |fatal| return closeAbrupt(engine, &conditions, fatal, generation);
            engine.freeValue(last_error); last_error = reason;
            // A failed assignment leaves the previous resolved value intact.
            if (s.truthy(resolved)) { try conditions.close(); return c.JS_DupValue(engine.context, resolved); }
            continue;
        };
        resolved = try s.own(result);
        if (s.truthy(resolved)) { try conditions.close(); return c.JS_DupValue(engine.context, resolved); }
    }
    const direct_generation = engine.native_allocation_generation;
    if (nativeDirect(engine, context, id, options)) |value| return value else |err| {
        const reason = try takeCaught(engine, err, direct_generation);
        engine.freeValue(last_error); last_error = reason;
    }
    var extensions = try v.iterator(&s, try s.get(context, "additionalExts")); defer extensions.deinit();
    while (try extensions.next()) |ext| {
        defer engine.freeValue(ext);
        const generation = engine.native_allocation_generation;
        const result = resolveExtension(engine, inputs, context, id, ext, parent, options) catch |err| return closeAbrupt(engine, &extensions, err, generation);
        if (s.truthy(result)) { errdefer engine.freeValue(result); try extensions.close(); return result; }
        engine.freeValue(result);
    }
    if (s.truthy(try v.optional(&s, options, "try"))) return c.pi_js_undefined();
    return throwReason(engine, last_error);
}
fn conditionPair(s: *Scope, mode: []const u8) !c.JSValue {
    const pair = try s.array(); try s.index(pair, 0, try s.text("node")); try s.index(pair, 1, try s.text(mode)); return pair;
}
fn resolveCandidate(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, candidate: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const nested = try s.own(try v.js.spread(engine, options));
    try s.put(nested, "try", c.pi_js_bool(engine.context, 1));
    try s.put(nested, "skipTsConfigPaths", c.pi_js_bool(engine.context, 1));
    return resolve(engine, inputs, context, candidate, nested);
}
fn resolveCondition(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, id: c.JSValue, parent: c.JSValue, conditions: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const options = try s.object();
    try s.put(options, "url", parent);
    try s.put(options, "conditions", conditions);
    try s.put(options, "extensions", try s.get(try s.get(context, "opts"), "extensions"));
    return v.js.call(engine, inputs.mlly_resolve_path_sync, c.pi_js_undefined(), &.{ id, options });
}
fn nativeDirect(engine: *v.em.Engine, context: c.JSValue, id: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const require = try s.get(context, "nativeRequire");
    const method = try s.get(require, "resolve");
    const opts = try s.object(); try s.put(opts, "paths", try s.get(options, "paths"));
    return v.js.call(engine, method, require, &.{ id, opts });
}
fn regex(s: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try s.text(pattern)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, 1, &args)));
}
fn resolveExtension(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, id: c.JSValue, ext: c.JSValue, parent: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const first = try s.own(try tryNative(engine, inputs, context, try s.concat(id, ext), parent, options));
    const result = if (s.truthy(first)) first else try s.own(try tryNative(engine, inputs, context, try s.concat(try s.concat(id, try s.text("/index")), ext), parent, options));
    if (s.truthy(result)) return c.JS_DupValue(engine.context, result);
    const ts = inputs.ts_ext_re;
    const js = inputs.js_ext_re;
    const first_test = try s.get(ts, "test");
    const from_ts = s.truthy(try s.call(first_test, ts, &.{try s.get(context, "filename")}));
    if (from_ts or parent_ts: {
        const second_test = try s.get(ts, "test");
        const module = try s.get(context, "parentModule");
        const name = if (v.nullish(module)) c.pi_js_undefined() else try s.get(module, "filename");
        break :parent_ts s.truthy(try s.call(second_test, ts, &.{if (s.truthy(name)) name else try s.text("")}));
    } or s.truthy(try s.invoke(js, "test", &.{id}))) {
        const replaced = try s.invoke(id, "replace", &.{ js, try s.text(".$1t$2") });
        return tryNative(engine, inputs, context, replaced, parent, options);
    }
    return c.pi_js_undefined();
}
fn nativeFallback(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, id: c.JSValue, parent: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const require = try s.get(context, "nativeRequire");
    const method = try s.get(require, "resolve");
    const opts = try s.own(try v.js.spread(engine, options));
    const paths = try s.array();
    const directory = try s.call(inputs.pathe_dirname, c.pi_js_undefined(), &.{try s.call(inputs.mlly_file_url_to_path, c.pi_js_undefined(), &.{parent})});
    try s.index(paths, 0, directory);
    const requested = try v.optional(&s, options, "paths");
    const tail = if (s.truthy(requested)) requested else try s.array();
    // Array spread uses the real iterator; no coercion to a string list.
    var iterator = try v.iterator(&s, tail); defer iterator.deinit();
    var index: u32 = 1;
    while (try iterator.next()) |item| {
        defer engine.freeValue(item);
        const generation = engine.native_allocation_generation;
        s.index(paths, index, item) catch |err| return closeAbrupt(engine, &iterator, err, generation);
        index = @addWithOverflow(index, 1)[0];
    }
    try s.put(opts, "paths", paths);
    return v.js.call(engine, method, require, &.{ id, opts });
}
fn tryNative(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, id: c.JSValue, parent: c.JSValue, options: c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    return nativeFallback(engine, inputs, context, id, parent, options) catch |err| {
        const reason = try takeCaught(engine, err, generation); engine.freeValue(reason);
        return c.pi_js_undefined();
    };
}
/// Catch only ordinary guest failures. Fresh private allocation tags escape as
/// the exact reason; direct native failures never become catchable JS errors.
pub fn takeCaught(engine: *v.em.Engine, err: anyerror, generation: u64) !c.JSValue {
    if (err != error.JavaScriptException) return err;
    const reason = engine.captured_exception orelse return error.MissingActualJitiCapturedReason;
    if (c.JS_IsUncatchableError(reason)) return err;
    try body.rethrowRecognizedAllocation(engine, reason, generation);
    engine.captured_exception = null;
    return reason;
}
pub fn exactFailure(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        if (c.JS_IsUncatchableError(reason)) return err;
        body.rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| return fatal;
    };
    return err;
}
pub fn throwReason(engine: *v.em.Engine, reason: c.JSValue) anyerror {
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))) catch |err| return err;
    unreachable;
}
fn closeAbrupt(engine: *v.em.Engine, iterator: *v.js.Iterator, err: anyerror, generation: u64) anyerror {
    // Trusted fatal is never consumed to execute guest iterator cleanup.
    const reason = takeCaught(engine, err, generation) catch |fatal| return fatal;
    defer engine.freeValue(reason);
    const close_generation = engine.native_allocation_generation;
    iterator.close() catch |close_err| {
        const discarded = takeCaught(engine, close_err, close_generation) catch |fatal| return fatal;
        engine.freeValue(discarded);
    };
    return throwReason(engine, reason);
}
