//! Pinned SDK's TypeScript __asyncGenerator queue and live Promise operations.
//! Its iterator is an ordinary object in Source; EventStream uses the real VM
//! AsyncGenerator separately. No synthetic ticks or message snapshots occur.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub const Verb = enum { next, thrown, returned };
pub const Action = union(enum) { awaited: c.JSValue, yielded: c.JSValue, complete: c.JSValue, thrown: c.JSValue };
pub const Body = *const fn (*v.em.Engine, c.JSValue, Verb, c.JSValue) anyerror!Action;
fn name(comptime verb: Verb) [*:0]const u8 {
    return switch (verb) {
        .next => "next",
        .thrown => "throw",
        .returned => "return",
    };
}
pub fn create(engine: *v.em.Engine, state: c.JSValue, comptime body: Body) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const symbol = try scope.get(try scope.global("Symbol"), "asyncIterator");
    if (!scope.truthy(symbol)) return v.js.typeError(engine, "Symbol.asyncIterator is not defined.");
    const owner = try scope.object();
    try scope.put(owner, "state", state);
    try scope.put(owner, "queue", try scope.array());
    try scope.put(owner, "finished", c.pi_js_bool(engine.context, 0));
    inline for (.{ Verb.next, Verb.thrown }) |verb| {
        const Continued = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var row: Scope = .{ .engine = host };
                defer row.deinit();
                try resumeQueue(&row, roots[0], verb, if (args.len > 0) args[0] else c.pi_js_undefined(), body);
                return c.pi_js_undefined();
            }
        };
        try scope.put(owner, if (verb == .next) "fulfill" else "reject", try scope.own(try @import("native_node_function.zig").create(engine, if (verb == .next) "fulfill" else "reject", 1, Continued.call, &.{owner})));
    }
    const selected = try scope.global("AsyncIterator");
    const parent = try scope.get(if (c.JS_IsFunction(engine.context, selected)) selected else try scope.global("Object"), "prototype");
    const iterator = try scope.invoke(try scope.global("Object"), "create", &.{parent});
    inline for (.{ Verb.next, Verb.thrown, Verb.returned }) |verb| {
        const Enqueue = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var row: Scope = .{ .engine = host };
                defer row.deinit();
                return enqueue(&row, roots[0], verb, if (args.len > 0) args[0] else c.pi_js_undefined(), body);
            }
        };
        const method = try scope.own(try @import("native_node_function.zig").create(engine, "", 1, Enqueue.call, &.{owner}));
        if (verb == .returned) {
            const Return = struct {
                fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                    var row: Scope = .{ .engine = host };
                    defer row.deinit();
                    const resolved = try row.invoke(try row.global("Promise"), "resolve", &.{if (args.len > 0) args[0] else c.pi_js_undefined()});
                    return c.JS_DupValue(host.context, try row.invoke(resolved, "then", &.{ roots[1], try row.get(roots[0], "reject") }));
                }
            };
            try scope.set(iterator, name(verb), try scope.own(try @import("native_node_function.zig").create(engine, "", 1, Return.call, &.{ owner, method })));
        } else try scope.set(iterator, name(verb), method);
    }
    const Identity = struct {
        fn call(host: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return c.JS_DupValue(host.context, receiver);
        }
    };
    try v.js.setKey(engine, iterator, symbol, try scope.own(try @import("native_node_function.zig").create(engine, "", 0, Identity.call, &.{})));
    return c.JS_DupValue(engine.context, iterator);
}
fn enqueue(scope: *Scope, owner: c.JSValue, comptime verb: Verb, input: c.JSValue, comptime body: Body) !c.JSValue {
    const Executor = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            const entry = try row.array();
            try row.index(entry, 0, try row.text(@import("std").mem.span(name(verb))));
            try row.index(entry, 1, roots[1]);
            try row.index(entry, 2, if (args.len > 0) args[0] else c.pi_js_undefined());
            try row.index(entry, 3, if (args.len > 1) args[1] else c.pi_js_undefined());
            const count = try row.invoke(try row.get(roots[0], "queue"), "push", &.{entry});
            if (!try @import("native_image_arithmetic.zig").compare(host, .greater, count, c.JS_NewInt32(host.context, 1))) try resumeQueue(&row, roots[0], verb, roots[1], body);
            return c.pi_js_undefined();
        }
    };
    const executor = try scope.own(try @import("native_node_function.zig").create(scope.engine, "", 2, Executor.call, &.{ owner, input }));
    return v.js.builtin(scope.engine, "Promise", &.{executor});
}
fn resumeQueue(scope: *Scope, owner: c.JSValue, verb: Verb, input: c.JSValue, comptime body: Body) anyerror!void {
    step(scope, owner, verb, input, body) catch |err| {
        const reason = try scope.own(@import("native_agent_async.zig").reason(scope.engine, err));
        try settle(scope, owner, reason, true, body);
    };
}
fn step(scope: *Scope, owner: c.JSValue, verb: Verb, input: c.JSValue, comptime body: Body) !void {
    const finished = scope.truthy(try scope.get(owner, "finished"));
    const action: Action = if (finished) switch (verb) {
        .next => .{ .complete = c.pi_js_undefined() },
        .returned => .{ .complete = c.JS_DupValue(scope.engine.context, input) },
        .thrown => .{ .thrown = c.JS_DupValue(scope.engine.context, input) },
    } else body(scope.engine, try scope.get(owner, "state"), verb, input) catch |err| failure: {
        try scope.put(owner, "finished", c.pi_js_bool(scope.engine.context, 1));
        break :failure .{ .thrown = @import("native_agent_async.zig").reason(scope.engine, err) };
    };
    switch (action) {
        .awaited => |value| {
            defer scope.engine.freeValue(value);
            const promise = try scope.invoke(try scope.global("Promise"), "resolve", &.{value});
            _ = try scope.invoke(promise, "then", &.{ try scope.get(owner, "fulfill"), try scope.get(owner, "reject") });
        },
        .yielded, .complete => |value| {
            defer scope.engine.freeValue(value);
            const done = @import("std").meta.activeTag(action) == .complete;
            const result = try scope.object();
            try scope.put(result, "value", value);
            try scope.put(result, "done", c.pi_js_bool(scope.engine.context, @intFromBool(done)));
            if (done) try scope.put(owner, "finished", c.pi_js_bool(scope.engine.context, 1));
            try settle(scope, owner, result, false, body);
        },
        .thrown => |value| {
            defer scope.engine.freeValue(value);
            try scope.put(owner, "finished", c.pi_js_bool(scope.engine.context, 1));
            try settle(scope, owner, value, true, body);
        },
    }
}
fn settle(scope: *Scope, owner: c.JSValue, value: c.JSValue, rejected: bool, comptime body: Body) !void {
    const queue = try scope.get(owner, "queue");
    const entry = try v.at(scope, queue, 0);
    _ = try scope.call(try v.at(scope, entry, if (rejected) 3 else 2), c.pi_js_undefined(), &.{value});
    _ = try scope.invoke(queue, "shift", &.{});
    if (scope.truthy(try scope.get(queue, "length"))) {
        const next = try v.at(scope, queue, 0);
        const operation = try v.at(scope, next, 0);
        const verb: Verb = if (try v.eq(scope, operation, "throw")) .thrown else if (try v.eq(scope, operation, "return")) .returned else .next;
        try resumeQueue(scope, owner, verb, try v.at(scope, next, 1), body);
    }
}
