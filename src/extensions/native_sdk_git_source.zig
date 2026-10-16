//! Actual Pi utils/git.ts parser over the separately required concrete hosted
//! projection. Global URL/decoder and String operations remain Source-visible.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const f = @import("native_node_function.zig");
const caught = @import("native_sdk_package_catch.zig");
pub const Inputs = struct { hosted_git_info: c.JSValue };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (!c.JS_IsObject(inputs.hosted_git_info) or !c.JS_IsFunction(engine.context, try s.get(inputs.hosted_git_info, "fromUrl"))) return error.RequiredActualHostedGitInfo;
    const result = try s.object(); try s.put(result, "parseGitUrl", try s.own(try f.create(engine, "parseGitUrl", 1, parse, &.{inputs.hosted_git_info})));
    return c.JS_DupValue(engine.context, result);
}
fn text(s: *Scope, value: []const u8) !c.JSValue { return s.text(value); }
fn starts(s: *Scope, value: c.JSValue, prefix: []const u8) !bool { return s.truthy(try s.invoke(value, "startsWith", &.{try text(s, prefix)})); }
fn includes(s: *Scope, value: c.JSValue, needle: []const u8) !bool { return s.truthy(try s.invoke(value, "includes", &.{try text(s, needle)})); }
fn index(s: *Scope, value: c.JSValue, needle: []const u8) !c.JSValue { return s.invoke(value, "indexOf", &.{try text(s, needle)}); }
fn negative(s: *Scope, value: c.JSValue) !bool { return @import("native_image_arithmetic.zig").compare(s.engine, .less, value, c.JS_NewInt32(s.engine.context, 0)); }
fn increment(s: *Scope, value: c.JSValue) !c.JSValue { return s.own(try s.engine.checked(c.JS_PiIncrement(s.engine.context, value))); }
fn slice(s: *Scope, value: c.JSValue, first: c.JSValue, last: ?c.JSValue) !c.JSValue { return if (last) |end| s.invoke(value, "slice", &.{ first, end }) else s.invoke(value, "slice", &.{first}); }
fn regex(s: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue { var args = [_]c.JSValue{ try text(s, pattern), try text(s, flags) }; return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args))); }
fn replace(s: *Scope, value: c.JSValue, pattern: []const u8, replacement: []const u8) !c.JSValue { const method = try s.get(value, "replace"); return s.call(method, value, &.{ try regex(s, pattern, ""), try text(s, replacement) }); }
fn match(s: *Scope, value: c.JSValue, pattern: []const u8) !c.JSValue { const method = try s.get(value, "match"); return s.call(method, value, &.{try regex(s, pattern, "")}); }
fn orText(s: *Scope, value: c.JSValue) !c.JSValue { return if (v.nullish(value)) text(s, "") else value; }
fn splitResult(s: *Scope, repo: c.JSValue, ref: ?c.JSValue) !c.JSValue { const result = try s.object(); try s.put(result, "repo", repo); if (ref) |value| try s.put(result, "ref", value); return result; }
fn url(s: *Scope, input: c.JSValue) !c.JSValue { var args = [_]c.JSValue{input}; return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, try s.global("URL"), 1, &args))); }
fn urlSplit(s: *Scope, input: c.JSValue) !c.JSValue {
    const parsed = try url(s, input); const path = try replace(s, try s.get(parsed, "pathname"), "^/+", ""); const separator = try index(s, path, "@");
    if (try negative(s, separator)) return splitResult(s, input, null);
    const repo = try slice(s, path, c.JS_NewInt32(s.engine.context, 0), separator); const slice_method = try s.get(path, "slice"); const ref = try s.call(slice_method, path, &.{try increment(s, separator)});
    if (!s.truthy(repo) or !s.truthy(ref)) return splitResult(s, input, null);
    try s.set(parsed, "pathname", try s.concat(try text(s, "/"), try s.stringify(repo)));
    return splitResult(s, try replace(s, try s.invoke(parsed, "toString", &.{}), "/$", ""), ref);
}
fn splitRef(s: *Scope, input: c.JSValue) !c.JSValue {
    const scp = try match(s, input, "^git@([^:]+):(.+)$");
    if (s.truthy(scp)) {
        const path = try orText(s, try v.at(s, scp, 2)); const separator = try index(s, path, "@"); if (try negative(s, separator)) return splitResult(s, input, null);
        const repo = try slice(s, path, c.JS_NewInt32(s.engine.context, 0), separator); const method = try s.get(path, "slice"); const ref = try s.call(method, path, &.{try increment(s, separator)});
        if (!s.truthy(repo) or !s.truthy(ref)) return splitResult(s, input, null);
        const host = try orText(s, try v.at(s, scp, 1)); return splitResult(s, try s.concat(try s.concat(try s.concat(try text(s, "git@"), try s.stringify(host)), try text(s, ":")), try s.stringify(repo)), ref);
    }
    if (try includes(s, input, "://")) { const generation = s.engine.native_allocation_generation; return urlSplit(s, input) catch |err| { try caught.ignore(s.engine, err, generation); return splitResult(s, input, null); }; }
    const slash = try index(s, input, "/"); if (try negative(s, slash)) return splitResult(s, input, null);
    const host = try slice(s, input, c.JS_NewInt32(s.engine.context, 0), slash); const method = try s.get(input, "slice"); const path = try s.call(method, input, &.{try increment(s, slash)}); const separator = try index(s, path, "@"); if (try negative(s, separator)) return splitResult(s, input, null);
    const repo = try slice(s, path, c.JS_NewInt32(s.engine.context, 0), separator); const ref_method = try s.get(path, "slice"); const ref = try s.call(ref_method, path, &.{try increment(s, separator)}); if (!s.truthy(repo) or !s.truthy(ref)) return splitResult(s, input, null);
    return splitResult(s, try s.concat(try s.concat(try s.stringify(host), try text(s, "/")), try s.stringify(repo)), ref);
}
fn decode(s: *Scope, value: c.JSValue) !c.JSValue { return s.call(try s.global("decodeURIComponent"), c.pi_js_undefined(), &.{value}); }
fn unsafeCandidate(s: *Scope, candidate: c.JSValue, slash: bool) !bool {
    if (try includes(s, candidate, "\x00") or try includes(s, candidate, "\\") or try starts(s, candidate, "/")) return true;
    if (!slash and try includes(s, candidate, "/")) return true;
    return s.truthy(try s.invoke(try s.invoke(candidate, "split", &.{try text(s, "/")}), "includes", &.{try text(s, "..")}));
}
fn unsafe(s: *Scope, value: c.JSValue, slash: bool) !bool {
    const generation = s.engine.native_allocation_generation;
    const decoded = decode(s, value) catch |err| { try caught.ignore(s.engine, err, generation); return true; };
    if (c.JS_IsNull(decoded)) return true;
    const candidates = try s.array(); try s.index(candidates, 0, value); try s.index(candidates, 1, decoded); var iterator = try v.iterator(s, candidates); defer iterator.deinit(); errdefer iterator.closePreserving();
    while (try iterator.next()) |item| { const candidate = try s.own(item); if (try unsafeCandidate(s, candidate, slash)) { try iterator.close(); return true; } }
    return false;
}
fn build(s: *Scope, repo: c.JSValue, host: c.JSValue, path: c.JSValue, ref: c.JSValue) !c.JSValue {
    if (try starts(s, path, "/")) return c.pi_js_null();
    const normalized = try replace(s, try replace(s, path, "\\.git$", ""), "^/+", "");
    if (!s.truthy(host) or !s.truthy(normalized)) return c.pi_js_null();
    if (try @import("native_image_arithmetic.zig").compare(s.engine, .less, try s.get(try s.invoke(normalized, "split", &.{try text(s, "/")}), "length"), c.JS_NewInt32(s.engine.context, 2))) return c.pi_js_null();
    if (try unsafe(s, host, false) or try unsafe(s, normalized, true)) return c.pi_js_null();
    const result = try s.object(); try s.put(result, "type", try text(s, "git")); try s.put(result, "repo", repo); try s.put(result, "host", host); try s.put(result, "path", normalized); try s.put(result, "ref", ref); try s.put(result, "pinned", try s.call(try s.global("Boolean"), c.pi_js_undefined(), &.{ref})); return result;
}
fn genericUrl(s: *Scope, repo: c.JSValue) !c.JSValue { const parsed = try url(s, repo); const result = try s.object(); try s.put(result, "host", try s.get(parsed, "hostname")); try s.put(result, "path", try replace(s, try s.get(parsed, "pathname"), "^/+", "")); return result; }
fn generic(s: *Scope, input: c.JSValue) !c.JSValue {
    const split = try splitRef(s, input); const original = try s.get(split, "repo"); const ref = try s.get(split, "ref"); var repo = original; var host = try text(s, ""); var path = try text(s, "");
    const scp = try match(s, original, "^git@([^:]+):(.+)$");
    if (s.truthy(scp)) { host = try orText(s, try v.at(s, scp, 1)); path = try orText(s, try v.at(s, scp, 2)); }
    else if (try starts(s, original, "https://") or try starts(s, original, "http://") or try starts(s, original, "ssh://") or try starts(s, original, "git://")) {
        const generation = s.engine.native_allocation_generation; const parsed = genericUrl(s, original) catch |err| { try caught.ignore(s.engine, err, generation); return c.pi_js_null(); }; host = try s.get(parsed, "host"); path = try s.get(parsed, "path");
    } else {
        const slash = try index(s, original, "/"); if (try negative(s, slash)) return c.pi_js_null(); host = try slice(s, original, c.JS_NewInt32(s.engine.context, 0), slash); const method = try s.get(original, "slice"); path = try s.call(method, original, &.{try increment(s, slash)});
        if (!try includes(s, host, ".") and !try v.eq(s, host, "localhost")) return c.pi_js_null(); repo = try s.concat(try text(s, "https://"), try s.stringify(original));
    }
    return build(s, repo, host, path, ref);
}
fn filterBoolean(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { var s: Scope = .{ .engine = engine }; defer s.deinit(); return c.JS_DupValue(engine.context, try s.call(try s.global("Boolean"), c.pi_js_undefined(), &.{arg(args, 0)})); }
fn hostedResult(s: *Scope, hosted: c.JSValue, split: c.JSValue, input: c.JSValue, https: bool) !?c.JSValue {
    const ref = try s.get(split, "ref"); const split_repo = try s.get(split, "repo");
    const candidates = try s.array(); try s.index(candidates, 0, if (s.truthy(ref)) try s.concat(try s.concat(if (https) try s.concat(try text(s, "https://"), try s.stringify(split_repo)) else try s.stringify(split_repo), try text(s, "#")), try s.stringify(try s.get(split, "ref"))) else c.pi_js_undefined()); try s.index(candidates, 1, if (https) try s.concat(try text(s, "https://"), try s.stringify(input)) else input);
    const filtered = try s.invoke(candidates, "filter", &.{try s.own(try f.createArrow(s.engine, "", 1, filterBoolean, &.{}))}); var iterator = try v.iterator(s, filtered); defer iterator.deinit(); errdefer iterator.closePreserving();
    while (try iterator.next()) |item| {
        const candidate = try s.own(item);
        const info = try s.invoke(hosted, "fromUrl", &.{candidate}); if (!s.truthy(info)) continue;
        if (s.truthy(try s.get(split, "ref"))) { const project = try s.get(info, "project"); if (!v.nullish(project) and try includes(s, project, "@")) continue; }
        var prefix = https;
        if (!https) prefix = !try starts(s, split_repo, "http://") and !try starts(s, split_repo, "https://") and !try starts(s, split_repo, "ssh://") and !try starts(s, split_repo, "git://") and !try starts(s, split_repo, "git@");
        const repo = if (prefix) try s.concat(try text(s, "https://"), try s.stringify(split_repo)) else split_repo;
        const domain = try s.get(info, "domain"); const host = if (s.truthy(domain)) domain else try text(s, "");
        const user = try s.stringify(try s.get(info, "user")); const project = try s.stringify(try s.get(info, "project")); const path = try s.concat(try s.concat(user, try text(s, "/")), project);
        const committish = try s.get(info, "committish"); const split_ref = if (s.truthy(committish)) committish else try s.get(split, "ref");
        const result = try build(s, repo, host, path, if (s.truthy(split_ref)) split_ref else c.pi_js_undefined()); try iterator.close(); return result;
    }
    return null;
}
fn parse(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const trimmed = try s.invoke(arg(args, 0), "trim", &.{}); const prefixed = try starts(&s, trimmed, "git:"); const input = if (prefixed) try s.invoke(try slice(&s, trimmed, c.JS_NewInt32(engine.context, 4), null), "trim", &.{}) else trimmed;
    if (!prefixed and !s.truthy(try s.invoke(try regex(&s, "^(https?|ssh|git)://", "i"), "test", &.{input}))) return c.pi_js_null();
    const split = try splitRef(&s, input); const result = if (try hostedResult(&s, roots[0], split, input, false)) |value| value else if (try hostedResult(&s, roots[0], split, input, true)) |value| value else try generic(&s, input);
    return c.JS_DupValue(engine.context, result);
}
