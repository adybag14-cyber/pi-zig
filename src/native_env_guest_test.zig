const std = @import("std");
const em = @import("extensions/engine.zig");
const values = @import("extensions/native_env_values.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
test "native Env guest actual compiled inventory" {
    const builtin = @import("builtin");
    const names = try std.testing.allocator.alloc([]const u8, builtin.test_functions.len);
    defer std.testing.allocator.free(names);
    for (builtin.test_functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("\nENV_GUEST_TEST_INVENTORY={s}\n", .{encoded});
}
fn fixtureValue(engine: *em.Engine, comptime source: []const u8) !c.JSValue {
    return engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "native-env-source.json"));
}
fn nodeReaderModule(engine: *em.Engine) !c.JSValue {
    try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    const shared = try values.exports(engine);
    defer engine.freeValue(shared);
    var scope: @import("extensions/native_sdk_prompt_scope.zig").Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.object();
    inline for (.{ "FileError", "toError" }) |name| try scope.put(bindings, name, try scope.get(shared, name));
    var promises = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer promises.deinit(engine);
    try scope.put(bindings, "promise_constructor", promises.constructor);
    try scope.put(bindings, "promise_resolve", promises.resolve);
    try scope.put(bindings, "promise_then", promises.then_function);
    try scope.put(bindings, "paths", engine.native_module_values.get("node:path").?);
    try scope.put(bindings, "StreamDecoder", try scope.own(try @import("extensions/native_env_decode.zig").create(engine)));
    const scanner = try scope.own(try @import("extensions/native_env_line_scan.zig").create(engine));
    try scope.put(bindings, "LineScanner", scanner);
    const internal = try scope.object();
    try scope.put(internal, "LineScanner", scanner);
    try scope.put(internal, "NodeBinaryReader", try scope.own(try @import("extensions/native_env_node_readers.zig").create(&scope, bindings, .binary)));
    try scope.put(internal, "NodeTextLineReader", try scope.own(try @import("extensions/native_env_node_readers.zig").create(&scope, bindings, .text)));
    return c.JS_DupValue(engine.context, internal);
}
test "native Env guest Node public reader values and LineScanner match original Source virtual files" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const internal = try nodeReaderModule(engine);
    defer engine.freeValue(internal);
    try engine.registerValueModule("native-env-node-readers-test", internal);
    var scope: @import("extensions/native_sdk_prompt_scope.zig").Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "nodeReaderSource", try scope.own(try fixtureValue(engine, @embedFile("extensions/fixtures/env-node-reader-values-source-e6220e1.json"))));
    const result = engine.evalModule("import{NodeBinaryReader,NodeTextLineReader,LineScanner}from'native-env-node-readers-test';\n" ++
        @embedFile("extensions/fixtures/env-node-reader-values-source-e6220e1.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(nodeReaderSource))throw Error(JSON.stringify({actual:packet,expected:nodeReaderSource}));export const proof=true;", "native-env-node-reader-source.mjs") catch |err| {
        std.debug.print("Native Env Node reader Source failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    try scope.put(global, "nodeReaderGettersSource", try scope.own(try fixtureValue(engine, @embedFile("extensions/fixtures/env-node-reader-getters-source-e6220e1.json"))));
    const getter_result = engine.evalModule("import{NodeBinaryReader,NodeTextLineReader}from'native-env-node-readers-test';\n" ++
        @embedFile("extensions/fixtures/env-node-reader-getters-source-e6220e1.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(nodeReaderGettersSource))throw Error(JSON.stringify({actual:packet,expected:nodeReaderGettersSource}));export const proof=true;", "native-env-node-reader-getters-source.mjs") catch |err| {
        std.debug.print("Native Env Node reader getter Source failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(getter_result);
    c.JS_RunGC(engine.runtime);
}
fn allocationNodeReaders(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const internal = try nodeReaderModule(engine);
    defer engine.freeValue(internal);
    try engine.registerValueModule("native-env-node-readers-test", internal);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "nodeReaderGpaSource", try fixtureValue(engine, @embedFile("extensions/fixtures/env-node-reader-gpa-source-e6220e1.json")));
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule("import{NodeBinaryReader,NodeTextLineReader}from'native-env-node-readers-test';\n" ++
        @embedFile("extensions/fixtures/env-node-reader-gpa-source-e6220e1.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(nodeReaderGpaSource))throw Error(JSON.stringify({actual:packet,expected:nodeReaderGpaSource}));export const proof=true;", "native-env-node-reader-gpa-source.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native Env guest Node reader scan and text continuations release every host allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationNodeReaders, .{});
}
test "native Env guest public decoder exports preserve Source BOM globals and function values" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/text_encoding.zig").install(engine);
    const exports = try js.object(engine);
    defer engine.freeValue(exports);
    try @import("extensions/native_env_decode_exports.zig").install(engine, exports);
    try js.define(engine, exports, "StreamDecoder", try @import("extensions/native_env_decode.zig").create(engine));
    try engine.registerValueModule("native-env-decode-test", exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "decodeSource", try fixtureValue(engine, @embedFile("extensions/fixtures/env-decode-exports-source-e6220e1.json")));
    const result = engine.evalModule("import{rangeDecoder,startsWithBom,StreamDecoder}from'native-env-decode-test';\n" ++
        @embedFile("extensions/fixtures/env-decode-exports-source-e6220e1.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(decodeSource))throw Error(JSON.stringify({actual:packet,expected:decodeSource}));export const proof=true;", "native-env-decode-source.mjs") catch |err| {
        std.debug.print("Native Env public decoder Source failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native Env guest shared Error Result and platform values match original e6220e1 descriptors and live getters" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const exports = try values.exports(engine);
    defer engine.freeValue(exports);
    try engine.registerValueModule("@earendil-works/pi-durable/env", exports);
    const env = try js.object(engine);
    defer engine.freeValue(env);
    try js.define(engine, env, "nodePlatform", try js.get(engine, exports, "nodePlatform"));
    try engine.registerValueModule("@earendil-works/pi-env", env);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "envSource", try fixtureValue(engine, @embedFile("extensions/fixtures/env-values-source-e6220e1.json")));
    const result = engine.evalModule("import{FileError,ExecutionError,ok,err,getOrThrow,getOrUndefined,toError}from'@earendil-works/pi-durable/env';import{nodePlatform}from'@earendil-works/pi-env';\n" ++
        @embedFile("extensions/fixtures/env-values-source-e6220e1.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(envSource))throw Error(JSON.stringify({actual:packet,expected:envSource}));export const proof=true;", "native-env-values-source.mjs") catch |err| {
        std.debug.print("Native Env source value failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Env guest listing continuations preserve Source virtual calls validation cancellation and error identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/node_buffer.zig").install(engine);
    try @import("extensions/abort_signal.zig").install(engine);
    const exports = try values.exports(engine);
    defer engine.freeValue(exports);
    try engine.registerValueModule("@earendil-works/pi-durable/env", exports);
    const env = try js.object(engine);
    defer engine.freeValue(env);
    inline for (.{ "RemoteError", "isConnectionLost", "nodePlatform" }) |name| try js.define(engine, env, name, try js.get(engine, exports, name));
    try engine.registerValueModule("@earendil-works/pi-env", env);
    const internal = try js.object(engine);
    defer engine.freeValue(internal);
    try js.define(engine, internal, "listFilesOver", try @import("extensions/native_env_list_files.zig").create(engine, exports));
    try engine.registerValueModule("native/env/list-files-internal", internal);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "listingSource", try fixtureValue(engine, @embedFile("extensions/fixtures/env-list-over-source-e6220e1.json")));
    const result = engine.evalModule("import{FileError}from'@earendil-works/pi-durable/env';import{RemoteError,isConnectionLost}from'@earendil-works/pi-env';import{listFilesOver}from'native/env/list-files-internal';\n" ++
        @embedFile("extensions/fixtures/env-list-over-source-e6220e1.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(listingSource))throw Error(JSON.stringify({actual:packet,expected:listingSource}));export const proof=true;", "native-env-listing-source.mjs") catch |err| {
        std.debug.print("Native Env Source listing continuation failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Env guest error constructors and closures survive collection with original live causes" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const exports = try values.exports(engine);
    defer engine.freeValue(exports);
    try engine.registerValueModule("@earendil-works/pi-durable/env", exports);
    const prepared = try engine.evalModule(
        \\import{FileError,toError,nodePlatform}from'@earendil-works/pi-durable/env';
        \\class Child extends FileError{};const cause={alive:71};globalThis.envRetained={Child,cause,error:new Child('invalid','same','path',cause),convert:toError,platform:nodePlatform};
    , "native-env-collection-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const checked = try engine.eval(
        \\const saved=envRetained;if(saved.error.cause!==saved.cause||saved.cause.alive!==71||!(saved.error instanceof saved.Child)||saved.convert(saved.error)!==saved.error||saved.platform({os:'windows',arch:'aarch64'}).platform!=='win32')throw Error('Env private class roots lost');delete globalThis.envRetained;
    , "native-env-collection-check.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}
fn allocationValues(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const exports = try values.exports(engine);
    defer engine.freeValue(exports);
    try engine.registerValueModule("@earendil-works/pi-durable/env", exports);
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule(
        \\import{FileError,ExecutionError,ok,getOrThrow,toError,nodePlatform}from'@earendil-works/pi-durable/env';
        \\const cause={owned:true},f=new FileError('invalid','reason','path',cause),e=new ExecutionError('timeout','reason',cause);if(f.cause!==cause||e.cause!==cause||toError(f)!==f||getOrThrow(ok(f))!==f||nodePlatform({os:'macos',arch:'x86_64'}).arch!=='x64')throw Error('Env allocation result changed');export const proof=true;
    , "native-env-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
}
test "native Env guest shared constructors results and platform helpers release every host allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationValues, .{});
}
test "native Env guest Connection class matches original lazy starts failure sharing retries and close ordering" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const exports = try values.exports(engine);
    defer engine.freeValue(exports);
    try js.define(engine, exports, "Connection", try @import("extensions/native_env_connection.zig").create(engine, exports));
    try engine.registerValueModule("@earendil-works/pi-env", exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "connectionSource", try fixtureValue(engine, @embedFile("extensions/fixtures/env-connection-values-source-e6220e1.json")));
    const result = engine.evalModule("import{Connection,isConnectionLost}from'@earendil-works/pi-env';\n" ++
        @embedFile("extensions/fixtures/env-connection-values-source-e6220e1.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(connectionSource))throw Error(JSON.stringify({actual:packet,expected:connectionSource}));export const proof=true;", "native-env-connection-source.mjs") catch |err| {
        std.debug.print("Native Env Source Connection class failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native Env guest real Connection transport matches Source daemon writes events signal getters and close from callback" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const daemon = environ.get("PI_TEST_ENV_DAEMON") orelse return error.MissingRequiredNativeEnvDaemon;
    const command = environ.get("ComSpec") orelse return error.MissingRequiredWindowsCommand;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = io;
    try @import("extensions/node_buffer.zig").install(engine);
    const exports = try values.exports(engine);
    defer engine.freeValue(exports);
    try js.define(engine, exports, "Connection", try @import("extensions/native_env_connection.zig").create(engine, exports));
    try engine.registerValueModule("@earendil-works/pi-env", exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    inline for (.{ .{ "daemonPath", daemon }, .{ "treePath", root }, .{ "commandPath", command } }) |entry| try js.define(engine, global, entry[0], try engine.checked(c.JS_NewStringLen(engine.context, entry[1].ptr, entry[1].len)));
    try js.define(engine, global, "transportSource", try fixtureValue(engine, @embedFile("extensions/fixtures/env-connection-transport-source-e6220e1.json")));
    const result = engine.evalModule("import{Connection,isConnectionLost}from'@earendil-works/pi-env';\n" ++
        @embedFile("extensions/fixtures/env-connection-transport-source-e6220e1.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(transportSource))throw Error(JSON.stringify({actual:packet,expected:transportSource}));export const proof=true;", "native-env-connection-transport-source.mjs") catch |err| {
        std.debug.print("Native Env Source real Connection transport failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native Env guest RemoteExecutionEnv complete class shape and virtual path filesystem calls match Source" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/node_buffer.zig").install(engine);
    const exports = try values.exports(engine);
    defer engine.freeValue(exports);
    try js.define(engine, exports, "RemoteExecutionEnv", try @import("extensions/native_env_remote.zig").create(engine, exports));
    try engine.registerValueModule("@earendil-works/pi-env", exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "remoteSource", try fixtureValue(engine, @embedFile("extensions/fixtures/env-remote-basic-source-e6220e1.json")));
    const result = engine.evalModule("import{RemoteExecutionEnv,RemoteError}from'@earendil-works/pi-env';\n" ++
        @embedFile("extensions/fixtures/env-remote-basic-source-e6220e1.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(remoteSource))throw Error(JSON.stringify({actual:packet,expected:remoteSource}));export const proof=true;", "native-env-remote-basic-source.mjs") catch |err| {
        std.debug.print("Native Env Source RemoteExecutionEnv class failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native Env guest RemoteExecutionEnv retained readers chunk pipelines and exec match original real Source daemon" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const daemon = environ.get("PI_TEST_ENV_DAEMON") orelse return error.MissingRequiredNativeEnvDaemon;
    const command = environ.get("ComSpec") orelse return error.MissingRequiredWindowsCommand;
    // The admitted worker schedules exposed an actual writeChunk reorder; replay the unchanged Source caller.
    for (0..3) |_| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
        const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10_000 });
        defer engine.deinit();
        engine.native_io = io;
        try @import("extensions/node_buffer.zig").install(engine);
        const exports = try values.exports(engine);
        defer engine.freeValue(exports);
        try js.define(engine, exports, "Connection", try @import("extensions/native_env_connection.zig").create(engine, exports));
        try js.define(engine, exports, "RemoteExecutionEnv", try @import("extensions/native_env_remote.zig").create(engine, exports));
        try engine.registerValueModule("@earendil-works/pi-env", exports);
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        inline for (.{ .{ "daemonPath", daemon }, .{ "treePath", root }, .{ "commandPath", command } }) |entry| try js.define(engine, global, entry[0], try engine.checked(c.JS_NewStringLen(engine.context, entry[1].ptr, entry[1].len)));
        try js.define(engine, global, "functionalSource", try fixtureValue(engine, @embedFile("extensions/fixtures/env-remote-functional-source-e6220e1.json")));
        const result = engine.evalModule("import{Connection,RemoteExecutionEnv}from'@earendil-works/pi-env';\n" ++
            @embedFile("extensions/fixtures/env-remote-functional-source-e6220e1.input.txt") ++
            "\nif(JSON.stringify(packet)!==JSON.stringify(functionalSource))throw Error(JSON.stringify({actual:packet,expected:functionalSource}));export const proof=true;", "native-env-remote-functional-source.mjs") catch |err| {
            std.debug.print("Native Env Source RemoteExecutionEnv real reader failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
            return err;
        };
        engine.freeValue(result);
        c.JS_RunGC(engine.runtime);
    }
}
test "native Env guest closing queued frames shares Source rejection detaches listeners and preserves retained callbacks" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const daemon = environ.get("PI_TEST_ENV_DAEMON") orelse return error.MissingRequiredNativeEnvDaemon;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = io;
    const exports = try values.exports(engine);
    defer engine.freeValue(exports);
    try js.define(engine, exports, "Connection", try @import("extensions/native_env_connection.zig").create(engine, exports));
    try engine.registerValueModule("@earendil-works/pi-env", exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    inline for (.{ .{ "daemonPath", daemon }, .{ "treePath", root } }) |entry| try js.define(engine, global, entry[0], try engine.checked(c.JS_NewStringLen(engine.context, entry[1].ptr, entry[1].len)));
    try js.define(engine, global, "closeSource", try fixtureValue(engine, @embedFile("extensions/fixtures/env-connection-close-source-e6220e1.json")));
    const result = engine.evalModule("import{Connection,isConnectionLost}from'@earendil-works/pi-env';\n" ++
        @embedFile("extensions/fixtures/env-connection-close-source-e6220e1.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(closeSource))throw Error(JSON.stringify({actual:packet,expected:closeSource}));export const proof=true;", "native-env-connection-close-source.mjs") catch |err| {
        std.debug.print("Native Env Source queued-close failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
