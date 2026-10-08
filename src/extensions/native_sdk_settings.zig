//! SettingsManager accessors and mutations use live owner-thread values.
const std = @import("std");
const builtin = @import("builtin");
const sdk = @import("native_sdk.zig");
const models = @import("native_sdk_models.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Mode = enum { raw, normal, truthy, array, object, special, set };
const Field = struct { name: [:0]const u8, path: []const u8 = "", mode: Mode = .normal };
const fields = [_]Field{
    .{ .name = "getSettings", .path = "settings", .mode = .special },
    .{ .name = "getGlobalSettings", .path = "global", .mode = .special },
    .{ .name = "getProjectSettings", .path = "project", .mode = .special },
    .{ .name = "getDefaultProvider", .path = "defaultProvider", .mode = .raw },
    .{ .name = "getDefaultModel", .path = "defaultModel", .mode = .raw },
    .{ .name = "getDefaultThinkingLevel", .path = "defaultThinkingLevel", .mode = .raw },
    .{ .name = "getLastChangelogVersion", .path = "lastChangelogVersion", .mode = .raw },
    .{ .name = "getThinkingBudgets", .path = "thinkingBudgets", .mode = .raw },
    .{ .name = "getEnabledModels", .path = "enabledModels", .mode = .raw },
    .{ .name = "getShellCommandPrefix", .path = "shellCommandPrefix", .mode = .raw },
    .{ .name = "getTrackingId", .path = "trackingId", .mode = .raw },
    .{ .name = "getOrCreateDeviceId", .mode = .special },
    .{ .name = "isProjectTrusted", .mode = .special },
    .{ .name = "setProjectTrusted", .mode = .set },
    .{ .name = "setProjectPackages", .path = "packages", .mode = .set },
    .{ .name = "setProjectExtensionPaths", .path = "extensions", .mode = .set },
    .{ .name = "setProjectSkillPaths", .path = "skills", .mode = .set },
    .{ .name = "setProjectPromptTemplatePaths", .path = "prompts", .mode = .set },
    .{ .name = "setProjectThemePaths", .path = "themes", .mode = .set },
    .{ .name = "getTransport", .path = "transport" },
    .{ .name = "getSteeringMode", .path = "steeringMode", .mode = .truthy },
    .{ .name = "getFollowUpMode", .path = "followUpMode", .mode = .truthy },
    .{ .name = "getCompactionEnabled", .path = "compaction.enabled" },
    .{ .name = "getBranchSummarySkipPrompt", .path = "branchSummary.skipPrompt" },
    .{ .name = "getRetryEnabled", .path = "retry.enabled" },
    .{ .name = "getHideThinkingBlock", .path = "hideThinkingBlock" },
    .{ .name = "getShowCacheMissNotices", .path = "showCacheMissNotices" },
    .{ .name = "getCollapseChangelog", .path = "collapseChangelog" },
    .{ .name = "getEnableInstallTelemetry", .path = "enableInstallTelemetry" },
    .{ .name = "getEnableAnalytics", .path = "enableAnalytics" },
    .{ .name = "getEnableSkillCommands", .path = "enableSkillCommands" },
    .{ .name = "getShowImages", .path = "terminal.showImages" },
    .{ .name = "getShowTerminalProgress", .path = "terminal.showTerminalProgress" },
    .{ .name = "getFullscreenCopyOnSelect", .path = "fullscreenCopyOnSelect" },
    .{ .name = "getImageAutoResize", .path = "images.autoResize" },
    .{ .name = "getBlockImages", .path = "images.blockImages" },
    .{ .name = "getDoubleEscapeAction", .path = "doubleEscapeAction" },
    .{ .name = "getEditorPaddingX", .path = "editorPaddingX" },
    .{ .name = "getAutocompleteMaxVisible", .path = "autocompleteMaxVisible" },
    .{ .name = "getCodeBlockIndent", .path = "markdown.codeBlockIndent" },
    .{ .name = "getAllModelThinkingLevels", .path = "modelThinkingLevels", .mode = .object },
    .{ .name = "getWarnings", .path = "warnings", .mode = .object },
    .{ .name = "getPackages", .path = "packages", .mode = .array },
    .{ .name = "getExtensionPaths", .path = "extensions", .mode = .array },
    .{ .name = "getSkillPaths", .path = "skills", .mode = .array },
    .{ .name = "getPromptTemplatePaths", .path = "prompts", .mode = .array },
    .{ .name = "getThemePaths", .path = "themes", .mode = .array },
    .{ .name = "getNpmCommand", .path = "npmCommand", .mode = .special },
    .{ .name = "getThemeSetting", .path = "theme", .mode = .special },
    .{ .name = "getTheme", .path = "theme", .mode = .special },
    .{ .name = "getSessionDir", .path = "sessionDir", .mode = .special },
    .{ .name = "getShellPath", .path = "shellPath", .mode = .special },
    .{ .name = "getHttpIdleTimeoutMs", .path = "httpIdleTimeoutMs", .mode = .special },
    .{ .name = "getWebSocketConnectTimeoutMs", .path = "websocketConnectTimeoutMs", .mode = .special },
    .{ .name = "getCacheWarmingMode", .path = "cacheWarming", .mode = .special },
    .{ .name = "getDefaultProjectTrust", .path = "defaultProjectTrust", .mode = .special },
    .{ .name = "getQuietStartup", .path = "quietStartup", .mode = .special },
    .{ .name = "getTuiMode", .path = "tuiMode", .mode = .special },
    .{ .name = "getFullscreenExitOutput", .path = "fullscreenExitOutput", .mode = .special },
    .{ .name = "getFullscreenScrollbar", .path = "fullscreenScrollbar", .mode = .special },
    .{ .name = "getFullscreenWheelScrollLines", .path = "fullscreenWheelScrollLines", .mode = .special },
    .{ .name = "getImageWidthCells", .path = "terminal.imageWidthCells", .mode = .special },
    .{ .name = "getClearOnShrink", .path = "terminal.clearOnShrink", .mode = .special },
    .{ .name = "getShowHardwareCursor", .path = "showHardwareCursor", .mode = .special },
    .{ .name = "getExternalEditorCommand", .path = "externalEditor", .mode = .special },
    .{ .name = "getOutputPad", .path = "outputPad", .mode = .special },
    .{ .name = "getMermaidRenderingMode", .path = "markdown.mermaid", .mode = .special },
    .{ .name = "getTerminalCapabilityOverrides", .mode = .special },
    .{ .name = "getBranchSummarySettings", .path = "branchSummary", .mode = .special },
    .{ .name = "getRetrySettings", .path = "retry", .mode = .special },
    .{ .name = "getProviderRetrySettings", .path = "retry.provider", .mode = .special },
    .{ .name = "getCompactionSettings", .mode = .special },
    .{ .name = "getCompactionTokenSetting", .mode = .special },
    .{ .name = "getCompactionReserveTokens", .mode = .special },
    .{ .name = "getCompactionKeepRecentTokens", .mode = .special },
    .{ .name = "getModelThinkingLevel", .mode = .special },
    .{ .name = "getDefaultTools", .path = "defaultTools", .mode = .special },
    .{ .name = "setDefaultProvider", .path = "defaultProvider", .mode = .set },
    .{ .name = "setDefaultModel", .path = "defaultModel", .mode = .set },
    .{ .name = "setDefaultModelAndProvider", .mode = .set },
    .{ .name = "setDefaultThinkingLevel", .path = "defaultThinkingLevel", .mode = .set },
    .{ .name = "setLastChangelogVersion", .path = "lastChangelogVersion", .mode = .set },
    .{ .name = "setTransport", .path = "transport", .mode = .set },
    .{ .name = "setSteeringMode", .path = "steeringMode", .mode = .set },
    .{ .name = "setFollowUpMode", .path = "followUpMode", .mode = .set },
    .{ .name = "setTheme", .path = "theme", .mode = .set },
    .{ .name = "setCompactionEnabled", .path = "compaction.enabled", .mode = .set },
    .{ .name = "setRetryEnabled", .path = "retry.enabled", .mode = .set },
    .{ .name = "setHttpIdleTimeoutMs", .path = "httpIdleTimeoutMs", .mode = .set },
    .{ .name = "setCacheWarmingMode", .path = "cacheWarming", .mode = .set },
    .{ .name = "setDefaultProjectTrust", .path = "defaultProjectTrust", .mode = .set },
    .{ .name = "setHideThinkingBlock", .path = "hideThinkingBlock", .mode = .set },
    .{ .name = "setShowCacheMissNotices", .path = "showCacheMissNotices", .mode = .set },
    .{ .name = "setShellPath", .path = "shellPath", .mode = .set },
    .{ .name = "setShellCommandPrefix", .path = "shellCommandPrefix", .mode = .set },
    .{ .name = "setNpmCommand", .path = "npmCommand", .mode = .set },
    .{ .name = "setCollapseChangelog", .path = "collapseChangelog", .mode = .set },
    .{ .name = "setEnableInstallTelemetry", .path = "enableInstallTelemetry", .mode = .set },
    .{ .name = "setEnableAnalytics", .path = "enableAnalytics", .mode = .set },
    .{ .name = "setPackages", .path = "packages", .mode = .set },
    .{ .name = "setExtensionPaths", .path = "extensions", .mode = .set },
    .{ .name = "setSkillPaths", .path = "skills", .mode = .set },
    .{ .name = "setPromptTemplatePaths", .path = "prompts", .mode = .set },
    .{ .name = "setThemePaths", .path = "themes", .mode = .set },
    .{ .name = "setEnableSkillCommands", .path = "enableSkillCommands", .mode = .set },
    .{ .name = "setShowImages", .path = "terminal.showImages", .mode = .set },
    .{ .name = "setImageWidthCells", .path = "terminal.imageWidthCells", .mode = .set },
    .{ .name = "setClearOnShrink", .path = "terminal.clearOnShrink", .mode = .set },
    .{ .name = "setShowTerminalProgress", .path = "terminal.showTerminalProgress", .mode = .set },
    .{ .name = "setTuiMode", .path = "tuiMode", .mode = .set },
    .{ .name = "setFullscreenExitOutput", .path = "fullscreenExitOutput", .mode = .set },
    .{ .name = "setFullscreenScrollbar", .path = "fullscreenScrollbar", .mode = .set },
    .{ .name = "setFullscreenCopyOnSelect", .path = "fullscreenCopyOnSelect", .mode = .set },
    .{ .name = "setFullscreenWheelScrollLines", .path = "fullscreenWheelScrollLines", .mode = .set },
    .{ .name = "setImageAutoResize", .path = "images.autoResize", .mode = .set },
    .{ .name = "setBlockImages", .path = "images.blockImages", .mode = .set },
    .{ .name = "setEnabledModels", .path = "enabledModels", .mode = .set },
    .{ .name = "setDoubleEscapeAction", .path = "doubleEscapeAction", .mode = .set },
    .{ .name = "setTreeFilterMode", .path = "treeFilterMode", .mode = .set },
    .{ .name = "setShowHardwareCursor", .path = "showHardwareCursor", .mode = .set },
    .{ .name = "setEditorPaddingX", .path = "editorPaddingX", .mode = .set },
    .{ .name = "setOutputPad", .path = "outputPad", .mode = .set },
    .{ .name = "setAutocompleteMaxVisible", .path = "autocompleteMaxVisible", .mode = .set },
    .{ .name = "setMermaidRenderingMode", .path = "markdown.mermaid", .mode = .set },
    .{ .name = "setWarnings", .path = "warnings", .mode = .set },
    .{ .name = "setModelThinkingLevel", .mode = .set },
    .{ .name = "removeModelThinkingLevel", .mode = .set },
    .{ .name = "getTreeFilterMode", .path = "treeFilterMode", .mode = .special },
};
pub fn install(engine: *engine_mod.Engine, prototype: c.JSValue) !void {
    for (fields, 0..) |field, index| {
        const value = try engine.checked(c.pi_js_function_magic(engine.context, callback, field.name, if (field.mode == .set) 1 else 0, @intCast(index)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, value, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    }
}
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const owner = sdk.state(engine, receiver) catch |err| return sdk.fail(engine, err);
    return dispatch(engine, owner.data, fields[@intCast(magic)], if (argc > 0) args[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn pathValue(engine: *engine_mod.Engine, root: c.JSValue, path: []const u8) !c.JSValue {
    var result = c.JS_DupValue(engine.context, root);
    errdefer engine.freeValue(result);
    var components = std.mem.splitScalar(u8, path, '.');
    while (components.next()) |component| {
        if (component.len == 0 or c.JS_IsUndefined(result) or c.JS_IsNull(result)) {
            engine.freeValue(result);
            return c.pi_js_undefined();
        }
        const key = try engine.gpa.dupeZ(u8, component);
        defer engine.gpa.free(key);
        const next = try sdk.get(engine, result, key);
        engine.freeValue(result);
        result = next;
    }
    return result;
}
fn assignPath(engine: *engine_mod.Engine, root: c.JSValue, path: []const u8, value: c.JSValue) !void {
    var target = c.JS_DupValue(engine.context, root);
    defer engine.freeValue(target);
    var components = std.mem.splitScalar(u8, path, '.');
    while (components.next()) |component| {
        const key = try engine.gpa.dupeZ(u8, component);
        defer engine.gpa.free(key);
        if (components.peek() == null) return sdk.put(engine, target, key, c.JS_DupValue(engine.context, value));
        var next = try sdk.get(engine, target, key);
        if (c.JS_ToBool(engine.context, next) != 1) {
            engine.freeValue(next);
            next = try sdk.object(engine);
            try sdk.put(engine, target, key, c.JS_DupValue(engine.context, next));
        }
        engine.freeValue(target);
        target = next;
    }
}
fn defaults(engine: *engine_mod.Engine, data: c.JSValue) !c.JSValue {
    const stored = try sdk.get(engine, data, "accessorDefaults");
    if (c.JS_IsObject(stored)) return stored;
    engine.freeValue(stored);
    const value = try sdk.jsonObject(engine, @embedFile("../coding_agent/assets/SDK-SETTINGS-DEFAULTS-6fb2e78.json"));
    errdefer engine.freeValue(value);
    try sdk.put(engine, data, "accessorDefaults", c.JS_DupValue(engine.context, value));
    return value;
}
fn shallow(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try models.copy(engine, result, value);
    return result;
}
pub fn clone(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    var length: usize = 0;
    const bytes = c.JS_WriteObject(engine.context, &length, value, c.JS_WRITE_OBJ_REFERENCE);
    if (bytes == null) {
        const original = c.JS_GetException(engine.context);
        defer engine.freeValue(original);
        const message_value = try sdk.get(engine, original, "message");
        defer engine.freeValue(message_value);
        const message = try engine.toString(message_value);
        defer engine.gpa.free(message);
        const failure = try @import("dom_exception.zig").create(engine, message, "DataCloneError");
        return engine.checked(c.JS_Throw(engine.context, failure));
    }
    defer c.js_free(engine.context, bytes);
    return engine.checked(c.JS_ReadObject(engine.context, bytes, length, c.JS_READ_OBJ_REFERENCE));
}
fn same(engine: *engine_mod.Engine, value: c.JSValue, text: []const u8) !bool {
    const expected = try sdk.text(engine, text);
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, value, expected);
}
fn env(engine: *engine_mod.Engine, name: [*:0]const u8) !c.JSValue {
    const environment = try @import("native_sdk_config_value.zig").processEnv(engine);
    defer engine.freeValue(environment);
    return sdk.get(engine, environment, name);
}
fn uuid(engine: *engine_mod.Engine) !c.JSValue {
    const raw = try @import("../auth/pkce.zig").generateUuidV4(engine.gpa, engine.native_io orelse return error.NativeSDKRequiresIO);
    defer engine.gpa.free(raw);
    return sdk.text(engine, raw);
}
fn normalizePath(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    if (c.JS_ToBool(engine.context, value) != 1) return c.JS_DupValue(engine.context, value);
    const raw = try engine.toString(value);
    defer engine.gpa.free(raw);
    const windows = builtin.os.tag == .windows;
    if (windows and std.mem.startsWith(u8, raw, "/") and !std.mem.startsWith(u8, raw, "//") and std.mem.indexOfScalar(u8, raw, '\\') == null) {
        const body = if (std.mem.startsWith(u8, raw, "/mnt/")) raw[5..] else if (std.mem.startsWith(u8, raw, "/cygdrive/")) raw[10..] else raw[1..];
        if (body.len >= 1 and std.ascii.isAlphabetic(body[0]) and (body.len == 1 or body[1] == '/')) {
            const converted = try std.fmt.allocPrint(engine.gpa, "{c}:\\{s}", .{ std.ascii.toUpper(body[0]), if (body.len > 1) body[2..] else "" });
            defer engine.gpa.free(converted);
            for (converted) |*char| if (char.* == '/') {
                char.* = '\\';
            };
            return sdk.text(engine, converted);
        }
    }
    if (std.mem.eql(u8, raw, "~") or std.mem.startsWith(u8, raw, "~/") or (windows and std.mem.startsWith(u8, raw, "~\\"))) {
        const home = try env(engine, if (windows) "USERPROFILE" else "HOME");
        defer engine.freeValue(home);
        const directory = try engine.toString(home);
        defer engine.gpa.free(directory);
        if (raw.len == 1) return sdk.text(engine, directory);
        const joined = try std.fs.path.resolve(engine.gpa, &.{ directory, raw[2..] });
        defer engine.gpa.free(joined);
        return sdk.text(engine, joined);
    }
    if (std.mem.startsWith(u8, raw, "file://")) {
        const path = try @import("file_urls.zig").toPath(engine.gpa, raw, windows);
        defer engine.gpa.free(path);
        return sdk.text(engine, path);
    }
    return c.JS_DupValue(engine.context, value);
}
fn nullish(value: c.JSValue) bool {
    return c.JS_IsUndefined(value) or c.JS_IsNull(value);
}
fn number(engine: *engine_mod.Engine, value: c.JSValue) !f64 {
    var result: f64 = undefined;
    if (c.JS_ToFloat64(engine.context, &result, value) < 0) return error.JavaScriptException;
    return result;
}
fn failSetting(engine: *engine_mod.Engine, path: []const u8, value: c.JSValue) !c.JSValue {
    const raw = try engine.toString(value);
    defer engine.gpa.free(raw);
    const message = try std.fmt.allocPrint(engine.gpa, "Invalid {s} setting: {s}", .{ path, raw });
    defer engine.gpa.free(message);
    const error_value = try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(error_value);
    try sdk.put(engine, error_value, "message", try sdk.text(engine, message));
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, error_value)));
}
pub fn deepMerge(engine: *engine_mod.Engine, base: c.JSValue, update: c.JSValue, depth: usize) anyerror!c.JSValue {
    if (depth > 64) return error.NativeSDKSettingsDepth;
    const result = try shallow(engine, base);
    errdefer engine.freeValue(result);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, update, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (0..count) |index| {
        const next = try engine.checked(c.JS_GetProperty(engine.context, update, names[index].atom));
        defer engine.freeValue(next);
        if (c.JS_IsUndefined(next)) continue;
        const previous = try engine.checked(c.JS_GetProperty(engine.context, base, names[index].atom));
        defer engine.freeValue(previous);
        const value = if (c.JS_IsObject(previous) and !c.JS_IsArray(previous) and c.JS_IsObject(next) and !c.JS_IsArray(next)) try deepMerge(engine, previous, next, depth + 1) else c.JS_DupValue(engine.context, next);
        if (c.JS_DefinePropertyValue(engine.context, result, names[index].atom, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    if (depth == 0) {
        const inherited = try sdk.get(engine, base, "defaultTools");
        defer engine.freeValue(inherited);
        const changed = try sdk.get(engine, update, "defaultTools");
        defer engine.freeValue(changed);
        if (c.JS_IsArray(inherited) and c.JS_IsArray(changed)) {
            var modifiers = true;
            for (0..try sdk.length(engine, changed)) |index| {
                const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, changed, @intCast(index)));
                defer engine.freeValue(item);
                if (!c.JS_IsString(item)) {
                    modifiers = false;
                    break;
                }
                const text = try engine.toString(item);
                defer engine.gpa.free(text);
                if (text.len == 0 or (text[0] != '+' and text[0] != '-')) {
                    modifiers = false;
                    break;
                }
            }
            if (modifiers) try sdk.put(engine, result, "defaultTools", try sdk.invoke(engine, inherited, "concat", &.{changed}));
        }
    }
    return result;
}
fn save(engine: *engine_mod.Engine, data: c.JSValue) !void {
    try @import("native_sdk_settings_storage.zig").save(engine, data, false);
}
fn setter(engine: *engine_mod.Engine, data: c.JSValue, field: Field, args: []const c.JSValue) !c.JSValue {
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const storage = @import("native_sdk_settings_storage.zig");
    if (std.mem.eql(u8, field.name, "setProjectTrusted")) {
        try storage.setTrusted(engine, data, first);
        return c.pi_js_undefined();
    }
    if (std.mem.startsWith(u8, field.name, "setProject")) {
        try storage.assertTrusted(engine, data);
        const old = try sdk.get(engine, data, "project");
        defer engine.freeValue(old);
        const next = try clone(engine, old);
        defer engine.freeValue(next);
        try assignPath(engine, next, field.path, first);
        try sdk.put(engine, data, "project", try clone(engine, next));
        try storage.mark(engine, data, field.path, true);
        try storage.save(engine, data, true);
        return c.pi_js_undefined();
    }
    const global = try sdk.get(engine, data, "global");
    defer engine.freeValue(global);
    if (std.mem.eql(u8, field.name, "setDefaultModelAndProvider")) {
        try sdk.put(engine, global, "defaultProvider", c.JS_DupValue(engine.context, first));
        try sdk.put(engine, global, "defaultModel", if (args.len > 1) c.JS_DupValue(engine.context, args[1]) else c.pi_js_undefined());
        try storage.mark(engine, data, "defaultProvider", false);
        try storage.mark(engine, data, "defaultModel", false);
    } else if (std.mem.eql(u8, field.name, "setModelThinkingLevel") or std.mem.eql(u8, field.name, "removeModelThinkingLevel")) {
        const p = try engine.toString(first);
        defer engine.gpa.free(p);
        const m = try engine.toString(if (args.len > 1) args[1] else c.pi_js_undefined());
        defer engine.gpa.free(m);
        const key = try std.fmt.allocPrintSentinel(engine.gpa, "{s}/{s}", .{ p, m }, 0);
        defer engine.gpa.free(key);
        var levels = try sdk.get(engine, global, "modelThinkingLevels");
        defer engine.freeValue(levels);
        if (field.name[0] == 'r') {
            if (!c.JS_IsObject(levels)) return c.pi_js_undefined();
            const atom = c.JS_NewAtom(engine.context, key);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DeleteProperty(engine.context, levels, atom, 0) < 0) return error.JavaScriptException;
            var properties: [*c]c.JSPropertyEnum = null;
            var count: u32 = 0;
            if (c.JS_GetOwnPropertyNames(engine.context, &properties, &count, levels, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
            defer c.JS_FreePropertyEnum(engine.context, properties, count);
            if (count == 0) {
                const root_atom = c.JS_NewAtom(engine.context, "modelThinkingLevels");
                defer c.JS_FreeAtom(engine.context, root_atom);
                if (c.JS_DeleteProperty(engine.context, global, root_atom, 0) < 0) return error.JavaScriptException;
            }
        } else {
            if (!c.JS_IsObject(levels)) {
                engine.freeValue(levels);
                levels = try sdk.object(engine);
                try sdk.put(engine, global, "modelThinkingLevels", c.JS_DupValue(engine.context, levels));
            }
            try sdk.put(engine, levels, key, if (args.len > 2) c.JS_DupValue(engine.context, args[2]) else c.pi_js_undefined());
        }
        try storage.mark(engine, data, "modelThinkingLevels", false);
    } else {
        var value = c.JS_DupValue(engine.context, first);
        defer engine.freeValue(value);
        const name = field.name;
        if (std.mem.eql(u8, name, "setHttpIdleTimeoutMs")) {
            const n = try number(engine, first);
            if (!c.JS_IsNumber(first) or !std.math.isFinite(n) or n < 0) return failSetting(engine, field.path, first);
            engine.freeValue(value);
            value = c.JS_NewFloat64(engine.context, @floor(n));
        } else if (std.mem.eql(u8, name, "setEditorPaddingX") or std.mem.eql(u8, name, "setAutocompleteMaxVisible") or std.mem.eql(u8, name, "setImageWidthCells") or (std.mem.eql(u8, name, "setFullscreenWheelScrollLines") and !try same(engine, first, "auto"))) {
            const n = @floor(try number(engine, first));
            const min: f64 = if (std.mem.eql(u8, name, "setEditorPaddingX")) 0 else if (std.mem.eql(u8, name, "setAutocompleteMaxVisible")) 3 else 1;
            const max: f64 = if (std.mem.eql(u8, name, "setEditorPaddingX")) 3 else if (std.mem.eql(u8, name, "setAutocompleteMaxVisible")) 20 else if (std.mem.eql(u8, name, "setFullscreenWheelScrollLines")) 100 else std.math.inf(f64);
            engine.freeValue(value);
            value = c.JS_NewFloat64(engine.context, if (std.math.isNan(n)) n else @max(min, @min(max, n)));
        } else if (std.mem.eql(u8, name, "setWarnings")) {
            engine.freeValue(value);
            value = try shallow(engine, first);
        } else if (std.mem.eql(u8, name, "setNpmCommand") and c.JS_ToBool(engine.context, first) == 1) {
            engine.freeValue(value);
            value = try sdk.invoke(engine, first, "slice", &.{});
        }
        try assignPath(engine, global, field.path, value);
        try storage.mark(engine, data, field.path, false);
        if (std.mem.eql(u8, name, "setEnableAnalytics") and c.JS_ToBool(engine.context, first) == 1) {
            const tracking = try sdk.get(engine, global, "trackingId");
            defer engine.freeValue(tracking);
            if (c.JS_ToBool(engine.context, tracking) != 1) {
                try sdk.put(engine, global, "trackingId", try uuid(engine));
                try storage.mark(engine, data, "trackingId", false);
            }
        }
    }
    try save(engine, data);
    return c.pi_js_undefined();
}
fn dispatch(engine: *engine_mod.Engine, data: c.JSValue, field: Field, args: []const c.JSValue) !c.JSValue {
    if (field.mode == .set) return setter(engine, data, field, args);
    const root = try sdk.get(engine, data, if (std.mem.eql(u8, field.name, "getCacheWarmingMode") or std.mem.eql(u8, field.name, "getDefaultProjectTrust")) "global" else "settings");
    defer engine.freeValue(root);
    const raw = if (field.path.len > 0) try pathValue(engine, root, field.path) else c.pi_js_undefined();
    defer engine.freeValue(raw);
    if (field.mode == .raw) return c.JS_DupValue(engine.context, raw);
    if (field.mode == .object) return shallow(engine, raw);
    if (field.mode == .array) return if (nullish(raw)) sdk.array(engine) else sdk.invoke(engine, raw, "slice", &.{});
    const base = try defaults(engine, data);
    defer engine.freeValue(base);
    const default = if (field.path.len > 0) try pathValue(engine, base, field.path) else c.pi_js_undefined();
    defer engine.freeValue(default);
    if (field.mode == .normal or field.mode == .truthy) return c.JS_DupValue(engine.context, if (if (field.mode == .truthy) c.JS_ToBool(engine.context, raw) == 1 else !nullish(raw)) raw else default);
    return special(engine, data, root, field, args, raw, default);
}
fn special(engine: *engine_mod.Engine, data: c.JSValue, root: c.JSValue, field: Field, args: []const c.JSValue, raw: c.JSValue, default: c.JSValue) !c.JSValue {
    const name = field.name;
    if (std.mem.eql(u8, name, "getOrCreateDeviceId")) {
        const global = try sdk.get(engine, data, "global");
        defer engine.freeValue(global);
        var id = try sdk.get(engine, global, "deviceId");
        errdefer engine.freeValue(id);
        if (c.JS_ToBool(engine.context, id) != 1) {
            const created = try uuid(engine);
            engine.freeValue(id);
            id = created;
            try sdk.put(engine, global, "deviceId", c.JS_DupValue(engine.context, id));
            try @import("native_sdk_settings_storage.zig").mark(engine, data, "deviceId", false);
            try save(engine, data);
        }
        return id;
    }
    if (std.mem.eql(u8, name, "isProjectTrusted")) return sdk.get(engine, data, "projectTrusted");
    if (std.mem.eql(u8, name, "getSettings") or std.mem.eql(u8, name, "getGlobalSettings") or std.mem.eql(u8, name, "getProjectSettings")) {
        const key = try engine.gpa.dupeZ(u8, field.path);
        defer engine.gpa.free(key);
        const target = try sdk.get(engine, data, key);
        defer engine.freeValue(target);
        return clone(engine, target);
    }
    if (std.mem.eql(u8, name, "getThemeSetting") or std.mem.eql(u8, name, "getTheme")) {
        if (!c.JS_IsString(raw)) return c.pi_js_undefined();
        const text = try engine.toString(raw);
        defer engine.gpa.free(text);
        return if (std.mem.eql(u8, name, "getTheme") and std.mem.indexOfScalar(u8, text, '/') != null) c.pi_js_undefined() else c.JS_DupValue(engine.context, raw);
    }
    if (std.mem.eql(u8, name, "getNpmCommand")) return if (c.JS_ToBool(engine.context, raw) == 1) sdk.invoke(engine, raw, "slice", &.{}) else c.pi_js_undefined();
    if (std.mem.eql(u8, name, "getSessionDir") or std.mem.eql(u8, name, "getShellPath")) return normalizePath(engine, raw);
    if (std.mem.eql(u8, name, "getHttpIdleTimeoutMs") or std.mem.eql(u8, name, "getWebSocketConnectTimeoutMs")) {
        if (c.JS_IsUndefined(raw)) return if (std.mem.eql(u8, name, "getHttpIdleTimeoutMs")) c.JS_NewInt32(engine.context, 300000) else c.pi_js_undefined();
        if (c.JS_IsString(raw)) {
            const text = try engine.toString(raw);
            defer engine.gpa.free(text);
            if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, text, " \t\r\n"), "disabled")) return c.JS_NewInt32(engine.context, 0);
            if (std.mem.trim(u8, text, " \t\r\n").len == 0) return failSetting(engine, field.path, raw);
        } else if (!c.JS_IsNumber(raw)) return failSetting(engine, field.path, raw);
        const n = try number(engine, raw);
        if (!std.math.isFinite(n) or n < 0) return failSetting(engine, field.path, raw);
        return c.JS_NewFloat64(engine.context, @floor(n));
    }
    if (std.mem.eql(u8, name, "getOutputPad")) return c.JS_NewInt32(engine.context, if (c.JS_IsNumber(raw) and try number(engine, raw) == 0) 0 else 1);
    if (std.mem.eql(u8, name, "getImageWidthCells") or std.mem.eql(u8, name, "getFullscreenWheelScrollLines")) {
        if (!c.JS_IsNumber(raw)) return c.JS_DupValue(engine.context, default);
        const n = try number(engine, raw);
        if (!std.math.isFinite(n)) return c.JS_DupValue(engine.context, default);
        return c.JS_NewFloat64(engine.context, @max(1, @min(if (std.mem.eql(u8, name, "getImageWidthCells")) std.math.inf(f64) else 100, @floor(n))));
    }
    if (std.mem.eql(u8, name, "getClearOnShrink") or std.mem.eql(u8, name, "getShowHardwareCursor")) {
        if (if (std.mem.eql(u8, name, "getClearOnShrink")) !c.JS_IsUndefined(raw) else !nullish(raw)) return c.JS_DupValue(engine.context, raw);
        const value = try env(engine, if (std.mem.eql(u8, name, "getClearOnShrink")) "PI_CLEAR_ON_SHRINK" else "PI_HARDWARE_CURSOR");
        defer engine.freeValue(value);
        return c.pi_js_bool(engine.context, @intFromBool(try same(engine, value, "1")));
    }
    if (std.mem.eql(u8, name, "getExternalEditorCommand")) {
        if (c.JS_IsString(raw)) {
            const text = try engine.toString(raw);
            defer engine.gpa.free(text);
            if (std.mem.trim(u8, text, " \t\r\n").len > 0) return c.JS_DupValue(engine.context, raw);
        }
        inline for (.{ "VISUAL", "EDITOR" }) |key| {
            const value = try env(engine, key);
            if (c.JS_ToBool(engine.context, value) == 1) return value;
            engine.freeValue(value);
        }
        return sdk.text(engine, if (builtin.os.tag == .windows) "notepad" else "nano");
    }
    if (std.mem.eql(u8, name, "getQuietStartup")) return c.JS_DupValue(engine.context, if ((c.JS_IsBool(raw) and c.JS_ToBool(engine.context, raw) == 1) or try same(engine, raw, "header")) raw else default);
    inline for (.{ .{ "getCacheWarmingMode", "off", "streaming", "idle" }, .{ "getDefaultProjectTrust", "always", "never", "ask" }, .{ "getTuiMode", "regular", "fullscreen", "fullscreen" }, .{ "getFullscreenExitOutput", "resume-hint", "transcript", "transcript" }, .{ "getFullscreenScrollbar", "always", "hidden", "auto" }, .{ "getMermaidRenderingMode", "off", "final", "streaming" } }) |rule| {
        if (std.mem.eql(u8, name, rule[0])) return c.JS_DupValue(engine.context, if (try same(engine, raw, rule[1]) or try same(engine, raw, rule[2]) or try same(engine, raw, rule[3])) raw else default);
    }
    if (std.mem.eql(u8, name, "getTreeFilterMode")) {
        inline for (.{ "default", "no-tools", "user-only", "labeled-only", "all" }) |mode| if (try same(engine, raw, mode)) return c.JS_DupValue(engine.context, raw);
        return c.JS_DupValue(engine.context, default);
    }
    if (std.mem.eql(u8, name, "getRetrySettings") or std.mem.eql(u8, name, "getBranchSummarySettings") or std.mem.eql(u8, name, "getProviderRetrySettings")) {
        const result = try sdk.object(engine);
        errdefer engine.freeValue(result);
        const keys: []const [:0]const u8 = if (std.mem.eql(u8, name, "getRetrySettings")) &.{ "enabled", "maxRetries", "baseDelayMs", "maxAgentDelayMs" } else if (std.mem.eql(u8, name, "getProviderRetrySettings")) &.{ "timeoutMs", "maxRetries", "maxRetryDelayMs" } else &.{ "reserveTokens", "skipPrompt" };
        for (keys) |key| {
            const value = if (c.JS_IsObject(raw)) try sdk.get(engine, raw, key) else c.pi_js_undefined();
            defer engine.freeValue(value);
            try sdk.put(engine, result, key, if (nullish(value)) if (c.JS_IsObject(default)) try sdk.get(engine, default, key) else c.pi_js_undefined() else c.JS_DupValue(engine.context, value));
        }
        return result;
    }
    if (std.mem.eql(u8, name, "getTerminalCapabilityOverrides")) {
        const result = try sdk.object(engine);
        errdefer engine.freeValue(result);
        const images = try pathValue(engine, root, "terminal.images");
        defer engine.freeValue(images);
        if (try same(engine, images, "kitty") or try same(engine, images, "iterm2")) try sdk.put(engine, result, "images", c.JS_DupValue(engine.context, images)) else if (c.JS_IsBool(images) and c.JS_ToBool(engine.context, images) == 0) try sdk.put(engine, result, "images", c.pi_js_null());
        inline for (.{ "trueColor", "hyperlinks" }) |key| {
            const value = try pathValue(engine, root, "terminal." ++ key);
            defer engine.freeValue(value);
            if (c.JS_IsBool(value)) try sdk.put(engine, result, key, c.JS_DupValue(engine.context, value));
        }
        return result;
    }
    if (std.mem.eql(u8, name, "getModelThinkingLevel")) {
        const p = try engine.toString(if (args.len > 0) args[0] else c.pi_js_undefined());
        defer engine.gpa.free(p);
        const m = try engine.toString(if (args.len > 1) args[1] else c.pi_js_undefined());
        defer engine.gpa.free(m);
        const key = try std.fmt.allocPrintSentinel(engine.gpa, "{s}/{s}", .{ p, m }, 0);
        defer engine.gpa.free(key);
        const levels = try sdk.get(engine, root, "modelThinkingLevels");
        defer engine.freeValue(levels);
        return if (nullish(levels)) c.pi_js_undefined() else sdk.get(engine, levels, key);
    }
    if (std.mem.startsWith(u8, name, "getCompaction")) return compaction(engine, root, name, args);
    if (std.mem.eql(u8, name, "getDefaultTools")) return defaultTools(engine, raw);
    return error.NativeSDKSettingsMethodUnavailable;
}
fn compaction(engine: *engine_mod.Engine, root: c.JSValue, name: []const u8, args: []const c.JSValue) !c.JSValue {
    if (std.mem.eql(u8, name, "getCompactionSettings")) {
        const result = try sdk.object(engine);
        errdefer engine.freeValue(result);
        const enabled = try pathValue(engine, root, "compaction.enabled");
        defer engine.freeValue(enabled);
        try sdk.put(engine, result, "enabled", if (nullish(enabled)) c.pi_js_bool(engine.context, 1) else c.JS_DupValue(engine.context, enabled));
        try sdk.put(engine, result, "reserveTokens", try tokenSetting(engine, root, "reserveTokens", if (args.len > 0) args[0] else c.pi_js_undefined()));
        try sdk.put(engine, result, "keepRecentTokens", try tokenSetting(engine, root, "keepRecentTokens", if (args.len > 0) args[0] else c.pi_js_undefined()));
        return result;
    }
    if (std.mem.eql(u8, name, "getCompactionTokenSetting")) {
        const key = try engine.toString(if (args.len > 0) args[0] else c.pi_js_undefined());
        defer engine.gpa.free(key);
        return tokenSetting(engine, root, key, if (args.len > 1) args[1] else c.pi_js_undefined());
    }
    return tokenSetting(engine, root, if (std.mem.eql(u8, name, "getCompactionReserveTokens")) "reserveTokens" else "keepRecentTokens", if (args.len > 0) args[0] else c.pi_js_undefined());
}
fn tokenFailure(engine: *engine_mod.Engine, label: []const u8, value: c.JSValue, object: bool) !c.JSValue {
    const raw = try engine.toString(value);
    defer engine.gpa.free(raw);
    const message = try std.fmt.allocPrint(engine.gpa, "Invalid {s} setting: {s}. Expected {s}.", .{ label, raw, if (object) "an object" else "a non-negative safe integer" });
    defer engine.gpa.free(message);
    const failure = try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(failure);
    try sdk.put(engine, failure, "message", try sdk.text(engine, message));
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, failure)));
}
fn tokenSetting(engine: *engine_mod.Engine, root: c.JSValue, key: []const u8, model: c.JSValue) !c.JSValue {
    const path = try std.fmt.allocPrint(engine.gpa, "compaction.{s}", .{key});
    defer engine.gpa.free(path);
    const ordinary = try pathValue(engine, root, path);
    defer engine.freeValue(ordinary);
    if (!c.JS_IsUndefined(ordinary)) {
        const n = try number(engine, ordinary);
        if (!c.JS_IsNumber(ordinary) or !std.math.isFinite(n) or @floor(n) != n or n < 0 or n > 9007199254740991) return tokenFailure(engine, path, ordinary, false);
    }
    var override = c.pi_js_undefined();
    defer engine.freeValue(override);
    if (c.JS_ToBool(engine.context, model) == 1) {
        const provider = try sdk.get(engine, model, "provider");
        defer engine.freeValue(provider);
        const id = try sdk.get(engine, model, "id");
        defer engine.freeValue(id);
        const p = try engine.toString(provider);
        defer engine.gpa.free(p);
        const m = try engine.toString(id);
        defer engine.gpa.free(m);
        const model_key = try std.fmt.allocPrintSentinel(engine.gpa, "{s}/{s}", .{ p, m }, 0);
        defer engine.gpa.free(model_key);
        const overrides = try pathValue(engine, root, "compaction.modelOverrides");
        defer engine.freeValue(overrides);
        const entry = if (!nullish(overrides)) try sdk.get(engine, overrides, model_key) else c.pi_js_undefined();
        defer engine.freeValue(entry);
        if (!c.JS_IsUndefined(entry)) {
            const label = try std.fmt.allocPrint(engine.gpa, "compaction.modelOverrides[\"{s}\"]", .{model_key});
            defer engine.gpa.free(label);
            if (!c.JS_IsObject(entry) or c.JS_IsArray(entry)) return tokenFailure(engine, label, entry, true);
            const terminated = try engine.gpa.dupeZ(u8, key);
            defer engine.gpa.free(terminated);
            override = try sdk.get(engine, entry, terminated);
            if (!c.JS_IsUndefined(override)) {
                const n = try number(engine, override);
                if (!c.JS_IsNumber(override) or !std.math.isFinite(n) or @floor(n) != n or n < 0 or n > 9007199254740991) {
                    const full = try std.fmt.allocPrint(engine.gpa, "{s}.{s}", .{ label, key });
                    defer engine.gpa.free(full);
                    return tokenFailure(engine, full, override, false);
                }
            }
        }
    }
    if (!nullish(override)) return c.JS_DupValue(engine.context, override);
    if (!nullish(ordinary)) return c.JS_DupValue(engine.context, ordinary);
    return if (std.mem.eql(u8, key, "reserveTokens")) c.JS_NewInt32(engine.context, 16384) else if (std.mem.eql(u8, key, "keepRecentTokens")) c.JS_NewInt32(engine.context, 20000) else c.pi_js_undefined();
}
fn defaultTools(engine: *engine_mod.Engine, raw: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(raw)) return c.pi_js_undefined();
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    if (!c.JS_IsArray(raw)) return result;
    var modifiers = false;
    for (0..try sdk.length(engine, raw)) |index| {
        const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, raw, @intCast(index)));
        defer engine.freeValue(value);
        if (!c.JS_IsString(value)) continue;
        const text = try engine.toString(value);
        defer engine.gpa.free(text);
        if (text.len > 0 and (text[0] == '+' or text[0] == '-')) modifiers = true else try sdk.append(engine, result, c.JS_DupValue(engine.context, value));
    }
    if (try sdk.length(engine, result) == 0 and modifiers) inline for (.{ "read", "bash", "edit", "write" }) |name| try sdk.append(engine, result, try sdk.text(engine, name));
    for (0..try sdk.length(engine, raw)) |index| {
        const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, raw, @intCast(index)));
        defer engine.freeValue(value);
        if (!c.JS_IsString(value)) continue;
        const text = try engine.toString(value);
        defer engine.gpa.free(text);
        if (text.len == 0 or (text[0] != '+' and text[0] != '-')) continue;
        const name = try sdk.text(engine, text[1..]);
        defer engine.freeValue(name);
        const found = try sdk.invoke(engine, result, "indexOf", &.{name});
        defer engine.freeValue(found);
        const position = try number(engine, found);
        if (text[0] == '+' and position == -1 and text.len > 1) try sdk.append(engine, result, c.JS_DupValue(engine.context, name)) else if (text[0] == '-' and position >= 0) {
            const removed = try sdk.invoke(engine, result, "splice", &.{ found, c.JS_NewInt32(engine.context, 1) });
            engine.freeValue(removed);
        }
    }
    return result;
}
