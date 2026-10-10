//! Native pi-tui component classes and owned scene/control transport values.
const std = @import("std");
const engine_mod = @import("engine.zig");
const components = @import("native_components.zig");
const terminal_text = @import("../tui/terminal_text.zig");
const keys = @import("../tui/keys.zig");
const c = engine_mod.c;

pub const protocol = @import("component_protocol.zig");
pub const Fence = protocol.Fence;
pub const OverlayLayout = protocol.OverlayLayout;
pub const Mouse = protocol.Mouse;
pub const Scene = protocol.Scene;
pub const Control = protocol.Control;
pub const SceneSink = protocol.SceneSink;
pub const ControlQueue = protocol.ControlQueue;

const Kind = enum { text, container, box, spacer };
const Node = struct {
    engine: *engine_mod.Engine,
    kind: Kind,
    text: c.JSValue,
    padding_x: c.JSValue,
    padding_y: c.JSValue,
    background: c.JSValue,
    array_is_array: c.JSValue,
    cache: ?c.JSValue = null,
    cache_width: usize = 0,
    rendering: bool = false,
    revision: u64 = 0,
};
const Constructor = struct { engine: *engine_mod.Engine, prototype: c.JSValue, array_is_array: c.JSValue, node_class: c.JSClassID, kind: Kind };

/// Match upstream mounted containment: identity, then genuine Container children.
/// Snapshots stay rooted on the worker owner across observable child getters.
pub fn containsComponent(engine: *engine_mod.Engine, root: c.JSValue, target: c.JSValue) !bool {
    return @import("native_container_component.zig").containsComponent(engine, root, target);
}
const Method = enum(c_int) { render, invalidate, setText, setLines, setBgFn, addChild, removeChild, clear, handleMouse };

fn fail(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    return c.JS_ThrowTypeError(engine.context, "Native TUI component: %s", @as([*:0]const u8, @errorName(err)));
}
fn define(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, value, c.JS_PROP_C_W_E) < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        return error.JavaScriptException;
    }
}
fn set(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_SetPropertyStr(engine.context, object, name, value) < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        return error.JavaScriptException;
    }
}
fn nodeFinalizer(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const node: *Node = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    for ([_]c.JSValue{ node.text, node.padding_x, node.padding_y, node.background, node.array_is_array }) |value| c.JS_FreeValueRT(runtime, value);
    if (node.cache) |value| c.JS_FreeValueRT(runtime, value);
    node.engine.gpa.destroy(node);
}
fn nodeMark(runtime: ?*c.JSRuntime, object: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const node: *Node = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    for ([_]c.JSValue{ node.text, node.padding_x, node.padding_y, node.background, node.array_is_array }) |value| c.JS_MarkValue(runtime, value, mark);
    if (node.cache) |value| c.JS_MarkValue(runtime, value, mark);
}
fn constructorFinalizer(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const state: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    c.JS_FreeValueRT(runtime, state.prototype);
    c.JS_FreeValueRT(runtime, state.array_is_array);
    state.engine.gpa.destroy(state);
}
fn constructorMark(runtime: ?*c.JSRuntime, object: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    c.JS_MarkValue(runtime, state.prototype, mark);
    c.JS_MarkValue(runtime, state.array_is_array, mark);
}
fn constructorCall(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) return c.JS_ThrowTypeError(context, "Native TUI classes require new");
    const state: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    return construct(state, target, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn construct(state: *Constructor, target: c.JSValue, args: []c.JSValue) !c.JSValue {
    const engine = state.engine;
    const selected = try engine.checked(c.JS_GetPropertyStr(engine.context, target, "prototype"));
    defer engine.freeValue(selected);
    const object = try engine.checked(c.JS_NewObjectProtoClass(engine.context, if (c.JS_IsObject(selected)) selected else state.prototype, state.node_class));
    errdefer engine.freeValue(object);
    const node = try engine.gpa.create(Node);
    node.* = .{ .engine = engine, .kind = state.kind, .text = c.pi_js_undefined(), .padding_x = c.pi_js_undefined(), .padding_y = c.pi_js_undefined(), .background = c.pi_js_undefined(), .array_is_array = c.JS_DupValue(engine.context, state.array_is_array) };
    _ = c.JS_SetOpaque(object, node);
    switch (state.kind) {
        .text => {
            node.text = if (args.len > 0 and !c.JS_IsUndefined(args[0])) c.JS_DupValue(engine.context, args[0]) else try engine.checked(c.JS_NewString(engine.context, ""));
            node.padding_x = c.JS_DupValue(engine.context, if (args.len > 1 and !c.JS_IsUndefined(args[1])) args[1] else c.JS_NewInt32(engine.context, 1));
            node.padding_y = c.JS_DupValue(engine.context, if (args.len > 2 and !c.JS_IsUndefined(args[2])) args[2] else c.JS_NewInt32(engine.context, 1));
            node.background = c.JS_DupValue(engine.context, if (args.len > 3) args[3] else c.pi_js_undefined());
        },
        .spacer => node.padding_y = c.JS_DupValue(engine.context, if (args.len > 0 and !c.JS_IsUndefined(args[0])) args[0] else c.JS_NewInt32(engine.context, 1)),
        .box, .container => {
            node.padding_x = c.JS_DupValue(engine.context, if (args.len > 0 and state.kind == .box and !c.JS_IsUndefined(args[0])) args[0] else c.JS_NewInt32(engine.context, if (state.kind == .box) 1 else 0));
            node.padding_y = c.JS_DupValue(engine.context, if (args.len > 1 and state.kind == .box and !c.JS_IsUndefined(args[1])) args[1] else c.JS_NewInt32(engine.context, if (state.kind == .box) 1 else 0));
            node.background = c.JS_DupValue(engine.context, if (args.len > 2 and state.kind == .box) args[2] else c.pi_js_undefined());
            try define(engine, object, "children", try engine.checked(c.JS_NewArray(engine.context)));
        },
    }
    return object;
}
fn invalidateNode(node: *Node) void {
    if (node.cache) |value| node.engine.freeValue(value);
    node.cache = null;
    node.revision +%= 1;
}
fn methodCall(context: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var class_id: u32 = 0;
    if (c.JS_ToUint32(context, &class_id, data[0]) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    const node: *Node = @ptrCast(@alignCast(c.JS_GetOpaque(this, class_id) orelse return c.JS_ThrowTypeError(context, "Illegal native TUI receiver")));
    return operation(node, this, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn count(engine: *engine_mod.Engine, value: c.JSValue, ceil: bool) !usize {
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, value) < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        return error.JavaScriptException;
    }
    if (!std.math.isFinite(number) or number < 0 or number > 16_384) return error.NativeTuiLayoutLimit;
    return @intFromFloat(if (ceil) @ceil(number) else @floor(number));
}
fn children(engine: *engine_mod.Engine, object: c.JSValue) !c.JSValue {
    const array = try engine.checked(c.JS_GetPropertyStr(engine.context, object, "children"));
    errdefer engine.freeValue(array);
    if (!c.JS_IsObject(array)) return error.InvalidNativeTuiChildren;
    return array;
}
fn operation(node: *Node, object: c.JSValue, method: Method, args: []c.JSValue) !c.JSValue {
    const engine = node.engine;
    const first = if (args.len == 0) c.pi_js_undefined() else args[0];
    if (method == .handleMouse) return @import("native_mouse.zig").containerDispatch(engine, object, first, if (node.kind == .box) @floatFromInt(try count(engine, node.padding_x, false)) else 0, if (node.kind == .box) @floatFromInt(try count(engine, node.padding_y, true)) else 0, node.kind == .box);
    if (method == .render) return render(node, object, try count(engine, first, false));
    if (method == .setText or method == .setLines or method == .setBgFn) {
        const slot = if (method == .setText) &node.text else if (method == .setLines) &node.padding_y else &node.background;
        const replacement = c.JS_DupValue(engine.context, first);
        engine.freeValue(slot.*);
        slot.* = replacement;
        invalidateNode(node);
        return c.pi_js_undefined();
    }
    if (method == .clear) {
        try set(engine, object, "children", try engine.checked(c.JS_NewArray(engine.context)));
        invalidateNode(node);
        return c.pi_js_undefined();
    }
    invalidateNode(node);
    if (node.kind != .container and node.kind != .box) return c.pi_js_undefined();
    const array = try children(engine, object);
    defer engine.freeValue(array);
    const length = try engine.checked(c.JS_GetPropertyStr(engine.context, array, "length"));
    defer engine.freeValue(length);
    const size = try count(engine, length, false);
    if (size >= components.maximum_lines and method == .addChild) return error.NativeTuiChildrenLimit;
    if (method == .addChild) {
        var pushed = [_]c.JSValue{first};
        const result = (try components.callMethod(engine, array, "push", &pushed, false)).?;
        engine.freeValue(result);
    } else if (method == .removeChild) {
        var searched = [_]c.JSValue{first};
        const index = (try components.callMethod(engine, array, "indexOf", &searched, false)).?;
        defer engine.freeValue(index);
        if (!c.JS_IsStrictEqual(engine.context, index, c.JS_NewInt32(engine.context, -1))) {
            // A user indexOf callback may replace children before splice.
            const current = try children(engine, object);
            defer engine.freeValue(current);
            var removed = [_]c.JSValue{ index, c.JS_NewInt32(engine.context, 1) };
            const result = (try components.callMethod(engine, current, "splice", &removed, false)).?;
            engine.freeValue(result);
        }
    } else if (method == .invalidate) {
        for (0..size) |index| {
            const child = try engine.checked(c.JS_GetPropertyUint32(engine.context, array, @intCast(index)));
            defer engine.freeValue(child);
            if (try components.callMethod(engine, child, "invalidate", &.{}, true)) |value| engine.freeValue(value);
        }
    }
    return c.pi_js_undefined();
}

fn appendOwned(engine: *engine_mod.Engine, output: *std.ArrayList([]u8), line: []u8) !void {
    errdefer engine.gpa.free(line);
    if (output.items.len >= components.maximum_lines) return error.NativeComponentFrameLimit;
    try output.append(engine.gpa, line);
}
fn padded(node: *Node, line: []const u8, width: usize, left: usize) ![]u8 {
    const engine = node.engine;
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(engine.gpa);
    try output.appendNTimes(engine.gpa, ' ', left);
    try output.appendSlice(engine.gpa, line);
    try output.appendNTimes(engine.gpa, ' ', left);
    const visible = terminal_text.visibleWidth(output.items);
    if (visible < width) try output.appendNTimes(engine.gpa, ' ', width - visible);
    if (c.JS_IsUndefined(node.background)) return output.toOwnedSlice(engine.gpa);
    const background = c.JS_DupValue(engine.context, node.background);
    defer engine.freeValue(background);
    if (!c.JS_IsFunction(engine.context, background)) return error.InvalidNativeTuiBackground;
    var args = [_]c.JSValue{try engine.checked(c.JS_NewStringLen(engine.context, output.items.ptr, output.items.len))};
    defer engine.freeValue(args[0]);
    const result = try engine.checked(c.JS_Call(engine.context, background, c.pi_js_undefined(), 1, &args));
    defer engine.freeValue(result);
    if (!c.JS_IsString(result)) return error.InvalidNativeTuiBackground;
    return engine.toString(result);
}

fn blankText(source: []const u8) bool {
    var iterator = std.unicode.Wtf8View.initUnchecked(source).iterator();
    while (iterator.nextCodepoint()) |point| {
        switch (point) {
            0x9...0xd, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => {},
            else => return false,
        }
    }
    return true;
}
fn wrappedText(node: *Node, source: []const u8, width: usize, left: usize, output: *std.ArrayList([]u8)) !void {
    const content_width = @max(@as(usize, 1), width -| left * 2);
    const lines = try @import("native_text_wrap.zig").wrap(node.engine, source, content_width);
    defer {
        for (lines) |line| node.engine.gpa.free(line);
        node.engine.gpa.free(lines);
    }
    for (lines) |line| try appendOwned(node.engine, output, try padded(node, line, width, left));
}
fn render(node: *Node, object: c.JSValue, width: usize) !c.JSValue {
    const engine = node.engine;
    if (node.rendering) return error.NativeTuiComponentCycle;
    node.rendering = true;
    defer node.rendering = false;
    const revision = node.revision;
    if (node.kind != .container and node.kind != .box) if (node.cache) |cache| if (node.cache_width == width) return c.JS_DupValue(engine.context, cache);
    var output: std.ArrayList([]u8) = .empty;
    defer {
        for (output.items) |line| engine.gpa.free(line);
        output.deinit(engine.gpa);
    }
    if (node.kind == .spacer) {
        const amount = try count(engine, node.padding_y, true);
        if (amount > components.maximum_lines) return error.NativeComponentFrameLimit;
        for (0..amount) |_| try appendOwned(engine, &output, try engine.gpa.dupe(u8, ""));
    } else if (node.kind == .text) {
        const source = if (c.JS_ToBool(engine.context, node.text) == 0) try engine.gpa.dupe(u8, "") else blk: {
            if (!c.JS_IsString(node.text)) return error.InvalidNativeTuiText;
            break :blk try engine.toString(node.text);
        };
        defer engine.gpa.free(source);
        if (source.len > components.maximum_frame_bytes) return error.NativeComponentFrameLimit;
        if (!blankText(source)) {
            const left = @min(try count(engine, node.padding_x, false), (width -| 1) / 2);
            const vertical = try count(engine, node.padding_y, true);
            if (vertical > components.maximum_lines / 2) return error.NativeComponentFrameLimit;
            var normalized: std.ArrayList(u8) = .empty;
            defer normalized.deinit(engine.gpa);
            for (source) |byte| if (byte == '\t') {
                try normalized.appendSlice(engine.gpa, "   ");
            } else {
                try normalized.append(engine.gpa, byte);
            };
            for (0..vertical) |_| try appendOwned(engine, &output, try padded(node, "", width, 0));
            try wrappedText(node, normalized.items, width, left, &output);
            for (0..vertical) |_| try appendOwned(engine, &output, try padded(node, "", width, 0));
        }
    } else {
        const array = try children(engine, object);
        defer engine.freeValue(array);
        const length = try engine.checked(c.JS_GetPropertyStr(engine.context, array, "length"));
        defer engine.freeValue(length);
        const amount = try count(engine, length, false);
        if (amount > components.maximum_lines) return error.NativeTuiChildrenLimit;
        const left = try count(engine, node.padding_x, false);
        const vertical = try count(engine, node.padding_y, true);
        const inner_width = @max(@as(usize, 1), width -| left * 2);
        const mouse_children = try engine.checked(c.JS_NewArray(engine.context));
        defer engine.freeValue(mouse_children);
        var rendered: std.ArrayList([]u8) = .empty;
        defer {
            for (rendered.items) |line| engine.gpa.free(line);
            rendered.deinit(engine.gpa);
        }
        for (0..amount) |index| {
            const child = try engine.checked(c.JS_GetPropertyUint32(engine.context, array, @intCast(index)));
            defer engine.freeValue(child);
            var args = [_]c.JSValue{c.JS_NewInt64(engine.context, @intCast(if (node.kind == .box) inner_width else width))};
            defer engine.freeValue(args[0]);
            const pending = (try components.callMethod(engine, child, "render", &args, false)).?;
            defer engine.freeValue(pending);
            const result = try engine.awaitValue(pending);
            defer engine.freeValue(result);
            var frame = try components.normalizeWithPredicate(engine, result, node.array_is_array);
            defer frame.deinit();
            const mouse_child = try engine.checked(c.JS_NewObject(engine.context));
            var child_transferred = false;
            defer if (!child_transferred) engine.freeValue(mouse_child);
            try define(engine, mouse_child, "component", c.JS_DupValue(engine.context, child));
            try define(engine, mouse_child, "height", try engine.checked(c.JS_GetPropertyStr(engine.context, result, "length")));
            child_transferred = true;
            if (c.JS_SetPropertyUint32(engine.context, mouse_children, @intCast(index), mouse_child) < 0) return error.JavaScriptException;
            for (frame.lines) |line| try appendOwned(engine, &rendered, try engine.gpa.dupe(u8, line));
        }
        const mouse_layout = try engine.checked(c.JS_NewObject(engine.context));
        var mouse_transferred = false;
        defer if (!mouse_transferred) engine.freeValue(mouse_layout);
        try define(engine, mouse_layout, "width", c.JS_NewFloat64(engine.context, @floatFromInt(if (node.kind == .box) inner_width else width)));
        try define(engine, mouse_layout, "children", c.JS_DupValue(engine.context, mouse_children));
        mouse_transferred = true;
        try set(engine, object, "mouseLayout", mouse_layout);
        if (rendered.items.len != 0) {
            if (vertical > components.maximum_lines / 2) return error.NativeComponentFrameLimit;
            for (0..vertical) |_| try appendOwned(engine, &output, try padded(node, "", width, 0));
            for (rendered.items) |line| try appendOwned(engine, &output, if (node.kind == .box) try padded(node, line, width, left) else try engine.gpa.dupe(u8, line));
            for (0..vertical) |_| try appendOwned(engine, &output, try padded(node, "", width, 0));
        }
    }
    var bytes: usize = 0;
    for (output.items) |line| {
        if (line.len > components.maximum_frame_bytes - bytes) return error.NativeComponentFrameLimit;
        bytes += line.len;
    }
    const frame: components.Frame = .{ .gpa = engine.gpa, .lines = output.items, .bytes = bytes };
    const result = try components.frameToValue(&frame, engine);
    if ((node.kind == .text or node.kind == .spacer) and node.revision == revision) {
        if (node.cache) |previous| engine.freeValue(previous);
        node.cache = c.JS_DupValue(engine.context, result);
        node.cache_width = width;
    }
    return result;
}

const Helper = enum(c_int) { visibleWidth, matchesKey, parseKey, isKeyRelease, isKeyRepeat, decodePrintableKey, decodeKittyPrintable, setKittyProtocolActive, isKittyProtocolActive, truncateToWidth, wrapTextWithAnsi, renderFakeCursor };
fn helperCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return helper(engine, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn helper(engine: *engine_mod.Engine, method: Helper, args: []c.JSValue) !c.JSValue {
    if (method == .renderFakeCursor) {
        const text = try engine.toString(if (args.len > 0) args[0] else c.pi_js_undefined());
        defer engine.gpa.free(text);
        const wrapped = try std.fmt.allocPrint(engine.gpa, "{s}{s}{s}", .{ @import("../tui/cursor_markers.zig").fake_start, text, @import("../tui/cursor_markers.zig").fake_end });
        defer engine.gpa.free(wrapped);
        return engine.checked(c.JS_NewStringLen(engine.context, wrapped.ptr, wrapped.len));
    }
    if (method == .isKittyProtocolActive) return c.pi_js_bool(engine.context, @intFromBool(keys.isKittyProtocolActive()));
    if (method == .setKittyProtocolActive) {
        keys.setKittyProtocolActive(args.len != 0 and c.JS_ToBool(engine.context, args[0]) != 0);
        return c.pi_js_undefined();
    }
    if (args.len == 0 or !c.JS_IsString(args[0])) return error.InvalidNativeTuiText;
    if (method == .visibleWidth) {
        const units = try @import("native_utf16.zig").unitsAlloc(engine, args[0]);
        defer engine.gpa.free(units);
        const width = try @import("../tui/utf16_terminal.zig").visibleWidth(engine.gpa, units);
        return engine.checked(c.JS_NewInt64(engine.context, @intCast(width)));
    }
    if (method == .wrapTextWithAnsi) {
        const units = try @import("native_utf16.zig").unitsAlloc(engine, args[0]);
        defer engine.gpa.free(units);
        var width: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &width, if (args.len > 1) args[1] else c.pi_js_undefined()) < 0) return @import("native_js_values.zig").capture(engine);
        const lines = try @import("native_utf16_wrap.zig").wrap(engine, units, width);
        defer {
            for (lines) |line| engine.gpa.free(line);
            engine.gpa.free(lines);
        }
        const result = try @import("native_js_values.zig").array(engine);
        errdefer engine.freeValue(result);
        for (lines, 0..) |line, index| if (c.JS_SetPropertyUint32(engine.context, result, @intCast(index), try @import("native_utf16.zig").string(engine, line)) < 0) return @import("native_js_values.zig").capture(engine);
        return result;
    }
    if (method == .truncateToWidth) {
        const units = try @import("native_utf16.zig").unitsAlloc(engine, args[0]);
        defer engine.gpa.free(units);
        var width: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &width, if (args.len > 1) args[1] else c.pi_js_undefined()) < 0) return @import("native_js_values.zig").capture(engine);
        const ellipsis = if (args.len > 2 and !c.JS_IsUndefined(args[2])) try @import("native_utf16.zig").unitsAlloc(engine, args[2]) else try engine.gpa.dupe(u16, std.unicode.utf8ToUtf16LeStringLiteral("..."));
        defer engine.gpa.free(ellipsis);
        const clipped = try @import("../tui/utf16_terminal.zig").truncateOptionsAlloc(engine.gpa, units, width, ellipsis, args.len > 3 and c.JS_ToBool(engine.context, args[3]) != 0);
        defer engine.gpa.free(clipped);
        return @import("native_utf16.zig").string(engine, clipped);
    }
    const text = try engine.toString(args[0]);
    defer engine.gpa.free(text);
    return switch (method) {
        .matchesKey => blk: {
            if (args.len < 2 or !c.JS_IsString(args[1])) return error.InvalidNativeTuiKey;
            const name = try engine.toString(args[1]);
            defer engine.gpa.free(name);
            break :blk c.pi_js_bool(engine.context, @intFromBool(keys.matchesKey(text, name)));
        },
        .isKeyRelease => c.pi_js_bool(engine.context, @intFromBool(keys.isKeyRelease(text))),
        .isKeyRepeat => c.pi_js_bool(engine.context, @intFromBool(keys.isKeyRepeat(text))),
        .parseKey => blk: {
            const parsed = keys.parseKey(text) orelse break :blk c.pi_js_undefined();
            const name = try parsed.formatAlloc(engine.gpa);
            defer engine.gpa.free(name);
            break :blk try engine.checked(c.JS_NewStringLen(engine.context, name.ptr, name.len));
        },
        .decodeKittyPrintable => try @import("native_input.zig").decodeKittyPrintable(engine, text),
        .decodePrintableKey => blk: {
            const decoded = try keys.decodePrintableKey(engine.gpa, text) orelse break :blk c.pi_js_undefined();
            defer engine.gpa.free(decoded);
            break :blk try engine.checked(c.JS_NewStringLen(engine.context, decoded.ptr, decoded.len));
        },
        else => unreachable,
    };
}
fn keyCombination(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const prefix = engine.toString(data[0]) catch |err| return fail(engine, err);
    defer engine.gpa.free(prefix);
    const key = engine.toString(if (argc == 0) c.pi_js_undefined() else argv[0]) catch |err| return fail(engine, err);
    defer engine.gpa.free(key);
    const encoded = std.fmt.allocPrint(engine.gpa, "{s}{s}", .{ prefix, key }) catch |err| return fail(engine, err);
    defer engine.gpa.free(encoded);
    return c.JS_NewStringLen(context, encoded.ptr, encoded.len);
}

pub fn install(engine: *engine_mod.Engine) !void {
    if (engine.native_module_names.contains("@earendil-works/pi-tui")) return;
    var node_class: c.JSClassID = 0;
    var constructor_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &node_class);
    _ = c.JS_NewClassID(engine.runtime, &constructor_class);
    const node_definition: c.JSClassDef = .{ .class_name = "Native TUI Component", .finalizer = nodeFinalizer, .gc_mark = nodeMark, .call = null, .exotic = null };
    const constructor_definition: c.JSClassDef = .{ .class_name = "Native TUI Constructor", .finalizer = constructorFinalizer, .gc_mark = constructorMark, .call = constructorCall, .exotic = null };
    if (c.JS_NewClass(engine.runtime, node_class, &node_definition) < 0 or c.JS_NewClass(engine.runtime, constructor_class, &constructor_definition) < 0) return error.OutOfMemory;
    const exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(exports);
    try @import("native_color.zig").install(engine, exports);
    try @import("native_mouse.zig").install(engine, exports);
    try @import("native_keybindings.zig").install(engine, exports);
    try @import("native_input.zig").install(engine, exports);
    try @import("native_select_list.zig").install(engine, exports);
    try @import("native_fuzzy.zig").install(engine, exports);
    try @import("native_terminal_image.zig").install(engine, exports);
    try @import("native_settings_list.zig").install(engine, exports);
    try define(engine, exports, "CURSOR_MARKER", try engine.checked(c.JS_NewString(engine.context, @import("../tui/cursor_markers.zig").cursor)));
    const array_is_array = try components.arrayPredicate(engine);
    defer engine.freeValue(array_is_array);
    inline for (std.meta.fields(Helper)) |field| {
        const name: [:0]const u8 = field.name;
        const arity: c_int = switch (@as(Helper, @enumFromInt(field.value))) {
            .matchesKey, .truncateToWidth, .wrapTextWithAnsi => 2,
            .isKittyProtocolActive => 0,
            else => 1,
        };
        try define(engine, exports, name.ptr, try engine.checked(c.pi_js_function_magic(engine.context, helperCall, name.ptr, arity, @intCast(field.value))));
    }
    const key = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(key);
    inline for (.{ "escape", "esc", "enter", "return", "tab", "space", "backspace", "delete", "insert", "clear", "home", "end", "pageUp", "pageDown", "up", "down", "left", "right", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12" }) |name| try define(engine, key, name, try engine.checked(c.JS_NewString(engine.context, name)));
    inline for (.{ .{ "backtick", "`" }, .{ "hyphen", "-" }, .{ "equals", "=" }, .{ "leftbracket", "[" }, .{ "rightbracket", "]" }, .{ "backslash", "\\" }, .{ "semicolon", ";" }, .{ "quote", "'" }, .{ "comma", "," }, .{ "period", "." }, .{ "slash", "/" }, .{ "exclamation", "!" }, .{ "at", "@" }, .{ "hash", "#" }, .{ "dollar", "$" }, .{ "percent", "%" }, .{ "caret", "^" }, .{ "ampersand", "&" }, .{ "asterisk", "*" }, .{ "leftparen", "(" }, .{ "rightparen", ")" }, .{ "underscore", "_" }, .{ "plus", "+" }, .{ "pipe", "|" }, .{ "tilde", "~" }, .{ "leftbrace", "{" }, .{ "rightbrace", "}" }, .{ "colon", ":" }, .{ "lessthan", "<" }, .{ "greaterthan", ">" }, .{ "question", "?" } }) |symbol| try define(engine, key, symbol[0], try engine.checked(c.JS_NewString(engine.context, symbol[1])));
    inline for (.{ "ctrl", "shift", "alt", "super", "ctrlShift", "shiftCtrl", "ctrlAlt", "altCtrl", "shiftAlt", "altShift", "ctrlSuper", "superCtrl", "shiftSuper", "superShift", "altSuper", "superAlt", "ctrlShiftAlt", "ctrlShiftSuper" }) |name| {
        var prefix: std.ArrayList(u8) = .empty;
        defer prefix.deinit(engine.gpa);
        for (name, 0..) |byte, index| {
            if (std.ascii.isUpper(byte) and index != 0) try prefix.append(engine.gpa, '+');
            try prefix.append(engine.gpa, std.ascii.toLower(byte));
        }
        try prefix.append(engine.gpa, '+');
        var data = [_]c.JSValue{try engine.checked(c.JS_NewStringLen(engine.context, prefix.items.ptr, prefix.items.len))};
        defer engine.freeValue(data[0]);
        try define(engine, key, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, keyCombination, name, 1, 0, 1, &data)));
    }
    try define(engine, exports, "Key", c.JS_DupValue(engine.context, key));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const function_type = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Function"));
    defer engine.freeValue(function_type);
    const function_prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, function_type, "prototype"));
    defer engine.freeValue(function_prototype);
    inline for (.{ .{ "Text", Kind.text }, .{ "Container", Kind.container }, .{ "Box", Kind.box }, .{ "Spacer", Kind.spacer } }) |item| {
        const prototype = try engine.checked(c.JS_NewObject(engine.context));
        defer engine.freeValue(prototype);
        inline for (.{ .{ "render", Method.render }, .{ "invalidate", Method.invalidate }, .{ "setText", Method.setText }, .{ "setLines", Method.setLines }, .{ "setCustomBgFn", Method.setBgFn }, .{ "setBgFn", Method.setBgFn }, .{ "addChild", Method.addChild }, .{ "removeChild", Method.removeChild }, .{ "clear", Method.clear }, .{ "handleMouse", Method.handleMouse } }) |operation_name| {
            const available = operation_name[1] == .render or operation_name[1] == .invalidate or
                (item[1] == .text and (operation_name[1] == .setText or std.mem.eql(u8, operation_name[0], "setCustomBgFn"))) or
                (item[1] == .spacer and operation_name[1] == .setLines) or
                ((item[1] == .container or item[1] == .box) and (operation_name[1] == .addChild or operation_name[1] == .removeChild or operation_name[1] == .clear)) or
                ((item[1] == .container or item[1] == .box) and operation_name[1] == .handleMouse) or
                (item[1] == .box and std.mem.eql(u8, operation_name[0], "setBgFn"));
            if (available) {
                var data = [_]c.JSValue{c.JS_NewInt64(engine.context, node_class)};
                defer engine.freeValue(data[0]);
                try define(engine, prototype, operation_name[0], try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, operation_name[0], 1, @intFromEnum(operation_name[1]), 1, &data)));
            }
        }
        const constructor = try engine.checked(c.JS_NewObjectProtoClass(engine.context, function_prototype, constructor_class));
        defer engine.freeValue(constructor);
        const state = try engine.gpa.create(Constructor);
        state.* = .{ .engine = engine, .prototype = c.JS_DupValue(engine.context, prototype), .array_is_array = c.JS_DupValue(engine.context, array_is_array), .node_class = node_class, .kind = item[1] };
        _ = c.JS_SetOpaque(constructor, state);
        _ = c.JS_SetConstructorBit(engine.context, constructor, true);
        if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
        try define(engine, constructor, "name", try engine.checked(c.JS_NewString(engine.context, item[0])));
        try define(engine, exports, item[0], c.JS_DupValue(engine.context, constructor));
    }
    try @import("native_container_component.zig").install(engine, exports);
    try @import("native_text_component.zig").install(engine, exports);
    try @import("native_truncated_text.zig").install(engine, exports);
    try @import("native_loader.zig").install(engine, exports);
    try @import("native_tui_public_helpers.zig").install(engine, exports);
    try @import("native_image_component.zig").install(engine, exports);
    try @import("native_tui_columns.zig").install(engine, exports);
    try @import("native_stack_components.zig").install(engine, exports);
    try @import("native_scroll_view.zig").install(engine, exports);
    try @import("native_stdin_buffer.zig").install(engine, exports);
    try @import("native_process_terminal.zig").install(engine, exports);
    try @import("native_box_component.zig").install(engine, exports);
    try @import("native_spacer_component.zig").install(engine, exports);
    try @import("native_markdown_component.zig").install(engine, exports);
    try @import("native_editor.zig").install(engine, exports);
    try @import("native_tui_main_screen.zig").install(engine, exports);
    try @import("native_tui_function_metadata.zig").install(engine, exports);
    try engine.registerValueModule("@earendil-works/pi-tui", exports);
    try engine.registerValueModule("@mariozechner/pi-tui", exports);
    try engine.registerValueModule("pi-tui", exports);
}

test "native color exports preserve concrete frozen values validation and observable style reads" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const module = try engine.evalModule(
        \\import * as c from 'pi-tui';
        \\const rgb=c.rgbColor(1.5,2,255), index=c.indexedColor(255), lch=c.oklchColor(.5,.2,-30);
        \\for(const value of [rgb,index,lch,c.okhslColor(180,.5,.5),c.parseColor('#abc')])if(!Object.isFrozen(value))throw Error('unfrozen color');
        \\if(rgb.r!==1.5||index.index!==255||lch.h!==330||c.colorToHex(c.parseColor('#abc'))!=='#aabbcc')throw Error('channels');
        \\if(c.foregroundAnsi(rgb,'truecolor')!=='\x1b[38;2;2;2;255m'||c.backgroundAnsi(index,'truecolor')!=='\x1b[48;5;255m')throw Error('ansi');
        \\const failures=[[()=>c.indexedColor(1.5),'ANSI color index must be an integer from 0 to 255: 1.5'],[()=>c.rgbColor('1',0,0),'r must be finite'],[()=>c.rgbColor(0,256,0),'g must be between 0 and 255: 256'],[()=>c.okhslColor(0,Infinity,-1),'s must be finite'],[()=>c.oklchColor(.5,-1,0),'c must not be negative: -1'],[()=>c.parseColor('red'),'Invalid color value: red'],[()=>c.mixColors(rgb,rgb,2),'amount must be between 0 and 1: 2']];
        \\for(const [invoke,message]of failures){let actual;try{invoke()}catch(error){if(!(error instanceof Error))throw error;actual=error.message}if(actual!==message)throw Error(actual+' != '+message)}
        \\const reads=[];const options={get fg(){reads.push('fg');return rgb},get bg(){reads.push('bg');return index},get bold(){reads.push('bold');return true},get dim(){reads.push('dim');return false},get italic(){reads.push('italic');return false},get underline(){reads.push('underline');return false},get inverse(){reads.push('inverse');return false},get strikethrough(){reads.push('strikethrough');return false}};
        \\const styled=c.styleText('x',options,'truecolor');
        \\if(styled!=='\x1b[38;2;2;2;255m\x1b[48;5;255m\x1b[1mx\x1b[22m\x1b[49m\x1b[39m')throw Error('style');
        \\if(reads.join(',')!=='fg,fg,bg,bg,bold,dim,bold,italic,underline,inverse,strikethrough')throw Error('getter order '+reads);
        \\const marker={};try{c.colorToRgb({get kind(){throw marker}})}catch(error){if(error!==marker)throw Error('exception identity')}
        \\if(c.colorToRgb({kind:'other'})!==undefined)throw Error('switch fallback');
        \\globalThis.colorRoots=[rgb,index,lch,c.mixColors(rgb,c.rgbColor(255,0,0),.5,'srgb')];
    , "native-color-contract.mjs");
    defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval("if(colorRoots[0].r!==1.5||!Object.isFrozen(colorRoots[3]))throw Error('GC roots');delete globalThis.colorRoots;", "native-color-gc.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}

test "original color API results parser errors and all styles replay through exported native bindings" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const fixture = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("../tui/fixtures/colors-original-7fb.json"), .{});
    defer fixture.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try define(engine, global, "colorOracle", try engine.fromJsonValue(fixture.value));
    const module = try engine.evalModule(
        \\import * as c from 'pi-tui';
        \\function compare(expected,actual,path='root'){if(typeof expected==='number'&&typeof actual==='number'){if(Math.abs(expected-actual)>1e-10)throw Error(path+': '+expected+' != '+actual);return}if(expected&&typeof expected==='object'){if(!actual||Object.keys(expected).sort().join('|')!==Object.keys(actual).sort().join('|'))throw Error(path+' keys');for(const key of Object.keys(expected))compare(expected[key],actual[key],path+'.'+key);return}if(expected!==actual)throw Error(path+': '+expected+' != '+actual)}
        \\for(const item of colorOracle.cases){const color=c.parseColor(item.input);compare(item.color,color,'color');compare(item.rgb,c.colorToRgb(color),'rgb');compare(item.oklch,c.colorToOklch(color),'oklch');compare(item.okhsl,c.colorToOkhsl(color),'okhsl');compare(item.hex,c.colorToHex(color),'hex');compare(item.fgTrue,c.foregroundAnsi(color,'truecolor'));compare(item.fg256,c.foregroundAnsi(color,'256color'));compare(item.bgTrue,c.backgroundAnsi(color,'truecolor'));compare(item.bg256,c.backgroundAnsi(color,'256color'));if(!Object.isFrozen(color)||Object.isFrozen(c.colorToRgb(color)))throw Error('record freeze contract')}
        \\for(const item of colorOracle.invalid){let error=null;try{c.parseColor(item.input)}catch(caught){error=caught.message}compare(item.error,error,'invalid '+item.input)}
        \\for(const item of colorOracle.mix){const value=c.mixColors(c.parseColor(item.first),c.parseColor(item.second),item.amount,item.space);compare(item.color,value,'mix');compare(item.rgb,c.colorToRgb(value),'mix rgb');compare(item.hex,c.colorToHex(value),'mix hex')}
        \\for(const item of colorOracle.styles){const options=Object.fromEntries(['bold','dim','italic','underline','inverse','strikethrough'].map((name,index)=>[name,!!(item.flags&(1<<index))]));compare(item.value,c.styleTextWithAnsi('first\nsecond','\x1b[38;2;18;171;205m','\x1b[48;5;244m',options),'style '+item.flags)}delete globalThis.colorOracle;
    , "native-color-original-all.mjs");
    defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
}

test "original structural RGB exceptional magnitudes and indexed ANSI retain guest math semantics without native casts" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const fixture = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("fixtures/color-structural-original-7fb.json"), .{});
    defer fixture.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try define(engine, global, "structuralOracle", try engine.fromJsonValue(fixture.value));
    const module = try engine.evalModule(
        \\import {colorToHex,foregroundAnsi,backgroundAnsi} from 'pi-tui';
        \\for(const item of structuralOracle.cases){const value=eval(item.input);for(const [key,actual]of [['fgTrue',foregroundAnsi(value,'truecolor')],['bgTrue',backgroundAnsi(value,'truecolor')],['fg256',foregroundAnsi(value,'256color')],...(item.hex!==undefined?[['hex',colorToHex(value)]]:[])])if(actual!==item[key])throw Error(key+' '+item.input+' '+JSON.stringify(actual)+' != '+JSON.stringify(item[key]));}delete globalThis.structuralOracle;
    , "native-color-structural-original.mjs");
    defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
}

fn themeCall(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return themeOperation(engine, receiver, magic, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn themeOperation(engine: *engine_mod.Engine, receiver: c.JSValue, magic: c_int, args: []c.JSValue) !c.JSValue {
    if (magic == 10) return engine.checked(c.JS_GetPropertyStr(engine.context, receiver, "_nativeColorMode"));
    const color_magic: ?c_int = switch (magic) {
        0, 8 => 0,
        1, 9 => 1,
        else => null,
    };
    const opening_only = magic == 8 or magic == 9;
    const index: usize = if (color_magic != null) 1 else 0;
    const text = if (opening_only) try engine.gpa.dupe(u8, "") else try engine.toString(if (args.len > index) args[index] else c.pi_js_undefined());
    defer engine.gpa.free(text);
    if (color_magic != null and c.JS_IsObject(receiver)) {
        const colors = try engine.checked(c.JS_GetPropertyStr(engine.context, receiver, "_nativeColors"));
        defer engine.freeValue(colors);
        if (c.JS_IsObject(colors)) {
            const name = try engine.toString(if (args.len > 0) args[0] else c.pi_js_undefined());
            defer engine.gpa.free(name);
            const name_z = try engine.gpa.dupeZ(u8, name);
            defer engine.gpa.free(name_z);
            const selected = try engine.checked(c.JS_GetPropertyStr(engine.context, colors, name_z.ptr));
            defer engine.freeValue(selected);
            if (c.JS_IsString(selected)) {
                const foreground = try engine.toString(selected);
                defer engine.gpa.free(foreground);
                const parameters = if (color_magic.? == 0) try engine.gpa.dupe(u8, foreground) else if (std.mem.startsWith(u8, foreground, "38;")) try std.mem.concat(engine.gpa, u8, &.{ "48", foreground[2..] }) else blk: {
                    const number = std.fmt.parseInt(u16, foreground, 10) catch 39;
                    break :blk try std.fmt.allocPrint(engine.gpa, "{d}", .{number + 10});
                };
                defer engine.gpa.free(parameters);
                const dim_tokens = try engine.checked(c.JS_GetPropertyStr(engine.context, receiver, "_nativeDim"));
                defer engine.freeValue(dim_tokens);
                const dim_token = if (c.JS_IsObject(dim_tokens)) try engine.checked(c.JS_GetPropertyStr(engine.context, dim_tokens, name_z.ptr)) else c.pi_js_undefined();
                defer engine.freeValue(dim_token);
                const faint = color_magic.? == 0 and c.JS_ToBool(engine.context, dim_token) == 1;
                const painted = if (opening_only) try std.fmt.allocPrint(engine.gpa, "\x1b[{s}m{s}", .{ parameters, if (faint) "\x1b[2m" else "" }) else try std.fmt.allocPrint(engine.gpa, "\x1b[{s}m{s}{s}\x1b[{s}m", .{ parameters, if (faint) "\x1b[2m" else "", text, if (faint) "22;39" else if (color_magic.? == 0) "39" else "49" });
                defer engine.gpa.free(painted);
                return engine.checked(c.JS_NewStringLen(engine.context, painted.ptr, painted.len));
            }
            const unknown = try engine.checked(c.JS_NewError(engine.context));
            defer engine.freeValue(unknown);
            const message = try std.fmt.allocPrint(engine.gpa, "Unknown theme color: {s}", .{name});
            defer engine.gpa.free(message);
            try define(engine, unknown, "message", try engine.checked(c.JS_NewStringLen(engine.context, message.ptr, message.len)));
            _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, unknown)));
            return error.JavaScriptException;
        }
    }
    const style: []const u8 = if (color_magic != null) blk: {
        const name = try engine.toString(if (args.len > 0) args[0] else c.pi_js_undefined());
        defer engine.gpa.free(name);
        const foreground: []const u8 = if (std.mem.eql(u8, name, "error")) "31" else if (std.mem.eql(u8, name, "success")) "32" else if (std.mem.eql(u8, name, "warning")) "33" else if (std.mem.eql(u8, name, "accent") or std.mem.eql(u8, name, "border")) "36" else if (std.mem.eql(u8, name, "dim") or std.mem.eql(u8, name, "muted")) "90" else "39";
        if (color_magic.? == 1) break :blk if (std.mem.eql(u8, name, "error")) "41" else if (std.mem.eql(u8, name, "success")) "42" else if (std.mem.eql(u8, name, "warning")) "43" else "49";
        break :blk foreground;
    } else switch (magic) {
        2 => "1",
        3 => "2",
        4 => "3",
        5 => "4",
        6 => "7",
        else => "9",
    };
    const closing: []const u8 = switch (magic) {
        0 => "39",
        1 => "49",
        2, 3 => "22",
        4 => "23",
        5 => "24",
        6 => "27",
        else => "29",
    };
    const painted = if (opening_only) try std.fmt.allocPrint(engine.gpa, "\x1b[{s}m", .{style}) else try std.fmt.allocPrint(engine.gpa, "\x1b[{s}m{s}\x1b[{s}m", .{ style, text, closing });
    defer engine.gpa.free(painted);
    return engine.checked(c.JS_NewStringLen(engine.context, painted.ptr, painted.len));
}
pub fn createTheme(engine: *engine_mod.Engine) !c.JSValue {
    const object = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(object);
    try define(engine, object, "name", try engine.checked(c.JS_NewString(engine.context, "default")));
    try define(engine, object, "_nativeColorMode", try engine.checked(c.JS_NewString(engine.context, if (try themeTrueColor(engine)) "truecolor" else "256color")));
    inline for (.{ "fg", "bg", "bold", "dim", "italic", "underline", "inverse", "strikethrough", "getFgAnsi", "getBgAnsi", "getColorMode" }, 0..) |name, index| try define(engine, object, name, try engine.checked(c.pi_js_function_magic(engine.context, themeCall, name, if (index < 2) 2 else if (index == 10) 0 else 1, @intCast(index))));
    return object;
}
pub fn themeTrueColor(engine: *engine_mod.Engine) !bool {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const process = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "process"));
    defer engine.freeValue(process);
    // Bare embedded-engine component tests have no terminal binding.
    if (!c.JS_IsObject(process)) return true;
    const variables = try engine.checked(c.JS_GetPropertyStr(engine.context, process, "env"));
    defer engine.freeValue(variables);
    if (!c.JS_IsObject(variables)) return true;
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const images = @import("../tui/terminal_image.zig");
    var env: images.Environment = .{};
    inline for (.{ .{ "term_program", "TERM_PROGRAM" }, .{ "terminal_emulator", "TERMINAL_EMULATOR" }, .{ "term", "TERM" }, .{ "color_term", "COLORTERM" }, .{ "tmux", "TMUX" }, .{ "kitty_window_id", "KITTY_WINDOW_ID" }, .{ "ghostty_resources_dir", "GHOSTTY_RESOURCES_DIR" }, .{ "wezterm_pane", "WEZTERM_PANE" }, .{ "warp_session_id", "WARP_SESSION_ID" }, .{ "warp_terminal_session_uuid", "WARP_TERMINAL_SESSION_UUID" }, .{ "iterm_session_id", "ITERM_SESSION_ID" }, .{ "wt_session", "WT_SESSION" }, .{ "pi_true_color", "PI_TRUE_COLOR" } }) |field| {
        const value = try engine.checked(c.JS_GetPropertyStr(engine.context, variables, field[1]));
        defer engine.freeValue(value);
        if (c.JS_IsString(value)) {
            const text = try engine.toString(value);
            defer engine.gpa.free(text);
            @field(env, field[0]) = try arena.allocator().dupe(u8, text);
        }
    }
    return images.detectCapabilities(env, @import("builtin").os.tag == .windows, false).true_color;
}
fn ansi256(r: f64, g: f64, b: f64) u16 {
    const cube = [_]f64{ 0, 95, 135, 175, 215, 255 };
    var indices = [_]usize{0} ** 3;
    for ([_]f64{ r, g, b }, 0..) |value, channel| {
        for (cube, 0..) |candidate, index| if (@abs(value - candidate) < @abs(value - cube[indices[channel]])) {
            indices[channel] = index;
        };
    }
    const gray = @round(0.299 * r + 0.587 * g + 0.114 * b);
    var gray_index: u16 = 0;
    var distance: f64 = @abs(gray - 8);
    for (1..24) |index| {
        const next = @abs(gray - @as(f64, @floatFromInt(8 + index * 10)));
        if (next < distance) {
            distance = next;
            gray_index = @intCast(index);
        }
    }
    const level: f64 = @floatFromInt(8 + gray_index * 10);
    const gray_distance = 0.299 * (r - level) * (r - level) + 0.587 * (g - level) * (g - level) + 0.114 * (b - level) * (b - level);
    const cube_distance = 0.299 * (r - cube[indices[0]]) * (r - cube[indices[0]]) + 0.587 * (g - cube[indices[1]]) * (g - cube[indices[1]]) + 0.114 * (b - cube[indices[2]]) * (b - cube[indices[2]]);
    return if (@max(r, @max(g, b)) - @min(r, @min(g, b)) < 10 and gray_distance < cube_distance) 232 + gray_index else @intCast(16 + 36 * indices[0] + 6 * indices[1] + indices[2]);
}
pub fn hydrateTheme(engine: *engine_mod.Engine, target: c.JSValue, resource: c.JSValue) !void {
    if (!c.JS_IsObject(resource)) return;
    const encoded = try engine.stringify(resource);
    defer engine.gpa.free(encoded);
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const root = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), encoded, .{});
    if (root != .object) return error.InvalidNativeTheme;
    const colors_value = root.object.get("colors") orelse return error.InvalidNativeTheme;
    if (colors_value != .object) return error.InvalidNativeTheme;
    const variables = root.object.getPtr("vars");
    const vars = if (variables) |value| if (value.* == .object) &value.object else null else null;
    const colors = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(colors);
    const color_mode = try engine.checked(c.JS_GetPropertyStr(engine.context, target, "_nativeColorMode"));
    defer engine.freeValue(color_mode);
    const mode = try engine.toString(color_mode);
    defer engine.gpa.free(mode);
    var entries = colors_value.object.iterator();
    while (entries.next()) |entry| {
        var stack: std.ArrayList([]const u8) = .empty;
        const resolved = try @import("../themes/theme.zig").resolveColor(arena.allocator(), entry.value_ptr.*, vars, &stack);
        const sgr = if (std.mem.eql(u8, mode, "256color") and std.mem.startsWith(u8, resolved.sgr, "38;2;")) blk: {
            var channels = std.mem.splitScalar(u8, resolved.sgr[5..], ';');
            const r = try std.fmt.parseFloat(f64, channels.next() orelse return error.InvalidNativeTheme);
            const g = try std.fmt.parseFloat(f64, channels.next() orelse return error.InvalidNativeTheme);
            const b = try std.fmt.parseFloat(f64, channels.next() orelse return error.InvalidNativeTheme);
            break :blk try std.fmt.allocPrint(arena.allocator(), "38;5;{d}", .{ansi256(r, g, b)});
        } else resolved.sgr;
        const name = try arena.allocator().dupeZ(u8, entry.key_ptr.*);
        try define(engine, colors, name, try engine.checked(c.JS_NewStringLen(engine.context, sgr.ptr, sgr.len)));
    }
    if (root.object.get("name")) |name| if (name == .string) try define(engine, target, "name", try engine.checked(c.JS_NewStringLen(engine.context, name.string.ptr, name.string.len)));
    try define(engine, target, "_nativeColors", c.JS_DupValue(engine.context, colors));
    const faint = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(faint);
    if (root.object.get("dim")) |list| if (list == .array) for (list.array.items) |item| {
        if (item != .string) continue;
        const name = try arena.allocator().dupeZ(u8, item.string);
        try define(engine, faint, name, c.pi_js_bool(engine.context, 1));
    };
    try define(engine, target, "_nativeDim", c.JS_DupValue(engine.context, faint));
}
pub fn createKeybindings(engine: *engine_mod.Engine) !c.JSValue {
    return @import("native_keybindings.zig").getEditor(engine);
}

test "native hydrated theme methods replay actual original ANSI color modes dim tokens and unknown errors" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var capture = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("fixtures/theme-methods-original-7fb.json"), .{});
    defer capture.deinit();
    for (capture.value.object.get("values").?.array.items) |source| {
        const theme = try createTheme(engine);
        defer engine.freeValue(theme);
        const mode = source.object.get("mode").?.string;
        try define(engine, theme, "_nativeColorMode", try engine.checked(c.JS_NewStringLen(engine.context, mode.ptr, mode.len)));
        const resource = try engine.eval("({name:'source-theme',vars:{accent:'#12abcd'},colors:{accent:'accent',dim:244},dim:['dim']})", "native-theme-original-resource.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(resource);
        try hydrateTheme(engine, theme, resource);
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        if (c.JS_SetPropertyStr(engine.context, global, "sourceTheme", c.JS_DupValue(engine.context, theme)) < 0) return error.JavaScriptException;
        c.JS_RunGC(engine.runtime);
        const observation = try engine.eval("({mode:sourceTheme.getColorMode(),fg:sourceTheme.fg('accent','a\\nb'),bg:sourceTheme.bg('accent','x'),dim:sourceTheme.fg('dim','dim'),fgAnsi:sourceTheme.getFgAnsi('dim'),bgAnsi:sourceTheme.getBgAnsi('accent'),unknown:(()=>{try{sourceTheme.fg('missing','x')}catch(error){return error.message}})()})", "native-theme-original-observation.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(observation);
        const actual = try engine.stringify(observation);
        defer engine.gpa.free(actual);
        const expected = try std.json.Stringify.valueAlloc(engine.gpa, source, .{});
        defer engine.gpa.free(expected);
        try std.testing.expectEqualStrings(expected, actual);
    }
}

fn focusContainmentOwnershipCase(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const module = try engine.evalModule("import {Container,Box} from '@earendil-works/pi-tui';export const target={};export const missing={};export const root=new Container();root.addChild(target);root.addChild(root);export const box=new Box();box.addChild(target);export const fake={get children(){throw Error('plain object children must not be visited')}};", "focus-containment-input.mjs");
    defer engine.freeValue(module);
    const root = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "root"));
    defer engine.freeValue(root);
    const target = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "target"));
    defer engine.freeValue(target);
    const missing = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "missing"));
    defer engine.freeValue(missing);
    const box = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "box"));
    defer engine.freeValue(box);
    const fake = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "fake"));
    defer engine.freeValue(fake);
    // Isolate the new owned traversal allocations from constructor setup while
    // retaining genuine native objects and GC roots throughout every failure.
    const original_allocator = engine.gpa;
    engine.gpa = gpa;
    defer engine.gpa = original_allocator;
    defer engine.beginInvocation();
    try std.testing.expect(try focusContainsNormalized(engine, root, target));
    if (focusContainsNormalized(engine, root, missing)) |_| {
        return error.ExpectedNativeContainmentCycleFailure;
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.JavaScriptException, err);
    }
    try std.testing.expect(!try focusContainsNormalized(engine, box, target));
    try std.testing.expect(!try focusContainsNormalized(engine, fake, target));
    engine.beginInvocation();
    engine.gpa = original_allocator;
    c.JS_RunGC(engine.runtime);
}
fn focusContainsNormalized(engine: *engine_mod.Engine, root: c.JSValue, target: c.JSValue) !bool {
    return containsComponent(engine, root, target) catch |err| return @import("native_text_component.zig").allocationError(engine, err);
}

test "native focus containment is Source instanceof bounded cycle safe and releases every failed traversal allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, focusContainmentOwnershipCase, .{});
}

test "native TUI classes preserve constructors aliases children mutation Unicode padding and render cache" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const module = engine.evalModule("import {Text,Box,Container,Spacer} from '@earendil-works/pi-tui';import {Text as Alias} from '@mariozechner/pi-tui';if(Alias!==Text)throw Error('alias');const text=new Text('hello world',0,0);if(!(text instanceof Text)||text.render(7).join('|')!=='hello  |world  ')throw Error('word wrap');if(text.render(7)!==text.render(7))throw Error('cache');text.setText('界😀');if(text.render(6)[0]!=='界😀  ')throw Error('unicode');class Derived extends Text{};if(!(new Derived('x',0,0) instanceof Derived))throw Error('subclass');const box=new Box(1,1);box.addChild(new Text('x',0,0));if(box.render(6).join('|')!=='      | x    |      ')throw Error('box');const container=new Container();container.addChild(text);container.addChild(new Spacer(2));if(container.render(6).length!==3)throw Error('children');container.removeChild(text);if(container.render(6).length!==2)throw Error('remove');container.clear();if(container.children.length!==0)throw Error('clear');let branded=false;try{text.render.call(null,3)}catch(e){branded=e instanceof TypeError}if(!branded)throw Error('brand');", "native-tui-components.mjs") catch |err| {
        std.debug.print("Native TUI fixture failed: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
}

test "native component control queue owns accepted controls and rejects every mismatched fence" {
    const gpa = std.testing.allocator;
    var queue = ControlQueue.init(gpa, std.testing.io);
    defer queue.deinit();
    const fence: Fence = .{ .token = 1, .generation = 2, .invocation_id = 3, .component_id = 4 };
    queue.reset(fence);
    for (0..4) |index| {
        var stale = fence;
        switch (index) {
            0 => stale.token += 1,
            1 => stale.generation += 1,
            2 => stale.invocation_id += 1,
            else => stale.component_id += 1,
        }
        var control: Control = .{ .gpa = gpa, .fence = stale, .kind = .{ .input = try gpa.dupe(u8, "owned") } };
        defer control.deinit();
        try std.testing.expectError(error.StaleNativeComponentControl, queue.send(control));
    }
    try queue.send(.{ .gpa = gpa, .fence = fence, .kind = .{ .input = try gpa.dupe(u8, "accepted") } });
    var control = (try queue.next()).?;
    defer control.deinit();
    try std.testing.expectEqualStrings("accepted", control.kind.input);
    try queue.send(.{ .gpa = gpa, .fence = fence, .kind = .{ .input = try gpa.dupe(u8, "discarded") } });
    queue.reset(null);
    try std.testing.expectEqual(@as(usize, 0), queue.queued_bytes);
    queue.stop();
    try std.testing.expect((try queue.next()) == null);
}

test "native TUI keyboard and width helpers use native terminal rules and explicit undefined constructor defaults" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const module = try engine.evalModule("import {Text,Spacer,Key,matchesKey,parseKey,isKeyRelease,visibleWidth} from 'pi-tui';if(Key.ctrl('c')!=='ctrl+c'||Key.ctrlShiftAlt('x')!=='ctrl+shift+alt+x'||Key.question!=='?')throw Error('Key');if(!matchesKey('\\x03',Key.ctrl('c'))||parseKey('\\x1b[A')!=='up'||!isKeyRelease('\\x1b[97;1:3u'))throw Error('native keys');if(visibleWidth('界😀e\\u0301')!==5)throw Error('width');if(new Text(undefined,undefined,undefined).render(5).length!==0||new Spacer(undefined).render(5).length!==1)throw Error('default');if(new Text('\\u00a0\\u2000\\ufeff').render(5).length!==0)throw Error('Unicode whitespace');if(new Text('界😀',0,0).render(1).join('|')!==' |界| |😀')throw Error('narrow grapheme loss');", "native-tui-helpers.mjs");
    defer engine.freeValue(module);
}

test "native TUI input queue admits teardown ahead of saturated input and then fences late controls" {
    const gpa = std.testing.allocator;
    var queue = ControlQueue.init(gpa, std.testing.io);
    defer queue.deinit();
    const fence: Fence = .{ .token = 1, .generation = 1, .invocation_id = 1, .component_id = 1 };
    queue.reset(fence);
    for (0..128) |_| try queue.send(.{ .gpa = gpa, .fence = fence, .kind = .{ .input = try gpa.dupe(u8, "pending") } });
    try queue.send(.{ .gpa = gpa, .fence = fence, .kind = .cancel });
    var cancelled = (try queue.next()).?;
    defer cancelled.deinit();
    try std.testing.expect(cancelled.kind == .cancel);
    try std.testing.expectEqual(@as(usize, 0), queue.queued_bytes);
    try std.testing.expectError(error.NativeComponentChannelClosing, queue.send(.{ .gpa = gpa, .fence = fence, .kind = .invalidate }));
    queue.reset(fence);
    try queue.send(.{ .gpa = gpa, .fence = fence, .kind = .invalidate });
    var reused = (try queue.next()).?;
    defer reused.deinit();
}

fn tuiAllocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try install(engine);
    // Class state allocation failures cross the C callback boundary as native
    // JS OutOfMemory. Inspect its C string without allocating another Zig copy.
    const module = engine.evalModule("import {Text,Box} from 'pi-tui';const box=new Box(1,1);box.addChild(new Text('owned',0,0));box.render(12);", "native-tui-allocation.mjs") catch |err| {
        if (err == error.JavaScriptException) if (engine.captured_exception) |exception| {
            const message = c.JS_GetPropertyStr(engine.context, exception, "message");
            defer engine.freeValue(message);
            if (!c.JS_IsException(message)) {
                const text = c.JS_ToCString(engine.context, message);
                if (text != null) {
                    defer c.JS_FreeCString(engine.context, text);
                    if (std.mem.indexOf(u8, std.mem.span(text), "out of memory") != null) return error.OutOfMemory;
                }
            }
        };
        return err;
    };
    defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
}

test "native TUI allocator failures release native constructor prototype cycles child renders and caches" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, tuiAllocationProbe, .{});
}

test "native component control queue stop wakes a concurrent owner without inline blocking work" {
    const io = std.testing.io;
    var queue = ControlQueue.init(std.testing.allocator, io);
    defer queue.deinit();
    const Consumer = struct {
        queue: *ControlQueue,
        entered: bool = false,
        ended: bool = false,
        failure: ?anyerror = null,
        fn run(self: *@This()) void {
            @atomicStore(bool, &self.entered, true, .release);
            const item = self.queue.next() catch |err| {
                self.failure = err;
                return;
            };
            if (item) |value| {
                var owned = value;
                owned.deinit();
            } else self.ended = true;
        }
    };
    var consumer: Consumer = .{ .queue = &queue };
    var group: std.Io.Group = .init;
    try group.concurrent(io, Consumer.run, .{&consumer});
    defer {
        group.cancel(io);
        group.await(io) catch {};
    }
    var waited: usize = 0;
    while (!@atomicLoad(bool, &consumer.entered, .acquire) and waited < 1000) : (waited += 5) try io.sleep(.fromMilliseconds(5), .awake);
    try std.testing.expect(@atomicLoad(bool, &consumer.entered, .acquire));
    queue.stop();
    try group.await(io);
    try std.testing.expect(consumer.failure == null and consumer.ended);
}

test "native TUI child proxy setters and background callbacks throw the original exception object" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const module = try engine.evalModule("import {Text,Container} from 'pi-tui';const original={original:true};const container=new Container();container.children=new Proxy([],{set(){throw original}});let caught=false;try{container.addChild({render(){return []}})}catch(error){if(error!==original)throw Error('child setter identity');caught=true}if(!caught)throw Error('setter missing');const text=new Text('content',0,0,()=>{throw original});caught=false;try{text.render(8)}catch(error){if(error!==original)throw Error('background identity');caught=true}if(!caught)throw Error('background missing');", "native-tui-original-setters.mjs");
    defer engine.freeValue(module);
}

test "native public fake cursor helper preserves coercion exceptions aliases and rooting across GC" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const module = try engine.evalModule("import {renderFakeCursor,CURSOR_MARKER} from 'pi-tui';import * as alias from '@mariozechner/pi-tui';if(alias.renderFakeCursor!==renderFakeCursor||renderFakeCursor.length!==1||CURSOR_MARKER!=='\\x1b_pi:c\\x07')throw Error('exports');const start='\\x1b_pi:fc\\x07',end='\\x1b_pi:/fc\\x07';for(const value of [undefined,null,42,'界','👨‍👩‍👧‍👦'])if(renderFakeCursor(value)!==start+String(value)+end)throw Error('coercion');const original={};try{renderFakeCursor({toString(){throw original}});throw Error('missing throw')}catch(e){if(e!==original)throw e}globalThis.retainedCursor=renderFakeCursor('held');", "cursor-helper-original.mjs");
    defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
    const checked = try engine.eval("if(globalThis.retainedCursor!=='\\x1b_pi:fc\\x07held\\x1b_pi:/fc\\x07')throw Error('root');", "cursor-helper-gc.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(checked);
}
