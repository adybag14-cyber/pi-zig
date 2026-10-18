//! Actual c268 RPC extension UI methods and dialog Promise executors.
const h = @import("native_public_rpc_state.zig");
const v = h.v;
const c = h.c;
const Engine = h.Engine;
const Scope = h.Scope;
const Main = h.Frame;
const Dialog = h.lexical.Frame(enum { opts, default_value, request, parse_response, id });
const Executor = h.lexical.Frame(enum { resolve, reject, timeout_id, cleanup, on_abort });
const Editor = h.lexical.Frame(enum { title, prefill, id });
const EditorExecutor = h.lexical.Frame(enum { resolve, reject });
const RequestKind = enum { select, confirm, input };
const Notice = enum { notify, status, widget, title, editor_text };

/// Captures the actual main pending/output cells and the actual UUID binding.
pub fn dialogFunction(s: *Scope, pending: c.JSValue, output: c.JSValue, uuid: c.JSValue) !c.JSValue {
    return v.ordinary(s, "createDialogPromise", 4, dialog, &.{ pending, output, uuid });
}
/// Captures createDialogPromise, output, pending map, UUID and original Theme.
pub fn contextFunction(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    return v.arrow(s, "createExtensionUIContext", 0, createContext, roots);
}
fn dialog(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    const f = Dialog.create(&s) catch |err| return v.owned.finishValue(&s, err);
    const keeper = h.duplicate(engine, f.owner);
    var selected = v.owned.Completion.initValue(engine, dialogBody(f, args, roots));
    selected.releaseScope(&s); f.close(&selected); selected.release(keeper);
    return selected.finishValue();
}
fn dialogBody(f: *Dialog, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try f.copy(.opts, v.arg(args, 0)); try f.copy(.default_value, v.arg(args, 1));
    try f.copy(.request, v.arg(args, 2)); try f.copy(.parse_response, v.arg(args, 3));
    if (h.truthy(f.engine, try h.expression(f.engine, initialAborted, .{f.get(.opts)})))
        return h.expression(f.engine, resolvedDefault, .{f.get(.default_value)});
    try f.take(.id, h.expression(f.engine, h.functionCall, .{ roots[2], @as([]const c.JSValue, &.{}) }));
    return h.expression(f.engine, newDialogPromise, .{ f, roots });
}
fn optionalSignal(s: *Scope, opts: c.JSValue) !c.JSValue {
    return if (v.nullish(opts)) c.pi_js_undefined() else v.duplicate(s, try v.get(s, opts, "signal"));
}
fn initialAborted(s: *Scope, opts: c.JSValue) !c.JSValue {
    const signal = try v.own(s, try h.expression(s.engine, optionalSignal, .{opts}));
    return v.boolean(s, if (v.nullish(signal)) false else v.truthy(s, try v.get(s, signal, "aborted")));
}
fn resolvedDefault(s: *Scope, default_value: c.JSValue) !c.JSValue {
    const promise = try v.global(s, "Promise"); const resolve = try v.get(s, promise, "resolve");
    return v.duplicate(s, try v.call(s, resolve, promise, &.{default_value}));
}
fn newDialogPromise(s: *Scope, f: *Dialog, roots: []const c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Promise");
    const executor = try v.arrow(s, "", 2, dialogExecutor, &.{
        try f.capture(s, .opts, "opts"), try f.capture(s, .default_value, "defaultValue"),
        try f.capture(s, .request, "request"), try f.capture(s, .parse_response, "parseResponse"),
        try f.capture(s, .id, "id"), roots[0], roots[1],
    });
    return v.duplicate(s, try v.construct(s, constructor, &.{executor}));
}
fn dialogExecutor(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    const f = Executor.create(&s) catch |err| return v.owned.finishValue(&s, err);
    const keeper = h.duplicate(engine, f.owner);
    var selected = v.owned.Completion.initValue(engine, executorBody(f, args, roots));
    selected.releaseScope(&s); f.close(&selected); selected.release(keeper);
    return selected.finishValue();
}
fn executorBody(f: *Executor, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try f.copy(.resolve, v.arg(args, 0)); try f.copy(.reject, v.arg(args, 1)); try f.clear(.timeout_id);
    try f.take(.cleanup, h.expression(f.engine, makeCleanup, .{ f, roots }));
    try f.take(.on_abort, h.expression(f.engine, makeAbort, .{ f, roots, @as([*:0]const u8, "onAbort") }));
    try h.statement(f.engine, addAbort, .{ f, roots[0] });
    if (h.truthy(f.engine, try h.expression(f.engine, timeoutTruthy, .{roots[0]})))
        try f.take(.timeout_id, h.expression(f.engine, startTimeout, .{ f, roots }));
    try h.statement(f.engine, registerPending, .{ f, roots });
    try h.statement(f.engine, sendDialog, .{roots});
    return c.pi_js_undefined();
}
fn makeCleanup(s: *Scope, f: *Executor, roots: []const c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.arrow(s, "cleanup", 0, cleanup, &.{
        try f.capture(s, .timeout_id, "timeoutId"), roots[0], try f.capture(s, .on_abort, "onAbort"), roots[5], roots[4],
    }));
}
fn makeAbort(s: *Scope, f: *Executor, roots: []const c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.arrow(s, name, 0, abort, &.{
        try f.capture(s, .cleanup, "cleanup"), try f.capture(s, .resolve, "resolve"), roots[1],
    }));
}
fn executorCellTruthy(s: *Scope, cell: c.JSValue) !c.JSValue { return v.boolean(s, v.truthy(s, try Executor.read(s, cell))); }
fn cleanup(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (h.truthy(engine, try h.expression(engine, executorCellTruthy, .{roots[0]}))) try h.statement(engine, clearTimeout, .{roots[0]});
    try h.statement(engine, removeAbort, .{ roots[1], roots[2] });
    try h.statement(engine, deletePending, .{ roots[3], roots[4] });
    return c.pi_js_undefined();
}
fn clearTimeout(s: *Scope, cell: c.JSValue) !void {
    const callable = try v.global(s, "clearTimeout"); _ = try v.call(s, callable, c.pi_js_undefined(), &.{try Executor.read(s, cell)});
}
fn dialogSignal(s: *Scope, opts_cell: c.JSValue) !c.JSValue {
    const opts = try Dialog.read(s, opts_cell);
    return if (v.nullish(opts)) c.pi_js_undefined() else v.duplicate(s, try v.get(s, opts, "signal"));
}
fn removeAbort(s: *Scope, opts_cell: c.JSValue, on_abort: c.JSValue) !void {
    const signal = try v.own(s, try h.expression(s.engine, dialogSignal, .{opts_cell}));
    if (v.nullish(signal)) return;
    const method = try v.get(s, signal, "removeEventListener"); const name = try v.text(s, "abort");
    _ = try v.call(s, method, signal, &.{ name, try Executor.read(s, on_abort) });
}
fn addAbort(s: *Scope, f: *Executor, opts_cell: c.JSValue) !void {
    const signal = try v.own(s, try h.expression(s.engine, dialogSignal, .{opts_cell}));
    if (v.nullish(signal)) return;
    const method = try v.get(s, signal, "addEventListener"); const name = try v.text(s, "abort");
    const options = try v.object(s); try v.put(s, options, "once", v.boolean(s, true));
    _ = try v.call(s, method, signal, &.{ name, f.get(.on_abort), options });
}
fn deletePending(s: *Scope, pending: c.JSValue, id_cell: c.JSValue) !void {
    const receiver = try Main.read(s, pending); const method = try v.get(s, receiver, "delete");
    _ = try v.call(s, method, receiver, &.{try Dialog.read(s, id_cell)});
}
fn executorCall(s: *Scope, cell: c.JSValue) !void { _ = try v.call(s, try Executor.read(s, cell), c.pi_js_undefined(), &.{}); }
fn abort(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.statement(engine, executorCall, .{roots[0]});
    try h.statement(engine, resolveDefault, .{ roots[1], roots[2] });
    return c.pi_js_undefined();
}
fn resolveDefault(s: *Scope, resolve_cell: c.JSValue, default_cell: c.JSValue) !void {
    const resolve = try Executor.read(s, resolve_cell);
    _ = try v.call(s, resolve, c.pi_js_undefined(), &.{try Dialog.read(s, default_cell)});
}
fn timeoutTruthy(s: *Scope, opts_cell: c.JSValue) !c.JSValue {
    const opts = try Dialog.read(s, opts_cell);
    return v.boolean(s, if (v.nullish(opts)) false else v.truthy(s, try v.get(s, opts, "timeout")));
}
fn timeoutValue(s: *Scope, opts_cell: c.JSValue) !c.JSValue { return v.duplicate(s, try v.get(s, try Dialog.read(s, opts_cell), "timeout")); }
fn startTimeout(s: *Scope, f: *Executor, roots: []const c.JSValue) !c.JSValue {
    const callable = try v.global(s, "setTimeout");
    const callback = try v.own(s, try h.expression(s.engine, makeAbort, .{ f, roots, @as([*:0]const u8, "") }));
    const timeout = try v.own(s, try h.expression(s.engine, timeoutValue, .{roots[0]}));
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{ callback, timeout }));
}
fn registerPending(s: *Scope, f: *Executor, roots: []const c.JSValue) !void {
    const pending = try Main.read(s, roots[5]); const method = try v.get(s, pending, "set");
    const id = try Dialog.read(s, roots[4]); const record = try v.object(s);
    try v.put(s, record, "resolve", try v.arrow(s, "resolve", 1, resolveDialog, &.{
        try f.capture(s, .cleanup, "cleanup"), try f.capture(s, .resolve, "resolve"), roots[3],
    }));
    try v.put(s, record, "reject", f.get(.reject));
    _ = try v.call(s, method, pending, &.{ id, record });
}
fn resolveDialog(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.statement(engine, executorCall, .{roots[0]});
    try h.statement(engine, resolveParsed, .{ roots[1], roots[2], v.arg(args, 0) });
    return c.pi_js_undefined();
}
fn parseResponse(s: *Scope, cell: c.JSValue, response: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, try Dialog.read(s, cell), c.pi_js_undefined(), &.{response}));
}
fn resolveParsed(s: *Scope, resolve_cell: c.JSValue, parse_cell: c.JSValue, response: c.JSValue) !void {
    const resolve = try Executor.read(s, resolve_cell);
    const parsed = try v.own(s, try h.expression(s.engine, parseResponse, .{ parse_cell, response }));
    _ = try v.call(s, resolve, c.pi_js_undefined(), &.{parsed});
}
fn sendDialog(s: *Scope, roots: []const c.JSValue) !void {
    const output = try Main.read(s, roots[6]); const record = try v.object(s);
    try v.put(s, record, "type", try v.text(s, "extension_ui_request"));
    try v.put(s, record, "id", try Dialog.read(s, roots[4]));
    try h.statement(s.engine, spreadRequest, .{ record, roots[2] });
    _ = try v.call(s, output, c.pi_js_undefined(), &.{record});
}
fn spreadRequest(s: *Scope, target: c.JSValue, cell: c.JSValue) !void {
    const source = try Dialog.read(s, cell);
    if (v.nullish(source)) return;
    const boxed = try v.guest.toObject(s, source);
    var names: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const status = c.JS_GetOwnPropertyNames(s.engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK);
    defer if (names != null) c.JS_FreePropertyEnum(s.engine.context, names, count);
    try boundary.finishStatus(status);
    for (names[0..count]) |entry| {
        if (!try enumerable(s.engine, boxed, entry.atom)) continue;
        try h.statement(s.engine, copyProperty, .{ target, boxed, entry.atom });
    }
}
fn enumerable(engine: *Engine, source: c.JSValue, atom: c.JSAtom) !bool {
    var descriptor: c.JSPropertyDescriptor = undefined;
    var boundary: v.guest.Boundary = .{ .engine = engine }; try boundary.begin();
    const status = c.JS_GetOwnProperty(engine.context, &descriptor, source, atom);
    const outcome: anyerror!c.JSValue = if (boundary.finishStatus(status)) |_|
        c.JS_NewBool(engine.context, status != 0 and descriptor.flags & c.JS_PROP_ENUMERABLE != 0) else |err| err;
    var completion = v.owned.Completion.initValue(engine, outcome);
    if (status > 0) { completion.release(descriptor.value); completion.release(descriptor.getter); completion.release(descriptor.setter); }
    return h.truthy(engine, try completion.finishValue());
}
fn copyProperty(s: *Scope, target: c.JSValue, source: c.JSValue, atom: c.JSAtom) !void {
    const value = try v.guest.getAtom(s, source, atom);
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishStatus(c.JS_DefinePropertyValue(s.engine.context, target, atom, v.duplicate(s, value), c.JS_PROP_C_W_E));
}

fn createContext(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return h.expression(engine, contextBody, .{roots}); }
fn requestArrow(s: *Scope, comptime kind: RequestKind, dialog_cell: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return h.expression(engine, requestBody, .{ kind, args, roots[0] });
        }
    };
    return v.arrow(s, @tagName(kind), 3, Adapter.call, &.{dialog_cell});
}
fn requestBody(s: *Scope, comptime kind: RequestKind, args: []const c.JSValue, dialog_cell: c.JSValue) !c.JSValue {
    const callable = try Main.read(s, dialog_cell); const opts = v.arg(args, 2);
    const default = if (kind == .confirm) v.boolean(s, false) else c.pi_js_undefined();
    const request = try v.object(s);
    try v.put(s, request, "method", try v.text(s, @tagName(kind)));
    try v.put(s, request, "title", v.arg(args, 0));
    try v.put(s, request, if (kind == .select) "options" else if (kind == .confirm) "message" else "placeholder", v.arg(args, 1));
    try v.put(s, request, "timeout", try h.optionalField(s, opts, "timeout"));
    const Adapter = struct {
        fn call(engine: *Engine, _: c.JSValue, incoming: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return h.expression(engine, responseValue, .{ v.arg(incoming, 0), kind == .confirm });
        }
    };
    const parser = try v.arrow(s, "", 1, Adapter.call, &.{});
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{ opts, default, request, parser }));
}
fn cancelled(s: *Scope, response: c.JSValue) !c.JSValue {
    return v.boolean(s, try h.has(s, response, "cancelled") and v.truthy(s, try h.fieldValue(s, response, "cancelled")));
}
fn responseValue(s: *Scope, response: c.JSValue, confirm: bool) !c.JSValue {
    const default = if (confirm) v.boolean(s, false) else c.pi_js_undefined();
    if (h.truthy(s.engine, try h.expression(s.engine, cancelled, .{response}))) return default;
    const name: [*:0]const u8 = if (confirm) "confirmed" else "value";
    return if (try h.has(s, response, name)) v.duplicate(s, try v.get(s, response, name)) else default;
}
fn noticeMethod(s: *Scope, comptime kind: Notice, name: [*:0]const u8, length: c_int, output: c.JSValue, uuid: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return h.expression(engine, noticeBody, .{ kind, args, roots });
        }
    };
    return v.method(s, name, length, Adapter.call, &.{ output, uuid });
}
fn arrayTest(s: *Scope, content: c.JSValue) !c.JSValue {
    const array = try v.global(s, "Array");
    const method = try v.get(s, array, "isArray");
    const result = try v.call(s, method, array, &.{content});
    return v.boolean(s, v.truthy(s, result));
}
fn noticeBody(s: *Scope, comptime kind: Notice, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (kind == .widget and !c.JS_IsUndefined(v.arg(args, 1)) and !h.truthy(s.engine, try h.expression(s.engine, arrayTest, .{v.arg(args, 1)}))) return c.pi_js_undefined();
    const output = try Main.read(s, roots[0]); const record = try v.object(s);
    try v.put(s, record, "type", try v.text(s, "extension_ui_request"));
    try v.put(s, record, "id", try v.own(s, try h.expression(s.engine, h.functionCall, .{ roots[1], @as([]const c.JSValue, &.{}) })));
    try v.put(s, record, "method", try v.text(s, switch (kind) { .notify => "notify", .status => "setStatus", .widget => "setWidget", .title => "setTitle", .editor_text => "set_editor_text" }));
    switch (kind) {
        .notify => { try v.put(s, record, "message", v.arg(args, 0)); try v.put(s, record, "notifyType", v.arg(args, 1)); },
        .status => { try v.put(s, record, "statusKey", v.arg(args, 0)); try v.put(s, record, "statusText", v.arg(args, 1)); },
        .widget => { try v.put(s, record, "widgetKey", v.arg(args, 0)); try v.put(s, record, "widgetLines", v.arg(args, 1)); try v.put(s, record, "widgetPlacement", try h.optionalField(s, v.arg(args, 2), "placement")); },
        .title => try v.put(s, record, "title", v.arg(args, 0)),
        .editor_text => try v.put(s, record, "text", v.arg(args, 0)),
    }
    _ = try v.call(s, output, c.pi_js_undefined(), &.{record});
    return c.pi_js_undefined();
}
fn onTerminal(engine: *Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return h.expression(engine, emptyArrow, .{}); }
fn emptyArrow(s: *Scope) !c.JSValue { return v.duplicate(s, try v.arrow(s, "", 0, h.emptyCallback, &.{})); }
fn paste(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    try h.statement(engine, pasteBody, .{ receiver, v.arg(args, 0) }); return c.pi_js_undefined();
}
fn pasteBody(s: *Scope, receiver: c.JSValue, text: c.JSValue) !void { _ = try v.invoke(s, receiver, "setEditorText", &.{text}); }
fn editorText(engine: *Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return h.expression(engine, h.emptyText, .{}); }
fn allThemes(engine: *Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return h.expression(engine, h.emptyArray, .{}); }
fn theme(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return h.duplicate(engine, roots[0]); }
fn setTheme(engine: *Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return h.expression(engine, themeFailure, .{}); }
fn themeFailure(s: *Scope) !c.JSValue {
    const result = try v.object(s); try v.put(s, result, "success", v.boolean(s, false));
    try v.put(s, result, "error", try v.text(s, "Theme switching not supported in RPC mode")); return v.duplicate(s, result);
}
fn falseCallback(engine: *Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.JS_NewBool(engine.context, false); }
fn asyncMethod(s: *Scope, name: [*:0]const u8, length: c_int, callback: h.af.Callback, roots: []const c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, h.af.create(s.engine, name, length, callback, roots));
}
fn contextBody(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "select", try requestArrow(s, .select, roots[0]));
    try v.put(s, result, "confirm", try requestArrow(s, .confirm, roots[0]));
    try v.put(s, result, "input", try requestArrow(s, .input, roots[0]));
    try v.put(s, result, "notify", try noticeMethod(s, .notify, "notify", 2, roots[1], roots[3]));
    try v.put(s, result, "onTerminalInput", try v.method(s, "onTerminalInput", 0, onTerminal, &.{}));
    try v.put(s, result, "setStatus", try noticeMethod(s, .status, "setStatus", 2, roots[1], roots[3]));
    inline for (.{ "setWorkingMessage", "setWorkingVisible", "setWorkingIndicator", "setHiddenThinkingLabel" }) |name|
        try v.put(s, result, name, try v.method(s, name, 1, h.emptyCallback, &.{}));
    try v.put(s, result, "setWidget", try noticeMethod(s, .widget, "setWidget", 3, roots[1], roots[3]));
    try v.put(s, result, "setFooter", try v.method(s, "setFooter", 1, h.emptyCallback, &.{}));
    try v.put(s, result, "setHeader", try v.method(s, "setHeader", 1, h.emptyCallback, &.{}));
    try v.put(s, result, "setTitle", try noticeMethod(s, .title, "setTitle", 1, roots[1], roots[3]));
    try v.put(s, result, "custom", try asyncMethod(s, "custom", 0, h.emptyCallback, &.{}));
    try v.put(s, result, "pasteToEditor", try v.method(s, "pasteToEditor", 1, paste, &.{}));
    try v.put(s, result, "setEditorText", try noticeMethod(s, .editor_text, "setEditorText", 1, roots[1], roots[3]));
    try v.put(s, result, "getEditorText", try v.method(s, "getEditorText", 0, editorText, &.{}));
    try v.put(s, result, "editor", try asyncMethod(s, "editor", 2, editor, &.{ roots[2], roots[1], roots[3] }));
    try v.put(s, result, "addAutocompleteProvider", try v.method(s, "addAutocompleteProvider", 0, h.emptyCallback, &.{}));
    try v.put(s, result, "setEditorComponent", try v.method(s, "setEditorComponent", 0, h.emptyCallback, &.{}));
    try v.put(s, result, "getEditorComponent", try v.method(s, "getEditorComponent", 0, h.emptyCallback, &.{}));
    const getter = try v.method(s, "get theme", 0, theme, &.{roots[4]});
    const atom = c.JS_NewAtom(s.engine.context, "theme");
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(s.engine.context, atom);
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    try boundary.finishStatus(c.JS_DefinePropertyGetSet(s.engine.context, result, atom, v.duplicate(s, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE));
    try v.put(s, result, "getAllThemes", try v.method(s, "getAllThemes", 0, allThemes, &.{}));
    try v.put(s, result, "getTheme", try v.method(s, "getTheme", 1, h.emptyCallback, &.{}));
    try v.put(s, result, "setTheme", try v.method(s, "setTheme", 1, setTheme, &.{}));
    try v.put(s, result, "getToolsExpanded", try v.method(s, "getToolsExpanded", 0, falseCallback, &.{}));
    try v.put(s, result, "setToolsExpanded", try v.method(s, "setToolsExpanded", 1, h.emptyCallback, &.{}));
    return v.duplicate(s, result);
}

fn editor(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    const f = Editor.create(&s) catch |err| return v.owned.finishValue(&s, err);
    const keeper = h.duplicate(engine, f.owner);
    var selected = v.owned.Completion.initValue(engine, editorBody(f, args, roots));
    selected.releaseScope(&s); f.close(&selected); selected.release(keeper);
    return selected.finishValue();
}
fn editorBody(f: *Editor, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try f.copy(.title, v.arg(args, 0)); try f.copy(.prefill, v.arg(args, 1));
    try f.take(.id, h.expression(f.engine, h.functionCall, .{ roots[2], @as([]const c.JSValue, &.{}) }));
    return h.expression(f.engine, editorPromise, .{ f, roots });
}
fn editorPromise(s: *Scope, f: *Editor, roots: []const c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Promise");
    const executor = try v.arrow(s, "", 2, editorExecutor, &.{
        roots[0], roots[1], try f.capture(s, .title, "title"), try f.capture(s, .prefill, "prefill"), try f.capture(s, .id, "id"),
    });
    return v.duplicate(s, try v.construct(s, constructor, &.{executor}));
}
fn editorExecutor(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    const f = EditorExecutor.create(&s) catch |err| return v.owned.finishValue(&s, err);
    const keeper = h.duplicate(engine, f.owner);
    var selected = v.owned.Completion.initValue(engine, editorExecutorBody(f, args, roots));
    selected.releaseScope(&s); f.close(&selected); selected.release(keeper);
    return selected.finishValue();
}
fn editorExecutorBody(f: *EditorExecutor, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try f.copy(.resolve, v.arg(args, 0)); try f.copy(.reject, v.arg(args, 1));
    try h.statement(f.engine, editorPending, .{ f, roots }); try h.statement(f.engine, editorOutput, .{roots});
    return c.pi_js_undefined();
}
fn editorPending(s: *Scope, f: *EditorExecutor, roots: []const c.JSValue) !void {
    const pending = try Main.read(s, roots[0]); const method = try v.get(s, pending, "set"); const id = try Editor.read(s, roots[4]);
    const record = try v.object(s); try v.put(s, record, "resolve", try v.arrow(s, "resolve", 1, resolveEditor, &.{try f.capture(s, .resolve, "resolve")}));
    try v.put(s, record, "reject", f.get(.reject)); _ = try v.call(s, method, pending, &.{ id, record });
}
fn resolveEditor(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return h.expression(engine, resolveEditorBody, .{ roots[0], v.arg(args, 0) }); }
fn resolveEditorBody(s: *Scope, cell: c.JSValue, response: c.JSValue) !c.JSValue {
    const is_cancelled = h.truthy(s.engine, try h.expression(s.engine, cancelled, .{response}));
    if (is_cancelled) {
        _ = try v.call(s, try EditorExecutor.read(s, cell), c.pi_js_undefined(), &.{c.pi_js_undefined()});
    } else if (try h.has(s, response, "value")) {
        const resolve = try EditorExecutor.read(s, cell);
        _ = try v.call(s, resolve, c.pi_js_undefined(), &.{try h.fieldValue(s, response, "value")});
    } else _ = try v.call(s, try EditorExecutor.read(s, cell), c.pi_js_undefined(), &.{c.pi_js_undefined()});
    return c.pi_js_undefined();
}
fn editorOutput(s: *Scope, roots: []const c.JSValue) !void {
    const output = try Main.read(s, roots[1]); const record = try v.object(s);
    try v.put(s, record, "type", try v.text(s, "extension_ui_request")); try v.put(s, record, "id", try Editor.read(s, roots[4]));
    try v.put(s, record, "method", try v.text(s, "editor")); try v.put(s, record, "title", try Editor.read(s, roots[2]));
    try v.put(s, record, "prefill", try Editor.read(s, roots[3])); _ = try v.call(s, output, c.pi_js_undefined(), &.{record});
}
