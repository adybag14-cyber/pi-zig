//! Original package identity, dedupe and project autoload-delta bodies. Parsing
//! and package storage remain real dynamic class dependencies, never aliases.
const data = @import("native_sdk_package_data.zig");
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Method = enum(c_int) { getPackageSourceString, getPackageIdentity, dedupePackages, findAutoloadDeltaBase };
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    inline for (std.meta.fields(Method)) |field| {
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) {
            .getPackageSourceString, .dedupePackages => 1,
            .getPackageIdentity => 2,
            .findAutoloadDeltaBase => 3,
        };
        const function = try engine.checked(c.pi_js_function_magic(engine.context, dispatch, field.name, length, field.value));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn dispatch(context: ?*c.JSContext, manager: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return method(engine, manager, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn objectType(engine: *em.Engine, value: c.JSValue) bool {
    return c.JS_IsNull(value) or (c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value));
}
fn identity(scope: *Scope, manager: c.JSValue, source: c.JSValue, selected_scope: c.JSValue) !c.JSValue {
    const parsed = try scope.invoke(manager, "parseSource", &.{source});
    if (scope.equal(try scope.get(parsed, "type"), try scope.text("npm"))) return scope.concat(try scope.text("npm:"), try scope.stringify(try scope.get(parsed, "name")));
    if (scope.equal(try scope.get(parsed, "type"), try scope.text("git"))) {
        const prefix = try scope.concat(try scope.concat(try scope.text("git:"), try scope.stringify(try scope.get(parsed, "host"))), try scope.text("/"));
        return scope.concat(prefix, try scope.stringify(try scope.get(parsed, "path")));
    }
    var resolved: c.JSValue = undefined;
    if (scope.truthy(selected_scope)) {
        const base = try scope.invoke(manager, "getBaseDirForScope", &.{selected_scope});
        const resolve = try scope.get(manager, "resolvePathFromBase");
        resolved = try scope.call(resolve, manager, &.{ try scope.get(parsed, "path"), base });
    } else {
        const resolve = try scope.get(manager, "resolvePath");
        resolved = try scope.call(resolve, manager, &.{try scope.get(parsed, "path")});
    }
    return scope.concat(try scope.text("local:"), try scope.stringify(resolved));
}
fn entryIdentity(scope: *Scope, manager: c.JSValue, entry: c.JSValue, selected_scope: ?c.JSValue) !c.JSValue {
    const get_identity = try scope.get(manager, "getPackageIdentity");
    const get_source = try scope.get(manager, "getPackageSourceString");
    const source = try scope.call(get_source, manager, &.{try scope.get(entry, "pkg")});
    return scope.call(get_identity, manager, &.{ source, selected_scope orelse try scope.get(entry, "scope") });
}
fn dedupe(scope: *Scope, manager: c.JSValue, packages: c.JSValue) !c.JSValue {
    const result = try scope.array();
    const seen = try scope.own(try js.builtin(scope.engine, "Map", &.{}));
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, packages, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer scope.engine.freeValue(entry);
        const key = try entryIdentity(scope, manager, entry, null);
        const index = try scope.invoke(seen, "get", &.{key});
        if (c.JS_IsUndefined(index)) {
            const set = try scope.get(seen, "set");
            _ = try scope.call(set, seen, &.{ key, try scope.get(result, "length") });
            _ = try scope.invoke(result, "push", &.{entry});
            continue;
        }
        const existing = try scope.own(try js.getKey(scope.engine, result, index));
        const existing_scope = if (temp.nullish(existing)) c.pi_js_undefined() else try scope.get(existing, "scope");
        if (scope.equal(existing_scope, try scope.text("project")) and scope.equal(try scope.get(entry, "scope"), try scope.text("user"))) {
            if (objectType(scope.engine, try scope.get(existing, "pkg")) and scope.equal(try scope.get(try scope.get(existing, "pkg"), "autoload"), c.pi_js_bool(scope.engine.context, 0))) _ = try scope.invoke(result, "push", &.{entry});
        } else if (scope.equal(try scope.get(entry, "scope"), try scope.text("project"))) {
            const atom = try js.atom(scope.engine, index);
            defer c.JS_FreeAtom(scope.engine.context, atom);
            if (c.JS_SetProperty(scope.engine.context, result, atom, c.JS_DupValue(scope.engine.context, entry)) < 0) return js.capture(scope.engine);
        }
    }
    return result;
}
fn find(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return matches(engine, roots[0], roots[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn matches(engine: *em.Engine, manager: c.JSValue, key: c.JSValue, entry: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const user = try scope.text("user");
    const equal = scope.equal(try scope.get(entry, "scope"), user) and scope.equal(try entryIdentity(&scope, manager, entry, user), key);
    return c.pi_js_bool(engine.context, @intFromBool(equal));
}
fn delta(scope: *Scope, manager: c.JSValue, package: c.JSValue, selected_scope: c.JSValue, sources: c.JSValue) !c.JSValue {
    if (!scope.equal(selected_scope, try scope.text("project")) or !objectType(scope.engine, package) or !scope.equal(try scope.get(package, "autoload"), c.pi_js_bool(scope.engine.context, 0))) return c.pi_js_undefined();
    const get_identity = try scope.get(manager, "getPackageIdentity");
    const key = try scope.call(get_identity, manager, &.{ try scope.get(package, "source"), selected_scope });
    const find_method = try scope.get(sources, "find");
    var roots = [_]c.JSValue{ manager, key };
    const predicate = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, find, "", 1, 0, roots.len, &roots)));
    const user = try scope.call(find_method, sources, &.{predicate});
    if (!scope.truthy(user)) return c.pi_js_undefined();
    const result = try scope.object();
    const get_source = try scope.get(manager, "getPackageSourceString");
    try data.put(scope.engine, result, "source", try scope.call(get_source, manager, &.{try scope.get(user, "pkg")}));
    try data.put(scope.engine, result, "scope", try scope.text("user"));
    return result;
}
fn method(engine: *em.Engine, manager: c.JSValue, kind: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = argument(args, 0);
    const result = switch (kind) {
        .getPackageSourceString => if (c.JS_IsString(first)) first else try scope.get(first, "source"),
        .getPackageIdentity => try identity(&scope, manager, first, argument(args, 1)),
        .dedupePackages => try dedupe(&scope, manager, first),
        .findAutoloadDeltaBase => try delta(&scope, manager, first, argument(args, 1), argument(args, 2)),
    };
    return c.JS_DupValue(engine.context, result);
}
