//! Complete original project-trust.ts runtime export and private helpers.
//! Required genuine imported owners; no policy, context or Store substitute.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const Engine = h.Engine;
const Scope = h.Scope;
const af = v.af;
const lexical = @import("native_public_lexical_frame.zig");
const caught = @import("native_agent_af_values.zig").caught;

pub const Inputs = struct {
    configuration: c.JSValue,
    emit_project_trust_event: c.JSValue,
    settings_defaults: c.JSValue,
    trust_manager: c.JSValue,
};
const input_names = .{ "configuration", "emit_project_trust_event", "settings_defaults", "trust_manager" };
const cache_key = "pi-private:actual-sdk-project-trust-resolution";
const Creating = struct { engine: *Engine, previous: ?*Creating };
threadlocal var creating: ?*Creating = null;
const SelectFrame = lexical.Frame(enum { options, selected });
const ResolveLocal = enum {
    result, errors, error_item, trusted, decision, selected,
    // Operand roots follow all original locals at terminal retirement.
    iterator_receiver, iterator_next, iterator_active, stage,
};
const ResolveFrame = lexical.Frame(ResolveLocal);
const Root = enum { has_resources, emit_event, defaults, select_option, save_result };
fn root(roots: []const c.JSValue, comptime name: Root) c.JSValue {
    return roots[@intFromEnum(name)];
}

pub fn create(engine: *Engine, inputs: Inputs) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached|
        return h.expression(engine, cachedBody, .{ cached, inputs });
    var cursor = creating;
    while (cursor) |current| : (cursor = current.previous)
        if (current.engine == engine) return error.ActualProjectTrustResolutionCreationReentry;
    var entry: Creating = .{ .engine = engine, .previous = creating };
    creating = &entry;
    defer creating = entry.previous;
    var invocation: Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const result = createOwned(engine, inputs) catch |err|
        return engine.checked(engine.leaveNativeInvocation(&invocation,
            @import("native_sdk.zig").fail(engine, err)));
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn cachedBody(s: *Scope, cached: c.JSValue, inputs: Inputs) !c.JSValue {
    inline for (input_names) |name|
        if (!v.equal(s, try v.get(s, cached, name), @field(inputs, name)))
            return error.ActualProjectTrustResolutionImportsChanged;
    return v.duplicate(s, try v.get(s, cached, "exports"));
}
fn createOwned(engine: *Engine, inputs: Inputs) !c.JSValue {
    const graph = try h.expression(engine, createBody, .{inputs});
    const exports = h.get(engine, graph, "exports") catch |err| {
        var selected = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        selected.release(graph); return selected.finishValue();
    };
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var selected = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        selected.release(exports); selected.release(graph); return selected.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, graph);
    return exports;
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    inline for (input_names) |name|
        _ = try v.own(s, v.duplicate(s, @field(inputs, name)));
    const app_name = try v.get(s, inputs.configuration, "APP_NAME");
    const config_dir = try v.get(s, inputs.configuration, "CONFIG_DIR_NAME");
    // The event function and defaults are genuine owned import values supplied
    // by their native creators, not a fabricated partial export namespace.
    const get_options = try v.get(s, inputs.trust_manager, "getProjectTrustOptions");
    const has_resources = try v.get(s, inputs.trust_manager, "hasTrustRequiringProjectResources");
    const format_prompt = try v.ordinary(s, "formatProjectTrustPrompt", 1, formatPromptCall, &.{app_name, config_dir});
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const select_option = try boundary.finishValue(s, af.createResumableWithClose(
        s.engine, "selectProjectTrustOption", 2, selectBody, &.{get_options, format_prompt}, SelectFrame.closeAtAsyncTerminal));
    const save_result = try v.ordinary(s, "saveProjectTrustPromptResult", 2, saveCall, &.{});
    var resolve_boundary: v.guest.Boundary = .{ .engine = s.engine };
    try resolve_boundary.begin();
    const resolver = try resolve_boundary.finishValue(s, af.createResumableWithClose(
        s.engine, "resolveProjectTrusted", 1, resolveBody,
        &.{ has_resources, inputs.emit_project_trust_event, inputs.settings_defaults, select_option, save_result },
        ResolveFrame.closeAtAsyncTerminal));
    const exports = try v.object(s);
    try v.put(s, exports, "resolveProjectTrusted", resolver);
    const graph = try v.stateObject(s);
    inline for (input_names) |name| try v.put(s, graph, name, @field(inputs, name));
    try v.put(s, graph, "exports", exports);
    return v.duplicate(s, graph);
}

fn formatPromptCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, formatPromptBody, .{ v.arg(args, 0), roots[0], roots[1] });
}
fn formatPromptBody(s: *Scope, cwd: c.JSValue, app_name: c.JSValue, config_dir: c.JSValue) !c.JSValue {
    const first = try h.binary(s, .add, try v.text(s, "Trust project folder?\n"), try v.stringify(s, cwd));
    const second = try h.binary(s, .add, first, try v.text(s, "\n\nThis allows "));
    const third = try h.binary(s, .add, second, try v.stringify(s, app_name));
    const fourth = try h.binary(s, .add, third, try v.text(s, " to load "));
    const fifth = try h.binary(s, .add, fourth, try v.stringify(s, config_dir));
    return v.duplicate(s, try h.binary(s, .add, fifth,
        try v.text(s, " settings and resources, install missing project packages, and execute project extensions.")));
}
fn optionLabelCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return h.get(engine, v.arg(args, 0), "label");
}
fn labelsBody(s: *Scope, options: c.JSValue) !c.JSValue {
    const map = try v.get(s, options, "map");
    const callback = try v.arrow(s, "", 1, optionLabelCall, &.{});
    return v.duplicate(s, try v.call(s, map, options, &.{callback}));
}
fn optionsBody(s: *Scope, get_options: c.JSValue, cwd: c.JSValue) !c.JSValue {
    const options = try v.object(s);
    try v.put(s, options, "includeSessionOnly", v.boolean(s, true));
    return v.duplicate(s, try v.call(s, get_options, c.pi_js_undefined(), &.{cwd, options}));
}
fn selectCallBody(s: *Scope, ctx: c.JSValue, cwd: c.JSValue, options: c.JSValue, format: c.JSValue) !c.JSValue {
    const ui = try v.get(s, ctx, "ui");
    const select = try v.get(s, ui, "select");
    const prompt = try v.call(s, format, c.pi_js_undefined(), &.{cwd});
    const labels = try v.own(s, try h.expression(s.engine, labelsBody, .{options}));
    return v.duplicate(s, try v.call(s, select, ui, &.{prompt, labels}));
}
fn selectedLabelCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, selectedLabelBody, .{ v.arg(args, 0), roots[0] });
}
fn selectedLabelBody(s: *Scope, option: c.JSValue, cell: c.JSValue) !c.JSValue {
    const label = try v.get(s, option, "label");
    const selected = try SelectFrame.read(s, cell);
    return v.boolean(s, v.equal(s, label, selected));
}
fn findBody(s: *Scope, frame: *SelectFrame) !c.JSValue {
    const options = frame.get(.options);
    const find = try v.get(s, options, "find");
    const selected = try frame.capture(s, .selected, "selected");
    const callback = try v.arrow(s, "", 1, selectedLabelCall, &.{selected});
    return v.duplicate(s, try v.call(s, find, options, &.{callback}));
}
fn selectAdvance(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue,
    completion: af.Completion, input: c.JSValue) !af.Action
{
    if (completion == .start) {
        const frame = try SelectFrame.createAsync(s);
        af.replaceState(s.engine, state, v.duplicate(s, frame.owner));
        try frame.take(.options, h.expression(s.engine, optionsBody, .{ roots[0], v.arg(args, 0) }));
        return .{ .awaited = try h.expression(s.engine, selectCallBody,
            .{ v.arg(args, 1), v.arg(args, 0), frame.get(.options), roots[1] }) };
    }
    if (completion == .rejected) return .{ .thrown = v.duplicate(s, input) };
    const frame = SelectFrame.from(state.*);
    try frame.copy(.selected, input);
    return .{ .returned = try h.expression(s.engine, findBody, .{frame}) };
}
fn selectBody(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue,
    state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action
{
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    var s: Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, selectAdvance(&s, args, roots, state, completion, input));
}
fn updatesLengthBody(s: *Scope, result: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.get(s, result, "updates"), "length"));
}
fn hasUpdatesBody(s: *Scope, result: c.JSValue) !c.JSValue {
    const length = try v.own(s, try h.expression(s.engine, updatesLengthBody, .{result}));
    return v.duplicate(s, try h.binary(s, .greater, length, v.number(s, 0)));
}
fn saveBody(s: *Scope, trust_store: c.JSValue, result: c.JSValue) !void {
    if (!h.truthy(s.engine, try h.expression(s.engine, hasUpdatesBody, .{result}))) return;
    const method = try v.get(s, trust_store, "setMany");
    _ = try v.call(s, method, trust_store, &.{try v.get(s, result, "updates")});
}
fn saveCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    try h.statement(engine, saveBody, .{ v.arg(args, 0), v.arg(args, 1) });
    return c.pi_js_undefined();
}
fn overridePresentBody(s: *Scope, options: c.JSValue) !c.JSValue {
    return v.boolean(s, !c.JS_IsUndefined(try v.get(s, options, "trustOverride")));
}
fn resourcesBody(s: *Scope, options: c.JSValue, has_resources: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.call(s, has_resources, c.pi_js_undefined(),
        &.{try v.get(s, options, "cwd")})));
}
fn extensionsPresentBody(s: *Scope, options: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.get(s, options, "extensionsResult")));
}
fn emitBody(s: *Scope, options: c.JSValue, emitter: c.JSValue) !c.JSValue {
    const extensions = try v.get(s, options, "extensionsResult");
    const event = try v.object(s);
    try v.put(s, event, "type", try v.text(s, "project_trust"));
    try v.put(s, event, "cwd", try v.get(s, options, "cwd"));
    const context = try v.get(s, options, "projectTrustContext");
    return v.duplicate(s, try v.call(s, emitter, c.pi_js_undefined(), &.{extensions, event, context}));
}
fn bindEventBody(s: *Scope, frame: *ResolveFrame, input: c.JSValue) !void {
    const object = try v.guest.toObject(s, input);
    try frame.take(.result, h.get(s.engine, object, "result"));
    try frame.take(.errors, h.get(s.engine, object, "errors"));
}
fn fieldString(s: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, try v.get(s, object, name)));
}
fn errorTextBody(s: *Scope, error_item: c.JSValue) !c.JSValue {
    const path = try v.own(s, try h.expression(s.engine, fieldString, .{error_item, @as([*:0]const u8, "extensionPath")}));
    const first = try h.binary(s, .add, try v.text(s, "Extension \""), path);
    const second = try h.binary(s, .add, first, try v.text(s, "\" project_trust error: "));
    const message = try v.own(s, try h.expression(s.engine, fieldString, .{error_item, @as([*:0]const u8, "error")}));
    return v.duplicate(s, try h.binary(s, .add, second, message));
}
fn reportBody(s: *Scope, options: c.JSValue, error_item: c.JSValue) !void {
    const callback = try v.get(s, options, "onExtensionError");
    if (v.nullish(callback)) return;
    const message = try v.own(s, try h.expression(s.engine, errorTextBody, .{error_item}));
    _ = try v.call(s, callback, options, &.{message});
}

fn iteratorCallBody(s: *Scope, iterable: c.JSValue) !c.JSValue {
    const method = try v.key(s, iterable, try v.iteratorSymbol(s));
    if (!c.JS_IsFunction(s.engine.context, method)) return v.typeError(s, "value is not iterable");
    return v.duplicate(s, try v.call(s, method, iterable, &.{}));
}
fn iteratorObjectBody(s: *Scope, incoming: c.JSValue) !c.JSValue {
    const iterable = try v.own(s, incoming);
    const receiver = try v.own(s, try h.expression(s.engine, iteratorCallBody, .{iterable}));
    if (!c.JS_IsObject(receiver)) return v.typeError(s, "not an object");
    return v.duplicate(s, receiver);
}
fn hiddenBoolean(frame: *ResolveFrame, value: bool) void {
    const position = @intFromEnum(ResolveLocal.iterator_active);
    frame.values[position] = c.JS_NewBool(frame.engine.context, value);
    frame.ready[position] = true; // Internal flag, always primitive.
}
fn setStage(frame: *ResolveFrame, value: i32) void {
    const position = @intFromEnum(ResolveLocal.stage);
    frame.values[position] = c.JS_NewInt32(frame.engine.context, value);
    frame.ready[position] = true; // Internal resume label, always primitive.
}
fn retireOperand(frame: *ResolveFrame, comptime name: ResolveLocal, selected: *v.owned.Completion) void {
    const position = @intFromEnum(name);
    const previous = frame.values[position];
    frame.values[position] = c.pi_js_undefined();
    frame.ready[position] = true;
    selected.release(previous);
}
fn iteratorDoneBody(s: *Scope, result: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.get(s, result, "done")));
}
fn iteratorNextBody(s: *Scope, frame: *ResolveFrame, done: *bool) !c.JSValue {
    const result = try v.call(s, frame.get(.iterator_next), frame.get(.iterator_receiver), &.{});
    if (!c.JS_IsObject(result)) return v.typeError(s, "iterator must return an object");
    done.* = h.truthy(s.engine, try h.expression(s.engine, iteratorDoneBody, .{result}));
    return if (done.*) c.pi_js_undefined() else v.duplicate(s, try v.get(s, result, "value"));
}
fn nextError(frame: *ResolveFrame, steps: *usize) !?c.JSValue {
    try v.poll(frame.engine, steps);
    var done = false;
    const result = h.expression(frame.engine, iteratorNextBody, .{ frame, &done }) catch |err| {
        hiddenBoolean(frame, false);
        // The failing iterator drops its receiver before the enclosing unwind,
        // without invoking its own return method.
        var selected = v.owned.Completion.initVoid(frame.engine, err);
        retireOperand(frame, .iterator_receiver, &selected);
        try selected.finishVoid();
        unreachable;
    };
    if (!done) return result;
    hiddenBoolean(frame, false);
    var selected = v.owned.Completion.initValue(frame.engine, result);
    retireOperand(frame, .iterator_receiver, &selected);
    frame.engine.freeValue(try selected.finishValue()); // primitive undefined
    return null;
}
fn closeErrorBody(s: *Scope, receiver: c.JSValue, incoming: c.JSValue) !af.Action {
    const original = try v.own(s, incoming);
    closeErrorCall(s, receiver) catch |err| { _ = try v.own(s, try caught(s.engine, err)); };
    return .{ .thrown = v.duplicate(s, original) };
}
fn closeErrorCall(s: *Scope, receiver: c.JSValue) !void {
    const method = try v.get(s, receiver, "return");
    if (v.nullish(method)) return;
    _ = try v.call(s, method, receiver, &.{});
    // Throw completion ignores a primitive return; the original throw wins.
}
fn failErrorLoop(frame: *ResolveFrame, err: anyerror) !void {
    // A real fatal or termination bypasses guest IteratorClose and leaves
    // the operand roots for the actual argument/local terminal owner.
    const reason = try caught(frame.engine, err);
    const active = h.truthy(frame.engine, frame.get(.iterator_active));
    hiddenBoolean(frame, false);
    var drop_next = v.owned.Completion.initAction(frame.engine, .{ .thrown = reason });
    retireOperand(frame, .iterator_next, &drop_next);
    const original = switch (try drop_next.finishAction()) {
        .thrown => |value| value, .returned, .awaited => unreachable,
    };
    const action: af.Action = if (active) block: {
        var scope: Scope = .{ .engine = frame.engine };
        break :block try v.owned.finishAction(&scope,
            closeErrorBody(&scope, frame.get(.iterator_receiver), original));
    } else .{ .thrown = original };
    var drop_receiver = v.owned.Completion.initAction(frame.engine, action);
    retireOperand(frame, .iterator_receiver, &drop_receiver);
    return drop_receiver.finishVoid();
}
fn runErrorLoop(frame: *ResolveFrame, options: c.JSValue) !void {
    try frame.take(.iterator_receiver, h.expression(frame.engine, iteratorObjectBody,
        .{h.duplicate(frame.engine, frame.get(.errors))}));
    try frame.take(.iterator_next, h.get(frame.engine, frame.get(.iterator_receiver), "next"));
    hiddenBoolean(frame, true);
    var steps: usize = 0;
    while (try nextError(frame, &steps)) |value| {
        // The uncaptured const head persists until the next actual assignment.
        try frame.take(.error_item, value);
        try h.statement(frame.engine, reportBody, .{ options, frame.get(.error_item) });
    }
    try frame.take(.iterator_next, c.pi_js_undefined());
}
fn reportErrors(frame: *ResolveFrame, options: c.JSValue) !void {
    return runErrorLoop(frame, options) catch |err| failErrorLoop(frame, err);
}
fn rememberBody(s: *Scope, result: c.JSValue) !c.JSValue {
    return v.boolean(s, v.equal(s, try v.get(s, result, "remember"), v.boolean(s, true)));
}
fn rememberDecisionBody(s: *Scope, options: c.JSValue, trusted: c.JSValue) !void {
    const store = try v.get(s, options, "trustStore");
    const method = try v.get(s, store, "set");
    _ = try v.call(s, method, store, &.{ try v.get(s, options, "cwd"), trusted });
}
fn readDecisionBody(s: *Scope, options: c.JSValue) !c.JSValue {
    const store = try v.get(s, options, "trustStore");
    const method = try v.get(s, store, "get");
    return v.duplicate(s, try v.call(s, method, store, &.{try v.get(s, options, "cwd")}));
}
fn policyBody(s: *Scope, options: c.JSValue, defaults: c.JSValue) !c.JSValue {
    const supplied = try v.get(s, options, "defaultProjectTrust");
    const policy = if (v.nullish(supplied)) try v.get(s, defaults, "defaultProjectTrust") else supplied;
    // The Source switch performs strict comparisons, with no coercion or
    // unrequested default case. Unknown values fall through to the UI branch.
    return v.number(s, if (try v.eq(s, policy, "always")) 1 else if (try v.eq(s, policy, "never")) 2 else 0);
}
fn hasUiBody(s: *Scope, options: c.JSValue) !c.JSValue {
    const context = try v.get(s, options, "projectTrustContext");
    return v.boolean(s, v.truthy(s, try v.get(s, context, "hasUI")));
}
fn selectFromOptionsBody(s: *Scope, options: c.JSValue, select_option: c.JSValue) !c.JSValue {
    const cwd = try v.get(s, options, "cwd");
    const context = try v.get(s, options, "projectTrustContext");
    return v.duplicate(s, try v.call(s, select_option, c.pi_js_undefined(), &.{cwd, context}));
}
fn saveFromOptionsBody(s: *Scope, options: c.JSValue, selected: c.JSValue, save_result: c.JSValue) !void {
    _ = try v.call(s, save_result, c.pi_js_undefined(), &.{try v.get(s, options, "trustStore"), selected});
}
fn afterExtension(frame: *ResolveFrame, options: c.JSValue) !?af.Action {
    try reportErrors(frame, options);
    if (!h.truthy(frame.engine, frame.get(.result))) return null;
    try frame.take(.trusted, h.expression(frame.engine, trustedBody, .{frame.get(.result)}));
    if (h.truthy(frame.engine, try h.expression(frame.engine, rememberBody, .{frame.get(.result)})))
        try h.statement(frame.engine, rememberDecisionBody, .{ options, frame.get(.trusted) });
    return .{ .returned = h.duplicate(frame.engine, frame.get(.trusted)) };
}
fn trustedBody(s: *Scope, result: c.JSValue) !c.JSValue {
    return v.boolean(s, try v.eq(s, try v.get(s, result, "trusted"), "yes"));
}
fn afterSelection(frame: *ResolveFrame, options: c.JSValue, roots: []const c.JSValue) !af.Action {
    if (c.JS_IsUndefined(frame.get(.selected)))
        return .{ .returned = c.JS_NewBool(frame.engine.context, false) };
    try h.statement(frame.engine, saveFromOptionsBody,
        .{ options, frame.get(.selected), root(roots, .save_result) });
    return .{ .returned = try h.get(frame.engine, frame.get(.selected), "trusted") };
}
fn afterPolicy(frame: *ResolveFrame, options: c.JSValue, roots: []const c.JSValue) !af.Action {
    try frame.take(.decision, h.expression(frame.engine, readDecisionBody, .{options}));
    if (!c.JS_IsNull(frame.get(.decision)))
        return .{ .returned = h.duplicate(frame.engine, frame.get(.decision)) };
    const policy = try h.expression(frame.engine, policyBody, .{ options, root(roots, .defaults) });
    if (c.JS_IsStrictEqual(frame.engine.context, policy, c.JS_NewInt32(frame.engine.context, 1)))
        return .{ .returned = c.JS_NewBool(frame.engine.context, true) };
    if (c.JS_IsStrictEqual(frame.engine.context, policy, c.JS_NewInt32(frame.engine.context, 2)))
        return .{ .returned = c.JS_NewBool(frame.engine.context, false) };
    if (!h.truthy(frame.engine, try h.expression(frame.engine, hasUiBody, .{options})))
        return .{ .returned = c.JS_NewBool(frame.engine.context, false) };
    setStage(frame, 2);
    return .{ .awaited = try h.expression(frame.engine, selectFromOptionsBody,
        .{ options, root(roots, .select_option) }) };
}
fn resolveAdvance(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue,
    completion: af.Completion, input: c.JSValue) !af.Action
{
    const options = v.arg(args, 0);
    if (completion == .start) {
        const frame = try ResolveFrame.createAsync(s);
        af.replaceState(s.engine, state, v.duplicate(s, frame.owner));
        if (h.truthy(s.engine, try h.expression(s.engine, overridePresentBody, .{options})))
            return .{ .returned = try h.get(s.engine, options, "trustOverride") };
        if (!h.truthy(s.engine, try h.expression(s.engine, resourcesBody, .{ options, root(roots, .has_resources) })))
            return .{ .returned = c.JS_NewBool(s.engine.context, true) };
        if (h.truthy(s.engine, try h.expression(s.engine, extensionsPresentBody, .{options}))) {
            setStage(frame, 1);
            return .{ .awaited = try h.expression(s.engine, emitBody, .{ options, root(roots, .emit_event) }) };
        }
        return afterPolicy(frame, options, roots);
    }
    if (completion == .rejected) return .{ .thrown = v.duplicate(s, input) };
    const frame = ResolveFrame.from(state.*);
    if (c.JS_IsStrictEqual(s.engine.context, frame.get(.stage), c.JS_NewInt32(s.engine.context, 1))) {
        try h.statement(s.engine, bindEventBody, .{ frame, input });
        if (try afterExtension(frame, options)) |action| return action;
        return afterPolicy(frame, options, roots);
    }
    try frame.copy(.selected, input);
    return afterSelection(frame, options, roots);
}
fn resolveBody(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue,
    state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action
{
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    var s: Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, resolveAdvance(&s, args, roots, state, completion, input));
}
