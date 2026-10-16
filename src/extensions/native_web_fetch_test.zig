//! Complete unchanged genuine Fetch39 rows over an actual Zig loopback peer.
//! Peer gate getters read real socket-task state; all responses/streams are the
//! native product classes. No HTTP/Response fixture object replaces fetch.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const c = em.c;
const Gate = struct {
    sent: std.atomic.Value(bool) = .init(false),
    seen: std.atomic.Value(bool) = .init(false),
    finished: std.atomic.Value(bool) = .init(false),
    release: std.Io.Event = .unset,
};
const Peer = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    listener: std.Io.net.Server,
    future: ?std.Io.Future(anyerror!void) = null,
    group: std.Io.Group = .init,
    gates: [4]Gate = .{ .{}, .{}, .{}, .{} },
    failures: std.atomic.Value(usize) = .init(0),
    requests: std.atomic.Value(usize) = .init(0),
    fn init(gpa: std.mem.Allocator, io: std.Io) !*Peer {
        const self = try gpa.create(Peer);
        errdefer gpa.destroy(self);
        self.* = .{ .io = io, .gpa = gpa, .listener = try (try std.Io.net.IpAddress.parseLiteral("127.0.0.1:0")).listen(io, .{ .reuse_address = true }) };
        errdefer self.listener.deinit(io);
        self.future = try io.concurrent(serve, .{self});
        return self;
    }
    fn deinit(self: *Peer) void {
        for (&self.gates) |*gate| gate.release.set(self.io);
        if (self.future) |*future| future.cancel(self.io) catch {};
        self.group.cancel(self.io);
        self.listener.deinit(self.io);
        self.gpa.destroy(self);
    }
    fn serve(self: *Peer) anyerror!void {
        while (true) {
            const connection = try self.listener.accept(self.io);
            self.group.concurrent(self.io, connectionTask, .{ self, connection }) catch |err| {
                connection.close(self.io);
                return err;
            };
        }
    }
    fn connectionTask(self: *Peer, connection: std.Io.net.Stream) std.Io.Cancelable!void {
        defer connection.close(self.io);
        self.handleConnection(connection) catch |err| {
            if (err == error.Canceled) return error.Canceled;
            _ = self.failures.fetchAdd(1, .monotonic);
            std.debug.print("Fetch39 peer error: {s}\n", .{@errorName(err)});
        };
    }
    fn header(request: *std.http.Server.Request, name: []const u8) ?[]const u8 {
        var headers = request.iterateHeaders();
        while (headers.next()) |item| if (std.ascii.eqlIgnoreCase(item.name, name)) return item.value;
        return null;
    }
    const Echo = struct {
        method: []const u8,
        path: []const u8,
        authorization: ?[]const u8,
        custom: ?[]const u8,
        content_type: ?[]const u8,
        bytes: []const u8,
        pub fn jsonStringify(self: Echo, out: anytype) !void {
            try out.beginObject();
            try out.objectField("method");
            try out.write(self.method);
            try out.objectField("path");
            try out.write(self.path);
            if (self.authorization) |value| {
                try out.objectField("authorization");
                try out.write(value);
            }
            if (self.custom) |value| {
                try out.objectField("custom");
                try out.write(value);
            }
            if (self.content_type) |value| {
                try out.objectField("contentType");
                try out.write(if (std.mem.startsWith(u8, value, "multipart/form-data; boundary=")) "multipart/form-data" else value);
            }
            try out.objectField("bytes");
            try out.beginArray();
            for (self.bytes) |byte| try out.write(byte);
            try out.endArray();
            try out.endObject();
        }
    };
    fn handleConnection(self: *Peer, stream: std.Io.net.Stream) anyerror!void {
        var input: [16 * 1024]u8 = undefined;
        var output: [4096]u8 = undefined;
        var reader = stream.reader(self.io, &input);
        var writer = stream.writer(self.io, &output);
        var server = std.http.Server.init(&reader.interface, &writer.interface);
        var request = try server.receiveHead();
        // The body reader may refill its storage; retain the actual head data
        // before reading payload bytes rather than holding borrowed slices.
        const target = try self.gpa.dupe(u8, request.head.target);
        defer self.gpa.free(target);
        const authorization = if (header(&request, "authorization")) |value| try self.gpa.dupe(u8, value) else null;
        defer if (authorization) |value| self.gpa.free(value);
        const custom = if (header(&request, "x-custom")) |value| try self.gpa.dupe(u8, value) else null;
        defer if (custom) |value| self.gpa.free(value);
        const content_type = if (header(&request, "content-type")) |value| try self.gpa.dupe(u8, value) else null;
        defer if (content_type) |value| self.gpa.free(value);
        const bytes = try request.readerExpectNone(&.{}).allocRemaining(self.gpa, .limited(4 * 1024 * 1024));
        defer self.gpa.free(bytes);
        _ = self.requests.fetchAdd(1, .monotonic);
        if (std.mem.startsWith(u8, target, "/echo")) {
            const payload = try std.json.Stringify.valueAlloc(self.gpa, Echo{ .method = @tagName(request.head.method), .path = target, .authorization = authorization, .custom = custom, .content_type = content_type, .bytes = bytes }, .{});
            defer self.gpa.free(payload);
            return request.respond(payload, .{ .keep_alive = false, .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }} });
        }
        if (std.mem.eql(u8, target, "/json")) return request.respond("{\"native\":true,\"text\":\"é😀\"}", .{ .keep_alive = false, .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }} });
        if (std.mem.eql(u8, target, "/binary")) return request.respond(&.{ 0, 65, 128, 255, 13, 10 }, .{ .keep_alive = false, .extra_headers = &.{.{ .name = "Content-Type", .value = "application/octet-stream" }} });
        if (std.mem.eql(u8, target, "/error")) return request.respond("{\"error\":{\"type\":\"permission\",\"message\":\"denied\"}}", .{ .status = .forbidden, .keep_alive = false, .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }} });
        if (std.mem.eql(u8, target, "/cookies")) return request.respond("cookies", .{ .keep_alive = false, .extra_headers = &.{ .{ .name = "Set-Cookie", .value = "one=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT" }, .{ .name = "Set-Cookie", .value = "two=2" }, .{ .name = "X-Duplicate", .value = "one" }, .{ .name = "X-Duplicate", .value = "two" } } });
        if (std.mem.eql(u8, target, "/latin1")) return request.respond("latin1", .{ .status = .created, .reason = "Cr\xe9\xe9", .keep_alive = false, .extra_headers = &.{ .{ .name = "__proto__", .value = "own" }, .{ .name = "X-Latin1", .value = "caf\xe9" }, .{ .name = "constructor", .value = "wire" } } });
        if (std.mem.eql(u8, target, "/redirect")) return request.respond("", .{ .status = .found, .keep_alive = false, .extra_headers = &.{.{ .name = "Location", .value = "/json" }} });
        if (std.mem.eql(u8, target, "/null204")) return request.respond("", .{ .status = .no_content, .keep_alive = false });
        if (std.mem.eql(u8, target, "/empty")) return request.respond("", .{ .keep_alive = false });
        if (std.mem.eql(u8, target, "/broken-body")) {
            try writer.interface.writeAll("HTTP/1.1 200 OK\r\nContent-Length: 100\r\nConnection: close\r\n\r\nshort");
            return writer.interface.flush();
        }
        const index: usize = if (std.mem.eql(u8, target, "/gate?id=head200")) 0 else if (std.mem.eql(u8, target, "/gate?id=head403")) 1 else if (std.mem.eql(u8, target, "/abort-head?id=abort-head")) 2 else if (std.mem.eql(u8, target, "/abort-body?id=abort-body")) 3 else return error.UnexpectedFetch39PeerPath;
        self.gateResponse(&request, index) catch |err| {
            // The two abort fixtures deliberately close their real peer socket.
            if (index >= 2 and err != error.OutOfMemory and err != error.Canceled) return;
            return err;
        };
    }
    fn gateResponse(self: *Peer, request: *std.http.Server.Request, index: usize) !void {
        const gate = &self.gates[index];
        gate.seen.store(true, .release);
        if (index == 2) {
            try gate.release.waitTimeout(self.io, .{ .duration = .{ .raw = .fromSeconds(10), .clock = .awake } });
            return request.respond("late", .{ .keep_alive = false });
        }
        const payload = if (index == 3) "firstlast" else "{\"headBeforeBody\":true}";
        var buffer: [256]u8 = undefined;
        var response = try request.respondStreaming(&buffer, .{ .content_length = payload.len, .respond_options = .{ .status = if (index == 1) .forbidden else .ok, .keep_alive = false, .extra_headers = if (index == 3) &.{} else &.{.{ .name = "Content-Type", .value = "application/json" }} } });
        try request.server.out.flush();
        gate.sent.store(true, .release);
        if (index == 3) {
            try response.writer.writeAll("first");
            try request.server.out.flush();
        }
        try gate.release.waitTimeout(self.io, .{ .duration = .{ .raw = .fromSeconds(10), .clock = .awake } });
        gate.finished.store(true, .release);
        try response.writer.writeAll(if (index == 3) "last" else payload);
        try response.end();
        try request.server.out.flush();
    }
};
fn peerOf(context: ?*c.JSContext, pointer: c.JSValue) !*Peer {
    var address: u64 = 0;
    if (c.JS_ToIndex(context, &address, pointer) < 0) return js.capture(em.Engine.fromContext(context.?));
    return @ptrFromInt(@as(usize, @intCast(address)));
}
fn gateField(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, raw: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const peer = peerOf(context, roots[0]) catch |err| return @import("native_sdk.zig").fail(engine, err);
    var index: u32 = 0;
    if (c.JS_ToUint32(context, &index, roots[1]) < 0 or index >= peer.gates.len) return c.JS_ThrowTypeError(context, "Invalid native peer gate");
    const gate = &peer.gates[index];
    if (raw == 3) {
        gate.release.set(peer.io);
        return c.pi_js_undefined();
    }
    return c.JS_NewBool(context, switch (raw) {
        0 => gate.sent.load(.acquire),
        1 => gate.seen.load(.acquire),
        2 => gate.finished.load(.acquire),
        else => false,
    });
}
fn gateObject(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const id = try engine.toString(if (args.len > 0) args[0] else c.pi_js_undefined());
    defer engine.gpa.free(id);
    const index: u32 = if (std.mem.eql(u8, id, "head200")) 0 else if (std.mem.eql(u8, id, "head403")) 1 else if (std.mem.eql(u8, id, "abort-head")) 2 else if (std.mem.eql(u8, id, "abort-body")) 3 else return error.UnknownFetch39PeerGate;
    const object = try scope.object();
    var captures = [_]c.JSValue{ roots[0], c.JS_NewUint32(engine.context, index) };
    inline for (.{ "sent", "seen", "finished" }, 0..) |name, kind| {
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, gateField, "get " ++ name, 0, @intCast(kind), captures.len, &captures)));
        const atom = c.JS_NewAtom(engine.context, name);
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, object, atom, c.JS_DupValue(engine.context, function), c.pi_js_undefined(), c.JS_PROP_ENUMERABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
    try scope.set(object, "unblock", try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, gateField, "unblock", 0, 3, captures.len, &captures))));
    return c.JS_DupValue(engine.context, object);
}
fn traceCase(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const name = engine.toString(if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return @import("native_sdk.zig").fail(engine, err);
    defer engine.gpa.free(name);
    std.debug.print("Fetch39 begin: {s}\n", .{name});
    return c.pi_js_undefined();
}
fn progress(engine: *em.Engine, peer: *Peer) void {
    const original_message = engine.last_error;
    const original_exception = engine.captured_exception;
    engine.last_error = null;
    engine.captured_exception = null;
    defer {
        if (engine.last_error) |message| engine.gpa.free(message);
        if (engine.captured_exception) |exception| engine.freeValue(exception);
        engine.last_error = original_message;
        engine.captured_exception = original_exception;
    }
    const value = engine.eval("JSON.stringify({active:globalThis.nativeFetch39ActiveCase,completed:globalThis.nativeFetch39ProgressRows?.length,last:globalThis.nativeFetch39ProgressRows?.at(-1)?.name})", "fetch39-failure-progress.js", c.JS_EVAL_TYPE_GLOBAL) catch return;
    defer engine.freeValue(value);
    const text = engine.toString(value) catch return;
    defer engine.gpa.free(text);
    std.debug.print("Fetch39 diagnostic {s} actual-peer-requests={d} peer-failures={d} transport-pending={any}\n", .{ text, peer.requests.load(.acquire), peer.failures.load(.acquire), @import("native_ai_http.zig").pending(engine) });
}
test "Web fetch Source39 complete unchanged observations real peer classes bytes redirects signals and upload" {
    const peer = try Peer.init(std.testing.allocator, std.testing.io);
    defer peer.deinit();
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_web_fetch.zig").install(engine);
    try engine.bindFunction("nativeTraceFetch39Case", traceCase, 1);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const origin = try std.fmt.allocPrint(engine.gpa, "http://127.0.0.1:{d}", .{peer.listener.socket.address.getPort()});
    defer engine.gpa.free(origin);
    try scope.set(global, "nativeFetch39Origin", try scope.text(origin));
    const gate = try scope.own(try @import("native_node_function.zig").create(engine, "nativeFetch39Gate", 2, gateObject, &.{c.JS_NewFloat64(engine.context, @floatFromInt(@intFromPtr(peer)))}));
    try scope.set(global, "nativeFetch39Gate", gate);
    const packet = @embedFile("fixtures/web-fetch-node24.json");
    try scope.set(global, "originalFetchPacket", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, packet.ptr, packet.len, "genuine-fetch39.json"))));
    const pending = engine.evalModule(@embedFile("fixtures/web-fetch-node24.input.txt") ++
        \\
        \\if(originalFetchPacket.rows.length!==39||webFetchRows.length!==39||new Set(webFetchRows.map(row=>row.name)).size!==39)throw Error('Fetch39 complete projection inventory mismatch');
        \\const mismatches=[];for(let i=0;i<39;i++){const actual=webFetchRows[i],expected=originalFetchPacket.rows[i];if(JSON.stringify(actual)!==JSON.stringify(expected))mismatches.push({index:i,actual,expected})}
        \\if(mismatches.length)throw Error(JSON.stringify({mapped:39,mismatches}));
    , "genuine-fetch39-native-peer-projection.mjs") catch |err| {
        progress(engine, peer);
        if (engine.last_error) |message| std.debug.print("Fetch39: {s}\n", .{message});
        return err;
    };
    defer engine.freeValue(pending);
    const settled = engine.awaitValue(pending) catch |err| {
        progress(engine, peer);
        if (engine.last_error) |message| std.debug.print("Fetch39: {s}\n", .{message});
        return err;
    };
    engine.freeValue(settled);
    try std.testing.expectEqual(@as(usize, 0), peer.failures.load(.acquire));
    std.debug.print("Fetch39 actual peer requests={d} all39-rows-compared=true\n", .{peer.requests.load(.acquire)});
    c.JS_RunGC(engine.runtime);
}

fn ownedHttpStream(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const request = if (args.len > 0) args[0] else c.pi_js_undefined();
    const view = try @import("native_web_request.zig").view(&scope, request);
    const url = try engine.toString(view.url);
    defer engine.gpa.free(url);
    const transport = try scope.own(try @import("native_ai_http.zig").openWithOptions(engine, .{ .url = url, .framing = .bytes, .stream_error_bytes = true, .redirect_behavior = .unhandled }, view.signal, .{ .raw_header_pairs = true }));
    c.JS_PromiseMarkAsHandled(engine.context, try scope.get(transport, "ready"));
    return @import("native_web_byte_source.zig").fromEvents(engine, try scope.get(transport, "events"), .{ .request = request, .signal = view.signal, .cancel = try scope.get(transport, "cancel") });
}
test "HTTP byte source retains actual Request across GC and releases on EOF error cancel and abort" {
    const peer = try Peer.init(std.testing.allocator, std.testing.io);
    defer peer.deinit();
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_web_fetch.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const origin = try std.fmt.allocPrint(engine.gpa, "http://127.0.0.1:{d}", .{peer.listener.socket.address.getPort()});
    defer engine.gpa.free(origin);
    try scope.set(global, "ownerOrigin", try scope.text(origin));
    try scope.set(global, "nativeOwnedHttpStream", try scope.own(try @import("native_node_function.zig").create(engine, "nativeOwnedHttpStream", 1, ownedHttpStream, &.{})));
    inline for (.{ "eof", "error", "cancel", "abort" }) |mode| {
        const prepared = try engine.evalModule(
            \\globalThis.ownerParent=new AbortController();
            \\globalThis.ownerRequest=new Request(ownerOrigin+
        ++ (if (std.mem.eql(u8, mode, "error")) "'/broken-body'" else "'/json'") ++
            \\,{signal:ownerParent.signal});
            \\globalThis.ownerWeak=new WeakRef(ownerRequest);
            \\globalThis.ownerStream=nativeOwnedHttpStream(ownerRequest);
            \\ownerRequest=null;
        , "http-request-root-prepare-" ++ mode ++ ".mjs");
        engine.freeValue(prepared);
        // These are synchronous native VM operations, not a timer or a promise
        // about when ECMAScript FinalizationRegistry callbacks will run.
        c.JS_ClearKeptObjects(engine.runtime);
        c.JS_RunGC(engine.runtime);
        const retained = try engine.evalModule("if(ownerWeak.deref()===undefined)throw Error('Request retired before terminal body transition');", "http-request-root-retained-" ++ mode ++ ".mjs");
        engine.freeValue(retained);
        const terminal = try engine.evalModule(if (std.mem.eql(u8, mode, "eof")) "await new Response(ownerStream).text();" else if (std.mem.eql(u8, mode, "error")) "let failure;try{await new Response(ownerStream).text()}catch(e){failure=e}if(failure===undefined)throw Error('Expected actual truncated HTTP body rejection');" else if (std.mem.eql(u8, mode, "cancel")) "await ownerStream.cancel({owned:'cancel'});" else "const reason={owned:'abort'};ownerParent.abort(reason);let failure;try{await new Response(ownerStream).text()}catch(e){failure=e}if(failure!==reason)throw Error('Original abort reason not retained');", "http-request-root-terminal-" ++ mode ++ ".mjs");
        engine.freeValue(terminal);
        c.JS_ClearKeptObjects(engine.runtime);
        c.JS_RunGC(engine.runtime);
        const released = try engine.evalModule("if(ownerWeak.deref()!==undefined)throw Error('Request retained after terminal body cleanup');ownerStream=null;ownerParent=null;ownerWeak=null;", "http-request-root-released-" ++ mode ++ ".mjs");
        engine.freeValue(released);
    }
    try std.testing.expectEqual(@as(usize, 0), peer.failures.load(.acquire));
}
