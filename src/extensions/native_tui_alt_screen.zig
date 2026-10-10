//! Genuine TuiAltScreen class. Public installation waits for qualification.
const std = @import("std");
const a = @import("native_tui_alt_frame.zig");
const Frame = a.Frame;
const js = a.js;
const c = a.c;
const v = a.v;
const state = @import("native_tui_alt_state.zig");
const search = @import("native_tui_alt_search.zig");
const mouse = @import("native_tui_alt_mouse.zig");
const selection = @import("native_tui_alt_selection.zig");
const render = @import("native_tui_alt_render.zig");
const Method = enum(c_int) {
    viewportTop,
    isFollowingOutput,
    setWheelScrollLines,
    getCopyOnSelect,
    setCopyOnSelect,
    hasActiveSelection,
    copyActiveSelectionToClipboard,
    resetTextSelection,
    getScreenLines,
    setLayoutRoot,
    render,
    getMountedRoots,
    getPrimaryScrollView,
    beforeTerminalStart,
    beforeTerminalStop,
    afterTerminalStop,
    deleteKittyImages,
    prepareKittyScreen,
    resetRenderState,
    scrollBy,
    scrollToTop,
    scrollToBottom,
    scrollToPrompt,
    toggleSearch,
    closeSearch,
    updateSearchQuery,
    navigateSearch,
    getSearchNavigationDirectionAt,
    handleSearchMouseEvent,
    refreshSearch,
    flash,
    shouldDeferViewportInputToOverlay,
    clearComponentMouseGesture,
    handleViewportInput,
    decodeMouseButton,
    createMouseEvent,
    dispatchMouseToLayout,
    applyMouseDispatchResult,
    dispatchMouseToTarget,
    getComponentClickCount,
    clearTextSelection,
    handleMouseEvent,
    parseWheelEvent,
    routeWheel,
    parseSgrMouseEvent,
    handleRightClickPaste,
    handleScrollToEndIndicatorMouseEvent,
    getScrollbarTargetAt,
    setScrollbarHover,
    updateScrollbarHover,
    stopScrollbarHover,
    scrollScrollbarToPointer,
    handleScrollbarMouseEvent,
    stopScrollbarDrag,
    getScrollSelectionPoint,
    getSelectionPoint,
    getSelectionSourceLine,
    getWordSelection,
    getLineSelection,
    updateSelectionFocus,
    getClickCount,
    updateSelectionAutoScroll,
    autoScrollSelection,
    stopSelectionAutoScroll,
    handleSelectionMouseEvent,
    getSelectionBounds,
    getSelectionColumns,
    getActiveSelectionText,
    copySelectionToClipboard,
    copyTextToClipboard,
    applySearchTextHighlight,
    applySearchHighlights,
    applySelectionHighlight,
    applySelection,
    isMouseSequence,
    compositeScrollToEndIndicator,
    compositeFlashes,
    doRender,
};
fn length(method: Method) c_int {
    return switch (method) {
        .setWheelScrollLines, .setCopyOnSelect, .setLayoutRoot, .render, .beforeTerminalStop, .afterTerminalStop, .prepareKittyScreen, .scrollBy, .scrollToPrompt, .updateSearchQuery, .navigateSearch, .handleSearchMouseEvent, .refreshSearch, .handleViewportInput, .decodeMouseButton, .dispatchMouseToLayout, .handleMouseEvent, .parseWheelEvent, .parseSgrMouseEvent, .handleRightClickPaste, .handleScrollToEndIndicatorMouseEvent, .setScrollbarHover, .handleScrollbarMouseEvent, .getSelectionSourceLine, .getWordSelection, .getLineSelection, .updateSelectionFocus, .updateSelectionAutoScroll, .handleSelectionMouseEvent, .copyTextToClipboard, .applySelectionHighlight, .applySelection, .isMouseSequence => 1,
        .getSearchNavigationDirectionAt, .applyMouseDispatchResult, .dispatchMouseToTarget, .routeWheel, .getScrollbarTargetAt, .updateScrollbarHover, .getClickCount, .applySearchTextHighlight, .applySearchHighlights, .flash, .getSelectionPoint => 2,
        .getComponentClickCount, .getScrollSelectionPoint, .getSelectionColumns, .compositeScrollToEndIndicator, .compositeFlashes => 3,
        .createMouseEvent, .scrollScrollbarToPointer => 4,
        else => 0,
    };
}
fn asynchronous(method: Method) bool {
    return method == .copyActiveSelectionToClipboard or method == .copySelectionToClipboard or method == .copyTextToClipboard;
}
fn body(f: *Frame, method: Method, args: []const c.JSValue) anyerror!c.JSValue {
    if (method == .handleViewportInput) return @import("native_tui_alt_input.zig").invoke(f, v.arg(args, 0));
    inline for (.{ state, search, mouse, selection, render }) |module| {
        inline for (std.meta.fields(module.Method)) |field| {
            if (method == @field(Method, field.name)) return module.invoke(f, @enumFromInt(field.value), args);
        }
    }
    unreachable;
}
fn call(ctx: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    var f: Frame = .{ .engine = engine, .object = this, .bindings = data[0] };
    defer f.deinit();
    const method: Method = @enumFromInt(magic);
    const result = body(&f, method, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| {
        const failure = a.fail(engine, err);
        if (!asynchronous(method)) return failure;
        const reason = c.JS_GetException(engine.context);
        defer engine.freeValue(reason);
        return c.JS_NewSettledPromise(engine.context, true, reason);
    };
    if (asynchronous(method)) {
        const promise = selection.resolved(&f, result) catch |err| return a.fail(engine, err);
        return f.result(promise);
    }
    return f.result(result);
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    const self = try js.get(engine, data[0], "TuiAltScreen");
    defer engine.freeValue(self);
    const base = try engine.checked(c.JS_GetPrototype(engine.context, self));
    defer engine.freeValue(base);
    var base_args = [_]c.JSValue{ v.arg(args, 0), v.arg(args, 1), v.arg(args, 2) };
    const object = try engine.checked(c.JS_CallConstructor2(engine.context, base, target, 3, &base_args));
    errdefer engine.freeValue(object);
    var f: Frame = .{ .engine = engine, .object = object, .bindings = data[0] };
    defer f.deinit();
    try state.initialize(&f, args);
    return object;
}
fn dispatch(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return (if (magic == 0) @import("native_mouse.zig").dispatch(engine, v.arg(args, 0), v.arg(args, 1)) else @import("native_mouse.zig").retarget(engine, v.arg(args, 0), v.arg(args, 1))) catch |err| a.fail(engine, err);
}
pub fn create(engine: *js.Engine, exports: c.JSValue, base: c.JSValue) !c.JSValue {
    const bindings = try js.object(engine);
    defer engine.freeValue(bindings);
    inline for (.{ "Container", "ScrollView", "getKeybindings", "isKeyRelease", "getCapabilities", "setCapabilities", "deleteAllKittyImages", "deleteAllKittyPlacements", "deleteKittyImage", "getKittyImagePlacement", "getKittyImagePlacementRows", "getKittyImageMetadata", "cropKittyImageLine", "isImageLine", "CURSOR_MARKER", "compositeTuiLine", "sliceByColumn", "stripTerminalSequences", "truncateToWidth", "visibleWidth" }) |name| try js.define(engine, bindings, name, try js.get(engine, exports, name));
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    try js.define(engine, bindings, "iteratorSymbol", try js.get(engine, symbol, "iterator"));
    try js.define(engine, bindings, "primitiveSymbol", try js.get(engine, symbol, "toPrimitive"));
    inline for (.{ .{ "layoutSymbol", "@earendil-works/pi-tui/layout-node" }, .{ "viewportSymbol", "@earendil-works/pi-tui/viewport" } }) |item| {
        const key = try v.text(engine, item[1]);
        defer engine.freeValue(key);
        try js.define(engine, bindings, item[0], try js.invoke(engine, symbol, "for", &.{key}));
    }
    const joiners = try js.array(engine);
    defer engine.freeValue(joiners);
    inline for (.{ "/", "-" }) |text| {
        const value = try v.text(engine, text);
        defer engine.freeValue(value);
        try js.push(engine, joiners, value);
    }
    const set = try js.global(engine, "Set");
    defer engine.freeValue(set);
    var joiner_args = [_]c.JSValue{joiners};
    try js.define(engine, bindings, "wordJoiners", try engine.checked(c.JS_CallConstructor(engine.context, set, 1, &joiner_args)));
    try js.define(engine, bindings, "osc133ZonePrefix", try @import("native_tui_base_utilities.zig").regexp(engine, "^(?:\x1b\\]133;[ABC](?:\\x07|\\x1b\\\\))+", ""));
    try js.define(engine, bindings, "osc133PromptStart", try @import("native_tui_base_utilities.zig").regexp(engine, "^\x1b\\]133;A(?:\\x07|\\x1b\\\\)", ""));
    try js.define(engine, bindings, "WheelScrollAccelerator", try @import("native_wheel_scroll.zig").create(engine));
    try js.define(engine, bindings, "AltScreenFlashContainer", try @import("native_alt_screen_flash.zig").create(engine, exports));
    try js.define(engine, bindings, "AltScreenSearchComponent", try @import("native_alt_screen_search_component.zig").create(engine, exports));
    const search_exports = try @import("native_alt_screen_search_index.zig").create(engine, exports);
    defer engine.freeValue(search_exports);
    inline for (.{ "AltScreenSearchIndex", "getAltScreenSearchMatchKey" }) |name| try js.define(engine, bindings, name, try js.get(engine, search_exports, name));
    inline for (.{ .{ "dispatchMouseEvent", 0 }, .{ "retargetMouseEvent", 1 } }) |item| try js.define(engine, bindings, item[0], try engine.checked(c.JS_NewCFunction2(engine.context, @ptrCast(&dispatch), item[0], 2, c.JS_CFUNC_generic_magic, item[1])));
    try @import("native_tui_alt_utilities.zig").install(engine, bindings);
    try @import("native_tui_layout.zig").install(engine, bindings);
    const parent = try js.get(engine, base, "prototype");
    defer engine.freeValue(parent);
    const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, parent));
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    try js.define(engine, bindings, "altPrototype", c.JS_DupValue(engine.context, prototype));
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        const getter = method == .viewportTop or method == .isFollowingOutput;
        var data = [_]c.JSValue{bindings};
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, call, if (getter) "get " ++ field.name else field.name, length(method), field.value, 1, &data));
        var transferred = false;
        defer if (!transferred) engine.freeValue(function);
        if (asynchronous(method)) {
            const intrinsic = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
            defer engine.freeValue(intrinsic);
            if (c.JS_SetPrototype(engine.context, function, intrinsic) < 0) {
                return js.capture(engine);
            }
        }
        if (getter) {
            const atom = c.JS_NewAtom(engine.context, field.name);
            if (atom == c.JS_ATOM_NULL) {
                return js.capture(engine);
            }
            defer c.JS_FreeAtom(engine.context, atom);
            transferred = true;
            if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, function, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        } else {
            transferred = true;
            if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
        }
    }
    const constructor = try @import("native_class.zig").constructor(engine, "TuiAltScreen", 3, prototype, construct, &.{bindings});
    errdefer engine.freeValue(constructor);
    if (c.JS_SetPrototype(engine.context, constructor, base) < 0) return js.capture(engine);
    try js.define(engine, bindings, "TuiAltScreen", c.JS_DupValue(engine.context, constructor));
    return constructor;
}
