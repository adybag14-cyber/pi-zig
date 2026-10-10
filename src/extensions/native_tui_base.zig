//! Genuine ordinary Source TuiBase constructor and complete prototype.
//! Main/Alt public installation is separate until their renderer bodies exist.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const presentation = @import("native_tui_base_presentation.zig");
const focus = @import("native_tui_base_focus.zig");
const lifecycle = @import("native_tui_base_lifecycle.zig");
const scheduler = @import("native_tui_base_scheduler.zig");
const reports = @import("native_tui_base_reports.zig");
const overlays = @import("native_tui_base_overlays.zig");
const utilities = @import("native_tui_base_utilities.zig");
const Method = enum(c_int) {
    hasOverlayEntries,
    resetRenderState,
    beforeTerminalStart,
    afterTerminalStart,
    beforeTerminalStop,
    afterTerminalStop,
    fullRedraws,
    getShowHardwareCursor,
    setShowHardwareCursor,
    getClearOnShrink,
    setClearOnShrink,
    getFocusedComponent,
    setFocus,
    setFocusInternal,
    clearOverlayFocusRestore,
    clearOverlayFocusRestoreFor,
    resolveBlockedOverlayFocusResume,
    getVisibleOverlayFocusRestore,
    isOverlayFocusAncestor,
    retargetOverlayPreFocus,
    getMountedRoots,
    isComponentMounted,
    containsComponent,
    showOverlay,
    hideOverlay,
    hideTerminalCursor,
    hasOverlay,
    isOverlayFocused,
    resolveMouseFocusTarget,
    dispatchMouseToOverlay,
    isOverlayVisible,
    getTopmostVisibleOverlay,
    invalidate,
    start,
    addInputListener,
    removeInputListener,
    onTerminalColorSchemeChange,
    setTerminalColorSchemeNotifications,
    queryCellSize,
    stop,
    renderNow,
    requestRender,
    requestImmediateRender,
    cancelRenderTimer,
    scheduleRender,
    handleTerminalInput,
    consumeTerminalColorResponse,
    terminalColorQueryResult,
    completeTerminalColorQuery,
    consumeTerminalColorSchemeReport,
    consumeCellSizeResponse,
    resolveOverlayLayout,
    resolveAnchorRow,
    resolveAnchorCol,
    compositeOverlays,
    applyLineResets,
    compositeLineAt,
    extractCursorPosition,
    resolveFakeCursors,
    queryTerminalColors,
};
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    return c.JS_ThrowTypeError(engine.context, "Native TuiBase: %s", @as([*:0]const u8, @errorName(err)));
}
fn dispatchMouse(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return @import("native_mouse.zig").dispatch(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn clockBinding(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return @import("native_process_clock.zig").performance(engine) catch |err| fail(engine, err);
}
fn bindClock(engine: *js.Engine, bindings: c.JSValue) !void {
    const clock = @import("native_process_clock.zig").performance(engine) catch |err| {
        if (err != error.NativeProcessClockUnavailable) return err;
        // Native hosts may register ordinary class declarations before their
        // genuine process IO binding. The actual clock still starts at process
        // install, before factories; no substitute process or clock is created.
        const atom = c.JS_NewAtom(engine.context, "performance");
        if (atom == c.JS_ATOM_NULL) return js.capture(engine);
        defer c.JS_FreeAtom(engine.context, atom);
        const getter = try engine.checked(c.JS_NewCFunction2(engine.context, clockBinding, "get performance", 0, c.JS_CFUNC_generic, 0));
        if (c.JS_DefinePropertyGetSet(engine.context, bindings, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        return;
    };
    try js.define(engine, bindings, "performance", clock);
}
fn methodCall(context: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invoke(engine, this, data[0], @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| fail(engine, err);
}
fn invoke(engine: *js.Engine, this: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .resetRenderState, .beforeTerminalStart, .afterTerminalStart, .beforeTerminalStop, .afterTerminalStop => return c.pi_js_undefined(),
        .showOverlay => return @import("native_tui_base_overlay_handle.zig").show(engine, this, bindings, args),
        .handleTerminalInput => return @import("native_tui_base_input.zig").invoke(engine, this, bindings, v.arg(args, 0)),
        .resolveOverlayLayout => return @import("native_tui_base_layout.zig").resolve(engine, this, bindings, args),
        .compositeOverlays => return @import("native_tui_base_composite.zig").composite(engine, this, bindings, args),
        else => {},
    }
    inline for (.{ presentation, focus, scheduler, reports, overlays }) |module| {
        inline for (std.meta.fields(module.Method)) |field| {
            if (method == @field(Method, field.name)) return module.invoke(engine, this, bindings, @enumFromInt(field.value), args);
        }
    }
    inline for (std.meta.fields(lifecycle.Method)) |field| {
        if (method == @field(Method, field.name)) return lifecycle.invoke(engine, this, @enumFromInt(field.value), args);
    }
    unreachable;
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    const self = try js.get(engine, data[0], "TuiBase");
    defer engine.freeValue(self);
    const parent = try engine.checked(c.JS_GetPrototype(engine.context, self));
    defer engine.freeValue(parent);
    const object = try engine.checked(c.JS_CallConstructor2(engine.context, parent, target, 0, null));
    errdefer engine.freeValue(object);
    try @import("native_tui_base_fields.zig").initialize(engine, object, args);
    return object;
}
fn length(method: Method) c_int {
    return switch (method) {
        .beforeTerminalStop, .afterTerminalStop, .setShowHardwareCursor, .setClearOnShrink, .setFocus, .setFocusInternal, .clearOverlayFocusRestoreFor, .resolveBlockedOverlayFocusResume, .retargetOverlayPreFocus, .isComponentMounted, .resolveMouseFocusTarget, .dispatchMouseToOverlay, .isOverlayVisible, .addInputListener, .removeInputListener, .onTerminalColorSchemeChange, .setTerminalColorSchemeNotifications, .handleTerminalInput, .consumeTerminalColorResponse, .terminalColorQueryResult, .completeTerminalColorQuery, .consumeTerminalColorSchemeReport, .consumeCellSizeResponse, .applyLineResets, .resolveFakeCursors, .queryTerminalColors => 1,
        .isOverlayFocusAncestor, .containsComponent, .showOverlay, .extractCursorPosition => 2,
        .compositeOverlays => 3,
        .resolveOverlayLayout, .resolveAnchorRow, .resolveAnchorCol => 4,
        .compositeLineAt => 5,
        else => 0,
    };
}
/// Build the actual base class; callers supply the already installed TUI
/// import bindings. This does not expose incomplete Main/Alt screen classes.
pub fn create(engine: *js.Engine, exports: c.JSValue) !c.JSValue {
    const bindings = try js.object(engine);
    defer engine.freeValue(bindings);
    inline for (.{ "Container", "isFocusable", "getCapabilities", "isImageLine", "visibleWidth", "compositeTuiLine", "parseTerminalColorSchemeReport", "setCellDimensions", "matchesKey", "isKeyRelease", "sliceByColumn" }) |name| try js.define(engine, bindings, name, try js.get(engine, exports, name));
    try bindClock(engine, bindings);
    try js.define(engine, bindings, "dispatchMouseEvent", try engine.checked(c.JS_NewCFunction(engine.context, dispatchMouse, "dispatchMouseEvent", 2)));
    const symbols = try js.global(engine, "Symbol");
    defer engine.freeValue(symbols);
    try js.define(engine, bindings, "iteratorSymbol", try js.get(engine, symbols, "iterator"));
    try js.define(engine, bindings, "primitiveSymbol", try js.get(engine, symbols, "toPrimitive"));
    try js.define(engine, bindings, "deviceAttributesResponsePattern", try utilities.regexp(engine, "^\x1b\\[\\?[\\d;]*c$", ""));
    try js.define(engine, bindings, "cellSizeResponsePattern", try utilities.regexp(engine, "^\x1b\\[6;(\\d+);(\\d+)t$", ""));
    try js.define(engine, bindings, "focusedFakeRegex", try utilities.regexp(engine, "(\x1b_pi:c\x07)\x1b_pi:fc\x07(.*?)(?:\x1b_pi:/fc\x07|$)", "s"));
    try utilities.install(engine, bindings);
    const container = try js.get(engine, bindings, "Container");
    defer engine.freeValue(container);
    const parent_prototype = try js.get(engine, container, "prototype");
    defer engine.freeValue(parent_prototype);
    const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, parent_prototype));
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        const getter = method == .hasOverlayEntries or method == .fullRedraws;
        const function_name: [:0]const u8 = if (getter) "get " ++ field.name else field.name;
        var data = [_]c.JSValue{bindings};
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, function_name.ptr, length(method), field.value, 1, &data));
        if (getter) {
            const atom = c.JS_NewAtom(engine.context, field.name);
            if (atom == c.JS_ATOM_NULL) {
                engine.freeValue(function);
                return js.capture(engine);
            }
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, function, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        } else if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const constructor = try @import("native_class.zig").constructor(engine, "TuiBase", 3, prototype, construct, &.{bindings});
    errdefer engine.freeValue(constructor);
    if (c.JS_SetPrototype(engine.context, constructor, container) < 0) return js.capture(engine);
    try js.define(engine, constructor, "MIN_RENDER_INTERVAL_MS", c.JS_NewInt32(engine.context, 16));
    try js.define(engine, bindings, "TuiBase", c.JS_DupValue(engine.context, constructor));
    return constructor;
}
