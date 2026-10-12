//! Durable discovery reads only persisted start data. Namespace matching and
//! search documents intentionally follow durable's narrower Source contract.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const vm = @import("native_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const identifiers = @import("../mcp/codemode_discovery.zig");
const search = @import("../mcp/tool_search.zig");
const c = em.c;
fn item(scope: *Scope, array: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, array, @intCast(index))));
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn errorMessage(engine: *em.Engine, message: []const u8) anyerror {
    _ = @import("native_sdk.zig").sourceError(engine, message) catch |err| return err;
    unreachable;
}
fn identifier(scope: *Scope, value: c.JSValue) !c.JSValue {
    const raw = try scope.engine.toString(value);
    defer scope.engine.gpa.free(raw);
    const id = try identifiers.identifier(scope.engine.gpa, raw);
    defer scope.engine.gpa.free(id);
    return scope.text(id);
}
fn matches(scope: *Scope, namespace: c.JSValue, query: c.JSValue) !bool {
    const name = try scope.get(namespace, "name");
    return scope.equal(name, query) or scope.equal(try identifier(scope, name), try identifier(scope, query));
}
fn ownNamespace(scope: *Scope, namespaces: c.JSValue, name: c.JSValue) !c.JSValue {
    for (0..try vm.length(scope.engine, namespaces)) |i| {
        const namespace = try item(scope, namespaces, i);
        if (scope.truthy(try scope.invoke(try scope.get(namespace, "tools"), "includes", &.{name}))) return namespace;
    }
    return c.pi_js_undefined();
}
fn arenaText(scope: *Scope, a: std.mem.Allocator, value: c.JSValue) ![]const u8 {
    const text = try scope.engine.toString(value);
    defer scope.engine.gpa.free(text);
    return a.dupe(u8, text);
}
pub fn isDiscovery(engine: *em.Engine, name: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "searchTools", "describeTool", "describeNamespace" }) |text| if (try is(&scope, name, text)) return true;
    return false;
}
pub fn invoke(engine: *em.Engine, start: c.JSValue, call: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const name = try scope.get(call, "name");
    const given = try scope.get(call, "args");
    const args = if (c.JS_IsArray(given)) given else try scope.array();
    const query = try item(&scope, args, 0);
    const tools = try scope.get(start, "tools");
    const namespaces = try scope.get(start, "namespaces");
    if (try is(&scope, name, "describeTool")) {
        if (!c.JS_IsString(query)) return errorMessage(engine, "describeTool() expects a tool name");
        for (0..try vm.length(engine, tools)) |i| {
            const tool = try item(&scope, tools, i);
            if (scope.truthy(try scope.get(tool, "hidden"))) continue;
            if (scope.equal(try scope.get(tool, "name"), query) or scope.equal(try scope.get(tool, "jsName"), query)) return c.JS_DupValue(engine.context, try scope.get(tool, "description"));
        }
        return c.pi_js_undefined();
    }
    if (try is(&scope, name, "describeNamespace")) {
        if (!c.JS_IsString(query)) return errorMessage(engine, "describeNamespace() expects a namespace name");
        for (0..try vm.length(engine, namespaces)) |i| {
            const namespace = try item(&scope, namespaces, i);
            if (!try matches(&scope, namespace, query)) continue;
            const result = try scope.object();
            try scope.put(result, "name", try scope.get(namespace, "name"));
            inline for (.{ "description", "instructions" }) |key| {
                const value = try scope.get(namespace, key);
                if (!c.JS_IsUndefined(value)) try scope.put(result, key, value);
            }
            const names = try scope.array();
            const members = try scope.get(namespace, "tools");
            for (0..try vm.length(engine, members)) |j| _ = try scope.invoke(names, "push", &.{try identifier(&scope, try item(&scope, members, j))});
            try scope.put(result, "tools", names);
            return c.JS_DupValue(engine.context, result);
        }
        return c.pi_js_undefined();
    }
    if (!c.JS_IsString(query)) return errorMessage(engine, "searchTools() expects a query string");
    const options = try item(&scope, args, 1);
    var limit = c.JS_NewInt32(engine.context, 8);
    var namespace = c.pi_js_undefined();
    if (!c.JS_IsUndefined(options) and !c.JS_IsNull(options)) {
        const supplied = try scope.get(options, "limit");
        if (!c.JS_IsUndefined(supplied) and !c.JS_IsNull(supplied)) limit = supplied;
        namespace = try scope.get(options, "namespace");
    }
    var count: f64 = 0;
    if (!c.JS_IsNumber(limit) or c.JS_ToFloat64(engine.context, &count, limit) < 0 or !std.math.isFinite(count) or @floor(count) != count or count <= 0) return errorMessage(engine, "searchTools() limit must be a positive integer");
    if (!c.JS_IsUndefined(namespace) and !c.JS_IsNull(namespace) and !c.JS_IsString(namespace)) return errorMessage(engine, "searchTools() namespace must be a string");
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var documents: std.ArrayList(search.Document) = .empty;
    for (0..try vm.length(engine, tools)) |i| {
        const tool = try item(&scope, tools, i);
        if (scope.truthy(try scope.get(tool, "hidden"))) continue;
        const raw_name = try scope.get(tool, "name");
        const own = try ownNamespace(&scope, namespaces, raw_name);
        if (c.JS_IsString(namespace) and (c.JS_IsUndefined(own) or !try matches(&scope, own, namespace))) continue;
        const own_name = if (c.JS_IsUndefined(own)) try scope.text("") else try scope.get(own, "name");
        var own_description = if (c.JS_IsUndefined(own)) try scope.text("") else try scope.get(own, "description");
        if (c.JS_IsUndefined(own_description) or c.JS_IsNull(own_description)) own_description = try scope.text("");
        const pieces = try scope.array();
        inline for (.{ raw_name, try scope.invoke(raw_name, "replaceAll", &.{ try scope.text("_"), try scope.text(" ") }), try scope.get(tool, "description"), own_name, own_description }) |part| _ = try scope.invoke(pieces, "push", &.{part});
        try documents.append(a, .{ .name = try arenaText(&scope, a, raw_name), .text = try arenaText(&scope, a, try scope.invoke(pieces, "join", &.{try scope.text(" ")})) });
    }
    const query_text = try arenaText(&scope, a, query);
    const ranked = try search.rank(engine.gpa, query_text, documents.items, @intFromFloat(@min(count, @as(f64, @floatFromInt(documents.items.len)))), .{});
    defer engine.gpa.free(ranked);
    const result = try scope.array();
    for (ranked) |match| for (0..try vm.length(engine, tools)) |i| {
        const tool = try item(&scope, tools, i);
        if (!try is(&scope, try scope.get(tool, "name"), match.name)) continue;
        const entry = try scope.object();
        try scope.put(entry, "name", try scope.get(tool, "jsName"));
        try scope.put(entry, "description", try scope.get(tool, "description"));
        _ = try scope.invoke(result, "push", &.{entry});
        break;
    };
    return c.JS_DupValue(engine.context, result);
}
