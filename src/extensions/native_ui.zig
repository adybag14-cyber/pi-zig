//! Standard extension dialogs and retained actions over the native worker wire.
const std = @import("std");
const engine_mod = @import("engine.zig");
const components_mod = @import("native_components.zig");
const native_tui = @import("native_tui.zig");
const native_editor = @import("native_editor.zig");
const protocol = @import("component_protocol.zig");
const c = engine_mod.c;

pub const Bridge = struct {
    context: ?*anyopaque = null,
    request: *const fn (?*anyopaque, u32, []const u8, []const u8) anyerror!void,
    action: *const fn (?*anyopaque, []const u8, []const u8) anyerror!void,
    cancel: *const fn (?*anyopaque, u32) anyerror!void,
    component_scene: ?*const fn (?*anyopaque, protocol.Scene) anyerror!void = null,
    component_close: ?*const fn (?*anyopaque, protocol.Fence) anyerror!void = null,
};

const Method = enum(c_int) { select, confirm, input, editor, notify, setStatus, setTitle, setEditorText, pasteToEditor, getEditorText, setWidget, setWorkingMessage, setWorkingVisible, setHiddenThinkingLabel, custom, setEditorComponent, getEditorComponent, addAutocompleteProvider };
const Pending = struct {
    id: u32,
    generation: u32,
    confirm: bool,
    resolve: c.JSValue,
    reject: c.JSValue,
    listener: c.JSValue,
    signals: [2]c.JSValue = undefined,
    signal_count: usize = 0,
    deadline: ?i64 = null,
    provider_request: bool = false,
};
const Custom = struct {
    fence: protocol.Fence,
    ui_generation: u32,
    promise: c.JSValue,
    width: usize,
    height: usize,
    presented: bool = false,
    closing: bool = false,
    options: c.JSValue,
    overlay: bool = false,
    hidden: bool = false,
    permanently_hidden: bool = false,
    focused: bool = true,
    focus_mode: protocol.FocusMode = .custom,
    focus_target: ?c.JSValue = null,
    focus_target_id: u64 = 0,
    focus_target_generation: u64 = 0,
    next_target_id: u64 = 1,
    explicit_focus: bool = false,
    restore_state: enum { cleared, eligible, blocked } = .cleared,
    restore_to_target: bool = false,
    restore_target: ?c.JSValue = null,
    layout: ?protocol.OverlayLayout = null,
    handle_published: bool = false,
    overlay_options: ?c.JSValue = null,
};
const OverlayMethod = enum(c_int) { hide, setHidden, isHidden, focus, unfocus, isFocused, getBounds, terminalColumns, terminalRows, setFocus };
const OpeningFocus = struct { token: u64, target: ?c.JSValue = null, mode: protocol.FocusMode = .custom, explicit: bool = false, previous: ?*OpeningFocus = null };
const OAuthMethod = enum(c_int) { onAuth, onDeviceCode, onPrompt, onProgress, onManualCodeInput, onSelect };
pub const ProviderActionFn = *const fn (?*anyopaque, [*:0]const u8, c.JSValue) anyerror!void;

pub const Manager = struct {
    engine: *engine_mod.Engine,
    token: c.JSValue,
    opening_focus: ?*OpeningFocus = null,
    add_listener: c.JSValue,
    remove_listener: c.JSValue,
    abort_text: c.JSValue,
    editor_text: c.JSValue,
    bridge: ?Bridge = null,
    generation: u32 = 0,
    active: bool = false,
    provider_action_fn: ?ProviderActionFn = null,
    provider_action_context: ?*anyopaque = null,
    has_ui: bool = false,
    signal: ?c.JSValue = null,
    next_id: u32 = 1,
    pending: std.ArrayList(Pending) = .empty,
    components: components_mod.Manager,
    editors: native_editor.Manager,
    editor_owner_id: u64 = 0,
    theme: c.JSValue,
    keybindings: c.JSValue,
    invocation_id: u64 = 0,
    width: usize = 80,
    height: usize = 24,
    customs: std.ArrayList(Custom) = .empty,
    polling_custom: bool = false,

    pub fn init(engine: *engine_mod.Engine) !*Manager {
        if (engine.native_ui_manager != null) return error.NativeUiAlreadyAttached;
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const constructor = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "AbortSignal"));
        defer engine.freeValue(constructor);
        const prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, constructor, "prototype"));
        defer engine.freeValue(prototype);
        const token = try engine.checked(c.JS_NewObject(engine.context));
        errdefer engine.freeValue(token);
        const add = try engine.checked(c.JS_GetPropertyStr(engine.context, prototype, "addEventListener"));
        errdefer engine.freeValue(add);
        const remove = try engine.checked(c.JS_GetPropertyStr(engine.context, prototype, "removeEventListener"));
        errdefer engine.freeValue(remove);
        const abort_text = try engine.checked(c.JS_NewString(engine.context, "abort"));
        errdefer engine.freeValue(abort_text);
        const editor_text = try engine.checked(c.JS_NewString(engine.context, ""));
        errdefer engine.freeValue(editor_text);
        var components = try components_mod.Manager.init(engine);
        errdefer components.deinit();
        var editors = try native_editor.Manager.init(engine);
        errdefer editors.deinit();
        const theme = try native_tui.createTheme(engine);
        errdefer engine.freeValue(theme);
        const keybindings = try native_tui.createKeybindings(engine);
        errdefer engine.freeValue(keybindings);
        const self = try engine.gpa.create(Manager);
        self.* = .{ .engine = engine, .token = token, .add_listener = add, .remove_listener = remove, .abort_text = abort_text, .editor_text = editor_text, .components = components, .editors = editors, .theme = theme, .keybindings = keybindings };
        self.editors.attach();
        self.components.completion_bridge = .{ .context = self, .request_close = requestComponentClose };
        engine.native_ui_manager = self;
        return self;
    }

    pub fn deinit(self: *Manager) void {
        self.editors.deinit();
        self.bridge = null;
        self.finish();
        self.engine.native_ui_manager = null;
        self.pending.deinit(self.engine.gpa);
        self.customs.deinit(self.engine.gpa);
        self.components.deinit();
        self.engine.freeValue(self.theme);
        self.engine.freeValue(self.keybindings);
        for ([_]c.JSValue{ self.token, self.add_listener, self.remove_listener, self.abort_text, self.editor_text }) |value| self.engine.freeValue(value);
        self.engine.gpa.destroy(self);
    }

    pub fn begin(self: *Manager, generation: u32, snapshot: ?c.JSValue, signal: ?c.JSValue) !void {
        self.finish();
        self.generation = generation;
        self.has_ui = false;
        if (snapshot) |context| {
            const available = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, context, "hasUI"));
            defer self.engine.freeValue(available);
            self.has_ui = c.JS_ToBool(self.engine.context, available) != 0;
            if (self.has_ui) try self.editors.updateAutocompleteContext(context);
            const text = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, context, "editorText"));
            defer self.engine.freeValue(text);
            if (c.JS_IsString(text)) {
                if (self.editors.component == null) {
                    const contents = try self.engine.toString(text);
                    defer self.engine.gpa.free(contents);
                    try self.editors.setDraft(contents);
                }
                self.engine.freeValue(self.editor_text);
                self.editor_text = c.JS_DupValue(self.engine.context, text);
            }
            self.width = try self.snapshotDimension(context, "width", 80);
            self.height = try self.snapshotDimension(context, "height", 24);
            if (self.has_ui and self.editors.component == null) {
                self.editors.width = self.width;
                self.editors.height = self.height;
            }
        }
        if (signal) |value| self.signal = c.JS_DupValue(self.engine.context, value);
        self.active = true;
    }

    pub fn finish(self: *Manager) void {
        while (self.pending.items.len > 0) self.cancel(self.pending.items[self.pending.items.len - 1].id) catch {};
        while (self.customs.items.len != 0) {
            const custom_request = self.customs.pop().?;
            if (custom_request.presented) self.engine.host_ui_pending -= 1;
            if (self.bridge) |bridge| if (bridge.component_close) |close| close(bridge.context, custom_request.fence) catch {};
            self.components.close(custom_request.fence.component_id, custom_request.fence.generation, c.pi_js_undefined()) catch {};
            self.engine.freeValue(custom_request.promise);
            self.engine.freeValue(custom_request.options);
            if (custom_request.overlay_options) |options| self.engine.freeValue(options);
            if (custom_request.focus_target) |target| self.engine.freeValue(target);
            if (custom_request.restore_target) |target| self.engine.freeValue(target);
        }
        self.components.retireGeneration(c.pi_js_undefined()) catch {};
        if (self.signal) |signal| self.engine.freeValue(signal);
        self.signal = null;
        self.active = false;
    }

    pub fn createObject(self: *Manager) !c.JSValue {
        const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
        errdefer self.engine.freeValue(object);
        var data = [_]c.JSValue{ self.token, c.JS_NewInt64(self.engine.context, self.generation), c.JS_NewInt64(self.engine.context, @intCast(self.editor_owner_id)), c.pi_js_bool(self.engine.context, @intFromBool(self.has_ui)) };
        defer self.engine.freeValue(data[1]);
        defer self.engine.freeValue(data[2]);
        inline for (std.meta.fields(Method)) |field| {
            const name: [:0]const u8 = field.name;
            const length: c_int = switch (@as(Method, @enumFromInt(field.value))) {
                .select, .confirm, .setStatus, .setWidget => 2,
                .getEditorText, .getEditorComponent => 0,
                else => 1,
            };
            const function = try self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, invoke, name.ptr, length, @intCast(field.value), data.len, &data));
            if (c.JS_DefinePropertyValueStr(self.engine.context, object, name.ptr, function, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        }
        try self.defineField(object, "theme", c.JS_DupValue(self.engine.context, self.theme));
        return object;
    }

    fn current(engine: *engine_mod.Engine, data: [*c]c.JSValue) !*Manager {
        const self: *Manager = @ptrCast(@alignCast(engine.native_ui_manager orelse return error.StaleNativeUi));
        var generation: i64 = 0;
        if (c.JS_ToInt64(engine.context, &generation, data[1]) < 0) return error.JavaScriptException;
        if (!self.active or generation != self.generation or !c.JS_IsStrictEqual(engine.context, self.token, data[0])) return error.StaleNativeUi;
        return self;
    }

    fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        const method: Method = @enumFromInt(magic);
        const args: []c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
        if (method == .setEditorComponent or method == .getEditorComponent or method == .getEditorText or method == .setEditorText or method == .pasteToEditor or method == .addAutocompleteProvider) {
            const self: *Manager = @ptrCast(@alignCast(engine.native_ui_manager orelse return fail(engine, error.StaleNativeUi)));
            if (!c.JS_IsStrictEqual(engine.context, self.token, data[0])) return fail(engine, error.StaleNativeUi);
            var owner: i64 = 0;
            if (c.JS_ToInt64(context, &owner, data[2]) < 0) return engine.throwCaptured();
            if (!self.editors.owners.contains(@intCast(owner))) return fail(engine, error.StaleNativeExtensionOwner);
            // Snapshot capability is independent of the shared invocation's
            // mutable hasUI state. Headless contexts never acquire editor UI.
            if (c.JS_ToBool(context, data[3]) == 0) return if (method == .getEditorText) c.JS_NewString(context, "") else c.pi_js_undefined();
            if (method == .addAutocompleteProvider) {
                self.editors.addAutocompleteProvider(@intCast(owner), if (args.len > 0) args[0] else c.pi_js_undefined()) catch |err| return fail(engine, err);
                return c.pi_js_undefined();
            }
            if (method == .getEditorText) return self.editors.textValue() catch |err| fail(engine, err);
            if (method == .setEditorText or method == .pasteToEditor) {
                if (self.editors.component != null) {
                    const contents = engine.toString(if (args.len > 0) args[0] else c.pi_js_undefined()) catch |err| return fail(engine, err);
                    defer engine.gpa.free(contents);
                    self.editors.updateText(contents, method == .pasteToEditor) catch |err| return fail(engine, err);
                    return c.pi_js_undefined();
                }
                const active_manager = current(engine, data) catch |err| return fail(engine, err);
                return active_manager.action(method, args) catch |err| fail(engine, err);
            }
            if (method == .getEditorComponent) return self.editors.getFactory(@intCast(owner)) catch |err| fail(engine, err);
            self.editors.setFactory(@intCast(owner), if (args.len > 0) args[0] else c.pi_js_undefined(), self.editor_text, self.theme, self.keybindings, self.width, self.height) catch |err| return fail(engine, err);
            self.editors.refreshAutocomplete() catch |err| return fail(engine, err);
            return c.pi_js_undefined();
        }
        const self = current(engine, data) catch |err| return fail(engine, err);
        if (@intFromEnum(method) <= @intFromEnum(Method.editor) or method == .custom) return self.dialog(method, args) catch |err| fail(engine, err);
        return self.action(method, args) catch |err| fail(engine, err);
    }

    fn fail(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
        return c.JS_ThrowTypeError(engine.context, "Native UI: %s", @as([*:0]const u8, @errorName(err)));
    }

    fn call(self: *Manager, function: c.JSValue, value: c.JSValue) !void {
        var args = [_]c.JSValue{value};
        const result = try self.engine.checked(c.JS_Call(self.engine.context, function, c.pi_js_undefined(), 1, &args));
        self.engine.freeValue(result);
    }

    fn rejectError(self: *Manager, reject: c.JSValue, err: anyerror) !void {
        _ = fail(self.engine, err);
        const reason = c.JS_GetException(self.engine.context);
        defer self.engine.freeValue(reason);
        try self.call(reject, reason);
    }

    fn rejectedPromise(self: *Manager, err: anyerror) !c.JSValue {
        var capabilities: [2]c.JSValue = undefined;
        const promise = try self.engine.checked(c.JS_NewPromiseCapability(self.engine.context, &capabilities));
        errdefer self.engine.freeValue(promise);
        defer for (capabilities) |value| self.engine.freeValue(value);
        try self.rejectError(capabilities[1], err);
        return promise;
    }

    fn defineField(self: *Manager, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        if (c.JS_DefinePropertyValueStr(self.engine.context, object, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }

    fn stringArgument(self: *Manager, args: []c.JSValue, index: usize, default: ?[]const u8) !c.JSValue {
        if (default) |fallback| if (index >= args.len or c.JS_IsUndefined(args[index]) or c.JS_IsNull(args[index])) return self.engine.checked(c.JS_NewStringLen(self.engine.context, fallback.ptr, fallback.len));
        const bytes = try self.engine.toString(if (index < args.len) args[index] else c.pi_js_undefined());
        defer self.engine.gpa.free(bytes);
        return self.engine.checked(c.JS_NewStringLen(self.engine.context, bytes.ptr, bytes.len));
    }

    fn isAborted(self: *Manager, signal: c.JSValue) !bool {
        if (c.JS_GetOpaque(signal, self.engine.abort_signal_class) == null) return error.InvalidNativeDialogSignal;
        // Native signal branding precedes observable property access.
        const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, signal, "aborted"));
        defer self.engine.freeValue(value);
        return c.JS_ToBool(self.engine.context, value) != 0;
    }

    fn snapshotDimension(self: *Manager, snapshot: c.JSValue, name: [*:0]const u8, fallback: usize) !usize {
        const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, snapshot, name));
        defer self.engine.freeValue(value);
        if (!c.JS_IsNumber(value)) return fallback;
        var number: f64 = 0;
        if (c.JS_ToFloat64(self.engine.context, &number, value) < 0) return error.JavaScriptException;
        if (!std.math.isFinite(number) or number < 0 or number > protocol.maximum_dimension) return fallback;
        return @intFromFloat(@floor(number));
    }

    fn overlayFunction(self: *Manager, token_id: u64, name: [*:0]const u8, method: OverlayMethod) !c.JSValue {
        var data = [_]c.JSValue{ self.token, c.JS_NewInt64(self.engine.context, self.generation), c.JS_NewInt64(self.engine.context, @intCast(token_id)) };
        defer self.engine.freeValue(data[1]);
        defer self.engine.freeValue(data[2]);
        return self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, overlayCall, name, 1, @intFromEnum(method), data.len, &data));
    }

    fn createFacade(self: *Manager, token_id: u64) !c.JSValue {
        const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
        errdefer self.engine.freeValue(object);
        const terminal = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(terminal);
        inline for (.{ .{ "columns", OverlayMethod.terminalColumns }, .{ "rows", OverlayMethod.terminalRows } }) |field| {
            const atom = c.JS_NewAtom(self.engine.context, field[0]);
            if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
            defer c.JS_FreeAtom(self.engine.context, atom);
            const getter = try self.overlayFunction(token_id, field[0], field[1]);
            if (c.JS_DefinePropertyGetSet(self.engine.context, terminal, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
        }
        try self.defineField(object, "terminal", c.JS_DupValue(self.engine.context, terminal));
        try self.defineField(object, "hideOverlay", try self.overlayFunction(token_id, "hideOverlay", .hide));
        try self.defineField(object, "setFocus", try self.overlayFunction(token_id, "setFocus", .setFocus));
        return object;
    }

    fn createOverlayHandle(self: *Manager, token_id: u64) !c.JSValue {
        const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
        errdefer self.engine.freeValue(object);
        inline for (.{ .{ "hide", OverlayMethod.hide }, .{ "setHidden", OverlayMethod.setHidden }, .{ "isHidden", OverlayMethod.isHidden }, .{ "focus", OverlayMethod.focus }, .{ "unfocus", OverlayMethod.unfocus }, .{ "isFocused", OverlayMethod.isFocused }, .{ "getBounds", OverlayMethod.getBounds } }) |field| try self.defineField(object, field[0], try self.overlayFunction(token_id, field[0], field[1]));
        return object;
    }

    fn overlayCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        const method: OverlayMethod = @enumFromInt(magic);
        const self = current(engine, data) catch return if (method == .isHidden) c.pi_js_bool(context, 1) else if (method == .isFocused) c.pi_js_bool(context, 0) else c.pi_js_undefined();
        var token_id: i64 = 0;
        if (c.JS_ToInt64(context, &token_id, data[2]) < 0) return engine.throwCaptured();
        return self.overlayOperation(@intCast(token_id), method, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
    }

    fn overlayOperation(self: *Manager, token_id: u64, method: OverlayMethod, args: []c.JSValue) !c.JSValue {
        const selected = for (self.customs.items) |*custom_request| {
            if (custom_request.fence.token == token_id) break custom_request;
        } else null;
        if (method == .terminalColumns) return c.JS_NewInt64(self.engine.context, @intCast(if (selected) |request| request.width else self.width));
        if (method == .terminalRows) return c.JS_NewInt64(self.engine.context, @intCast(if (selected) |request| request.height else self.height));
        var request = selected orelse {
            if (method == .setFocus) {
                var opening = self.opening_focus;
                while (opening) |candidate| : (opening = candidate.previous) {
                    if (candidate.token != token_id) continue;
                    const value = if (args.len > 0) args[0] else c.pi_js_null();
                    if (!c.JS_IsNull(value) and !c.JS_IsObject(value)) return error.InvalidNativeFocusTarget;
                    const owned = if (c.JS_IsNull(value)) null else c.JS_DupValue(self.engine.context, value);
                    if (candidate.target) |old| self.engine.freeValue(old);
                    candidate.target = owned;
                    candidate.mode = if (owned == null) .none else .custom;
                    candidate.explicit = true;
                    break;
                }
            }
            return if (method == .isHidden) c.pi_js_bool(self.engine.context, 1) else if (method == .isFocused) c.pi_js_bool(self.engine.context, 0) else c.pi_js_undefined();
        };
        if (request.closing) return c.pi_js_undefined();
        const fence = request.fence;
        switch (method) {
            .isHidden => return c.pi_js_bool(self.engine.context, @intFromBool(request.hidden or request.permanently_hidden)),
            .isFocused => return c.pi_js_bool(self.engine.context, @intFromBool(request.focused and request.focus_target_id == 0 and !request.hidden and !request.permanently_hidden)),
            .getBounds => {
                const layout = request.layout orelse return c.pi_js_undefined();
                if (layout.hidden) return c.pi_js_undefined();
                const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
                errdefer self.engine.freeValue(object);
                inline for (.{ "row", "col", "width", "height" }) |name| try self.defineField(object, name, c.JS_NewInt64(self.engine.context, @intCast(if (comptime std.mem.eql(u8, name, "row")) layout.row else if (comptime std.mem.eql(u8, name, "col")) layout.column else if (comptime std.mem.eql(u8, name, "width")) layout.width else layout.height)));
                return object;
            },
            .hide => {
                request.permanently_hidden = true;
                request.hidden = true;
                request.focused = false;
            },
            .setHidden => if (!request.permanently_hidden) {
                request.hidden = args.len != 0 and c.JS_ToBool(self.engine.context, args[0]) != 0;
            },
            .focus => {
                self.clearRestoreTarget(request);
                request.restore_state = .eligible;
                try self.changeFocus(fence, .custom, null);
            },
            .setFocus => {
                const target = if (args.len > 0) args[0] else c.pi_js_null();
                if (!c.JS_IsNull(target) and !c.JS_IsObject(target)) return error.InvalidNativeFocusTarget;
                if (c.JS_IsNull(target) and request.restore_state == .blocked) {
                    try self.resumeBlockedFocus(fence);
                    try self.components.invalidate(fence.component_id, fence.generation);
                    return c.pi_js_undefined();
                }
                const previous_restore = request.restore_state;
                if (request.focus_target_generation == std.math.maxInt(u64)) return error.NativeFocusTargetLimit;
                const expected_revision = request.focus_target_generation + 1;
                try self.changeFocus(fence, if (c.JS_IsNull(target)) .none else .custom, if (c.JS_IsNull(target)) null else target);
                if (self.findCustom(fence)) |active| {
                    if (active.focus_target_generation == expected_revision) {
                        active.restore_state = if (c.JS_IsNull(target)) .cleared else if (active.focus_target_id == 0) .eligible else if (previous_restore == .eligible) .blocked else previous_restore;
                        if (active.restore_state != .blocked) self.clearRestoreTarget(active);
                    }
                }
            },
            .unfocus => {
                if (args.len == 0 or c.JS_IsUndefined(args[0])) {
                    self.clearRestoreTarget(request);
                    request.restore_state = .cleared;
                    // A temporary replacement retains focus until it closes;
                    // an unfocus without a target cancels the pending restore.
                    if (request.focus_target_id == 0) try self.changeFocus(fence, .editor, null);
                } else {
                    if (!c.JS_IsObject(args[0])) return error.InvalidNativeFocusTarget;
                    const target = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, args[0], "target"));
                    defer self.engine.freeValue(target);
                    if (!c.JS_IsNull(target) and !c.JS_IsObject(target)) return error.InvalidNativeFocusTarget;
                    request = self.findCustom(fence) orelse return error.NativeComponentClosed;
                    if (request.closing) return error.NativeComponentClosing;
                    if (request.restore_state == .blocked) {
                        self.clearRestoreTarget(request);
                        request.restore_to_target = true;
                        request.restore_target = if (c.JS_IsNull(target)) null else c.JS_DupValue(self.engine.context, target);
                        try self.components.invalidate(fence.component_id, fence.generation);
                        return c.pi_js_undefined();
                    }
                    self.clearRestoreTarget(request);
                    request.restore_state = .cleared;
                    try self.changeFocus(fence, if (c.JS_IsNull(target)) .none else .custom, if (c.JS_IsNull(target)) null else target);
                }
            },
            else => {},
        }
        self.components.invalidate(fence.component_id, fence.generation) catch |err| try self.rejectCustom(fence, err);
        return c.pi_js_undefined();
    }

    fn rootComponent(self: *Manager, fence: protocol.Fence) !c.JSValue {
        const entry = self.components.entries.get(fence.component_id) orelse return error.NativeComponentClosed;
        if (entry.generation != fence.generation) return error.NativeComponentClosed;
        return c.JS_DupValue(self.engine.context, entry.component orelse return error.NativeComponentNotReady);
    }
    fn clearRestoreTarget(self: *Manager, request: *Custom) void {
        if (request.restore_target) |target| self.engine.freeValue(target);
        request.restore_target = null;
        request.restore_to_target = false;
    }
    fn resumeBlockedFocus(self: *Manager, fence: protocol.Fence) !void {
        const request = self.findCustom(fence) orelse return error.NativeComponentClosed;
        const to_target = request.restore_to_target;
        const target = if (request.restore_target) |value| c.JS_DupValue(self.engine.context, value) else null;
        defer if (target) |value| self.engine.freeValue(value);
        self.clearRestoreTarget(request);
        request.restore_state = if (to_target) .cleared else .eligible;
        try self.changeFocus(fence, if (to_target and target == null) .none else .custom, target);
    }
    fn setFocusedProperty(self: *Manager, value: c.JSValue, focused: bool) !void {
        const atom = c.JS_NewAtom(self.engine.context, "focused");
        if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        defer c.JS_FreeAtom(self.engine.context, atom);
        const has = c.JS_HasProperty(self.engine.context, value, atom);
        if (has < 0) {
            _ = try self.engine.checked(c.JS_Throw(self.engine.context, c.JS_GetException(self.engine.context)));
        }
        if (has != 0 and c.JS_SetProperty(self.engine.context, value, atom, c.pi_js_bool(self.engine.context, @intFromBool(focused))) < 0) {
            _ = try self.engine.checked(c.JS_Throw(self.engine.context, c.JS_GetException(self.engine.context)));
        }
    }
    fn changeFocus(self: *Manager, fence: protocol.Fence, mode: protocol.FocusMode, target: ?c.JSValue) !void {
        const selected = self.findCustom(fence) orelse return error.NativeComponentClosed;
        if (selected.closing) return error.NativeComponentClosing;
        if (selected.focus_target_generation == std.math.maxInt(u64) or selected.next_target_id == std.math.maxInt(u64)) return error.NativeFocusTargetLimit;
        selected.focus_target_generation += 1;
        const focus_revision = selected.focus_target_generation;
        const root: ?c.JSValue = self.rootComponent(fence) catch |err| switch (err) {
            error.NativeComponentNotReady => null,
            else => return err,
        };
        defer if (root) |value| self.engine.freeValue(value);
        const value = if (mode == .custom) if (target orelse root) |value| c.JS_DupValue(self.engine.context, value) else null else null;
        defer if (value) |owned| self.engine.freeValue(owned);
        const previous = if (selected.focus_target) |old| c.JS_DupValue(self.engine.context, old) else if (selected.focused and root != null) c.JS_DupValue(self.engine.context, root.?) else null;
        defer if (previous) |old| self.engine.freeValue(old);
        // Stage the rooted target before observable setters. A reentrant
        // setFocus then sees and clears this target, and its newer generation
        // cannot be overwritten by the outer transition.
        if (selected.focus_target) |old| self.engine.freeValue(old);
        selected.focus_target = if (value) |owned| c.JS_DupValue(self.engine.context, owned) else null;
        selected.focused = mode == .custom;
        selected.focus_mode = mode;
        selected.explicit_focus = true;
        selected.focus_target_id = if (value) |owned| if (root != null and c.JS_IsStrictEqual(self.engine.context, owned, root.?)) 0 else selected.next_target_id else 0;
        if (selected.focus_target_id != 0) selected.next_target_id += 1;
        if (previous) |old| try self.setFocusedProperty(old, false);
        if ((self.findCustom(fence) orelse return error.NativeComponentClosed).focus_target_generation != focus_revision) return;
        if (value) |owned| try self.setFocusedProperty(owned, true);
        // Getters/setters may reenter done(); select the owner again afterwards.
        const active = self.findCustom(fence) orelse return error.NativeComponentClosed;
        if (active.closing) return error.NativeComponentClosing;
        if (active.focus_target_generation != focus_revision) return;
    }

    fn sizeValue(self: *Manager, options: c.JSValue, name: [*:0]const u8, reference: usize, fallback: i64) !i64 {
        const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, options, name));
        defer self.engine.freeValue(value);
        if (c.JS_IsUndefined(value)) return fallback;
        var number: f64 = 0;
        if (c.JS_IsString(value)) {
            const text = try self.engine.toString(value);
            defer self.engine.gpa.free(text);
            if (text.len < 2 or text[text.len - 1] != '%') return fallback;
            for (text[0 .. text.len - 1]) |byte| if (!std.ascii.isDigit(byte) and byte != '.') return fallback;
            number = (std.fmt.parseFloat(f64, text[0 .. text.len - 1]) catch return fallback) * @as(f64, @floatFromInt(reference)) / 100;
        } else {
            if (!c.JS_IsNumber(value)) return fallback;
            if (c.JS_ToFloat64(self.engine.context, &number, value) < 0) return error.JavaScriptException;
        }
        if (!std.math.isFinite(number) or @abs(number) > protocol.maximum_dimension) return fallback;
        return @intFromFloat(@floor(number));
    }

    fn overlayOptions(self: *Manager, request: Custom) !c.JSValue {
        const options = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, request.options, "overlayOptions"));
        defer self.engine.freeValue(options);
        if (c.JS_IsFunction(self.engine.context, options)) {
            const result = try self.engine.checked(c.JS_Call(self.engine.context, options, c.pi_js_undefined(), 0, null));
            if (!c.JS_IsNull(result) and !c.JS_IsUndefined(result)) return result;
            self.engine.freeValue(result);
            return self.engine.checked(c.JS_NewObject(self.engine.context));
        }
        if (c.JS_IsObject(options)) return c.JS_DupValue(self.engine.context, options);
        const result = try self.engine.checked(c.JS_NewObject(self.engine.context));
        errdefer self.engine.freeValue(result);
        if (c.JS_ToBool(self.engine.context, options) == 0) {
            const width = try self.components.property(request.fence.component_id, request.fence.generation, "width");
            defer self.engine.freeValue(width);
            if (c.JS_ToBool(self.engine.context, width) != 0) try self.defineField(result, "width", c.JS_DupValue(self.engine.context, width));
        }
        return result;
    }

    fn overlayLayout(self: *Manager, request: Custom, options: c.JSValue, content_height: usize) !protocol.OverlayLayout {
        if (!c.JS_IsObject(options)) return error.InvalidNativeOverlayOptions;
        const margin = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, options, "margin"));
        defer self.engine.freeValue(margin);
        var margins: [4]usize = @splat(0);
        if (c.JS_IsNumber(margin)) {
            var number: f64 = 0;
            if (c.JS_ToFloat64(self.engine.context, &number, margin) < 0) return error.JavaScriptException;
            if (std.math.isFinite(number)) margins = @splat(@intFromFloat(@max(0, @min(protocol.maximum_dimension, @floor(number)))));
        } else if (c.JS_IsObject(margin)) inline for (.{ "top", "right", "bottom", "left" }, 0..) |name, i| {
            margins[i] = @intCast(@max(0, try self.sizeValue(margin, name, 0, 0)));
        };
        const top = margins[0];
        const right = margins[1];
        const bottom = margins[2];
        const left = margins[3];
        const available_width = @max(1, request.width -| (left + right));
        const available_height = @max(1, request.height -| (top + bottom));
        const width: usize = @intCast(@max(1, @min(@as(i64, @intCast(available_width)), @max(try self.sizeValue(options, "width", request.width, @intCast(@min(80, available_width))), try self.sizeValue(options, "minWidth", request.width, 1)))));
        const requested_height = try self.sizeValue(options, "maxHeight", request.height, -1);
        const maximum_height: usize = if (requested_height < 0) protocol.maximum_lines else @intCast(@max(1, @min(@as(i64, @intCast(available_height)), requested_height)));
        const height = @min(content_height, maximum_height);
        const anchor_value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, options, "anchor"));
        defer self.engine.freeValue(anchor_value);
        const anchor = if (c.JS_IsUndefined(anchor_value)) try self.engine.gpa.dupe(u8, "center") else try self.engine.toString(anchor_value);
        defer self.engine.gpa.free(anchor);
        var row: i64 = @intCast(top + (available_height -| height) / 2);
        var column: i64 = @intCast(left + (available_width -| width) / 2);
        inline for (.{ "top-left", "top-center", "top-right" }) |name| if (std.mem.eql(u8, anchor, name)) {
            row = @intCast(top);
        };
        inline for (.{ "bottom-left", "bottom-center", "bottom-right" }) |name| if (std.mem.eql(u8, anchor, name)) {
            row = @intCast(top + (available_height -| height));
        };
        inline for (.{ "top-left", "left-center", "bottom-left" }) |name| if (std.mem.eql(u8, anchor, name)) {
            column = @intCast(left);
        };
        inline for (.{ "top-right", "right-center", "bottom-right" }) |name| if (std.mem.eql(u8, anchor, name)) {
            column = @intCast(left + (available_width -| width));
        };
        row = try self.positionValue(options, "row", available_height -| height, top, row);
        column = try self.positionValue(options, "col", available_width -| width, left, column);
        row += try self.sizeValue(options, "offsetY", request.height, 0);
        column += try self.sizeValue(options, "offsetX", request.width, 0);
        const hidden = request.hidden or request.permanently_hidden;
        const non_capturing = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, options, "nonCapturing"));
        defer self.engine.freeValue(non_capturing);
        return .{ .row = @intCast(@max(@as(i64, @intCast(top)), @min(@as(i64, @intCast(request.height -| (bottom + height))), row))), .column = @intCast(@max(@as(i64, @intCast(left)), @min(@as(i64, @intCast(request.width -| (right + width))), column))), .width = width, .height = height, .hidden = hidden, .capture_input = c.JS_ToBool(self.engine.context, non_capturing) == 0 };
    }

    fn positionValue(self: *Manager, options: c.JSValue, name: [*:0]const u8, span: usize, margin: usize, fallback: i64) !i64 {
        const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, options, name));
        defer self.engine.freeValue(value);
        var number: f64 = 0;
        if (c.JS_IsString(value)) {
            const text = try self.engine.toString(value);
            defer self.engine.gpa.free(text);
            if (text.len < 2 or text[text.len - 1] != '%') return fallback;
            for (text[0 .. text.len - 1]) |byte| if (!std.ascii.isDigit(byte) and byte != '.') return fallback;
            number = (std.fmt.parseFloat(f64, text[0 .. text.len - 1]) catch return fallback) * @as(f64, @floatFromInt(span)) / 100;
            if (!std.math.isFinite(number) or @abs(number) > protocol.maximum_dimension) return fallback;
            return @as(i64, @intCast(margin)) + @as(i64, @intFromFloat(@floor(number)));
        }
        if (!c.JS_IsNumber(value)) return fallback;
        if (c.JS_ToFloat64(self.engine.context, &number, value) < 0) return error.JavaScriptException;
        if (!std.math.isFinite(number) or @abs(number) > protocol.maximum_dimension) return fallback;
        return @intFromFloat(@floor(number));
    }

    fn custom(self: *Manager, args: []c.JSValue) !c.JSValue {
        if (!self.has_ui or self.bridge == null) {
            var capabilities: [2]c.JSValue = undefined;
            const promise = try self.engine.checked(c.JS_NewPromiseCapability(self.engine.context, &capabilities));
            errdefer self.engine.freeValue(promise);
            defer for (capabilities) |value| self.engine.freeValue(value);
            try self.call(capabilities[0], c.pi_js_undefined());
            return promise;
        }
        if (self.customs.items.len >= 128 or self.next_id == std.math.maxInt(u32)) return error.NativeDialogLimit;
        if (self.invocation_id == 0) return error.NativeComponentInvocationMissing;
        const options = if (args.len > 1 and c.JS_IsObject(args[1])) c.JS_DupValue(self.engine.context, args[1]) else try self.engine.checked(c.JS_NewObject(self.engine.context));
        var options_transferred = false;
        defer if (!options_transferred) self.engine.freeValue(options);
        const overlay_value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, options, "overlay"));
        defer self.engine.freeValue(overlay_value);
        const overlay = c.JS_ToBool(self.engine.context, overlay_value) != 0;
        const token_id = self.next_id;
        self.next_id += 1;
        var opening: OpeningFocus = .{ .token = token_id, .previous = self.opening_focus };
        self.opening_focus = &opening;
        defer {
            self.opening_focus = opening.previous;
            if (opening.target) |target| self.engine.freeValue(target);
        }
        const facade = try self.createFacade(token_id);
        defer self.engine.freeValue(facade);
        const opened = try self.components.openWithFacade(if (args.len == 0) c.pi_js_undefined() else args[0], self.theme, self.keybindings, facade);
        errdefer self.engine.freeValue(opened.result);
        errdefer self.components.close(opened.id, opened.generation, c.pi_js_undefined()) catch {};
        if (c.JS_PromiseState(self.engine.context, opened.result) != c.JS_PROMISE_PENDING) return opened.result;
        const fence: protocol.Fence = .{ .token = token_id, .generation = opened.generation, .invocation_id = self.invocation_id, .component_id = opened.id };
        const custom_request: Custom = .{ .fence = fence, .ui_generation = self.generation, .promise = opened.result, .width = self.width, .height = self.height, .options = options, .overlay = overlay };
        var request: std.Io.Writer.Allocating = .init(self.engine.gpa);
        defer request.deinit();
        try request.writer.writeByte('{');
        try protocol.writeFence(&request.writer, fence);
        try request.writer.writeByte('}');
        try self.customs.append(self.engine.gpa, custom_request);
        options_transferred = true;
        self.bridge.?.request(self.bridge.?.context, @intCast(fence.token), "custom_native", request.written()) catch |err| {
            _ = self.customs.pop();
            options_transferred = false;
            return err;
        };
        if (opening.explicit) {
            self.changeFocus(fence, opening.mode, opening.target) catch |err| try self.rejectCustom(fence, err);
            if (self.findCustom(fence)) |active| if (!active.closing and active.focus_target_generation == 1) {
                active.restore_state = if (opening.mode == .custom and active.focus_target_id == 0) .eligible else .cleared;
            };
        }
        return c.JS_DupValue(self.engine.context, opened.result);
    }

    fn requestComponentClose(context: ?*anyopaque, id: u64, generation: u64) !void {
        const self: *Manager = @ptrCast(@alignCast(context.?));
        for (self.customs.items) |*custom_request| {
            if (custom_request.fence.component_id != id or custom_request.fence.generation != generation) continue;
            if (custom_request.closing) return;
            custom_request.closing = true;
            if (self.bridge) |bridge| if (bridge.component_close) |close| {
                try close(bridge.context, custom_request.fence);
                return;
            };
            try self.components.acknowledgeCompletion(id, generation);
            return;
        }
        // Synchronous done() before open returns has not published a scene.
        try self.components.acknowledgeCompletion(id, generation);
    }

    fn rejectCustom(self: *Manager, fence: protocol.Fence, err: anyerror) !void {
        const reason = try self.exceptionReason(err);
        defer self.engine.freeValue(reason);
        try self.components.reject(fence.component_id, fence.generation, reason);
    }
    fn exceptionReason(self: *Manager, err: anyerror) !c.JSValue {
        return if (err == error.JavaScriptException and self.engine.captured_exception != null) c.JS_DupValue(self.engine.context, self.engine.captured_exception.?) else blk: {
            _ = fail(self.engine, err);
            break :blk c.JS_GetException(self.engine.context);
        };
    }

    fn findCustom(self: *Manager, fence: protocol.Fence) ?*Custom {
        for (self.customs.items) |*request| if (protocol.Fence.matches(request.fence, fence)) return request;
        return null;
    }

    fn renderCustom(self: *Manager, initial: Custom) !protocol.Scene {
        var request = initial;
        var options: ?c.JSValue = null;
        defer if (options) |value| self.engine.freeValue(value);
        var layout: ?protocol.OverlayLayout = null;
        if (request.overlay) {
            if (request.overlay_options) |value| options = c.JS_DupValue(self.engine.context, value) else {
                options = try self.overlayOptions(request);
                const active = self.findCustom(request.fence) orelse return error.NativeComponentClosed;
                if (active.closing) return error.NativeComponentClosing;
                active.overlay_options = c.JS_DupValue(self.engine.context, options.?);
                const non_capturing = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, options.?, "nonCapturing"));
                defer self.engine.freeValue(non_capturing);
                if (self.findCustom(request.fence)) |selected| if (!selected.explicit_focus) {
                    selected.focused = c.JS_ToBool(self.engine.context, non_capturing) == 0;
                    selected.focus_mode = if (selected.focused) .custom else .editor;
                    selected.restore_state = if (selected.focused) .eligible else .cleared;
                };
            }
            request = (self.findCustom(request.fence) orelse return error.NativeComponentClosed).*;
            layout = try self.overlayLayout(request, options.?, 0);
            const visible = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, options.?, "visible"));
            defer self.engine.freeValue(visible);
            if (c.JS_IsFunction(self.engine.context, visible)) {
                var args = [_]c.JSValue{ c.JS_NewInt64(self.engine.context, @intCast(request.width)), c.JS_NewInt64(self.engine.context, @intCast(request.height)) };
                defer for (args) |value| self.engine.freeValue(value);
                const result = try self.engine.checked(c.JS_Call(self.engine.context, visible, options.?, args.len, &args));
                defer self.engine.freeValue(result);
                layout.?.hidden = layout.?.hidden or c.JS_ToBool(self.engine.context, result) == 0;
            }
        }
        var frame = if (layout != null and layout.?.hidden) protocol.Frame{ .gpa = self.engine.gpa, .lines = try self.engine.gpa.alloc([]u8, 0), .bytes = 0 } else try self.components.render(request.fence.component_id, request.fence.generation, if (layout) |geometry| geometry.width else request.width);
        errdefer frame.deinit();
        if (layout != null and layout.?.hidden) self.components.consumeHiddenFrame(request.fence.component_id, request.fence.generation);
        const active = self.findCustom(request.fence) orelse return error.NativeComponentClosed;
        if (active.closing) return error.NativeComponentClosing;
        request = active.*;
        const wants_release = (try self.focusWantsRelease(request.fence)) orelse return error.NativeFocusChanged;
        if (layout) |geometry| {
            const hidden = geometry.hidden;
            layout = try self.overlayLayout(request, options.?, frame.lines.len);
            layout.?.hidden = hidden or layout.?.hidden;
            if (frame.lines.len > layout.?.height) {
                const lines = try self.engine.gpa.alloc([]u8, layout.?.height);
                @memcpy(lines, frame.lines[0..lines.len]);
                for (frame.lines[lines.len..]) |line| {
                    frame.bytes -= line.len;
                    self.engine.gpa.free(line);
                }
                self.engine.gpa.free(frame.lines);
                frame.lines = lines;
            }
        }
        const latest = self.findCustom(request.fence) orelse return error.NativeComponentClosed;
        if (latest.closing) return error.NativeComponentClosing;
        if (latest.focus_target_generation != request.focus_target_generation) return error.NativeFocusChanged;
        latest.layout = layout;
        return .{ .fence = request.fence, .width = request.width, .height = request.height, .frame = frame, .overlay = layout, .focused = request.focused, .wants_key_release = wants_release, .focus_mode = if (layout != null and layout.?.hidden and request.focus_mode == .custom) .editor else request.focus_mode, .target_id = request.focus_target_id, .target_generation = request.focus_target_generation };
    }

    fn focusWantsRelease(self: *Manager, fence: protocol.Fence) !?bool {
        const request = self.findCustom(fence) orelse return error.NativeComponentClosed;
        const revision = request.focus_target_generation;
        const target = if (request.focus_target) |value| c.JS_DupValue(self.engine.context, value) else try self.rootComponent(fence);
        defer self.engine.freeValue(target);
        const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, target, "wantsKeyRelease"));
        defer self.engine.freeValue(value);
        const active = self.findCustom(fence) orelse return error.NativeComponentClosed;
        if (active.closing) return error.NativeComponentClosing;
        if (active.focus_target_generation != revision) return null;
        return c.JS_ToBool(self.engine.context, value) != 0;
    }

    fn publishOverlayHandle(self: *Manager, fence: protocol.Fence) !void {
        const selected = self.findCustom(fence) orelse return;
        if (!selected.overlay or selected.handle_published or selected.closing) return;
        selected.handle_published = true;
        const options = c.JS_DupValue(self.engine.context, selected.options);
        defer self.engine.freeValue(options);
        const callback = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, options, "onHandle"));
        defer self.engine.freeValue(callback);
        if (!c.JS_IsFunction(self.engine.context, callback)) return;
        var args = [_]c.JSValue{try self.createOverlayHandle(fence.token)};
        defer self.engine.freeValue(args[0]);
        const result = try self.engine.checked(c.JS_Call(self.engine.context, callback, c.pi_js_undefined(), args.len, &args));
        self.engine.freeValue(result);
    }

    fn pollCustom(self: *Manager) !bool {
        if (self.polling_custom) return false;
        self.polling_custom = true;
        defer self.polling_custom = false;
        var changed = false;
        const index: usize = 0;
        while (index < self.customs.items.len) {
            const custom_request = self.customs.items[index];
            if (c.JS_PromiseState(self.engine.context, custom_request.promise) != c.JS_PROMISE_PENDING) {
                const removed = self.customs.orderedRemove(index);
                if (removed.presented) self.engine.host_ui_pending -= 1;
                self.engine.freeValue(removed.promise);
                self.engine.freeValue(removed.options);
                if (removed.overlay_options) |options| self.engine.freeValue(options);
                if (removed.focus_target) |target| self.engine.freeValue(target);
                if (removed.restore_target) |target| self.engine.freeValue(target);
                changed = true;
                continue;
            }
            if (custom_request.closing) return changed;
            if (self.signal) |signal| if (try self.isAborted(signal)) {
                try self.components.complete(custom_request.fence.component_id, custom_request.fence.generation, c.pi_js_undefined());
                return true;
            };
            if (self.components.ready(custom_request.fence.component_id, custom_request.fence.generation) and self.components.dirty(custom_request.fence.component_id, custom_request.fence.generation)) {
                var rendered = self.renderCustom(custom_request) catch |err| {
                    if (err == error.NativeFocusChanged) {
                        try self.components.invalidate(custom_request.fence.component_id, custom_request.fence.generation);
                        return true;
                    }
                    if (err == error.NativeComponentClosed or err == error.NativeComponentClosing) return true;
                    try self.rejectCustom(custom_request.fence, err);
                    return true;
                };
                var consumed = false;
                defer if (!consumed) rendered.deinit();
                const active = self.findCustom(custom_request.fence) orelse return true;
                if (active.closing) return true;
                if (self.bridge) |bridge| if (bridge.component_scene) |scene| {
                    try scene(bridge.context, rendered);
                    consumed = true;
                    const presented = self.findCustom(custom_request.fence) orelse return true;
                    if (!presented.presented) {
                        presented.presented = true;
                        self.engine.host_ui_pending += 1;
                    }
                    self.publishOverlayHandle(custom_request.fence) catch |err| try self.rejectCustom(custom_request.fence, err);
                    changed = true;
                } else {
                    try self.components.complete(active.fence.component_id, active.fence.generation, c.pi_js_undefined());
                    return true;
                };
            }
            // Foreground custom dialogs preserve FIFO, including async factories.
            return changed;
        }
        return changed;
    }

    pub fn componentControl(self: *Manager, control: *const protocol.Control) !bool {
        if (!self.active or self.invocation_id != control.fence.invocation_id) return false;
        const selected = for (self.customs.items) |*custom_request| {
            if (protocol.Fence.matches(custom_request.fence, control.fence)) break custom_request;
        } else return false;
        if (selected.ui_generation != self.generation) return false;
        const fence = selected.fence;
        switch (control.kind) {
            .close_ack => |ok| {
                if (!selected.closing) return false;
                const target = if (selected.focus_target) |value| c.JS_DupValue(self.engine.context, value) else self.rootComponent(fence) catch null;
                defer if (target) |value| self.engine.freeValue(value);
                if (target) |value| self.setFocusedProperty(value, false) catch |err| {
                    const reason = try self.exceptionReason(err);
                    defer self.engine.freeValue(reason);
                    // done()/render errors already staged a primary result.
                    // Cleanup cannot replace an existing primary rejection.
                    const entry = self.components.entries.get(fence.component_id) orelse return true;
                    if (entry.generation != fence.generation) return true;
                    if (!entry.pending_success) try self.components.acknowledgeCompletion(fence.component_id, fence.generation) else try self.components.failAcknowledgement(fence.component_id, fence.generation, reason);
                    return true;
                };
                if (self.findCustom(fence) == null) return true;
                if (ok) try self.components.acknowledgeCompletion(fence.component_id, fence.generation) else {
                    const reason = try self.engine.checked(c.JS_NewError(self.engine.context));
                    defer self.engine.freeValue(reason);
                    const text = control.error_message orelse "Native component close failed";
                    try self.defineField(reason, "message", try self.engine.checked(c.JS_NewStringLen(self.engine.context, text.ptr, text.len)));
                    try self.components.failAcknowledgement(fence.component_id, fence.generation, reason);
                }
            },
            .input => |data| {
                if (selected.closing) return false;
                if (control.target_id != selected.focus_target_id or (control.target_generation != 0 and control.target_generation != selected.focus_target_generation)) return false;
                if (selected.overlay) if (selected.layout) |layout| if (layout.hidden or !selected.focused) return false;
                self.inputFocused(fence, data) catch |err| {
                    if (err == error.NativeComponentClosed or err == error.NativeComponentClosing) return false;
                    try self.rejectCustom(fence, err);
                };
            },
            .resize => |size| {
                selected.width = size.width;
                selected.height = size.height;
                self.components.invalidate(fence.component_id, fence.generation) catch |err| try self.rejectCustom(fence, err);
            },
            .invalidate => self.components.invalidate(fence.component_id, fence.generation) catch |err| try self.rejectCustom(fence, err),
            .close, .cancel => try self.components.complete(fence.component_id, fence.generation, c.pi_js_undefined()),
            .mouse => return error.NativeMouseComponentNotImplemented,
        }
        return true;
    }

    fn inputFocused(self: *Manager, fence: protocol.Fence, data: []const u8) !void {
        var request = self.findCustom(fence) orelse return error.NativeComponentClosed;
        if (request.focus_mode != .custom) return;
        if (request.restore_state == .blocked and request.focus_target_id != 0) {
            const revision = request.focus_target_generation;
            const target = c.JS_DupValue(self.engine.context, request.focus_target orelse return error.NativeComponentClosed);
            defer self.engine.freeValue(target);
            const root = try self.rootComponent(fence);
            defer self.engine.freeValue(root);
            const mounted = try native_tui.containsComponent(self.engine, root, target);
            request = self.findCustom(fence) orelse return error.NativeComponentClosed;
            if (request.closing or request.focus_target_generation != revision) return;
            if (!mounted or request.restore_to_target) {
                try self.resumeBlockedFocus(fence);
                request = self.findCustom(fence) orelse return error.NativeComponentClosed;
            }
        }
        if (request.focus_mode != .custom) return;
        if (request.focus_target_id == 0) return self.components.input(fence.component_id, fence.generation, data);
        const revision = request.focus_target_generation;
        const target = c.JS_DupValue(self.engine.context, request.focus_target orelse return error.NativeComponentClosed);
        defer self.engine.freeValue(target);
        const handler = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, target, "handleInput"));
        defer self.engine.freeValue(handler);
        const current_target = self.findCustom(fence) orelse return;
        if (current_target.closing or current_target.focus_target_generation != revision) return;
        if (c.JS_IsFunction(self.engine.context, handler)) {
            var args = [_]c.JSValue{try self.engine.checked(c.JS_NewStringLen(self.engine.context, data.ptr, data.len))};
            defer self.engine.freeValue(args[0]);
            const result = try self.engine.checked(c.JS_Call(self.engine.context, handler, target, args.len, &args));
            self.engine.freeValue(result);
        }
        self.components.invalidate(fence.component_id, fence.generation) catch |err| if (err != error.NativeComponentClosed and err != error.NativeComponentClosing) return err;
    }

    fn dialog(self: *Manager, method: Method, args: []c.JSValue) !c.JSValue {
        if (method == .custom) return self.custom(args) catch |err| {
            var capabilities: [2]c.JSValue = undefined;
            const promise = try self.engine.checked(c.JS_NewPromiseCapability(self.engine.context, &capabilities));
            errdefer self.engine.freeValue(promise);
            defer for (capabilities) |value| self.engine.freeValue(value);
            try self.rejectError(capabilities[1], err);
            return promise;
        };
        var capabilities: [2]c.JSValue = undefined;
        const promise = try self.engine.checked(c.JS_NewPromiseCapability(self.engine.context, &capabilities));
        errdefer self.engine.freeValue(promise);
        var transferred = false;
        defer if (!transferred) for (capabilities) |function| self.engine.freeValue(function);
        if (!self.has_ui or self.bridge == null) {
            try self.call(capabilities[0], if (method == .confirm) c.pi_js_bool(self.engine.context, 0) else c.pi_js_undefined());
            return promise;
        }
        self.requestDialog(method, args, capabilities, &transferred) catch |err| {
            try self.rejectError(capabilities[1], err);
            return promise;
        };
        return promise;
    }

    fn requestDialog(self: *Manager, method: Method, args: []c.JSValue, capabilities: [2]c.JSValue, transferred: *bool) !void {
        if (self.pending.items.len >= 128 or self.next_id == std.math.maxInt(u32)) return error.NativeDialogLimit;
        const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(object);
        try self.defineField(object, "title", try self.stringArgument(args, 0, null));
        if (method == .select) {
            if (args.len < 2 or !c.JS_IsArray(args[1])) return error.InvalidNativeDialogOptions;
            const array = try self.engine.checked(c.JS_NewArray(self.engine.context));
            var consumed = false;
            defer if (!consumed) self.engine.freeValue(array);
            const raw_length = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, args[1], "length"));
            defer self.engine.freeValue(raw_length);
            var length: u32 = 0;
            if (c.JS_ToUint32(self.engine.context, &length, raw_length) < 0) return error.JavaScriptException;
            if (length > 4096) return error.NativeDialogOptionsLimit;
            for (0..length) |index| {
                const value = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, args[1], @intCast(index)));
                defer self.engine.freeValue(value);
                var item = [_]c.JSValue{value};
                if (c.JS_SetPropertyUint32(self.engine.context, array, @intCast(index), try self.stringArgument(&item, 0, null)) < 0) return error.JavaScriptException;
            }
            consumed = true;
            try self.defineField(object, "options", array);
        } else try self.defineField(object, if (method == .confirm) "message" else if (method == .editor) "prefill" else "placeholder", try self.stringArgument(args, 1, if (method == .confirm) null else ""));
        var requested_signal: ?c.JSValue = null;
        defer if (requested_signal) |signal| self.engine.freeValue(signal);
        var deadline: ?i64 = null;
        if (method != .editor and args.len > 2 and c.JS_IsObject(args[2])) {
            const signal = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, args[2], "signal"));
            if (c.JS_IsUndefined(signal) or c.JS_IsNull(signal)) self.engine.freeValue(signal) else requested_signal = signal;
            const timeout = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, args[2], "timeout"));
            defer self.engine.freeValue(timeout);
            if (!c.JS_IsUndefined(timeout)) {
                var number: f64 = 0;
                if (c.JS_ToFloat64(self.engine.context, &number, timeout) < 0) return error.JavaScriptException;
                if (std.math.isFinite(number) and number > 0) {
                    try self.defineField(object, "timeout", c.JS_NewFloat64(self.engine.context, number));
                    const io = self.engine.native_io orelse return error.NativeDialogClockUnavailable;
                    deadline = std.Io.Clock.awake.now(io).toMilliseconds() +| @as(i64, @intFromFloat(@min(@ceil(number), @as(f64, @floatFromInt(std.math.maxInt(i64) - 1024)))));
                }
            }
        }
        if (requested_signal) |signal| if (try self.isAborted(signal)) {
            try self.call(capabilities[0], if (method == .confirm) c.pi_js_bool(self.engine.context, 0) else c.pi_js_undefined());
            return;
        };
        if (self.signal) |signal| if (try self.isAborted(signal)) {
            try self.call(capabilities[0], if (method == .confirm) c.pi_js_bool(self.engine.context, 0) else c.pi_js_undefined());
            return;
        };
        const encoded = try self.engine.stringify(object);
        defer self.engine.gpa.free(encoded);
        var data = [_]c.JSValue{ self.token, c.JS_NewInt64(self.engine.context, self.generation), c.JS_NewInt64(self.engine.context, self.next_id) };
        defer self.engine.freeValue(data[1]);
        defer self.engine.freeValue(data[2]);
        const listener = try self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, onAbort, "native dialog abort", 0, 0, data.len, &data));
        var pending: Pending = .{ .id = self.next_id, .generation = self.generation, .confirm = method == .confirm, .resolve = capabilities[0], .reject = capabilities[1], .listener = listener, .deadline = deadline };
        var attached = false;
        errdefer if (!attached) {
            self.detach(&pending);
            self.engine.freeValue(listener);
        };
        if (self.signal) |signal| try self.listen(&pending, signal);
        if (requested_signal) |signal| if (self.signal == null or !c.JS_IsStrictEqual(self.engine.context, signal, self.signal.?)) try self.listen(&pending, signal);
        try self.pending.append(self.engine.gpa, pending);
        self.engine.host_ui_pending += 1;
        attached = true;
        transferred.* = true;
        self.next_id += 1;
        self.bridge.?.request(self.bridge.?.context, pending.id, @tagName(method), encoded) catch |err| {
            const removed = self.takePending(pending.id) orelse return;
            // Capabilities return to dialog() so rejection preserves the cause.
            transferred.* = false;
            var release = removed;
            self.detach(&release);
            self.engine.freeValue(release.listener);
            return err;
        };
    }

    fn listen(self: *Manager, pending: *Pending, signal: c.JSValue) !void {
        _ = try self.isAborted(signal);
        const options = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(options);
        try self.defineField(options, "once", c.pi_js_bool(self.engine.context, 1));
        var args = [_]c.JSValue{ self.abort_text, pending.listener, options };
        const result = try self.engine.checked(c.JS_Call(self.engine.context, self.add_listener, signal, args.len, &args));
        self.engine.freeValue(result);
        pending.signals[pending.signal_count] = c.JS_DupValue(self.engine.context, signal);
        pending.signal_count += 1;
    }

    fn detach(self: *Manager, pending: *Pending) void {
        for (pending.signals[0..pending.signal_count]) |signal| {
            var args = [_]c.JSValue{ self.abort_text, pending.listener };
            const result = c.JS_Call(self.engine.context, self.remove_listener, signal, args.len, &args);
            if (c.JS_IsException(result)) self.engine.freeValue(c.JS_GetException(self.engine.context)) else self.engine.freeValue(result);
            self.engine.freeValue(signal);
        }
        pending.signal_count = 0;
    }

    fn takePending(self: *Manager, id: u32) ?Pending {
        for (self.pending.items, 0..) |pending, index| if (pending.id == id) {
            self.engine.host_ui_pending -= 1;
            return self.pending.orderedRemove(index);
        };
        return null;
    }

    fn freePending(self: *Manager, pending: *Pending) void {
        self.detach(pending);
        for ([_]c.JSValue{ pending.resolve, pending.reject, pending.listener }) |value| self.engine.freeValue(value);
    }

    pub fn respond(self: *Manager, id: u32, ok: bool, value: c.JSValue) !void {
        var pending = self.takePending(id) orelse return;
        defer self.freePending(&pending);
        if (!self.active or pending.generation != self.generation) return;
        const result = if (!ok or pending.provider_request) value else if (pending.confirm) c.pi_js_bool(self.engine.context, c.JS_ToBool(self.engine.context, value)) else if (c.JS_IsNull(value)) c.pi_js_undefined() else value;
        try self.call(if (ok) pending.resolve else pending.reject, result);
    }

    pub fn cancel(self: *Manager, id: u32) !void {
        var pending = self.takePending(id) orelse return;
        defer self.freePending(&pending);
        if (!pending.provider_request) if (self.bridge) |bridge| bridge.cancel(bridge.context, id) catch |err| {
            try self.rejectError(pending.reject, err);
            return err;
        };
        if (pending.provider_request) {
            const reason = if (pending.signal_count != 0) try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, pending.signals[0], "reason")) else c.pi_js_undefined();
            defer self.engine.freeValue(reason);
            try self.call(pending.reject, reason);
        } else try self.call(pending.resolve, if (pending.confirm) c.pi_js_bool(self.engine.context, 0) else c.pi_js_undefined());
    }

    /// Shared provider host requests preserve the result verbatim and reject
    /// with the invocation's original abort reason. All capabilities remain
    /// on the QuickJS owner thread; the host transports only JSON records.
    pub fn requestProvider(self: *Manager, method: []const u8, object: c.JSValue) !c.JSValue {
        if (!self.active or self.bridge == null or self.signal == null) return error.NativeProviderSignalMissing;
        if (self.pending.items.len >= 128 or self.next_id == std.math.maxInt(u32)) return error.NativeDialogLimit;
        var capabilities: [2]c.JSValue = undefined;
        const promise = try self.engine.checked(c.JS_NewPromiseCapability(self.engine.context, &capabilities));
        errdefer self.engine.freeValue(promise);
        var transferred = false;
        defer if (!transferred) for (capabilities) |value| self.engine.freeValue(value);
        if (try self.isAborted(self.signal.?)) {
            const reason = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, self.signal.?, "reason"));
            defer self.engine.freeValue(reason);
            try self.call(capabilities[1], reason);
            return promise;
        }
        const encoded = try self.engine.stringify(object);
        defer self.engine.gpa.free(encoded);
        var data = [_]c.JSValue{ self.token, c.JS_NewInt64(self.engine.context, self.generation), c.JS_NewInt64(self.engine.context, self.next_id) };
        defer self.engine.freeValue(data[1]);
        defer self.engine.freeValue(data[2]);
        const listener = try self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, onAbort, "native provider request abort", 0, 0, data.len, &data));
        var pending: Pending = .{ .id = self.next_id, .generation = self.generation, .confirm = false, .resolve = capabilities[0], .reject = capabilities[1], .listener = listener, .provider_request = true };
        var attached = false;
        errdefer if (!attached) {
            self.detach(&pending);
            self.engine.freeValue(listener);
        };
        try self.listen(&pending, self.signal.?);
        try self.pending.append(self.engine.gpa, pending);
        self.engine.host_ui_pending += 1;
        attached = true;
        transferred = true;
        self.next_id += 1;
        self.bridge.?.request(self.bridge.?.context, pending.id, method, encoded) catch |err| {
            var removed = self.takePending(pending.id).?;
            self.freePending(&removed);
            return err;
        };
        return promise;
    }

    pub fn createOAuthCallbacks(self: *Manager) !c.JSValue {
        const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
        errdefer self.engine.freeValue(object);
        var data = [_]c.JSValue{ self.token, c.JS_NewInt64(self.engine.context, self.generation) };
        defer self.engine.freeValue(data[1]);
        inline for (std.meta.fields(OAuthMethod)) |field| {
            try self.defineField(object, field.name, try self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, oauthCallback, field.name, 1, @intCast(field.value), data.len, &data)));
        }
        try self.defineField(object, "signal", c.JS_DupValue(self.engine.context, self.signal orelse return error.NativeProviderSignalMissing));
        return object;
    }

    fn oauthCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        const method: OAuthMethod = @enumFromInt(magic);
        const self = current(engine, data) catch |err| return fail(engine, err);
        return self.oauthOperation(method, if (argc == 0) c.pi_js_undefined() else argv[0]) catch |err| {
            if (method == .onPrompt or method == .onManualCodeInput or method == .onSelect) return self.rejectedPromise(err) catch |failure| fail(engine, failure);
            return fail(engine, err);
        };
    }

    fn oauthText(self: *Manager, value: c.JSValue, optional: bool) !c.JSValue {
        if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) return if (optional) c.pi_js_undefined() else self.engine.checked(c.JS_NewString(self.engine.context, ""));
        const text = try self.engine.toString(value);
        defer self.engine.gpa.free(text);
        return self.engine.checked(c.JS_NewStringLen(self.engine.context, text.ptr, text.len));
    }

    fn oauthProperty(self: *Manager, info: c.JSValue, names: []const [*:0]const u8) !c.JSValue {
        for (names, 0..) |name, i| {
            const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, info, name));
            if (i == names.len - 1 or (!c.JS_IsUndefined(value) and !c.JS_IsNull(value))) return value;
            self.engine.freeValue(value);
        }
        return c.pi_js_undefined();
    }

    fn oauthField(self: *Manager, object: c.JSValue, name: [*:0]const u8, info: c.JSValue, aliases: []const [*:0]const u8, optional: bool) !void {
        const value = try self.oauthProperty(info, aliases);
        defer self.engine.freeValue(value);
        try self.defineField(object, name, try self.oauthText(value, optional));
    }

    fn oauthOperation(self: *Manager, method: OAuthMethod, argument: c.JSValue) !c.JSValue {
        const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(object);
        const info = if (c.JS_IsUndefined(argument)) try self.engine.checked(c.JS_NewObject(self.engine.context)) else c.JS_DupValue(self.engine.context, argument);
        defer self.engine.freeValue(info);
        switch (method) {
            .onAuth => {
                try self.oauthField(object, "url", info, &.{"url"}, false);
                try self.oauthField(object, "instructions", info, &.{"instructions"}, true);
            },
            .onDeviceCode => {
                try self.oauthField(object, "verificationUri", info, &.{ "verificationUri", "verification_uri", "url" }, false);
                try self.oauthField(object, "userCode", info, &.{ "userCode", "user_code", "code" }, false);
                try self.defineField(object, "intervalSeconds", try self.oauthProperty(info, &.{ "intervalSeconds", "interval_seconds" }));
                try self.defineField(object, "expiresInSeconds", try self.oauthProperty(info, &.{ "expiresInSeconds", "expires_in_seconds" }));
                try self.oauthField(object, "instructions", info, &.{"instructions"}, true);
            },
            .onPrompt, .onSelect => {
                try self.oauthField(object, "message", info, &.{ "message", "title" }, false);
                if (method == .onPrompt) {
                    try self.oauthField(object, "placeholder", info, &.{"placeholder"}, true);
                    const secret = try self.oauthProperty(info, &.{"secret"});
                    defer self.engine.freeValue(secret);
                    try self.defineField(object, "secret", c.pi_js_bool(self.engine.context, c.JS_ToBool(self.engine.context, secret)));
                } else {
                    const source = try self.oauthProperty(info, &.{"options"});
                    defer self.engine.freeValue(source);
                    const options = try self.engine.checked(c.JS_NewArray(self.engine.context));
                    var transferred = false;
                    defer if (!transferred) self.engine.freeValue(options);
                    var args = [_]c.JSValue{source};
                    const is_array = try self.engine.checked(c.JS_Call(self.engine.context, self.components.array_is_array, c.pi_js_undefined(), 1, &args));
                    defer self.engine.freeValue(is_array);
                    if (c.JS_ToBool(self.engine.context, is_array) != 0) {
                        const length = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, source, "length"));
                        defer self.engine.freeValue(length);
                        var number: f64 = 0;
                        if (c.JS_ToFloat64(self.engine.context, &number, length) < 0) return error.JavaScriptException;
                        if (!std.math.isFinite(number) or number < 0 or number > 4096) return error.NativeDialogLimit;
                        for (0..@as(usize, @intFromFloat(number))) |i| {
                            const option = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, source, @intCast(i)));
                            defer self.engine.freeValue(option);
                            const normalized = try self.engine.checked(c.JS_NewObject(self.engine.context));
                            var published = false;
                            defer if (!published) self.engine.freeValue(normalized);
                            if (c.JS_IsObject(option)) {
                                try self.oauthField(normalized, "value", option, &.{ "id", "value" }, false);
                                try self.oauthField(normalized, "label", option, &.{ "label", "id", "value" }, false);
                                try self.oauthField(normalized, "description", option, &.{"description"}, true);
                            } else {
                                try self.defineField(normalized, "value", try self.oauthText(option, false));
                                try self.defineField(normalized, "label", try self.oauthText(option, false));
                            }
                            published = true;
                            if (c.JS_SetPropertyUint32(self.engine.context, options, @intCast(i), normalized) < 0) return error.JavaScriptException;
                        }
                    }
                    transferred = true;
                    try self.defineField(object, "options", options);
                }
            },
            .onProgress => try self.defineField(object, "message", try self.oauthText(argument, false)),
            .onManualCodeInput => try self.defineField(object, "message", try self.engine.checked(c.JS_NewString(self.engine.context, "Paste the authorization code"))),
        }
        const name: [*:0]const u8 = switch (method) {
            .onAuth => "oauth_auth",
            .onDeviceCode => "oauth_device_code",
            .onPrompt => "oauth_prompt",
            .onProgress => "oauth_progress",
            .onManualCodeInput => "oauth_manual_code",
            .onSelect => "oauth_select",
        };
        if (method == .onPrompt or method == .onManualCodeInput or method == .onSelect) return self.requestProvider(std.mem.span(name), object);
        if (self.provider_action_fn) |record| try record(self.provider_action_context, name, object);
        const encoded = try self.engine.stringify(object);
        defer self.engine.gpa.free(encoded);
        if (self.bridge) |bridge| try bridge.action(bridge.context, std.mem.span(name), encoded);
        return c.pi_js_undefined();
    }

    pub fn poll(self: *Manager) !bool {
        var changed = try self.pollCustom();
        if (try self.editors.pumpDirty()) changed = true;
        const io = self.engine.native_io orelse return changed;
        const now = std.Io.Clock.awake.now(io).toMilliseconds();
        var index: usize = 0;
        while (index < self.pending.items.len) {
            const pending = self.pending.items[index];
            if (pending.deadline) |deadline| if (now >= deadline) {
                try self.cancel(pending.id);
                changed = true;
                continue;
            };
            index += 1;
        }
        return changed;
    }

    fn onAbort(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        const self = current(engine, data) catch return c.pi_js_undefined();
        var id: u32 = 0;
        if (c.JS_ToUint32(context, &id, data[2]) < 0) return engine.throwCaptured();
        self.cancel(id) catch |err| return fail(engine, err);
        return c.pi_js_undefined();
    }

    fn action(self: *Manager, method: Method, args: []c.JSValue) !c.JSValue {
        if (method == .getEditorText) return c.JS_DupValue(self.engine.context, self.editor_text);
        const object = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(object);
        switch (method) {
            .notify => {
                try self.defineField(object, "message", try self.stringArgument(args, 0, null));
                try self.defineField(object, "type", try self.stringArgument(args, 1, "info"));
            },
            .setStatus => {
                try self.defineField(object, "key", try self.stringArgument(args, 0, null));
                try self.defineField(object, "text", if (args.len < 2 or c.JS_IsUndefined(args[1]) or c.JS_IsNull(args[1])) c.pi_js_null() else try self.stringArgument(args, 1, null));
            },
            .setTitle => try self.defineField(object, "title", try self.stringArgument(args, 0, null)),
            .setEditorText, .pasteToEditor => {
                const text = try self.stringArgument(args, 0, null);
                defer self.engine.freeValue(text);
                if (method == .setEditorText) {
                    self.engine.freeValue(self.editor_text);
                    self.editor_text = c.JS_DupValue(self.engine.context, text);
                } else {
                    const old = try self.engine.toString(self.editor_text);
                    defer self.engine.gpa.free(old);
                    const added = try self.engine.toString(text);
                    defer self.engine.gpa.free(added);
                    const joined = try std.mem.concat(self.engine.gpa, u8, &.{ old, added });
                    defer self.engine.gpa.free(joined);
                    const value = try self.engine.checked(c.JS_NewStringLen(self.engine.context, joined.ptr, joined.len));
                    self.engine.freeValue(self.editor_text);
                    self.editor_text = value;
                }
                try self.defineField(object, "text", c.JS_DupValue(self.engine.context, text));
                const draft_contents = try self.engine.toString(self.editor_text);
                defer self.engine.gpa.free(draft_contents);
                try self.editors.setDraft(draft_contents);
            },
            .setWorkingVisible => try self.defineField(object, "visible", c.pi_js_bool(self.engine.context, if (args.len > 0) c.JS_ToBool(self.engine.context, args[0]) else 0)),
            .setWorkingMessage, .setHiddenThinkingLabel => try self.defineField(object, if (method == .setWorkingMessage) "message" else "label", if (args.len == 0 or c.JS_IsUndefined(args[0]) or c.JS_IsNull(args[0])) c.pi_js_null() else try self.stringArgument(args, 0, null)),
            .setWidget => {
                try self.defineField(object, "key", try self.stringArgument(args, 0, null));
                if (args.len > 1 and !c.JS_IsUndefined(args[1]) and !c.JS_IsNull(args[1]) and !c.JS_IsArray(args[1])) return error.NativeWidgetFactoriesNotImplemented;
                try self.defineField(object, "lines", if (args.len < 2 or c.JS_IsUndefined(args[1])) c.pi_js_null() else c.JS_DupValue(self.engine.context, args[1]));
                var placement = try self.engine.checked(c.JS_NewString(self.engine.context, "aboveEditor"));
                if (args.len > 2 and c.JS_IsObject(args[2])) {
                    const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, args[2], "placement"));
                    defer self.engine.freeValue(value);
                    if (!c.JS_IsUndefined(value)) {
                        self.engine.freeValue(placement);
                        var values = [_]c.JSValue{value};
                        placement = try self.stringArgument(&values, 0, null);
                    }
                }
                try self.defineField(object, "placement", placement);
            },
            else => return error.NativeUiOperationUnsupported,
        }
        const encoded = try self.engine.stringify(object);
        defer self.engine.gpa.free(encoded);
        if (self.bridge) |bridge| try bridge.action(bridge.context, @tagName(method), encoded);
        return c.pi_js_undefined();
    }
};

fn focusLifetimeCase(source: []const u8, finish: ?[]const u8, inspect: ?[]const u8) !void {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("abort_signal.zig").install(engine);
    const manager = try Manager.init(engine);
    defer manager.deinit();
    const Receiver = struct {
        engine: *engine_mod.Engine,
        closed: ?protocol.Fence = null,
        frames: usize = 0,
        fn request(_: ?*anyopaque, _: u32, _: []const u8, _: []const u8) !void {}
        fn action(_: ?*anyopaque, _: []const u8, _: []const u8) !void {}
        fn cancel(_: ?*anyopaque, _: u32) !void {}
        fn scene(raw: ?*anyopaque, received: protocol.Scene) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const global_object = c.JS_GetGlobalObject(self.engine.context);
            defer self.engine.freeValue(global_object);
            const expected = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global_object, "expectedFocusedRelease"));
            defer self.engine.freeValue(expected);
            if (c.JS_ToBool(self.engine.context, expected) != 0) {
                try std.testing.expect(received.target_id != 0);
                try std.testing.expect(received.wants_key_release);
            }
            var owned = received;
            owned.deinit();
            self.frames += 1;
        }
        fn close(raw: ?*anyopaque, fence: protocol.Fence) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try std.testing.expect(self.closed == null);
            self.closed = fence;
        }
    };
    var receiver: Receiver = .{ .engine = engine };
    manager.bridge = .{ .context = &receiver, .request = Receiver.request, .action = Receiver.action, .cancel = Receiver.cancel, .component_scene = Receiver.scene, .component_close = Receiver.close };
    const snapshot = try engine.checked(c.JS_ParseJSON(engine.context, "{\"hasUI\":true}", 14, "focus-lifetime-context"));
    defer engine.freeValue(snapshot);
    try manager.begin(1, snapshot, null);
    manager.invocation_id = 1;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(engine.context, global, "nativeUi", try manager.createObject(), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    const promise = try engine.eval(source, "focus-lifetime-input.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(promise);
    for (0..16) |_| {
        _ = try manager.pollCustom();
        if (receiver.frames > 0 or receiver.closed != null) break;
    }
    if (receiver.frames == 0 and receiver.closed == null) return error.MissingNativeComponentScene;
    if (receiver.closed == null) {
        const active = manager.customs.items[0];
        var stale: protocol.Control = .{ .gpa = std.testing.allocator, .fence = active.fence, .target_id = active.focus_target_id, .target_generation = active.focus_target_generation + 1, .kind = .{ .input = try std.testing.allocator.dupe(u8, "stale") } };
        defer stale.deinit();
        try std.testing.expect(!try manager.componentControl(&stale));
        stale.target_generation = active.focus_target_generation;
        stale.target_id += 1;
        try std.testing.expect(!try manager.componentControl(&stale));
    }
    if (inspect) |expression| {
        const result = try engine.eval(expression, "focus-lifetime-inspection.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(result);
        try std.testing.expect(c.JS_ToBool(engine.context, result) != 0);
    }
    if (finish) |expression| {
        const result = engine.eval(expression, "focus-lifetime-finish.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
            if (engine.captured_exception) |exception| {
                const detail = try engine.toString(exception);
                defer engine.gpa.free(detail);
                std.debug.print("Focus lifecycle finish failed: {s}\n", .{detail});
            }
            return err;
        };
        defer engine.freeValue(result);
    }
    c.JS_RunGC(engine.runtime);
    const fence = receiver.closed orelse return error.MissingNativeComponentClose;
    const control: protocol.Control = .{ .gpa = std.testing.allocator, .fence = fence, .kind = .{ .close_ack = true } };
    try std.testing.expect(try manager.componentControl(&control));
    _ = try manager.pollCustom();
    const result = try engine.awaitValue(promise);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_ToBool(engine.context, result) != 0);
    try std.testing.expectEqual(@as(usize, 0), manager.customs.items.len);
    try std.testing.expectEqual(@as(usize, 0), manager.components.entries.count());
    c.JS_RunGC(engine.runtime);
}

test "native focused opening setter failure rejects through close acknowledgement without duplicate ownership" {
    try focusLifetimeCase(
        "globalThis.original={opening:1}; nativeUi.custom((tui)=>{const root={get focused(){return false},set focused(value){if(value)throw original},render(){return ['root']}}; tui.setFocus(root);return root}).then(()=>false,error=>error===original)",
        null,
        null,
    );
}

test "native focused close setter failure replaces success but preserves a primary rejection" {
    try focusLifetimeCase(
        "globalThis.original={cleanup:1};nativeUi.custom((tui,theme,keys,done)=>{let armed=false,focused=false;globalThis.finish=()=>{armed=true;done('success')};const root={get focused(){return focused},set focused(value){if(!value&&armed)throw original;focused=value},render(){return ['root']}};tui.setFocus(root);return root}).then(()=>false,error=>error===original)",
        "finish()",
        null,
    );
    try focusLifetimeCase(
        "globalThis.original={primary:1};nativeUi.custom((tui)=>{let armed=false,focused=false;const root={get focused(){return focused},set focused(value){if(!value&&armed)throw {cleanup:1};focused=value},render(){armed=true;throw original}};tui.setFocus(root);return root}).then(()=>false,error=>error===original)",
        null,
        null,
    );
}

test "native focused setters reenter without committing an obsolete target and clear focus before disposal" {
    try focusLifetimeCase(
        "globalThis.one=null;globalThis.two=null;nativeUi.custom((tui,theme,keys,done)=>{let first=false;two={focused:false,handleInput(){}};one={get focused(){return first},set focused(value){first=value;if(value)tui.setFocus(two)},handleInput(){}};globalThis.finish=()=>done('success');const root={render(){return ['root']},dispose(){if(two.focused)throw Error('target still focused')}};tui.setFocus(one);return root}).then(value=>value==='success',()=>false)",
        "finish()",
        "one.focused===false&&two.focused===true",
    );
}

test "native focused blocked replacement null resumes root and explicit unfocus target waits for replacement close" {
    try focusLifetimeCase(
        "globalThis.root=null;globalThis.replacement={focused:false};nativeUi.custom((tui,theme,keys,done)=>{root={focused:false,render(){return ['root']}};tui.setFocus(root);globalThis.finish=()=>{tui.setFocus(replacement);if(root.focused||!replacement.focused)throw Error('replacement');tui.setFocus(null);if(!root.focused||replacement.focused)throw Error('blocked null');done('success')};return root}).then(value=>value==='success',()=>false)",
        "finish()",
        null,
    );
    try focusLifetimeCase(
        "globalThis.root=null;globalThis.replacement={focused:false};globalThis.destination={focused:false};let tuiRef;nativeUi.custom((tui,theme,keys,done)=>{tuiRef=tui;root={focused:false,render(){return ['root']}};globalThis.finish=()=>{tui.setFocus(replacement);h.unfocus({target:destination});if(!replacement.focused||destination.focused)throw Error('premature restore');tui.setFocus(null);if(!destination.focused||replacement.focused||root.focused)throw Error('explicit target');done('success')};return root},{overlay:true,overlayOptions:{nonCapturing:true,width:12},onHandle(handle){globalThis.h=handle;handle.focus()}}).then(value=>value==='success',()=>false)",
        "finish()",
        null,
    );
}

test "native focused overlay geometry getters cannot publish obsolete target or release metadata" {
    try focusLifetimeCase(
        "globalThis.expectedFocusedRelease=true;nativeUi.custom((tui,theme,keys,done)=>{let widths=0;const child={focused:false,wantsKeyRelease:true};const root={focused:false,render(){return ['root']}};tui.setFocus(root);globalThis.options={get width(){if(++widths===2)tui.setFocus(child);return 12}};globalThis.finish=()=>done('success');return root},{overlay:true,overlayOptions:()=>options}).then(value=>value==='success',()=>false)",
        "finish()",
        null,
    );
}

test "native overlay default options retain component width and omitted maximum height" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("abort_signal.zig").install(engine);
    const manager = try Manager.init(engine);
    defer manager.deinit();
    const Fake = struct {
        frames: usize = 0,
        fn request(_: ?*anyopaque, _: u32, _: []const u8, _: []const u8) !void {}
        fn action(_: ?*anyopaque, _: []const u8, _: []const u8) !void {}
        fn cancel(_: ?*anyopaque, _: u32) !void {}
        fn scene(raw: ?*anyopaque, received: protocol.Scene) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const layout = received.overlay orelse return error.MissingOverlay;
            try std.testing.expectEqual(@as(usize, 12), layout.width);
            try std.testing.expectEqual(@as(usize, 30), layout.height);
            try std.testing.expectEqual(@as(usize, 30), received.frame.lines.len);
            self.frames += 1;
            var owned = received;
            owned.deinit();
        }
    };
    var fake: Fake = .{};
    manager.bridge = .{ .context = &fake, .request = Fake.request, .action = Fake.action, .cancel = Fake.cancel, .component_scene = Fake.scene };
    const context = try engine.fromJsonValue(.{ .object = .empty });
    defer engine.freeValue(context);
    try manager.defineField(context, "hasUI", c.pi_js_bool(engine.context, 1));
    try manager.begin(1, context, null);
    manager.invocation_id = 1;
    const module = try engine.evalModule("export function factory(){return {width:12,render(){return Array(30).fill('line')}}}", "overlay-defaults.mjs");
    defer engine.freeValue(module);
    const factory = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "factory"));
    defer engine.freeValue(factory);
    const options = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(options);
    try manager.defineField(options, "overlay", c.pi_js_bool(engine.context, 1));
    var args = [_]c.JSValue{ factory, options };
    const promise = try manager.custom(&args);
    defer engine.freeValue(promise);
    try std.testing.expect(try manager.pollCustom());
    try std.testing.expectEqual(@as(usize, 1), fake.frames);
}

test "native dialog awaiting human response suspends ordinary engine deadline and resumes after settlement" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 1 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("abort_signal.zig").install(engine);
    const manager = try Manager.init(engine);
    defer manager.deinit();
    const Context = struct {
        manager: *Manager,
        id: u32 = 0,
        polls: usize = 0,
        fn request(context: ?*anyopaque, id: u32, _: []const u8, _: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.id = id;
        }
        fn action(_: ?*anyopaque, _: []const u8, _: []const u8) !void {}
        fn cancel(_: ?*anyopaque, _: u32) !void {}
        fn pump(owner: *engine_mod.Engine) !bool {
            const self: *@This() = @ptrCast(@alignCast(owner.host_control_context.?));
            self.polls += 1;
            if (self.polls < 3 or self.id == 0) return false;
            const value = try owner.checked(c.JS_NewString(owner.context, "human-answer"));
            defer owner.freeValue(value);
            try self.manager.respond(self.id, true, value);
            self.id = 0;
            return true;
        }
    };
    var context: Context = .{ .manager = manager };
    manager.bridge = .{ .context = &context, .request = Context.request, .action = Context.action, .cancel = Context.cancel };
    const snapshot = try engine.checked(c.JS_ParseJSON(engine.context, "{\"hasUI\":true}", 14, "ui-deadline-context"));
    defer engine.freeValue(snapshot);
    try manager.begin(1, snapshot, null);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(engine.context, global, "nativeUi", try manager.createObject(), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    engine.host_control_context = &context;
    engine.host_control_pump = Context.pump;
    const promise = try engine.eval("nativeUi.select('Title',[])", "native-ui-human-deadline.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(promise);
    const result = try engine.awaitValue(promise);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("human-answer", text);
    try std.testing.expectEqual(@as(usize, 3), context.polls);
    try std.testing.expectEqual(@as(usize, 0), engine.host_ui_pending);
}
