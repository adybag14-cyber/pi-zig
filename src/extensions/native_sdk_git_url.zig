//! Actual Pi utils/git.ts parseGitUrl, with the private consumed hosted9 policy.
//! Namespace input is the genuine node:url value, not a URL-shaped collaborator.
const v = @import("native_ai_provider_values.zig");
const x = @import("native_sdk_git_url_values.zig");
const hosted = @import("native_sdk_hosted_git_info.zig");
const f = @import("native_node_function.zig");
const c = v.c;
fn arg(args: []const c.JSValue, i: usize) c.JSValue { return if (i < args.len) args[i] else c.pi_js_undefined(); }
pub fn create(engine: *v.em.Engine, actual_node_url_namespace: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: v.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    const result = createScoped(engine, actual_node_url_namespace) catch |err| {
        const failed = @import("native_sdk.zig").fail(engine, err);
        return engine.checked(engine.leaveNativeInvocation(&invocation, failed));
    };
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn createScoped(engine: *v.em.Engine, actual: c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, createBody(&o, actual));
}
fn createBody(o: *x.Ops, actual: c.JSValue) !c.JSValue {
    const engine = o.s.engine;
    const owner = try hosted.create(o, actual);
    const function = try o.own(try f.create(engine, "parseGitUrl", 1, parse, &.{owner}));
    const namespace = try o.object(); try o.put(namespace, "parseGitUrl", function);
    return c.JS_DupValue(engine.context, namespace);
}
fn parse(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const prior = engine.captured_exception; engine.captured_exception = null;
    var s: v.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    const result = x.owned.finishValue(&s, x.duplicate(engine, parseBody(&o, roots[0], arg(args, 0)))) catch |err| {
        var failure = x.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        if (prior) |reason| failure.release(reason);
        _ = failure.finishValue() catch |outcome| {
            if (outcome == error.JavaScriptException and !c.JS_HasException(engine.context)) if (engine.captured_exception) |reason| {
                engine.captured_exception = null; _ = c.JS_Throw(engine.context, reason);
            };
            return outcome;
        };
        unreachable;
    };
    engine.captured_exception = prior;
    return result;
}
fn repoRecord(o: *x.Ops, repo: c.JSValue, ref: ?c.JSValue) !c.JSValue {
    const result = try o.object(); try o.put(result, "repo", repo); if (ref) |value| try o.put(result, "ref", value); return result;
}
fn splitRef(parent: *x.Ops, url: c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = parent.s.engine }; var o: x.Ops = .{ .s = &s };
    return parent.own(try x.owned.finishValue(&s, x.duplicate(s.engine, splitRefBody(&o, url))));
}
fn splitRefBody(o: *x.Ops, url: c.JSValue) !c.JSValue {
    const matched = try o.match(url, "^git@([^:]+):(.+)$");
    if (o.truthy(matched)) {
        const second = try o.at(matched, 2); const path = if (x.nullish(second)) try o.text("") else second;
        const separator = try o.invoke(path, "indexOf", &.{try o.text("@")});
        if (try o.compare(4, separator, o.number(0))) return repoRecord(o, url, null);
        const repo = try o.invoke(path, "slice", &.{ o.number(0), separator });
        const ref = try o.sliceAfter(path, separator);
        if (!o.truthy(repo) or !o.truthy(ref)) return repoRecord(o, url, null);
        const first = try o.at(matched, 1);
        return repoRecord(o, try o.template(&.{ try o.text("git@"), if (x.nullish(first)) try o.text("") else first, try o.text(":"), repo }), ref);
    }
    if (o.truthy(try o.invoke(url, "includes", &.{try o.text("://")}))) return splitProtocol(o, url) catch |err| { try x.swallow(o.s.engine, err); return repoRecord(o, url, null); };
    const slash = try o.invoke(url, "indexOf", &.{try o.text("/")});
    if (try o.compare(4, slash, o.number(0))) return repoRecord(o, url, null);
    const host = try o.invoke(url, "slice", &.{ o.number(0), slash });
    const path = try o.sliceAfter(url, slash);
    const separator = try o.invoke(path, "indexOf", &.{try o.text("@")});
    if (try o.compare(4, separator, o.number(0))) return repoRecord(o, url, null);
    const repo = try o.invoke(path, "slice", &.{ o.number(0), separator });
    const ref = try o.sliceAfter(path, separator);
    if (!o.truthy(repo) or !o.truthy(ref)) return repoRecord(o, url, null);
    return repoRecord(o, try o.template(&.{ host, try o.text("/"), repo }), ref);
}
fn splitProtocol(o: *x.Ops, url: c.JSValue) !c.JSValue {
    const parsed = try o.construct(try o.global("URL"), &.{url});
    const path = try o.replace(try o.get(parsed, "pathname"), "^/+", "", "");
    const separator = try o.invoke(path, "indexOf", &.{try o.text("@")});
    if (try o.compare(4, separator, o.number(0))) return repoRecord(o, url, null);
    const repo = try o.invoke(path, "slice", &.{ o.number(0), separator });
    const ref = try o.sliceAfter(path, separator);
    if (!o.truthy(repo) or !o.truthy(ref)) return repoRecord(o, url, null);
    try o.set(parsed, "pathname", try o.template(&.{ try o.text("/"), repo }));
    const result = try o.replace(try o.invoke(parsed, "toString", &.{}), "/$", "", "");
    return repoRecord(o, result, ref);
}
fn decodeValidation(o: *x.Ops, value: c.JSValue) !c.JSValue {
    return o.decode(value) catch |err| { try x.swallow(o.s.engine, err); return c.pi_js_null(); };
}
fn unsafePart(parent: *x.Ops, value: c.JSValue, allow_slash: bool) !bool {
    var s: v.Scope = .{ .engine = parent.s.engine }; var o: x.Ops = .{ .s = &s };
    return x.finishNative(&s, unsafePartBody(&o, value, allow_slash));
}
fn unsafePartBody(o: *x.Ops, value: c.JSValue, allow_slash: bool) !bool {
    const s = o.s;
    const decoded = try decodeValidation(o, value); if (c.JS_IsNull(decoded)) return true;
    const candidates = try o.array(); try o.index(candidates, 0, value); try o.index(candidates, 1, decoded);
    var iterator = try x.initIterator(s, candidates);
    return x.retireNative(s.engine, &iterator, unsafeLoop(o, &iterator, allow_slash));
}
fn unsafeLoop(o: *x.Ops, iterator: *v.js.Iterator, allow_slash: bool) !bool {
    const s = o.s;
    while (true) {
        const next = x.iterators.advance(s.engine, iterator) catch |err| return x.iterators.closeAbrupt(s.engine, iterator, x.current(s.engine, err), s.engine.native_allocation_generation);
        const raw = next orelse return false;
        const candidate = o.own(raw) catch |err| return x.iterators.closeAbrupt(s.engine, iterator, err, s.engine.native_allocation_generation);
        const unsafe = unsafeCandidate(o, candidate, allow_slash) catch |err| return x.iterators.closeAbrupt(s.engine, iterator, err, s.engine.native_allocation_generation);
        if (unsafe) { try x.iterators.closeNormal(o.s.engine, iterator); return true; }
    }
}
fn unsafeCandidate(o: *x.Ops, candidate: c.JSValue, allow_slash: bool) !bool {
    if (o.truthy(try o.invoke(candidate, "includes", &.{try o.text("\x00")})) or o.truthy(try o.invoke(candidate, "includes", &.{try o.text("\\")})) or o.truthy(try o.invoke(candidate, "startsWith", &.{try o.text("/")}))) return true;
    if (!allow_slash and o.truthy(try o.invoke(candidate, "includes", &.{try o.text("/")}))) return true;
    return o.truthy(try o.invoke(try o.invoke(candidate, "split", &.{try o.text("/")}), "includes", &.{try o.text("..")}));
}
fn build(parent: *x.Ops, args: c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = parent.s.engine }; var o: x.Ops = .{ .s = &s };
    return parent.own(try x.owned.finishValue(&s, buildBody(&o, args)));
}
fn buildBody(o: *x.Ops, args: c.JSValue) !c.JSValue {
    if (o.truthy(try o.invoke(try o.get(args, "path"), "startsWith", &.{try o.text("/")}))) return c.pi_js_null();
    const normalized = try o.replace(try o.replace(try o.get(args, "path"), "\\.git$", "", ""), "^/+", "", "");
    if (!o.truthy(try o.get(args, "host")) or !o.truthy(normalized) or try o.compare(4, try o.get(try o.invoke(normalized, "split", &.{try o.text("/")}), "length"), o.number(2))) return c.pi_js_null();
    if (try unsafePart(o, try o.get(args, "host"), false) or try unsafePart(o, normalized, true)) return c.pi_js_null();
    const result = try o.object(); try o.put(result, "type", try o.text("git")); try o.put(result, "repo", try o.get(args, "repo")); try o.put(result, "host", try o.get(args, "host")); try o.put(result, "path", normalized); try o.put(result, "ref", try o.get(args, "ref"));
    const boolean = try o.global("Boolean"); try o.put(result, "pinned", try o.call(boolean, c.pi_js_undefined(), &.{try o.get(args, "ref")}));
    return c.JS_DupValue(o.s.engine.context, result);
}
fn generic(parent: *x.Ops, url: c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = parent.s.engine }; var o: x.Ops = .{ .s = &s };
    return parent.own(try x.owned.finishValue(&s, genericBody(&o, url)));
}
fn genericBody(o: *x.Ops, url: c.JSValue) !c.JSValue {
    const split = try splitRef(o, url); const repo_without_ref = try o.get(split, "repo"); const ref = try o.get(split, "ref");
    var repo = repo_without_ref; var host = try o.text(""); var path = try o.text("");
    const matched = try o.match(repo_without_ref, "^git@([^:]+):(.+)$");
    if (o.truthy(matched)) {
        const first = try o.at(matched, 1); host = if (x.nullish(first)) try o.text("") else first;
        const second = try o.at(matched, 2); path = if (x.nullish(second)) try o.text("") else second;
    } else if (o.truthy(try o.invoke(repo_without_ref, "startsWith", &.{try o.text("https://")})) or o.truthy(try o.invoke(repo_without_ref, "startsWith", &.{try o.text("http://")})) or o.truthy(try o.invoke(repo_without_ref, "startsWith", &.{try o.text("ssh://")})) or o.truthy(try o.invoke(repo_without_ref, "startsWith", &.{try o.text("git://")}))) {
        const parsed = genericProtocol(o, repo_without_ref) catch |err| { try x.swallow(o.s.engine, err); return c.pi_js_null(); };
        host = try o.get(parsed, "host"); path = try o.get(parsed, "path");
    } else {
        const slash = try o.invoke(repo_without_ref, "indexOf", &.{try o.text("/")}); if (try o.compare(4, slash, o.number(0))) return c.pi_js_null();
        host = try o.invoke(repo_without_ref, "slice", &.{ o.number(0), slash }); path = try o.sliceAfter(repo_without_ref, slash);
        if (!o.truthy(try o.invoke(host, "includes", &.{try o.text(".")})) and !try o.equal(host, "localhost")) return c.pi_js_null();
        repo = try o.template(&.{ try o.text("https://"), repo_without_ref });
    }
    const args = try o.object(); try o.put(args, "repo", repo); try o.put(args, "host", host); try o.put(args, "path", path); try o.put(args, "ref", ref);
    return c.JS_DupValue(o.s.engine.context, try build(o, args));
}
fn genericProtocol(o: *x.Ops, repo: c.JSValue) !c.JSValue {
    const parsed = try o.construct(try o.global("URL"), &.{repo}); const host = try o.get(parsed, "hostname");
    const path = try o.replace(try o.get(parsed, "pathname"), "^/+", "", "");
    const result = try o.object(); try o.put(result, "host", host); try o.put(result, "path", path); return result;
}
fn filterTruthy(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, x.duplicate(engine, filterBody(&o, args)));
}
fn filterBody(o: *x.Ops, args: []const c.JSValue) !c.JSValue {
    return o.call(try o.global("Boolean"), c.pi_js_undefined(), &.{arg(args, 0)});
}
fn filtered(o: *x.Ops, candidates: c.JSValue) !c.JSValue {
    const method = try o.get(candidates, "filter");
    const callback = try o.own(try f.createArrow(o.s.engine, "", 1, filterTruthy, &.{}));
    return o.call(method, candidates, &.{callback});
}
fn hostedResult(o: *x.Ops, split: c.JSValue, info: c.JSValue, https: bool) !c.JSValue {
    const result = try o.object();
    var repo: c.JSValue = undefined;
    if (https) { repo = try o.text("https://"); try o.append(&repo, try o.get(split, "repo")); } else repo = try o.get(split, "repo");
    try o.put(result, "repo", repo);
    const domain = try o.get(info, "domain"); try o.put(result, "host", if (o.truthy(domain)) domain else try o.text(""));
    var path = try o.text(""); try o.append(&path, try o.get(info, "user")); try o.append(&path, try o.text("/")); try o.append(&path, try o.get(info, "project")); try o.put(result, "path", path);
    const committish = try o.get(info, "committish");
    const ref = if (o.truthy(committish)) committish else blk: { const value = try o.get(split, "ref"); break :blk if (o.truthy(value)) value else c.pi_js_undefined(); };
    try o.put(result, "ref", ref); return build(o, result);
}
fn candidatesLoop(o: *x.Ops, owner: c.JSValue, split: c.JSValue, candidates: c.JSValue, force_https: bool) !?c.JSValue {
    var iterator = try x.initIterator(o.s, candidates);
    return x.retireNative(o.s.engine, &iterator, candidatesBody(o, owner, split, &iterator, force_https));
}
fn candidatesBody(o: *x.Ops, owner: c.JSValue, split: c.JSValue, iterator: *v.js.Iterator, force_https: bool) !?c.JSValue {
    while (true) {
        const next = x.iterators.advance(o.s.engine, iterator) catch |err| return x.iterators.closeAbrupt(o.s.engine, iterator, x.current(o.s.engine, err), o.s.engine.native_allocation_generation);
        const raw = next orelse return null;
        const candidate = o.own(raw) catch |err| return x.iterators.closeAbrupt(o.s.engine, iterator, err, o.s.engine.native_allocation_generation);
        const result = tryCandidate(o, owner, split, candidate, force_https) catch |err| return x.iterators.closeAbrupt(o.s.engine, iterator, err, o.s.engine.native_allocation_generation);
        if (result) |value| { try x.iterators.closeNormal(o.s.engine, iterator); return value; }
    }
}
fn tryCandidate(o: *x.Ops, owner: c.JSValue, split: c.JSValue, candidate: c.JSValue, force_https: bool) !?c.JSValue {
    const info = try hosted.fromUrl(o, owner, candidate); if (!o.truthy(info)) return null;
    if (o.truthy(try o.get(split, "ref"))) {
        const project = try o.get(info, "project"); if (!x.nullish(project) and o.truthy(try o.invoke(project, "includes", &.{try o.text("@")}))) return null;
    }
    var https = force_https;
    if (!force_https) https = !o.truthy(try o.invoke(try o.get(split, "repo"), "startsWith", &.{try o.text("http://")})) and !o.truthy(try o.invoke(try o.get(split, "repo"), "startsWith", &.{try o.text("https://")})) and !o.truthy(try o.invoke(try o.get(split, "repo"), "startsWith", &.{try o.text("ssh://")})) and !o.truthy(try o.invoke(try o.get(split, "repo"), "startsWith", &.{try o.text("git://")})) and !o.truthy(try o.invoke(try o.get(split, "repo"), "startsWith", &.{try o.text("git@")}));
    // A hosted match returns buildGitSource's null too; it does not continue.
    return @as(?c.JSValue, try hostedResult(o, split, info, https));
}
fn parseBody(o: *x.Ops, owner: c.JSValue, source: c.JSValue) !c.JSValue {
    const trim = try o.get(source, "trim");
    if (!c.JS_IsFunction(o.s.engine.context, trim)) return v.js.typeError(o.s.engine, "source.trim is not a function");
    const trimmed = try o.call(trim, source, &.{});
    const has_prefix = o.truthy(try o.invoke(trimmed, "startsWith", &.{try o.text("git:")}));
    const url = if (has_prefix) try o.invoke(try o.invoke(trimmed, "slice", &.{o.number(4)}), "trim", &.{}) else trimmed;
    if (!has_prefix and !try o.test("^(https?|ssh|git)://", "i", url)) return c.pi_js_null();
    const split = try splitRef(o, url);
    const hosted_candidates = try o.array();
    var first = c.pi_js_undefined();
    if (o.truthy(try o.get(split, "ref"))) { first = try o.text(""); try o.append(&first, try o.get(split, "repo")); try o.append(&first, try o.text("#")); try o.append(&first, try o.get(split, "ref")); }
    try o.index(hosted_candidates, 0, first); try o.index(hosted_candidates, 1, url);
    if (try candidatesLoop(o, owner, split, try filtered(o, hosted_candidates), false)) |result| return result;
    const https_candidates = try o.array(); first = c.pi_js_undefined();
    if (o.truthy(try o.get(split, "ref"))) { first = try o.text("https://"); try o.append(&first, try o.get(split, "repo")); try o.append(&first, try o.text("#")); try o.append(&first, try o.get(split, "ref")); }
    try o.index(https_candidates, 0, first); try o.index(https_candidates, 1, try o.template(&.{ try o.text("https://"), url }));
    if (try candidatesLoop(o, owner, split, try filtered(o, https_candidates), true)) |result| return result;
    return generic(o, url);
}
