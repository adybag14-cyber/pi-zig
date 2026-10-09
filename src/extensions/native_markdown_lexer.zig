//! Native Marked18 token graphs and Source Markdown tokenizer extensions.
const std = @import("std");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
const utf16 = @import("native_utf16.zig");
const v = @import("native_select_list.zig");
const regex = @import("native_markdown_regex.zig");
const Pending = struct { text: []u16, tokens: c.JSValue };
pub const Lexer = struct {
    engine: *Engine,
    grammar: regex.Grammar,
    pending: std.ArrayList(Pending) = .empty,
    top: bool = true,
    in_link: bool = false,
    in_raw_block: bool = false,
    link_emitted: bool = false,
    links: c.JSValue,
    depth: usize = 0,
    pub fn init(engine: *Engine) !Lexer {
        return .{ .engine = engine, .grammar = try .init(engine), .links = c.pi_js_undefined() };
    }
    pub fn deinit(self: *Lexer) void {
        for (self.pending.items) |pending| {
            self.engine.gpa.free(pending.text);
            self.engine.freeValue(pending.tokens);
        }
        self.pending.deinit(self.engine.gpa);
        self.grammar.deinit();
        self.engine.freeValue(self.links);
        self.* = undefined;
    }
    fn token(self: *Lexer, kind: []const u8, raw: []const u16) !c.JSValue {
        const result = try js.object(self.engine);
        errdefer self.engine.freeValue(result);
        try js.define(self.engine, result, "type", try v.text(self.engine, kind));
        try js.define(self.engine, result, "raw", try utf16.string(self.engine, raw));
        return result;
    }
    fn text(self: *Lexer, object: c.JSValue, name: [*:0]const u8, units: []const u16) !void {
        try js.define(self.engine, object, name, try utf16.string(self.engine, units));
    }
    fn queueInline(self: *Lexer, units: []const u16) !c.JSValue {
        const owned = try self.engine.gpa.dupe(u16, units);
        errdefer self.engine.gpa.free(owned);
        const tokens = try js.array(self.engine);
        errdefer self.engine.freeValue(tokens);
        try self.pending.append(self.engine.gpa, .{ .text = owned, .tokens = tokens });
        return c.JS_DupValue(self.engine.context, tokens);
    }
    fn field(self: *Lexer, object: c.JSValue, name: [*:0]const u8) ![]u16 {
        const value = try js.get(self.engine, object, name);
        defer self.engine.freeValue(value);
        return utf16.unitsAlloc(self.engine, value);
    }
    fn last(self: *Lexer, tokens: c.JSValue) !c.JSValue {
        return js.invoke(self.engine, tokens, "at", &.{v.numeric(self.engine, -1)});
    }
    fn sameType(self: *Lexer, value: c.JSValue, wanted: []const u8) !bool {
        if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) return false;
        const kind = try js.get(self.engine, value, "type");
        defer self.engine.freeValue(kind);
        const expected = try v.text(self.engine, wanted);
        defer self.engine.freeValue(expected);
        return c.JS_IsStrictEqual(self.engine.context, kind, expected);
    }
    fn trim(units: []const u16) []const u16 {
        var start: usize = 0;
        var end = units.len;
        while (start < end and @import("../tui/utf16_input.zig").State.whitespace(units[start])) start += 1;
        while (end > start and @import("../tui/utf16_input.zig").State.whitespace(units[end - 1])) end -= 1;
        return units[start..end];
    }
    fn rtrim(units: []const u16, unit: u16) []const u16 {
        var end = units.len;
        while (end > 0 and units[end - 1] == unit) end -= 1;
        return units[0..end];
    }
    fn appendField(self: *Lexer, object: c.JSValue, name: [*:0]const u8, units: []const u16, separator: []const u16) !void {
        const previous = try self.field(object, name);
        defer self.engine.gpa.free(previous);
        const combined = try std.mem.concat(self.engine.gpa, u16, &.{ previous, separator, units });
        defer self.engine.gpa.free(combined);
        try v.set(self.engine, object, name, try utf16.string(self.engine, combined));
    }
    fn updatePending(self: *Lexer, object: c.JSValue) !void {
        if (self.pending.items.len == 0) return error.InvalidNativeMarkdownInlineQueue;
        const replacement = try self.field(object, "text");
        const pending = &self.pending.items[self.pending.items.len - 1];
        self.engine.gpa.free(pending.text);
        pending.text = replacement;
    }
    fn replaceRule(self: *Lexer, scope: regex.Scope, name: []const u8, source: []const u16, replacement: []const u16) ![]u16 {
        const rule = self.grammar.rule(scope, name).object;
        const pattern = rule.get("source").?.string;
        const flags = rule.get("flags").?.string;
        const global = std.mem.indexOfScalar(u8, flags, 'g') != null;
        var output: std.ArrayList(u16) = .empty;
        errdefer output.deinit(self.engine.gpa);
        var at: usize = 0;
        var search: usize = 0;
        while (search <= source.len) {
            var matched = try self.grammar.match(pattern, flags, source, search);
            const cap = if (matched) |*value| value else break;
            defer cap.deinit();
            const span = cap.ranges[0].?;
            try output.appendSlice(self.engine.gpa, source[at..span.start]);
            var index: usize = 0;
            while (index < replacement.len) : (index += 1) {
                if (replacement[index] == '$' and index + 1 < replacement.len and replacement[index + 1] >= '1' and replacement[index + 1] <= '9') {
                    index += 1;
                    try output.appendSlice(self.engine.gpa, cap.group(source, replacement[index] - '0'));
                } else try output.append(self.engine.gpa, replacement[index]);
            }
            at = span.end;
            if (!global) break;
            search = span.end;
            if (span.start == span.end) search += 1;
        }
        try output.appendSlice(self.engine.gpa, source[at..]);
        return output.toOwnedSlice(self.engine.gpa);
    }
    fn trimBlankLines(self: *Lexer, source: []const u16) ![]const u16 {
        var end = source.len;
        var count: usize = 0;
        while (true) {
            const start = if (std.mem.lastIndexOfScalar(u16, source[0..end], '\n')) |at| at + 1 else 0;
            if (!try self.matches(.other, "blankLine", source[start..end])) break;
            count += 1;
            if (start == 0) {
                end = 0;
                break;
            }
            end = start - 1;
        }
        return if (count > 1) source[0..end] else source;
    }
    pub fn lex(self: *Lexer, source: []const u16) !c.JSValue {
        var normalized: std.ArrayList(u16) = .empty;
        defer normalized.deinit(self.engine.gpa);
        var at: usize = 0;
        while (at < source.len) : (at += 1) {
            if (source[at] == '\r') {
                try normalized.append(self.engine.gpa, '\n');
                if (at + 1 < source.len and source[at + 1] == '\n') at += 1;
            } else try normalized.append(self.engine.gpa, source[at]);
        }
        const tokens = try js.array(self.engine);
        errdefer self.engine.freeValue(tokens);
        self.engine.freeValue(self.links);
        self.links = try self.engine.checked(c.JS_NewObjectProto(self.engine.context, c.pi_js_null()));
        try js.define(self.engine, tokens, "links", c.JS_DupValue(self.engine.context, self.links));
        try self.block(normalized.items, tokens);
        var index: usize = 0;
        while (index < self.pending.items.len) : (index += 1) {
            const pending = self.pending.items[index];
            try self.inlineTokens(pending.text, pending.tokens);
        }
        try self.trimPartialFence(tokens);
        return tokens;
    }
    fn trimPartialFence(self: *Lexer, tokens: c.JSValue) anyerror!void {
        const item = try self.last(tokens);
        defer self.engine.freeValue(item);
        if (try self.sameType(item, "list")) {
            const items = try js.get(self.engine, item, "items");
            defer self.engine.freeValue(items);
            const last_item = try self.last(items);
            defer self.engine.freeValue(last_item);
            if (c.JS_IsUndefined(last_item)) return;
            const children = try js.get(self.engine, last_item, "tokens");
            defer self.engine.freeValue(children);
            return self.trimPartialFence(children);
        }
        if (try self.sameType(item, "blockquote")) {
            const children = try js.get(self.engine, item, "tokens");
            defer self.engine.freeValue(children);
            return self.trimPartialFence(children);
        }
        if (!try self.sameType(item, "code")) return;
        const raw = try self.field(item, "raw");
        defer self.engine.gpa.free(raw);
        if (raw.len < 3 or (raw[0] != '`' and raw[0] != '~')) return;
        var marker_length: usize = 0;
        while (marker_length < raw.len and raw[marker_length] == raw[0]) marker_length += 1;
        if (marker_length < 3) return;
        const last_line = raw[if (std.mem.lastIndexOfScalar(u16, raw, '\n')) |at| at + 1 else 0..];
        if (last_line.len == 0 or last_line.len >= marker_length) return;
        for (last_line) |unit| if (unit != raw[0]) return;
        const content = try self.field(item, "text");
        defer self.engine.gpa.free(content);
        var end = content.len -| last_line.len;
        if (end > 0 and content[end - 1] == '\n') end -= 1;
        try v.set(self.engine, item, "text", try utf16.string(self.engine, content[0..end]));
    }
    fn matchPattern(self: *Lexer, pattern: []const u8, source: []const u16) !bool {
        var matched = try self.grammar.match(pattern, "", source, 0);
        if (matched) |*cap| {
            cap.deinit();
            return true;
        }
        return false;
    }
    fn pendingMath(self: *Lexer, source: []const u16) !bool {
        return self.matchPattern("\\\\[A-Za-z]+|[_^=+*/<>()[\\]|±≤≥≠≈∈→⇒∞∫∑√-]", source);
    }
    fn latex(self: *Lexer, source: []const u16, block_mode: bool) !?c.JSValue {
        if (block_mode) {
            for ([_][]const u8{ "^ {0,3}\\$\\$[ \\t]*(?:\\n)?([\\s\\S]*?)\\$\\$[ \\t]*(?:\\n|$)", "^ {0,3}\\\\\\[[ \\t]*(?:\\n)?([\\s\\S]*?)\\\\\\][ \\t]*(?:\\n|$)", "^ {0,3}\\\\\\[[ \\t]*(?:\\n)?([\\s\\S]*)$", "^ {0,3}\\$\\$[ \\t]*(?:\\n)?([\\s\\S]*)$" }, 0..) |pattern, index| {
                var matched = try self.grammar.match(pattern, "", source, 0);
                if (matched) |*cap| {
                    defer cap.deinit();
                    const content = cap.group(source, 1);
                    if ((index < 2 or index == 3) and content.len == 0) continue;
                    if (index == 3 and !try self.pendingMath(content)) continue;
                    const item = try self.token("latexBlock", cap.group(source, 0));
                    errdefer self.engine.freeValue(item);
                    try self.text(item, "text", if (index < 2) trim(content) else content);
                    if (index >= 2) try js.define(self.engine, item, "pending", c.pi_js_bool(self.engine.context, 1));
                    return item;
                }
            }
            return null;
        }
        const opening: []const u16 = if (std.mem.startsWith(u16, source, &.{ '$', '$' })) &.{ '$', '$' } else if (std.mem.startsWith(u16, source, &.{ '\\', '(' })) &.{ '\\', '(' } else if (std.mem.startsWith(u16, source, &.{ '\\', '[' })) &.{ '\\', '[' } else if (source[0] == '$' and !try self.matchPattern("^\\$\\s", source)) &.{'$'} else return null;
        const closing: []const u16 = if (opening[0] == '$') opening else if (opening[1] == '(') &.{ '\\', ')' } else &.{ '\\', ']' };
        var search = opening.len;
        var closing_at: ?usize = null;
        while (std.mem.indexOfPos(u16, source, search, closing)) |at| {
            var slash = at;
            while (slash > 0 and source[slash - 1] == '\\') slash -= 1;
            if ((at - slash) % 2 == 0) {
                closing_at = at;
                break;
            }
            search = at + closing.len;
        }
        if (closing_at) |at| {
            const content = source[opening.len..at];
            if (opening.len == 1 and (try self.matchPattern("\\s$", content) or try self.matchPattern("^\\d", source[at + 1 ..]) or (try self.matchPattern("^[A-Z_][A-Z0-9_]*(?:[^A-Za-z0-9_\\s])?$", content) and try self.matchPattern("^[A-Za-z_][A-Za-z0-9_]*", source[at + 1 ..])) or std.mem.indexOfScalar(u16, content, '`') != null)) return null;
            if (content.len == 0 or std.mem.indexOfScalar(u16, content, '\n') != null) return null;
            const item = try self.token("latex", source[0 .. at + closing.len]);
            errdefer self.engine.freeValue(item);
            try self.text(item, "text", content);
            return item;
        }
        const content = source[opening.len..];
        if (opening[0] != '\\' and !try self.pendingMath(content)) return null;
        const item = try self.token("latex", source);
        errdefer self.engine.freeValue(item);
        try self.text(item, "text", content);
        try js.define(self.engine, item, "pending", c.pi_js_bool(self.engine.context, 1));
        return item;
    }
    pub fn block(self: *Lexer, original: []const u16, tokens: c.JSValue) anyerror!void {
        return self.blockInternal(original, tokens, false);
    }
    fn blockInternal(self: *Lexer, original: []const u16, tokens: c.JSValue, merge_paragraph: bool) anyerror!void {
        self.depth += 1;
        defer self.depth -= 1;
        if (self.depth > 128) return error.NativeMarkdownNestingLimit;
        var source = original;
        var last_paragraph_clipped = merge_paragraph;
        while (source.len != 0) {
            if (try self.latex(source, true)) |item| {
                defer self.engine.freeValue(item);
                const raw = try self.field(item, "raw");
                defer self.engine.gpa.free(raw);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            var matched: ?regex.Match = try self.grammar.matchRule(.block, "newline", source);
            if (matched) |*cap| {
                defer cap.deinit();
                const raw = cap.group(source, 0);
                if (raw.len > 0) {
                    const previous = try self.last(tokens);
                    defer self.engine.freeValue(previous);
                    if (raw.len == 1 and !c.JS_IsUndefined(previous)) {
                        try self.appendField(previous, "raw", &.{'\n'}, &.{});
                    } else {
                        const item = try self.token("space", raw);
                        defer self.engine.freeValue(item);
                        try js.push(self.engine, tokens, item);
                    }
                    source = source[@min(raw.len, source.len)..];
                    continue;
                }
            }
            matched = try self.grammar.matchRule(.block, "code", source);
            if (matched) |*cap| {
                defer cap.deinit();
                const raw = try self.trimBlankLines(cap.group(source, 0));
                const content = try self.replaceRule(.other, "codeRemoveIndent", raw, &.{});
                defer self.engine.gpa.free(content);
                const previous = try self.last(tokens);
                defer self.engine.freeValue(previous);
                if (try self.sameType(previous, "paragraph") or try self.sameType(previous, "text")) {
                    const old_raw = try self.field(previous, "raw");
                    defer self.engine.gpa.free(old_raw);
                    try self.appendField(previous, "raw", raw, if (old_raw.len > 0 and old_raw[old_raw.len - 1] == '\n') &.{} else &.{'\n'});
                    try self.appendField(previous, "text", content, &.{'\n'});
                    try self.updatePending(previous);
                } else {
                    const item = try self.token("code", raw);
                    defer self.engine.freeValue(item);
                    try js.define(self.engine, item, "codeBlockStyle", try v.text(self.engine, "indented"));
                    try self.text(item, "text", content);
                    try js.push(self.engine, tokens, item);
                }
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            matched = try self.grammar.matchRule(.block, "fences", source);
            if (matched) |*cap| {
                defer cap.deinit();
                const raw = cap.group(source, 0);
                const item = try self.token("code", raw);
                defer self.engine.freeValue(item);
                if (cap.optional(source, 2)) |lang| {
                    const normalized = try self.replaceRule(.inline_rule, "anyPunctuation", trim(lang), &.{ '$', '1' });
                    defer self.engine.gpa.free(normalized);
                    try self.text(item, "lang", normalized);
                } else try js.define(self.engine, item, "lang", c.pi_js_undefined());
                const content = cap.group(source, 3);
                var indentation = try self.grammar.matchRule(.other, "indentCodeCompensation", raw);
                if (indentation) |*indent_cap| {
                    defer indent_cap.deinit();
                    const width = indent_cap.group(raw, 1).len;
                    var compensated: std.ArrayList(u16) = .empty;
                    defer compensated.deinit(self.engine.gpa);
                    var lines = std.mem.splitScalar(u16, content, '\n');
                    var first_line = true;
                    while (lines.next()) |line| {
                        if (!first_line) try compensated.append(self.engine.gpa, '\n');
                        first_line = false;
                        var leading = try self.grammar.matchRule(.other, "beginningSpace", line);
                        const count = if (leading) |*value| blk: {
                            defer value.deinit();
                            break :blk value.group(line, 0).len;
                        } else 0;
                        try compensated.appendSlice(self.engine.gpa, if (count >= width) line[width..] else line);
                    }
                    try self.text(item, "text", compensated.items);
                } else try self.text(item, "text", content);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            matched = try self.grammar.matchRule(.block, "heading", source);
            if (matched) |*cap| {
                defer cap.deinit();
                const raw = rtrim(cap.group(source, 0), '\n');
                var content = trim(cap.group(source, 2));
                if (content.len > 0 and content[content.len - 1] == '#') {
                    const clipped = rtrim(content, '#');
                    if (clipped.len == 0 or @import("../tui/utf16_input.zig").State.whitespace(clipped[clipped.len - 1])) content = trim(clipped);
                }
                const item = try self.token("heading", raw);
                defer self.engine.freeValue(item);
                try js.define(self.engine, item, "depth", v.numeric(self.engine, @floatFromInt(cap.group(source, 1).len)));
                try self.text(item, "text", content);
                try js.define(self.engine, item, "tokens", try self.queueInline(content));
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            matched = try self.grammar.matchRule(.block, "hr", source);
            if (matched) |*cap| {
                defer cap.deinit();
                const raw = rtrim(cap.group(source, 0), '\n');
                const item = try self.token("hr", raw);
                defer self.engine.freeValue(item);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            if (try self.blockquote(source)) |item| {
                defer self.engine.freeValue(item);
                const raw = try self.field(item, "raw");
                defer self.engine.gpa.free(raw);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            if (try self.list(source)) |item| {
                defer self.engine.freeValue(item);
                const raw = try self.field(item, "raw");
                defer self.engine.gpa.free(raw);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            matched = try self.grammar.matchRule(.block, "html", source);
            if (matched) |*cap| {
                defer cap.deinit();
                const raw = try self.trimBlankLines(cap.group(source, 0));
                const item = try js.object(self.engine);
                defer self.engine.freeValue(item);
                try js.define(self.engine, item, "type", try v.text(self.engine, "html"));
                try js.define(self.engine, item, "block", c.pi_js_bool(self.engine.context, 1));
                try self.text(item, "raw", raw);
                const tag = cap.group(source, 1);
                const pre = std.mem.eql(u16, tag, std.unicode.utf8ToUtf16LeStringLiteral("pre")) or std.mem.eql(u16, tag, std.unicode.utf8ToUtf16LeStringLiteral("script")) or std.mem.eql(u16, tag, std.unicode.utf8ToUtf16LeStringLiteral("style"));
                try js.define(self.engine, item, "pre", c.pi_js_bool(self.engine.context, @intFromBool(pre)));
                try self.text(item, "text", raw);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            matched = try self.grammar.matchRule(.block, "def", source);
            if (matched) |*cap| {
                defer cap.deinit();
                const raw = rtrim(cap.group(source, 0), '\n');
                const previous = try self.last(tokens);
                defer self.engine.freeValue(previous);
                if (try self.sameType(previous, "paragraph") or try self.sameType(previous, "text")) {
                    const old_raw = try self.field(previous, "raw");
                    defer self.engine.gpa.free(old_raw);
                    try self.appendField(previous, "raw", raw, if (old_raw.len > 0 and old_raw[old_raw.len - 1] == '\n') &.{} else &.{'\n'});
                    try self.appendField(previous, "text", raw, &.{'\n'});
                    try self.updatePending(previous);
                } else {
                    const lower_value = try utf16.string(self.engine, cap.group(source, 1));
                    defer self.engine.freeValue(lower_value);
                    const lowered = try js.invoke(self.engine, lower_value, "toLowerCase", &.{});
                    defer self.engine.freeValue(lowered);
                    const lower_units = try utf16.unitsAlloc(self.engine, lowered);
                    defer self.engine.gpa.free(lower_units);
                    const tag = try self.replaceRule(.other, "multipleSpaceGlobal", lower_units, &.{' '});
                    defer self.engine.gpa.free(tag);
                    const key = try utf16.string(self.engine, tag);
                    defer self.engine.freeValue(key);
                    if (!try js.hasKey(self.engine, self.links, key)) {
                        const href_brackets = try self.replaceRule(.other, "hrefBrackets", cap.group(source, 2), &.{ '$', '1' });
                        defer self.engine.gpa.free(href_brackets);
                        const href = try self.replaceRule(.inline_rule, "anyPunctuation", href_brackets, &.{ '$', '1' });
                        defer self.engine.gpa.free(href);
                        const title_capture = cap.optional(source, 3);
                        const title = if (title_capture) |value| try self.replaceRule(.inline_rule, "anyPunctuation", value[1 .. value.len - 1], &.{ '$', '1' }) else null;
                        defer if (title) |value| self.engine.gpa.free(value);
                        const item = try js.object(self.engine);
                        defer self.engine.freeValue(item);
                        try js.define(self.engine, item, "type", try v.text(self.engine, "def"));
                        try self.text(item, "tag", tag);
                        try self.text(item, "raw", raw);
                        try self.text(item, "href", href);
                        try js.define(self.engine, item, "title", if (title) |value| try utf16.string(self.engine, value) else c.pi_js_undefined());
                        const link = try js.object(self.engine);
                        defer self.engine.freeValue(link);
                        try self.text(link, "href", href);
                        try js.define(self.engine, link, "title", if (title) |value| try utf16.string(self.engine, value) else c.pi_js_undefined());
                        try js.setKey(self.engine, self.links, key, link);
                        try js.push(self.engine, tokens, item);
                    }
                }
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            if (try self.table(source)) |item| {
                defer self.engine.freeValue(item);
                const raw = try self.field(item, "raw");
                defer self.engine.gpa.free(raw);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            matched = try self.grammar.matchRule(.block, "lheading", source);
            if (matched) |*cap| {
                defer cap.deinit();
                const raw = rtrim(cap.group(source, 0), '\n');
                const content = trim(cap.group(source, 1));
                const item = try self.token("heading", raw);
                defer self.engine.freeValue(item);
                try js.define(self.engine, item, "depth", v.numeric(self.engine, if (cap.group(source, 2)[0] == '=') 1 else 2));
                try self.text(item, "text", content);
                try js.define(self.engine, item, "tokens", try self.queueInline(content));
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            var clipped = source;
            if (source.len > 1) {
                var extension_start = try self.grammar.match("(?:^|\\n) {0,3}(?:\\$\\$|\\\\\\[)", "", source[1..], 0);
                if (extension_start) |*cap| {
                    defer cap.deinit();
                    const at = cap.ranges[0].?.start + @as(usize, if (cap.group(source[1..], 0)[0] == '\n') 1 else 0);
                    clipped = source[0 .. at + 1];
                }
            }
            matched = try self.grammar.matchRule(.block, if (self.top) "paragraph" else "text", if (self.top) clipped else source);
            if (matched) |*cap| {
                defer cap.deinit();
                const raw = cap.group(source, 0);
                const content = if (self.top) rtrim(cap.group(source, 1), '\n') else cap.group(source, 0);
                const previous = try self.last(tokens);
                defer self.engine.freeValue(previous);
                if ((!self.top and try self.sameType(previous, "text")) or (self.top and last_paragraph_clipped and try self.sameType(previous, "paragraph"))) {
                    const previous_raw = try self.field(previous, "raw");
                    defer self.engine.gpa.free(previous_raw);
                    try self.appendField(previous, "raw", raw, if (previous_raw.len > 0 and previous_raw[previous_raw.len - 1] == '\n') &.{} else &.{'\n'});
                    try self.appendField(previous, "text", content, &.{'\n'});
                    try self.updatePending(previous);
                } else {
                    const item = try self.token(if (self.top) "paragraph" else "text", raw);
                    defer self.engine.freeValue(item);
                    try self.text(item, "text", content);
                    try js.define(self.engine, item, "tokens", try self.queueInline(content));
                    try js.push(self.engine, tokens, item);
                }
                if (self.top) last_paragraph_clipped = clipped.len != source.len;
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            return error.NativeMarkdownLexerNoProgress;
        }
        self.top = true;
    }
    fn matches(self: *Lexer, scope: regex.Scope, name: []const u8, source: []const u16) !bool {
        var result = try self.grammar.matchRule(scope, name, source);
        if (result) |*match| {
            match.deinit();
            return true;
        }
        return false;
    }
    fn splitLines(gpa: std.mem.Allocator, source: []const u16) ![][]const u16 {
        var output: std.ArrayList([]const u16) = .empty;
        errdefer output.deinit(gpa);
        var iterator = std.mem.splitScalar(u16, source, '\n');
        while (iterator.next()) |line| try output.append(gpa, line);
        return output.toOwnedSlice(gpa);
    }
    fn joinLines(gpa: std.mem.Allocator, lines: []const []const u16) ![]u16 {
        var output: std.ArrayList(u16) = .empty;
        errdefer output.deinit(gpa);
        for (lines, 0..) |line, index| {
            if (index > 0) try output.append(gpa, '\n');
            try output.appendSlice(gpa, line);
        }
        return output.toOwnedSlice(gpa);
    }
    fn blockquote(self: *Lexer, source: []const u16) anyerror!?c.JSValue {
        var matched = try self.grammar.matchRule(.block, "blockquote", source);
        const cap = if (matched) |*value| value else return null;
        defer cap.deinit();
        var arena = std.heap.ArenaAllocator.init(self.engine.gpa);
        defer arena.deinit();
        const temporary = arena.allocator();
        var lines: []const []const u16 = try splitLines(temporary, rtrim(cap.group(source, 0), '\n'));
        var raw: []const u16 = &.{};
        var content: []const u16 = &.{};
        const children = try js.array(self.engine);
        var children_transferred = false;
        defer if (!children_transferred) self.engine.freeValue(children);
        while (lines.len > 0) {
            var in_quote = false;
            var index: usize = 0;
            while (index < lines.len) : (index += 1) {
                if (try self.matches(.other, "blockquoteStart", lines[index])) {
                    in_quote = true;
                } else if (in_quote) break;
            }
            const current_raw = try joinLines(temporary, lines[0..index]);
            lines = lines[index..];
            const first = try self.replaceRule(.other, "blockquoteSetextReplace", current_raw, std.unicode.utf8ToUtf16LeStringLiteral("\n    $1"));
            defer self.engine.gpa.free(first);
            const current_text = try self.replaceRule(.other, "blockquoteSetextReplace2", first, &.{});
            defer self.engine.gpa.free(current_text);
            raw = if (raw.len > 0) try std.mem.concat(temporary, u16, &.{ raw, &.{'\n'}, current_raw }) else current_raw;
            content = if (content.len > 0) try std.mem.concat(temporary, u16, &.{ content, &.{'\n'}, current_text }) else try temporary.dupe(u16, current_text);
            const top = self.top;
            self.top = true;
            self.blockInternal(current_text, children, true) catch |err| {
                self.top = top;
                return err;
            };
            self.top = top;
            if (lines.len == 0) break;
            const last_child = try self.last(children);
            defer self.engine.freeValue(last_child);
            if (try self.sameType(last_child, "code")) break;
            if (try self.sameType(last_child, "blockquote")) {
                const continuation = try joinLines(temporary, lines);
                const stripped = try self.replaceRule(.other, "blockquoteSetextReplace2", continuation, &.{});
                defer self.engine.gpa.free(stripped);
                const old_raw = try self.field(last_child, "raw");
                defer self.engine.gpa.free(old_raw);
                const old_text = try self.field(last_child, "text");
                defer self.engine.gpa.free(old_text);
                const new_text = try std.mem.concat(temporary, u16, &.{ old_raw, &.{'\n'}, stripped });
                const replacement = (try self.blockquote(new_text)) orelse return error.NativeMarkdownLexerNoProgress;
                defer self.engine.freeValue(replacement);
                const replacement_text = try self.field(replacement, "text");
                defer self.engine.gpa.free(replacement_text);
                const length: u32 = @intFromFloat(try v.numberField(self.engine, children, "length"));
                if (c.JS_SetPropertyUint32(self.engine.context, children, length - 1, c.JS_DupValue(self.engine.context, replacement)) < 0) return js.capture(self.engine);
                raw = try std.mem.concat(temporary, u16, &.{ raw, &.{'\n'}, continuation });
                content = try std.mem.concat(temporary, u16, &.{ content[0..content.len -| old_text.len], replacement_text });
                break;
            }
            if (try self.sameType(last_child, "list")) {
                const old_raw = try self.field(last_child, "raw");
                defer self.engine.gpa.free(old_raw);
                const continuation = try joinLines(temporary, lines);
                const new_text = try std.mem.concat(temporary, u16, &.{ old_raw, &.{'\n'}, continuation });
                const replacement = (try self.list(new_text)) orelse return error.NativeMarkdownLexerNoProgress;
                defer self.engine.freeValue(replacement);
                const replacement_raw = try self.field(replacement, "raw");
                defer self.engine.gpa.free(replacement_raw);
                const length: u32 = @intFromFloat(try v.numberField(self.engine, children, "length"));
                if (c.JS_SetPropertyUint32(self.engine.context, children, length - 1, c.JS_DupValue(self.engine.context, replacement)) < 0) return js.capture(self.engine);
                raw = try std.mem.concat(temporary, u16, &.{ raw[0..raw.len -| old_raw.len], replacement_raw });
                content = try std.mem.concat(temporary, u16, &.{ content[0..content.len -| old_raw.len], replacement_raw });
                lines = try splitLines(temporary, new_text[@min(replacement_raw.len, new_text.len)..]);
            }
        }
        const item = try self.token("blockquote", raw);
        errdefer self.engine.freeValue(item);
        children_transferred = true;
        try js.define(self.engine, item, "tokens", children);
        try self.text(item, "text", content);
        return item;
    }
    fn splitCells(self: *Lexer, row: []const u16, count: ?usize) ![][]u16 {
        var cells: std.ArrayList([]u16) = .empty;
        errdefer {
            for (cells.items) |entry| self.engine.gpa.free(entry);
            cells.deinit(self.engine.gpa);
        }
        var start: usize = 0;
        for (row, 0..) |unit, at| {
            if (unit != '|') continue;
            var slash = at;
            while (slash > 0 and row[slash - 1] == '\\') slash -= 1;
            if ((at - slash) % 2 != 0) continue;
            try cells.append(self.engine.gpa, try self.replaceRule(.other, "slashPipe", trim(row[start..at]), &.{'|'}));
            start = at + 1;
        }
        try cells.append(self.engine.gpa, try self.replaceRule(.other, "slashPipe", trim(row[start..]), &.{'|'}));
        if (cells.items.len > 0 and cells.items[0].len == 0) self.engine.gpa.free(cells.orderedRemove(0));
        if (cells.items.len > 0 and cells.items[cells.items.len - 1].len == 0) self.engine.gpa.free(cells.pop().?);
        if (count) |wanted| if (wanted > 0) {
            while (cells.items.len > wanted) self.engine.gpa.free(cells.pop().?);
            while (cells.items.len < wanted) try cells.append(self.engine.gpa, try self.engine.gpa.dupe(u16, &.{}));
        };
        return cells.toOwnedSlice(self.engine.gpa);
    }
    fn cell(self: *Lexer, text_units: []const u16, header: bool, alignment: c.JSValue) !c.JSValue {
        const item = try js.object(self.engine);
        errdefer self.engine.freeValue(item);
        try self.text(item, "text", text_units);
        try js.define(self.engine, item, "tokens", try self.queueInline(text_units));
        try js.define(self.engine, item, "header", c.pi_js_bool(self.engine.context, @intFromBool(header)));
        try js.define(self.engine, item, "align", c.JS_DupValue(self.engine.context, alignment));
        return item;
    }
    fn table(self: *Lexer, source: []const u16) !?c.JSValue {
        var matched = try self.grammar.matchRule(.block, "table", source);
        const cap = if (matched) |*value| value else return null;
        defer cap.deinit();
        if (!try self.matches(.other, "tableDelimiter", cap.group(source, 2))) return null;
        const headers = try self.splitCells(cap.group(source, 1), null);
        defer {
            for (headers) |value| self.engine.gpa.free(value);
            self.engine.gpa.free(headers);
        }
        const aligned = try self.replaceRule(.other, "tableAlignChars", cap.group(source, 2), &.{});
        defer self.engine.gpa.free(aligned);
        var alignments: std.ArrayList(c.JSValue) = .empty;
        defer {
            for (alignments.items) |value| self.engine.freeValue(value);
            alignments.deinit(self.engine.gpa);
        }
        var columns = std.mem.splitScalar(u16, aligned, '|');
        while (columns.next()) |column| {
            const alignment = if (try self.matches(.other, "tableAlignRight", column)) try v.text(self.engine, "right") else if (try self.matches(.other, "tableAlignCenter", column)) try v.text(self.engine, "center") else if (try self.matches(.other, "tableAlignLeft", column)) try v.text(self.engine, "left") else c.pi_js_null();
            try alignments.append(self.engine.gpa, alignment);
        }
        if (headers.len != alignments.items.len) return null;
        const item = try self.token("table", rtrim(cap.group(source, 0), '\n'));
        errdefer self.engine.freeValue(item);
        const header = try js.array(self.engine);
        try js.define(self.engine, item, "header", header);
        const aligns = try js.array(self.engine);
        try js.define(self.engine, item, "align", aligns);
        const rows = try js.array(self.engine);
        try js.define(self.engine, item, "rows", rows);
        for (headers, alignments.items) |label, alignment| {
            try js.push(self.engine, aligns, alignment);
            const entry = try self.cell(label, true, alignment);
            defer self.engine.freeValue(entry);
            try js.push(self.engine, header, entry);
        }
        if (trim(cap.group(source, 3)).len > 0) {
            const row_source = try self.replaceRule(.other, "tableRowBlankLine", cap.group(source, 3), &.{});
            defer self.engine.gpa.free(row_source);
            var lines = std.mem.splitScalar(u16, row_source, '\n');
            while (lines.next()) |line| {
                const cells = try self.splitCells(line, headers.len);
                defer {
                    for (cells) |value| self.engine.gpa.free(value);
                    self.engine.gpa.free(cells);
                }
                const row = try js.array(self.engine);
                defer self.engine.freeValue(row);
                for (cells, alignments.items) |label, alignment| {
                    const entry = try self.cell(label, false, alignment);
                    defer self.engine.freeValue(entry);
                    try js.push(self.engine, row, entry);
                }
                try js.push(self.engine, rows, row);
            }
        }
        return item;
    }
    fn trimEnd(source: []const u16) []const u16 {
        var end = source.len;
        while (end > 0 and @import("../tui/utf16_input.zig").State.whitespace(source[end - 1])) end -= 1;
        return source[0..end];
    }
    fn lineOf(source: []const u16) []const u16 {
        return source[0 .. std.mem.indexOfScalar(u16, source, '\n') orelse source.len];
    }
    fn firstNonSpace(source: []const u16) ?usize {
        for (source, 0..) |unit, index| if (unit != ' ') return index;
        return null;
    }
    fn expandTabs(self: *Lexer, source: []const u16, indent: usize, fixed: bool) ![]u16 {
        var output: std.ArrayList(u16) = .empty;
        errdefer output.deinit(self.engine.gpa);
        var column = indent;
        for (source) |unit| {
            if (unit == '\t') {
                const width = if (fixed) @as(usize, 4) else 4 - column % 4;
                try output.appendNTimes(self.engine.gpa, ' ', width);
                column += width;
            } else {
                try output.append(self.engine.gpa, unit);
                column += 1;
            }
        }
        return output.toOwnedSlice(self.engine.gpa);
    }
    fn boundary(self: *Lexer, line: []const u16, indent: usize, all: bool) !bool {
        const suffix: []const u8 = if (all) "(?:```|~~~|#|<(?:[a-z].*>|!--)|>|(?:[*+-]|\\d{1,9}[.)])((?:[ \\t][^\\n]*)?(?:\\n|$))|((?:- *){3,}|(?:_ *){3,}|(?:\\* *){3,})(?:\\n+|$))" else "(?:```|~~~|#|((?:- *){3,}|(?:_ *){3,}|(?:\\* *){3,})(?:\\n+|$))";
        const pattern = try std.fmt.allocPrint(self.engine.gpa, "^ {{0,{d}}}{s}", .{ @min(3, indent -| 1), suffix });
        defer self.engine.gpa.free(pattern);
        var matched = try self.grammar.match(pattern, "i", line, 0);
        if (matched) |*cap| {
            cap.deinit();
            return true;
        }
        return false;
    }
    fn list(self: *Lexer, original: []const u16) anyerror!?c.JSValue {
        var initial = try self.grammar.matchRule(.block, "list", original);
        const first = if (initial) |*value| value else return null;
        defer first.deinit();
        const bullet = trim(first.group(original, 1));
        const ordered = bullet.len > 1;
        const bullet_pattern = if (ordered) try std.fmt.allocPrint(self.engine.gpa, "\\d{{1,9}}\\{c}", .{@as(u8, @intCast(bullet[bullet.len - 1]))}) else try std.fmt.allocPrint(self.engine.gpa, "\\{c}", .{@as(u8, @intCast(bullet[0]))});
        defer self.engine.gpa.free(bullet_pattern);
        const item_pattern = try std.fmt.allocPrint(self.engine.gpa, "^( {{0,3}}{s})((?:[\\t ][^\\n]*)?(?:\\n|$))", .{bullet_pattern});
        defer self.engine.gpa.free(item_pattern);
        const result = try self.token("list", &.{});
        errdefer self.engine.freeValue(result);
        try js.define(self.engine, result, "ordered", c.pi_js_bool(self.engine.context, @intFromBool(ordered)));
        var start: usize = 0;
        if (ordered) for (bullet[0 .. bullet.len - 1]) |digit| {
            start = start * 10 + digit - '0';
        };
        try js.define(self.engine, result, "start", if (ordered) v.numeric(self.engine, @floatFromInt(start)) else try v.text(self.engine, ""));
        try js.define(self.engine, result, "loose", c.pi_js_bool(self.engine.context, 0));
        const items = try js.array(self.engine);
        try js.define(self.engine, result, "items", items);
        var native_items: std.ArrayList(c.JSValue) = .empty;
        defer {
            for (native_items.items) |item| self.engine.freeValue(item);
            native_items.deinit(self.engine.gpa);
        }
        var source = original;
        var loose = false;
        var ends_blank = false;
        while (source.len > 0) {
            var matched = try self.grammar.match(item_pattern, "", source, 0);
            const cap = if (matched) |*value| value else break;
            defer cap.deinit();
            if (try self.matches(.block, "hr", source)) break;
            var raw: std.ArrayList(u16) = .empty;
            defer raw.deinit(self.engine.gpa);
            var contents: std.ArrayList(u16) = .empty;
            defer contents.deinit(self.engine.gpa);
            try raw.appendSlice(self.engine.gpa, cap.group(source, 0));
            var line = try self.expandTabs(lineOf(cap.group(source, 2)), cap.group(source, 1).len, false);
            defer self.engine.gpa.free(line);
            const bullet_length = cap.group(source, 1).len;
            source = source[cap.group(source, 0).len..];
            var blank = trim(line).len == 0;
            var indent = bullet_length + 1;
            if (!blank) {
                const spaces = firstNonSpace(line) orelse 0;
                const leading = if (spaces > 4) @as(usize, 1) else spaces;
                try contents.appendSlice(self.engine.gpa, line[@min(leading, line.len)..]);
                indent = leading + bullet_length;
            }
            const next_line = lineOf(source);
            if (blank and try self.matches(.other, "blankLine", next_line)) {
                try raw.appendSlice(self.engine.gpa, next_line);
                try raw.append(self.engine.gpa, '\n');
                source = source[@min(next_line.len + 1, source.len)..];
            } else while (source.len > 0) {
                const raw_line = lineOf(source);
                const next = try self.expandTabs(raw_line, 0, true);
                defer self.engine.gpa.free(next);
                if (try self.boundary(raw_line, indent, true)) break;
                if ((firstNonSpace(next) orelse 0) >= indent or trim(raw_line).len == 0) {
                    try contents.append(self.engine.gpa, '\n');
                    try contents.appendSlice(self.engine.gpa, next[@min(indent, next.len)..]);
                } else {
                    if (blank or (firstNonSpace(line) orelse 0) >= 4 or try self.boundary(line, indent, false)) break;
                    try contents.append(self.engine.gpa, '\n');
                    try contents.appendSlice(self.engine.gpa, raw_line);
                }
                blank = trim(raw_line).len == 0;
                try raw.appendSlice(self.engine.gpa, raw_line);
                try raw.append(self.engine.gpa, '\n');
                source = source[@min(raw_line.len + 1, source.len)..];
                const replacement = try self.engine.gpa.dupe(u16, next[@min(indent, next.len)..]);
                self.engine.gpa.free(line);
                line = replacement;
            }
            if (!loose) {
                if (ends_blank) loose = true else if (try self.matches(.other, "doubleBlankLine", raw.items)) ends_blank = true;
            }
            const item = try self.token("list_item", raw.items);
            errdefer self.engine.freeValue(item);
            try js.define(self.engine, item, "task", c.pi_js_bool(self.engine.context, @intFromBool(try self.matches(.other, "listIsTask", contents.items))));
            try js.define(self.engine, item, "loose", c.pi_js_bool(self.engine.context, 0));
            try self.text(item, "text", contents.items);
            try js.define(self.engine, item, "tokens", try js.array(self.engine));
            try native_items.append(self.engine.gpa, item);
            try js.push(self.engine, items, item);
        }
        if (native_items.items.len == 0) {
            self.engine.freeValue(result);
            return null;
        }
        const final_item = native_items.items[native_items.items.len - 1];
        inline for (.{ "raw", "text" }) |name| {
            const value = try self.field(final_item, name);
            defer self.engine.gpa.free(value);
            try v.set(self.engine, final_item, name, try utf16.string(self.engine, trimEnd(value)));
        }
        try v.set(self.engine, result, "raw", try utf16.string(self.engine, trimEnd(original[0 .. original.len - source.len])));
        for (native_items.items) |item| {
            const content = try self.field(item, "text");
            defer self.engine.gpa.free(content);
            const children = try js.get(self.engine, item, "tokens");
            defer self.engine.freeValue(children);
            self.top = false;
            try self.block(content, children);
            const length_value = try js.get(self.engine, children, "length");
            defer self.engine.freeValue(length_value);
            const length: usize = @intFromFloat(try v.number(self.engine, length_value));
            for (0..length) |index| {
                const child = try v.fieldAt(self.engine, children, @floatFromInt(index));
                defer self.engine.freeValue(child);
                if (try self.sameType(child, "space")) {
                    const raw = try self.field(child, "raw");
                    defer self.engine.gpa.free(raw);
                    if (try self.matches(.other, "anyLine", raw)) loose = true;
                }
            }
        }
        for (native_items.items) |item| {
            const task = try js.get(self.engine, item, "task");
            defer self.engine.freeValue(task);
            const children = try js.get(self.engine, item, "tokens");
            defer self.engine.freeValue(children);
            const first_child = try v.fieldAt(self.engine, children, 0);
            defer self.engine.freeValue(first_child);
            if (c.JS_ToBool(self.engine.context, task) != 0) {
                if (try self.sameType(first_child, "text") or try self.sameType(first_child, "paragraph")) {
                    inline for (.{ "text", "raw" }) |name| {
                        const value = try self.field(first_child, name);
                        defer self.engine.gpa.free(value);
                        const replaced = try self.replaceRule(.other, "listReplaceTask", value, &.{});
                        defer self.engine.gpa.free(replaced);
                        try v.set(self.engine, first_child, name, try utf16.string(self.engine, replaced));
                    }
                    const content = try self.field(item, "text");
                    defer self.engine.gpa.free(content);
                    const replaced = try self.replaceRule(.other, "listReplaceTask", content, &.{});
                    defer self.engine.gpa.free(replaced);
                    try v.set(self.engine, item, "text", try utf16.string(self.engine, replaced));
                    var queue_index = self.pending.items.len;
                    while (queue_index > 0) {
                        queue_index -= 1;
                        const pending = &self.pending.items[queue_index];
                        if (try self.matches(.other, "listIsTask", pending.text)) {
                            const replacement = try self.replaceRule(.other, "listReplaceTask", pending.text, &.{});
                            self.engine.gpa.free(pending.text);
                            pending.text = replacement;
                            break;
                        }
                    }
                    const raw = try self.field(item, "raw");
                    defer self.engine.gpa.free(raw);
                    var task_match = try self.grammar.matchRule(.other, "listTaskCheckbox", raw);
                    if (task_match) |*cap| {
                        defer cap.deinit();
                        const check_raw = try std.mem.concat(self.engine.gpa, u16, &.{ cap.group(raw, 0), &.{' '} });
                        defer self.engine.gpa.free(check_raw);
                        const checked = !std.mem.eql(u16, cap.group(raw, 0), &.{ '[', ' ', ']' });
                        const checkbox = try self.token("checkbox", check_raw);
                        defer self.engine.freeValue(checkbox);
                        try js.define(self.engine, checkbox, "checked", c.pi_js_bool(self.engine.context, @intFromBool(checked)));
                        try js.define(self.engine, item, "checked", c.pi_js_bool(self.engine.context, @intFromBool(checked)));
                        if (loose) {
                            inline for (.{ "raw", "text" }) |name| {
                                const value = try self.field(first_child, name);
                                defer self.engine.gpa.free(value);
                                const replacement = try std.mem.concat(self.engine.gpa, u16, &.{ check_raw, value });
                                defer self.engine.gpa.free(replacement);
                                try v.set(self.engine, first_child, name, try utf16.string(self.engine, replacement));
                            }
                            const inline_tokens = try js.get(self.engine, first_child, "tokens");
                            defer self.engine.freeValue(inline_tokens);
                            try v.invokeVoid(self.engine, inline_tokens, "unshift", &.{checkbox});
                        } else try v.invokeVoid(self.engine, children, "unshift", &.{checkbox});
                    }
                } else try v.set(self.engine, item, "task", c.pi_js_bool(self.engine.context, 0));
            }
            if (loose) {
                try v.set(self.engine, item, "loose", c.pi_js_bool(self.engine.context, 1));
                const length_value = try js.get(self.engine, children, "length");
                defer self.engine.freeValue(length_value);
                const length: usize = @intFromFloat(try v.number(self.engine, length_value));
                for (0..length) |index| {
                    const child = try v.fieldAt(self.engine, children, @floatFromInt(index));
                    defer self.engine.freeValue(child);
                    if (try self.sameType(child, "text")) try v.set(self.engine, child, "type", try v.text(self.engine, "paragraph"));
                }
            }
        }
        try v.set(self.engine, result, "loose", c.pi_js_bool(self.engine.context, @intFromBool(loose)));
        return result;
    }
    fn inlineText(self: *Lexer, tokens: c.JSValue, raw: []const u16, escaped: bool) !void {
        const previous = try self.last(tokens);
        defer self.engine.freeValue(previous);
        if (try self.sameType(previous, "text")) {
            try self.appendField(previous, "raw", raw, &.{});
            try self.appendField(previous, "text", raw, &.{});
        } else {
            const item = try self.token("text", raw);
            defer self.engine.freeValue(item);
            try self.text(item, "text", raw);
            try js.define(self.engine, item, "escaped", c.pi_js_bool(self.engine.context, @intFromBool(escaped)));
            try js.push(self.engine, tokens, item);
        }
    }
    fn outputLink(self: *Lexer, raw: []const u16, label: []const u16, href: []const u16, title: []const u16) !?c.JSValue {
        const content = try self.replaceRule(.other, "outputLinkReplace", label, &.{ '$', '1' });
        defer self.engine.gpa.free(content);
        const image = raw[0] == '!';
        const outer_emitted = self.link_emitted;
        const outer_raw = self.in_raw_block;
        self.in_link = true;
        self.link_emitted = false;
        const children = try js.array(self.engine);
        errdefer self.engine.freeValue(children);
        self.inlineTokens(content, children) catch |err| {
            self.link_emitted = outer_emitted;
            self.in_link = false;
            return err;
        };
        const child_link = self.link_emitted;
        self.link_emitted = outer_emitted;
        self.in_link = false;
        if (!image and child_link) {
            self.in_raw_block = outer_raw;
            self.engine.freeValue(children);
            return null;
        }
        if (!image) self.link_emitted = true;
        const item = try self.token(if (image) "image" else "link", raw);
        errdefer self.engine.freeValue(item);
        try self.text(item, "href", href);
        try js.define(self.engine, item, "title", if (title.len > 0) try utf16.string(self.engine, title) else c.pi_js_null());
        try self.text(item, "text", content);
        try js.define(self.engine, item, "tokens", children);
        return item;
    }
    fn directLink(self: *Lexer, source: []const u16) !?c.JSValue {
        var matched = try self.grammar.matchRule(.inline_rule, "link", source);
        const cap = if (matched) |*value| value else return null;
        defer cap.deinit();
        var raw = cap.group(source, 0);
        var href = cap.group(source, 2);
        var title = cap.group(source, 3);
        const trimmed = trim(href);
        if (try self.matches(.other, "startAngleBracket", trimmed)) {
            if (!try self.matches(.other, "endAngleBracket", trimmed)) return null;
            if ((trimmed.len - rtrim(trimmed[0 .. trimmed.len - 1], '\\').len) % 2 == 0) return null;
        } else if (std.mem.indexOfScalar(u16, href, ')') != null) {
            var level: isize = 0;
            var at: usize = 0;
            var closing: ?usize = null;
            while (at < href.len) : (at += 1) {
                if (href[at] == '\\') {
                    at += 1;
                } else if (href[at] == '(') {
                    level += 1;
                } else if (href[at] == ')') {
                    level -= 1;
                    if (level < 0) {
                        closing = at;
                        break;
                    }
                }
            }
            if (level > 0) return null;
            if (closing) |end| {
                href = href[0..end];
                raw = trim(raw[0 .. (if (raw[0] == '!') @as(usize, 5) else 4) + cap.group(source, 1).len + end]);
                title = &.{};
            }
        }
        href = trim(href);
        if (try self.matches(.other, "startAngleBracket", href)) href = href[1 .. href.len - 1];
        const unescaped_href = try self.replaceRule(.inline_rule, "anyPunctuation", href, &.{ '$', '1' });
        defer self.engine.gpa.free(unescaped_href);
        const unescaped_title = try self.replaceRule(.inline_rule, "anyPunctuation", if (title.len > 0) title[1 .. title.len - 1] else &.{}, &.{ '$', '1' });
        defer self.engine.gpa.free(unescaped_title);
        return self.outputLink(raw, cap.group(source, 1), unescaped_href, unescaped_title);
    }
    fn referenceLink(self: *Lexer, source: []const u16) !?c.JSValue {
        var matched = try self.grammar.matchRule(.inline_rule, "reflink", source);
        if (matched == null) matched = try self.grammar.matchRule(.inline_rule, "nolink", source);
        const cap = if (matched) |*value| value else return null;
        defer cap.deinit();
        const normalized = try self.replaceRule(.other, "multipleSpaceGlobal", if (cap.group(source, 2).len > 0) cap.group(source, 2) else cap.group(source, 1), &.{' '});
        defer self.engine.gpa.free(normalized);
        const text_value = try utf16.string(self.engine, normalized);
        defer self.engine.freeValue(text_value);
        const key = try js.invoke(self.engine, text_value, "toLowerCase", &.{});
        defer self.engine.freeValue(key);
        const link = try js.getKey(self.engine, self.links, key);
        defer self.engine.freeValue(link);
        if (c.JS_IsUndefined(link)) {
            const item = try self.token("text", source[0..1]);
            errdefer self.engine.freeValue(item);
            try self.text(item, "text", source[0..1]);
            return item;
        }
        const href = try self.field(link, "href");
        defer self.engine.gpa.free(href);
        const title_value = try js.get(self.engine, link, "title");
        defer self.engine.freeValue(title_value);
        const title = if (c.JS_IsUndefined(title_value)) try self.engine.gpa.dupe(u16, &.{}) else try utf16.unitsAlloc(self.engine, title_value);
        defer self.engine.gpa.free(title);
        return self.outputLink(cap.group(source, 0), cap.group(source, 1), href, title);
    }
    fn autoLink(self: *Lexer, source: []const u16, bare: bool) !?c.JSValue {
        var matched = try self.grammar.matchRule(.inline_rule, if (bare) "url" else "autolink", source);
        const cap = if (matched) |*value| value else return null;
        defer cap.deinit();
        var raw = cap.group(source, 0);
        const email = std.mem.eql(u16, cap.group(source, 2), &.{'@'});
        if (bare and !email) {
            while (true) {
                var backpedal = try self.grammar.matchRule(.inline_rule, "_backpedal", raw);
                const shorter = if (backpedal) |*value| value else return error.NativeMarkdownLexerNoProgress;
                defer shorter.deinit();
                const next = shorter.group(raw, 0);
                if (next.len == raw.len) break;
                raw = next;
            }
        }
        const content = if (bare) raw else cap.group(source, 1);
        const prefix: []const u16 = if (email) std.unicode.utf8ToUtf16LeStringLiteral("mailto:") else if (bare and std.mem.eql(u16, cap.group(source, 1), std.unicode.utf8ToUtf16LeStringLiteral("www."))) std.unicode.utf8ToUtf16LeStringLiteral("http://") else &.{};
        const href = try std.mem.concat(self.engine.gpa, u16, &.{ prefix, content });
        defer self.engine.gpa.free(href);
        const item = try self.token("link", raw);
        errdefer self.engine.freeValue(item);
        try self.text(item, "text", content);
        try self.text(item, "href", href);
        const children = try js.array(self.engine);
        errdefer self.engine.freeValue(children);
        const child = try self.token("text", content);
        defer self.engine.freeValue(child);
        try self.text(child, "text", content);
        try js.push(self.engine, children, child);
        try js.define(self.engine, item, "tokens", children);
        return item;
    }
    fn referenceKeyPresent(self: *Lexer, label: []const u16) !bool {
        const key = try utf16.string(self.engine, label);
        defer self.engine.freeValue(key);
        return js.hasKey(self.engine, self.links, key);
    }
    fn linkInText(self: *Lexer, source: []const u16) anyerror!bool {
        if (std.mem.indexOfScalar(u16, source, '[') == null) return false;
        const skip = self.grammar.rule(.inline_rule, "blockSkip").object;
        var at: usize = 0;
        while (at <= source.len) {
            var matched = try self.grammar.match(skip.get("source").?.string, skip.get("flags").?.string, source, at);
            const cap = if (matched) |*value| value else break;
            defer cap.deinit();
            const span = cap.ranges[0].?;
            if (try self.matches(.inline_rule, "link", cap.group(source, 0)) and (span.start == 0 or source[span.start - 1] != '!')) return true;
            at = span.end;
            if (span.start == span.end) at += 1;
        }
        const reference = self.grammar.rule(.inline_rule, "reflinkSearch").object;
        at = 0;
        while (at <= source.len) {
            var matched = try self.grammar.match(reference.get("source").?.string, reference.get("flags").?.string, source, at);
            const cap = if (matched) |*value| value else break;
            defer cap.deinit();
            const raw = cap.group(source, 0);
            const span = cap.ranges[0].?;
            at = span.end;
            if (span.start == span.end) at += 1;
            const ref_start = std.mem.lastIndexOfScalar(u16, raw, '[') orelse continue;
            if (raw[0] == '!' or !try self.referenceKeyPresent(raw[ref_start + 1 .. raw.len - 1])) continue;
            if (ref_start > 1 and try self.linkInText(raw[1 .. ref_start - 1])) continue;
            return true;
        }
        return false;
    }
    fn maskReferences(self: *Lexer, source: []const u16) anyerror![]u16 {
        const result = try self.engine.gpa.dupe(u16, source);
        errdefer self.engine.gpa.free(result);
        if (std.mem.indexOfScalar(u16, source, '[') == null) return result;
        const rule = self.grammar.rule(.inline_rule, "reflinkSearch").object;
        var at: usize = 0;
        while (at <= source.len) {
            var matched = try self.grammar.match(rule.get("source").?.string, rule.get("flags").?.string, source, at);
            const cap = if (matched) |*value| value else break;
            defer cap.deinit();
            const span = cap.ranges[0].?;
            const raw = cap.group(source, 0);
            at = span.end;
            if (span.start == span.end) at += 1;
            const ref_start = std.mem.lastIndexOfScalar(u16, raw, '[') orelse continue;
            if (!try self.referenceKeyPresent(raw[ref_start + 1 .. raw.len - 1])) continue;
            if (ref_start > 1 and raw[0] != '!') {
                const content = raw[1 .. ref_start - 1];
                if (try self.linkInText(content)) {
                    const inner = try self.maskReferences(content);
                    defer self.engine.gpa.free(inner);
                    result[span.start] = '[';
                    @memcpy(result[span.start + 1 .. span.start + 1 + inner.len], inner);
                    const suffix = span.start + 1 + inner.len;
                    result[suffix] = ']';
                    result[suffix + 1] = '[';
                    @memset(result[suffix + 2 .. span.end - 1], 'a');
                    result[span.end - 1] = ']';
                    continue;
                }
            }
            result[span.start] = '[';
            @memset(result[span.start + 1 .. span.end - 1], 'a');
            result[span.end - 1] = ']';
        }
        return result;
    }
    fn mask(self: *Lexer, source: []const u16) ![]u16 {
        const result = try self.maskReferences(source);
        errdefer self.engine.gpa.free(result);
        inline for (.{ "anyPunctuation", "blockSkip" }) |name| {
            const rule = self.grammar.rule(.inline_rule, name).object;
            var start: usize = 0;
            while (start <= source.len) {
                var matched = try self.grammar.match(rule.get("source").?.string, rule.get("flags").?.string, result, start);
                const cap = if (matched) |*value| value else break;
                defer cap.deinit();
                const span = cap.ranges[0].?;
                if (comptime std.mem.eql(u8, name, "anyPunctuation")) {
                    @memset(result[span.start..span.end], '+');
                } else {
                    const offset = cap.group(result, 2).len;
                    if (span.end >= span.start + offset + 2) {
                        result[span.start + offset] = '[';
                        @memset(result[span.start + offset + 1 .. span.end - 1], 'a');
                        result[span.end - 1] = ']';
                    }
                }
                start = span.end;
                if (span.start == span.end) start += 1;
            }
        }
        return result;
    }
    fn scalarLength(source: []const u16) usize {
        var count: usize = 0;
        var at: usize = 0;
        while (at < source.len) : (at += 1) {
            count += 1;
            if (source[at] >= 0xd800 and source[at] <= 0xdbff and at + 1 < source.len and source[at + 1] >= 0xdc00 and source[at + 1] <= 0xdfff) at += 1;
        }
        return count;
    }
    fn delimiter(self: *Lexer, source: []const u16, masked: []const u16, previous: []const u16, deletion: bool) !?c.JSValue {
        var left_match = try self.grammar.matchRule(.inline_rule, if (deletion) "delLDelim" else "emStrongLDelim", source);
        const left = if (left_match) |*value| value else return null;
        defer left.deinit();
        if (!deletion) {
            if (left.group(source, 1).len == 0 and left.group(source, 2).len == 0 and left.group(source, 3).len == 0 and left.group(source, 4).len == 0) return null;
            if (left.group(source, 4).len > 0 and try self.matches(.other, "unicodeAlphaNumeric", previous)) return null;
        }
        const next = if (left.group(source, 1).len > 0) left.group(source, 1) else if (!deletion) left.group(source, 3) else &.{};
        if (next.len > 0 and previous.len > 0 and !try self.matches(.inline_rule, "punctuation", previous)) return null;
        const left_length = scalarLength(left.group(source, 0)) - 1;
        const mid_run = previous.len == 1 and previous[0] == source[0];
        const rule = self.grammar.rule(.inline_rule, if (deletion) "delRDelim" else if (source[0] == '*') "emStrongRDelimAst" else "emStrongRDelimUnd").object;
        var total: isize = @intCast(left_length);
        var mid_total: usize = 0;
        const clipped = masked[masked.len - source.len + left_length ..];
        var at: usize = 0;
        while (at <= clipped.len) {
            var matched = try self.grammar.match(rule.get("source").?.string, rule.get("flags").?.string, clipped, at);
            const cap = if (matched) |*value| value else break;
            defer cap.deinit();
            const span = cap.ranges[0].?;
            at = span.end;
            if (span.start == span.end) at += 1;
            var right: []const u16 = &.{};
            for (1..7) |index| if (cap.group(clipped, index).len > 0) {
                right = cap.group(clipped, index);
                break;
            };
            if (right.len == 0) continue;
            var right_length = scalarLength(right);
            if (deletion and right_length != left_length) continue;
            if (cap.group(clipped, 3).len > 0 or cap.group(clipped, 4).len > 0) {
                total += @intCast(right_length);
                continue;
            } else if (!deletion and (cap.group(clipped, 5).len > 0 or cap.group(clipped, 6).len > 0)) {
                if (left_length % 3 != 0 and (left_length + right_length) % 3 == 0) {
                    mid_total += right_length;
                    continue;
                }
                if (mid_run) break;
            }
            total -= @intCast(right_length);
            if (total > 0) continue;
            right_length = @min(right_length, @as(usize, @intCast(@as(isize, @intCast(right_length + mid_total)) + total)));
            const matched_raw = cap.group(clipped, 0);
            const first_width: usize = if (matched_raw.len >= 2 and matched_raw[0] >= 0xd800 and matched_raw[0] <= 0xdbff and matched_raw[1] >= 0xdc00 and matched_raw[1] <= 0xdfff) 2 else 1;
            const raw = source[0 .. left_length + span.start + first_width + right_length];
            const border = if (deletion) left_length else if (@min(left_length, right_length) % 2 != 0) @as(usize, 1) else 2;
            const content = raw[border .. raw.len - border];
            const item = try self.token(if (deletion) "del" else if (border == 1) "em" else "strong", raw);
            errdefer self.engine.freeValue(item);
            try self.text(item, "text", content);
            const children = try js.array(self.engine);
            errdefer self.engine.freeValue(children);
            try self.inlineTokens(content, children);
            try js.define(self.engine, item, "tokens", children);
            return item;
        }
        return null;
    }
    pub fn inlineTokens(self: *Lexer, original: []const u16, tokens: c.JSValue) anyerror!void {
        self.depth += 1;
        defer self.depth -= 1;
        if (self.depth > 128) return error.NativeMarkdownNestingLimit;
        var source = original;
        const masked = try self.mask(original);
        defer self.engine.gpa.free(masked);
        var previous: []const u16 = &.{};
        var keep_previous = false;
        while (source.len != 0) {
            if (!keep_previous) previous = &.{};
            keep_previous = false;
            if (try self.latex(source, false)) |item| {
                defer self.engine.freeValue(item);
                const raw = try self.field(item, "raw");
                defer self.engine.gpa.free(raw);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            var matched = try self.grammar.matchRule(.inline_rule, "escape", source);
            if (matched) |*cap| {
                defer cap.deinit();
                const raw = cap.group(source, 0);
                const item = try self.token("escape", raw);
                defer self.engine.freeValue(item);
                try self.text(item, "text", cap.group(source, 1));
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            matched = try self.grammar.matchRule(.inline_rule, "tag", source);
            if (matched) |*cap| {
                defer cap.deinit();
                const raw = cap.group(source, 0);
                if (!self.in_link and try self.matches(.other, "startATag", raw)) {
                    self.in_link = true;
                } else if (self.in_link and try self.matches(.other, "endATag", raw)) self.in_link = false;
                if (!self.in_raw_block and try self.matches(.other, "startPreScriptTag", raw)) {
                    self.in_raw_block = true;
                } else if (self.in_raw_block and try self.matches(.other, "endPreScriptTag", raw)) self.in_raw_block = false;
                const item = try self.token("html", raw);
                defer self.engine.freeValue(item);
                try js.define(self.engine, item, "inLink", c.pi_js_bool(self.engine.context, @intFromBool(self.in_link)));
                try js.define(self.engine, item, "inRawBlock", c.pi_js_bool(self.engine.context, @intFromBool(self.in_raw_block)));
                try js.define(self.engine, item, "block", c.pi_js_bool(self.engine.context, 0));
                try self.text(item, "text", raw);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            // These paths are implemented independently before public admission.
            if (try self.directLink(source)) |item| {
                defer self.engine.freeValue(item);
                const raw = try self.field(item, "raw");
                defer self.engine.gpa.free(raw);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            if (try self.referenceLink(source)) |item| {
                defer self.engine.freeValue(item);
                const raw = try self.field(item, "raw");
                defer self.engine.gpa.free(raw);
                const last_item = try self.last(tokens);
                defer self.engine.freeValue(last_item);
                if (try self.sameType(item, "text") and try self.sameType(last_item, "text")) {
                    try self.appendField(last_item, "raw", raw, &.{});
                    try self.appendField(last_item, "text", raw, &.{});
                } else try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            if (try self.delimiter(source, masked, previous, false)) |item| {
                defer self.engine.freeValue(item);
                const raw = try self.field(item, "raw");
                defer self.engine.gpa.free(raw);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            matched = try self.grammar.matchRule(.inline_rule, "code", source);
            if (matched) |*cap| {
                defer cap.deinit();
                const raw = cap.group(source, 0);
                const content = try self.engine.gpa.dupe(u16, cap.group(source, 2));
                defer self.engine.gpa.free(content);
                for (content) |*unit| if (unit.* == '\n') {
                    unit.* = ' ';
                };
                var has_non_space = false;
                for (content) |unit| if (unit != ' ') {
                    has_non_space = true;
                };
                const padded = content.len >= 2 and content[0] == ' ' and content[content.len - 1] == ' ';
                const item = try self.token("codespan", raw);
                defer self.engine.freeValue(item);
                try self.text(item, "text", if (has_non_space and padded) content[1 .. content.len - 1] else content);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            matched = try self.grammar.matchRule(.inline_rule, "br", source);
            if (matched) |*cap| {
                defer cap.deinit();
                const raw = cap.group(source, 0);
                const item = try self.token("br", raw);
                defer self.engine.freeValue(item);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            var strict_delete = try self.grammar.match("^(~~)(?=[^\\s~])((?:\\\\.|[^\\\\])*?(?:\\\\.|[^\\s~\\\\]))\\1(?=[^~]|$)", "", source, 0);
            if (strict_delete) |*cap| {
                defer cap.deinit();
                const raw = cap.group(source, 0);
                const content = cap.group(source, 2);
                const item = try self.token("del", raw);
                defer self.engine.freeValue(item);
                try self.text(item, "text", content);
                const children = try js.array(self.engine);
                errdefer self.engine.freeValue(children);
                try self.inlineTokens(content, children);
                try js.define(self.engine, item, "tokens", children);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            if (try self.autoLink(source, false)) |item| {
                defer self.engine.freeValue(item);
                const raw = try self.field(item, "raw");
                defer self.engine.gpa.free(raw);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            if (!self.in_link) if (try self.autoLink(source, true)) |item| {
                defer self.engine.freeValue(item);
                const raw = try self.field(item, "raw");
                defer self.engine.gpa.free(raw);
                try js.push(self.engine, tokens, item);
                source = source[@min(raw.len, source.len)..];
                continue;
            };
            var clipped = source;
            var at: usize = 1;
            while (at < source.len) : (at += 1) {
                if (source[at] == '$' or (source[at] == '\\' and at + 1 < source.len and (source[at + 1] == '(' or source[at + 1] == '['))) {
                    clipped = source[0..at];
                    break;
                }
            }
            matched = try self.grammar.matchRule(.inline_rule, "text", clipped);
            if (matched) |*cap| {
                defer cap.deinit();
                const raw = cap.group(source, 0);
                if (raw.len == 0) return error.NativeMarkdownLexerNoProgress;
                try self.inlineText(tokens, raw, self.in_raw_block);
                if (raw[raw.len - 1] != '_') previous = raw[raw.len - 1 ..];
                keep_previous = true;
                source = source[@min(raw.len, source.len)..];
                continue;
            }
            return error.NativeMarkdownLexerNoProgress;
        }
    }
};
fn lexCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return lexValue(engine, if (argc == 0) c.pi_js_undefined() else argv[0]) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return c.JS_ThrowTypeError(context, "Native Markdown development: %s", @as([*:0]const u8, @errorName(err)));
    };
}
fn lexValue(engine: *Engine, value: c.JSValue) !c.JSValue {
    var lexer = try Lexer.init(engine);
    defer lexer.deinit();
    const units = try utf16.unitsAlloc(engine, value);
    defer engine.gpa.free(units);
    return lexer.lex(units);
}
test "Source6fb native Markdown lexer compares every original token graph without a text fallback" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/markdown-component-original-6fb.json");
    try js.define(engine, root, "markdownFixture", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "markdown-component-original-6fb.json")));
    const source_tests = @embedFile("fixtures/markdown-source-tests-original-6fb.json");
    try js.define(engine, root, "markdownSourceTests", try engine.checked(c.JS_ParseJSON(engine.context, source_tests.ptr, source_tests.len, "markdown-source-tests-original-6fb.json")));
    const adversarial = @embedFile("fixtures/markdown-adversarial-original-6fb.json");
    try js.define(engine, root, "markdownAdversarial", try engine.checked(c.JS_ParseJSON(engine.context, adversarial.ptr, adversarial.len, "markdown-adversarial-original-6fb.json")));
    try js.define(engine, root, "nativeLex", try engine.checked(c.JS_NewCFunction(engine.context, lexCall, "nativeLex", 1)));
    const result = engine.evalModule(
        \\const seen=new Set(),failures=[];for(const[index,item]of [...markdownFixture.cases,...markdownSourceTests.cases,...markdownAdversarial.cases].entries()){if(item.hasTransform||seen.has(item.text)||item.tokens===null)continue;seen.add(item.text);let actual;try{actual=nativeLex(item.text.replace(/\t/g,'   '))}catch(e){failures.push({index,text:item.text,error:String(e)});continue}if(JSON.stringify(actual)!==JSON.stringify(item.tokens)||JSON.stringify(actual.links)!==JSON.stringify(item.links))failures.push({index,text:item.text,actual,actualLinks:actual.links,expected:item.tokens,expectedLinks:item.links});}if(failures.length)throw Error(JSON.stringify({count:failures.length,first:failures.slice(0,8)}));
    , "native-markdown-token-conformance.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Markdown token conformance: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
