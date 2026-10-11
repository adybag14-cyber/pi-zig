//! Source AgentSession._expandSkillCommand through native filesystem/YAML.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const v = @import("native_select_list.zig");
const frontmatter = @import("../coding_agent/frontmatter.zig");
const c = em.c;
extern "c" fn JS_GetToPrimitiveSymbol(context: ?*c.JSContext) c.JSValue;
fn call(engine: *em.Engine, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const function = try sdk.get(engine, receiver, name);
    defer engine.freeValue(function);
    return engine.checked(c.JS_Call(engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)));
}
fn addOne(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    const symbol = try engine.checked(JS_GetToPrimitiveSymbol(engine.context));
    defer engine.freeValue(symbol);
    return @import("native_tui_value_arithmetic.zig").add(engine, value, c.JS_NewInt32(engine.context, 1), symbol);
}
fn matches(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const name = sdk.get(engine, if (argc > 0) args[0] else c.pi_js_undefined(), "name") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(name);
    return c.pi_js_bool(context, @intFromBool(c.JS_IsStrictEqual(context, name, roots[0])));
}
pub fn expand(owner: *sdk.State, receiver: c.JSValue, input: c.JSValue) !c.JSValue {
    const engine = owner.engine;
    const prefix = try sdk.text(engine, "/skill:");
    defer engine.freeValue(prefix);
    const starts = try call(engine, input, "startsWith", &.{prefix});
    defer engine.freeValue(starts);
    if (c.JS_ToBool(engine.context, starts) != 1) return c.JS_DupValue(engine.context, input);
    const space = try sdk.text(engine, " ");
    defer engine.freeValue(space);
    const index = try call(engine, input, "indexOf", &.{space});
    defer engine.freeValue(index);
    const no_arguments = c.JS_IsStrictEqual(engine.context, index, c.JS_NewInt32(engine.context, -1));
    const name = if (no_arguments) try call(engine, input, "slice", &.{c.JS_NewInt32(engine.context, 7)}) else try call(engine, input, "slice", &.{ c.JS_NewInt32(engine.context, 7), index });
    defer engine.freeValue(name);
    const arguments = if (no_arguments) try sdk.text(engine, "") else argument_tail: {
        // Call-expression evaluation resolves slice before index + 1 can run
        // any user-authored ToPrimitive/valueOf hooks.
        const slice = try sdk.get(engine, input, "slice");
        defer engine.freeValue(slice);
        var parameters = [_]c.JSValue{try addOne(engine, index)};
        defer engine.freeValue(parameters[0]);
        const tail = try engine.checked(c.JS_Call(engine.context, slice, input, 1, &parameters));
        defer engine.freeValue(tail);
        break :argument_tail try call(engine, tail, "trim", &.{});
    };
    defer engine.freeValue(arguments);
    const loader = try sdk.get(engine, receiver, "resourceLoader");
    defer engine.freeValue(loader);
    const resources = try call(engine, loader, "getSkills", &.{});
    defer engine.freeValue(resources);
    const skills = try sdk.get(engine, resources, "skills");
    defer engine.freeValue(skills);
    const find = try sdk.get(engine, skills, "find");
    defer engine.freeValue(find);
    var roots = [_]c.JSValue{name};
    var parameters = [_]c.JSValue{try engine.checked(c.JS_NewCFunctionData2(engine.context, matches, "", 1, 0, roots.len, &roots))};
    defer engine.freeValue(parameters[0]);
    const skill = try engine.checked(c.JS_Call(engine.context, find, skills, 1, &parameters));
    defer engine.freeValue(skill);
    if (c.JS_ToBool(engine.context, skill) != 1) return c.JS_DupValue(engine.context, input);
    return expandKnown(owner, skill, arguments) catch |err| {
        try emitError(owner, skill, err);
        return c.JS_DupValue(engine.context, input);
    };
}
fn expandKnown(owner: *sdk.State, skill: c.JSValue, arguments: c.JSValue) !c.JSValue {
    const engine = owner.engine;
    const path = try sdk.get(engine, skill, "filePath");
    defer engine.freeValue(path);
    const content = try @import("node_fs.zig").readUtf8(engine, path);
    defer engine.freeValue(content);
    const bytes = try engine.toString(content);
    defer engine.gpa.free(bytes);
    var parsed = try frontmatter.parse(engine.gpa, bytes);
    defer parsed.deinit();
    if (parsed.frontmatter.diagnostic) |diagnostic| return throwYaml(engine, parsed.yaml_source orelse "", diagnostic);
    const body = try sdk.text(engine, frontmatter.trim(parsed.body));
    defer engine.freeValue(body);
    // Each getter and conversion follows its template-literal position.
    const name = try sdk.get(engine, skill, "name");
    defer engine.freeValue(name);
    const heading = try concatenate(engine, "<skill name=\"", name, "\" location=\"");
    defer engine.freeValue(heading);
    const location = try sdk.get(engine, skill, "filePath");
    defer engine.freeValue(location);
    const located = try concatenateValue(engine, heading, location, "\">\nReferences are relative to ");
    defer engine.freeValue(located);
    const directory = try sdk.get(engine, skill, "baseDir");
    defer engine.freeValue(directory);
    const reference = try concatenateValue(engine, located, directory, ".\n\n");
    defer engine.freeValue(reference);
    const block = try concatenateValue(engine, reference, body, "\n</skill>");
    if (c.JS_ToBool(engine.context, arguments) != 1) return block;
    defer engine.freeValue(block);
    const separator = try sdk.text(engine, "\n\n");
    defer engine.freeValue(separator);
    return v.concat(engine, &.{ block, separator, arguments });
}
fn concatenate(engine: *em.Engine, before: []const u8, value: c.JSValue, after: []const u8) !c.JSValue {
    const first = try sdk.text(engine, before);
    defer engine.freeValue(first);
    return concatenateValue(engine, first, value, after);
}
fn concatenateValue(engine: *em.Engine, before: c.JSValue, value: c.JSValue, after: []const u8) !c.JSValue {
    const tail = try sdk.text(engine, after);
    defer engine.freeValue(tail);
    return v.concat(engine, &.{ before, value, tail });
}
fn throwYaml(engine: *em.Engine, source: []const u8, diagnostic: frontmatter.yaml.Diagnostic) anyerror {
    const message = frontmatter.prettyUnits(engine.gpa, source, diagnostic) catch |err| return err;
    defer engine.gpa.free(message);
    const reason = engine.checked(c.JS_NewError(engine.context)) catch |err| return err;
    sdk.put(engine, reason, "name", sdk.text(engine, diagnostic.name) catch |err| {
        engine.freeValue(reason);
        return err;
    }) catch |err| {
        engine.freeValue(reason);
        return err;
    };
    sdk.put(engine, reason, "message", @import("native_utf16.zig").string(engine, message) catch |err| {
        engine.freeValue(reason);
        return err;
    }) catch |err| {
        engine.freeValue(reason);
        return err;
    };
    if (diagnostic.code) |code| sdk.put(engine, reason, "code", sdk.text(engine, code) catch |err| {
        engine.freeValue(reason);
        return err;
    }) catch |err| {
        engine.freeValue(reason);
        return err;
    };
    _ = c.JS_Throw(engine.context, reason);
    return js.capture(engine);
}
fn emitError(owner: *sdk.State, skill: c.JSValue, failure: anyerror) !void {
    const engine = owner.engine;
    _ = sdk.fail(engine, failure);
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    const event = try sdk.object(engine);
    defer engine.freeValue(event);
    try sdk.put(engine, event, "extensionPath", try sdk.get(engine, skill, "filePath"));
    try sdk.put(engine, event, "event", try sdk.text(engine, "skill_expansion"));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, "Error");
    defer engine.freeValue(constructor);
    const is_error = c.JS_IsInstanceOf(engine.context, reason, constructor);
    if (is_error < 0) return js.capture(engine);
    const message = if (is_error == 1) try sdk.get(engine, reason, "message") else converted: {
        // Source calls the ambient String identifier in this branch. It may
        // have been replaced independently of primitive ToString semantics.
        const stringify = try sdk.get(engine, global, "String");
        defer engine.freeValue(stringify);
        var argument = [_]c.JSValue{reason};
        break :converted try engine.checked(c.JS_Call(engine.context, stringify, c.pi_js_undefined(), 1, &argument));
    };
    try sdk.put(engine, event, "error", message);
    const callback = try sdk.get(engine, owner.data, "extension_onError");
    defer engine.freeValue(callback);
    if (c.JS_IsUndefined(callback) or c.JS_IsNull(callback)) return;
    var parameters = [_]c.JSValue{event};
    const ignored = try engine.checked(c.JS_Call(engine.context, callback, c.pi_js_undefined(), 1, &parameters));
    engine.freeValue(ignored);
}
