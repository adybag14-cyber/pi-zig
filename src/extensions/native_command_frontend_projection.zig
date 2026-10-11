//! Source InteractiveMode extension-command filter/map only. No Main activation
//! or full frontend factory claim. Caller supplies its real builtins and mode.
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const owners = @import("native_command_metadata_owner.zig");
const c = js.c;
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    return sdk.fail(engine, err);
}

pub fn extensionRows(engine: *js.Engine, resolved: c.JSValue, slash_commands: c.JSValue, mode: c.JSValue) !c.JSValue {
    const name_mapper = try engine.checked(c.JS_NewCFunction2(engine.context, commandName, "", 1, c.JS_CFUNC_generic, 0));
    defer engine.freeValue(name_mapper);
    const names = try js.invoke(engine, slash_commands, "map", &.{name_mapper});
    defer engine.freeValue(names);
    const builtin_names = try js.builtin(engine, "Set", &.{names});
    defer engine.freeValue(builtin_names);
    var filter_roots = [_]c.JSValue{builtin_names};
    const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, keepExtension, "", 1, 0, filter_roots.len, &filter_roots));
    defer engine.freeValue(predicate);
    const filtered = try js.invoke(engine, resolved, "filter", &.{predicate});
    defer engine.freeValue(filtered);
    var map_roots = [_]c.JSValue{mode};
    const mapper = try engine.checked(c.JS_NewCFunctionData2(engine.context, mapExtension, "", 1, 0, map_roots.len, &map_roots));
    defer engine.freeValue(mapper);
    return js.invoke(engine, filtered, "map", &.{mapper});
}
fn commandName(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return js.get(engine, if (argc > 0) args[0] else c.pi_js_undefined(), "name") catch |err| fail(engine, err);
}
fn keepExtension(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return filterValue(engine, if (argc > 0) args[0] else c.pi_js_undefined(), roots[0]) catch |err| fail(engine, err);
}
fn filterValue(engine: *js.Engine, command: c.JSValue, names: c.JSValue) !c.JSValue {
    // Resolve .has before cmd.name, as in builtinCommandNames.has(cmd.name).
    const has = try js.get(engine, names, "has");
    defer engine.freeValue(has);
    const name = try js.get(engine, command, "name");
    defer engine.freeValue(name);
    const found = try js.call(engine, has, names, &.{name});
    defer engine.freeValue(found);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_ToBool(engine.context, found) == 0));
}
fn mapExtension(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return mapValue(engine, if (argc > 0) args[0] else c.pi_js_undefined(), roots[0]) catch |err| fail(engine, err);
}
fn mapValue(engine: *js.Engine, command: c.JSValue, mode: c.JSValue) !c.JSValue {
    const metadata = try js.object(engine);
    defer engine.freeValue(metadata);
    try js.define(engine, metadata, "name", try js.get(engine, command, "invocationName"));
    // Keep the actual dynamic mode method lookup, receiver, and two arguments.
    const describe = try js.get(engine, mode, "prefixAutocompleteDescription");
    defer engine.freeValue(describe);
    const description = try js.get(engine, command, "description");
    defer engine.freeValue(description);
    const source_info = try js.get(engine, command, "sourceInfo");
    defer engine.freeValue(source_info);
    try js.define(engine, metadata, "description", try js.call(engine, describe, mode, &.{ description, source_info }));
    try js.define(engine, metadata, "getArgumentCompletions", try js.get(engine, command, "getArgumentCompletions"));
    // This private operation must retain the original registered callable in
    // its owner record. A guest-replaced public function must stay ordinary.
    return owners.copyRetainedMetadata(engine, command, metadata);
}
