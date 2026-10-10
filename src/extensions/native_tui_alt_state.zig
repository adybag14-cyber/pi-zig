//! Ordinary alternate-screen fields, constructor arrows and lifecycle bodies.
const a = @import("native_tui_alt_frame.zig");
const Frame = a.Frame;
const js = a.js;
const c = a.c;
const v = a.v;
const callbacks = @import("native_tui_alt_callbacks.zig");
pub const Method = enum(c_int) { viewportTop, isFollowingOutput, setWheelScrollLines, getCopyOnSelect, setCopyOnSelect, hasActiveSelection, resetTextSelection, getScreenLines, setLayoutRoot, render, getMountedRoots, getPrimaryScrollView, beforeTerminalStart, beforeTerminalStop, afterTerminalStop, deleteKittyImages, resetRenderState, scrollBy, scrollToTop, scrollToBottom, scrollToPrompt, flash, shouldDeferViewportInputToOverlay, clearComponentMouseGesture, clearTextSelection };
pub const sequence = struct {
    pub const enter = "\x1b[?1049h";
    pub const exit = "\x1b[?1049l";
    pub const disable_wrap = "\x1b[?7l";
    pub const enable_wrap = "\x1b[?7h";
    pub const button_mouse = "\x1b[?1000h\x1b[?1002h\x1b[?1004h\x1b[?1006h";
    pub const all_mouse = "\x1b[?1000h\x1b[?1002h\x1b[?1003h\x1b[?1004h\x1b[?1006h";
    pub const disable_mouse = "\x1b[?1006l\x1b[?1004l\x1b[?1003l\x1b[?1002l\x1b[?1000l";
    pub const begin = "\x1b[?2026h";
    pub const end = "\x1b[?2026l";
};
const Arrow = enum(c_int) { documentRender, documentMouse, documentInvalidate, requestRender, matchStyle, currentStyle, navigationStyle, input, queryChange, autoScroll };
fn superCall(f: *Frame, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const prototype = try f.own(try f.engine.checked(c.JS_GetPrototype(f.engine.context, try f.get(f.bindings, "altPrototype"))));
    return f.call(try f.get(prototype, name), f.object, args);
}
fn arrow(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    var f: Frame = .{ .engine = engine, .object = data[0], .bindings = data[1] };
    defer f.deinit();
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const result = arrowBody(&f, @enumFromInt(magic), args) catch |err| return a.fail(engine, err);
    return f.result(result);
}
fn arrowBody(f: *Frame, kind: Arrow, args: []const c.JSValue) !c.JSValue {
    switch (kind) {
        .documentRender => return superCall(f, "render", &.{v.arg(args, 0)}),
        .documentMouse => return superCall(f, "handleMouse", &.{v.arg(args, 0)}),
        .documentInvalidate => {
            const children = try f.field("children");
            var iterator = try js.Iterator.init(f.engine, children, try f.get(f.bindings, "iteratorSymbol"));
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |child| {
                defer f.engine.freeValue(child);
                _ = try f.method(child, "invalidate", &.{});
            }
        },
        .requestRender => return f.invoke("requestRender", &.{}),
        .matchStyle => return f.concat(&.{ try f.text("\x1b[4m"), v.arg(args, 0), try f.text("\x1b[24m") }),
        .currentStyle => return f.concat(&.{ try f.text("\x1b[1;7m"), v.arg(args, 0), try f.text("\x1b[22;27m") }),
        .navigationStyle => return v.arg(args, 0),
        .input => return f.invoke("handleViewportInput", &.{v.arg(args, 0)}),
        .queryChange => return f.invoke("updateSearchQuery", &.{v.arg(args, 0)}),
        .autoScroll => return f.invoke("autoScrollSelection", &.{}),
    }
    return c.pi_js_undefined();
}
fn closure(f: *Frame, kind: Arrow, name: [*:0]const u8, length: c_int) !c.JSValue {
    var data = [_]c.JSValue{ f.object, f.bindings };
    return f.own(try f.engine.checked(c.JS_NewCFunctionData2(f.engine.context, arrow, name, length, @intFromEnum(kind), 2, &data)));
}
pub fn requestRenderClosure(f: *Frame) !c.JSValue {
    return closure(f, .requestRender, "", 0);
}
pub fn queryClosure(f: *Frame) !c.JSValue {
    return closure(f, .queryChange, "", 1);
}
pub fn autoScrollClosure(f: *Frame) !c.JSValue {
    return closure(f, .autoScroll, "", 0);
}
pub fn initialize(f: *Frame, args: []const c.JSValue) !void {
    try f.define(f.object, "mode", try f.text("fullscreen"));
    try js.setKey(f.engine, f.object, try f.get(f.bindings, "viewportSymbol"), f.boolean(true));
    try f.define(f.object, "previousScreen", try f.array());
    try f.define(f.object, "lastDocument", try f.array());
    try f.define(f.object, "previousScreenWidth", f.num(0));
    try f.define(f.object, "previousScreenHeight", f.num(0));
    inline for (.{ "layoutRoot", "currentLayout", "implicitDocument", "implicitScrollView", "flashes" }) |name| try f.define(f.object, name, c.pi_js_undefined());
    try f.define(f.object, "altScreenActive", f.boolean(false));
    try f.define(f.object, "imageProtocol", c.pi_js_null());
    try f.define(f.object, "savedCapabilities", c.pi_js_undefined());
    try f.define(f.object, "uploadedKittyImages", try f.construct(try f.global("Map"), &.{}));
    try f.define(f.object, "selectionAnchor", c.pi_js_undefined());
    try f.define(f.object, "selectionFocus", c.pi_js_undefined());
    try f.define(f.object, "selectionGranularity", try f.text("character"));
    inline for (.{ "selectionInitialRange", "lastClick", "selectionDragPointer" }) |name| try f.define(f.object, name, c.pi_js_undefined());
    try f.define(f.object, "selectionAutoScrollDirection", f.num(0));
    try f.define(f.object, "selectionAutoScrollTimer", c.pi_js_undefined());
    try f.define(f.object, "selectionPressActive", f.boolean(false));
    inline for (.{ "scrollbarDrag", "scrollbarHover", "scrollToEndIndicatorRect", "activeSearch", "pressedUrl" }) |name| try f.define(f.object, name, c.pi_js_undefined());
    try f.define(f.object, "selectionDragged", f.boolean(false));
    inline for (.{ "mouseCapture", "mousePressTarget", "mousePressPoint" }) |name| try f.define(f.object, name, c.pi_js_undefined());
    try f.define(f.object, "mousePressMoved", f.boolean(false));
    inline for (.{ "lastComponentClick", "wheelScroll", "mouseEnabled", "searchMatchStyle", "searchCurrentMatchStyle", "searchNavigationButtonStyle", "scrollToEndIndicator", "openUrl", "onRightClickPaste", "copyOnSelect", "copySelection" }) |name| try f.define(f.object, name, c.pi_js_undefined());
    const options = if (c.JS_IsUndefined(v.arg(args, 3))) try f.record() else v.arg(args, 3);
    const document = try f.record();
    try f.define(document, "render", try closure(f, .documentRender, "render", 1));
    try f.define(document, "handleMouse", try closure(f, .documentMouse, "handleMouse", 1));
    try f.define(document, "invalidate", try closure(f, .documentInvalidate, "invalidate", 0));
    try f.put("implicitDocument", document);
    const scroll_options = try f.record();
    try f.define(scroll_options, "follow", try f.text("end"));
    try f.define(scroll_options, "primary", f.boolean(true));
    try f.put("implicitScrollView", try f.construct(try f.get(f.bindings, "ScrollView"), &.{ try f.field("implicitDocument"), scroll_options }));
    try f.put("flashes", try f.construct(try f.get(f.bindings, "AltScreenFlashContainer"), &.{try requestRenderClosure(f)}));
    const wheel = try f.get(options, "wheelScrollLines");
    try f.put("wheelScroll", try f.construct(try f.get(f.bindings, "WheelScrollAccelerator"), &.{if (f.nullish(wheel)) f.num(1) else wheel}));
    const mouse = try f.get(options, "mouse");
    try f.put("mouseEnabled", if (f.nullish(mouse)) f.boolean(true) else mouse);
    inline for (.{ .{ "searchMatchStyle", Arrow.matchStyle }, .{ "searchCurrentMatchStyle", Arrow.currentStyle }, .{ "searchNavigationButtonStyle", Arrow.navigationStyle } }) |item| {
        const style = try f.get(options, item[0]);
        try f.put(item[0], if (f.nullish(style)) try closure(f, item[1], "", 1) else style);
    }
    inline for (.{ "scrollToEndIndicator", "openUrl", "onRightClickPaste" }) |name| try f.put(name, try f.get(options, name));
    const copy = try f.get(options, "copyOnSelect");
    try f.put("copyOnSelect", if (f.nullish(copy)) f.boolean(true) else copy);
    try f.put("copySelection", try f.get(options, "copySelection"));
    _ = try f.invoke("addInputListener", &.{try closure(f, .input, "", 1)});
}
fn resetSelection(f: *Frame) !void {
    try f.put("selectionAnchor", c.pi_js_undefined());
    try f.put("selectionFocus", c.pi_js_undefined());
    try f.put("selectionGranularity", try f.text("character"));
    try f.put("selectionInitialRange", c.pi_js_undefined());
}
fn beforeStart(f: *Frame) !void {
    _ = try f.invoke("stopSelectionAutoScroll", &.{});
    try f.put("selectionPressActive", f.boolean(false));
    _ = try f.invoke("stopScrollbarHover", &.{});
    _ = try f.invoke("stopScrollbarDrag", &.{});
    _ = try f.method(try f.field("flashes"), "dispose", &.{});
    try f.put("altScreenActive", f.boolean(true));
    const capabilities = try f.imported("getCapabilities", &.{});
    try f.put("imageProtocol", try f.get(capabilities, "images"));
    _ = try f.method(try f.field("uploadedKittyImages"), "clear", &.{});
    if (try f.is(try f.get(capabilities, "images"), "iterm2")) {
        try f.put("savedCapabilities", capabilities);
        const replacement = try f.spread(capabilities);
        try f.define(replacement, "images", c.pi_js_null());
        _ = try f.imported("setCapabilities", &.{replacement});
        _ = try f.invoke("invalidate", &.{});
    }
    try f.put("lastDocument", try f.array());
    try resetSelection(f);
    try f.put("lastClick", c.pi_js_undefined());
    try f.put("pressedUrl", c.pi_js_undefined());
    try f.put("selectionDragged", f.boolean(false));
    _ = try f.invoke("clearComponentMouseGesture", &.{});
    try f.put("lastComponentClick", c.pi_js_undefined());
    _ = try f.invoke("resetRenderState", &.{});
    const environment = try f.get(try f.global("process"), "env");
    const raw_term = try f.get(environment, "TERM");
    const term = if (f.nullish(raw_term)) try f.text("") else try f.method(raw_term, "toLowerCase", &.{});
    var multiplexer = false;
    inline for (.{ "TMUX", "ZELLIJ", "STY" }) |name| {
        if (!multiplexer) multiplexer = !c.JS_IsUndefined(try f.get(try f.get(try f.global("process"), "env"), name));
    }
    if (!multiplexer) multiplexer = f.truth(try f.method(term, "startsWith", &.{try f.text("tmux")}));
    if (!multiplexer) multiplexer = f.truth(try f.method(term, "startsWith", &.{try f.text("screen")}));
    try f.write(try f.concat(&.{ try f.text(sequence.enter ++ sequence.disable_wrap), try f.text(if (f.truth(try f.field("mouseEnabled"))) if (multiplexer) sequence.button_mouse else sequence.all_mouse else ""), try f.text("\x1b[2J\x1b[H\x1b[?25l") }));
}
fn beforeStop(f: *Frame) !void {
    _ = try f.invoke("closeSearch", &.{});
    _ = try f.invoke("stopSelectionAutoScroll", &.{});
    try f.put("selectionPressActive", f.boolean(false));
    _ = try f.invoke("stopScrollbarHover", &.{});
    _ = try f.invoke("stopScrollbarDrag", &.{});
    _ = try f.invoke("clearComponentMouseGesture", &.{});
    _ = try f.method(try f.field("flashes"), "dispose", &.{});
    if (!f.truth(try f.field("altScreenActive"))) return;
    try f.write(try f.concat(&.{ try f.text(sequence.begin), try f.invoke("deleteKittyImages", &.{}), try f.text(if (f.truth(try f.field("mouseEnabled"))) sequence.disable_mouse else ""), try f.text(sequence.enable_wrap ++ sequence.end) }));
    _ = try f.method(try f.field("uploadedKittyImages"), "clear", &.{});
}
fn afterStop(f: *Frame, options: c.JSValue) !void {
    if (!f.truth(try f.field("altScreenActive"))) return;
    try f.put("altScreenActive", f.boolean(false));
    if (f.truth(try f.get(options, "preserveScreen"))) try f.write(try f.text(sequence.begin ++ sequence.exit ++ "\x1b[?25h" ++ sequence.end)) else {
        const width = try f.math("max", &.{ f.num(1), try f.get(try f.field("terminal"), "columns") });
        const resolved = try f.invoke("resolveFakeCursors", &.{try f.invoke("render", &.{f.num(width)})});
        const document = try callbacks.map(f, resolved, .stripZones, c.pi_js_undefined());
        const clean = try callbacks.map(f, document, .removeCursor, c.pi_js_undefined());
        const resets = try f.invoke("applyLineResets", &.{clean});
        const capture = try f.record();
        try f.define(capture, "width", f.num(width));
        const last = try callbacks.map(f, resets, .clampLine, capture);
        try f.put("lastDocument", last);
        var buffer = try f.text(sequence.begin ++ sequence.exit ++ sequence.disable_wrap);
        var row: f64 = 0;
        while (row < try f.n(try f.field("lastDocument"), "length")) : (row += 1) {
            if (row > 0) buffer = try f.concat(&.{ buffer, try f.text("\r\n") });
            buffer = try f.concat(&.{ buffer, try f.text("\r\x1b[2K"), try f.emptyLine(try f.field("lastDocument"), row) });
        }
        buffer = try f.concat(&.{ buffer, try f.text("\x1b[0m" ++ sequence.enable_wrap ++ "\r\n\x1b[?25h" ++ sequence.end) });
        try f.write(buffer);
    }
    if (f.truth(try f.field("savedCapabilities"))) {
        _ = try f.imported("setCapabilities", &.{try f.field("savedCapabilities")});
        try f.put("savedCapabilities", c.pi_js_undefined());
    }
}
pub fn invoke(f: *Frame, method: Method, args: []const c.JSValue) anyerror!c.JSValue {
    switch (method) {
        .viewportTop, .isFollowingOutput => return f.get(try f.invoke("getPrimaryScrollView", &.{}), if (method == .viewportTop) "scrollTop" else "isFollowingEnd"),
        .setWheelScrollLines => {
            _ = try f.method(try f.field("wheelScroll"), "setLines", &.{v.arg(args, 0)});
        },
        .getCopyOnSelect => return f.field("copyOnSelect"),
        .setCopyOnSelect => try f.put("copyOnSelect", v.arg(args, 0)),
        .hasActiveSelection => return f.boolean(!c.JS_IsUndefined(try f.invoke("getActiveSelectionText", &.{}))),
        .resetTextSelection => {
            _ = try f.invoke("clearTextSelection", &.{});
            try f.put("lastClick", c.pi_js_undefined());
        },
        .getScreenLines => return f.copy(try f.field("previousScreen")),
        .setLayoutRoot => {
            if (f.equal(try f.field("layoutRoot"), v.arg(args, 0))) return c.pi_js_undefined();
            try f.put("layoutRoot", v.arg(args, 0));
            try f.put("currentLayout", c.pi_js_undefined());
            _ = try f.invoke("requestRender", &.{});
        },
        .render => {
            const root = try f.field("layoutRoot");
            if (!f.nullish(root)) {
                const lines = try f.method(root, "render", &.{v.arg(args, 0)});
                if (!f.nullish(lines)) return lines;
            }
            return superCall(f, "render", &.{v.arg(args, 0)});
        },
        .getMountedRoots => {
            if (!f.truth(try f.field("layoutRoot"))) return f.field("children");
            return f.literal(&.{try f.field("layoutRoot")});
        },
        .getPrimaryScrollView => {
            const layout = try f.field("currentLayout");
            if (!f.nullish(layout)) {
                const primary = try f.get(layout, "primaryScrollView");
                if (!f.nullish(primary)) return primary;
            }
            return f.field("implicitScrollView");
        },
        .beforeTerminalStart => try beforeStart(f),
        .beforeTerminalStop => try beforeStop(f),
        .afterTerminalStop => try afterStop(f, v.arg(args, 0)),
        .deleteKittyImages => return if (try f.is(try f.field("imageProtocol"), "kitty")) f.imported("deleteAllKittyImages", &.{}) else f.text(""),
        .resetRenderState => {
            try f.put("previousScreen", try f.array());
            try f.put("previousScreenWidth", f.num(0));
            try f.put("previousScreenHeight", f.num(0));
            try f.put("currentLayout", c.pi_js_undefined());
        },
        .scrollBy, .scrollToTop, .scrollToBottom => {
            _ = try f.method(try f.invoke("getPrimaryScrollView", &.{}), switch (method) {
                .scrollBy => "scrollBy",
                .scrollToTop => "scrollToStart",
                else => "scrollToEnd",
            }, if (method == .scrollBy) &.{v.arg(args, 0)} else &.{});
            _ = try f.invoke("requestRender", &.{});
        },
        .scrollToPrompt => {
            if (!f.truth(try f.field("currentLayout"))) return c.pi_js_undefined();
            const scroll = try f.invoke("getPrimaryScrollView", &.{});
            const box = try f.imported("getScrollViewBox", &.{ try f.field("currentLayout"), scroll });
            if (f.nullish(box)) return c.pi_js_undefined();
            const lines = try f.get(box, "scrollContentLines");
            if (!f.truth(lines)) return c.pi_js_undefined();
            const direction = try f.number(v.arg(args, 0));
            var row = try f.n(scroll, "scrollTop") + direction;
            while (row >= 0 and row < try f.n(lines, "length")) : (row += direction) {
                if (!f.truth(try f.method(try f.get(f.bindings, "osc133PromptStart"), "test", &.{try f.emptyLine(lines, row)}))) continue;
                _ = try f.method(scroll, "scrollTo", &.{f.num(row)});
                _ = try f.invoke("requestRender", &.{});
                break;
            }
        },
        .flash => {
            _ = try f.method(try f.field("flashes"), "flash", &.{ v.arg(args, 0), v.arg(args, 1) });
        },
        .shouldDeferViewportInputToOverlay => {
            if (!f.truth(try f.invoke("isOverlayFocused", &.{}))) return f.boolean(false);
            const search = try f.field("activeSearch");
            if (f.nullish(search)) return f.boolean(true);
            const overlay = try f.get(search, "overlay");
            if (f.nullish(overlay)) return f.boolean(true);
            return f.boolean(!f.equal(try f.method(overlay, "isFocused", &.{}), f.boolean(true)));
        },
        .clearComponentMouseGesture => {
            inline for (.{ "mouseCapture", "mousePressTarget", "mousePressPoint" }) |name| try f.put(name, c.pi_js_undefined());
            try f.put("mousePressMoved", f.boolean(false));
        },
        .clearTextSelection => {
            _ = try f.invoke("stopSelectionAutoScroll", &.{});
            try f.put("selectionPressActive", f.boolean(false));
            try resetSelection(f);
            try f.put("pressedUrl", c.pi_js_undefined());
            try f.put("selectionDragged", f.boolean(false));
        },
    }
    return c.pi_js_undefined();
}
