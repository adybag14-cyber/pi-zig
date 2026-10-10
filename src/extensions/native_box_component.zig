//! Source Box padding, background sampling, child cache and mouse layout.
const std = @import("std");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
const v = @import("native_select_list.zig");
const Method = enum(c_int) { addChild, removeChild, clear, setBgFn, setPaddingX, invalidateCache, matchCache, invalidate, handleMouse, render, applyBg };
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Box: %s", @as([*:0]const u8, @errorName(err)));
}
fn spaces(engine: *Engine, count: f64) !c.JSValue {
    const space = try v.text(engine, " ");
    defer engine.freeValue(space);
    return js.invoke(engine, space, "repeat", &.{v.numeric(engine, count)});
}
fn push(engine: *Engine, lines: c.JSValue, line: c.JSValue) !void {
    defer engine.freeValue(line);
    try js.push(engine, lines, line);
}
fn applyBg(engine: *Engine, object: c.JSValue, line: c.JSValue, width: c.JSValue) !c.JSValue {
    const padding = try spaces(engine, v.maximum(0, try v.number(engine, width) - try v.width(engine, line)));
    defer engine.freeValue(padding);
    const padded = try v.concat(engine, &.{ line, padding });
    var returned = false;
    defer if (!returned) engine.freeValue(padded);
    const check = try js.get(engine, object, "bgFn");
    defer engine.freeValue(check);
    if (!v.truthy(engine, check)) {
        returned = true;
        return padded;
    }
    const function = try js.get(engine, object, "bgFn");
    defer engine.freeValue(function);
    return js.call(engine, function, object, &.{padded});
}
fn matchCache(engine: *Engine, object: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const cache = try js.get(engine, object, "cache");
    defer engine.freeValue(cache);
    if (!v.truthy(engine, cache)) return c.pi_js_bool(engine.context, 0);
    const width = try js.get(engine, cache, "width");
    defer engine.freeValue(width);
    if (!c.JS_IsStrictEqual(engine.context, width, v.arg(args, 0))) return c.pi_js_bool(engine.context, 0);
    const bg = try js.get(engine, cache, "bgSample");
    defer engine.freeValue(bg);
    if (!c.JS_IsStrictEqual(engine.context, bg, v.arg(args, 2))) return c.pi_js_bool(engine.context, 0);
    const previous = try js.get(engine, cache, "childLines");
    defer engine.freeValue(previous);
    const length = try v.numberField(engine, previous, "length");
    if (length != try v.numberField(engine, v.arg(args, 1), "length")) return c.pi_js_bool(engine.context, 0);
    var index: f64 = 0;
    while (index < length) : (index += 1) {
        const left = try v.fieldAt(engine, previous, index);
        defer engine.freeValue(left);
        const right = try v.fieldAt(engine, v.arg(args, 1), index);
        defer engine.freeValue(right);
        if (!c.JS_IsStrictEqual(engine.context, left, right)) return c.pi_js_bool(engine.context, 0);
    }
    return c.pi_js_bool(engine.context, 1);
}
fn render(engine: *Engine, object: c.JSValue, terminal_width: c.JSValue, iterator_symbol: c.JSValue) !c.JSValue {
    const children = try js.get(engine, object, "children");
    defer engine.freeValue(children);
    if (try v.numberField(engine, children, "length") == 0) return js.array(engine);
    const width = try v.number(engine, terminal_width);
    const content_width = v.maximum(1, width - try v.numberField(engine, object, "paddingX") * 2);
    const left_pad = try spaces(engine, try v.numberField(engine, object, "paddingX"));
    defer engine.freeValue(left_pad);
    const child_lines = try js.array(engine);
    defer engine.freeValue(child_lines);
    const mouse_children = try js.array(engine);
    defer engine.freeValue(mouse_children);
    var iterator = try js.Iterator.init(engine, children, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |child| {
        defer engine.freeValue(child);
        const lines = try js.invoke(engine, child, "render", &.{v.numeric(engine, content_width)});
        defer engine.freeValue(lines);
        const entry = try js.object(engine);
        defer engine.freeValue(entry);
        try js.define(engine, entry, "component", c.JS_DupValue(engine.context, child));
        try js.define(engine, entry, "height", try js.get(engine, lines, "length"));
        try js.push(engine, mouse_children, entry);
        var line_iterator = try js.Iterator.init(engine, lines, iterator_symbol);
        defer line_iterator.deinit();
        errdefer line_iterator.closePreserving();
        while (try line_iterator.next()) |line| try push(engine, child_lines, line);
    }
    const layout = try js.object(engine);
    var layout_transferred = false;
    defer if (!layout_transferred) engine.freeValue(layout);
    try js.define(engine, layout, "width", v.numeric(engine, content_width));
    try js.define(engine, layout, "children", c.JS_DupValue(engine.context, mouse_children));
    layout_transferred = true;
    try v.set(engine, object, "mouseLayout", layout);
    if (try v.numberField(engine, child_lines, "length") == 0) return js.array(engine);
    const check = try js.get(engine, object, "bgFn");
    defer engine.freeValue(check);
    const sample = if (v.truthy(engine, check)) value: {
        const function = try js.get(engine, object, "bgFn");
        defer engine.freeValue(function);
        const label = try v.text(engine, "test");
        defer engine.freeValue(label);
        break :value try js.call(engine, function, object, &.{label});
    } else c.pi_js_undefined();
    defer engine.freeValue(sample);
    const hit = try js.invoke(engine, object, "matchCache", &.{ terminal_width, child_lines, sample });
    defer engine.freeValue(hit);
    if (v.truthy(engine, hit)) {
        const cache = try js.get(engine, object, "cache");
        defer engine.freeValue(cache);
        return js.get(engine, cache, "lines");
    }
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    const empty = try v.text(engine, "");
    defer engine.freeValue(empty);
    var at: f64 = 0;
    while (at < try v.numberField(engine, object, "paddingY")) : (at += 1) {
        if (at >= 4096) return error.NativeComponentFrameLimit;
        try push(engine, result, try js.invoke(engine, object, "applyBg", &.{ empty, terminal_width }));
    }
    var line_iterator = try js.Iterator.init(engine, child_lines, iterator_symbol);
    defer line_iterator.deinit();
    errdefer line_iterator.closePreserving();
    while (try line_iterator.next()) |line| {
        defer engine.freeValue(line);
        const prefixed = try v.concat(engine, &.{ left_pad, line });
        defer engine.freeValue(prefixed);
        try push(engine, result, try js.invoke(engine, object, "applyBg", &.{ prefixed, terminal_width }));
    }
    at = 0;
    while (at < try v.numberField(engine, object, "paddingY")) : (at += 1) {
        if (at >= 4096) return error.NativeComponentFrameLimit;
        try push(engine, result, try js.invoke(engine, object, "applyBg", &.{ empty, terminal_width }));
    }
    try @import("native_text_component.zig").flattenLines(engine, result, iterator_symbol);
    const cache = try js.object(engine);
    var cache_transferred = false;
    defer if (!cache_transferred) engine.freeValue(cache);
    try js.define(engine, cache, "childLines", c.JS_DupValue(engine.context, child_lines));
    try js.define(engine, cache, "width", c.JS_DupValue(engine.context, terminal_width));
    try js.define(engine, cache, "bgSample", c.JS_DupValue(engine.context, sample));
    try js.define(engine, cache, "lines", c.JS_DupValue(engine.context, result));
    cache_transferred = true;
    try v.set(engine, object, "cache", cache);
    return result;
}
fn mouseLayoutEntry(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return layoutEntry(engine, if (argc == 0) c.pi_js_undefined() else argv[0], data[0]) catch |err| fail(engine, err);
}
fn layoutEntry(engine: *Engine, child: c.JSValue, width: c.JSValue) !c.JSValue {
    const lines = try js.invoke(engine, child, "render", &.{width});
    defer engine.freeValue(lines);
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "component", c.JS_DupValue(engine.context, child));
    try js.define(engine, result, "height", try js.get(engine, lines, "length"));
    return result;
}
fn childLayout(engine: *Engine, object: c.JSValue, width: f64) !c.JSValue {
    const layout = try js.get(engine, object, "mouseLayout");
    defer engine.freeValue(layout);
    if (!c.JS_IsNull(layout) and !c.JS_IsUndefined(layout)) {
        const previous = try js.get(engine, layout, "width");
        defer engine.freeValue(previous);
        if (c.JS_IsStrictEqual(engine.context, previous, v.numeric(engine, width))) {
            const current = try js.get(engine, object, "mouseLayout");
            defer engine.freeValue(current);
            return js.get(engine, current, "children");
        }
    }
    const children = try js.get(engine, object, "children");
    defer engine.freeValue(children);
    var data = [_]c.JSValue{v.numeric(engine, width)};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, mouseLayoutEntry, "", 1, 0, 1, &data));
    defer engine.freeValue(callback);
    return js.invoke(engine, children, "map", &.{callback});
}
fn mouse(engine: *Engine, object: c.JSValue, event: c.JSValue, iterator_symbol: c.JSValue) !c.JSValue {
    const content_width = v.maximum(1, try v.numberField(engine, event, "width") - try v.numberField(engine, object, "paddingX") * 2);
    const content_y = try v.numberField(engine, event, "y") - try v.numberField(engine, object, "paddingY");
    const content_x = try v.numberField(engine, event, "x") - try v.numberField(engine, object, "paddingX");
    if (content_y < 0 or content_x < 0 or content_x >= content_width) return c.pi_js_undefined();
    const children = try childLayout(engine, object, content_width);
    defer engine.freeValue(children);
    var iterator = try js.Iterator.init(engine, children, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var child_y: f64 = 0;
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        const child = try js.get(engine, entry, "component");
        defer engine.freeValue(child);
        const height = try js.get(engine, entry, "height");
        defer engine.freeValue(height);
        const child_height = try v.number(engine, height);
        if (content_y >= child_y and content_y < child_y + child_height) {
            const local = try js.spread(engine, event);
            defer engine.freeValue(local);
            try v.set(engine, local, "x", v.numeric(engine, content_x));
            try v.set(engine, local, "y", v.numeric(engine, content_y - child_y));
            try v.set(engine, local, "width", v.numeric(engine, content_width));
            try v.set(engine, local, "height", c.JS_DupValue(engine.context, height));
            const result = try @import("native_mouse.zig").dispatch(engine, child, local);
            errdefer engine.freeValue(result);
            // Returning from Source's for-of performs IteratorClose.
            try iterator.close();
            return result;
        }
        child_y += child_height;
    }
    return c.pi_js_undefined();
}
fn invalidate(engine: *Engine, object: c.JSValue, iterator_symbol: c.JSValue) !void {
    try v.invokeVoid(engine, object, "invalidateCache", &.{});
    const children = try js.get(engine, object, "children");
    defer engine.freeValue(children);
    var iterator = try js.Iterator.init(engine, children, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |child| {
        defer engine.freeValue(child);
        const callback = try js.get(engine, child, "invalidate");
        defer engine.freeValue(callback);
        if (!c.JS_IsNull(callback) and !c.JS_IsUndefined(callback)) {
            const value = try js.call(engine, callback, child, &.{});
            engine.freeValue(value);
        }
    }
}
fn methodCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return method(engine, object, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)], data[0]) catch |err| fail(engine, err);
}
fn method(engine: *Engine, object: c.JSValue, operation: Method, args: []const c.JSValue, iterator_symbol: c.JSValue) !c.JSValue {
    switch (operation) {
        .addChild => {
            const children = try js.get(engine, object, "children");
            defer engine.freeValue(children);
            try js.push(engine, children, v.arg(args, 0));
            try v.invokeVoid(engine, object, "invalidateCache", &.{});
        },
        .removeChild => {
            const children = try js.get(engine, object, "children");
            defer engine.freeValue(children);
            const index = try js.invoke(engine, children, "indexOf", &.{v.arg(args, 0)});
            defer engine.freeValue(index);
            if (try v.number(engine, index) != -1) {
                try v.invokeVoid(engine, children, "splice", &.{ index, v.numeric(engine, 1) });
                try v.invokeVoid(engine, object, "invalidateCache", &.{});
            }
        },
        .clear => {
            try v.set(engine, object, "children", try js.array(engine));
            try v.invokeVoid(engine, object, "invalidateCache", &.{});
        },
        .setBgFn => try v.set(engine, object, "bgFn", c.JS_DupValue(engine.context, v.arg(args, 0))),
        .setPaddingX => {
            try v.set(engine, object, "paddingX", c.JS_DupValue(engine.context, v.arg(args, 0)));
            try v.invokeVoid(engine, object, "invalidateCache", &.{});
        },
        .invalidateCache => try v.set(engine, object, "cache", c.pi_js_undefined()),
        .matchCache => return matchCache(engine, object, args),
        .invalidate => try invalidate(engine, object, iterator_symbol),
        .handleMouse => return mouse(engine, object, v.arg(args, 0), iterator_symbol),
        .render => return render(engine, object, v.arg(args, 0), iterator_symbol),
        .applyBg => return applyBg(engine, object, v.arg(args, 0), v.arg(args, 1)),
    }
    return c.pi_js_undefined();
}
fn construct(engine: *Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const object = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(object);
    try js.define(engine, object, "children", try js.array(engine));
    inline for (.{ "paddingX", "paddingY", "bgFn", "cache", "mouseLayout" }) |name| try js.define(engine, object, name, c.pi_js_undefined());
    try v.set(engine, object, "paddingX", if (c.JS_IsUndefined(v.arg(args, 0))) v.numeric(engine, 1) else c.JS_DupValue(engine.context, v.arg(args, 0)));
    try v.set(engine, object, "paddingY", if (c.JS_IsUndefined(v.arg(args, 1))) v.numeric(engine, 1) else c.JS_DupValue(engine.context, v.arg(args, 1)));
    try v.set(engine, object, "bgFn", c.JS_DupValue(engine.context, v.arg(args, 2)));
    return object;
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    const iterator = try js.get(engine, symbol, "iterator");
    defer engine.freeValue(iterator);
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        var data = [_]c.JSValue{iterator};
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) {
            .clear, .invalidateCache, .invalidate => 0,
            .matchCache => 3,
            .applyBg => 2,
            else => 1,
        };
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name.ptr, length, @intCast(field.value), 1, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name.ptr, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    try js.define(engine, exports, "Box", try @import("native_class.zig").constructor(engine, "Box", 0, prototype, construct, &.{}));
}
test "Source6fb public Text Box original layouts child cache backgrounds mouse and callback structural cases" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/box-component-original-6fb.json");
    try js.define(engine, root, "boxFixture", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "box-component-original-6fb.json")));
    const result = engine.evalModule(
        \\import{Box}from'pi-tui';for(const[index,item]of boxFixture.cases.entries()){const calls=[],box=new Box(item.paddingX,item.paddingY,item.background?function(line){calls.push({kind:'background',line,receiver:this===box});return '\x1b[41m'+line+'\x1b[49m'}:undefined);for(const[index,lines]of item.childLines.entries()){const child={render(width){calls.push({kind:'render',index,width,receiver:this===child});return lines}};box.addChild(child)}const lines=box.render(item.width),firstCalls=[...calls],next=box.render(item.width),actual={lines,calls:firstCalls,same:next===lines,nextCalls:calls.slice(firstCalls.length)},expected={lines:item.lines,calls:item.calls,same:item.same,nextCalls:item.nextCalls};if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index,actual,expected}));}
        \\for(const[index,item]of boxFixture.structural.entries()){let actual;try{actual=new Function('Box','"use strict";'+item.script)(Box)}catch(e){if(e.name===item.errorName&&e.message===item.errorMessage)continue;throw e}if(item.errorName||JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({index,actual,expected:item}));}
        \\const shape={name:Box.name,length:Box.length,own:Object.keys(new Box()),methods:Object.fromEntries(Object.getOwnPropertyNames(Box.prototype).filter(k=>k!=='constructor').map(k=>[k,{name:Box.prototype[k].name,length:Box.prototype[k].length,enumerable:Object.getOwnPropertyDescriptor(Box.prototype,k).enumerable}]))};if(JSON.stringify(shape)!==JSON.stringify(boxFixture.shape))throw Error(JSON.stringify({shape,expected:boxFixture.shape}));
    , "box-component-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Source Box: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const allocationError = @import("native_text_component.zig").allocationError;
    @import("native_tui.zig").install(engine) catch |err| return allocationError(engine, err);
    const result = engine.evalModule(
        \\import{Box,Text}from'pi-tui';const box=new Box(1,1,line=>'\x1b[41m'+line+'\x1b[49m'),text=new Text('Alpha界 words',0,0),child={render:()=>['mouse'],handleMouse(event){return{handled:true,focus:true}},invalidate(){}};box.addChild(text);box.addChild(child);const first=box.render(12);if(first!==box.render(12))throw Error('box cache');box.handleMouse({type:'click',x:1,y:3,screenX:11,screenY:13,width:12,height:6});box.setBgFn(undefined);box.setPaddingX(0);box.render(8);text.setText('changed');box.invalidate();box.render(8);globalThis.retainedBox=box;
    , "box-allocation.mjs") catch |err| return allocationError(engine, err);
    defer engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    const retained = engine.eval("retainedBox.clear();retainedBox.render(8);delete globalThis.retainedBox", "box-retained.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return allocationError(engine, err);
    defer engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}
test "Source6fb public Text Box all allocation failures release retained child cache mouse and background graphs" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
