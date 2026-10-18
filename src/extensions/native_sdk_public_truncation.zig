//! Actual c268 public tool truncation functions over live JS values.
//! Buffer methods, string methods and option coercions remain guest operations.
const x = @import("native_sdk_catalog_values.zig");
const c = x.c;
const Ops = x.Ops;
const Scope = x.Scope;
const nf = @import("native_node_function.zig");
const math = @import("native_image_arithmetic.zig");
const cache_key = "\x00sdk-public-truncation-module";
const Kind = enum { formatSize, truncateHead, truncateTail, truncateLine };
const Limit = enum { lines, bytes };
const Counter = struct {
    value: c.JSValue,
    fn set(self: *Counter, engine: *x.em.Engine, borrowed: c.JSValue) !void {
        return self.take(engine, c.JS_DupValue(engine.context, borrowed));
    }
    fn take(self: *Counter, engine: *x.em.Engine, incoming: c.JSValue) !void {
        var completion = x.owned.Completion.initValue(engine, incoming);
        completion.release(self.value);
        self.value = c.pi_js_undefined();
        self.value = try completion.finishValue();
    }
};
const Output = struct {
    content: c.JSValue,
    truncated: bool,
    by: ?Limit = null,
    total_lines: c.JSValue,
    total_bytes: c.JSValue,
    output_lines: c.JSValue,
    output_bytes: c.JSValue,
    partial: bool = false,
    first_exceeds: bool = false,
    max_lines: c.JSValue,
    max_bytes: c.JSValue,
};

pub fn create(engine: *x.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return c.JS_DupValue(engine.context, cached);
    var invocation: x.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    const value = createOwned(engine) catch |err|
        return engine.checked(engine.leaveNativeInvocation(&invocation, @import("native_sdk.zig").fail(engine, err)));
    return engine.checked(engine.leaveNativeInvocation(&invocation, value));
}
fn createOwned(engine: *x.em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine }; var o: Ops = .{ .s = &s };
    const namespace = try x.owned.finishValue(&s, createBody(&o));
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = x.owned.Completion.initValue(engine, err); completion.release(namespace);
        return completion.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, c.JS_DupValue(engine.context, namespace));
    return namespace;
}
fn createBody(o: *Ops) !c.JSValue {
    const namespace = try o.object();
    try o.put(namespace, "DEFAULT_MAX_LINES", c.JS_NewInt32(o.s.engine.context, 2000));
    try o.put(namespace, "DEFAULT_MAX_BYTES", c.JS_NewInt32(o.s.engine.context, 50 * 1024));
    inline for (@typeInfo(Kind).@"enum".fields) |field| {
        const Callback = struct {
            fn invoke(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                return dispatch(engine, @enumFromInt(field.value), args);
            }
        };
        try o.put(namespace, field.name, try o.own(try nf.create(o.s.engine, field.name, 1, Callback.invoke, &.{})));
    }
    return c.JS_DupValue(o.s.engine.context, namespace);
}
fn argument(args: []const c.JSValue, position: usize) c.JSValue { return if (position < args.len) args[position] else c.pi_js_undefined(); }
fn boolean(engine: *x.em.Engine, value: bool) c.JSValue { return c.pi_js_bool(engine.context, @intFromBool(value)); }
fn number(engine: *x.em.Engine, value: f64) c.JSValue { return c.JS_NewFloat64(engine.context, value); }
fn operation(o: *Ops, kind: math.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue { return o.binary(@intFromEnum(kind), left, right); }
fn dispatch(engine: *x.em.Engine, kind: Kind, args: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; var o: Ops = .{ .s = &s };
    var bytes: Counter = .{ .value = c.JS_NewInt32(engine.context, 0) };
    var completion = x.owned.Completion.initValue(engine, switch (kind) {
        .formatSize => formatBytes(&o, argument(args, 0)),
        .truncateLine => truncateLineBody(&o, argument(args, 0), argument(args, 1)),
        .truncateHead, .truncateTail => truncateBody(&o, argument(args, 0), argument(args, 1), kind == .truncateTail, &bytes),
    });
    completion.releaseScope(&s); completion.release(bytes.value); bytes.value = c.pi_js_undefined();
    return completion.finishValue();
}
fn formatBytes(o: *Ops, bytes: c.JSValue) !c.JSValue {
    const engine = o.s.engine;
    if (try o.compare(.less, bytes, c.JS_NewInt32(engine.context, 1024)))
        return c.JS_DupValue(engine.context, try o.concat(try o.stringify(bytes), try o.text("B")));
    const kilobytes = try o.compare(.less, bytes, c.JS_NewInt32(engine.context, 1024 * 1024));
    const quotient = try operation(o, .divide, bytes, c.JS_NewInt32(engine.context, if (kilobytes) 1024 else 1024 * 1024));
    const fixed = try o.own(try o.invokeOwned(quotient, "toFixed", &.{c.JS_NewInt32(engine.context, 1)}));
    return c.JS_DupValue(engine.context, try o.concat(try o.stringify(fixed), try o.text(if (kilobytes) "KB" else "MB")));
}
fn truncateLineBody(o: *Ops, line: c.JSValue, supplied: c.JSValue) !c.JSValue {
    const engine = o.s.engine;
    const limit = if (c.JS_IsUndefined(supplied)) c.JS_NewInt32(engine.context, 500) else supplied;
    const fits = try lengthComparison(o, line, .less_equal, limit);
    const result = try o.object();
    if (fits) {
        try o.put(result, "text", line); try o.put(result, "wasTruncated", boolean(engine, false));
    } else {
        try o.put(result, "text", try o.own(try truncatedLineText(o, line, limit)));
        try o.put(result, "wasTruncated", boolean(engine, true));
    }
    return c.JS_DupValue(engine.context, result);
}
fn truncatedLineText(o: *Ops, line: c.JSValue, limit: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
    return x.owned.finishValue(&s, truncatedLineTextBody(&local, line, limit));
}
fn truncatedLineTextBody(o: *Ops, line: c.JSValue, limit: c.JSValue) !c.JSValue {
    const slice = try o.own(try o.invokeOwned(line, "slice", &.{c.JS_NewInt32(o.s.engine.context, 0), limit}));
    return c.JS_DupValue(o.s.engine.context, try o.concat(try o.stringify(slice), try o.text("... [truncated]")));
}
fn lengthComparison(o: *Ops, target: c.JSValue, kind: math.Operation, bound: c.JSValue) !bool {
    var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
    return o.truthy(try x.owned.finishValue(&s, lengthComparisonBody(&local, target, kind, bound)));
}
fn lengthComparisonBody(o: *Ops, target: c.JSValue, kind: math.Operation, bound: c.JSValue) !c.JSValue {
    return boolean(o.s.engine, try o.compare(kind, try o.get(target, "length"), bound));
}
fn emptyValue(o: *Ops, target: c.JSValue) !bool {
    var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
    return o.truthy(try x.owned.finishValue(&s, emptyValueBody(&local, target)));
}
fn emptyValueBody(o: *Ops, target: c.JSValue) !c.JSValue {
    return boolean(o.s.engine, o.equal(try o.get(target, "length"), c.JS_NewInt32(o.s.engine.context, 0)));
}
fn discard(engine: *x.em.Engine, owned_value: c.JSValue) !void {
    var completion = x.owned.Completion.initVoid(engine, {});
    completion.release(owned_value); return completion.finishVoid();
}
fn splitLines(o: *Ops, content: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
    return x.owned.finishValue(&s, splitLinesBody(&local, content));
}
fn splitLinesBody(o: *Ops, content: c.JSValue) !c.JSValue {
    if (try emptyValue(o, content)) return c.JS_DupValue(o.s.engine.context, try o.array());
    const lines = try o.own(try o.invokeOwned(content, "split", &.{try o.text("\n")}));
    const ends = try o.invokeOwned(content, "endsWith", &.{try o.text("\n")});
    const has_final_newline = o.truthy(ends); try discard(o.s.engine, ends);
    if (has_final_newline) try discard(o.s.engine, try o.invokeOwned(lines, "pop", &.{}));
    return c.JS_DupValue(o.s.engine.context, lines);
}
fn byteLength(o: *Ops, content: c.JSValue, first_line: bool) !c.JSValue {
    var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
    return x.owned.finishValue(&s, byteLengthBody(&local, content, first_line));
}
fn byteLengthBody(o: *Ops, content: c.JSValue, first_line: bool) !c.JSValue {
    const buffer = try o.global("Buffer");
    const function = try o.get(buffer, "byteLength");
    const input = if (first_line) try o.at(content, 0) else content;
    return c.JS_DupValue(o.s.engine.context, try o.call(function, buffer, &.{input, try o.text("utf-8")}));
}
fn outputRecord(o: *Ops, value: Output) !c.JSValue {
    const result = try o.object();
    try o.put(result, "content", value.content);
    try o.put(result, "truncated", boolean(o.s.engine, value.truncated));
    try o.put(result, "truncatedBy", if (value.by) |kind| try o.text(@tagName(kind)) else c.pi_js_null());
    try o.put(result, "totalLines", value.total_lines); try o.put(result, "totalBytes", value.total_bytes);
    try o.put(result, "outputLines", value.output_lines); try o.put(result, "outputBytes", value.output_bytes);
    try o.put(result, "lastLinePartial", boolean(o.s.engine, value.partial));
    try o.put(result, "firstLineExceedsLimit", boolean(o.s.engine, value.first_exceeds));
    try o.put(result, "maxLines", value.max_lines); try o.put(result, "maxBytes", value.max_bytes);
    return c.JS_DupValue(o.s.engine.context, result);
}
fn truncateBody(o: *Ops, content: c.JSValue, supplied: c.JSValue, tail: bool, bytes: *Counter) !c.JSValue {
    const engine = o.s.engine;
    const options = if (c.JS_IsUndefined(supplied)) try o.object() else supplied;
    const supplied_lines = try o.get(options, "maxLines");
    const max_lines = if (x.nullish(supplied_lines)) c.JS_NewInt32(engine.context, 2000) else supplied_lines;
    const supplied_bytes = try o.get(options, "maxBytes");
    const max_bytes = if (x.nullish(supplied_bytes)) c.JS_NewInt32(engine.context, 50 * 1024) else supplied_bytes;
    const total_bytes = try o.own(try byteLength(o, content, false));
    const lines = try o.own(try splitLines(o, content));
    const total_lines = try o.get(lines, "length");
    if (try o.compare(.less_equal, total_lines, max_lines) and try o.compare(.less_equal, total_bytes, max_bytes))
        return outputRecord(o, .{ .content = content, .truncated = false, .total_lines = total_lines, .total_bytes = total_bytes, .output_lines = total_lines, .output_bytes = total_bytes, .max_lines = max_lines, .max_bytes = max_bytes });
    if (!tail) {
        // Source's firstLineBytes is a lexical binding for the entire head call.
        const first_bytes = try o.own(try byteLength(o, lines, true));
        if (try o.compare(.greater, first_bytes, max_bytes))
            return outputRecord(o, .{ .content = try o.text(""), .truncated = true, .by = .bytes, .total_lines = total_lines, .total_bytes = total_bytes, .output_lines = c.JS_NewInt32(engine.context, 0), .output_bytes = c.JS_NewInt32(engine.context, 0), .first_exceeds = true, .max_lines = max_lines, .max_bytes = max_bytes });
    }
    const output_lines = try o.array();
    var by: Limit = .lines; var partial = false;
    var cursor: f64 = 0;
    if (tail) {
        var s: Scope = .{ .engine = engine }; var local: Ops = .{ .s = &s };
        const initial = try x.owned.finishValue(&s, initialTailIndex(&local, lines));
        // The subtraction has already performed Source ToNumeric with Number 1.
        if (c.JS_ToFloat64(engine.context, &cursor, initial) < 0) {
            var completion = x.owned.Completion.initVoid(engine, error.JavaScriptException); completion.release(initial); try completion.finishVoid(); unreachable;
        }
        try discard(engine, initial);
    }
    var steps: usize = 0;
    while (true) {
        if (tail) {
            if (!(cursor >= 0)) break;
            if (!try lengthComparison(o, output_lines, .less, max_lines)) break;
        } else {
            if (!try indexBeforeLength(o, cursor, lines)) break;
            if (!try o.compare(.less, number(engine, cursor), max_lines)) break;
        }
        try poll(engine, &steps);
        var iteration: Scope = .{ .engine = engine }; var local: Ops = .{ .s = &iteration };
        const step_result = x.owned.finishValue(&iteration, collectLine(&local, lines, number(engine, cursor), output_lines, max_bytes, bytes, tail, &partial));
        if (!o.truthy(try step_result)) { by = .bytes; break; }
        cursor += if (tail) -1 else 1;
    }
    if (try lengthComparison(o, output_lines, .greater_equal, max_lines) and try o.compare(.less_equal, bytes.value, max_bytes)) by = .lines;
    const output_content = try o.own(try o.invokeOwned(output_lines, "join", &.{try o.text("\n")}));
    const final_bytes = try o.own(try byteLength(o, output_content, false));
    return outputRecord(o, .{ .content = output_content, .truncated = true, .by = by, .total_lines = total_lines, .total_bytes = total_bytes, .output_lines = try o.get(output_lines, "length"), .output_bytes = final_bytes, .partial = partial, .max_lines = max_lines, .max_bytes = max_bytes });
}
fn initialTailIndex(o: *Ops, lines: c.JSValue) !c.JSValue { return c.JS_DupValue(o.s.engine.context, try operation(o, .subtract, try o.get(lines, "length"), c.JS_NewInt32(o.s.engine.context, 1))); }
fn indexBeforeLength(o: *Ops, cursor: f64, lines: c.JSValue) !bool {
    var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
    return o.truthy(try x.owned.finishValue(&s, indexBeforeLengthBody(&local, cursor, lines)));
}
fn indexBeforeLengthBody(o: *Ops, cursor: f64, lines: c.JSValue) !c.JSValue { return boolean(o.s.engine, try o.compare(.less, number(o.s.engine, cursor), try o.get(lines, "length"))); }
fn sumExceeds(o: *Ops, accumulated: c.JSValue, next: c.JSValue, limit: c.JSValue) !bool {
    var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
    return o.truthy(try x.owned.finishValue(&s, sumExceedsBody(&local, accumulated, next, limit)));
}
fn sumExceedsBody(o: *Ops, accumulated: c.JSValue, next: c.JSValue, limit: c.JSValue) !c.JSValue { return boolean(o.s.engine, try o.compare(.greater, try operation(o, .add, accumulated, next), limit)); }
fn countedLineBytes(o: *Ops, line: c.JSValue, cursor: c.JSValue, output_lines: c.JSValue, tail: bool) !c.JSValue {
    var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
    return x.owned.finishValue(&s, countedLineBytesBody(&local, line, cursor, output_lines, tail));
}
fn countedLineBytesBody(o: *Ops, line: c.JSValue, cursor: c.JSValue, output_lines: c.JSValue, tail: bool) !c.JSValue {
    const line_length = try o.own(try byteLength(o, line, false));
    const add_newline = if (tail) try lengthComparison(o, output_lines, .greater, c.JS_NewInt32(o.s.engine.context, 0)) else try o.compare(.greater, cursor, c.JS_NewInt32(o.s.engine.context, 0));
    return c.JS_DupValue(o.s.engine.context, try operation(o, .add, line_length, c.JS_NewInt32(o.s.engine.context, @intFromBool(add_newline))));
}
fn collectLine(o: *Ops, lines: c.JSValue, cursor: c.JSValue, output_lines: c.JSValue, limit: c.JSValue, bytes: *Counter, tail: bool, partial: *bool) !c.JSValue {
    const engine = o.s.engine;
    const line = try o.key(lines, cursor);
    const line_bytes = try o.own(try countedLineBytes(o, line, cursor, output_lines, tail));
    if (try sumExceeds(o, bytes.value, line_bytes, limit)) {
        if (tail and try emptyValue(o, output_lines)) {
            const suffix = try o.own(try truncateFromEnd(o, line, limit));
            try discard(engine, try o.invokeOwned(output_lines, "unshift", &.{suffix}));
            const amount = try o.own(try byteLength(o, suffix, false)); try bytes.set(engine, amount); partial.* = true;
        }
        return boolean(engine, false);
    }
    try discard(engine, try o.invokeOwned(output_lines, if (tail) "unshift" else "push", &.{line}));
    try bytes.set(engine, try operation(o, .add, bytes.value, line_bytes));
    return boolean(engine, true);
}
fn truncateFromEnd(o: *Ops, content: c.JSValue, limit: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
    var cursor: Counter = .{ .value = c.pi_js_undefined() };
    var completion = x.owned.Completion.initValue(o.s.engine, truncateFromEndBody(&local, content, limit, &cursor));
    completion.releaseScope(&s); completion.release(cursor.value);
    return completion.finishValue();
}
fn bufferFrom(o: *Ops, content: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
    return x.owned.finishValue(&s, bufferFromBody(&local, content));
}
fn bufferFromBody(o: *Ops, content: c.JSValue) !c.JSValue {
    const buffer = try o.global("Buffer"); const from = try o.get(buffer, "from");
    return c.JS_DupValue(o.s.engine.context, try o.call(from, buffer, &.{content, try o.text("utf-8")}));
}
fn truncateFromEndBody(o: *Ops, content: c.JSValue, limit: c.JSValue, cursor: *Counter) !c.JSValue {
    const engine = o.s.engine;
    const value = try o.own(try bufferFrom(o, content));
    if (try lengthComparison(o, value, .less_equal, limit)) return c.JS_DupValue(engine.context, content);
    try cursor.take(engine, try lengthMinus(o, value, limit));
    var steps: usize = 0;
    while (try cursorBeforeLength(o, cursor.value, value) and try continuationByte(o, value, cursor.value)) {
        try poll(engine, &steps);
        try cursor.take(engine, try incrementOwned(o, cursor.value));
    }
    const suffix = try o.own(try o.invokeOwned(value, "slice", &.{cursor.value}));
    return o.invokeOwned(suffix, "toString", &.{try o.text("utf-8")});
}
fn lengthMinus(o: *Ops, target: c.JSValue, amount: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
    return x.owned.finishValue(&s, lengthMinusBody(&local, target, amount));
}
fn lengthMinusBody(o: *Ops, target: c.JSValue, amount: c.JSValue) !c.JSValue {
    return c.JS_DupValue(o.s.engine.context, try operation(o, .subtract, try o.get(target, "length"), amount));
}
fn incrementOwned(o: *Ops, value: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = o.s.engine };
    const result: anyerror!c.JSValue = if (x.guest.increment(&s, value)) |incremented| c.JS_DupValue(s.engine.context, incremented) else |err| err;
    return x.owned.finishValue(&s, result);
}
fn cursorBeforeLength(o: *Ops, cursor: c.JSValue, target: c.JSValue) !bool {
    var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
    return o.truthy(try x.owned.finishValue(&s, cursorBeforeLengthBody(&local, cursor, target)));
}
fn cursorBeforeLengthBody(o: *Ops, cursor: c.JSValue, target: c.JSValue) !c.JSValue {
    return boolean(o.s.engine, try o.compare(.less, cursor, try o.get(target, "length")));
}
fn continuationByte(o: *Ops, value: c.JSValue, cursor: c.JSValue) !bool {
    var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
    return o.truthy(try x.owned.finishValue(&s, continuationByteBody(&local, value, cursor)));
}
fn continuationByteBody(o: *Ops, value: c.JSValue, cursor: c.JSValue) !c.JSValue {
    return boolean(o.s.engine, o.equal(try operation(o, .bit_and, try o.key(value, cursor), c.JS_NewInt32(o.s.engine.context, 0xc0)), c.JS_NewInt32(o.s.engine.context, 0x80)));
}
fn poll(engine: *x.em.Engine, steps: *usize) !void {
    steps.* +|= 1;
    if (engine.cancelled.load(.acquire) or (steps.* % 256 == 0 and blk: { engine.interrupts +|= 1; break :blk engine.interrupts > engine.options.interrupt_budget; })) {
        _ = c.JS_ThrowInternalError(engine.context, "interrupted");
        const reason = c.JS_GetException(engine.context); c.JS_SetUncatchableError(engine.context, reason);
        _ = try engine.checked(c.JS_Throw(engine.context, reason)); unreachable;
    }
}
