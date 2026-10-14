//! Original compaction token heuristic over live VM values and iterators.
//! Numeric coercions remain guest operators; mutable Math/JSON/Object methods
//! are resolved in the same evaluation order as the upstream function.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;

pub fn create(engine: *em.Engine) !c.JSValue {
    return @import("native_node_function.zig").create(engine, "estimateTokens", 1, call, &.{});
}
fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return estimateTokens(engine, if (args.len > 0) args[0] else c.pi_js_undefined());
}

fn equalText(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn iterator(scope: *Scope, value: c.JSValue) !js.Iterator {
    const symbol = try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context)));
    return js.Iterator.init(scope.engine, value, symbol);
}
fn textImageChars(engine: *em.Engine, content: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (c.JS_IsString(content)) return js.get(engine, content, "length");
    var chars = c.JS_NewInt32(engine.context, 0);
    var blocks = try iterator(&scope, content);
    defer blocks.deinit();
    errdefer blocks.closePreserving();
    while (try blocks.next()) |block| {
        defer engine.freeValue(block);
        var step: Scope = .{ .engine = engine };
        defer step.deinit();
        if (try equalText(&step, try step.get(block, "type"), "text") and step.truthy(try step.get(block, "text"))) {
            chars = try scope.concat(chars, try step.get(try step.get(block, "text"), "length"));
        } else if (try equalText(&step, try step.get(block, "type"), "image")) {
            chars = try scope.concat(chars, c.JS_NewInt32(engine.context, 4800));
        }
    }
    return c.JS_DupValue(engine.context, chars);
}
fn jsonChars(scope: *Scope, owner: c.JSValue, field: [*:0]const u8) !c.JSValue {
    const json = try scope.global("JSON");
    const stringify = try scope.get(json, "stringify");
    const encoded = try scope.call(stringify, json, &.{try scope.get(owner, field)});
    return scope.get(encoded, "length");
}
fn ceilChars(scope: *Scope, chars: c.JSValue) !c.JSValue {
    const math = try scope.global("Math");
    const ceil = try scope.get(math, "ceil");
    const divided = try scope.own(try arithmetic.binary(scope.engine, .divide, chars, c.JS_NewInt32(scope.engine.context, 4)));
    return js.call(scope.engine, ceil, math, &.{divided});
}
pub fn estimateTokens(engine: *em.Engine, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const role = try scope.get(message, "role");
    var chars = c.JS_NewInt32(engine.context, 0);
    if (try equalText(&scope, role, "system")) {
        chars = try scope.own(try textImageChars(engine, try scope.get(message, "content")));
        if (scope.truthy(try scope.get(message, "sections"))) {
            const object = try scope.global("Object");
            const values = try scope.get(object, "values");
            const sections = try scope.call(values, object, &.{try scope.get(message, "sections")});
            var entries = try iterator(&scope, sections);
            defer entries.deinit();
            errdefer entries.closePreserving();
            while (try entries.next()) |section| {
                defer engine.freeValue(section);
                if (scope.truthy(section)) {
                    var step: Scope = .{ .engine = engine };
                    defer step.deinit();
                    chars = try scope.concat(chars, try step.get(section, "length"));
                }
            }
        }
        if (scope.truthy(try scope.get(message, "toolsAdded"))) chars = try scope.concat(chars, try jsonChars(&scope, message, "toolsAdded"));
        return ceilChars(&scope, chars);
    }
    if (try equalText(&scope, role, "user") or try equalText(&scope, role, "custom") or try equalText(&scope, role, "toolResult")) {
        chars = try scope.own(try textImageChars(engine, try scope.get(message, "content")));
        return ceilChars(&scope, chars);
    }
    if (try equalText(&scope, role, "assistant")) {
        var blocks = try iterator(&scope, try scope.get(message, "content"));
        defer blocks.deinit();
        errdefer blocks.closePreserving();
        while (try blocks.next()) |block| {
            defer engine.freeValue(block);
            var step: Scope = .{ .engine = engine };
            defer step.deinit();
            if (try equalText(&step, try step.get(block, "type"), "text")) {
                chars = try scope.concat(chars, try step.get(try step.get(block, "text"), "length"));
            } else if (try equalText(&step, try step.get(block, "type"), "thinking")) {
                chars = try scope.concat(chars, try step.get(try step.get(block, "thinking"), "length"));
            } else if (try equalText(&step, try step.get(block, "type"), "toolCall")) {
                const name_length = try step.get(try step.get(block, "name"), "length");
                const argument_length = try jsonChars(&step, block, "arguments");
                const length = try step.concat(name_length, argument_length);
                chars = try scope.concat(chars, length);
            }
        }
        return ceilChars(&scope, chars);
    }
    if (try equalText(&scope, role, "bashExecution")) {
        const command_length = try scope.get(try scope.get(message, "command"), "length");
        const output_length = try scope.get(try scope.get(message, "output"), "length");
        chars = try scope.concat(command_length, output_length);
        return ceilChars(&scope, chars);
    }
    if (try equalText(&scope, role, "branchSummary") or try equalText(&scope, role, "compactionSummary")) {
        return ceilChars(&scope, try scope.get(try scope.get(message, "summary"), "length"));
    }
    return chars;
}
