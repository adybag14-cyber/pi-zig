//! Pinned beta.messages.create parameter transformation and wire-only fields.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
fn rest(scope: *Scope, input: c.JSValue, comptime excluded: []const [*:0]const u8) !c.JSValue {
    const boxed = try scope.own(try scope.engine.checked(c.JS_ToObject(scope.engine.context, input)));
    const result = try scope.object();
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(scope.engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return v.js.capture(scope.engine);
    defer c.JS_FreePropertyEnum(scope.engine.context, names, count);
    var atoms: [excluded.len]c.JSAtom = undefined;
    var initialized: usize = 0;
    defer for (atoms[0..initialized]) |atom| c.JS_FreeAtom(scope.engine.context, atom);
    inline for (excluded) |key| {
        const atom = c.JS_NewAtom(scope.engine.context, key);
        if (atom == c.JS_ATOM_NULL) return v.js.capture(scope.engine);
        atoms[initialized] = atom;
        initialized += 1;
    }
    for (names[0..count]) |entry| {
        var skip = false;
        for (atoms) |atom| if (atom == entry.atom) {
            skip = true;
            break;
        };
        if (skip) continue;
        var descriptor: c.JSPropertyDescriptor = undefined;
        const found = c.JS_GetOwnProperty(scope.engine.context, &descriptor, boxed, entry.atom);
        if (found < 0) return v.js.capture(scope.engine);
        if (found == 0) continue;
        defer scope.engine.freeValue(descriptor.value);
        defer scope.engine.freeValue(descriptor.getter);
        defer scope.engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try scope.engine.checked(c.JS_GetProperty(scope.engine.context, boxed, entry.atom));
        if (c.JS_DefinePropertyValue(scope.engine.context, result, entry.atom, value, c.JS_PROP_C_W_E) < 0) return v.js.capture(scope.engine);
    }
    return result;
}
fn transform(scope: *Scope, params: c.JSValue, errors: c.JSValue) !c.JSValue {
    if (!scope.truthy(try scope.get(params, "output_format"))) return params;
    if (scope.truthy(try v.optional(scope, try scope.get(params, "output_config"), "format"))) {
        const constructor = try scope.get(errors, "AnthropicError");
        var args = [_]c.JSValue{try scope.text("Both output_format and output_config.format were provided. Please use only output_config.format (output_format is deprecated).")};
        const failure = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 1, &args)));
        return scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, failure)));
    }
    const format = try scope.get(params, "output_format");
    const result = try rest(scope, params, &.{"output_format"});
    const config = try v.spread(scope, try scope.get(params, "output_config"));
    try scope.put(config, "format", format);
    try scope.put(result, "output_config", config);
    return result;
}
pub fn prepare(scope: *Scope, params: c.JSValue, errors: c.JSValue) !c.JSValue {
    const modified = try transform(scope, params, errors);
    const betas = try scope.get(modified, "betas");
    const user_profile = try scope.get(modified, "user_profile_id");
    const workspace = try scope.get(modified, "workspace_id");
    const body = try rest(scope, modified, &.{ "betas", "user_profile_id", "workspace_id" });
    const headers = try scope.object();
    if (!v.nullish(betas)) {
        if (!v.nullish(try scope.invoke(betas, "toString", &.{}))) try scope.put(headers, "anthropic-beta", try scope.invoke(betas, "toString", &.{}));
    }
    if (!v.nullish(user_profile)) try scope.put(headers, "anthropic-user-profile-id", user_profile);
    if (!v.nullish(workspace)) try scope.put(headers, "anthropic-workspace-id", workspace);
    const result = try scope.object();
    try scope.put(result, "body", body);
    try scope.put(result, "headers", headers);
    return result;
}
