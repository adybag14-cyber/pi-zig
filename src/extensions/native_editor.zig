//! Directly linked Editor and CustomEditor classes; extension input may subclass them.
const std = @import("std");
const engine_mod = @import("engine.zig");
const components = @import("native_components.zig");
const Editor = @import("../tui/editor.zig").Editor;
const line_editor = @import("../tui/line_editor.zig");
const Keybindings = @import("../tui/keybindings.zig").Manager;
const keys = @import("../tui/keys.zig");
const autocomplete_mod = @import("native_autocomplete.zig");
const autocomplete_registry = @import("native_autocomplete_registry.zig");
const c = engine_mod.c;

const Node = struct {
    engine: *engine_mod.Engine,
    editor: Editor,
    bindings: Keybindings,
    tui: c.JSValue,
    theme: c.JSValue,
    keybindings: c.JSValue,
    custom: bool,
    padding: u8 = 0,
    autocomplete_max: usize = 5,
    autocomplete: autocomplete_mod.State = undefined,
};
const Constructor = struct { engine: *engine_mod.Engine, prototype: c.JSValue, node_class: c.JSClassID, custom: bool };
const Method = enum(c_int) { getText, getExpandedText, setText, insertTextAtCursor, addToHistory, handleInput, render, invalidate, setPaddingX, getPaddingX, setAutocompleteMaxVisible, getAutocompleteMaxVisible, setAutocompleteProvider, isShowingAutocomplete, onAction };
fn fail(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native editor: %s", @as([*:0]const u8, @errorName(err)));
}
fn put(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}
fn mark(runtime: ?*c.JSRuntime, object: c.JSValue, mark_fn: ?*const c.JS_MarkFunc) callconv(.c) void {
    const node: *Node = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    for ([_]c.JSValue{ node.tui, node.theme, node.keybindings }) |value| c.JS_MarkValue(runtime, value, mark_fn);
    node.autocomplete.mark(runtime, mark_fn);
}
fn finalizer(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const node: *Node = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    for ([_]c.JSValue{ node.tui, node.theme, node.keybindings }) |value| c.JS_FreeValueRT(runtime, value);
    node.autocomplete.deinit(runtime);
    node.editor.deinit();
    node.bindings.deinit();
    node.engine.gpa.destroy(node);
}
fn constructorMark(runtime: ?*c.JSRuntime, object: c.JSValue, mark_fn: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    c.JS_MarkValue(runtime, state.prototype, mark_fn);
}
fn constructorFinalizer(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const state: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    c.JS_FreeValueRT(runtime, state.prototype);
    state.engine.gpa.destroy(state);
}
fn constructorCall(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) return c.JS_ThrowTypeError(context, "Editor requires new");
    const state: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    return construct(state, target, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn construct(state: *Constructor, target: c.JSValue, args: []c.JSValue) !c.JSValue {
    const engine = state.engine;
    const prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, target, "prototype"));
    defer engine.freeValue(prototype);
    const object = try engine.checked(c.JS_NewObjectProtoClass(engine.context, if (c.JS_IsObject(prototype)) prototype else state.prototype, state.node_class));
    errdefer engine.freeValue(object);
    const node = try engine.gpa.create(Node);
    node.* = .{ .engine = engine, .editor = Editor.init(engine.gpa), .bindings = Keybindings.init(engine.gpa), .tui = c.JS_DupValue(engine.context, if (args.len > 0) args[0] else c.pi_js_undefined()), .theme = c.JS_DupValue(engine.context, if (args.len > 1) args[1] else c.pi_js_undefined()), .keybindings = c.JS_DupValue(engine.context, if (state.custom and args.len > 2) args[2] else c.pi_js_undefined()), .custom = state.custom };
    node.autocomplete = autocomplete_mod.State.init(engine, &node.editor, object, node.tui);
    _ = c.JS_SetOpaque(object, node);
    try put(engine, object, "tui", c.JS_DupValue(engine.context, node.tui));
    try put(engine, object, "theme", c.JS_DupValue(engine.context, node.theme));
    try put(engine, object, "keybindings", c.JS_DupValue(engine.context, node.keybindings));
    const color = if (c.JS_IsObject(node.theme)) try engine.checked(c.JS_GetPropertyStr(engine.context, node.theme, "borderColor")) else c.pi_js_undefined();
    defer engine.freeValue(color);
    try put(engine, object, "borderColor", if (c.JS_IsFunction(engine.context, color)) c.JS_DupValue(engine.context, color) else try engine.checked(c.pi_js_function_magic(engine.context, borderColor, "borderColor", 1, 0)));
    const option_index: usize = if (state.custom) 3 else 2;
    if (args.len > option_index and c.JS_IsObject(args[option_index])) {
        const padding = try engine.checked(c.JS_GetPropertyStr(engine.context, args[option_index], "paddingX"));
        defer engine.freeValue(padding);
        if (!c.JS_IsUndefined(padding)) node.padding = @intCast(try count(engine, padding, 3));
    }
    if (state.custom) {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const map = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Map"));
        defer engine.freeValue(map);
        try put(engine, object, "actionHandlers", try engine.checked(c.JS_CallConstructor(engine.context, map, 0, null)));
    }
    return object;
}
fn count(engine: *engine_mod.Engine, value: c.JSValue, maximum: usize) !usize {
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, value) < 0) return error.JavaScriptException;
    if (!std.math.isFinite(number) or number < 0) return error.InvalidEditorDimension;
    return @intFromFloat(@min(@as(f64, @floatFromInt(maximum)), @floor(number)));
}
fn borderColor(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const theme = @import("native_theme.zig").getEditorTheme(engine) catch |err| return fail(engine, err);
    defer engine.freeValue(theme);
    const paint = engine.checked(c.JS_GetPropertyStr(context, theme, "borderColor")) catch |err| return fail(engine, err);
    defer engine.freeValue(paint);
    var args = [_]c.JSValue{if (argc > 0) argv[0] else c.pi_js_undefined()};
    return c.JS_Call(context, paint, theme, args.len, &args);
}
fn callback(node: *Node, object: c.JSValue, name: [*:0]const u8, args: []c.JSValue) !?c.JSValue {
    return components.callMethod(node.engine, object, name, args, true);
}
fn changed(node: *Node, object: c.JSValue) !void {
    const text = try node.engine.checked(c.JS_NewStringLen(node.engine.context, node.editor.slice().ptr, node.editor.slice().len));
    defer node.engine.freeValue(text);
    var args = [_]c.JSValue{text};
    if (try callback(node, object, "onChange", &args)) |value| node.engine.freeValue(value);
}
fn matchesAction(node: *Node, input: c.JSValue, action: c.JSValue) !bool {
    if (c.JS_IsObject(node.keybindings)) {
        const matches = try node.engine.checked(c.JS_GetPropertyStr(node.engine.context, node.keybindings, "matches"));
        defer node.engine.freeValue(matches);
        if (c.JS_IsFunction(node.engine.context, matches)) {
            var args = [_]c.JSValue{ input, action };
            const result = try node.engine.checked(c.JS_Call(node.engine.context, matches, node.keybindings, args.len, &args));
            defer node.engine.freeValue(result);
            return c.JS_ToBool(node.engine.context, result) != 0;
        }
    }
    return false;
}
fn dispatchActions(node: *Node, object: c.JSValue, input: c.JSValue) !bool {
    const engine = node.engine;
    const handlers = try engine.checked(c.JS_GetPropertyStr(engine.context, object, "actionHandlers"));
    defer engine.freeValue(handlers);
    const iterator = (try components.callMethod(engine, handlers, "entries", &.{}, false)).?;
    defer engine.freeValue(iterator);
    var count_entries: usize = 0;
    while (count_entries < 4096) : (count_entries += 1) {
        const entry = (try components.callMethod(engine, iterator, "next", &.{}, false)).?;
        defer engine.freeValue(entry);
        const done = try engine.checked(c.JS_GetPropertyStr(engine.context, entry, "done"));
        defer engine.freeValue(done);
        if (c.JS_ToBool(engine.context, done) != 0) return false;
        const pair = try engine.checked(c.JS_GetPropertyStr(engine.context, entry, "value"));
        defer engine.freeValue(pair);
        const action = try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, 0));
        defer engine.freeValue(action);
        const handler = try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, 1));
        defer engine.freeValue(handler);
        if (try matchesAction(node, input, action)) {
            if (!c.JS_IsFunction(engine.context, handler)) return error.InvalidEditorAction;
            const result = try engine.checked(c.JS_Call(engine.context, handler, c.pi_js_undefined(), 0, null));
            engine.freeValue(result);
            return true;
        }
    }
    return error.EditorActionLimit;
}
fn render(node: *Node, object: c.JSValue, width: usize) !c.JSValue {
    const engine = node.engine;
    _ = try node.autocomplete.poll();
    const focused = try engine.checked(c.JS_GetPropertyStr(engine.context, object, "focused"));
    defer engine.freeValue(focused);
    var view = node.editor;
    if (!c.JS_IsUndefined(focused) and c.JS_ToBool(engine.context, focused) == 0) view.cursor = std.math.maxInt(usize);
    var lines = try line_editor.renderEditorLinesPadded(engine.gpa, &view, @max(3, width), node.padding);
    defer lines.deinit(engine.gpa);
    const array = try engine.checked(c.JS_NewArray(engine.context));
    errdefer engine.freeValue(array);
    const border_bytes = try engine.gpa.alloc(u8, width * 3);
    defer engine.gpa.free(border_bytes);
    for (0..width) |i| @memcpy(border_bytes[i * 3 ..][0..3], "─");
    const border = try engine.checked(c.JS_NewStringLen(engine.context, border_bytes.ptr, border_bytes.len));
    defer engine.freeValue(border);
    var border_args = [_]c.JSValue{border};
    const painted = (try callback(node, object, "borderColor", &border_args)) orelse c.JS_DupValue(engine.context, border);
    defer engine.freeValue(painted);
    if (c.JS_SetPropertyUint32(engine.context, array, 0, c.JS_DupValue(engine.context, painted)) < 0) return error.JavaScriptException;
    for (lines.items, 0..) |line, i| if (c.JS_SetPropertyUint32(engine.context, array, @intCast(i + 1), try engine.checked(c.JS_NewStringLen(engine.context, line.ptr, line.len))) < 0) return error.JavaScriptException;
    if (c.JS_SetPropertyUint32(engine.context, array, @intCast(lines.items.len + 1), c.JS_DupValue(engine.context, painted)) < 0) return error.JavaScriptException;
    try node.autocomplete.appendRows(array, lines.items.len + 2, width);
    return array;
}
fn methodCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var class: i64 = 0;
    if (c.JS_ToInt64(context, &class, data[0]) < 0) return engine.throwCaptured();
    const node: *Node = @ptrCast(@alignCast(c.JS_GetOpaque(object, @intCast(class)) orelse return c.JS_ThrowTypeError(context, "Invalid Editor receiver")));
    return operation(node, object, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn operation(node: *Node, object: c.JSValue, method: Method, args: []c.JSValue) !c.JSValue {
    const engine = node.engine;
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    switch (method) {
        .getText, .getExpandedText => return engine.checked(c.JS_NewStringLen(engine.context, node.editor.slice().ptr, node.editor.slice().len)),
        .getPaddingX => return c.JS_NewInt64(engine.context, node.padding),
        .getAutocompleteMaxVisible => return c.JS_NewInt64(engine.context, @intCast(node.autocomplete_max)),
        .setPaddingX => node.padding = @intCast(try count(engine, first, 3)),
        .setAutocompleteMaxVisible => {
            node.autocomplete_max = try count(engine, first, 4096);
            node.autocomplete.max_visible = node.autocomplete_max;
        },
        .setAutocompleteProvider => try node.autocomplete.setProvider(first),
        .isShowingAutocomplete => return c.pi_js_bool(engine.context, @intFromBool(node.autocomplete.showing())),
        .invalidate => {},
        .render => return render(node, object, try count(engine, first, 16384)),
        .onAction => {
            if (args.len < 2 or !c.JS_IsFunction(engine.context, args[1])) return error.InvalidEditorAction;
            const handlers = try engine.checked(c.JS_GetPropertyStr(engine.context, object, "actionHandlers"));
            defer engine.freeValue(handlers);
            const result = (try components.callMethod(engine, handlers, "set", args[0..2], false)).?;
            engine.freeValue(result);
        },
        .setText, .insertTextAtCursor, .addToHistory => {
            const text = try engine.toString(first);
            defer engine.gpa.free(text);
            if (method != .addToHistory) try node.autocomplete.cancel();
            switch (method) {
                .setText => try node.editor.setText(text),
                .insertTextAtCursor => try node.editor.insert(text),
                .addToHistory => try node.editor.addHistory(text),
                else => unreachable,
            }
            if (method != .addToHistory) try changed(node, object);
        },
        .handleInput => {
            const input = try engine.toString(first);
            defer engine.gpa.free(input);
            if (!node.custom) if (try node.autocomplete.input(input) == .handled) return c.pi_js_undefined();
            if (keys.matchesKey(input, "tab") and node.autocomplete.provider == null) {
                if (try callback(node, object, "_nativeAutocomplete", &.{})) |value| {
                    engine.freeValue(value);
                    return c.pi_js_undefined();
                }
            }
            if (node.custom) {
                var shortcut_args = [_]c.JSValue{first};
                if (try callback(node, object, "onExtensionShortcut", &shortcut_args)) |value| {
                    defer engine.freeValue(value);
                    if (c.JS_ToBool(engine.context, value) != 0) return c.pi_js_undefined();
                }
                if (try node.autocomplete.input(input) == .handled) return c.pi_js_undefined();
                const hook: ?[*:0]const u8 = if (keys.matchesKey(input, "escape")) "onEscape" else if (keys.matchesKey(input, "ctrl+d") and node.editor.slice().len == 0) "onCtrlD" else null;
                if (hook) |name| if (try callback(node, object, name, &.{})) |value| {
                    engine.freeValue(value);
                    return c.pi_js_undefined();
                };
                if (try dispatchActions(node, object, first)) return c.pi_js_undefined();
            }
            const previous = try engine.gpa.dupe(u8, node.editor.slice());
            defer engine.gpa.free(previous);
            try node.autocomplete.cancel();
            const disposition = try line_editor.applyInputSequence(engine.gpa, &node.editor, &node.bindings, input, null);
            if (disposition == .submit) {
                const text = try engine.checked(c.JS_NewStringLen(engine.context, node.editor.slice().ptr, node.editor.slice().len));
                defer engine.freeValue(text);
                var values = [_]c.JSValue{text};
                if (try callback(node, object, "onSubmit", &values)) |value| engine.freeValue(value);
                try node.editor.addHistory(node.editor.slice());
                try node.editor.setText("");
            }
            if (disposition == .cancel) try node.editor.setText("");
            if (!std.mem.eql(u8, previous, node.editor.slice())) {
                try changed(node, object);
                if (disposition != .submit and disposition != .cancel) try node.autocomplete.automatic();
            }
        },
    }
    return c.pi_js_undefined();
}

/// Add classes to the TUI module and the coding-agent module before input loads.
pub fn install(engine: *engine_mod.Engine, tui_exports: c.JSValue) !void {
    if (engine.abort_signal_class == 0) try @import("abort_signal.zig").install(engine);
    var node_class: c.JSClassID = 0;
    var constructor_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &node_class);
    _ = c.JS_NewClassID(engine.runtime, &constructor_class);
    const node_definition: c.JSClassDef = .{ .class_name = "Native Editor", .finalizer = finalizer, .gc_mark = mark, .call = null, .exotic = null };
    const constructor_definition: c.JSClassDef = .{ .class_name = "Native Editor Constructor", .finalizer = constructorFinalizer, .gc_mark = constructorMark, .call = constructorCall, .exotic = null };
    if (c.JS_NewClass(engine.runtime, node_class, &node_definition) < 0 or c.JS_NewClass(engine.runtime, constructor_class, &constructor_definition) < 0) return error.OutOfMemory;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const function = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Function"));
    defer engine.freeValue(function);
    const function_prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, function, "prototype"));
    defer engine.freeValue(function_prototype);
    const coding = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(coding);
    try put(engine, coding, "VERSION", try engine.checked(c.JS_NewString(engine.context, @import("../config.zig").upstream_api_version)));
    var editor_constructor = c.pi_js_undefined();
    defer engine.freeValue(editor_constructor);
    var editor_prototype = c.pi_js_undefined();
    defer engine.freeValue(editor_prototype);
    inline for (.{ false, true }) |custom| {
        const prototype = try engine.checked(if (custom) c.JS_NewObjectProto(engine.context, editor_prototype) else c.JS_NewObject(engine.context));
        defer engine.freeValue(prototype);
        inline for (std.meta.fields(Method)) |field| {
            if (!custom or field.value == @intFromEnum(Method.onAction)) {
                const name: [:0]const u8 = field.name;
                var data = [_]c.JSValue{c.JS_NewInt64(engine.context, node_class)};
                defer engine.freeValue(data[0]);
                try put(engine, prototype, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name, 1, @intCast(field.value), 1, &data)));
            }
        }
        const constructor = try engine.checked(c.JS_NewObjectProtoClass(engine.context, if (custom) editor_constructor else function_prototype, constructor_class));
        defer engine.freeValue(constructor);
        const state = try engine.gpa.create(Constructor);
        state.* = .{ .engine = engine, .prototype = c.JS_DupValue(engine.context, prototype), .node_class = node_class, .custom = custom };
        _ = c.JS_SetOpaque(constructor, state);
        _ = c.JS_SetConstructorBit(engine.context, constructor, true);
        if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
        try put(engine, constructor, "name", try engine.checked(c.JS_NewString(engine.context, if (custom) "CustomEditor" else "Editor")));
        try put(engine, if (custom) coding else tui_exports, if (custom) "CustomEditor" else "Editor", c.JS_DupValue(engine.context, constructor));
        if (!custom) {
            editor_constructor = c.JS_DupValue(engine.context, constructor);
            editor_prototype = c.JS_DupValue(engine.context, prototype);
        }
    }
    try @import("native_sdk.zig").install(engine, coding);
    try @import("native_durable.zig").install(engine);
    try @import("native_theme.zig").install(engine, coding);
    try engine.registerValueModule("@earendil-works/pi-coding-agent", coding);
    try engine.registerValueModule("@mariozechner/pi-coding-agent", coding);
    try engine.registerValueModule("pi-coding-agent", coding);
}

fn autocompleteNode(engine: *engine_mod.Engine, component: c.JSValue) !?*Node {
    if (!c.JS_IsObject(component)) return null;
    const class_id = c.JS_GetClassID(component);
    const atom = c.JS_GetClassName(engine.runtime, class_id);
    defer c.JS_FreeAtom(engine.context, atom);
    const name = c.JS_AtomToCString(engine.context, atom) orelse return error.OutOfMemory;
    defer c.JS_FreeCString(engine.context, name);
    if (!std.mem.eql(u8, std.mem.span(name), "Native Editor")) return null;
    return @ptrCast(@alignCast(c.JS_GetOpaque(component, class_id) orelse return null));
}
pub fn pollAutocomplete(engine: *engine_mod.Engine, component: c.JSValue) !bool {
    const node = (try autocompleteNode(engine, component)) orelse return false;
    return node.autocomplete.poll();
}
pub fn retireAutocomplete(engine: *engine_mod.Engine, component: c.JSValue) void {
    if (autocompleteNode(engine, component) catch null) |node| node.autocomplete.retire();
}

const protocol = @import("editor_protocol.zig");
const OwnerToken = struct { gpa: std.mem.Allocator, manager: ?*Manager };
fn ownerFinalizer(_: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const token: *OwnerToken = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    token.gpa.destroy(token);
}
const OwnerMethod = enum(c_int) { requestRender, onChange, onSubmit, interrupt, exit, paste_image, complete, columns, rows, setFocus, autocompleteError };
pub const Manager = struct {
    engine: *engine_mod.Engine,
    token: c.JSValue,
    token_class: c.JSClassID,
    owners: std.AutoHashMapUnmanaged(u64, void) = .empty,
    factory: ?c.JSValue = null,
    component: ?c.JSValue = null,
    owner_id: u64 = 0,
    owner_generation: u64 = 1,
    generation: u64 = 0,
    sequence: u64 = 0,
    width: usize = 80,
    height: usize = 24,
    dirty: bool = false,
    polling: bool = false,
    draft: ?[]u8 = null,
    retiring: bool = false,
    creating: bool = false,
    focused: bool = true,
    autocomplete_wrappers: std.ArrayList(autocomplete_registry.Wrapper) = .empty,
    autocomplete_holder: ?c.JSValue = null,
    autocomplete_snapshot: ?c.JSValue = null,
    default_component: bool = false,
    refreshing_autocomplete: bool = false,
    record_fn: ?*const fn (?*anyopaque, protocol.Record) anyerror!void = null,
    record_context: ?*anyopaque = null,
    pub fn init(engine: *engine_mod.Engine) !Manager {
        var class: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Native Editor Owner", .finalizer = ownerFinalizer, .gc_mark = null, .call = null, .exotic = null };
        if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
        const token = try engine.checked(c.JS_NewObjectClass(engine.context, @intCast(class)));
        errdefer engine.freeValue(token);
        const state = try engine.gpa.create(OwnerToken);
        state.* = .{ .gpa = engine.gpa, .manager = null };
        _ = c.JS_SetOpaque(token, state);
        return .{ .engine = engine, .token = token, .token_class = class };
    }
    pub fn attach(self: *Manager) void {
        const state: *OwnerToken = @ptrCast(@alignCast(c.JS_GetOpaque(self.token, self.token_class).?));
        state.manager = self;
    }
    pub fn deinit(self: *Manager) void {
        if (self.autocomplete_holder) |holder_value| autocomplete_registry.deactivate(self.engine, holder_value);
        self.owners.clearRetainingCapacity();
        self.retire() catch {};
        const state: *OwnerToken = @ptrCast(@alignCast(c.JS_GetOpaque(self.token, self.token_class).?));
        state.manager = null;
        self.owners.deinit(self.engine.gpa);
        for (self.autocomplete_wrappers.items) |entry| self.engine.freeValue(entry.factory);
        self.autocomplete_wrappers.deinit(self.engine.gpa);
        if (self.autocomplete_holder) |value| self.engine.freeValue(value);
        if (self.autocomplete_snapshot) |value| self.engine.freeValue(value);
        if (self.draft) |contents| self.engine.gpa.free(contents);
        self.engine.freeValue(self.token);
    }
    pub fn addOwner(self: *Manager, id: u64) !void {
        try self.owners.put(self.engine.gpa, id, {});
    }
    pub fn removeOwner(self: *Manager, id: u64) void {
        _ = self.owners.remove(id);
        if (self.owner_id == id) self.retire() catch {};
        var index: usize = 0;
        while (index < self.autocomplete_wrappers.items.len) {
            if (self.autocomplete_wrappers.items[index].owner_id != id) {
                index += 1;
                continue;
            }
            self.engine.freeValue(self.autocomplete_wrappers.orderedRemove(index).factory);
        }
        if (self.owners.count() > 0) self.refreshAutocomplete() catch {};
    }
    pub fn updateAutocompleteContext(self: *Manager, snapshot: c.JSValue) !void {
        const owned = c.JS_DupValue(self.engine.context, snapshot);
        if (self.autocomplete_snapshot) |previous| self.engine.freeValue(previous);
        self.autocomplete_snapshot = owned;
        if (self.autocomplete_holder) |holder_value| try autocomplete_registry.update(self.engine, holder_value, snapshot);
    }
    pub fn addAutocompleteProvider(self: *Manager, owner: u64, factory: c.JSValue) !void {
        if (!self.owners.contains(owner)) return error.StaleNativeExtensionOwner;
        if (!c.JS_IsFunction(self.engine.context, factory)) return error.InvalidAutocompleteFactory;
        if (self.autocomplete_wrappers.items.len >= 256) return error.AutocompleteProviderLimit;
        const owned = c.JS_DupValue(self.engine.context, factory);
        errdefer self.engine.freeValue(owned);
        try self.autocomplete_wrappers.append(self.engine.gpa, .{ .owner_id = owner, .factory = owned });
        errdefer _ = self.autocomplete_wrappers.pop();
        try self.refreshAutocomplete();
    }
    pub fn refreshAutocomplete(self: *Manager) !void {
        if (self.refreshing_autocomplete) return error.AutocompleteFactoryReentry;
        self.refreshing_autocomplete = true;
        defer self.refreshing_autocomplete = false;
        if (self.autocomplete_wrappers.items.len == 0) {
            if (self.default_component) try self.retire();
            return;
        }
        if (self.autocomplete_holder == null) {
            self.autocomplete_holder = try autocomplete_registry.holder(self.engine);
            if (self.autocomplete_snapshot) |snapshot| try autocomplete_registry.update(self.engine, self.autocomplete_holder.?, snapshot);
        }
        const provider = try autocomplete_registry.wrapped(self.engine, self.autocomplete_holder.?, self.autocomplete_wrappers.items);
        defer self.engine.freeValue(provider);
        if (self.component == null) {
            const factory = try autocomplete_registry.defaultFactory(self.engine);
            defer self.engine.freeValue(factory);
            const draft_value = try self.textValue();
            defer self.engine.freeValue(draft_value);
            const native_tui = @import("native_tui.zig");
            const theme = try @import("native_theme.zig").current(self.engine);
            defer self.engine.freeValue(theme);
            const keybindings = try native_tui.createKeybindings(self.engine);
            defer self.engine.freeValue(keybindings);
            try self.setFactory(self.autocomplete_wrappers.items[0].owner_id, factory, draft_value, theme, keybindings, self.width, self.height);
            self.engine.freeValue(self.factory.?);
            self.factory = null;
            self.default_component = true;
        }
        var args = [_]c.JSValue{provider};
        if (try components.callMethod(self.engine, self.component.?, "setAutocompleteProvider", &args, true)) |value| self.engine.freeValue(value);
        self.dirty = true;
        _ = try self.pumpDirty();
    }
    fn fence(self: *Manager) protocol.Fence {
        return .{ .owner_generation = self.owner_generation, .extension_id = @max(1, self.owner_id), .editor_generation = self.generation };
    }
    fn send(self: *Manager, kind: @FieldType(protocol.Record, "kind")) !void {
        self.sequence += 1;
        var record: protocol.Record = .{ .gpa = self.engine.gpa, .fence = self.fence(), .sequence = self.sequence, .kind = kind };
        defer record.deinit();
        if (self.record_fn) |sink| try sink(self.record_context, record);
    }
    pub fn getFactory(self: *Manager, owner: u64) !c.JSValue {
        if (!self.owners.contains(owner)) return error.StaleNativeExtensionOwner;
        return if (self.factory) |value| c.JS_DupValue(self.engine.context, value) else c.pi_js_undefined();
    }
    pub fn textValue(self: *Manager) !c.JSValue {
        if (self.component != null) {
            const contents = try self.getText();
            defer self.engine.gpa.free(contents);
            return self.engine.checked(c.JS_NewStringLen(self.engine.context, contents.ptr, contents.len));
        }
        const contents = self.draft orelse "";
        return self.engine.checked(c.JS_NewStringLen(self.engine.context, contents.ptr, contents.len));
    }
    pub fn updateText(self: *Manager, contents: []const u8, paste: bool) !void {
        var value: protocol.Control = .{ .gpa = self.engine.gpa, .fence = self.fence(), .kind = if (paste) .{ .paste = try self.engine.gpa.dupe(u8, contents) } else .{ .set_text = try self.engine.gpa.dupe(u8, contents) } };
        defer value.deinit();
        _ = try self.control(value);
    }
    fn getText(self: *Manager) ![]u8 {
        const component_value = self.component orelse return self.engine.gpa.dupe(u8, "");
        const value = (try components.callMethod(self.engine, component_value, "getText", &.{}, false)).?;
        defer self.engine.freeValue(value);
        if (!c.JS_IsString(value)) return error.InvalidEditorText;
        return self.engine.toString(value);
    }
    pub fn setDraft(self: *Manager, contents: []const u8) !void {
        const copied = try self.engine.gpa.dupe(u8, contents);
        if (self.draft) |old| self.engine.gpa.free(old);
        self.draft = copied;
    }
    pub fn retire(self: *Manager) !void {
        const current_component = self.component orelse return;
        const current_factory = self.factory;
        retireAutocomplete(self.engine, current_component);
        // Detach before any observable dispose callback; captured methods now
        // fail their generation fence even if disposal re-enters user input.
        self.component = null;
        self.default_component = false;
        self.factory = null;
        self.dirty = false;
        self.retiring = true;
        defer self.retiring = false;
        defer self.engine.freeValue(current_component);
        defer if (current_factory) |value| self.engine.freeValue(value);
        defer {
            if (components.callMethod(self.engine, current_component, "dispose", &.{}, true) catch null) |value| self.engine.freeValue(value);
        }
        const text_value = (try components.callMethod(self.engine, current_component, "getText", &.{}, false)).?;
        defer self.engine.freeValue(text_value);
        const contents = try self.engine.toString(text_value);
        defer self.engine.gpa.free(contents);
        try self.setDraft(contents);
        try self.send(.{ .retire = try self.engine.gpa.dupe(u8, contents) });
    }
    fn function(self: *Manager, method: OwnerMethod) !c.JSValue {
        var data = [_]c.JSValue{ self.token, c.JS_NewInt64(self.engine.context, self.token_class), c.JS_NewInt64(self.engine.context, @intCast(self.generation)) };
        defer self.engine.freeValue(data[1]);
        defer self.engine.freeValue(data[2]);
        return self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, ownerCall, @tagName(method), 1, @intFromEnum(method), data.len, &data));
    }
    pub fn setFactory(self: *Manager, owner: u64, factory: c.JSValue, draft: c.JSValue, theme: c.JSValue, keybindings: c.JSValue, width: usize, height: usize) !void {
        // Source custom-editor factories receive getEditorTheme(), whose
        // callbacks read the retained global theme rather than this UI argument.
        _ = theme;
        if (!self.owners.contains(owner)) return error.StaleNativeExtensionOwner;
        if (self.retiring or self.polling or self.creating) return error.EditorCallbackReentry;
        self.creating = true;
        defer self.creating = false;
        if (!c.JS_IsUndefined(factory) and !c.JS_IsFunction(self.engine.context, factory)) return error.InvalidEditorFactory;
        const previous = if (self.component != null) try self.getText() else if (self.draft) |contents| try self.engine.gpa.dupe(u8, contents) else try self.engine.toString(draft);
        defer self.engine.gpa.free(previous);
        try self.retire();
        if (c.JS_IsUndefined(factory)) return;
        self.owner_id = owner;
        self.generation += 1;
        self.sequence = 0;
        self.width = @min(width, 16384);
        self.height = @min(height, 16384);
        self.focused = true;
        const tui = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(tui);
        try put(self.engine, tui, "requestRender", try self.function(.requestRender));
        try put(self.engine, tui, "setFocus", try self.function(.setFocus));
        const terminal = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(terminal);
        inline for (.{ .{ "columns", OwnerMethod.columns }, .{ "rows", OwnerMethod.rows } }) |field| {
            const getter = try self.function(field[1]);
            defer self.engine.freeValue(getter);
            const atom = c.JS_NewAtom(self.engine.context, field[0]);
            defer c.JS_FreeAtom(self.engine.context, atom);
            if (c.JS_DefinePropertyGetSet(self.engine.context, terminal, atom, c.JS_DupValue(self.engine.context, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
        }
        try put(self.engine, tui, "terminal", c.JS_DupValue(self.engine.context, terminal));
        const editor_theme = try @import("native_theme.zig").getEditorTheme(self.engine);
        defer self.engine.freeValue(editor_theme);
        var args = [_]c.JSValue{ tui, editor_theme, keybindings };
        const created = try self.engine.checked(c.JS_Call(self.engine.context, factory, c.pi_js_undefined(), args.len, &args));
        errdefer self.engine.freeValue(created);
        if (!c.JS_IsObject(created)) return error.InvalidEditorComponent;
        inline for (.{ "getText", "setText", "handleInput", "render" }) |method| {
            const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, created, method));
            defer self.engine.freeValue(value);
            if (!c.JS_IsFunction(self.engine.context, value)) return error.InvalidEditorComponent;
        }
        try put(self.engine, created, "onSubmit", try self.function(.onSubmit));
        try put(self.engine, created, "onChange", try self.function(.onChange));
        try put(self.engine, created, "_nativeAutocomplete", try self.function(.complete));
        try put(self.engine, created, "_nativeAutocompleteError", try self.function(.autocompleteError));
        inline for (.{ .{ "onEscape", OwnerMethod.interrupt }, .{ "onCtrlD", OwnerMethod.exit }, .{ "onPasteImage", OwnerMethod.paste_image } }) |field| {
            const existing = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, created, field[0]));
            defer self.engine.freeValue(existing);
            if (c.JS_IsUndefined(existing) or c.JS_IsNull(existing)) try put(self.engine, created, field[0], try self.function(field[1]));
        }
        const text_value = try self.engine.checked(c.JS_NewStringLen(self.engine.context, previous.ptr, previous.len));
        defer self.engine.freeValue(text_value);
        var set_args = [_]c.JSValue{text_value};
        const result = (try components.callMethod(self.engine, created, "setText", &set_args, false)).?;
        self.engine.freeValue(result);
        self.factory = c.JS_DupValue(self.engine.context, factory);
        self.component = created;
        // The component now owns this root; setup error unwinding must not
        // release the same JSValue a second time after retiring it.
        self.dirty = true;
        _ = self.pumpDirty() catch |err| {
            self.component = null;
            if (self.factory) |held_factory| self.engine.freeValue(held_factory);
            self.factory = null;
            self.dirty = false;
            if (components.callMethod(self.engine, created, "dispose", &.{}, true) catch null) |value| self.engine.freeValue(value);
            return err;
        };
    }
    pub fn pumpDirty(self: *Manager) !bool {
        if (self.polling) return false;
        // A serialized provider request can start its successor during poll.
        // Drain and consume those ready promise jobs before the owner parks
        // for external input; a synchronous base provider has no timer wake.
        for (0..4) |_| {
            if (self.component) |component_value| if (try pollAutocomplete(self.engine, component_value)) {
                self.dirty = true;
            };
            if (!c.JS_IsJobPending(self.engine.runtime)) break;
            _ = try self.engine.drainReadyJobs();
        }
        if (!self.dirty) return false;
        const current_component = self.component orelse return false;
        self.polling = true;
        defer self.polling = false;
        self.dirty = false;
        const held = c.JS_DupValue(self.engine.context, current_component);
        defer self.engine.freeValue(held);
        if (c.JS_SetPropertyStr(self.engine.context, held, "focused", c.pi_js_bool(self.engine.context, @intFromBool(self.focused))) < 0) return error.JavaScriptException;
        const identity = self.fence();
        var args = [_]c.JSValue{c.JS_NewInt64(self.engine.context, @intCast(self.width))};
        defer self.engine.freeValue(args[0]);
        const rendered = (try components.callMethod(self.engine, held, "render", &args, false)).?;
        defer self.engine.freeValue(rendered);
        var frame = try components.normalize(self.engine, rendered);
        var transferred = false;
        defer if (!transferred) frame.deinit();
        const contents = try self.getText();
        defer if (!transferred) self.engine.gpa.free(contents);
        if (self.component == null or !identity.matches(self.fence())) {
            return false;
        }
        const class_id = c.JS_GetClassID(held);
        const class_atom = c.JS_GetClassName(self.engine.runtime, class_id);
        defer c.JS_FreeAtom(self.engine.context, class_atom);
        const class_name = c.JS_AtomToCString(self.engine.context, class_atom) orelse return error.OutOfMemory;
        defer c.JS_FreeCString(self.engine.context, class_name);
        const cursor = if (std.mem.eql(u8, std.mem.span(class_name), "Native Editor")) native: {
            const node: *Node = @ptrCast(@alignCast(c.JS_GetOpaque(held, class_id) orelse break :native contents.len));
            break :native @min(node.editor.cursor, contents.len);
        } else contents.len;
        transferred = true;
        try self.send(.{ .frame = .{ .text = contents, .width = self.width, .frame = frame, .focused = self.focused, .cursor = cursor } });
        return true;
    }
    pub fn control(self: *Manager, value: protocol.Control) !bool {
        const component_value = self.component orelse return false;
        if (!value.fence.matches(self.fence())) return false;
        const held = c.JS_DupValue(self.engine.context, component_value);
        defer self.engine.freeValue(held);
        switch (value.kind) {
            .retire => try self.retire(),
            .resize => |width| {
                self.width = width;
                self.dirty = true;
            },
            .input, .paste, .set_text => |contents| {
                const text_value = try self.engine.checked(c.JS_NewStringLen(self.engine.context, contents.ptr, contents.len));
                defer self.engine.freeValue(text_value);
                var args = [_]c.JSValue{text_value};
                const method: [*:0]const u8 = switch (value.kind) {
                    .input => "handleInput",
                    .paste => "insertTextAtCursor",
                    .set_text => "setText",
                    else => unreachable,
                };
                if (try components.callMethod(self.engine, held, method, &args, value.kind == .paste)) |result| self.engine.freeValue(result) else {
                    const old = try self.getText();
                    defer self.engine.gpa.free(old);
                    const joined = try std.mem.concat(self.engine.gpa, u8, &.{ old, contents });
                    defer self.engine.gpa.free(joined);
                    const joined_value = try self.engine.checked(c.JS_NewStringLen(self.engine.context, joined.ptr, joined.len));
                    defer self.engine.freeValue(joined_value);
                    var fallback_args = [_]c.JSValue{joined_value};
                    const result = (try components.callMethod(self.engine, held, "setText", &fallback_args, false)).?;
                    self.engine.freeValue(result);
                }
                self.dirty = true;
            },
        }
        _ = try self.pumpDirty();
        return true;
    }
};
fn ownerCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var class: i64 = 0;
    var generation: i64 = 0;
    if (c.JS_ToInt64(context, &class, data[1]) < 0 or c.JS_ToInt64(context, &generation, data[2]) < 0) return engine.throwCaptured();
    const token: *OwnerToken = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], @intCast(class)) orelse return c.pi_js_undefined()));
    const manager = token.manager orelse return c.pi_js_undefined();
    if (generation != manager.generation) return c.pi_js_undefined();
    const method: OwnerMethod = @enumFromInt(magic);
    if (method == .columns or method == .rows) return c.JS_NewInt64(context, @intCast(if (method == .columns) manager.width else manager.height));
    if (method == .requestRender or method == .onChange) manager.dirty = true;
    if (method == .autocompleteError and manager.component != null) {
        _ = engine.checked(c.JS_Throw(context, c.JS_DupValue(context, if (argc > 0) argv[0] else c.pi_js_undefined()))) catch {};
        const message = engine.gpa.dupe(u8, engine.last_error orelse "Autocomplete provider rejected") catch |err| return fail(engine, err);
        manager.send(.{ .failure = message }) catch |err| return fail(engine, err);
    }
    if (method == .setFocus) {
        const target = if (argc > 0) argv[0] else c.pi_js_null();
        if (manager.component) |component_value| {
            if (!c.JS_IsNull(target) and !c.JS_IsUndefined(target) and !c.JS_IsStrictEqual(context, component_value, target)) return fail(engine, error.InvalidEditorFocusTarget);
        }
        manager.focused = !c.JS_IsNull(target) and !c.JS_IsUndefined(target);
        manager.dirty = true;
    }
    if (method == .onSubmit) {
        if (manager.component == null) return c.pi_js_undefined();
        const contents = engine.toString(if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return fail(engine, err);
        manager.send(.{ .submit = contents }) catch |err| return fail(engine, err);
    }
    if (method == .interrupt or method == .exit or method == .paste_image or method == .complete) {
        if (manager.component == null) return c.pi_js_undefined();
        manager.send(.{ .action = switch (method) {
            .interrupt => .interrupt,
            .exit => .exit,
            .paste_image => .paste_image,
            .complete => .complete,
            else => unreachable,
        } }) catch |err| return fail(engine, err);
    }
    return c.pi_js_undefined();
}
