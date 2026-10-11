//! Original Source command-only getSuggestions mapping, argument callbacks and
//! pure completion adapter. Noncommand work delegates to an owned fallback.
const a = @import("native_tui_alt_frame.zig");
const Frame = a.Frame;
const js = a.js;
const c = a.c;
const awaiting = @import("native_command_source_await.zig");
const pure = @import("native_command_source_pure.zig");
const Callback = enum(c_int) { commandItem, bareName, fullNameOnly, name, filtered, findCommand };
fn has(f: *Frame, object: c.JSValue, key: []const u8) !bool {
    return js.hasKey(f.engine, object, try f.text(key));
}
fn contains(f: *Frame, text: c.JSValue, method: [*:0]const u8, key: []const u8) !bool {
    return f.truth(try f.method(text, method, &.{try f.text(key)}));
}
fn commandName(f: *Frame, command: c.JSValue) !c.JSValue {
    return f.get(command, if (try has(f, command, "name")) "name" else "value");
}
fn callbackBody(f: *Frame, kind: Callback, item: c.JSValue, capture: c.JSValue) !c.JSValue {
    switch (kind) {
        .commandItem => {
            const name = try commandName(f, item);
            const hint = if (try has(f, item, "argumentHint") and f.truth(try f.get(item, "argumentHint"))) try f.get(item, "argumentHint") else c.pi_js_undefined();
            const description = try f.get(item, "description");
            const desc = if (f.nullish(description)) try f.text("") else description;
            const full = if (f.truth(hint)) (if (f.truth(desc)) try f.concat(&.{ hint, try f.text(" — "), desc }) else hint) else desc;
            const value = try f.record();
            try f.define(value, "name", name);
            try f.define(value, "label", name);
            try f.define(value, "description", if (f.truth(full)) full else c.pi_js_undefined());
            return value;
        },
        .bareName => return if (try contains(f, try f.get(item, "name"), "startsWith", "skill:")) f.method(try f.get(item, "name"), "slice", &.{f.num(6)}) else f.get(item, "name"),
        .fullNameOnly => {
            if (!try contains(f, try f.get(item, "name"), "startsWith", "skill:")) return f.boolean(false);
            return f.boolean(!f.truth(try f.method(capture, "has", &.{item})));
        },
        .name => return f.get(item, "name"),
        .filtered => {
            const value = try f.record();
            try f.define(value, "value", try f.get(item, "name"));
            try f.define(value, "label", try f.get(item, "label"));
            if (f.truth(try f.get(item, "description"))) try f.define(value, "description", try f.get(item, "description"));
            return value;
        },
        .findCommand => return f.boolean(f.equal(try commandName(f, item), capture)),
    }
}
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    var f: Frame = .{ .engine = engine, .object = c.pi_js_undefined(), .bindings = data[0] };
    defer f.deinit();
    const value = callbackBody(&f, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), data[1]) catch |err| return a.fail(engine, err);
    return f.result(value);
}
fn arrow(f: *Frame, kind: Callback, capture: c.JSValue) !c.JSValue {
    var data = [_]c.JSValue{ f.bindings, capture };
    return f.own(try f.engine.checked(c.JS_NewCFunctionData2(f.engine.context, callback, "", 1, @intFromEnum(kind), 2, &data)));
}
fn suggestion(f: *Frame, items: c.JSValue, prefix: c.JSValue) !c.JSValue {
    const value = try f.record();
    try f.define(value, "items", items);
    try f.define(value, "prefix", prefix);
    return value;
}
fn resolved(f: *Frame, value: c.JSValue) !c.JSValue {
    return f.own(try f.engine.checked(c.JS_NewSettledPromise(f.engine.context, false, value)));
}
fn continueSuggestions(engine: *js.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    if (stage == 2) return c.JS_DupValue(engine.context, value);
    const bindings = try js.get(engine, state, "bindings");
    defer engine.freeValue(bindings);
    var f: Frame = .{ .engine = engine, .object = state, .bindings = bindings };
    defer f.deinit();
    if (stage == 1 and !f.truth(try f.method(try f.global("Array"), "isArray", &.{value}))) return c.pi_js_null();
    if (f.equal(try f.get(value, "length"), f.num(0))) return c.pi_js_null();
    return f.result(try suggestion(&f, value, try f.field("prefix")));
}
fn wait(f: *Frame, value: c.JSValue, prefix: c.JSValue, stage: c_int) !c.JSValue {
    const state = try f.record();
    try f.define(state, "bindings", f.bindings);
    try f.define(state, "prefix", prefix);
    var intrinsics: awaiting.Intrinsics = .{ .constructor = try f.get(f.bindings, "promiseConstructor"), .resolve = try f.get(f.bindings, "promiseResolve"), .then_function = try f.get(f.bindings, "promiseThen") };
    return f.own(try awaiting.continueWith(continueSuggestions, f.engine, &intrinsics, state, value, stage));
}
pub fn suggestions(f: *Frame, args: []const c.JSValue) anyerror!c.JSValue {
    const lines = a.v.arg(args, 0);
    const row = a.v.arg(args, 1);
    const col = a.v.arg(args, 2);
    const options = a.v.arg(args, 3);
    const current = try f.own(try js.getKey(f.engine, lines, row));
    const line = if (f.truth(current)) current else try f.text("");
    const before = try f.method(line, "slice", &.{ f.num(0), col });
    const at = try pure.prefix(f, &.{before}, true);
    if (f.truth(at)) return delegate(f, args);
    const command_text = try f.method(before, "trimStart", &.{});
    if (!f.truth(try f.get(options, "force")) and try contains(f, command_text, "startsWith", "/")) {
        const space = try f.method(command_text, "indexOf", &.{try f.text(" ")});
        if (f.equal(space, f.num(-1))) {
            const prefix = try f.method(command_text, "slice", &.{f.num(1)});
            const items = try f.method(try f.field("commands"), "map", &.{try arrow(f, .commandItem, c.pi_js_undefined())});
            const bare = try f.imported("fuzzyFilter", &.{ items, prefix, try arrow(f, .bareName, c.pi_js_undefined()) });
            const matches = try f.construct(try f.global("Set"), &.{bare});
            const filtered_items = try f.method(items, "filter", &.{try arrow(f, .fullNameOnly, matches)});
            const full = try f.imported("fuzzyFilter", &.{ filtered_items, prefix, try arrow(f, .name, c.pi_js_undefined()) });
            const combined = try f.copy(bare);
            var iterator = try js.Iterator.init(f.engine, full, try f.get(f.bindings, "iteratorSymbol"));
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            var index = try f.n(combined, "length");
            while (try iterator.next()) |item| {
                defer f.engine.freeValue(item);
                if (c.JS_DefinePropertyValueUint32(f.engine.context, combined, @intFromFloat(index), c.JS_DupValue(f.engine.context, item), c.JS_PROP_C_W_E) < 0) return js.capture(f.engine);
                index += 1;
            }
            const filtered = try f.method(combined, "map", &.{try arrow(f, .filtered, c.pi_js_undefined())});
            if (f.equal(try f.get(filtered, "length"), f.num(0))) return resolved(f, c.pi_js_null());
            return resolved(f, try suggestion(f, filtered, command_text));
        }
        const name = try f.method(command_text, "slice", &.{ f.num(1), space });
        const argument = try f.method(command_text, "slice", &.{try f.add(space, f.num(1))});
        const command = try f.method(try f.field("commands"), "find", &.{try arrow(f, .findCommand, name)});
        if (!f.truth(command) or !try has(f, command, "getArgumentCompletions") or !f.truth(try f.get(command, "getArgumentCompletions"))) return resolved(f, c.pi_js_null());
        return wait(f, try f.method(command, "getArgumentCompletions", &.{argument}), argument, 1);
    }
    return delegate(f, args);
}

fn delegate(f: *Frame, args: []const c.JSValue) !c.JSValue {
    const fallback = try f.get(f.bindings, "fallback");
    if (c.JS_IsNull(fallback) or c.JS_IsUndefined(fallback)) return resolved(f, c.pi_js_null());
    return wait(f, try f.method(fallback, "getSuggestions", args), c.pi_js_undefined(), 2);
}
const Method = enum(c_int) { getSuggestions, applyCompletion, shouldTriggerFileCompletion };
fn call(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    var f: Frame = .{ .engine = engine, .object = receiver, .bindings = data[0] };
    defer f.deinit();
    const method: Method = @enumFromInt(magic);
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const holder = js.get(engine, data[0], "holder") catch |err| return a.fail(engine, err);
    defer engine.freeValue(holder);
    if (c.JS_IsObject(holder)) {
        const active = js.get(engine, holder, "active") catch |err| return a.fail(engine, err);
        defer engine.freeValue(active);
        if (c.JS_ToBool(engine.context, active) == 0)
            return if (method == .getSuggestions) c.JS_NewSettledPromise(engine.context, false, c.pi_js_null()) else c.pi_js_null();
    }
    const result = (switch (method) {
        .getSuggestions => suggestions(&f, args),
        .applyCompletion => pure.applyCompletion(&f, args),
        .shouldTriggerFileCompletion => pure.trigger(&f, args),
    }) catch |err| {
        const exception = a.fail(engine, err);
        if (method != .getSuggestions) return exception;
        const reason = c.JS_GetException(engine.context);
        defer engine.freeValue(reason);
        return c.JS_NewSettledPromise(engine.context, true, reason);
    };
    return f.result(result);
}
fn commands(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    const snapshot = js.get(engine, data[0], "snapshot") catch |err| return a.fail(engine, err);
    defer engine.freeValue(snapshot);
    return js.get(engine, snapshot, "mainAutocompleteCommands") catch |err| a.fail(engine, err);
}
pub fn create(engine: *js.Engine, metadata: c.JSValue, fallback: c.JSValue) !c.JSValue {
    const object = try js.object(engine);
    errdefer engine.freeValue(object);
    try js.define(engine, object, "commands", c.JS_DupValue(engine.context, metadata));
    try install(engine, object, fallback, c.pi_js_undefined());
    return object;
}
pub fn createForHolder(engine: *js.Engine, holder: c.JSValue, fallback: c.JSValue) !c.JSValue {
    const object = try js.object(engine);
    errdefer engine.freeValue(object);
    var capture = [_]c.JSValue{holder};
    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, commands, "get commands", 0, 0, 1, &capture));
    const atom = c.JS_NewAtom(engine.context, "commands");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, object, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    try install(engine, object, fallback, holder);
    return object;
}
fn install(engine: *js.Engine, object: c.JSValue, fallback: c.JSValue, holder: c.JSValue) !void {
    const bindings = try js.object(engine);
    defer engine.freeValue(bindings);
    try pure.initialize(engine, bindings);
    try js.define(engine, bindings, "fallback", c.JS_DupValue(engine.context, fallback));
    try js.define(engine, bindings, "holder", c.JS_DupValue(engine.context, holder));
    try @import("native_fuzzy.zig").install(engine, bindings);
    var promises = try awaiting.Intrinsics.init(engine);
    defer promises.deinit(engine);
    inline for (.{ .{ "promiseConstructor", promises.constructor }, .{ "promiseResolve", promises.resolve }, .{ "promiseThen", promises.then_function } }) |entry| try js.define(engine, bindings, entry[0], c.JS_DupValue(engine.context, entry[1]));
    inline for (.{ .{ "getSuggestions", Method.getSuggestions, 4 }, .{ "applyCompletion", Method.applyCompletion, 5 }, .{ "shouldTriggerFileCompletion", Method.shouldTriggerFileCompletion, 3 } }) |entry| {
        var data = [_]c.JSValue{bindings};
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, call, entry[0], entry[2], @intFromEnum(entry[1]), 1, &data));
        if (entry[1] == .getSuggestions) {
            const prototype = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
            defer engine.freeValue(prototype);
            if (c.JS_SetPrototype(engine.context, function, prototype) < 0) {
                engine.freeValue(function);
                return js.capture(engine);
            }
        }
        if (c.JS_DefinePropertyValueStr(engine.context, object, entry[0], function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
