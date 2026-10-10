//! Genuine Source TuiMainScreen class over complete ordinary TuiBase methods.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const state = @import("native_tui_main_state.zig");
const images = @import("native_tui_main_images.zig");
const Method = enum(c_int) { captureRenderState, restoreRenderState, resetRenderState, beforeTerminalStop, collectKittyImageIds, deleteKittyImages, getKittyImageReservedRows, expandChangedRangeForKittyImages, deleteChangedKittyImages, doRender, positionHardwareCursor };
const Binding = enum(c_int) { fs, path, os };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native TuiMainScreen: %s", @as([*:0]const u8, @errorName(err)));
}
fn bindingCall(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return bindingValue(engine, @enumFromInt(magic), data[0]) catch |err| fail(engine, err);
}
fn bindingValue(engine: *js.Engine, binding: Binding, record: c.JSValue) !c.JSValue {
    const name = switch (binding) {
        .fs => "node:fs",
        .path => "node:path",
        .os => "node:os",
    };
    if (engine.native_module_values.get(name)) |module| return c.JS_DupValue(engine.context, module);
    if (binding != .os) return error.NativeTuiMainIoBindingUnavailable;
    const cached = try js.get(engine, record, "privateOs");
    if (!c.JS_IsUndefined(cached)) return cached;
    engine.freeValue(cached);
    const object = try @import("native_os_tmpdir.zig").create(engine);
    errdefer engine.freeValue(object);
    try js.define(engine, record, "privateOs", c.JS_DupValue(engine.context, object));
    return object;
}
fn methodCall(context: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invoke(engine, this, data[0], @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| fail(engine, err);
}
fn invoke(engine: *js.Engine, this: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    if (method == .doRender) return @import("native_tui_main_render.zig").render(engine, this, bindings);
    inline for (.{ state, images }) |module| {
        inline for (std.meta.fields(module.Method)) |field| if (method == @field(Method, field.name)) return module.invoke(engine, this, bindings, @enumFromInt(field.value), args);
    }
    unreachable;
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    const self = try js.get(engine, data[0], "TuiMainScreen");
    defer engine.freeValue(self);
    const parent = try engine.checked(c.JS_GetPrototype(engine.context, self));
    defer engine.freeValue(parent);
    const object = try engine.checked(c.JS_CallConstructor2(engine.context, parent, target, @intCast(args.len), @constCast(args.ptr)));
    errdefer engine.freeValue(object);
    try state.initialize(engine, object);
    return object;
}
pub fn create(engine: *js.Engine, exports: c.JSValue, base: c.JSValue) !c.JSValue {
    const bindings = try js.object(engine);
    defer engine.freeValue(bindings);
    inline for (.{ "isImageLine", "deleteKittyImage", "visibleWidth" }) |name| try js.define(engine, bindings, name, try js.get(engine, exports, name));
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    try js.define(engine, bindings, "iteratorSymbol", try js.get(engine, symbol, "iterator"));
    try js.define(engine, bindings, "primitiveSymbol", try js.get(engine, symbol, "toPrimitive"));
    inline for (std.meta.fields(Binding)) |field| {
        const atom = c.JS_NewAtom(engine.context, field.name);
        if (atom == c.JS_ATOM_NULL) return js.capture(engine);
        defer c.JS_FreeAtom(engine.context, atom);
        var data = [_]c.JSValue{bindings};
        const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, bindingCall, "get " ++ field.name, 0, field.value, 1, &data));
        if (c.JS_DefinePropertyGetSet(engine.context, bindings, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
    const parent_prototype = try js.get(engine, base, "prototype");
    defer engine.freeValue(parent_prototype);
    const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, parent_prototype));
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        const length: c_int = switch (method) {
            .restoreRenderState, .beforeTerminalStop, .collectKittyImageIds, .deleteKittyImages => 1,
            .getKittyImageReservedRows, .deleteChangedKittyImages, .positionHardwareCursor => 2,
            .expandChangedRangeForKittyImages => 3,
            else => 0,
        };
        var data = [_]c.JSValue{bindings};
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, field.name, length, field.value, 1, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const constructor = try @import("native_class.zig").constructor(engine, "TuiMainScreen", 0, prototype, construct, &.{bindings});
    errdefer engine.freeValue(constructor);
    if (c.JS_SetPrototype(engine.context, constructor, base) < 0) return js.capture(engine);
    try js.define(engine, bindings, "TuiMainScreen", c.JS_DupValue(engine.context, constructor));
    return constructor;
}
pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    const base = try @import("native_tui_base.zig").create(engine, exports);
    defer engine.freeValue(base);
    try js.define(engine, exports, "TuiMainScreen", try create(engine, exports, base));
}
