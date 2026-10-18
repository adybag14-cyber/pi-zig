//! Public c268 Theme helpers with the original native Theme/proxy identity.
//! One retained complete191 syntax bundle owns eager code, lazy registration,
//! Source import completion, and the separate actual-factory readiness channel.
const v = @import("native_public_values.zig");
const highlight = @import("native_sdk_themed_highlight.zig");
const complete = @import("native_syntax_highlight_complete191.zig");
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const cache_key = highlight.public_owner_key;

pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    var invocation: Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const result = createOwned(engine) catch |err|
        return engine.checked(engine.leaveNativeInvocation(&invocation, @import("native_sdk.zig").fail(engine, err)));
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn createOwned(engine: *Engine) !c.JSValue {
    if (engine.native_module_values.get(cache_key)) |cached| return exportsOwned(engine, cached);
    var s: Scope = .{ .engine = engine };
    const owner = try v.owned.finishValue(&s, createBody(&s));
    // All staging scopes and original Bundle roots have retired before this
    // owner can become visible through the private application cache.
    if (engine.native_module_values.get(cache_key)) |reentrant| {
        var completion = v.owned.Completion.initValue(engine, exportsOwned(engine, reentrant));
        completion.release(owner);
        return completion.finishValue();
    }
    const exports = exportsOwned(engine, owner) catch |err| {
        var completion = v.owned.Completion.initValue(engine, err);
        completion.release(owner);
        return completion.finishValue();
    };
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = v.owned.Completion.initValue(engine, err);
        completion.release(exports);
        completion.release(owner);
        return completion.finishValue();
    };
    // Transfer the actual owned graph. No allocation, guest call, root free, or
    // immutable C-module registration remains after this single commit point.
    engine.native_module_values.putAssumeCapacity(cache_key, owner);
    return exports;
}
fn exportsOwned(engine: *Engine, owner: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    const result: anyerror!c.JSValue = if (v.get(&s, owner, "exports")) |exports| v.duplicate(&s, exports) else |err| err;
    return v.owned.finishValue(&s, result);
}
fn createBody(s: *Scope) !c.JSValue {
    // Application composition installs this genuine actor before linking public
    // owners. Reusing it keeps Theme.moduleState and every existing proxy live.
    const runtime = s.engine.native_module_values.get("pi-coding-agent") orelse return error.NativeThemeModuleUnavailable;
    const bundle = try complete.create(s.engine);
    var completion = v.owned.Completion.initValue(s.engine, withBundle(s, runtime, bundle));
    completion.release(bundle.eager.core);
    completion.release(bundle.eager.syntax);
    completion.release(bundle.eager.factories);
    completion.release(bundle.syntax);
    completion.release(bundle.load);
    completion.release(bundle.readiness);
    completion.release(bundle.import_function);
    return completion.finishValue();
}
fn withBundle(s: *Scope, runtime: c.JSValue, bundle: complete.Bundle) !c.JSValue {
    const owner = try v.stateObject(s);
    try v.put(s, owner, "runtime", runtime);
    try v.put(s, owner, "core", bundle.eager.core);
    try v.put(s, owner, "eagerSyntax", bundle.eager.syntax);
    try v.put(s, owner, "factories", bundle.eager.factories);
    try v.put(s, owner, "syntax", bundle.syntax);
    try v.put(s, owner, "loadAllHighlightLanguages", bundle.load);
    try v.put(s, owner, "readiness", bundle.readiness);
    try v.put(s, owner, "importFunction", bundle.import_function);
    const state = try v.own(s, try highlight.createState(s.engine, bundle.syntax, runtime));
    try v.put(s, owner, "highlightState", state);
    const theme = try v.get(s, runtime, "theme");
    const exports = try v.object(s);
    try v.put(s, exports, "Theme", try v.get(s, runtime, "Theme"));
    try v.put(s, exports, "theme", theme);
    try v.put(s, exports, "initTheme", try v.ordinary(s, "initTheme", 1, initTheme, &.{try v.get(s, runtime, "initTheme")}));
    try v.put(s, exports, "getLanguageFromPath", try v.ordinary(s, "getLanguageFromPath", 1, language, &.{}));
    try v.put(s, exports, "getMarkdownTheme", try v.ordinary(s, "getMarkdownTheme", 0, markdown, &.{ state, theme }));
    try v.put(s, exports, "getSelectListTheme", try v.ordinary(s, "getSelectListTheme", 0, select, &.{theme}));
    try v.put(s, exports, "getSettingsListTheme", try v.ordinary(s, "getSettingsListTheme", 0, settings, &.{theme}));
    try v.put(s, exports, "highlightCode", try v.ordinary(s, "highlightCode", 2, highlightCode, &.{state}));
    try v.put(s, owner, "exports", exports);
    return v.duplicate(s, owner);
}
/// Returns the same genuine private syntax namespace used by public highlighting.
/// InteractiveMode awaits its actual load function at the Source startup edge.
pub fn syntax(engine: *Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, syntaxBody(&s));
}
fn syntaxBody(s: *Scope) !c.JSValue {
    _ = try v.own(s, try create(s.engine));
    const owner = s.engine.native_module_values.get(cache_key).?;
    return v.duplicate(s, try v.get(s, owner, "syntax"));
}
pub fn readiness(engine: *Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, readinessBody(&s));
}
fn readinessBody(s: *Scope) !c.JSValue {
    _ = try v.own(s, try create(s.engine));
    const owner = s.engine.native_module_values.get(cache_key).?;
    return v.duplicate(s, try v.get(s, owner, "readiness"));
}
fn initTheme(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, initBody(&s, args, roots[0]));
}
fn initBody(s: *Scope, args: []const c.JSValue, actual: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, actual, c.pi_js_undefined(), args));
}
fn language(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return @import("native_sdk_highlight_paths.zig").get(engine, v.arg(args, 0));
}
fn highlightCode(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return highlight.highlightState(engine, roots[0], v.arg(args, 0), v.arg(args, 1), false);
}
fn markdownCode(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return highlight.highlightState(engine, roots[0], v.arg(args, 0), v.arg(args, 1), true);
}
fn markdown(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, markdownBody(&s, roots[0], roots[1]));
}
fn markdownBody(s: *Scope, state: c.JSValue, theme: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    inline for (.{
        .{ "heading", "mdHeading" }, .{ "link", "mdLink" },
        .{ "linkUrl", "mdLinkUrl" }, .{ "code", "mdCode" },
        .{ "codeBlock", "mdCodeBlock" }, .{ "codeBlockBorder", "mdCodeBlockBorder" },
        .{ "quote", "mdQuote" }, .{ "quoteBorder", "mdQuoteBorder" },
        .{ "hr", "mdHr" }, .{ "listBullet", "mdListBullet" },
    }) |entry| try v.put(s, result, entry[0], try highlight.formatter(s, theme, entry[0], entry[1], "fg"));
    inline for (.{ "bold", "italic", "underline", "strikethrough" }) |method_name|
        try v.put(s, result, method_name, try highlight.formatter(s, theme, method_name, "", method_name));
    try v.put(s, result, "highlightCode", try v.arrow(s, "highlightCode", 2, markdownCode, &.{state}));
    return v.duplicate(s, result);
}
fn select(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, selectBody(&s, roots[0]));
}
fn selectBody(s: *Scope, theme: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    inline for (.{
        .{ "selectedPrefix", "accent" }, .{ "selectedText", "accent" },
        .{ "description", "muted" }, .{ "scrollInfo", "muted" }, .{ "noMatch", "muted" },
    }) |entry| try v.put(s, result, entry[0], try highlight.formatter(s, theme, entry[0], entry[1], "fg"));
    return v.duplicate(s, result);
}
fn settings(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, settingsBody(&s, roots[0]));
}
fn settingsBody(s: *Scope, theme: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "label", try v.arrow(s, "label", 2, settingsLabel, &.{theme}));
    try v.put(s, result, "value", try v.arrow(s, "value", 2, settingsValue, &.{theme}));
    try v.put(s, result, "description", try highlight.formatter(s, theme, "description", "dim", "fg"));
    try v.put(s, result, "cursor", try v.own(s, try cursorOwned(s.engine, theme)));
    try v.put(s, result, "hint", try highlight.formatter(s, theme, "hint", "dim", "fg"));
    return v.duplicate(s, result);
}
fn cursorOwned(engine: *Engine, theme: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, cursorBody(&s, theme));
}
fn cursorBody(s: *Scope, theme: c.JSValue) !c.JSValue {
    const color = try v.get(s, theme, "fg");
    return v.duplicate(s, try v.call(s, color, theme, &.{ try v.text(s, "accent"), try v.text(s, "→ ") }));
}
fn settingsLabel(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (c.JS_ToBool(engine.context, v.arg(args, 1)) != 1) return c.JS_DupValue(engine.context, v.arg(args, 0));
    return selectedColor(engine, roots[0], v.arg(args, 0), true);
}
fn settingsValue(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return selectedColor(engine, roots[0], v.arg(args, 0), c.JS_ToBool(engine.context, v.arg(args, 1)) == 1);
}
fn selectedColor(engine: *Engine, theme: c.JSValue, input: c.JSValue, selected: bool) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, selectedColorBody(&s, theme, input, selected));
}
fn selectedColorBody(s: *Scope, theme: c.JSValue, input: c.JSValue, selected: bool) !c.JSValue {
    const color = try v.get(s, theme, "fg");
    return v.duplicate(s, try v.call(s, color, theme, &.{ try v.text(s, if (selected) "accent" else "muted"), input }));
}
