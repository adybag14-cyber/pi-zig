//! The actual SDK runtime incarnation owns the exposed command Maps.
const sdk = @import("native_sdk.zig");
const em = @import("engine.zig");
pub fn resolve(owner: *sdk.State) !em.c.JSValue {
    const runner = try sdk.get(owner.engine, owner.data, "_sdkCommandRunner");
    defer owner.engine.freeValue(runner);
    return @import("native_js_values.zig").invoke(owner.engine, runner, "getRegisteredCommands", &.{});
}
pub fn getCommand(owner: *sdk.State, name: em.c.JSValue) !em.c.JSValue {
    const runner = try sdk.get(owner.engine, owner.data, "_sdkCommandRunner");
    defer owner.engine.freeValue(runner);
    return @import("native_js_values.zig").invoke(owner.engine, runner, "getCommand", &.{name});
}
pub fn catalog(owner: *sdk.State) !em.c.JSValue {
    const engine = owner.engine;
    const commands = try resolve(owner);
    defer engine.freeValue(commands);
    const mapper = try engine.checked(em.c.JS_NewCFunction(engine.context, projectCatalog, "", 1));
    defer engine.freeValue(mapper);
    const result = try sdk.invoke(engine, commands, "map", &.{mapper});
    errdefer engine.freeValue(result);
    const session = try sdk.sessionDataSessionValue(engine, owner.data);
    defer engine.freeValue(session);
    const prompts = try sdk.get(engine, session, "promptTemplates");
    defer engine.freeValue(prompts);
    try appendResources(engine, result, prompts, false);
    const loader = try sdk.get(engine, owner.data, "resourceLoader");
    defer engine.freeValue(loader);
    const found = try sdk.invoke(engine, loader, "getSkills", &.{});
    defer engine.freeValue(found);
    const skills = try sdk.get(engine, found, "skills");
    defer engine.freeValue(skills);
    try appendResources(engine, result, skills, true);
    return result;
}
fn projectCatalog(context: ?*em.c.JSContext, _: em.c.JSValue, argc: c_int, argv: [*c]em.c.JSValue) callconv(.c) em.c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return project(engine, if (argc > 0) argv[0] else em.c.pi_js_undefined(), "invocationName", "extension", false) catch |err| sdk.fail(engine, err);
}
fn project(engine: *em.Engine, row: em.c.JSValue, name: [*:0]const u8, source: []const u8, skill: bool) !em.c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    const raw = try sdk.get(engine, row, name);
    defer engine.freeValue(raw);
    try sdk.put(engine, result, "name", if (skill) prefixed: {
        const prefix = try sdk.text(engine, "skill:");
        defer engine.freeValue(prefix);
        break :prefixed try @import("native_select_list.zig").concat(engine, &.{ prefix, raw });
    } else em.c.JS_DupValue(engine.context, raw));
    try sdk.put(engine, result, "description", try sdk.get(engine, row, "description"));
    try sdk.put(engine, result, "source", try sdk.text(engine, source));
    try sdk.put(engine, result, "sourceInfo", try sdk.get(engine, row, "sourceInfo"));
    return result;
}
fn appendResources(engine: *em.Engine, result: em.c.JSValue, rows: em.c.JSValue, skill: bool) !void {
    for (0..try sdk.length(engine, rows)) |index| {
        const row = try engine.checked(em.c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const item = try project(engine, row, "name", if (skill) "skill" else "prompt", skill);
        defer engine.freeValue(item);
        const ignored = try sdk.invoke(engine, result, "push", &.{item});
        engine.freeValue(ignored);
    }
}
