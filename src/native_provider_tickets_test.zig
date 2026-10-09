const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const group_mod = @import("extensions/native_group.zig");
const tickets_mod = @import("extensions/native_provider_tickets.zig");
const json = @import("mcp/protocol.zig").json;
const c = engine_mod.c;
test "native provider tickets admit four callbacks before completion and isolate snapshots actions timers and one abort" {
    const gpa = std.testing.allocator;
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const binding = try group.add("ticket-fixture.js");
    try binding.loadFactory(source, "ticket-fixture.js");
    const manifest = try binding.manifestJson("ticket-fixture.js");
    defer gpa.free(manifest);
    var definition = try std.json.parseFromSlice(std.json.Value, gpa, manifest, .{});
    defer definition.deinit();
    const config = definition.value.object.get("providers").?.array.items[0].object.get("config").?;
    const descriptor = try @import("extensions/provider_method_ref.zig").ProviderMethodRef.fromJson(config.object.get("classify").?);
    var manager: tickets_mod.Manager = .{ .engine = engine, .io = std.testing.io };
    defer manager.deinit();
    const pending = try engine.checked(c.JS_NewArray(engine.context));
    defer engine.freeValue(pending);
    for (0..4) |index| {
        const id = try std.fmt.allocPrint(gpa, "{d}", .{index + 1});
        defer gpa.free(id);
        const input = try std.json.Stringify.valueAlloc(gpa, .{ .kind = "provider_typed_begin", .callbackId = descriptor.callback_id, .providerName = "ticket", .callbackGeneration = descriptor.generation, .operation = "classify", .model = .{ .id = "same", .provider = "ticket", .api = "fixture" }, .modelContext = .{ .state = .{ .id = index + 1 }, .questions = .{} }, .options = .{}, .context = .{ .nativeRuntimeBound = true, .settings = .{ .marker = if (index % 2 == 0) "A" else "B" }, .sessionName = id } }, .{});
        defer gpa.free(input);
        var request = try std.json.parseFromSlice(std.json.Value, gpa, input, .{});
        defer request.deinit();
        try manager.begin(binding, id, request.value.object);
        const ticket = manager.find(id).?;
        if (c.JS_SetPropertyUint32(engine.context, pending, @intCast(index), c.JS_DupValue(engine.context, ticket.pending)) < 0) return error.JavaScriptException;
    }
    const started = try engine.eval("globalThis.started", "tickets-started.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(started);
    var count: i64 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt64(engine.context, &count, started));
    try std.testing.expectEqual(@as(i64, 4), count);
    try manager.find("2").?.abort();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "ticketPromises", c.JS_DupValue(engine.context, pending)) < 0) return error.JavaScriptException;
    const all = try engine.eval("Promise.allSettled(ticketPromises)", "tickets-settle.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(all);
    const settled = try engine.awaitValue(all);
    defer engine.freeValue(settled);
    try manager.pump();
    for (manager.tickets.items, 0..) |ticket, index| {
        try std.testing.expect(ticket.failure == null);
        var result = try json.Owned.parse(gpa, ticket.result orelse return error.TicketDidNotSettle);
        defer result.deinit();
        const value = result.value.object.get("value").?;
        if (index == 1) {
            try std.testing.expectEqualStrings("aborted", value.object.get("stopReason").?.string);
            continue;
        }
        try std.testing.expectEqualStrings(if (index % 2 == 0) "A" else "B", value.object.get("marker").?.string);
        try std.testing.expect(value.object.get("canonical").?.bool and value.object.get("receiver").?.bool);
        try std.testing.expectEqual(@as(f64, @floatFromInt(index + 1)), try json.asNumber(value.object.get("id").?));
        const action = result.value.object.get("actionQueue").?.array.items[0];
        try std.testing.expectEqualStrings(ticket.id, action.object.get("name").?.string);
    }
    const aborts = try engine.eval("globalThis.aborts", "tickets-aborts.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(aborts);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt64(engine.context, &count, aborts));
    try std.testing.expectEqual(@as(i64, 1), count);
}
const source =
    \\globalThis.started=0;globalThis.aborts=0;globalThis.barrier=[];
    \\export default pi=>{
    \\const model={id:'same',provider:'ticket',type:'classifier',api:'fixture',baseUrl:'https://fixture.invalid'};
    \\const provider={id:'ticket',getModels(){return [model]},getAllModels(){return [model]},async classify(selected,context,{signal}){
    \\const marker=pi.getSettings().marker;const id=context.state.id;
    \\await new Promise(resolve=>{barrier.push(resolve);started++;if(started===4)for(const release of barrier)release()});
    \\await new Promise((resolve,reject)=>{if(signal.aborted){aborts++;reject(Error('aborted'));return}signal.addEventListener('abort',()=>{aborts++;reject(Error('aborted'))},{once:true});setTimeout(resolve,10)});
    \\await Promise.resolve();if(pi.getSettings().marker!==marker)throw Error('snapshot changed');pi.setSessionName(String(id));
    \\return {stopReason:'stop',id,marker,canonical:selected===model,receiver:this===provider};
    \\}};pi.registerProvider(provider)};
;
