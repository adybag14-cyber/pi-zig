//! Real loopback RFC6455 wire proof, separate from provider/cleanup parity.
const std = @import("std");
const raw = @import("extensions/native_ai_codex_socket_worker.zig");
const fixture = @import("test_support/codex_socket_peer.zig");
const em = @import("extensions/engine.zig");
const v = @import("extensions/native_ai_provider_values.zig");
const Scope = v.Scope;
const c = em.c;
const owner = @import("extensions/native_ai_codex_socket.zig");
fn object(value: std.json.Value, key: []const u8) std.json.Value {
    return value.object.get(key).?;
}
fn stringify(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    return std.json.Stringify.valueAlloc(gpa, value, .{});
}
const Notice = struct {
    io: std.Io,
    event: std.Io.Event = .unset,
    fn notify(context: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.event.set(self.io);
    }
};
fn next(worker: *raw.Worker, notice: *Notice) !raw.Event {
    while (true) {
        if (worker.pop()) |event| return event;
        if (worker.finished.load(.acquire)) return worker.failure orelse error.SourceSocketEndedEarly;
        try notice.event.waitTimeout(notice.io, .{ .duration = .{ .raw = .fromSeconds(2), .clock = .awake } });
        notice.event.reset();
    }
}
test "native Codex socket replays genuine captured Source path headers and two cached request frames over real loopback" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Genuine completed protocol output retains sourceLifecycleQualified=false.
    // This test makes no provider-factory or Source-cleanup qualification.
    const source = try std.json.parseFromSlice(std.json.Value, a, @embedFile("extensions/fixtures/ai-codex-socket10-5ab.protocol.json"), .{});
    try std.testing.expectEqualStrings("5ab7fe74c400097b386662205cd93900695b8a71", object(source.value, "sourceHead").string);
    try std.testing.expect(object(source.value, "protocolSourceCompleted").bool);
    try std.testing.expect(!object(source.value, "sourceLifecycleQualified").bool);
    const row = object(source.value, "rows").array.items[0];
    const connection = object(row, "connections").array.items[0];
    try std.testing.expectEqualStrings("cached-continuation", object(row, "name").string);
    const original_url = try std.Uri.parse(object(connection, "url").string);
    const path = switch (original_url.path) {
        .raw, .percent_encoded => |value| value,
    };
    const route = if (original_url.query) |query| try std.fmt.allocPrint(a, "{s}?{s}", .{ path, switch (query) {
        .raw, .percent_encoded => |value| value,
    } }) else path;
    var headers: std.ArrayList(std.http.Header) = .empty;
    var header_iterator = object(connection, "headers").object.iterator();
    while (header_iterator.next()) |entry| try headers.append(a, .{ .name = entry.key_ptr.*, .value = entry.value_ptr.string });
    const sends = object(connection, "sends").array.items;
    const observations = object(row, "turns").array.items;
    try std.testing.expectEqual(@as(usize, 2), sends.len);
    var turns = try a.alloc(fixture.Turn, sends.len);
    for (sends, observations, 0..) |send, observed, index| {
        var replies: std.ArrayList([]const u8) = .empty;
        for (object(observed, "trace").array.items) |trace| {
            if (!std.mem.eql(u8, trace.array.items[0].string, "provider-enter")) continue;
            try replies.append(a, try stringify(a, trace.array.items[3]));
        }
        turns[index] = .{ .request = try stringify(a, send), .replies = try replies.toOwnedSlice(a) };
    }
    const server = try fixture.Peer.init(std.testing.allocator, std.testing.io, route, headers.items, turns);
    defer server.deinit();
    const rebound_url = try server.url(a); // Only the origin is rebound.
    var notice: Notice = .{ .io = std.testing.io };
    const worker = try raw.Worker.create(std.testing.io, .{ .url = rebound_url, .headers = headers.items, .connect_timeout_ms = 1000 }, &notice, Notice.notify);
    defer worker.destroy();
    const opened = try next(worker, &notice);
    defer opened.deinit();
    try std.testing.expect(opened == .connected);
    for (turns) |turn| {
        try worker.send(turn.request);
        const sent = try next(worker, &notice);
        defer sent.deinit();
        try std.testing.expect(sent == .sent);
        for (turn.replies) |expected| {
            try worker.read(1000);
            const response = try next(worker, &notice);
            defer response.deinit();
            try std.testing.expect(response == .message);
            try std.testing.expectEqualStrings(expected, response.message);
        }
    }
    try server.finish();
}

fn installOwnerFixture(engine: *em.Engine, url: []const u8, headers: std.json.Value, turns: []const fixture.Turn, comptime acquire_name: [:0]const u8) !void {
    engine.native_io = std.testing.io;
    if (engine.host_scheduler == null) try @import("extensions/timers.zig").install(engine, std.testing.io);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const encoded = try stringify(engine.gpa, headers);
    defer engine.gpa.free(encoded);
    const terminated = try engine.gpa.dupeZ(u8, encoded);
    defer engine.gpa.free(terminated);
    const values = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, terminated.len, "source-socket-headers.json")));
    const Adapter = struct {
        fn acquire(host: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            const address = try host.toString(roots[0]);
            defer host.gpa.free(address);
            var fields: std.ArrayList(std.http.Header) = .empty;
            defer {
                for (fields.items) |field| {
                    host.gpa.free(field.name);
                    host.gpa.free(field.value);
                }
                fields.deinit(host.gpa);
            }
            var entries = try v.iterator(&row, try row.invoke(try row.global("Object"), "entries", &.{roots[1]}));
            defer entries.deinit();
            errdefer entries.closePreserving();
            while (try entries.next()) |entry| {
                defer host.freeValue(entry);
                const name = try host.toString(try v.at(&row, entry, 0));
                errdefer host.gpa.free(name);
                const value = try host.toString(try v.at(&row, entry, 1));
                errdefer host.gpa.free(value);
                try fields.append(host.gpa, .{ .name = name, .value = value });
            }
            return owner.acquire(host, .{ .url = address, .headers = fields.items, .connect_timeout_ms = 1000 }, roots[2], roots[3], c.pi_js_undefined(), c.JS_NewInt32(host.context, 1000));
        }
        fn close(host: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            try owner.closeSession(host, roots[0]);
            return c.pi_js_undefined();
        }
    };
    const session = try scope.text("owned-native-session");
    try scope.put(global, acquire_name, try scope.own(try @import("extensions/native_node_function.zig").create(engine, acquire_name, 0, Adapter.acquire, &.{ try scope.text(url), values, session, try scope.text("fake-account") })));
    try scope.put(global, "closeOwnedSocketSession", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "closeOwnedSocketSession", 0, Adapter.close, &.{session})));
    const array = try scope.array();
    const counts = try scope.array();
    for (turns, 0..) |turn, index| {
        try scope.index(array, @intCast(index), try scope.text(turn.request));
        try scope.index(counts, @intCast(index), c.JS_NewUint32(engine.context, @intCast(turn.replies.len)));
    }
    try scope.put(global, "sourceSocketFrames", array);
    try scope.put(global, "sourceSocketReplyCounts", counts);
}

test "native Codex socket owner reuses the real connection retains guest metadata and closes owned state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.json.parseFromSlice(std.json.Value, a, @embedFile("extensions/fixtures/ai-codex-socket10-5ab.protocol.json"), .{});
    const row = object(source.value, "rows").array.items[0];
    const connection = object(row, "connections").array.items[0];
    const original = try std.Uri.parse(object(connection, "url").string);
    const path = switch (original.path) {
        .raw, .percent_encoded => |value| value,
    };
    const route = if (original.query) |query| try std.fmt.allocPrint(a, "{s}?{s}", .{ path, switch (query) {
        .raw, .percent_encoded => |value| value,
    } }) else path;
    var headers: std.ArrayList(std.http.Header) = .empty;
    var fields = object(connection, "headers").object.iterator();
    while (fields.next()) |entry| try headers.append(a, .{ .name = entry.key_ptr.*, .value = entry.value_ptr.string });
    const sends = object(connection, "sends").array.items;
    const observations = object(row, "turns").array.items;
    var turns = try a.alloc(fixture.Turn, sends.len);
    var frames = try a.alloc([]const u8, sends.len);
    for (sends, observations, 0..) |send, observed, index| {
        var replies: std.ArrayList([]const u8) = .empty;
        for (object(observed, "trace").array.items) |trace| if (std.mem.eql(u8, trace.array.items[0].string, "provider-enter")) {
            try replies.append(a, try stringify(a, trace.array.items[3]));
        };
        frames[index] = try stringify(a, send);
        turns[index] = .{ .request = frames[index], .replies = try replies.toOwnedSlice(a) };
    }
    const peer = try fixture.Peer.init(std.testing.allocator, std.testing.io, route, headers.items, turns);
    defer peer.deinit();
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try installOwnerFixture(engine, try peer.url(a), object(connection, "headers"), turns, "acquireOwnedSocket");
    const result = engine.evalModule(
        \\const first=acquireOwnedSocket();await first.ready;if(first.reused||!first.cached)throw Error('first acquisition');await first.send(sourceSocketFrames[0]);for(let i=0;i<sourceSocketReplyCounts[0];i++){const event=await first.events.next();if(event.done||!JSON.parse(event.value).type)throw Error('real first message')};first.release(true);const next=acquireOwnedSocket();await next.ready;if(!next.reused||next.meta!==first.meta)throw Error('retained connection metadata');await next.send(sourceSocketFrames[1]);for(let i=0;i<sourceSocketReplyCounts[1];i++){const event=await next.events.next();if(event.done||!JSON.parse(event.value).type)throw Error('real second message')};next.release(true);closeOwnedSocketSession();export const proof=true;
    , "native-owned-codex-pool-loopback.mjs") catch |err| {
        std.debug.print("Codex owner loopback: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    try std.testing.expect(!owner.pending(engine));
    try peer.finish();
}

test "native Codex socket session cleanup disconnects both busy cached and uncached owned connections" {
    try checkConcurrentCleanup(false);
}
test "native Codex socket publishes simultaneous initial cache entries after connect and retains both for cleanup" {
    try checkConcurrentCleanup(true);
}
fn checkConcurrentCleanup(comptime simultaneous: bool) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.json.parseFromSlice(std.json.Value, a, @embedFile("extensions/fixtures/ai-codex-socket10-5ab.protocol.json"), .{});
    const rows = object(source.value, "rows").array.items;
    var captured: ?std.json.Value = null;
    for (rows) |row| if (std.mem.eql(u8, object(row, "name").string, "busy-session")) {
        captured = row;
        break;
    };
    const connections = object(captured orelse return error.MissingSourceBusySession, "connections").array.items;
    try std.testing.expectEqual(@as(usize, 2), connections.len);
    const original = try std.Uri.parse(object(connections[0], "url").string);
    const path = switch (original.path) {
        .raw, .percent_encoded => |value| value,
    };
    const route = if (original.query) |query| try std.fmt.allocPrint(a, "{s}?{s}", .{ path, switch (query) {
        .raw, .percent_encoded => |value| value,
    } }) else path;
    var headers: std.ArrayList(std.http.Header) = .empty;
    var fields = object(connections[0], "headers").object.iterator();
    while (fields.next()) |entry| try headers.append(a, .{ .name = entry.key_ptr.*, .value = entry.value_ptr.string });
    const first = try fixture.Peer.initDisconnect(std.testing.allocator, std.testing.io, route, headers.items);
    defer first.deinit();
    const second = try fixture.Peer.initDisconnect(std.testing.allocator, std.testing.io, route, headers.items);
    defer second.deinit();
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try installOwnerFixture(engine, try first.url(a), object(connections[0], "headers"), &.{}, "acquireOwnedSocket");
    try installOwnerFixture(engine, try second.url(a), object(connections[0], "headers"), &.{}, "acquireConcurrentOwnedSocket");
    const script = if (simultaneous)
        \\const first=acquireOwnedSocket();const second=acquireConcurrentOwnedSocket();await Promise.all([first.ready,second.ready]);if(!first.cached||!second.cached||first.reused||second.reused)throw Error('initial concurrent ownership');closeOwnedSocketSession();export const proof=true;
    else
        \\const first=acquireOwnedSocket();await first.ready;const second=acquireConcurrentOwnedSocket();await second.ready;if(!first.cached||second.cached||first.reused||second.reused)throw Error('busy ownership');closeOwnedSocketSession();export const proof=true;
    ;
    const result = engine.evalModule(script, "native-owned-codex-concurrent-cleanup.mjs") catch |err| {
        std.debug.print("Codex concurrent cleanup: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    // Join the canceled workers before verifying EOF at both independent peers.
    // This explicitly improves the Source overwritten-cache-entry leak.
    owner.deinit(engine);
    try std.testing.expect(engine.native_ai_codex_socket_state == null);
    try first.finish();
    try second.finish();
}
