//! The complete c268 runRpcMode command switch. All replies and host/session
//! calls use the actual captured bindings; Await is owned by QuickJS.
const h = @import("native_public_rpc_state.zig");
const v = h.v;
const c = h.c;
const Engine = h.Engine;
const Scope = h.Scope;
const af = h.af;
const Main = h.Frame;
// Captures: session, runtimeHost, rebindSession, success, error, output.
const Frame = h.lexical.Frame(enum {
    command, id, preflight_succeeded, steer_disposition, followup_disposition,
    new_options, new_result, state, models, model, cycle_result, available_models,
    level, levels, compact_result, event_result, bash_result, stats, path,
    switch_result, fork_result, leaf_id, clone_result, messages,
    entry_manager, entries, since_index, tree_manager, text, name,
    commands, extension_command, template, skill, unknown_command,
    native_kind, native_phase,
});
const Kind = enum(i32) {
    prompt, steer, follow_up, abort, clear_queue, new_session, get_state,
    set_model, cycle_model, get_available_models, set_thinking_level,
    cycle_thinking_level, get_available_thinking_levels, set_steering_mode,
    set_follow_up_mode, compact, set_auto_compaction, set_auto_retry,
    abort_retry, bash, abort_bash, get_session_stats, export_html, switch_session,
    fork, clone, get_fork_messages, get_entries, get_tree, get_last_assistant_text,
    set_session_name, get_messages, get_commands, unknown,
};
pub fn create(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    return h.asyncArrow(s, "handleCommand", 1, call, roots);
}
fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine };
    const outcome = v.owned.finishAction(&s, advance(&s, args, roots, state, completion, input));
    if (outcome) |action| { if (action == .awaited) return action; } else |_| {}
    var selected = v.owned.Completion.initAction(engine, outcome);
    if (!c.JS_IsUndefined(state.*)) Frame.from(state.*).close(&selected);
    return selected.finishAction();
}
fn advance(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) {
        try h.enterRejected(s.engine);
        return .{ .thrown = v.duplicate(s, input) };
    }
    if (completion == .start) {
        const f = try Frame.create(s);
        af.replaceState(s.engine, state, v.duplicate(s, f.owner));
        try f.copy(.command, v.arg(args, 0));
        try f.take(.id, h.fieldOwned(s.engine, f.get(.command), "id"));
        const selected = try h.expression(s.engine, selectKind, .{f.get(.command)});
        try f.take(.native_kind, selected);
        try f.take(.native_phase, c.JS_NewInt32(s.engine.context, 0));
        return start(f, roots);
    }
    return resumeCommand(Frame.from(state.*), roots, input);
}
fn selectedKind(f: *Frame) Kind {
    var tag: i32 = 0; _ = c.JS_ToInt32(f.engine.context, &tag, f.get(.native_kind));
    return @enumFromInt(tag);
}
fn phase(f: *Frame) i32 {
    var tag: i32 = 0; _ = c.JS_ToInt32(f.engine.context, &tag, f.get(.native_phase));
    return tag;
}
fn setPhase(f: *Frame, value: i32) !void { try f.take(.native_phase, c.JS_NewInt32(f.engine.context, value)); }
fn selectKind(s: *Scope, command: c.JSValue) !c.JSValue {
    const value = try h.fieldValue(s, command, "type");
    inline for (@typeInfo(Kind).@"enum".fields) |entry| {
        if (comptime !@import("std").mem.eql(u8, entry.name, "unknown"))
            if (try v.eq(s, value, entry.name)) return c.JS_NewInt32(s.engine.context, entry.value);
    }
    return c.JS_NewInt32(s.engine.context, @intFromEnum(Kind.unknown));
}
fn returned(f: *Frame, roots: []const c.JSValue, comptime kind: Kind, data: c.JSValue, present: bool) !af.Action {
    return .{ .returned = try h.expression(f.engine, reply, .{ f, roots, kind, data, present }) };
}
fn reply(s: *Scope, f: *Frame, roots: []const c.JSValue, comptime kind: Kind, data: c.JSValue, present: bool) !c.JSValue {
    const callable = try Main.read(s, roots[3]);
    const name = try v.text(s, @tagName(kind));
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(),
        if (present) &.{ f.get(.id), name, data } else &.{ f.get(.id), name }));
}
fn literalFailure(s: *Scope, f: *Frame, roots: []const c.JSValue, comptime kind: Kind, message: []const u8) !c.JSValue {
    const callable = try Main.read(s, roots[4]);
    const name = try v.text(s, @tagName(kind));
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{ f.get(.id), name, try v.text(s, message) }));
}
fn wrappedReply(s: *Scope, f: *Frame, roots: []const c.JSValue, comptime kind: Kind, property: [*:0]const u8, data: c.JSValue) !c.JSValue {
    const callable = try Main.read(s, roots[3]); const name = try v.text(s, @tagName(kind));
    const record = try v.object(s); try v.put(s, record, property, data);
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{ f.get(.id), name, record }));
}
fn wrapped(f: *Frame, roots: []const c.JSValue, comptime kind: Kind, property: [*:0]const u8, data: c.JSValue) !af.Action {
    return .{ .returned = try h.expression(f.engine, wrappedReply, .{ f, roots, kind, property, data }) };
}
fn sessionField(s: *Scope, roots: []const c.JSValue, name: [*:0]const u8) !c.JSValue { return h.bindingField(s, roots[0], name); }
fn sessionMethod(s: *Scope, roots: []const c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return h.bindingMethod(s, roots[0], name, args);
}
fn sessionCommandMethod(s: *Scope, f: *Frame, roots: []const c.JSValue, name: [*:0]const u8, property: [*:0]const u8) !c.JSValue {
    const receiver = try Main.read(s, roots[0]); const callable = try v.get(s, receiver, name);
    const arg = try h.fieldValue(s, f.get(.command), property);
    return v.duplicate(s, try v.call(s, callable, receiver, &.{arg}));
}
fn hostCommandMethod(s: *Scope, f: *Frame, roots: []const c.JSValue, name: [*:0]const u8, property: [*:0]const u8) !c.JSValue {
    const receiver = try Main.read(s, roots[1]); const callable = try v.get(s, receiver, name);
    const arg = try h.fieldValue(s, f.get(.command), property);
    return v.duplicate(s, try v.call(s, callable, receiver, &.{arg}));
}
fn discardSession(s: *Scope, roots: []const c.JSValue, name: [*:0]const u8) !void { _ = try v.own(s, try h.expression(s.engine, sessionMethod, .{ roots, name, @as([]const c.JSValue, &.{}) })); }
fn discardSessionCommand(s: *Scope, f: *Frame, roots: []const c.JSValue, name: [*:0]const u8, property: [*:0]const u8) !void {
    _ = try v.own(s, try h.expression(s.engine, sessionCommandMethod, .{ f, roots, name, property }));
}
fn managerMethod(s: *Scope, roots: []const c.JSValue, name: [*:0]const u8) !c.JSValue {
    const manager = try v.own(s, try h.expression(s.engine, sessionField, .{ roots, @as([*:0]const u8, "sessionManager") }));
    const method = try v.get(s, manager, name);
    return v.duplicate(s, try v.call(s, method, manager, &.{}));
}
fn modelSnapshot(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const runtime = try v.own(s, try h.expression(s.engine, sessionField, .{ roots, @as([*:0]const u8, "modelRuntime") }));
    const method = try v.get(s, runtime, "getAvailableSnapshot");
    return v.duplicate(s, try v.call(s, method, runtime, &.{}));
}
fn start(f: *Frame, roots: []const c.JSValue) !af.Action {
    switch (selectedKind(f)) {
        .prompt => {
            try f.take(.preflight_succeeded, c.JS_NewBool(f.engine.context, false));
            try h.statement(f.engine, prompt, .{ f, roots });
            return .{ .returned = c.pi_js_undefined() };
        },
        .steer => return .{ .awaited = try h.expression(f.engine, queuePrompt, .{ f, roots, @as([*:0]const u8, "steer") }) },
        .follow_up => return .{ .awaited = try h.expression(f.engine, queuePrompt, .{ f, roots, @as([*:0]const u8, "followUp") }) },
        .abort => return .{ .awaited = try h.expression(f.engine, sessionMethod, .{ roots, @as([*:0]const u8, "abort"), @as([]const c.JSValue, &.{}) }) },
        .clear_queue => return .{ .returned = try h.expression(f.engine, clearQueueReply, .{ f, roots }) },
        .new_session => {
            try f.take(.new_options, h.expression(f.engine, newOptions, .{f}));
            return .{ .awaited = try h.expression(f.engine, h.bindingMethod, .{ roots[1], @as([*:0]const u8, "newSession"), @as([]const c.JSValue, &.{f.get(.new_options)}) }) };
        },
        .get_state => { try f.take(.state, h.expression(f.engine, stateRecord, .{roots})); return returned(f, roots, .get_state, f.get(.state), true); },
        .set_model => {
            try f.take(.models, h.expression(f.engine, modelSnapshot, .{roots}));
            try f.take(.model, h.expression(f.engine, findModel, .{f}));
            if (!h.truthy(f.engine, f.get(.model))) return .{ .returned = try h.expression(f.engine, modelMissing, .{ f, roots }) };
            return .{ .awaited = try h.expression(f.engine, sessionMethod, .{ roots, @as([*:0]const u8, "setModel"), @as([]const c.JSValue, &.{f.get(.model)}) }) };
        },
        .cycle_model => return .{ .awaited = try h.expression(f.engine, sessionMethod, .{ roots, @as([*:0]const u8, "cycleModel"), @as([]const c.JSValue, &.{}) }) },
        .get_available_models => { try f.take(.available_models, h.expression(f.engine, modelSnapshot, .{roots})); return wrapped(f, roots, .get_available_models, "models", f.get(.available_models)); },
        .set_thinking_level => { try h.statement(f.engine, discardSessionCommand, .{ f, roots, @as([*:0]const u8, "setThinkingLevel"), @as([*:0]const u8, "level") }); return returned(f, roots, .set_thinking_level, c.pi_js_undefined(), false); },
        .cycle_thinking_level => {
            try f.take(.level, h.expression(f.engine, sessionMethod, .{ roots, @as([*:0]const u8, "cycleThinkingLevel"), @as([]const c.JSValue, &.{}) }));
            if (!h.truthy(f.engine, f.get(.level))) return returned(f, roots, .cycle_thinking_level, c.pi_js_null(), true);
            return wrapped(f, roots, .cycle_thinking_level, "level", f.get(.level));
        },
        .get_available_thinking_levels => {
            try f.take(.levels, h.expression(f.engine, sessionMethod, .{ roots, @as([*:0]const u8, "getAvailableThinkingLevels"), @as([]const c.JSValue, &.{}) }));
            return wrapped(f, roots, .get_available_thinking_levels, "levels", f.get(.levels));
        },
        .set_steering_mode => { try h.statement(f.engine, discardSessionCommand, .{ f, roots, @as([*:0]const u8, "setSteeringMode"), @as([*:0]const u8, "mode") }); return returned(f, roots, .set_steering_mode, c.pi_js_undefined(), false); },
        .set_follow_up_mode => { try h.statement(f.engine, discardSessionCommand, .{ f, roots, @as([*:0]const u8, "setFollowUpMode"), @as([*:0]const u8, "mode") }); return returned(f, roots, .set_follow_up_mode, c.pi_js_undefined(), false); },
        .compact => return .{ .awaited = try h.expression(f.engine, sessionCommandMethod, .{ f, roots, @as([*:0]const u8, "compact"), @as([*:0]const u8, "customInstructions") }) },
        .set_auto_compaction => { try h.statement(f.engine, discardSessionCommand, .{ f, roots, @as([*:0]const u8, "setAutoCompactionEnabled"), @as([*:0]const u8, "enabled") }); return returned(f, roots, .set_auto_compaction, c.pi_js_undefined(), false); },
        .set_auto_retry => { try h.statement(f.engine, discardSessionCommand, .{ f, roots, @as([*:0]const u8, "setAutoRetryEnabled"), @as([*:0]const u8, "enabled") }); return returned(f, roots, .set_auto_retry, c.pi_js_undefined(), false); },
        .abort_retry => { try h.statement(f.engine, discardSession, .{ roots, @as([*:0]const u8, "abortRetry") }); return returned(f, roots, .abort_retry, c.pi_js_undefined(), false); },
        .bash => return .{ .awaited = try h.expression(f.engine, emitBash, .{ f, roots }) },
        .abort_bash => { try h.statement(f.engine, discardSession, .{ roots, @as([*:0]const u8, "abortBash") }); return returned(f, roots, .abort_bash, c.pi_js_undefined(), false); },
        .get_session_stats => { try f.take(.stats, h.expression(f.engine, sessionMethod, .{ roots, @as([*:0]const u8, "getSessionStats"), @as([]const c.JSValue, &.{}) })); return returned(f, roots, .get_session_stats, f.get(.stats), true); },
        .export_html => return .{ .awaited = try h.expression(f.engine, sessionCommandMethod, .{ f, roots, @as([*:0]const u8, "exportToHtml"), @as([*:0]const u8, "outputPath") }) },
        .switch_session => return .{ .awaited = try h.expression(f.engine, hostCommandMethod, .{ f, roots, @as([*:0]const u8, "switchSession"), @as([*:0]const u8, "sessionPath") }) },
        .fork => return .{ .awaited = try h.expression(f.engine, hostCommandMethod, .{ f, roots, @as([*:0]const u8, "fork"), @as([*:0]const u8, "entryId") }) },
        .clone => {
            try f.take(.leaf_id, h.expression(f.engine, managerMethod, .{ roots, @as([*:0]const u8, "getLeafId") }));
            if (!h.truthy(f.engine, f.get(.leaf_id))) return .{ .returned = try h.expression(f.engine, literalFailure, .{ f, roots, Kind.clone, @as([]const u8, "Cannot clone session: no current entry selected") }) };
            return .{ .awaited = try h.expression(f.engine, cloneSession, .{ f, roots }) };
        },
        .get_fork_messages => { try f.take(.messages, h.expression(f.engine, sessionMethod, .{ roots, @as([*:0]const u8, "getUserMessagesForForking"), @as([]const c.JSValue, &.{}) })); return wrapped(f, roots, .get_fork_messages, "messages", f.get(.messages)); },
        .get_entries => return entriesReply(f, roots),
        .get_tree => { try f.take(.tree_manager, h.expression(f.engine, sessionField, .{ roots, @as([*:0]const u8, "sessionManager") })); return .{ .returned = try h.expression(f.engine, treeReply, .{ f, roots }) }; },
        .get_last_assistant_text => { try f.take(.text, h.expression(f.engine, sessionMethod, .{ roots, @as([*:0]const u8, "getLastAssistantText"), @as([]const c.JSValue, &.{}) })); return wrapped(f, roots, .get_last_assistant_text, "text", f.get(.text)); },
        .set_session_name => {
            try f.take(.name, h.expression(f.engine, sessionName, .{f}));
            if (!h.truthy(f.engine, f.get(.name))) return .{ .returned = try h.expression(f.engine, literalFailure, .{ f, roots, Kind.set_session_name, @as([]const u8, "Session name cannot be empty") }) };
            try h.statement(f.engine, setSessionName, .{ f, roots }); return returned(f, roots, .set_session_name, c.pi_js_undefined(), false);
        },
        .get_messages => return .{ .returned = try h.expression(f.engine, messagesReply, .{ f, roots }) },
        .get_commands => {
            try f.take(.commands, h.expression(f.engine, h.emptyArray, .{}));
            try commandRows(f, roots);
            return wrapped(f, roots, .get_commands, "commands", f.get(.commands));
        },
        .unknown => { try f.copy(.unknown_command, f.get(.command)); return .{ .returned = try h.expression(f.engine, unknownReply, .{ f, roots }) }; },
    }
}
fn resumeCommand(f: *Frame, roots: []const c.JSValue, input: c.JSValue) !af.Action {
    switch (selectedKind(f)) {
        .steer => { try f.copy(.steer_disposition, input); return wrapped(f, roots, .steer, "disposition", f.get(.steer_disposition)); },
        .follow_up => { try f.copy(.followup_disposition, input); return wrapped(f, roots, .follow_up, "disposition", f.get(.followup_disposition)); },
        .abort => return returned(f, roots, .abort, c.pi_js_undefined(), false),
        .set_model => return returned(f, roots, .set_model, f.get(.model), true),
        .cycle_model => { try f.copy(.cycle_result, input); return returned(f, roots, .cycle_model, if (h.truthy(f.engine, f.get(.cycle_result))) f.get(.cycle_result) else c.pi_js_null(), true); },
        .compact => { try f.copy(.compact_result, input); return returned(f, roots, .compact, f.get(.compact_result), true); },
        .export_html => { try f.copy(.path, input); return wrapped(f, roots, .export_html, "path", f.get(.path)); },
        .new_session, .switch_session, .fork, .clone => {
            if (phase(f) == 0) {
                switch (selectedKind(f)) {
                    .new_session => try f.copy(.new_result, input),
                    .switch_session => try f.copy(.switch_result, input),
                    .fork => try f.copy(.fork_result, input),
                    .clone => try f.copy(.clone_result, input),
                    else => unreachable,
                }
                if (!try h.fieldTruthy(f.engine, sessionResult(f), "cancelled")) {
                    try setPhase(f, 1);
                    return .{ .awaited = try h.expression(f.engine, h.bindingCall, .{ roots[2], @as([]const c.JSValue, &.{}) }) };
                }
            }
            return switch (selectedKind(f)) {
                .new_session => returned(f, roots, .new_session, f.get(.new_result), true),
                .switch_session => returned(f, roots, .switch_session, f.get(.switch_result), true),
                .fork => .{ .returned = try h.expression(f.engine, forkReply, .{ f, roots, false }) },
                .clone => .{ .returned = try h.expression(f.engine, forkReply, .{ f, roots, true }) },
                else => unreachable,
            };
        },
        .bash => {
            if (phase(f) == 0) {
                try f.copy(.event_result, input);
                if (try optionalResultTruthy(f)) {
                    try h.statement(f.engine, recordBash, .{ f, roots });
                    return .{ .returned = try h.expression(f.engine, eventBashReply, .{ f, roots }) };
                }
                try setPhase(f, 1);
                return .{ .awaited = try h.expression(f.engine, executeBash, .{ f, roots }) };
            }
            try f.copy(.bash_result, input);
            return returned(f, roots, .bash, f.get(.bash_result), true);
        },
        else => return error.RpcCommandInvalidAwaitStage,
    }
}
fn sessionResult(f: *Frame) c.JSValue { return switch (selectedKind(f)) { .new_session => f.get(.new_result), .switch_session => f.get(.switch_result), .fork => f.get(.fork_result), .clone => f.get(.clone_result), else => unreachable }; }
fn newOptions(s: *Scope, f: *Frame) !c.JSValue {
    if (!try h.fieldTruthy(s.engine, f.get(.command), "parentSession")) return c.pi_js_undefined();
    const result = try v.object(s); try v.put(s, result, "parentSession", try h.fieldValue(s, f.get(.command), "parentSession")); return v.duplicate(s, result);
}
fn clearQueueReply(s: *Scope, f: *Frame, roots: []const c.JSValue) !c.JSValue {
    const callable = try Main.read(s, roots[3]); const name = try v.text(s, "clear_queue");
    const data = try v.own(s, try h.expression(s.engine, sessionMethod, .{ roots, @as([*:0]const u8, "clearQueue"), @as([]const c.JSValue, &.{}) }));
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{ f.get(.id), name, data }));
}
fn stateRecord(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const result = try v.object(s);
    inline for (.{ "model", "thinkingLevel", "isStreaming", "isCompacting", "steeringMode", "followUpMode", "sessionFile", "sessionId", "sessionName", "autoCompactionEnabled" }) |name|
        try v.put(s, result, name, try v.own(s, try h.expression(s.engine, sessionField, .{ roots, @as([*:0]const u8, name) })));
    try v.put(s, result, "messageCount", try v.own(s, try h.expression(s.engine, messagesLength, .{roots})));
    try v.put(s, result, "pendingMessageCount", try v.own(s, try h.expression(s.engine, sessionField, .{ roots, @as([*:0]const u8, "pendingMessageCount") })));
    return v.duplicate(s, result);
}
fn messagesLength(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const messages = try v.own(s, try h.expression(s.engine, sessionField, .{ roots, @as([*:0]const u8, "messages") }));
    return v.duplicate(s, try v.get(s, messages, "length"));
}
fn queuePrompt(s: *Scope, f: *Frame, roots: []const c.JSValue, name: [*:0]const u8) !c.JSValue {
    const session = try Main.read(s, roots[0]); const callable = try v.get(s, session, name);
    const message = try h.fieldValue(s, f.get(.command), "message"); const images = try h.fieldValue(s, f.get(.command), "images");
    const options = try v.object(s); try v.put(s, options, "source", try v.text(s, "rpc"));
    return v.duplicate(s, try v.call(s, callable, session, &.{ message, images, options }));
}
fn prompt(s: *Scope, f: *Frame, roots: []const c.JSValue) !void {
    const promise = try v.own(s, try h.expression(s.engine, promptCall, .{ f, roots }));
    const method = try v.get(s, promise, "catch");
    const callback = try v.arrow(s, "", 1, promptError, &.{ try f.capture(s, .preflight_succeeded, "preflightSucceeded"), roots[5], roots[4], try f.capture(s, .id, "id") });
    _ = try v.call(s, method, promise, &.{callback});
}
fn promptCall(s: *Scope, f: *Frame, roots: []const c.JSValue) !c.JSValue {
    const session = try Main.read(s, roots[0]); const callable = try v.get(s, session, "prompt");
    const message = try h.fieldValue(s, f.get(.command), "message");
    const options = try v.object(s);
    try v.put(s, options, "images", try h.fieldValue(s, f.get(.command), "images"));
    try v.put(s, options, "streamingBehavior", try h.fieldValue(s, f.get(.command), "streamingBehavior"));
    try v.put(s, options, "source", try v.text(s, "rpc"));
    try v.put(s, options, "preflightResult", try v.arrow(s, "preflightResult", 1, preflight, &.{ try f.capture(s, .preflight_succeeded, "preflightSucceeded"), roots[5], roots[3], try f.capture(s, .id, "id") }));
    return v.duplicate(s, try v.call(s, callable, session, &.{ message, options }));
}
fn preflight(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try Frame.assign(roots[0], c.JS_NewBool(engine.context, true));
    return h.expression(engine, preflightBody, .{ roots, v.arg(args, 0) });
}
fn preflightBody(s: *Scope, roots: []const c.JSValue, disposition: c.JSValue) !c.JSValue {
    const output = try Main.read(s, roots[1]);
    const response = try v.own(s, try h.expression(s.engine, preflightReply, .{ roots, disposition }));
    _ = try v.call(s, output, c.pi_js_undefined(), &.{response}); return c.pi_js_undefined();
}
fn preflightReply(s: *Scope, roots: []const c.JSValue, disposition: c.JSValue) !c.JSValue {
    const success = try Main.read(s, roots[2]); const id = try Frame.read(s, roots[3]); const name = try v.text(s, "prompt");
    const data = try v.object(s); try v.put(s, data, "disposition", disposition);
    return v.duplicate(s, try v.call(s, success, c.pi_js_undefined(), &.{ id, name, data }));
}
fn promptError(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, promptErrorBody, .{ roots, v.arg(args, 0) });
}
fn promptErrorBody(s: *Scope, roots: []const c.JSValue, reason: c.JSValue) !c.JSValue {
    if (h.truthy(s.engine, try h.expression(s.engine, preflightTruthy, .{roots[0]}))) return c.pi_js_undefined();
    const output = try Main.read(s, roots[1]); const response = try v.own(s, try h.expression(s.engine, promptFailureReply, .{ roots, reason }));
    _ = try v.call(s, output, c.pi_js_undefined(), &.{response}); return c.pi_js_undefined();
}
fn preflightTruthy(s: *Scope, cell: c.JSValue) !c.JSValue { return v.boolean(s, v.truthy(s, try Frame.read(s, cell))); }
fn promptFailureReply(s: *Scope, roots: []const c.JSValue, reason: c.JSValue) !c.JSValue {
    const failure = try Main.read(s, roots[2]); const id = try Frame.read(s, roots[3]); const name = try v.text(s, "prompt");
    return v.duplicate(s, try v.call(s, failure, c.pi_js_undefined(), &.{ id, name, try h.fieldValue(s, reason, "message") }));
}
fn findModel(s: *Scope, f: *Frame) !c.JSValue {
    const models = try v.own(s, v.duplicate(s, f.get(.models))); const find = try v.get(s, models, "find");
    const predicate = try v.arrow(s, "", 1, modelMatches, &.{try f.capture(s, .command, "command")});
    return v.duplicate(s, try v.call(s, find, models, &.{predicate}));
}
fn modelMatches(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return h.expression(engine, modelMatchesBody, .{ v.arg(args, 0), roots[0] }); }
fn modelMatchesBody(s: *Scope, model: c.JSValue, command_cell: c.JSValue) !c.JSValue {
    if (!h.truthy(s.engine, try h.expression(s.engine, matchModelField, .{ model, command_cell, @as([*:0]const u8, "provider"), @as([*:0]const u8, "provider") }))) return v.boolean(s, false);
    return matchModelField(s, model, command_cell, "id", "modelId");
}
fn matchModelField(s: *Scope, model: c.JSValue, command_cell: c.JSValue, left: [*:0]const u8, right: [*:0]const u8) !c.JSValue {
    const a = try h.fieldValue(s, model, left);
    const b = try v.own(s, try h.expression(s.engine, commandCellField, .{ command_cell, right }));
    return v.boolean(s, v.equal(s, a, b));
}
fn commandCellField(s: *Scope, cell: c.JSValue, property: [*:0]const u8) !c.JSValue { return v.duplicate(s, try v.get(s, try Frame.read(s, cell), property)); }
fn stringField(s: *Scope, target: c.JSValue, name: [*:0]const u8) !c.JSValue { return v.duplicate(s, try v.stringify(s, try h.fieldValue(s, target, name))); }
fn modelMessage(s: *Scope, command: c.JSValue) !c.JSValue {
    const provider = try v.own(s, try h.expression(s.engine, stringField, .{ command, @as([*:0]const u8, "provider") }));
    const prefix = try v.binary(s, 0, try v.text(s, "Model not found: "), provider);
    const slash = try v.binary(s, 0, prefix, try v.text(s, "/"));
    const model = try v.own(s, try h.expression(s.engine, stringField, .{ command, @as([*:0]const u8, "modelId") }));
    return v.duplicate(s, try v.binary(s, 0, slash, model));
}
fn modelMissing(s: *Scope, f: *Frame, roots: []const c.JSValue) !c.JSValue {
    const callable = try Main.read(s, roots[4]); const name = try v.text(s, "set_model");
    const message = try v.own(s, try h.expression(s.engine, modelMessage, .{f.get(.command)}));
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{ f.get(.id), name, message }));
}
fn emitBash(s: *Scope, f: *Frame, roots: []const c.JSValue) !c.JSValue {
    const runner = try v.own(s, try h.expression(s.engine, sessionField, .{ roots, @as([*:0]const u8, "extensionRunner") }));
    const method = try v.get(s, runner, "emitUserBash"); const event = try v.object(s);
    try v.put(s, event, "type", try v.text(s, "user_bash"));
    try v.put(s, event, "command", try h.fieldValue(s, f.get(.command), "command"));
    const exclude = try h.fieldValue(s, f.get(.command), "excludeFromContext");
    try v.put(s, event, "excludeFromContext", if (v.nullish(exclude)) v.boolean(s, false) else exclude);
    try v.put(s, event, "cwd", try v.own(s, try h.expression(s.engine, managerMethod, .{ roots, @as([*:0]const u8, "getCwd") })));
    return v.duplicate(s, try v.call(s, method, runner, &.{event}));
}
fn optionalResultTruthy(f: *Frame) !bool { return h.truthy(f.engine, try h.expression(f.engine, optionalResultBody, .{f.get(.event_result)})); }
fn optionalResultBody(s: *Scope, result: c.JSValue) !c.JSValue { return v.boolean(s, v.truthy(s, try h.optionalField(s, result, "result"))); }
fn recordBash(s: *Scope, f: *Frame, roots: []const c.JSValue) !void {
    const session = try Main.read(s, roots[0]); const method = try v.get(s, session, "recordBashResult");
    const command = try h.fieldValue(s, f.get(.command), "command"); const result = try h.fieldValue(s, f.get(.event_result), "result");
    const options = try v.object(s); try v.put(s, options, "excludeFromContext", try h.fieldValue(s, f.get(.command), "excludeFromContext"));
    _ = try v.call(s, method, session, &.{ command, result, options });
}
fn eventBashReply(s: *Scope, f: *Frame, roots: []const c.JSValue) !c.JSValue {
    const success = try Main.read(s, roots[3]); const name = try v.text(s, "bash");
    return v.duplicate(s, try v.call(s, success, c.pi_js_undefined(), &.{ f.get(.id), name, try h.fieldValue(s, f.get(.event_result), "result") }));
}
fn executeBash(s: *Scope, f: *Frame, roots: []const c.JSValue) !c.JSValue {
    const session = try Main.read(s, roots[0]); const method = try v.get(s, session, "executeBash");
    const command = try h.fieldValue(s, f.get(.command), "command"); const options = try v.object(s);
    try v.put(s, options, "excludeFromContext", try h.fieldValue(s, f.get(.command), "excludeFromContext"));
    try v.put(s, options, "id", f.get(.id)); try v.put(s, options, "operations", try h.optionalField(s, f.get(.event_result), "operations"));
    return v.duplicate(s, try v.call(s, method, session, &.{ command, c.pi_js_undefined(), options }));
}
fn cloneSession(s: *Scope, f: *Frame, roots: []const c.JSValue) !c.JSValue {
    const host = try Main.read(s, roots[1]); const method = try v.get(s, host, "fork");
    const options = try v.object(s); try v.put(s, options, "position", try v.text(s, "at"));
    return v.duplicate(s, try v.call(s, method, host, &.{ f.get(.leaf_id), options }));
}
fn forkReply(s: *Scope, f: *Frame, roots: []const c.JSValue, clone: bool) !c.JSValue {
    const success = try Main.read(s, roots[3]); const name = try v.text(s, if (clone) "clone" else "fork"); const result = try v.object(s);
    if (!clone) try v.put(s, result, "text", try h.fieldValue(s, f.get(.fork_result), "selectedText"));
    try v.put(s, result, "cancelled", try h.fieldValue(s, if (clone) f.get(.clone_result) else f.get(.fork_result), "cancelled"));
    return v.duplicate(s, try v.call(s, success, c.pi_js_undefined(), &.{ f.get(.id), name, result }));
}
fn entriesReply(f: *Frame, roots: []const c.JSValue) !af.Action {
    try f.take(.entry_manager, h.expression(f.engine, sessionField, .{ roots, @as([*:0]const u8, "sessionManager") }));
    try f.take(.entries, v.invokeOwned(f.engine, f.get(.entry_manager), "getEntries", &.{}));
    if (h.truthy(f.engine, try h.expression(f.engine, hasSince, .{f}))) {
        try f.take(.since_index, h.expression(f.engine, findEntry, .{f}));
        if (c.JS_IsStrictEqual(f.engine.context, f.get(.since_index), c.JS_NewInt32(f.engine.context, -1)))
            return .{ .returned = try h.expression(f.engine, entryMissing, .{ f, roots }) };
        try f.take(.entries, h.expression(f.engine, entriesTail, .{f}));
    }
    return .{ .returned = try h.expression(f.engine, entriesRecord, .{ f, roots }) };
}
fn hasSince(s: *Scope, f: *Frame) !c.JSValue { return v.boolean(s, !c.JS_IsUndefined(try h.fieldValue(s, f.get(.command), "since"))); }
fn findEntry(s: *Scope, f: *Frame) !c.JSValue {
    const entries = try v.own(s, v.duplicate(s, f.get(.entries))); const method = try v.get(s, entries, "findIndex");
    const predicate = try v.arrow(s, "", 1, entryMatches, &.{try f.capture(s, .command, "command")});
    return v.duplicate(s, try v.call(s, method, entries, &.{predicate}));
}
fn entryMatches(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, matchModelField, .{ v.arg(args, 0), roots[0], @as([*:0]const u8, "id"), @as([*:0]const u8, "since") });
}
fn entryMissing(s: *Scope, f: *Frame, roots: []const c.JSValue) !c.JSValue {
    const failure = try Main.read(s, roots[4]); const name = try v.text(s, "get_entries");
    const message = try v.own(s, try h.expression(s.engine, entryMessage, .{f.get(.command)}));
    return v.duplicate(s, try v.call(s, failure, c.pi_js_undefined(), &.{ f.get(.id), name, message }));
}
fn entryMessage(s: *Scope, command: c.JSValue) !c.JSValue {
    const value = try v.own(s, try h.expression(s.engine, stringField, .{ command, @as([*:0]const u8, "since") }));
    return v.duplicate(s, try v.binary(s, 0, try v.text(s, "Entry not found: "), value));
}
fn entriesTail(s: *Scope, f: *Frame) !c.JSValue {
    const entries = try v.own(s, v.duplicate(s, f.get(.entries))); const method = try v.get(s, entries, "slice");
    const offset = try v.binary(s, 0, f.get(.since_index), v.number(s, 1));
    return v.duplicate(s, try v.call(s, method, entries, &.{offset}));
}
fn entriesRecord(s: *Scope, f: *Frame, roots: []const c.JSValue) !c.JSValue {
    const success = try Main.read(s, roots[3]); const name = try v.text(s, "get_entries"); const data = try v.object(s);
    try v.put(s, data, "entries", f.get(.entries)); try v.put(s, data, "leafId", try v.invoke(s, f.get(.entry_manager), "getLeafId", &.{}));
    return v.duplicate(s, try v.call(s, success, c.pi_js_undefined(), &.{ f.get(.id), name, data }));
}
fn treeReply(s: *Scope, f: *Frame, roots: []const c.JSValue) !c.JSValue {
    const success = try Main.read(s, roots[3]); const name = try v.text(s, "get_tree"); const data = try v.object(s);
    try v.put(s, data, "tree", try v.invoke(s, f.get(.tree_manager), "getTree", &.{}));
    try v.put(s, data, "leafId", try v.invoke(s, f.get(.tree_manager), "getLeafId", &.{}));
    return v.duplicate(s, try v.call(s, success, c.pi_js_undefined(), &.{ f.get(.id), name, data }));
}
fn sessionName(s: *Scope, f: *Frame) !c.JSValue {
    const name = try h.fieldValue(s, f.get(.command), "name"); const method = try v.get(s, name, "trim");
    return v.duplicate(s, try v.call(s, method, name, &.{}));
}
fn setSessionName(s: *Scope, f: *Frame, roots: []const c.JSValue) !void { _ = try v.own(s, try h.expression(s.engine, sessionMethod, .{ roots, @as([*:0]const u8, "setSessionName"), @as([]const c.JSValue, &.{f.get(.name)}) })); }
fn messagesReply(s: *Scope, f: *Frame, roots: []const c.JSValue) !c.JSValue {
    const success = try Main.read(s, roots[3]); const name = try v.text(s, "get_messages"); const data = try v.object(s);
    try v.put(s, data, "messages", try v.own(s, try h.expression(s.engine, sessionField, .{ roots, @as([*:0]const u8, "messages") })));
    return v.duplicate(s, try v.call(s, success, c.pi_js_undefined(), &.{ f.get(.id), name, data }));
}
const Row = enum { extension, prompt, skill };
fn commandRows(f: *Frame, roots: []const c.JSValue) !void {
    {
        var iterator = try v.Iterator.initOwned(f.engine, try h.expression(f.engine, registeredCommands, .{roots}));
        try iterator.finish(appendRows(f, &iterator, .extension));
    }
    {
        var iterator = try v.Iterator.initOwned(f.engine, try h.expression(f.engine, sessionField, .{ roots, @as([*:0]const u8, "promptTemplates") }));
        try iterator.finish(appendRows(f, &iterator, .prompt));
    }
    {
        var iterator = try v.Iterator.initOwned(f.engine, try h.expression(f.engine, skills, .{roots}));
        try iterator.finish(appendRows(f, &iterator, .skill));
    }
}
fn registeredCommands(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const runner = try v.own(s, try h.expression(s.engine, sessionField, .{ roots, @as([*:0]const u8, "extensionRunner") }));
    const method = try v.get(s, runner, "getRegisteredCommands");
    return v.duplicate(s, try v.call(s, method, runner, &.{}));
}
fn getSkills(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const loader = try v.own(s, try h.expression(s.engine, sessionField, .{ roots, @as([*:0]const u8, "resourceLoader") }));
    const method = try v.get(s, loader, "getSkills");
    return v.duplicate(s, try v.call(s, method, loader, &.{}));
}
fn skills(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const result = try v.own(s, try h.expression(s.engine, getSkills, .{roots}));
    return v.duplicate(s, try v.get(s, result, "skills"));
}
fn appendRows(f: *Frame, iterator: *v.Iterator, comptime row: Row) !void {
    while (try iterator.next()) |incoming| {
        switch (row) { .extension => try f.take(.extension_command, incoming), .prompt => try f.take(.template, incoming), .skill => try f.take(.skill, incoming) }
        try h.statement(f.engine, appendRow, .{ f, row });
    }
}
fn skillName(s: *Scope, skill: c.JSValue) !c.JSValue {
    const name = try v.own(s, try h.expression(s.engine, stringField, .{ skill, @as([*:0]const u8, "name") }));
    return v.duplicate(s, try v.binary(s, 0, try v.text(s, "skill:"), name));
}
fn appendRow(s: *Scope, f: *Frame, comptime row: Row) !void {
    const commands = try v.own(s, v.duplicate(s, f.get(.commands))); const push = try v.get(s, commands, "push");
    const source = switch (row) { .extension => f.get(.extension_command), .prompt => f.get(.template), .skill => f.get(.skill) };
    const record = try v.object(s);
    try v.put(s, record, "name", if (row == .skill) try v.own(s, try h.expression(s.engine, skillName, .{source})) else try h.fieldValue(s, source, if (row == .extension) "invocationName" else "name"));
    try v.put(s, record, "description", try h.fieldValue(s, source, "description"));
    try v.put(s, record, "source", try v.text(s, @tagName(row)));
    try v.put(s, record, "sourceInfo", try h.fieldValue(s, source, "sourceInfo"));
    _ = try v.call(s, push, commands, &.{record});
}
fn unknownMessage(s: *Scope, command: c.JSValue) !c.JSValue {
    const value = try v.own(s, try h.expression(s.engine, stringField, .{ command, @as([*:0]const u8, "type") }));
    return v.duplicate(s, try v.binary(s, 0, try v.text(s, "Unknown command: "), value));
}
fn unknownReply(s: *Scope, f: *Frame, roots: []const c.JSValue) !c.JSValue {
    const failure = try Main.read(s, roots[4]); const name = try h.fieldValue(s, f.get(.unknown_command), "type");
    const message = try v.own(s, try h.expression(s.engine, unknownMessage, .{f.get(.unknown_command)}));
    return v.duplicate(s, try v.call(s, failure, c.pi_js_undefined(), &.{ f.get(.id), name, message }));
}
