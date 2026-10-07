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
    var pending: std.ArrayList(c.JSValue) = .empty;
    defer {
        for (pending.items) |value| engine.freeValue(value);
        pending.deinit(engine.gpa);
    }
    var visited: std.ArrayList(c.JSValue) = .empty;
    defer {
        for (visited.items) |value| engine.freeValue(value);
        visited.deinit(engine.gpa);
    }
    {
        const owned = c.JS_DupValue(engine.context, root);
        errdefer engine.freeValue(owned);
        try pending.append(engine.gpa, owned);
    }
    while (pending.pop()) |value| {
        var transferred = false;
        defer if (!transferred) engine.freeValue(value);
        if (c.JS_IsStrictEqual(engine.context, value, target)) return true;
        var seen = false;
        for (visited.items) |previous| if (c.JS_IsStrictEqual(engine.context, previous, value)) {
            seen = true;
            break;
        };
        if (seen) continue;
        if (visited.items.len >= 4096) return error.NativeFocusContainmentLimit;
        try visited.append(engine.gpa, value);
        transferred = true;
        if (!c.JS_IsObject(value)) continue;
        const class_id = c.JS_GetClassID(value);
        const atom = c.JS_GetClassName(engine.runtime, class_id);
        defer c.JS_FreeAtom(engine.context, atom);
        const name = c.JS_AtomToCString(engine.context, atom) orelse return error.OutOfMemory;
        defer c.JS_FreeCString(engine.context, name);
        if (!std.mem.eql(u8, std.mem.span(name), "Native TUI Component")) continue;
        const node: *Node = @ptrCast(@alignCast(c.JS_GetOpaque(value, class_id) orelse continue));
        if (node.kind != .container) continue;
        const array = try children(engine, value);
        defer engine.freeValue(array);
        const length_value = try engine.checked(c.JS_GetPropertyStr(engine.context, array, "length"));
        defer engine.freeValue(length_value);
        const length = try count(engine, length_value, false);
        if (length > 4096 - pending.items.len) return error.NativeFocusContainmentLimit;
        for (0..length) |index| {
            const child = try engine.checked(c.JS_GetPropertyUint32(engine.context, array, @intCast(index)));
            errdefer engine.freeValue(child);
            try pending.append(engine.gpa, child);
        }
    }
    return false;
}
const Method = enum(c_int) { render, invalidate, setText, setLines, setBgFn, addChild, removeChild, clear };

fn fail(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
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
    if (node.cache) |cache| if (node.cache_width == width) return c.JS_DupValue(engine.context, cache);
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
            for (frame.lines) |line| try appendOwned(engine, &rendered, try engine.gpa.dupe(u8, line));
        }
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

const Helper = enum(c_int) { visibleWidth, matchesKey, parseKey, isKeyRelease, isKeyRepeat, decodePrintableKey, setKittyProtocolActive, isKittyProtocolActive, truncateToWidth };
fn helperCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return helper(engine, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn helper(engine: *engine_mod.Engine, method: Helper, args: []c.JSValue) !c.JSValue {
    if (method == .isKittyProtocolActive) return c.pi_js_bool(engine.context, @intFromBool(keys.isKittyProtocolActive()));
    if (method == .setKittyProtocolActive) {
        keys.setKittyProtocolActive(args.len != 0 and c.JS_ToBool(engine.context, args[0]) != 0);
        return c.pi_js_undefined();
    }
    if (args.len == 0 or !c.JS_IsString(args[0])) return error.InvalidNativeTuiText;
    const text = try engine.toString(args[0]);
    defer engine.gpa.free(text);
    return switch (method) {
        .truncateToWidth => blk: {
            const width = try count(engine, if (args.len > 1) args[1] else c.pi_js_undefined(), false);
            if (width == 0) break :blk try engine.checked(c.JS_NewString(engine.context, ""));
            const ellipsis = if (args.len > 2 and !c.JS_IsUndefined(args[2])) try engine.toString(args[2]) else try engine.gpa.dupe(u8, "...");
            defer engine.gpa.free(ellipsis);
            const clipped = try terminal_text.truncateAlloc(engine.gpa, text, width, .{ .ellipsis = ellipsis, .pad = args.len > 3 and c.JS_ToBool(engine.context, args[3]) != 0 });
            defer engine.gpa.free(clipped);
            break :blk try engine.checked(c.JS_NewStringLen(engine.context, clipped.ptr, clipped.len));
        },
        .visibleWidth => engine.checked(c.JS_NewInt64(engine.context, @intCast(terminal_text.visibleWidth(text)))),
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
    const array_is_array = try components.arrayPredicate(engine);
    defer engine.freeValue(array_is_array);
    inline for (std.meta.fields(Helper)) |field| {
        const name: [:0]const u8 = field.name;
        try define(engine, exports, name.ptr, try engine.checked(c.pi_js_function_magic(engine.context, helperCall, name.ptr, 2, @intCast(field.value))));
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
        inline for (.{ .{ "render", Method.render }, .{ "invalidate", Method.invalidate }, .{ "setText", Method.setText }, .{ "setLines", Method.setLines }, .{ "setCustomBgFn", Method.setBgFn }, .{ "setBgFn", Method.setBgFn }, .{ "addChild", Method.addChild }, .{ "removeChild", Method.removeChild }, .{ "clear", Method.clear } }) |operation_name| {
            const available = operation_name[1] == .render or operation_name[1] == .invalidate or
                (item[1] == .text and (operation_name[1] == .setText or std.mem.eql(u8, operation_name[0], "setCustomBgFn"))) or
                (item[1] == .spacer and operation_name[1] == .setLines) or
                ((item[1] == .container or item[1] == .box) and (operation_name[1] == .addChild or operation_name[1] == .removeChild or operation_name[1] == .clear)) or
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
    try @import("native_editor.zig").install(engine, exports);
    try engine.registerValueModule("@earendil-works/pi-tui", exports);
    try engine.registerValueModule("@mariozechner/pi-tui", exports);
    try engine.registerValueModule("pi-tui", exports);
}

fn themeCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return themeOperation(engine, magic, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn themeOperation(engine: *engine_mod.Engine, magic: c_int, args: []c.JSValue) !c.JSValue {
    const index: usize = if (magic < 2) 1 else 0;
    const text = try engine.toString(if (args.len > index) args[index] else c.pi_js_undefined());
    defer engine.gpa.free(text);
    const style: []const u8 = if (magic < 2) blk: {
        const name = try engine.toString(if (args.len > 0) args[0] else c.pi_js_undefined());
        defer engine.gpa.free(name);
        const foreground: []const u8 = if (std.mem.eql(u8, name, "error")) "31" else if (std.mem.eql(u8, name, "success")) "32" else if (std.mem.eql(u8, name, "warning")) "33" else if (std.mem.eql(u8, name, "accent") or std.mem.eql(u8, name, "border")) "36" else if (std.mem.eql(u8, name, "dim") or std.mem.eql(u8, name, "muted")) "90" else "39";
        if (magic == 1) break :blk if (std.mem.eql(u8, name, "error")) "41" else if (std.mem.eql(u8, name, "success")) "42" else if (std.mem.eql(u8, name, "warning")) "43" else "49";
        break :blk foreground;
    } else switch (magic) {
        2 => "1",
        3 => "2",
        4 => "3",
        5 => "4",
        6 => "7",
        else => "9",
    };
    const painted = try std.fmt.allocPrint(engine.gpa, "\x1b[{s}m{s}\x1b[0m", .{ style, text });
    defer engine.gpa.free(painted);
    return engine.checked(c.JS_NewStringLen(engine.context, painted.ptr, painted.len));
}
pub fn createTheme(engine: *engine_mod.Engine) !c.JSValue {
    const object = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(object);
    try define(engine, object, "name", try engine.checked(c.JS_NewString(engine.context, "default")));
    inline for (.{ "fg", "bg", "bold", "dim", "italic", "underline", "inverse", "strikethrough" }, 0..) |name, index| try define(engine, object, name, try engine.checked(c.pi_js_function_magic(engine.context, themeCall, name, if (index < 2) 2 else 1, @intCast(index))));
    return object;
}
fn keybindingCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return keybindingOperation(engine, magic, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn keybindingOperation(engine: *engine_mod.Engine, magic: c_int, args: []c.JSValue) !c.JSValue {
    const action_index: usize = if (magic == 0) 1 else 0;
    const action = try engine.toString(if (args.len > action_index) args[action_index] else c.pi_js_undefined());
    defer engine.gpa.free(action);
    const binding: []const []const u8 = if (std.mem.eql(u8, action, "tui.select.confirm")) &.{"enter"} else if (std.mem.eql(u8, action, "tui.select.cancel")) &.{ "escape", "ctrl+c" } else if (std.mem.eql(u8, action, "tui.select.up")) &.{"up"} else if (std.mem.eql(u8, action, "tui.select.down")) &.{"down"} else if (std.mem.eql(u8, action, "tui.select.pageUp")) &.{"pageUp"} else if (std.mem.eql(u8, action, "tui.select.pageDown")) &.{"pageDown"} else @import("../tui/keybindings.zig").defaultKeysForAction(action);
    if (magic != 0) {
        const array = try engine.checked(c.JS_NewArray(engine.context));
        errdefer engine.freeValue(array);
        for (binding, 0..) |key, index| if (c.JS_SetPropertyUint32(engine.context, array, @intCast(index), try engine.checked(c.JS_NewStringLen(engine.context, key.ptr, key.len))) < 0) return error.JavaScriptException;
        return array;
    }
    const input = try engine.toString(if (args.len > 0) args[0] else c.pi_js_undefined());
    defer engine.gpa.free(input);
    for (binding) |key| if (keys.matchesKey(input, key)) return c.pi_js_bool(engine.context, 1);
    return c.pi_js_bool(engine.context, 0);
}
pub fn createKeybindings(engine: *engine_mod.Engine) !c.JSValue {
    const object = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(object);
    try define(engine, object, "matches", try engine.checked(c.pi_js_function_magic(engine.context, keybindingCall, "matches", 2, 0)));
    try define(engine, object, "getKeys", try engine.checked(c.pi_js_function_magic(engine.context, keybindingCall, "getKeys", 1, 1)));
    return object;
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
    try std.testing.expect(try containsComponent(engine, root, target));
    try std.testing.expect(!try containsComponent(engine, root, missing));
    try std.testing.expect(!try containsComponent(engine, box, target));
    try std.testing.expect(!try containsComponent(engine, fake, target));
    c.JS_RunGC(engine.runtime);
}

test "native focus containment is branded bounded cycle safe and releases every failed traversal allocation" {
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
