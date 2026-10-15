const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const http = @import("extensions/native_ai_http.zig");
const raw = @import("extensions/native_ai_http_worker.zig");
const fixture = @import("ai/http_fixture.zig");
const c = em.c;
test "native AI HTTP fetch opt-ins preserve non-2xx binary bodies and repeated raw header pairs" {
    const body = "denied\x00\xff";
    const first = "first=one; Expires=Thu, 01 Jan 2037 00:00:00 GMT";
    const second = "second=two; Path=/";
    const server = try fixture.PlanServer.init(std.testing.allocator, std.testing.io, &.{.{ .path = "/binary-error?original=query", .status = .forbidden, .body = body, .headers = &.{ .{ .name = "Set-Cookie", .value = first }, .{ .name = "Set-Cookie", .value = second }, .{ .name = "constructor", .value = "literal" }, .{ .name = "__proto__", .value = "literal-proto" }, .{ .name = "x-latin", .value = "latin-\x80\xff" } } }});
    defer server.deinit();
    const url = try server.url(std.testing.allocator, "/binary-error?original=query");
    defer std.testing.allocator.free(url);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "rawRequest", try http.openWithOptions(engine, .{ .url = url, .payload = "{}", .headers = &.{}, .timeout_ms = 2000, .framing = .bytes, .stream_error_bytes = true }, c.pi_js_undefined(), .{ .raw_header_pairs = true }));
    const checked = try engine.evalModule(
        \\const head=await rawRequest.ready;if(head.status!==403||head.statusText!=='Forbidden')throw Error('unsuccessful head');const pairs=head.rawHeaders.filter(([name])=>name.toLowerCase()==='set-cookie');if(pairs.length!==2||pairs[0][1]!=='first=one; Expires=Thu, 01 Jan 2037 00:00:00 GMT'||pairs[1][1]!=='second=two; Path=/')throw Error('cookie boundaries');if(!Object.hasOwn(head.headers,'constructor')||head.headers.constructor!=='literal'||!Object.hasOwn(head.headers,'__proto__')||head.headers.__proto__!=='literal-proto'||Object.getPrototypeOf(head.headers)!==Object.prototype)throw Error('internal own header record');if(head.headers['x-latin']!=='latin-\x80\xff'||head.rawHeaders.find(([name])=>name==='x-latin')[1]!=='latin-\x80\xff')throw Error('lossless Latin1');const bytes=[];for await(const event of rawRequest.events){if(event.type!=='bytes')throw Error('binary error incorrectly decoded');bytes.push(...event.data)}if(JSON.stringify(bytes)!==JSON.stringify([100,101,110,105,101,100,0,255]))throw Error('non-2xx raw bytes changed');export const done=true;
    , "native-ai-http-fetch-opt-ins.mjs");
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
    try std.testing.expect(!http.pending(engine));
    try server.finish();
}
test "native AI HTTP observed header-only deadline permits long body and rejects late headers" {
    const server = try fixture.PlanServer.init(std.testing.allocator, std.testing.io, &.{ .{ .path = "/body", .body = "long-body", .body_delay_ms = 200 }, .{ .path = "/headers", .body = "late", .delay_ms = 200 } });
    defer server.deinit();
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    for (.{ "/body", "/headers" }, 0..) |path, index| {
        const url = try server.url(std.testing.allocator, path);
        defer std.testing.allocator.free(url);
        try sdk.put(engine, global, if (index == 0) "longBody" else "lateHeaders", try http.open(engine, .{ .url = url, .payload = "{}", .headers = &.{}, .timeout_ms = if (index == 0) 100 else 30, .headers_timeout_only = true, .framing = .body }, c.pi_js_undefined()));
        const module = try engine.evalModule(if (index == 0) "const head=await longBody.ready;if(head.status!==200)throw Error('ready');let body='';for await(const event of longBody.events)body+=event.body;if(body!=='long-body')throw Error('body deadline was not retired at headers');export const done=true;" else "const error=await lateHeaders.ready.catch(error=>error);if(error.code!=='ProviderRequestTimeout')throw Error('late headers accepted');export const done=true;", if (index == 0) "http-header-deadline-long.mjs" else "http-header-deadline-late.mjs");
        engine.freeValue(module);
    }
}
test "native AI HTTP opt-in byte and JSON body framing preserves exact bytes and real status text" {
    const byte_body = "data: first\r\ndata: second\r\n\r\nunterminated\x00\xff";
    const server = try fixture.PlanServer.init(std.testing.allocator, std.testing.io, &.{ .{ .path = "/bytes", .body = byte_body, .status = .created }, .{ .path = "/json", .body = "{\"token\":\"fixture-placeholder\"}" } });
    defer server.deinit();
    for ([_]raw.Framing{ .bytes, .body }, [_][]const u8{ "/bytes", "/json" }) |framing, suffix| {
        const url = try server.url(std.testing.allocator, suffix);
        defer std.testing.allocator.free(url);
        const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        engine.native_io = std.testing.io;
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try sdk.put(engine, global, "rawRequest", try http.open(engine, .{ .url = url, .payload = "{}", .headers = &.{}, .timeout_ms = 2000, .framing = framing }, c.pi_js_undefined()));
        const checked = if (framing == .bytes) try engine.evalModule(
            \\const head=await rawRequest.ready;if(head.status!==201||head.statusText!=='Created')throw Error('actual status text');const bytes=[];for await(const event of rawRequest.events){if(event.type!=='bytes'||!(event.data instanceof Uint8Array))throw Error('byte framing');bytes.push(...event.data)}const expected='data: first\r\ndata: second\r\n\r\nunterminated';if(bytes.length!==expected.length+2||bytes.at(-2)!==0||bytes.at(-1)!==255||bytes.slice(0,-2).some((byte,index)=>byte!==expected.charCodeAt(index)))throw Error('unmodified binary bytes including final line');export const done=true;
        , "native-ai-http-bytes.mjs") else try engine.evalModule(
            \\const head=await rawRequest.ready;if(head.status!==200||head.statusText!=='OK')throw Error('actual OK status');const events=[];for await(const event of rawRequest.events)events.push(event);if(events.length!==1||events[0].type!=='body'||events[0].body!=='{"token":"fixture-placeholder"}')throw Error('JSON body framing');export const done=true;
        , "native-ai-http-json-body.mjs");
        engine.freeValue(checked);
        c.JS_RunGC(engine.runtime);
        try std.testing.expect(!http.pending(engine));
    }
    try server.finish();
}
fn install(engine: *em.Engine, url: []const u8, payload: []const u8) !void {
    engine.native_io = std.testing.io;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const Adapter = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            host.native_exception_diagnostics_suppressed += 1;
            defer host.native_exception_diagnostics_suppressed -= 1;
            const address = try host.toString(roots[0]);
            defer host.gpa.free(address);
            const body = try host.toString(roots[1]);
            defer host.gpa.free(body);
            return http.open(host, .{ .url = address, .payload = body, .timeout_ms = 2000, .headers = &.{ .{ .name = "content-type", .value = "application/json" }, .{ .name = "authorization", .value = "Bearer fixture-placeholder-key" } } }, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    const function = try scope.own(try @import("extensions/native_node_function.zig").create(engine, "openRawHTTP", 1, Adapter.call, &.{ try scope.text(url), try scope.text(payload) }));
    try scope.put(global, "openRawHTTP", function);
}
test "native AI HTTP raw transport replays12 genuine Source wire payloads and exact SSE data without provider substitution" {
    const gpa = std.testing.allocator;
    const input = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/ai-openai-http-b45.input.json"), .{});
    defer input.deinit();
    const source = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/ai-openai-http-b45.json"), .{});
    defer source.deinit();
    const cases = input.value.array.items;
    const rows = source.value.object.get("rows").?.array.items;
    try std.testing.expectEqualStrings("b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb", source.value.object.get("sourceHead").?.string);
    try std.testing.expectEqual(@as(usize, 12), cases.len);
    try std.testing.expectEqual(cases.len, rows.len);
    for (cases, rows, 0..) |item, row, index| {
        try std.testing.expectEqualStrings(item.object.get("name").?.string, row.object.get("name").?.string);
        const payload = try std.json.Stringify.valueAlloc(gpa, row.object.get("request").?.object.get("body").?, .{});
        defer gpa.free(payload);
        var body: std.ArrayList(u8) = .empty;
        defer body.deinit(gpa);
        for (item.object.get("chunks").?.array.items) |chunk| {
            const encoded = try std.json.Stringify.valueAlloc(gpa, chunk, .{});
            defer gpa.free(encoded);
            try body.appendSlice(gpa, "data: ");
            try body.appendSlice(gpa, encoded);
            try body.appendSlice(gpa, "\n\n");
        }
        try body.appendSlice(gpa, "data: [DONE]\n\n");
        const server = try fixture.PlanServer.init(gpa, std.testing.io, &.{.{ .path = "/v1/chat/completions", .body = body.items, .payload_contains = payload, .expected_request_headers = &.{.{ .name = "authorization", .value = "Bearer fixture-placeholder-key" }}, .headers = &.{.{ .name = "x-fixture", .value = "source-only" }} }});
        defer server.deinit();
        const url = try server.url(gpa, "/v1/chat/completions");
        defer gpa.free(url);
        const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        try install(engine, url, payload);
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const expected = try std.json.Stringify.valueAlloc(gpa, item.object.get("chunks").?, .{});
        defer gpa.free(expected);
        // The direct QuickJS C parser requires a NUL byte after buf_len.
        const expected_z = try gpa.dupeZ(u8, expected);
        defer gpa.free(expected_z);
        try sdk.put(engine, global, "expectedRawChunks", try engine.checked(c.JS_ParseJSON(engine.context, expected_z.ptr, expected_z.len, "expected-raw-chunks.json")));
        const result = engine.evalModule(
            \\const request=openRawHTTP(),head=await request.ready;if(head.status!==200||head.headers['x-fixture']!=='source-only')throw Error('native response head');const chunks=[];let done=0;for await(const event of request.events){if(event.type!=='frame'||event.event!==null)throw Error('raw frame shape');if(event.data==='[DONE]'){done++;continue}chunks.push(JSON.parse(event.data));}if(done!==1||JSON.stringify(chunks)!==JSON.stringify(expectedRawChunks))throw Error('raw Source wire fidelity');const late=await request.events.next();if(!late.done)throw Error('retired iterator');export const proof=true;
        , "native-ai-http-source-wire.mjs") catch |err| {
            std.debug.print("Raw HTTP Source case {d}: {s}\n", .{ index, engine.last_error orelse "no diagnostic" });
            return err;
        };
        engine.freeValue(result);
        c.JS_RunGC(engine.runtime);
        try std.testing.expect(!http.pending(engine));
        try server.finish();
    }
}
test "native AI HTTP preserves CR LF BOM multiline event fields and non-success response body" {
    const server = try fixture.PlanServer.init(std.testing.allocator, std.testing.io, &.{ .{ .path = "/sse", .body = "\xef\xbb\xbf: comment\r\nevent: named\rdata: first\r\ndata:  second\r\n\r\ndata: tail-without-empty-line" }, .{ .path = "/error", .status = .too_many_requests, .body = "{\"error\":{\"message\":\"fixture\"}}" } });
    defer server.deinit();
    const first = try server.url(std.testing.allocator, "/sse");
    defer std.testing.allocator.free(first);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine, first, "{}");
    const result = try engine.evalModule("const request=openRawHTTP();await request.ready;const events=[];for await(const event of request.events)events.push(event);if(JSON.stringify(events)!==JSON.stringify([{type:'frame',event:'named',data:'first'+String.fromCharCode(10)+' second'}]))throw Error('SSE field preservation');export const proof=true;", "native-ai-http-sse-lines.mjs");
    engine.freeValue(result);
    const second = try server.url(std.testing.allocator, "/error");
    defer std.testing.allocator.free(second);
    try install(engine, second, "{}");
    const error_result = try engine.evalModule("const request=openRawHTTP(),head=await request.ready,events=[];for await(const event of request.events)events.push(event);if(head.status!==429||events.length!==1||events[0].type!=='error_body'||JSON.parse(events[0].body).error.message!=='fixture')throw Error('raw status/body');export const proof=true;", "native-ai-http-status-body.mjs");
    engine.freeValue(error_result);
    try server.finish();
    try std.testing.expect(!http.pending(engine));
}
test "native AI HTTP real abort signal cancels owned body work and retires reader roots" {
    const server = try fixture.PlanServer.init(std.testing.allocator, std.testing.io, &.{.{ .path = "/slow", .body = "data: {}\n\n", .body_delay_ms = 250 }});
    defer server.deinit();
    const url = try server.url(std.testing.allocator, "/slow");
    defer std.testing.allocator.free(url);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try install(engine, url, "{}");
    const result = try engine.evalModule(
        \\const controller=new AbortController(),request=openRawHTTP(controller.signal);setTimeout(()=>controller.abort(),10);let code;try{await request.ready;for await(const event of request.events){}}catch(error){code=error.code}if(!['ProviderRequestAborted','NativeHttpAborted'].includes(code))throw Error('owned cancellation '+code);export const proof=true;
    , "native-ai-http-owned-abort.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    try std.testing.expect(!http.pending(engine));
}
test "native AI HTTP full-queue timeout and VM teardown cancel join and release owned responses" {
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(std.testing.allocator);
    for (0..200) |_| try body.appendSlice(std.testing.allocator, "data: {\"text\":\"queued\"}\n\n");
    const server = try fixture.PlanServer.init(std.testing.allocator, std.testing.io, &.{.{ .path = "/queued", .body = body.items }});
    defer server.deinit();
    const url = try server.url(std.testing.allocator, "/queued");
    defer std.testing.allocator.free(url);
    const worker = try raw.Worker.create(std.testing.io, .{ .url = url, .payload = "{}", .headers = &.{}, .timeout_ms = 50 }, null, null);
    defer worker.destroy();
    const deadline = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() + 2000;
    while (!worker.finished.load(.acquire)) {
        if (std.Io.Clock.awake.now(std.testing.io).toMilliseconds() >= deadline) return error.WorkerTimeoutDidNotCancelBackpressure;
        try std.testing.io.sleep(.fromMilliseconds(1), .awake);
    }
    try std.testing.expectEqual(error.ProviderRequestTimeout, worker.failure.?);
    const server2 = try fixture.PlanServer.init(std.testing.allocator, std.testing.io, &.{.{ .path = "/queued", .body = body.items }});
    defer server2.deinit();
    const url2 = try server2.url(std.testing.allocator, "/queued");
    defer std.testing.allocator.free(url2);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    errdefer engine.deinit();
    try install(engine, url2, "{}");
    const opened = try engine.evalModule("globalThis.unconsumedRaw=openRawHTTP();await unconsumedRaw.ready;export const started=true;", "native-ai-http-teardown-start.mjs");
    engine.freeValue(opened);
    try std.testing.expect(http.pending(engine));
    engine.deinit();
}
test "native AI HTTP every host allocation unwinds pre-aborted preparation without starting a worker" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine, "http://127.0.0.1:1/never", "{}") catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule("const request=openRawHTTP({aborted:true});let code;try{await request.ready}catch(error){code=error.code}if(code!=='ProviderRequestAborted'||!(await request.events.next()).done)throw Error('pre-aborted preparation');export const proof=true;", "native-ai-http-allocation-pre-aborted.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            if (http.pending(engine)) return error.PreAbortedWorkerStarted;
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
