//! Source1692 syntax-highlight.ts HTML/theme formatter and html.ts entities.
//! Private formatter only; the highlight.js grammar engine remains separate.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temporary = @import("native_highlight_scope.zig");
const Scope = temporary.Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;

fn op(scope: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, operation, left, right)));
}
fn key(scope: *Scope, object: c.JSValue, name: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, object, name));
}
fn integer(scope: *Scope, value: i32) c.JSValue {
    return c.JS_NewInt32(scope.engine.context, value);
}
fn equalsText(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn regex(scope: *Scope, pattern: []const u8) !c.JSValue {
    var arguments = [_]c.JSValue{try scope.text(pattern)};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, arguments.len, &arguments)));
}

pub fn decodeEntity(engine: *em.Engine, entity: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ .{ "amp", "&" }, .{ "lt", "<" }, .{ "gt", ">" }, .{ "quot", "\"" }, .{ "apos", "'" } }) |entry| {
        if (try equalsText(&scope, entity, entry[0])) return sdk.text(engine, entry[1]);
    }
    const hex = scope.truthy(try scope.invoke(entity, "startsWith", &.{try scope.text("#x")})) or scope.truthy(try scope.invoke(entity, "startsWith", &.{try scope.text("#X")}));
    if (!hex and !scope.truthy(try scope.invoke(entity, "startsWith", &.{try scope.text("#")}))) return c.pi_js_undefined();
    const number = try scope.global("Number");
    const parse = try scope.get(number, "parseInt");
    const value = try scope.call(parse, number, &.{ try scope.invoke(entity, "slice", &.{integer(&scope, if (hex) 2 else 1)}), integer(&scope, if (hex) 16 else 10) });
    if (!scope.truthy(try scope.invoke(try scope.global("Number"), "isInteger", &.{value})) or scope.truthy(try op(&scope, 4, value, integer(&scope, 0))) or scope.truthy(try op(&scope, 6, value, integer(&scope, 0x10ffff)))) return c.pi_js_undefined();
    const result = try scope.invoke(try scope.global("String"), "fromCodePoint", &.{value});
    return c.JS_DupValue(engine.context, result);
}

pub fn decodeEntityAt(engine: *em.Engine, html: c.JSValue, index: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const end = try scope.invoke(html, "indexOf", &.{ try scope.text(";"), try op(&scope, 0, index, integer(&scope, 1)) });
    if (scope.equal(end, integer(&scope, -1)) or scope.truthy(try op(&scope, 6, try op(&scope, 1, end, index), integer(&scope, 16)))) return c.pi_js_undefined();
    const entity = try scope.invoke(html, "slice", &.{ try op(&scope, 0, index, integer(&scope, 1)), end });
    const decoded = try scope.own(try decodeEntity(engine, entity));
    if (c.JS_IsUndefined(decoded)) return c.pi_js_undefined();
    const result = try scope.object();
    try scope.put(result, "text", decoded);
    try scope.put(result, "length", try op(&scope, 0, try op(&scope, 1, end, index), integer(&scope, 1)));
    return c.JS_DupValue(engine.context, result);
}

fn scopeFromTag(scope: *Scope, tag: c.JSValue) !c.JSValue {
    const expression = try regex(scope, "\\sclass\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')");
    const matched = try scope.invoke(expression, "exec", &.{tag});
    const first = if (temporary.nullish(matched)) c.pi_js_undefined() else try key(scope, matched, integer(scope, 1));
    const classes = if (temporary.nullish(first)) (if (temporary.nullish(matched)) c.pi_js_undefined() else try key(scope, matched, integer(scope, 2))) else first;
    if (!scope.truthy(classes)) return c.pi_js_undefined();
    const split = try scope.invoke(classes, "split", &.{try regex(scope, "\\s+")});
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, split, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |class_name| {
        defer scope.engine.freeValue(class_name);
        if (scope.truthy(try scope.invoke(class_name, "startsWith", &.{try scope.text("hljs-")}))) {
            const selected = try scope.invoke(class_name, "slice", &.{integer(scope, 5)});
            try iterator.close();
            return selected;
        }
    }
    return c.pi_js_undefined();
}
fn scopeFormatter(scope: *Scope, name: c.JSValue, theme: c.JSValue) !c.JSValue {
    const exact = try key(scope, theme, name);
    if (scope.truthy(exact)) return exact;
    inline for (.{ ".", "-" }) |separator| {
        const position = try scope.invoke(name, "indexOf", &.{try scope.text(separator)});
        if (!scope.equal(position, integer(scope, -1))) {
            const formatter = try key(scope, theme, try scope.invoke(name, "slice", &.{ integer(scope, 0), position }));
            if (scope.truthy(formatter)) return formatter;
        }
    }
    return c.pi_js_undefined();
}
fn activeFormatter(scope: *Scope, scopes: c.JSValue, theme: c.JSValue) !c.JSValue {
    var index = try op(scope, 1, try scope.get(scopes, "length"), integer(scope, 1));
    while (scope.truthy(try op(scope, 7, index, integer(scope, 0)))) {
        const name = try key(scope, scopes, index);
        if (scope.truthy(name)) {
            const formatter = try scopeFormatter(scope, name, theme);
            if (scope.truthy(formatter)) return formatter;
        }
        index = try op(scope, 1, index, integer(scope, 1));
    }
    return scope.get(theme, "default");
}
fn mapLine(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const line = if (argc > 0) argv[0] else c.pi_js_undefined();
    if (c.JS_ToBool(engine.context, line) != 1) return c.JS_DupValue(engine.context, line);
    return js.call(engine, roots[0], c.pi_js_undefined(), &.{line}) catch |err| sdk.fail(engine, err);
}
const Output = struct {
    engine: *em.Engine,
    output: c.JSValue,
    buffer: c.JSValue,
    fn replace(self: *Output, target: *c.JSValue, value: c.JSValue) void {
        const held = c.JS_DupValue(self.engine.context, value);
        self.engine.freeValue(target.*);
        target.* = held;
    }
    fn flush(self: *Output, scope: *Scope, scopes: c.JSValue, theme: c.JSValue) !void {
        if (!scope.truthy(self.buffer)) return;
        const formatter = try activeFormatter(scope, scopes, theme);
        const text = if (scope.truthy(formatter)) formatted: {
            const lines = try scope.invoke(self.buffer, "split", &.{try scope.text("\n")});
            const map_method = try scope.get(lines, "map");
            var roots = [_]c.JSValue{formatter};
            const callback = try scope.own(try self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, mapLine, "", 1, 0, roots.len, &roots)));
            const mapped = try scope.call(map_method, lines, &.{callback});
            break :formatted try scope.invoke(mapped, "join", &.{try scope.text("\n")});
        } else self.buffer;
        self.replace(&self.output, try scope.concat(self.output, text));
        self.replace(&self.buffer, try scope.text(""));
    }
};

pub fn renderHtml(engine: *em.Engine, html: c.JSValue, supplied_theme: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const theme = if (c.JS_IsUndefined(supplied_theme)) try scope.object() else supplied_theme;
    const scopes = try scope.array();
    var output: Output = .{ .engine = engine, .output = try sdk.text(engine, ""), .buffer = undefined };
    defer engine.freeValue(output.output);
    output.buffer = try sdk.text(engine, "");
    defer engine.freeValue(output.buffer);
    var index = integer(&scope, 0);
    defer engine.freeValue(index);
    var native_steps: usize = 0;
    while (true) {
        var frame: Scope = .{ .engine = engine };
        defer frame.deinit();
        native_steps +|= 1;
        if (engine.cancelled.load(.acquire) or (native_steps % 256 == 0 and interrupted: {
            engine.interrupts +|= 1;
            break :interrupted engine.interrupts > engine.options.interrupt_budget;
        })) {
            _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
            unreachable;
        }
        if (!frame.truthy(try op(&frame, 4, index, try frame.get(html, "length")))) break;
        if (frame.truthy(try frame.invoke(html, "startsWith", &.{ try frame.text("<span"), index }))) {
            const next = try key(&frame, html, try op(&frame, 0, index, integer(&frame, 5)));
            const is_open = try equalsText(&frame, next, ">") or try equalsText(&frame, next, " ") or try equalsText(&frame, next, "\t") or try equalsText(&frame, next, "\n") or try equalsText(&frame, next, "\r");
            if (is_open) {
                const end = try frame.invoke(html, "indexOf", &.{ try frame.text(">"), try op(&frame, 0, index, integer(&frame, 5)) });
                if (!frame.equal(end, integer(&frame, -1))) {
                    try output.flush(&frame, scopes, theme);
                    const after = try op(&frame, 0, end, integer(&frame, 1));
                    const tag = try frame.invoke(html, "slice", &.{ index, after });
                    _ = try frame.invoke(scopes, "push", &.{try scopeFromTag(&frame, tag)});
                    output.replace(&index, after);
                    continue;
                }
            }
        }
        if (frame.truthy(try frame.invoke(html, "startsWith", &.{ try frame.text("</span>"), index }))) {
            try output.flush(&frame, scopes, theme);
            if (frame.truthy(try op(&frame, 6, try frame.get(scopes, "length"), integer(&frame, 0)))) _ = try frame.invoke(scopes, "pop", &.{});
            output.replace(&index, try op(&frame, 0, index, integer(&frame, 7)));
            continue;
        }
        if (try equalsText(&frame, try key(&frame, html, index), "&")) {
            const decoded = try frame.own(try decodeEntityAt(engine, html, index));
            if (frame.truthy(decoded)) {
                output.replace(&output.buffer, try frame.concat(output.buffer, try frame.get(decoded, "text")));
                output.replace(&index, try op(&frame, 0, index, try frame.get(decoded, "length")));
                continue;
            }
        }
        output.replace(&output.buffer, try frame.concat(output.buffer, try key(&frame, html, index)));
        output.replace(&index, try frame.own(try engine.checked(c.JS_PiIncrement(engine.context, index))));
    }
    try output.flush(&scope, scopes, theme);
    return c.JS_DupValue(engine.context, output.output);
}
