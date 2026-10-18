//! Private SDK-only hosted-git-info9.0.3 consumed policy. This is not a public
//! hosted-git-info replacement: no template/fromManifest/addHost API is exposed.
const std = @import("std");
const x = @import("native_sdk_git_url_values.zig");
const c = x.c;
const f = @import("native_node_function.zig");
const Entry = struct { key: c.JSValue, info: c.JSValue };
const State = struct { engine: *x.em.Engine, node_url: c.JSValue, hosts: c.JSValue, protocols: c.JSValue, object_assign: c.JSValue, object_prototype: c.JSValue, map_prototype: c.JSValue, map_get: c.JSValue, map_set: c.JSValue, map_delete: c.JSValue, count: usize = 0, entries: [1000]Entry = undefined };
const names = [_][]const u8{ "github", "bitbucket", "gitlab", "gist", "sourcehut" };
const domains = [_][]const u8{ "github.com", "bitbucket.org", "gitlab.com", "gist.github.com", "git.sr.ht" };
fn finalizer(rt: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    for (state.entries[0..state.count]) |entry| { c.JS_FreeValueRT(rt, entry.key); c.JS_FreeValueRT(rt, entry.info); }
    for (.{ state.node_url, state.hosts, state.protocols, state.object_assign, state.object_prototype, state.map_prototype, state.map_get, state.map_set, state.map_delete }) |value| c.JS_FreeValueRT(rt, value);
    const engine = state.engine; engine.gpa.destroy(state); c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
}
fn mark(rt: ?*c.JSRuntime, owner: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    for (state.entries[0..state.count]) |entry| { c.JS_MarkValue(rt, entry.key, visit); c.JS_MarkValue(rt, entry.info, visit); }
    for (.{ state.node_url, state.hosts, state.protocols, state.object_assign, state.object_prototype, state.map_prototype, state.map_get, state.map_set, state.map_delete }) |value| c.JS_MarkValue(rt, value, visit);
}
pub fn create(o: *x.Ops, node_url: c.JSValue) !c.JSValue {
    const engine = o.s.engine;
    if (!c.JS_IsObject(node_url)) return error.RequiredActualNodeUrlNamespace;
    const hosts = try o.object(); const shortcut = try o.object(); const by_domain = try o.object(); const protocols = try o.object();
    try o.put(hosts, "byShortcut", shortcut); try o.put(hosts, "byDomain", by_domain);
    for ([_][]const u8{ "git+ssh:", "ssh:", "git+https:", "git:", "http:", "https:", "git+http:" }, 0..) |protocol, index| {
        const record = try o.object(); if (index < 2) try o.put(record, "name", try o.text("sshurl")) else if (index == 2) try o.put(record, "name", try o.text("https"));
        if (index >= 2) try o.put(record, "auth", c.pi_js_bool(engine.context, 1));
        try putKey(o, protocols, try o.text(protocol), record);
    }
    for (names, domains, 0..) |name, domain, index| {
        const record = try o.object(); try o.put(record, "domain", try o.text(domain));
        const allowed = try o.array();
        const list: []const []const u8 = switch (index) {
            0 => &.{ "git:", "http:", "git+ssh:", "git+https:", "ssh:", "https:" },
            3 => &.{ "git:", "git+ssh:", "git+https:", "ssh:", "https:" },
            4 => &.{ "git+ssh:", "https:" },
            else => &.{ "git+ssh:", "git+https:", "ssh:", "https:" },
        };
        for (list, 0..) |protocol, at| try o.index(allowed, @intCast(at), try o.text(protocol));
        try o.put(record, "protocols", allowed);
        const extract = try o.own(try f.createArrow(engine, "extract", 1, extractCallback, &.{o.number(@intCast(index))})); try o.put(record, "extract", extract);
        try putKey(o, hosts, try o.text(name), record);
        try putKey(o, by_domain, try o.text(domain), try o.text(name));
        const protocol = try o.template(&.{ try o.text(name), try o.text(":") });
        try putKey(o, shortcut, protocol, try o.text(name));
        const descriptor = try o.object(); try o.put(descriptor, "name", try o.text(name)); try putKey(o, protocols, protocol, descriptor);
    }
    const object_assign = try o.get(try o.global("Object"), "assign");
    const ordinary = try o.object(); const object_prototype = try o.own(try engine.checked(c.JS_GetPrototype(engine.context, ordinary)));
    const map_constructor = try o.global("Map");
    const actual_map = try o.get(engine.intrinsic_clone_operations, "Map");
    if (!c.JS_IsStrictEqual(engine.context, map_constructor, actual_map)) return error.UnsupportedHostedGitMapConstructorInterposition;
    const map_prototype = try o.get(map_constructor, "prototype");
    const map_get = try o.get(map_prototype, "get"); const map_set = try o.get(map_prototype, "set"); const map_delete = try o.get(map_prototype, "delete");
    const actual_insert = try o.get(engine.intrinsic_clone_operations, "Map.insert");
    if (!c.JS_IsStrictEqual(engine.context, map_set, actual_insert)) return error.UnsupportedHostedGitLruInterposition;
    const builtin_class = c.JS_GetClassID(engine.intrinsic_regexp_constructor);
    if (c.JS_GetClassID(object_assign) != builtin_class or c.JS_GetClassID(map_constructor) != builtin_class or c.JS_GetClassID(map_get) != builtin_class or c.JS_GetClassID(map_set) != builtin_class or c.JS_GetClassID(map_delete) != builtin_class) return error.UnsupportedHostedGitInternalInitializationInterposition;
    try admitMap(o, actual_map, map_get, map_set, map_delete);
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
    var attached = false; errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
    const state = try engine.gpa.create(State); errdefer if (!attached) engine.gpa.destroy(state);
    var class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Private actual SDK hosted Git policy", .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const owner = try o.own(try engine.checked(c.JS_NewObjectClass(engine.context, class)));
    state.* = .{ .engine = engine, .node_url = c.JS_DupValue(engine.context, node_url), .hosts = c.JS_DupValue(engine.context, hosts), .protocols = c.JS_DupValue(engine.context, protocols), .object_assign = c.JS_DupValue(engine.context, object_assign), .object_prototype = c.JS_DupValue(engine.context, object_prototype), .map_prototype = c.JS_DupValue(engine.context, map_prototype), .map_get = c.JS_DupValue(engine.context, map_get), .map_set = c.JS_DupValue(engine.context, map_set), .map_delete = c.JS_DupValue(engine.context, map_delete) };
    _ = c.JS_SetOpaque(owner, state); attached = true; try guardCache(o, state); return owner;
}
fn admitMap(o: *x.Ops, constructor: c.JSValue, get: c.JSValue, set: c.JSValue, delete: c.JSValue) !void {
    var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, admitMapBody(&local, constructor, get, set, delete));
}
fn admitMapBody(o: *x.Ops, constructor: c.JSValue, get: c.JSValue, set: c.JSValue, delete: c.JSValue) !void {
    const map = try o.construct(constructor, &.{});
    const key = try o.text("pi-private:actual-sdk-map-admission"); const marker = try o.object();
    _ = o.call(set, map, &.{ key, marker }) catch |err| { try x.swallow(o.s.engine, err); return error.UnsupportedHostedGitLruInterposition; };
    const value = o.call(get, map, &.{key}) catch |err| { try x.swallow(o.s.engine, err); return error.UnsupportedHostedGitLruInterposition; };
    if (!c.JS_IsStrictEqual(o.s.engine.context, value, marker)) return error.UnsupportedHostedGitLruInterposition;
    const removed = o.call(delete, map, &.{key}) catch |err| { try x.swallow(o.s.engine, err); return error.UnsupportedHostedGitLruInterposition; };
    if (!c.JS_IsBool(removed) or !o.truthy(removed)) return error.UnsupportedHostedGitLruInterposition;
    const absent = o.call(get, map, &.{key}) catch |err| { try x.swallow(o.s.engine, err); return error.UnsupportedHostedGitLruInterposition; };
    if (!c.JS_IsUndefined(absent)) return error.UnsupportedHostedGitLruInterposition;
}
fn releaseDescriptor(engine: *x.em.Engine, descriptor: c.JSPropertyDescriptor, result: anyerror!void, reverse: bool) !void {
    var completion = x.owned.Completion.initVoid(engine, result);
    if (reverse) { completion.release(descriptor.setter); completion.release(descriptor.getter); completion.release(descriptor.value); }
    else { completion.release(descriptor.value); completion.release(descriptor.getter); completion.release(descriptor.setter); }
    return completion.finishVoid();
}
fn putKey(o: *x.Ops, target: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    const atom = c.JS_ValueToAtom(o.s.engine.context, key); if (atom == c.JS_ATOM_NULL) return x.allocationFailure(o.s.engine);
    defer c.JS_FreeAtom(o.s.engine.context, atom);
    if (c.JS_DefinePropertyValue(o.s.engine.context, target, atom, c.JS_DupValue(o.s.engine.context, value), c.JS_PROP_C_W_E) < 0) return x.allocationFailure(o.s.engine);
    try o.s.engine.checkNativeEntry();
}
fn less(o: *x.Ops, value: c.JSValue, limit: i32) !bool { return o.compare(4, value, o.number(limit)); }
fn greater(o: *x.Ops, value: c.JSValue, limit: i32) !bool { return o.compare(6, value, o.number(limit)); }
fn lastBefore(o: *x.Ops, text: c.JSValue, char: []const u8, before: []const u8) !c.JSValue {
    const start = try o.invoke(text, "indexOf", &.{try o.text(before)});
    const function = try o.get(text, "lastIndexOf");
    return o.call(function, text, &.{ try o.text(char), if (try greater(o, start, -1)) start else c.JS_NewFloat64(o.s.engine.context, std.math.inf(f64)) });
}
fn correctProtocol(o: *x.Ops, text: c.JSValue, protocols: c.JSValue) !c.JSValue {
    const colon = try o.invoke(text, "indexOf", &.{try o.text(":")});
    const proto = try o.sliceToAfter(text, colon);
    const has = try o.get(try o.get(try o.global("Object"), "prototype"), "hasOwnProperty");
    if (o.truthy(try o.invoke(has, "call", &.{ protocols, proto }))) return text;
    if (try o.equal(try o.invoke(text, "substr", &.{ colon, o.number(3) }), "://")) return text;
    const at = try o.invoke(text, "indexOf", &.{try o.text("@")});
    if (try greater(o, at, -1)) {
        if (try o.compare(6, at, colon)) return o.template(&.{ try o.text("git+ssh://"), text });
        return text;
    }
    var corrected = try o.text(""); try o.append(&corrected, try o.sliceToAfter(text, colon)); try o.append(&corrected, try o.text("//")); try o.append(&corrected, try o.sliceAfter(text, colon)); return corrected;
}
fn correctUrl(o: *x.Ops, text: c.JSValue) !c.JSValue {
    var result = text; const at = try lastBefore(o, result, "@", "#"); const colon = try lastBefore(o, result, ":", "#");
    if (try o.compare(6, colon, at)) {
        const left = try o.invoke(result, "slice", &.{ o.number(0), colon });
        const prefix = try o.binary(0, left, try o.text("/"));
        const right = try o.sliceAfter(result, colon);
        // Source uses binary + here, not template ToString.
        result = try o.binary(0, prefix, right);
    }
    if (o.s.equal(try lastBefore(o, result, ":", "#"), o.number(-1)) and o.s.equal(try o.invoke(result, "indexOf", &.{try o.text("//")}), o.number(-1))) result = try o.template(&.{ try o.text("git+ssh://"), result });
    return result;
}
fn safeUrl(o: *x.Ops, state: *State, text: c.JSValue) !c.JSValue {
    return safeUrlInner(o, state, text) catch |err| { try x.swallow(o.s.engine, err); return c.pi_js_undefined(); };
}
fn safeUrlInner(o: *x.Ops, state: *State, text: c.JSValue) !c.JSValue { return o.construct(try o.get(state.node_url, "URL"), &.{text}); }
fn parsedUrl(o: *x.Ops, state: *State, text: c.JSValue) !c.JSValue {
    const corrected = try correctProtocol(o, text, state.protocols);
    const first = try safeUrl(o, state, corrected); if (o.truthy(first)) return first;
    return safeUrl(o, state, try correctUrl(o, corrected));
}
fn shorthand(o: *x.Ops, text: c.JSValue) !bool {
    const hash = try o.invoke(text, "indexOf", &.{try o.text("#")}); const slash = try o.invoke(text, "indexOf", &.{try o.text("/")});
    const second_method = try o.get(text, "indexOf"); const second = try o.call(second_method, text, &.{ try o.text("/"), try o.binary(0, slash, o.number(1)) });
    const colon = try o.invoke(text, "indexOf", &.{try o.text(":")}); const space = try o.invoke(try o.regex("\\s", ""), "exec", &.{text}); const at = try o.invoke(text, "indexOf", &.{try o.text("@")});
    const space_ok = !o.truthy(space) or ((try greater(o, hash, -1)) and try o.compare(6, try o.get(space, "index"), hash));
    const at_ok = o.s.equal(at, o.number(-1)) or ((try greater(o, hash, -1)) and try o.compare(6, at, hash));
    const colon_ok = o.s.equal(colon, o.number(-1)) or ((try greater(o, hash, -1)) and try o.compare(6, colon, hash));
    const second_ok = o.s.equal(second, o.number(-1)) or ((try greater(o, hash, -1)) and try o.compare(6, second, hash));
    const has_slash = try greater(o, slash, 0);
    const end_ok = if (try greater(o, hash, -1)) !try o.equal(try o.key(text, try o.binary(1, hash, o.number(1))), "/") else !o.truthy(try o.invoke(text, "endsWith", &.{try o.text("/")}));
    const start_ok = !o.truthy(try o.invoke(text, "startsWith", &.{try o.text(".")}));
    return space_ok and has_slash and end_ok and start_ok and at_ok and colon_ok and second_ok;
}
fn elision(o: *x.Ops, iterator: *x.iterators.v.js.Iterator) !void {
    var scope: x.Scope = .{ .engine = o.s.engine };
    return x.owned.finishVoid(&scope, elisionBody(&scope, iterator));
}
fn elisionBody(scope: *x.Scope, iterator: *x.iterators.v.js.Iterator) !void {
    var local: x.Ops = .{ .s = scope }; const o = &local;
    try x.iterators.budget(o.s.engine, &iterator.native_steps);
    errdefer iterator.closed = true;
    const step = try o.call(iterator.next_function, iterator.iterator, &.{});
    if (!c.JS_IsObject(step)) return @import("native_js_values.zig").typeError(o.s.engine, "Iterator result is not an object");
    if (o.truthy(try o.get(step, "done"))) iterator.closed = true;
    // A destructuring elision does not perform IteratorValue.
}
fn destructure(o: *x.Ops, segments: c.JSValue, count: usize) ![5]c.JSValue {
    var iterator = try x.initIterator(o.s, segments);
    return x.retireNative(o.s.engine, &iterator, destructureBody(o, &iterator, count));
}
fn destructureBody(o: *x.Ops, iterator: *x.iterators.v.js.Iterator, count: usize) ![5]c.JSValue {
    var values: [5]c.JSValue = undefined; for (&values) |*value| value.* = c.pi_js_undefined();
    for (values[0..count], 0..) |*slot, index| {
        if (iterator.closed) continue;
        if (index == 0) { try elision(o, iterator); continue; }
        const generation = o.s.engine.native_allocation_generation;
        const next = x.iterators.advance(o.s.engine, iterator) catch |err| return x.iterators.closeAbrupt(o.s.engine, iterator, x.current(o.s.engine, err, generation), o.s.engine.native_allocation_generation);
        if (next) |value| slot.* = o.own(value) catch |err| return x.iterators.closeAbrupt(o.s.engine, iterator, err, o.s.engine.native_allocation_generation);
    }
    try x.iterators.closeNormal(o.s.engine, iterator);
    return values;
}
fn extractCallback(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, extractBody(&o, args, roots));
}
fn extractBody(o: *x.Ops, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const engine = o.s.engine;
    var kind: i32 = 0; if (c.JS_ToInt32(engine.context, &kind, roots[0]) < 0) return @import("native_js_values.zig").capture(engine);
    const url = if (args.len == 0) c.pi_js_undefined() else args[0];
    var user: c.JSValue = undefined; var project: c.JSValue = undefined; var committish: c.JSValue = undefined;
    if (kind == 2) {
        const path = try o.invoke(try o.get(url, "pathname"), "slice", &.{o.number(1)});
        if (o.truthy(try o.invoke(path, "includes", &.{try o.text("/-/")})) or o.truthy(try o.invoke(path, "includes", &.{try o.text("/archive.tar.gz")}))) return c.pi_js_undefined();
        const segments = try o.invoke(path, "split", &.{try o.text("/")}); project = try o.invoke(segments, "pop", &.{});
        if (o.truthy(try o.invoke(project, "endsWith", &.{try o.text(".git")}))) project = try o.invoke(project, "slice", &.{ o.number(0), o.number(-4) });
        user = try o.invoke(segments, "join", &.{try o.text("/")}); if (!o.truthy(user) or !o.truthy(project)) return c.pi_js_undefined();
        committish = try o.invoke(try o.get(url, "hash"), "slice", &.{o.number(1)});
    } else {
        const segments = try o.invoke(try o.get(url, "pathname"), "split", &.{ try o.text("/"), o.number(if (kind == 0) 5 else 4) });
        // Array binding uses the actual iterator, including early normal close.
        const bindings = try destructure(o, segments, if (kind == 0) 5 else 4);
        user = bindings[1]; project = bindings[2]; const aux = bindings[3];
        if (kind == 0) committish = bindings[4];
        if (kind == 0) {
            if (o.truthy(aux) and !try o.equal(aux, "tree")) return c.pi_js_undefined();
            if (!o.truthy(aux)) committish = try o.invoke(try o.get(url, "hash"), "slice", &.{o.number(1)});
        } else if (kind == 3) {
            if (try o.equal(aux, "raw")) return c.pi_js_undefined();
            if (!o.truthy(project)) { if (!o.truthy(user)) return c.pi_js_undefined(); project = user; user = c.pi_js_null(); }
        } else {
            const excluded = try o.array(); try o.index(excluded, 0, try o.text(if (kind == 1) "get" else "archive"));
            if (o.truthy(try o.invoke(excluded, "includes", &.{aux}))) return c.pi_js_undefined();
        }
        if ((kind == 3 or o.truthy(project)) and o.truthy(try o.invoke(project, "endsWith", &.{try o.text(".git")}))) project = try o.invoke(project, "slice", &.{ o.number(0), o.number(-4) });
        if (kind != 3 and (!o.truthy(user) or !o.truthy(project))) return c.pi_js_undefined();
        if (kind != 0) committish = try o.invoke(try o.get(url, "hash"), "slice", &.{o.number(1)});
    }
    const result = try o.object(); try o.put(result, "user", user); try o.put(result, "project", project); try o.put(result, "committish", committish); return c.JS_DupValue(engine.context, result);
}
fn find(state: *State, key: c.JSValue) !?usize {
    var steps: usize = 0;
    for (state.entries[0..state.count], 0..) |entry, index| {
        try x.iterators.budget(state.engine, &steps);
        if (c.JS_IsStrictEqual(state.engine.context, entry.key, key)) return index;
    }
    return null;
}
fn cached(state: *State, key: c.JSValue) !?c.JSValue {
    const index = (try find(state, key)) orelse return null;
    const entry = state.entries[index];
    std.mem.copyForwards(Entry, state.entries[index .. state.count - 1], state.entries[index + 1 .. state.count]);
    state.entries[state.count - 1] = entry;
    return c.JS_DupValue(state.engine.context, entry.info);
}
fn remember(state: *State, key: c.JSValue, info: c.JSValue) !void {
    const old_index = try find(state, key);
    var retired: ?Entry = null;
    if (old_index) |index| {
        retired = state.entries[index];
        std.mem.copyForwards(Entry, state.entries[index .. state.count - 1], state.entries[index + 1 .. state.count]);
        state.count -= 1;
    } else if (!c.JS_IsUndefined(info) and state.count == state.entries.len) {
        retired = state.entries[0]; std.mem.copyForwards(Entry, state.entries[0 .. state.count - 1], state.entries[1..state.count]); state.count -= 1;
    }
    if (!c.JS_IsUndefined(info)) {
        state.entries[state.count] = .{ .key = c.JS_DupValue(state.engine.context, key), .info = c.JS_DupValue(state.engine.context, info) }; state.count += 1;
    }
    // LRU set(undefined) deletes, rather than caching an undefined value.
    // Publish the replacement topology before any finalizer-capable retirement.
    var completion = x.owned.Completion.initVoid(state.engine, {});
    if (retired) |entry| { completion.release(entry.key); completion.release(entry.info); }
    try completion.finishVoid();
}
fn guardMetadataConstruction(o: *x.Ops, state: *State) !void {
    const assign = try o.get(try o.global("Object"), "assign");
    if (!c.JS_IsStrictEqual(o.s.engine.context, assign, state.object_assign)) return error.UnsupportedHostedGitConstructorInterposition;
    // The private consumed record does not expose GitHost's unused URL-template
    // API. Reject a setter/nonwritable prototype that could observe omitted
    // constructor fields instead of inventing partial template functions.
    inline for (.{ "sshtemplate", "sshurltemplate", "edittemplate", "browsetemplate", "browsetreetemplate", "browseblobtemplate", "docstemplate", "httpstemplate", "filetemplate", "shortcuttemplate", "pathtemplate", "bugstemplate", "hashformat", "protocols", "domain", "treepath", "blobpath", "editpath", "gittemplate", "tarballtemplate", "extract", "type", "user", "auth", "project", "committish", "default", "opts" }) |name| {
        const atom = c.JS_NewAtom(o.s.engine.context, name); if (atom == c.JS_ATOM_NULL) return @import("native_js_values.zig").capture(o.s.engine);
        defer c.JS_FreeAtom(o.s.engine.context, atom);
        var descriptor: c.JSPropertyDescriptor = undefined;
        const has = c.JS_GetOwnProperty(o.s.engine.context, &descriptor, state.object_prototype, atom);
        if (has < 0) return @import("native_js_values.zig").capture(o.s.engine);
        if (has != 0) {
            const status: anyerror!void = if (o.s.engine.checkNativeEntry()) |_| blk: {
                if (descriptor.flags & c.JS_PROP_GETSET != 0 or descriptor.flags & c.JS_PROP_WRITABLE == 0) break :blk error.UnsupportedHostedGitConstructorInterposition;
                break :blk {};
            } else |err| err;
            try releaseDescriptor(o.s.engine, descriptor, status, true);
        } else try o.s.engine.checkNativeEntry();
    }
}
fn guardCache(o: *x.Ops, state: *State) !void {
    // lru-cache11.4 default per-call options are private plain {} objects.
    // Inherited options/status can expose its full diagnostics/cache API, which
    // this SDK-only fixed-default policy intentionally does not impersonate.
    inline for (.{ "status", "ttl", "start", "noDisposeOnSet", "sizeCalculation", "noUpdateTTL", "size", "allowStale", "updateAgeOnGet", "noDeleteOnStaleGet", "updateAgeOnHas", "ttlResolution", "ttlAutopurge", "dispose", "onInsert", "disposeAfter", "maxSize", "maxEntrySize", "fetchMethod", "memoMethod", "noDeleteOnFetchRejection", "allowStaleOnFetchRejection", "allowStaleOnFetchAbort", "ignoreFetchAbort", "perf" }) |name| {
        const atom = c.JS_NewAtom(o.s.engine.context, name); if (atom == c.JS_ATOM_NULL) return x.allocationFailure(o.s.engine);
        defer c.JS_FreeAtom(o.s.engine.context, atom);
        var descriptor: c.JSPropertyDescriptor = undefined;
        const has = c.JS_GetOwnProperty(o.s.engine.context, &descriptor, state.object_prototype, atom);
        if (has < 0) return @import("native_js_values.zig").capture(o.s.engine);
        if (has != 0) {
            const status: anyerror!void = if (o.s.engine.checkNativeEntry()) |_| error.UnsupportedHostedGitLruOptionsInterposition else |err| err;
            try releaseDescriptor(o.s.engine, descriptor, status, false);
        } else try o.s.engine.checkNativeEntry();
    }
    inline for (.{ .{ "get", state.map_get }, .{ "set", state.map_set }, .{ "delete", state.map_delete } }) |item| {
        const atom = c.JS_NewAtom(o.s.engine.context, item[0]); if (atom == c.JS_ATOM_NULL) return @import("native_js_values.zig").capture(o.s.engine);
        defer c.JS_FreeAtom(o.s.engine.context, atom);
        var descriptor: c.JSPropertyDescriptor = undefined;
        const has = c.JS_GetOwnProperty(o.s.engine.context, &descriptor, state.map_prototype, atom);
        if (has < 0) return @import("native_js_values.zig").capture(o.s.engine);
        if (has == 0) { try o.s.engine.checkNativeEntry(); return error.UnsupportedHostedGitLruInterposition; }
        const status: anyerror!void = if (o.s.engine.checkNativeEntry()) |_| blk: {
            if (descriptor.flags & c.JS_PROP_GETSET != 0 or !c.JS_IsStrictEqual(o.s.engine.context, descriptor.value, item[1])) break :blk error.UnsupportedHostedGitLruInterposition;
            break :blk {};
        } else |err| err;
        try releaseDescriptor(o.s.engine, descriptor, status, true);
    }
}
fn createInfo(o: *x.Ops, state: *State, host_name: c.JSValue, user: c.JSValue, auth: c.JSValue, project: c.JSValue, committish: c.JSValue, representation: c.JSValue, opts: c.JSValue) !c.JSValue {
    try guardMetadataConstruction(o, state);
    const host = try o.key(state.hosts, host_name);
    const result = try o.object();
    if (!x.nullish(host)) try o.put(result, "domain", try o.get(host, "domain"));
    try o.put(result, "type", host_name); try o.put(result, "user", user); try o.put(result, "auth", auth);
    try o.put(result, "project", project); try o.put(result, "committish", committish); try o.put(result, "default", representation); try o.put(result, "opts", if (c.JS_IsUndefined(opts)) try o.object() else opts);
    return result;
}
fn hostArgs(parent: *x.Ops, state: *State, input: c.JSValue) !c.JSValue {
    var scope: x.Scope = .{ .engine = parent.s.engine }; var o: x.Ops = .{ .s = &scope };
    return parent.own(try x.owned.finishValue(&scope, x.duplicate(scope.engine, hostArgsBody(&o, state, input))));
}
fn hostArgsBody(o: *x.Ops, state: *State, input: c.JSValue) !c.JSValue {
    if (!o.truthy(input)) return c.pi_js_undefined();
    const corrected = if (try shorthand(o, input)) try o.template(&.{ try o.text("github:"), input }) else input;
    const parsed = try parsedUrl(o, state, corrected); if (!o.truthy(parsed)) return c.pi_js_undefined();
    const shortcut_map = try o.get(state.hosts, "byShortcut");
    const shortcut_name = try o.key(shortcut_map, try o.get(parsed, "protocol"));
    const domain_map = try o.get(state.hosts, "byDomain");
    const domain = if (o.truthy(try o.invoke(try o.get(parsed, "hostname"), "startsWith", &.{try o.text("www.")}))) try o.invoke(try o.get(parsed, "hostname"), "slice", &.{o.number(4)}) else try o.get(parsed, "hostname");
    const domain_name = try o.key(domain_map, domain); const host_name = if (o.truthy(shortcut_name)) shortcut_name else domain_name;
    if (!o.truthy(host_name)) return c.pi_js_undefined();
    const host = try o.key(state.hosts, if (o.truthy(shortcut_name)) shortcut_name else domain_name);
    var auth = c.pi_js_null();
    const protocol = try o.key(state.protocols, try o.get(parsed, "protocol"));
    if (!x.nullish(protocol) and o.truthy(try o.get(protocol, "auth")) and (o.truthy(try o.get(parsed, "username")) or o.truthy(try o.get(parsed, "password")))) {
        const username = try o.stringify(try o.get(parsed, "username"));
        const password = if (o.truthy(try o.get(parsed, "password"))) try o.binary(0, try o.text(":"), try o.get(parsed, "password")) else try o.text("");
        auth = try o.template(&.{ username, password });
    }
    return parseFields(o, state, parsed, shortcut_name, host_name, host, auth) catch |err| {
        const reason = try o.own(try x.takeOrdinary(o.s.engine, err));
        const constructor = try o.global("URIError");
        const generation = o.s.engine.native_allocation_generation;
        const instance = c.JS_IsInstanceOf(o.s.engine.context, reason, constructor);
        if (instance < 0) return x.current(o.s.engine, @import("native_js_values.zig").capture(o.s.engine), generation);
        o.s.engine.checkNativeEntry() catch |err| return x.current(o.s.engine, err, generation);
        if (instance == 1) return c.pi_js_undefined();
        return x.throwReason(o.s.engine, reason);
    };
}
fn parseFields(o: *x.Ops, state: *State, parsed: c.JSValue, shortcut_name: c.JSValue, host_name: c.JSValue, host: c.JSValue, auth: c.JSValue) !c.JSValue {
    var user = c.pi_js_null(); var project = c.pi_js_null(); var committish = c.pi_js_null(); var representation = c.pi_js_null();
    if (o.truthy(shortcut_name)) {
        var pathname = if (o.truthy(try o.invoke(try o.get(parsed, "pathname"), "startsWith", &.{try o.text("/")}))) try o.invoke(try o.get(parsed, "pathname"), "slice", &.{o.number(1)}) else try o.get(parsed, "pathname");
        const at = try o.invoke(pathname, "indexOf", &.{try o.text("@")}); if (try greater(o, at, -1)) pathname = try o.sliceAfter(pathname, at);
        const slash = try o.invoke(pathname, "lastIndexOf", &.{try o.text("/")});
        if (try greater(o, slash, -1)) {
            const decode_user = try o.global("decodeURIComponent"); user = try o.call(decode_user, c.pi_js_undefined(), &.{try o.invoke(pathname, "slice", &.{ o.number(0), slash })}); if (!o.truthy(user)) user = c.pi_js_null();
            const decode_project = try o.global("decodeURIComponent"); project = try o.call(decode_project, c.pi_js_undefined(), &.{try o.sliceAfter(pathname, slash)});
        } else project = try o.decode(pathname);
        if (o.truthy(try o.invoke(project, "endsWith", &.{try o.text(".git")}))) project = try o.invoke(project, "slice", &.{ o.number(0), o.number(-4) });
        if (o.truthy(try o.get(parsed, "hash"))) { const decode = try o.global("decodeURIComponent"); committish = try o.call(decode, c.pi_js_undefined(), &.{try o.invoke(try o.get(parsed, "hash"), "slice", &.{o.number(1)})}); }
        representation = try o.text("shortcut");
    } else {
        const allowed = try o.get(host, "protocols"); const includes = try o.get(allowed, "includes");
        if (!o.truthy(try o.call(includes, allowed, &.{try o.get(parsed, "protocol")}))) return c.pi_js_undefined();
        const segments = try o.invoke(host, "extract", &.{parsed}); if (!o.truthy(segments)) return c.pi_js_undefined();
        const first_user = try o.get(segments, "user");
        if (o.truthy(first_user)) { const decode = try o.global("decodeURIComponent"); user = try o.call(decode, c.pi_js_undefined(), &.{try o.get(segments, "user")}); } else user = first_user;
        const decode_project = try o.global("decodeURIComponent"); project = try o.call(decode_project, c.pi_js_undefined(), &.{try o.get(segments, "project")});
        const decode_ref = try o.global("decodeURIComponent"); committish = try o.call(decode_ref, c.pi_js_undefined(), &.{try o.get(segments, "committish")});
        const descriptor = try o.key(state.protocols, try o.get(parsed, "protocol"));
        const name = if (x.nullish(descriptor)) c.pi_js_undefined() else try o.get(descriptor, "name");
        representation = if (o.truthy(name)) name else try o.invoke(try o.get(parsed, "protocol"), "slice", &.{ o.number(0), o.number(-1) });
    }
    // Source's from-url returns arguments; construction happens OUTSIDE its
    // URIError catch in GitHost.fromUrl. Preserve that catch boundary below.
    const result = try o.array();
    for ([_]c.JSValue{ host_name, user, auth, project, committish, representation }, 0..) |value, i| try o.index(result, @intCast(i), value);
    try o.index(result, 6, c.pi_js_undefined());
    return result;
}
fn spreadArguments(o: *x.Ops, fields: c.JSValue) ![7]c.JSValue {
    var iterator = try x.initIterator(o.s, fields);
    return x.retireNative(o.s.engine, &iterator, spreadBody(o, &iterator));
}
fn spreadBody(o: *x.Ops, iterator: *x.iterators.v.js.Iterator) ![7]c.JSValue {
    var result: [7]c.JSValue = undefined; for (&result) |*value| value.* = c.pi_js_undefined();
    var index: usize = 0;
    while (true) {
        const generation = o.s.engine.native_allocation_generation;
        const value = x.iterators.advance(o.s.engine, iterator) catch |err| return x.iterators.closeAbrupt(o.s.engine, iterator, x.current(o.s.engine, err, generation), o.s.engine.native_allocation_generation);
        const item = value orelse break;
        const retained = o.own(item) catch |err| return x.iterators.closeAbrupt(o.s.engine, iterator, err, o.s.engine.native_allocation_generation);
        if (index < result.len) result[index] = retained;
        index +|= 1;
    }
    return result;
}
pub fn fromUrl(parent: *x.Ops, owner: c.JSValue, input: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(input)) return c.pi_js_undefined();
    var scope: x.Scope = .{ .engine = parent.s.engine }; var o: x.Ops = .{ .s = &scope };
    return parent.own(try x.owned.finishValue(&scope, fromUrlBody(&o, owner, input)));
}
fn fromUrlBody(o: *x.Ops, owner: c.JSValue, input: c.JSValue) !c.JSValue {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?));
    const json = try o.global("JSON"); const stringify = try o.get(json, "stringify");
    const serialized = try o.call(stringify, json, &.{try o.object()});
    const key = try o.binary(0, input, serialized);
    try guardCache(o, state);
    if (try cached(state, key)) |info| return info;
    const fields = try hostArgs(o, state, input);
    const info = if (o.truthy(fields)) blk: {
        const args = try spreadArguments(o, fields);
        break :blk try createInfo(o, state, args[0], args[1], args[2], args[3], args[4], args[5], args[6]);
    } else c.pi_js_undefined();
    try guardCache(o, state);
    try remember(state, key, info);
    // Source reads cache.get AFTER construction/set; reentrant callbacks can
    // therefore affect the cache. Do not return a manufactured local result.
    return (try cached(state, key)) orelse c.pi_js_undefined();
}
