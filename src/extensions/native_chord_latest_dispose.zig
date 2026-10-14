//! Actual holder-before-held Host disposal waves with independent failures.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
pub fn close(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const host_data = (try h.actor(&s, host, bindings, .HostImpl)).data;
    const lingering = try h.values(&s, try s.get(host_data, "lingering"));
    for (0..try h.length(&s, lingering)) |index| _ = try h.invoke(&s, try s.at(lingering, index), "close", &.{});
    _ = try h.invoke(&s, try s.get(host, "hostObjects"), "clear", &.{});
    const data = (try h.actor(&s, host, bindings, .HostImpl)).data;
    const facets = try h.snapshot(&s, try h.invoke(&s, try s.get(data, "facetRuns"), "keys", &.{}));
    for (0..try h.length(&s, facets)) |index| _ = try h.invoke(&s, host, "facetRunChanged", &.{ try s.at(facets, index), c.pi_js_undefined() });
    const reason = try h.errorValue(&s, bindings, "gone", &.{ try s.text("host "), try s.get(host, "name"), try s.text(" closed") }, c.pi_js_undefined());
    const records = try h.values(&s, try s.get(host, "objects"));
    return holders(engine, bindings, host, records, reason, try s.text("host close: disposal failed"), true) catch |err| {
        const original = if (err == error.JavaScriptException) try s.keep(c.JS_DupValue(engine.context, engine.captured_exception.?)) else c.pi_js_undefined();
        try closeLinks(&s, host);
        if (err == error.JavaScriptException) return h.throwValue(&s, original);
        return err;
    };
}
pub fn holders(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, records: c.JSValue, reason: c.JSValue, message: c.JSValue, close_links: bool) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const remaining = try s.keep(try js.builtin(engine, "Set", &.{records}));
    const holds = try h.map(&s);
    const count = try h.length(&s, records);
    for (0..count) |index| {
        const record = try s.at(records, index);
        const held = try h.set(&s);
        const declarations = try h.snapshot(&s, try h.invoke(&s, record, "allDecls", &.{}));
        const size = try h.length(&s, declarations);
        for (0..size) |position| {
            const values = try h.values(&s, try s.get(try s.at(declarations, position), "refs"));
            const value_count = try h.length(&s, values);
            for (0..value_count) |slot| {
                const target = try s.get(try s.at(values, slot), "object");
                if (!c.JS_IsUndefined(target)) _ = try h.invoke(&s, held, "add", &.{target});
            }
        }
        _ = try h.invoke(&s, holds, "set", &.{ record, held });
    }
    const work = try s.record();
    try h.field(&s, work, "host", host);
    try h.field(&s, work, "bindings", bindings);
    try h.field(&s, work, "remaining", remaining);
    try h.field(&s, work, "refs", holds);
    try h.field(&s, work, "errors", try s.list());
    try h.field(&s, work, "reason", reason);
    try h.field(&s, work, "message", message);
    try h.field(&s, work, "closeLinks", c.pi_js_bool(engine.context, @intFromBool(close_links)));
    return wave(engine, work);
}
fn closeLinks(s: *Scope, host: c.JSValue) !void {
    const connections = try h.snapshot(s, try s.get(host, "connections"));
    const count = try h.length(s, connections);
    for (0..count) |index| _ = try h.invoke(s, try s.get(try s.at(connections, index), "link"), "close", &.{try s.text("host closed")});
}
fn wave(engine: *h.Engine, work: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const remaining = try s.get(work, "remaining");
    const records = try h.snapshot(&s, remaining);
    const size = try h.length(&s, records);
    if (size == 0) return h.wait(finish, engine, work, c.pi_js_undefined(), 1);
    const held_by_remaining = try h.set(&s);
    const holds = try s.get(work, "refs");
    for (0..size) |index| {
        const record = try s.at(records, index);
        const targets = try h.invoke(&s, holds, "get", &.{record});
        if (h.nullish(targets)) continue;
        const values = try h.snapshot(&s, targets);
        const count = try h.length(&s, values);
        for (0..count) |position| _ = try h.invoke(&s, held_by_remaining, "add", &.{try s.at(values, position)});
    }
    var selected = try s.list();
    for (0..size) |index| {
        const record = try s.at(records, index);
        if (c.JS_ToBool(engine.context, try h.invoke(&s, held_by_remaining, "has", &.{record})) == 0) try js.push(engine, selected, record);
    }
    if (try h.length(&s, selected) == 0) selected = records;
    const count = try h.length(&s, selected);
    for (0..count) |index| _ = try h.invoke(&s, remaining, "delete", &.{try s.at(selected, index)});
    const promises = try s.list();
    for (0..count) |index| try js.push(engine, promises, try h.invoke(&s, try s.at(selected, index), "dispose", &.{ c.pi_js_bool(engine.context, 1), try s.get(work, "reason") }));
    const promise_type = try s.keep(try js.global(engine, "Promise"));
    const settled = try h.invoke(&s, promise_type, "allSettled", &.{promises});
    return h.wait(finish, engine, work, settled, 0);
}
fn finish(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const host = try s.get(work, "host");
    if (rejected) {
        if (try h.flag(&s, work, "closeLinks")) try closeLinks(&s, host);
        return engine.checked(c.JS_Throw(engine.context, s.result(value)));
    }
    if (stage == 0) {
        const errors = try s.get(work, "errors");
        const symbol = try s.keep(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
        var iterator = try js.Iterator.init(engine, value, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |item| {
            defer engine.freeValue(item);
            if (try s.equal(try s.get(item, "status"), "rejected")) try js.push(engine, errors, try s.get(item, "reason"));
        }
        return wave(engine, work) catch |err| {
            if (try h.flag(&s, work, "closeLinks")) try closeLinks(&s, host);
            return err;
        };
    }
    const errors = try s.get(work, "errors");
    const count = try h.length(&s, errors);
    var failure = c.pi_js_undefined();
    if (count == 1) failure = try s.at(errors, 0) else if (count > 1) failure = try s.keep(try js.builtin(engine, "AggregateError", &.{ errors, try s.get(work, "message") }));
    if (try h.flag(&s, work, "closeLinks")) try closeLinks(&s, host);
    return if (count > 0) engine.checked(c.JS_Throw(engine.context, s.result(failure))) else c.pi_js_undefined();
}
