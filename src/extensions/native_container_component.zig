//! Source Container's ordinary objects, live iteration and mouse-layout values.
const std = @import("std");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
const v = @import("native_select_list.zig");
const Method = enum(c_int) { addChild, removeChild, clear, invalidate, handleMouse, render };
const private_module = "#pi-native-container-internals";
const Traversal = struct { engine: *Engine, path: std.ArrayList(c.JSValue) = .empty, visits: usize = 0 };
fn traversalFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Traversal = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (state.path.items) |item| c.JS_FreeValueRT(runtime, item);
    state.path.deinit(state.engine.gpa);
    state.engine.gpa.destroy(state);
}
fn traversalMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Traversal = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (state.path.items) |item| c.JS_MarkValue(runtime, item, visit);
}
fn containmentCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const state: *Traversal = @ptrCast(@alignCast(c.JS_GetOpaque(data[2], c.JS_GetClassID(data[2])) orelse return c.JS_ThrowTypeError(context, "Invalid containment callback")));
    return containsValue(engine, if (argc == 0) c.pi_js_undefined() else argv[0], data[0], data[1], data[2], state) catch |err| fail(engine, err);
}
fn containsValue(engine: *Engine, root: c.JSValue, target: c.JSValue, constructor: c.JSValue, holder: c.JSValue, state: *Traversal) anyerror!c.JSValue {
    if (state.path.items.len == 0) state.visits = 0;
    if (c.JS_IsStrictEqual(engine.context, root, target)) return c.pi_js_bool(engine.context, 1);
    const admitted = c.JS_IsInstanceOf(engine.context, root, constructor);
    if (admitted < 0) return js.capture(engine);
    if (admitted == 0) return c.pi_js_bool(engine.context, 0);
    state.visits += 1;
    var cycle = false;
    for (state.path.items) |ancestor| if (c.JS_IsStrictEqual(engine.context, root, ancestor)) {
        cycle = true;
        break;
    };
    if (cycle or state.path.items.len >= 128 or state.visits > 4096) {
        _ = try engine.checked(c.JS_ThrowRangeError(engine.context, "Maximum call stack size exceeded"));
        unreachable;
    }
    const owned = c.JS_DupValue(engine.context, root);
    state.path.append(engine.gpa, owned) catch |err| {
        engine.freeValue(owned);
        return err;
    };
    defer engine.freeValue(state.path.pop().?);
    const children = try js.get(engine, root, "children");
    defer engine.freeValue(children);
    var data = [_]c.JSValue{ target, constructor, holder };
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, containmentCallback, "", 1, 0, 3, &data));
    defer engine.freeValue(callback);
    return js.invoke(engine, children, "some", &.{callback});
}
pub fn containsComponent(engine: *Engine, root: c.JSValue, target: c.JSValue) !bool {
    const result = try containsRaw(engine, root, target);
    defer engine.freeValue(result);
    return v.truthy(engine, result);
}
fn containsRaw(engine: *Engine, root: c.JSValue, target: c.JSValue) !c.JSValue {
    const internals = engine.native_module_values.get(private_module) orelse return error.NativeContainerUnavailable;
    const constructor = try js.get(engine, internals, "constructor");
    defer engine.freeValue(constructor);
    const class_value = try js.get(engine, internals, "traversalClass");
    defer engine.freeValue(class_value);
    const class_id: c.JSClassID = @intFromFloat(try v.number(engine, class_value));
    const holder = try engine.checked(c.JS_NewObjectClass(engine.context, class_id));
    defer engine.freeValue(holder);
    const state = try engine.gpa.create(Traversal);
    state.* = .{ .engine = engine };
    _ = c.JS_SetOpaque(holder, state);
    return containsValue(engine, root, target, constructor, holder, state);
}
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Container: %s", @as([*:0]const u8, @errorName(err)));
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
fn layoutCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return layoutEntry(engine, if (argc == 0) c.pi_js_undefined() else argv[0], data[0]) catch |err| fail(engine, err);
}
fn render(engine: *Engine, object: c.JSValue, width: c.JSValue, symbol: c.JSValue) !c.JSValue {
    const lines = try js.array(engine);
    errdefer engine.freeValue(lines);
    const mouse_children = try js.array(engine);
    defer engine.freeValue(mouse_children);
    const children = try js.get(engine, object, "children");
    defer engine.freeValue(children);
    var iterator = try js.Iterator.init(engine, children, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |child| {
        defer engine.freeValue(child);
        const child_lines = try js.invoke(engine, child, "render", &.{width});
        defer engine.freeValue(child_lines);
        const entry = try js.object(engine);
        defer engine.freeValue(entry);
        try js.define(engine, entry, "component", c.JS_DupValue(engine.context, child));
        try js.define(engine, entry, "height", try js.get(engine, child_lines, "length"));
        try js.push(engine, mouse_children, entry);
        var line_iterator = try js.Iterator.init(engine, child_lines, symbol);
        defer line_iterator.deinit();
        errdefer line_iterator.closePreserving();
        while (try line_iterator.next()) |line| {
            defer engine.freeValue(line);
            try js.push(engine, lines, line);
        }
    }
    const layout = try js.object(engine);
    var transferred = false;
    defer if (!transferred) engine.freeValue(layout);
    try js.define(engine, layout, "width", c.JS_DupValue(engine.context, width));
    try js.define(engine, layout, "children", c.JS_DupValue(engine.context, mouse_children));
    transferred = true;
    try v.set(engine, object, "mouseLayout", layout);
    return lines;
}
fn invalidate(engine: *Engine, object: c.JSValue, symbol: c.JSValue) !void {
    const children = try js.get(engine, object, "children");
    defer engine.freeValue(children);
    var iterator = try js.Iterator.init(engine, children, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |child| {
        defer engine.freeValue(child);
        const callback = try js.get(engine, child, "invalidate");
        defer engine.freeValue(callback);
        if (!c.JS_IsNull(callback) and !c.JS_IsUndefined(callback)) {
            const result = try js.call(engine, callback, child, &.{});
            engine.freeValue(result);
        }
    }
}
fn mouse(engine: *Engine, object: c.JSValue, event: c.JSValue, symbol: c.JSValue) !c.JSValue {
    if (try v.numberField(engine, event, "y") < 0 or try v.numberField(engine, event, "y") >= try v.numberField(engine, event, "height")) return c.pi_js_undefined();
    const layout = try js.get(engine, object, "mouseLayout");
    defer engine.freeValue(layout);
    const layout_width = if (c.JS_IsUndefined(layout) or c.JS_IsNull(layout)) c.pi_js_undefined() else try js.get(engine, layout, "width");
    defer engine.freeValue(layout_width);
    const event_width = try js.get(engine, event, "width");
    defer engine.freeValue(event_width);
    const mouse_children = if (c.JS_IsStrictEqual(engine.context, layout_width, event_width)) blk: {
        const current = try js.get(engine, object, "mouseLayout");
        defer engine.freeValue(current);
        break :blk try js.get(engine, current, "children");
    } else blk: {
        const children = try js.get(engine, object, "children");
        defer engine.freeValue(children);
        const width = try js.get(engine, event, "width");
        defer engine.freeValue(width);
        var data = [_]c.JSValue{width};
        const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, layoutCallback, "", 1, 0, 1, &data));
        defer engine.freeValue(callback);
        break :blk try js.invoke(engine, children, "map", &.{callback});
    };
    defer engine.freeValue(mouse_children);
    var iterator = try js.Iterator.init(engine, mouse_children, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var child_y: f64 = 0;
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        const child = try js.get(engine, entry, "component");
        defer engine.freeValue(child);
        const child_height = try js.get(engine, entry, "height");
        defer engine.freeValue(child_height);
        if (try v.numberField(engine, event, "y") >= child_y and try v.numberField(engine, event, "y") < child_y + try v.number(engine, child_height)) {
            const local = try js.spread(engine, event);
            defer engine.freeValue(local);
            try v.set(engine, local, "y", v.numeric(engine, try v.numberField(engine, event, "y") - child_y));
            try v.set(engine, local, "height", c.JS_DupValue(engine.context, child_height));
            const result = try @import("native_mouse.zig").dispatch(engine, child, local);
            errdefer engine.freeValue(result);
            const focus = if (c.JS_IsUndefined(result) or c.JS_IsNull(result)) c.pi_js_undefined() else try js.get(engine, result, "focus");
            defer engine.freeValue(focus);
            if (v.truthy(engine, focus)) {
                const handler = try js.get(engine, object, "handleInput");
                defer engine.freeValue(handler);
                if (v.truthy(engine, handler)) {
                    const forwarded = try js.spread(engine, result);
                    errdefer engine.freeValue(forwarded);
                    try v.set(engine, forwarded, "focusTarget", c.JS_DupValue(engine.context, object));
                    try iterator.close();
                    engine.freeValue(result);
                    return forwarded;
                }
            }
            try iterator.close();
            return result;
        }
        child_y += try v.number(engine, child_height);
    }
    return c.pi_js_undefined();
}
fn methodCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return method(engine, object, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)], data[0]) catch |err| fail(engine, err);
}
fn method(engine: *Engine, object: c.JSValue, operation: Method, args: []const c.JSValue, symbol: c.JSValue) !c.JSValue {
    switch (operation) {
        .addChild => {
            const children = try js.get(engine, object, "children");
            defer engine.freeValue(children);
            try js.push(engine, children, v.arg(args, 0));
        },
        .removeChild => {
            const children = try js.get(engine, object, "children");
            defer engine.freeValue(children);
            const index = try js.invoke(engine, children, "indexOf", &.{v.arg(args, 0)});
            defer engine.freeValue(index);
            if (!c.JS_IsStrictEqual(engine.context, index, v.numeric(engine, -1))) {
                const current = try js.get(engine, object, "children");
                defer engine.freeValue(current);
                try v.invokeVoid(engine, current, "splice", &.{ index, v.numeric(engine, 1) });
            }
        },
        .clear => try v.set(engine, object, "children", try js.array(engine)),
        .invalidate => try invalidate(engine, object, symbol),
        .render => return render(engine, object, v.arg(args, 0), symbol),
        .handleMouse => return mouse(engine, object, v.arg(args, 0), symbol),
    }
    return c.pi_js_undefined();
}
fn construct(engine: *Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const object = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(object);
    try js.define(engine, object, "children", try js.array(engine));
    try js.define(engine, object, "mouseLayout", c.pi_js_undefined());
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
        const arity: c_int = if (std.mem.eql(u8, field.name, "clear") or std.mem.eql(u8, field.name, "invalidate")) 0 else 1;
        var data = [_]c.JSValue{iterator};
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name.ptr, arity, @intCast(field.value), 1, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name.ptr, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    try js.define(engine, exports, "Container", try @import("native_class.zig").constructor(engine, "Container", 0, prototype, construct, &.{}));
    var traversal_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &traversal_class);
    const definition: c.JSClassDef = .{ .class_name = "Native containment callback state", .finalizer = traversalFinalizer, .gc_mark = traversalMark };
    if (c.JS_NewClass(engine.runtime, traversal_class, &definition) < 0) return error.OutOfMemory;
    const internals = try js.object(engine);
    defer engine.freeValue(internals);
    try js.define(engine, internals, "constructor", try js.get(engine, exports, "Container"));
    try js.define(engine, internals, "traversalClass", v.numeric(engine, @floatFromInt(traversal_class)));
    try engine.registerValueModule(private_module, internals);
}
fn testContains(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const args: []const c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
    return containsRaw(engine, v.arg(args, 0), v.arg(args, 1)) catch |err| fail(engine, err);
}
test "Source6fb native Container original iteration mouse shape and containment" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeContains", try engine.checked(c.JS_NewCFunction(engine.context, testContains, "containsComponent", 2)));
    const bytes = @embedFile("fixtures/container-original-6fb.json");
    try js.define(engine, root, "containerFixture", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "container-original-6fb.json")));
    const result = engine.evalModule(
        \\import{Container}from'pi-tui';const TUI={prototype:{containsComponent:nativeContains}};for(const[index,item]of containerFixture.cases.entries()){let actual;try{actual=new Function('Container','TUI','"use strict";'+item.script)(Container,TUI)}catch(e){if(item.errorName===e.name&&item.errorMessage===e.message)continue;throw Error(JSON.stringify({index,error:String(e),expected:item}))}if(item.errorName||JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({index,actual,expected:item}));}const shape={name:Container.name,length:Container.length,own:Object.keys(new Container()),methods:Object.fromEntries(Object.getOwnPropertyNames(Container.prototype).filter(k=>k!=='constructor').map(k=>[k,{name:Container.prototype[k].name,length:Container.prototype[k].length,enumerable:Object.getOwnPropertyDescriptor(Container.prototype,k).enumerable}]))};if(JSON.stringify(shape)!==JSON.stringify(containerFixture.shape))throw Error(JSON.stringify({shape,expected:containerFixture.shape}));
    , "container-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Container: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const exports = try js.object(engine);
    defer engine.freeValue(exports);
    try install(engine, exports);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "Container", try js.get(engine, exports, "Container"));
    try js.define(engine, root, "nativeContains", try engine.checked(c.JS_NewCFunction(engine.context, testContains, "containsComponent", 2)));
    const original_allocator = engine.gpa;
    engine.gpa = gpa;
    defer engine.gpa = original_allocator;
    defer engine.beginInvocation();
    const result = engine.eval(
        \\(()=>{const root=new Container(),nested=new Container(),target={render:width=>['value'+width],invalidate(){},handleMouse(){return{handled:true,focus:true}}};nested.addChild(target);root.addChild(nested);root.render(8);root.invalidate();if(!nativeContains(root,target))throw Error('nested focus');root.handleInput=()=>{};if(root.handleMouse({y:0,height:2,width:8,x:0,type:'press',button:'left'}).focusTarget!==root)throw Error('focus forwarding');let saved;const retained=Object.create(Container.prototype);retained.children={some(callback){saved=callback;return false}};if(nativeContains(retained,target)||!saved(root))throw Error('retained callback');saved=undefined;nested.clear();root.removeChild(nested);root.clear();return true})()
    , "container-owned-allocation.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return @import("native_text_component.zig").allocationError(engine, err);
    engine.freeValue(result);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "Source6fb native Container all allocation failures release retained containment callbacks and layouts" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
