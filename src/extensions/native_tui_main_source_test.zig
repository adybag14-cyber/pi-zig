//! Actual Source class fields/state and complete lossless terminal write replays.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
fn setup() !*js.Engine {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    errdefer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"tui-main-source"});
    try @import("node_fs.zig").install(engine, std.testing.io);
    try @import("node_path.zig").install(engine, std.testing.io);
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_tui.zig").install(engine);
    return engine;
}
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Source write probe: %s", @as([*:0]const u8, @errorName(err)));
}
fn summarize(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return summaries(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn summaries(engine: *js.Engine, writes: c.JSValue) !c.JSValue {
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    const length = try v.numberField(engine, writes, "length");
    var index: u32 = 0;
    while (@as(f64, @floatFromInt(index)) < length) : (index += 1) {
        const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, writes, index));
        defer engine.freeValue(value);
        const units = try @import("native_utf16.zig").unitsAlloc(engine, value);
        defer engine.gpa.free(units);
        const encoded = try engine.gpa.alloc(u8, units.len * 2);
        defer engine.gpa.free(encoded);
        for (units, 0..) |unit, position| std.mem.writeInt(u16, encoded[position * 2 ..][0..2], unit, .little);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(encoded, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        const summary = blk: {
            const object = try js.object(engine);
            errdefer engine.freeValue(object);
            try js.define(engine, object, "length", v.numeric(engine, @floatFromInt(units.len)));
            try js.define(engine, object, "utf16leSHA256", try v.text(engine, &hex));
            try js.define(engine, object, "start", try js.invoke(engine, value, "slice", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewInt32(engine.context, 24) }));
            try js.define(engine, object, "end", try js.invoke(engine, value, "slice", &.{c.JS_NewInt32(engine.context, -24)}));
            try js.define(engine, object, "first", try js.invoke(engine, value, "charCodeAt", &.{c.JS_NewInt32(engine.context, 0)}));
            try js.define(engine, object, "last", try js.invoke(engine, value, "charCodeAt", &.{v.numeric(engine, @as(f64, @floatFromInt(units.len)) - 1)}));
            break :blk object;
        };
        if (c.JS_DefinePropertyValueUint32(engine.context, result, index, summary, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    }
    return result;
}
test "Source6fb native TuiMainScreen genuine constructor fields hierarchy and render state" {
    const engine = try setup();
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const expected = @embedFile("fixtures/tui-screen-construction-original-6fb.json");
    try js.define(engine, root, "mainConstructionSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "tui-screen-construction-original-6fb.json")));
    const result = engine.evalModule(
        \\import{TuiMainScreen,Container,isViewportTUI}from'pi-tui';
        \\function shape(value){return Reflect.ownKeys(value).map(key=>{const d=Object.getOwnPropertyDescriptor(value,key),entry={key:typeof key==='symbol'?'Symbol('+key.description+')':key,enumerable:d.enumerable,configurable:d.configurable,writable:d.writable,type:typeof d.value};if(d.value===null)entry.value=null;else if(d.value instanceof Set||d.value instanceof Map)entry.value={kind:d.value.constructor.name,size:d.value.size};else if(Array.isArray(d.value))entry.value=d.value;else if(typeof d.value==='function')entry.value={name:d.value.name,length:d.value.length};else if(typeof d.value!=='object')entry.value=d.value;else entry.value={kind:d.value.constructor?.name??null,keys:Object.keys(d.value)};return entry})}
        \\const cases=[];for(const cursor of[undefined,false,true]){const terminal={columns:40,rows:12,write(){},start(){},stop(){},hideCursor(){},showCursor(){}},instance=new TuiMainScreen(terminal,cursor,'source-debug',{mouse:false,copyOnSelect:false}),TuiBase=Object.getPrototypeOf(TuiMainScreen);cases.push({name:'main '+String(cursor),shape:shape(instance),terminalIdentity:instance.terminal===terminal,mode:instance.mode,container:instance instanceof Container,base:instance instanceof TuiBase,viewport:isViewportTUI(instance),parentConstructor:Object.getPrototypeOf(TuiMainScreen).name,instanceParents:[Object.getPrototypeOf(instance).constructor.name,Object.getPrototypeOf(Object.getPrototypeOf(instance)).constructor.name,Object.getPrototypeOf(Object.getPrototypeOf(Object.getPrototypeOf(instance))).constructor.name],hardwareCursor:instance.getShowHardwareCursor(),clearOnShrink:instance.getClearOnShrink(),focused:instance.getFocusedComponent(),fullRedraws:instance.fullRedraws,overlayEntries:instance.hasOverlayEntries,renderState:instance.captureRenderState()});}
        \\const expected=mainConstructionSource.cases.filter(value=>value.name.startsWith('main '));if(JSON.stringify(cases)!==JSON.stringify(expected))throw Error(JSON.stringify({actual:cases,expected}));
    , "tui-main-construction-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native TuiMainScreen construction: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb native TuiMainScreen complete actual callable descriptors and method constructibility" {
    const engine = try setup();
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const expected = @embedFile("fixtures/tui-main-callables-original-6fb.json");
    try js.define(engine, root, "mainCallablesSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "tui-main-callables-original-6fb.json")));
    const result = engine.evalModule(
        \\import * as tui from'pi-tui';
        \\function callable(value){return Reflect.ownKeys(value).map(key=>{const descriptor=Object.getOwnPropertyDescriptor(value,key);return{key:typeof key==='symbol'?'Symbol('+key.description+')':key,enumerable:descriptor.enumerable,configurable:descriptor.configurable,writable:descriptor.writable,type:typeof descriptor.value,value:typeof descriptor.value==='function'?{name:descriptor.value.name,length:descriptor.value.length}:typeof descriptor.value==='object'?{kind:descriptor.value?.constructor?.name??null}:descriptor.value}})}
        \\const main=tui.TuiMainScreen;const cases={constructor:callable(main),prototype:callable(main.prototype),methods:Object.getOwnPropertyNames(main.prototype).filter(key=>key!=='constructor').map(key=>({key,own:callable(main.prototype[key]),constructible:(()=>{try{Reflect.construct(main.prototype[key],[]);return true}catch(error){return error instanceof TypeError?false:error.name}})()}))};
        \\if(JSON.stringify(cases)!==JSON.stringify(mainCallablesSource.cases))throw Error(JSON.stringify({actual:cases,expected:mainCallablesSource.cases}));
    , "tui-main-callables-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native TuiMainScreen callables: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Native TuiMainScreen ordinary class registration permits subsequent genuine process binding" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"tui-main-late-process"});
    try @import("timers.zig").install(engine, std.testing.io);
    const result = try engine.evalModule(
        \\import{TuiMainScreen,Container}from'pi-tui';
        \\const terminal={columns:20,rows:4,write(){},hideCursor(){},showCursor(){},start(){},stop(){}},screen=new TuiMainScreen(terminal,false);
        \\if(!(screen instanceof Container)||screen.mode!=='regular')throw Error('ordinary class registration changed');
        \\screen.addChild({render(){return['bound']},invalidate(){}});screen.renderNow();
        \\if(screen.captureRenderState().previousLines.length!==1||screen.fullRedraws!==1)throw Error(JSON.stringify(screen.captureRenderState()));
    , "tui-main-late-process.mjs");
    engine.freeValue(result);
}
test "Source6fb native TuiMainScreen exact differential writes scrollback resize images cursor and bounded surrogate chunks" {
    const engine = try setup();
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const expected = @embedFile("fixtures/tui-main-rendering-original-6fb.json");
    try js.define(engine, root, "mainRenderingSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "tui-main-rendering-original-6fb.json")));
    try js.define(engine, root, "nativeSummarizeMainWrites", try engine.checked(c.JS_NewCFunction(engine.context, summarize, "summarizeWrites", 1)));
    const result = engine.evalModule("import*as tui from'pi-tui';const TuiMainScreen=tui.TuiMainScreen,summarizeWrites=nativeSummarizeMainWrites;\n" ++ @embedFile("fixtures/tui-main-rendering-original-6fb.input.txt") ++
        "\nif(JSON.stringify(tuiMainRenderCases)!==JSON.stringify(mainRenderingSource.cases))throw Error(JSON.stringify({actual:tuiMainRenderCases,expected:mainRenderingSource.cases}));", "tui-main-rendering-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native TuiMainScreen render Source mismatch: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
