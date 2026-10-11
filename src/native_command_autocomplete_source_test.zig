const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const command = @import("extensions/native_command_autocomplete.zig");
const pure = @import("extensions/native_command_source_pure.zig");
const a = @import("extensions/native_tui_alt_frame.zig");
fn create(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    return command.create(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), c.pi_js_undefined()) catch |err| a.fail(engine, err);
}
const PureMethod = enum(c_int) { at, path, display };
fn pureCall(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    var frame: a.Frame = .{ .engine = engine, .object = receiver, .bindings = data[0] };
    defer frame.deinit();
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const value = (switch (@as(PureMethod, @enumFromInt(magic))) {
        .at => pure.prefix(&frame, args, true),
        .path => pure.prefix(&frame, args, false),
        .display => pure.scopedDisplay(&frame, args),
    }) catch |err| return a.fail(engine, err);
    return frame.result(value);
}
// Private fixture constructor only: tests selected original pure methods;
// neither exports nor claims the complete Combined class or any fd behavior.
fn construct(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const object = try command.create(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), c.pi_js_undefined());
    errdefer engine.freeValue(object);
    const bindings = try js.object(engine);
    defer engine.freeValue(bindings);
    try pure.initialize(engine, bindings);
    inline for (.{ .{ "extractAtPrefix", PureMethod.at, 1 }, .{ "extractPathPrefix", PureMethod.path, 1 }, .{ "scopedPathForDisplay", PureMethod.display, 2 } }) |entry| {
        var data = [_]c.JSValue{bindings};
        try js.define(engine, object, entry[0], try engine.checked(c.JS_NewCFunctionData2(engine.context, pureCall, entry[0], entry[2], @intFromEnum(entry[1]), 1, &data)));
    }
    return object;
}
fn setup(gpa: std.mem.Allocator) !*js.Engine {
    const engine = try js.Engine.init(gpa, .{ .memory_limit = 64 * 1024 * 1024 });
    errdefer engine.deinit();
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"command-source"});
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/native_tui.zig").install(engine);
    try engine.bindFunction("createCommandProvider", create, 1);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    try js.define(engine, root, "privateCommandFixture", try @import("extensions/native_class.zig").constructor(engine, "CommandSourceFixture", 0, prototype, construct, &.{}));
    return engine;
}
fn expected(engine: *js.Engine, name: [*:0]const u8, bytes: []const u8) !void {
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, name, try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, name)));
}
fn replay(engine: *js.Engine, bytes: []const u8, filename: [:0]const u8) !void {
    const result = engine.evalModule(bytes, filename) catch |err| {
        if (engine.last_error) |message| std.debug.print("Native command Source failure: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "Command Source original142 actual Root names fuzzy skill mapping argument callbacks getters identity and pure application" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try expected(engine, "commandOriginal", @embedFile("extensions/fixtures/main-command-autocomplete-source.json"));
    try replay(engine, "const rootCommands=commandOriginal.rootCoreMetadataNames.map(name=>({name}));\n" ++ @embedFile("extensions/fixtures/main-command-autocomplete-source.input.txt") ++
        "\nif(commandCases.length!==142)throw Error('command Source count');for(let index=0;index<commandCases.length;index++)if(JSON.stringify(commandCases[index])!==JSON.stringify(commandOriginal.cases[index]))throw Error(JSON.stringify({index,actual:commandCases[index],expected:commandOriginal.cases[index]}));if(JSON.stringify(commandMethodMetadata)!==JSON.stringify(commandOriginal.metadata))throw Error(JSON.stringify({actual:commandMethodMetadata,expected:commandOriginal.metadata}));", "command-original142.mjs");
}
test "Command Source original20 actual StdinBuffer Editor cold burst ready menu separate Tab and wrapper phases" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try expected(engine, "turnOriginal", @embedFile("extensions/fixtures/main-editor-autocomplete-turns-source.json"));
    try expected(engine, "turnMetadata", @embedFile("extensions/fixtures/main-editor-autocomplete-original-metadata.json"));
    try replay(engine, "import{Editor,StdinBuffer}from'pi-tui';const CombinedAutocompleteProvider=privateCommandFixture,upstreamCommands=turnMetadata.upstreamCommands,rootCommands=turnOriginal.rootCoreMetadataNames.map(name=>({name})),sourceFixtureDirectory='.';\n" ++ @embedFile("extensions/fixtures/main-editor-autocomplete-turns-source.input.txt") ++
        "\nif(turnCases.length!==20)throw Error('turn Source count');for(let index=0;index<turnCases.length;index++)if(JSON.stringify(turnCases[index])!==JSON.stringify(turnOriginal.cases[index]))throw Error(JSON.stringify({index,actual:turnCases[index],expected:turnOriginal.cases[index]}));", "command-original20-turns.mjs");
}
test "Command Source original97 pure Unicode prefixes ordinary iterators and scoped display" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try expected(engine, "pureOriginal", @embedFile("extensions/fixtures/tui-combined-prefix-original-ea.json"));
    try replay(engine, "const Combined=privateCommandFixture;\n" ++ @embedFile("extensions/fixtures/tui-combined-prefix-original-ea.input.txt") ++
        "\nif(tuiCombinedPrefixCases.length!==97)throw Error('prefix Source count');for(let index=0;index<tuiCombinedPrefixCases.length;index++)if(JSON.stringify(tuiCombinedPrefixCases[index])!==JSON.stringify(pureOriginal.cases[index]))throw Error(JSON.stringify({index,actual:tuiCombinedPrefixCases[index],expected:pureOriginal.cases[index]}));", "command-original97-prefixes.mjs");
}
test "Command Source original34 pure completion quotes UTF16 cursors callback chronology and original reasons" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try expected(engine, "pureOriginal", @embedFile("extensions/fixtures/tui-combined-completion-original-ea.json"));
    try replay(engine, "const Combined=privateCommandFixture;\n" ++ @embedFile("extensions/fixtures/tui-combined-completion-original-ea.input.txt") ++
        "\nif(tuiCombinedCompletionCases.length!==34)throw Error('completion Source count');for(let index=0;index<tuiCombinedCompletionCases.length;index++)if(JSON.stringify(tuiCombinedCompletionCases[index])!==JSON.stringify(pureOriginal.cases[index]))throw Error(JSON.stringify({index,actual:tuiCombinedCompletionCases[index],expected:pureOriginal.cases[index]}));", "command-original34-completion.mjs");
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try setup(gpa);
    defer engine.deinit();
    try expected(engine, "commandOriginal", @embedFile("extensions/fixtures/main-command-autocomplete-source.json"));
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule("const provider=createCommandProvider(commandOriginal.rootCoreMetadataNames.map(name=>({name})));for(const query of [\"/hel\",\"/model\"]){const original=commandOriginal.cases.find(row=>row.lines?.[0]===query);const result=await provider.getSuggestions(original.lines,original.row,original.col,{force:false});if(JSON.stringify(result)!==JSON.stringify(original.value))throw Error(JSON.stringify({query,result,expected:original.value}));}const original=commandOriginal.cases.find(row=>row.args?.[4]===\"/he\"),value=provider.applyCompletion(...original.args);if(JSON.stringify(value)!==JSON.stringify(original.value))throw Error(JSON.stringify({value,expected:original.value}));", "command-allocation-source.mjs") catch |err| {
        const actual = engine.nativeAllocationError(err, generation);
        if (actual != error.OutOfMemory) {
            std.debug.print("Command GPA unexpected {s} generation={d}->{d}\n", .{ @errorName(actual), generation, engine.native_allocation_generation });
            if (engine.last_error) |message| std.debug.print("Original exception: {s}\n", .{message});
            var known_failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
            const known = known_failing.allocator();
            if (gpa.vtable.alloc == known.vtable.alloc and gpa.vtable.free == known.vtable.free) {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                std.debug.print("Command GPA fail_index={d} current={d} induced={}\n", .{ failing.fail_index, failing.alloc_index, failing.has_induced_failure });
                if (failing.has_induced_failure) std.debug.print("Command original induced allocation stack:\n{f}\n", .{std.debug.FormatStackTrace{ .stack_trace = failing.getStackTrace() }});
            }
        }
        return actual;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "Command Source exhaustive host allocation cleanup in native command mapping await fuzzy and application" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
test "Command Source dynamic Main metadata holder retained across GC and fenced retirement" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const holder = try @import("extensions/native_autocomplete_registry.zig").holder(engine);
    defer engine.freeValue(holder);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "commandHolder", c.JS_DupValue(engine.context, holder));
    try js.define(engine, root, "retainedCommandProvider", try command.createForHolder(engine, holder, c.pi_js_undefined()));
    try replay(engine, "commandHolder.snapshot={mainAutocompleteCommands:[{name:'help'},{name:'changelog'}]};let result=await retainedCommandProvider.getSuggestions(['/hel'],0,4,{force:false});if(result.items[0].value!=='help')throw Error('initial holder');commandHolder.snapshot={mainAutocompleteCommands:[{name:'model'}]};result=await retainedCommandProvider.getSuggestions(['/mod'],0,4,{force:false});if(result.items[0].value!=='model')throw Error('updated holder');commandHolder.active=false;if(await retainedCommandProvider.getSuggestions(['/mod'],0,4,{force:false})!==null||retainedCommandProvider.applyCompletion(['/mod'],0,4,{value:'model',label:'model'},'/mod')!==null)throw Error('retired holder');", "command-holder-lifecycle.mjs");
}
