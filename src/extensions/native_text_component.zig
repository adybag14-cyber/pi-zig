//! Source Text layout, background callback ordering and observable cache identity.
const std = @import("std");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
const v = @import("native_select_list.zig");
const utf16 = @import("native_utf16.zig");
const Method = enum(c_int) { setText, setCustomBgFn, setPaddingX, invalidate, render };
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Text: %s", @as([*:0]const u8, @errorName(err)));
}
fn clearCache(engine: *Engine, object: c.JSValue) !void {
    inline for (.{ "cachedText", "cachedWidth", "cachedLines" }) |name| try v.set(engine, object, name, c.pi_js_undefined());
}
fn spaces(engine: *Engine, count: f64) !c.JSValue {
    const space = try v.text(engine, " ");
    defer engine.freeValue(space);
    return js.invoke(engine, space, "repeat", &.{v.numeric(engine, count)});
}
fn background(engine: *Engine, line: c.JSValue, width: f64, function: c.JSValue, apply: bool) !c.JSValue {
    const padding = try spaces(engine, v.maximum(0, width - try v.width(engine, line)));
    defer engine.freeValue(padding);
    const padded = try v.concat(engine, &.{ line, padding });
    if (!apply) return padded;
    defer engine.freeValue(padded);
    return js.call(engine, function, c.pi_js_undefined(), &.{padded});
}
fn cache(engine: *Engine, object: c.JSValue, width: c.JSValue, lines: c.JSValue) !void {
    try v.set(engine, object, "cachedText", try js.get(engine, object, "text"));
    try v.set(engine, object, "cachedWidth", c.JS_DupValue(engine.context, width));
    try v.set(engine, object, "cachedLines", c.JS_DupValue(engine.context, lines));
}
fn push(engine: *Engine, lines: c.JSValue, line: c.JSValue) !void {
    defer engine.freeValue(line);
    try js.push(engine, lines, line);
}
pub fn flattenLines(engine: *Engine, lines: c.JSValue, iterator_symbol: c.JSValue) !void {
    var iterator = try js.Iterator.init(engine, lines, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |line| {
        defer engine.freeValue(line);
        const number = try js.global(engine, "Number");
        defer engine.freeValue(number);
        const ignored = try js.call(engine, number, c.pi_js_undefined(), &.{line});
        engine.freeValue(ignored);
    }
}
fn render(engine: *Engine, object: c.JSValue, terminal_width: c.JSValue, regex: c.JSValue, iterator_symbol: c.JSValue) !c.JSValue {
    const cached = try js.get(engine, object, "cachedLines");
    defer engine.freeValue(cached);
    if (v.truthy(engine, cached)) {
        const cached_text = try js.get(engine, object, "cachedText");
        defer engine.freeValue(cached_text);
        const text = try js.get(engine, object, "text");
        defer engine.freeValue(text);
        if (c.JS_IsStrictEqual(engine.context, cached_text, text)) {
            const cached_width = try js.get(engine, object, "cachedWidth");
            defer engine.freeValue(cached_width);
            if (c.JS_IsStrictEqual(engine.context, cached_width, terminal_width)) return js.get(engine, object, "cachedLines");
        }
    }
    const lines = try js.array(engine);
    errdefer engine.freeValue(lines);
    const first_text = try js.get(engine, object, "text");
    defer engine.freeValue(first_text);
    var blank = !v.truthy(engine, first_text);
    if (!blank) {
        const text = try js.get(engine, object, "text");
        defer engine.freeValue(text);
        const trimmed = try js.invoke(engine, text, "trim", &.{});
        defer engine.freeValue(trimmed);
        const empty = try v.text(engine, "");
        defer engine.freeValue(empty);
        blank = c.JS_IsStrictEqual(engine.context, trimmed, empty);
    }
    if (blank) {
        try cache(engine, object, terminal_width, lines);
        return lines;
    }
    const replacement = try v.text(engine, "   ");
    defer engine.freeValue(replacement);
    const text = try js.get(engine, object, "text");
    defer engine.freeValue(text);
    const normalized = try js.invoke(engine, text, "replace", &.{ regex, replacement });
    defer engine.freeValue(normalized);
    const width = try v.number(engine, terminal_width);
    const padding_x = v.minimum(try v.numberField(engine, object, "paddingX"), v.maximum(0, @floor((width - 1) / 2)));
    const content_width = v.maximum(1, width - padding_x * 2);
    const units = try utf16.unitsAlloc(engine, normalized);
    defer engine.gpa.free(units);
    const wrapped = try @import("native_utf16_wrap.zig").wrap(engine, units, content_width);
    defer {
        for (wrapped) |line| engine.gpa.free(line);
        engine.gpa.free(wrapped);
    }
    const left = try spaces(engine, padding_x);
    defer engine.freeValue(left);
    const right = try spaces(engine, padding_x);
    defer engine.freeValue(right);
    const contents = try js.array(engine);
    defer engine.freeValue(contents);
    for (wrapped) |line| {
        const raw = try utf16.string(engine, line);
        defer engine.freeValue(raw);
        const margins = try v.concat(engine, &.{ left, raw, right });
        defer engine.freeValue(margins);
        const check = try js.get(engine, object, "customBgFn");
        defer engine.freeValue(check);
        const bg = if (v.truthy(engine, check)) try js.get(engine, object, "customBgFn") else c.pi_js_undefined();
        defer engine.freeValue(bg);
        try push(engine, contents, try background(engine, margins, width, bg, v.truthy(engine, check)));
    }
    const empty_line = try spaces(engine, width);
    defer engine.freeValue(empty_line);
    const empty_lines = try js.array(engine);
    defer engine.freeValue(empty_lines);
    var index: f64 = 0;
    while (index < try v.numberField(engine, object, "paddingY")) : (index += 1) {
        if (index >= 4096) return error.NativeComponentFrameLimit;
        const check = try js.get(engine, object, "customBgFn");
        defer engine.freeValue(check);
        if (v.truthy(engine, check)) {
            const bg = try js.get(engine, object, "customBgFn");
            defer engine.freeValue(bg);
            try push(engine, empty_lines, try background(engine, empty_line, width, bg, true));
        } else try push(engine, empty_lines, c.JS_DupValue(engine.context, empty_line));
    }
    // Source reuses the same precomputed vertical-padding array above and below.
    for ([_]c.JSValue{ empty_lines, contents, empty_lines }) |part| {
        const count = try v.numberField(engine, part, "length");
        var at: f64 = 0;
        while (at < count) : (at += 1) try push(engine, lines, try v.fieldAt(engine, part, at));
    }
    try flattenLines(engine, lines, iterator_symbol);
    try cache(engine, object, terminal_width, lines);
    if (try v.numberField(engine, lines, "length") == 0) try push(engine, lines, try v.text(engine, ""));
    return lines;
}
fn methodCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return method(engine, object, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)], data[0], data[1]) catch |err| fail(engine, err);
}
fn method(engine: *Engine, object: c.JSValue, operation: Method, args: []const c.JSValue, regex: c.JSValue, iterator_symbol: c.JSValue) !c.JSValue {
    switch (operation) {
        .setText => {
            try v.set(engine, object, "text", c.JS_DupValue(engine.context, v.arg(args, 0)));
            try clearCache(engine, object);
        },
        .setCustomBgFn => {
            try v.set(engine, object, "customBgFn", c.JS_DupValue(engine.context, v.arg(args, 0)));
            try clearCache(engine, object);
        },
        .setPaddingX => {
            try v.set(engine, object, "paddingX", c.JS_DupValue(engine.context, v.arg(args, 0)));
            try v.invokeVoid(engine, object, "invalidate", &.{});
        },
        .invalidate => try clearCache(engine, object),
        .render => return render(engine, object, v.arg(args, 0), regex, iterator_symbol),
    }
    return c.pi_js_undefined();
}
fn construct(engine: *Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const object = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(object);
    inline for (.{ "text", "paddingX", "paddingY", "customBgFn", "cachedText", "cachedWidth", "cachedLines" }) |name| try js.define(engine, object, name, c.pi_js_undefined());
    try v.set(engine, object, "text", if (c.JS_IsUndefined(v.arg(args, 0))) try v.text(engine, "") else c.JS_DupValue(engine.context, v.arg(args, 0)));
    try v.set(engine, object, "paddingX", if (c.JS_IsUndefined(v.arg(args, 1))) v.numeric(engine, 1) else c.JS_DupValue(engine.context, v.arg(args, 1)));
    try v.set(engine, object, "paddingY", if (c.JS_IsUndefined(v.arg(args, 2))) v.numeric(engine, 1) else c.JS_DupValue(engine.context, v.arg(args, 2)));
    try v.set(engine, object, "customBgFn", c.JS_DupValue(engine.context, v.arg(args, 3)));
    return object;
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const pattern = try v.text(engine, "\t");
    defer engine.freeValue(pattern);
    const flags = try v.text(engine, "g");
    defer engine.freeValue(flags);
    const regex = try js.builtin(engine, "RegExp", &.{ pattern, flags });
    defer engine.freeValue(regex);
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    const iterator = try js.get(engine, symbol, "iterator");
    defer engine.freeValue(iterator);
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        var data = [_]c.JSValue{ regex, iterator };
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name.ptr, if (std.mem.eql(u8, field.name, "invalidate")) 0 else 1, @intCast(field.value), 2, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name.ptr, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    try js.define(engine, exports, "Text", try @import("native_class.zig").constructor(engine, "Text", 0, prototype, construct, &.{}));
}
fn fixtureEngine(gpa: std.mem.Allocator) !*Engine {
    const engine = try Engine.init(gpa, .{});
    errdefer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/text-component-original-6fb.json");
    try js.define(engine, root, "textFixture", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "text-component-original-6fb.json")));
    return engine;
}
test "Source6fb public Text original layouts backgrounds callback ordering and shared cache identity" {
    const engine = try fixtureEngine(std.testing.allocator);
    defer engine.deinit();
    const result = engine.evalModule(
        \\import{Text}from'pi-tui';for(const[index,item]of textFixture.cases.entries()){const calls=[],instance=new Text(item.text,item.paddingX,item.paddingY,item.background?function(line){calls.push({line,receiver:this===instance});return '\x1b[41m'+line+'\x1b[49m'}:undefined),lines=instance.render(item.width),actual={lines,calls,same:instance.render(item.width)===lines},expected={lines:item.lines,calls:item.calls,same:item.same};if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index,actual,expected}));}
        \\for(const[index,item]of textFixture.structural.entries()){let actual;try{actual=new Function('Text','"use strict";'+item.script)(Text)}catch(e){if(e.name===item.errorName&&e.message===item.errorMessage)continue;throw e}if(item.errorName||JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({index,actual,expected:item}));}
        \\const shape={name:Text.name,length:Text.length,own:Object.keys(new Text()),methods:Object.fromEntries(Object.getOwnPropertyNames(Text.prototype).filter(k=>k!=='constructor').map(k=>[k,{name:Text.prototype[k].name,length:Text.prototype[k].length,enumerable:Object.getOwnPropertyDescriptor(Text.prototype,k).enumerable}]))};if(JSON.stringify(shape)!==JSON.stringify(textFixture.shape))throw Error(JSON.stringify({shape,expected:textFixture.shape}));
    , "text-component-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Source Text: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
pub fn allocationError(engine: *Engine, err: anyerror) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |exception| {
        const message = c.JS_GetPropertyStr(engine.context, exception, "message");
        defer engine.freeValue(message);
        const value = c.JS_ToCString(engine.context, message);
        if (value != null) {
            defer c.JS_FreeCString(engine.context, value);
            if (std.mem.indexOf(u8, std.mem.span(value), "out of memory") != null) return error.OutOfMemory;
        }
    };
    return err;
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    @import("native_tui.zig").install(engine) catch |err| return allocationError(engine, err);
    const result = engine.evalModule(
        \\import{Text}from'pi-tui';const text=new Text('\x1b[4mAlpha界 words\x1b[24m tail',1,2,line=>'\x1b[41m'+line+'\x1b[49m'),first=text.render(12);if(first!==text.render(12))throw Error('cache identity');text.setPaddingX(0);text.render(8);text.setCustomBgFn(undefined);text.setText('中文测试语言');text.render(3);globalThis.retainedText=text;
    , "text-allocation.mjs") catch |err| return allocationError(engine, err);
    defer engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    const retained = engine.eval("retainedText.invalidate();retainedText.render(8);delete globalThis.retainedText", "text-retained.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return allocationError(engine, err);
    defer engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}
test "Source6fb public Text all allocation failures release backgrounds caches and retained subclass graphs" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
