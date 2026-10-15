//! Actual b45 generateDiffString default four-context-line path for edit preview.
//! Real native jsdiff line parts; no unified-patch/full-public-options facade.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn number(s: *Scope, n: usize) c.JSValue {
    return c.JS_NewFloat64(s.engine.context, @floatFromInt(n));
}
fn length(s: *Scope, value: c.JSValue) !usize {
    var out: u32 = 0;
    if (c.JS_ToUint32(s.engine.context, &out, try s.get(value, "length")) < 0) return js.capture(s.engine);
    return out;
}
fn at(s: *Scope, value: c.JSValue, index: usize) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, value, @intCast(index))));
}
fn pushLine(s: *Scope, output: c.JSValue, prefix: []const u8, line: usize, width: c.JSValue, text: c.JSValue) !void {
    const num = try s.call(try s.global("String"), c.pi_js_undefined(), &.{number(s, line)});
    const padded = try s.invoke(num, "padStart", &.{ width, try s.text(" ") });
    const value = try s.concat(try s.concat(try s.concat(try s.text(prefix), padded), try s.text(" ")), text);
    _ = try s.invoke(output, "push", &.{value});
}
fn ellipsis(s: *Scope, output: c.JSValue, width: c.JSValue) !void {
    const blank = try s.invoke(try s.text(""), "padStart", &.{ width, try s.text(" ") });
    _ = try s.invoke(output, "push", &.{try s.concat(try s.concat(try s.text(" "), blank), try s.text(" ..."))});
}
fn contextLines(s: *Scope, output: c.JSValue, raw: c.JSValue, start: usize, end: usize, width: c.JSValue, old_line: *usize, new_line: *usize) !void {
    for (start..end) |index| {
        try pushLine(s, output, " ", old_line.*, width, try at(s, raw, index));
        old_line.* += 1;
        new_line.* += 1;
    }
}
pub fn generateDefault(engine: *em.Engine, old: c.JSValue, newer: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const parts = try s.own(try @import("native_sdk_jsdiff_default.zig").diffLines(engine, old, newer));
    const output = try s.array();
    const old_lines = try s.invoke(old, "split", &.{try s.text("\n")});
    const new_lines = try s.invoke(newer, "split", &.{try s.text("\n")});
    const maximum = try s.invoke(try s.global("Math"), "max", &.{ try s.get(old_lines, "length"), try s.get(new_lines, "length") });
    const width = try s.get(try s.call(try s.global("String"), c.pi_js_undefined(), &.{maximum}), "length");
    var old_line: usize = 1;
    var new_line: usize = 1;
    var last_change = false;
    var first_changed = c.pi_js_undefined();
    const count = try length(&s, parts);
    for (0..count) |index| {
        const part = try at(&s, parts, index);
        const raw = try s.invoke(try s.get(part, "value"), "split", &.{try s.text("\n")});
        var raw_count = try length(&s, raw);
        if (raw_count > 0 and s.equal(try at(&s, raw, raw_count - 1), try s.text(""))) {
            _ = try s.invoke(raw, "pop", &.{});
            raw_count -= 1;
        }
        if (s.truthy(try s.get(part, "added")) or s.truthy(try s.get(part, "removed"))) {
            if (c.JS_IsUndefined(first_changed)) first_changed = number(&s, new_line);
            for (0..raw_count) |line_index| {
                const line = try at(&s, raw, line_index);
                if (s.truthy(try s.get(part, "added"))) {
                    try pushLine(&s, output, "+", new_line, width, line);
                    new_line += 1;
                } else {
                    try pushLine(&s, output, "-", old_line, width, line);
                    old_line += 1;
                }
            }
            last_change = true;
        } else {
            const next_change = index + 1 < count and (s.truthy(try s.get(try at(&s, parts, index + 1), "added")) or s.truthy(try s.get(try at(&s, parts, index + 1), "removed")));
            if (last_change and next_change) {
                if (raw_count <= 8) {
                    try contextLines(&s, output, raw, 0, raw_count, width, &old_line, &new_line);
                } else {
                    try contextLines(&s, output, raw, 0, 4, width, &old_line, &new_line);
                    try ellipsis(&s, output, width);
                    old_line += raw_count - 8;
                    new_line += raw_count - 8;
                    try contextLines(&s, output, raw, raw_count - 4, raw_count, width, &old_line, &new_line);
                }
            } else if (last_change) {
                const shown = @min(raw_count, 4);
                try contextLines(&s, output, raw, 0, shown, width, &old_line, &new_line);
                if (raw_count > shown) {
                    try ellipsis(&s, output, width);
                    old_line += raw_count - shown;
                    new_line += raw_count - shown;
                }
            } else if (next_change) {
                const skipped = raw_count - @min(raw_count, 4);
                if (skipped > 0) {
                    try ellipsis(&s, output, width);
                    old_line += skipped;
                    new_line += skipped;
                }
                try contextLines(&s, output, raw, skipped, raw_count, width, &old_line, &new_line);
            } else {
                old_line += raw_count;
                new_line += raw_count;
            }
            last_change = false;
        }
    }
    const value = try s.object();
    try s.put(value, "diff", try s.invoke(output, "join", &.{try s.text("\n")}));
    try s.put(value, "firstChangedLine", first_changed);
    return c.JS_DupValue(engine.context, value);
}
