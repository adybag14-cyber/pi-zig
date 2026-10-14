//! Actual shared b45 remote binding, one hold and decoder set for all views.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
pub const Scope = h.Scope;
const aw = @import("native_chord_async_work.zig");
const Method = enum(c_int) { ended, stateViews, wantsState, applied, addView, removeView, listen, unlisten, inVariant, read, whenHydrated, readable, terminalError, bound, shaped, state, gone, detached, close, call };
pub fn data(s: *Scope, binding: c.JSValue, bindings: c.JSValue) !c.JSValue {
    return (try h.actor(s, binding, bindings, .RemoteBinding)).data;
}
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    const method: Method = @enumFromInt(magic);
    return invoke(engine, receiver, captures[0], if (argc > 0) argv[0..@intCast(argc)] else &.{}, method) catch |err| if (method == .call) @import("native_durable.zig").rejectedPromise(engine, err) else @import("native_durable.zig").reject(engine, err);
}
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn executor(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    inline for (.{ "resolve", "reject" }, 0..) |name, index| h.field(&s, captures[0], name, if (argc > index) argv[index] else c.pi_js_undefined()) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_undefined();
}
pub fn deferred(s: *Scope) !c.JSValue {
    return createDeferred(s, true);
}
fn createDeferred(s: *Scope, observe: bool) !c.JSValue {
    const result = try s.record();
    var captures = [_]c.JSValue{result};
    const create = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, executor, "", 2, 0, 1, &captures)));
    const promise = try s.keep(try js.builtin(s.engine, "Promise", &.{create}));
    if (observe) {
        const ignored = try s.keep(try s.engine.checked(c.JS_NewCFunction(s.engine.context, noop, "noop", 0)));
        _ = try h.invoke(s, promise, "catch", &.{ignored});
    }
    try h.field(s, result, "promise", promise);
    return result;
}
pub fn settle(s: *Scope, target: c.JSValue, value: c.JSValue, rejected: bool) !void {
    _ = try s.keep(try js.call(s.engine, try s.get(target, if (rejected) "reject" else "resolve"), target, if (rejected) &.{value} else &.{}));
}
fn each(s: *Scope, iterable: c.JSValue, method: [*:0]const u8, args: []const c.JSValue, snapshot: bool) !void {
    const source = if (snapshot) try h.snapshot(s, iterable) else iterable;
    var iterator = try js.Iterator.init(s.engine, source, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |item| {
        defer s.engine.freeValue(item);
        _ = try h.invoke(s, item, method, args);
    }
}
fn has(s: *Scope, collection: c.JSValue, key: c.JSValue) !bool {
    return c.JS_ToBool(s.engine.context, try h.invoke(s, collection, "has", &.{key})) != 0;
}
fn countViews(s: *Scope, binding: c.JSValue) !usize {
    var iterator = try js.Iterator.init(s.engine, try s.get(binding, "views"), try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var count: usize = 0;
    while (try iterator.next()) |view| {
        defer s.engine.freeValue(view);
        if (try h.flag(s, view, "wantsState")) count += 1;
    }
    return count;
}
fn syncState(s: *Scope, binding: c.JSValue, owned: c.JSValue) !void {
    if (try h.flag(s, binding, "ended") or !try @import("native_chord_object.zig").nonempty(s, try s.get(binding, "views"))) return;
    const wanted = try countViews(s, binding) > 0;
    if (wanted == try h.flag(s, binding, "stateOn")) return;
    try h.field(s, binding, "stateOn", c.pi_js_bool(s.engine.context, @intFromBool(wanted)));
    if (!wanted) {
        try h.field(s, binding, "hydrated", c.pi_js_bool(s.engine.context, 0));
        _ = try h.invoke(s, try s.get(binding, "members"), "clear", &.{});
        const pending = try s.get(owned, "pending");
        if (!c.JS_IsUndefined(pending)) _ = try h.invoke(s, try s.get(pending, "missing"), "clear", &.{});
    }
    const hold = try s.get(binding, "hold");
    if (!c.JS_IsUndefined(hold)) _ = try h.invoke(s, try s.get(hold, "channel"), "wantState", &.{ try s.get(hold, "id"), c.pi_js_bool(s.engine.context, @intFromBool(wanted)) });
    try each(s, try s.get(binding, "views"), "update", &.{}, false);
}
pub fn inVariant(s: *Scope, binding: c.JSValue, name: c.JSValue) !bool {
    const shape = try s.get(binding, "shape");
    const variant = if (h.nullish(shape)) c.pi_js_undefined() else try s.get(shape, "variant");
    if (c.JS_IsUndefined(variant)) return false;
    const members = try s.key(try s.get(try s.get(try s.get(binding, "contract"), "description"), "variants"), variant);
    if (h.nullish(members)) return false;
    const member = try s.key(members, name);
    return !h.nullish(member) and try s.equal(try s.get(member, "kind"), "state");
}
fn stateMembers(s: *Scope, binding: c.JSValue, shape: c.JSValue) !c.JSValue {
    const variant = try s.get(shape, "variant");
    if (c.JS_IsUndefined(variant)) return h.set(s);
    const members = try s.key(try s.get(try s.get(try s.get(binding, "contract"), "description"), "variants"), try s.get(shape, "variant"));
    if (c.JS_IsUndefined(members)) return h.set(s);
    var captures = [_]c.JSValue{members};
    const filter = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, stateMemberFilter, "", 1, 0, 1, &captures)));
    const selected = try h.invoke(s, try s.get(shape, "members"), "filter", &.{filter});
    return s.keep(try js.builtin(s.engine, "Set", &.{selected}));
}
fn stateMemberFilter(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const name = if (argc > 0) argv[0] else c.pi_js_undefined();
    const member = s.key(captures[0], name) catch |err| return @import("native_durable.zig").reject(engine, err);
    if (h.nullish(member)) return c.pi_js_bool(engine.context, 0);
    const kind = s.get(member, "kind") catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(s.equal(kind, "state") catch |err| return @import("native_durable.zig").reject(engine, err)));
}
fn settleHydration(s: *Scope, owned: c.JSValue, failure: c.JSValue) !void {
    const set = try s.get(owned, "hydrationWaiters");
    const waiters = try h.snapshot(s, set);
    _ = try h.invoke(s, set, "clear", &.{});
    for (0..try h.length(s, waiters)) |index| try settle(s, try s.at(waiters, index), failure, !c.JS_IsUndefined(failure));
}
fn deliver(s: *Scope, owned: c.JSValue, name: c.JSValue, delivered: c.JSValue) !void {
    const listeners = try h.invoke(s, try s.get(owned, "listeners"), "get", &.{name});
    if (!c.JS_IsUndefined(listeners)) try each(s, listeners, "deliver", &.{delivered}, true);
}
fn event(s: *Scope, kind: []const u8, value: c.JSValue) !c.JSValue {
    const result = try s.record();
    try h.field(s, result, "type", try s.text(kind));
    try h.field(s, result, "value", value);
    return result;
}
fn apply(s: *Scope, binding: c.JSValue, owned: c.JSValue) !void {
    const pending = try s.get(owned, "pending");
    if (c.JS_IsUndefined(pending)) return;
    try h.field(s, owned, "pending", c.pi_js_undefined());
    try h.field(s, binding, "shape", try s.get(pending, "shape"));
    const wanted = try stateMembers(s, binding, try s.get(pending, "shape"));
    const members = try s.get(binding, "members");
    const names = try h.snapshot(s, try h.invoke(s, members, "keys", &.{}));
    for (0..try h.length(s, names)) |index| {
        const name = try s.at(names, index);
        if (!try has(s, wanted, name)) _ = try h.invoke(s, members, "delete", &.{name});
    }
    const values = try s.get(pending, "values");
    try applyValues(s, values, wanted, members);
    var hydrated = try h.flag(s, binding, "stateOn");
    const required = try h.snapshot(s, wanted);
    for (0..try h.length(s, required)) |index| {
        if (!hydrated) break;
        hydrated = try has(s, members, try s.at(required, index));
    }
    try h.field(s, binding, "hydrated", c.pi_js_bool(s.engine.context, @intFromBool(hydrated)));
    if (hydrated) try settleHydration(s, owned, c.pi_js_undefined());
    try h.field(s, binding, "status", try s.text("live"));
    try h.field(s, owned, "applied", c.pi_js_bool(s.engine.context, 1));
    try settle(s, try s.get(owned, "live"), c.pi_js_undefined(), false);
    try each(s, try s.get(binding, "views"), "update", &.{}, false);
    var iterator = try js.Iterator.init(s.engine, values, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |pair| {
        defer s.engine.freeValue(pair);
        const name = try s.at(pair, 0);
        if (try has(s, wanted, name)) try deliver(s, owned, name, try event(s, "reset", try s.get(try s.at(pair, 1), "value")));
    }
    try each(s, try s.get(binding, "views"), "shapeChanged", &.{}, true);
}
fn applyValues(s: *Scope, values: c.JSValue, wanted: c.JSValue, members: c.JSValue) !void {
    var iterator = try js.Iterator.init(s.engine, values, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |pair| {
        defer s.engine.freeValue(pair);
        if (try has(s, wanted, try s.at(pair, 0))) _ = try h.invoke(s, members, "set", &.{ try s.at(pair, 0), try s.at(pair, 1) });
    }
}
fn invoke(engine: *h.Engine, binding: c.JSValue, bindings: c.JSValue, args: []const c.JSValue, method: Method) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owned = try data(&s, binding, bindings);
    const first = h.arg(args, 0);
    const second = h.arg(args, 1);
    switch (method) {
        .ended => return c.pi_js_bool(engine.context, @intFromBool(try s.equal(try s.get(binding, "status"), "ended"))),
        .stateViews => return c.JS_NewFloat64(engine.context, @floatFromInt(try countViews(&s, binding))),
        .wantsState => return if (!try @import("native_chord_object.zig").nonempty(&s, try s.get(binding, "views"))) s.result(try s.get(binding, "stateOn")) else c.pi_js_bool(engine.context, @intFromBool(try countViews(&s, binding) > 0)),
        .applied => return s.result(try s.get(owned, "applied")),
        .terminalError => {
            const failure = try s.get(binding, "error");
            return if (!h.nullish(failure)) s.result(failure) else s.result(try h.errorValue(&s, bindings, "released", &.{ try s.text("reference "), try s.get(binding, "key"), try s.text(" released") }, c.pi_js_undefined()));
        },
        .inVariant => return c.pi_js_bool(engine.context, @intFromBool(try inVariant(&s, binding, first))),
        .readable => return c.pi_js_bool(engine.context, @intFromBool(!try h.flag(&s, binding, "ended") and try h.flag(&s, binding, "hydrated") and try inVariant(&s, binding, first))),
        .read => {
            if (try h.flag(&s, binding, "ended")) return h.throwValue(&s, try h.invoke(&s, binding, "terminalError", &.{}));
            if (!try h.flag(&s, binding, "hydrated")) return h.throwValue(&s, try h.errorValue(&s, bindings, "not_ready", &.{ try s.get(binding, "key"), try s.text("."), first, try s.text(" is not hydrated yet") }, c.pi_js_undefined()));
            if (!try inVariant(&s, binding, first)) {
                const shape = try s.get(binding, "shape");
                return h.throwValue(&s, try h.errorValue(&s, bindings, "not_in_variant", &.{ try s.get(binding, "key"), try s.text(": "), first, try s.text(" is not a state member of variant "), if (h.nullish(shape)) c.pi_js_undefined() else try s.get(shape, "variant") }, c.pi_js_undefined()));
            }
            const member = try h.invoke(&s, try s.get(binding, "members"), "get", &.{first});
            return if (h.nullish(member)) c.pi_js_undefined() else js.get(engine, member, "value");
        },
        .whenHydrated => {
            const promise = try s.keep(try js.global(engine, "Promise"));
            if (try h.flag(&s, binding, "hydrated")) return js.invoke(engine, promise, "resolve", &.{});
            if (try h.flag(&s, binding, "ended")) return js.invoke(engine, promise, "reject", &.{try h.invoke(&s, binding, "terminalError", &.{})});
            const waiter = try createDeferred(&s, false);
            _ = try h.invoke(&s, try s.get(owned, "hydrationWaiters"), "add", &.{waiter});
            return s.result(try s.get(waiter, "promise"));
        },
        .addView => {
            _ = try h.invoke(&s, try s.get(binding, "views"), "add", &.{first});
            const timer = try s.get(binding, "lingerTimer");
            if (!c.JS_IsUndefined(timer)) {
                _ = try s.keep(try js.call(engine, try s.keep(try js.global(engine, "clearTimeout")), c.pi_js_undefined(), &.{timer}));
                try h.field(&s, binding, "lingerTimer", c.pi_js_undefined());
            }
            try syncState(&s, binding, owned);
            _ = try h.invoke(&s, first, "update", &.{});
        },
        .removeView => {
            if (c.JS_ToBool(engine.context, try h.invoke(&s, try s.get(binding, "views"), "delete", &.{first})) == 0) return c.pi_js_undefined();
            var sets = try js.Iterator.init(engine, try h.invoke(&s, try s.get(owned, "listeners"), "values", &.{}), try h.iteratorSymbol(&s));
            defer sets.deinit();
            errdefer sets.closePreserving();
            while (try sets.next()) |set| {
                defer engine.freeValue(set);
                var readables = try js.Iterator.init(engine, set, try h.iteratorSymbol(&s));
                defer readables.deinit();
                errdefer readables.closePreserving();
                while (try readables.next()) |readable_value| {
                    defer engine.freeValue(readable_value);
                    if (c.JS_IsStrictEqual(engine.context, try s.get(readable_value, "view"), first)) _ = try h.invoke(&s, set, "delete", &.{readable_value});
                }
            }
            if (!try @import("native_chord_object.zig").nonempty(&s, try s.get(binding, "views"))) _ = try h.invoke(&s, try s.get(binding, "host"), "bindingIdle", &.{binding}) else try syncState(&s, binding, owned);
        },
        .listen, .unlisten => {
            const listeners = try s.get(owned, "listeners");
            var set = try h.invoke(&s, listeners, "get", &.{first});
            if (c.JS_IsUndefined(set)) {
                if (method == .unlisten) return c.pi_js_undefined();
                set = try h.set(&s);
                _ = try h.invoke(&s, listeners, "set", &.{ first, set });
            }
            _ = try h.invoke(&s, set, if (method == .listen) "add" else "delete", &.{second});
        },
        .bound => {
            const hold = try s.record();
            try h.field(&s, hold, "channel", first);
            try h.field(&s, hold, "id", second);
            try h.field(&s, binding, "hold", hold);
            try h.field(&s, binding, "stateOn", try s.get(binding, "wantsState"));
        },
        .shaped => {
            if (try h.flag(&s, binding, "ended")) return c.pi_js_undefined();
            const previous = try s.get(owned, "pending");
            const missing = try s.keep(try js.builtin(engine, "Set", &.{second}));
            if (!c.JS_IsUndefined(previous)) {
                var iterator = try js.Iterator.init(engine, try s.get(previous, "missing"), try h.iteratorSymbol(&s));
                defer iterator.deinit();
                errdefer iterator.closePreserving();
                while (try iterator.next()) |name| {
                    defer engine.freeValue(name);
                    _ = try h.invoke(&s, missing, "add", &.{name});
                }
            }
            const wanted = try stateMembers(&s, binding, first);
            const names = try h.snapshot(&s, missing);
            for (0..try h.length(&s, names)) |index| {
                const name = try s.at(names, index);
                if (!try has(&s, wanted, name) or !try h.flag(&s, binding, "stateOn")) _ = try h.invoke(&s, missing, "delete", &.{name});
            }
            const pending = try s.record();
            try h.field(&s, pending, "shape", first);
            try h.field(&s, pending, "missing", missing);
            try h.field(&s, pending, "values", if (c.JS_IsUndefined(previous)) try h.map(&s) else try s.get(previous, "values"));
            try h.field(&s, owned, "pending", pending);
            if (!try @import("native_chord_object.zig").nonempty(&s, missing)) try apply(&s, binding, owned);
        },
        .state => try stateFrame(&s, binding, bindings, owned, first, second),
        .gone => {
            if (try h.flag(&s, binding, "ended")) return c.pi_js_undefined();
            try h.field(&s, binding, "status", try s.text("ended"));
            try h.field(&s, binding, "error", first);
            try h.field(&s, binding, "hold", c.pi_js_undefined());
            try h.field(&s, owned, "pending", c.pi_js_undefined());
            try settle(&s, try s.get(owned, "live"), first, true);
            try settleHydration(&s, owned, first);
            try each(&s, try s.get(binding, "views"), "end", &.{first}, true);
            _ = try h.invoke(&s, try s.get(owned, "listeners"), "clear", &.{});
            _ = try h.invoke(&s, try s.get(binding, "host"), "forgetBinding", &.{binding});
        },
        .detached => {
            if (try h.flag(&s, binding, "ended")) return c.pi_js_undefined();
            try h.field(&s, binding, "hold", c.pi_js_undefined());
            try h.field(&s, owned, "pending", c.pi_js_undefined());
            if (try s.equal(try s.get(binding, "status"), "live")) {
                try h.field(&s, binding, "status", try s.text("loading"));
                try h.field(&s, owned, "live", try deferred(&s));
            }
            try each(&s, try s.get(binding, "views"), "update", &.{}, false);
        },
        .close => {
            const timer = try s.get(binding, "lingerTimer");
            if (!c.JS_IsUndefined(timer)) _ = try s.keep(try js.call(engine, try s.keep(try js.global(engine, "clearTimeout")), c.pi_js_undefined(), &.{timer}));
            try h.field(&s, binding, "lingerTimer", c.pi_js_undefined());
            const hold = try s.get(binding, "hold");
            if (!c.JS_IsUndefined(hold)) _ = try h.invoke(&s, try s.get(hold, "channel"), "release", &.{try s.get(hold, "id")});
            try h.field(&s, binding, "hold", c.pi_js_undefined());
            if (!try h.flag(&s, binding, "ended")) {
                try h.field(&s, binding, "status", try s.text("ended"));
                const failure = try h.errorValue(&s, bindings, "released", &.{ try s.text("reference "), try s.get(binding, "key"), try s.text(" released") }, c.pi_js_undefined());
                try settle(&s, try s.get(owned, "live"), failure, true);
                try settleHydration(&s, owned, failure);
                try each(&s, try s.get(binding, "views"), "end", &.{failure}, true);
            }
            try h.field(&s, owned, "pending", c.pi_js_undefined());
            _ = try h.invoke(&s, try s.get(owned, "listeners"), "clear", &.{});
            _ = try h.invoke(&s, try s.get(binding, "host"), "forgetBinding", &.{binding});
        },
        .call => return call(engine, binding, bindings, first, second, h.arg(args, 2)),
    }
    return c.pi_js_undefined();
}
fn stateFrame(s: *Scope, binding: c.JSValue, bindings: c.JSValue, owned: c.JSValue, name: c.JSValue, frame: c.JSValue) !void {
    if (try h.flag(s, binding, "ended")) return;
    if (try s.equal(try s.get(frame, "as"), "error")) {
        const failure = try h.invoke(s, try s.get(bindings, "Wire"), "fromWireError", &.{try s.get(frame, "error")});
        if (!try h.flag(s, binding, "hydrated") and try h.flag(s, binding, "stateOn")) {
            _ = try h.invoke(s, binding, "gone", &.{failure});
            _ = try h.invoke(s, binding, "close", &.{});
        } else _ = try h.invoke(s, try s.get(binding, "host"), "report", &.{failure});
        return;
    }
    const pending = try s.get(owned, "pending");
    const members = try s.get(binding, "members");
    const codec = try s.get(bindings, "DeltaCodec");
    if (try s.equal(try s.get(frame, "as"), "ops")) {
        var target = if (h.nullish(pending)) c.pi_js_undefined() else try h.invoke(s, try s.get(pending, "values"), "get", &.{name});
        if (h.nullish(target)) target = try h.invoke(s, members, "get", &.{name});
        if (c.JS_IsUndefined(target)) return;
        const given_ops = try s.get(frame, "ops");
        const ops = try h.invoke(s, try s.get(target, "decoder"), "decode", &.{if (h.nullish(given_ops)) try s.list() else given_ops});
        try h.field(s, target, "value", try h.invoke(s, codec, "applyImmutable", &.{ try s.get(target, "value"), ops }));
        if (c.JS_IsStrictEqual(s.engine.context, target, try h.invoke(s, members, "get", &.{name}))) {
            const delivered = try event(s, "ops", try s.get(target, "value"));
            try h.field(s, delivered, "ops", ops);
            try deliver(s, owned, name, delivered);
        }
        return;
    }
    const fresh = try s.record();
    try h.field(s, fresh, "value", try s.get(frame, "value"));
    try h.field(s, fresh, "decoder", try h.invoke(s, codec, "decoder", &.{}));
    if (!c.JS_IsUndefined(pending) and (try has(s, try s.get(pending, "missing"), name) or try has(s, try s.get(pending, "values"), name))) {
        _ = try h.invoke(s, try s.get(pending, "values"), "set", &.{ name, fresh });
        _ = try h.invoke(s, try s.get(pending, "missing"), "delete", &.{name});
        if (!try @import("native_chord_object.zig").nonempty(s, try s.get(pending, "missing"))) try apply(s, binding, owned);
        return;
    }
    if (!try inVariant(s, binding, name)) return;
    _ = try h.invoke(s, members, "set", &.{ name, fresh });
    try deliver(s, owned, name, try event(s, "reset", try s.get(fresh, "value")));
}
fn callStage(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected or stage == 1) {
        try aw.complete(&s, work, value, rejected);
        return;
    }
    try callAttempt(&s, work);
}
fn callAttempt(s: *Scope, work: c.JSValue) !void {
    const binding = try s.get(work, "binding");
    if (try h.flag(s, binding, "ended")) {
        try aw.complete(s, work, try h.invoke(s, binding, "terminalError", &.{}), true);
        return;
    }
    const owned = try data(s, binding, try s.get(work, "bindings"));
    const ctx = try s.get(work, "ctx");
    if (!try s.equal(try s.get(binding, "status"), "live") or c.JS_IsUndefined(try s.get(binding, "hold"))) {
        const pending = try s.keep(try @import("native_chord_ready_v4.zig").raceSignal(s.engine, try s.get(work, "bindings"), try s.get(try s.get(owned, "live"), "promise"), try s.get(ctx, "signal")));
        try aw.wait(callStage, s, work, pending, 0);
        return;
    }
    const hold = try s.get(binding, "hold");
    const shape = try s.get(binding, "shape");
    const variant = if (h.nullish(shape)) c.pi_js_undefined() else try s.get(shape, "variant");
    const members = if (c.JS_IsUndefined(variant)) c.pi_js_undefined() else try s.key(try s.get(try s.get(try s.get(binding, "contract"), "description"), "variants"), variant);
    const name = try s.get(work, "name");
    const description = if (h.nullish(members)) c.pi_js_undefined() else try s.key(members, name);
    if (h.nullish(description) or !try s.equal(try s.get(description, "kind"), "method")) {
        const reason = try h.errorValue(s, try s.get(work, "bindings"), "not_in_variant", &.{ try s.get(binding, "key"), try s.text(": "), name, try s.text(" is not a method of variant "), variant }, c.pi_js_undefined());
        try aw.complete(s, work, reason, true);
        return;
    }
    const schema = try s.get(description, "args");
    const sent = if (c.JS_IsUndefined(schema)) c.pi_js_undefined() else try @import("native_chord_object_schema.zig").clean(s, schema, try s.get(work, "args"));
    const root = try s.record();
    inline for (.{ "rootId", "codeVersion" }) |field| try h.field(s, root, field, try s.get(ctx, field));
    // Source returns the channel promise from its async method. Resolve this
    // capability with that value, preserving real async-return adoption.
    try aw.complete(s, work, try h.invoke(s, try s.get(hold, "channel"), "call", &.{ try s.get(hold, "id"), name, sent, root, try s.get(ctx, "signal") }), false);
}
fn call(engine: *h.Engine, binding: c.JSValue, bindings: c.JSValue, name: c.JSValue, args: c.JSValue, ctx: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try aw.create(&s);
    inline for (.{ "binding", "bindings", "name", "args", "ctx" }, .{ binding, bindings, name, args, ctx }) |field, value| try h.field(&s, work, field, value);
    const generation = engine.native_allocation_generation;
    callAttempt(&s, work) catch |err| try aw.rejectErrorSince(&s, work, err, generation);
    return aw.result(&s, work);
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const binding = try s.keep(try h.allocate(engine, target, captures[0], .RemoteBinding));
    const owned = try data(&s, binding, captures[0]);
    try h.field(&s, binding, "host", h.arg(args, 0));
    inline for (.{ "key", "contract", "at", "input", "principal" }) |field| try h.field(&s, binding, field, try s.get(h.arg(args, 1), field));
    try h.field(&s, binding, "status", try s.text("loading"));
    inline for (.{ "error", "shape", "hold", "lingerTimer" }) |field| try h.field(&s, binding, field, c.pi_js_undefined());
    inline for (.{ "hydrated", "stateOn" }) |field| try h.field(&s, binding, field, c.pi_js_bool(engine.context, 0));
    try h.field(&s, binding, "views", try h.set(&s));
    try h.field(&s, binding, "members", try h.map(&s));
    try h.field(&s, owned, "listeners", try h.map(&s));
    try h.field(&s, owned, "hydrationWaiters", try h.set(&s));
    try h.field(&s, owned, "pending", c.pi_js_undefined());
    try h.field(&s, owned, "applied", c.pi_js_bool(engine.context, 0));
    try h.field(&s, owned, "live", try deferred(&s));
    return s.result(binding);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .RemoteBinding);
    const prototype = try s.record();
    try js.define(engine, bindings, "RemoteBinding", try @import("native_class.zig").constructor(engine, "RemoteBinding", 2, prototype, construct, &.{bindings}));
    inline for (.{ .{ "ended", Method.ended, 0, true }, .{ "stateViews", Method.stateViews, 0, true }, .{ "wantsState", Method.wantsState, 0, true }, .{ "applied", Method.applied, 0, true }, .{ "addView", Method.addView, 1, false }, .{ "removeView", Method.removeView, 1, false }, .{ "listen", Method.listen, 2, false }, .{ "unlisten", Method.unlisten, 2, false }, .{ "inVariant", Method.inVariant, 1, false }, .{ "read", Method.read, 1, false }, .{ "whenHydrated", Method.whenHydrated, 0, false }, .{ "readable", Method.readable, 1, false }, .{ "terminalError", Method.terminalError, 0, false }, .{ "bound", Method.bound, 2, false }, .{ "shaped", Method.shaped, 2, false }, .{ "state", Method.state, 2, false }, .{ "gone", Method.gone, 1, false }, .{ "detached", Method.detached, 0, false }, .{ "close", Method.close, 0, false }, .{ "call", Method.call, 3, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], item[1] == .call);
}
