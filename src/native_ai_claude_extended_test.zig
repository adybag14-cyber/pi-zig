const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const fixture = @import("ai/http_fixture.zig");
comptime {
    _ = @import("native_ai_constrained_sampling_test.zig");
    _ = @import("native_ai_sdk_headers_test.zig");
    _ = @import("native_node_function_exception_test.zig");
    _ = @import("native_ai_anthropic_api_error_test.zig");
}

fn putJson(scope: *v.Scope, global: c.JSValue, name: [*:0]const u8, bytes: []const u8) !void {
    const terminated = try scope.engine.gpa.dupeZ(u8, bytes);
    defer scope.engine.gpa.free(terminated);
    try scope.put(global, name, try scope.own(try scope.engine.checked(c.JS_ParseJSON(scope.engine.context, terminated.ptr, bytes.len, name))));
}
fn functionalHeader(request: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    if (request.get("headers").?.object.get(name)) |value| return value.string;
    const raw = request.get("rawHeaders").?.array.items;
    var index: usize = 0;
    while (index + 1 < raw.len) : (index += 2) {
        if (std.ascii.eqlIgnoreCase(raw[index].string, name)) return raw[index + 1].string;
    }
    return null;
}

test "native Claude5ab extended public Source16 wire federation retry long result-only and callback ownership" {
    const gpa = std.testing.allocator;
    const source_bytes = @embedFile("extensions/fixtures/ai-anthropic5ab-extended.json");
    const source = try std.json.parseFromSlice(std.json.Value, gpa, source_bytes, .{});
    defer source.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const plan_gpa = arena.allocator();
    const native_user_agent = try std.fmt.allocPrint(plan_gpa, "pi-zig/Zig-{s} QuickJS-{s} ({s}; {s})", .{ @import("builtin").zig_version_string, std.mem.span(c.JS_GetVersion()), @tagName(@import("builtin").os.tag), @tagName(@import("builtin").cpu.arch) });
    var replies: std.ArrayList(fixture.Reply) = .empty;
    var expected_requests: usize = 0;
    for (source.value.object.get("rows").?.array.items) |row| {
        const requests = row.object.get("requests").?.array.items;
        const responses = row.object.get("responses").?.array.items;
        try std.testing.expectEqual(requests.len, responses.len);
        for (requests, responses) |request, response| {
            const expected = request.object;
            const reply = response.object;
            var request_headers: std.ArrayList(std.http.Header) = .empty;
            // Source runtime diagnostics remain raw and immutable. Native
            // requests independently identify their real compiler/VM/host.
            try request_headers.append(plan_gpa, .{ .name = "User-Agent", .value = native_user_agent });
            var absent_headers: std.ArrayList([]const u8) = .empty;
            for ([_][]const u8{ "authorization", "x-api-key", "content-type", "accept", "anthropic-beta", "anthropic-version", "anthropic-dangerous-direct-browser-access", "x-app", "x-session-id", "x-session-affinity", "anthropic-user-profile-id", "anthropic-workspace-id", "x-captured", "x-option" }) |name| {
                if (functionalHeader(expected, name)) |value| try request_headers.append(plan_gpa, .{ .name = name, .value = value }) else try absent_headers.append(plan_gpa, name);
            }
            var response_headers: std.ArrayList(std.http.Header) = .empty;
            var fields = reply.get("headers").?.object.iterator();
            while (fields.next()) |field| try response_headers.append(plan_gpa, .{ .name = field.key_ptr.*, .value = field.value_ptr.string });
            try replies.append(plan_gpa, .{
                .path = expected.get("path").?.string,
                .body = reply.get("body").?.string,
                .status = @enumFromInt(reply.get("status").?.integer),
                .headers = response_headers.items,
                .expected_request_headers = request_headers.items,
                .absent_request_headers = absent_headers.items,
                .expected_request_method = std.meta.stringToEnum(std.http.Method, expected.get("method").?.string) orelse return error.UnknownSourceMethod,
            });
            expected_requests += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 18), expected_requests);
    const server = try fixture.PlanServer.init(gpa, std.testing.io, replies.items);
    defer server.deinit();
    const address = try server.url(gpa, "");
    defer gpa.free(address);
    const engine = try v.em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    try @import("extensions/commonjs.zig").install(engine);
    try @import("extensions/native_url.zig").install(engine);
    try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    try @import("extensions/native_headers.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "extendedStreams", try scope.own(try @import("extensions/native_ai_anthropic_factory.zig").create(engine)));
    try putJson(&scope, global, "extendedSource", source_bytes);
    try scope.put(global, "extendedBaseURL", try scope.text(address));
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "owned-public-fixture.jwt", .data = source.value.object.get("identityFixture").?.object.get("contents").?.string });
    var directory_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const directory_length = try tmp.dir.realPath(std.testing.io, &directory_buffer);
    const identity_path = try std.fs.path.join(gpa, &.{ directory_buffer[0..directory_length], "owned-public-fixture.jwt" });
    defer gpa.free(identity_path);
    try scope.put(global, "extendedIdentityFile", try scope.text(identity_path));
    const guest = @embedFile("extensions/fixtures/ai-anthropic5ab-extended-native.mjs");
    const result = engine.evalModule(guest ++ "\nexport const compared=await run(extendedSource,extendedStreams,extendedBaseURL,extendedIdentityFile);", "native-claude5ab-extended-source16.mjs") catch |err| {
        std.debug.print("Anthropic extended Source16: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    var retirement_polls: usize = 0;
    while (@import("extensions/native_ai_http.zig").pending(engine) and retirement_polls < 200) : (retirement_polls += 1) {
        _ = try engine.pumpControls();
        if (@import("extensions/native_ai_http.zig").pending(engine)) try std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake);
    }
    try std.testing.expect(!@import("extensions/native_ai_http.zig").pending(engine));
    try server.finish();
    try std.testing.expectEqual(expected_requests, server.captured.items.len);
    const captured = try scope.array();
    for (server.captured.items, 0..) |request, index| {
        const record = try scope.object();
        try scope.put(record, "method", try scope.text(@tagName(request.method)));
        try scope.put(record, "path", try scope.text(request.path));
        try putJson(&scope, record, "body", request.payload);
        try scope.index(captured, @intCast(index), record);
    }
    try scope.put(global, "extendedCaptured", captured);
    const checked = engine.evalModule(guest ++ "\nexport const requestsCompared=checkRequests(extendedSource,extendedCaptured);", "native-claude5ab-extended-captured-requests.mjs") catch |err| {
        std.debug.print("Anthropic extended Source16 wire requests: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}

test "native Claude5ab extended fresh native allocation identity survives stream delivery while stale and user errors remain caller failures" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try @import("extensions/native_headers.zig").install(engine);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "allocationStreams", try scope.own(try @import("extensions/native_ai_anthropic_factory.zig").create(engine)));
    const Fault = struct {
        fn call(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            return v.em.Engine.fromContext(context.?).throwNativeOutOfMemory();
        }
    };
    // This tests private allocation-tag delivery, not an exhaustive allocator
    // sweep. The separate unchanged full-index suites exercise real failures.
    try engine.bindFunction("nativeHostAllocationFault", Fault.call, 0);
    const result = engine.evalModule(
        \\const model={api:'anthropic-messages',provider:'anthropic',id:'claude-sonnet-4-6',name:'Claude',baseUrl:'https://fixture.invalid',input:['text'],reasoning:true,maxTokens:1024,cost:{input:1,output:1,cacheRead:1,cacheWrite:1}},context={messages:[{role:'user',content:'hello'}]};
        \\let original;const fresh=allocationStreams.stream(model,context,{apiKey:'fixture-placeholder-key',onPayload(){try{nativeHostAllocationFault()}catch(error){original=error;throw error}}});let delivered;try{await fresh.result();throw Error('fresh native allocation unexpectedly became an assistant message')}catch(error){delivered=error}if(!original||delivered!==original)throw Error('fresh allocation identity lost');
        \\const stale=allocationStreams.stream(model,context,{apiKey:'fixture-placeholder-key',onPayload(){throw original}}),staleResult=await stale.result();if(staleResult.stopReason!=='error'||staleResult.errorMessage!==original.message)throw Error('old caught allocation error must remain caller failure');let terminal;for await(const event of stale)terminal=event;if(terminal.error!==staleResult)throw Error('stale caller error terminal identity lost');
        \\const user=new Error('out of memory');user.name='InternalError';const ordinary=allocationStreams.stream(model,context,{apiKey:'fixture-placeholder-key',onPayload(){throw user}}),ordinaryResult=await ordinary.result();if(ordinaryResult.stopReason!=='error'||ordinaryResult.errorMessage!=='out of memory')throw Error('user error was classified by name');export const taggedDelivery=true;
    , "native-claude5ab-allocation-delivery.mjs") catch |err| {
        std.debug.print("Anthropic allocation delivery: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
