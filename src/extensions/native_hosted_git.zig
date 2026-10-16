//! Full pinned GitHost constructor/prototype and static consumers. Original
//! host/template values and live Object.assign are retained, not projected.
const data = @import("native_sdk_package_data.zig");
const std = @import("std");
const h = @import("native_hosted_git_template_values.zig");
const v = h.v; const c = v.c; const Scope = v.Scope;
const f = @import("native_node_function.zig");
const parser = @import("native_hosted_git_parser.zig");
const cache_ops = @import("native_hosted_git_projection.zig");
const caught = @import("native_sdk_package_catch.zig");
pub const Inputs = struct { node_url: c.JSValue };
const Method = enum(i32) { hash, ssh, sshurl, browse, browseFile, docs, bugs, https, git, shortcut, path, tarball, file, edit, getDefaultRepresentation, toString };
const Static = enum(i32) { addHost, fromUrl, fromManifest, parseUrl };
fn private(s: *Scope) !c.JSValue { return s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, c.pi_js_null()))); }
fn getKey(s: *Scope, object: c.JSValue, key: c.JSValue) !c.JSValue { return s.own(try v.js.getKey(s.engine, object, key)); }
fn setKey(s: *Scope, object: c.JSValue, key: c.JSValue, value: c.JSValue) !void { const atom = try v.js.atom(s.engine, key); defer c.JS_FreeAtom(s.engine.context, atom); if (c.JS_SetProperty(s.engine.context, object, atom, c.JS_DupValue(s.engine.context, value)) < 0) return v.js.capture(s.engine); }
fn integer(s: *Scope, object: c.JSValue, name: [*:0]const u8) !u32 { var value: u32 = 0; if (c.JS_ToUint32(s.engine.context, &value, try s.get(object, name)) < 0) return v.js.capture(s.engine); return value; }
fn brand(s: *Scope, owner: c.JSValue, receiver: c.JSValue) !void {
    if (!c.JS_IsObject(receiver) or c.JS_GetClassID(receiver) != try integer(s, owner, "ordinaryClass")) return v.js.typeError(s.engine, "Receiver must be an instance of class GitHost");
    const atom = try v.js.atom(s.engine, try s.get(owner, "brand")); defer c.JS_FreeAtom(s.engine.context, atom); var descriptor: c.JSPropertyDescriptor = undefined; const found = c.JS_GetOwnProperty(s.engine.context, &descriptor, receiver, atom); if (found < 0) return v.js.capture(s.engine); if (found == 0) return v.js.typeError(s.engine, "Receiver must be an instance of class GitHost"); defer s.engine.freeValue(descriptor.value); defer s.engine.freeValue(descriptor.getter); defer s.engine.freeValue(descriptor.setter);
}
fn construct(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const owner = roots[0]; const receiver = try s.own(try @import("native_class.zig").object(engine, target));
    const atom = try v.js.atom(engine, try s.get(owner, "brand")); defer c.JS_FreeAtom(engine.context, atom); if (c.JS_DefinePropertyValue(engine.context, receiver, atom, c.pi_js_bool(engine.context, 1), 0) < 0) return v.js.capture(engine);
    const opts = if (c.JS_IsUndefined(h.arg(args, 6))) try s.object() else h.arg(args, 6); const object = try s.global("Object"); const assign = try s.get(object, "assign"); const host = try getKey(&s, try s.get(owner, "hosts"), h.arg(args, 0)); const fields = try s.object(); inline for (.{ "type", "user", "auth", "project", "committish", "default" }, 0..) |name, i| try data.put(s.engine, fields, name, h.arg(args, i)); try data.put(s.engine, fields, "opts", opts); _ = try s.call(assign, object, &.{ receiver, host, fields }); return c.JS_DupValue(engine.context, receiver);
}
fn fill(s: *Scope, receiver: c.JSValue, template: c.JSValue, opts: c.JSValue) !c.JSValue {
    if (!c.JS_IsFunction(s.engine.context, template)) return c.pi_js_null(); const options = try s.own(try v.js.spread(s.engine, receiver)); try v.js.spreadInto(s.engine, options, try s.get(receiver, "opts")); try v.js.spreadInto(s.engine, options, opts);
    if (!s.truthy(try s.get(options, "path"))) try s.set(options, "path", try s.text("")); if (s.truthy(try s.invoke(try s.get(options, "path"), "startsWith", &.{try s.text("/")}))) try s.set(options, "path", try s.invoke(try s.get(options, "path"), "slice", &.{c.JS_NewInt32(s.engine.context, 1)})); if (s.truthy(try s.get(options, "noCommittish"))) try s.set(options, "committish", c.pi_js_null()); const result = try s.call(template, c.pi_js_undefined(), &.{options}); return if (s.truthy(try s.get(options, "noGitPlus")) and s.truthy(try s.invoke(result, "startsWith", &.{try s.text("git+")}))) s.invoke(result, "slice", &.{c.JS_NewInt32(s.engine.context, 4)}) else result;
}
fn templateName(kind: Method) [*:0]const u8 { return switch (kind) { .ssh => "sshtemplate", .sshurl => "sshurltemplate", .docs => "docstemplate", .bugs => "bugstemplate", .https => "httpstemplate", .git => "gittemplate", .shortcut => "shortcuttemplate", .path => "pathtemplate", .tarball => "tarballtemplate", .file => "filetemplate", .edit => "edittemplate", else => unreachable }; }
fn method(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine); const kind: Method = @enumFromInt(raw); const first = h.arg(args, 0); var result = c.pi_js_undefined();
    switch (kind) {
        .hash => result = if (s.truthy(try s.get(receiver, "committish"))) try s.concat(try s.text("#"), try s.stringify(try s.get(receiver, "committish"))) else try s.text(""),
        .getDefaultRepresentation => result = try s.get(receiver, "default"),
        .toString => { if (s.truthy(try s.get(receiver, "default")) and c.JS_IsFunction(engine.context, try getKey(&s, receiver, try s.get(receiver, "default")))) { const function = try getKey(&s, receiver, try s.get(receiver, "default")); result = try s.call(function, receiver, &.{first}); } else result = try s.invoke(receiver, "sshurl", &.{first}); },
        .browse, .browseFile => {
            const rest = try s.array(); if (args.len > 1) for (args[1..], 0..) |value, i| try s.index(rest, @intCast(i), value);
            if (kind == .browse and !c.JS_IsString(first)) { try brand(&s, roots[0], receiver); result = try fill(&s, receiver, try s.get(receiver, "browsetemplate"), first); }
            else { const fragment_is_string = c.JS_IsString(try v.at(&s, rest, 0)); try brand(&s, roots[0], receiver); const template = try s.get(receiver, if (kind == .browse) "browsetreetemplate" else "browseblobtemplate"); const opts = try s.own(try v.js.spread(engine, try v.at(&s, rest, if (fragment_is_string) 1 else 0))); if (fragment_is_string) try data.put(s.engine, opts, "fragment", try v.at(&s, rest, 0)); try data.put(s.engine, opts, "path", first); result = try fill(&s, receiver, template, opts); }
        },
        else => {
            try brand(&s, roots[0], receiver); const template = try s.get(receiver, templateName(kind)); var opts = first;
            if (kind == .tarball) { opts = try s.own(try v.js.spread(engine, first)); try data.put(s.engine, opts, "noCommittish", c.pi_js_bool(engine.context, 0)); }
            if (kind == .file or kind == .edit) { opts = try s.own(try v.js.spread(engine, h.arg(args, 1))); try data.put(s.engine, opts, "path", first); }
            result = try fill(&s, receiver, template, opts);
        },
    }
    return c.JS_DupValue(engine.context, result);
}
fn addHost(s: *Scope, owner: c.JSValue, name: c.JSValue, host: c.JSValue) !void {
    const hosts = try s.get(owner, "hosts"); try setKey(s, hosts, name, host); const domains = try s.get(hosts, "byDomain"); try setKey(s, domains, try s.get(host, "domain"), name); const shortcuts = try s.get(hosts, "byShortcut"); try setKey(s, shortcuts, try s.concat(try s.stringify(name), try s.text(":")), name); const protocols = try s.get(owner, "protocols"); const key = try s.concat(try s.stringify(name), try s.text(":")); const value = try s.object(); try data.put(s.engine, value, "name", name); try setKey(s, protocols, key, value);
}
fn constructSpread(s: *Scope, constructor: c.JSValue, values: c.JSValue) !c.JSValue { var arguments: std.ArrayList(c.JSValue) = .empty; defer arguments.deinit(s.engine.gpa); var iterator = try v.iterator(s, values); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |item| { const value = try s.own(item); try arguments.append(s.engine.gpa, value); } return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, @intCast(arguments.items.len), arguments.items.ptr))); }
fn fromUrl(s: *Scope, owner: c.JSValue, input: c.JSValue, opts: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(input)) return c.pi_js_undefined(); const json = try s.global("JSON"); const stringify = try s.get(json, "stringify"); const key = try s.concat(input, try s.call(stringify, json, &.{if (s.truthy(opts)) opts else try s.object()})); const cache = try s.get(owner, "cache"); const entries = try s.get(cache, "entries"); var size = try cache_ops.count(s, cache);
    if (try cache_ops.find(s, entries, size, key)) |found| return cache_ops.moveLast(s, entries, size, found);
    const host_args = try parser.arguments(s, owner, input, opts); const info = if (s.truthy(host_args)) try constructSpread(s, try s.get(owner, "constructor"), host_args) else c.pi_js_undefined(); size = try cache_ops.count(s, cache);
    if (c.JS_IsUndefined(info)) { if (try cache_ops.find(s, entries, size, key)) |found| try cache_ops.remove(s, cache, entries, size, found); return info; }
    if (try cache_ops.find(s, entries, size, key)) |found| { const row = try v.at(s, entries, found); try data.put(s.engine, row, "value", info); _ = try cache_ops.moveLast(s, entries, size, found); }
    else { const row = try private(s); try data.put(s.engine, row, "key", key); try data.put(s.engine, row, "value", info); if (size == 1000) { _ = try cache_ops.moveLast(s, entries, size, 0); try s.index(entries, size - 1, row); } else { try s.index(entries, size, row); size += 1; try data.put(s.engine, cache, "size", c.JS_NewUint32(s.engine.context, size)); } }
    return cache_ops.moveLast(s, entries, size, (try cache_ops.find(s, entries, size, key)) orelse return error.MissingHostedCacheEntry);
}
fn replace(s: *Scope, value: c.JSValue, pattern: []const u8, replacement: []const u8) !c.JSValue { const method_value = try s.get(value, "replace"); var args = [_]c.JSValue{ try s.text(pattern), try s.text("") }; const regex = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, 2, &args))); return s.call(method_value, value, &.{ regex, try s.text(replacement) }); }
fn unknownInner(s: *Scope, input: c.JSValue) !c.JSValue {
    var args = [_]c.JSValue{input}; const parsed = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, try s.global("URL"), 1, &args))); const protocol = try s.get(parsed, "protocol"); const hostname = try s.get(parsed, "hostname"); const pathname = try s.get(parsed, "pathname"); if (!s.truthy(hostname)) return c.pi_js_null(); var regex_args = [_]c.JSValue{ try s.text("(?:git\\+)http:$"), try s.text("") }; const regex = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, 2, &regex_args))); const proto = try s.text(if (s.truthy(try s.invoke(regex, "test", &.{protocol}))) "http:" else "https:"); const path = try replace(s, pathname, "\\.git$", ""); return s.concat(try s.concat(try s.concat(proto, try s.text("//")), try s.stringify(hostname)), try s.stringify(path));
}
fn unknown(s: *Scope, input: c.JSValue) !c.JSValue { const generation = s.engine.native_allocation_generation; return unknownInner(s, input) catch |err| { try caught.ignore(s.engine, err, generation); return c.pi_js_null(); }; }
fn fromManifest(s: *Scope, owner: c.JSValue, manifest: c.JSValue, opts: c.JSValue) !c.JSValue {
    if (!s.truthy(manifest) or !c.JS_IsObject(manifest) or c.JS_IsFunction(s.engine.context, manifest)) return c.pi_js_undefined(); const repository = try s.get(manifest, "repository"); var url = repository;
    if (s.truthy(repository)) url = if (c.JS_IsString(repository)) repository else if (c.JS_IsObject(repository) and !c.JS_IsFunction(s.engine.context, repository) and c.JS_IsString(try s.get(repository, "url"))) try s.get(repository, "url") else c.pi_js_null(); if (!s.truthy(url)) return v.errorText(s, try s.text("no repository"));
    const constructor = try s.get(owner, "constructor"); const method_value = try s.get(constructor, "fromUrl"); const info = try s.call(method_value, constructor, &.{ try replace(s, url, "^git\\+", ""), opts }); if (s.truthy(info)) return info; const unk = try unknown(s, url); const fallback = try s.invoke(constructor, "fromUrl", &.{ unk, opts }); return if (s.truthy(fallback)) fallback else unk;
}
fn staticMethod(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var kind: i32 = 0; if (c.JS_ToInt32(engine.context, &kind, roots[1]) < 0) return v.js.capture(engine); const owner = roots[0]; const first = h.arg(args, 0); const result = switch (@as(Static, @enumFromInt(kind))) { .addHost => blk: { try addHost(&s, owner, first, h.arg(args, 1)); break :blk c.pi_js_undefined(); }, .fromUrl => try fromUrl(&s, owner, first, h.arg(args, 1)), .fromManifest => try fromManifest(&s, owner, first, if (c.JS_IsUndefined(h.arg(args, 1))) try s.object() else h.arg(args, 1)), .parseUrl => try parser.parseUrl(&s, try s.get(owner, "nodeUrl"), first, c.pi_js_undefined()) }; return c.JS_DupValue(engine.context, result);
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); if (!c.JS_IsObject(inputs.node_url)) return error.RequiredActualNodeUrlModule; const host_values = try s.own(try @import("native_hosted_git_hosts.zig").create(engine)); const owner = try private(&s); const prototype = try s.object(); try data.put(s.engine, owner, "nodeUrl", inputs.node_url); try data.put(s.engine, owner, "brand", try s.own(try engine.checked(c.JS_NewPrivateSymbol(engine.context, "GitHost.#fill")))); try data.put(s.engine, owner, "ordinaryClass", c.JS_NewUint32(engine.context, c.JS_GetClassID(prototype)));
    const hosts = try s.object(); try data.put(s.engine, hosts, "byShortcut", try s.object()); try data.put(s.engine, hosts, "byDomain", try s.object()); try data.put(s.engine, owner, "hosts", hosts); const protocols = try s.object(); inline for (.{ "git+ssh:", "ssh:", "git+https:", "git:", "http:", "https:", "git+http:" }, 0..) |name, i| { const value = try s.object(); if (i < 3) try data.put(s.engine, value, "name", try s.text(if (i < 2) "sshurl" else "https")); if (i >= 2) try data.put(s.engine, value, "auth", c.pi_js_bool(engine.context, 1)); try data.put(s.engine, protocols, name, value); } try data.put(s.engine, owner, "protocols", protocols); const cache = try private(&s); try data.put(s.engine, cache, "entries", try private(&s)); try data.put(s.engine, cache, "size", c.JS_NewInt32(engine.context, 0)); try data.put(s.engine, owner, "cache", cache);
    const constructor = try s.own(try @import("native_hosted_git_class.zig").constructor(engine, "GitHost", 6, prototype, construct, &.{owner})); try data.put(s.engine, owner, "constructor", constructor);
    inline for (@typeInfo(Static).@"enum".fields) |field_value| { const function = try s.own(try f.createMethod(engine, field_value.name, if (field_value.value < 2) 2 else 1, staticMethod, &.{ owner, c.JS_NewInt32(engine.context, field_value.value) })); if (c.JS_DefinePropertyValueStr(engine.context, constructor, field_value.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine); }
    inline for (@typeInfo(Method).@"enum".fields) |field_value| { const kind: Method = @enumFromInt(field_value.value); const length: c_int = switch (kind) { .hash, .getDefaultRepresentation => 0, .file, .edit => 2, else => 1 }; const function = try s.own(try f.createMethod(engine, field_value.name, length, method, &.{ owner, c.JS_NewInt32(engine.context, field_value.value) })); if (c.JS_DefinePropertyValueStr(engine.context, prototype, field_value.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine); }
    const entries = try s.invoke(try s.global("Object"), "entries", &.{host_values}); var iterator = try v.iterator(&s, entries); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |item| { const pair = try s.own(item); const values = try h.parts(&s, pair, 2); const add = try s.get(constructor, "addHost"); _ = try s.call(add, constructor, &.{ try v.at(&s, values, 0), try v.at(&s, values, 1) }); }
    return c.JS_DupValue(engine.context, constructor);
}
