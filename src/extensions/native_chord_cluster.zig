//! Source1692 runClusterReload: retirement before prepare, all votes, FIFO commit before starts and final cleanup.
const r = @import("native_chord_reload_values.zig");
const v = @import("native_chord_cluster_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, mode: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return execute(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), mode) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn execute(engine: *h.Engine, work: c.JSValue, value: c.JSValue, mode: c_int) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (mode == 0) {
        try h.field(&s, work, "local", c.pi_js_bool(engine.context, 1));
        return c.pi_js_undefined();
    }
    if (mode == 1) return s.result(try r.pair(&s, try s.get(work, "name"), value));
    if (mode == 2) return childFailure(&s, work, value);
    const participants = try s.get(work, "participants");
    var iter = try r.iterate(&s, participants);
    defer iter.deinit();
    errdefer iter.closePreserving();
    while (try iter.next()) |connection| {
        defer engine.freeValue(connection);
        try v.send(&s, connection, try v.frame(&s, "commit", try s.get(work, "id")));
        try r.put(&s, connection, "peerCodeVersion", try s.get(work, "codeVersion"));
    }
    return c.pi_js_undefined();
}
fn childFailure(s: *Scope, work: c.JSValue, value: c.JSValue) !c.JSValue {
    const cause = try r.reloadError(s, try s.get(work, "bindings"), value);
    const options = try s.record();
    try h.field(s, options, "cause", cause);
    try h.field(s, options, "reason", try s.get(cause, "reason"));
    const constructor = try s.get(try s.get(try s.get(work, "bindings"), "errors"), "ChordError");
    var args = [_]c.JSValue{ try s.get(cause, "code"), try r.concat(s, &.{ try s.get(work, "name"), try s.text(": "), try s.get(cause, "message") }), options };
    return h.throwValue(s, try s.keep(try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, 3, &args))));
}
fn function(s: *Scope, work: c.JSValue, mode: c_int) !c.JSValue {
    var data = [_]c.JSValue{work};
    return s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 1, mode, 1, &data)));
}
pub fn run(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, plugins: c.JSValue, options: c.JSValue) anyerror!c.JSValue {
    const pending = begin(engine, bindings, host, plugins, options) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    defer engine.freeValue(pending);
    return @import("native_durable.zig").resolvedPromise(engine, pending);
}
fn begin(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, plugins: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const synced = try s.list();
    const connections = try h.snapshot(&s, try s.get(host, "connections"));
    for (0..try h.length(&s, connections)) |index| {
        const connection = try s.at(connections, index);
        if (try s.equal(try s.get(connection, "role"), "downstream") and try s.equal(try s.get(try s.get(connection, "peer"), "kind"), "host") and try h.flag(&s, connection, "open") and try h.flag(&s, connection, "synced")) try js.push(engine, synced, connection);
    }
    const version = try h.invoke(&s, host, "peekNextCodeVersion", &.{});
    const work = try s.record();
    inline for (.{ "bindings", "host", "options", "synced", "codeVersion" }, .{ bindings, host, options, synced, version }) |name, value| try h.field(&s, work, name, value);
    const pending = try s.keep(try @import("native_chord_reload.zig").begin(engine, bindings, host, plugins, options, version));
    return h.wait(started, engine, work, pending, 0);
}
fn started(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, value);
    try h.field(&s, work, "reload", value);
    const pending = h.invoke(&s, value, "waitForRetirement", &.{}) catch |err| {
        const failure = if (err == error.JavaScriptException) try s.keep(c.JS_DupValue(engine.context, engine.captured_exception.?)) else c.pi_js_undefined();
        try r.endReload(&s, try s.get(work, "host"));
        if (err == error.JavaScriptException) return h.throwValue(&s, failure);
        return err;
    };
    return h.wait(step, engine, work, pending, 0);
}
fn finish(s: *Scope, work: c.JSValue, value: c.JSValue, rejected: bool) !c.JSValue {
    try h.field(s, work, "endCalled", c.pi_js_bool(s.engine.context, 1));
    try r.endReload(s, try s.get(work, "host"));
    return if (rejected) h.throwValue(s, value) else s.result(value);
}
fn step(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, phase: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return finish(&s, work, value, true);
    return advance(&s, work, value, phase) catch |err| {
        const failure = if (err == error.JavaScriptException) try s.keep(c.JS_DupValue(engine.context, engine.captured_exception.?)) else c.pi_js_undefined();
        if (!try h.flag(&s, work, "endCalled")) try r.endReload(&s, try s.get(work, "host"));
        if (err == error.JavaScriptException) return h.throwValue(&s, failure);
        return err;
    };
}
fn advance(s: *Scope, work: c.JSValue, value: c.JSValue, phase: c_int) anyerror!c.JSValue {
    const host = try s.get(work, "host");
    const reload = try s.get(work, "reload");
    const bindings = try s.get(work, "bindings");
    if (phase == 0) {
        const participants = try s.list();
        const synced = try s.get(work, "synced");
        for (0..try h.length(s, synced)) |index| {
            const connection = try s.at(synced, index);
            if (try h.flag(s, connection, "open")) try js.push(s.engine, participants, connection);
        }
        try h.field(s, work, "participants", participants);
        const id = try v.nextId(s, bindings);
        try h.field(s, work, "id", id);
        const options = try s.get(work, "options");
        var deadline = try s.get(options, "voteDeadline");
        if (h.nullish(deadline)) {
            const gate = r.default(s, try s.get(options, "gateDeadline"), c.JS_NewInt32(s.engine.context, 5000));
            const retire = r.default(s, try s.get(options, "retireDeadline"), c.JS_NewInt32(s.engine.context, 5000));
            const sum = try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 0, gate, retire)));
            deadline = try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 0, sum, c.JS_NewInt32(s.engine.context, 5000))));
        }
        const votes = try s.list();
        for (0..try h.length(s, participants)) |index| {
            const connection = try s.at(participants, index);
            const name = r.default(s, try s.get(connection, "name"), try s.text("child"));
            const vote = try v.awaitVote(s, bindings, connection, id, deadline);
            const message = try v.frame(s, "prepare", id);
            try h.field(s, message, "codeVersion", try s.get(work, "codeVersion"));
            try h.field(s, message, "plugins", try v.modulesFor(s, try s.get(options, "remote"), name));
            const child_options = try s.record();
            try h.field(s, child_options, "remove", try v.modulesFor(s, try s.get(options, "remoteRemove"), name));
            inline for (.{ "gateDeadline", "retireDeadline" }) |key| try h.field(s, child_options, key, try s.get(options, key));
            try h.field(s, message, "options", child_options);
            try v.send(s, connection, message);
            const child = try s.record();
            try h.field(s, child, "bindings", bindings);
            try h.field(s, child, "name", name);
            try js.push(s.engine, votes, try h.invoke(s, vote, "then", &.{ try function(s, child, 1), try function(s, child, 2) }));
        }
        try h.field(s, work, "local", c.pi_js_bool(s.engine.context, 0));
        const pending = try s.list();
        try js.push(s.engine, pending, try h.invoke(s, try h.invoke(s, reload, "prepare", &.{}), "then", &.{try function(s, work, 0)}));
        for (0..try h.length(s, votes)) |index| try js.push(s.engine, pending, try s.at(votes, index));
        return h.wait(step, s.engine, work, try r.promise(s, "allSettled", pending), 1);
    }
    if (phase == 2) return finish(s, work, try s.get(work, "failure"), true);
    for (0..try h.length(s, value)) |index| {
        const result = try s.at(value, index);
        if (!try s.equal(try s.get(result, "status"), "rejected")) continue;
        const failure = try s.get(result, "reason");
        const participants = try s.get(work, "participants");
        for (0..try h.length(s, participants)) |participant_index| {
            const connection = try s.at(participants, participant_index);
            _ = try h.invoke(s, try s.get(connection, "votes"), "delete", &.{try s.get(work, "id")});
            try v.send(s, connection, try v.frame(s, "abort", try s.get(work, "id")));
        }
        if (try h.flag(s, work, "local")) {
            try h.field(s, work, "failure", failure);
            return h.wait(step, s.engine, work, try h.invoke(s, reload, "rollback", &.{}), 2);
        }
        return finish(s, work, failure, true);
    }
    const report = try h.invoke(s, reload, "commit", &.{try function(s, work, 3)});
    const options = try s.get(work, "options");
    _ = try h.invoke(s, host, "rememberRemoteModules", &.{ try s.get(options, "remote"), try s.get(options, "remoteRemove") });
    const children = try s.record();
    for (1..try h.length(s, value)) |index| {
        const result = try s.at(value, index);
        if (!try s.equal(try s.get(result, "status"), "fulfilled")) continue;
        const entry = try s.get(result, "value");
        const child = try s.at(entry, 1);
        if (!c.JS_IsUndefined(child)) try js.setKey(s.engine, children, try s.at(entry, 0), child);
    }
    const result = try s.record();
    try js.spreadInto(s.engine, result, report);
    try h.field(s, result, "children", children);
    return finish(s, work, result, false);
}
