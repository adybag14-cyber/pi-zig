//! Original SettingsManager default-bearing accessors over the one genuine
//! shared SETTINGS_DEFAULTS import. No per-instance parser or eager fallback.
const std = @import("std");
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const Engine = h.Engine;
const Scope = h.Scope;
const sync = @import("native_sync_arguments.zig");
const Frame = @import("native_public_lexical_frame.zig").Frame(enum {
    value, valid, compaction, ordinary, model_key, entry, override,
});
const sdk = @import("native_sdk.zig");
const cache_key = "pi-private:actual-sdk-settings-accessor-imports";
const Creating = struct { engine: *Engine, previous: ?*Creating };
threadlocal var creating: ?*Creating = null;

pub const Kind = enum {
    getSteeringMode, getFollowUpMode, getTransport, getSessionShareDestination,
    getCompactionEnabled, getCompactionTokenSetting, getCompactionReserveTokens,
    getCompactionKeepRecentTokens, getCompactionSettings,
    getBranchSummarySettings, getBranchSummarySkipPrompt, getRetryEnabled,
    getRetrySettings, getCacheWarmingMode, getProviderRetrySettings,
    getHideThinkingBlock, getShowCacheMissNotices, getQuietStartup,
    getDefaultProjectTrust, getCollapseChangelog, getEnableInstallTelemetry,
    getEnableAnalytics, getEnableSkillCommands, getShowImages, getImageWidthCells,
    getClearOnShrink, getShowTerminalProgress, getTuiMode, getFullscreenExitOutput,
    getFullscreenScrollbar, getFullscreenCopyOnSelect, getFullscreenWheelScrollLines,
    getImageAutoResize, getBlockImages, getDoubleEscapeAction, getTreeFilterMode,
    getEditorPaddingX, getOutputPad, getAutocompleteMaxVisible,
    getCodeBlockIndent, getMermaidRenderingMode,
};

/// Actual settings-manager module evaluation: the mutable exported mode array
/// is created first, then the two private compaction defaults are read once.
/// The original shared defaults object remains live for every later fallback.
pub fn acquire(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    var cursor = creating;
    while (cursor) |current| : (cursor = current.previous)
        if (current.engine == engine) return error.ActualSettingsAccessorImportsCreationReentry;
    var entry: Creating = .{ .engine = engine, .previous = creating };
    creating = &entry; defer creating = entry.previous;
    const candidate = try h.expression(engine, importsBody, .{});
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var selected = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        selected.release(candidate); return selected.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, candidate);
    return h.duplicate(engine, candidate);
}
fn importsBody(s: *Scope) !c.JSValue {
    const defaults = try v.own(s, try @import("native_sdk_settings_defaults.zig").create(s.engine));
    const modes = try v.array(s);
    inline for (.{ "off", "streaming", "idle" }, 0..) |mode, index|
        try v.index(s, modes, @intCast(index), try v.text(s, mode));
    const tokens = try v.object(s);
    try v.put(s, tokens, "reserveTokens", try v.own(s, try h.nested(s.engine, defaults, "compaction", "reserveTokens")));
    try v.put(s, tokens, "keepRecentTokens", try v.own(s, try h.nested(s.engine, defaults, "compaction", "keepRecentTokens")));
    const result = try v.stateObject(s);
    try v.put(s, result, "defaults", defaults);
    try v.put(s, result, "compactionDefaults", tokens);
    try v.put(s, result, "cacheWarmingModes", modes);
    return v.duplicate(s, result);
}
/// The actual retained export value for a later complete settings-manager module
/// publisher. This does not publish a stand-in or partial module namespace.
pub fn cacheWarmingModes(engine: *Engine) !c.JSValue {
    const imports = try acquire(engine);
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, cacheModesBody(&s, imports));
}
fn cacheModesBody(s: *Scope, incoming: c.JSValue) !c.JSValue {
    const imports = try v.own(s, incoming);
    return v.duplicate(s, try v.get(s, imports, "cacheWarmingModes"));
}
pub fn supports(name: []const u8) bool {
    return std.meta.stringToEnum(Kind, name) != null;
}
pub fn method(engine: *Engine, name: []const u8, imports: c.JSValue) !c.JSValue {
    inline for (std.meta.tags(Kind)) |kind| {
        if (std.mem.eql(u8, name, @tagName(kind))) return h.expression(engine, methodBody, .{ kind, imports });
    }
    return error.ActualSettingsDefaultAccessorRequired;
}
fn arity(comptime kind: Kind) comptime_int {
    return switch (kind) {
        .getCompactionTokenSetting => 2,
        .getCompactionReserveTokens, .getCompactionKeepRecentTokens, .getCompactionSettings => 1,
        else => 0,
    };
}
fn methodBody(s: *Scope, comptime kind: Kind, imports: c.JSValue) !c.JSValue {
    const roots = [_]c.JSValue{
        try v.get(s, imports, "defaults"), try v.get(s, imports, "compactionDefaults"),
        try v.get(s, imports, "cacheWarmingModes"),
    };
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return v.duplicate(s, try boundary.finishValue(s, v.function.createMethodWithArguments(
        s.engine, @tagName(kind), arity(kind), .{
            .formal_count = arity(kind), .callback = callback(kind), .hooks = sync.frameHooks(Frame),
        }, &roots)));
}
fn callback(comptime kind: Kind) sync.Callback {
    return struct {
        fn call(engine: *Engine, receiver: c.JSValue, arguments: *sync.Arguments, roots: []const c.JSValue) anyerror!c.JSValue {
            var s: Scope = .{ .engine = engine };
            return v.owned.finishValue(&s, accessorBody(&s, kind, receiver, arguments, roots));
        }
    }.call;
}
fn ownedFieldBody(s: *Scope, incoming: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const receiver = try v.own(s, incoming);
    return v.duplicate(s, try v.get(s, receiver, name));
}
fn sourcePath(s: *Scope, data: c.JSValue, root_name: [*:0]const u8, path: []const [:0]const u8, optional: bool) !c.JSValue {
    var current = try h.get(s.engine, data, root_name);
    for (path, 0..) |part, index| {
        if (index != 0 and optional and v.nullish(current)) {
            s.engine.freeValue(current); // Only null or undefined.
            return c.pi_js_undefined();
        }
        // Each ordinary field operation consumes its receiver before the next
        // source Get, including a sole holder returned by a hostile getter.
        current = try h.expression(s.engine, ownedFieldBody, .{ current, @as([*:0]const u8, part) });
    }
    return current;
}
fn defaultsPath(s: *Scope, defaults: c.JSValue, path: []const [:0]const u8) !c.JSValue {
    var current = v.duplicate(s, defaults);
    for (path) |part|
        current = try h.expression(s.engine, ownedFieldBody, .{ current, @as([*:0]const u8, part) });
    return current;
}
fn readPath(engine: *Engine, data: c.JSValue, root_name: [*:0]const u8, path: []const [:0]const u8, optional: bool) !c.JSValue {
    return h.expression(engine, sourcePath, .{ data, root_name, path, optional });
}
fn fallbackBody(s: *Scope, data: c.JSValue, defaults: c.JSValue, path: []const [:0]const u8, use_truthiness: bool) !c.JSValue {
    const value = try v.own(s, try readPath(s.engine, data, "settings", path, true));
    if (if (use_truthiness) v.truthy(s, value) else !v.nullish(value)) return v.duplicate(s, value);
    return defaultsPath(s, defaults, path);
}
fn simplePath(comptime kind: Kind) ?[]const [:0]const u8 {
    return switch (kind) {
        .getSteeringMode => &.{"steeringMode"}, .getFollowUpMode => &.{"followUpMode"},
        .getTransport => &.{"transport"}, .getCompactionEnabled => &.{ "compaction", "enabled" },
        .getBranchSummarySkipPrompt => &.{ "branchSummary", "skipPrompt" },
        .getRetryEnabled => &.{ "retry", "enabled" },
        .getHideThinkingBlock => &.{"hideThinkingBlock"}, .getShowCacheMissNotices => &.{"showCacheMissNotices"},
        .getCollapseChangelog => &.{"collapseChangelog"}, .getEnableInstallTelemetry => &.{"enableInstallTelemetry"},
        .getEnableAnalytics => &.{"enableAnalytics"}, .getEnableSkillCommands => &.{"enableSkillCommands"},
        .getShowImages => &.{ "terminal", "showImages" }, .getShowTerminalProgress => &.{ "terminal", "showTerminalProgress" },
        .getFullscreenCopyOnSelect => &.{"fullscreenCopyOnSelect"},
        .getImageAutoResize => &.{ "images", "autoResize" }, .getBlockImages => &.{ "images", "blockImages" },
        .getDoubleEscapeAction => &.{"doubleEscapeAction"}, .getEditorPaddingX => &.{"editorPaddingX"},
        .getAutocompleteMaxVisible => &.{"autocompleteMaxVisible"}, .getCodeBlockIndent => &.{ "markdown", "codeBlockIndent" },
        else => null,
    };
}
fn localPath(comptime kind: Kind) []const [:0]const u8 {
    return switch (kind) {
        .getSessionShareDestination => &.{"sessionShareDestination"},
        .getCacheWarmingMode => &.{"cacheWarming"}, .getQuietStartup => &.{"quietStartup"},
        .getDefaultProjectTrust => &.{"defaultProjectTrust"}, .getImageWidthCells => &.{ "terminal", "imageWidthCells" },
        .getFullscreenScrollbar => &.{"fullscreenScrollbar"},
        .getFullscreenWheelScrollLines => &.{"fullscreenWheelScrollLines"},
        .getTreeFilterMode => &.{"treeFilterMode"}, .getMermaidRenderingMode => &.{ "markdown", "mermaid" },
        else => unreachable,
    };
}
fn invokeBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const function = try v.get(s, receiver, name);
    return v.duplicate(s, try v.call(s, function, receiver, args));
}
fn globalInvokeBody(s: *Scope, name: [*:0]const u8, method_name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return invokeBody(s, try v.global(s, name), method_name, args);
}
fn isFiniteBody(s: *Scope, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsNumber(value)) return v.boolean(s, false);
    return v.boolean(s, v.truthy(s, try v.own(s, try h.expression(s.engine, globalInvokeBody,
        .{ @as([*:0]const u8, "Number"), @as([*:0]const u8, "isFinite"), @as([]const c.JSValue, &.{value}) }))));
}
fn minBody(s: *Scope, value: c.JSValue) !c.JSValue {
    const owner = try v.global(s, "Math");
    const function = try v.get(s, owner, "min");
    const floor = try v.own(s, try h.expression(s.engine, globalInvokeBody,
        .{ @as([*:0]const u8, "Math"), @as([*:0]const u8, "floor"), @as([]const c.JSValue, &.{value}) }));
    return v.duplicate(s, try v.call(s, function, owner, &.{ v.number(s, 100), floor }));
}
fn mathBody(s: *Scope, value: c.JSValue, bounded: bool) !c.JSValue {
    // Capture the outer callee before evaluating its nested original argument.
    const owner = try v.global(s, "Math");
    const function = try v.get(s, owner, "max");
    const inner = try v.own(s, if (bounded) try h.expression(s.engine, minBody, .{value}) else
        try h.expression(s.engine, globalInvokeBody,
            .{ @as([*:0]const u8, "Math"), @as([*:0]const u8, "floor"), @as([]const c.JSValue, &.{value}) }));
    return v.duplicate(s, try v.call(s, function, owner, &.{ v.number(s, 1), inner }));
}
fn includesBody(s: *Scope, array: c.JSValue, value: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.own(s, try h.expression(s.engine, invokeBody,
        .{ array, @as([*:0]const u8, "includes"), @as([]const c.JSValue, &.{value}) }))));
}
fn validModesBody(s: *Scope) !c.JSValue {
    const array = try v.array(s);
    inline for (.{ "default", "no-tools", "user-only", "labeled-only", "all" }, 0..) |value, index|
        try v.index(s, array, @intCast(index), try v.text(s, value));
    return v.duplicate(s, array);
}
fn validated(s: *Scope, comptime kind: Kind, data: c.JSValue, arguments: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    const frame = try arguments.createFrame(s, Frame);
    const path = comptime localPath(kind);
    try frame.take(.value, readPath(s.engine, data,
        if (kind == .getCacheWarmingMode or kind == .getDefaultProjectTrust) "global" else "settings", path, true));
    const value = frame.get(.value);
    const accepted = switch (kind) {
        .getSessionShareDestination => try v.eq(s, value, "gist") or try v.eq(s, value, "radius"),
        .getQuietStartup => v.equal(s, value, v.boolean(s, true)) or try v.eq(s, value, "header"),
        .getDefaultProjectTrust => try v.eq(s, value, "always") or try v.eq(s, value, "never"),
        .getFullscreenScrollbar => try v.eq(s, value, "always") or try v.eq(s, value, "hidden"),
        .getMermaidRenderingMode => try v.eq(s, value, "off") or try v.eq(s, value, "final"),
        .getCacheWarmingMode => !c.JS_IsUndefined(value) and h.truthy(s.engine, try h.expression(s.engine, includesBody, .{ roots[2], value })),
        .getTreeFilterMode => block: {
            try frame.take(.valid, h.expression(s.engine, validModesBody, .{}));
            break :block v.truthy(s, value) and h.truthy(s.engine, try h.expression(s.engine, includesBody, .{ frame.get(.valid), value }));
        },
        .getImageWidthCells, .getFullscreenWheelScrollLines => h.truthy(s.engine, try h.expression(s.engine, isFiniteBody, .{value})),
        else => unreachable,
    };
    if (!accepted) return defaultsPath(s, roots[0], path);
    if (kind == .getImageWidthCells or kind == .getFullscreenWheelScrollLines)
        return h.expression(s.engine, mathBody, .{ value, kind == .getFullscreenWheelScrollLines });
    return v.duplicate(s, value);
}

fn comparePathBody(s: *Scope, data: c.JSValue, path: []const [:0]const u8, expected: c.JSValue) !c.JSValue {
    const value = try v.own(s, try readPath(s.engine, data, "settings", path, true));
    return v.boolean(s, v.equal(s, value, expected));
}
fn definedClearBody(s: *Scope, data: c.JSValue) !c.JSValue {
    const value = try v.own(s, try readPath(s.engine, data, "settings", &.{ "terminal", "clearOnShrink" }, true));
    return v.boolean(s, !c.JS_IsUndefined(value));
}
fn clearEnvironmentBody(s: *Scope) !c.JSValue {
    const process = try h.expression(s.engine, globalValueBody, .{@as([*:0]const u8, "process")});
    const environment = try h.expression(s.engine, ownedFieldBody, .{ process, @as([*:0]const u8, "env") });
    const value = try v.own(s, try h.expression(s.engine, ownedFieldBody,
        .{ environment, @as([*:0]const u8, "PI_CLEAR_ON_SHRINK") }));
    return v.boolean(s, try v.eq(s, value, "1"));
}
fn globalValueBody(s: *Scope, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.global(s, name));
}
fn literalChoice(s: *Scope, comptime kind: Kind, data: c.JSValue, defaults: c.JSValue) !c.JSValue {
    const path: []const [:0]const u8 = switch (kind) {
        .getTuiMode => &.{"tuiMode"}, .getFullscreenExitOutput => &.{"fullscreenExitOutput"},
        .getOutputPad => &.{"outputPad"}, else => unreachable,
    };
    const expected = switch (kind) {
        .getTuiMode => try v.text(s, "regular"), .getFullscreenExitOutput => try v.text(s, "resume-hint"),
        .getOutputPad => v.number(s, 0), else => unreachable,
    };
    // This comparison consumes its temporary before the fallback Get. These
    // three original methods have no local binding retaining the compared value.
    if (h.truthy(s.engine, try h.expression(s.engine, comparePathBody, .{ data, path, expected })))
        return v.duplicate(s, expected);
    return defaultsPath(s, defaults, path);
}
fn compound(s: *Scope, comptime kind: Kind, receiver: c.JSValue, data: c.JSValue, defaults: c.JSValue, model: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    switch (kind) {
        .getBranchSummarySettings => {
            inline for (.{ "reserveTokens", "skipPrompt" }) |name|
                try v.put(s, result, name, try v.own(s, try h.expression(s.engine, fallbackBody,
                    .{ data, defaults, @as([]const [:0]const u8, &.{ "branchSummary", name }), false })));
        },
        .getRetrySettings => {
            try v.put(s, result, "enabled", try v.own(s, try v.invokeOwned(s.engine, receiver, "getRetryEnabled", &.{})));
            inline for (.{ "maxRetries", "baseDelayMs", "maxAgentDelayMs" }) |name|
                try v.put(s, result, name, try v.own(s, try h.expression(s.engine, fallbackBody,
                    .{ data, defaults, @as([]const [:0]const u8, &.{ "retry", name }), false })));
        },
        .getProviderRetrySettings => {
            inline for (.{ "timeoutMs", "maxRetries" }) |name|
                try v.put(s, result, name, try v.own(s, try readPath(s.engine, data, "settings", &.{ "retry", "provider", name }, true)));
            try v.put(s, result, "maxRetryDelayMs", try v.own(s, try h.expression(s.engine, fallbackBody,
                .{ data, defaults, @as([]const [:0]const u8, &.{ "retry", "provider", "maxRetryDelayMs" }), false })));
        },
        .getCompactionSettings => {
            try v.put(s, result, "enabled", try v.own(s, try v.invokeOwned(s.engine, receiver, "getCompactionEnabled", &.{})));
            try v.put(s, result, "reserveTokens", try v.own(s, try v.invokeOwned(s.engine, receiver, "getCompactionReserveTokens", &.{model})));
            try v.put(s, result, "keepRecentTokens", try v.own(s, try v.invokeOwned(s.engine, receiver, "getCompactionKeepRecentTokens", &.{model})));
        },
        else => unreachable,
    }
    return v.duplicate(s, result);
}
fn primitiveFieldBody(s: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, try v.get(s, object, name)));
}
fn modelKeyBody(s: *Scope, model: c.JSValue) !c.JSValue {
    const provider = try v.own(s, try h.expression(s.engine, primitiveFieldBody, .{ model, @as([*:0]const u8, "provider") }));
    const prefix = try h.binary(s, .add, provider, try v.text(s, "/"));
    const id = try v.own(s, try h.expression(s.engine, primitiveFieldBody, .{ model, @as([*:0]const u8, "id") }));
    return v.duplicate(s, try h.binary(s, .add, prefix, id));
}
fn optionalKeyBody(s: *Scope, object: c.JSValue, key: c.JSValue) !c.JSValue {
    if (v.nullish(object)) return c.pi_js_undefined();
    return v.duplicate(s, try v.key(s, object, key));
}
fn entryBody(s: *Scope, compaction: c.JSValue, model_key: c.JSValue) !c.JSValue {
    if (v.nullish(compaction)) return c.pi_js_undefined();
    const overrides = try v.get(s, compaction, "modelOverrides");
    if (v.nullish(overrides)) return c.pi_js_undefined();
    return v.duplicate(s, try v.key(s, overrides, model_key));
}
fn globalPredicateBody(s: *Scope, name: [*:0]const u8, method_name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const result = try v.own(s, try h.expression(s.engine, globalInvokeBody,
        .{ name, method_name, @as([]const c.JSValue, &.{value}) }));
    return v.boolean(s, v.truthy(s, result));
}
fn validIntegerBody(s: *Scope, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsNumber(value)) return v.boolean(s, false);
    if (!h.truthy(s.engine, try h.expression(s.engine, globalPredicateBody,
        .{ @as([*:0]const u8, "Number"), @as([*:0]const u8, "isSafeInteger"), value })))
        return v.boolean(s, false);
    return v.boolean(s, !v.truthy(s, try h.binary(s, .less, value, v.number(s, 0))));
}
fn mergeableBody(s: *Scope, value: c.JSValue) !c.JSValue {
    // Original typeof value === "object" also admits non-callable proxies,
    // but excludes functions even though the C VM regards them as objects.
    if (!c.JS_IsObject(value) or c.JS_IsFunction(s.engine.context, value)) return v.boolean(s, false);
    return v.boolean(s, !h.truthy(s.engine, try h.expression(s.engine, globalPredicateBody,
        .{ @as([*:0]const u8, "Array"), @as([*:0]const u8, "isArray"), value })));
}
fn globalStringBody(s: *Scope, value: c.JSValue) !c.JSValue {
    const function = try v.global(s, "String");
    return v.duplicate(s, try v.stringify(s, try v.call(s, function, c.pi_js_undefined(), &.{value})));
}
const TokenFailure = enum { ordinary, entry, override };
fn failureMessage(s: *Scope, which: TokenFailure, field: c.JSValue, model_key: c.JSValue, value: c.JSValue) !c.JSValue {
    var message = try v.text(s, if (which == .ordinary) "Invalid compaction." else "Invalid compaction.modelOverrides[\"");
    if (which == .ordinary) {
        message = try h.binary(s, .add, message, try v.stringify(s, field));
    } else {
        message = try h.binary(s, .add, message, try v.stringify(s, model_key));
        message = try h.binary(s, .add, message, try v.text(s, "\"]"));
        if (which == .override) {
            message = try h.binary(s, .add, message, try v.text(s, "."));
            message = try h.binary(s, .add, message, try v.stringify(s, field));
        }
    }
    message = try h.binary(s, .add, message, try v.text(s, " setting: "));
    const displayed = try v.own(s, try h.expression(s.engine, globalStringBody, .{value}));
    message = try h.binary(s, .add, message, displayed);
    return v.duplicate(s, try h.binary(s, .add, message, try v.text(s,
        if (which == .entry) ". Expected an object." else ". Expected a non-negative safe integer.")));
}
fn raise(s: *Scope, reason: c.JSValue) anyerror {
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    boundary.begin() catch |err| return err;
    _ = boundary.finishValue(s, c.JS_Throw(s.engine.context, v.duplicate(s, reason))) catch |err| return err;
    unreachable;
}
fn errorValueBody(s: *Scope, which: TokenFailure, field: c.JSValue, model_key: c.JSValue, value: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Error");
    const message = try v.own(s, try h.expression(s.engine, failureMessage, .{ which, field, model_key, value }));
    return v.duplicate(s, try v.construct(s, constructor, &.{message}));
}
fn tokenError(s: *Scope, which: TokenFailure, field: c.JSValue, model_key: c.JSValue, value: c.JSValue) !c.JSValue {
    const reason = try v.own(s, try h.expression(s.engine, errorValueBody, .{ which, field, model_key, value }));
    return raise(s, reason);
}
fn tokensBody(s: *Scope, data: c.JSValue, arguments: *sync.Arguments, defaults: c.JSValue) !c.JSValue {
    const frame = try arguments.createFrame(s, Frame);
    const field = arguments.get(0);
    const model = arguments.get(1);
    try frame.take(.compaction, readPath(s.engine, data, "settings", &.{"compaction"}, false));
    try frame.take(.ordinary, h.expression(s.engine, optionalKeyBody, .{ frame.get(.compaction), field }));
    if (!c.JS_IsUndefined(frame.get(.ordinary)) and
        !h.truthy(s.engine, try h.expression(s.engine, validIntegerBody, .{frame.get(.ordinary)})))
        return tokenError(s, .ordinary, field, c.pi_js_undefined(), frame.get(.ordinary));
    try frame.take(.model_key, if (v.truthy(s, model)) h.expression(s.engine, modelKeyBody, .{model}) else c.pi_js_undefined());
    try frame.take(.entry, if (!c.JS_IsUndefined(frame.get(.model_key)))
        h.expression(s.engine, entryBody, .{ frame.get(.compaction), frame.get(.model_key) }) else c.pi_js_undefined());
    if (!c.JS_IsUndefined(frame.get(.entry)) and
        !h.truthy(s.engine, try h.expression(s.engine, mergeableBody, .{frame.get(.entry)})))
        return tokenError(s, .entry, field, frame.get(.model_key), frame.get(.entry));
    try frame.take(.override, h.expression(s.engine, optionalKeyBody, .{ frame.get(.entry), field }));
    if (!c.JS_IsUndefined(frame.get(.override)) and
        !h.truthy(s.engine, try h.expression(s.engine, validIntegerBody, .{frame.get(.override)})))
        return tokenError(s, .override, field, frame.get(.model_key), frame.get(.override));
    if (!v.nullish(frame.get(.override))) return v.duplicate(s, frame.get(.override));
    if (!v.nullish(frame.get(.ordinary))) return v.duplicate(s, frame.get(.ordinary));
    return v.duplicate(s, try v.key(s, defaults, field));
}
fn accessorBody(s: *Scope, comptime kind: Kind, receiver: c.JSValue, arguments: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    // Preserve the existing genuine native SettingsManager storage authority.
    // Its actual C argument owner retains receiver; duplicate backing data before
    // any observable field lookup can reenter the host.
    const owner = try sdk.state(s.engine, receiver);
    const data = try v.own(s, v.duplicate(s, owner.data));
    const simple = comptime simplePath(kind);
    if (simple) |path|
        return fallbackBody(s, data, roots[0], path, kind == .getSteeringMode or kind == .getFollowUpMode);
    return switch (kind) {
        .getSessionShareDestination, .getCacheWarmingMode, .getQuietStartup,
        .getDefaultProjectTrust, .getImageWidthCells, .getFullscreenScrollbar,
        .getFullscreenWheelScrollLines, .getTreeFilterMode, .getMermaidRenderingMode =>
            validated(s, kind, data, arguments, roots),
        .getTuiMode, .getFullscreenExitOutput, .getOutputPad => literalChoice(s, kind, data, roots[0]),
        .getClearOnShrink => block: {
            if (h.truthy(s.engine, try h.expression(s.engine, definedClearBody, .{data})))
                break :block readPath(s.engine, data, "settings", &.{ "terminal", "clearOnShrink" }, false);
            if (h.truthy(s.engine, try h.expression(s.engine, clearEnvironmentBody, .{})))
                break :block v.boolean(s, true);
            break :block defaultsPath(s, roots[0], &.{ "terminal", "clearOnShrink" });
        },
        .getBranchSummarySettings, .getRetrySettings, .getProviderRetrySettings, .getCompactionSettings =>
            compound(s, kind, receiver, data, roots[0], arguments.get(0)),
        .getCompactionTokenSetting => tokensBody(s, data, arguments, roots[1]),
        .getCompactionReserveTokens, .getCompactionKeepRecentTokens => block: {
            const function = try v.get(s, receiver, "getCompactionTokenSetting");
            const field = try v.text(s, if (kind == .getCompactionReserveTokens) "reserveTokens" else "keepRecentTokens");
            break :block v.duplicate(s, try v.call(s, function, receiver, &.{ field, arguments.get(0) }));
        },
        else => unreachable,
    };
}
