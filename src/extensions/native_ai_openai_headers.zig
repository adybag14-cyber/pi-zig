//! Functional OpenAI request headers with honest native runtime diagnostics.
//! The original SDK's Node/JS/Stainless identity is never fabricated here.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn providerRecord(scope: *Scope, sources: []const c.JSValue) !c.JSValue {
    const map = try scope.own(try v.js.builtin(scope.engine, "Map", &.{}));
    for (sources) |source| {
        if (v.nullish(source)) continue;
        var entries = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{source}));
        defer entries.deinit();
        errdefer entries.closePreserving();
        while (try entries.next()) |entry| {
            defer scope.engine.freeValue(entry);
            var row: Scope = .{ .engine = scope.engine };
            defer row.deinit();
            const name = try v.at(&row, entry, 0);
            const value = try v.at(&row, entry, 1);
            const normalized = try row.invoke(name, "toLowerCase", &.{});
            _ = try row.invoke(map, "delete", &.{normalized});
            if (!c.JS_IsNull(value)) _ = try row.invoke(map, "set", &.{ normalized, entry });
        }
    }
    return if (scope.truthy(try scope.get(map, "size"))) scope.invoke(try scope.global("Object"), "fromEntries", &.{try scope.invoke(map, "values", &.{})}) else c.pi_js_undefined();
}
pub fn build(scope: *Scope, model: c.JSValue, options: c.JSValue, api_key: c.JSValue) !c.JSValue {
    return buildPrepared(scope, try prepare(scope, model, try v.optional(scope, options, "headers")), api_key, try v.optional(scope, options, "timeoutMs"));
}
pub fn prepare(scope: *Scope, model: c.JSValue, options_headers: c.JSValue) !c.JSValue {
    const combined = try v.spread(scope, try scope.get(model, "headers"));
    try v.js.spreadInto(scope.engine, combined, options_headers);
    return providerRecord(scope, &.{combined});
}
pub fn buildPrepared(scope: *Scope, overrides: c.JSValue, api_key: c.JSValue, configured_timeout: c.JSValue) !c.JSValue {
    const base = try scope.object();
    try scope.put(base, "accept", try scope.text("application/json"));
    const identity = try std.fmt.allocPrint(scope.engine.gpa, "pi-zig (Zig {s}; QuickJS-NG {s}; {s}; {s})", .{ builtin.zig_version_string, std.mem.span(c.JS_GetVersion()), @tagName(builtin.os.tag), @tagName(builtin.cpu.arch) });
    defer scope.engine.gpa.free(identity);
    try scope.put(base, "user-agent", try scope.text(identity));
    try scope.put(base, "x-pi-runtime", try scope.text("zig"));
    try scope.put(base, "x-pi-runtime-version", try scope.text(builtin.zig_version_string));
    try scope.put(base, "x-pi-engine", try scope.text("quickjs-ng"));
    try scope.put(base, "x-stainless-retry-count", try scope.text("0"));
    // SDK buildHeaders receives inputOptions, before the client's default
    // timeout is merged into the request. Only an explicit option emits this.
    if (scope.truthy(configured_timeout)) try scope.put(base, "x-stainless-timeout", try scope.stringify(try scope.invoke(try scope.global("Math"), "trunc", &.{try @import("native_ai_classifier_values.zig").binary(scope, .divide, configured_timeout, c.JS_NewInt32(scope.engine.context, 1000))})));
    try scope.put(base, "authorization", try scope.concat(try scope.text("Bearer "), try scope.stringify(api_key)));
    const result = try scope.own(try @import("native_headers.zig").fromRecord(scope.engine, base));
    var iterator = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{if (c.JS_IsUndefined(overrides)) try scope.object() else overrides}));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer scope.engine.freeValue(entry);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const value = try v.at(&row, entry, 1);
        if (c.JS_IsUndefined(value)) continue;
        _ = try row.invoke(result, "set", &.{ try v.at(&row, entry, 0), value });
    }
    // The SDK body encoder applies this after defaultHeaders for JSON bodies.
    _ = try scope.invoke(result, "set", &.{ try scope.text("content-type"), try scope.text("application/json") });
    return result;
}
