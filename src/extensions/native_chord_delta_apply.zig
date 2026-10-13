//! Actual decoded Chord operations and final-result-only immutable batch replay.
const h = @import("native_chord_host_values.zig");
const codec = @import("native_chord_delta_codec.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Mode = enum(c_int) { mutable, immutable, batches, validate };
fn array(s: *Scope, value: c.JSValue) !bool {
    return c.JS_ToBool(s.engine.context, try s.builtin("Array", "isArray", &.{value})) != 0;
}
fn container(s: *Scope, value: c.JSValue) bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(s.engine.context, value);
}
fn natural(s: *Scope, value: c.JSValue) !bool {
    if (c.JS_ToBool(s.engine.context, try s.builtin("Number", "isInteger", &.{value})) == 0) return false;
    var number: f64 = 0;
    if (c.JS_ToFloat64(s.engine.context, &number, value) < 0) return js.capture(s.engine);
    return number >= 0;
}
fn typeFailure(s: *Scope, message: []const u8) anyerror {
    _ = try h.typeError(s, &.{try s.text(message)});
    unreachable;
}
fn pathFailure(s: *Scope, api: c.JSValue, value: c.JSValue, unsafe: bool) anyerror {
    _ = try h.throwValue(s, try h.construct(s, api, if (unsafe) "UnsafePathError" else "PathError", &.{value}));
    unreachable;
}
fn pathArg(s: *Scope, api: c.JSValue, path: c.JSValue, nonempty: bool) !void {
    if (!try array(s, path)) return typeFailure(s, "path is not an array");
    if (nonempty and try h.length(s, path) == 0) return typeFailure(s, "path is empty");
    try codec.safePath(s, api, path);
}
pub fn validOp(s: *Scope, api: c.JSValue, op: c.JSValue) !void {
    if (!try array(s, op) or try h.length(s, op) == 0) return typeFailure(s, "op is not a tuple");
    const verb = try s.at(op, 0);
    if (try s.equal(verb, "r")) {
        if (try h.length(s, op) != 2) return typeFailure(s, "r arity");
    } else if (try s.equal(verb, "s") or try s.equal(verb, "d")) {
        const deletion = try s.equal(verb, "d");
        if (try h.length(s, op) != (if (deletion) @as(u32, 2) else 3)) return typeFailure(s, if (deletion) "d arity" else "s arity");
        try pathArg(s, api, try s.at(op, 1), true);
    } else if (try s.equal(verb, "a") or try s.equal(verb, "t")) {
        const append = try s.equal(verb, "a");
        if (try h.length(s, op) != 3 or (if (append) !c.JS_IsString(try s.at(op, 2)) else !try natural(s, try s.at(op, 2)))) return typeFailure(s, if (append) "a shape" else "t shape");
        try pathArg(s, api, try s.at(op, 1), true);
    } else if (try s.equal(verb, "p")) {
        if (try h.length(s, op) != 5) return typeFailure(s, "p arity");
        try pathArg(s, api, try s.at(op, 1), false);
        if (!try natural(s, try s.at(op, 2))) return typeFailure(s, "p index");
        if (!try natural(s, try s.at(op, 3))) return typeFailure(s, "p remove");
        if (!try array(s, try s.at(op, 4))) return typeFailure(s, "p items");
    } else if (try s.equal(verb, "m")) {
        if (try h.length(s, op) != 3) return typeFailure(s, "m arity");
        try pathArg(s, api, try s.at(op, 1), false);
        try codec.permutation(s, try s.at(op, 2));
    } else {
        const text = try s.keep(try js.call(s.engine, try s.keep(try js.global(s.engine, "String")), c.pi_js_undefined(), &.{verb}));
        _ = try h.typeError(s, &.{ try s.text("unknown op verb: "), text });
    }
}
fn own(s: *Scope, target: c.JSValue, key: c.JSValue) !bool {
    return c.JS_ToBool(s.engine.context, try s.builtin("Object", "hasOwn", &.{ target, key })) != 0;
}
fn define(s: *Scope, target: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    const object = try s.keep(try js.global(s.engine, "Object"));
    const function = try s.get(object, "defineProperty");
    const descriptor = try s.record();
    try h.field(s, descriptor, "value", value);
    inline for (.{ "writable", "enumerable", "configurable" }) |name| try h.field(s, descriptor, name, c.pi_js_bool(s.engine.context, 1));
    _ = try s.keep(try js.call(s.engine, function, object, &.{ target, key, descriptor }));
}
fn resolveValue(s: *Scope, api: c.JSValue, initial: c.JSValue, path: c.JSValue, require_container: bool) !c.JSValue {
    var node = initial;
    var iterator = try js.Iterator.init(s.engine, path, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |segment| {
        defer s.engine.freeValue(segment);
        if (!container(s, node)) return pathFailure(s, api, path, false);
        if (try array(s, node) and !c.JS_IsNumber(segment)) return pathFailure(s, api, segment, true);
        if (!try own(s, node, segment)) return pathFailure(s, api, path, false);
        node = try s.key(node, segment);
    }
    if (require_container and !container(s, node)) return pathFailure(s, api, path, false);
    return node;
}
fn copy(s: *Scope, api: c.JSValue, value: c.JSValue, path: c.JSValue) !c.JSValue {
    if (try array(s, value)) return h.invoke(s, value, "slice", &.{});
    if (!container(s, value)) return pathFailure(s, api, path, false);
    const prototype = try s.builtin("Object", "getPrototypeOf", &.{value});
    const parent = if (c.JS_IsNull(prototype)) prototype else try s.get(try s.keep(try js.global(s.engine, "Object")), "prototype");
    const result = try s.builtin("Object", "create", &.{parent});
    var keys = try js.Iterator.init(s.engine, try s.keys(value), try h.iteratorSymbol(s));
    defer keys.deinit();
    errdefer keys.closePreserving();
    while (try keys.next()) |key| {
        defer s.engine.freeValue(key);
        try define(s, result, key, try s.key(value, key));
    }
    return result;
}
fn copyContainers(s: *Scope, api: c.JSValue, initial: c.JSValue, path: c.JSValue, owned: c.JSValue) !c.JSValue {
    if (!container(s, initial)) return pathFailure(s, api, path, false);
    const root = if (c.JS_ToBool(s.engine.context, try h.invoke(s, owned, "has", &.{initial})) != 0) initial else cloned: {
        const cloned = try copy(s, api, initial, path);
        _ = try h.invoke(s, owned, "add", &.{cloned});
        break :cloned cloned;
    };
    var destination = root;
    var iterator = try js.Iterator.init(s.engine, path, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |segment| {
        defer s.engine.freeValue(segment);
        if (!try own(s, destination, segment)) return pathFailure(s, api, path, false);
        if (try array(s, destination) and !c.JS_IsNumber(segment)) return pathFailure(s, api, segment, true);
        const child = try s.key(destination, segment);
        if (!container(s, child)) return pathFailure(s, api, path, false);
        if (c.JS_ToBool(s.engine.context, try h.invoke(s, owned, "has", &.{child})) != 0) {
            destination = child;
            continue;
        }
        const cloned = try copy(s, api, child, path);
        try define(s, destination, segment, cloned);
        _ = try h.invoke(s, owned, "add", &.{cloned});
        destination = cloned;
    }
    return root;
}
fn appendCopy(s: *Scope, api: c.JSValue, root: c.JSValue, op: c.JSValue, owned: c.JSValue) !c.JSValue {
    // Source destructures five fields and closes a custom iterator afterward.
    var fields: [5]c.JSValue = undefined;
    var tuple = try js.Iterator.init(s.engine, op, try h.iteratorSymbol(s));
    defer tuple.deinit();
    errdefer tuple.closePreserving();
    for (&fields) |*field| field.* = if (tuple.closed) c.pi_js_undefined() else if (try tuple.next()) |value| try s.keep(value) else c.pi_js_undefined();
    try tuple.close();
    const path = fields[1];
    const index = fields[2];
    const deleted = fields[3];
    const items = fields[4];
    if (!c.JS_IsStrictEqual(s.engine.context, deleted, c.JS_NewInt32(s.engine.context, 0))) return c.pi_js_undefined();
    var target = root;
    var iterator = try js.Iterator.init(s.engine, path, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |segment| {
        defer s.engine.freeValue(segment);
        const valid = if (c.JS_IsString(segment)) c.JS_ToBool(s.engine.context, try h.invoke(s, try s.get(api, "RESERVED_SEGMENTS"), "has", &.{segment})) == 0 and container(s, target) and !try array(s, target) else try natural(s, segment) and try array(s, target);
        if (!valid or !try own(s, target, segment)) return c.pi_js_undefined();
        target = try s.key(target, segment);
    }
    if (!try array(s, target) or c.JS_ToBool(s.engine.context, try h.invoke(s, owned, "has", &.{target})) != 0 or !c.JS_IsStrictEqual(s.engine.context, index, try s.get(target, "length"))) return c.pi_js_undefined();
    const appended = try h.invoke(s, target, "concat", &.{items});
    _ = try h.invoke(s, owned, "add", &.{appended});
    if (try h.length(s, path) == 0) return appended;
    const parent_path = try h.invoke(s, path, "slice", &.{ c.JS_NewInt32(s.engine.context, 0), c.JS_NewInt32(s.engine.context, -1) });
    const copied = try copyContainers(s, api, root, parent_path, owned);
    try define(s, try resolveValue(s, api, copied, parent_path, true), try s.at(path, try h.length(s, path) - 1), appended);
    return copied;
}
fn applyOne(s: *Scope, api: c.JSValue, initial: c.JSValue, op: c.JSValue) !c.JSValue {
    try validOp(s, api, op);
    const verb = try s.at(op, 0);
    if (try s.equal(verb, "r")) return s.at(op, 1);
    const path = try s.at(op, 1);
    try codec.safePath(s, api, path);
    const splice = try s.equal(verb, "p");
    if (splice or try s.equal(verb, "m")) {
        const target = if (try h.length(s, path) == 0) initial else try resolveValue(s, api, initial, path, true);
        if (!try array(s, target)) return pathFailure(s, api, path, false);
        if (splice) {
            _ = try h.invoke(s, target, "splice", &.{ try s.at(op, 2), try s.at(op, 3) });
            var offset: u32 = 0;
            while (offset < try h.length(s, try s.at(op, 4))) : (offset += 10000) {
                const function = try s.get(target, "splice");
                const raw = try s.at(op, 2);
                var at: f64 = 0;
                if (c.JS_ToFloat64(s.engine.context, &at, raw) < 0) return js.capture(s.engine);
                const arguments = try s.list();
                try js.push(s.engine, arguments, c.JS_NewFloat64(s.engine.context, at + @as(f64, @floatFromInt(offset))));
                try js.push(s.engine, arguments, c.JS_NewInt32(s.engine.context, 0));
                const items = try h.invoke(s, try s.at(op, 4), "slice", &.{ c.JS_NewUint32(s.engine.context, offset), c.JS_NewFloat64(s.engine.context, @as(f64, @floatFromInt(offset)) + 10000) });
                var expanded = try js.Iterator.init(s.engine, items, try h.iteratorSymbol(s));
                defer expanded.deinit();
                errdefer expanded.closePreserving();
                while (try expanded.next()) |item| {
                    defer s.engine.freeValue(item);
                    try js.push(s.engine, arguments, item);
                }
                _ = try s.keep(try @import("native_iterator_spread.zig").call(s.engine, target, function, arguments));
            }
        } else {
            const order = try s.at(op, 2);
            if (!c.JS_IsStrictEqual(s.engine.context, try s.get(target, "length"), try s.get(order, "length"))) return pathFailure(s, api, path, false);
            const previous = try h.invoke(s, target, "slice", &.{});
            var index: u32 = 0;
            while (index < try h.length(s, try s.at(op, 2))) : (index += 1) try js.setKey(s.engine, target, c.JS_NewUint32(s.engine.context, index), try s.key(previous, try s.at(try s.at(op, 2), index)));
        }
        return initial;
    }
    const parent_path = try h.invoke(s, path, "slice", &.{ c.JS_NewInt32(s.engine.context, 0), c.JS_NewInt32(s.engine.context, -1) });
    const parent = try resolveValue(s, api, initial, parent_path, true);
    const key = try s.at(path, try h.length(s, path) - 1);
    const parent_array = try array(s, parent);
    var index: f64 = 0;
    var count: f64 = 0;
    if (parent_array) {
        if (!c.JS_IsNumber(key)) return pathFailure(s, api, key, true);
        if (c.JS_ToFloat64(s.engine.context, &index, key) < 0 or c.JS_ToFloat64(s.engine.context, &count, try s.get(parent, "length")) < 0) return js.capture(s.engine);
        if (index > count) return pathFailure(s, api, key, true);
    }
    if (try s.equal(verb, "s")) {
        try define(s, parent, key, try s.at(op, 2));
    } else if (try s.equal(verb, "d")) {
        if (parent_array) {
            if (index >= count) return pathFailure(s, api, path, false);
            _ = try h.invoke(s, parent, "splice", &.{ key, c.JS_NewInt32(s.engine.context, 1) });
        } else {
            const atom = try js.atom(s.engine, key);
            defer c.JS_FreeAtom(s.engine.context, atom);
            if (c.JS_DeleteProperty(s.engine.context, parent, atom, c.JS_PROP_THROW) < 0) return js.capture(s.engine);
        }
    } else {
        const current = if (try own(s, parent, key)) try s.key(parent, key) else c.pi_js_undefined();
        if (!c.JS_IsString(current)) return pathFailure(s, api, path, false);
        const value = if (try s.equal(verb, "a")) try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ current, try s.at(op, 2) })) else try h.invoke(s, current, "slice", &.{try s.at(op, 2)});
        try define(s, parent, key, value);
    }
    return initial;
}
pub fn apply(engine: *h.Engine, api: c.JSValue, initial: c.JSValue, operations: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var root = initial;
    var iterator = try js.Iterator.init(engine, operations, try h.iteratorSymbol(&s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |op| {
        defer engine.freeValue(op);
        root = try applyOne(&s, api, root, op);
    }
    return s.result(root);
}
pub fn immutableBatches(engine: *h.Engine, api: c.JSValue, initial: c.JSValue, batches: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var root = initial;
    const owned = try s.keep(try js.builtin(engine, "WeakSet", &.{}));
    const symbol = try h.iteratorSymbol(&s);
    var batch_iterator = try js.Iterator.init(engine, batches, symbol);
    defer batch_iterator.deinit();
    errdefer batch_iterator.closePreserving();
    while (try batch_iterator.next()) |operations| {
        defer engine.freeValue(operations);
        var iterator = try js.Iterator.init(engine, operations, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |op| {
            defer engine.freeValue(op);
            try validOp(&s, api, op);
            const verb = try s.at(op, 0);
            if (try s.equal(verb, "r")) {
                root = try s.at(op, 1);
                continue;
            }
            if (try s.equal(verb, "p")) {
                const appended = try appendCopy(&s, api, root, op, owned);
                if (!c.JS_IsUndefined(appended)) {
                    root = appended;
                    continue;
                }
            }
            const path = try s.at(op, 1);
            const copied_path = if (try s.equal(verb, "p") or try s.equal(verb, "m")) path else try h.invoke(&s, path, "slice", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewInt32(engine.context, -1) });
            root = try copyContainers(&s, api, root, copied_path, owned);
            root = try applyOne(&s, api, root, op);
        }
    }
    return s.result(root);
}
pub fn immutable(engine: *h.Engine, api: c.JSValue, initial: c.JSValue, operations: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const batches = try s.list();
    try js.push(engine, batches, operations);
    return immutableBatches(engine, api, initial, batches);
}
fn invoke(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, captures[1]) < 0) return js.capture(engine);
    const mode: Mode = @enumFromInt(raw);
    if (mode == .validate) {
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        try validOp(&s, captures[0], h.arg(args, 0));
        return c.pi_js_undefined();
    }
    return switch (mode) {
        .mutable => apply(engine, captures[0], h.arg(args, 0), h.arg(args, 1)),
        .immutable => immutable(engine, captures[0], h.arg(args, 0), h.arg(args, 1)),
        .batches => immutableBatches(engine, captures[0], h.arg(args, 0), h.arg(args, 1)),
        .validate => unreachable,
    };
}
pub fn install(engine: *h.Engine, api: c.JSValue) !void {
    inline for (.{ .{ "apply", Mode.mutable, 2 }, .{ "applyImmutable", Mode.immutable, 2 }, .{ "applyImmutableBatches", Mode.batches, 2 }, .{ "assertValidOp", Mode.validate, 1 } }) |entry| try js.define(engine, api, entry[0], try @import("native_node_function.zig").create(engine, entry[0], entry[2], invoke, &.{ api, c.JS_NewInt32(engine.context, @intFromEnum(entry[1])) }));
}
