//! Prepared all58 original-source replay. This strict diagnostic gate deliberately
//! retains transport identity differences until Root reviews their native contract.
const std = @import("std");
const em = @import("extensions/engine.zig");
const v = @import("extensions/native_ai_provider_values.zig");
const fixture = @import("ai/http_fixture.zig");
const c = em.c;
const golden = @embedFile("extensions/fixtures/ai-openai-full58-ae7.json");
const producer_golden = @embedFile("extensions/fixtures/ai-openai-producer58-ae7.json");
const answer = "{\"chunks\":[{\"id\":\"fixture-response\",\"choices\":[{\"delta\":{\"content\":\"done\"},\"finish_reason\":\"stop\"}]}]}";
fn publish(scope: *v.Scope, name: [*:0]const u8, value: std.json.Value) !void {
    const encoded = try std.json.Stringify.valueAlloc(scope.engine.gpa, value, .{});
    defer scope.engine.gpa.free(encoded);
    const terminated = try scope.engine.gpa.dupeZ(u8, encoded);
    defer scope.engine.gpa.free(terminated);
    const global = try scope.own(c.JS_GetGlobalObject(scope.engine.context));
    try scope.put(global, name, try scope.own(try scope.engine.checked(c.JS_ParseJSON(scope.engine.context, terminated.ptr, encoded.len, "original-source58.json"))));
}
fn install(scope: *v.Scope) !void {
    const engine = scope.engine;
    engine.native_io = std.testing.io;
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    try @import("extensions/commonjs.zig").install(engine);
    try @import("extensions/native_url.zig").install(engine);
    try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    try @import("extensions/native_headers.zig").install(engine);
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const loaded = try engine.evalModule("import 'pi-ai';export const loaded=true;", "full58-native-installed-stream.mjs");
    engine.freeValue(loaded);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const apis = try scope.own(try @import("extensions/native_ai_builtin_apis.zig").create(engine));
    try scope.put(global, "source58Apis", apis);
    try scope.put(global, "source58Factories", try scope.own(try @import("extensions/native_ai_provider_factories.zig").create(engine, apis)));
    // Original Source58 imports the direct implementation for non-Kimi rows;
    // the four Kimi rows deliberately retain their real lazy provider wrapper.
    try scope.put(global, "source58DirectOpenAI", try scope.own(try @import("extensions/native_ai_openai_factory.zig").create(engine)));
    const stream_module = engine.native_module_values.get("@earendil-works/pi-ai").?;
    try scope.put(global, "source58EventStream", try scope.get(stream_module, "AssistantMessageEventStream"));
}
fn responseBody(gpa: std.mem.Allocator, plan: std.json.Value) ![]const u8 {
    const fields = plan.object;
    if (fields.get("body")) |body| return if (body == .string) body.string else std.json.Stringify.valueAlloc(gpa, body, .{});
    if (fields.get("rawSSE")) |body| return body.string;
    var output: std.ArrayList(u8) = .empty;
    for (fields.get("chunks").?.array.items) |chunk| {
        try output.appendSlice(gpa, "data: ");
        try output.appendSlice(gpa, try std.json.Stringify.valueAlloc(gpa, chunk, .{}));
        try output.appendSlice(gpa, "\n\n");
    }
    try output.appendSlice(gpa, "data: [DONE]\n\n");
    return output.toOwnedSlice(gpa);
}
fn replies(gpa: std.mem.Allocator, input: std.json.Value, requests: []const std.json.Value) ![]const fixture.Reply {
    const fallback = try std.json.parseFromSlice(std.json.Value, gpa, answer, .{});
    const plans = if (input.object.get("responses")) |value| value.array.items else &.{fallback.value};
    var result: std.ArrayList(fixture.Reply) = .empty;
    for (requests, 0..) |request, index| {
        const plan = plans[index];
        var headers: std.ArrayList(std.http.Header) = .empty;
        const status: std.http.Status = if (plan.object.get("status")) |value| @enumFromInt(value.integer) else .ok;
        try headers.append(gpa, .{ .name = "content-type", .value = if (@intFromEnum(status) < 300) "text/event-stream" else "application/json" });
        try headers.append(gpa, .{ .name = "x-fixture", .value = "source-only" });
        if (plan.object.get("headers")) |entries| {
            var iterator = entries.object.iterator();
            while (iterator.next()) |header| try headers.append(gpa, .{ .name = header.key_ptr.*, .value = header.value_ptr.string });
        }
        try result.append(gpa, .{ .path = request.object.get("path").?.string, .body = try responseBody(gpa, plan), .status = status, .headers = try headers.toOwnedSlice(gpa), .expected_request_method = .POST, .capture_request_headers = true });
    }
    return result.toOwnedSlice(gpa);
}
fn compareWire(name: []const u8, captured: []const fixture.Captured, expected: []const std.json.Value) bool {
    var matches = captured.len == expected.len;
    for (captured, 0..) |record, index| {
        std.debug.print("Source58 raw native request {s}/{d}: method={s} path={s} bytes={s}\n", .{ name, index, @tagName(record.method), record.path, record.payload });
        for (record.headers) |header| std.debug.print("Source58 raw native header {s}/{d}: {s}: {s}\n", .{ name, index, header.name, header.value });
        if (index >= expected.len) continue;
        const source = expected[index].object;
        if (!std.mem.eql(u8, @tagName(record.method), source.get("method").?.string) or !std.mem.eql(u8, record.path, source.get("path").?.string) or !std.mem.eql(u8, record.payload, source.get("rawBody").?.string)) matches = false;
        // The owned loopback port is the only wire normalization currently
        // approved. All other fields remain strict, including runtime identity.
        const expected_headers = source.get("rawHeaders").?.object;
        var iterator = expected_headers.iterator();
        while (iterator.next()) |entry| {
            if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, "host")) continue;
            var found = false;
            for (record.headers) |header| if (std.ascii.eqlIgnoreCase(header.name, entry.key_ptr.*)) {
                found = std.mem.eql(u8, header.value, entry.value_ptr.string);
                break;
            };
            if (!found) {
                matches = false;
                std.debug.print("Source58 raw header differs {s}/{d}: expected {s}: {s}\n", .{ name, index, entry.key_ptr.*, entry.value_ptr.string });
            }
        }
        for (record.headers) |header| {
            var known = std.ascii.eqlIgnoreCase(header.name, "host");
            var names = expected_headers.iterator();
            while (names.next()) |entry| if (std.ascii.eqlIgnoreCase(header.name, entry.key_ptr.*)) {
                known = true;
                break;
            };
            if (!known) {
                matches = false;
                std.debug.print("Source58 additional native header {s}/{d}: {s}: {s}\n", .{ name, index, header.name, header.value });
            }
        }
    }
    return matches;
}
fn nativeDefaultHeader(record: fixture.Captured, name: []const u8, expected: ?[]const u8) bool {
    var count: usize = 0;
    var matches = true;
    for (record.headers) |header| if (std.ascii.eqlIgnoreCase(header.name, name)) {
        count += 1;
        if (expected) |value| matches = matches and std.mem.eql(u8, value, header.value);
    };
    return matches and count == (if (expected == null) @as(usize, 0) else 1);
}
fn compareNativeDefaults(name: []const u8, captured: []const fixture.Captured, owned_host: []const u8, identity: []const u8) !bool {
    var matches = true;
    for (captured, 0..) |record, index| {
        const length = try std.fmt.allocPrint(std.testing.allocator, "{d}", .{record.payload.len});
        defer std.testing.allocator.free(length);
        const current = nativeDefaultHeader(record, "host", owned_host) and
            nativeDefaultHeader(record, "user-agent", identity) and
            nativeDefaultHeader(record, "x-stainless-retry-count", "0") and
            nativeDefaultHeader(record, "content-length", length) and
            nativeDefaultHeader(record, "content-type", "application/json") and
            nativeDefaultHeader(record, "connection", "close") and
            nativeDefaultHeader(record, "accept-encoding", "gzip, deflate") and
            nativeDefaultHeader(record, "transfer-encoding", null);
        var identity_absent = true;
        // This fixed original58 corpus has no caller-owned header overrides.
        // These are independent native-default assertions, not a projection of
        // Source's immutable Node header record or a native-generated golden.
        for ([_][]const u8{ "x-stainless-lang", "x-stainless-package-version", "x-stainless-os", "x-stainless-arch", "x-stainless-runtime", "x-stainless-runtime-version", "accept-language", "sec-fetch-mode" }) |field| {
            identity_absent = identity_absent and nativeDefaultHeader(record, field, null);
        }
        if (!current or !identity_absent) {
            matches = false;
            std.debug.print("Source58 independent native identity/protocol contract differs {s}/{d}; owned Host={s} identity={s} UTF8 body length={s}\n", .{ name, index, owned_host, identity, length });
        }
    }
    return matches;
}
test "native OpenAI original Source58 actual fourteen constructors Models Kimi full snapshots and strict raw wire" {
    const source = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, golden, .{});
    defer source.deinit();
    try std.testing.expectEqualStrings("ae7b16d43b7c78c5b6fa3213fdd1215bb339729d", source.value.object.get("sourceHead").?.string);
    const rows = source.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 58), rows.len);
    const native_identity = try @import("native_ai_openai_header_contract_test.zig").expectedNativeIdentity(std.testing.allocator);
    defer std.testing.allocator.free(native_identity);
    const producer_source = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, producer_golden, .{});
    defer producer_source.deinit();
    try std.testing.expectEqualStrings("ae7b16d43b7c78c5b6fa3213fdd1215bb339729d", producer_source.value.object.get("sourceHead").?.string);
    try std.testing.expectEqualStrings("df4b11133d4caf456de583f099ab6ebbeccccddedd040482714ae2452134db49", producer_source.value.object.get("driverSha256").?.string);
    const producer_rows = producer_source.value.object.get("producerRows").?.array.items;
    try std.testing.expectEqual(@as(usize, 58), producer_rows.len);
    try std.testing.expect(producer_source.value.object.get("instrumentation").?.object.get("allOriginalRowsUnchanged").?.bool);
    try std.testing.expectEqualStrings("6349299a388cbeb1f1086dfa58317ae4f296a26d6b620bb5a7987b6d44d82852", producer_source.value.object.get("instrumentation").?.object.get("baselineSha256").?.string);
    var all_match = true;
    for (rows, producer_rows) |row, producer_row| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const requests = row.object.get("requests").?.array.items;
        const input_fields = row.object.get("input").?.object;
        inline for (.{ "model", "options" }) |field| if (input_fields.get(field)) |entry| {
            if (entry.object.get("headers")) |overrides| if (overrides != .null) return error.NativeDefaultHeaderCorpusMustNotContainCallerOverrides;
        };
        const server = try fixture.PlanServer.init(std.testing.allocator, std.testing.io, try replies(arena.allocator(), row.object.get("input").?, requests));
        defer server.deinit();
        const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        var scope: v.Scope = .{ .engine = engine };
        defer scope.deinit();
        try install(&scope);
        try publish(&scope, "source58Row", row);
        try publish(&scope, "source58ExpectedProducer", producer_row);
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        const url = try server.url(arena.allocator(), "/v1");
        try scope.put(global, "source58BaseUrl", try scope.text(url));
        const name = row.object.get("name").?.string;
        const result = engine.evalModule(@embedFile("extensions/fixtures/ai-openai-full58-native.input.txt"), "native-original-source58-caller.mjs") catch |err| {
            std.debug.print("Source58 caller failure {s}: {s}\n", .{ name, engine.last_error orelse @errorName(err) });
            return err;
        };
        try scope.put(global, "source58Actual", try scope.get(result, "default"));
        engine.freeValue(result);
        const checked = try engine.evalModule(
            \\function canonical(value){if(Array.isArray(value))return value.map(canonical);if(value&&typeof value==='object'){const out={};for(const key of Object.keys(value).sort())if(value[key]!==undefined)out[key]=canonical(value[key]);return out}return value}const actual=source58Actual;const expected={...source58Row};delete expected.requests;globalThis.source58FullSnapshotMatches=JSON.stringify(canonical(actual))===JSON.stringify(canonical(expected));globalThis.source58FullSnapshotDiagnostic=JSON.stringify({actual,expected});export const done=true;
        , "native-original-source58-compare.mjs");
        engine.freeValue(checked);
        if (!scope.truthy(try scope.get(global, "source58FullSnapshotMatches"))) {
            all_match = false;
            const diagnostic = try engine.toString(try scope.get(global, "source58FullSnapshotDiagnostic"));
            defer engine.gpa.free(diagnostic);
            std.debug.print("Source58 complete intermediate snapshots {s}: {s}\n", .{ name, diagnostic });
        }
        const producer_checked = try engine.evalModule(
            \\function canonical(value){if(Array.isArray(value))return value.map(canonical);if(value&&typeof value==='object'){const out={};for(const key of Object.keys(value).sort())if(value[key]!==undefined)out[key]=canonical(value[key]);return out}return value}globalThis.source58ProducerMatches=JSON.stringify(canonical(source58NativeProducer))===JSON.stringify(canonical(source58ExpectedProducer));globalThis.source58ProducerDiagnostic=JSON.stringify({actual:source58NativeProducer,expected:source58ExpectedProducer});export const done=true;
        , "native-original-source58-producer-compare.mjs");
        engine.freeValue(producer_checked);
        if (!scope.truthy(try scope.get(global, "source58ProducerMatches"))) {
            all_match = false;
            const diagnostic = try engine.toString(try scope.get(global, "source58ProducerDiagnostic"));
            defer engine.gpa.free(diagnostic);
            std.debug.print("Source58 complete producer boundaries and identities {s}: {s}\n", .{ name, diagnostic });
        }
        try server.finish();
        if (!compareWire(name, server.captured.items, requests)) all_match = false;
        const owned_host = try std.fmt.allocPrint(arena.allocator(), "127.0.0.1:{d}", .{server.listener.socket.address.getPort()});
        if (!try compareNativeDefaults(name, server.captured.items, owned_host, native_identity)) all_match = false;
        c.JS_RunGC(engine.runtime);
        try std.testing.expect(!@import("extensions/native_ai_http.zig").pending(engine));
    }
    try std.testing.expect(all_match);
}

test "native OpenAI original Source58 shared deep JSON and error image split remain complete" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const source = try std.json.parseFromSlice(std.json.Value, engine.gpa, golden, .{});
    defer source.deinit();
    try publish(&scope, "source58Original", source.value);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "source58Json", try scope.own(try @import("extensions/native_ai_json_parse.zig").create(engine)));
    const Split = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return @import("extensions/native_ai_transform_messages.zig").splitErrorImages(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    try scope.put(global, "source58Split", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "splitErrorToolResultImages", 1, Split.call, &.{})));
    const result = try engine.evalModule(
        \\const deep=[];for(const expected of source58Original.deep){const parsed=source58Json.parseStreamingJson(expected.input);let current=parsed,actualDepth=0;while(Array.isArray(current)&&current.length){actualDepth++;current=current[0]}deep.push({name:expected.name,depth:expected.depth,input:expected.input,actualDepth,leaf:Array.isArray(current)?{type:'array',length:current.length}:current})}const split=source58Original.split.map(expected=>({isError:expected.isError,input:expected.input,result:source58Split(expected.input)??null}));if(deep.length!==6||split.length!==2||JSON.stringify(deep)!==JSON.stringify(source58Original.deep)||JSON.stringify(split)!==JSON.stringify(source58Original.split))throw Error(JSON.stringify({deep,split,expectedDeep:source58Original.deep,expectedSplit:source58Original.split}));export const done=true;
    , "native-original-source58-deep-split.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
