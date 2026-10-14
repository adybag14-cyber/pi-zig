//! Source prepare pipeline, activation fixpoint and exclusive gate replacement.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
pub fn prepareAll(s: *Scope, bindings: c.JSValue, reload: c.JSValue) anyerror!c.JSValue {
    const work = try s.record();
    try h.field(s, work, "bindings", bindings);
    try h.field(s, work, "reload", reload);
    return allStep(s.engine, work, c.pi_js_undefined(), false, 0);
}
fn allStep(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, phase: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, value);
    const reload = try s.get(work, "reload");
    const bindings = try s.get(work, "bindings");
    if (phase != 0) try r.alive(&s, bindings, reload);
    if (phase == 0) {
        const todo = try s.list();
        const records = try h.values(&s, try s.get(try s.get(reload, "host"), "records"));
        for (0..try h.length(&s, records)) |index| {
            const record = try s.at(records, index);
            const name = try s.get(record, "typeName");
            if (try r.has(&s, try s.get(reload, "changed"), name) and !try r.has(&s, try s.get(reload, "candidates"), record) and !c.JS_IsStrictEqual(engine.context, try s.get(record, "service"), try h.invoke(&s, try s.get(reload, "services"), "get", &.{name})) and (try s.equal(try s.get(record, "status"), "live") or try s.equal(try s.get(record, "status"), "activating"))) try js.push(engine, todo, record);
        }
        if (try h.length(&s, todo) == 0) return c.pi_js_undefined();
        try h.field(&s, work, "todo", todo);
        try h.field(&s, work, "index", c.JS_NewInt32(engine.context, 0));
        const ready = try s.list();
        for (0..try h.length(&s, todo)) |index| try js.push(engine, ready, try s.get(try s.at(todo, index), "ready"));
        return h.wait(allStep, engine, work, try r.promise(&s, "allSettled", ready), 1);
    }
    const todo = try s.get(work, "todo");
    while (try r.index(&s, work, "index") < try h.length(&s, todo)) {
        const record = try s.at(todo, try r.advance(&s, work, "index"));
        if (try s.equal(try s.get(record, "status"), "live") and !c.JS_IsStrictEqual(engine.context, try s.get(record, "service"), try h.invoke(&s, try s.get(reload, "services"), "get", &.{try s.get(record, "typeName")}))) return h.wait(allStep, engine, work, try h.invoke(&s, reload, "prepareRecord", &.{record}), 2);
    }
    return allStep(engine, work, c.pi_js_undefined(), false, 0);
}
pub fn gate(s: *Scope, bindings: c.JSValue, reload: c.JSValue) anyerror!c.JSValue {
    const work = try s.record();
    try h.field(s, work, "bindings", bindings);
    try h.field(s, work, "reload", reload);
    return h.wait(gateStep, s.engine, work, try @import("native_chord_reload_timing.zig").drain(s, reload), 0);
}
fn gateStep(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, phase: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, value);
    const reload = try s.get(work, "reload");
    const bindings = try s.get(work, "bindings");
    const gated = try s.get(reload, "gated");
    if (phase == 0) {
        if (c.JS_ToBool(engine.context, value) != 0) {
            const blocking = try s.list();
            for (0..try h.length(&s, gated)) |index| {
                const gate_value = try s.get(try s.get(try s.at(gated, index), "record"), "gate");
                const roots = try r.optional(&s, gate_value, "grandfathered");
                const list = try h.snapshot(&s, if (h.nullish(roots)) try s.list() else roots);
                for (0..try h.length(&s, list)) |root_index| try js.push(engine, blocking, try s.at(list, root_index));
            }
            const options = try r.reason(&s, "gate_deadline");
            const details = try s.record();
            try h.field(&s, details, "blocking", blocking);
            try h.field(&s, options, "details", details);
            const deadline = r.default(&s, try s.get(try s.get(reload, "options"), "gateDeadline"), c.JS_NewInt32(engine.context, 5000));
            return h.throwValue(&s, try h.errorValue(&s, bindings, "aborted", &.{ try s.text("gate deadline ("), deadline, try s.text(" ms) missed; blocking roots: "), try h.invoke(&s, blocking, "join", &.{try s.text(", ")}) }, options));
        }
        try r.alive(&s, bindings, reload);
        try h.field(&s, work, "candidateIndex", c.JS_NewInt32(engine.context, 0));
        try h.field(&s, work, "replacedIndex", c.JS_NewInt32(engine.context, 0));
    } else if (phase == 2) {
        try r.alive(&s, bindings, reload);
        _ = try r.advance(&s, work, "candidateIndex");
        try r.put(&s, work, "replacedIndex", c.JS_NewInt32(engine.context, 0));
    }
    while (try r.index(&s, work, "candidateIndex") < try h.length(&s, gated)) {
        const candidate = try s.at(gated, try r.index(&s, work, "candidateIndex"));
        const record = try s.get(candidate, "record");
        const replaced = try s.get(candidate, "replaced");
        if (try r.index(&s, work, "replacedIndex") < try h.length(&s, replaced)) {
            const old = try s.at(replaced, try r.advance(&s, work, "replacedIndex"));
            try js.push(engine, try s.get(reload, "closed"), try r.pair(&s, record, old));
            return h.wait(gateStep, engine, work, try h.invoke(&s, old, "close", &.{try s.get(record, "openOrder")}), 1);
        }
        return h.wait(gateStep, engine, work, try h.invoke(&s, record, "open", &.{ try s.get(candidate, "atGate"), try s.list(), try s.get(try s.get(reload, "abort"), "signal") }), 2);
    }
    var iter = try r.iterate(&s, gated);
    defer iter.deinit();
    errdefer iter.closePreserving();
    while (try iter.next()) |candidate| {
        defer engine.freeValue(candidate);
        _ = try h.invoke(&s, reload, "migrate", &.{candidate});
    }
    return c.pi_js_undefined();
}
pub fn prepare(s: *Scope, bindings: c.JSValue, reload: c.JSValue) anyerror!c.JSValue {
    const work = try s.record();
    try h.field(s, work, "bindings", bindings);
    try h.field(s, work, "reload", reload);
    return caught(s, work, 0);
}
fn caught(s: *Scope, work: c.JSValue, phase: c_int) anyerror!c.JSValue {
    return pipeline(s, work, phase) catch |err| {
        if (err != error.JavaScriptException) return err;
        const original = try s.keep(c.JS_DupValue(s.engine.context, s.engine.captured_exception.?));
        return fail(s, work, original);
    };
}
fn fail(s: *Scope, work: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    try h.field(s, work, "failure", value);
    return h.wait(prepareStep, s.engine, work, try h.invoke(s, try s.get(work, "reload"), "rollback", &.{}), 9);
}
fn prepareStep(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, phase: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (phase == 9) {
        if (rejected) return h.throwValue(&s, value);
        return h.throwValue(&s, try r.reloadError(&s, try s.get(work, "bindings"), try s.get(work, "failure")));
    }
    if (rejected) return fail(&s, work, value);
    return caught(&s, work, phase);
}
fn pipeline(s: *Scope, work: c.JSValue, phase: c_int) anyerror!c.JSValue {
    const reload = try s.get(work, "reload");
    const bindings = try s.get(work, "bindings");
    const host = try s.get(reload, "host");
    if (phase == 0) return h.wait(prepareStep, s.engine, work, try h.invoke(s, reload, "waitForRetirement", &.{}), 1);
    if (phase == 1) {
        _ = try h.invoke(s, reload, "load", &.{});
        _ = try h.invoke(s, reload, "checkProviders", &.{});
        return h.wait(prepareStep, s.engine, work, try h.invoke(s, reload, "prepareAll", &.{}), 2);
    }
    if (phase == 2) {
        try r.put(s, host, "gating", try s.get(reload, "changed"));
        return h.wait(prepareStep, s.engine, work, try h.invoke(s, reload, "withDeadline", &.{ try h.invoke(s, reload, "prepareAll", &.{}), try s.text("activations in flight did not finish") }), 3);
    }
    if (phase == 3) {
        _ = try h.invoke(s, reload, "checkHolds", &.{});
        try r.put(s, reload, "tables", try h.invoke(s, host, "buildTables", &.{try h.invoke(s, reload, "entries", &.{})}));
        return h.wait(prepareStep, s.engine, work, try h.invoke(s, reload, "gate", &.{}), 4);
    }
    try r.alive(s, bindings, reload);
    try @import("native_chord_reload_table.zig").stage(s, reload);
    return c.pi_js_undefined();
}
