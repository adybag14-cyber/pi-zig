//! Source MouseRegion and owner-thread mouse dispatch. Retained targets never
//! cross the VM boundary; the protocol carries their fenced numeric handles.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const State = struct { engine: *engine_mod.Engine, prototype: c.JSValue };
const Method = enum(c_int) { render, handleMouse, invalidate };
fn get(engine: *engine_mod.Engine, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, value, name));
}
fn put(engine: *engine_mod.Engine, value: c.JSValue, name: [*:0]const u8, property: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, value, name, property, c.JS_PROP_C_W_E) < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        return error.JavaScriptException;
    }
}
fn object(engine: *engine_mod.Engine) !c.JSValue {
    return engine.checked(c.JS_NewObject(engine.context));
}
fn call(engine: *engine_mod.Engine, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Call(engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)));
}
fn invoke(engine: *engine_mod.Engine, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const function = try get(engine, receiver, name);
    defer engine.freeValue(function);
    return call(engine, function, receiver, args);
}
fn fail(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native mouse: %s", @as([*:0]const u8, @errorName(err)));
}
fn copy(engine: *engine_mod.Engine, source: c.JSValue) !c.JSValue {
    const result = try object(engine);
    errdefer engine.freeValue(result);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, source, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        return error.JavaScriptException;
    }
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (names[0..count]) |entry| {
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(engine.context, &descriptor, source, entry.atom);
        if (present < 0) {
            _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
            return error.JavaScriptException;
        }
        if (present == 0) continue;
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try engine.checked(c.JS_GetProperty(engine.context, source, entry.atom));
        if (c.JS_DefinePropertyValue(engine.context, result, entry.atom, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    return result;
}
fn truthy(engine: *engine_mod.Engine, value: c.JSValue, name: [*:0]const u8) !bool {
    const property = try get(engine, value, name);
    defer engine.freeValue(property);
    return c.JS_ToBool(engine.context, property) != 0;
}
fn difference(engine: *engine_mod.Engine, value: c.JSValue, left_name: [*:0]const u8, right_name: [*:0]const u8) !f64 {
    return subtract(engine, value, left_name, value, right_name);
}
fn subtract(engine: *engine_mod.Engine, lhs_object: c.JSValue, left_name: [*:0]const u8, rhs_object: c.JSValue, right_name: [*:0]const u8) !f64 {
    // Both operands are read before either observable numeric conversion.
    const left = try get(engine, lhs_object, left_name);
    defer engine.freeValue(left);
    const right = try get(engine, rhs_object, right_name);
    defer engine.freeValue(right);
    const lhs = try @import("native_color.zig").number(engine, left);
    const rhs = try @import("native_color.zig").number(engine, right);
    return lhs - rhs;
}
pub fn retarget(engine: *engine_mod.Engine, event: c.JSValue, target: c.JSValue) !c.JSValue {
    const result = try copy(engine, event);
    errdefer engine.freeValue(result);
    try put(engine, result, "x", c.JS_NewFloat64(engine.context, try subtract(engine, event, "screenX", target, "originX")));
    try put(engine, result, "y", c.JS_NewFloat64(engine.context, try subtract(engine, event, "screenY", target, "originY")));
    try put(engine, result, "width", try get(engine, target, "width"));
    try put(engine, result, "height", try get(engine, target, "height"));
    return result;
}
pub fn eventValue(engine: *engine_mod.Engine, event: @import("component_protocol.zig").Mouse) !c.JSValue {
    var buffer: std.Io.Writer.Allocating = .init(engine.gpa);
    defer buffer.deinit();
    @import("component_protocol.zig").writeMouse(&buffer.writer, event) catch return error.OutOfMemory;
    const text = try engine.gpa.dupeZ(u8, buffer.written());
    defer engine.gpa.free(text);
    return engine.checked(c.JS_ParseJSON(engine.context, text.ptr, text.len, "native-mouse-event.json"));
}
fn layoutEntry(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return makeLayoutEntry(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), data[0]) catch |err| fail(engine, err);
}
fn makeLayoutEntry(engine: *engine_mod.Engine, component: c.JSValue, width: c.JSValue) !c.JSValue {
    var args = [_]c.JSValue{width};
    const lines = try invoke(engine, component, "render", &args);
    defer engine.freeValue(lines);
    const entry = try object(engine);
    errdefer engine.freeValue(entry);
    try put(engine, entry, "component", c.JS_DupValue(engine.context, component));
    try put(engine, entry, "height", try get(engine, lines, "length"));
    return entry;
}
pub fn childLayout(engine: *engine_mod.Engine, receiver: c.JSValue, width: c.JSValue) !c.JSValue {
    const layout = try get(engine, receiver, "mouseLayout");
    defer engine.freeValue(layout);
    if (!c.JS_IsNull(layout) and !c.JS_IsUndefined(layout)) {
        const cached_width = try get(engine, layout, "width");
        defer engine.freeValue(cached_width);
        if (c.JS_IsStrictEqual(engine.context, cached_width, width)) return get(engine, layout, "children");
    }
    const children = try get(engine, receiver, "children");
    defer engine.freeValue(children);
    var data = [_]c.JSValue{width};
    const mapper = try engine.checked(c.JS_NewCFunctionData2(engine.context, layoutEntry, "mouseLayoutEntry", 1, 0, data.len, &data));
    defer engine.freeValue(mapper);
    var args = [_]c.JSValue{mapper};
    return invoke(engine, children, "map", &args);
}
pub fn containerDispatch(engine: *engine_mod.Engine, receiver: c.JSValue, event: c.JSValue, padding_x: f64, padding_y: f64, box: bool) !c.JSValue {
    const y_value = try get(engine, event, "y");
    defer engine.freeValue(y_value);
    const y = try @import("native_color.zig").number(engine, y_value);
    const event_height = try get(engine, event, "height");
    defer engine.freeValue(event_height);
    const height = try @import("native_color.zig").number(engine, event_height);
    const width_value = try get(engine, event, "width");
    defer engine.freeValue(width_value);
    const width = try @import("native_color.zig").number(engine, width_value);
    const x_value = try get(engine, event, "x");
    defer engine.freeValue(x_value);
    const x = try @import("native_color.zig").number(engine, x_value);
    const content_x = x - padding_x;
    const content_y = y - padding_y;
    const content_width = if (box) @max(1, width - padding_x * 2) else width;
    if (box) {
        if (content_y < 0 or content_x < 0 or content_x >= content_width) return c.pi_js_undefined();
    } else if (y < 0 or y >= height) return c.pi_js_undefined();
    const children = try childLayout(engine, receiver, c.JS_NewFloat64(engine.context, content_width));
    defer engine.freeValue(children);
    const length_value = try get(engine, children, "length");
    defer engine.freeValue(length_value);
    var length: u32 = 0;
    if (c.JS_ToUint32(engine.context, &length, length_value) < 0) return error.JavaScriptException;
    var child_y: f64 = 0;
    for (0..length) |index| {
        const entry = try engine.checked(c.JS_GetPropertyUint32(engine.context, children, @intCast(index)));
        defer engine.freeValue(entry);
        const child = try get(engine, entry, "component");
        defer engine.freeValue(child);
        const child_height_value = try get(engine, entry, "height");
        defer engine.freeValue(child_height_value);
        const child_height = try @import("native_color.zig").number(engine, child_height_value);
        if (content_y >= child_y and content_y < child_y + child_height) {
            const local = try copy(engine, event);
            defer engine.freeValue(local);
            if (box) {
                try put(engine, local, "x", c.JS_NewFloat64(engine.context, content_x));
                try put(engine, local, "width", c.JS_NewFloat64(engine.context, content_width));
            }
            try put(engine, local, "y", c.JS_NewFloat64(engine.context, content_y - child_y));
            try put(engine, local, "height", c.JS_DupValue(engine.context, child_height_value));
            const result = try dispatch(engine, child, local);
            if (!box and !c.JS_IsUndefined(result) and try truthy(engine, result, "focus") and try truthy(engine, receiver, "handleInput")) {
                defer engine.freeValue(result);
                const forwarded = try copy(engine, result);
                errdefer engine.freeValue(forwarded);
                try put(engine, forwarded, "focusTarget", c.JS_DupValue(engine.context, receiver));
                return forwarded;
            }
            return result;
        }
        child_y += child_height;
    }
    return c.pi_js_undefined();
}
pub fn dispatch(engine: *engine_mod.Engine, component: c.JSValue, event: c.JSValue) !c.JSValue {
    const handler = try get(engine, component, "handleMouse");
    defer engine.freeValue(handler);
    if (c.JS_IsUndefined(handler) or c.JS_IsNull(handler)) return c.pi_js_undefined();
    var args = [_]c.JSValue{event};
    const result = try call(engine, handler, component, &args);
    defer engine.freeValue(result);
    if (c.JS_ToBool(engine.context, result) == 0) return c.pi_js_undefined();
    if (!c.JS_IsObject(result)) {
        const text = try engine.toString(result);
        defer engine.gpa.free(text);
        const message = try std.fmt.allocPrint(engine.gpa, "Cannot use 'in' operator to search for 'target' in {s}", .{text});
        defer engine.gpa.free(message);
        const terminated = try engine.gpa.dupeZ(u8, message);
        defer engine.gpa.free(terminated);
        _ = try engine.checked(c.JS_ThrowTypeError(engine.context, "%s", terminated.ptr));
        return error.JavaScriptException;
    }
    const atom = c.JS_NewAtom(engine.context, "target");
    defer c.JS_FreeAtom(engine.context, atom);
    const has_target = c.JS_HasProperty(engine.context, result, atom);
    if (has_target < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        return error.JavaScriptException;
    }
    if (has_target != 0) {
        if (try truthy(engine, result, "focus") and try truthy(engine, component, "handleInput")) {
            const forwarded = try copy(engine, result);
            errdefer engine.freeValue(forwarded);
            try put(engine, forwarded, "focusTarget", c.JS_DupValue(engine.context, component));
            return forwarded;
        }
        return c.JS_DupValue(engine.context, result);
    }
    if (!try truthy(engine, result, "handled") and !try truthy(engine, result, "capture") and !try truthy(engine, result, "focus")) return c.pi_js_undefined();
    const normalized = try copy(engine, result);
    errdefer engine.freeValue(normalized);
    try put(engine, normalized, "handled", c.JS_NewBool(engine.context, true));
    if (try truthy(engine, result, "focus")) try put(engine, normalized, "focusTarget", c.JS_DupValue(engine.context, component));
    const target = try object(engine);
    var transferred = false;
    defer if (!transferred) engine.freeValue(target);
    try put(engine, target, "component", c.JS_DupValue(engine.context, component));
    try put(engine, target, "originX", c.JS_NewFloat64(engine.context, try difference(engine, event, "screenX", "x")));
    try put(engine, target, "originY", c.JS_NewFloat64(engine.context, try difference(engine, event, "screenY", "y")));
    try put(engine, target, "width", try get(engine, event, "width"));
    try put(engine, target, "height", try get(engine, event, "height"));
    transferred = true;
    try put(engine, normalized, "target", target);
    return normalized;
}
fn methodCall(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return operate(engine, receiver, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn operate(engine: *engine_mod.Engine, receiver: c.JSValue, method: Method, argument: c.JSValue) !c.JSValue {
    const child = try get(engine, receiver, "child");
    defer engine.freeValue(child);
    var args = [_]c.JSValue{argument};
    return switch (method) {
        .render => invoke(engine, child, "render", &args),
        .invalidate => blk: {
            const result = try invoke(engine, child, "invalidate", &.{});
            engine.freeValue(result);
            break :blk c.pi_js_undefined();
        },
        .handleMouse => blk: {
            const result = try dispatch(engine, child, argument);
            if (!c.JS_IsUndefined(result) and !c.JS_IsNull(result)) break :blk result;
            engine.freeValue(result);
            break :blk try invoke(engine, receiver, "onMouse", &args);
        },
    };
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.prototype);
    state.engine.gpa.destroy(state);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, callback: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.prototype, callback);
}
fn construct(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) return c.JS_ThrowTypeError(context, "Class constructor MouseRegion cannot be invoked without 'new'");
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)) orelse return c.JS_ThrowTypeError(context, "Invalid MouseRegion constructor")));
    return create(engine, state, target, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn create(engine: *engine_mod.Engine, state: *State, target: c.JSValue, args: []const c.JSValue) !c.JSValue {
    _ = state;
    const inherited = try get(engine, target, "prototype");
    defer engine.freeValue(inherited);
    const result = try engine.checked(if (c.JS_IsObject(inherited)) c.JS_NewObjectProto(engine.context, inherited) else c.JS_NewObject(engine.context));
    errdefer engine.freeValue(result);
    try put(engine, result, "child", c.JS_DupValue(engine.context, if (args.len > 0) args[0] else c.pi_js_undefined()));
    try put(engine, result, "onMouse", c.JS_DupValue(engine.context, if (args.len > 1) args[1] else c.pi_js_undefined()));
    return result;
}
pub fn install(engine: *engine_mod.Engine, exports: c.JSValue) !void {
    var class_id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class_id);
    var definition = std.mem.zeroes(c.JSClassDef);
    definition.class_name = "MouseRegion Constructor";
    definition.finalizer = finalize;
    definition.gc_mark = mark;
    definition.call = construct;
    if (c.JS_NewClass(engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
    const prototype = try object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    inline for (std.meta.fields(Method)) |method| {
        const function_value = try engine.checked(c.pi_js_function_magic(engine.context, methodCall, method.name, if (method.value == @intFromEnum(Method.invalidate)) 0 else 1, @intCast(method.value)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, method.name, function_value, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    }
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const function = try get(engine, global, "Function");
    defer engine.freeValue(function);
    const function_prototype = try get(engine, function, "prototype");
    defer engine.freeValue(function_prototype);
    const constructor = try engine.checked(c.JS_NewObjectProtoClass(engine.context, function_prototype, class_id));
    defer engine.freeValue(constructor);
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .prototype = c.JS_DupValue(engine.context, prototype) };
    _ = c.JS_SetOpaque(constructor, state);
    _ = c.JS_SetConstructorBit(engine.context, constructor, true);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "length", c.JS_NewInt32(engine.context, 2), c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "name", try engine.checked(c.JS_NewString(engine.context, "MouseRegion")), c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
    try put(engine, exports, "MouseRegion", c.JS_DupValue(engine.context, constructor));
}

fn dispatchProbe(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return dispatch(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
test "actual original MouseRegion dispatch fallback forwarding target focus shape getter order and symbol spread replay" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const fixture = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("fixtures/mouse-original-7fb.json"), .{});
    defer fixture.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try put(engine, global, "mouseOracle", try engine.fromJsonValue(fixture.value));
    try put(engine, global, "dispatchMouseProbe", try engine.checked(c.JS_NewCFunction(engine.context, dispatchProbe, "dispatchMouseEvent", 2)));
    const module = try engine.evalModule(
        \\import {MouseRegion} from 'pi-tui';
        \\const event=mouseOracle.event,cases=[];
        \\function observe(value,components){if(value===undefined)return null;return Object.fromEntries(Reflect.ownKeys(value).filter(key=>typeof key==='string').map(key=>[key,key==='target'?{...value.target,component:components.indexOf(value.target.component)}:key==='focusTarget'?components.indexOf(value.focusTarget):value[key]]))}
        \\for(const kind of ['absent','undefined','unhandled','handled','capture','focus','forwarded','forwarded-focus'])for(const hasInput of [false,true]){const child={render(width){return ['child:'+width]},invalidate(){return 'ignored'}},outer={},target={component:child,originX:7,originY:9,width:11,height:12};const outputs={undefined:undefined,unhandled:{render:true},handled:{handled:true,render:false},capture:{capture:true},focus:{focus:true},forwarded:{handled:true,target},'forwarded-focus':{handled:true,focus:true,target,focusTarget:child}};if(kind!=='absent')child.handleMouse=function(actual){if(this!==child||actual!==event)throw Error('receiver/event');return outputs[kind]};if(hasInput)outer.handleInput=()=>{};const regionObject=new MouseRegion(child,function(actual){if(this!==regionObject||actual!==event)throw Error('fallback receiver/event');return {handled:true,fallback:true}});if(hasInput)regionObject.handleInput=outer.handleInput;const result=dispatchMouseProbe(regionObject,event);cases.push({kind,hasInput,result:observe(result,[child,regionObject]),render:regionObject.render(17),invalidate:regionObject.invalidate()??null,keys:Object.keys(regionObject),prototypeKeys:Object.keys(MouseRegion.prototype)});globalThis.retainedMouse=regionObject;}
        \\const logs=[],symbol=Symbol('source'),metadata={get handled(){logs.push('handled');return true},get focus(){logs.push('focus');return true},get discard(){logs.push('discard');delete metadata.later;return 'kept'},later:'removed',[symbol]:'symbol-value'},component={handleMouse(){return metadata},handleInput(){}};const enriched=dispatchMouseProbe(component,event),getterCase={logs,result:observe(enriched,[component]),symbolRetained:enriched[symbol]==='symbol-value',laterPresent:Object.hasOwn(enriched,'later')};
        \\const constructorShape={name:MouseRegion.name,length:MouseRegion.length,keys:Object.keys(MouseRegion),prototypeWritable:Object.getOwnPropertyDescriptor(MouseRegion,'prototype').writable};for(const [expected,actual]of [[mouseOracle.cases,cases],[mouseOracle.getterCase,getterCase],[mouseOracle.constructorShape,constructorShape]])if(JSON.stringify(expected)!==JSON.stringify(actual))throw Error(JSON.stringify({expected,actual}));
        \\const marker={};let same=false;try{dispatchMouseProbe({get handleMouse(){throw marker}},event)}catch(error){same=error===marker}if(!same)throw Error('handler getter identity');same=false;try{new MouseRegion({render(){throw marker}},()=>{}).render(1)}catch(error){same=error===marker}if(!same)throw Error('render error identity');class Child extends MouseRegion{};const inherited=new Child({render(){return ['subclass']},invalidate(){}},()=>undefined);if(!(inherited instanceof Child)||!(inherited instanceof MouseRegion)||inherited.render(1)[0]!=='subclass')throw Error('subclass');
    , "native-mouse-original.mjs");
    defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval("if(retainedMouse.render(5)[0]!=='child:5')throw Error('retained child');delete globalThis.retainedMouse;", "native-mouse-retained.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}
test "actual original mouse wheel fixed automatic burst gesture direction fractional carry and reset replay" {
    const wheel = @import("../tui/wheel_scroll.zig");
    const fixture = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("../tui/fixtures/wheel-original-7fb.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items) |item| {
        const spec = item.object.get("lines").?;
        const lines: wheel.Lines = if (spec == .string) if (std.mem.eql(u8, spec.string, "auto")) .auto else .{ .fixed = if (std.mem.eql(u8, spec.string, "infinity")) std.math.inf(f64) else std.math.nan(f64) } else .{ .fixed = if (spec == .integer) @floatFromInt(spec.integer) else spec.float };
        var accelerator: wheel.Accelerator = .{ .lines = lines, .accelerate = item.object.get("accelerate").?.bool };
        for (item.object.get("points").?.array.items, item.object.get("values").?.array.items) |point, expected| {
            const actual = accelerator.next(@intCast(point.array.items[0].integer), @floatFromInt(point.array.items[1].integer));
            try std.testing.expectEqual(@as(f64, @floatFromInt(expected.integer)), actual);
        }
    }
    var reset: wheel.Accelerator = .{};
    _ = reset.next(1, 0);
    _ = reset.next(1, 20);
    reset.setLines(.{ .fixed = 4.8 });
    try std.testing.expectEqual(@as(f64, @floatFromInt(fixture.value.object.get("setLines").?.object.get("fixed").?.integer)), reset.next(1, 30));
    reset.setLines(.auto);
    try std.testing.expectEqual(@as(f64, @floatFromInt(fixture.value.object.get("setLines").?.object.get("reset").?.integer)), reset.next(1, 40));
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const result = engine.evalModule("import {MouseRegion} from 'pi-tui';const marker={};globalThis.mouseRoot=new MouseRegion({render(width){return ['width:'+width]},invalidate(){},handleMouse(){return {handled:true,capture:true,focus:true}}},()=>undefined);mouseRoot.render(5);mouseRoot.invalidate();", "mouse-allocation-input.mjs") catch |err| return allocationError(engine, err);
    defer engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const root = get(engine, global, "mouseRoot") catch |err| return allocationError(engine, err);
    defer engine.freeValue(root);
    const event = eventValue(engine, .{ .kind = .press, .button = .left, .x = 2, .y = 3, .screen_x = 12, .screen_y = 23, .width = 40, .height = 20 }) catch |err| return allocationError(engine, err);
    defer engine.freeValue(event);
    const handled = dispatch(engine, root, event) catch |err| return allocationError(engine, err);
    defer engine.freeValue(handled);
    c.JS_RunGC(engine.runtime);
    const target = get(engine, handled, "target") catch |err| return allocationError(engine, err);
    defer engine.freeValue(target);
    const local = retarget(engine, event, target) catch |err| return allocationError(engine, err);
    defer engine.freeValue(local);
}
fn allocationError(engine: *engine_mod.Engine, err: anyerror) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |value| {
        const message = get(engine, value, "message") catch return error.OutOfMemory;
        defer engine.freeValue(message);
        const text = engine.toString(message) catch return error.OutOfMemory;
        defer engine.gpa.free(text);
        if (std.mem.indexOf(u8, text, "out of memory") != null or std.mem.indexOf(u8, text, "OutOfMemory") != null) return error.OutOfMemory;
    };
    return err;
}
test "MouseRegion construction callback dispatch retarget and final VM retirement release every induced allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
test "actual original nested Container Box padding cached mouse layout and delegating parent focus replay" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const fixture = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("fixtures/mouse-container-original-7fb.json"), .{});
    defer fixture.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try put(engine, global, "mouseContainerOracle", try engine.fromJsonValue(fixture.value));
    try put(engine, global, "dispatchMouseProbe", try engine.checked(c.JS_NewCFunction(engine.context, dispatchProbe, "dispatchMouseEvent", 2)));
    const script = try engine.evalModule(
        \\import {Container,Box} from 'pi-tui';const cases=[],event=mouseContainerOracle.event;
        \\for(const kind of ['container','box'])for(const hasInput of [false,true])for(const cached of [false,true]){const logs=[],parent=kind==='box'?new Box(2,1):new Container();const a={render(width){logs.push(['render','a',width]);return ['a0','a1']},handleMouse(e){logs.push(['mouse','a',{...e}]);return {handled:true,focus:true}}};const b={render(width){logs.push(['render','b',width]);return ['b0']},handleMouse(e){logs.push(['mouse','b',{...e}]);return {handled:true,focus:true}}};parent.addChild(a);parent.addChild(b);if(hasInput)parent.handleInput=()=>{};if(cached){if(kind==='container')parent.render(20);else parent.mouseLayout={width:16,children:[{component:a,height:2},{component:b,height:1}]};logs.length=0;parent.children=[]}const result=dispatchMouseProbe(parent,event);cases.push({kind,hasInput,cached,logs,result:result?{...result,focusTarget:result.focusTarget===parent?'parent':result.focusTarget===a?'a':'b',target:{...result.target,component:result.target.component===a?'a':'b'}}:null})}
        \\if(JSON.stringify(cases)!==JSON.stringify(mouseContainerOracle.cases))throw Error(JSON.stringify({actual:cases,expected:mouseContainerOracle.cases}));
    , "native-container-mouse-original.mjs");
    defer engine.freeValue(script);
    c.JS_RunGC(engine.runtime);
}
