//! Actual b45 interactive/components/diff.ts rendering body.
//! Private draft using the real native jsdiff default-word implementation.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const Line = struct { number: c.JSValue, content: c.JSValue };
fn integer(s: *Scope, n: usize) c.JSValue {
    return c.JS_NewFloat64(s.engine.context, @floatFromInt(n));
}
fn at(s: *Scope, array: c.JSValue, n: usize) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, array, @intCast(n))));
}
fn length(s: *Scope, array: c.JSValue) !usize {
    var size: u32 = 0;
    if (c.JS_ToUint32(s.engine.context, &size, try s.get(array, "length")) < 0) return js.capture(s.engine);
    return size;
}
fn expression(s: *Scope, source: []const u8, flags: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ try s.text(source), try s.text(flags) };
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn parse(s: *Scope, line: c.JSValue, pattern: c.JSValue) !c.JSValue {
    return s.invoke(line, "match", &.{pattern});
}
fn tabs(s: *Scope, text: c.JSValue) !c.JSValue {
    return s.invoke(text, "replace", &.{ try expression(s, "\t", "g"), try s.text("   ") });
}
fn fg(s: *Scope, theme: c.JSValue, token: []const u8, text: c.JSValue) !c.JSValue {
    return s.invoke(theme, "fg", &.{ try s.text(token), text });
}
fn formatted(s: *Scope, prefix: []const u8, num: c.JSValue, text: c.JSValue) !c.JSValue {
    return s.concat(try s.concat(try s.concat(try s.text(prefix), num), try s.text(" ")), text);
}
const Intra = struct { removed: c.JSValue, added: c.JSValue };
fn intra(s: *Scope, old: c.JSValue, newer: c.JSValue, theme: c.JSValue) !Intra {
    const diff = try s.own(try @import("native_sdk_jsdiff_default.zig").diffWords(s.engine, old, newer));
    var removed = try s.text("");
    var added = try s.text("");
    var first_removed = true;
    var first_added = true;
    const ws = try expression(s, "^(\\s*)", "");
    for (0..try length(s, diff)) |index| {
        const part = try at(s, diff, index);
        if (s.truthy(try s.get(part, "removed"))) {
            var text = try s.get(part, "value");
            if (first_removed) {
                const matched = try s.invoke(text, "match", &.{ws});
                const maybe = if (c.JS_IsNull(matched) or c.JS_IsUndefined(matched)) c.pi_js_undefined() else try at(s, matched, 1);
                const leading = if (s.truthy(maybe)) maybe else try s.text("");
                text = try s.invoke(text, "slice", &.{try s.get(leading, "length")});
                removed = try s.concat(removed, leading);
                first_removed = false;
            }
            if (s.truthy(text)) removed = try s.concat(removed, try s.invoke(theme, "inverse", &.{text}));
        } else if (s.truthy(try s.get(part, "added"))) {
            var text = try s.get(part, "value");
            if (first_added) {
                const matched = try s.invoke(text, "match", &.{ws});
                const maybe = if (c.JS_IsNull(matched) or c.JS_IsUndefined(matched)) c.pi_js_undefined() else try at(s, matched, 1);
                const leading = if (s.truthy(maybe)) maybe else try s.text("");
                text = try s.invoke(text, "slice", &.{try s.get(leading, "length")});
                added = try s.concat(added, leading);
                first_added = false;
            }
            if (s.truthy(text)) added = try s.concat(added, try s.invoke(theme, "inverse", &.{text}));
        } else {
            removed = try s.concat(removed, try s.get(part, "value"));
            added = try s.concat(added, try s.get(part, "value"));
        }
    }
    return .{ .removed = removed, .added = added };
}
pub fn render(engine: *em.Engine, diff: c.JSValue, theme: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const lines = try s.invoke(diff, "split", &.{try s.text("\n")});
    const result = try s.array();
    const pattern = try expression(&s, "^([+-\\s])(\\s*\\d*)\\s(.*)$", "");
    var index: usize = 0;
    while (index < try length(&s, lines)) {
        if (engine.cancelled.load(.acquire)) {
            _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
            unreachable;
        }
        const line = try at(&s, lines, index);
        const parsed = try parse(&s, line, pattern);
        if (!s.truthy(parsed)) {
            _ = try s.invoke(result, "push", &.{try fg(&s, theme, "toolDiffContext", line)});
            index += 1;
            continue;
        }
        const prefix = try at(&s, parsed, 1);
        if (s.equal(prefix, try s.text("-"))) {
            var removed: std.ArrayList(Line) = .empty;
            defer removed.deinit(engine.gpa);
            var added: std.ArrayList(Line) = .empty;
            defer added.deinit(engine.gpa);
            while (index < try length(&s, lines)) {
                const selected = try parse(&s, try at(&s, lines, index), pattern);
                if (!s.truthy(selected) or !s.equal(try at(&s, selected, 1), try s.text("-"))) break;
                try removed.append(engine.gpa, .{ .number = try at(&s, selected, 2), .content = try at(&s, selected, 3) });
                index += 1;
            }
            while (index < try length(&s, lines)) {
                const selected = try parse(&s, try at(&s, lines, index), pattern);
                if (!s.truthy(selected) or !s.equal(try at(&s, selected, 1), try s.text("+"))) break;
                try added.append(engine.gpa, .{ .number = try at(&s, selected, 2), .content = try at(&s, selected, 3) });
                index += 1;
            }
            if (removed.items.len == 1 and added.items.len == 1) {
                const changed = try intra(&s, try tabs(&s, removed.items[0].content), try tabs(&s, added.items[0].content), theme);
                _ = try s.invoke(result, "push", &.{try fg(&s, theme, "toolDiffRemoved", try formatted(&s, "-", removed.items[0].number, changed.removed))});
                _ = try s.invoke(result, "push", &.{try fg(&s, theme, "toolDiffAdded", try formatted(&s, "+", added.items[0].number, changed.added))});
            } else {
                for (removed.items) |item| _ = try s.invoke(result, "push", &.{try fg(&s, theme, "toolDiffRemoved", try formatted(&s, "-", item.number, try tabs(&s, item.content)))});
                for (added.items) |item| _ = try s.invoke(result, "push", &.{try fg(&s, theme, "toolDiffAdded", try formatted(&s, "+", item.number, try tabs(&s, item.content)))});
            }
        } else {
            const add = s.equal(prefix, try s.text("+"));
            _ = try s.invoke(result, "push", &.{try fg(&s, theme, if (add) "toolDiffAdded" else "toolDiffContext", try formatted(&s, if (add) "+" else " ", try at(&s, parsed, 2), try tabs(&s, try at(&s, parsed, 3))))});
            index += 1;
        }
    }
    return c.JS_DupValue(engine.context, try s.invoke(result, "join", &.{try s.text("\n")}));
}
