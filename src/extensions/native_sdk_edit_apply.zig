//! Native bodies of b45 edit-diff text normalization/fuzzy matching/multi-edit
//! replacement and preservation of unchanged original line blocks. Private draft.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const Match = struct { found: bool, index: usize = 0, length: usize = 0, fuzzy: bool = false };
const Replacement = struct { edit: usize, start: usize, len: usize, text: c.JSValue };
const Span = struct { start: usize, end: usize };
fn num(s: *Scope, n: usize) c.JSValue {
    return c.JS_NewFloat64(s.engine.context, @floatFromInt(n));
}
fn at(s: *Scope, value: c.JSValue, index: usize) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, value, @intCast(index))));
}
fn size(s: *Scope, value: c.JSValue) !usize {
    var count: u32 = 0;
    if (c.JS_ToUint32(s.engine.context, &count, try s.get(value, "length")) < 0) return js.capture(s.engine);
    return count;
}
fn regex(s: *Scope, source: []const u8, flags: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ try s.text(source), try s.text(flags) };
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn replace(s: *Scope, value: c.JSValue, source: []const u8, replacement: []const u8) !c.JSValue {
    return s.invoke(value, "replace", &.{ try regex(s, source, "g"), try s.text(replacement) });
}
fn lf(s: *Scope, value: c.JSValue) !c.JSValue {
    return replace(s, try replace(s, value, "\r\n", "\n"), "\r", "\n");
}
fn trim(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.invoke(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "trimEnd", &.{}) catch |err| sdk.fail(engine, err);
}
fn fuzzy(s: *Scope, text: c.JSValue) !c.JSValue {
    const normalized = try s.invoke(text, "normalize", &.{try s.text("NFKC")});
    const lines = try s.invoke(normalized, "split", &.{try s.text("\n")});
    const mapper = try s.own(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, trim, "", 1, 0, 0, null)));
    var out = try s.invoke(try s.invoke(lines, "map", &.{mapper}), "join", &.{try s.text("\n")});
    out = try replace(s, out, "[\\u2018\\u2019\\u201A\\u201B]", "'");
    out = try replace(s, out, "[\\u201C\\u201D\\u201E\\u201F]", "\"");
    out = try replace(s, out, "[\\u2010\\u2011\\u2012\\u2013\\u2014\\u2015\\u2212]", "-");
    return replace(s, out, "[\\u00A0\\u2002-\\u200A\\u202F\\u205F\\u3000]", " ");
}
fn indexOf(s: *Scope, content: c.JSValue, old: c.JSValue) !i64 {
    const value = try s.invoke(content, "indexOf", &.{old});
    var index: i64 = 0;
    if (c.JS_ToInt64(s.engine.context, &index, value) < 0) return js.capture(s.engine);
    return index;
}
fn find(s: *Scope, content: c.JSValue, old: c.JSValue) !Match {
    const exact = try indexOf(s, content, old);
    if (exact != -1) return .{ .found = true, .index = @intCast(exact), .length = try size(s, old) };
    const normalized = try fuzzy(s, content);
    const normalized_old = try fuzzy(s, old);
    const approximate = try indexOf(s, normalized, normalized_old);
    return if (approximate == -1) .{ .found = false } else .{ .found = true, .index = @intCast(approximate), .length = try size(s, normalized_old), .fuzzy = true };
}
fn errorText(s: *Scope, message: c.JSValue) anyerror!noreturn {
    var args = [_]c.JSValue{message};
    const reason = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, try s.global("Error"), args.len, &args)));
    _ = try s.engine.checked(c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, reason)));
    unreachable;
}
fn combine(s: *Scope, prefix: []const u8, value: c.JSValue, suffix: []const u8) !c.JSValue {
    return s.concat(try s.concat(try s.text(prefix), try s.stringify(value)), try s.text(suffix));
}
fn normalizeEdit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return normalizedEdit(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn normalizedEdit(engine: *em.Engine, edit: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const out = try s.object();
    try s.put(out, "oldText", try lf(&s, try s.get(edit, "oldText")));
    try s.put(out, "newText", try lf(&s, try s.get(edit, "newText")));
    return c.JS_DupValue(engine.context, out);
}
fn apply(s: *Scope, content: c.JSValue, replacements: []const Replacement, offset: usize) !c.JSValue {
    var out = content;
    var index = replacements.len;
    while (index != 0) {
        index -= 1;
        const current = replacements[index];
        const start = current.start - offset;
        const before = try s.invoke(out, "substring", &.{ num(s, 0), num(s, start) });
        const after = try s.invoke(out, "substring", &.{num(s, start + current.len)});
        out = try s.concat(try s.concat(before, current.text), after);
    }
    return out;
}
fn splitLinesWithEndings(s: *Scope, content: c.JSValue) !c.JSValue {
    const matches = try s.invoke(content, "match", &.{try regex(s, "[^\n]*\n|[^\n]+", "g")});
    return if (c.JS_IsNull(matches) or c.JS_IsUndefined(matches)) s.array() else matches;
}
fn preserve(s: *Scope, original: c.JSValue, base: c.JSValue, replacements: []const Replacement) !c.JSValue {
    const original_lines = try splitLinesWithEndings(s, original);
    const base_lines = try splitLinesWithEndings(s, base);
    const count = try size(s, base_lines);
    if (try size(s, original_lines) != count) try errorText(s, try s.text("Cannot preserve unchanged lines because the base content has a different line count."));
    const spans = try s.engine.gpa.alloc(Span, count);
    defer s.engine.gpa.free(spans);
    var offset: usize = 0;
    for (spans, 0..) |*span, index| {
        span.* = .{ .start = offset, .end = offset + try size(s, try at(s, base_lines, index)) };
        offset = span.end;
    }
    const Group = struct { start: usize, end: usize, first: usize, last: usize };
    var groups: std.ArrayList(Group) = .empty;
    defer groups.deinit(s.engine.gpa);
    for (replacements, 0..) |replacement, index| {
        var start: ?usize = null;
        for (spans, 0..) |span, line_index| if (replacement.start >= span.start and replacement.start < span.end) {
            start = line_index;
            break;
        };
        var end = start orelse {
            try errorText(s, try s.text("Replacement range is outside the base content."));
        };
        while (end < count and spans[end].end < replacement.start + replacement.len) end += 1;
        if (end >= count) try errorText(s, try s.text("Replacement range is outside the base content."));
        if (groups.items.len != 0 and start.? < groups.items[groups.items.len - 1].end) {
            const current = &groups.items[groups.items.len - 1];
            current.end = @max(current.end, end + 1);
            current.last = index + 1;
        } else try groups.append(s.engine.gpa, .{ .start = start.?, .end = end + 1, .first = index, .last = index + 1 });
    }
    var old_index: usize = 0;
    var out = try s.text("");
    for (groups.items) |group| {
        const unchanged = try s.invoke(try s.invoke(original_lines, "slice", &.{ num(s, old_index), num(s, group.start) }), "join", &.{try s.text("")});
        out = try s.concat(out, unchanged);
        const start = spans[group.start].start;
        const end = spans[group.end - 1].end;
        const selected = try s.invoke(base, "slice", &.{ num(s, start), num(s, end) });
        out = try s.concat(out, try apply(s, selected, replacements[group.first..group.last], start));
        old_index = group.end;
    }
    return s.concat(out, try s.invoke(try s.invoke(original_lines, "slice", &.{num(s, old_index)}), "join", &.{try s.text("")}));
}
fn less(_: void, left: Replacement, right: Replacement) bool {
    return left.start < right.start;
}
pub fn applyNormalized(engine: *em.Engine, content: c.JSValue, edits: c.JSValue, path: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const mapper = try s.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, normalizeEdit, "", 1, 0, 0, null)));
    const normalized = try s.invoke(edits, "map", &.{mapper});
    const count = try size(&s, normalized);
    for (0..count) |index| if (try size(&s, try s.get(try at(&s, normalized, index), "oldText")) == 0) {
        const subject = if (count == 1) try s.text("oldText must not be empty in ") else try combine(&s, "edits[", num(&s, index), "].oldText must not be empty in ");
        try errorText(&s, try s.concat(subject, try combine(&s, "", path, ".")));
    };
    var used_fuzzy = false;
    for (0..count) |index| {
        const match = try find(&s, content, try s.get(try at(&s, normalized, index), "oldText"));
        used_fuzzy = used_fuzzy or match.fuzzy;
    }
    const replacement_base = if (used_fuzzy) try fuzzy(&s, content) else content;
    var replacements: std.ArrayList(Replacement) = .empty;
    defer replacements.deinit(engine.gpa);
    for (0..count) |index| {
        const edit = try at(&s, normalized, index);
        const match = try find(&s, replacement_base, try s.get(edit, "oldText"));
        if (!match.found) {
            const lead = if (count == 1) try s.text("Could not find the exact text in ") else try combine(&s, "Could not find edits[", num(&s, index), "] in ");
            const tail = if (count == 1) ". The old text must match exactly including all whitespace and newlines." else ". The oldText must match exactly including all whitespace and newlines.";
            try errorText(&s, try s.concat(lead, try combine(&s, "", path, tail)));
        }
        const fuzzy_content = try fuzzy(&s, replacement_base);
        const fuzzy_old = try fuzzy(&s, try s.get(edit, "oldText"));
        const occurrences = (try size(&s, try s.invoke(fuzzy_content, "split", &.{fuzzy_old}))) - 1;
        if (occurrences > 1) {
            const lead = try combine(&s, "Found ", num(&s, occurrences), " occurrences of ");
            const name = if (count == 1) try s.text("the text in ") else try combine(&s, "edits[", num(&s, index), "] in ");
            const tail = if (count == 1) ". The text must be unique. Please provide more context to make it unique." else ". Each oldText must be unique. Please provide more context to make it unique.";
            try errorText(&s, try s.concat(try s.concat(lead, name), try combine(&s, "", path, tail)));
        }
        try replacements.append(engine.gpa, .{ .edit = index, .start = match.index, .len = match.length, .text = try s.get(edit, "newText") });
    }
    std.sort.block(Replacement, replacements.items, {}, less);
    if (replacements.items.len > 1) for (1..replacements.items.len) |index| {
        const previous = replacements.items[index - 1];
        const current = replacements.items[index];
        if (previous.start + previous.len > current.start) {
            const pair = try s.concat(try combine(&s, "edits[", num(&s, previous.edit), "] and edits["), try combine(&s, "", num(&s, current.edit), "] overlap in "));
            try errorText(&s, try s.concat(pair, try combine(&s, "", path, ". Merge them into one edit or target disjoint regions.")));
        }
    };
    const newer = if (used_fuzzy) try preserve(&s, content, replacement_base, replacements.items) else try apply(&s, replacement_base, replacements.items, 0);
    if (s.equal(content, newer)) try errorText(&s, try combine(&s, "No changes made to ", path, if (count == 1) ". The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected." else ". The replacements produced identical content."));
    const out = try s.object();
    try s.put(out, "baseContent", content);
    try s.put(out, "newContent", newer);
    return c.JS_DupValue(engine.context, out);
}
pub fn normalizeLF(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return c.JS_DupValue(engine.context, try lf(&s, value));
}
