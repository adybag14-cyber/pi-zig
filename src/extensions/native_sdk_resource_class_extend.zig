//! Ordinary Source DefaultResourceLoader.extendResources over observable fields.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const categories = .{
    .{ "skillPaths", "extensionSkillSourceInfos", "lastSkillPaths", "updateSkillsFromPaths" },
    .{ "promptPaths", "extensionPromptSourceInfos", "lastPromptPaths", "updatePromptsFromPaths" },
    .{ "themePaths", "extensionThemeSourceInfos", "lastThemePaths", "updateThemesFromPaths" },
};
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    const function = try engine.checked(c.pi_js_function_magic(engine.context, dispatch, "extendResources", 1, 0));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "extendResources", function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, loader: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    extend(engine, loader, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn mappedPath(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return sdk.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "path") catch |err| sdk.fail(engine, err);
}
fn sourceInfo(scope: *Scope, path: c.JSValue, metadata: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "path", path);
    inline for (.{ "source", "scope", "origin", "baseDir" }) |field| try scope.put(result, field, try scope.get(metadata, field));
    return result;
}
fn extend(engine: *em.Engine, loader: c.JSValue, input: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var normalized: [3]c.JSValue = undefined;
    inline for (categories, 0..) |category, index| {
        const normalize = try scope.get(loader, "normalizeExtensionPaths");
        const supplied = try scope.get(input, category[0]);
        normalized[index] = try scope.call(normalize, loader, &.{if (temp.nullish(supplied)) try scope.array() else supplied});
    }
    inline for (categories, 0..) |category, index| {
        const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
        var it = try js.Iterator.init(engine, normalized[index], symbol);
        defer it.deinit();
        errdefer it.closePreserving();
        while (try it.next()) |entry| {
            defer engine.freeValue(entry);
            const infos = try scope.get(loader, category[1]);
            const set = try scope.get(infos, "set");
            const path = try scope.get(entry, "path");
            const info = try sourceInfo(&scope, try scope.get(entry, "path"), try scope.get(entry, "metadata"));
            _ = try scope.call(set, infos, &.{ path, info });
        }
    }
    inline for (categories, 0..) |category, index| {
        if (try scope.positive(try scope.get(normalized[index], "length"))) {
            const merge = try scope.get(loader, "mergePaths");
            const previous = try scope.get(loader, category[2]);
            const map = try scope.get(normalized[index], "map");
            const callback = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, mappedPath, "", 1)));
            const additional = try scope.call(map, normalized[index], &.{callback});
            try scope.set(loader, category[2], try scope.call(merge, loader, &.{ previous, additional }));
            const update = try scope.get(loader, category[3]);
            _ = try scope.call(update, loader, &.{ try scope.get(loader, category[2]), try scope.get(loader, "resourceMetadataByPath") });
        }
    }
}
