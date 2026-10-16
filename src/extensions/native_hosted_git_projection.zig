//! Bounded hosted-git-info 9.0.3 fromUrl projection used by Pi parseGitUrl.
//! This namespace does not expose or claim the wider GitHost/template API.
//! Cache roots are private VM values; successful entries use max-1000 LRU,
//! while lru-cache 11.4.0 set(undefined) removes rather than negative-caches.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const f = @import("native_node_function.zig");
const caught = @import("native_sdk_package_catch.zig");
pub const Inputs = struct { node_url: c.JSValue };
const Host = enum { github, bitbucket, gitlab, gist, sourcehut };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const constructor = try s.get(inputs.node_url, "URL"); if (!c.JS_IsFunction(engine.context, constructor)) return error.RequiredActualNodeUrlConstructor;
    const entries = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()))); const cache = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try s.put(cache, "entries", entries); try s.put(cache, "size", c.JS_NewInt32(engine.context, 0));
    const result = try s.object(); try s.put(result, "fromUrl", try s.own(try f.createMethod(engine, "fromUrl", 2, fromUrl, &.{ inputs.node_url, cache })));
    return c.JS_DupValue(engine.context, result);
}
pub fn starts(s: *Scope, value: c.JSValue, prefix: []const u8) !bool { return s.truthy(try s.invoke(value, "startsWith", &.{try s.text(prefix)})); }
pub fn ends(s: *Scope, value: c.JSValue, suffix: []const u8) !bool { return s.truthy(try s.invoke(value, "endsWith", &.{try s.text(suffix)})); }
pub fn includes(s: *Scope, value: c.JSValue, needle: []const u8) !bool { return s.truthy(try s.invoke(value, "includes", &.{try s.text(needle)})); }
pub fn cmp(s: *Scope, comptime operation: @import("native_image_arithmetic.zig").Operation, first: c.JSValue, second: c.JSValue) !bool { return @import("native_image_arithmetic.zig").compare(s.engine, operation, first, second); }
pub fn index(s: *Scope, value: c.JSValue, needle: []const u8) !c.JSValue { return s.invoke(value, "indexOf", &.{try s.text(needle)}); }
pub fn offset(s: *Scope, value: c.JSValue, amount: i32) !c.JSValue { return s.own(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 0, value, c.JS_NewInt32(s.engine.context, amount)))); }
pub fn slice(s: *Scope, value: c.JSValue, first: c.JSValue, last: ?c.JSValue) !c.JSValue { return if (last) |end| s.invoke(value, "slice", &.{ first, end }) else s.invoke(value, "slice", &.{first}); }
fn regex(s: *Scope, pattern: []const u8) !c.JSValue { var args = [_]c.JSValue{ try s.text(pattern), try s.text("") }; return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, 2, &args))); }
fn array(s: *Scope, values: []const []const u8) !c.JSValue { const result = try s.array(); for (values, 0..) |value, i| try s.index(result, @intCast(i), try s.text(value)); return result; }
pub fn shorthand(s: *Scope, input: c.JSValue) !bool {
    const hash = try index(s, input, "#"); const slash = try index(s, input, "/"); const second_method = try s.get(input, "indexOf"); const second = try s.call(second_method, input, &.{ try s.text("/"), try offset(s, slash, 1) }); const colon = try index(s, input, ":");
    const space = try s.invoke(try regex(s, "\\s"), "exec", &.{input}); const at = try index(s, input, "@"); const minus = c.JS_NewInt32(s.engine.context, -1); const zero = c.JS_NewInt32(s.engine.context, 0);
    const after_hash = try cmp(s, .greater, hash, minus);
    const space_after = !s.truthy(space) or (after_hash and try cmp(s, .greater, try s.get(space, "index"), hash));
    const at_after = s.equal(at, minus) or (after_hash and try cmp(s, .greater, at, hash)); const colon_after = s.equal(colon, minus) or (after_hash and try cmp(s, .greater, colon, hash)); const second_after = s.equal(second, minus) or (after_hash and try cmp(s, .greater, second, hash));
    const has_slash = try cmp(s, .greater, slash, zero);
    const no_trailing_slash = if (after_hash) blk: { const atom = try v.js.atom(s.engine, try s.own(try @import("native_image_arithmetic.zig").binary(s.engine, .subtract, hash, c.JS_NewInt32(s.engine.context, 1)))); defer c.JS_FreeAtom(s.engine.context, atom); break :blk !try v.eq(s, try s.own(try s.engine.checked(c.JS_GetProperty(s.engine.context, input, atom))), "/"); } else !try ends(s, input, "/");
    const no_dot = !try starts(s, input, "."); return space_after and has_slash and no_trailing_slash and no_dot and at_after and colon_after and second_after;
}
fn protocol(s: *Scope, value: c.JSValue) !bool { inline for (.{ "git+ssh:", "ssh:", "git+https:", "git:", "http:", "https:", "git+http:", "github:", "bitbucket:", "gitlab:", "gist:", "sourcehut:" }) |name| if (try v.eq(s, value, name)) return true; return false; }
fn correctProtocol(s: *Scope, input: c.JSValue) !c.JSValue {
    const colon = try index(s, input, ":"); const method = try s.get(input, "slice"); const proto = try s.call(method, input, &.{ c.JS_NewInt32(s.engine.context, 0), try offset(s, colon, 1) }); if (try protocol(s, proto)) return input;
    if (try v.eq(s, try s.invoke(input, "substr", &.{ colon, c.JS_NewInt32(s.engine.context, 3) }), "://")) return input;
    const at = try index(s, input, "@"); if (try cmp(s, .greater, at, c.JS_NewInt32(s.engine.context, -1))) return if (try cmp(s, .greater, at, colon)) s.concat(try s.text("git+ssh://"), try s.stringify(input)) else input;
    const left = try s.get(input, "slice"); const prefix = try s.call(left, input, &.{ c.JS_NewInt32(s.engine.context, 0), try offset(s, colon, 1) }); const right = try s.get(input, "slice"); const suffix = try s.call(right, input, &.{try offset(s, colon, 1)}); return s.concat(try s.concat(try s.stringify(prefix), try s.text("//")), try s.stringify(suffix));
}
fn lastBefore(s: *Scope, input: c.JSValue, char: []const u8) !c.JSValue { const hash = try index(s, input, "#"); const method = try s.get(input, "lastIndexOf"); const before = if (try cmp(s, .greater, hash, c.JS_NewInt32(s.engine.context, -1))) hash else try s.global("Infinity"); return s.call(method, input, &.{ try s.text(char), before }); }
pub fn correctUrl(s: *Scope, input: c.JSValue) !c.JSValue {
    var result = input; const at = try lastBefore(s, result, "@"); const colon = try lastBefore(s, result, ":"); if (try cmp(s, .greater, colon, at)) { const first = try s.stringify(try slice(s, result, c.JS_NewInt32(s.engine.context, 0), colon)); const method = try s.get(result, "slice"); const last = try s.stringify(try s.call(method, result, &.{try offset(s, colon, 1)})); result = try s.concat(try s.concat(first, try s.text("/")), last); }
    if (s.equal(try lastBefore(s, result, ":"), c.JS_NewInt32(s.engine.context, -1)) and s.equal(try index(s, result, "//"), c.JS_NewInt32(s.engine.context, -1))) result = try s.concat(try s.text("git+ssh://"), try s.stringify(result)); return result;
}
fn construct(s: *Scope, namespace: c.JSValue, input: c.JSValue) !c.JSValue { const constructor = try s.get(namespace, "URL"); var args = [_]c.JSValue{input}; return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, 1, &args))); }
pub fn safeUrl(s: *Scope, constructor: c.JSValue, input: c.JSValue) !c.JSValue { const generation = s.engine.native_allocation_generation; return construct(s, constructor, input) catch |err| { try caught.ignore(s.engine, err, generation); return c.pi_js_undefined(); }; }
fn parseUrl(s: *Scope, constructor: c.JSValue, input: c.JSValue) !c.JSValue { const corrected = try correctProtocol(s, input); const parsed = try safeUrl(s, constructor, corrected); return if (s.truthy(parsed)) parsed else safeUrl(s, constructor, try correctUrl(s, corrected)); }
fn shortcutHost(s: *Scope, value: c.JSValue) !?Host { inline for (.{ .{ "github:", Host.github }, .{ "bitbucket:", Host.bitbucket }, .{ "gitlab:", Host.gitlab }, .{ "gist:", Host.gist }, .{ "sourcehut:", Host.sourcehut } }) |pair| if (try v.eq(s, value, pair[0])) return pair[1]; return null; }
fn domainHost(s: *Scope, value: c.JSValue) !?Host { inline for (.{ .{ "github.com", Host.github }, .{ "bitbucket.org", Host.bitbucket }, .{ "gitlab.com", Host.gitlab }, .{ "gist.github.com", Host.gist }, .{ "git.sr.ht", Host.sourcehut } }) |pair| if (try v.eq(s, value, pair[0])) return pair[1]; return null; }
fn domain(host: Host) []const u8 { return switch (host) { .github => "github.com", .bitbucket => "bitbucket.org", .gitlab => "gitlab.com", .gist => "gist.github.com", .sourcehut => "git.sr.ht" }; }
fn supported(s: *Scope, host: Host, proto: c.JSValue) !bool {
    const values: []const []const u8 = switch (host) { .github => &.{ "git:", "http:", "git+ssh:", "git+https:", "ssh:", "https:" }, .bitbucket, .gitlab => &.{ "git+ssh:", "git+https:", "ssh:", "https:" }, .gist => &.{ "git:", "git+ssh:", "git+https:", "ssh:", "https:" }, .sourcehut => &.{ "git+ssh:", "https:" } };
    return s.truthy(try s.invoke(try array(s, values), "includes", &.{proto}));
}
fn decode(s: *Scope, value: c.JSValue) !c.JSValue { return s.call(try s.global("decodeURIComponent"), c.pi_js_undefined(), &.{value}); }
fn stripGit(s: *Scope, value: c.JSValue) !c.JSValue { return if (try ends(s, value, ".git")) slice(s, value, c.JS_NewInt32(s.engine.context, 0), c.JS_NewInt32(s.engine.context, -4)) else value; }
fn field(s: *Scope, host: Host, user: c.JSValue, project: c.JSValue, ref: c.JSValue) !c.JSValue { const result = try s.object(); try s.put(result, "domain", try s.text(domain(host))); try s.put(result, "user", user); try s.put(result, "project", project); try s.put(result, "committish", ref); return result; }
fn parts(s: *Scope, values: c.JSValue, length: u32) !c.JSValue { const result = try s.array(); var iterator = try v.iterator(s, values); defer iterator.deinit(); errdefer iterator.closePreserving(); var i: u32 = 0; while (i < length) : (i += 1) { const value = if (try iterator.next()) |item| try s.own(item) else c.pi_js_undefined(); try s.index(result, i, value); } try iterator.close(); return result; }
fn extract(s: *Scope, host: Host, shortcut: bool, parsed: c.JSValue) !c.JSValue {
    var user = c.pi_js_null(); var project = c.pi_js_null(); var ref = c.pi_js_null();
    if (shortcut) {
        const pathname = try s.get(parsed, "pathname"); var path = if (try starts(s, pathname, "/")) try slice(s, pathname, c.JS_NewInt32(s.engine.context, 1), null) else pathname; const at = try index(s, path, "@"); if (try cmp(s, .greater, at, c.JS_NewInt32(s.engine.context, -1))) { const method = try s.get(path, "slice"); path = try s.call(method, path, &.{try offset(s, at, 1)}); }
        const slash = try s.invoke(path, "lastIndexOf", &.{try s.text("/")}); if (try cmp(s, .greater, slash, c.JS_NewInt32(s.engine.context, -1))) { user = try decode(s, try slice(s, path, c.JS_NewInt32(s.engine.context, 0), slash)); if (!s.truthy(user)) user = c.pi_js_null(); const method = try s.get(path, "slice"); project = try decode(s, try s.call(method, path, &.{try offset(s, slash, 1)})); } else project = try decode(s, path);
        project = try stripGit(s, project); if (s.truthy(try s.get(parsed, "hash"))) { const decoder = try s.global("decodeURIComponent"); ref = try s.call(decoder, c.pi_js_undefined(), &.{try slice(s, try s.get(parsed, "hash"), c.JS_NewInt32(s.engine.context, 1), null)}); }
        return field(s, host, user, project, ref);
    }
    if (!try supported(s, host, try s.get(parsed, "protocol"))) return c.pi_js_undefined();
    const path = try s.get(parsed, "pathname");
    if (host == .gitlab) {
        const without = try slice(s, path, c.JS_NewInt32(s.engine.context, 1), null); if (try includes(s, without, "/-/") or try includes(s, without, "/archive.tar.gz")) return c.pi_js_undefined(); const segments = try s.invoke(without, "split", &.{try s.text("/")}); project = try stripGit(s, try s.invoke(segments, "pop", &.{})); user = try s.invoke(segments, "join", &.{try s.text("/")}); if (!s.truthy(user) or !s.truthy(project)) return c.pi_js_undefined();
    } else {
        const length: u32 = if (host == .github) 5 else 4; const segments = try parts(s, try s.invoke(path, "split", &.{ try s.text("/"), c.JS_NewInt32(s.engine.context, @intCast(length)) }), length); user = try v.at(s, segments, 1); project = try v.at(s, segments, 2); const aux = try v.at(s, segments, 3);
        switch (host) {
            .github => { if (s.truthy(aux) and !try v.eq(s, aux, "tree")) return c.pi_js_undefined(); ref = if (s.truthy(aux)) try v.at(s, segments, 4) else try slice(s, try s.get(parsed, "hash"), c.JS_NewInt32(s.engine.context, 1), null); },
            .bitbucket => if (s.truthy(try s.invoke(try array(s, &.{"get"}), "includes", &.{aux}))) return c.pi_js_undefined(),
            .gist => { if (try v.eq(s, aux, "raw")) return c.pi_js_undefined(); if (!s.truthy(project)) { if (!s.truthy(user)) return c.pi_js_undefined(); project = user; user = c.pi_js_null(); } },
            .sourcehut => if (s.truthy(try s.invoke(try array(s, &.{"archive"}), "includes", &.{aux}))) return c.pi_js_undefined(),
            .gitlab => unreachable,
        }
        if (s.truthy(project)) project = try stripGit(s, project); if ((host != .gist and !s.truthy(user)) or !s.truthy(project)) return c.pi_js_undefined();
    }
    if (host != .github) ref = try slice(s, try s.get(parsed, "hash"), c.JS_NewInt32(s.engine.context, 1), null);
    // Source from-url decodes the extractor fields inside its URIError catch.
    user = if (s.truthy(user)) try decode(s, user) else user; project = try decode(s, project); ref = try decode(s, ref);
    const proto = try s.get(parsed, "protocol"); if (!(try v.eq(s, proto, "git+ssh:") or try v.eq(s, proto, "ssh:") or try v.eq(s, proto, "git+https:"))) _ = try slice(s, try s.get(parsed, "protocol"), c.JS_NewInt32(s.engine.context, 0), c.JS_NewInt32(s.engine.context, -1));
    return field(s, host, user, project, ref);
}
fn parseHosted(s: *Scope, constructor: c.JSValue, input: c.JSValue) !c.JSValue {
    if (!s.truthy(input)) return c.pi_js_undefined(); const corrected = if (try shorthand(s, input)) try s.concat(try s.text("github:"), try s.stringify(input)) else input; const parsed = try parseUrl(s, constructor, corrected); if (!s.truthy(parsed)) return c.pi_js_undefined();
    const shortcut = try shortcutHost(s, try s.get(parsed, "protocol")); const hostname = try s.get(parsed, "hostname"); const normalized = if (try starts(s, hostname, "www.")) try slice(s, try s.get(parsed, "hostname"), c.JS_NewInt32(s.engine.context, 4), null) else try s.get(parsed, "hostname"); const host = shortcut orelse (try domainHost(s, normalized) orelse return c.pi_js_undefined());
    // Even though auth is not consumed by Pi, these Source reads/conversions
    // are observable through the actual captured URL prototype.
    const proto = try s.get(parsed, "protocol"); if (try v.eq(s, proto, "git+https:") or try v.eq(s, proto, "git:") or try v.eq(s, proto, "http:") or try v.eq(s, proto, "https:") or try v.eq(s, proto, "git+http:")) {
        if (s.truthy(try s.get(parsed, "username")) or s.truthy(try s.get(parsed, "password"))) { const username = try s.stringify(try s.get(parsed, "username")); const password = if (s.truthy(try s.get(parsed, "password"))) try s.concat(try s.text(":"), try s.stringify(try s.get(parsed, "password"))) else try s.text(""); _ = try s.concat(username, password); }
    }
    const generation = s.engine.native_allocation_generation;
    return extract(s, host, shortcut != null, parsed) catch |err| {
        const reason = (try caught.take(s.engine, err, generation)) orelse return err; defer s.engine.freeValue(reason);
        const is_uri = c.JS_IsInstanceOf(s.engine.context, reason, try s.global("URIError")); if (is_uri < 0) return v.js.capture(s.engine); if (is_uri != 0) return c.pi_js_undefined(); _ = try s.engine.checked(c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, reason))); unreachable;
    };
}
pub fn count(s: *Scope, cache: c.JSValue) !u32 { var value: u32 = 0; if (c.JS_ToUint32(s.engine.context, &value, try s.get(cache, "size")) < 0) return v.js.capture(s.engine); return value; }
pub fn find(s: *Scope, entries: c.JSValue, size: u32, key: c.JSValue) !?u32 { for (0..size) |index_value| { var local: Scope = .{ .engine = s.engine }; defer local.deinit(); const row = try v.at(&local, entries, @intCast(index_value)); if (local.equal(try local.get(row, "key"), key)) return @intCast(index_value); } return null; }
pub fn moveLast(s: *Scope, entries: c.JSValue, size: u32, index_value: u32) !c.JSValue { const row = try v.at(s, entries, index_value); var i = index_value; while (i + 1 < size) : (i += 1) { var local: Scope = .{ .engine = s.engine }; defer local.deinit(); try local.index(entries, i, try v.at(&local, entries, i + 1)); } try s.index(entries, size - 1, row); return s.get(row, "value"); }
pub fn remove(s: *Scope, cache: c.JSValue, entries: c.JSValue, size: u32, index_value: u32) !void {
    _ = try moveLast(s, entries, size, index_value); const atom = c.JS_NewAtomUInt32(s.engine.context, size - 1); if (atom == c.JS_ATOM_NULL) return v.js.capture(s.engine); defer c.JS_FreeAtom(s.engine.context, atom); if (c.JS_DeleteProperty(s.engine.context, entries, atom, 0) < 0) return v.js.capture(s.engine); try s.put(cache, "size", c.JS_NewUint32(s.engine.context, size - 1));
}
fn fromUrl(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (!c.JS_IsString(arg(args, 0))) return c.pi_js_undefined(); var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = arg(args, 0); const opts = arg(args, 1);
    // Evaluate the real stringify on every call, even a cache hit.
    const json = try s.global("JSON"); const stringify = try s.get(json, "stringify"); const suffix = try s.call(stringify, json, &.{if (s.truthy(opts)) opts else try s.object()}); const key = try s.concat(input, suffix); const cache = roots[1]; const entries = try s.get(cache, "entries"); var size = try count(&s, cache);
    if (try find(&s, entries, size, key)) |found| return c.JS_DupValue(engine.context, try moveLast(&s, entries, size, found));
    const info = try parseHosted(&s, roots[0], input); if (c.JS_IsUndefined(info)) { size = try count(&s, cache); if (try find(&s, entries, size, key)) |found| try remove(&s, cache, entries, size, found); return info; }
    // A parse can reenter from a live URL/decoder hook. Source cache.set updates
    // an existing key and recency; do not append a duplicate after reentry.
    size = try count(&s, cache); if (try find(&s, entries, size, key)) |found| { const row = try v.at(&s, entries, found); try s.put(row, "value", info); _ = try moveLast(&s, entries, size, found); }
    else {
        const row = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()))); try s.put(row, "key", key); try s.put(row, "value", info);
        if (size == 1000) { _ = try moveLast(&s, entries, size, 0); try s.index(entries, size - 1, row); } else { try s.index(entries, size, row); size += 1; try s.put(cache, "size", c.JS_NewUint32(engine.context, size)); }
    }
    // Source returns cache.get(key), not the transient parse result.
    return c.JS_DupValue(engine.context, try moveLast(&s, entries, size, (try find(&s, entries, size, key)) orelse return error.MissingHostedCacheEntry));
}
