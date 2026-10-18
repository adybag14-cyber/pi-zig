//! Actual c268 token heuristic with AF33/C435 expression retirement.
//! Source chars and iteration heads are lexical slots, distinct from temporary
//! receivers; the last head survives final done until function completion.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const em = v.em;
const c = v.c;
const Scope = v.Scope;
const TextFrame = h.Frame(enum { chars, block });
const MessageFrame = h.Frame(enum { chars, system, section, assistant, block });

pub fn create(engine: *em.Engine) !c.JSValue {
    return h.expression(engine, createBody, .{});
}
fn createBody(s: *Scope) !c.JSValue {
    return v.duplicate(s, try v.ordinary(s, "estimateTokens", 1, call, &.{}));
}
fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return estimateTokens(engine, v.arg(args, 0));
}
fn roleCode(s: *Scope, message: c.JSValue) !c.JSValue {
    const role = try v.get(s, message, "role");
    inline for (.{ "system", "user", "assistant", "custom", "toolResult", "bashExecution", "branchSummary", "compactionSummary" }, 1..) |name, index| {
        if (try v.eq(s, role, name)) return c.JS_NewInt32(s.engine.context, @intCast(index));
    }
    return c.JS_NewInt32(s.engine.context, 0);
}
fn addIncoming(s: *Scope, left: c.JSValue, incoming: anyerror!c.JSValue) !c.JSValue {
    const right = try v.own(s, try incoming);
    return v.duplicate(s, try h.binary(s, .add, left, right));
}
fn textImageChars(engine: *em.Engine, content: c.JSValue) !c.JSValue {
    var f = TextFrame.init(engine);
    return f.finish(textImageSource(&f, content));
}
fn textImageSource(f: *TextFrame, content: c.JSValue) !c.JSValue {
    if (c.JS_IsString(content)) return h.get(f.engine, content, "length");
    try f.set(.chars, h.number(f.engine, 0));
    var iterator = try v.Iterator.init(f.engine, content);
    try iterator.finish(textImageLoop(f, &iterator));
    return h.duplicate(f.engine, f.get(.chars));
}
fn textImageLoop(f: *TextFrame, iterator: *v.Iterator) !void {
    const engine = f.engine;
    while (try iterator.next()) |block| {
        try f.set(.block, block);
        if (try h.fieldEqual(engine, f.get(.block), "type", "text") and
            try h.fieldTest(engine, f.get(.block), "text", .truthy))
        {
            try f.set(.chars, h.expression(engine, addIncoming, .{
                f.get(.chars), h.nested(engine, f.get(.block), "text", "length"),
            }));
        } else if (try h.fieldEqual(engine, f.get(.block), "type", "image")) {
            try f.set(.chars, h.expression(engine, addIncoming, .{ f.get(.chars), @as(anyerror!c.JSValue, h.number(engine, 4800)) }));
        }
    }
}
fn textImageIncoming(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    const content = try v.own(s, try incoming);
    return textImageChars(s.engine, content);
}
fn jsonEncoded(s: *Scope, owner: c.JSValue, field: [*:0]const u8) !c.JSValue {
    const json = try v.global(s, "JSON");
    const stringify = try v.get(s, json, "stringify");
    return v.duplicate(s, try v.call(s, stringify, json, &.{try v.get(s, owner, field)}));
}
fn incomingLength(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try incoming);
    return v.duplicate(s, try v.get(s, receiver, "length"));
}
fn jsonChars(engine: *em.Engine, owner: c.JSValue, field: [*:0]const u8) !c.JSValue {
    return h.expression(engine, incomingLength, .{h.expression(engine, jsonEncoded, .{owner, field})});
}
fn ceilChars(s: *Scope, chars: c.JSValue) !c.JSValue {
    const math = try v.global(s, "Math");
    const ceil = try v.get(s, math, "ceil");
    const divided = try h.binary(s, .divide, chars, h.number(s.engine, 4));
    return v.duplicate(s, try v.call(s, ceil, math, &.{divided}));
}
fn sectionValues(s: *Scope, system: c.JSValue) !c.JSValue {
    const object = try v.global(s, "Object");
    const values = try v.get(s, object, "values");
    return v.duplicate(s, try v.call(s, values, object, &.{try v.get(s, system, "sections")}));
}
fn sectionsLoop(f: *MessageFrame, iterator: *v.Iterator) !void {
    while (try iterator.next()) |section| {
        try f.set(.section, section);
        if (h.truthy(f.engine, f.get(.section))) try f.set(.chars, h.expression(f.engine, addIncoming, .{
            f.get(.chars), h.get(f.engine, f.get(.section), "length"),
        }));
    }
}
fn toolChars(s: *Scope, block: c.JSValue) !c.JSValue {
    const name_length = try v.own(s, try h.nested(s.engine, block, "name", "length"));
    const argument_length = try v.own(s, try jsonChars(s.engine, block, "arguments"));
    return v.duplicate(s, try h.binary(s, .add, name_length, argument_length));
}
fn assistantLoop(f: *MessageFrame, iterator: *v.Iterator) !void {
    const engine = f.engine;
    while (try iterator.next()) |block| {
        try f.set(.block, block);
        if (try h.fieldEqual(engine, f.get(.block), "type", "text")) {
            try f.set(.chars, h.expression(engine, addIncoming, .{ f.get(.chars), h.nested(engine, f.get(.block), "text", "length") }));
        } else if (try h.fieldEqual(engine, f.get(.block), "type", "thinking")) {
            try f.set(.chars, h.expression(engine, addIncoming, .{ f.get(.chars), h.nested(engine, f.get(.block), "thinking", "length") }));
        } else if (try h.fieldEqual(engine, f.get(.block), "type", "toolCall")) {
            try f.set(.chars, h.expression(engine, addIncoming, .{ f.get(.chars), h.expression(engine, toolChars, .{f.get(.block)}) }));
        }
    }
}
fn bashChars(s: *Scope, message: c.JSValue) !c.JSValue {
    const command_length = try v.own(s, try h.nested(s.engine, message, "command", "length"));
    const output_length = try v.own(s, try h.nested(s.engine, message, "output", "length"));
    return v.duplicate(s, try h.binary(s, .add, command_length, output_length));
}
pub fn estimateTokens(engine: *em.Engine, message: c.JSValue) !c.JSValue {
    var f = MessageFrame.init(engine);
    return f.finish(messageSource(&f, message));
}
fn messageSource(f: *MessageFrame, message: c.JSValue) !c.JSValue {
    const engine = f.engine;
    try f.set(.chars, h.number(engine, 0));
    const code = try h.expression(engine, roleCode, .{message});
    // roleCode returns an immediate Number after retiring the switch operand.
    var role: i32 = 0;
    _ = c.JS_ToInt32(engine.context, &role, code);
    switch (role) {
        1 => {
            try f.set(.system, h.duplicate(engine, message));
            try f.set(.chars, h.expression(engine, textImageIncoming, .{h.get(engine, f.get(.system), "content")}));
            if (try h.fieldTest(engine, f.get(.system), "sections", .truthy)) {
                var iterator = try v.Iterator.initOwned(engine, try h.expression(engine, sectionValues, .{f.get(.system)}));
                try iterator.finish(sectionsLoop(f, &iterator));
            }
            if (try h.fieldTest(engine, f.get(.system), "toolsAdded", .truthy))
                try f.set(.chars, h.expression(engine, addIncoming, .{ f.get(.chars), jsonChars(engine, f.get(.system), "toolsAdded") }));
            return h.expression(engine, ceilChars, .{f.get(.chars)});
        },
        2, 4, 5 => {
            try f.set(.chars, h.expression(engine, textImageIncoming, .{h.get(engine, message, "content")}));
            return h.expression(engine, ceilChars, .{f.get(.chars)});
        },
        3 => {
            try f.set(.assistant, h.duplicate(engine, message));
            var iterator = try v.Iterator.initOwned(engine, try h.get(engine, f.get(.assistant), "content"));
            try iterator.finish(assistantLoop(f, &iterator));
            return h.expression(engine, ceilChars, .{f.get(.chars)});
        },
        6 => {
            try f.set(.chars, h.expression(engine, bashChars, .{message}));
            return h.expression(engine, ceilChars, .{f.get(.chars)});
        },
        7, 8 => {
            try f.set(.chars, h.nested(engine, message, "summary", "length"));
            return h.expression(engine, ceilChars, .{f.get(.chars)});
        },
        else => return h.number(engine, 0),
    }
}
