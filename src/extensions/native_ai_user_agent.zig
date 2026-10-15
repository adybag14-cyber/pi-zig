//! Source getPiUserAgent over a captured actual OS module; no synthetic Node identity.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn load(scope: *Scope) !c.JSValue {
    const process = try scope.global("process");
    const versions = try v.optional(scope, process, "versions");
    if (c.JS_IsUndefined(process) or !(scope.truthy(try v.optional(scope, versions, "node")) or scope.truthy(try v.optional(scope, versions, "bun")))) return c.pi_js_null();
    const loader = try scope.get(process, "getBuiltinModule");
    if (v.nullish(loader)) return c.pi_js_null();
    const os = try scope.call(loader, process, &.{try scope.text("node:os")});
    return if (v.nullish(os)) c.pi_js_null() else os;
}
pub fn value(scope: *Scope, os: c.JSValue) !c.JSValue {
    if (!scope.truthy(os)) return scope.text("pi (browser)");
    var result = try scope.concat(try scope.text("pi ("), try scope.stringify(try scope.invoke(os, "platform", &.{})));
    result = try scope.concat(try scope.concat(result, try scope.text(" ")), try scope.stringify(try scope.invoke(os, "release", &.{})));
    result = try scope.concat(try scope.concat(result, try scope.text("; ")), try scope.stringify(try scope.invoke(os, "arch", &.{})));
    return scope.concat(result, try scope.text(")"));
}
