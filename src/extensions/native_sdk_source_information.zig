//! Actual core/source-info.ts exports. Synthetic here means a Source path such
//! as builtin:read or <inline:name>, with the original metadata semantics.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const Method = enum(c_int) { getSyntheticPathSource, isSyntheticPath, createSourceInfo, createSyntheticSourceInfo };
pub fn create(engine: *v.em.Engine) !c.JSValue {
    const module_name = "pi-native:source-information";
    if (engine.native_module_values.get(module_name)) |value| return c.JS_DupValue(engine.context, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    try scope.put(result, "BUILTIN_PATH_PREFIX", try scope.text("builtin:"));
    inline for (@typeInfo(Method).@"enum".fields) |field| try scope.put(result, field.name, try scope.own(try @import("native_node_function.zig").create(engine, field.name, if (field.value <= 1) 1 else 2, callback, &.{c.JS_NewInt32(engine.context, field.value)})));
    try engine.registerValueModule(module_name, result);
    return c.JS_DupValue(engine.context, result);
}
fn callback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, roots[0]) < 0) return v.js.capture(engine);
    const operation: Method = @enumFromInt(raw);
    const path = if (args.len > 0) args[0] else c.pi_js_undefined();
    const options = if (args.len > 1) args[1] else c.pi_js_undefined();
    switch (operation) {
        .getSyntheticPathSource => {
            if (scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("builtin:")}))) return c.JS_DupValue(engine.context, try scope.text("builtin"));
            if (scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("<")})) and scope.truthy(try scope.invoke(path, "endsWith", &.{try scope.text(">")}))) {
                const split = try scope.invoke(try scope.invoke(path, "slice", &.{ c.JS_NewInt32(engine.context, 1), c.JS_NewInt32(engine.context, -1) }), "split", &.{try scope.text(":")});
                const source = try v.at(&scope, split, 0);
                return c.JS_DupValue(engine.context, if (scope.truthy(source)) source else try scope.text("temporary"));
            }
            return c.pi_js_undefined();
        },
        .isSyntheticPath => return c.pi_js_bool(engine.context, @intFromBool(scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("builtin:")})) or scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("<")})))),
        .createSourceInfo, .createSyntheticSourceInfo => {
            const result = try scope.object();
            try scope.put(result, "path", path);
            try scope.put(result, "source", try scope.get(options, "source"));
            const selected_scope = try scope.get(options, "scope");
            try scope.put(result, "scope", if (operation == .createSyntheticSourceInfo and v.nullish(selected_scope)) try scope.text("temporary") else selected_scope);
            const origin = try scope.get(options, "origin");
            try scope.put(result, "origin", if (operation == .createSyntheticSourceInfo and v.nullish(origin)) try scope.text("top-level") else origin);
            try scope.put(result, "baseDir", try scope.get(options, "baseDir"));
            return c.JS_DupValue(engine.context, result);
        },
    }
}
