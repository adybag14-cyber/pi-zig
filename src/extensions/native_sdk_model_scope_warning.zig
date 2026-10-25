//! Complete original 4954 resolveModelScope warning wrapper.
//! Uses genuine shared model resolver and consumed Chalk owners. This private
//! callable is not a completed Main runtime factory or public module namespace.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const Engine = h.Engine;
const Scope = h.Scope;
const af = v.af;
const Frame = @import("native_public_lexical_frame.zig").Frame(enum {
    scoped_models, diagnostics, diagnostic,
});
const key = "pi-private:actual-sdk-model-scope-warning";
const Creating = struct { engine: *Engine, previous: ?*Creating };
threadlocal var creating: ?*Creating = null;

/// Acquire only actual native imported owners. The corresponding original
/// default-map successor and matched resolver bodies are source prerequisites.
pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |cached|
        return h.get(engine, cached, "function");
    var cursor = creating;
    while (cursor) |current| : (cursor = current.previous)
        if (current.engine == engine) return error.ActualModelScopeWarningCreationReentry;
    var entry: Creating = .{ .engine = engine, .previous = creating };
    creating = &entry;
    defer creating = entry.previous;
    const owner = try h.expression(engine, createBody, .{});
    const function = h.get(engine, owner, "function") catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(owner); return failed.finishValue();
    };
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(function); failed.release(owner); return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(key, owner);
    return function;
}
fn createBody(s: *Scope) !c.JSValue {
    const chalk = try v.own(s, try @import("native_sdk_chalk.zig").createDefault(s.engine));
    const cli = try v.own(s, try @import("native_sdk_main_runtime_helpers.zig").cliBindings(s.engine));
    const thinking = try v.get(s, cli, "isValidThinkingLevel");
    const resolver = try v.own(s, try @import("native_sdk_public_model_resolver.zig").create(
        s.engine, .{ .thinking = thinking }));
    const with_diagnostics = try v.get(s, resolver, "resolveModelScopeWithDiagnostics");
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const function = try boundary.finishValue(s, af.createResumableWithClose(
        s.engine, "resolveModelScope", 3, resolveBody,
        &.{with_diagnostics, chalk}, Frame.closeAtAsyncTerminal));
    const owner = try v.stateObject(s);
    try v.put(s, owner, "chalk", chalk);
    try v.put(s, owner, "cli", cli);
    try v.put(s, owner, "resolver", resolver);
    try v.put(s, owner, "function", function);
    return v.duplicate(s, owner);
}
fn invokeResolver(s: *Scope, function: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, function, c.pi_js_undefined(),
        &.{v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)}));
}
fn bindResult(s: *Scope, frame: *Frame, incoming: c.JSValue) !void {
    // The original object pattern converts exactly once, then commits each
    // lexical binding in order. Its temporary ends before iterator acquisition.
    const object = try v.guest.toObject(s, incoming);
    try frame.copy(.scoped_models, try v.get(s, object, "scopedModels"));
    try frame.copy(.diagnostics, try v.get(s, object, "diagnostics"));
}
fn messageString(s: *Scope, diagnostic: c.JSValue) !c.JSValue {
    // A message object is a temporary operand of the template's ToString.
    // It must retire before the later color and console calls can observe it.
    return v.duplicate(s, try v.stringify(s, try v.get(s, diagnostic, "message")));
}
fn warningText(s: *Scope, diagnostic: c.JSValue) !c.JSValue {
    const prefix = try v.text(s, "Warning: ");
    const message = try v.own(s, try h.expression(s.engine, messageString, .{diagnostic}));
    return v.duplicate(s, try h.binary(s, .add, prefix, message));
}
fn coloredWarning(s: *Scope, chalk: c.JSValue, diagnostic: c.JSValue) !c.JSValue {
    const yellow = try v.get(s, chalk, "yellow");
    const text = try v.own(s, try h.expression(s.engine, warningText, .{diagnostic}));
    return v.duplicate(s, try v.call(s, yellow, chalk, &.{text}));
}
fn consoleBinding(s: *Scope) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    // Interning this fixed native name is allocation-only, before any guest
    // getter. The VM helper performs the same lexical/global lookup as get_var.
    const atom = c.JS_NewAtom(s.engine.context, "console");
    if (atom == c.JS_ATOM_NULL) return boundary.finishValue(s, error.OutOfMemory);
    defer c.JS_FreeAtom(s.engine.context, atom);
    return boundary.finishValue(s, c.JS_PiGetGlobalBinding(s.engine.context, atom));
}
fn warning(s: *Scope, chalk: c.JSValue, diagnostic: c.JSValue) !void {
    // Capture the outer callee/reference before evaluating its argument.
    // The nested yellow call retires its own callee and argument temporaries
    // before invoking the captured console.warn, matching the source expression.
    const console = try consoleBinding(s);
    const warn = try v.get(s, console, "warn");
    const colored = try v.own(s, try h.expression(s.engine, coloredWarning, .{chalk, diagnostic}));
    _ = try v.call(s, warn, console, &.{colored});
}
fn diagnosticsLoop(frame: *Frame, chalk: c.JSValue, iterator: *v.Iterator) !void {
    while (try iterator.next()) |incoming| {
        // The uncaptured for-of head is replaced only by the next assignment;
        // its previous value remains live through iterator-step evaluation.
        try frame.take(.diagnostic, incoming);
        try h.statement(frame.engine, warning, .{chalk, frame.get(.diagnostic)});
    }
}
fn advance(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue,
    state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action
{
    if (completion == .start) {
        const frame = try Frame.createAsync(s);
        af.replaceState(s.engine, state, v.duplicate(s, frame.owner));
        return .{ .awaited = try h.expression(s.engine, invokeResolver, .{roots[0], args}) };
    }
    if (completion == .rejected) return .{ .thrown = v.duplicate(s, input) };
    const frame = Frame.from(state.*);
    try h.statement(s.engine, bindResult, .{frame, input});
    var iterator = try v.Iterator.init(s.engine, frame.get(.diagnostics));
    try iterator.finish(diagnosticsLoop(frame, roots[1], &iterator));
    return .{ .returned = v.duplicate(s, frame.get(.scoped_models)) };
}
fn resolveBody(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion,
    input: c.JSValue) !af.Action
{
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine)
    else try engine.checkNativeEntry();
    var s: Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, advance(&s, args, roots, state, completion, input));
}
