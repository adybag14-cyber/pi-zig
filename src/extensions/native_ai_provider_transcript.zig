//! Actual provider-facing transcript resolution and addition-only tool routing.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn resolve(engine: *v.em.Engine, context: c.JSValue, mid_system: bool) !c.JSValue {
    if (mid_system) return c.JS_DupValue(engine.context, context);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const messages = try scope.get(context, "messages");
    const head = try scope.own(try @import("native_sdk_transcript_replay.zig").currentSystemMessage(engine, messages));
    const conversation = try scope.own(try @import("native_sdk_transcript_replay.zig").conversation(engine, messages));
    const output = try scope.object();
    try scope.put(output, "messages", if (scope.truthy(head)) try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(engine, conversation, head)) else conversation);
    return c.JS_DupValue(engine.context, output);
}
pub fn declared(engine: *v.em.Engine, messages: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const definitions = try scope.own(try v.js.builtin(engine, "Map", &.{}));
    var rows = try v.iterator(&scope, messages);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |message| {
        defer engine.freeValue(message);
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        if (!try v.eq(&row, try row.get(message, "role"), "system")) continue;
        const added = try row.get(message, "toolsAdded");
        var tools = try v.iterator(&row, if (v.nullish(added)) try row.array() else added);
        defer tools.deinit();
        errdefer tools.closePreserving();
        while (try tools.next()) |tool| {
            defer engine.freeValue(tool);
            const setter = try row.get(definitions, "set");
            _ = try row.call(setter, definitions, &.{ try row.get(tool, "name"), tool });
        }
    }
    const values = try scope.invoke(definitions, "values", &.{});
    return @import("native_sdk_transcript_replay.zig").arraySpread(engine, values, null);
}
pub fn tools(engine: *v.em.Engine, messages: c.JSValue, supports_additions: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var anchors = supports_additions;
    if (anchors) {
        const names = try scope.own(try v.js.builtin(engine, "Set", &.{}));
        var rows = try v.iterator(&scope, messages);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |message| {
            defer engine.freeValue(message);
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            if (!try v.eq(&row, try row.get(message, "role"), "system")) continue;
            const removed = try row.get(message, "toolsRemoved");
            if (!v.nullish(removed) and try @import("native_image_arithmetic.zig").compare(engine, .greater, try row.get(removed, "length"), c.JS_NewInt32(engine.context, 0))) {
                anchors = false;
                break;
            }
            const added = try row.get(message, "toolsAdded");
            var changes = try v.iterator(&row, if (v.nullish(added)) try row.array() else added);
            defer changes.deinit();
            errdefer changes.closePreserving();
            while (try changes.next()) |tool| {
                defer engine.freeValue(tool);
                if (row.truthy(try row.invoke(names, "has", &.{try row.get(tool, "name")}))) {
                    anchors = false;
                    break;
                }
                _ = try row.invoke(names, "add", &.{try row.get(tool, "name")});
            }
            if (!anchors) break;
        }
    }
    const result = try scope.object();
    var request = c.pi_js_undefined();
    if (anchors) {
        const first = try v.at(&scope, messages, 0);
        if (scope.truthy(first) and try v.eq(&scope, try scope.get(first, "role"), "system")) request = try scope.get(first, "toolsAdded");
        if (v.nullish(request)) request = try scope.array();
    } else request = try scope.own(try @import("native_agent_tool_changes.zig").currentTools(engine, messages));
    try scope.put(result, "requestTools", request);
    try scope.put(result, "anchorsAdditions", c.pi_js_bool(engine.context, @intFromBool(anchors)));
    return c.JS_DupValue(engine.context, result);
}
