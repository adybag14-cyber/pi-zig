// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual internal/errors argument messages. Captured primitive methods are
//! installed at the genuine Node bootstrap. All later getters and iterator
//! heads retain the same Source lifetimes through the actual message call.
const a = @import("native_node_argument_values.zig");
const v = a.v;
const c = a.c;
const Scope = a.Scope;
const functions = @import("native_node_module_callable.zig");
const Iterator = @import("native_public_values.zig").Iterator;
const TypeFrame = a.frames.Frame(enum { name, expected, actual, message, kind, types, instances, other, value, position });
const ValueFrame = a.frames.Frame(enum { name, value, reason, inspected, kind });
pub const Inputs = struct { internal_inspect: c.JSValue, assert: c.JSValue, determine_specific_type: c.JSValue };
pub const Exports = struct {
    invalid_arg_type: c.JSValue,
    invalid_arg_value: c.JSValue,
    internal_assertion: c.JSValue,
    pub fn deinit(self: Exports, engine: *v.em.Engine) void {
        var completion = a.owned.Completion.initVoid(engine, {});
        completion.release(self.invalid_arg_type); completion.release(self.invalid_arg_value);
        completion.release(self.internal_assertion); completion.finishVoid() catch {};
    }
};
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Exports {
    var s = Scope.init(engine);
    var output = [_]c.JSValue{c.pi_js_undefined()} ** 3;
    var failure: ?anyerror = null;
    if (createBody(&s, inputs)) |result| output = result else |err| failure = err;
    try s.boundary.finishMany(failure, &s.values, &output);
    return .{ .invalid_arg_type = output[0], .invalid_arg_value = output[1], .internal_assertion = output[2] };
}
fn createBody(s: *Scope, inputs: Inputs) ![3]c.JSValue {
    try s.pending();
    if (!c.JS_IsObject(inputs.internal_inspect) or !c.JS_IsFunction(s.engine.context, inputs.assert) or
        !c.JS_IsFunction(s.engine.context, inputs.determine_specific_type)) return error.ActualArgumentMessageAuthoritiesRequired;
    const roots = try s.objectProto(c.pi_js_null());
    try s.put(roots, "inspect", inputs.internal_inspect);
    try s.put(roots, "assert", inputs.assert);
    try s.put(roots, "specific", inputs.determine_specific_type);
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    const array = try s.get(global, "Array");
    const arrays = try s.get(array, "prototype");
    try s.put(roots, "isArray", try s.get(array, "isArray"));
    inline for (.{ .{ "includes", "includes" }, .{ "indexOf", "indexOf" }, .{ "push", "push" },
        .{ "splice", "splice" }, .{ "arraySlice", "slice" }, .{ "join", "join" } }) |pair|
        try s.put(roots, pair[0], try s.get(arrays, pair[1]));
    const strings = try s.get(try s.get(global, "String"), "prototype");
    inline for (.{ .{ "endsWith", "endsWith" }, .{ "stringIncludes", "includes" },
        .{ "lower", "toLowerCase" }, .{ "stringSlice", "slice" } }) |pair|
        try s.put(roots, pair[0], try s.get(strings, pair[1]));
    const regex = try s.construct(s.engine.intrinsic_regexp_constructor, &.{try s.text("^[A-Z][a-zA-Z0-9]*$")});
    try s.put(roots, "classRegex", regex);
    try s.put(roots, "exec", try s.get(try s.get(try s.get(global, "RegExp"), "prototype"), "exec"));
    const known_types = try a.array(s);
    inline for (.{ "string", "function", "number", "object", "Function", "Object", "boolean", "bigint", "symbol" }, 0..) |name, position|
        try a.index(s, known_types, @intCast(position), try s.text(name));
    try s.put(roots, "types", known_types);
    const type_message = try s.own(try functions.create(s.engine, "", 3, false, typeCall, &.{roots}));
    const value_message = try s.own(try functions.create(s.engine, "", 2, false, valueCall, &.{roots}));
    const assertion_message = try s.own(try functions.create(s.engine, "", 1, false, assertionCall, &.{}));
    return .{ a.duplicate(s.engine, type_message), a.duplicate(s.engine, value_message), a.duplicate(s.engine, assertion_message) };
}
fn methodBody(s: *Scope, roots: c.JSValue, name: [*:0]const u8, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(try s.get(roots, name), receiver, args));
}
fn method(engine: *v.em.Engine, roots: c.JSValue, name: [*:0]const u8, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return a.expression(engine, methodBody, .{roots, name, receiver, args});
}
fn methodBoolean(s: *Scope, roots: c.JSValue, name: [*:0]const u8, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const result = try s.own(try method(s.engine, roots, name, receiver, args));
    return a.boolean(s, s.truthy(result));
}
fn literalMethodBoolean(s: *Scope, roots: c.JSValue, name: [*:0]const u8, receiver: c.JSValue, literal: []const u8) !c.JSValue {
    return methodBoolean(s, roots, name, receiver, &.{try s.text(literal)});
}
fn assertBody(s: *Scope, roots: c.JSValue, valid: bool, message: []const u8) !c.JSValue {
    _ = try s.own(try method(s.engine, roots, "assert", c.pi_js_undefined(), &.{a.boolean(s, valid), try s.text(message)}));
    return c.pi_js_undefined();
}
fn assertion(engine: *v.em.Engine, roots: c.JSValue, valid: bool, message: []const u8) !void {
    _ = try a.expression(engine, assertBody, .{roots, valid, message});
}
fn arrayBody(s: *Scope) !c.JSValue { return a.duplicate(s.engine, try a.array(s)); }
fn wrapExpected(s: *Scope, value: c.JSValue) !c.JSValue {
    const array = try a.array(s); try a.index(s, array, 0, value); return a.duplicate(s.engine, array);
}
fn textBody(s: *Scope, literal: []const u8) !c.JSValue { return a.duplicate(s.engine, try s.text(literal)); }
fn appendText(s: *Scope, previous: c.JSValue, literal: []const u8) !c.JSValue {
    return a.duplicate(s.engine, try a.add(s, previous, try s.text(literal)));
}
fn lengthGreater(s: *Scope, receiver: c.JSValue, count: i32) !c.JSValue {
    return a.boolean(s, s.truthy(try s.binary(6, try s.get(receiver, "length"), c.JS_NewInt32(s.engine.context, count))));
}
fn indexText(s: *Scope, receiver: c.JSValue, index: u32) !c.JSValue {
    return a.duplicate(s.engine, try s.toString(try s.getKey(receiver, c.JS_NewUint32(s.engine.context, index))));
}
fn formatBranch(s: *Scope, receiver: c.JSValue) !c.JSValue {
    const length = try s.get(receiver, "length");
    inline for (0..4) |count| if (s.equal(length, c.JS_NewInt32(s.engine.context, count)))
        return c.JS_NewInt32(s.engine.context, count);
    return c.JS_NewInt32(s.engine.context, 4);
}
fn joinedPrefix(s: *Scope, roots: c.JSValue, receiver: c.JSValue) !c.JSValue {
    const prefix = try s.own(try method(s.engine, roots, "arraySlice", receiver,
        &.{c.JS_NewInt32(s.engine.context, 0), c.JS_NewInt32(s.engine.context, -1)}));
    return method(s.engine, roots, "join", prefix, &.{try s.text(", ")});
}
fn prefixText(s: *Scope, roots: c.JSValue, receiver: c.JSValue) !c.JSValue {
    const joined = try s.own(try a.expression(s.engine, joinedPrefix, .{roots, receiver}));
    // The returned call operand retires at its template ToString, before
    // the final array.length / computed-index expression begins.
    return a.duplicate(s.engine, try s.toString(joined));
}
fn lastKey(s: *Scope, receiver: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.binary(1, try s.get(receiver, "length"), c.JS_NewInt32(s.engine.context, 1)));
}
fn lastText(s: *Scope, receiver: c.JSValue) !c.JSValue {
    const key = try s.own(try a.expression(s.engine, lastKey, .{receiver}));
    return a.duplicate(s.engine, try s.toString(try s.getKey(receiver, key)));
}
fn formatList(s: *Scope, roots: c.JSValue, receiver: c.JSValue) !c.JSValue {
    const branch = try a.expression(s.engine, formatBranch, .{receiver});
    if (s.equal(branch, c.JS_NewInt32(s.engine.context, 0))) return a.duplicate(s.engine, try s.text(""));
    if (s.equal(branch, c.JS_NewInt32(s.engine.context, 4))) {
        const joined = try s.own(try a.expression(s.engine, prefixText, .{roots, receiver}));
        var result = try a.add(s, joined, try s.text(", or "));
        const last = try s.own(try a.expression(s.engine, lastText, .{receiver}));
        result = try a.add(s, result, last);
        return a.duplicate(s.engine, result);
    }
    var result = try s.own(try a.expression(s.engine, indexText, .{receiver, @as(u32, 0)}));
    if (s.equal(branch, c.JS_NewInt32(s.engine.context, 1))) return a.duplicate(s.engine, result);
    result = try a.add(s, result, try s.text(if (s.equal(branch, c.JS_NewInt32(s.engine.context, 2))) " or " else ", "));
    result = try a.add(s, result, try s.own(try a.expression(s.engine, indexText, .{receiver, @as(u32, 1)})));
    if (s.equal(branch, c.JS_NewInt32(s.engine.context, 2))) return a.duplicate(s.engine, result);
    result = try a.add(s, result, try s.text(", or "));
    result = try a.add(s, result, try s.own(try a.expression(s.engine, indexText, .{receiver, @as(u32, 2)})));
    return a.duplicate(s.engine, result);
}
fn namedArgument(s: *Scope, previous: c.JSValue, name: c.JSValue) !c.JSValue {
    const suffix = try a.add(s, try s.toString(name), try s.text(" "));
    return a.duplicate(s.engine, try a.add(s, previous, suffix));
}
fn namedProperty(s: *Scope, previous: c.JSValue, name: c.JSValue, kind: c.JSValue) !c.JSValue {
    var suffix = try a.add(s, try s.text("\""), try s.toString(name));
    suffix = try a.add(s, suffix, try s.text("\" "));
    suffix = try a.add(s, suffix, try s.toString(kind));
    suffix = try a.add(s, suffix, try s.text(" "));
    return a.duplicate(s.engine, try a.add(s, previous, suffix));
}
fn knownType(s: *Scope, roots: c.JSValue, value: c.JSValue) !c.JSValue {
    return methodBoolean(s, roots, "includes", try s.get(roots, "types"), &.{value});
}
fn classType(s: *Scope, roots: c.JSValue, value: c.JSValue) !c.JSValue {
    const result = try s.own(try method(s.engine, roots, "exec", try s.get(roots, "classRegex"), &.{value}));
    return a.boolean(s, !c.JS_IsNull(result));
}
fn pushLower(s: *Scope, roots: c.JSValue, receiver: c.JSValue, value: c.JSValue) !c.JSValue {
    const lower = try s.own(try method(s.engine, roots, "lower", value, &.{}));
    _ = try s.own(try method(s.engine, roots, "push", receiver, &.{lower}));
    return c.pi_js_undefined();
}
fn discardMethod(s: *Scope, roots: c.JSValue, name: [*:0]const u8, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    _ = try s.own(try method(s.engine, roots, name, receiver, args)); return c.pi_js_undefined();
}
fn loopStep(s: *Scope, frame: *TypeFrame, roots: c.JSValue) !c.JSValue {
    const value = frame.get(.value);
    try assertion(s.engine, roots, c.JS_IsString(value), "All expected entries have to be of type string");
    if (try a.condition(s.engine, knownType, .{roots, value})) {
        _ = try a.expression(s.engine, pushLower, .{roots, frame.get(.types), value});
    } else if (try a.condition(s.engine, classType, .{roots, value})) {
        _ = try a.expression(s.engine, discardMethod, .{roots, @as([*:0]const u8, "push"), frame.get(.instances), @as([]const c.JSValue, &.{value})});
    } else {
        try assertion(s.engine, roots, !s.equal(value, try s.text("object")), "The value \"object\" should be written as \"Object\"");
        _ = try a.expression(s.engine, discardMethod, .{roots, @as([*:0]const u8, "push"), frame.get(.other), @as([]const c.JSValue, &.{value})});
    }
    return c.pi_js_undefined();
}
fn loop(engine: *v.em.Engine, iterator: *Iterator, frame: *TypeFrame, roots: c.JSValue) !void {
    while (try iterator.next()) |value| {
        // The old uncaptured Source head survives next/done/value. Assignment
        // publishes the new head before retiring the old; final head survives.
        try frame.take(.value, value);
        _ = try a.expression(engine, loopStep, .{frame, roots});
    }
}
fn positionBody(s: *Scope, roots: c.JSValue, receiver: c.JSValue) !c.JSValue {
    return method(s.engine, roots, "indexOf", receiver, &.{try s.text("object")});
}
fn adjustObject(s: *Scope, roots: c.JSValue, frame: *TypeFrame) !c.JSValue {
    _ = try a.expression(s.engine, discardMethod, .{roots, @as([*:0]const u8, "splice"), frame.get(.types),
        @as([]const c.JSValue, &.{frame.get(.position), c.JS_NewInt32(s.engine.context, 1)})});
    _ = try a.expression(s.engine, discardMethod, .{roots, @as([*:0]const u8, "push"), frame.get(.instances),
        @as([]const c.JSValue, &.{try s.text("Object")})});
    return c.pi_js_undefined();
}
fn appendList(s: *Scope, previous: c.JSValue, roots: c.JSValue, receiver: c.JSValue, prefix: []const u8) !c.JSValue {
    const list = try s.own(try a.expression(s.engine, formatList, .{roots, receiver}));
    const suffix = try a.add(s, try s.text(prefix), try s.toString(list));
    return a.duplicate(s.engine, try a.add(s, previous, suffix));
}
fn appendTypes(s: *Scope, previous: c.JSValue, roots: c.JSValue, receiver: c.JSValue) !c.JSValue {
    const many = try a.condition(s.engine, lengthGreater, .{receiver, @as(i32, 1)});
    return appendList(s, previous, roots, receiver, if (many) "one of type " else "of type ");
}
fn lowerFirst(s: *Scope, roots: c.JSValue, receiver: c.JSValue) !c.JSValue {
    return method(s.engine, roots, "lower", try s.getKey(receiver, c.JS_NewInt32(s.engine.context, 0)), &.{});
}
fn lowerDifferent(s: *Scope, roots: c.JSValue, receiver: c.JSValue) !c.JSValue {
    const lower = try s.own(try a.expression(s.engine, lowerFirst, .{roots, receiver}));
    const compared = try s.getKey(receiver, c.JS_NewInt32(s.engine.context, 0));
    return a.boolean(s, !s.equal(lower, compared));
}
fn appendOther(s: *Scope, previous: c.JSValue, receiver: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try a.add(s, previous, try s.own(try a.expression(s.engine, indexText, .{receiver, @as(u32, 0)}))));
}
fn appendReceived(s: *Scope, previous: c.JSValue, roots: c.JSValue, actual: c.JSValue) !c.JSValue {
    const specific = try s.own(try method(s.engine, roots, "specific", c.pi_js_undefined(), &.{actual}));
    const suffix = try a.add(s, try s.text(". Received "), try s.toString(specific));
    return a.duplicate(s.engine, try a.add(s, previous, suffix));
}
fn typeCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = TypeFrame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, typeBody(&s, frame, args, roots[0]));
}
fn typeBody(s: *Scope, frame: *TypeFrame, args: []const c.JSValue, roots: c.JSValue) !c.JSValue {
    try s.pending();
    try frame.copy(.name, a.arg(args, 0)); try frame.copy(.expected, a.arg(args, 1)); try frame.copy(.actual, a.arg(args, 2));
    try assertion(s.engine, roots, c.JS_IsString(frame.get(.name)), "'name' must be a string");
    if (!try a.condition(s.engine, methodBoolean, .{roots, @as([*:0]const u8, "isArray"), c.pi_js_undefined(),
        @as([]const c.JSValue, &.{frame.get(.expected)})}))
        try frame.take(.expected, a.expression(s.engine, wrapExpected, .{frame.get(.expected)}));
    try frame.take(.message, a.expression(s.engine, textBody, .{@as([]const u8, "The ")}));
    if (try a.condition(s.engine, literalMethodBoolean, .{roots, @as([*:0]const u8, "endsWith"), frame.get(.name), @as([]const u8, " argument")})) {
        try frame.take(.message, a.expression(s.engine, namedArgument, .{frame.get(.message), frame.get(.name)}));
    } else {
        const dotted = try a.condition(s.engine, literalMethodBoolean, .{roots, @as([*:0]const u8, "stringIncludes"), frame.get(.name), @as([]const u8, ".")});
        try frame.take(.kind, a.expression(s.engine, textBody, .{@as([]const u8, if (dotted) "property" else "argument")}));
        try frame.take(.message, a.expression(s.engine, namedProperty, .{frame.get(.message), frame.get(.name), frame.get(.kind)}));
    }
    try frame.take(.message, a.expression(s.engine, appendText, .{frame.get(.message), @as([]const u8, "must be ")}));
    try frame.take(.types, a.expression(s.engine, arrayBody, .{}));
    try frame.take(.instances, a.expression(s.engine, arrayBody, .{}));
    try frame.take(.other, a.expression(s.engine, arrayBody, .{}));
    var iterator = try Iterator.init(s.engine, frame.get(.expected));
    try iterator.finish(loop(s.engine, &iterator, frame, roots));
    if (try a.condition(s.engine, lengthGreater, .{frame.get(.instances), @as(i32, 0)})) {
        try frame.take(.position, a.expression(s.engine, positionBody, .{roots, frame.get(.types)}));
        if (!s.equal(frame.get(.position), c.JS_NewInt32(s.engine.context, -1)))
            _ = try a.expression(s.engine, adjustObject, .{roots, frame});
    }
    if (try a.condition(s.engine, lengthGreater, .{frame.get(.types), @as(i32, 0)})) {
        try frame.take(.message, a.expression(s.engine, appendTypes, .{frame.get(.message), roots, frame.get(.types)}));
        if (try a.condition(s.engine, lengthGreater, .{frame.get(.instances), @as(i32, 0)}) or
            try a.condition(s.engine, lengthGreater, .{frame.get(.other), @as(i32, 0)}))
            try frame.take(.message, a.expression(s.engine, appendText, .{frame.get(.message), @as([]const u8, " or ")}));
    }
    if (try a.condition(s.engine, lengthGreater, .{frame.get(.instances), @as(i32, 0)})) {
        try frame.take(.message, a.expression(s.engine, appendList, .{frame.get(.message), roots, frame.get(.instances), @as([]const u8, "an instance of ")}));
        if (try a.condition(s.engine, lengthGreater, .{frame.get(.other), @as(i32, 0)}))
            try frame.take(.message, a.expression(s.engine, appendText, .{frame.get(.message), @as([]const u8, " or ")}));
    }
    if (try a.condition(s.engine, lengthGreater, .{frame.get(.other), @as(i32, 0)})) {
        if (try a.condition(s.engine, lengthGreater, .{frame.get(.other), @as(i32, 1)})) {
            try frame.take(.message, a.expression(s.engine, appendList, .{frame.get(.message), roots, frame.get(.other), @as([]const u8, "one of ")}));
        } else {
            if (try a.condition(s.engine, lowerDifferent, .{roots, frame.get(.other)}))
                try frame.take(.message, a.expression(s.engine, appendText, .{frame.get(.message), @as([]const u8, "an ")}));
            try frame.take(.message, a.expression(s.engine, appendOther, .{frame.get(.message), frame.get(.other)}));
        }
    }
    try frame.take(.message, a.expression(s.engine, appendReceived, .{frame.get(.message), roots, frame.get(.actual)}));
    return a.duplicate(s.engine, frame.get(.message));
}
fn inspectCall(s: *Scope, roots: c.JSValue, value: c.JSValue) !c.JSValue {
    const module = try s.get(roots, "inspect");
    return a.duplicate(s.engine, try s.call(try s.get(module, "inspect"), module, &.{value}));
}
fn truncateInspected(s: *Scope, roots: c.JSValue, value: c.JSValue) !c.JSValue {
    const part = try s.own(try method(s.engine, roots, "stringSlice", value,
        &.{c.JS_NewInt32(s.engine.context, 0), c.JS_NewInt32(s.engine.context, 128)}));
    return a.duplicate(s.engine, try a.add(s, try s.toString(part), try s.text("...")));
}
fn valueCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = ValueFrame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, valueBody(&s, frame, args, roots[0]));
}
fn valueBody(s: *Scope, frame: *ValueFrame, args: []const c.JSValue, roots: c.JSValue) !c.JSValue {
    try s.pending();
    try frame.copy(.name, a.arg(args, 0)); try frame.copy(.value, a.arg(args, 1));
    if (c.JS_IsUndefined(a.arg(args, 2)))
        try frame.take(.reason, a.expression(s.engine, textBody, .{@as([]const u8, "is invalid")}))
    else try frame.copy(.reason, a.arg(args, 2));
    try frame.take(.inspected, a.expression(s.engine, inspectCall, .{roots, frame.get(.value)}));
    if (try a.condition(s.engine, lengthGreater, .{frame.get(.inspected), @as(i32, 128)}))
        try frame.take(.inspected, a.expression(s.engine, truncateInspected, .{roots, frame.get(.inspected)}));
    const dotted = try a.condition(s.engine, literalMethodBoolean, .{roots, @as([*:0]const u8, "stringIncludes"), frame.get(.name), @as([]const u8, ".")});
    try frame.take(.kind, a.expression(s.engine, textBody, .{@as([]const u8, if (dotted) "property" else "argument")}));
    var result = try a.add(s, try s.text("The "), try s.toString(frame.get(.kind)));
    result = try a.add(s, result, try s.text(" '"));
    result = try a.add(s, result, try s.toString(frame.get(.name)));
    result = try a.add(s, result, try s.text("' "));
    result = try a.add(s, result, try s.toString(frame.get(.reason)));
    result = try a.add(s, result, try s.text(". Received "));
    return a.duplicate(s.engine, try a.add(s, result, try s.toString(frame.get(.inspected))));
}
fn assertionCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return a.expression(engine, assertionMessage, .{a.arg(args, 0)});
}
fn assertionMessage(s: *Scope, message: c.JSValue) !c.JSValue {
    const suffix = try s.text("This is caused by either a bug in Node.js or incorrect usage of Node.js internals.\nPlease open an issue with this stack trace at https://github.com/nodejs/node/issues\n");
    return a.duplicate(s.engine, if (c.JS_IsUndefined(message)) suffix else
        try a.add(s, try a.add(s, try s.toString(message), try s.text("\n")), suffix));
}
